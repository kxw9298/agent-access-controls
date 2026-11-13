#!/usr/bin/env bash
# Baseline for scripts/demo_approval_binding.sh: the same scenarios with the
# control removed.
#
# It models a pipeline where a reviewer approves a plan and the approval is
# recorded against a change identifier (here, the plan's file name). The
# executor checks that an approval exists for that identifier, then applies
# whatever file it finds. It records no digest, no agent identity, no
# requester and no expiry, so it checks none of them.
#
# This is a model of one weak design, not a measurement of any named
# product and not a stand-in for a well-configured workflow; see
# scripts/demo_hardened_baseline.sh and docs/evaluation.md.
#
# Exit status 0 means every case behaved as modeled. Most attack cases are
# expected to be applied: that matches the model's expectation and is a
# failure of protection. Exit status 1 means the model did not reproduce.
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
# shellcheck source=scripts/lib/portable.sh
. "$ROOT/scripts/lib/portable.sh"
# shellcheck source=scripts/lib/results.sh
. "$ROOT/scripts/lib/results.sh"
require_tools terraform jq

WORK="$(mktemp -d)"
results_begin no-binding-baseline model approved-plan substituted-plan \
  replan-after-approval different-agent expired-approval self-approval no-approval
results_assume "Modeled, not measured: it represents a pipeline that records approval against a file name and does not hash what it applies."
results_assume "The executor checks only that an approval line exists for the plan's file name."
results_assume "Approvals carry no digest, agent, requester or expiry, so none can be checked."
results_assume "Anything that can write the plan file can change what is applied."
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

# run_executor: checks for an approval by name, then applies whatever file is there.
# Sets OBSERVED to applied or blocked.
run_executor() {
  if [ -f approvals.txt ] && grep -q "^$PLAN_FILE approved by " approvals.txt; then
    echo "executor: approval found for $PLAN_FILE, applying"
    terraform apply -input=false -no-color "$PLAN_FILE" >/dev/null
    OBSERVED="applied"
  else
    echo "executor: no approval found, refusing"
    OBSERVED="blocked"
  fi
}

# run_case <id> <name> <expected: applied|blocked> <authorized: true|false> <variant>
# Variants: none, substitute, replan, other-agent, late, self, unapproved.
run_case() {
  local id="$1" name="$2" expected="$3" authorized="$4" variant="$5" attacker="${6:-}" before after
  echo
  echo "== $name"
  fresh_dir "$id"
  terraform plan -input=false -no-color -var "release=v1" -out="$PLAN_FILE" >/dev/null
  echo "reviewer reads the plan: $(terraform show -no-color "$PLAN_FILE" | grep -E 'release' | head -1 | sed 's/^ *//')"
  case "$variant" in
    unapproved) echo "no approval recorded" ;;
    self)       echo "$PLAN_FILE approved by alice" > approvals.txt
                echo "approval recorded by the requester (alice)" ;;
    *)          echo "$PLAN_FILE approved by bob" > approvals.txt
                echo "approval recorded for: $PLAN_FILE" ;;
  esac
  case "$variant" in
    substitute) terraform plan -input=false -no-color -var "release=v2-not-reviewed" -out="$PLAN_FILE" >/dev/null
                echo "the file $PLAN_FILE now holds a different plan" ;;
    replan)     terraform plan -input=false -no-color -var "release=v3-replanned" -out="$PLAN_FILE" >/dev/null
                echo "a new plan was written to $PLAN_FILE after approval" ;;
    other-agent) echo "the executor is run by a different agent; this model does not check who runs it" ;;
    late)       echo "the approval was granted long ago; this model records no expiry" ;;
  esac
  before="$(release_state)"
  run_executor
  after="$(release_state)"
  results_case "$id" "$name" "$expected" "$authorized" "$OBSERVED" "$before" "$after" "[]" "$attacker"
  echo "terraform state: release $before -> $after"
  if [ "$OBSERVED" != "$expected" ]; then
    echo "FAIL  $name: expected $expected, observed $OBSERVED" >&2
    failures=$((failures + 1))
  elif [ "$authorized" = "false" ] && [ "$OBSERVED" = "applied" ]; then
    echo "BASELINE RESULT: an unauthorized change was applied (protection not held)."
  fi
}

echo "== Baseline: approval recorded against a file name, no digest binding"
run_case approved-plan          "approved plan"          applied true  none
run_case substituted-plan       "substituted plan"       applied false substitute v2-not-reviewed
run_case replan-after-approval  "re-plan after approval" applied false replan v3-replanned
run_case different-agent        "different agent"        applied false other-agent
run_case expired-approval       "expired approval"       applied false late
run_case self-approval          "self-approval"          applied false self
run_case no-approval            "no approval"            blocked false unapproved

[ "$failures" -eq 0 ] || exit 1
