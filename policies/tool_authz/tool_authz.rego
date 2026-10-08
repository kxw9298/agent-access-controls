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
#     "request": {"server": "...", "tool": "...", "action": "...",
#                 "approval": {"granted": true, "approver": "..."}}
#   }
#
# Expected data:
#   data.grants[agent_id] = [{"server": "...", "tool": "...", "actions": ["..."]}]
#   data.tools[server][tool] = {"impact": "low" | "high",
#                               "required_entitlement": "..."}
package agentaccess.tool_authz

default allow := false

allow if count(deny_reasons) == 0

tool_meta := data.tools[input.request.server][input.request.tool]

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

# Decision record for audit logging (AAC-AU-01).
decision := {
	"allow": allow,
	"reasons": deny_reasons,
	"agent": object.get(input, ["agent", "id"], null),
	"user": object.get(input, ["user", "id"], null),
	"server": object.get(input, ["request", "server"], null),
	"tool": object.get(input, ["request", "tool"], null),
	"action": object.get(input, ["request", "action"], null),
}
