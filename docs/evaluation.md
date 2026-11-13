# Evaluating this project

This page says what the demonstrations show, what they do not, and how to run and challenge them. It is written for someone deciding whether the approach holds up, not for someone looking for a finished product.

## Run it

Needs Docker only. No cloud account, no credentials, no network at run time.

```sh
scripts/run_in_container.sh
```

Without Docker, install Terraform 1.4 or later, [OPA](https://www.openpolicyagent.org/docs/latest/#running-opa) v1.x and `jq`, then run the two scripts from the repository root:

```sh
scripts/demo_baseline_no_binding.sh
scripts/demo_approval_binding.sh
```

CI runs both on Linux and macOS, and runs the container with networking disabled.

## What the demonstrations show

| Script | Shows |
| --- | --- |
| `scripts/demo_baseline_no_binding.sh` | A plan is approved, the plan file is then replaced, and an executor that checks only that an approval exists for the file name applies the replacement. |
| `scripts/demo_approval_binding.sh` | With the approval bound to the plan's SHA-256 digest, the same replacement is refused, along with a different agent, an expired approval, self-approval, and a missing approval. |

## What they do not show

- **The baseline is a model.** It represents a pipeline where approval is recorded against a name or identifier and the executor does not hash the file it applies. It is not a measurement of any named product. Some tools tie approval to a specific run or lock the plan, and they may refuse the swap. A comparison against specific tools has not been written, and no claim is made here about what they do.
- **The substitution is staged by the script.** The scripts show that the check works when a substitution happens. They do not show how often an AI agent can cause one in practice.
- **The approved path on GitHub is not yet exercised end to end.** The reference pipeline's refusal on pull requests runs in CI. The path where a second reviewer approves a run and the apply job proceeds needs a manual run with two accounts and has not been done.
- **One enforcement point.** Anything else that can run `terraform apply` with the same credentials bypasses the check. See the limits in [approval-binding.md](approval-binding.md).
- **Correctness of the plan.** A matching digest shows the applied plan is the approved one. It does not show the plan is safe.

## How to challenge it

Open an issue describing a way to get an unapproved change applied while the check passes, or a way the check refuses a legitimate change. A reproduction that runs against the scripts is the most useful form. See [CONTRIBUTING.md](../CONTRIBUTING.md) and [SECURITY.md](../SECURITY.md) for where to send what.
