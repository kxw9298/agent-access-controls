# Attack harness (v0.4, first slice)

**Status:** runs in CI against two policies: the approval policy for Terraform plans (`policies/change_approval`) and the approval policy for container images (`policies/image_admission`). It has already found one real defect (below). Attacks driven by an LLM agent are not part of the CI run; the interface for them exists.

## What it does

[`scripts/attack_harness.py`](../scripts/attack_harness.py) tries to get the approval policy to allow something it should refuse, and judges every try against an independent reference model.

1. **A named attack catalog.** 23 hand-written attacks for the plan policy and 27 for the image policy, each with an expected result. For the plan policy: substituted digest, uppercase or truncated digest, a digest with a trailing newline, self-approval (exact and with different letter case), an agent recorded as approver, a different agent or user, expiry at the exact boundary, an unparseable expiry, a missing or malformed approval, `requires_approval` set to null or to the string `"false"`, and others. The image catalog adds tag-only and versioned-tag references, a second digest hidden behind a second `@`, whitespace in the reference, and a sha512 digest. Entries marked `allow-by-design` are explained under "Known limits".
2. **A seeded mutation fuzzer.** From one valid input it deletes fields, swaps in wrong types, edits strings (case, whitespace, zero-width characters, look-alike characters, truncation), copies one field's value into another, and makes look-alike copies of other fields. A seed fixes the sequence, so a run can be repeated exactly. CI runs 20 seeds of 300 inputs.
3. **A reference model per policy.** The policy cannot grade itself, so the harness restates in Python what each control is supposed to decide. A case where the policy **allows** and the model **denies** is a security finding and fails the run. A case where the policy denies and the model allows is a false refusal, which is counted and reported but does not fail the run.
4. **Candidates from other attackers.** `--candidates file.jsonl` takes one JSON input per line, for example inputs proposed by an LLM agent, and judges them the same way. Nothing in this repository calls an LLM.

Results are written to `results/attack-harness/summary.json` and `transcripts.jsonl` (distinct findings, plus up to 50 false refusals). CI uploads them.

## Run it

```sh
python3 scripts/attack_harness.py                          # both policies; needs OPA on PATH and Python 3.10 or later
python3 scripts/attack_harness.py --target image_admission # one policy
```

## What it found

The first run of the catalog showed the policy compared the approver with the requester and the agent case-sensitively. An approver recorded as `Alice` for a change requested by `alice`, or `Deploy-Agent` for the agent `deploy-agent`, passed the self-approval check. The mutation fuzzer found the same defect independently once it could make look-alike copies of other fields. GitHub logins are case-insensitive, so these are the same identity. Both approval policies now compare identities without regard to case, with tests for both forms. To check that the harness can see this class of defect in the image policy as well, I ran it against a copy of that policy with the case-insensitive comparison removed: the catalog failed two attacks and the fuzzer found three distinct bypasses. In the reference pipeline the approver and requester both come from GitHub's own records, so it is not known that the pipeline could have produced differing case; the fix is defense in depth.

## Known limits

- **It is a second opinion, not a proof.** If the reference model shares a mistake with the policy, the harness will not see it. The model was written by the same person as the policy.
- **Coverage is bounded.** Mutations are random but shallow, typically one to three edits per input. 6,000 inputs with zero findings does not mean no input exists that is wrongly allowed. In the first run of 6,000 inputs, 547 were inputs both the policy and model allowed.
- **Repeated trials of a deterministic attacker repeat themselves.** More seeds mean more inputs, not more variance. Variance would come from a stochastic attacker such as an LLM, which is not included.
- **The policy trusts what the executor supplies.** Two catalog entries are expected to succeed and are labeled `allow-by-design`: a backdated clock (`execution.now`) and an executor that claims `requires_approval` is false. If an attacker controls the executor's inputs, this policy cannot help. Those inputs must come from the trusted executor and the plan policy, as in the reference pipeline. Protecting the executor is outside this policy.
- **Two policies.** The Kubernetes admission stage, the plan policy for Terraform changes (`policies/terraform_plan`), the workload-identity policy and the tool-authorization policy are not covered.
- **Policy level only.** The harness feeds inputs to the policy. It does not drive the Terraform scripts or a pipeline.
