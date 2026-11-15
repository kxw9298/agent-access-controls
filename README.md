# agent-access-controls

Open-source guardrails that control what AI agents can change in software and cloud infrastructure. They bind human approval to the exact change that is executed, within a defined enforcement boundary, and produce verifiable records of authorized changes.

The scope is Terraform saved-plan changes through GitHub Actions. A second interface, admission of container images by approved digest in a local Kubernetes cluster, is demonstrated (roadmap stage v0.3, first slice). Its approval is a signed record; signing the image itself and verifying it in the cluster are planned. Control of agent tool, API, and data access (the v0.1 tool-authorization policy) is groundwork for a later stage and is not part of the change-path guarantee.

> **Status: pre-alpha.** The latest tagged release is v0.2.0: the change path for Terraform plans on GitHub Actions, a first slice of the container-image path, and a first slice of the attack harness. Not production-ready; interfaces will change. Not yet covered: the approved-apply path on real GitHub, signing of the image itself (the approval record is signed), signing key custody, and LLM-driven attacks in CI. See the roadmap.

## The problem

AI agents now propose and make changes to software and cloud infrastructure: they write Terraform, open pull requests, and name the container images to deploy. A person often approves the change, but the approval and the change that actually runs are not always tied together:

- a person approves one infrastructure change, and a different one is applied, because the agent re-planned or a file was swapped after review;
- an approval given for one agent or one requester is used by another, is given by the requester, or is used after it has gone stale;
- an image is approved by a tag such as `app:latest`, and the tag later points to different content;
- after a change, nobody can show which approval authorized it.

Well-configured pipelines already cover part of this, for example with Terraform saved plans, protected environments and required reviewers. [`docs/evaluation.md`](docs/evaluation.md) compares this project with a model of one such configuration: both block substitution, re-planning and self-approval. What this project adds is approval bound to the agent and the requesting user, with an expiry, and, on the image path, a signed approval record. Whether that is worth the extra mechanism is for reviewers to judge.

