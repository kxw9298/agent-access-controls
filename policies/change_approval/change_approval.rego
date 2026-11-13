# Approval binding for agent-proposed infrastructure changes.
#
# Implements controls AAC-CH-02 (approval bound to the digest of the exact
# change), AAC-CH-03 (artifact verified at execution), and AAC-CH-04
# (approval bound to agent and user identity, with expiry).
#
# The executor evaluates this policy immediately before it applies a saved
# plan. It must compute `artifact.sha256` itself, from the same file it is
# about to apply.
#
# Expected input:
#   {
#     "artifact":      {"sha256": "<64 hex chars>"},
#     "execution":     {"agent": "...", "requested_by": "...",
#                       "now": "<RFC 3339 time>"},
#     "plan_decision": {"allow": true, "requires_approval": true},
#     "approval":      {"plan_sha256": "...", "agent": "...",
#                       "requested_by": "...", "approver": "...",
#                       "expires_at": "<RFC 3339 time>"}
#   }
#
# `plan_decision` is the decision from policies/terraform_plan. `approval`
# may be absent when the plan policy does not require one.
package agentaccess.change_approval

default allow := false

allow if count(deny_reasons) == 0

# Helper rules keep possibly-undefined input inside the negations below, so
# that a missing field denies instead of silently allowing.
valid_digest(value) if regex.match(`^[0-9a-f]{64}$`, value)

artifact_digest_valid if valid_digest(input.artifact.sha256)

plan_decision_present if {
	is_boolean(input.plan_decision.allow)
	is_boolean(input.plan_decision.requires_approval)
}

plan_allowed if input.plan_decision.allow == true

nonempty_string(value) if {
	is_string(value)
	value != ""
}

agent_present if nonempty_string(input.execution.agent)

requester_present if nonempty_string(input.execution.requested_by)

# Anything other than an explicit "no approval needed" requires approval.
approval_not_required if input.plan_decision.requires_approval == false

approval_required if not approval_not_required

approval_present if is_object(input.approval)

digest_matches if {
	valid_digest(input.approval.plan_sha256)
	input.approval.plan_sha256 == input.artifact.sha256
}

agent_matches if input.approval.agent == input.execution.agent

requester_matches if input.approval.requested_by == input.execution.requested_by

approver_present if nonempty_string(input.approval.approver)

# Identities are compared without regard to letter case. GitHub logins and many
# directory identities are case-insensitive, so "Alice" and "alice" are one
# person and must not count as two. An identity that is not a string makes the
# comparison undefined, which denies.
approver_independent if {
	approver_present
	lower(input.approval.approver) != lower(input.approval.requested_by)
	lower(input.approval.approver) != lower(input.approval.agent)
	lower(input.approval.approver) != lower(input.execution.requested_by)
	lower(input.approval.approver) != lower(input.execution.agent)
}

approval_current if {
	expires := time.parse_rfc3339_ns(input.approval.expires_at)
	now := time.parse_rfc3339_ns(input.execution.now)
	now < expires
}

deny_reasons contains "plan policy decision is missing" if not plan_decision_present

deny_reasons contains "plan was denied by the plan policy" if {
	plan_decision_present
	not plan_allowed
}

deny_reasons contains "artifact digest is missing or malformed" if not artifact_digest_valid

deny_reasons contains "executing agent identity is missing" if not agent_present

deny_reasons contains "requesting user identity is missing" if not requester_present

deny_reasons contains "change requires approval and none was provided" if {
	approval_required
	not approval_present
}

deny_reasons contains "approved digest does not match the artifact to be applied" if {
	approval_required
	approval_present
	not digest_matches
}

deny_reasons contains "executing agent is not the agent named in the approval" if {
	approval_required
	approval_present
	not agent_matches
}

deny_reasons contains "requesting user is not the user named in the approval" if {
	approval_required
	approval_present
	not requester_matches
}

deny_reasons contains "approver is missing, or is the requester or the agent" if {
	approval_required
	approval_present
	not approver_independent
}

deny_reasons contains "approval has expired or has no valid expiry" if {
	approval_required
	approval_present
	not approval_current
}

# Decision record for this execution check.
decision := {
	"allow": allow,
	"reasons": deny_reasons,
	"approval_required": approval_required,
	"artifact_sha256": object.get(input, ["artifact", "sha256"], null),
	"agent": object.get(input, ["execution", "agent"], null),
	"requested_by": object.get(input, ["execution", "requested_by"], null),
	"approver": object.get(input, ["approval", "approver"], null),
}
