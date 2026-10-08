# Threat model (draft)

**Scope:** AI agents that call enterprise tools, MCP servers, and APIs on behalf of users, through the gateway described in [architecture.md](architecture.md). Model training, model hosting, and the internal security of individual tools are out of scope.

**Assets:** enterprise data reachable through tools; the ability to change records or move money; agent and user credentials; the audit trail.

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

## Open items

- Decision-record schema and log retention (v0.2).
- Threats specific to MCP server registration and tool metadata integrity.
- Mapping to the CSA AI Controls Matrix (v1.0).
