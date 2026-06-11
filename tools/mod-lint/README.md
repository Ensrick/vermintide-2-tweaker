# mod-lint

Static analysis for recurring bug classes that have cost multiple
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

### 3. Late local shadows global  (warning, exit 1; error under `-Strict`)

Per memory `feedback_lua_forward_reference.md` and the v0.7.99-dev ct fix (chest-of-trials crash, GUID `4c5d2157-e5ee-45fd-8f49-ecdcd2e7ade3`).

A top-level `local NAME = <table-or-value>` declared LATE in the file while
function bodies / closures EARLIER in the file reference `NAME`. Lua scope
is LEXICAL — every earlier reference resolves to `_G.NAME` (typically nil)
at function-definition time, NOT the late local. Symptom: silent until the
referencing closure runs (e.g. first chest interaction), then `attempt to
index a nil value`.

This is a SEPARATE bug class from check 2 (forward-ref):

- Check 2 fires on `local function NAME(...)` defined late with calls earlier — about FUNCTIONS.
- Check 3 fires on `local NAME = <table-or-value>` declared late with reads earlier — about DATA TABLES / non-function locals.

Heuristic to keep false-positive rate near zero: only `ALL_CAPS_SNAKE` names
are flagged. By convention in this repo, capitalized names are reserved for
module-level data tables; functions use lowercase_snake (already covered by
check 2). A future generalization could widen the heuristic, but for now
this is enough — both the ct DORMANT_BOON_RARITY bug and the most likely
future regressions fit the ALL_CAPS_SNAKE shape.

Each finding lists the late local's declaration line, the earliest earlier
reference (file:line), and whether that reference sits inside a function
body (closure semantics — captures _G.NAME at definition time) or at
top-level code (would crash immediately at load).

Emitted as WARNING by default; pass `-Strict` to promote to error (exit 2),
which also blocks `publish-release.ps1`.

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

# promote forward-ref + late-local + save/restore warnings to errors
.\tools\mod-lint\lint-mod.ps1 -Strict

# verify the linter against its built-in fixtures
.\tools\mod-lint\lint-mod.ps1 -SelfTest
```

## Exit codes

| Code | Meaning |
|------|---------|
| 0    | Clean — no findings |
| 1    | Warnings only (forward-ref / late-local / save-restore candidates) — non-blocking |
| 2    | Errors (duplicate hooks; with `-Strict`, also forward-ref + late-local + save/restore) — `publish-release.ps1` aborts |

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

The `late-local-shadows-global` check has an in-memory self-test that
synthesizes its fixtures programmatically (the bug only reproduces when the
local is declared many lines below the earliest reference; a fixture file
that small would be artificial). Run with `.\lint-mod.ps1 -SelfTest`.
Coverage: bad case where closure at L4 references `MY_TABLE` declared at
L100; good case where local declared at L10 with closure ref at L100; good
case for the canonical `local foo; function foo() end` forward-decl
pattern; bad top-level executable case; good cases for comment / string /
field-access false-positive guards.

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
