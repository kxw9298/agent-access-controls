package agentaccess.image_admission_test

import data.agentaccess.image_admission

digest_a := "sha256:3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855a"

digest_b := "sha256:9f86d081884c7d659a2feaa0c55ad015a3bf4f1b2b0b822cd15d6c15b0f00a08"

approval := {
	"image_digest": digest_a,
	"agent": "deploy-agent",
	"requested_by": "alice",
	"approver": "bob",
	"expires_at": "2026-12-01T13:00:00Z",
}

execution := {"agent": "deploy-agent", "requested_by": "alice", "now": "2026-12-01T12:00:00Z"}

base := {
	"image": {"reference": concat("@", ["registry.example/app", digest_a])},
	"execution": execution,
	"approval": approval,
}

# Replace one top-level field of the base input. The field is removed first
# because object.union merges nested objects instead of replacing them.
with_field(key, value) := object.union(object.remove(base, [key]), {key: value})

with_approval(patch) := with_field("approval", object.union(approval, patch))

denied_with(inp, reason) if {
	not image_admission.allow with input as inp
	reason in image_admission.deny_reasons with input as inp
}

test_allows_approved_image if {
	image_admission.allow with input as base
}

test_publishes_only_the_approved_digest if {
	image_admission.approved_digest == digest_a with input as base
}

test_publishes_nothing_when_denied if {
	inp := with_field("image", {"reference": concat("@", ["registry.example/app", digest_b])})
	not image_admission.approved_digest with input as inp
}

test_denies_different_digest if {
	inp := with_field("image", {"reference": concat("@", ["registry.example/app", digest_b])})
	denied_with(inp, "approved digest does not match the image to be deployed")
}

test_denies_tag_reference if {
	inp := with_field("image", {"reference": "registry.example/app:latest"})
	denied_with(inp, "image reference is not pinned to a sha256 digest")
}

test_denies_tag_and_digest_with_other_repo_form if {
	inp := with_field("image", {"reference": "registry.example/app:1.0@sha256:short"})
	denied_with(inp, "image reference is not pinned to a sha256 digest")
}

test_denies_missing_reference if {
	inp := object.remove(base, ["image"])
	denied_with(inp, "image reference is not pinned to a sha256 digest")
}

test_denies_different_agent if {
	inp := with_field("execution", object.union(execution, {"agent": "other-agent"}))
	denied_with(inp, "executing agent is not the agent named in the approval")
}

test_denies_different_requester if {
	inp := with_field("execution", object.union(execution, {"requested_by": "mallory"}))
	denied_with(inp, "requesting user is not the user named in the approval")
}

test_denies_expired_approval if {
	inp := with_field("execution", object.union(execution, {"now": "2026-12-01T13:00:00Z"}))
	denied_with(inp, "approval has expired or has no valid expiry")
}

test_denies_unparseable_expiry if {
	denied_with(with_approval({"expires_at": "tomorrow"}), "approval has expired or has no valid expiry")
}

test_denies_self_approval_by_requester if {
	denied_with(with_approval({"approver": "alice"}), "approver is missing, or is the requester or the agent")
}

test_denies_self_approval_by_agent if {
	denied_with(with_approval({"approver": "deploy-agent"}), "approver is missing, or is the requester or the agent")
}

test_denies_self_approval_with_different_case if {
	denied_with(with_approval({"approver": "Alice"}), "approver is missing, or is the requester or the agent")
}

test_denies_missing_approver if {
	inp := with_field("approval", object.remove(approval, ["approver"]))
	denied_with(inp, "approver is missing, or is the requester or the agent")
}

test_denies_no_approval if {
	inp := object.remove(base, ["approval"])
	denied_with(inp, "no approval was provided")
}

test_denies_malformed_approved_digest if {
	denied_with(with_approval({"image_digest": "sha256:abc"}), "approved digest does not match the image to be deployed")
}

test_denies_missing_execution_identity if {
	inp := with_field("execution", {"now": "2026-12-01T12:00:00Z"})
	denied_with(inp, "executing agent identity is missing")
}

identity_reason := "an identity contains characters other than visible ASCII"

test_denies_approver_with_trailing_space if {
	denied_with(with_approval({"approver": "alice "}), identity_reason)
}

test_denies_approver_with_zero_width_space if {
	denied_with(with_approval({"approver": "ali\u200bce"}), identity_reason)
}

test_denies_non_ascii_executing_agent if {
	inp := with_field("execution", object.union(execution, {"agent": "deploy-ag\u0435nt"}))
	denied_with(inp, identity_reason)
}
