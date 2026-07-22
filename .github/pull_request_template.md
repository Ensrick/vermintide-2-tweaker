## Outcome

<!-- What changed for the player, contributor, or repository? Keep this concise. -->

Refs #
<!-- Use Refs only. Auto-closing keywords require a trusted issue-local closure receipt. -->

## Evidence

<!-- Reproduction, crash GUID/log line, source file:line, or measured repo state. -->

## Engine trace

Use `N/A` with a reason for documentation or repository-only work.

| Field | Finding |
|---|---|
| Vanilla entry point | `Class.function` — `file:line` |
| State owner | |
| Authority | Host / client / every peer / local UI / N/A |
| Runtime lifecycle | Registration / creation / update / RPC / teardown / UI render / N/A |
| Native seam | |
| Runtime unknown | |
| Test topology | One player / host + client / static only |

## Verification

- [ ] `./qa/run_all.ps1` completed; warnings or exceptions are summarized below.
- [ ] `./tools/mod-lint/lint-mod.ps1` completed for mod-code changes.
- [ ] A regression check would fail if this bug returned, or this is not a bug.
- [ ] Host/client coverage is included when the affected path is networked.
- [ ] MOD_VERSION, per-mod CHANGELOG, and owning docs were updated for a built mod change.
- [ ] No mod version was bumped for documentation-only work.
- [ ] No duplicate `(Class, method)` hook registration was introduced.
- [ ] No game, deployment, Workshop upload, or public release was performed without authorization.

### In-game or autonomous test

<!-- Exact command/repro and expected output. State what was not run and why. -->

## Issue lifecycle

Every open issue has exactly one lifecycle label: `not-started`,
`diagnostics-armed`, or `verify-fix`. A ready issue requires a strict
`## CURRENT LIVE TEST` comment; the newest exact card must be the only pinned
exact card. Complete useful solo testing before adding `coop-required` for a
remaining co-op test. Blocked, partial, documentation, and tooling work stays
`not-started`. `Fixed` and `verify-fix-coop` are invalid while open. After
verification, complete hardening/documentation/regression coverage and close.

## Risks and rollback

<!-- Authority mismatch, lifecycle timing, compatibility, data migration, or N/A. -->
