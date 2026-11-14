#!/usr/bin/env python3
"""Attack harness for the approval policy: a named attack catalog and a seeded
mutation fuzzer, both judged against an independent reference model.

Why a reference model: the policy under test cannot grade itself. The model in
this file restates, in Python, what the policy is supposed to decide. A case
where the policy ALLOWS and the model DENIES is a security finding. A case
where the policy denies and the model allows is a false refusal and is only
reported. The model is written from the control's intent (docs/approval-binding.md)
and is a second opinion, not proof: if the model shares a mistake with the
policy, this harness will not see it.

The fuzzer is deterministic for a given seed. Running more seeds covers more
inputs; repeating the same seed repeats the same inputs. Attackers that are not
deterministic, such as an LLM agent, can supply their own inputs with
--candidates, one JSON object per line; they are judged the same way.

Usage:
  python scripts/attack_harness.py [--opa opa] [--seeds 20] [--per-seed 300]
         [--out results/attack-harness] [--candidates file.jsonl ...]
Exit status 0: no security finding and every catalog attack was refused.
"""
import argparse
import copy
import datetime as dt
import json
import random
import re
import subprocess
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
POLICY = ROOT / "policies" / "change_approval" / "change_approval.rego"
PACKAGE = "data.agentaccess.change_approval"

DIGEST_A = "3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855a"
DIGEST_B = "9f86d081884c7d659a2feaa0c55ad015a3bf4f1b2b0b822cd15d6c15b0f00a08"
NOW = "2026-12-01T12:00:00Z"
EXPIRES = "2026-12-01T13:00:00Z"

BASE = {
    "artifact": {"sha256": DIGEST_A},
    "execution": {"agent": "deploy-agent", "requested_by": "alice", "now": NOW},
    "plan_decision": {"allow": True, "requires_approval": True},
    "approval": {
        "plan_sha256": DIGEST_A,
        "agent": "deploy-agent",
        "requested_by": "alice",
        "approver": "bob",
        "expires_at": EXPIRES,
    },
}

_MISSING = object()


def get(d, *path):
    for key in path:
        if not isinstance(d, dict) or key not in d:
            return _MISSING
        d = d[key]
    return d


def nonempty_str(v):
    return isinstance(v, str) and v != ""


def valid_digest(v):
    return isinstance(v, str) and re.fullmatch(r"[0-9a-f]{64}", v) is not None


_RFC3339 = re.compile(r"(\d{4}-\d{2}-\d{2}T\d{2}:\d{2}:\d{2})(\.\d+)?(Z|[+-]\d{2}:\d{2})")
_EPOCH = dt.datetime(1970, 1, 1, tzinfo=dt.timezone.utc)
_INT64 = 2**63


def parse_time(v):
    """Nanoseconds since the epoch, or None. OPA keeps times as int64
    nanoseconds, so an instant outside roughly 1677 to 2262 is an error."""
    if not isinstance(v, str):
        return None
    m = _RFC3339.fullmatch(v)
    if not m:
        return None
    zone = "+00:00" if m.group(3) == "Z" else m.group(3)
    try:
        moment = dt.datetime.fromisoformat(m.group(1) + zone)
    except ValueError:
        return None
    frac_ns = int((m.group(2) or ".")[1:].ljust(9, "0")[:9] or 0)
    delta = moment - _EPOCH
    ns = (delta.days * 86400 + delta.seconds) * 10**9 + frac_ns
    return ns if -_INT64 <= ns < _INT64 else None


def visible_ascii(v):
    """Identities must be visible ASCII, with no spaces or control, zero-width
    or look-alike characters (see policies/change_approval)."""
    return isinstance(v, str) and re.fullmatch(r"[!-~]+", v) is not None


def same_identity(a, b):
    """Identities are compared case-insensitively: GitHub logins and many
    directory identities are, so 'Alice' and 'alice' are one person."""
    if isinstance(a, str) and isinstance(b, str):
        return a.casefold() == b.casefold()
    return a == b


