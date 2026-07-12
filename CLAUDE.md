# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## NON-NEGOTIABLES (read every session; details below)

| # | Rule |
|---|---|
| 1 | No recursive deletes (`rm -rf`, `Remove-Item -Recurse -Force`, etc.). Rename to `.bak.v<old>` and delete one path at a time with approval. |
| 2 | Never auto-launch VT2 or any game/interactive app without explicit user permission. |
| 3 | Edit ONLY the `*_dev/` dir for the 5 split mods (ct, cim, gt, gut, vdl). `weapon_tweaker_dev/` is a STALE clone: never edit it; `weapon_tweaker/` is active. |
| 4 | Ship doctrine keys off the MOD_VERSION suffix. `-dev`/`-alpha`/`-beta` = FULL pipeline every build, NO ask. Clean version (no suffix) = stable: needs a fresh per-build ship signal naming the version. |
| 5 | Bump MOD_VERSION (3-segment semver + suffix) every build; write the CHANGELOG entry and doc updates in the SAME response. |
| 6 | VMBLauncher is the ONLY build/deploy/upload path. Never raw `node vmb.js`, `ugc_tool`, `scp`, or hand-wrapped SDK. |
| 7 | Never write into `steamapps/workshop/content/552500/<real_id>/` by hand - Steam reconciles foreign writes and may wipe the folder. |
| 8 | Before ANY `mod:hook`/`mod:hook_safe`: grep for existing hooks on that `(Class, method)`. VMF silently drops the 2nd - merge into the existing body. |
| 9 | Diagnostics use engine `printf`, NOT `mod:info`/`mod:echo` (user runs with mod-logging OFF, so those are invisible). |
| 10 | Never claim "fixed" / "feature-complete" until the USER confirms in-game. Compile success and structural review are not verification. |
| 11 | Loc: raw setting keys in widget fields, never pre-localize before registration; escape a literal `%` as `%%`. No em dashes in menu-facing strings. Dev builds carry option-title status tags per `docs/LOCALIZATION_STANDARD.md` § 13 "Dev status tags"; stable (clean-versioned) never does. |
| 12 | Mechanics claims: grep `C:\Users\danjo\source\repos\Vermintide-2-Source-Code` and cite `file:line`, else write `[unverified]`. Never invent internals. |
| 13 | Deferred/blocked work goes to GitHub Issues (search first), not floating TODO comments. Label with the FIXED taxonomy — status lifecycle (`verify-fix`, or `verify-fix-coop` when 2+ people are needed to test; `diagnostics-armed` for probes; `Fixed` once the user confirms in-game = post-fix pass owed: hardening + docs + regression test before close) + type (`bug`/`enhancement`/`feature`, with `crash` a flag on `bug`) + mod tag. Never invent a new status label. Issue format: title 8 words max; body = empirical data only (~150 words: Symptom/Evidence/Fix/Refs). Full scheme: `PROJECT_STANDARDS.md` §11 "Labels" + "Issue format". |
| 14 | On any bug report: read `docs/BUG_TRIAGE_RUNBOOK.md` FIRST, then match `docs/BUG_CLASSES.md`, before diving into mod source. |

> **READ FIRST**: `PROJECT_STANDARDS.md` (repo root) is the operational rulebook
> for HOW we work in this repo - workflow conventions, error-handling rules,
> logging conventions, anti-patterns to avoid, pre-ship checklists. This
> `CLAUDE.md` describes HOW the code works (technical reference); the standards
> doc describes how WE work on it. When in doubt, cite the section.
>
> **Bug class catalog: `docs/BUG_CLASSES.md`** - match symptoms against known
> patterns before deep dive. Most bug reports are repeats of a class already
> shipped, debugged, and fixed elsewhere in the monorepo. Triage workflow lives
> in `docs/BUG_TRIAGE_RUNBOOK.md`.
>
> **STOP: BEFORE WRITING ANY `mod:hook(...)` OR `mod:hook_safe(...)` LINE**
>
> VMF silently drops the SECOND hook on the same `(Class, method)` pair from
> the same mod (whether `mod:hook` or `mod:hook_safe`, doesn't matter - same
> target = drop). This has burned this codebase **at minimum five times**
> (cim, ct v0.7.121, ct v0.7.129/.130, plus older ct entries). The lint at
> `tools/mod-lint/lint-mod.ps1` is supposed to catch it; if your hook still
> ships and a `Attempting to rehook active hook` log line appears in the
> user's session, the lint missed it AND so did you.
>
> **MANDATORY pre-flight before writing a new hook:**
> 1. `Grep` the target mod source file for `("ClassName"` AND for `<ClassNameSymbol>,` to find every existing hook on that class. Inspect every match for the method you want to hook.
> 2. If ANY match exists for `(ClassName, method)`, **DO NOT add a new hook line**. Instead, merge your new logic INTO the body of the existing hook. Add a banner comment naming the consolidation site (e.g. `_ct_consolidated_open_chest_hook` marker) so the next session can grep for it.
> 3. Add or extend a `/ct_regression_test` `_rt_register` source-pattern marker for the consolidation, so the singleton invariant is checked on every release.
>
> When in doubt: search for `"<method>"` (with quotes) in the file. A grep that returns more than one hit on `mod:hook` or `mod:hook_safe` is a bug, full stop. Reference: `docs/VMF_RECIPES.md` section 1 + `memory/feedback_vmf_no_duplicate_hooks_burned_again.md`.

## Project Overview

A modular set of **Vermintide 2** VMF (Vermintide Mod Framework) mods written in Lua 5.1. Originally a monolithic mod ("Tweaker"), now split into focused sub-mods. Runs on the Stingray engine. The VT2 decompiled source code lives at `c:\Users\danjo\source\repos\Vermintide-2-Source-Code` - use it as a reference for game APIs, class structures, and data tables.

## Documentation Map

Navigation anchor for the entire monorepo's docs. `CLAUDE.md` (this file) is the
technical entry point; from here, follow the tree to the topic-specific reference.

> This map is a **navigation aid** (file -> one-line purpose). It deliberately
> does NOT carry per-file version or staleness stickers - those drift faster
> than the map gets updated. The canonical doc index, including which docs are
> required/current for which mods, is `PROJECT_STANDARDS.md` section 7.1.

**Tier 1 - repo-wide (read first):**
- `CLAUDE.md` (this file) - technical overview: how every mod is wired, the build pipeline, the architecture invariants.
- `PROJECT_STANDARDS.md` - operational rulebook: workflow conventions, error-handling rules, logging conventions, anti-patterns, pre-ship checklists. Binding when working on any mod.
- `docs/BUG_CLASSES.md` - catalog of known bug patterns this repo has seen (symptom -> diagnosis pattern -> fix template + Issue/commit citation). Pattern-match here FIRST on any bug report before deep dive.
- `docs/BUG_TRIAGE_RUNBOOK.md` - workflow for using the bug-class catalog: intake, match, fix, verify, document.
- `docs/MECHANICS.md` - provenance-enforced index of how VT2 / Stingray mechanics actually work. Every factual bullet carries a provenance tag (`[src: file:line]` / `[dump:]` / `[memory:]` / `[bugclass:]` / `[user:]` / `[unverified]`). **Before stating any mechanic, grep the decompiled source and cite it, or write `[unverified]` - never confabulate** (PROJECT_STANDARDS section 12a capture doctrine). `qa/check_mechanics_citations.ps1` fails on any untagged claim. This is an INDEX that points at source/memory/BUG_CLASSES, not a fourth prose surface.
- `docs/engine/README.md` - index for the 11-doc engine reference set (`docs/engine/01..11_*.md`: foundation/OOP, extensions, network, unit lifecycle, packages, items/husk, conflict director, game states, UI, buffs, backend) - per-subsystem architecture/seams/traps with `file:line` citations into the decompile, plus `IMPROVEMENT_BACKLOG.md` feeding the OOP professionalization program. Read the relevant subsystem doc before deep engine work.
- `DEVELOPMENT.md` - historical/detailed technical reference (hooking rules, animation system, shield swap architecture, known errors). Pre-dates this CLAUDE.md but still authoritative for the topics it covers.
- `docs/CROSS_MOD_ARCHITECTURE.md` - how `weapon_tweaker`, `cosmetics_tweaker`, `character_weapon_variants`, and `modded_progression` interact at runtime; LA bridge pattern; co-installed-mod detection.

