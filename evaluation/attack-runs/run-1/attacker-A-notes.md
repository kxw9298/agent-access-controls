# Attacker A notes: type confusion / encoding

Policy: change_approval.rego, OPA 1.4.2. 132 inputs tried (A_all.jsonl), 41 allowed (A_allowed.jsonl).
Labels (e.g. "21 approver ZWSP...") are in gen_a.py; the line order matches the printed run order.
All inputs use now=2026-11-14T12:00:00Z, and the base is a valid approval (approver bob, requester alice, agent deploy-agent).

## Bottom line
I found NO input where allow=true while a condition is violated, if identities are compared as raw strings
and digests/times are compared as the policy defines them. Digest, expiry, plan_decision, and
type-confusion checks all held. The only "wins" are identity string-equivalence gaps: the approver
is the same principal as the requester or agent under some normalization, but not after lower().
Whether those are real violations depends on how the identity provider canonicalizes names (unverified).

## What held (denied)
- Digest: uppercase, trailing newline (RE2 `$` is not multiline), leading space, 63/65 chars, fullwidth digits,
  Cyrillic hex lookalikes, NUL suffix, "sha256:" prefix, number/list/object/null/missing, "D\nD". All denied.
- Types: approver as list/object/number/bool/null/empty/missing; approval as list/string/null/{}/missing;
  requires_approval as "false"/0/null/missing/[false]; allow as "true"/1; plan_decision as list/missing.
  All denied. Only boolean false skips approval (design intent).
- Non-string exec agent/requester equal in approval: denied (agent_present/requester_present need strings).
- Case: ALICE/aLiCe/DEPLOY-AGENT/email case variants denied. Kelvin sign (U+212A) and U+0130 both lower to ASCII
  in OPA, so they are denied (stricter than needed).
- Time: expires==now denied (strict <); lowercase t/z, space separator, leap second :60, hour 24, Feb 30,
  date-only, no offset, epoch number, null/list/missing, whitespace padded, 5-digit/negative/0000 year: denied.
- int64 overflow idea (expired year 1500/0001/1677 wrapping to a large positive ns): OPA 1.4.2 raises
  "time outside of valid range" for years < 1678 or > 2262, so these are undefined and deny. Not exploitable here.
  (This depends on OPA version; older builds may wrap silently. Unverified for them.)

## Allowed inputs and my assessment
Legitimately allowed (not violations):
- 00 control; 75/76 requires_approval=false (design: plan policy says none needed); 88 extra key; 91 expires +1ns;
  100 expires "2026-11-14T00:00:00-24:00" (OPA accepts offsets up to +/-24:xx, beyond RFC 3339's 23:59, but the
  parsed instant is 2026-11-15T00:00Z, genuinely future); 103 offset -23:59 (genuinely future);
  122-124, 127, 130, 131 duplicate-key JSON (OPA uses the last key, result is a valid approval under that reading).

Allowed with a plausible violation (identity string-equivalence; "approver is a different person"):
- Whitespace/control variants of the requester or agent as approver: 22 "alice ", 23 " alice", 24 "alice\n",
  39 "deploy-agent ", 58 "alice\u0000". Most likely to be real: many systems trim these.
- Unicode normalization: 27/28 NFD vs NFC "josé", 29 fullwidth "ａｌｉｃｅ" (NFKC equals alice), 65 fullwidth agent.
  Real if the IdP normalizes (NFC/NFKC).
- Invisible/default-ignorable chars: 21 ZWSP suffix, 38 ZWSP on agent, 55/56 reverse (ZWSP on the requester/agent
  side), 57 combining mark, 59 RLO, 66 soft hyphen, 67 tag char. Real only where the IdP strips these; also a
  lookalike impersonation concern for reviewers reading the record.
- Case-fold gaps: 35 dotless i vs "I" (Turkish casing), 36 final sigma vs capital sigma word, 37 sharp s vs "STRASSE".
  lower() is not a full case fold. Real only for case-folding identity systems.
- 31 "alice@example.com" vs "alice" (same person, different identifier form). The policy has no identity canonical form.
- 30 Cyrillic а lookalike: a different account in most systems, so a homoglyph/impersonation issue, not self-approval.
- 60: 50k-char strings differing in the last char: allowed correctly (they differ); shown only as a length test.

Allowed but really an input-authenticity limit, not a policy-logic bug:
- 41/42/43/126: approver " ", ZWSP only, "system", lone surrogate. Any non-empty string counts as an approver.
  Since the attacker controls the approval record text, a forged record naming an arbitrary approver is allowed.
  The policy cannot tell, since it has no signature or directory lookup. This follows from the stated threat model,
  so I do not count it as a win, but it is a real design limit.
- 93: expires 2262-04-11 allowed. No maximum lifetime, so a record can set an expiry centuries out.
  Technically unexpired, so it is not a violation of the stated condition.
- 124 vs 134: duplicate expires_at keys are resolved last-wins by OPA. If the approval store parses first-wins,
  the two components would see different expiries (a parser differential). Low confidence; requires a mismatched parser.

## Suggested fixes (for the defender)
- Require identities to be canonical (NFKC, trimmed, no default-ignorable/control chars, ASCII-restricted or an immutable ID),
  or compare immutable subject IDs, not display names.
- Use a case fold on canonicalized strings; or reject non-ASCII identities.
- Verify the approval's authenticity (signature or fetch from the approval system) outside this policy.
- Cap approval lifetime (expires_at - issued_at) and reject offsets outside RFC 3339.
