# Contributing

Thanks for your interest. The project is early, so design feedback is as valuable as code.

## Before you start

For anything beyond a small fix, open an issue first to describe the problem and the change you propose.

## Making changes

- **Policies:** every change to a policy in `policies/` needs a unit test. Run `opa test policies/ -v` (OPA v1.x) before opening a pull request.
- **Control catalog:** add or change controls in `controls/catalog.yaml`, then run `python scripts/validate_catalog.py`.
- **Docs:** keep the threat model and architecture in step with the catalog.

## Pull requests

- Keep each pull request focused on one change.
- Describe what changed and why, and link the related issue.
- CI must pass before review.

By contributing, you agree that your contributions are licensed under the Apache License 2.0.
