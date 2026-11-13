# Reviewer quickstart

This is the shortest path to running the demonstrations yourself and checking what they do and do not show. It takes a few minutes and needs no cloud account, credentials or network at run time.

## What you are reviewing

A control for one case: an AI agent proposes a Terraform change, a person approves it, and a pipeline applies it. The control binds the approval to the SHA-256 digest of the saved plan, the agent, the requesting user and an expiry, and refuses an apply that does not match. The design and its limits are in [approval-binding.md](approval-binding.md). What the demonstrations do not show is in [evaluation.md](evaluation.md); please read that page too.

## Prerequisites

- Docker (Linux, or Docker Desktop on macOS) and Git.
- Nothing else. Terraform and OPA run inside the container.

## Run it

Check out the release tag or commit you intend to review, and note which one. Then, from the repository root:

```sh
scripts/run_in_container.sh
```

The container runs with networking disabled. Results are written to `results/results.json`. The command exits with status 0 only if every case ran and behaved as expected.

Without Docker, install Terraform 1.4 or later, [OPA](https://www.openpolicyagent.org/docs/latest/#running-opa) v1.x, `jq` and Python 3 with `jsonschema`, then run `scripts/run_evaluation.sh` and `python scripts/validate_results.py`.

## The cases

Baseline: approval is recorded against a file name, and the executor applies whatever file it finds. It models one weak design and is not a measurement of any named product.

| Case | What happens | Expected outcome | Protection |
| --- | --- | --- | --- |
| approved-plan | The approved plan is applied unchanged | Applied | Not applicable |
| substituted-plan | The plan file is replaced after approval, and the replacement is applied | Applied | **Not held** (expected for this baseline) |

Approval binding: the approval is bound to the plan digest, the agent, the requester and an expiry.

| Case | What happens | Expected outcome | Protection |
| --- | --- | --- | --- |
| approved-plan | The approved plan is applied | Applied | Not applicable |
| substituted-plan | A different plan is made after approval and reuses the approval | Blocked: digest mismatch | Held |
| different-agent | The approved plan is executed by another agent | Blocked: agent mismatch | Held |
| expired-approval | The approved plan is executed after the approval expired | Blocked: expired | Held |
| self-approval | The requester approved their own change | Blocked: self-approval | Held |
| no-approval | No approval is provided | Blocked: approval required | Held |

## Reading results.json

Each case records the expected and observed outcome, the denial reasons, and the Terraform state (`release_before`, `release_after`). Two fields are kept apart on purpose:

- `matched_expectation`: the case behaved as the configuration is expected to behave. The weak baseline matches its expectation when it applies the substituted plan.
- `protection`: whether an unauthorized change was actually prevented. It is `held` only if nothing was applied and the state did not change. It is judged from the Terraform state, not from the policy decision alone.

A case that did not run is reported as `not_executed`. A run with any case missing, or any mismatch, fails; an error is never counted as protection. The schema is [`schemas/evaluation-results.schema.json`](../schemas/evaluation-results.schema.json).

## Not yet covered

- **The hosted approved-apply path.** The reference GitHub Actions pipeline refuses on pull requests in CI. The path where a second reviewer approves a workflow run and the apply job proceeds has not been run end to end. Treat it as pending. This page will link the run and its evidence when it exists.
- **Comparison with hardened existing workflows.** Not yet done. Do not read the baseline as representing them.
- **Anything outside the Terraform and GitHub Actions path.**

## Report what you find

- A way to get an unapproved change applied while the check passes, a false refusal, or an unclear instruction: open an issue, ideally with a reproduction against these scripts.
- A security vulnerability: do not open a public issue. See [SECURITY.md](../SECURITY.md).
- Your own findings: use [EXTERNAL_REVIEW_TEMPLATE.md](EXTERNAL_REVIEW_TEMPLATE.md). Write them yourself, say which cases you ran yourself, and disclose any relationship with the maintainer.