def model_allows(inp):
    """What the policy is supposed to decide, restated independently."""
    pd_allow = get(inp, "plan_decision", "allow")
    pd_req = get(inp, "plan_decision", "requires_approval")
    if not (isinstance(pd_allow, bool) and isinstance(pd_req, bool)):
        return False
    if pd_allow is not True:
        return False
    if not valid_digest(get(inp, "artifact", "sha256")):
        return False
    ex_agent = get(inp, "execution", "agent")
    ex_user = get(inp, "execution", "requested_by")
    if not (nonempty_str(ex_agent) and nonempty_str(ex_user)):
        return False
    if not (visible_ascii(ex_agent) and visible_ascii(ex_user)):
        return False
    if pd_req is False:
        return True
    ap = get(inp, "approval")
    if not isinstance(ap, dict):
        return False
    if not valid_digest(ap.get("plan_sha256")) or ap["plan_sha256"] != inp["artifact"]["sha256"]:
        return False
    if ap.get("agent", _MISSING) is _MISSING or ap["agent"] != ex_agent:
        return False
    if ap.get("requested_by", _MISSING) is _MISSING or ap["requested_by"] != ex_user:
        return False
    approver = ap.get("approver")
    if not nonempty_str(approver):
        return False
    if not (visible_ascii(approver) and visible_ascii(ap["requested_by"]) and visible_ascii(ap["agent"])):
        return False
    others = [ap["requested_by"], ap["agent"], ex_user, ex_agent]
    if any(same_identity(approver, o) for o in others):
        return False
    expires = parse_time(ap.get("expires_at"))
    now = parse_time(get(inp, "execution", "now"))
    if expires is None or now is None:
        return False
    return now < expires


def evaluate(opa, cases):
    """Evaluate the policy for every case in one OPA call."""
    query = (
        "[a | some c in input.cases; a := "
        + PACKAGE + ".allow with input as c]"
    )
    proc = subprocess.run(
        [opa, "eval", "-f", "json", "-d", str(POLICY), "-I", query],
        input=json.dumps({"cases": cases}), capture_output=True, text=True,
    )
    if proc.returncode != 0:
        sys.exit("opa failed: " + proc.stderr.strip())
    return json.loads(proc.stdout)["result"][0]["expressions"][0]["value"]


def variant(path, value):
    out = copy.deepcopy(BASE)
    node = out
    for key in path[:-1]:
        node = node[key]
    if value is _MISSING:
        del node[path[-1]]
    else:
        node[path[-1]] = value
    return out


