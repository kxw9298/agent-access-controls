# Changelog

All notable changes to this project are documented here.

## [Unreleased]

### Added

- Design for approval binding on agent-proposed infrastructure changes (`docs/approval-binding.md`).
- Planned controls AAC-CH-01 to AAC-CH-04 and AAC-AU-02 in the catalog, and threats T9 to T12 in the threat model.
- Decision-record schema (`schemas/decision-record.schema.json`) for control AAC-AU-01 on the tool-call path, with valid and invalid examples in `examples/audit/`.
- `scripts/validate_decision_log.py`, which validates records, checks that the schema's denial reasons match the policy, and runs in CI against real policy output.
- Decision records now include `schema_version`, `request_id`, `impact`, `approval_granted`, and `approver`.
- Example input for an approved high-impact request.

### Changed

- Roadmap: v0.2 to v0.5 now cover the change path (Terraform plan policy, approval bound to the plan digest, Kubernetes admission demonstration, signed records, incident-based tests). Gateway deployment examples move to a later stage.
- The tool-authorization policy denies tools whose metadata is incomplete (`impact` not `low` or `high`, or no `required_entitlement`) with the reason `tool metadata incomplete`. Previously such a tool skipped the approval or entitlement check.

## [0.1.0] - 2026-10-09

### Added

- Control catalog with eight controls covering gateway mediation, agent identity, tool-level authorization, user entitlements, approvals, audit, content filtering, and rate limits.
- Tool-authorization policy (OPA/Rego) implementing per-agent grants, user entitlement checks, and approval for high-impact actions, with unit tests and example data.
- Reference architecture and draft threat model mapped to the OWASP Top 10 for LLM Applications 2025.
- CI for policy tests and catalog validation.

### Changed

- CI uses current major versions of the checkout, Python, and OPA setup actions.

[Unreleased]: https://github.com/kxw9298/agent-access-controls/compare/v0.1.0...HEAD
[0.1.0]: https://github.com/kxw9298/agent-access-controls/releases/tag/v0.1.0