Agents that call tools, MCP servers and APIs raise related risks: more tools or actions than the task needs, data the user is not entitled to see, a high-impact action that nobody approved. The [OWASP Top 10 for LLM Applications (2025)](https://genai.owasp.org/llm-top-10/) names several of them, including LLM06 Excessive Agency and LLM02 Sensitive Information Disclosure. The v0.1 tool-authorization policy covers part of that path; it is not part of the change-path guarantee.

## What this project provides

| Part | Location | Status |
| --- | --- | --- |
| Control catalog: objective, enforcement point, risks addressed and status for each control | [`controls/`](controls/) | In progress; status is listed per control |
| Policy-as-code: five policies in Rego for [Open Policy Agent](https://www.openpolicyagent.org/), with unit tests: Terraform plan gate, plan approval, image approval, workload identity, and tool authorization | [`policies/`](policies/) | Released in v0.2.0 |
| Decision-record schema for tool-call decisions | [`schemas/`](schemas/) | Released in v0.2.0 |
| Reference architecture and threat model | [`docs/`](docs/) | Draft |
| Change path: policy gate on Terraform plans, approval bound to the plan digest, workload identity from GitHub Actions OIDC, reference pipeline. Design and limits in [`docs/approval-binding.md`](docs/approval-binding.md) | `policies/`, `examples/`, `scripts/`, `.github/workflows/` | Released in v0.2.0; the approved-apply path on real GitHub is not yet exercised |
| Demonstration, no-control baseline, and container runner | `scripts/`, `containers/` | Released in v0.2.0; see [`docs/evaluation.md`](docs/evaluation.md) |
| Image path: approval of an exact image digest, and Kubernetes admission that refuses any other. The approval is a signed in-toto record; the image itself is not signed. See [`docs/image-admission.md`](docs/image-admission.md) | `policies/image_admission/`, `examples/image_admission/`, `scripts/` | Released in v0.2.0; demonstrated in CI on a kind cluster |
| Attack harness: a named attack catalog and a seeded fuzzer for the two approval policies, judged by independent reference models, with stored inputs from LLM attackers replayed in CI. See [`docs/attack-harness.md`](docs/attack-harness.md) | `scripts/attack_harness.py`, `evaluation/attack-runs/` | Released in v0.2.0; LLM attackers are not run in CI |
| Deployment examples: Infrastructure-as-Code for an open-source gateway on Kubernetes and for a managed cloud API gateway | `deploy/` | Planned |

## Design principles

1. **Check where the action takes effect.** Each kind of agent action has its own enforcement point: the executor that applies an infrastructure change, the cluster's admission check for images, and a gateway for tool and API calls.
2. **Deny by default.** An agent gets only the tools and actions its task requires.
3. **Separate identities.** Each agent has its own workload identity. When it acts for a user, it is limited to that user's entitlements.
4. **Approval bound to the exact change.** A high-impact change or action needs a recorded approval that names the artifact, the agent and the user it acts for, and expires.
5. **Every decision is logged** with enough context to reconstruct what happened.
6. **Controls are code:** versioned, reviewed, and tested.

## Try the change-path demonstration

Needs Docker only. No cloud account and no network at run time.

```sh
scripts/run_in_container.sh
```

It first applies a swapped plan under an approval recorded against a file name (the baseline), then runs the same swap with the approval bound to the plan digest, and refuses it. Per-case results, including the Terraform state before and after, are written to `results/results.json`.

## Try the image path and the attack harness

```sh
scripts/demo_image_admission.sh   # stage 1: approval decision and signed record; needs OPA, jq and cosign v2
python3 scripts/attack_harness.py # both approval policies; needs OPA and Python 3.10 or later
```

Stage 2 of the image path needs a Kubernetes 1.30+ cluster such as kind; see [`docs/image-admission.md`](docs/image-admission.md).

## Run the policy tests

Requires [OPA](https://www.openpolicyagent.org/docs/latest/#running-opa) v1.x.

```sh
# Run the unit tests for all policies
opa test policies/ -v

# Evaluate one tool-call request against the example grants
opa eval \
  -d policies/tool_authz/tool_authz.rego \
  -d examples/tool_authz/data.json \
  -i examples/tool_authz/input-refund-without-approval.json \
  "data.agentaccess.tool_authz.decision"
```

**Reviewing this project?** Start with [`docs/REVIEWER_QUICKSTART.md`](docs/REVIEWER_QUICKSTART.md), and record findings with [`docs/EXTERNAL_REVIEW_TEMPLATE.md`](docs/EXTERNAL_REVIEW_TEMPLATE.md). [`docs/evaluation.md`](docs/evaluation.md) says what the demonstrations do and do not show.

## Three enforcement paths

An agent can change things in three ways, and each needs its own enforcement point:

- **Change path.** The agent proposes an infrastructure change (a Terraform plan) and a pipeline applies it. The controls here are a policy gate on the plan and human approval bound to the exact plan that is applied. See [`docs/approval-binding.md`](docs/approval-binding.md) for the design and its limits.
- **Image path.** The agent names a container image to deploy. The policy approves one exact digest and the cluster refuses any other. See [`docs/image-admission.md`](docs/image-admission.md).
- **Tool-call path.** The agent calls a tool or API through a gateway. The policy in [`policies/tool_authz`](policies/tool_authz/) decides each call. This shipped in v0.1; gateway deployment and approval binding for direct tool calls are not built.

## Decision records (tool-call path)

Every tool-call authorization decision produces a record that follows [`schemas/decision-record.schema.json`](schemas/decision-record.schema.json): outcome, denial reasons, agent, user, tool, action, request ID, impact, and approval. It does not include the user's entitlements or request payload. Examples are in [`examples/audit/`](examples/audit/).

```sh
pip install jsonschema
python scripts/validate_decision_log.py
```

This project defines the record, not the log pipeline. A gateway writes the record to an audit log; OPA's own decision log wraps it with a decision ID and timestamp.

Records of authorized *changes*: for container image approvals, the approval is a signed in-toto Statement that is verified before use (roadmap stage v0.3, first slice; see [`docs/image-admission.md`](docs/image-admission.md) for what a signature does and does not show). Signed records for Terraform plan approvals come later.

## Roadmap

Versions in this table are stages of work, not release tags. Release v0.2.0 contains stage v0.2 and first slices of stages v0.3 and v0.4.

| Version | Scope | Status |
| --- | --- | --- |
| v0.1 | Control catalog, tool-authorization policy with tests, threat model, CI | Released |
| v0.2 | Change path, first slice: policy gate on Terraform plans; approval bound to the saved-plan digest and to the agent and user identity; identity from GitHub Actions OIDC; reference pipeline; demonstration and no-control baseline | Released in v0.2.0; approved-apply path on real GitHub not yet exercised |
| v0.3 | Second interface: container images approved by digest and admitted in a local Kubernetes cluster. First slice: approval policy and a built-in Kubernetes admission policy. The approval is recorded as a signed in-toto Statement ([cosign](https://github.com/sigstore/cosign)) and verified before the policy runs. Planned next: signing the image itself and verifying it in the cluster with [Kyverno](https://kyverno.io/), signing key custody | First slice in v0.2.0; image signing planned |
| v0.4 | Attack harness. First slice: a named attack catalog and a seeded mutation fuzzer for the two approval policies, judged by independent reference models ([`docs/attack-harness.md`](docs/attack-harness.md)). Planned: attacks driven by an LLM agent, other policies, attacks based on public incidents | First slice in v0.2.0; LLM-driven attacks not run in CI |
| v0.5 | Review kit and external evaluation: reproducible instructions, an evaluation template, and published reviewer findings | Planned |
| Later | Signed records for Terraform plan approvals; gateway deployment examples for the tool-call path; approval binding for direct tool calls; mapping to OWASP and the CSA AI Controls Matrix | Not scheduled |

Not covered, and not planned for these versions: administrator break-glass access, CI systems other than GitHub Actions, dependency and vulnerability scanning, SBOM generation, signing of artifacts other than container images, and production hardening.

## Related work

This project builds on existing gateways and guidance rather than replacing them:

- [OWASP Top 10 for LLM Applications](https://genai.owasp.org/llm-top-10/)
- [CSA AI Controls Matrix](https://cloudsecurityalliance.org/artifacts/ai-controls-matrix/)
- [Open Policy Agent](https://www.openpolicyagent.org/)
- [Terraform saved plans](https://developer.hashicorp.com/terraform/cli/commands/plan#out-filename)
- [in-toto attestations](https://github.com/in-toto/attestation) and [Sigstore](https://www.sigstore.dev/)
- [Kyverno](https://kyverno.io/)
- [agentgateway](https://agentgateway.dev/)
- [Envoy AI Gateway](https://aigateway.envoyproxy.io/)

## Contributing, security, license

- Contributions: see [CONTRIBUTING.md](CONTRIBUTING.md).
- Reporting vulnerabilities: see [SECURITY.md](SECURITY.md).
- License: [Apache License 2.0](LICENSE).