def attack_catalog():
    """(id, description, input, expected). Expected is 'deny', 'allow' (a legitimate
    control, to catch false refusals) or 'allow-by-design' (a known limit)."""
    a = BASE["approval"]
    cat = []

    def add(i, d, inp, expected="deny"):
        cat.append({"id": i, "description": d, "input": inp, "expected": expected})

    add("substituted-digest", "Approval names a digest that differs from the plan to apply by one character",
        variant(["approval", "plan_sha256"], DIGEST_A[:-1] + "0"))
    add("uppercase-digest", "Both digests in uppercase hex, to slip past comparison",
        {**variant(["artifact", "sha256"], DIGEST_A.upper()),
         "approval": {**a, "plan_sha256": DIGEST_A.upper()}})
    add("digest-trailing-newline", "Both digests end in a newline",
        {**variant(["artifact", "sha256"], DIGEST_A + "\n"),
         "approval": {**a, "plan_sha256": DIGEST_A + "\n"}})
    add("short-digest", "Both digests are truncated",
        {**variant(["artifact", "sha256"], DIGEST_A[:32]),
         "approval": {**a, "plan_sha256": DIGEST_A[:32]}})
    add("self-approval-case-variant", "Requester approves their own change with different letter case",
        variant(["approval", "approver"], "Alice"))
    add("agent-approval-case-variant", "The agent is recorded as approver with different letter case",
        variant(["approval", "approver"], "Deploy-Agent"))
    add("self-approval-exact", "Requester is recorded as approver", variant(["approval", "approver"], "alice"))
    add("empty-approver", "Approver is an empty string", variant(["approval", "approver"], ""))
    add("different-agent", "A different agent executes the approved plan",
        variant(["execution", "agent"], "other-agent"))
    add("different-requester", "A different user is recorded as requester",
        variant(["execution", "requested_by"], "mallory"))
    add("expired-at-boundary", "Executed at the exact expiry instant",
        variant(["execution", "now"], EXPIRES))
    add("expired-later", "Executed after expiry", variant(["execution", "now"], "2026-12-02T00:00:00Z"))
    add("expiry-unparseable", "Expiry is not a time", variant(["approval", "expires_at"], "never"))
    add("expiry-no-timezone", "Expiry has no timezone", variant(["approval", "expires_at"], "2026-12-01T13:00:00"))
    add("approval-missing", "No approval record", {k: v for k, v in BASE.items() if k != "approval"})
    add("approval-is-a-list", "Approval record is a list", variant(["approval"], [a]))
    add("requires-approval-null", "requires_approval is null, to dodge the approval check",
        variant(["plan_decision", "requires_approval"], None) | {"approval": None})
    add("requires-approval-string-false", "requires_approval is the string 'false'",
        variant(["plan_decision", "requires_approval"], "false") | {"approval": None})
    add("plan-allow-string", "plan_decision.allow is the string 'true'",
        variant(["plan_decision", "allow"], "true"))
    add("plan-denied-but-approved", "The plan policy denied the plan but a valid approval exists",
        variant(["plan_decision", "allow"], False))
    add("identity-missing", "Executing agent identity is missing",
        variant(["execution", "agent"], _MISSING))
    # Found by LLM attackers: identity strings that differ as text but could
    # name one person.
    add("approver-decomposed-unicode", "Approver is the requester's name in decomposed Unicode form",
        {**variant(["execution", "requested_by"], "jos\u00e9"),
         "approval": {**a, "requested_by": "jos\u00e9", "approver": "jose\u0301"}})
    add("approver-trailing-space", "Approver is the requester's name plus a trailing space",
        variant(["approval", "approver"], "alice "))
    add("approver-zero-width", "Approver is the requester's name with a zero-width space",
        variant(["approval", "approver"], "ali\u200bce"))
    add("approver-greek-sigma", "Requester and approver differ only by Greek final sigma",
        {**variant(["execution", "requested_by"], "\u03b1\u03c2"),
         "approval": {**a, "requested_by": "\u03b1\u03c2", "approver": "\u0391\u03a3"}})
    add("approver-whitespace-only", "Approver is a single space", variant(["approval", "approver"], " "))
    add("agent-homoglyph", "Executing agent uses a Cyrillic look-alike letter",
        variant(["execution", "agent"], "deploy-ag\u0435nt"))
    add("expiry-year-2200", "Legitimate control: a far-future expiry is allowed (no maximum lifetime is checked)",
        variant(["approval", "expires_at"], "2200-01-01T00:00:00Z"), expected="allow")
    add("expiry-one-nanosecond-ahead", "Legitimate control: expiry one nanosecond after now",
        variant(["approval", "expires_at"], "2026-12-01T12:00:00.000000001Z"), expected="allow")
    add("bot-style-identities", "Legitimate control: workflow reference and [bot] login",
        {**BASE, "execution": {"agent": "o/r/.github/workflows/x.yml@refs/heads/main", "requested_by": "dependabot[bot]", "now": NOW},
         "approval": {**a, "agent": "o/r/.github/workflows/x.yml@refs/heads/main", "requested_by": "dependabot[bot]"}},
        expected="allow")
    # Known limits: the policy trusts what the executor supplies.
    add("backdated-clock", "The executor supplies a clock value before expiry for an expired approval",
        {**variant(["execution", "now"], "2026-11-01T00:00:00Z"),
         "approval": {**a, "expires_at": "2026-11-15T00:00:00Z"}}, expected="allow-by-design")
    add("executor-claims-no-approval-needed", "The executor supplies requires_approval=false",
        variant(["plan_decision", "requires_approval"], False) | {"approval": None}, expected="allow-by-design")
    return cat


JUNK = [None, 0, 1, True, False, "", [], {}, "false", "true", "null"]
CONFUSABLE = {"a": "а", "e": "е", "o": "о", "0": "O", "l": "1"}


def leaf_paths(d, prefix=()):
    for k, v in d.items():
        if isinstance(v, dict):
            yield from leaf_paths(v, prefix + (k,))
        else:
            yield prefix + (k,)


def mutate_string(rng, s):
    ops = [
        lambda x: x.upper(), lambda x: x.lower(), lambda x: x.capitalize(),
        lambda x: " " + x, lambda x: x + " ", lambda x: x + "\n", lambda x: "​" + x,
        lambda x: x[:-1], lambda x: x + "0", lambda x: x * 2,
        lambda x: x[:-1] + ("0" if not x.endswith("0") else "1"),
        lambda x: "".join(CONFUSABLE.get(c, c) if rng.random() < 0.5 else c for c in x),
        lambda x: x.replace("-", "_"),
        lambda x: rng.choice([DIGEST_A, DIGEST_B, "alice", "bob", "deploy-agent", "mallory", NOW, EXPIRES]),
    ]
    return rng.choice(ops)(s)


