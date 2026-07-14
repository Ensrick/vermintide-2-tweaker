# Weapons of Chaos — Postmortems

Incident writeups for bugs whose diagnosis taught a reusable lesson. Fix detail
lives in `CHANGELOG.md`; reusable patterns are promoted to
`docs/BUG_CLASSES.md`. Newest first.

---

## #595 — Startup crash from a source-only wire-policy helper

- **Detected:** 2026-07-14, WOC v0.1.11-dev.
- **Crash GUID:** `5906f1d7-ed94-444b-8f61-832ee17c1e49`.
- **Fix build:** WOC v0.1.12-dev.

### Symptom
The game reached initial keep player spawn, then crashed in
`weapons_of_chaos.lua:_wire_safe_item` with `attempt to index upvalue
_wire_policy (a nil value)`. Earlier in the same log, VMF reported that
`scripts/mods/weapons_of_chaos/_woc_wire_policy.lua` was not a resource.

### Root cause
v0.1.11-dev extracted wire logic into `_woc_wire_policy.lua` and added offline
tests that loaded the loose source file directly. WOC's resource package used an
explicit three-file Lua list and was not updated, so VMB correctly compiled only
those three files. The Workshop bundle therefore differed materially from the
source tree the tests exercised. VMF contained the failed dofile, but the later
loadout hook assumed a table and converted the packaging omission into a startup
crash.

### Prevention
- WOC's package now explicitly includes `_woc_wire_policy`.
- The module load validates both the table and `safe_item` function. On failure,
  vanilla items pass unchanged and explicit `woc_` items fail closed.
- The blocking Quick gate `check_dofile_package_coverage.ps1` audits every
  literal dofile in all canonical active mods against source and package lists.
- The built v0.1.12-dev bundle was independently listed: Murmur64
  `DFB5217E81413589` for `_woc_wire_policy` is present as a compiled Lua entry.
- BUG_CLASSES class 45 records the cross-mod diagnosis and fix template.
