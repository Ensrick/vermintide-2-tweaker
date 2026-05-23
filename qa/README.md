# qa/

Automated quality-assurance checks for the VT2 Tweaker monorepo. Runs locally
or in CI.

**Read first**: [PROJECT_STANDARDS.md](../PROJECT_STANDARDS.md) — the
operational rulebook. **Then**: [CHECKS.md](CHECKS.md) — the comprehensive
bug-class-to-detection map.

## TL;DR

```powershell
# From repo root:
.\qa\run_all.ps1                    # everything (luacheck + scripts + docs)
.\qa\run_all.ps1 -Quick             # cfg + versions only (~3 seconds)
.\qa\run_all.ps1 -SkipLua           # if luacheck not installed locally
.\qa\run_all.ps1 -FixStale          # auto-banner stale audit docs
```

## What runs

| Check | Catches | Speed | CI |
|---|---|---|---|
| `check_cfg.ps1`         | `tags=[]`, missing preview, wrong visibility, missing BMC/bug-report blocks | <1s | ✓ |
| `check_versions.ps1`    | Missing `MOD_VERSION`, cfg title doesn't match version, no CHANGELOG entry | <2s | ✓ |
| `check_localization.ps1`| Unescaped `%`, referenced-but-undefined keys, missing `mod_description` | <3s | ✓ |
| `check_file_sizes.ps1`  | Files over 1500-line target / 2500-line hard limit | <1s | ✓ |
| `check_stale_docs.ps1`  | Audit/review markdowns >30 days old without SUPERSEDED banner | <1s | ✓ |
| `luacheck`              | Forward-references, unused vars, undefined globals, Lua 5.1 syntax issues | <10s | ✓ |

Total runtime locally: ~20 seconds.

## When to run

- **Before every Workshop upload**: `.\qa\run_all.ps1 -Quick` minimum.
- **Before every push**: `run_all.ps1` (full).
- **In CI**: every push and PR (see `.github/workflows/qa.yml`).
- **Periodically (weekly)**: with `-FixStale` to banner stale audits.

## Installing luacheck

A **portable Windows binary ships with this repo** at
`tools/luacheck/luacheck.exe`. The QA scripts auto-detect it — no system
install required.

If you need to refresh / install for other platforms:

```powershell
# Refresh the bundled Windows binary (idempotent)
iwr https://github.com/lunarmodules/luacheck/releases/download/v1.2.0/luacheck.exe `
    -OutFile tools\luacheck\luacheck.exe

# Or via scoop / luarocks / Docker
scoop install luacheck
luarocks install luacheck
docker run --rm -v ${PWD}:/work pipelinecomponents/luacheck check ./<mod>
```

GitHub Actions installs the native Linux package via `apt-get install lua-check`.

## Current baseline

After initial config tuning (2026-05-23), the repo has **~415 luacheck
warnings**. About 141 of those are the known CWV bare-globals audit finding
(tracked in PROJECT_STANDARDS §11). Net non-CWV signal: ~274 warnings,
distributed across unused locals, shadowing, and minor cleanup. CI runs
luacheck in **non-blocking mode** — surface findings without failing the
build — until the baseline is driven down.

## What the checks WON'T catch (PRE-SHIP review territory)

Per [CHECKS.md](CHECKS.md), 21 bug classes are too contextual for static
analysis and require the **pre-ship subagent review pattern**
(PROJECT_STANDARDS §5.3). Examples:

- **Hook on BASE class** when DERIVED is the runtime type
- **Hook signature drops vanilla args** (`function(func, self, a, b)` when
  vanilla takes 5)
- **Guard that bails without calling vanilla `func`** — silently changes state
- **Cross-character mesh applied to wrong skeleton** (j_spine1/j_spine2 class)
- **Speculative defense stacking** (v0.9.8.x lesson)

If you're touching `cosmetics_tweaker`, `chaos_wastes_tweaker`,
`weapon_tweaker`, or `character_weapon_variants`, **dispatch a pre-ship
review subagent** before uploading.

## Adding a new check

When you find a recurring bug:

1. Document it in a memory file (`feedback_*.md` or `reference_*.md`).
2. Add a row to [CHECKS.md](CHECKS.md) (which table depends on the bug class).
3. If automatable: write `check_<name>.ps1` in this directory, following the
   conventions in existing checks:
   - PowerShell 5.1 + 7 compatible
   - `-Quiet` flag
   - Exit codes: 0=pass, 1=warnings only, 2=errors
   - UTF-8 file reads via `[System.IO.File]::ReadAllText(..., UTF8)`
     (per `tools/vmb-launcher/CLAUDE.md` PS encoding rule)
4. Wire into `run_all.ps1`.
5. Update GitHub Action.

## Architecture

- **Checks are PowerShell scripts** for native Windows + cross-platform PS Core
  compatibility. PowerShell handles Steam/Workshop tooling already.
- **No build step** — each check is a standalone `.ps1` file. Cheap to add,
  cheap to skip.
- **Exit codes are uniform**: 0/1/2 across all checks for `run_all.ps1`
  aggregation.
- **`.luacheckrc`** lives at repo root (not in `qa/`) because luacheck looks
  for it there.

## Known limitations

- **No in-game smoke tests**. Stingray engine has no headless runtime. Manual
  in-game verification is the only safety net for runtime bugs.
- **`luacheck` Lua 5.1 dialect is strict**. Some VT2 patterns (monkey-patching
  `_G`, dynamic loader access) trigger warnings that may need per-file ignores.
- **PowerShell on Linux CI**: GitHub Actions runs via `pwsh` (PowerShell Core
  7+). Scripts should avoid PS5.1-only cmdlets. UTF-8 read pattern is portable.

## Roadmap

Future checks listed as DEFERRED in [CHECKS.md](CHECKS.md):

- `check_network_send.ps1` — flag `mod:network_send(..., "server", ...)`
  silently-dropped recipients
- `check_changelog_format.ps1` — normalize header style across mods
- `check_hook_audit.ps1` — flag duplicate `mod:hook(Class, "method", ...)`
  per mod handle (the "Attempting to rehook" warning class)
