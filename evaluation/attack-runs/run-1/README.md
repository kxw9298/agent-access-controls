# Attack run 1: three LLM attackers against the plan approval policy

Three Claude agents, each with a different angle, tried to get `policies/change_approval` to allow an input that violates the control. Angles: type and encoding confusion (A), identity and logic (B), and a free-form prompt-injected agent (C). 384 inputs in total.

What the attackers were given: the policy file, the control's intent in plain words, and the ability to run OPA on their own inputs. What they were told not to read: the harness, the unit tests and the docs. This is an instruction, not an enforced restriction.

Files: `attacker-X-inputs.jsonl` (every input tried, one JSON object per line) and `attacker-X-notes.md` (the attacker's own account, unedited except for one removed sandbox path).

## Replay

```sh
cat evaluation/attack-runs/run-1/attacker-*-inputs.jsonl > /tmp/run1.jsonl
python3 scripts/attack_harness.py --target change_approval --candidates /tmp/run1.jsonl
```

Three inputs are not valid JSON text (a lone surrogate, or Infinity) and are skipped; the harness says so.

## Result

- Against the policy as it was before the approver check was added (commit `6f0bf33`): of the 381 evaluable inputs, the policy allowed 164, and 98 of those are refused by the reference model as it stands now.
- Against the policy with the approver check: 0 such inputs.

## How much weight this carries

- **The model was tightened after the attackers reported.** Adding the approver-form rule to the reference model after reading their results means the "98" is measured against a model that already contains their findings. It shows the fix covers what they found. It is not an independent count of bugs.
- **One run, one model family.** The attackers are the same kind of model as the author's assistant. Shared blind spots are possible. A different model, or a human red team, may find different things.
- **Black box with a decision oracle.** The attackers could see whether each of their inputs was allowed. They could not see the model.
- **Not run in CI.** CI replays the stored inputs through `--candidates`; it does not call an LLM. Nothing here shows how often an LLM-driven attacker would succeed on a new run.
