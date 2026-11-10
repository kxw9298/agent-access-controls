# Terraform plan policy examples

The two plan files are trimmed, hand-written examples in the shape of `terraform show -json` output. They use generic resource names and are not taken from any real environment.

```sh
# A low-risk create: allowed, no approval needed
opa eval \
  -d policies/terraform_plan/terraform_plan.rego \
  -d examples/terraform_plan/data.json \
  -i examples/terraform_plan/plan-create-topic.json \
  "data.agentaccess.terraform_plan.decision"

# Deletes a protected bucket and adds an IAM grant: denied
opa eval \
  -d policies/terraform_plan/terraform_plan.rego \
  -d examples/terraform_plan/data.json \
  -i examples/terraform_plan/plan-delete-audit-logs.json \
  "data.agentaccess.terraform_plan.decision"
```

To check a real plan:

```sh
terraform plan -out=tfplan
terraform show -json tfplan > plan.json
opa eval -d policies/terraform_plan/terraform_plan.rego -d your-policy-data.json \
  -i plan.json "data.agentaccess.terraform_plan.decision"
```

The policy reads only `format_version` and `resource_changes`. It does not inspect attribute values, so it cannot tell a safe update from a dangerous one on an allowed resource type. Mark such types as high-risk so they need approval.
