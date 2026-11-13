# External review template

For someone who has run or read this project and wants to record findings. Write it in your own words. Leave a section blank or write "not done" rather than guess. Nothing here asks you to endorse the project.

## Reviewer

- Name and affiliation (or a handle, if you prefer):
- Relevant experience, in a sentence or two:
- Relationship to the maintainer, if any (colleague, client, friend, none), and whether you were asked or paid to review:

## What you reviewed

- Release tag or commit:
- Environment (operating system, Docker version, or native tool versions):
- Date of review:

## What you personally ran

Mark each as run, read only, or not done.

| Item | Run / read only / not done |
| --- | --- |
| Baseline: approved-plan, substituted-plan | |
| Approval binding: approved-plan | |
| Approval binding: substituted-plan | |
| Approval binding: different-agent | |
| Approval binding: expired-approval | |
| Approval binding: self-approval | |
| Approval binding: no-approval | |
| Reference GitHub Actions pipeline | |
| Source or policies (Rego) | |
| Documentation only | |

## Observed results

- Did every case behave as the quickstart says? List any that did not, with the `results.json` entry or output.
- Did you try anything beyond the listed cases? What, and what happened?

## Limitations you found

Ways the demonstrations or the design could mislead, gaps in what is tested, and attacks or setups that are not covered.

## Usefulness

- Would this control fit a pipeline you know? What would have to change?
- How does it compare, from your own experience, with what teams use today? Say which tools and settings, and whether you tested them.
- What would you want to see before relying on it?

## Anything else

Reproduction steps for problems should go in an issue. Security problems go through [SECURITY.md](../SECURITY.md), not a public issue or this form.
