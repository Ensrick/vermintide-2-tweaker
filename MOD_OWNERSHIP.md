# MOD_OWNERSHIP.md

Single source of truth for **who maintains each mod** and its durable stream or
lifecycle role. Read this before starting substantive work on any mod. Live
edit claims exist only in `.in_progress/`; this committed file must not duplicate
ephemeral in-flight state.

> **Why this exists.** Today's session had four coordination collisions:
> parallel agents collided on `crafting_in_modded` (broken build blocked
> `publish-release.ps1` twice), `weapon_tweaker` (MOD_VERSION reverted
> 0.12.78 → 0.12.77 by an in-flight edit, masking a real fix), and
> `character_weapon_variants` (version-bump churn v0.1.336 → .339 between
> two simultaneous agents). The fix is awareness, not enforcement — see
> `CLAUDE.md` § "Multi-agent coordination" for the workflow.

## Live edit status

`Get-ChildItem .in_progress\*.md -Exclude README.md` is the sole live claim
view. No sentinel means no recorded claim; it does not prove another process is
idle, so inspect `git status` and coordinate before overlapping files. GitHub
Issues owns current feature/bug lifecycle and priority.

## Ownership table

| Mod | Owner | Durable role |
|-----|-------|--------------|
| weapon_tweaker | Ensrick | public-beta primary |
| weapon_tweaker_dev | Ensrick | friends-only runtime-parity mirror |
| chaos_wastes_tweaker | Ensrick | promotion stable |
| chaos_wastes_tweaker_dev | Ensrick | promotion development |
| general_tweaker | Ensrick | promotion stable |
| general_tweaker_dev | Ensrick | promotion development |
| gui_tweaker | Ensrick | promotion stable |
| gui_tweaker_dev | Ensrick | promotion development |
| cosmetics_tweaker | Ensrick | single stream |
| dynamic_cosmetic_portraits | Ensrick | single stream |
| career_tweaker | Ensrick | single stream |
| enemy_tweaker | Ensrick | single stream |
| character_weapon_variants | Ensrick | single stream |
| crafting_in_modded | Ensrick | promotion stable |
| crafting_in_modded_dev | Ensrick | promotion development |
| event_tweaker | Ensrick | single stream |
| character_dialogue | Ensrick | single stream |
| modded_progression | Ensrick | single stream |
| verminious_dreams_lighting | Ensrick | promotion stable |
| verminious_dreams_lighting_dev | Ensrick | promotion development |
| weapons_of_chaos | Ensrick | single stream |
| tweaker (legacy) | Ensrick | frozen; do not modify |

Workshop visibility is deliberately absent: each mod's current `itemV2.cfg` is
the only authority for public/friends-only/private state. See `CLAUDE.md` §
"Dev/stable split workflow" for promotion and WT parity rules.

> **NOTE:** `la_prefix_patch` (retired 2026-05-25; absorbed into cosmetics_tweaker; archived to `_archive/la_prefix_patch_v0.3.6-dev/`).
>
> **NOTE:** `lobby_tweaker` (retired 2026-05-25; merged into general_tweaker; archived to `_archive/lobby_tweaker_v0.1.7-dev/`).
>
> **NOTE:** `buff_tweaker` (`bt`) — **retired 2026-06-08** ("not a mod we're working on anymore"); archived to `_archive/buff_tweaker_v0.1.12-alpha/`. It was the shared Big Rebalance registry + `net_replay` ring buffer. All consumers (wt/ct/et/crt) reference it via the guarded `if not (bt and bt.is_br_active) then return false end` pattern, so with bt gone their BR sub-features **cleanly go inert (no crash)** — they were never stripped from the consumers. The friends-only Workshop item (3730358590) still exists; unsubscribe/delete it in Steam if you want it fully gone.

## How to claim a mod for in-flight work

When you start substantive multi-step work on a mod:

1. Drop a sentinel file at `.in_progress/<mod>.md` (template in
   `.in_progress/README.md`).
2. When work finishes (commit landed, build green, ready to ship), delete the
   sentinel. Do not edit this durable ownership table for an ephemeral claim.

`.in_progress/*.md` are gitignored — they're an ephemeral coordination signal,
not committed history. The README is the only tracked file in there.

## How to check before starting

```powershell
# 1. Read this table to see who owns the mod and which stream it belongs to.
# 2. List the live sentinels:
Get-ChildItem .in_progress\*.md -Exclude README.md
# 3. Run the QA check (also runs as part of qa/run_all.ps1):
.\qa\check_in_progress.ps1
```

If a sentinel covers the mod you want to touch, ping the owner (or the
session ID inside the sentinel) before editing.

## Single-human-owner footnote

Right now every mod is owned by Ensrick (the maintainer). The table column
exists so the convention generalises: future contributors, friends, or agent
teams with delegated authority over a specific mod can be listed here. The
in-flight sentinel mechanism remains the separate per-session claim layer.
