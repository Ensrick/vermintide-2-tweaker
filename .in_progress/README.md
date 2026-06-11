# `.in_progress/` — live in-flight claim sentinels

Drop a sentinel file here when you start substantive multi-step work on a mod.
Other sessions / agents check this directory before starting work on the same
mod, so two parallel sessions don't race-edit the same files. The pre-commit
hook + `qa/check_in_progress.ps1` also surface a non-blocking WARNING when a
commit touches a mod that's currently claimed.

This is **advisory**, not enforced. The point is awareness, not locking.

## Convention

- One sentinel file per mod, named exactly: `<mod_name>.md`
  (e.g. `weapon_tweaker.md`, `crafting_in_modded.md`, `cosmetics_tweaker.md`).
- The basename **must** match the directory name of the mod at the repo root.
- When the work finishes, **delete the sentinel** (don't leave it stale).
- Sentinels older than 24 hours auto-warn as suspicious — clean them up.

## Template

```markdown
# <mod_name> in-flight

- **Started:** 2026-05-25T14:32:00Z
- **Session ID:** <Claude session ID, branch name, or "Ensrick (manual)">
- **Owner:** Ensrick
- **Description:** One-line summary of what's being changed.

## Files expected to be touched

- `<mod_name>/scripts/mods/<mod_name>/<mod_name>.lua`
- `<mod_name>/scripts/mods/<mod_name>/_feature.lua`
- `<mod_name>/itemV2.cfg` (if bumping MOD_VERSION suffix)
- `<mod_name>/CHANGELOG.md`

## Notes

Anything other sessions need to know — partially-applied refactors, broken
intermediate states, "don't touch X until I'm done", etc.
```

## What's tracked vs ignored

- `README.md` (this file) and `.gitkeep` are **tracked** — they document the
  convention so it's discoverable by new contributors and `git clone`s.
- Every other `*.md` in this directory is **gitignored** (see `.gitignore`).
  Sentinels are ephemeral coordination state, not commit history.

## Integration points

- **`MOD_OWNERSHIP.md`** (repo root) — flip the affected row's `Status` column
  to `in-flight` and fill in your session/branch ID alongside dropping the
  sentinel file.
- **`qa/check_in_progress.ps1`** — wired into `qa/run_all.ps1`. Scans this
  directory, warns on stale sentinels (>24h old), and cross-checks staged
  files against claimed mods.
- **`CLAUDE.md` § "Multi-agent coordination"** — workflow doctrine.

## Burn history

2026-05-25 session had four coordination collisions before this convention
existed:

1. Debug-toggle agent + fix agent both editing `character_weapon_variants`
   simultaneously → version-bump churn v0.1.336 → .337 → .338 → .339.
2. `crafting_in_modded` build broken by uncommitted in-flight changes →
   blocked `publish-release.ps1` twice.
3. `weapon_tweaker` MOD_VERSION reverted 0.12.78 → 0.12.77 by an in-flight
   edit, masking a real fix.
4. Informal verbal ownership ("I have agents on Crafting Cosmetics and
   General Tweaker") didn't survive parallel context switches.

The sentinel + ownership-table convention closes the gap.
