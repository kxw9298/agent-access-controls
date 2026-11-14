# Attack harness (v0.4, first slice)

**Status:** runs in CI against the approval policy for Terraform plans (`policies/change_approval`). It has already found one real defect (below). It does not yet include attacks driven by an LLM agent, and it does not cover the other policies.

## What it does

[`scripts/attack_harness.py`](../scripts/attack_harness.py) tries to get the approval policy to allow something it should refuse, and judges every try against an independent reference model.

1. **A named attack catalog.** 23 hand-written attacks, each with an expected result: substituted digest, uppercase or truncated digest, a digest with a trailing newline, self-approval (exact and with different letter case), an agent recorded as approver, a different agent or user, expiry at the exact boundary, an unparseable expiry, a missing or malformed approval, `requires_approval` set to null or to the string `"false"`, and others. Two entries are marked `allow-by-design` (see "Known limits").
2. **A seeded mutation fuzzer.** From one valid input it deletes fields, swaps in wrong types, edits strings (case, whitespace, zero-width characters, look-alike characters, truncation), copies one field's value into another, and makes look-alike copies of other fields. A seed fixes the sequence, so a run can be repeated exactly. CI runs 20 seeds of 300 inputs.
3. **A reference model.** The policy cannot grade itself, so the harness restates in Python what the control is supposed to decide. A case where the policy **allows** and the model **denies** is a security finding and fails the run. A case where the policy denies and the model allows is a false refusal, which is counted and reported but does not fail the run.
4. **Candidates from other attackers.** `--candidates file.jsonl` takes one JSON input per line, for example inputs proposed by an LLM agent, and judges them the same way. Nothing in this repository calls an LLM.

Results are written to `results/attack-harness/summary.json` and `transcripts.jsonl` (distinct findings, plus up to 50 false refusals). CI uploads them.

## Run it

```sh
python3 scripts/attack_harness.py        # needs OPA on PATH and Python 3.10 or later; no other packages
```

## What it found

The first run of the catalog showed the policy compared the approver with the requester and the agent case-sensitively. An approver recorded as `Alice` for a change requested by `alice`, or `Deploy-Agent` for the agent `deploy-agent`, passed the self-approval check. The mutation fuzzer found the same defect independently once it could make look-alike copies of other fields. GitHub logins are case-insensitive, so these are the same identity. The policy now compares identities without regard to case, with tests for both forms. In the reference pipeline the approver and requester both come from GitHub's own records, so it is not known that the pipeline could have produced differing case; the fix is defense in depth.

## Known limits

- **It is a second opinion, not a proof.** If the reference model shares a mistake with the policy, the harness will not see it. The model was written by the same person as the policy.
- **Coverage is bounded.** Mutations are random but shallow, typically one to three edits per input. 6,000 inputs with zero findings does not mean no input exists that is wrongly allowed. In the first run of 6,000 inputs, 547 were inputs both the policy and model allowed.
- **Repeated trials of a deterministic attacker repeat themselves.** More seeds mean more inputs, not more variance. Variance would come from a stochastic attacker such as an LLM, which is not included.
- **The policy trusts what the executor supplies.** Two catalog entries are expected to succeed and are labeled `allow-by-design`: a backdated clock (`execution.now`) and an executor that claims `requires_approval` is false. If an attacker controls the executor's inputs, this policy cannot help. Those inputs must come from the trusted executor and the plan policy, as in the reference pipeline. Protecting the executor is outside this policy.
- **One policy.** The image-approval policy and the Kubernetes admission stage are not covered yet. The tool-authorization policy is not covered.
- **Policy level only.** The harness feeds inputs to the policy. It does not drive the Terraform scripts or a pipeline.
