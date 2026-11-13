"""Validate authorization decision records against the decision-record schema.

With no arguments, checks that:
  * the schema is itself a valid JSON Schema;
  * the schema's list of denial reasons matches the reasons in
    policies/tool_authz/tool_authz.rego, so the two cannot drift apart;
  * every record in examples/audit/ is valid;
  * every record in examples/audit/invalid/ is rejected.

With file arguments, also validates each file. A file may hold one record, or
the JSON output of `opa eval -f json` for the decision rule.

Exits non-zero on any error.
"""

import json
import re
import sys
from pathlib import Path

from jsonschema import Draft202012Validator

ROOT = Path(__file__).resolve().parent.parent
SCHEMA = ROOT / "schemas" / "decision-record.schema.json"
POLICY = ROOT / "policies" / "tool_authz" / "tool_authz.rego"
EXAMPLES = ROOT / "examples" / "audit"
REASON_PATTERN = re.compile(r'^deny_reasons contains "([^"]+)"', re.MULTILINE)


def unwrap(doc):
    """Return the decision record from either a bare record or OPA eval output."""
    if isinstance(doc, dict) and "result" in doc:
        try:
            return doc["result"][0]["expressions"][0]["value"]
        except (KeyError, IndexError, TypeError) as exc:
            raise ValueError(f"unrecognised opa eval output: {exc!r}") from exc
    return doc


def check_record(validator: Draft202012Validator, path: Path) -> list[str]:
    try:
        record = unwrap(json.loads(path.read_text()))
    except (OSError, ValueError) as exc:
        return [f"{path}: cannot read record: {exc}"]
    errors = sorted(validator.iter_errors(record), key=lambda e: list(e.path))
    return [f"{path}: {'/'.join(map(str, e.path)) or '(record)'}: {e.message}" for e in errors]


def check_schema_matches_policy(schema: dict) -> list[str]:
    in_schema = set(schema["properties"]["reasons"]["items"]["enum"])
    in_policy = set(REASON_PATTERN.findall(POLICY.read_text()))
    errors = []
    for reason in sorted(in_policy - in_schema):
        errors.append(f"policy reason missing from schema: {reason!r}")
    for reason in sorted(in_schema - in_policy):
        errors.append(f"schema reason not produced by policy: {reason!r}")
    return errors


def main(argv: list[str]) -> int:
    schema = json.loads(SCHEMA.read_text())
    Draft202012Validator.check_schema(schema)
    validator = Draft202012Validator(schema)

    errors = check_schema_matches_policy(schema)

    valid = sorted(EXAMPLES.glob("*.json"))
    invalid = sorted((EXAMPLES / "invalid").glob("*.json"))
    if not valid or not invalid:
        errors.append("examples/audit/ needs at least one valid and one invalid example")

    for path in valid:
        errors += check_record(validator, path)
    for path in invalid:
        if not check_record(validator, path):
            errors.append(f"{path}: expected the schema to reject this record")
    for name in argv:
        errors += check_record(validator, Path(name))

    for error in errors:
        print(f"ERROR {error}")
    if errors:
        return 1
    print(
        f"OK: schema valid and in sync with policy; "
        f"{len(valid)} valid and {len(invalid)} invalid examples behave as expected"
        + (f"; {len(argv)} extra file(s) valid" if argv else "")
    )
    return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
