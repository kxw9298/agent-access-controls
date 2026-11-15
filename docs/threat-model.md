# Threat model (draft)

**Scope:** AI agents that call enterprise tools, MCP servers, and APIs on behalf of users, through the gateway described in [architecture.md](architecture.md); AI agents that propose infrastructure changes applied by a pipeline, as described in [approval-binding.md](approval-binding.md); and AI agents that name container images to deploy to a Kubernetes cluster, as described in [image-admission.md](image-admission.md). Model training, model hosting, and the internal security of individual tools are out of scope.

**Assets:** enterprise data reachable through tools; the ability to change records or move money; the ability to change infrastructure and to run code in a cluster; agent and user credentials; approval records and the key that signs them; the audit trail.

**Assumption:** an agent's output can be manipulated (for example through prompt injection in retrieved content), so the agent is not trusted to limit its own actions.

## Threats and controls

Where a threat matches an item in the [OWASP Top 10 for LLM Applications 2025](https://genai.owasp.org/llm-top-10/), the ID is listed.

| ID | Threat | OWASP LLM 2025 | Controls |
| --- | --- | --- | --- |
| T1 | An agent invokes a tool or action outside what its task needs | LLM06 | AAC-AZ-01, AAC-GW-01 |
| T2 | Injected instructions steer an agent into an unauthorized action | LLM01, LLM06 | AAC-CF-01, AAC-AZ-01, AAC-AZ-03 |
| T3 | An agent retrieves data the user it acts for is not entitled to see | LLM02, LLM08 | AAC-AZ-02 |
| T4 | An agent bypasses the gateway and calls a backend directly | LLM06 | AAC-GW-01, AAC-ID-01 |
| T5 | Shared or stolen credentials let one agent act as another | LLM06 | AAC-ID-01 |
| T6 | A high-impact action runs without human review | LLM06 | AAC-AZ-03 |
| T7 | After an incident, nobody can reconstruct what an agent did or why it was allowed | — | AAC-AU-01 |
| T8 | A runaway agent exhausts request capacity or token budget | LLM10 | AAC-RL-01 |
| T9 | An agent proposes a destructive or out-of-scope infrastructure change | LLM06 | AAC-CH-01 |
| T10 | The change applied differs from the change a person approved (re-planning or substitution after approval) | LLM01, LLM06 | AAC-CH-02, AAC-CH-03 |
| T11 | An approval is reused by a different agent or user, approved by the requester, or used after it has gone stale | LLM06 | AAC-CH-04 |
| T12 | After a change, nobody can show which approval authorized it | — | AAC-AU-02 |
| T13 | An image other than the approved one runs, through a different digest or a mutable tag that now points to different content | LLM01, LLM06 | AAC-CH-05, AAC-CH-06 |
| T14 | An image approval is used for a different agent or user, approved by the requester, or used after it has expired | LLM06 | AAC-CH-05 |
| T15 | An image approval record is forged, or altered after it was made | — | AAC-AU-02 |
| T16 | A pod with an unapproved image is created outside the pipeline, for example with `kubectl apply` | LLM06 | AAC-CH-06 |

## Open items

- Log retention and tamper protection. The decision-record schema for tool-call decisions is on `main`. Container image approvals are signed records; Terraform plan approvals are not signed yet. The log pipeline is not defined.
- The key that signs image approval records: custody, rotation and revocation. Whoever holds it can sign any approval (T15 is addressed only against someone without the key).
- Who can edit the published list of approved images, or the admission policy itself. Either can approve any image (T13, T16).
- Who built an image. A digest fixes the content, not its origin; image signing and provenance checks are not implemented.
- Replay and revocation of approvals, and a maximum approval lifetime.
- Telling an AI agent apart from other callers of the same workflow. The reference pipeline takes the agent from the workflow identity (v0.2).
- Paths to infrastructure that bypass the pipeline (see the limits in [approval-binding.md](approval-binding.md)).
- Threats specific to MCP server registration and tool metadata integrity.
- Mapping to the CSA AI Controls Matrix (not scheduled).
