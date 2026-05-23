# mod-lint

Static analysis for two recurring bug classes that have cost multiple
version bumps across the VT2 tweaker mods.

## Patterns caught

### 1. Duplicate VMF hook registration  (error, exit 2)

Per `VMF_RECIPES.md § hook_safe doesn't chain on same Class+method`: VMF silently drops the second
`mod:hook*` registration on the same `(class, method)` pair. The dropped
hook never fires, so the bundle ships broken in a way no error message
will surface. Burned cim v0.7.21 / v0.7.23 / v0.7.27 (see
`crafting_in_modded/CHANGELOG.md`).

The linter walks every `mod:hook(` / `mod:hook_safe(` / `mod:hook_origin(`
in a mod, including hooks registered from inside `for _, klass in
ipairs({ "A", "B" }) do ... end` loops (whose class list it expands by
reading the literal table — also follows
`local _LIT = { "A", "B" }; for ... ipairs(_LIT) ...`).

A finding lists the duplicated `(class, method)` plus every file:line that
registered against it.

### 2. Lua forward-reference bug  (warning, exit 1)

Per `PROJECT_STANDARDS.md § Pre-ship checklist` (Lua forward-ref class) — CRITICAL, 6 documented
crashes in cosmetics_tweaker alone (v0.7.1, v0.7.37, v0.7.39, v0.7.51,
v0.7.53, v0.8.39).

A closure that captures a `local function NAME` whose declaration appears
LATER in the same scope binds the name as `_ENV.NAME` (nil global) instead
of the local — and crashes at call time. The fix is either to move the
helper definition above the call site, or to add a bare `local NAME`
forward declaration near the top of the file.

The linter flags any top-level `local function NAME` (column-zero
declaration) whose name is referenced from a closure starting on an
earlier line, with no matching `local NAME` forward declaration above the
closure.

False-positive rate is kept low by:
- Only considering column-0 declarations (helpers defined inside another
  function's body are scoped there, not module-level).
- Skipping `obj.NAME` / `obj:NAME` table-access references (those resolve
  dynamically against a table, not against the closure's upvalue).
- Recognising explicit forward declarations (`local NAME` on its own
  line, no `=`, no `function`).

## Usage

```powershell
# scan every mod under the repo root
.\tools\mod-lint\lint-mod.ps1

# scan one mod (folder name, repo-relative path, or absolute path)
.\tools\mod-lint\lint-mod.ps1 -ModPath crafting_in_modded

# also emit JSON sidecar (default path: <repo>/.release-stage/mod-lint.json)
.\tools\mod-lint\lint-mod.ps1 -ModPath crafting_in_modded -Json

# emit JSON to a custom path
.\tools\mod-lint\lint-mod.ps1 -JsonPath C:\tmp\lint.json
```

## Exit codes

| Code | Meaning |
|------|---------|
| 0    | Clean — no findings |
| 1    | Warnings only (forward-ref candidates) — non-blocking |
| 2    | Errors (duplicate hooks) — `publish-release.ps1` aborts |

## Integration

`publish-release.ps1` runs the linter at the top of the script, before any
build. Exit code 2 aborts the release. Exit code 1 prints a warning and
continues.

## Test fixtures

`test_fixtures/sample_dupe_mod/` — synthetic mod that reproduces the three
cim v0.7.28 rehook patterns. Linter should report 4 duplicate-hook errors.

`test_fixtures/sample_forward_ref_mod/` — synthetic mod with a real
forward-ref pattern. Linter should report 1 forward-ref warning.

Both fixtures live outside the `$KnownMods` list in `lint-mod.ps1` so the
default no-argument scan does NOT include them.

## Known limitations

- Single-mod scope. Cross-mod hook collisions (`mod A` and `mod B` both
  hooking `Foo.bar`) are out of scope — VMF chains those correctly across
  mods.
- The closure-extent walker uses a keyword-balance heuristic, not a full
  Lua parser. It excludes `do` from openers because bare `do ... end`
  blocks are not used in any current VMB mod (confirmed empty grep at
  scaffold time). If a future mod adds bare-do blocks, swap in a proper
  Lua lexer.
- Forward-ref scan only inspects anonymous-closure bodies. References
  from inside a named `local function` to a later `local function` are
  not flagged directly, but the calling code path usually has at least
  one closure on the chain so the bug surfaces in practice.
