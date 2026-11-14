#!/usr/bin/env python3
"""Attack harness for the approval policies: a named attack catalog and a seeded
mutation fuzzer, both judged against an independent reference model.

Why a reference model: the policy under test cannot grade itself. The model in
this file restates, in Python, what the policy is supposed to decide. A case
where the policy ALLOWS and the model DENIES is a security finding. A case
where the policy denies and the model allows is a false refusal and is only
reported. Each model is written from the control's intent (docs/approval-binding.md,
docs/image-admission.md) and is a second opinion, not proof: if the model shares a
mistake with the policy, this harness will not see it.

The fuzzer is deterministic for a given seed. Running more seeds covers more
inputs; repeating the same seed repeats the same inputs. Attackers that are not
deterministic, such as an LLM agent, can supply their own inputs with
--candidates, one JSON object per line; they are judged the same way.

Targets: change_approval (Terraform plan approval) and image_admission (image
digest approval). Each has its own base input, reference model and catalog.

Usage:
  python scripts/attack_harness.py [--target change_approval|image_admission|all]
         [--opa opa] [--seeds 20] [--per-seed 300]
         [--out results/attack-harness] [--candidates file.jsonl]
Exit status 0: no security finding and every catalog attack behaved as expected.
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

NOW = "2026-12-01T12:00:00Z"
EXPIRES = "2026-12-01T13:00:00Z"
HEX_A = "3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855a"
HEX_B = "9f86d081884c7d659a2feaa0c55ad015a3bf4f1b2b0b822cd15d6c15b0f00a08"

_MISSING = object()


# ---------------------------------------------------------------- helpers

def get(d, *path):
    for key in path:
        if not isinstance(d, dict) or key not in d:
            return _MISSING
        d = d[key]
    return d


def nonempty_str(v):
    return isinstance(v, str) and v != ""


_RFC3339 = re.compile(r"(\d{4}-\d{2}-\d{2}T\d{2}:\d{2}:\d{2})(\.\d+)?(Z|[+-]\d{2}:\d{2})")


def parse_time(v):
    if not isinstance(v, str):
        return None
    m = _RFC3339.fullmatch(v)
    if not m:
        return None
    frac = (m.group(2) or "")[:7]
    zone = "+00:00" if m.group(3) == "Z" else m.group(3)
    try:
        return dt.datetime.fromisoformat(m.group(1) + frac + zone)
    except ValueError:
        return None


def same_identity(a, b):
    """Identities are compared case-insensitively: GitHub logins and many
    directory identities are, so 'Alice' and 'alice' are one person."""
    if isinstance(a, str) and isinstance(b, str):
        return a.casefold() == b.casefold()
    return a == b


def approver_independent(approver, others):
    return nonempty_str(approver) and not any(same_identity(approver, o) for o in others)


def variant(base, path, value):
    out = copy.deepcopy(base)
    node = out
    for key in path[:-1]:
        node = node[key]
    if value is _MISSING:
        del node[path[-1]]
    else:
        node[path[-1]] = value
    return out


def without(base, key):
    return {k: v for k, v in base.items() if k != key}


# ------------------------------------------------- target: change_approval

DIGEST_A = HEX_A
DIGEST_B = HEX_B

PLAN_BASE = {
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


def plan_valid_digest(v):
    return isinstance(v, str) and re.fullmatch(r"[0-9a-f]{64}", v) is not None


def plan_model(inp):
    """What the plan approval policy is supposed to decide, restated independently."""
    pd_allow = get(inp, "plan_decision", "allow")
    pd_req = get(inp, "plan_decision", "requires_approval")
    if not (isinstance(pd_allow, bool) and isinstance(pd_req, bool)):
        return False
    if pd_allow is not True:
        return False
    if not plan_valid_digest(get(inp, "artifact", "sha256")):
        return False
    ex_agent = get(inp, "execution", "agent")
    ex_user = get(inp, "execution", "requested_by")
    if not (nonempty_str(ex_agent) and nonempty_str(ex_user)):
        return False
    if pd_req is False:
        return True
    ap = get(inp, "approval")
    if not isinstance(ap, dict):
        return False
    if not plan_valid_digest(ap.get("plan_sha256")) or ap["plan_sha256"] != inp["artifact"]["sha256"]:
        return False
    if ap.get("agent", _MISSING) is _MISSING or ap["agent"] != ex_agent:
        return False
    if ap.get("requested_by", _MISSING) is _MISSING or ap["requested_by"] != ex_user:
        return False
    if not approver_independent(ap.get("approver"), [ap["requested_by"], ap["agent"], ex_user, ex_agent]):
        return False
    expires, now = parse_time(ap.get("expires_at")), parse_time(get(inp, "execution", "now"))
    return expires is not None and now is not None and now < expires


def plan_catalog():
    base, a = PLAN_BASE, PLAN_BASE["approval"]
    cat = []

    def add(i, d, inp, expected="deny"):
        cat.append({"id": i, "description": d, "input": inp, "expected": expected})

    both = lambda v: {**variant(base, ["artifact", "sha256"], v), "approval": {**a, "plan_sha256": v}}
    add("substituted-digest", "Approval names a digest that differs from the plan to apply by one character",
        variant(base, ["approval", "plan_sha256"], DIGEST_A[:-1] + "0"))
    add("uppercase-digest", "Both digests in uppercase hex, to slip past comparison", both(DIGEST_A.upper()))
    add("digest-trailing-newline", "Both digests end in a newline", both(DIGEST_A + "\n"))
    add("short-digest", "Both digests are truncated", both(DIGEST_A[:32]))
    add("self-approval-case-variant", "Requester approves their own change with different letter case",
        variant(base, ["approval", "approver"], "Alice"))
    add("agent-approval-case-variant", "The agent is recorded as approver with different letter case",
        variant(base, ["approval", "approver"], "Deploy-Agent"))
    add("self-approval-exact", "Requester is recorded as approver", variant(base, ["approval", "approver"], "alice"))
    add("empty-approver", "Approver is an empty string", variant(base, ["approval", "approver"], ""))
    add("different-agent", "A different agent executes the approved plan",
        variant(base, ["execution", "agent"], "other-agent"))
    add("different-requester", "A different user is recorded as requester",
        variant(base, ["execution", "requested_by"], "mallory"))
    add("expired-at-boundary", "Executed at the exact expiry instant", variant(base, ["execution", "now"], EXPIRES))
    add("expired-later", "Executed after expiry", variant(base, ["execution", "now"], "2026-12-02T00:00:00Z"))
    add("expiry-unparseable", "Expiry is not a time", variant(base, ["approval", "expires_at"], "never"))
    add("expiry-no-timezone", "Expiry has no timezone", variant(base, ["approval", "expires_at"], "2026-12-01T13:00:00"))
    add("approval-missing", "No approval record", without(base, "approval"))
    add("approval-is-a-list", "Approval record is a list", variant(base, ["approval"], [a]))
    add("requires-approval-null", "requires_approval is null, to dodge the approval check",
        variant(base, ["plan_decision", "requires_approval"], None) | {"approval": None})
    add("requires-approval-string-false", "requires_approval is the string 'false'",
        variant(base, ["plan_decision", "requires_approval"], "false") | {"approval": None})
    add("plan-allow-string", "plan_decision.allow is the string 'true'",
        variant(base, ["plan_decision", "allow"], "true"))
    add("plan-denied-but-approved", "The plan policy denied the plan but a valid approval exists",
        variant(base, ["plan_decision", "allow"], False))
    add("identity-missing", "Executing agent identity is missing", variant(base, ["execution", "agent"], _MISSING))
    # Known limits: the policy trusts what the executor supplies.
    add("backdated-clock", "The executor supplies a clock value before expiry for an expired approval",
        {**variant(base, ["execution", "now"], "2026-11-01T00:00:00Z"),
         "approval": {**a, "expires_at": "2026-11-15T00:00:00Z"}}, expected="allow-by-design")
    add("executor-claims-no-approval-needed", "The executor supplies requires_approval=false",
        variant(base, ["plan_decision", "requires_approval"], False) | {"approval": None}, expected="allow-by-design")
    return cat


# -------------------------------------------------- target: image_admission

IMG_DIGEST = "sha256:" + HEX_A
IMG_OTHER = "sha256:" + HEX_B
REPO = "registry.example/team/app"

IMG_BASE = {
    "image": {"reference": f"{REPO}@{IMG_DIGEST}"},
    "execution": {"agent": "deploy-agent", "requested_by": "alice", "now": NOW},
    "approval": {
        "image_digest": IMG_DIGEST,
        "agent": "deploy-agent",
        "requested_by": "alice",
        "approver": "bob",
        "expires_at": EXPIRES,
    },
}

# RE2's \s is ASCII whitespace only.
_IMG_REF = re.compile(r"([^@\t\n\f\r ]+)@(sha256:[0-9a-f]{64})")


def img_model(inp):
    """What the image approval policy is supposed to decide, restated independently."""
    ref = get(inp, "image", "reference")
    m = _IMG_REF.fullmatch(ref) if isinstance(ref, str) else None
    if not m:
        return False
    ex_agent = get(inp, "execution", "agent")
    ex_user = get(inp, "execution", "requested_by")
    if not (nonempty_str(ex_agent) and nonempty_str(ex_user)):
        return False
    ap = get(inp, "approval")
    if not isinstance(ap, dict):
        return False
    if ap.get("image_digest") != m.group(2):
        return False
    if ap.get("agent", _MISSING) is _MISSING or ap["agent"] != ex_agent:
        return False
    if ap.get("requested_by", _MISSING) is _MISSING or ap["requested_by"] != ex_user:
        return False
    if not approver_independent(ap.get("approver"), [ap["requested_by"], ap["agent"], ex_user, ex_agent]):
        return False
    expires, now = parse_time(ap.get("expires_at")), parse_time(get(inp, "execution", "now"))
    return expires is not None and now is not None and now < expires


def img_catalog():
    base, a = IMG_BASE, IMG_BASE["approval"]
    cat = []

    def add(i, d, inp, expected="deny"):
        cat.append({"id": i, "description": d, "input": inp, "expected": expected})

    ref = lambda r, approved=IMG_DIGEST: {**variant(base, ["image", "reference"], r),
                                          "approval": {**a, "image_digest": approved}}
    add("tag-only", "Mutable tag instead of a digest", ref(f"{REPO}:latest"))
    add("versioned-tag", "Versioned tag instead of a digest", ref(f"{REPO}:1.0"))
    add("different-digest", "Image digest differs from the approved digest", ref(f"{REPO}@{IMG_OTHER}"))
    add("digest-last-char", "Image digest differs from the approved digest by one character",
        ref(f"{REPO}@{IMG_DIGEST[:-1]}0"))
    add("uppercase-digest", "Both digests in uppercase hex",
        ref(f"{REPO}@sha256:{HEX_A.upper()}", f"sha256:{HEX_A.upper()}"))
    add("digest-trailing-newline", "Reference and approved digest end in a newline",
        ref(f"{REPO}@{IMG_DIGEST}\n", f"{IMG_DIGEST}\n"))
    add("digest-leading-space", "Reference has leading whitespace", ref(f" {REPO}@{IMG_DIGEST}"))
    add("whitespace-in-repo", "Reference has whitespace inside the repository part", ref(f"{REPO} x@{IMG_DIGEST}"))
    add("double-at", "Two @ separators, to hide a second digest", ref(f"{REPO}@{IMG_OTHER}@{IMG_DIGEST}"))
    add("sha512-digest", "A sha512 digest of the right length for sha256 tooling",
        ref(f"{REPO}@sha512:{HEX_A}{HEX_B}", f"sha512:{HEX_A}{HEX_B}"))
    add("short-digest", "Truncated digest", ref(f"{REPO}@sha256:{HEX_A[:32]}", f"sha256:{HEX_A[:32]}"))
    add("empty-repo", "Empty repository part", ref(f"@{IMG_DIGEST}"))
    add("approval-for-other-image", "Approval names a different image digest", ref(f"{REPO}@{IMG_DIGEST}", IMG_OTHER))
    add("self-approval-exact", "Requester is recorded as approver", variant(base, ["approval", "approver"], "alice"))
    add("self-approval-case-variant", "Requester approves their own change with different letter case",
        variant(base, ["approval", "approver"], "ALICE"))
    add("agent-approval-case-variant", "The agent is recorded as approver with different letter case",
        variant(base, ["approval", "approver"], "Deploy-Agent"))
    add("empty-approver", "Approver is an empty string", variant(base, ["approval", "approver"], ""))
    add("different-agent", "A different agent deploys the approved image",
        variant(base, ["execution", "agent"], "other-agent"))
    add("different-requester", "A different user is recorded as requester",
        variant(base, ["execution", "requested_by"], "mallory"))
    add("expired-at-boundary", "Deployed at the exact expiry instant", variant(base, ["execution", "now"], EXPIRES))
    add("expiry-unparseable", "Expiry is not a time", variant(base, ["approval", "expires_at"], "never"))
    add("expiry-no-timezone", "Expiry has no timezone", variant(base, ["approval", "expires_at"], "2026-12-01T13:00:00"))
    add("approval-missing", "No approval record", without(base, "approval"))
    add("approval-is-a-list", "Approval record is a list", variant(base, ["approval"], [a]))
    add("reference-missing", "No image reference", without(base, "image"))
    add("identity-missing", "Executing agent identity is missing", variant(base, ["execution", "agent"], _MISSING))
    add("backdated-clock", "The executor supplies a clock value before expiry for an expired approval",
        {**variant(base, ["execution", "now"], "2026-11-01T00:00:00Z"),
         "approval": {**a, "expires_at": "2026-11-15T00:00:00Z"}}, expected="allow-by-design")
    return cat


TARGETS = {
    "change_approval": {
        "policy": ROOT / "policies" / "change_approval" / "change_approval.rego",
        "package": "data.agentaccess.change_approval",
        "base": PLAN_BASE, "model": plan_model, "catalog": plan_catalog,
        "pool": [DIGEST_A, DIGEST_B],
    },
    "image_admission": {
        "policy": ROOT / "policies" / "image_admission" / "image_admission.rego",
        "package": "data.agentaccess.image_admission",
        "base": IMG_BASE, "model": img_model, "catalog": img_catalog,
        "pool": [IMG_DIGEST, IMG_OTHER, f"{REPO}@{IMG_DIGEST}", f"{REPO}@{IMG_OTHER}", f"{REPO}:latest"],
    },
}


# ------------------------------------------------------------------ fuzzer

def evaluate(opa, target, cases):
    """Evaluate the policy for every case in one OPA call."""
    query = "[a | some c in input.cases; a := " + target["package"] + ".allow with input as c]"
    proc = subprocess.run(
        [opa, "eval", "-f", "json", "-d", str(target["policy"]), "-I", query],
        input=json.dumps({"cases": cases}), capture_output=True, text=True,
    )
    if proc.returncode != 0:
        sys.exit("opa failed: " + proc.stderr.strip())
    return json.loads(proc.stdout)["result"][0]["expressions"][0]["value"]


JUNK = [None, 0, 1, True, False, "", [], {}, "false", "true", "null"]
CONFUSABLE = {"a": "а", "e": "е", "o": "о", "0": "O", "l": "1"}


def leaf_paths(d, prefix=()):
    for k, v in d.items():
        if isinstance(v, dict):
            yield from leaf_paths(v, prefix + (k,))
        else:
            yield prefix + (k,)


def mutate_string(rng, s, pool):
    ops = [
        lambda x: x.upper(), lambda x: x.lower(), lambda x: x.capitalize(),
        lambda x: " " + x, lambda x: x + " ", lambda x: x + "\n", lambda x: "​" + x,
        lambda x: x[:-1], lambda x: x + "0", lambda x: x * 2,
        lambda x: x[:-1] + ("0" if not x.endswith("0") else "1"),
        lambda x: "".join(CONFUSABLE.get(c, c) if rng.random() < 0.5 else c for c in x),
        lambda x: x.replace("-", "_"),
        lambda x: rng.choice(pool + ["alice", "bob", "deploy-agent", "mallory", NOW, EXPIRES]),
    ]
    return rng.choice(ops)(s)


def lookup(d, path):
    for k in path:
        d = d[k] if isinstance(d, dict) and k in d else None
    return d


def mutate(rng, base, pool):
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
            node[key] = mutate_string(rng, node[key], pool)
        elif op == "copy":
            node[key] = lookup(out, rng.choice(paths))
        elif op == "alias":
            # Another field's value, altered: how a spoofed or look-alike identity arises.
            src = lookup(out, rng.choice(paths))
            node[key] = mutate_string(rng, src, pool) if isinstance(src, str) else src
        elif op == "section":
            out[rng.choice(list(out.keys()))] = rng.choice([None, [], "x", {}])
    return out


def run_target(name, args, out_root):
    target = TARGETS[name]
    out = out_root / name if args.target == "all" else out_root
    out.mkdir(parents=True, exist_ok=True)
    model = target["model"]

    # 1. Named attacks.
    catalog = target["catalog"]()
    allowed = evaluate(args.opa, target, [c["input"] for c in catalog])
    catalog_results, catalog_failures = [], 0
    for c, got in zip(catalog, allowed):
        ok = got == (c["expected"] == "allow-by-design")
        catalog_failures += 0 if ok else 1
        catalog_results.append({"id": c["id"], "description": c["description"], "expected": c["expected"],
                                "policy_allowed": got, "model_allowed": model(c["input"]), "ok": ok})

    # 2. Seeded mutation fuzzing, and any candidates, against the model.
    cases = []
    for seed in range(args.seeds):
        rng = random.Random(seed)
        for _ in range(args.per_seed):
            cases.append({"source": f"fuzz-seed-{seed}", "input": mutate(rng, target["base"], target["pool"])})
    candidate_count = 0
    if args.candidates:
        for n, line in enumerate(Path(args.candidates).read_text().splitlines(), 1):
            if line.strip():
                cases.append({"source": f"candidate-line-{n}", "input": json.loads(line)})
                candidate_count += 1
    decisions = evaluate(args.opa, target, [c["input"] for c in cases])
    findings, false_refusals, both_allow = [], [], 0
    for c, got in zip(cases, decisions):
        want = model(c["input"])
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
        "target": f"policies/{name}", "source_commit": commit or None, "opa": opa_version,
        "seeds": args.seeds, "inputs_per_seed": args.per_seed, "candidate_inputs": candidate_count,
        "inputs_total": len(cases), "agreed_allow": both_allow,
        "security_findings": len(unique), "false_refusals": len(false_refusals),
        "catalog_attacks": len(catalog), "catalog_failures": catalog_failures, "catalog": catalog_results,
    }
    (out / "summary.json").write_text(json.dumps(summary, indent=2) + "\n")
    with (out / "transcripts.jsonl").open("w") as fh:
        for f in unique:
            fh.write(json.dumps({"kind": "security-finding", **f}) + "\n")
        for f in false_refusals[:50]:
            fh.write(json.dumps({"kind": "false-refusal", **f}) + "\n")

    print(f"[{name}] catalog: {len(catalog)} attacks, {catalog_failures} not as expected")
    for r in catalog_results:
        print(f"  {'ok ' if r['ok'] else 'FAIL'} {r['id']:<36} expected {r['expected']:<15} policy_allowed={r['policy_allowed']}")
    print(f"[{name}] fuzz: {len(cases)} inputs ({args.seeds} seeds x {args.per_seed}"
          f"{f' + {candidate_count} candidates' if candidate_count else ''}), "
          f"{len(unique)} distinct security findings, {len(false_refusals)} false refusals")
    for f in unique[:5]:
        print("  FINDING", f["source"], json.dumps(f["input"], sort_keys=True)[:300])
    return bool(unique or catalog_failures)


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--target", default="all", choices=[*TARGETS, "all"])
    ap.add_argument("--opa", default="opa")
    ap.add_argument("--seeds", type=int, default=20)
    ap.add_argument("--per-seed", type=int, default=300)
    ap.add_argument("--out", default=str(ROOT / "results" / "attack-harness"))
    ap.add_argument("--candidates", help="JSON lines of inputs proposed by an external attacker")
    args = ap.parse_args()
    names = list(TARGETS) if args.target == "all" else [args.target]
    failed = [run_target(n, args, Path(args.out)) for n in names]
    sys.exit(1 if any(failed) else 0)


if __name__ == "__main__":
    main()
