#!/usr/bin/env bash
# Demonstrates approval binding for a Terraform saved plan.
# See examples/terraform_pipeline/README.md.
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
PLAN_POLICY="$ROOT/policies/terraform_plan/terraform_plan.rego"
APPROVAL_POLICY="$ROOT/policies/change_approval/change_approval.rego"
POLICY_DATA="$ROOT/examples/terraform_pipeline/policy-data.json"

# shellcheck source=scripts/lib/portable.sh
. "$ROOT/scripts/lib/portable.sh"
# shellcheck source=scripts/lib/results.sh
. "$ROOT/scripts/lib/results.sh"
require_tools terraform opa jq

WORK="$(mktemp -d)"
results_begin approval-binding implementation approved-plan substituted-plan \
  replan-after-approval different-agent expired-approval self-approval no-approval
results_assume "The approval record, including the plan digest it names, is written by a trusted step and cannot be altered by the attacker."
results_assume "The executor that runs this check is the only path to apply a plan."
results_assume "The agent and requester identities given to the check come from a trusted source. The demonstration script supplies them itself; the reference pipeline takes them from verified GitHub Actions tokens."
results_assume "Local demonstration: it is not the hosted GitHub environment approval path, which has not been exercised end to end."
trap 'results_end; rm -rf "$WORK"' EXIT
cp "$ROOT/examples/terraform_pipeline/main.tf" "$WORK/"
cd "$WORK"

AGENT="deploy-agent"
REQUESTER="alice"
APPROVER="bob"
failures=0

digest() { sha256_file "$1"; }

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
  allowed="$(jq -r '.allow' <<<"$decision" 2>/dev/null || true)"
  # An error here must stop the run: inside an if-condition, set -e is off,
  # and an empty or malformed decision would otherwise read as a refusal.
  if [ "$allowed" != "true" ] && [ "$allowed" != "false" ]; then
    echo "runner error: no usable decision for case '$name'" >&2
    exit 3
  fi
  if [ "$allowed" = "true" ]; then outcome="allow"; else outcome="refuse"; fi

  if [ "$outcome" = "$expected" ]; then
    echo "PASS  $name: $outcome"
  else
    echo "FAIL  $name: expected $expected, got $outcome"
    failures=$((failures + 1))
  fi
  jq -r '.reasons[] | "        - " + .' <<<"$decision"
  LAST_REASONS="$(jq -c '.reasons' <<<"$decision")"
  [ "$outcome" = "allow" ]
}

release_state() {
  local out
  out="$(terraform output -no-color -json)" || return 1
  jq -r '.release.value // "none"' <<<"$out"
}

# execute <id> <name> <expected: applied|blocked> <authorized: true|false> \
#         <plan file> <approval file or "none"> <agent> <now> [attacker release]
# Acts as the executor: applies the plan only if the check allows it, then
# records what actually happened to the Terraform state.
execute() {
  local id="$1" name="$2" expected="$3" authorized="$4" plan="$5" approval="$6" agent="$7" now="$8" attacker="${9:-}"
  local policy_expectation="refuse" before after observed
  [ "$expected" = "applied" ] && policy_expectation="allow"
  before="$(release_state)"
  if check "$name" "$policy_expectation" "$plan" "$approval" "$agent" "$now"; then
    terraform apply -input=false -no-color "$plan" >/dev/null
    observed="applied"
  else
    observed="blocked"
  fi
  after="$(release_state)"
  results_case "$id" "$name" "$expected" "$authorized" "$observed" "$before" "$after" "$LAST_REASONS" "$attacker"
  echo "        terraform state: release $before -> $after"
  if [ "$authorized" = "false" ] && [ "$observed" = "applied" ]; then
    echo "        the executor applied a plan nobody approved"
  fi
}

echo "== Plan, and record an approval for the plan digest"
terraform init -input=false -no-color >/dev/null
terraform plan -input=false -no-color -var "release=v1" -out=approved.tfplan >/dev/null
echo "plan policy decision: $(plan_decision approved.tfplan)"
approved_digest="$(digest approved.tfplan)"
echo "approved plan digest: $approved_digest"

NOW="$(iso_utc_offset 0)"
approval_record() { # <approver> <expires_at>
  jq -n --arg sha "$approved_digest" --arg agent "$AGENT" --arg requester "$REQUESTER" \
    --arg approver "$1" --arg expires "$2" \
    '{plan_sha256: $sha, agent: $agent, requested_by: $requester, approver: $approver, expires_at: $expires}'
}
approval_record "$APPROVER" "$(iso_utc_offset 3600)" > approval.json
approval_record "$APPROVER" "$(iso_utc_offset -3600)" > approval-expired.json
approval_record "$REQUESTER" "$(iso_utc_offset 3600)" > approval-self.json

echo
echo "== Case 1: apply the approved plan"
execute approved-plan "approved plan" applied true approved.tfplan approval.json "$AGENT" "$NOW"
echo "        applied: release=$(release_state)"

echo
echo "== Case 2: a different plan is made after approval and reuses the approval"
terraform plan -input=false -no-color -var "release=v2-not-reviewed" -out=substituted.tfplan >/dev/null
echo "substituted plan digest: $(digest substituted.tfplan)"
execute substituted-plan "substituted plan" blocked false substituted.tfplan approval.json "$AGENT" "$NOW" v2-not-reviewed

echo
echo "== Case 3: a new plan is made after approval and reuses the approval"
terraform plan -input=false -no-color -var "release=v3-replanned" -out=replanned.tfplan >/dev/null
echo "re-planned plan digest: $(digest replanned.tfplan)"
execute replan-after-approval "re-plan after approval" blocked false replanned.tfplan approval.json "$AGENT" "$NOW" v3-replanned

echo
echo "== Case 4: the approved plan is executed by a different agent"
execute different-agent "different agent" blocked false approved.tfplan approval.json "other-agent" "$NOW"

echo
echo "== Case 5: the approval has expired"
execute expired-approval "expired approval" blocked false approved.tfplan approval-expired.json "$AGENT" "$NOW"

echo
echo "== Case 6: the requester approved their own change"
execute self-approval "self-approval" blocked false approved.tfplan approval-self.json "$AGENT" "$NOW"

echo
echo "== Case 7: no approval is provided"
execute no-approval "no approval" blocked false approved.tfplan none "$AGENT" "$NOW"

echo
echo "applied release is still: $(release_state)"
if [ "$(release_state)" != "v1" ]; then
  echo "FAIL  an unapproved change was applied"
  failures=$((failures + 1))
fi

if [ "$failures" -gt 0 ]; then
  echo "$failures case(s) did not behave as expected"
  exit 1
fi
echo "all cases behaved as expected"
