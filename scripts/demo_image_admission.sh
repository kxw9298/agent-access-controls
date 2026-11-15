#!/usr/bin/env bash
# Stage 1 of the image path: decide whether an approval covers an image.
#
# An approval reaches the policy only as a signed record. Each scenario builds
# a record (signed with cosign, as an in-toto Statement), verifies it, and
# gives the policy the approval inside it. A record that is missing, unsigned,
# altered after signing, signed by another key, or inconsistent with itself is
# rejected, and the policy then sees no approval. See scripts/attest_approval.sh.
#
# No cluster and no network are needed. For the one allowed scenario this writes
# the ConfigMap that stage 2 (the cluster) reads; see
# scripts/demo_image_admission_cluster.sh. The ConfigMap names the signed
# record it came from by the record's SHA-256.
#
# This is a demonstration of what the policy and the record check do for given
# inputs. It does not show that an agent cannot obtain a signature in a real
# pipeline: whoever holds the signing key can sign any approval, and key custody
# is not handled here.
#
# Usage: scripts/demo_image_admission.sh [output-dir]
# Exit status 0 means every scenario behaved as expected.
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
# shellcheck source=scripts/lib/portable.sh
. "$ROOT/scripts/lib/portable.sh"
require_tools opa jq cosign

OUT="${1:-$ROOT/results/image-admission}"
mkdir -p "$OUT"
WORK="$(mktemp -d)"
trap 'rm -rf "$WORK"' EXIT

# Throwaway keys for this run only. The password protects nothing; cosign wants one.
export COSIGN_PASSWORD="demo-only"
mkdir -p "$WORK/trusted" "$WORK/other"
(cd "$WORK/trusted" && cosign generate-key-pair >/dev/null 2>&1)
(cd "$WORK/other" && cosign generate-key-pair >/dev/null 2>&1)
TRUSTED_KEY="$WORK/trusted/cosign.key"; TRUSTED_PUB="$WORK/trusted/cosign.pub"
OTHER_KEY="$WORK/other/cosign.key"

# Fixed example digests. They identify no real image.
DIGEST_APPROVED="sha256:3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855a"
DIGEST_OTHER="sha256:9f86d081884c7d659a2feaa0c55ad015a3bf4f1b2b0b822cd15d6c15b0f00a08"
REPO="registry.example/team/app"

NOW="$(iso_utc_offset 0)"
FUTURE="$(iso_utc_offset 3600)"
PAST="$(iso_utc_offset -60)"

approval() { # approval <digest> <agent> <approver> <expires_at>
  jq -n --arg d "$1" --arg a "$2" --arg p "$3" --arg e "$4" \
    '{image_digest: $d, agent: $a, requested_by: "alice", approver: $p, expires_at: $e}'
}

# record_for <scenario> <approval-json> <approved-reference> [signing-key]
# Writes $WORK/<scenario>/statement.json and statement.sig.
record_for() {
  local dir="$WORK/$1"; mkdir -p "$dir"
  echo "$2" > "$dir/approval.json"
  COSIGN_PASSWORD="$COSIGN_PASSWORD" "$ROOT/scripts/attest_approval.sh" sign \
    "$dir/approval.json" "$3" "${4:-$TRUSTED_KEY}" "$dir"
}

printf '%-22s %-8s %-8s %-46s %s\n' scenario expected observed record reasons
failures=0

