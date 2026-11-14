# Attack harness (v0.4, first slice)

**Status:** runs in CI against the approval policy for Terraform plans (`policies/change_approval`). It has found real defects (below). It includes one round of attacks written by LLM agents, stored as a regression set. LLM attacks with published transcripts through the API are not done, and the other policies are not in the harness.

## What it does

[`scripts/attack_harness.py`](../scripts/attack_harness.py) tries to get the approval policy to allow something it should refuse, and judges every try against an independent reference model.

1. **A named attack catalog.** 32 hand-written attacks, each with an expected result: substituted digest, uppercase or truncated digest, a digest with a trailing newline, self-approval (exact and with different letter case), an agent recorded as approver, a different agent or user, expiry at the exact boundary, an unparseable expiry, a missing or malformed approval, `requires_approval` set to null or to the string `"false"`, and others. Three entries are legitimate controls that must be allowed, and two are marked `allow-by-design` (see "Known limits").
2. **A seeded mutation fuzzer.** From one valid input it deletes fields, swaps in wrong types, edits strings (case, whitespace, zero-width characters, look-alike characters, truncation), copies one field's value into another, and makes look-alike copies of other fields. A seed fixes the sequence, so a run can be repeated exactly. CI runs 20 seeds of 300 inputs.
3. **A reference model.** The policy cannot grade itself, so the harness restates in Python what the control is supposed to decide. A case where the policy **allows** and the model **denies** is a security finding and fails the run. A case where the policy denies and the model allows is a false refusal, which is counted and reported but does not fail the run.
4. **Candidates from other attackers.** `--candidates file.jsonl ...` takes files with one JSON input per line and judges them the same way. [`evaluation/llm-attacks/`](../evaluation/llm-attacks/README.md) holds 224 candidates written by three LLM agents, replayed in CI. Nothing in this repository calls an LLM at run time.

Results are written to `results/attack-harness/summary.json` and `transcripts.jsonl` (distinct findings, plus up to 50 false refusals). CI uploads them.

## Run it

```sh
python3 scripts/attack_harness.py        # needs OPA on PATH and Python 3.10 or later; no other packages
```

## What it found

The first run of the catalog showed the policy compared the approver with the requester and the agent case-sensitively. An approver recorded as `Alice` for a change requested by `alice`, or `Deploy-Agent` for the agent `deploy-agent`, passed the self-approval check. The mutation fuzzer found the same defect independently once it could make look-alike copies of other fields. GitHub logins are case-insensitive, so these are the same identity. The policy now compares identities without regard to case, with tests for both forms. In the reference pipeline the approver and requester both come from GitHub's own records, so it is not known that the pipeline could have produced differing case; the fix is defense in depth.

## What the LLM attackers found

Three Claude agents, each with a different angle (type and encoding confusion, identity and logic, Rego semantics), wrote 224 candidates after reading the policy and its tests. All three converged on one weakness: identities were compared as raw strings, so look-alike, decomposed and invisible-character variants of a name passed the independence check. The policy now refuses any identity that is not visible ASCII. They also found that the decision record was empty when no approval was needed, which is fixed. Details, counts and what remains allowed are in [`evaluation/llm-attacks/README.md`](../evaluation/llm-attacks/README.md).

My reference model could not see most of these: it compared identities by letter case only, so it agreed with the policy. The attackers found what the model could not, and the model now applies the same rule. That is the limit of a model written by the same person as the policy.

## Known limits

- **It is a second opinion, not a proof.** If the reference model shares a mistake with the policy, the harness will not see it. The model was written by the same person as the policy.
- **Coverage is bounded.** Mutations are random but shallow, typically one to three edits per input. 6,000 inputs with zero findings does not mean no input exists that is wrongly allowed. In the first run of 6,000 inputs, 547 were inputs both the policy and model allowed.
- **LLM attackers ran once each.** One run of about 60 to 80 candidates per agent is not a measure of how often an attacker succeeds. Repeated runs, with the transcripts published, are not done. More seeds of the deterministic fuzzer mean more inputs, not more variance.
- **The policy trusts what the executor supplies.** Two catalog entries are expected to succeed and are labeled `allow-by-design`: a backdated clock (`execution.now`) and an executor that claims `requires_approval` is false. If an attacker controls the executor's inputs, this policy cannot help. Those inputs must come from the trusted executor and the plan policy, as in the reference pipeline. Protecting the executor is outside this policy.
- **One policy in the harness.** The image-approval policy received the same fixes, but its harness target, with its own reference model, is not written. The Kubernetes admission stage and the tool-authorization policy are not covered.
- **Still allowed, by design of a text-comparing policy:** ASCII aliases for one person (an email for a username), an approver that is not a person (a bot, `-`, `*`), no maximum approval lifetime, and a caller-supplied clock. See `docs/approval-binding.md`.
- **Policy level only.** The harness feeds inputs to the policy. It does not drive the Terraform scripts or a pipeline.
