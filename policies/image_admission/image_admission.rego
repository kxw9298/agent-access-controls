# Approval of a container image by digest, for agent-proposed deployments.
#
# Decides whether a person's approval covers the exact image an agent wants
# to run. When it allows, the digest is published to the cluster, where
# Kubernetes admission (examples/image_admission/admission-policy.yaml)
# refuses any image whose digest was not published. The two stages are
# separate on purpose: this policy decides what may be approved; the cluster
# enforces it even if the agent or the pipeline is bypassed.
#
# Not implemented: verification of an image signature or of a supply-chain
# attestation. A digest identifies image content; it does not say who built
# it. See docs/image-admission.md.
#
# Expected input:
#   {
#     "image":     {"reference": "<repo>@sha256:<64 hex chars>"},
#     "execution": {"agent": "...", "requested_by": "...",
#                   "now": "<RFC 3339 time>"},
#     "approval":  {"image_digest": "sha256:<64 hex chars>", "agent": "...",
#                   "requested_by": "...", "approver": "...",
#                   "expires_at": "<RFC 3339 time>"}
#   }
package agentaccess.image_admission

default allow := false

allow if count(deny_reasons) == 0

# Helper rules keep possibly-undefined input inside the negations below, so
# that a missing field denies instead of silently allowing.
pinned_reference(ref) if regex.match(`^[^@\s]+@sha256:[0-9a-f]{64}$`, ref)

valid_digest(value) if regex.match(`^sha256:[0-9a-f]{64}$`, value)

nonempty_string(value) if {
	is_string(value)
	value != ""
}

reference_pinned if pinned_reference(input.image.reference)

image_digest := concat("@", array.slice(split(input.image.reference, "@"), 1, 2)) if reference_pinned

agent_present if nonempty_string(input.execution.agent)

requester_present if nonempty_string(input.execution.requested_by)

approval_present if is_object(input.approval)

digest_matches if {
	valid_digest(input.approval.image_digest)
	input.approval.image_digest == image_digest
}

agent_matches if input.approval.agent == input.execution.agent

requester_matches if input.approval.requested_by == input.execution.requested_by

approver_independent if {
	nonempty_string(input.approval.approver)
	input.approval.approver != input.approval.requested_by
	input.approval.approver != input.approval.agent
	input.approval.approver != input.execution.requested_by
	input.approval.approver != input.execution.agent
}

approval_current if {
	expires := time.parse_rfc3339_ns(input.approval.expires_at)
	now := time.parse_rfc3339_ns(input.execution.now)
	now < expires
}

deny_reasons contains "image reference is not pinned to a sha256 digest" if not reference_pinned

deny_reasons contains "executing agent identity is missing" if not agent_present

deny_reasons contains "requesting user identity is missing" if not requester_present

deny_reasons contains "no approval was provided" if not approval_present

deny_reasons contains "approved digest does not match the image to be deployed" if {
	approval_present
	reference_pinned
	not digest_matches
}

deny_reasons contains "executing agent is not the agent named in the approval" if {
	approval_present
	not agent_matches
}

deny_reasons contains "requesting user is not the user named in the approval" if {
	approval_present
	not requester_matches
}

deny_reasons contains "approver is missing, or is the requester or the agent" if {
	approval_present
	not approver_independent
}

deny_reasons contains "approval has expired or has no valid expiry" if {
	approval_present
	not approval_current
}

# The digest the cluster may admit. Present only when the request is allowed.
approved_digest := image_digest if allow

published_digest := approved_digest

published_digest := null if not allow

decision := {
	"allow": allow,
	"reasons": deny_reasons,
	"approved_digest": published_digest,
	"agent": object.get(input, ["execution", "agent"], null),
	"requested_by": object.get(input, ["execution", "requested_by"], null),
	"approver": object.get(input, ["approval", "approver"], null),
}
