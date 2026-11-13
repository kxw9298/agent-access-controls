# Tool-level authorization for AI agents.
#
# Implements controls AAC-AZ-01 (per-agent grants, deny by default),
# AAC-AZ-02 (user entitlements on delegated calls), AAC-AZ-03 (approval for
# high-impact actions), and the decision record used by AAC-AU-01.
#
# Expected input:
#   {
#     "agent":   {"id": "...", "identity_verified": true},
#     "user":    {"id": "...", "entitlements": ["..."]},
#     "request": {"id": "...", "server": "...", "tool": "...", "action": "...",
#                 "approval": {"granted": true, "approver": "..."}}
#   }
#
# Expected data:
#   data.grants[agent_id] = [{"server": "...", "tool": "...", "actions": ["..."]}]
#   data.tools[server][tool] = {"impact": "low" | "high",
#                               "required_entitlement": "..."}
#
# Tool metadata is fail-closed: a tool whose "impact" is not "low" or "high",
# or that has no "required_entitlement", is denied rather than treated as
# low-impact or entitlement-free.
package agentaccess.tool_authz

default allow := false

allow if count(deny_reasons) == 0

tool_meta := data.tools[input.request.server][input.request.tool]

valid_impacts := {"low", "high"}

tool_meta_valid if {
	tool_meta.impact in valid_impacts
	is_string(tool_meta.required_entitlement)
	tool_meta.required_entitlement != ""
}

tool_granted if {
	some grant in data.grants[input.agent.id]
	grant.server == input.request.server
	grant.tool == input.request.tool
	input.request.action in grant.actions
}

user_has_entitlement(entitlement) if {
	entitlement in input.user.entitlements
}

deny_reasons contains "agent identity not verified" if {
	not input.agent.identity_verified == true
}

deny_reasons contains "unknown tool" if {
	not tool_meta
}

deny_reasons contains "tool metadata incomplete" if {
	tool_meta
	not tool_meta_valid
}

deny_reasons contains "tool or action not granted to agent" if {
	not tool_granted
}

deny_reasons contains "user lacks required entitlement" if {
	required := tool_meta.required_entitlement
	not user_has_entitlement(required)
}

deny_reasons contains "high-impact action requires approval" if {
	tool_meta.impact == "high"
	not input.request.approval.granted == true
}

# Decision record for audit logging (AAC-AU-01). The shape is defined by
# schemas/decision-record.schema.json. It deliberately omits the user's
# entitlement list and any request payload: the record says what was decided
# and why, not what the user may do elsewhere.
default approval_granted := false

approval_granted if input.request.approval.granted == true

default logged_impact := null

logged_impact := tool_meta.impact if tool_meta.impact in valid_impacts

decision := {
	"schema_version": "0.2.0",
	"allow": allow,
	"reasons": deny_reasons,
	"agent": object.get(input, ["agent", "id"], null),
	"user": object.get(input, ["user", "id"], null),
	"server": object.get(input, ["request", "server"], null),
	"tool": object.get(input, ["request", "tool"], null),
	"action": object.get(input, ["request", "action"], null),
	"request_id": object.get(input, ["request", "id"], null),
	"impact": logged_impact,
	"approval_granted": approval_granted,
	"approver": object.get(input, ["request", "approval", "approver"], null),
}
