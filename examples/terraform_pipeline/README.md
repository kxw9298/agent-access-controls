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

## Reference pipeline

[`.github/workflows/change-pipeline.yml`](../../.github/workflows/change-pipeline.yml) runs the same checks as a two-job GitHub Actions workflow, with identities and the approval taken from GitHub instead of from a script:

| Value | Source |
| --- | --- |
| Agent | `workflow_ref` claim of the job's OIDC token, verified by `policies/workload_identity` |
| Requesting user | `actor` claim of the same token |
| Plan digest | Computed in the plan job, shown in the run summary for the reviewer, and recomputed in the apply job from the downloaded plan file |
| Approver | GitHub's review history for the `change-approval` environment in this run |
| Expiry | Plan time plus `PLAN_MAX_AGE_HOURS` |

To use it:

1. In the repository settings, create an environment named `change-approval` and add required reviewers.
2. Run the workflow from the Actions tab. The plan job publishes the plan digest in its summary.
3. A reviewer approves the deployment to `change-approval`. The apply job then runs the execution check and applies the plan only if it passes.

The approver must be someone other than the person who started the run. If the same person starts and approves it, the apply is refused. A repository with one maintainer therefore needs a second reviewer to see an approved apply.

On pull requests the workflow runs without the environment. No approval can exist, so the apply job checks that the plan is refused for exactly that reason and does not apply it.

## What this does and does not show


- `policy-data.json` marks `terraform_data` as high-risk only so that the demo plan needs approval.
- In the demonstration script, the agent, user, and approver values and the approval record are written by the script. The reference pipeline takes them from GitHub.
- In the reference pipeline, the approved digest is the plan job's output within the same workflow run. The reviewer approves a run, and GitHub does not record the digest in the review itself. The binding therefore relies on job outputs and artifacts being fixed once the plan job finishes.
- The reference pipeline's "agent" is the workflow that runs. It does not distinguish an AI agent from any other caller of that workflow.
- The demo configuration has no remote state and changes nothing outside the runner.
- The check is only as strong as the executor. If something else can run `terraform apply` with the same credentials, this control does not stop it.
