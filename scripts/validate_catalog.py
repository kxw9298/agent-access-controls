"""Validate controls/catalog.yaml.

Checks required fields, ID format and uniqueness, allowed values, OWASP item
IDs, and that implementation paths exist. Exits non-zero on any error.
"""

import re
import sys
from pathlib import Path

import yaml

ROOT = Path(__file__).resolve().parent.parent
CATALOG = ROOT / "controls" / "catalog.yaml"

REQUIRED = ("id", "title", "objective", "enforcement", "owasp_llm_2025", "status")
STATUSES = {"planned", "partial", "implemented"}
ENFORCEMENT = {
    "gateway",
    "network",
    "identity-provider",
    "policy-decision-point",
    "audit-log",
    "content-filter",
}
ID_PATTERN = re.compile(r"^AAC-[A-Z]{2}-\d{2}$")
OWASP_PATTERN = re.compile(r"^LLM(0[1-9]|10)$")


def validate(catalog: dict) -> list[str]:
    errors = []
    controls = catalog.get("controls")
    if not isinstance(controls, list) or not controls:
        return ["catalog must contain a non-empty 'controls' list"]

    seen = set()
    for i, control in enumerate(controls):
        where = control.get("id", f"controls[{i}]")
        for field in REQUIRED:
            if field not in control:
                errors.append(f"{where}: missing field '{field}'")

        cid = control.get("id", "")
        if not ID_PATTERN.match(cid):
            errors.append(f"{where}: id must match AAC-XX-NN")
        if cid in seen:
            errors.append(f"{where}: duplicate id")
        seen.add(cid)

        if control.get("status") not in STATUSES:
            errors.append(f"{where}: status must be one of {sorted(STATUSES)}")

        for point in control.get("enforcement", []):
            if point not in ENFORCEMENT:
                errors.append(f"{where}: unknown enforcement point '{point}'")

        for item in control.get("owasp_llm_2025", []):
            if not OWASP_PATTERN.match(item):
                errors.append(f"{where}: invalid OWASP item '{item}'")

        impl = control.get("implementation")
        if control.get("status") in {"partial", "implemented"} and not impl:
            errors.append(f"{where}: status '{control['status']}' needs an implementation path")
        if impl and not (ROOT / impl).exists():
            errors.append(f"{where}: implementation path '{impl}' does not exist")

    return errors


def main() -> int:
    catalog = yaml.safe_load(CATALOG.read_text())
    errors = validate(catalog)
    for error in errors:
        print(f"ERROR {error}")
    if errors:
        return 1
    print(f"OK: {len(catalog['controls'])} controls valid")
    return 0


if __name__ == "__main__":
    sys.exit(main())
