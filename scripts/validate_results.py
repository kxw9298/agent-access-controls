#!/usr/bin/env python3
"""Validate results.json against the schema and check that it can be trusted.

Usage: python scripts/validate_results.py [path/to/results.json]

Fails if the file does not match the schema; if a configuration or scenario
from evaluation/scenarios.json is missing; if a case was not executed when it
should have been, or is reported unsupported when it should not be; if a case
differed from its expected outcome or its expected protection result; or if the
summary counts disagree with the cases.

Expected protection results are fixed here on purpose. A weak baseline that
applies a substituted plan is expected. A control that does is a failure, and
an "unsupported" scenario cannot stand in for one that should have run.
"""
import json
import sys
from pathlib import Path

from jsonschema import Draft202012Validator

ROOT = Path(__file__).resolve().parent.parent

# configuration -> {scenario: "held" | "not_held" | "not_applicable" | "unsupported"}
EXPECTED = {
    "no-binding-baseline": {
        "approved-plan": "not_applicable",
        "substituted-plan": "not_held",
        "replan-after-approval": "not_held",
        "different-agent": "not_held",
        "expired-approval": "not_held",
        "self-approval": "not_held",
        "no-approval": "held",
    },
    "hardened-baseline-model": {
        "approved-plan": "not_applicable",
        "substituted-plan": "held",
        "replan-after-approval": "held",
        "different-agent": "unsupported",
        "expired-approval": "unsupported",
        "self-approval": "held",
        "no-approval": "held",
    },
    "approval-binding": {
        "approved-plan": "not_applicable",
        "substituted-plan": "held",
        "replan-after-approval": "held",
        "different-agent": "held",
        "expired-approval": "held",
        "self-approval": "held",
        "no-approval": "held",
    },
}
KINDS = {
    "no-binding-baseline": "model",
    "hardened-baseline-model": "model",
    "approval-binding": "implementation",
}


def main() -> int:
    path = Path(sys.argv[1]) if len(sys.argv) > 1 else ROOT / "results" / "results.json"
    schema = json.loads((ROOT / "schemas" / "evaluation-results.schema.json").read_text())
    scenarios = [s["id"] for s in json.loads((ROOT / "evaluation" / "scenarios.json").read_text())["scenarios"]]
    data = json.loads(path.read_text())

    errors = [f"schema: {e.message} at {list(e.absolute_path)}"
              for e in Draft202012Validator(schema).iter_errors(data)]
    if errors:
        print("FAIL: results.json does not match the schema")
        for e in errors:
            print(f"  - {e}")
        return 1

    for name, expected in EXPECTED.items():
        if sorted(expected) != sorted(scenarios):
            errors.append(f"internal: expectations for {name} do not match evaluation/scenarios.json")

    by_name = {c["configuration"]: c for c in data["configurations"]}
    for name, expected in EXPECTED.items():
        config = by_name.get(name)
        if config is None:
            errors.append(f"configuration missing: {name}")
            continue
        if config["kind"] != KINDS[name]:
            errors.append(f"{name}: kind is {config['kind']}, expected {KINDS[name]}")
        cases = {c["id"]: c for c in config["cases"]}
        if sorted(cases) != sorted(scenarios):
            errors.append(f"{name}: cases do not match the scenario manifest")
        for sid in scenarios:
            case = cases.get(sid)
            want = expected[sid]
            if case is None:
                errors.append(f"{name}: scenario missing: {sid}")
            elif want == "unsupported":
                if case["status"] != "unsupported":
                    errors.append(f"{name}: {sid}: expected unsupported, status is {case['status']}")
            elif case["status"] != "executed":
                errors.append(f"{name}: {sid}: expected to be executed, status is {case['status']}")
            else:
                if not case["matched_expectation"]:
                    errors.append(f"{name}: {sid}: expected {case['expected_outcome']}, observed {case['observed_outcome']}")
                if case["protection"] != want:
                    errors.append(f"{name}: {sid}: protection is {case['protection']}, expected {want}")
        counts = {
            "planned": len(config["cases"]),
            "executed": sum(c["status"] == "executed" for c in config["cases"]),
            "unsupported": sum(c["status"] == "unsupported" for c in config["cases"]),
            "not_executed": sum(c["status"] == "not_executed" for c in config["cases"]),
            "protection_held": sum(c.get("protection") == "held" for c in config["cases"]),
            "protection_not_held": sum(c.get("protection") == "not_held" for c in config["cases"]),
        }
        for key, value in counts.items():
            if config["summary"][key] != value:
                errors.append(f"{name}: summary.{key} is {config['summary'][key]}, cases say {value}")

    verdict = data["verdict"]
    if not (verdict["all_configurations_present"] and verdict["all_cases_executed"]
            and verdict["all_matched_expectation"]):
        errors.append(f"verdict is not clean: {verdict}")

    if errors:
        print("FAIL: results.json is not trustworthy")
        for e in errors:
            print(f"  - {e}")
        return 1
    held = sum(c["summary"]["protection_held"] for c in data["configurations"])
    not_held = sum(c["summary"]["protection_not_held"] for c in data["configurations"])
    unsupported = sum(c["summary"]["unsupported"] for c in data["configurations"])
    print(f"OK: results valid; commit {data['source_commit'][:7]}; protection held in {held} case(s), "
          f"not held in {not_held} (expected for the weak baseline), unsupported in {unsupported}")
    return 0


if __name__ == "__main__":
    sys.exit(main())
