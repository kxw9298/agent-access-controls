package agentaccess.terraform_plan_test

import data.agentaccess.terraform_plan

policy := {
	"allowed_resource_types": ["google_storage_bucket", "google_storage_bucket_iam_member", "google_pubsub_topic"],
	"protected_address_prefixes": ["google_storage_bucket.audit_logs"],
	"high_risk_resource_types": ["google_storage_bucket_iam_member"],
}

rc(address, type, actions) := {"address": address, "type": type, "change": {"actions": actions}}

plan(resource_changes) := {"format_version": "1.2", "resource_changes": resource_changes}

create_topic := plan([rc("google_pubsub_topic.events", "google_pubsub_topic", ["create"])])

update_bucket := plan([rc("google_storage_bucket.reports", "google_storage_bucket", ["update"])])

delete_bucket := plan([rc("google_storage_bucket.reports", "google_storage_bucket", ["delete"])])

replace_bucket := plan([rc("google_storage_bucket.reports", "google_storage_bucket", ["delete", "create"])])

delete_protected := plan([rc("google_storage_bucket.audit_logs", "google_storage_bucket", ["delete"])])

replace_protected := plan([rc("google_storage_bucket.audit_logs", "google_storage_bucket", ["create", "delete"])])

update_protected := plan([rc("google_storage_bucket.audit_logs", "google_storage_bucket", ["update"])])

grant_iam := plan([rc("google_storage_bucket_iam_member.reader", "google_storage_bucket_iam_member", ["create"])])

out_of_scope := plan([rc("google_project_iam_member.owner", "google_project_iam_member", ["create"])])

unchanged_out_of_scope := plan([
	rc("google_project_iam_member.owner", "google_project_iam_member", ["no-op"]),
	rc("data.google_project.this", "google_project", ["read"]),
	rc("google_pubsub_topic.events", "google_pubsub_topic", ["create"]),
])

test_allows_low_risk_create_without_approval if {
	terraform_plan.allow with input as create_topic with data.change_policy as policy
	not terraform_plan.requires_approval with input as create_topic with data.change_policy as policy
}

test_allows_update_without_approval if {
	terraform_plan.allow with input as update_bucket with data.change_policy as policy
	not terraform_plan.requires_approval with input as update_bucket with data.change_policy as policy
}

test_delete_requires_approval if {
	terraform_plan.allow with input as delete_bucket with data.change_policy as policy
	terraform_plan.requires_approval with input as delete_bucket with data.change_policy as policy
}

test_replace_requires_approval if {
	terraform_plan.allow with input as replace_bucket with data.change_policy as policy
	terraform_plan.requires_approval with input as replace_bucket with data.change_policy as policy
}

test_denies_delete_of_protected_resource if {
	not terraform_plan.allow with input as delete_protected with data.change_policy as policy
	"protected resource may not be deleted or replaced: google_storage_bucket.audit_logs" in terraform_plan.deny_reasons with input as delete_protected with data.change_policy as policy
}

test_denies_replace_of_protected_resource if {
	not terraform_plan.allow with input as replace_protected with data.change_policy as policy
}

test_allows_update_of_protected_resource if {
	terraform_plan.allow with input as update_protected with data.change_policy as policy
}

test_high_risk_type_requires_approval if {
	terraform_plan.allow with input as grant_iam with data.change_policy as policy
	terraform_plan.requires_approval with input as grant_iam with data.change_policy as policy
}

test_denies_out_of_scope_type if {
	not terraform_plan.allow with input as out_of_scope with data.change_policy as policy
	"resource type out of scope: google_project_iam_member (google_project_iam_member.owner)" in terraform_plan.deny_reasons with input as out_of_scope with data.change_policy as policy
}

test_ignores_unchanged_resources_and_reads if {
	terraform_plan.allow with input as unchanged_out_of_scope with data.change_policy as policy
}

test_denies_unsupported_format if {
	bad := {"format_version": "2.0", "resource_changes": []}
	not terraform_plan.allow with input as bad with data.change_policy as policy
	"plan format not supported" in terraform_plan.deny_reasons with input as bad with data.change_policy as policy
}

test_denies_plan_without_resource_changes if {
	bad := {"format_version": "1.2"}
	not terraform_plan.allow with input as bad with data.change_policy as policy
}

test_denies_when_policy_data_missing if {
	not terraform_plan.allow with input as create_topic
	"change policy data is missing" in terraform_plan.deny_reasons with input as create_topic
}

test_denies_when_allowed_types_missing if {
	partial := {"protected_address_prefixes": [], "high_risk_resource_types": []}
	not terraform_plan.allow with input as create_topic with data.change_policy as partial
}

test_empty_plan_is_allowed if {
	terraform_plan.allow with input as plan([]) with data.change_policy as policy
	not terraform_plan.requires_approval with input as plan([]) with data.change_policy as policy
}

test_decision_and_summary if {
	mixed := plan([
		rc("google_pubsub_topic.events", "google_pubsub_topic", ["create"]),
		rc("google_storage_bucket.reports", "google_storage_bucket", ["delete", "create"]),
		rc("google_storage_bucket.tmp", "google_storage_bucket", ["delete"]),
		rc("google_storage_bucket.site", "google_storage_bucket", ["update"]),
	])
	d := terraform_plan.decision with input as mixed with data.change_policy as policy
	d.allow == true
	d.requires_approval == true
	d.summary == {"create": 1, "update": 1, "delete": 1, "replace": 1}
	count(d.approval_reasons) == 2
}
