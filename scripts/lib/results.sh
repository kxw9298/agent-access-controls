# Records evaluation cases as JSON. Source after portable.sh. Needs jq.
#
#   results_begin <configuration> <planned case id>...
#   results_case  <id> <name> <expected: applied|blocked> <authorized: true|false> \
#                 <observed: applied|blocked> <state before> <state after> [reasons JSON array]
#   results_end   # writes the file named by $RESULTS_FILE, if set; safe in an EXIT trap
#
# "authorized" says whether applying in this case would be a change the
# approval covers (true for the benign case, false for an attack). Protection
# is judged only on unauthorized cases: it holds when nothing was applied and
# the state did not change. A planned case that was never recorded is reported
# as not_executed, so an aborted run cannot look like a pass.

_RESULTS_CONFIG=""
_RESULTS_PLANNED=""
_RESULTS_CASES=""

results_begin() {
  _RESULTS_CONFIG="$1"; shift
  _RESULTS_PLANNED="$*"
  _RESULTS_CASES="$(mktemp)"
  if [ -n "${RESULTS_FILE:-}" ]; then
    mkdir -p "$(dirname "$RESULTS_FILE")"
    RESULTS_FILE="$(cd "$(dirname "$RESULTS_FILE")" && pwd)/$(basename "$RESULTS_FILE")"
  fi
}

results_case() {
  local id="$1" name="$2" expected="$3" authorized="$4" observed="$5"
  local before="$6" after="$7" reasons="${8:-[]}" protection
  if [ "$authorized" = "true" ]; then
    protection="not_applicable"
  elif [ "$observed" = "blocked" ] && [ "$before" = "$after" ]; then
    protection="held"
  else
    protection="not_held"
  fi
  jq -nc \
    --arg id "$id" --arg name "$name" --arg expected "$expected" \
    --argjson authorized "$authorized" --arg observed "$observed" \
    --arg before "$before" --arg after "$after" \
    --argjson reasons "$reasons" --arg protection "$protection" \
    '{id: $id, name: $name, status: "executed",
      change_authorized: $authorized,
      expected_outcome: $expected, observed_outcome: $observed,
      matched_expectation: ($expected == $observed),
      denial_reasons: $reasons,
      terraform_state: {release_before: $before, release_after: $after},
      protection: $protection}' >> "$_RESULTS_CASES"
}

results_end() {
  [ -n "${RESULTS_FILE:-}" ] || return 0
  [ -n "$_RESULTS_CASES" ] || return 0
  jq -s --arg config "$_RESULTS_CONFIG" --arg planned "$_RESULTS_PLANNED" '
    . as $recorded
    | ($planned | split(" ") | map(select(. != ""))) as $ids
    | ($ids | map(. as $id
        | ($recorded | map(select(.id == $id)) | first)
          // {id: $id, status: "not_executed"})) as $cases
    | {configuration: $config,
       cases: $cases,
       summary: {
         planned: ($ids | length),
         executed: ($cases | map(select(.status == "executed")) | length),
         not_executed: ($cases | map(select(.status != "executed")) | length),
         matched_expectation: ($cases | map(select(.matched_expectation == true)) | length),
         protection_held: ($cases | map(select(.protection == "held")) | length),
         protection_not_held: ($cases | map(select(.protection == "not_held")) | length)}}
  ' "$_RESULTS_CASES" > "$RESULTS_FILE"
  rm -f "$_RESULTS_CASES"
}
