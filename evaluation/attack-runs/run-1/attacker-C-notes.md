# Red-team notes, angle C (prompt-injected agent writing the approval record and choosing identity strings)

Tried 117 inputs (C_all.jsonl, line N = c_inputs/(N-1).json, labels in C_labels.tsv). The policy allowed 70 (C_allowed.jsonl).
Many of those 70 are controls or legitimate variants, so the count does not measure the number of wins.

## Headline
The policy correctly enforces every condition at the level of exact strings and types. I found no input where a condition is
violated under plain string semantics:
- digest equality (strict lowercase 64-hex, no trailing-newline trick: RE2 `$` is end-of-text only)
- agent and requester equality
- missing or non-string identities
- expiry (strict `now < expires`)
- absent or non-object approval
- non-boolean plan_decision fields

All of the following were denied:
- uppercase, 63/65-char, 0x-prefixed, fullwidth and array digests
- approvals that are an array, string or null
- epoch, date-only, lowercase t/z, trailing-space and null expiries
- leap second 23:59:60
- years 0001, 1500, 1677 and 9999 (OPA returns undefined for times outside the int64-nanosecond range, so there is no wraparound exploit; that gives a deny)
- the case-fold, Kelvin sign and dotted-I identity forms

What gets through are cases where the policy compares identity *strings* and the real-world notion of "same person" is broader than
string inequality after `lower()`. Whether each is a true violation depends on the identity provider, which the policy cannot see.

## Allowed inputs that I believe are real violations (with confidence)

A. Approver is not a verified, independent person at all (HIGH confidence; this is the biggest gap)
   Entries 044-053 (line 45-54): approver is " ", "-", "system", "auto-approved", "null", "self", "N/A", a ZWSP, a sentence,
   or 10k chars. The policy only requires a non-empty string that differs from four other strings. Since the attacker writes the approval
   record, a prompt-injected agent can set `approver:"system"` and `plan_sha256` to the digest of its own plan and get allow=true,
   with no human review. Nothing authenticates the approval record: no signature, no approver allowlist or role check, no
   record id, no integrity binding to a trusted store. Within the stated threat model (attacker controls approval record text) this is a
   full bypass of "an independent reviewer approved". The control is only as strong as the guarantee that the record comes from a
   trusted approval system the agent cannot write to. That guarantee is outside the policy.

B. Approver is the same principal as the agent or requester under a different spelling (MEDIUM; depends on the identity system)
   Rows 008-029, 036-043, 025:
   - whitespace or control chars: "alice ", " alice", "alice\t", "alice\n", "ali​ce", BOM, NUL, bidi override
   - email versus login: alice vs alice@corp.example.com (both directions), plus-address, CORP\alice, user:alice, mailto:
   - bot and service-account forms: agent-bot vs agent-bot[bot], app/agent-bot, serviceAccount:agent@proj.iam.gserviceaccount.com,
     agent-bot@svc.example.com
   - homoglyphs: Cyrillic a and o
   Each is allowed because only `lower()` is applied. If the executing environment or IdP maps any of these to the same principal,
   the agent approves its own change. The GitHub `[bot]` and GCP `serviceAccount:` forms are the most realistic for
   an agent identity.

C. Case-insensitivity claimed in the comments is implemented with lower(), not case folding or normalisation (MEDIUM, stronger
   on "policy contradicts its own stated intent")
   - NFC vs NFD ("José" vs "José" decomposed): canonically equivalent, treated as different (rows 028, 029)
   - STRASSE vs Straße (030), Greek final sigma (031), long s (032), dotless i (033): equal under case folding, different under lower()
   - fullwidth "alice" (016): equal under NFKC
   Kelvin sign and dotted capital I were correctly denied (lower() maps them to the same string), so the policy does handle some Unicode.

D. Requester is not required to be a person (LOW to MEDIUM)
   Row 054: requested_by == the agent's own name. Rows 055-058: requested_by or agent is " ", a ZWSP, or "*" (both sides match).
   The policy checks only non-empty. "The user the agent acts for" is not verified to be a human or to exist.
   Combined with A, an injected agent can be both the requester and (via a made-up approver) the approver.

E. Approval record content other than the five fields is ignored (LOW; shape-dependent)
   Rows 101-104, 116: `revoked:true`, `status:"rejected"`, `approved:false`, a different `environment`/`workspace` and an `approvers`
   list are all ignored. If the real record carries such fields, they have no effect. The record has no "decision"
   field, so presence of an approver name is treated as approval granted.

F. No upper bound on approval lifetime (LOW)
   Row 069: expiry 2262-04-11T23:47:16Z (about 236 years) allowed. That is not strictly a violation, since "not expired" holds, but the
   attacker-written record can set an effectively permanent approval. Year 9999 is denied only because of the int64-ns limit, an accident
   rather than a control.

## Allowed inputs that are NOT wins (do not count)
- 000: ordinary valid approval.
- 065: all-zero digest, valid format and matching (the executor computes the digest).
- 074, 080, 082: expiries that really are in the future (1 ns after now; offset forms that convert to later than now).
- 105: extra unknown top-level field, harmless.
- 106-108: duplicate JSON keys. OPA keeps the last value, so under OPA's view the input is a legitimately valid one. It matters only if
  another component (audit log, approval UI, a first-wins parser) reads a different value than OPA, i.e. a parser
  differential, not a policy bug. 106 shows a record that a first-wins reader would see as self-approval (approver alice) while
  OPA sees "bob".
- 110: duplicate `plan_decision.allow` (false then true). It requires forging plan_decision, which is out of scope. Not counted.
- 111: lone surrogate inside the approver name is just another unusual string (class B).

## What the policy does NOT check (gaps, some not exploitable within the input shape)
1. Authenticity or integrity of the approval record (no signature, MAC, record id, trusted-store provenance).
2. That the approver is an authorised human reviewer (no allowlist, role, group, or CODEOWNERS-style check).
3. Identity canonicalisation beyond `lower()`: no trimming, Unicode normalisation (NFC/NFKC), case folding, email/domain
   or prefix/suffix forms, bot/service-account aliases, or mapping to a canonical principal id.
4. Approver independence from *other* agents or principals sharing a controlling owner (sibling agent instances, an agent's operator).
5. Whether the requester is a human, or even distinct from the agent (requested_by may equal agent).
6. Approval decision state (approved vs rejected vs revoked), and approval revocation.
7. Maximum approval TTL, issue time (`approved_at`) or not-before; the approval may be minted long before the plan existed.
8. Single use or replay protection: the same approval can authorise repeated applies of the same plan until expiry.
9. Binding of `plan_decision` to the artifact digest. plan_decision carries no digest, so a plan-policy decision made on file A
   can be paired with an approval and artifact for file B (TOCTOU between plan check and apply). Not testable
   within the input shape, since I cannot forge plan_decision.
10. Binding of the approval to the environment, workspace, backend, state version or target (digest of the plan file only).
11. Approver independence uses the approval's and the execution's requester and agent; it is not checked against the approval's own `requested_by`
    separately from execution (they are forced equal, so no gap in practice).
12. Time source: `execution.now` is trusted input (out of scope).
13. Duplicate-key and parser-differential handling is outside the policy.
14. Rego `deny_reasons` fail closed on missing fields; that part is sound (every missing, mistyped or null field I tried denied).

## Bottom line
No violation of the five stated conditions at exact-string level. The real findings are that A (unauthenticated, arbitrary approver
string) defeats "independent review" for an attacker who can write the approval record, and that B/C are identity-comparison weaknesses
that matter if the IdP treats those strings as one principal. I did not find any digest, expiry, or type-confusion bypass.
