#!/usr/bin/env python3
"""Validate results.json against the schema and check that it can be trusted.

Usage: python scripts/validate_results.py [path/to/results.json]

Fails if the file does not match the schema, if any configuration or planned
case is missing, if any case differed from its expected outcome, or if the
summary counts disagree with the cases.
"""
import json
import sys
from pathlib import Path

from jsonschema import Draft202012Validator

ROOT = Path(__file__).resolve().parent.parent
REQUIRED_CASES = {
    "no-binding-baseline": {"approved-plan", "substituted-plan"},
    "approval-binding": {
        "approved-plan", "substituted-plan", "different-agent",
        "expired-approval", "self-approval", "no-approval",
    },
}
# Results that are expected for each configuration. A weak baseline that
# applies the substituted plan is expected; a control that does is a failure.
EXPECTED_PROTECTION = {
    "no-binding-baseline": {"substituted-plan": "not_held"},
    "approval-binding": {
        "substituted-plan": "held", "different-agent": "held",
        "expired-approval": "held", "self-approval": "held", "no-approval": "held",
    },
}


def main() -> int:
    path = Path(sys.argv[1]) if len(sys.argv) > 1 else ROOT / "results" / "results.json"
    schema = json.loads((ROOT / "schemas" / "evaluation-results.schema.json").read_text())
    data = json.loads(path.read_text())

    errors = [f"schema: {e.message} at {list(e.absolute_path)}"
              for e in Draft202012Validator(schema).iter_errors(data)]

    by_name = {c["configuration"]: c for c in data.get("configurations", [])}
    for name, required in REQUIRED_CASES.items():
        config = by_name.get(name)
        if config is None:
            errors.append(f"configuration missing: {name}")
            continue
        cases = {c["id"]: c for c in config["cases"]}
        for case_id in sorted(required):
            case = cases.get(case_id)
            if case is None:
                errors.append(f"{name}: case missing: {case_id}")
            elif case["status"] != "executed":
                errors.append(f"{name}: case not executed: {case_id}")
            elif not case["matched_expectation"]:
                errors.append(f"{name}: {case_id}: expected {case['expected_outcome']}, observed {case['observed_outcome']}")
        for case_id, want in EXPECTED_PROTECTION[name].items():
            case = cases.get(case_id)
            if case and case["status"] == "executed" and case["protection"] != want:
                errors.append(f"{name}: {case_id}: protection is {case['protection']}, expected {want}")
        executed = sum(1 for c in config["cases"] if c["status"] == "executed")
        if config["summary"]["executed"] != executed:
            errors.append(f"{name}: summary.executed disagrees with the cases")

    verdict = data.get("verdict", {})
    if not (verdict.get("all_configurations_present") and verdict.get("all_cases_executed")
            and verdict.get("all_matched_expectation")):
        errors.append(f"verdict is not clean: {verdict}")

    if errors:
        print("FAIL: results.json is not trustworthy")
        for e in errors:
            print(f"  - {e}")
        return 1
    held = sum(c["summary"]["protection_held"] for c in data["configurations"])
    not_held = sum(c["summary"]["protection_not_held"] for c in data["configurations"])
    print(f"OK: results valid; commit {data['source_commit'][:7]}; "
          f"protection held in {held} case(s), not held in {not_held} (expected: the baseline's substitution)")
    return 0


if __name__ == "__main__":
    sys.exit(main())
