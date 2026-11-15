# ADR 0001: rig launch, machine evidence, no manual cards

Date: 2026-11-13. Status: accepted (owner decisions, `docs/program/PLAN.md` section 3).

## Decisions

1. The only permitted game launch is the unattended rig, `tools/harness/run.ps1`: isolated profile, private desktop, one instance at a time. Any other launch stays forbidden, and nobody restarts Steam.
2. Issues of evidence class U, S or R close on machine evidence. Class V and C go to the human list and never block other work.
3. Manual `## CURRENT LIVE TEST` cards are stopped: no new card, no pin, no unpin, no edit, and no lifecycle label change by hand.

## Evidence classes

| Class | Evidence | Closes on machine evidence |
|---|---|---|
| U | engine-free unit test under `qa/lua/tests` | yes |
| S | static check | yes |
| R | rig run that reads engine state and asserts | yes |
| V | needs human eyes or ears | no |
| C | needs two real clients | no |
| X | blocked or owner decision | no |

## Reporting

A PASS is reported exactly as: `auto-verified (<class>) on <mod> <version> <commit>, run <id>`.

A rig PASS is never reported as "works".

## Closure receipt

`qa/check_pr_autoclose.ps1` accepts a trusted `## CLOSURE AUTHORIZATION` issue comment bound to the PR (`Authorized PR: #<n>`) when it carries either `Verification: user-confirmed`, or all of:

```
Verification: machine-evidence
Evidence class: <U, S or R>
Result: PASS
Spec: qa/specs/issue_<N>.json
Run: <run id>
```
