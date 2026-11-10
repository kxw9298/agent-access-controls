# Approval-binding demonstration

This shows the change-path controls working together on a real Terraform saved plan:

1. `policies/terraform_plan` checks the plan and marks it as needing approval.
2. An approval is recorded for the SHA-256 digest of the saved plan file.
3. `policies/change_approval` is evaluated before apply, with the digest recomputed from the file about to be applied.

Run it from the repository root. It needs Terraform 1.4 or later, OPA v1.x, `jq`, and `sha256sum`. It needs no cloud account.

```sh
scripts/demo_approval_binding.sh
```

| Case | What happens | Expected |
| --- | --- | --- |
| 1 | The approved plan is checked and applied | Allowed |
| 2 | A new plan is made after approval with a different input, and applied under the same approval | Refused: digest mismatch |
| 3 | The approved plan is executed by a different agent | Refused: agent mismatch |
| 4 | The approved plan is executed after the approval expired | Refused: expired |
| 5 | The approval was given by the requester | Refused: self-approval |
| 6 | No approval is provided | Refused: approval required |

The script exits non-zero if any case does not behave as expected. CI runs it on every pull request.

## What this does and does not show

- `policy-data.json` marks `terraform_data` as high-risk only so that the demo plan needs approval.
- The agent, user, and approver values and the approval record are written by the script. In a real pipeline they have to come from sources the agent cannot write to: a verified workload-identity token for the agent, and the CI system's own approval record for the approver. That wiring is not part of this demonstration.
- The check is only as strong as the executor. If something else can run `terraform apply` with the same credentials, this control does not stop it.
