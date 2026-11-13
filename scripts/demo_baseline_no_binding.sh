#!/usr/bin/env bash
# Baseline for scripts/demo_approval_binding.sh: the same plan swap with the
# control removed.
#
# It models a pipeline where a reviewer approves a plan and the approval is
# recorded against a change identifier (here, the plan's file name). The
# executor checks that an approval exists for that identifier, then applies
# whatever file it finds. Nothing ties the approval to the contents of the
# file that is applied.
#
# This is a model of one common weak design, not a measurement of any named
# product. Tools that tie approval to a specific run or lock the plan file
# behave differently; see docs/evaluation.md.
#
# Exit status 0 means the baseline behaved as modeled: the approved plan was
# applied and the substituted plan was applied too. That second result is a
# failure of protection, and it is the expected one for this configuration.
# Exit status 1 means the baseline did not reproduce.
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
# shellcheck source=scripts/lib/portable.sh
. "$ROOT/scripts/lib/portable.sh"
# shellcheck source=scripts/lib/results.sh
. "$ROOT/scripts/lib/results.sh"
require_tools terraform jq

WORK="$(mktemp -d)"
results_begin no-binding-baseline approved-plan substituted-plan
trap 'results_end; rm -rf "$WORK"' EXIT

PLAN_FILE="approved.tfplan"
failures=0

release_state() {
  local out
  out="$(terraform output -no-color -json)" || return 1
  jq -r '.release.value // "none"' <<<"$out"
}

# fresh_dir <name>: a clean working copy with its own Terraform state.
fresh_dir() {
  mkdir -p "$WORK/$1"
  cp "$ROOT/examples/terraform_pipeline/main.tf" "$WORK/$1/"
  cd "$WORK/$1"
  terraform init -input=false -no-color >/dev/null
}

# approve_plan: plan release=v1, show it to the "reviewer", record an approval by name.
approve_plan() {
  terraform plan -input=false -no-color -var "release=v1" -out="$PLAN_FILE" >/dev/null
  echo "reviewer reads the plan: $(terraform show -no-color "$PLAN_FILE" | grep -E 'release' | head -1 | sed 's/^ *//')"
  echo "$PLAN_FILE approved by bob" > approvals.txt
  echo "approval recorded for: $PLAN_FILE"
}

# run_executor: checks for an approval by name, then applies whatever file is there.
# Sets OBSERVED to applied or blocked.
run_executor() {
  if grep -q "^$PLAN_FILE approved by " approvals.txt; then
    echo "executor: approval found for $PLAN_FILE, applying"
    terraform apply -input=false -no-color "$PLAN_FILE" >/dev/null
    OBSERVED="applied"
  else
    echo "executor: no approval found, refusing"
    OBSERVED="blocked"
  fi
}

echo "== Baseline: approval recorded against a file name, no digest binding"

echo
echo "== Case 1: the approved plan is applied unchanged"
fresh_dir approved-plan
approve_plan
before="$(release_state)"
run_executor
after="$(release_state)"
results_case approved-plan "approved plan" applied true "$OBSERVED" "$before" "$after"
echo "terraform state: release $before -> $after"
[ "$OBSERVED" = "applied" ] && [ "$after" = "v1" ] || { echo "FAIL  the approved plan was not applied"; failures=$((failures + 1)); }

echo
echo "== Case 2: after approval, something that can write the plan location replaces the file"
fresh_dir substituted-plan
approve_plan
terraform plan -input=false -no-color -var "release=v2-not-reviewed" -out="$PLAN_FILE" >/dev/null
echo "the file $PLAN_FILE now holds a different plan"
before="$(release_state)"
run_executor
after="$(release_state)"
# Expected in this model: the substitution is applied. That is a protection failure.
results_case substituted-plan "substituted plan" applied false "$OBSERVED" "$before" "$after"
echo "terraform state: release $before -> $after (approved release was: v1)"
if [ "$after" = "v2-not-reviewed" ]; then
  echo "BASELINE RESULT: an unapproved change was applied."
  echo "scripts/demo_approval_binding.sh case 2 refuses the same swap."
else
  echo "FAIL  the swap did not reproduce; the baseline model is wrong." >&2
  failures=$((failures + 1))
fi

[ "$failures" -eq 0 ] || exit 1
