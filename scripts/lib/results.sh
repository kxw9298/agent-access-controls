# Records evaluation cases as JSON. Source after portable.sh. Needs jq.
#
#   results_begin <configuration> <kind: model|implementation> <planned scenario id>...
#   results_assume <trust assumption>             # repeatable
#   results_case  <id> <name> <expected: applied|blocked> <authorized: true|false> \
#                 <observed: applied|blocked> <state before> <state after> [reasons JSON array] [attacker release]
#   results_unsupported <id> <reason>            # the configuration has no mechanism for this scenario
#   results_end   # writes the file named by $RESULTS_FILE, if set; safe in an EXIT trap
#
# "authorized" says whether applying in this case would be a change the
# approval covers (true for the benign case, false for an attack). Protection
# is judged only on unauthorized cases. When the attack tries to land a
# specific release ("attacker release"), protection holds if that release is
# not the state afterwards. Otherwise it holds when nothing was applied and the
# state did not change. A planned scenario that was neither executed nor
# reported unsupported is reported as not_executed, so an aborted run cannot
# look like a pass. "unsupported" is a stated property of a configuration,
# not a failure and not protection.

_RESULTS_CONFIG=""
_RESULTS_KIND=""
_RESULTS_PLANNED=""
_RESULTS_CASES=""
_RESULTS_ASSUMPTIONS=""

results_begin() {
  _RESULTS_CONFIG="$1"; _RESULTS_KIND="$2"; shift 2
  _RESULTS_PLANNED="$*"
  _RESULTS_CASES="$(mktemp)"
  _RESULTS_ASSUMPTIONS="$(mktemp)"
  if [ -n "${RESULTS_FILE:-}" ]; then
    mkdir -p "$(dirname "$RESULTS_FILE")"
    RESULTS_FILE="$(cd "$(dirname "$RESULTS_FILE")" && pwd)/$(basename "$RESULTS_FILE")"
  fi
}

results_assume() {
  printf '%s\n' "$1" >> "$_RESULTS_ASSUMPTIONS"
}

results_case() {
  local id="$1" name="$2" expected="$3" authorized="$4" observed="$5"
  local before="$6" after="$7" reasons="${8:-[]}" attacker="${9:-}" protection
  if [ "$authorized" = "true" ]; then
    protection="not_applicable"
  elif [ -n "$attacker" ]; then
    if [ "$after" != "$attacker" ]; then protection="held"; else protection="not_held"; fi
  elif [ "$observed" = "blocked" ] && [ "$before" = "$after" ]; then
    protection="held"
  else
    protection="not_held"
  fi
  jq -nc \
    --arg id "$id" --arg name "$name" --arg expected "$expected" \
    --argjson authorized "$authorized" --arg observed "$observed" \
    --arg before "$before" --arg after "$after" \
    --argjson reasons "$reasons" --arg protection "$protection" --arg attacker "$attacker" \
    '{id: $id, name: $name, status: "executed",
      change_authorized: $authorized,
      expected_outcome: $expected, observed_outcome: $observed,
      matched_expectation: ($expected == $observed),
      denial_reasons: $reasons,
      terraform_state: {release_before: $before, release_after: $after},
      unauthorized_release: (if $attacker == "" then null else $attacker end),
      protection: $protection}' >> "$_RESULTS_CASES"
}

results_unsupported() {
  jq -nc --arg id "$1" --arg reason "$2" \
    '{id: $id, status: "unsupported", reason: $reason}' >> "$_RESULTS_CASES"
}

results_end() {
  [ -n "${RESULTS_FILE:-}" ] || return 0
  [ -n "$_RESULTS_CASES" ] || return 0
  jq -s --arg config "$_RESULTS_CONFIG" --arg kind "$_RESULTS_KIND" \
    --arg planned "$_RESULTS_PLANNED" \
    --rawfile assumptions "$_RESULTS_ASSUMPTIONS" '
    . as $recorded
    | ($planned | split(" ") | map(select(. != ""))) as $ids
    | ($ids | map(. as $id
        | ($recorded | map(select(.id == $id)) | first)
          // {id: $id, status: "not_executed"})) as $cases
    | {configuration: $config,
       kind: $kind,
       trust_assumptions: ($assumptions | split("\n") | map(select(. != ""))),
       cases: $cases,
       summary: {
         planned: ($ids | length),
         executed: ($cases | map(select(.status == "executed")) | length),
         unsupported: ($cases | map(select(.status == "unsupported")) | length),
         not_executed: ($cases | map(select(.status == "not_executed")) | length),
         matched_expectation: ($cases | map(select(.matched_expectation == true)) | length),
         protection_held: ($cases | map(select(.protection == "held")) | length),
         protection_not_held: ($cases | map(select(.protection == "not_held")) | length)}}
  ' "$_RESULTS_CASES" > "$RESULTS_FILE"
  rm -f "$_RESULTS_CASES" "$_RESULTS_ASSUMPTIONS"
}
