# agent-access-controls

Executable security controls for governing how AI agents access enterprise tools, MCP servers, APIs, and data.

> **Status: pre-alpha.** The control catalog and the first authorization policy are in progress. Not production-ready; interfaces will change.

## The problem

AI agents now act on enterprise systems. They call internal APIs, invoke tools through MCP servers, and read sensitive data on behalf of users. Many of the serious risks sit in that access path rather than in the model itself:

- an agent is allowed more tools or actions than its task needs;
- an agent retrieves data the user it acts for is not entitled to see;
- a high-impact action (a payment, a deletion) runs without anyone approving it;
- nobody can reconstruct afterward what an agent did and why it was allowed.

The [OWASP Top 10 for LLM Applications (2025)](https://genai.owasp.org/llm-top-10/) names several of these, including LLM06 Excessive Agency and LLM02 Sensitive Information Disclosure. Guidance on *what* to control exists. A tested, deployable implementation of those controls is harder to find.

## What this project provides

| Part | Location | Status |
| --- | --- | --- |
| Control catalog: objective, enforcement point, and risks addressed for each control | [`controls/`](controls/) | In progress |
| Policy-as-code: authorization policies in Rego for [Open Policy Agent](https://www.openpolicyagent.org/), with unit tests | [`policies/`](policies/) | First policy |
| Reference architecture and threat model | [`docs/`](docs/) | Draft |
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

## Roadmap

| Version | Scope |
| --- | --- |
| v0.1 | Control catalog, tool-authorization policy with tests, threat model, CI |
| v0.2 | Audit-log schema and decision logging; content-filter integration points |
| v0.3 | Deployment example: open-source gateway on Kubernetes, with workload identity |
| v0.4 | Deployment example: managed cloud API gateway |
| v1.0 | Control baseline mapped to OWASP and the CSA AI Controls Matrix; end-to-end tests; adopter documentation |

## Related work

This project builds on existing gateways and guidance rather than replacing them:

- [OWASP Top 10 for LLM Applications](https://genai.owasp.org/llm-top-10/)
- [CSA AI Controls Matrix](https://cloudsecurityalliance.org/artifacts/ai-controls-matrix/)
- [Open Policy Agent](https://www.openpolicyagent.org/)
- [agentgateway](https://agentgateway.dev/)
- [Envoy AI Gateway](https://aigateway.envoyproxy.io/)

## Contributing, security, license

- Contributions: see [CONTRIBUTING.md](CONTRIBUTING.md).
- Reporting vulnerabilities: see [SECURITY.md](SECURITY.md).
- License: [Apache License 2.0](LICENSE).
