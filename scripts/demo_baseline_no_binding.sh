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
# Exit status 0 means the baseline behaved as modeled (the unapproved change
# was applied). Exit status 1 means the baseline did not reproduce.
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
# shellcheck source=scripts/lib/portable.sh
. "$ROOT/scripts/lib/portable.sh"
require_tools terraform

WORK="$(mktemp -d)"
trap 'rm -rf "$WORK"' EXIT
cp "$ROOT/examples/terraform_pipeline/main.tf" "$WORK/"
cd "$WORK"

PLAN_FILE="approved.tfplan"

echo "== Baseline: approval recorded against a file name, no digest binding"
terraform init -input=false -no-color >/dev/null

echo
echo "== Step 1: a plan is made and a reviewer approves it"
terraform plan -input=false -no-color -var "release=v1" -out="$PLAN_FILE" >/dev/null
echo "reviewer reads the plan: $(terraform show -no-color "$PLAN_FILE" | grep -E 'release' | head -1 | sed 's/^ *//')"
echo "$PLAN_FILE approved by bob" > approvals.txt
echo "approval recorded for: $PLAN_FILE"

echo
echo "== Step 2: after approval, something that can write the plan location replaces the file"
terraform plan -input=false -no-color -var "release=v2-not-reviewed" -out="$PLAN_FILE" >/dev/null
echo "the file $PLAN_FILE now holds a different plan"

echo
echo "== Step 3: the executor checks for an approval by name, then applies"
if grep -q "^$PLAN_FILE approved by " approvals.txt; then
  echo "executor: approval found for $PLAN_FILE, applying"
  terraform apply -input=false -no-color "$PLAN_FILE" >/dev/null
else
  echo "executor: no approval found, refusing"
fi

applied="$(terraform output -raw release 2>/dev/null || echo "none")"
echo
echo "applied release: $applied (approved release was: v1)"
if [ "$applied" = "v2-not-reviewed" ]; then
  echo "BASELINE RESULT: an unapproved change was applied."
  echo "scripts/demo_approval_binding.sh case 2 refuses the same swap."
  exit 0
fi
echo "BASELINE RESULT: the swap did not reproduce; the baseline model is wrong." >&2
exit 1
