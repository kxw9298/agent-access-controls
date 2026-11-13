# Policy gate for Terraform plans proposed by AI agents.
#
# Implements control AAC-CH-01: a plan is checked before it can be applied.
# Out-of-scope and protected changes are denied. High-risk changes are
# allowed only with a human approval, which is checked separately against
# the plan digest.
#
# Expected input: the output of `terraform show -json <planfile>`. Only
# `format_version` and `resource_changes` are read:
#   {
#     "format_version": "1.2",
#     "resource_changes": [
#       {"address": "...", "type": "...",
#        "change": {"actions": ["create" | "update" | "delete" | "no-op" | "read"]}}
#     ]
#   }
#
# Expected data:
#   data.change_policy = {
#     "allowed_resource_types": ["..."],    # anything else is out of scope
#     "protected_address_prefixes": ["..."], # may not be deleted or replaced
#     "high_risk_resource_types": ["..."]    # any change needs approval
#   }
package agentaccess.terraform_plan

default allow := false

allow if count(deny_reasons) == 0

default requires_approval := false

requires_approval if count(approval_reasons) > 0

# Resource changes that do something. Terraform lists unchanged resources
# and data-source reads in the plan as well.
changes contains rc if {
	some rc in input.resource_changes
	some action in rc.change.actions
	action in {"create", "update", "delete"}
}

# A replacement appears as ["delete", "create"] or ["create", "delete"].
destructive(rc) if "delete" in rc.change.actions

# Helper rules keep undefined policy data inside the negations below, so
# that missing data denies instead of silently allowing.
policy_loaded if is_array(data.change_policy.allowed_resource_types)

type_allowed(type) if type in data.change_policy.allowed_resource_types

protected(rc) if {
	some prefix in data.change_policy.protected_address_prefixes
	startswith(rc.address, prefix)
}

# Fail closed on input this policy does not understand.
deny_reasons contains "plan format not supported" if {
	not startswith(object.get(input, "format_version", ""), "1.")
}

deny_reasons contains "plan has no resource_changes list" if {
	not is_array(object.get(input, "resource_changes", null))
}

deny_reasons contains "change policy data is missing" if {
	not policy_loaded
}

deny_reasons contains msg if {
	some rc in changes
	not type_allowed(rc.type)
	msg := sprintf("resource type out of scope: %s (%s)", [rc.type, rc.address])
}

deny_reasons contains msg if {
	some rc in changes
	destructive(rc)
	protected(rc)
	msg := sprintf("protected resource may not be deleted or replaced: %s", [rc.address])
}

approval_reasons contains msg if {
	some rc in changes
	destructive(rc)
	msg := sprintf("deletes or replaces a resource: %s", [rc.address])
}

approval_reasons contains msg if {
	some rc in changes
	rc.type in data.change_policy.high_risk_resource_types
	msg := sprintf("changes a high-risk resource type: %s (%s)", [rc.type, rc.address])
}

summary := {
	"create": count([rc | some rc in changes; "create" in rc.change.actions; not destructive(rc)]),
	"update": count([rc | some rc in changes; "update" in rc.change.actions]),
	"delete": count([rc | some rc in changes; destructive(rc); not "create" in rc.change.actions]),
	"replace": count([rc | some rc in changes; destructive(rc); "create" in rc.change.actions]),
}

# Decision passed to the approval check and kept as the record of this gate.
decision := {
	"allow": allow,
	"requires_approval": requires_approval,
	"deny_reasons": deny_reasons,
	"approval_reasons": approval_reasons,
	"summary": summary,
}