# run_case <id> <expected allow|deny> <deployed-reference> <agent>
# Uses $WORK/<id>/ as the record, if there is one.
run_case() {
  local id="$1" expected="$2" ref="$3" agent="$4" dir="$WORK/$1"
  local approval_json="null" record_note="no record" verdict input decision observed reasons
  if [ -f "$dir/statement.json" ]; then
    if verdict="$("$ROOT/scripts/attest_approval.sh" verify "$dir/statement.json" "$dir/statement.sig" "$TRUSTED_PUB" 2>&1)"; then
      approval_json="$verdict"; record_note="verified"
    else
      record_note="rejected: $verdict"
    fi
  fi
  input="$(jq -n --arg ref "$ref" --arg agent "$agent" --arg now "$NOW" --argjson approval "$approval_json" '
    {image: {reference: $ref}, execution: {agent: $agent, requested_by: "alice", now: $now}}
    + (if $approval == null then {} else {approval: $approval} end)')"
  decision="$(opa eval -f json -d "$ROOT/policies/image_admission/image_admission.rego" \
    -I "data.agentaccess.image_admission.decision" <<<"$input" | jq -c '.result[0].expressions[0].value')"
  if [ "$(jq -r '.allow' <<<"$decision")" = "true" ]; then observed=allow; else observed=deny; fi
  reasons="$(jq -r '.reasons | join("; ")' <<<"$decision")"
  printf '%-22s %-8s %-8s %-46s %s\n' "$id" "$expected" "$observed" "${record_note:0:46}" "${reasons:--}"
  [ "$observed" = "$expected" ] || { echo "  UNEXPECTED: $id" >&2; failures=$((failures+1)); }
  if [ "$observed" = deny ] && [ "$(jq -r '.approved_digest' <<<"$decision")" != "null" ]; then
    echo "  UNEXPECTED: $id published a digest while denied" >&2; failures=$((failures+1))
  fi
  if [ "$id" = "approved-image" ] && [ "$observed" = allow ]; then
    [ "$(jq -r '.approved_digest' <<<"$decision")" = "$DIGEST_APPROVED" ] \
      || { echo "  UNEXPECTED: wrong published digest" >&2; failures=$((failures+1)); }
    echo "$decision" > "$OUT/decision-approved-image.json"
    cp "$dir/statement.json" "$OUT/approval-statement.json"
    cp "$dir/statement.sig" "$OUT/approval-statement.sig"
  fi
}

A_OK="$(approval "$DIGEST_APPROVED" deploy-agent bob "$FUTURE")"
REF_OK="$REPO@$DIGEST_APPROVED"

# Scenarios the policy decides: the record is valid, the request is not.
record_for approved-image   "$A_OK" "$REF_OK"
record_for different-digest "$A_OK" "$REF_OK"
record_for tag-reference    "$A_OK" "$REF_OK"
record_for different-agent  "$A_OK" "$REF_OK"
record_for expired-approval "$(approval "$DIGEST_APPROVED" deploy-agent bob "$PAST")" "$REF_OK"
record_for self-approval    "$(approval "$DIGEST_APPROVED" deploy-agent alice "$FUTURE")" "$REF_OK"
# Scenarios the record check decides: the record itself is bad.
record_for tampered-record  "$A_OK" "$REF_OK"
jq '.predicate.approver = "mallory"' "$WORK/tampered-record/statement.json" > "$WORK/t.json" \
  && mv "$WORK/t.json" "$WORK/tampered-record/statement.json"
record_for unsigned-record  "$A_OK" "$REF_OK"; rm -f "$WORK/unsigned-record/statement.sig"
record_for wrong-signer     "$A_OK" "$REF_OK" "$OTHER_KEY"
# A validly signed record whose subject is a different image than the digest it approves.
record_for inconsistent-record "$A_OK" "$REPO@$DIGEST_OTHER"

run_case approved-image      allow "$REF_OK"                  deploy-agent
run_case different-digest    deny  "$REPO@$DIGEST_OTHER"      deploy-agent
run_case tag-reference       deny  "$REPO:latest"             deploy-agent
run_case different-agent     deny  "$REF_OK"                  other-agent
run_case expired-approval    deny  "$REF_OK"                  deploy-agent
run_case self-approval       deny  "$REF_OK"                  deploy-agent
run_case no-approval         deny  "$REF_OK"                  deploy-agent
run_case tampered-record     deny  "$REF_OK"                  deploy-agent
run_case unsigned-record     deny  "$REF_OK"                  deploy-agent
run_case wrong-signer        deny  "$REF_OK"                  deploy-agent
run_case inconsistent-record deny  "$REF_OK"                  deploy-agent

# Stage 2 input: the digests the policy allowed to be published, tied to the
# signed record they came from.
digests="$(jq -r '.approved_digest' "$OUT/decision-approved-image.json")"
record_sha="$(sha256_file "$OUT/approval-statement.json")"
cat > "$OUT/approved-images.yaml" <<YAML
apiVersion: v1
kind: ConfigMap
metadata:
  name: approved-images
  namespace: agent-managed
  annotations:
    approval-statement-sha256: "$record_sha"
data:
  approvedDigests: "$digests"
YAML

if [ "$failures" -ne 0 ]; then
  echo "$failures scenario(s) did not behave as expected" >&2
  exit 1
fi
echo "All 11 scenarios behaved as expected. Published digest list: $OUT/approved-images.yaml"
