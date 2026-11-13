# Evaluating this project

This page says what the demonstrations show, what they do not, and how to run and challenge them. It is written for someone deciding whether the approach holds up, not for someone looking for a finished product.

## Run it

Needs Docker only. No cloud account, no credentials, no network at run time.

```sh
scripts/run_in_container.sh
```

Without Docker, install Terraform 1.4 or later, [OPA](https://www.openpolicyagent.org/docs/latest/#running-opa) v1.x, `jq` and Python 3 with `jsonschema`, then from the repository root:

```sh
scripts/run_evaluation.sh
python scripts/validate_results.py
```

CI runs this on Linux and macOS, runs the container with networking disabled, validates the results file, checks that the comparison table below matches it, and publishes the results as a build artifact.

## What is compared

Three configurations run against the same seven scenarios in [`evaluation/scenarios.json`](../evaluation/scenarios.json), on the same Terraform example.

| Configuration | Script | Kind |
| --- | --- | --- |
| No-binding baseline | `scripts/demo_baseline_no_binding.sh` | Model: approval recorded against a file name; the executor applies whatever file it finds. |
| Hardened baseline | `scripts/demo_hardened_baseline.sh` | Model: a saved plan per run that cannot be overwritten, a protected environment with required reviewers and self-review prevented, apply only from the apply job, and a new approval for a new run. |
| Approval binding | `scripts/demo_approval_binding.sh` | This project's policy and executor check, run locally. |

A model is a local stand-in for a design. It does not test any product. The trust assumptions of each configuration are listed in `results.json` and summarized under "How to read the comparison".

## Results

<!-- comparison:start -->
| Scenario | No-binding baseline (model) | Hardened baseline (model) | Approval binding (this project) |
| --- | --- | --- | --- |
| approved plan | Applied (benign case) | Applied (benign case) | Applied (benign case) |
| substituted plan | **Not held** | Held | Held |
| re-plan after approval | **Not held** | Held | Held |
| different agent | **Not held** | Unsupported | Held |
| expired approval | **Not held** | Unsupported | Held |
| self-approval | **Not held** | Held | Held |
| no approval | Held | Held | Held |
<!-- comparison:end -->

"Held" means the unauthorized change was not applied, judged from the Terraform state and not from a policy decision alone. "Unsupported" means the configuration has no mechanism for the scenario. It is a stated property, not a pass and not a failure.

## How to read the comparison

- **Where both support a scenario, the hardened model and approval binding block the same cases.** Substitution, re-planning, self-approval and a missing approval are blocked by both. On those scenarios the result is parity.
- **The hardened model's "Held" results follow from how it is defined.** They show what that design does if it works as assumed. They are not evidence that any real workflow works that way. In particular, the substitution result assumes the saved plan cannot be overwritten, or deleted and re-uploaded, by the attacker. Whether a real workflow gives that guarantee has not been tested.
- **The differences are agent binding and expiry.** The hardened model records no agent identity and no approval expiry, so it reports those scenarios as unsupported. Whether the hosted features offer something equivalent is unverified.
- **Approval binding also produces a digest record.** The comparison does not measure how useful that is as an audit record.
- **Nothing here measures integration effort, auditability or operating cost.** Claims about those need separate measurements and are not made.
- **The weak baseline is deliberately weak.** Its "Not held" results show what the other designs are improving on. They are not a claim about any product.

## Results file

`scripts/run_evaluation.sh` merges the per-case records into `results/results.json` (schema: [`schemas/evaluation-results.schema.json`](../schemas/evaluation-results.schema.json)). For each case it records the expected and observed outcome, denial reasons, and the Terraform state before and after; for each configuration, its kind and trust assumptions. Whether a case matched its expectation and whether protection held are separate fields. A scenario that was neither executed nor reported unsupported is `not_executed`. `scripts/validate_results.py` fixes the expected result for every configuration and scenario, so an error, a missing case, an unexpected "unsupported", or a control that fails cannot read as a pass. [`REVIEWER_QUICKSTART.md`](REVIEWER_QUICKSTART.md) explains how to read the file.

## What the evaluation does not show

- **No real product is tested.** The baselines are models. A comparison against specific tools and settings, run for real, has not been done, and no claim is made about what they do.
- **The substitution is staged by the scripts.** They show that a check works when a substitution happens. They do not show how often an AI agent can cause one in practice.
- **The approved path on GitHub is not yet exercised end to end** and is reported as pending, not as passed. The reference pipeline's refusal on pull requests runs in CI. The path where a second reviewer approves a run and the apply job proceeds needs a manual run with a second person; it is tracked in [#11](https://github.com/kxw9298/agent-access-controls/issues/11).
- **One enforcement point.** Anything else that can run `terraform apply` with the same credentials bypasses the check. See the limits in [approval-binding.md](approval-binding.md).
- **Correctness of the plan.** A matching digest shows the applied plan is the approved one. It does not show the plan is safe.

## How to challenge it

Open an issue describing a way to get an unapproved change applied while a check passes, a modeled assumption that is wrong, or a way the check refuses a legitimate change. A reproduction that runs against the scripts is the most useful form. See [CONTRIBUTING.md](../CONTRIBUTING.md) and [SECURITY.md](../SECURITY.md) for where to send what.
