#!/usr/bin/env bash
# Build the approval record for this workflow run from GitHub's own review
# history for the protected environment. Writes nothing if nobody approved.
#
# Usage: build_approval.sh <environment> <output file>
# Environment variables:
#   PLAN_SHA256, PLAN_AGENT, PLAN_REQUESTED_BY, PLANNED_AT - outputs of the plan job
#   PLAN_MAX_AGE_HOURS - how long after planning an approval stays valid
#   GH_TOKEN - token with `actions: read`
set -euo pipefail

ENVIRONMENT="$1"
OUT="$2"
: "${PLAN_SHA256:?}" "${PLAN_AGENT:?}" "${PLAN_REQUESTED_BY:?}" "${PLANNED_AT:?}" "${PLAN_MAX_AGE_HOURS:?}"
: "${GITHUB_REPOSITORY:?}" "${GITHUB_RUN_ID:?}"

approver="$(gh api "repos/$GITHUB_REPOSITORY/actions/runs/$GITHUB_RUN_ID/approvals" |
  jq -r --arg env "$ENVIRONMENT" \
    '[.[] | select(.state == "approved" and any(.environments[]; .name == $env))] | last | .user.login // empty')"

if [ -z "$approver" ]; then
  echo "no approval recorded for environment '$ENVIRONMENT' in this run"
  exit 0
fi

expires_at="$(date -u -d "$PLANNED_AT + $PLAN_MAX_AGE_HOURS hours" +%Y-%m-%dT%H:%M:%SZ)"
jq -n --arg sha "$PLAN_SHA256" --arg agent "$PLAN_AGENT" --arg requester "$PLAN_REQUESTED_BY" \
  --arg approver "$approver" --arg expires "$expires_at" \
  '{plan_sha256: $sha, agent: $agent, requested_by: $requester, approver: $approver, expires_at: $expires}' > "$OUT"
echo "approval recorded by $approver, valid until $expires_at"
