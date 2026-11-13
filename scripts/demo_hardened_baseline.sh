#!/usr/bin/env bash
# A hardened baseline built from existing controls, run against the same
# scenarios as the other configurations.
#
# It models a GitHub Actions workflow that: saves the plan once per run as an
# artifact that cannot be overwritten; records approval against the run
# (a protected environment with required reviewers, self-review prevented);
# lets only the apply job apply, using the run's saved plan; and needs a new
# approval for a new run, so re-planning invalidates the approval.
#
# This is a local model. It is not a test of GitHub's or any other product's
# behavior, and it does not stand in for the hosted path, which is pending
# (see docs/evaluation.md). What each trust assumption is, and which scenarios
# the configuration has no mechanism for, is written to results.json.
#
# Exit status 0 means every executed case behaved as modeled. A scenario this
# configuration has no mechanism for is reported as unsupported; that is a
# stated property of the configuration, not a pass and not a failure.
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
# shellcheck source=scripts/lib/portable.sh
. "$ROOT/scripts/lib/portable.sh"
# shellcheck source=scripts/lib/results.sh
. "$ROOT/scripts/lib/results.sh"
require_tools terraform jq

WORK="$(mktemp -d)"
results_begin hardened-baseline-model model approved-plan substituted-plan \
  replan-after-approval different-agent expired-approval self-approval no-approval
results_assume "Modeled, not measured: a local model of a GitHub Actions workflow with a protected environment. It does not test GitHub's or any other product's behavior; the hosted path is pending."
results_assume "The saved plan artifact is written once per run and the attacker cannot overwrite it, or delete and re-upload it. If the attacker holds a step or token that can, this configuration does not stop substitution. That has not been tested."
results_assume "Approval is recorded against a run, not against a digest. The reviewer is assumed to have read the plan of that same run."
results_assume "Required reviewers with self-review prevented. Apply credentials are held only by the apply job."
results_assume "There is no agent identity, approval expiry or digest record in this configuration."
trap 'results_end; rm -rf "$WORK"' EXIT

failures=0

release_state() {
  local out
  out="$(terraform output -no-color -json)" || return 1
  jq -r '.release.value // "none"' <<<"$out"
}

fresh_dir() {
  mkdir -p "$WORK/$1/store" "$WORK/$1/approvals"
  cp "$ROOT/examples/terraform_pipeline/main.tf" "$WORK/$1/"
  cd "$WORK/$1"
  terraform init -input=false -no-color >/dev/null
}

# store_put <run> <file>: the artifact store is write-once per run.
store_put() {
  local dest="store/$1/plan.tfplan"
  if [ -e "$dest" ]; then
    echo "artifact store: refused, run $1 already has a saved plan"
    return 1
  fi
  mkdir -p "store/$1"
  cp "$2" "$dest"
  chmod a-w "$dest"
}

# plan_job <run> <release>: plan once and save the plan for the run.
plan_job() {
  terraform plan -input=false -no-color -var "release=$2" -out="tmp-$1.tfplan" >/dev/null
  store_put "$1" "tmp-$1.tfplan"
  echo "plan job: run $1 saved a plan for release $2"
}

# approve_run <run> <approver> <requester>: required reviewers, self-review prevented.
approve_run() {
  if [ "$2" = "$3" ]; then
    echo "environment: self-review prevented, $2 cannot approve their own run $1"
    return 1
  fi
  echo "$2" > "approvals/$1"
  echo "environment: run $1 approved by $2"
}

# apply_job <run>: applies the run's saved plan only if the run was approved.
# Sets OBSERVED to applied or blocked.
apply_job() {
  if [ -f "approvals/$1" ] && [ -f "store/$1/plan.tfplan" ]; then
    echo "apply job: run $1 is approved, applying its saved plan"
    terraform apply -input=false -no-color "store/$1/plan.tfplan" >/dev/null
    OBSERVED="applied"
  else
    echo "apply job: run $1 has no approval, refusing"
    OBSERVED="blocked"
  fi
}

# finish <id> <name> <expected> <authorized> <before> [attacker release]
# With an attacker release, "applied" means that release landed.
finish() {
  local id="$1" name="$2" expected="$3" authorized="$4" before="$5" attacker="${6:-}" after
  after="$(release_state)"
  if [ -n "$attacker" ]; then
    if [ "$after" = "$attacker" ]; then OBSERVED="applied"; else OBSERVED="blocked"; fi
  fi
  results_case "$id" "$name" "$expected" "$authorized" "$OBSERVED" "$before" "$after" "[]" "$attacker"
  echo "terraform state: release $before -> $after"
  if [ "$OBSERVED" != "$expected" ]; then
    echo "FAIL  $name: expected $expected, observed $OBSERVED" >&2
    failures=$((failures + 1))
  fi
}

unsupported() {
  echo
  echo "== $2"
  echo "unsupported: $3"
  results_unsupported "$1" "$3"
}

echo "== Hardened baseline: saved plan per run, run-keyed approval, self-review prevented"

echo
echo "== approved plan"
fresh_dir approved-plan
plan_job run1 v1
approve_run run1 bob alice
before="$(release_state)"
apply_job run1
finish approved-plan "approved plan" applied true "$before"

echo
echo "== substituted plan: the attacker tries to replace the saved plan after approval"
fresh_dir substituted-plan
plan_job run1 v1
approve_run run1 bob alice
terraform plan -input=false -no-color -var "release=v2-not-reviewed" -out=attacker.tfplan >/dev/null
store_put run1 attacker.tfplan || true
before="$(release_state)"
apply_job run1
finish substituted-plan "substituted plan" blocked false "$before" v2-not-reviewed

echo
echo "== re-plan after approval: a new plan is made and presented under the earlier approval"
fresh_dir replan-after-approval
plan_job run1 v1
approve_run run1 bob alice
plan_job run2 v3-replanned
before="$(release_state)"
apply_job run2
finish replan-after-approval "re-plan after approval" blocked false "$before" v3-replanned

unsupported different-agent "different agent" \
  "No agent identity is recorded in the approval, so executing under another identity cannot be detected by this configuration. Apply authority is limited to the apply job's credentials."
unsupported expired-approval "expired approval" \
  "The modeled approval is recorded against a run and has no expiry. Whether the hosted feature offers one is unverified."

echo
echo "== self-approval"
fresh_dir self-approval
plan_job run1 v1
approve_run run1 alice alice || true
before="$(release_state)"
apply_job run1
finish self-approval "self-approval" blocked false "$before"

echo
echo "== no approval"
fresh_dir no-approval
plan_job run1 v1
before="$(release_state)"
apply_job run1
finish no-approval "no approval" blocked false "$before"

[ "$failures" -eq 0 ] || exit 1
