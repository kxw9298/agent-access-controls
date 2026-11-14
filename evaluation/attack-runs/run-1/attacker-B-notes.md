# Attacker B notes (identity and logic angle)

Policy: policies/change_approval/change_approval.rego. OPA 1.4.2.
Fixed clock for all tests: execution.now = 2026-11-14T12:00:00Z.
Tried 135 inputs (B_all.jsonl), 55 allowed (B_allowed.jsonl). Per-input labels and results are in work/B_labels.tsv, in the same order as B_all.jsonl. The runner scripts are work/run_B.py and work/run_B2.py.
Every line of B_allowed.jsonl was re-evaluated from disk and returned allow=true.

## What I learned about the policy

Solid, fail-closed parts (all attempts denied):
- requires_approval absent, null, "false", 0 or a string -> deny, because plan_decision_present demands booleans. A missing approval with requires_approval true -> deny.
- approval null, {}, list, or approval with missing fields -> deny.
- Digest: uppercase, trailing newline, "sha256:" prefix, short, unicode digit, list -> deny. The Go regex `$` does not match before a trailing newline.
- agent and requested_by binding between execution and approval is exact string equality. Case, whitespace and missing-field differences -> deny. The binding is stricter than the approver check.
- Expiry: now == expires -> deny, and 1 ns past -> deny. Offsets are handled correctly, including +23:59 and +99:99. Leap second 60, no timezone, date-only, space separator, number and null all deny.
- Far-past years (1..1900) and years past 2262 all deny. I looked for int64 nanosecond overflow wrap-around that would make an expired approval look current, and found none; it fails closed. This also means valid far-future approvals (year 2300, 9999) are wrongly denied, but that is a false deny, not a bypass.
- Approver non-string, empty, missing or null -> deny.
- Duplicate JSON keys: OPA takes the last key. I found no differential within OPA itself.

The weakness is in approver_independent. It compares identities only with lower(), so approver independence is a case-insensitive exact string match. There is no trimming, no unicode normalization or casefolding, and no alias, domain or suffix handling. nonempty_string(approver) only tests != "", so whitespace-only and invisible-character approvers count as "present".

## Allowed inputs I believe are real violations
(The approver is the same person as the requester or the agent, or is not a real approver.)

Requester aliases (approver is the requesting user in another form):
- approver_email_form_of_requester ("alice@corp.com" vs requester "alice"), requester_email_approver_bare (the reverse), domain_backslash ("CORP\alice"), approver_at_prefix ("@alice"), approver_url_form ("https://github.com/alice"), plus_alias ("alice+approver@corp.com"), trailing_dot_domain.
- Whitespace and invisible characters: approver_trailing_space, leading_space, trailing_tab, trailing_newline, requester_trailing_space_both_sections, nbsp_suffix, zero_width_space_in_approver, soft_hyphen, bom_prefix, approver_requester_with_zwj, rtl_mark, tag_chars, and the zero-width-plus-case variant.
- Unicode: nfc_vs_nfd, fullwidth_a, combining_char_suffix. These are real same-person forms after NFKC or NFC normalization.
- Casefold gaps (lower() is not casefold): sharp_s_casefold ("STRASSE" vs "straße"), long_s_casefold ("SAM" vs "ſam"), greek_final_sigma.

Agent aliases (approver is the executing agent in another form):
- approver_agent_email, trailing_space, bot_suffix ("agent-1[bot]"), app_prefix ("app/agent-1"), fullwidth hyphen, agent_has_domain_approver_bare.
- approver_is_agent_nfd_variant is a misnomer. It uses U+2010 hyphen ("agent‐1") vs "agent-1"; it is a lookalike, weak.

Approver is blank or not an identity:
- approver_single_space, approver_nbsp, approver_zwsp, approver_newline. The approver is effectively missing, but the "approver is missing" check passes.

## Allowed but NOT real violations (do not count)
- control_valid, expiry_one_ns_future, expiry_utc_offset_zero, expiry_neg_zero_offset, expiry_max_ns_year_2262, expiry_comma_fraction: all legitimately unexpired and correctly allowed.
- requires_approval_false_no_approval and requires_approval_false_bad_approval: no approval is required, so an ignored approval record is correct.
- agent_same_as_requester_string (agent "alice", requester "alice", approver "bob"): the stated intent does not forbid it.
- dup_approver_first_alice_last_bob: allowed only because OPA takes the last duplicate key (approver "bob"), which is legitimate. A parser with first-key-wins semantics would see approver "alice", so this is a possible cross-parser differential, not a policy bug.
- approver_null_str, approver_dash, upn_vs_samaccount (different tenants, ambiguous), cyrillic_a_homoglyph (a different account that merely looks alike; arguably an impersonation, not the same person), approver_uppercase_turkish_dotless (I typed a different name, so it is junk).

## Bottom line
Found no bypass of digest, agent/requester binding, requires_approval handling or expiry. Found one cluster of real bypasses of "approver is a different person from the requester and the agent": identity normalization (aliases, whitespace, unicode) plus blank approver. Severity depends on whether the identity provider canonicalizes names upstream. Suggested fix: normalize (trim, NFKC, casefold, strip domain or suffix) before comparing, and require the approver to match a canonical identifier format.
