#!/usr/bin/env bash
# Request a GitHub Actions OIDC token, verify it with
# policies/workload_identity, and write the verified identity as JSON.
#
# Usage: verify_identity.sh <audience> <output file>
# Needs the job permission `id-token: write`.
set -euo pipefail

AUDIENCE="$1"
OUT="$2"
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
ISSUER="https://token.actions.githubusercontent.com"

: "${ACTIONS_ID_TOKEN_REQUEST_URL:?no OIDC endpoint; the job needs permissions: id-token: write}"
: "${ACTIONS_ID_TOKEN_REQUEST_TOKEN:?no OIDC request token; the job needs permissions: id-token: write}"
: "${GITHUB_REPOSITORY:?}"

TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT

token="$(curl -sSf -H "Authorization: bearer $ACTIONS_ID_TOKEN_REQUEST_TOKEN" \
  "$ACTIONS_ID_TOKEN_REQUEST_URL&audience=$AUDIENCE" | jq -r '.value')"
echo "::add-mask::$token"
jwks="$(curl -sSf "$ISSUER/.well-known/jwks")"

jq -n --arg token "$token" --arg jwks "$jwks" '{token: $token, jwks: $jwks}' > "$TMP/input.json"
# Only this repository may run its own pipeline. A shared pipeline would
# list its allowed repositories in reviewed policy data instead.
jq -n --arg issuer "$ISSUER" --arg audience "$AUDIENCE" --arg repo "$GITHUB_REPOSITORY" \
  '{identity_policy: {issuer: $issuer, audience: $audience, repositories: [$repo]}}' > "$TMP/data.json"

opa eval -f raw \
  -d "$ROOT/policies/workload_identity/github_oidc.rego" -d "$TMP/data.json" -i "$TMP/input.json" \
  "data.agentaccess.workload_identity.identity" > "$OUT"

if [ "$(jq -r '.verified' "$OUT")" != "true" ]; then
  echo "workload identity could not be verified:" >&2
  jq -r '.reasons[] | "  - " + .' "$OUT" >&2
  exit 1
fi
echo "verified identity: agent=$(jq -r '.agent' "$OUT") requested_by=$(jq -r '.requested_by' "$OUT")"
