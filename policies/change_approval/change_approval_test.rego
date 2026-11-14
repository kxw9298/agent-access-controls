package agentaccess.change_approval_test

import data.agentaccess.change_approval

digest_a := "3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855a"

digest_b := "9f86d081884c7d659a2feaa0c55ad015a3bf4f1b2b0b822cd15d6c15b0f00a08"

approval := {
	"plan_sha256": digest_a,
	"agent": "deploy-agent",
	"requested_by": "alice",
	"approver": "bob",
	"expires_at": "2026-11-09T13:00:00Z",
}

base := {
	"artifact": {"sha256": digest_a},
	"execution": {"agent": "deploy-agent", "requested_by": "alice", "now": "2026-11-09T12:00:00Z"},
	"plan_decision": {"allow": true, "requires_approval": true},
	"approval": approval,
}

# Replace one top-level field of the base input. The field is removed first
# because object.union merges nested objects instead of replacing them.
with_field(key, value) := object.union(object.remove(base, [key]), {key: value})

with_approval(patch) := with_field("approval", object.union(approval, patch))

denied_with(inp, reason) if {
	not change_approval.allow with input as inp
	reason in change_approval.deny_reasons with input as inp
}

test_allows_approved_plan if {
	change_approval.allow with input as base
}

test_denies_substituted_plan if {
	denied_with(
		with_field("artifact", {"sha256": digest_b}),
		"approved digest does not match the artifact to be applied",
	)
}

test_denies_different_agent if {
	inp := with_field("execution", {"agent": "other-agent", "requested_by": "alice", "now": "2026-11-09T12:00:00Z"})
	denied_with(inp, "executing agent is not the agent named in the approval")
}

test_denies_different_requester if {
	inp := with_field("execution", {"agent": "deploy-agent", "requested_by": "mallory", "now": "2026-11-09T12:00:00Z"})
	denied_with(inp, "requesting user is not the user named in the approval")
}

test_denies_expired_approval if {
	inp := with_field("execution", {"agent": "deploy-agent", "requested_by": "alice", "now": "2026-11-09T13:00:00Z"})
	denied_with(inp, "approval has expired or has no valid expiry")
}

test_denies_approval_without_expiry if {
	inp := with_field("approval", object.remove(approval, ["expires_at"]))
	denied_with(inp, "approval has expired or has no valid expiry")
}

test_denies_unparseable_expiry if {
	denied_with(with_approval({"expires_at": "tomorrow"}), "approval has expired or has no valid expiry")
}

test_denies_self_approval_by_requester if {
	denied_with(with_approval({"approver": "alice"}), "approver is missing, or is the requester or the agent")
}

test_denies_approval_by_agent if {
	denied_with(with_approval({"approver": "deploy-agent"}), "approver is missing, or is the requester or the agent")
}

test_denies_self_approval_with_different_case if {
	denied_with(with_approval({"approver": "Alice"}), "approver is missing, or is the requester or the agent")
}

test_denies_agent_as_approver_with_different_case if {
	denied_with(with_approval({"approver": "DEPLOY-AGENT"}), "approver is missing, or is the requester or the agent")
}

test_denies_missing_approver if {
	inp := with_field("approval", object.remove(approval, ["approver"]))
	denied_with(inp, "approver is missing, or is the requester or the agent")
}

test_denies_high_risk_without_approval if {
	inp := object.remove(base, ["approval"])
	denied_with(inp, "change requires approval and none was provided")
}

test_denies_plan_rejected_by_plan_policy if {
	inp := with_field("plan_decision", {"allow": false, "requires_approval": true})
	denied_with(inp, "plan was denied by the plan policy")
}

test_denies_missing_plan_decision if {
	inp := object.remove(base, ["plan_decision"])
	denied_with(inp, "plan policy decision is missing")
}

test_missing_plan_decision_still_requires_approval if {
	inp := object.remove(base, ["plan_decision", "approval"])
	denied_with(inp, "change requires approval and none was provided")
}

test_denies_malformed_artifact_digest if {
	denied_with(with_field("artifact", {"sha256": "not-a-digest"}), "artifact digest is missing or malformed")
}

test_denies_missing_artifact if {
	denied_with(object.remove(base, ["artifact"]), "artifact digest is missing or malformed")
}

test_denies_missing_execution_identity if {
	inp := with_field("execution", {"now": "2026-11-09T12:00:00Z"})
	denied_with(inp, "executing agent identity is missing")
	denied_with(inp, "requesting user identity is missing")
}

test_denies_empty_input if {
	not change_approval.allow with input as {}
}

test_allows_low_risk_plan_without_approval if {
	inp := object.remove(with_field("plan_decision", {"allow": true, "requires_approval": false}), ["approval"])
	change_approval.allow with input as inp
}

test_decision_records_refusal if {
	d := change_approval.decision with input as with_field("artifact", {"sha256": digest_b})
	d.allow == false
	d.approval_required == true
	d.artifact_sha256 == digest_b
	d.agent == "deploy-agent"
	d.requested_by == "alice"
	d.approver == "bob"
}

test_decision_is_defined_when_no_approval_is_needed if {
	inp := with_field("plan_decision", {"allow": true, "requires_approval": false})
	d := change_approval.decision with input as inp
	d.allow == true
	d.approval_required == false
}

identity_reason := "an identity contains characters other than visible ASCII"

test_denies_approver_with_trailing_space if {
	denied_with(with_approval({"approver": "alice "}), identity_reason)
}

test_denies_approver_with_zero_width_space if {
	denied_with(with_approval({"approver": "ali\u200bce"}), identity_reason)
}

test_denies_decomposed_unicode_approver if {
	inp := with_field("execution", {"agent": "deploy-agent", "requested_by": "jos\u00e9", "now": "2026-11-09T12:00:00Z"})
	inp2 := object.union(inp, {"approval": object.union(approval, {"requested_by": "jos\u00e9", "approver": "jose\u0301"})})
	denied_with(inp2, identity_reason)
}

test_denies_non_ascii_executing_agent if {
	inp := with_field("execution", {"agent": "deploy-ag\u0435nt", "requested_by": "alice", "now": "2026-11-09T12:00:00Z"})
	denied_with(inp, identity_reason)
}

test_denies_whitespace_only_approver if {
	denied_with(with_approval({"approver": " "}), identity_reason)
}

test_allows_bot_style_identities if {
	inp := object.union(base, {
		"execution": {"agent": "owner/repo/.github/workflows/x.yml@refs/heads/main", "requested_by": "dependabot[bot]", "now": "2026-11-09T12:00:00Z"},
		"approval": object.union(approval, {"agent": "owner/repo/.github/workflows/x.yml@refs/heads/main", "requested_by": "dependabot[bot]"}),
	})
	change_approval.allow with input as inp
}
