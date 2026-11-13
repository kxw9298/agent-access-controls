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

The container runs with networking disabled. Results are written to `results/results.json`. The command exits with status 0 only if every scenario was executed or reported unsupported, and every executed case behaved as expected.

Without Docker, install Terraform 1.4 or later, [OPA](https://www.openpolicyagent.org/docs/latest/#running-opa) v1.x, `jq` and Python 3 with `jsonschema`, then run `scripts/run_evaluation.sh` and `python scripts/validate_results.py`.

## The scenarios

Three configurations run against the same seven scenarios, listed in [`evaluation/scenarios.json`](../evaluation/scenarios.json). The two baselines are models, not tests of any product.

- **No-binding baseline:** approval is recorded against a file name, and the executor applies whatever file it finds. Deliberately weak.
- **Hardened baseline:** a saved plan per run that cannot be overwritten, run-keyed approval with self-review prevented, apply only from the apply job, and a new approval for a new run.
- **Approval binding:** this project. Approval is bound to the plan digest, the agent, the requester and an expiry.

The comparison table, generated from `results.json`, is in [evaluation.md](evaluation.md). What to expect:

| Scenario | No-binding baseline | Hardened baseline | Approval binding |
| --- | --- | --- | --- |
| approved plan | Applied | Applied | Applied |
| substituted plan | Not held | Held | Held |
| re-plan after approval | Not held | Held | Held |
| different agent | Not held | Unsupported | Held |
| expired approval | Not held | Unsupported | Held |
| self-approval | Not held | Held | Held |
| no approval | Held | Held | Held |

"Not held" for the no-binding baseline is the expected result for a weak design, and it does not fail the run. "Unsupported" means the configuration has no mechanism for the scenario.

## Reading results.json

Each case records the expected and observed outcome, the denial reasons, and the Terraform state (`release_before`, `release_after`). Two fields are kept apart on purpose:

- `matched_expectation`: the case behaved as the configuration is expected to behave. The weak baseline matches its expectation when it applies the substituted plan.
- `protection`: whether an unauthorized change was actually prevented. It is `held` only if nothing was applied and the state did not change. It is judged from the Terraform state, not from the policy decision alone.

A scenario with no mechanism in a configuration is `unsupported`, with a reason. A scenario that did not run is `not_executed`. A run with any scenario missing, or any mismatch, fails; an error is never counted as protection. Each configuration also lists its trust assumptions. The schema is [`schemas/evaluation-results.schema.json`](../schemas/evaluation-results.schema.json).

## The image path (optional second interface)

If you also want to review the container-image path, see [image-admission.md](image-admission.md). Stage 1 needs only OPA and `jq`; stage 2 needs a Kubernetes 1.30+ cluster such as kind. It is not part of `results.json` and does not run in the container.

## Not yet covered

- **The hosted approved-apply path.** The reference GitHub Actions pipeline refuses on pull requests in CI. The path where a second reviewer approves a workflow run and the apply job proceeds has not been run end to end. Treat it as pending; it is tracked in [#11](https://github.com/kxw9298/agent-access-controls/issues/11). This page will link the run and its evidence when it exists.
- **Real products and settings.** The hardened baseline is a model of one design. It has not been run against real GitHub environment protection or any other tool, so do not read its results as what those do.
- **Image signing and attestation.** The image path checks a digest only. It does not verify who built the image.
- **Anything outside the Terraform and GitHub Actions path and the image path described above.**

## Report what you find

- A way to get an unapproved change applied while the check passes, a false refusal, or an unclear instruction: open an issue, ideally with a reproduction against these scripts.
- A security vulnerability: do not open a public issue. See [SECURITY.md](../SECURITY.md).
- Your own findings: use [EXTERNAL_REVIEW_TEMPLATE.md](EXTERNAL_REVIEW_TEMPLATE.md). Write them yourself, say which cases you ran yourself, and disclose any relationship with the maintainer.
