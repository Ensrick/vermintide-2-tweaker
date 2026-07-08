# regression-lint

> **[SUPERSEDED 2026-07-07]** This is an ad-hoc EXPLORER / scanner, **not** the
> enforced gate. The WIRED pre-commit / pre-deploy lint gate is
> **`tools/mod-lint/lint-mod.ps1`** (installed by `tools/install-hooks.ps1`, see
> that directory's `README.md`). `regression-lint.ps1` here is run by hand for
> exploratory sweeps; it does not block any commit or deploy on its own. Wording
> below that implies it "refuses to deploy" describes the pattern, not a live hook.

Ad-hoc static scanner for the vermintide-2-tweaker monorepo. Sweeps every mod's
`scripts/` for patterns that have shipped as recurring crashes (each check is
sourced from a memory note or CHANGELOG incident; see citations per check below)
and reports an error for any hit.

Read-only — never writes into mod source. Run it by hand; it is not the wired gate.

## Run

```powershell
# scan all 16 mods, all checks
pwsh -File .\tools\lint\regression-lint.ps1

# scope to one mod (bare name, repo-relative path, or absolute path)
pwsh -File .\tools\lint\regression-lint.ps1 -Mod weapon_tweaker

# scope to one check
pwsh -File .\tools\lint\regression-lint.ps1 -Check forward-ref

# fail on warnings too (CI gate)
pwsh -File .\tools\lint\regression-lint.ps1 -WarningsAsErrors

# only show failing mods + summary
pwsh -File .\tools\lint\regression-lint.ps1 -Quiet

# verify the linter itself
pwsh -File .\tools\lint\regression-lint.ps1 -SelfTest
```

Exit code: `0` clean (errors=0, or warnings=0 when `-WarningsAsErrors` set);
`1` errors found or self-test failed.

## Mods scanned

The set is **dynamic**: anything in the repo root that has an `itemV2.cfg`. As of
2026-07-07 that resolves to the live single/stable mods —
`weapon_tweaker`, `chaos_wastes_tweaker`, `general_tweaker`, `gui_tweaker`,
`cosmetics_tweaker`, `dynamic_cosmetic_portraits`, `career_tweaker`,
`enemy_tweaker`, `weapons_of_chaos`, `character_weapon_variants`,
`crafting_in_modded`, `event_tweaker`, `modded_progression`,
`verminious_dreams_lighting` — plus the `_dev` clones that carry their own cfg
(`chaos_wastes_tweaker_dev`, `crafting_in_modded_dev`, `general_tweaker_dev`,
`gui_tweaker_dev`, `verminious_dreams_lighting_dev`, and the stale
`weapon_tweaker_dev`). The canonical mod list is the repo-root `CLAUDE.md`
"Mod Directory".

> **[SUPERSEDED 2026-07-07]** The old list here named `lobby_tweaker` and
> `buff_tweaker` (both RETIRED — now under `_archive/lobby_tweaker_v0.1.7-dev/`
> and `_archive/buff_tweaker_v0.1.12-alpha/`, so no cfg in the repo root and
> not scanned) and `material_hijack_patched` (never existed in this repo).
> Those are dropped above.

The deprecated `tweaker/` SDK mod is excluded (no `itemV2.cfg` in the VMB sense).

## Checks

| Check                    | Severity | What it catches                                                                                   |
|--------------------------|----------|---------------------------------------------------------------------------------------------------|
| `forward-ref`            | error    | Closure captures a name whose `local function NAME` definition appears later in the same chunk, with no `local NAME` forward declaration above. Lua sees the name as nil global at call time. |
| `unescaped-percent`      | error    | Localization strings (`*_localization.lua`) containing a single `%` not escaped to `%%`. `Localize` formats via `string.format`; a stray `%` swallows the next character. |
| `hook-safe-duplicate`    | error    | The same `(Class, method)` pair appears in multiple `mod:hook` / `mod:hook_safe` / `mod:hook_origin` calls. VMF silently drops the 2nd registration. Whitelist with `-- LINT_OK_REHOOK: <reason>` on a nearby line. |
| `unit-actor-zero-index`  | error    | `for i = 0, ...` loop within 3 lines of `Unit.actor` or `Unit.num_actors`. Stingray actor indices are 1-based. |
| `strict-table-lookup`    | error    | `BuffTemplates[name]` or `NetworkLookup.<lookup>[name]` outside `rawget(...)`. These tables install a strict `__index = error()` metatable; a missing-key check without `rawget` crashes. |
| `lua-200-locals`         | warn/err | Top-level `local` declaration count >= 180 (warn) or >= 200 (error, Lua 5.1 hard cap per chunk). |
| `base-class-hook`        | warning  | Hooks `HeroPreviewer.equip_item` / `_spawn_item` / `spawn_units` but not the same method on `MenuWorldPreviewer`. VT2's `class()` helper copies parent methods at boot — hooks on the base never fire on the derived class. |
| `dropdown-options-reuse` | warning  | The same `_<NAME>_OPTIONS` table is used by more than one widget in `<mod>.lua`. A runtime mutation (e.g. localization refresh) leaks across widgets. |

### Source citations

Each check's "why" is rooted in a documented prior incident:

- `forward-ref` — `feedback_lua_forward_reference.md`; cosmetics_tweaker shipped this 6 times. Cross-link: `feedback_pre_deploy_checklist.md`.
- `unescaped-percent` — wt v0.12.63, crt v0.2.36, et v0.5.2, gt v0.2.35, ct v0.7.79, lobby_tweaker v0.1.1.
- `hook-safe-duplicate` — `feedback_vmf_hook_safe_no_chain.md`, `reference_ct_husk_hook_shadow_tpe.md`. cim v0.7.21 / .23 / .27 and ct v0.9.0.5 → .10 burned this.
- `unit-actor-zero-index` — `reference_vt2_unit_actor_one_indexed.md`.
- `strict-table-lookup` — `reference_vt2_strict_lookup_rawget.md`; career_tweaker v0.3.4 incident.
- `lua-200-locals` — `reference_vt2_lua_200_locals.md`.
- `base-class-hook` — `feedback_vt2_class_hook_derived.md`, `feedback_inventory_preview_hook_menuworldpreviewer.md`; weapon_tweaker v0.12.16 → fixed v0.12.17.
- `dropdown-options-reuse` — `feedback_vmf_dropdown_options_mutated.md`; enemy_tweaker v0.4.x.

## Output format

```
regression-lint: scanning 16 mod(s)

[mod] weapon_tweaker
  forward-ref: weapon_tweaker\scripts\mods\weapon_tweaker\weapon_tweaker.lua:794 -- closure references local fn 'has' defined later at line 3211 (no forward decl)

[mod] chaos_wastes_tweaker
  OK

...

45 error(s), 0 warning(s)
```

Errors are red, warnings yellow, OK green. Summary at the bottom.

## Whitelist comments

`hook-safe-duplicate` is the only check that supports an in-code override.
Add `-- LINT_OK_REHOOK: <reason>` on the same line as the second hook, or
within 2 lines above/below. Example:

```lua
mod:hook("Foo", "bar", function() ... end)
-- LINT_OK_REHOOK: deliberately re-hook a broken upstream handler (e.g. an LA helper)
mod:hook_safe("Foo", "bar", function() ... end)
```

Use sparingly — the whole point of the check is to catch silent-no-op
re-hooks that ship as bugs.

## Adding a new check

1. Pick a name (lowercase-hyphen-separated, e.g. `network-channel-mismatch`).
2. Add the name to `$Script:AllChecks` near the top of `regression-lint.ps1`.
3. Implement a function `Invoke-Check-<PascalName>` that takes either
   - `[string]$File, [string[]]$Lines` for a per-file check, or
   - `[array]$Files` for a cross-file check.
   Use `$f.StrippedLines` (comments + string bodies blanked) for code-pattern
   scans, `$f.CommentStrippedLines` (only comments blanked) when you need to
   read literal string contents (`"ClassName"` etc.).
4. Yield findings via `New-Finding -Severity error|warning -Check <name>
   -File $path -Line $n -Message "..."`.
5. Wire it into the dispatch block in `Lint-Mod` (per-file or mod-level
   section, matching the function signature).
6. Add a synthetic bad+good case in `Invoke-SelfTest` and verify
   `-SelfTest` still reports `PASS (N/N)`.
7. Document the check in this README — what it covers, severity, source
   citation (memory note or CHANGELOG incident).

## Performance

The check is a pre-deploy gate that runs in ~11-13 seconds on a SSD for all
16 mods. The dominant cost is the `forward-ref` closure-end walker on the
two ~9000-line files (`character_weapon_variants.lua`,
`chaos_wastes_tweaker.lua`). Comment / string blanking is delegated to a
compiled C# helper (`VT2LintHelpers`) to avoid 1.2s/file PowerShell-side
regex overhead.

To skip the slow check during interactive dev: pass `-Check <fast-check>`
to run only one of the cheaper checks. `forward-ref` is the only one that
takes more than a second per file.

## CI integration

**The wired pre-commit gate is `tools/mod-lint/lint-mod.ps1`, not this script.**
`tools/install-hooks.ps1` installs the pre-commit hook that runs
`qa/run_all.ps1 -Quick -SkipLua` and `tools/mod-lint/lint-mod.ps1` against staged
files (blocks on errors only). This `regression-lint.ps1` is an exploratory
scanner and is **not** part of that hook.

If you want to run this explorer as an extra manual/optional check, invoke it
directly:

```powershell
& "$repoRoot\tools\lint\regression-lint.ps1" -Quiet
if ($LASTEXITCODE -ne 0) { throw "regression-lint reported errors" }
```

Don't wire it as a second blocking gate without deduplicating against
`tools/mod-lint/lint-mod.ps1` — the two overlap (both cover the duplicate-hook /
forward-ref classes).
