#!/usr/bin/env bash
# Sign and verify an approval record as an in-toto Statement.
#
# The record is the approval object that policies/image_admission reads (image
# digest, agent, requester, approver, expiry). It is wrapped in an in-toto
# Statement whose subject is the approved image, and signed with cosign.
#
# Limits, stated plainly:
# - The signature is a detached signature over the Statement file made with
#   `cosign sign-blob`. It is not a DSSE envelope, and nothing is written to a
#   transparency log.
# - The signature shows the record was made by the holder of the private key and
#   not changed afterwards. It does not show that a person approved. Whoever
#   holds the key can sign any approval. Key custody is not handled here.
# - The predicate type below is an identifier chosen for this project. It is not
#   registered anywhere.
#
# Usage:
#   scripts/attest_approval.sh sign   <approval.json> <image-reference> <private-key> <out-dir>
#   scripts/attest_approval.sh verify <statement.json> <signature> <public-key> [image-reference]
#
# sign reads the key password from COSIGN_PASSWORD. verify prints the approval
# (the Statement's predicate) on success and exits 1 with a reason on failure.
# It checks the signature and that the record is consistent with itself (its
# subject is the digest it approves). With an image reference it also checks
# that the record is for that image. Without one, whether the record covers the
# image about to be deployed is left to the approval policy.
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
# shellcheck source=scripts/lib/portable.sh
. "$ROOT/scripts/lib/portable.sh"
require_tools cosign jq

PREDICATE_TYPE="https://github.com/kxw9298/agent-access-controls/approval/v1"
STATEMENT_TYPE="https://in-toto.io/Statement/v1"

fail() { echo "$*" >&2; exit 1; }

# split_reference <repo@sha256:hex>: sets NAME and HEX, or fails.
split_reference() {
  [[ "$1" =~ ^([^@[:space:]]+)@sha256:([0-9a-f]{64})$ ]] \
    || fail "image reference is not pinned to a sha256 digest"
  NAME="${BASH_REMATCH[1]}"
  HEX="${BASH_REMATCH[2]}"
}

sign() {
  local approval="$1" ref="$2" key="$3" out="$4"
  split_reference "$ref"
  mkdir -p "$out"
  jq -n --arg name "$NAME" --arg hex "$HEX" --arg st "$STATEMENT_TYPE" --arg pt "$PREDICATE_TYPE" \
    --slurpfile predicate "$approval" \
    '{_type: $st, subject: [{name: $name, digest: {sha256: $hex}}], predicateType: $pt, predicate: $predicate[0]}' \
    > "$out/statement.json"
  cosign sign-blob --key "$key" --tlog-upload=false --yes \
    --output-signature "$out/statement.sig" "$out/statement.json" >/dev/null 2>&1 \
    || fail "signing failed"
}

verify() {
  local statement="$1" sig="$2" pub="$3" ref="${4:-}" err hex
  [ -f "$statement" ] || fail "no approval record"
  [ -f "$sig" ] || fail "approval record is not signed"
  if ! err="$(cosign verify-blob --key "$pub" --signature "$sig" --insecure-ignore-tlog=true \
        "$statement" 2>&1)"; then
    fail "signature does not verify: $(tail -1 <<<"$err")"
  fi
  hex="$(jq -r '.subject[0].digest.sha256 // ""' "$statement" 2>/dev/null)" || fail "approval record is not valid JSON"
  jq -e --arg st "$STATEMENT_TYPE" --arg pt "$PREDICATE_TYPE" --arg hex "$hex" '
      ._type == $st and .predicateType == $pt
      and (.subject | length == 1) and ($hex | test("^[0-9a-f]{64}$"))
      and .predicate.image_digest == ("sha256:" + $hex)' "$statement" >/dev/null \
    || fail "record is inconsistent: wrong type, or its subject differs from the digest it approves"
  if [ -n "$ref" ]; then
    split_reference "$ref"
    [ "$HEX" = "$hex" ] || fail "record is for a different image than the one given"
  fi
  jq -c '.predicate' "$statement"
}

case "${1:-}" in
  sign)   [ $# -eq 5 ] || fail "usage: sign <approval.json> <image-reference> <private-key> <out-dir>"; sign "$2" "$3" "$4" "$5" ;;
  verify) { [ $# -eq 4 ] || [ $# -eq 5 ]; } || fail "usage: verify <statement.json> <signature> <public-key> [image-reference]"; verify "$2" "$3" "$4" "${5:-}" ;;
  *) fail "usage: $0 sign|verify ..." ;;
esac