def mutate(rng, base):
    out = copy.deepcopy(base)
    for _ in range(rng.choice([1, 1, 2, 3])):
        paths = list(leaf_paths(out))
        if not paths:
            break
        path = rng.choice(paths)
        node = out
        for key in path[:-1]:
            node = node[key]
        key = path[-1]
        op = rng.choice(["delete", "junk", "string", "string", "copy", "alias", "section"])
        if op == "delete":
            del node[key]
        elif op == "junk":
            node[key] = rng.choice(JUNK)
        elif op == "string" and isinstance(node[key], str):
            node[key] = mutate_string(rng, node[key])
        elif op == "copy":
            other = rng.choice(paths)
            src = out
            for k in other:
                src = src[k] if isinstance(src, dict) and k in src else None
            node[key] = src
        elif op == "alias":
            # Another field's value, altered: how a spoofed or look-alike identity arises.
            other = rng.choice(paths)
            src = out
            for k in other:
                src = src[k] if isinstance(src, dict) and k in src else None
            node[key] = mutate_string(rng, src) if isinstance(src, str) else src
        elif op == "section":
            top = rng.choice(list(out.keys()))
            out[top] = rng.choice([None, [], "x", {}])
    return out


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--opa", default="opa")
    ap.add_argument("--seeds", type=int, default=20)
    ap.add_argument("--per-seed", type=int, default=300)
    ap.add_argument("--out", default=str(ROOT / "results" / "attack-harness"))
    ap.add_argument("--candidates", nargs="+", help="JSON lines files of inputs proposed by an external attacker")
    args = ap.parse_args()
    out = Path(args.out)
    out.mkdir(parents=True, exist_ok=True)

    # 1. Named attacks.
    catalog = attack_catalog()
    allowed = evaluate(args.opa, [c["input"] for c in catalog])
    catalog_results, catalog_failures = [], 0
    for c, got in zip(catalog, allowed):
        expected_allow = c["expected"] in ("allow-by-design", "allow")
        ok = got == expected_allow
        catalog_failures += 0 if ok else 1
        catalog_results.append({"id": c["id"], "description": c["description"],
                                "expected": c["expected"], "policy_allowed": got,
                                "model_allowed": model_allows(c["input"]), "ok": ok})

    # 2. Seeded mutation fuzzing, and any candidates, against the model.
    cases = []
    for seed in range(args.seeds):
        rng = random.Random(seed)
        for _ in range(args.per_seed):
            cases.append({"source": f"fuzz-seed-{seed}", "input": mutate(rng, BASE)})
    for name in args.candidates or []:
        for n, line in enumerate(Path(name).read_text().splitlines(), 1):
            if line.strip():
                cases.append({"source": f"{Path(name).name}:{n}", "input": json.loads(line)})
    decisions = evaluate(args.opa, [c["input"] for c in cases])
    findings, false_refusals, both_allow = [], [], 0
    for c, got in zip(cases, decisions):
        want = model_allows(c["input"])
        if got and not want:
            findings.append({"source": c["source"], "input": c["input"]})
        elif want and not got:
            false_refusals.append({"source": c["source"], "input": c["input"]})
        elif got and want:
            both_allow += 1

    # Distinct findings only; the same bypass shows up in many mutated inputs.
    seen, unique = set(), []
    for f in findings:
        key = json.dumps(f["input"], sort_keys=True)
        if key not in seen:
            seen.add(key)
            unique.append(f)

    commit = subprocess.run(["git", "rev-parse", "HEAD"], cwd=ROOT, capture_output=True, text=True).stdout.strip()
    opa_version = subprocess.run([args.opa, "version"], capture_output=True, text=True).stdout.splitlines()[0]
    summary = {
        "target": "policies/change_approval",
        "source_commit": commit or None,
        "opa": opa_version,
        "seeds": args.seeds,
        "inputs_per_seed": args.per_seed,
        "inputs_total": len(cases),
        "agreed_allow": both_allow,
        "security_findings": len(unique),
        "false_refusals": len(false_refusals),
        "catalog_attacks": len(catalog),
        "catalog_failures": catalog_failures,
        "catalog": catalog_results,
    }
    (out / "summary.json").write_text(json.dumps(summary, indent=2) + "\n")
    with (out / "transcripts.jsonl").open("w") as fh:
        for f in unique:
            fh.write(json.dumps({"kind": "security-finding", **f}) + "\n")
        for f in false_refusals[:50]:
            fh.write(json.dumps({"kind": "false-refusal", **f}) + "\n")

    print(f"catalog: {len(catalog)} attacks, {catalog_failures} not as expected")
    for r in catalog_results:
        print(f"  {'ok ' if r['ok'] else 'FAIL'} {r['id']:<34} expected {r['expected']:<15} policy_allowed={r['policy_allowed']}")
    print(f"fuzz: {len(cases)} inputs ({args.seeds} seeds x {args.per_seed}), "
          f"{len(unique)} distinct security findings, {len(false_refusals)} false refusals")
    for f in unique[:5]:
        print("  FINDING", f["source"], json.dumps(f["input"], sort_keys=True)[:300])
    sys.exit(1 if (unique or catalog_failures) else 0)


if __name__ == "__main__":
    main()
