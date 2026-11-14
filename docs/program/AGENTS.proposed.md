# Agent entry: Vermintide 2 Tweaker

Read this file first, every session, whichever agent or vendor you are. It is the only mandatory reading. Everything else is looked up by task (last table).

## What this is

Lua 5.1 mods for Vermintide 2 (Vermintide Mod Framework on the Stingray engine), one folder per mod. The decompiled game source used for every engine citation is the sibling folder `../Vermintide-2-Source-Code`; the framework source is `../Vermintide-Mod-Framework`. The repo is public.

## Mods (authority: `tools/mod-inventory.psd1`)

| Edit here | Id | Notes |
|---|---|---|
| `weapon_tweaker/` | `wt` | Public beta. `weapon_tweaker_dev/` (`wt_dev`) is its parity mirror: change it only to re-mirror |
| `chaos_wastes_tweaker_dev/` | `ct_dev` | Stable `chaos_wastes_tweaker/` (`ct`, public) changes by promotion only |
| `general_tweaker_dev/` | `gt_dev` | Stable `general_tweaker/` (`gt`, public): promotion only |
| `gui_tweaker_dev/` | `gut_dev` | Stable `gui_tweaker/` (`gut`, public): promotion only |
| `crafting_in_modded_dev/` | `cim_dev` | Stable `crafting_in_modded/` (`cim`, public): promotion only |
| `verminious_dreams_lighting_dev/` | folder name | Stable `verminious_dreams_lighting/` (public): promotion only |
| `cosmetics_tweaker/`, `character_weapon_variants/`, `career_tweaker/` (`crt`), `event_tweaker/` | | Single stream, public |
| `dynamic_cosmetic_portraits/`, `enemy_tweaker/`, `character_dialogue/`, `weapons_of_chaos/` (`WOC`) | | Single stream, friends-only |
| `modded_progression/` (`mp`) | | Single stream, private |
| `tweaker/` | `t` | Frozen. Never edit |

## Rules no script enforces (you are the only safeguard)

1. **Launch.** Only the unattended rig, `tools/harness/run.ps1`, may start the game. Never start Vermintide 2, Steam, a launcher window or any interactive app another way. Never restart Steam. If the rig script is absent, nothing may be launched.
2. **Steam folders.** Never write by hand into `steamapps/workshop/content/552500/`.
3. **Shared checkout.** Other sessions work in the primary checkout. There: no commit, stash, reset, clean, checkout or pull. Write only in a worktree you created with `tools/worktrees/worktree.ps1`. Stage by explicit path, never `git add -A`. Never touch a worktree or branch you did not create.
4. **Publishing.** Build and publish only through `tools/ship/ship.ps1`. The procedure owner is [PROJECT_STANDARDS.md section 6.6](PROJECT_STANDARDS.md#66-ship-doctrine-keyed-off-the-mod_version-suffix-canonical-2026-07-01). Never use raw vmb, `ugc_tool`, a launcher GUI or direct launcher publication.
5. **Evidence.** Never write "fixed" from a build, a review or a green gate. Classes U (unit test), S (static check) and R (rig run) close an issue on machine evidence, written as `auto-verified (<class>) on <mod> <version> <commit>, run <id>`. Classes V (human eyes or ears) and C (two clients) go to the human list and never block other work. See `docs/adr/0001-rig-launch-machine-evidence-no-cards.md`.
6. **Tracker.** No `## CURRENT LIVE TEST` cards (stopped 2026-11-13). Do not change lifecycle labels by hand. One issue or work package per pull request. PR bodies say `Refs #N`.
7. **Engine facts.** Cite `Vermintide-2-Source-Code/<path>:LINE` (or the VMF source) for every claim about engine or VMF behaviour, or write `[unverified]`. Documents here are often stale: check the code.
8. **Hooks.** Before adding `mod:hook` or `mod:hook_safe`, search the whole mod for the same `(Class, method)`. VMF keeps a mod's first registration and ignores later ones with a warning. Hook the class the game instantiates, not its base. Return every value the original returns and pass every argument on.
9. **Diagnostics.** Use engine `printf` with a `[<mod>:<feature>]` prefix. `mod:info` and `mod:echo` are invisible to users who run with mod logging off. Never replace the global `printf`.
10. **DLC.** Code that lists, unlocks or injects content must skip entries whose `required_dlc` the player does not own.
11. **Gates.** Never weaken, skip or delete a check to get green. `--no-verify` only when the commit message proves the gate wrong. If a gate fails for a reason outside your diff, stop and report it.
12. **Scope and privacy.** No personal paths, names, e-mail addresses or tokens in commits, issues or documents. An outside feature request is not authorization to implement it. Stable promotions and clean-version releases need the owner.

## Gates that will stop you (do not fight them)

- Five dev/stable pairs: edits go to the `_dev` folder (`qa/check_dev_only_edits.ps1`).
- A change under a mod folder (documentation included) needs a claimed version, a `-BuildOnly` build, and source, bundle and `.build-receipt.json` in one commit (`tools/ship/claim.ps1`, `qa/check_release_bundle_atomicity.ps1`, `qa/check_build_receipts.ps1`).
- At most 8 worktrees and 12 GiB (`qa/check_worktree_budget.ps1`).
- Duplicate hooks (`tools/mod-lint/lint-mod.ps1`).
- Before every push run `pwsh qa/run_all.ps1 -Quick -SkipLua`.

## Read next, by task

| Task | Read |
|---|---|
| Execute a work package or verification pack | `docs/EXECUTION_PROTOCOL.md` |
| Build, publish, recover a failed ship | section 6.6 (link above), `docs/PORTABLE_SETUP.md`, `tools/ship/CLAIMS.md` |
| Triage a bug report | `docs/BUG_TRIAGE_RUNBOOK.md`; search `docs/BUG_CLASSES.md`, do not read it whole |
| Engine or VMF behaviour | `docs/engine/README.md`, `docs/VMF_RECIPES.md` |
| One mod's hooks and known dead ends | `<mod>/ENGINE_SURFACE.md` |
| How the code is wired | [CLAUDE.md](CLAUDE.md) (long technical reference: read by section) |
| Labels and issue format | `PROJECT_STANDARDS.md` section 11 |
