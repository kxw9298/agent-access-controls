# agent-access-controls

Open-source guardrails that control what AI agents can change in software and cloud infrastructure. They bind human approval to the exact change that is executed, within a defined enforcement boundary, and produce verifiable records of authorized changes.

Version 1 covers Terraform saved-plan changes through GitHub Actions. Control of agent tool, API, and data access (the v0.1 tool-authorization policy) is groundwork for a later stage and is not part of the v1 guarantee.

> **Status: pre-alpha (v0.1.0).** The control catalog and the first authorization policy are released for review. Not production-ready; interfaces will change.

## The problem

AI agents now act on enterprise systems. They call internal APIs, invoke tools through MCP servers, and read sensitive data on behalf of users. Many of the serious risks sit in that access path rather than in the model itself:

- an agent is allowed more tools or actions than its task needs;
- an agent retrieves data the user it acts for is not entitled to see;
- a high-impact action (a payment, a deletion) runs without anyone approving it;
- a person approves one infrastructure change, and the change that actually runs is a different one;
- nobody can reconstruct afterward what an agent did and why it was allowed.

The [OWASP Top 10 for LLM Applications (2025)](https://genai.owasp.org/llm-top-10/) names several of these, including LLM06 Excessive Agency and LLM02 Sensitive Information Disclosure. Guidance on *what* to control exists. A tested, deployable implementation of those controls is harder to find.

## What this project provides

| Part | Location | Status |
| --- | --- | --- |
| Control catalog: objective, enforcement point, and risks addressed for each control | [`controls/`](controls/) | In progress |
| Policy-as-code: authorization policies in Rego for [Open Policy Agent](https://www.openpolicyagent.org/), with unit tests | [`policies/`](policies/) | First policy |
| Decision-record schema for tool-call decisions | [`schemas/`](schemas/) | On `main`, not yet released |
| Reference architecture and threat model | [`docs/`](docs/) | Draft |
| Approval binding for agent-proposed infrastructure changes: design in [`docs/approval-binding.md`](docs/approval-binding.md) | `policies/`, `examples/` | Planned for v0.2 |
| Deployment examples: Infrastructure-as-Code for an open-source gateway on Kubernetes and for a managed cloud API gateway | `deploy/` | Planned |

## Design principles

1. **Gateway-mediated access.** Every agent call to a tool or API passes through a gateway that enforces policy. Agents have no direct path to backends.
2. **Deny by default.** An agent gets only the tools and actions its task requires.
3. **Separate identities.** Each agent has its own workload identity. When it acts for a user, it is limited to that user's entitlements.
4. **Approval for high-impact actions.** Writes, payments, and deletions need an explicit, recorded approval.
5. **Every decision is logged** with enough context to reconstruct what happened.
6. **Controls are code:** versioned, reviewed, and tested.

## Try the policy

Requires [OPA](https://www.openpolicyagent.org/docs/latest/#running-opa) v1.x.

```sh
# Run the policy unit tests
opa test policies/ -v

# Evaluate one request against the example grants
opa eval \
  -d policies/tool_authz/tool_authz.rego \
  -d examples/tool_authz/data.json \
  -i examples/tool_authz/input-refund-without-approval.json \
  "data.agentaccess.tool_authz.decision"
```

## Two enforcement paths

An agent can change things in two ways, and each needs its own enforcement point:

- **Tool-call path.** The agent calls a tool or API through a gateway. The policy in [`policies/tool_authz`](policies/tool_authz/) decides each call. This shipped in v0.1.
- **Change path.** The agent proposes an infrastructure change (a Terraform plan) and a pipeline applies it. v0.2 adds controls here: a policy gate on the plan, and human approval bound to the exact plan that is applied.

See [`docs/approval-binding.md`](docs/approval-binding.md) for the change-path design and its limits.

## Decision records (tool-call path)

Every tool-call authorization decision produces a record that follows [`schemas/decision-record.schema.json`](schemas/decision-record.schema.json): outcome, denial reasons, agent, user, tool, action, request ID, impact, and approval. It does not include the user's entitlements or request payload. Examples are in [`examples/audit/`](examples/audit/).

```sh
pip install jsonschema
python scripts/validate_decision_log.py
```

This project defines the record, not the log pipeline. A gateway writes the record to an audit log; OPA's own decision log wraps it with a decision ID and timestamp.

Records of authorized *changes* on the change path are a separate item: signed attestations in v0.4.

## Roadmap

| Version | Scope |
| --- | --- |
| v0.1 | Control catalog, tool-authorization policy with tests, threat model, CI |
| v0.2 | Change path, first slice: policy gate on Terraform plans; human approval bound to the saved-plan digest and to the agent and user identity; a demonstration that a substituted plan is refused |
| v0.3 | The same approval binding at a second interface: a Kubernetes admission demonstration |
| v0.4 | Signed records of authorized changes (in-toto, Sigstore). The decision-record schema for tool-call decisions is already on `main`. |
| v0.5 | Test suite modeled on public incidents, run in one CI system and one local Kubernetes cluster, with published results |
| Later | Gateway deployment examples for the tool-call path (Kubernetes, managed cloud API gateway); approval binding for direct tool calls; mapping to OWASP and the CSA AI Controls Matrix |

Not covered, and not planned for these versions: administrator break-glass access, CI systems other than GitHub Actions, and production hardening.

## Related work

This project builds on existing gateways and guidance rather than replacing them:

- [OWASP Top 10 for LLM Applications](https://genai.owasp.org/llm-top-10/)
- [CSA AI Controls Matrix](https://cloudsecurityalliance.org/artifacts/ai-controls-matrix/)
- [Open Policy Agent](https://www.openpolicyagent.org/)
- [Terraform saved plans](https://developer.hashicorp.com/terraform/cli/commands/plan#out-filename)
- [in-toto attestations](https://github.com/in-toto/attestation) and [Sigstore](https://www.sigstore.dev/)
- [agentgateway](https://agentgateway.dev/)
- [Envoy AI Gateway](https://aigateway.envoyproxy.io/)

## Contributing, security, license

- Contributions: see [CONTRIBUTING.md](CONTRIBUTING.md).
- Reporting vulnerabilities: see [SECURITY.md](SECURITY.md).
- License: [Apache License 2.0](LICENSE).
