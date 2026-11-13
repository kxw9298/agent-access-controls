# Changelog

All notable changes to this project are documented here.

## [Unreleased]

### Added

- `results.json` output: `scripts/run_evaluation.sh` runs the baseline and the demonstration and records, for each case, the expected and observed outcome, denial reasons, and the Terraform state before and after. Matching expectations and holding protection are separate fields, and a case that did not run is reported as `not_executed`. Schema in `schemas/evaluation-results.schema.json`, checked by `scripts/validate_results.py`. CI publishes the file as a build artifact.
- `docs/REVIEWER_QUICKSTART.md` and `docs/EXTERNAL_REVIEW_TEMPLATE.md` for people who want to run and review the demonstrations.

### Changed

- The demonstration now acts as the executor: it applies a plan only when the check allows it and records the resulting state, so a refusal is confirmed by the state and not only by the policy decision.
- `scripts/run_in_container.sh` copies the results out of the container and records the tested commit.

## [0.2.0]

The change path, first slice: Terraform saved-plan changes through GitHub Actions. Pre-alpha; not production-ready. The path in which a second reviewer approves a run and the apply job proceeds has not yet been exercised end to end. See `docs/evaluation.md` for what the demonstrations do and do not show.

### Added

- Policy gate for agent-proposed Terraform plans (`policies/terraform_plan`).
- Approval binding for Terraform saved plans (`policies/change_approval`): approval tied to the plan's SHA-256 digest, the agent, the requesting user, an expiry, and an approver who differs from the requester.
- Workload identity from GitHub Actions OIDC tokens (`policies/workload_identity`).
- Reference GitHub Actions pipeline (`.github/workflows/change-pipeline.yml`) and its helper scripts.
- `scripts/demo_approval_binding.sh`, a six-case demonstration, and `scripts/demo_baseline_no_binding.sh`, the same swap with the control removed.
- `scripts/run_in_container.sh` and `containers/demo/Dockerfile` to run both without installing Terraform or OPA. CI runs the container with networking disabled, and runs the scripts on Linux and macOS.
- `docs/evaluation.md`: what the demonstrations show and do not show.
- Design for approval binding on agent-proposed infrastructure changes (`docs/approval-binding.md`).
- Planned controls AAC-CH-01 to AAC-CH-04 and AAC-AU-02 in the catalog, and threats T9 to T12 in the threat model.
- Decision-record schema (`schemas/decision-record.schema.json`) for control AAC-AU-01 on the tool-call path, with valid and invalid examples in `examples/audit/`.
- `scripts/validate_decision_log.py`, which validates records, checks that the schema's denial reasons match the policy, and runs in CI against real policy output.
- Decision records now include `schema_version`, `request_id`, `impact`, `approval_granted`, and `approver`.
- Example input for an approved high-impact request.

### Changed

- Roadmap: v0.2 to v0.5 now cover the change path (Terraform plan policy and approval binding), container image admission with signed attestations, an attack harness, and an external review kit. Gateway deployment examples move to a later stage.
- The tool-authorization policy denies tools whose metadata is incomplete (`impact` not `low` or `high`, or no `required_entitlement`) with the reason `tool metadata incomplete`. Previously such a tool skipped the approval or entitlement check.

## [0.1.0] - 2026-10-09

### Added

- Control catalog with eight controls covering gateway mediation, agent identity, tool-level authorization, user entitlements, approvals, audit, content filtering, and rate limits.
- Tool-authorization policy (OPA/Rego) implementing per-agent grants, user entitlement checks, and approval for high-impact actions, with unit tests and example data.
- Reference architecture and draft threat model mapped to the OWASP Top 10 for LLM Applications 2025.
- CI for policy tests and catalog validation.

### Changed

- CI uses current major versions of the checkout, Python, and OPA setup actions.

[Unreleased]: https://github.com/kxw9298/agent-access-controls/compare/v0.2.0...HEAD
[0.2.0]: https://github.com/kxw9298/agent-access-controls/compare/v0.1.0...v0.2.0
[0.1.0]: https://github.com/kxw9298/agent-access-controls/releases/tag/v0.1.0
