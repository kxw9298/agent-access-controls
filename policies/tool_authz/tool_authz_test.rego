package agentaccess.tool_authz_test

import data.agentaccess.tool_authz

grants := {"invoice-assistant": [
	{"server": "erp-mcp", "tool": "get_invoice", "actions": ["read"]},
	{"server": "erp-mcp", "tool": "issue_refund", "actions": ["write"]},
]}

tools := {"erp-mcp": {
	"get_invoice": {"impact": "low", "required_entitlement": "finance:read"},
	"issue_refund": {"impact": "high", "required_entitlement": "finance:refund"},
	"list_vendors": {"impact": "low", "required_entitlement": "finance:read"},
}}

read_invoice := {
	"agent": {"id": "invoice-assistant", "identity_verified": true},
	"user": {"id": "u-1001", "entitlements": ["finance:read"]},
	"request": {"server": "erp-mcp", "tool": "get_invoice", "action": "read"},
}

unverified_agent := {
	"agent": {"id": "invoice-assistant", "identity_verified": false},
	"user": {"id": "u-1001", "entitlements": ["finance:read"]},
	"request": {"server": "erp-mcp", "tool": "get_invoice", "action": "read"},
}

tool_not_granted := {
	"agent": {"id": "invoice-assistant", "identity_verified": true},
	"user": {"id": "u-1001", "entitlements": ["finance:read"]},
	"request": {"server": "erp-mcp", "tool": "list_vendors", "action": "read"},
}

action_not_granted := {
	"agent": {"id": "invoice-assistant", "identity_verified": true},
	"user": {"id": "u-1001", "entitlements": ["finance:read"]},
	"request": {"server": "erp-mcp", "tool": "get_invoice", "action": "write"},
}

user_without_entitlement := {
	"agent": {"id": "invoice-assistant", "identity_verified": true},
	"user": {"id": "u-2002", "entitlements": []},
	"request": {"server": "erp-mcp", "tool": "get_invoice", "action": "read"},
}

refund_without_approval := {
	"agent": {"id": "invoice-assistant", "identity_verified": true},
	"user": {"id": "u-3003", "entitlements": ["finance:read", "finance:refund"]},
	"request": {"server": "erp-mcp", "tool": "issue_refund", "action": "write"},
}

refund_with_approval := {
	"agent": {"id": "invoice-assistant", "identity_verified": true},
	"user": {"id": "u-3003", "entitlements": ["finance:read", "finance:refund"]},
	"request": {
		"server": "erp-mcp",
		"tool": "issue_refund",
		"action": "write",
		"approval": {"granted": true, "approver": "u-4004"},
	},
}

unknown_tool := {
	"agent": {"id": "invoice-assistant", "identity_verified": true},
	"user": {"id": "u-1001", "entitlements": ["finance:read"]},
	"request": {"server": "crm-mcp", "tool": "export_all_contacts", "action": "read"},
}

test_allows_granted_low_impact_read if {
	tool_authz.allow with input as read_invoice with data.grants as grants with data.tools as tools
}

test_denies_unverified_agent if {
	not tool_authz.allow with input as unverified_agent with data.grants as grants with data.tools as tools
	"agent identity not verified" in tool_authz.deny_reasons with input as unverified_agent with data.grants as grants with data.tools as tools
}

test_denies_tool_not_granted if {
	not tool_authz.allow with input as tool_not_granted with data.grants as grants with data.tools as tools
	"tool or action not granted to agent" in tool_authz.deny_reasons with input as tool_not_granted with data.grants as grants with data.tools as tools
}

test_denies_action_not_granted if {
	not tool_authz.allow with input as action_not_granted with data.grants as grants with data.tools as tools
	"tool or action not granted to agent" in tool_authz.deny_reasons with input as action_not_granted with data.grants as grants with data.tools as tools
}

test_denies_user_without_entitlement if {
	not tool_authz.allow with input as user_without_entitlement with data.grants as grants with data.tools as tools
	"user lacks required entitlement" in tool_authz.deny_reasons with input as user_without_entitlement with data.grants as grants with data.tools as tools
}

test_denies_high_impact_without_approval if {
	not tool_authz.allow with input as refund_without_approval with data.grants as grants with data.tools as tools
	"high-impact action requires approval" in tool_authz.deny_reasons with input as refund_without_approval with data.grants as grants with data.tools as tools
}

test_allows_high_impact_with_approval if {
	tool_authz.allow with input as refund_with_approval with data.grants as grants with data.tools as tools
}

test_denies_unknown_tool if {
	not tool_authz.allow with input as unknown_tool with data.grants as grants with data.tools as tools
	"unknown tool" in tool_authz.deny_reasons with input as unknown_tool with data.grants as grants with data.tools as tools
}

test_decision_records_denial if {
	d := tool_authz.decision with input as refund_without_approval with data.grants as grants with data.tools as tools
	d.allow == false
	d.agent == "invoice-assistant"
	d.user == "u-3003"
	d.tool == "issue_refund"
	"high-impact action requires approval" in d.reasons
}
