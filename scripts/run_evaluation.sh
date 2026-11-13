#!/usr/bin/env bash
# Runs the no-binding baseline and the approval-binding demonstration, and
# merges their per-case records into one results.json in $RESULTS_DIR
# (default: ./results). Exit status is non-zero if either script fails, any
# planned case did not run, or any case differed from its expected outcome.
#
# "matched_expectation" and "protection" are separate on purpose. The
# baseline is expected to apply the substituted plan, so it matches its
# expectation while protection is "not_held".
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
# shellcheck source=scripts/lib/portable.sh
. "$ROOT/scripts/lib/portable.sh"
require_tools terraform opa jq

RESULTS_DIR="${RESULTS_DIR:-$ROOT/results}"
mkdir -p "$RESULTS_DIR"
RESULTS_DIR="$(cd "$RESULTS_DIR" && pwd)"
rm -f "$RESULTS_DIR"/no-binding-baseline.json "$RESULTS_DIR"/approval-binding.json "$RESULTS_DIR"/results.json

COMMIT="${SOURCE_COMMIT:-$(git -C "$ROOT" rev-parse HEAD 2>/dev/null || echo unknown)}"

status=0
RESULTS_FILE="$RESULTS_DIR/no-binding-baseline.json" "$ROOT/scripts/demo_baseline_no_binding.sh" || status=$?
echo
RESULTS_FILE="$RESULTS_DIR/approval-binding.json" "$ROOT/scripts/demo_approval_binding.sh" || status=$?

files=()
for name in no-binding-baseline approval-binding; do
  [ -f "$RESULTS_DIR/$name.json" ] && files+=("$RESULTS_DIR/$name.json")
done

if [ "${#files[@]}" -eq 0 ]; then
  echo "runner error: no results were produced" >&2
  exit 1
fi

jq -s \
  --arg commit "$COMMIT" \
  --arg terraform "$(terraform version -json | jq -r .terraform_version)" \
  --arg opa "$(opa version | awk '/^Version:/ {print $2}')" \
  --arg jq "$(jq --version)" \
  --arg expected "no-binding-baseline approval-binding" '
  {schema_version: "1.0.0",
   source_commit: $commit,
   tool_versions: {terraform: $terraform, opa: $opa, jq: $jq},
   configurations: .,
   verdict: (
     ($expected | split(" ")) as $want
     | (map(.configuration)) as $have
     | {all_configurations_present: ($want - $have | length == 0),
        all_cases_executed: (all(.[]; .summary.not_executed == 0)),
        all_matched_expectation: (all(.[]; .summary.matched_expectation == .summary.executed)),
        protection_not_held_cases: (map(.summary.protection_not_held) | add)})}
' "${files[@]}" > "$RESULTS_DIR/results.json"

echo
echo "results written to: $RESULTS_DIR/results.json"
jq -c '.verdict' "$RESULTS_DIR/results.json"

jq -e '.verdict.all_configurations_present and .verdict.all_cases_executed and .verdict.all_matched_expectation' \
  "$RESULTS_DIR/results.json" >/dev/null || status=1
exit "$status"
