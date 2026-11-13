#!/usr/bin/env bash
# Stage 1 of the image path: decide whether an approval covers an image.
#
# Runs seven scenarios against policies/image_admission with OPA. No cluster
# and no network are needed. For the one allowed scenario it writes the
# ConfigMap that stage 2 (the cluster) reads; see
# scripts/demo_image_admission_cluster.sh.
#
# This is a policy-level demonstration. It shows what the policy decides for
# each input. It does not show that an agent can or cannot obtain such an
# approval in a real pipeline.
#
# Usage: scripts/demo_image_admission.sh [output-dir]
# Exit status 0 means every scenario behaved as expected.
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
# shellcheck source=scripts/lib/portable.sh
. "$ROOT/scripts/lib/portable.sh"
require_tools opa jq

OUT="${1:-$ROOT/results/image-admission}"
mkdir -p "$OUT"

# Fixed example digests. They identify no real image.
DIGEST_APPROVED="sha256:3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855a"
DIGEST_OTHER="sha256:9f86d081884c7d659a2feaa0c55ad015a3bf4f1b2b0b822cd15d6c15b0f00a08"
REPO="registry.example/team/app"

NOW="$(iso_utc_offset 0)"
FUTURE="$(iso_utc_offset 3600)"
PAST="$(iso_utc_offset -60)"

# input <reference> <agent> <approval-json-or-null>
make_input() {
  jq -n --arg ref "$1" --arg agent "$2" --arg now "$NOW" --argjson approval "$3" '
    {image: {reference: $ref},
     execution: {agent: $agent, requested_by: "alice", now: $now}}
    + (if $approval == null then {} else {approval: $approval} end)'
}

approval() { # approval <digest> <agent> <approver> <expires_at>
  jq -n --arg d "$1" --arg a "$2" --arg p "$3" --arg e "$4" \
    '{image_digest: $d, agent: $a, requested_by: "alice", approver: $p, expires_at: $e}'
}

decide() {
  opa eval -f json -d "$ROOT/policies/image_admission/image_admission.rego" \
    -I "data.agentaccess.image_admission.decision" <<<"$1" | jq -c '.result[0].expressions[0].value'
}

printf '%-22s %-9s %-9s %s\n' scenario expected observed reasons
failures=0

# run_case <id> <expected allow|deny> <input-json>
run_case() {
  local id="$1" expected="$2" decision observed reasons
  decision="$(decide "$3")"
  if [ "$(jq -r '.allow' <<<"$decision")" = "true" ]; then observed=allow; else observed=deny; fi
  reasons="$(jq -r '.reasons | join("; ")' <<<"$decision")"
  printf '%-22s %-9s %-9s %s\n' "$id" "$expected" "$observed" "${reasons:--}"
  [ "$observed" = "$expected" ] || { echo "  UNEXPECTED: $id" >&2; failures=$((failures+1)); }
  if [ "$id" = "approved-image" ] && [ "$observed" = allow ]; then
    published="$(jq -r '.approved_digest' <<<"$decision")"
    [ "$published" = "$DIGEST_APPROVED" ] || { echo "  UNEXPECTED: published digest $published" >&2; failures=$((failures+1)); }
    echo "$decision" > "$OUT/decision-approved-image.json"
  fi
  # A denied decision must never publish a digest.
  if [ "$observed" = deny ] && [ "$(jq -r '.approved_digest' <<<"$decision")" != "null" ]; then
    echo "  UNEXPECTED: $id published a digest while denied" >&2; failures=$((failures+1))
  fi
}

A_OK="$(approval "$DIGEST_APPROVED" deploy-agent bob "$FUTURE")"

run_case approved-image    allow "$(make_input "$REPO@$DIGEST_APPROVED" deploy-agent "$A_OK")"
run_case different-digest  deny  "$(make_input "$REPO@$DIGEST_OTHER"    deploy-agent "$A_OK")"
run_case tag-reference     deny  "$(make_input "$REPO:latest"           deploy-agent "$A_OK")"
run_case different-agent   deny  "$(make_input "$REPO@$DIGEST_APPROVED" other-agent  "$A_OK")"
run_case expired-approval  deny  "$(make_input "$REPO@$DIGEST_APPROVED" deploy-agent "$(approval "$DIGEST_APPROVED" deploy-agent bob "$PAST")")"
run_case self-approval     deny  "$(make_input "$REPO@$DIGEST_APPROVED" deploy-agent "$(approval "$DIGEST_APPROVED" deploy-agent alice "$FUTURE")")"
run_case no-approval       deny  "$(make_input "$REPO@$DIGEST_APPROVED" deploy-agent null)"

# Stage 2 input: the digests the policy allowed to be published.
digests="$(jq -r '.approved_digest' "$OUT/decision-approved-image.json")"
cat > "$OUT/approved-images.yaml" <<YAML
apiVersion: v1
kind: ConfigMap
metadata:
  name: approved-images
  namespace: agent-managed
data:
  approvedDigests: "$digests"
YAML

if [ "$failures" -ne 0 ]; then
  echo "$failures scenario(s) did not behave as expected" >&2
  exit 1
fi
echo "All 7 scenarios behaved as expected. Published digest list: $OUT/approved-images.yaml"
