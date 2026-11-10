#!/usr/bin/env bash
# The check an executor runs immediately before applying a saved plan.
# Recomputes the plan digest and the plan-policy decision from the plan file
# itself, then evaluates policies/change_approval. Writes the decision as
# JSON and exits 0 whether the decision is allow or refuse; the caller acts
# on the "allow" field.
#
# Usage: execution_check.sh <plan file> <identity file> <approval file> <policy data> <output file>
# Run from the Terraform working directory, after `terraform init`.
# The approval file may not exist, which means no approval.
set -euo pipefail

PLAN="$1"
IDENTITY="$2"
APPROVAL="$3"
POLICY_DATA="$4"
OUT="$5"
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"

TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT

terraform show -json "$PLAN" > "$TMP/plan.json"
opa eval -f raw -d "$ROOT/policies/terraform_plan/terraform_plan.rego" -d "$POLICY_DATA" \
  -i "$TMP/plan.json" "data.agentaccess.terraform_plan.decision" > "$TMP/plan-decision.json"

jq -n \
  --arg sha "$(sha256sum "$PLAN" | cut -d' ' -f1)" \
  --arg now "$(date -u +%Y-%m-%dT%H:%M:%SZ)" \
  --slurpfile identity "$IDENTITY" \
  --slurpfile plan_decision "$TMP/plan-decision.json" \
  '{artifact: {sha256: $sha},
    execution: {agent: $identity[0].agent, requested_by: $identity[0].requested_by, now: $now},
    plan_decision: $plan_decision[0]}' > "$TMP/input.json"
if [ -f "$APPROVAL" ]; then
  jq --slurpfile approval "$APPROVAL" '. + {approval: $approval[0]}' "$TMP/input.json" > "$TMP/input-with-approval.json"
  mv "$TMP/input-with-approval.json" "$TMP/input.json"
fi

opa eval -f raw -d "$ROOT/policies/change_approval/change_approval.rego" -i "$TMP/input.json" \
  "data.agentaccess.change_approval.decision" > "$OUT"
