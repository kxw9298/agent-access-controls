#!/usr/bin/env python3
"""Render the comparison table from results.json.

Usage:
  python scripts/render_comparison.py results/results.json            # print the table
  python scripts/render_comparison.py results/results.json --write docs/evaluation.md
  python scripts/render_comparison.py results/results.json --check docs/evaluation.md

--write replaces the text between the comparison markers in the given file.
--check exits non-zero if that text differs from the rendered table, so the
published table cannot drift from the results.
"""
import json
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
START = "<!-- comparison:start -->"
END = "<!-- comparison:end -->"
ORDER = ["no-binding-baseline", "hardened-baseline-model", "approval-binding"]
HEADINGS = {
    "no-binding-baseline": "No-binding baseline (model)",
    "hardened-baseline-model": "Hardened baseline (model)",
    "approval-binding": "Approval binding (this project)",
}


def cell(case: dict) -> str:
    if case["status"] == "unsupported":
        return "Unsupported"
    if case["protection"] == "not_applicable":
        return "Applied (benign case)" if case["observed_outcome"] == "applied" else "Blocked (benign case)"
    return "Held" if case["protection"] == "held" else "**Not held**"


def render(results: dict) -> str:
    manifest = json.loads((ROOT / "evaluation" / "scenarios.json").read_text())["scenarios"]
    by_name = {c["configuration"]: {k["id"]: k for k in c["cases"]} for c in results["configurations"]}
    lines = ["| Scenario | " + " | ".join(HEADINGS[n] for n in ORDER) + " |",
             "| --- | " + " | ".join("---" for _ in ORDER) + " |"]
    for s in manifest:
        lines.append(f"| {s['name']} | " + " | ".join(cell(by_name[n][s["id"]]) for n in ORDER) + " |")
    return "\n".join(lines)


def replace_region(text: str, table: str) -> str:
    if START not in text or END not in text:
        raise SystemExit(f"markers {START} and {END} not found")
    head, rest = text.split(START, 1)
    _, tail = rest.split(END, 1)
    return f"{head}{START}\n{table}\n{END}{tail}"


def main() -> int:
    args = sys.argv[1:]
    if not args:
        print(__doc__)
        return 2
    results = json.loads(Path(args[0]).read_text())
    table = render(results)
    if len(args) == 1:
        print(table)
        return 0
    mode, target = args[1], Path(args[2])
    text = target.read_text()
    updated = replace_region(text, table)
    if mode == "--write":
        target.write_text(updated)
        print(f"updated {target}")
        return 0
    if mode == "--check":
        if updated != text:
            print(f"FAIL: the comparison table in {target} does not match the results.")
            print("Run: python scripts/render_comparison.py results/results.json --write " + str(target))
            return 1
        print(f"OK: comparison table in {target} matches the results")
        return 0
    print(__doc__)
    return 2


if __name__ == "__main__":
    sys.exit(main())
