# Control catalog

[`catalog.yaml`](catalog.yaml) lists the controls this project defines. Each control has:

| Field | Meaning |
| --- | --- |
| `id` | Stable identifier, `AAC-<area>-<nn>` |
| `title` | One-line name |
| `objective` | What the control guarantees |
| `enforcement` | Where it is enforced: `gateway`, `network`, `identity-provider`, `policy-decision-point`, `audit-log`, `content-filter` |
| `owasp_llm_2025` | Related items from the [OWASP Top 10 for LLM Applications 2025](https://genai.owasp.org/llm-top-10/) |
| `status` | `planned`, `partial`, or `implemented` |
| `implementation` | Path to the code that implements it, once one exists |

Areas: `GW` gateway, `ID` identity, `AZ` authorization, `AU` audit, `CF` content filtering, `RL` rate limiting.

A mapping to the [CSA AI Controls Matrix](https://cloudsecurityalliance.org/artifacts/ai-controls-matrix/) is planned for v1.0.

Validate the catalog with:

```sh
python scripts/validate_catalog.py
```
