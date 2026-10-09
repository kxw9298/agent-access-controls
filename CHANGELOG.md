# Changelog

All notable changes to this project are documented here.

## [Unreleased]

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
