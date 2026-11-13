#!/usr/bin/env bash
# Demonstrates approval binding for a Terraform saved plan.
# See examples/terraform_pipeline/README.md.
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
PLAN_POLICY="$ROOT/policies/terraform_plan/terraform_plan.rego"
APPROVAL_POLICY="$ROOT/policies/change_approval/change_approval.rego"
POLICY_DATA="$ROOT/examples/terraform_pipeline/policy-data.json"

for tool in terraform opa jq sha256sum; do
  command -v "$tool" >/dev/null || { echo "missing required tool: $tool" >&2; exit 2; }
done

WORK="$(mktemp -d)"
trap 'rm -rf "$WORK"' EXIT
cp "$ROOT/examples/terraform_pipeline/main.tf" "$WORK/"
cd "$WORK"

AGENT="deploy-agent"
REQUESTER="alice"
APPROVER="bob"
failures=0

digest() { sha256sum "$1" | cut -d' ' -f1; }

timestamp() { date -u -d "$1" +%Y-%m-%dT%H:%M:%SZ; }

# plan_decision <plan file>: evaluate the plan policy on a saved plan.
plan_decision() {
  terraform show -json "$1" > "$1.json"
  opa eval -f raw -d "$PLAN_POLICY" -d "$POLICY_DATA" -i "$1.json" \
    "data.agentaccess.terraform_plan.decision"
}

# check <case name> <allow|refuse> <plan file> <approval file or "none"> <agent> <now>
# The digest is always recomputed from the plan file that would be applied.
check() {
  local name="$1" expected="$2" plan="$3" approval="$4" agent="$5" now="$6"
  local input="$WORK/input.json" decision allowed outcome

  jq -n \
    --arg sha "$(digest "$plan")" \
    --arg agent "$agent" \
    --arg requester "$REQUESTER" \
    --arg now "$now" \
    --argjson plan_decision "$(plan_decision "$plan")" \
    '{artifact: {sha256: $sha},
      execution: {agent: $agent, requested_by: $requester, now: $now},
      plan_decision: $plan_decision}' > "$input"
  if [ "$approval" != "none" ]; then
    jq --slurpfile approval "$approval" '. + {approval: $approval[0]}' "$input" > "$input.tmp"
    mv "$input.tmp" "$input"
  fi

  decision="$(opa eval -f raw -d "$APPROVAL_POLICY" -i "$input" "data.agentaccess.change_approval.decision")"
  allowed="$(jq -r '.allow' <<<"$decision")"
  if [ "$allowed" = "true" ]; then outcome="allow"; else outcome="refuse"; fi

  if [ "$outcome" = "$expected" ]; then
    echo "PASS  $name: $outcome"
  else
    echo "FAIL  $name: expected $expected, got $outcome"
    failures=$((failures + 1))
  fi
  jq -r '.reasons[] | "        - " + .' <<<"$decision"
  [ "$outcome" = "allow" ]
}

echo "== Plan, and record an approval for the plan digest"
terraform init -input=false -no-color >/dev/null
terraform plan -input=false -no-color -var "release=v1" -out=approved.tfplan >/dev/null
echo "plan policy decision: $(plan_decision approved.tfplan)"
approved_digest="$(digest approved.tfplan)"
echo "approved plan digest: $approved_digest"

NOW="$(timestamp now)"
approval_record() { # <approver> <expires_at>
  jq -n --arg sha "$approved_digest" --arg agent "$AGENT" --arg requester "$REQUESTER" \
    --arg approver "$1" --arg expires "$2" \
    '{plan_sha256: $sha, agent: $agent, requested_by: $requester, approver: $approver, expires_at: $expires}'
}
approval_record "$APPROVER" "$(timestamp '+1 hour')" > approval.json
approval_record "$APPROVER" "$(timestamp '-1 hour')" > approval-expired.json
approval_record "$REQUESTER" "$(timestamp '+1 hour')" > approval-self.json

echo
echo "== Case 1: apply the approved plan"
if check "approved plan" allow approved.tfplan approval.json "$AGENT" "$NOW"; then
  terraform apply -input=false -no-color approved.tfplan >/dev/null
  echo "        applied: release=$(terraform output -raw release)"
fi

echo
echo "== Case 2: a different plan is made after approval and reuses the approval"
terraform plan -input=false -no-color -var "release=v2-not-reviewed" -out=substituted.tfplan >/dev/null
echo "substituted plan digest: $(digest substituted.tfplan)"
if check "substituted plan" refuse substituted.tfplan approval.json "$AGENT" "$NOW"; then
  echo "        the executor would have applied a plan nobody approved"
fi

echo
echo "== Case 3: the approved plan is executed by a different agent"
check "different agent" refuse approved.tfplan approval.json "other-agent" "$NOW" || true

echo
echo "== Case 4: the approval has expired"
check "expired approval" refuse approved.tfplan approval-expired.json "$AGENT" "$NOW" || true

echo
echo "== Case 5: the requester approved their own change"
check "self-approval" refuse approved.tfplan approval-self.json "$AGENT" "$NOW" || true

echo
echo "== Case 6: no approval is provided"
check "no approval" refuse approved.tfplan none "$AGENT" "$NOW" || true

echo
echo "applied release is still: $(terraform output -raw release)"
if [ "$(terraform output -raw release)" != "v1" ]; then
  echo "FAIL  an unapproved change was applied"
  failures=$((failures + 1))
fi

if [ "$failures" -gt 0 ]; then
  echo "$failures case(s) did not behave as expected"
  exit 1
fi
echo "all cases behaved as expected"
