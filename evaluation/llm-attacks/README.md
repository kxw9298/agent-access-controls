# Candidates from LLM attackers

Inputs written by three Claude agents that were asked to find an input the policy `policies/change_approval` allows although the change is not properly authorized. They are kept as a regression set: CI replays them against the current policy with `scripts/attack_harness.py --candidates`.

| File | Attack angle | Candidates |
| --- | --- | --- |
| `types.jsonl` | Wrong JSON types, numbers, Unicode, whitespace, time formats | 82 |
| `logic.jsonl` | Identity aliases, relationships between fields, time boundaries, requirements the policy does not check | 66 |
| `semantics.jsonl` | Rego semantics: conditions that become undefined so a deny does not fire | 76 |

## How they were produced

- Each agent was given the policy source, its tests and `docs/approval-binding.md`, and was allowed to run OPA and iterate. It was told not to read the attack harness, its catalog or its reference model, and not to modify the repository.
- Each ran once, with a budget of about 60 candidates. The agents were not asked to repeat, and the results below are from one run each. They are not a statistical measure of anything.
- The agents' own reports about which candidates were attacks were not taken at face value. Every candidate was replayed through the harness and through OPA, and the categories below are from that replay and my reading of the inputs.
- One candidate was a string of 50,000 zero-width characters. It is shortened to 200 here to keep the file small.

## Results

Replayed against the policy before the fix described below, OPA allowed 94 of the 224 candidates. Against the policy after the fix it allows 46. Replayed through the harness at that earlier commit, six candidates were flagged as security findings: five letter-case variants that `lower()` does not fold (Greek sigma forms, long s, sharp s) and one fractional-second expiry that was a bug in the reference model, not in the policy. The model also reported 10 false refusals, all from that same bug. Most of the other 94 were invisible to the harness, because its model compared identities by case only and so agreed with the policy; the model now applies the same visible-ASCII rule as the policy.

What the attackers found:

1. **Identity strings that differ as text but could name one person.** All three agents converged on this. Examples: a decomposed and a composed accent, a trailing space, a zero-width character, a look-alike letter, Greek final sigma against capital sigma (which `lower()` does not fold). The policy compared raw strings. **Fixed** by refusing any identity that is not visible ASCII.
2. **`decision` was undefined when no approval was needed.** `allow` was correct, but the decision record the pipeline reads came back empty. **Fixed** with a default.

What remains allowed, because a policy that compares text cannot decide it. These are documented limits in `docs/approval-binding.md`:

- **ASCII aliases for one person.** An email address for a username (`alice@example.com` for `alice`), a prefix (`user:alice`, `app/alice`), or an agent alias. The policy needs identities from the identity provider in one canonical form.
- **An approver who is not a person.** `github-actions[bot]`, another agent, `-`, `*`, `unknown`. The policy checks that the approver is a non-empty, visible-ASCII string that differs from the requester and the agent. It does not check that the approver is a human.
- **No maximum lifetime and no not-before check.** An expiry in the year 2200 is allowed. The expiry is set by the pipeline that records the approval.
- **A caller-supplied clock.** `execution.now` set to 1970 makes an expired approval look current. This is the `allow-by-design` case in the catalog.

No attacker found a bypass of the digest check, the agent and requester match, the expiry comparison, or the plan-policy fields, and none found an undefined-condition bypass of a deny rule. That is a result for 224 inputs from three runs, not a proof.