**Tier 2 - repo-wide topical:**
- `STATUS.md` - the single what-now board; with GitHub Issues it replaced `TODO.md` / `WORK_ITEMS.md` / `TESTING_STATUS.md` (retired to pointer stubs 2026-07-08, issue #432).
- `ITEM_LIST.md` - full weapon key catalog from `ItemMasterList`.
- `docs/WEAPON_CATALOG.md` - repo-level weapon catalog (model paths, ownership, cross-character status).
- `ANIMATION_RESEARCH.md` - skeleton event probe results across the six character bodies.
- `docs/LOCALIZATION_STANDARD.md` - string-table and naming conventions for `*_localization.lua`.
- `docs/REGRESSION_CHECKLIST.md` - repo-wide regression gates (per-mod ones live under each mod folder).
- `CHANGELOG.md` - repo-aggregate release notes.
- `docs/VMF_RECIPES.md` - Vermintide Mod Framework gotchas (hook_safe chaining, multi-return collapse, network_send recipients, RPC string cap, dropdown options mutation, widget setting_id uniqueness, mod localization scope, custom_gui_textures format).
- `docs/COMMANDS.md` - per-mod chat command inventory (every `mod:command(...)` across the repo).

**Tier 3 - per-sub-mod docs worth reading from outside the mod (each mod also has its own CHANGELOG.md + REGRESSION_CHECKLIST.md):**

- `character_weapon_variants/`:
  - `DEFINITION_OF_DONE.md` - mandatory gate before declaring any CWV variant complete.
  - `RECIPES.md` - decision tree + per-archetype copy-paste recipes.
  - `DEVELOPMENT.md` - architectural reference for variant creation (template patterns, scale/grip, custom mesh, known errors).
  - `ANIMATION_FIX_PLAYBOOK.md` - closed-vocabulary procedure for fixing 3P animations on cross-character variants.
  - `ENGINE_SURFACE.md` - the mod's engine contact surface: every vanilla (Class, method) cwv hooks, mapped to what the engine does there, with `docs/engine/` links and the paid-for dead ends. Read before adding a hook or auditing a crash class.
- `chaos_wastes_tweaker/`:
  - `DEVELOPMENT.md` - engine gotchas: dormant buff registration, deus rarities, adventure mutator compat, NetworkedFlowStateManager leak, jewelry traits as boons, walk-through interactable, graph-snapshot RPC.
  - `TODO.md` - planned features (altar cost config, CW inventory).
- `cosmetics_tweaker/`:
  - `DEVELOPMENT.md` - three weapon rendering paths + cosmetic-specific recipes.
  - `LA_SYNC_MODEL.md` - full LA bridge architecture + section 6 gotcha catalogue (kind=texture/unit hats and shields, husk RPC race, offhand preload, hook_safe shadow).
  - `GLOW_SYSTEM.md` - MaterialSettingsTemplates engine reference + override mechanism.
  - `ENGINE_SURFACE.md` - the mod's engine contact surface: every vanilla (Class, method) cosmetics_tweaker hooks, mapped to what the engine does there, with `docs/engine/` links and the paid-for dead ends (LA bridge, glow, Material-Hijack #282, CosmeticUtils sync, hat spawning). Read before adding a hook or auditing a crash class.
- `dynamic_cosmetic_portraits/`:
  - `CLAUDE.md` - workflow guardrails for the portrait pipeline (read before touching portraits).
  - `DEVELOPMENT.md` - career_settings swap, texture/alpha requirements, VMF renderer-creator keys.
- `enemy_tweaker/`:
  - `DEVELOPMENT.md` - breed-adding checklist (pairs(Breeds) at boot, threat_values upvalue), architecture overview.
  - `EXPANSION_PLAN.md` - spawn-parity roadmap.
- `event_tweaker/`:
  - `CLAUDE.md` - workflow guardrails: module map discipline (`_evt_*` split), load-bearing injection guards, single-source catalogs. Read before touching the mod.
  - `DEVELOPMENT.md` - module contracts + "where new code goes", the three hooks (`get_special_events`, `get_active_events`, `get_level_variation_data`), mutator/preset registration, confirmed mutator catalog.
- `modded_progression/`:
  - `PLAN.md` - full design for the modded-realm vanilla-progression re-enable.
- `verminious_dreams_lighting/`:
  - `DEVELOPMENT.md` - per-mission lighting tuning architecture (ShadingEnvironment + Light overrides for dlc_termite_1/2/3).
- `weapon_tweaker/`:
  - `ANIMATION_COVERAGE.md` - **the release walk list**: per-(receiver, weapon) 3P animation status matrix (working / wired-unverified / decided-not-wired / undecided), the tune->export->bake workflow, and the model-substitute queue. Source of truth for "what's left before wt releases" (added 2026-06-11).
  - `CROSS_CHARACTER_PORT_RECIPE.md` - seven-step procedure for adding a new cross-character weapon port.
  - `DEVELOPMENT.md` - design direction + animation remap rules (per-unit state, closed-vocabulary, 3P fix process, character-skeleton constraints).
  - `ENGINE_SURFACE.md` - the mod's engine contact surface: every vanilla (Class, method) wt hooks, mapped to what the engine does there, centered on the cross-character 3P animation firing layer (`Unit.animation_event` / `anim_event_3p` / `wield_anim_career_3p`) and the three redirect layers, with `docs/engine/` links and the paid-for dead ends. Read before adding a hook or auditing a crash class.

**Tier 4 - tooling:**
- `tools/vmb-launcher/CLAUDE.md` - VMBLauncher doctrine (verbs, flags, preflight gates, visibility-public safety, remote-deploy config).
- `tools/publish-release/README.md` - GitHub-release pipeline that publishes built bundles for `vt2-mod-updater` consumers.
- `tools/mod-lint/README.md` + `qa/CHECKS.md` - luacheck + custom QA scans.

Full per-file index is in the **Key Reference Files** section at the bottom.

## Bug triage

On receiving a user bug report, read `docs/BUG_TRIAGE_RUNBOOK.md` first - it's the 60-second orientation (phase 1 reads, bug-class match, deep-dive log patterns, fix checklist with the `_rt_register` + `/verify_<feature>` + GitHub-release steps, post-fix hardening) and is the single entry point any session should use before diving into mod source.

## Mod Directory

All active mods build via **VMB** (the launcher). Only frozen legacy `tweaker` uses the raw SDK. Purposes here are one-liners; per-mod docs (Tier 3 above / Key Reference Files below) carry the detail. Do not re-add version numbers or dated notes to this table - they drift; the mod's own CHANGELOG is the source of truth.

| Mod | Internal ID | Workshop ID | Stream | Purpose |
|-----|-------------|-------------|--------|---------|
| weapon_tweaker | `wt` | 3712896117 | single | Full-freedom cross-character weapon access: any character wields any weapon (1P universal, untouched), 3P anim events remapped into a receiver-native weapon's vocab so the bystander view stays plausible. Identical-functional ports are migrating out to `cosmetics_tweaker`; wt keeps genuine functional cross-character ports. Operates **independently** of `character_weapon_variants` (overlap allowed); wt is the availability control surface — it owns the per-weapon enable/disable toggles and, when co-installed with CWV, also covers CWV's weapons. See `docs/CROSS_MOD_ARCHITECTURE.md` / Issue #368. |
| **weapon_tweaker_dev** | `wt_dev` | (none) | **STALE - DO NOT EDIT** | Abandoned experiment clone on disk. `weapon_tweaker/` (unsuffixed) is the ACTIVE dir for all wt work. Never edit this directory. |
| chaos_wastes_tweaker | `ct` | 3712929235 | stable | CW economy, curses, boons, altars, traits. In-flight work in `chaos_wastes_tweaker_dev`. |
| chaos_wastes_tweaker_dev | `ct_dev` | 3733366926 | dev | In-flight `ct` work; friends-only clone. Distinct VMF registration so it coexists with stable `ct`. See "Dev/stable split workflow". |
| general_tweaker | `gt` | 3713619122 | stable | 3rd-person camera, noclip, freecam, godmode, in-mission keep menus, debug/data dumps, host-side lobby controls (slot reservations, ignore list, kick-on-idle, MOTD, failed-join mod reveal). Lobby settings/commands namespaced `gt_lobby_*`; `mod.GT_LOBBY_RPC_SCHEMA` per VMF_RECIPES section 10. In-flight work in `general_tweaker_dev`. |
| general_tweaker_dev | `gt_dev` | 3733367409 | dev | In-flight `gt` work; friends-only clone. `GT_LOBBY_RPC_SCHEMA` is per-mod-id, so dev and stable can't share a lobby RPC channel - friends running dev should all pin to dev. See "Dev/stable split workflow". |
| gui_tweaker | `gut` | 3732144878 | stable | Hero/character GUI QoL: save/swap loadouts via chat commands (clean reimpl of `loadout_manager_vt2` fixing the gear/cosmetic namespace-merge bug), plus in-game drag-to-reposition HUD customization with per-resolution persistence. In-flight work in `gui_tweaker_dev`. |
| gui_tweaker_dev | `gut_dev` | 3751024698 | dev | In-flight `gut` work; friends-only clone. Has its own `hb/` HideBuffs-fork subdir. See "Dev/stable split workflow". |
| cosmetics_tweaker | `cosmetics_tweaker` | 3715714222 | single | Hat/skin unlocks, weapon model tweaks, shield swaps, custom illusions. Also the cross-character cosmetic swap for functionally-identical weapons (per-receiver scaling + grip offset) - absorbs identical-functional ports leaving wt. |
| dynamic_cosmetic_portraits | `dynamic_cosmetic_portraits` | 3721036701 | single | Hat/outfit-aware HUD and hero-select character portraits (split from cosmetics_tweaker). |
| career_tweaker | `crt` | 3716286199 | single | Talent/ability swapping. |
| enemy_tweaker | `enemy_tweaker` | 3716780252 | single | Enemy spawns, horde compositions, breed substitution. |
| character_weapon_variants | `character_weapon_variants` | 3716869446 | single | Semi-lore-friendly new variant items (MoreItemsLibrary) that clone cross-character base templates to bring other characters' movesets onto receivers. 1P wield/stance differentiates feel; 3P uses `anim_event_3p` remap into a good-enough native vocab. Designed to play distinctly, unlike wt's full-freedom access. **Independent** of `wt` (overlap allowed); default-on with no per-weapon toggles — `wt`, when co-installed, supplies those toggles and covers CWV's `cwv_variant` items. See `docs/CROSS_MOD_ARCHITECTURE.md` / Issue #368. |
| weapons_of_chaos | `WOC` | 3753880932 | single | Player characters wield ENEMY weapons + named keep-trophy artifacts via the duplicate-item approach (clone a player base template, swap held mesh to an enemy/prop `.unit`). First item: Blightreaper (Kruber 1H sword, all careers). Full research + crash post-mortem in `weapons_of_chaos/DEVELOPMENT.md`. |
| crafting_in_modded | `cim` | 3721038774 | stable | Modded crafting menus - Athanor forge UI for crafting any career-eligible weapon. In-flight work in `crafting_in_modded_dev`. |
| crafting_in_modded_dev | `cim_dev` | 3733366851 | dev | In-flight `cim` work; friends-only clone. See "Dev/stable split workflow". |
| event_tweaker | `event_tweaker` | 3721290755 | single | Host-side mutator picker ("Tweaker: Events"). Dropdown for canonical event presets (Geheimnisnacht / Skulls) plus checkbox-per-mutator. Three hooks: `get_special_events`, `get_active_events`, `get_level_variation_data`. See `event_tweaker/DEVELOPMENT.md`. |
| modded_progression | `mp` | 3730422873 (private) | single | Re-enables vanilla VT2 progression in modded realm (XP, shillings, loot, Okri's Challenges, Emporium, crafting bench). Intercepts `BackendInterface*Playfab`, writes through `backend_mirror`, persists via VMF settings, never commits to PlayFab. Sibling API consumed by CWV + cosmetics_tweaker. See `modded_progression/PLAN.md`. |
| buff_tweaker | `bt` | 3730358590 | **RETIRED** | Retired; archived to `_archive/buff_tweaker_v0.1.12-alpha/`. Was the shared Big Rebalance registry + `net_replay` ring buffer. Consumers (wt/ct/et/crt) guard on `if not (bt and bt.is_br_active) then return false end`, so their BR sub-features go inert (no crash) - they were NOT stripped. |
| verminious_dreams_lighting | `verminious_dreams_lighting` | 3727221800 | stable | Per-mission lighting overhaul for the three Verminious Dreams DLC missions (ShadingEnvironment + Light overrides; live tuning via `/vdl_*`). Client-side only, no host/version-sync risk. In-flight work in `verminious_dreams_lighting_dev`. |
| verminious_dreams_lighting_dev | `verminious_dreams_lighting_dev` | 3733366748 | dev | In-flight `vdl` work; friends-only clone. See "Dev/stable split workflow". |
| tweaker (legacy) | `t` | 3704660429 | frozen | Deprecated, raw Stingray SDK - split into the above mods. Do not iterate. |

## Dev/stable split workflow

**Why + what's split.** The five public-Workshop mods (`ct`, `cim`, `gt`, `verminious_dreams_lighting`, `gut`) run two parallel Workshop items each: dev = friends-only, stable = public. Public subscribers want a stable bundle; the friends cohort wants visibility into in-flight work. Shipping every dev iteration to the public item cost ~80 cim subs in a few days in May 2026, hence the split. Everything else is single-stream (already friends-only or unpublished: `wt`, `cosmetics_tweaker`, `cwv`, `enemy`, `event`, `crt`, `dcp`, `mp`, `WOC`). (`bt` is retired - see the Mod Directory.)

| Stable directory | Stable mod_id | Stable Workshop ID | Dev directory | Dev mod_id | Dev Workshop ID |
|---|---|---|---|---|---|
| `chaos_wastes_tweaker/` | `ct` | 3712929235 (public) | `chaos_wastes_tweaker_dev/` | `ct_dev` | 3733366926 (friends-only) |
| `crafting_in_modded/` | `cim` | 3721038774 (public) | `crafting_in_modded_dev/` | `cim_dev` | 3733366851 (friends-only) |
| `general_tweaker/` | `gt` | 3713619122 (public) | `general_tweaker_dev/` | `gt_dev` | 3733367409 (friends-only) |
| `gui_tweaker/` | `gut` | 3732144878 (public alpha) | `gui_tweaker_dev/` | `gut_dev` | 3751024698 (friends-only) |
| `verminious_dreams_lighting/` | `verminious_dreams_lighting` | 3727221800 (public) | `verminious_dreams_lighting_dev/` | `verminious_dreams_lighting_dev` | 3733366748 (friends-only) |

**Where work happens.**

- **`<mod>-dev/`** - all new feature work, in-flight fixes, experiments. Build/deploy/upload from here during the dev loop. MOD_VERSION carries the `-dev` (or `-alpha`/`-beta`) suffix.
- **`<mod>/`** - stable releases only. When dev work matures and the user signs off on a release, cherry-pick or merge the changes into the stable dir, set MOD_VERSION to whatever the user names for the release (it MAY keep a pre-release suffix - e.g. ct promoted as `0.7.130-beta`, a public beta; strip the suffix only when the user names a clean version), then `build` + `deploy` + `upload` to the public Workshop item. The stable directory should never contain in-flight `-dev` work between releases.

**Promotion tracking & safe port.** `docs/PROMOTION_PROCESS.md` is the full procedure. Run `tools/promote/promotion-status.ps1` before any public ship (and in CI) to catch a crash fix stranded in dev — the #278 failure mode where the fix sat in `cim_dev` while public kept crashing. Port a full rollup with `tools/promote/promote.ps1` (DryRun by default; identity-preserving; skips dev-only files). **When you promote a crash fix, cite its issue number in the public CHANGELOG entry** so the tracker stays exact (as cim v0.8.34 does for #278).

**Mod ID convention.** Stable carries the short canonical id (`ct`, `cim`, `gt`, plus the long `verminious_dreams_lighting`). Dev carries the `_dev` suffix (`ct_dev`, `cim_dev`, `gt_dev`, `verminious_dreams_lighting_dev`). Because these are distinct VMF mod registrations, both items can be subscribed simultaneously without conflict - a tester running dev keeps the stable item installed but disabled, or runs both side-by-side if their behaviors don't overlap destructively.

**Cross-mod refs always target stable.** External mods (CWV, cosmetics_tweaker, et, etc.) that consume sibling mods via `get_mod("cim")` / `get_mod("gt")` / `(get_mod('bt') or {}):is_br_active()` MUST resolve against the stable mod_id. Dev clones are isolated test surfaces; nothing external consumes them. If you need a cross-mod hook to fire against dev for testing, edit the consumer's `get_mod(...)` call to point at the dev id locally - never ship that change to a stable directory.

**Caveat - per-mod-id RPC channels.** Anything keyed by mod_id (network channels, lobby data slots, the `GT_LOBBY_RPC_SCHEMA` constant in `gt`) is automatically isolated between stable and dev because the mod_ids differ. That's the desired isolation in most cases, but it means **dev and stable can't talk to each other over a lobby RPC**. If a session needs the lobby/MOTD/slot-reservation surface, every peer should pin to the same stream (all dev or all stable). Don't mix.

**Upload doctrine** - governed by the "Ship doctrine" section under Build Commands (the MOD_VERSION suffix decides). Two split-mod-specific gates:

- **Dev uploads** target the friends-only Workshop item (`visibility = "friends_only"` in the dev clone's `itemV2.cfg`) and carry the `-dev` suffix, so they ship the full pipeline every build with NO ask. Dev clones must NEVER be promoted to public visibility under any circumstance; the launcher does not take `--allow-public` for them.
- **Stable uploads** target the public Workshop item. Two INDEPENDENT gates apply (user ruling 2026-07-04, closed #328): `-AllowPublic` keys off the item's `itemV2.cfg` visibility (`public` needs the flag, whatever the version says), and the fresh per-build ship signal keys off a CLEAN (no-suffix) MOD_VERSION only. A pre-release-suffixed build living on the stable/public item (e.g. ct `0.7.130-beta`) ships per the suffix rule - full pipeline, no ask. Workshop visibility is user-dictated per item; it is NEVER inferred from the version, directory, or stream, and no guard may couple the two.
- **GitHub release** is part of the canonical `ship.ps1` path, run for either stream so `vt2-mod-updater` consumers stay in sync (Workshop propagation to the friends cohort is unreliable).

## Build Commands

### Required: VMBLauncher headless CLI

VMBLauncher is **the only** sanctioned path to build / deploy / upload any VT2 mod in this repo. Not "preferred" - required. Do NOT invent ad-hoc PowerShell pipelines, raw `node vmb.js`, raw `ugc_tool` calls, raw `scp` to PC-B, or wrap the SDK compiler by hand. Every one of those one-off paths has burned multiple iterations in the past (hash-unverified deploys, stale PC-B, missed UTF-8 BOM, 0x2 empty-content-directory, wrong scp protocol, etc.). If the launcher binary is missing on the current machine, rebuild it via `tools/vmb-launcher/publish.ps1 -SkipOpen` before doing anything else.

```powershell
$exe = "C:\Users\danjo\source\repos\vermintide-2-tweaker\tools\vmb-launcher\bin\Release\net9.0-windows\win-x64\publish\VMBLauncher.exe"
& $exe list                                          # list discovered mods
& $exe info   general_tweaker                        # cfg + bundle state
& $exe doctor                                        # diagnostics
& $exe build  general_tweaker                        # VMB build -> bundleV2/
& $exe deploy general_tweaker                        # hash-verified copy to Workshop folder + PC-B
& $exe upload general_tweaker                        # stage + push via ugc_tool
& $exe upload chaos_wastes_tweaker --allow-public    # only required for public-visibility mods
& $exe all    general_tweaker                        # build + deploy + upload (incl. PC-B)
```

Same code as the GUI buttons; streams VMB output live to stdout; exit codes 0/1/2/3. **Read `tools/vmb-launcher/CLAUDE.md` for the full doctrine** - verbs, flags, preflight gates, visibility-public safety, remote-deploy config, the PowerShell pipeline-truncation quirk, GUI/headless detection rule.

### Ship doctrine (2026-07-01 canonical)

**The ship decision keys off the MOD_VERSION suffix, nothing else** - not the directory, not Workshop visibility.

**`-dev` / `-alpha` / `-beta` suffix (= every currently active mod):** EVERY update ships the FULL pipeline with NO per-build approval. Run:

```powershell
.\tools\ship\ship.ps1 -Mod <name>     # build + deploy (PC-A + PC-B) + upload + GitHub release + verify
```

Then `git add` + commit + push the source. Add `-AllowPublic` when the mod's `itemV2.cfg` has `visibility = public`. Add `-NoRemote` ONLY if PC-B is unreachable, and say so in your report. Local-deploy-only is NOT a valid test path: Steam re-syncs the subscribed Workshop bundle over any local deploy, so the user only ever runs the last UPLOADED build. Uploading is the only thing that reaches them.

**Clean version, no suffix (= stable / public promotion):** requires a fresh, explicit, per-build ship signal from the user naming the version (e.g. "ship cim v0.8.34 now"). A "ship it" from earlier does NOT carry forward. Default for these is `build` + `deploy` only; treat upload like `git push --force`. This guards public subscribers - reflex uploads of unstable mid-fix builds cost ~80 cim subscribers in May 2026.

| Intent | Verbs |
|---|---|
| Update a `-dev`/`-alpha`/`-beta` build (any active mod) | `ship.ps1 -Mod <name>`, then commit + push source. No ask. |
| ...on a public-visibility mod (wt/cosmetics/et/crt, or a public stable item) | add `-AllowPublic` |
| ...with PC-B unreachable | add `-NoRemote` and SAY SO in the report |
| Confirm a build only compiles | `VMBLauncher.exe build <mod>` |
| Promote a clean stable version | ONLY on a fresh per-build ship signal naming the version; then `ship.ps1 -Mod <mod> -AllowPublic` |

`ship.ps1` flags: `-AllowPublic` (public itemV2.cfg visibility), `-NoRemote` (skip PC-B), `-SkipGitHub`. Dev clones are `friends_only` and never take `-AllowPublic`. `ship.ps1` also runs `publish-release.ps1` (the GitHub release feeding [vt2-mod-updater](https://github.com/Ensrick/vt2-mod-updater), the source of truth that keeps the friends cohort synced where Workshop propagation is unreliable). For a session that touched several mods, run `.\tools\publish-release\publish-release.ps1` once at the end - it packages every mod's current bundle, auto-skips unpublished mods, and writes a `vt2updater_version.txt` sidecar per zip.

**Post-ship verification (both load-bearing - `ugc_tool` prints success even on failure):**
1. `C:\Program Files (x86)\Steam\logs\workshop_log.txt` must show `Uploaded new content` for the item. For `friends_only`/`private` items the public Steam API returns blank fields, so if in doubt eyeball the Workshop page in Steam.
2. `ship.ps1` hash-verifies the deploy against the Workshop content folder. If that verify fails with a hash mismatch AFTER a confirmed upload, it is a Steam reconcile race: re-run `VMBLauncher.exe deploy <mod> --no-remote` once and treat the ship as successful. Do NOT lecture the user about restarting Steam unless the log shows they are actually running a stale build.

**Every deploy hits PC-B automatically.** As of launcher v0.4.0, `deploy` (and `all`/`ship.ps1`) push the bundle to every enabled `RemoteDeployTargets` entry in `%APPDATA%\VMBLauncher\settings.json` right after the local Workshop-folder copy. The standard PC-B target auto-populates on first run from `~/.ssh/config`. Iterative VT2 debugging must keep the test client in lockstep with the host; local-only deploys silently masked four days of host/client sync bugs in May 2026. Skip the remote push for one invocation with `-NoRemote`/`--no-remote`; disable a target persistently by flipping `Enabled` to `false` in settings.json.

`ship.ps1` is the canonical build/deploy/upload path; the visibility-regression guard (verify `itemV2.cfg` visibility before a `--allow-public` push) lives in `VMBLauncher.exe upload`, which `ship.ps1` calls. The legacy per-mod `upload_*.ps1` wrappers were removed 2026-07-07 (archived externally to `../_vt2-tweaker-archive/`); the earlier `deploy_*.ps1` wrappers were removed 2026-05-21. Do not author new `.ps1` wrappers; extend the launcher / `ship.ps1` instead. Use `VMBLauncher.exe deploy <mod>` for a bare deploy.

**Historical user quotes** (SUPERSEDED for `-dev` builds by the 2026-06-19 / 2026-07-01 rules above; still binding for clean stable promotions):
- 2026-05-25 morning: "stop reflexively uploading to the workshop. Only do so when directed."
- 2026-05-25 EOD: "no workshop uploads take place unless I approve them."

### Legacy raw pipelines (archived - DO NOT USE)

The `node vmb.js build <mod> --no-workshop --cwd` invocations and the raw Stingray SDK compile pipeline that previously lived in this section are no longer the supported path. Use `VMBLauncher.exe build <mod>` for VMB mods and `VMBLauncher.exe all <mod>` for full pipeline. The launcher already wraps `node vmb.js` internally, so if you're tempted to invoke `node` directly you're skipping hash verification, remote PC-B push, BOM handling on staged cfgs, and the rest of the protective layers documented in `tools/vmb-launcher/CLAUDE.md`.

The one exception is the deprecated `tweaker` mod (Workshop ID 3704660429) - it pre-dates the VMB migration and only builds via raw SDK. Treat it as frozen: don't iterate on it, don't try to graft it onto the launcher.

### Version bumping

**Always increment `MOD_VERSION` before every build** - the version string is echoed in-game on load, confirming the correct build is running. Without a bump, you can't visually confirm the new code deployed.

**`MOD_VERSION` is the canonical source for the mod's Workshop title.** As of 2026-05-22, every Workshop upload appends/refreshes a trailing ` v<MOD_VERSION>` suffix on `itemV2.cfg`'s `title` field. Format: `<base_title> v<MOD_VERSION>`. Example: `Tweaker: Cosmetics v0.9.8.8`. The launcher's `upload` verb performs this rewrite automatically; the local cfg file's `title` is rewritten on each upload.

Rules:
1. **Every mod must define** `local MOD_VERSION = "X.Y.Z..."` near the top of `<mod>/scripts/mods/<mod>/<mod>.lua`. The launcher aborts the upload (rather than fall back to a date stamp) if no MOD_VERSION can be parsed - that surfaces gaps instead of hiding them.
2. **Base title** = the canonical title minus any existing trailing ` v<digits>` suffix. The launcher strips-and-reappends on each upload.
3. **Only the version suffix is auto-managed.** Description, visibility, preview, base title text remain user-dictated. See `tools/vmb-launcher/CLAUDE.md` section "ugc_tool pushes ALL cfg fields" for the full pre-upload checklist. Never auto-change those.
4. **Why:** subscribers see the version in their Workshop sub list (faster triage on crash reports), and the vt2-mod-updater app can read it directly from the title rather than the GitHub manifest.

#### Format: 3-segment semver only

`MOD_VERSION` follows `MAJOR.MINOR.PATCH[-track]`. Examples: `0.7.90-dev`, `0.12.68-dev`, `0.1.329-dev`, `1.0.0`. **Never add a 4th segment.**

- A change that fixes / adjusts / adds anything -> bump PATCH. `0.9.10-dev` -> `0.9.11-dev`. Don't bump within a patch via a 4th segment.
- PATCH can grow arbitrarily large (`0.1.329-dev` is fine). No need to roll over to MINOR.
- Pre-release track stays the same across patches - `alpha` stays `alpha`, `dev` stays `dev`. Only the user moves between tracks explicitly. The suffix is release-track only (`-alpha`/`-beta`/`-dev`/`-rc`), NEVER a change descriptor (`-revert`/`-hotfix`/`-la-icons`).
- If a mod has a stale 4-segment version (e.g. `0.9.9.4-dev`), normalize on the next bump by incrementing the third segment and dropping the fourth: `0.9.9.4-dev` -> `0.9.10-dev` (not `0.9.9.5-dev`). Past 4-segment versions stay in CHANGELOG as historical record - don't rewrite.

**Burned 2026-05-23:** cosmetics_tweaker drifted through `0.9.8.0-.9`, `0.9.9.0-.4`. Pattern came from treating the 4th segment as a within-patch hotfix counter - wrong instinct; just bump PATCH every time. Reset to `0.9.10-dev`.

### Local development setup

After cloning, run `./tools/install-hooks.ps1` to enable the local pre-commit hook. It runs `qa/run_all.ps1 -Quick -SkipLua` (cfg drift + MOD_VERSION / title suffix typos) and `tools/mod-lint/lint-mod.ps1` (duplicate hook registrations, forward-ref / late-local / save-restore / network-bound checks) against staged `*.lua` / `*.cfg` / `*.ps1` / `*.mod` files before the commit hits CI. **The gates block on ERRORS only; warnings report without blocking** (a QA change may be landing in parallel). The installer is idempotent. Bypass on a single commit with `git commit --no-verify` if you've verified the working tree locally and the hook is being overly cautious; cite the reason in the commit message. See `PROJECT_STANDARDS.md` section 8 for the escape-hatch convention.

## Multi-agent coordination

When more than one session / agent is working in this repo at the same time, parallel edits to the same mod cause silent breakage - broken builds blocking `publish-release.ps1`, MOD_VERSION reverts that mask real fixes, version-bump churn, etc. The 2026-05-25 session burned four times on this in a single afternoon (cwv v0.1.336 -> .339 churn, cim build broken twice, wt MOD_VERSION reverted 0.12.78 -> 0.12.77). The convention below is the fix - lightweight and advisory, not a locking mechanism.

- **`MOD_OWNERSHIP.md` (repo root)** - single table mapping every mod to its primary maintainer (`Ensrick` for all current mods) and a Status column: `stable` / `in-flight` / `frozen` / `blocked`. Read this before starting substantive work on a mod.
- **`.in_progress/<mod>.md` sentinel files** - when a session starts substantive multi-step work on a mod, drop a sentinel file at `.in_progress/<mod_name>.md` containing timestamp (`- **Started:** <ISO-8601-UTC>`), session ID, brief description, and files expected to be touched. Other sessions check this directory before starting work on the same mod. Sentinels are gitignored (advisory only); the README in that directory documents the template and is the only tracked file. Delete the sentinel when work finishes.
- **`qa/check_in_progress.ps1`** - wired into `qa/run_all.ps1`. Scans `.in_progress/`, warns on stale sentinels (>24h old), and cross-references staged files against claimed mods. Exit codes: 0 = clean, 1 = stale or staged-file collision, 2 = malformed sentinel. Never blocks - just surfaces awareness.
- **Workflow**: before editing a mod, (1) check `MOD_OWNERSHIP.md` for the row's status, (2) `Get-ChildItem .in_progress\*.md -Exclude README.md` to see active claims, (3) if no claim, drop your own sentinel + flip the MOD_OWNERSHIP row, (4) when done, remove the sentinel + flip the row back to `stable`.

The point is awareness, not enforcement - if a sentinel exists for a mod you need to edit, coordinate with the listed session/owner before stomping their in-flight state.

## Mod File Structure

All active mods use the VMB layout. Short internal IDs (`wt`, `ct`, `gt`, `crt`, `cim`, `mp`, `gut`) are the `new_mod()` registration name, not a separate directory pattern - those mods live under the same VMB layout as the long-ID ones. (`bt` used the same convention but is retired.)

```
<mod_name>/
|-- <mod_name>.mod                        # VMF entry point
|-- itemV2.cfg                            # Workshop upload config (MOD_VERSION suffix appended on upload)
|-- bundleV2/                             # Build output (VMB)
|-- resource_packages/<mod_name>/<mod_name>.package
\-- scripts/mods/<mod_name>/
    |-- <mod_name>.lua                    # Main logic - MOD_VERSION constant lives here
    |-- <mod_name>_data.lua               # VMF widget tree
    |-- <mod_name>_localization.lua       # Localized strings
    \-- _<feature>.lua                    # Per-feature subsystems (optional; see PROJECT_STANDARDS.md section 2.2 for docstring header rule)
```

**Legacy SDK layout** - only `tweaker/` (Workshop 3704660429, frozen) uses the SDK layout with `.build/OUT/`, `settings.ini`, and `upload/content/`. Do not iterate on it; do not pattern-copy from it.

## Architecture

### VMF Mod Pattern

Every mod registers via `new_mod(id, { mod_script, mod_data, mod_localization })`. The three files serve distinct roles:
- **`_data.lua`**: Returns a widget tree defining the VMF settings UI (checkboxes, sliders, dropdowns, groups)
- **`_localization.lua`**: Returns a table mapping setting IDs to `{ en = "Display Text" }` entries
- **`<mod>.lua`**: Main logic - hooks, commands, runtime data

Settings are read via `mod:get("setting_id")` and return the current value. Widget `setting_id` must match across data and localization files.

### Hooking

VMF provides `mod:hook(class, method, func)` and `mod:hook_safe(class, method, func)`:
- **String-form** `mod:hook("ClassName", "method", ...)` - lazy resolution, safe if class isn't loaded yet. **Use this by default.**
- **Table-form** `mod:hook(ClassTable, "method", ...)` - immediate resolution, required for plain tables like `BackendUtils` that aren't hookable by string. **Guard with nil check.**
- `mod:hook_safe` fires after the original function returns (no wrapping, no return value override).
- `_G` can be used to hook global functions: `mod:hook(_G, "Localize", ...)`

**Do NOT hook `BackendUtils.can_wield_item`** - it is not hookable from Workshop mods. Modify `ItemMasterList[key].can_wield` directly instead.

**`mod:hook_safe` does NOT chain on the same `Class.method`.** Two `mod:hook_safe(C, m, ...)` registrations on the same pair silently overwrite - only one body runs, with no error or warning. The diagnostic install log prints `Hooking '<m>' from [<C>]` twice with identical Origin pointers, but at runtime the shadowed handler never fires. Consolidate concerns (diagnostic + behavior) into a single callback per `(Class, method)` per mod. Full mechanic + burn history in `docs/VMF_RECIPES.md` section 1.

**Hook wrappers collapse multi-returns to one value.** Writing `return wrapper(func(self, ...))` drops every return after the first into the wrapper's argument list, where they are silently discarded. VT2 spawn / composition / `get_loadout` / `get_item_units` functions love returning 2-3 values - always capture them all into locals before transforming. Canonical WRONG/RIGHT block, burn history + full mechanic: `docs/VMF_RECIPES.md` section 2 (the owner doc for hooking rules; diagnosis pattern in `docs/BUG_CLASSES.md` section 2).

**`LootItemUnitPreviewer.spawn_units` MUST use `mod:hook`, not `hook_safe`.** Vanilla `_spawn_items` writes `self._spawned_units = units` AFTER `spawn_units` returns, so a `hook_safe` post-callback reads `nil`. Use the full wrapper and read units from the wrapped call's return. Hit twice (cosmetics_tweaker bret-thinning scale, character_weapon_variants v0.1.127). Full detail in `DEVELOPMENT.md` section "LootItemUnitPreviewer.spawn_units".

**`HeroPreviewer` / `MenuWorldPreviewer` slot keying is split.** `_item_info_by_slot` is **string-keyed** (`"melee"` / `"ranged"`); `_equipment_units` is **numeric-keyed** (`slot_index`). Bridge via `info.spawn_data[1].slot_index`. Iterating `_item_info_by_slot` and using the iterator key on `_equipment_units` returns nil silently. Hit twice (cosmetics_tweaker v0.7.88, character_weapon_variants v0.1.84). Full detail in `DEVELOPMENT.md` section "HeroPreviewer / MenuWorldPreviewer slot keying".

**`BackendUtils` dispatch caveat (LA bridge).** `BackendUtils` is a plain-table dispatcher; its functions are often reassigned at runtime by Loremaster's Armoury's "clone backend" pattern. Hooking `BackendUtils.get_item_from_id`, `.get_loadout_item_id`, etc. by string-form will silently miss calls routed through the LA clone path. See `docs/CROSS_MOD_ARCHITECTURE.md` "LA bridge" section for the dispatch model, the clone-backend_id pattern, and which methods need an explicit LA-aware hook. When in doubt, hook the table form against the post-LA `BackendUtils` reference, not the cold `_G.BackendUtils`.

**`rawget` for fragile globals.** Cold reads of `ItemMasterList[key]` and `NetworkLookup.weapon_skins[key]` will throw if a peer hasn't fully populated the table yet (CW peer-late-join, host-only DLC ownership, gated registration mismatch). Use `rawget(ItemMasterList, key)` / `rawget(NetworkLookup.weapon_skins, key)` and nil-check before dereferencing - full failure-mode table and the gated-registration crash class are in `DEVELOPMENT.md` "Known Errors" section.

### Three Weapon Rendering Paths

> Owner doc: `docs/WEAPON_APPEARANCE_STANDARD.md` §1 - the normative contract. It
> defines FOUR paths (the husk/remote path is separate from the owner in-world
> path) plus the concern-by-path matrix. The table below is the quick summary only.

Any weapon visual override must cover all three:

| Path | Hook Target | Hand Access |
|------|-------------|-------------|
| In-game (keep/mission) | `GearUtils.create_equipment` (or `GearUtils.spawn_inventory_unit`) | `result.left_unit_1p`, `.right_unit_1p`, `.left_unit_3p`, `.right_unit_3p` |
| Inventory character preview | **`MenuWorldPreviewer.equip_item` / `MenuWorldPreviewer._spawn_item`** (NOT HeroPreviewer - see below) | `self._equipment_units[slot].left` / `.right` |
| Illusion/skin browser | `LootItemUnitPreviewer.spawn_units` | `self._spawned_units` array (left=index 1, right=index 2) |

`MenuWorldPreviewer._spawn_item_unit` fires once per unit with **no hand indicator** - do not use it for per-hand operations.

**HOOK THE DERIVED CLASS, NEVER THE BASE.** Hooks on `HeroPreviewer.equip_item` / `HeroPreviewer._spawn_item` silently never fire on the keep inventory previewer instance. VT2's `foundation/scripts/util/class.lua:51-57` copies parent methods into the child *at class-definition time* (no `__index` chain). `MenuWorldPreviewer = class(MenuWorldPreviewer, HeroPreviewer)` runs at game load, before any mod loads - so by the time VMF replaces `HeroPreviewer.method`, `MenuWorldPreviewer.method` is already an independent copy of the original. The runtime keep inventory is `MenuWorldPreviewer` (verified at every `:new(...)` call site in `scripts/ui/views/`); `HeroPreviewer` itself is only instantiated by `team_previewer.lua`. Burned in weapon_tweaker v0.12.16 -> fixed in v0.12.17.

**In-mission player career detection caveat (in-game path):** career-gated hooks on `GearUtils.spawn_inventory_unit` (or `create_equipment`) must NOT rely on `Managers.player:owner(unit):career_name()` - at mission-spawn timing the unit->player reverse association isn't yet established, so the lookup returns nil and the hook silently bails. Read career from `ScriptUnit.has_extension(unit, "inventory_system")._career_name` instead - that field is set in `SimpleInventoryExtension.init` (line 47) BEFORE `extensions_ready` fires our hook.

### Shield/Weapon Unit Architecture

Shield weapons use **two independent units**: right hand (weapon) and left hand (shield). They attach to separate skeleton nodes and can be scaled, swapped, or offset independently. See `DEVELOPMENT.md` for unit paths and the `_weapon_scale_overrides` / `_custom_illusions` systems.

### Animation Remapping (weapon_tweaker)

**Load-bearing rule:** **1P animations are universal across all six characters and never need cross-character remapping.** The `first_person_base` unit is shared, so any weapon's 1P state machine and clips play correctly on any character's first-person view by default. Only the **3P body** is character-specific and needs remap work. Never override `anim_event` (1P), `wield_anim` (1P), or `state_machine` per character. Owner doc: `weapon_tweaker/DEVELOPMENT.md` (animation remap rules).

VT2 uses two separate units for the local player:
- `player.player_unit` = **3P body** (receives `anim_event_3p`) - character-specific skeleton, this is where remap work lives
- Separate non-player unit = **1P hands** (receives `anim_event`) - universal across characters, never touched

Cross-career weapons need animation redirects on the **3P side only** because different character 3P body skeletons have different event vocabularies. The system uses three layers:
1. **`_anim_redirect`**: global event renames
2. **`_career_anim_redirect`**: career-prefix-aware redirects
3. **`_suffix_career_map`**: suffix-based event swaps

For full **cross-character ports** (weapon X playable by character Y, rendered as Y's own 3P mesh + anims - e.g. brace-on-Kruber -> Repeating Handgun, longbow-on-Saltzpyre -> Crossbow), read `weapon_tweaker/CROSS_CHARACTER_PORT_RECIPE.md`. Seven-step procedure, failure-mode table, line citations into `weapon_tweaker.lua`, and verification matrix. Covers template patcher + force-load + in-mission unit swap + preview unit swap.

### Custom Illusion Injection (cosmetics_tweaker)

To add new selectable weapon skins at runtime, inject into three tables:
1. `ItemMasterList[skin_key]` - weapon_skin entry with `matching_item_key`
2. `WeaponSkins.skins[skin_key]` - unit paths and visual data
3. `WeaponSkins.skin_combinations[table_name]` - add to appropriate rarity tier

Then hook `BackendInterfaceCraftingPlayfab.get_unlocked_weapon_skins` to mark custom skins as unlocked, and hook `_G.Localize` for display names.

## Lua Environment

- **Lua 5.1** - use `unpack()`, NOT `table.unpack()`. `goto` is available in every active mod (all VMB-built); the SDK preprocessor's restriction only ever applied to the frozen legacy `tweaker`.
- Game globals: `ItemMasterList`, `WeaponSkins`, `Weapons`, `BackendUtils`, `GearUtils`, `Managers`, `Unit`, `World`, `Vector3`, `Quaternion`, `Material`, `Color`
- Console commands registered via `mod:command("name", "description", function(...) end)` - invoked in-game as `/<name>` directly (e.g. `/dump`, `/probe_hat`). There is NO mod-id prefix in chat: the mod-id you see in code (`wt`, `cos`, `ct`, etc.) is the mod's internal identifier, not a chat prefix. Documentation showing `/<mod> <command>` is wrong. Full per-mod command inventory in `docs/COMMANDS.md`.

**High-frequency engine quirks** (full mechanics in `DEVELOPMENT.md` section "Stingray / Lua engine quirks"):
- **`Unit.node(unit, name)` errors bypass `pcall`** - it's an engine-level fatal, not a Lua error. Use `Unit.has_node(unit, name)` (returns boolean) for existence checks. Same pattern applies to other Stingray `*.node` / `*.actor` APIs - prefer the `has_*` companion when it exists.
- **`Quaternion` / `Vector3` are stack temporaries** - valid only within the current frame. Storing the raw value in a global/table/upvalue silently corrupts on the next frame. Use `QuaternionBox` / `Vector3Box` / `Matrix4x4Box` for any storage that outlives a single statement; call `:unbox()` at apply time for a fresh raw value.
- **Lua 5.1 hard limit: 200 locals per function**, including the top-level chunk. Wrap helper groups in `do ... end` so their locals release back to the main chunk. Symptom is a Stingray compile error `main function has more than 200 local variables` - the cited line is the 201st local, not the problem source.
- **`#table` is undefined for arrays with nil holes.** Lua 5.1 `#t` does a binary boundary search over the array part - for `{1, nil, 2, nil, 3}`, the result could be 1, 3, or 5. Never use bare `unpack(t)` / `unpack(t, i)` if `t` may contain nils after position `i`. Capture the real count via `select("#", ...)` from the source variadic and pass `j` explicitly: `unpack(t, i, n)`. Burned in weapon_tweaker v0.12.77/.78 (2026-05-25 fix cycle through v0.12.79) - see `docs/VMF_RECIPES.md section 2a`.
- **`Unit.actor(unit, idx)` is 1-indexed** (vanilla pattern is `for i = 1, Unit.num_actors(unit)`). Iterating from 0 returns nil at index 0 and skips the final actor - silent no-op.
- **`pl.player_unit` is a FIELD, not a method.** `Managers.player:local_player().player_unit` (chained field access). `pl:player_unit()` crashes immediately.
- **`REAL_PLAYER_LOCAL_ID` is a file-scope local in vanilla, not a global.** Add `local REAL_PLAYER_LOCAL_ID = 1` near the top of any mod file that copy-pastes vanilla CW SharedState code, or the affected lookups silently return 0.

**Hooks that silently no-op:**
- **Upvalue capture bypasses table-entry hooks** - when a vanilla file does `local f = SomeTable.method` at the top, the upvalue holds the original function. Later `mod:hook("SomeTable", "method", ...)` only replaces the table entry; every call site through the captured local bypasses the wrapper. Grep for `local <name> = Class.method` before hooking. Fall back to mutating the data the function READS at call time.
- **Mutator template `server_*_function` is a dead field** - the engine wraps it into `template.server.start_function` (etc.) at boot. Hook the wrapped form, NOT `template.server_start_function`.
- **Self-owned vs husk extension classes** - `Simple*Extension` and `SimpleHusk*Extension` are separate root classes with no inheritance. Hooks on one don't fire for the other. Audit `scripts/network/unit_extension_templates.lua` and either hook both, or hook a global function both classes route through.

## DLC Ownership Gate (cross-mod)

**Modded mods unlock vanilla progression (career levels, crafting materials, XP grind), NOT paid DLC content.** When a mod surfaces / unlocks / grants items the player wouldn't otherwise have access to, it MUST respect the vanilla DLC paywall. Vanilla gate (used by the base game everywhere):

```lua
local data = rawget(<MasterTable>, key)        -- ItemMasterList / CareerSettings / DLCSettings / etc.
if data and data.required_dlc and Managers.unlock
   and not Managers.unlock:is_dlc_unlocked(data.required_dlc) then
    -- player does NOT own this DLC - skip
end
```

The DLC id lives on the master entry (`required_dlc` field). For tables that don't carry that field directly (mutator templates, level variations), look up the DLC by name in `scripts/settings/dlc_settings.lua` - entries register their content lists there. Pre-check with `Managers.unlock:dlc_exists(id)` before `is_dlc_unlocked(id)` to avoid the fassert at `unlock_manager.lua:527`.

**Three places the gate applies:**
1. **Enumerations** that walk `ItemMasterList` / `WeaponSkins.skins` / `CareerSettings` and surface entries to the player (e.g. crafting recipe lists, illusion grids, talent-swap dropdowns).
2. **Unlock hooks** that write into the backend mirror (e.g. `get_unlocked_weapon_skins`, `get_unlocked_cosmetics`, `get_unlocked_hero_portrait_frames`). Filter before the `mirror._unlocked_*[k] = true` write.
3. **Injection hooks** that push content into the lobby (e.g. event_tweaker's `get_special_events` / `get_active_events`). Filter before injection - the engine catches missing DLC at level-load with a confusing failure, so the mod should drop the entry cleanly instead.

**Helper pattern:** define a tiny `_X_requires_unowned_dlc(key) -> bool` per file (or shared via `mod._foo` for cross-file use). Examples:
- `cosmetics_tweaker.lua:43` - `_skin_requires_unowned_dlc(skin_key)` (reads `ItemMasterList`)
- `crafting_in_modded/illusion_swap.lua:51` - `_skin_requires_unowned_dlc(skin_key)` (same pattern, scoped to skins)
- `crafting_in_modded/standard_forge.lua:~40` - `_item_requires_unowned_dlc(item_key)` (weapons), exposed as `mod._cim_item_requires_unowned_dlc`
- `career_tweaker.lua:77` - `_career_requires_unowned_dlc(career_name)` (reads `CareerSettings`)
- `event_tweaker/.../event_tweaker_catalog.lua` (`DLC_BY_MUTATOR` / `DLC_BY_PRESET` maps) + `_evt_dlc.lua` (`owns_dlc(dlc_id)` helper) - mutator templates don't carry `required_dlc` directly

**Intentional exceptions.** `character_weapon_variants._build_entry()` (`character_weapon_variants.lua:~7895`) DELIBERATELY strips `required_dlc = nil` on its cloned variant entries because CWV variants are new mod-created items reusing base-package meshes - they are not the DLC content itself. Don't "fix" this. The blanket clearing is documented in CHANGELOG and CODE_REVIEW.md.

**DLC ids (verified 2026-05-18 against decompiled source `c:\Users\danjo\source\repos\Vermintide-2-Source-Code\scripts\settings\dlcs\`):**

| Career / Content | DLC id |
|---|---|
| Grail Knight (`es_questingknight`) | `lake` |
| Warrior Priest (`wh_priest`) | `bless` |
| Necromancer (`bw_necromancer`) | `shovel` |
| Outcast Engineer (`dr_engineer`) | `cog` |
| Sister of the Thorn (`we_thornsister`) | `woods` |
| Geheimnisnacht 2021 / Hard Mode mutators | `geheimnisnacht_2021` |
| Geheimnisnacht 2025 ritual-site engine | `geheimnisnacht_2025` |
| Skulls 2023 mutator | `skulls_2023` |
| Bardin Outcast Engineer's Cog | `cog` |
| Lake (Bretonnia) - used by `es_sword_shield_breton` etc. | `lake` |

For weapon DLCs (Bogenhafen / Karak Azgaraz / Lake), grep `scripts/settings/dlcs/<dlc>/item_master_list_<dlc>.lua` to see which `ItemMasterList` keys carry the `required_dlc` field.

**Audit history:** 2026-05-18 fan-out audit (`crafting_in_modded` v0.7.9-dev, `cosmetics_tweaker` v0.8.65-dev, `career_tweaker` v0.2.20-dev, `event_tweaker` v0.4.1-dev) caught and fixed four bypasses. Verified clean at the same date: `weapon_tweaker`, `chaos_wastes_tweaker`, `modded_progression` (scaffolding only - re-audit when loot hooks land), `enemy_tweaker`, `dynamic_cosmetic_portraits`, `general_tweaker`, and the `la_prefix` bridge (since folded into `cosmetics_tweaker/scripts/mods/cosmetics_tweaker/_la_prefix_embedded.lua`; no longer a standalone mod directory). When adding any new unlock surface to any mod, walk the three-places checklist above before merge.

## Important Constraints

- **Hot-reload crashes**: Ctrl+Shift+R is NOT safe for weapon_tweaker or cosmetics_tweaker - both hook unit creation paths (`GearUtils.create_equipment`, `BackendUtils.get_item_units`) and cosmetics_tweaker has non-Lua resources (materials/textures). The engine holds C++-level locks on spawned units that cannot be released from Lua. Always do a full game restart for these mods. chaos_wastes_tweaker, general_tweaker, and career_tweaker are Lua-only and may survive hot-reload, but a restart is still safest.
- **Never clean `.build/` unless file lock errors** - incremental builds work. Cleaning forces recovery.
- **Verify bundle output before deploying** - the compiler shows minimal console output; check the bundle dir for files.
- **Workshop upload verification**: `ugc_tool` prints "Upload finished" even when content fails to transfer. Always check Workshop page file size after upload.
- **Deploy via `VMBLauncher.exe deploy <mod>`** - the launcher handles every active mod (VMB-layout `bundleV2/`). The historical `deploy_all.ps1` shim was archived 2026-05-21 to `_archive/legacy_deploy_scripts/`; it only forwarded each `-Mods` entry to `VMBLauncher.exe deploy`.

## Key Reference Files

- `PROJECT_STANDARDS.md` - operational rulebook for the monorepo: workflow conventions, error-handling rules, logging conventions, anti-patterns to avoid, pre-ship checklists. Binding on Claude; cite section numbers when applying. Complements this CLAUDE.md (HOW the code works) with HOW WE WORK on it.
- `DEVELOPMENT.md` - detailed technical reference (hooking rules, animation system, shield swap architecture, known errors, Stingray / Lua engine quirks, dead ends).
- `docs/VMF_RECIPES.md` - repo-wide Vermintide Mod Framework gotchas: `hook_safe` no-chain, multi-return collapse, `network_send` recipients (`"server"` silently dropped), 500-char RPC string cap, dropdown options table mutation, widget setting_id uniqueness, mod `_localization.lua` not registered into global `Localize`, `custom_gui_textures` format. Every entry includes burn history.
- `docs/COMMANDS.md` - snapshot of every `mod:command(...)` across the monorepo (chat commands invoked as `/<name>`).
- `STATUS.md` - the single what-now board (replaced `TODO.md` / `WORK_ITEMS.md` / `TESTING_STATUS.md`, retired 2026-07-08, issue #432; pending work lives in GitHub Issues)
- `ITEM_LIST.md` - full weapon key catalog from ItemMasterList
- `docs/WEAPON_CATALOG.md` - repo-root weapon catalog: model paths, owning character, cross-character port status, illusion family membership. Use alongside `ITEM_LIST.md` when wiring a new weapon-side feature.
- `ANIMATION_RESEARCH.md` - skeleton event probe results across the six character bodies
- `docs/CROSS_MOD_ARCHITECTURE.md` - weapon sharing & cosmetics architecture across weapon_tweaker, cosmetics_tweaker, character_weapon_variants, and modded_progression. Contains the LA bridge dispatch model referenced from the Hooking section above.
- `weapon_tweaker/CROSS_CHARACTER_PORT_RECIPE.md` - seven-step procedure for adding a full cross-character weapon port (template patcher + force-load + in-mission unit swap + preview unit swap). Failure-mode table, line citations into `weapon_tweaker.lua`, verification matrix.
- `character_weapon_variants/DEFINITION_OF_DONE.md` - **MANDATORY GATE BEFORE DECLARING ANY CWV VARIANT COMPLETE.** Universal checklist (IML verified, build-from-ground-up integrity, scale/grip, icons, loc, forward-ref audit, build hygiene, live verification matrix) plus trait-gated checklists (G-DUAL, G-RANGED, G-THROWN, G-CROSS-CHAR, G-BLACKSMITH, G-MESH-FAMILY, G-3P-ANIM, G-STANCE, G-CUSTOM-ILLUSION). Variant CHANGELOG entries must end with the `**DoD:**` footer naming which gates were walked and any explicit deferrals. The repeated bug class of "looks right, breaks on equip / fire / forge / preview / dual-wield" is exactly what this file catches.
- `character_weapon_variants/RECIPES.md` - **READ THIS BEFORE ADDING A NEW VARIANT.** Decision tree (single-melee / 2H / shield / identical-mesh dual / mixed-mesh dual / ranged-ammo / skin-only / cross-access / custom illusion) plus per-archetype copy-paste recipes referencing shipped variants as canon, plus pre-deploy checklist and verification matrix. Each archetype has its own gotchas (dual-wield needs `_force_display_unit`, ranged ammo needs full skin-mirror + custom Pickups + projectile init hook, fire-DoT removal is a 3-step swap, etc.) - the recipes spell them out so you don't rediscover them. The DoD gate (above) supersedes the pre-deploy checklist and verification matrix in this file.
- `character_weapon_variants/DEVELOPMENT.md` - architectural reference for variant creation: rarity system, blacksmith template pattern, skin system, icon atlases, properties/traits, registration timing, custom templates / stat modifications, model scaling, base-weapon catalog. Cross-references RECIPES.md and ANIMATION_FIX_PLAYBOOK.md.
- `character_weapon_variants/ANIMATION_FIX_PLAYBOOK.md` - 9-step closed-vocabulary procedure for fixing 3P animations on cross-character variants. Read before touching `anim_event_3p`, `wield_anim_3p`, or any `_cross_access_action_remap` entry.
- `character_weapon_variants/J_LEFTWEAPONATTACH_INVESTIGATION.md` - post-mortem for the ~20-version dual-wield rig saga. Read once before adding any dual-wield variant.
- `character_weapon_variants/CHANGELOG.md` - version history for the Character Weapon Variants mod. Best source of "why we do X" - most recipes have a CHANGELOG entry behind every load-bearing rule.
- `character_weapon_variants/CODE_REVIEW.md` - snapshot architectural review for CWV. (Per-doc currency/staleness is tracked in `PROJECT_STANDARDS.md` section 7.1, the canonical doc index - not version-stickered here, since those stickers drift.)
- `character_weapon_variants/TODO.md` - feature roadmap for cross-character weapon variants
- `cosmetics_tweaker/TODO.md` - feature roadmap for cosmetics-specific work
- `dynamic_cosmetic_portraits/CLAUDE.md` - **READ THIS BEFORE TOUCHING PORTRAITS.** Workflow guardrails + the canonical asset-generation script.
- `dynamic_cosmetic_portraits/tools/add_portrait.ps1` - the only correct way to generate a new portrait's `.png` / `.texture` / `.material` files. Call it as `.\tools\add_portrait.ps1 -SourcePng "<110x130 PNG>" -HatKey "kruber_<key>"`. Free-handing the assets has broken multiple shipped versions; do not skip the script.
- `dynamic_cosmetic_portraits/CHANGELOG.md` - version history. v0.1.0 -> v0.1.3 documents every variant of the asset-pipeline mistake - read before reinventing.
- `dynamic_cosmetic_portraits/DEVELOPMENT.md` - full portrait-authoring workflow + career_settings swap architecture + dead ends not to retry.
- `dynamic_cosmetic_portraits/TODO.md` - portrait roadmap (which hats/careers/characters are next).
- `dynamic_cosmetic_portraits/CHARACTER_COSMETIC_CATALOG.md` - every `slot_hat`/`slot_skin` item key -> in-game display name across all 5 characters (sourced from `cosmetics_tweaker/_cos_probe.txt`). **Consult this whenever wiring a new portrait - it's the only reliable mapping from a key to a player-facing name.**
- `event_tweaker/CLAUDE.md` - workflow guardrails for the `_evt_*` module split: injection guards are load-bearing, catalogs are single-source, one hook per (Class, method). Read before touching the mod.
- `event_tweaker/CHANGELOG.md` - version history for the Tweaker: Events mod.
- `event_tweaker/DEVELOPMENT.md` - module contracts + "where new code goes" placement recipe, architecture (3 hooks: `get_special_events` / `get_active_events` / `get_level_variation_data`), how to add a new mutator or preset, sharp edges (special_events `name` field, hub-skip in `append_live_event_mutators`, keep-reload caveat).
