# MOD_OWNERSHIP.md

Single source of truth for **who maintains each mod** and **whether someone is
currently mid-edit on it**. Read this before starting substantive work on any
mod — and check `.in_progress/` for sentinel files claiming a live session.

> **Why this exists.** Today's session had four coordination collisions:
> parallel agents collided on `crafting_in_modded` (broken build blocked
> `publish-release.ps1` twice), `weapon_tweaker` (MOD_VERSION reverted
> 0.12.78 → 0.12.77 by an in-flight edit, masking a real fix), and
> `character_weapon_variants` (version-bump churn v0.1.336 → .339 between
> two simultaneous agents). The fix is awareness, not enforcement — see
> `CLAUDE.md` § "Multi-agent coordination" for the workflow.

## Status legend

- **stable** — no active work; safe to start a new task.
- **in-flight** — someone is mid-edit. Check `.in_progress/<mod>.md` for the
  claim. Coordinate with the listed owner before touching the same files.
- **frozen** — deprecated / archived. Do not modify (legacy `tweaker/`, etc.).
- **blocked** — waiting on something external (engine fix, upstream, decision).

## Ownership table

| Mod | Owner | Status | In-progress branch/session | Last updated |
|-----|-------|--------|----------------------------|--------------|
| weapon_tweaker | Ensrick | stable | — | 2026-06-05 |
| chaos_wastes_tweaker | Ensrick | stable | — | 2026-05-25 |
| chaos_wastes_tweaker_dev | Ensrick | in-flight | dev clone (split 2026-05-26) | 2026-05-26 |
| general_tweaker | Ensrick | stable | — | 2026-05-25 |
| general_tweaker_dev | Ensrick | in-flight | dev clone (split 2026-05-26) | 2026-05-26 |
| gui_tweaker | Ensrick | stable | — | 2026-05-25 |
| cosmetics_tweaker | Ensrick | stable | — | 2026-05-25 |
| dynamic_cosmetic_portraits | Ensrick | stable | — | 2026-05-25 |
| career_tweaker | Ensrick | stable | — | 2026-05-25 |
| enemy_tweaker | Ensrick | stable | — | 2026-05-25 |
| character_weapon_variants | Ensrick | stable | — | 2026-05-25 |
| crafting_in_modded | Ensrick | stable | — | 2026-05-25 |
| crafting_in_modded_dev | Ensrick | in-flight | dev clone (split 2026-05-26) | 2026-05-26 |
| event_tweaker | Ensrick | stable | — | 2026-05-25 |
| modded_progression | Ensrick | stable | — | 2026-05-25 |
| verminious_dreams_lighting | Ensrick | stable | — | 2026-05-25 |
| verminious_dreams_lighting_dev | Ensrick | in-flight | dev clone (split 2026-05-26) | 2026-05-26 |
| tweaker (legacy) | Ensrick | frozen | — | 2026-05-25 |

> **NOTE:** The four `-dev` rows above are the dev-stream clones of public Workshop mods (see `CLAUDE.md` § "Dev/stable split workflow"). Stable-row Workshop IDs stay public; dev rows ship to separate friends-only Workshop items. In-flight work happens in the `-dev` directory only; the stable directory receives merged-down releases.

> **NOTE:** `la_prefix_patch` (retired 2026-05-25; absorbed into cosmetics_tweaker; archived to `_archive/la_prefix_patch_v0.3.6-dev/`).
>
> **NOTE:** `lobby_tweaker` (retired 2026-05-25; merged into general_tweaker; archived to `_archive/lobby_tweaker_v0.1.7-dev/`).
>
> **NOTE:** `buff_tweaker` (`bt`) — **retired 2026-06-08** ("not a mod we're working on anymore"); archived to `_archive/buff_tweaker_v0.1.12-alpha/`. It was the shared Big Rebalance registry + `net_replay` ring buffer. All consumers (wt/ct/et/crt) reference it via the guarded `if not (bt and bt.is_br_active) then return false end` pattern, so with bt gone their BR sub-features **cleanly go inert (no crash)** — they were never stripped from the consumers. The friends-only Workshop item (3730358590) still exists; unsubscribe/delete it in Steam if you want it fully gone.

## How to claim a mod for in-flight work

When you start substantive multi-step work on a mod:

1. Drop a sentinel file at `.in_progress/<mod>.md` (template in
   `.in_progress/README.md`).
2. Flip this table's **Status** column for that row to `in-flight` and fill
   the **In-progress branch/session** column with your session ID or branch.
3. When work finishes (commit landed, build green, ready to ship), delete the
   sentinel and flip the row back to `stable`.

`.in_progress/*.md` are gitignored — they're an ephemeral coordination signal,
not committed history. The README is the only tracked file in there.

## How to check before starting

```powershell
# 1. Read this table to see who owns the mod.
# 2. List sentinels:
Get-ChildItem .in_progress\*.md -Exclude README.md
# 3. Run the QA check (also runs as part of qa/run_all.ps1):
.\qa\check_in_progress.ps1
```

If a sentinel covers the mod you want to touch, ping the owner (or the
session ID inside the sentinel) before editing.

## Single-human-owner footnote

Right now every mod is owned by Ensrick (the maintainer). The table column
exists so the convention generalises: future contributors / friends / agent
teams with delegated authority over a specific mod can be listed here, and
the in-flight sentinel mechanism handles the per-session claim layer on top.
