# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

> **READ FIRST**: `PROJECT_STANDARDS.md` (repo root) is the operational rulebook
> for HOW we work in this repo — workflow conventions, error-handling rules,
> logging conventions, anti-patterns to avoid, pre-ship checklists. This
> `CLAUDE.md` describes HOW the code works (technical reference); the standards
> doc describes how WE work on it. When in doubt, cite the section.
>
> **Bug class catalog: `docs/BUG_CLASSES.md`** — match symptoms against known
> patterns before deep dive. Most bug reports are repeats of a class already
> shipped, debugged, and fixed elsewhere in the monorepo. Triage workflow lives
> in `docs/BUG_TRIAGE_RUNBOOK.md`.
>
> **🛑 STOP: BEFORE WRITING ANY `mod:hook(...)` OR `mod:hook_safe(...)` LINE 🛑**
>
> VMF silently drops the SECOND hook on the same `(Class, method)` pair from
> the same mod (whether `mod:hook` or `mod:hook_safe`, doesn't matter — same
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
> When in doubt: search for `"<method>"` (with quotes) in the file. A grep that returns more than one hit on `mod:hook` or `mod:hook_safe` is a bug, full stop. Reference: `VMF_RECIPES.md` § 1 + `memory/feedback_vmf_no_duplicate_hooks.md`.

## Project Overview

A modular set of **Vermintide 2** VMF (Vermintide Mod Framework) mods written in Lua 5.1. Originally a monolithic mod ("Tweaker"), now split into focused sub-mods. Runs on the Stingray engine. The VT2 decompiled source code lives at `c:\Users\danjo\source\repos\Vermintide-2-Source-Code` — use it as a reference for game APIs, class structures, and data tables.

## Documentation Map

Navigation anchor for the entire monorepo's docs. `CLAUDE.md` (this file) is the
technical entry point; from here, follow the tree to the topic-specific reference.

> This map is a **navigation aid** (file → one-line purpose). It deliberately
> does NOT carry per-file version or staleness stickers — those drift faster
> than the map gets updated. The canonical doc index, including which docs are
> required/current for which mods, is `PROJECT_STANDARDS.md` §7.1.

**Tier 1 — repo-wide (read first):**
- `CLAUDE.md` (this file) — technical overview: how every mod is wired, the build pipeline, the architecture invariants.
- `PROJECT_STANDARDS.md` — operational rulebook: workflow conventions, error-handling rules, logging conventions, anti-patterns, pre-ship checklists. Binding when working on any mod.
- `docs/BUG_CLASSES.md` — catalog of known bug patterns this repo has seen (symptom -> diagnosis pattern -> fix template + Issue/commit citation). Pattern-match here FIRST on any bug report before deep dive.
- `docs/BUG_TRIAGE_RUNBOOK.md` — workflow for using the bug-class catalog: intake, match, fix, verify, document.
- `docs/MECHANICS.md` — provenance-enforced index of how VT2 / Stingray mechanics actually work. Every factual bullet carries a provenance tag (`[src: file:line]` / `[dump:]` / `[memory:]` / `[bugclass:]` / `[user:]` / `[unverified]`). **Before stating any mechanic, grep the decompiled source and cite it, or write `[unverified]` — never confabulate** (PROJECT_STANDARDS § 12a capture doctrine). `qa/check_mechanics_citations.ps1` fails on any untagged claim. This is an INDEX that points at source/memory/BUG_CLASSES, not a fourth prose surface.
- `DEVELOPMENT.md` — historical/detailed technical reference (hooking rules, animation system, shield swap architecture, known errors). Pre-dates this CLAUDE.md but still authoritative for the topics it covers.
- `CROSS_MOD_ARCHITECTURE.md` — how `weapon_tweaker`, `cosmetics_tweaker`, `character_weapon_variants`, and `modded_progression` interact at runtime; LA bridge pattern; co-installed-mod detection.

**Tier 2 — repo-wide topical:**
- `WORK_ITEMS.md` — current status of working features and animation remap tables.
- `TODO.md` — feature roadmap across all mods.
- `ITEM_LIST.md` — full weapon key catalog from `ItemMasterList`.
- `WEAPON_CATALOG.md` — repo-level weapon catalog (model paths, ownership, cross-character status).
- `ANIMATION_RESEARCH.md` — skeleton event probe results across the six character bodies.
- `LOCALIZATION_STANDARD.md` — string-table and naming conventions for `*_localization.lua`.
- `REGRESSION_CHECKLIST.md` — repo-wide regression gates (per-mod ones live under each mod folder).
- `CHANGELOG.md` — repo-aggregate release notes.
- `VMF_RECIPES.md` — Vermintide Mod Framework gotchas (hook_safe chaining, multi-return collapse, network_send recipients, RPC string cap, dropdown options mutation, widget setting_id uniqueness, mod localization scope, custom_gui_textures format).
- `COMMANDS.md` — per-mod chat command inventory (every `mod:command(...)` across the repo).

**Tier 3 — per-sub-mod docs worth reading from outside the mod (each mod also has its own CHANGELOG.md + REGRESSION_CHECKLIST.md):**

- `character_weapon_variants/`:
  - `DEFINITION_OF_DONE.md` — mandatory gate before declaring any CWV variant complete.
  - `RECIPES.md` — decision tree + per-archetype copy-paste recipes.
  - `DEVELOPMENT.md` — architectural reference for variant creation (template patterns, scale/grip, custom mesh, known errors).
  - `ANIMATION_FIX_PLAYBOOK.md` — closed-vocabulary procedure for fixing 3P animations on cross-character variants.
- `chaos_wastes_tweaker/`:
  - `DEVELOPMENT.md` — engine gotchas: dormant buff registration, deus rarities, adventure mutator compat, NetworkedFlowStateManager leak, jewelry traits as boons, walk-through interactable, graph-snapshot RPC.
  - `TODO.md` — planned features (altar cost config, CW inventory).
- `cosmetics_tweaker/`:
  - `DEVELOPMENT.md` — three weapon rendering paths + cosmetic-specific recipes.
  - `LA_SYNC_MODEL.md` — full LA bridge architecture + § 6 gotcha catalogue (kind=texture/unit hats and shields, husk RPC race, offhand preload, hook_safe shadow).
  - `GLOW_SYSTEM.md` — MaterialSettingsTemplates engine reference + override mechanism.
- `dynamic_cosmetic_portraits/`:
  - `CLAUDE.md` — workflow guardrails for the portrait pipeline (read before touching portraits).
  - `DEVELOPMENT.md` — career_settings swap, texture/alpha requirements, VMF renderer-creator keys.
- `enemy_tweaker/`:
  - `DEVELOPMENT.md` — breed-adding checklist (pairs(Breeds) at boot, threat_values upvalue), architecture overview.
  - `EXPANSION_PLAN.md` — spawn-parity roadmap.
- `event_tweaker/`:
  - `DEVELOPMENT.md` — three hooks (`get_special_events`, `get_active_events`, `get_level_variation_data`) plus mutator/preset registration and confirmed mutator catalog.
- `modded_progression/`:
  - `PLAN.md` — full design for the modded-realm vanilla-progression re-enable.
- `verminious_dreams_lighting/`:
  - `DEVELOPMENT.md` — per-mission lighting tuning architecture (ShadingEnvironment + Light overrides for dlc_termite_1/2/3).
- `weapon_tweaker/`:
  - `ANIMATION_COVERAGE.md` — **the release walk list**: per-(receiver, weapon) 3P animation status matrix (working / wired-unverified / decided-not-wired / undecided), the tune→export→bake workflow, and the model-substitute queue. Source of truth for "what's left before wt releases" (added 2026-06-11).
  - `CROSS_CHARACTER_PORT_RECIPE.md` — seven-step procedure for adding a new cross-character weapon port.
  - `DEVELOPMENT.md` — design direction + animation remap rules (per-unit state, closed-vocabulary, 3P fix process, character-skeleton constraints).

**Tier 4 — tooling:**
- `tools/vmb-launcher/CLAUDE.md` — VMBLauncher doctrine (verbs, flags, preflight gates, visibility-public safety, remote-deploy config).
- `tools/publish-release/README.md` — GitHub-release pipeline that publishes built bundles for `vt2-mod-updater` consumers.
- `tools/mod-lint/README.md` + `qa/CHECKS.md` — luacheck + custom QA scans.

Full per-file index is in the **Key Reference Files** section at the bottom.

## Bug triage

On receiving a user bug report, read `docs/BUG_TRIAGE_RUNBOOK.md` first — it's the 60-second orientation (phase 1 reads, bug-class match, deep-dive log patterns, fix checklist with the `_rt_register` + `/verify_<feature>` + GitHub-release steps, post-fix hardening) and is the single entry point any session should use before diving into mod source.

## Mod Directory

| Mod | Internal ID | Workshop ID | Build System | Stream | Purpose |
|-----|-------------|-------------|--------------|--------|---------|
| weapon_tweaker | `wt` | 3712896117 | **VMB** | single | Cross-character weapon access with full freedom: any character can wield any weapon (1P universal, never touched), with 3P anim events remapped into a functionally-similar receiver-native weapon's vocab so the bystander view stays plausible (e.g. brace-on-Kruber renders as Repeating Handgun in 3P, longbow-on-Saltzpyre as Crossbow). **Direction reversal 2026-05-23:** identical-functional ports (Bardin's axe on Saltzpyre when Saltzpyre already has a falchion-family native, etc.) are being removed from wt and absorbed into `cosmetics_tweaker` as a cross-character cosmetic swap. wt retains only genuine functional cross-character ports. |
| chaos_wastes_tweaker | `ct` | 3712929235 | **VMB** | stable | CW economy, curses, boons, altars, traits. Public Workshop; only merged-down releases land here — in-flight work happens in `chaos_wastes_tweaker_dev`. |
| chaos_wastes_tweaker_dev | `ct_dev` | 3733366926 | **VMB** | dev | In-flight `ct` work; friends-only Workshop clone. Distinct VMF mod registration (`ct_dev`) so it can coexist with stable `ct` in the same install. See § "Dev/stable split workflow". |
| general_tweaker | `gt` | 3713619122 | **VMB** | stable | 3rd person camera, noclip, freecam, godmode, in-mission keep menus, debug/data dumps, **host-side lobby controls (absorbed from lobby_tweaker 2026-05-25):** slot reservations, session ignore list, kick-on-idle, MOTD broadcast, modded-realm failed-join mod-list reveal. Lobby settings + chat commands namespaced `gt_lobby_*`. Defines `mod.GT_LOBBY_RPC_SCHEMA = 1` for the `gt_lobby_motd_show` RPC per VMF_RECIPES § 10. Public Workshop; only merged-down releases land here — in-flight work happens in `general_tweaker_dev`. |
| general_tweaker_dev | `gt_dev` | 3733367409 | **VMB** | dev | In-flight `gt` work; friends-only Workshop clone. Distinct VMF mod registration (`gt_dev`) so it can coexist with stable `gt` in the same install. Caveat: `GT_LOBBY_RPC_SCHEMA` is per-mod-id, so dev and stable can't share a lobby RPC channel — friends running dev should all pin to dev for a session. See § "Dev/stable split workflow". |
| gui_tweaker | `gut` | 3732144878 | **VMB** | single | Quality-of-life features for the hero/character GUI. v0.1 ships save/swap loadout via chat commands (`/gut_save_loadout N`, `/gut_load_loadout N`, `/gut_list_loadouts`) — a clean reimplementation of the sanctioned `loadout_manager_vt2` that fixes the gear/cosmetic namespace-merge bug. v0.2.0-dev adds in-game HUD customization: hold LEFT ALT while chat is focused OR `/gut_edit_hud` for sticky toggle, then click-drag any of 10 registered widgets (ability/equipment/overcharge/career-ability/energy/buff/boss-health/challenge-tracker/loot-objective/news) to reposition. Per-resolution persistence. Resize via corner-handles deferred to v0.2.1. Future v0.3+ adds HeroView UI integration. Scaffolded 2026-05-24. |
| cosmetics_tweaker | `cosmetics_tweaker` | 3715714222 | **VMB** | single | Hat/skin unlocks, weapon model tweaks, shield swaps, custom illusions. **Scoped 2026-05-23:** cross-character cosmetic swap for functionally-identical weapons (e.g. Bardin's axe model rendered on Saltzpyre's falchion family) with per-receiver scaling + grip offset adjustments — absorbs the identical-functional ports being removed from wt. |
| dynamic_cosmetic_portraits | `dynamic_cosmetic_portraits` | 3721036701 | **VMB** | single | Hat/outfit-aware HUD & hero-select character portraits (split from cosmetics_tweaker 2026-05-06) |
| career_tweaker | `crt` | 3716286199 | **VMB** | single | Talent/ability swapping (scaffolded) |
| enemy_tweaker | `enemy_tweaker` | 3716780252 | **VMB** | single | Enemy spawns, horde compositions, breed substitution |
| character_weapon_variants | `character_weapon_variants` | 3716869446 | **VMB** | single | Semi-lore-friendly new variant items that intentionally clone from cross-character base templates to bring other characters' movesets onto receivers (MoreItemsLibrary). 1P wield/stance differentiates the feel even when two variants are functionally identical; 3P side uses `anim_event_3p` remap into a good-enough native vocab so bystanders see something plausible. Planned hammer/mace differentiation toggle will further separate sibling variants on the same base. Variants are designed to *play differently enough* to feel like natural new weapons, distinct from wt's full-freedom cross-character access. |
| crafting_in_modded | `cim` | 3721038774 | **VMB** | stable | Modded crafting menus — Athanor forge UI for crafting any career-eligible weapon. Split from `wt` 2026-05-05. Public Workshop; only merged-down releases land here — in-flight work happens in `crafting_in_modded_dev`. |
| crafting_in_modded_dev | `cim_dev` | 3733366851 | **VMB** | dev | In-flight `cim` work; friends-only Workshop clone. Distinct VMF mod registration (`cim_dev`) so it can coexist with stable `cim` in the same install. See § "Dev/stable split workflow". |
| event_tweaker | `event_tweaker` | 3721290755 | **VMB** | single | Host-side mutator picker (Workshop title "Tweaker: Events"). VMF dropdown for canonical event presets (Geheimnisnacht / Skulls — drives mutator + active_events string + keep-level swap) plus checkbox-per-mutator across difficulty / specials / hordes / atmosphere / objectives / winds / raw event categories. Three hooks: `BackendInterfaceLiveEventsPlayfab.get_special_events`, `get_active_events`, `BackendManagerPlayFab.get_level_variation_data`. Scaffolded 2026-05-06 |
| modded_progression | `mp` | 3730422873 (private) | **VMB** | single | Re-enables 100% of vanilla VT2 progression in modded realm: XP, shillings, loot chests, Okri's Challenges, Lohner's Emporium, keep crafting bench. Intercepts `BackendInterface*Playfab` methods; writes through `backend_mirror` mutators; persists locally via VMF settings; never commits to PlayFab. Sibling API (`mp.is_unlocked` / `mp.spend` / `mp.credit` / `mp.grant_item`) consumed by CWV + cosmetics_tweaker when both installed. Three starting-state options. See `modded_progression/PLAN.md` for full design. Scaffolded 2026-05-14 |
| buff_tweaker | `bt` | 3730358590 | **VMB** | **RETIRED** | **Retired 2026-06-08; archived to `_archive/buff_tweaker_v0.1.12-alpha/`.** Was the shared Big Rebalance registry (buffs / damage profiles / explosion templates, deterministic sorted order) + `net_replay` ring buffer. Consumers (wt/ct/et/crt) reference it via the guarded `if not (bt and bt.is_br_active) then return false end` pattern, so their BR sub-features go **inert (no crash)** now that bt is gone — they were NOT stripped from the consumers. Friends-only Workshop item 3730358590 still live; delete in Steam if desired. |
| verminious_dreams_lighting | `verminious_dreams_lighting` | 3727221800 | **VMB** | stable | Per-mission lighting overhaul for the three Verminious Dreams DLC missions (The Forsaken Temple / Devious Delvings / The Well of Dreams). Ships per-mission ShadingEnvironment + Light component overrides; live tuning via `/vdl_*` chat commands. Client-side only — no host requirement, no version-sync risk. Public. Only merged-down releases land here — in-flight work happens in `verminious_dreams_lighting_dev`. |
| verminious_dreams_lighting_dev | `verminious_dreams_lighting_dev` | 3733366748 | **VMB** | dev | In-flight `verminious_dreams_lighting` work; friends-only Workshop clone. Distinct VMF mod registration (`verminious_dreams_lighting_dev`) so it can coexist with stable in the same install. See § "Dev/stable split workflow". |
| tweaker (legacy) | `t` | 3704660429 | Stingray SDK | frozen | Deprecated — split into above mods |

## Dev/stable split workflow

**Why the split exists.** The four public-Workshop mods (`ct`, `cim`, `gt`, `verminious_dreams_lighting`) have a mixed audience: public subscribers expect a stable bundle that doesn't break weekly, and the friends cohort wants visibility into in-flight work as it's being iterated on. Shipping every dev iteration to the public Workshop item caused subscriber loss (~80 cim subs in a few days in May 2026 from reflex uploads pushing unstable mid-fix builds). The fix is two parallel Workshop items per split mod: dev = friends-only, stable = public.

**What's split.** Only the four public mods. Everything else is single-stream (already friends-only or unpublished — `wt`, `cosmetics_tweaker`, `cwv`, `et`, `crt`, `gut`, `bt`, `dcp`, `mp`).

| Stable directory | Stable mod_id | Stable Workshop ID | Dev directory | Dev mod_id | Dev Workshop ID |
|---|---|---|---|---|---|
| `chaos_wastes_tweaker/` | `ct` | 3712929235 (public) | `chaos_wastes_tweaker_dev/` | `ct_dev` | 3733366926 (friends-only) |
| `crafting_in_modded/` | `cim` | 3721038774 (public) | `crafting_in_modded_dev/` | `cim_dev` | 3733366851 (friends-only) |
| `general_tweaker/` | `gt` | 3713619122 (public) | `general_tweaker_dev/` | `gt_dev` | 3733367409 (friends-only) |
| `verminious_dreams_lighting/` | `verminious_dreams_lighting` | 3727221800 (public) | `verminious_dreams_lighting_dev/` | `verminious_dreams_lighting_dev` | 3733366748 (friends-only) |

**Where work happens.**

- **`<mod>-dev/`** — all new feature work, in-flight fixes, experiments. Build/deploy/upload from here during the dev loop. MOD_VERSION carries the `-dev` (or `-alpha`/`-beta`) suffix.
- **`<mod>/`** — stable releases only. When dev work matures and the user signs off on a release, cherry-pick or merge the changes into the stable dir, normalize MOD_VERSION (strip `-dev`/`-alpha`/etc.), then `build` + `deploy` + `upload` to the public Workshop item. The stable directory should never contain in-flight `-dev` work between releases.

**Mod ID convention.** Stable carries the short canonical id (`ct`, `cim`, `gt`, plus the long `verminious_dreams_lighting`). Dev carries the `_dev` suffix (`ct_dev`, `cim_dev`, `gt_dev`, `verminious_dreams_lighting_dev`). Because these are distinct VMF mod registrations, both items can be subscribed simultaneously without conflict — a tester running dev keeps the stable item installed but disabled, or runs both side-by-side if their behaviors don't overlap destructively.

**Cross-mod refs always target stable.** External mods (CWV, cosmetics_tweaker, et, etc.) that consume sibling mods via `get_mod("cim")` / `get_mod("gt")` / `(get_mod('bt') or {}):is_br_active()` MUST resolve against the stable mod_id. Dev clones are isolated test surfaces; nothing external consumes them. If you need a cross-mod hook to fire against dev for testing, edit the consumer's `get_mod(...)` call to point at the dev id locally — never ship that change to a stable directory.

**Caveat — per-mod-id RPC channels.** Anything keyed by mod_id (network channels, lobby data slots, the `GT_LOBBY_RPC_SCHEMA` constant in `gt`) is automatically isolated between stable and dev because the mod_ids differ. That's the desired isolation in most cases, but it means **dev and stable can't talk to each other over a lobby RPC**. If a session needs the lobby/MOTD/slot-reservation surface, every peer should pin to the same stream (all dev or all stable). Don't mix.

**Upload doctrine** — same per-build approval rule as every other upload in this repo (see `PROJECT_STANDARDS.md` § 6 and the Build Commands section below). Two additional gates apply to the split mods:

- **Dev uploads** target the friends-only Workshop item. `visibility = "friends_only"` in the dev clone's `itemV2.cfg`. The launcher does NOT require `--allow-public` for these and never will — dev clones must not be promoted to public visibility under any circumstance.
- **Stable uploads** target the public Workshop item. They require `--allow-public` (the launcher's visibility gate) AND a fresh per-build ship signal from the user — "ship it" said three bug-fixes ago does not carry forward. Use the `upload_*.ps1` wrapper at repo root (which carries an extra visibility-regression guard on top of `VMBLauncher.exe upload --allow-public`).
- **GitHub release** still required after every Workshop upload of either stream (per `tools/publish-release/README.md`) so `vt2-mod-updater` consumers stay in sync — especially the friends cohort, where Workshop propagation is unreliable.

## Build Commands

### Required: VMBLauncher headless CLI

VMBLauncher is **the only** sanctioned path to build / deploy / upload any VT2 mod in this repo. Not "preferred" — required. Do NOT invent ad-hoc PowerShell pipelines, raw `node vmb.js`, raw `ugc_tool` calls, raw `scp` to PC-B, or wrap the SDK compiler by hand. Every one of those one-off paths has burned multiple iterations in the past (hash-unverified deploys, stale PC-B, missed UTF-8 BOM, 0x2 empty-content-directory, wrong scp protocol, etc.). If the launcher binary is missing on the current machine, rebuild it via `tools/vmb-launcher/publish.ps1 -SkipOpen` before doing anything else.

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

Same code as the GUI buttons; streams VMB output live to stdout; exit codes 0/1/2/3. **Read `tools/vmb-launcher/CLAUDE.md` for the full doctrine** — verbs, flags, preflight gates, visibility-public safety, remote-deploy config, the PowerShell pipeline-truncation quirk, GUI/headless detection rule.

### Default iteration workflow (2026-05-25 doctrine — IMPORTANT, REINFORCED 2026-05-25 EOD)

**HARD RULE: NO Workshop upload happens without explicit per-build user approval. Every upload needs its OWN ship signal — a standing "ship it" from earlier in the session does NOT carry forward to the next build.**

**Workflow the user wants:**

1. **Develop** in source (edit, `build`, optionally `deploy` to PC-A / PC-B for local testing).
2. **Test** in-game until the user confirms stability and that reported issues are fixed.
3. **User explicitly approves the upload** — naming the version and the verb (e.g. "ship v0.7.45 now", "upload cim", "push to friends").
4. **Then** `upload` (or `all` if also fresh-building) + `publish-release.ps1`.

A dev branch may be introduced if iterative pre-ship work warrants it — the user will direct that decision.

**Default: `build` + `deploy`. NEVER `upload` or `all` unless the user has approved THIS specific build for shipping.**

The user iterates many times per session. Every `upload` pushes to Steam Workshop and is visible to friends. Reflex-using `all` (which includes upload) means every dev iteration goes live to friends — they get broken/half-baked bundles. Earlier user directives:

- 2026-05-25 morning: "stop reflexively uploading to the workshop. Only do so when directed. Just deploy to PC-A and PC-B."
- 2026-05-25 EOD: "no workshop uploads take place unless I approve them. We develop the game, test to ensure stability and issues are fixed, and then upload to the workshop."

| User intent | Verbs to use |
|---|---|
| Iterate / test locally | `build` then `deploy` (deploy auto-pushes to PC-B too) |
| Confirm build compiles | `build` alone |
| **Ship to Workshop (REQUIRES FRESH PER-BUILD APPROVAL)** | `upload <mod>` (or `upload_*.ps1` wrapper for public), then `publish-release.ps1` |
| Bulk ship (also requires fresh approval) | `all <mod>` per mod, then `publish-release.ps1` |

**For agents:** NEVER chain `upload` or `all` in a fix flow. Friends-visible Workshop pushes are production deploys, not free iteration. "Ship it" said three hours ago does NOT authorize an upload three bug-fixes later — re-confirm before each push. When in doubt: `build + deploy --no-remote` and report back; let the user decide when to ship. Treat upload like `git push --force` — it ALWAYS warrants a fresh ask.

**Every deploy hits PC-B automatically.** As of launcher v0.4.0, `deploy` (and `all`) push the bundle to every enabled `RemoteDeployTargets` entry in `%APPDATA%\VMBLauncher\settings.json` right after the local Workshop-folder copy succeeds. The standard PC-B target auto-populates on first run from `~/.ssh/config`. Per `feedback_deploy_both_machines.md` — iterative VT2 debugging must keep the test client in lockstep with the host; local-only deploys silently masked four days of host/client sync bugs in May 2026. Skip the remote push for one invocation with `--no-remote`; disable a target persistently by flipping `Enabled` to `false` in settings.json.

The `upload_*.ps1` wrappers at repo root are kept because each carries a visibility-regression guard on top of `VMBLauncher.exe upload` (verifies `itemV2.cfg` visibility matches expectation before allowing a `--allow-public` push). Do not author new `.ps1` wrappers; extend the launcher instead.

The legacy `deploy_*.ps1` wrappers (`deploy_all.ps1`, `deploy_ct.ps1`, `deploy_gt.ps1`, `deploy_wt.ps1`) were archived 2026-05-21 to `_archive/legacy_deploy_scripts/` — they only delegated to the launcher with no added value. Use `VMBLauncher.exe deploy <mod>` directly (or `VMBLauncher.exe all <mod>` for full build+deploy+upload).

**Always verify Workshop file size after upload** — `ugc_tool` prints `Upload finished` even when content didn't transfer. For public mods that's automatable via `ISteamRemoteStorage/GetPublishedFileDetails`; for `friends_only`/`private` items the public API returns blank fields, so eyeball the Workshop page in Steam.

### Required: GitHub release after every Workshop upload

After every Workshop upload, also publish the built bundles to a GitHub release on this repo. This is non-optional — it's the source of truth that the [vt2-mod-updater](https://github.com/Ensrick/vt2-mod-updater) app reads to keep friends' Workshop folders synced (especially for `friends_only` mods, where Workshop propagation is unreliable and new friends often can't see the items at all).

```powershell
& $vmblauncher all <mod>                          # build + deploy + Workshop upload
.\tools\publish-release\publish-release.ps1       # then publish the GitHub release
```

Or for a session that touched multiple mods, run `publish-release.ps1` once at the end — it always packages every mod's current bundle. Tag defaults to `mods-YYYY-MM-DD`. See `tools/publish-release/README.md` for full doctrine. The script auto-skips unpublished mods (no `published_id`) and writes a `vt2updater_version.txt` sidecar into each zip so the updater app can detect installed versions on the consumer side.

### Legacy raw pipelines (archived — DO NOT USE)

The `node vmb.js build <mod> --no-workshop --cwd` invocations and the raw Stingray SDK compile pipeline that previously lived in this section are no longer the supported path. Use `VMBLauncher.exe build <mod>` for VMB mods and `VMBLauncher.exe all <mod>` for full pipeline. The launcher already wraps `node vmb.js` internally, so if you're tempted to invoke `node` directly you're skipping hash verification, remote PC-B push, BOM handling on staged cfgs, and the rest of the protective layers documented in `tools/vmb-launcher/CLAUDE.md`.

The one exception is the deprecated `tweaker` mod (Workshop ID 3704660429) — it pre-dates the VMB migration and only builds via raw SDK. Treat it as frozen: don't iterate on it, don't try to graft it onto the launcher.

### Version bumping

**Always increment `MOD_VERSION` before every build** — the version string is echoed in-game on load, confirming the correct build is running. Without a bump, you can't visually confirm the new code deployed.

**`MOD_VERSION` is the canonical source for the mod's Workshop title.** As of 2026-05-22, every Workshop upload appends/refreshes a trailing ` v<MOD_VERSION>` suffix on `itemV2.cfg`'s `title` field. Format: `<base_title> v<MOD_VERSION>`. Example: `Tweaker: Cosmetics v0.9.8.8`. The launcher's `upload` verb performs this rewrite automatically; the local cfg file's `title` is rewritten on each upload.

Rules:
1. **Every mod must define** `local MOD_VERSION = "X.Y.Z..."` near the top of `<mod>/scripts/mods/<mod>/<mod>.lua`. The launcher aborts the upload (rather than fall back to a date stamp) if no MOD_VERSION can be parsed — that surfaces gaps instead of hiding them.
2. **Base title** = the canonical title minus any existing trailing ` v<digits>` suffix. The launcher strips-and-reappends on each upload.
3. **Only the version suffix is auto-managed.** Description, visibility, preview, base title text remain user-dictated. See `tools/vmb-launcher/CLAUDE.md` § "ugc_tool pushes ALL cfg fields" for the full pre-upload checklist. Never auto-change those.
4. **Why:** subscribers see the version in their Workshop sub list (faster triage on crash reports), and the vt2-mod-updater app can read it directly from the title rather than the GitHub manifest.

#### Format: 3-segment semver only

`MOD_VERSION` follows `MAJOR.MINOR.PATCH[-track]`. Examples: `0.7.90-dev`, `0.12.68-dev`, `0.1.329-dev`, `1.0.0`. **Never add a 4th segment.**

- A change that fixes / adjusts / adds anything → bump PATCH. `0.9.10-dev` → `0.9.11-dev`. Don't bump within a patch via a 4th segment.
- PATCH can grow arbitrarily large (`0.1.329-dev` is fine). No need to roll over to MINOR.
- Pre-release track stays the same across patches — `alpha` stays `alpha`, `dev` stays `dev`. Only the user moves between tracks explicitly. The suffix is release-track only (`-alpha`/`-beta`/`-dev`/`-rc`), NEVER a change descriptor (`-revert`/`-hotfix`/`-la-icons`).
- If a mod has a stale 4-segment version (e.g. `0.9.9.4-dev`), normalize on the next bump by incrementing the third segment and dropping the fourth: `0.9.9.4-dev` → `0.9.10-dev` (not `0.9.9.5-dev`). Past 4-segment versions stay in CHANGELOG as historical record — don't rewrite.

**Burned 2026-05-23:** cosmetics_tweaker drifted through `0.9.8.0–.9`, `0.9.9.0–.4`. Pattern came from treating the 4th segment as a within-patch hotfix counter — wrong instinct; just bump PATCH every time. Reset to `0.9.10-dev`.

### Local development setup

After cloning, run `./tools/install-hooks.ps1` to enable the local pre-commit hook. It runs `qa/run_all.ps1 -Quick -SkipLua` (cfg drift + MOD_VERSION / title suffix typos) and `tools/mod-lint/lint-mod.ps1` (duplicate hook registrations, forward-ref / late-local / save-restore / network-bound warnings) against staged `*.lua` / `*.cfg` / `*.ps1` / `*.mod` files before the commit hits CI. The installer is idempotent — re-running is a no-op once the hook is in place. Bypass on a single commit with `git commit --no-verify` if you've verified the working tree locally and the hook is being overly cautious; cite the reason in the commit message. See `PROJECT_STANDARDS.md` § 8 for the escape-hatch convention.

## Multi-agent coordination

When more than one session / agent is working in this repo at the same time, parallel edits to the same mod cause silent breakage — broken builds blocking `publish-release.ps1`, MOD_VERSION reverts that mask real fixes, version-bump churn, etc. The 2026-05-25 session burned four times on this in a single afternoon (cwv v0.1.336 → .339 churn, cim build broken twice, wt MOD_VERSION reverted 0.12.78 → 0.12.77). The convention below is the fix — lightweight and advisory, not a locking mechanism.

- **`MOD_OWNERSHIP.md` (repo root)** — single table mapping every mod to its primary maintainer (`Ensrick` for all current mods) and a Status column: `stable` / `in-flight` / `frozen` / `blocked`. Read this before starting substantive work on a mod.
- **`.in_progress/<mod>.md` sentinel files** — when a session starts substantive multi-step work on a mod, drop a sentinel file at `.in_progress/<mod_name>.md` containing timestamp (`- **Started:** <ISO-8601-UTC>`), session ID, brief description, and files expected to be touched. Other sessions check this directory before starting work on the same mod. Sentinels are gitignored (advisory only); the README in that directory documents the template and is the only tracked file. Delete the sentinel when work finishes.
- **`qa/check_in_progress.ps1`** — wired into `qa/run_all.ps1`. Scans `.in_progress/`, warns on stale sentinels (>24h old), and cross-references staged files against claimed mods. Exit codes: 0 = clean, 1 = stale or staged-file collision, 2 = malformed sentinel. Never blocks — just surfaces awareness.
- **Workflow**: before editing a mod, (1) check `MOD_OWNERSHIP.md` for the row's status, (2) `Get-ChildItem .in_progress\*.md -Exclude README.md` to see active claims, (3) if no claim, drop your own sentinel + flip the MOD_OWNERSHIP row, (4) when done, remove the sentinel + flip the row back to `stable`.

The point is awareness, not enforcement — if a sentinel exists for a mod you need to edit, coordinate with the listed session/owner before stomping their in-flight state.

## Mod File Structure

All active mods use the VMB layout. Short internal IDs (`wt`, `ct`, `gt`, `crt`, `cim`, `mp`, `bt`) are the `new_mod()` registration name, not a separate directory pattern — those mods live under the same VMB layout as the long-ID ones.

```
<mod_name>/
├── <mod_name>.mod                        # VMF entry point
├── itemV2.cfg                            # Workshop upload config (MOD_VERSION suffix appended on upload)
├── bundleV2/                             # Build output (VMB)
├── resource_packages/<mod_name>/<mod_name>.package
└── scripts/mods/<mod_name>/
    ├── <mod_name>.lua                    # Main logic — MOD_VERSION constant lives here
    ├── <mod_name>_data.lua               # VMF widget tree
    ├── <mod_name>_localization.lua       # Localized strings
    └── _<feature>.lua                    # Per-feature subsystems (optional; see PROJECT_STANDARDS.md §2.2 for docstring header rule)
```

**Legacy SDK layout** — only `tweaker/` (Workshop 3704660429, frozen) uses the SDK layout with `.build/OUT/`, `settings.ini`, and `upload/content/`. Do not iterate on it; do not pattern-copy from it.

## Architecture

### VMF Mod Pattern

Every mod registers via `new_mod(id, { mod_script, mod_data, mod_localization })`. The three files serve distinct roles:
- **`_data.lua`**: Returns a widget tree defining the VMF settings UI (checkboxes, sliders, dropdowns, groups)
- **`_localization.lua`**: Returns a table mapping setting IDs to `{ en = "Display Text" }` entries
- **`<mod>.lua`**: Main logic — hooks, commands, runtime data

Settings are read via `mod:get("setting_id")` and return the current value. Widget `setting_id` must match across data and localization files.

### Hooking

VMF provides `mod:hook(class, method, func)` and `mod:hook_safe(class, method, func)`:
- **String-form** `mod:hook("ClassName", "method", ...)` — lazy resolution, safe if class isn't loaded yet. **Use this by default.**
- **Table-form** `mod:hook(ClassTable, "method", ...)` — immediate resolution, required for plain tables like `BackendUtils` that aren't hookable by string. **Guard with nil check.**
- `mod:hook_safe` fires after the original function returns (no wrapping, no return value override).
- `_G` can be used to hook global functions: `mod:hook(_G, "Localize", ...)`

**Do NOT hook `BackendUtils.can_wield_item`** — it is not hookable from Workshop mods. Modify `ItemMasterList[key].can_wield` directly instead.

**`mod:hook_safe` does NOT chain on the same `Class.method`.** Two `mod:hook_safe(C, m, ...)` registrations on the same pair silently overwrite — only one body runs, with no error or warning. The diagnostic install log prints `Hooking '<m>' from [<C>]` twice with identical Origin pointers, but at runtime the shadowed handler never fires. Consolidate concerns (diagnostic + behavior) into a single callback per `(Class, method)` per mod. Full mechanic + burn history in `VMF_RECIPES.md` § 1.

**Hook wrappers collapse multi-returns to one value.** Writing `return wrapper(func(self, ...))` drops every return after the first into the wrapper's argument list, where they are silently discarded. VT2 spawn / composition / `get_loadout` / `get_item_units` functions love returning 2-3 values — always capture them all into locals before transforming:
```lua
-- WRONG -- num_to_spawn collapses to nil at the caller
return _apply_swap(func(self, ...))

-- RIGHT -- capture every return, transform the one you need
local list, num_to_spawn = func(self, ...)
return _apply_swap(list), num_to_spawn
```
Burn history + full mechanic in `VMF_RECIPES.md` § 2.

**`LootItemUnitPreviewer.spawn_units` MUST use `mod:hook`, not `hook_safe`.** Vanilla `_spawn_items` writes `self._spawned_units = units` AFTER `spawn_units` returns, so a `hook_safe` post-callback reads `nil`. Use the full wrapper and read units from the wrapped call's return. Hit twice (cosmetics_tweaker bret-thinning scale, character_weapon_variants v0.1.127). Full detail in `DEVELOPMENT.md` § "LootItemUnitPreviewer.spawn_units".

**`HeroPreviewer` / `MenuWorldPreviewer` slot keying is split.** `_item_info_by_slot` is **string-keyed** (`"melee"` / `"ranged"`); `_equipment_units` is **numeric-keyed** (`slot_index`). Bridge via `info.spawn_data[1].slot_index`. Iterating `_item_info_by_slot` and using the iterator key on `_equipment_units` returns nil silently. Hit twice (cosmetics_tweaker v0.7.88, character_weapon_variants v0.1.84). Full detail in `DEVELOPMENT.md` § "HeroPreviewer / MenuWorldPreviewer slot keying".

**`BackendUtils` dispatch caveat (LA bridge).** `BackendUtils` is a plain-table dispatcher; its functions are often reassigned at runtime by Loremaster's Armoury's "clone backend" pattern. Hooking `BackendUtils.get_item_from_id`, `.get_loadout_item_id`, etc. by string-form will silently miss calls routed through the LA clone path. See `CROSS_MOD_ARCHITECTURE.md` "LA bridge" section for the dispatch model, the clone-backend_id pattern, and which methods need an explicit LA-aware hook. When in doubt, hook the table form against the post-LA `BackendUtils` reference, not the cold `_G.BackendUtils`.

**`rawget` for fragile globals.** Cold reads of `ItemMasterList[key]` and `NetworkLookup.weapon_skins[key]` will throw if a peer hasn't fully populated the table yet (CW peer-late-join, host-only DLC ownership, gated registration mismatch). Use `rawget(ItemMasterList, key)` / `rawget(NetworkLookup.weapon_skins, key)` and nil-check before dereferencing — full failure-mode table and the gated-registration crash class are in `DEVELOPMENT.md` "Known Errors" section.

### Three Weapon Rendering Paths

Any weapon visual override must cover all three:

| Path | Hook Target | Hand Access |
|------|-------------|-------------|
| In-game (keep/mission) | `GearUtils.create_equipment` (or `GearUtils.spawn_inventory_unit`) | `result.left_unit_1p`, `.right_unit_1p`, `.left_unit_3p`, `.right_unit_3p` |
| Inventory character preview | **`MenuWorldPreviewer.equip_item` / `MenuWorldPreviewer._spawn_item`** (NOT HeroPreviewer — see below) | `self._equipment_units[slot].left` / `.right` |
| Illusion/skin browser | `LootItemUnitPreviewer.spawn_units` | `self._spawned_units` array (left=index 1, right=index 2) |

`MenuWorldPreviewer._spawn_item_unit` fires once per unit with **no hand indicator** — do not use it for per-hand operations.

**HOOK THE DERIVED CLASS, NEVER THE BASE.** Hooks on `HeroPreviewer.equip_item` / `HeroPreviewer._spawn_item` silently never fire on the keep inventory previewer instance. VT2's `foundation/scripts/util/class.lua:51-57` copies parent methods into the child *at class-definition time* (no `__index` chain). `MenuWorldPreviewer = class(MenuWorldPreviewer, HeroPreviewer)` runs at game load, before any mod loads — so by the time VMF replaces `HeroPreviewer.method`, `MenuWorldPreviewer.method` is already an independent copy of the original. The runtime keep inventory is `MenuWorldPreviewer` (verified at every `:new(...)` call site in `scripts/ui/views/`); `HeroPreviewer` itself is only instantiated by `team_previewer.lua`. See `feedback_vt2_class_hook_derived.md` and `feedback_inventory_preview_hook_menuworldpreviewer.md`. Burned in weapon_tweaker v0.12.16 → fixed in v0.12.17.

**In-mission player career detection caveat (in-game path):** career-gated hooks on `GearUtils.spawn_inventory_unit` (or `create_equipment`) must NOT rely on `Managers.player:owner(unit):career_name()` — at mission-spawn timing the unit→player reverse association isn't yet established, so the lookup returns nil and the hook silently bails. Read career from `ScriptUnit.has_extension(unit, "inventory_system")._career_name` instead — that field is set in `SimpleInventoryExtension.init` (line 47) BEFORE `extensions_ready` fires our hook. See `feedback_vt2_mission_spawn_career_lookup.md`.

### Shield/Weapon Unit Architecture

Shield weapons use **two independent units**: right hand (weapon) and left hand (shield). They attach to separate skeleton nodes and can be scaled, swapped, or offset independently. See `DEVELOPMENT.md` for unit paths and the `_weapon_scale_overrides` / `_custom_illusions` systems.

### Animation Remapping (weapon_tweaker)

**Load-bearing rule:** **1P animations are universal across all six characters and never need cross-character remapping.** The `first_person_base` unit is shared, so any weapon's 1P state machine and clips play correctly on any character's first-person view by default. Only the **3P body** is character-specific and needs remap work. Never override `anim_event` (1P), `wield_anim` (1P), or `state_machine` per character. See `feedback_1p_animations_universal.md` and `feedback_animation_remap_rules.md`.

VT2 uses two separate units for the local player:
- `player.player_unit` = **3P body** (receives `anim_event_3p`) — character-specific skeleton, this is where remap work lives
- Separate non-player unit = **1P hands** (receives `anim_event`) — universal across characters, never touched

Cross-career weapons need animation redirects on the **3P side only** because different character 3P body skeletons have different event vocabularies. The system uses three layers:
1. **`_anim_redirect`**: global event renames
2. **`_career_anim_redirect`**: career-prefix-aware redirects
3. **`_suffix_career_map`**: suffix-based event swaps

For full **cross-character ports** (weapon X playable by character Y, rendered as Y's own 3P mesh + anims — e.g. brace-on-Kruber → Repeating Handgun, longbow-on-Saltzpyre → Crossbow), read `weapon_tweaker/CROSS_CHARACTER_PORT_RECIPE.md`. Seven-step procedure, failure-mode table, line citations into `weapon_tweaker.lua`, and verification matrix. Covers template patcher + force-load + in-mission unit swap + preview unit swap.

### Custom Illusion Injection (cosmetics_tweaker)

To add new selectable weapon skins at runtime, inject into three tables:
1. `ItemMasterList[skin_key]` — weapon_skin entry with `matching_item_key`
2. `WeaponSkins.skins[skin_key]` — unit paths and visual data
3. `WeaponSkins.skin_combinations[table_name]` — add to appropriate rarity tier

Then hook `BackendInterfaceCraftingPlayfab.get_unlocked_weapon_skins` to mark custom skins as unlocked, and hook `_G.Localize` for display names.

## Lua Environment

- **Lua 5.1** — use `unpack()`, NOT `table.unpack()`. `goto` is available in every active mod (all VMB-built); the SDK preprocessor's restriction only ever applied to the frozen legacy `tweaker`.
- Game globals: `ItemMasterList`, `WeaponSkins`, `Weapons`, `BackendUtils`, `GearUtils`, `Managers`, `Unit`, `World`, `Vector3`, `Quaternion`, `Material`, `Color`
- Console commands registered via `mod:command("name", "description", function(...) end)` — invoked in-game as `/<name>` directly (e.g. `/dump`, `/probe_hat`). There is NO mod-id prefix in chat: the mod-id you see in code (`wt`, `cos`, `ct`, etc.) is the mod's internal identifier, not a chat prefix. Documentation showing `/<mod> <command>` is wrong. Full per-mod command inventory in `COMMANDS.md`.

**High-frequency engine quirks** (full mechanics in `DEVELOPMENT.md` § "Stingray / Lua engine quirks"):
- **`Unit.node(unit, name)` errors bypass `pcall`** — it's an engine-level fatal, not a Lua error. Use `Unit.has_node(unit, name)` (returns boolean) for existence checks. Same pattern applies to other Stingray `*.node` / `*.actor` APIs — prefer the `has_*` companion when it exists.
- **`Quaternion` / `Vector3` are stack temporaries** — valid only within the current frame. Storing the raw value in a global/table/upvalue silently corrupts on the next frame. Use `QuaternionBox` / `Vector3Box` / `Matrix4x4Box` for any storage that outlives a single statement; call `:unbox()` at apply time for a fresh raw value.
- **Lua 5.1 hard limit: 200 locals per function**, including the top-level chunk. Wrap helper groups in `do ... end` so their locals release back to the main chunk. Symptom is a Stingray compile error `main function has more than 200 local variables` — the cited line is the 201st local, not the problem source.
- **`#table` is undefined for arrays with nil holes.** Lua 5.1 `#t` does a binary boundary search over the array part — for `{1, nil, 2, nil, 3}`, the result could be 1, 3, or 5. Never use bare `unpack(t)` / `unpack(t, i)` if `t` may contain nils after position `i`. Capture the real count via `select("#", ...)` from the source variadic and pass `j` explicitly: `unpack(t, i, n)`. Burned in weapon_tweaker v0.12.77/.78 (2026-05-25 fix cycle through v0.12.79) — see `VMF_RECIPES.md § 2a`.
- **`Unit.actor(unit, idx)` is 1-indexed** (vanilla pattern is `for i = 1, Unit.num_actors(unit)`). Iterating from 0 returns nil at index 0 and skips the final actor — silent no-op.
- **`pl.player_unit` is a FIELD, not a method.** `Managers.player:local_player().player_unit` (chained field access). `pl:player_unit()` crashes immediately.
- **`REAL_PLAYER_LOCAL_ID` is a file-scope local in vanilla, not a global.** Add `local REAL_PLAYER_LOCAL_ID = 1` near the top of any mod file that copy-pastes vanilla CW SharedState code, or the affected lookups silently return 0.

**Hooks that silently no-op:**
- **Upvalue capture bypasses table-entry hooks** — when a vanilla file does `local f = SomeTable.method` at the top, the upvalue holds the original function. Later `mod:hook("SomeTable", "method", ...)` only replaces the table entry; every call site through the captured local bypasses the wrapper. Grep for `local <name> = Class.method` before hooking. Fall back to mutating the data the function READS at call time.
- **Mutator template `server_*_function` is a dead field** — the engine wraps it into `template.server.start_function` (etc.) at boot. Hook the wrapped form, NOT `template.server_start_function`.
- **Self-owned vs husk extension classes** — `Simple*Extension` and `SimpleHusk*Extension` are separate root classes with no inheritance. Hooks on one don't fire for the other. Audit `scripts/network/unit_extension_templates.lua` and either hook both, or hook a global function both classes route through.

## DLC Ownership Gate (cross-mod)

**Modded mods unlock vanilla progression (career levels, crafting materials, XP grind), NOT paid DLC content.** When a mod surfaces / unlocks / grants items the player wouldn't otherwise have access to, it MUST respect the vanilla DLC paywall. Vanilla gate (used by the base game everywhere):

```lua
local data = rawget(<MasterTable>, key)        -- ItemMasterList / CareerSettings / DLCSettings / etc.
if data and data.required_dlc and Managers.unlock
   and not Managers.unlock:is_dlc_unlocked(data.required_dlc) then
    -- player does NOT own this DLC — skip
end
```

The DLC id lives on the master entry (`required_dlc` field). For tables that don't carry that field directly (mutator templates, level variations), look up the DLC by name in `scripts/settings/dlc_settings.lua` — entries register their content lists there. Pre-check with `Managers.unlock:dlc_exists(id)` before `is_dlc_unlocked(id)` to avoid the fassert at `unlock_manager.lua:527`.

**Three places the gate applies:**
1. **Enumerations** that walk `ItemMasterList` / `WeaponSkins.skins` / `CareerSettings` and surface entries to the player (e.g. crafting recipe lists, illusion grids, talent-swap dropdowns).
2. **Unlock hooks** that write into the backend mirror (e.g. `get_unlocked_weapon_skins`, `get_unlocked_cosmetics`, `get_unlocked_hero_portrait_frames`). Filter before the `mirror._unlocked_*[k] = true` write.
3. **Injection hooks** that push content into the lobby (e.g. event_tweaker's `get_special_events` / `get_active_events`). Filter before injection — the engine catches missing DLC at level-load with a confusing failure, so the mod should drop the entry cleanly instead.

**Helper pattern:** define a tiny `_X_requires_unowned_dlc(key) -> bool` per file (or shared via `mod._foo` for cross-file use). Examples:
- `cosmetics_tweaker.lua:43` — `_skin_requires_unowned_dlc(skin_key)` (reads `ItemMasterList`)
- `crafting_in_modded/illusion_swap.lua:51` — `_skin_requires_unowned_dlc(skin_key)` (same pattern, scoped to skins)
- `crafting_in_modded/standard_forge.lua:~40` — `_item_requires_unowned_dlc(item_key)` (weapons), exposed as `mod._cim_item_requires_unowned_dlc`
- `career_tweaker.lua:77` — `_career_requires_unowned_dlc(career_name)` (reads `CareerSettings`)
- `event_tweaker.lua:23-64` — `DLC_BY_MUTATOR` / `DLC_BY_PRESET` tables + `owns_dlc(dlc_id)` helper (mutator templates don't carry `required_dlc` directly)

**Intentional exceptions.** `character_weapon_variants._build_entry()` (`character_weapon_variants.lua:~7895`) DELIBERATELY strips `required_dlc = nil` on its cloned variant entries because CWV variants are new mod-created items reusing base-package meshes — they are not the DLC content itself. Don't "fix" this. The blanket clearing is documented in CHANGELOG and CODE_REVIEW.md.

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
| Lake (Bretonnia) — used by `es_sword_shield_breton` etc. | `lake` |

For weapon DLCs (Bogenhafen / Karak Azgaraz / Lake), grep `scripts/settings/dlcs/<dlc>/item_master_list_<dlc>.lua` to see which `ItemMasterList` keys carry the `required_dlc` field.

**Audit history:** 2026-05-18 fan-out audit (`crafting_in_modded` v0.7.9-dev, `cosmetics_tweaker` v0.8.65-dev, `career_tweaker` v0.2.20-dev, `event_tweaker` v0.4.1-dev) caught and fixed four bypasses. Verified clean at the same date: `weapon_tweaker`, `chaos_wastes_tweaker`, `modded_progression` (scaffolding only — re-audit when loot hooks land), `enemy_tweaker`, `dynamic_cosmetic_portraits`, `general_tweaker`, `la_prefix_patch`. When adding any new unlock surface to any mod, walk the three-places checklist above before merge.

## Important Constraints

- **Hot-reload crashes**: Ctrl+Shift+R is NOT safe for weapon_tweaker or cosmetics_tweaker — both hook unit creation paths (`GearUtils.create_equipment`, `BackendUtils.get_item_units`) and cosmetics_tweaker has non-Lua resources (materials/textures). The engine holds C++-level locks on spawned units that cannot be released from Lua. Always do a full game restart for these mods. chaos_wastes_tweaker, general_tweaker, and career_tweaker are Lua-only and may survive hot-reload, but a restart is still safest.
- **Never clean `.build/` unless file lock errors** — incremental builds work. Cleaning forces recovery.
- **Verify bundle output before deploying** — the compiler shows minimal console output; check the bundle dir for files.
- **Workshop upload verification**: `ugc_tool` prints "Upload finished" even when content fails to transfer. Always check Workshop page file size after upload.
- **Deploy via `VMBLauncher.exe deploy <mod>`** — the launcher handles every active mod (VMB-layout `bundleV2/`). The historical `deploy_all.ps1` shim was archived 2026-05-21 to `_archive/legacy_deploy_scripts/`; it only forwarded each `-Mods` entry to `VMBLauncher.exe deploy`.

## Key Reference Files

- `PROJECT_STANDARDS.md` — operational rulebook for the monorepo: workflow conventions, error-handling rules, logging conventions, anti-patterns to avoid, pre-ship checklists. Binding on Claude; cite section numbers when applying. Complements this CLAUDE.md (HOW the code works) with HOW WE WORK on it.
- `DEVELOPMENT.md` — detailed technical reference (hooking rules, animation system, shield swap architecture, known errors, Stingray / Lua engine quirks, dead ends).
- `VMF_RECIPES.md` — repo-wide Vermintide Mod Framework gotchas: `hook_safe` no-chain, multi-return collapse, `network_send` recipients (`"server"` silently dropped), 500-char RPC string cap, dropdown options table mutation, widget setting_id uniqueness, mod `_localization.lua` not registered into global `Localize`, `custom_gui_textures` format. Every entry includes burn history.
- `COMMANDS.md` — snapshot of every `mod:command(...)` across the monorepo (chat commands invoked as `/<name>`).
- `WORK_ITEMS.md` — current status of all working features and animation remap tables
- `TODO.md` — feature roadmap across all mods
- `ITEM_LIST.md` — full weapon key catalog from ItemMasterList
- `WEAPON_CATALOG.md` — repo-root weapon catalog: model paths, owning character, cross-character port status, illusion family membership. Use alongside `ITEM_LIST.md` when wiring a new weapon-side feature.
- `ANIMATION_RESEARCH.md` — skeleton event probe results across the six character bodies
- `CROSS_MOD_ARCHITECTURE.md` — weapon sharing & cosmetics architecture across weapon_tweaker, cosmetics_tweaker, character_weapon_variants, and modded_progression. Contains the LA bridge dispatch model referenced from the Hooking section above.
- `weapon_tweaker/CROSS_CHARACTER_PORT_RECIPE.md` — seven-step procedure for adding a full cross-character weapon port (template patcher + force-load + in-mission unit swap + preview unit swap). Failure-mode table, line citations into `weapon_tweaker.lua`, verification matrix.
- `character_weapon_variants/DEFINITION_OF_DONE.md` — **MANDATORY GATE BEFORE DECLARING ANY CWV VARIANT COMPLETE.** Universal checklist (IML verified, build-from-ground-up integrity, scale/grip, icons, loc, forward-ref audit, build hygiene, live verification matrix) plus trait-gated checklists (G-DUAL, G-RANGED, G-THROWN, G-CROSS-CHAR, G-BLACKSMITH, G-MESH-FAMILY, G-3P-ANIM, G-STANCE, G-CUSTOM-ILLUSION). Variant CHANGELOG entries must end with the `**DoD:**` footer naming which gates were walked and any explicit deferrals. The repeated bug class of "looks right, breaks on equip / fire / forge / preview / dual-wield" is exactly what this file catches.
- `character_weapon_variants/RECIPES.md` — **READ THIS BEFORE ADDING A NEW VARIANT.** Decision tree (single-melee / 2H / shield / identical-mesh dual / mixed-mesh dual / ranged-ammo / skin-only / cross-access / custom illusion) plus per-archetype copy-paste recipes referencing shipped variants as canon, plus pre-deploy checklist and verification matrix. Each archetype has its own gotchas (dual-wield needs `_force_display_unit`, ranged ammo needs full skin-mirror + custom Pickups + projectile init hook, fire-DoT removal is a 3-step swap, etc.) — the recipes spell them out so you don't rediscover them. The DoD gate (above) supersedes the pre-deploy checklist and verification matrix in this file.
- `character_weapon_variants/DEVELOPMENT.md` — architectural reference for variant creation: rarity system, blacksmith template pattern, skin system, icon atlases, properties/traits, registration timing, custom templates / stat modifications, model scaling, base-weapon catalog. Cross-references RECIPES.md and ANIMATION_FIX_PLAYBOOK.md.
- `character_weapon_variants/ANIMATION_FIX_PLAYBOOK.md` — 9-step closed-vocabulary procedure for fixing 3P animations on cross-character variants. Read before touching `anim_event_3p`, `wield_anim_3p`, or any `_cross_access_action_remap` entry.
- `character_weapon_variants/J_LEFTWEAPONATTACH_INVESTIGATION.md` — post-mortem for the ~20-version dual-wield rig saga. Read once before adding any dual-wield variant.
- `character_weapon_variants/CHANGELOG.md` — version history for the Character Weapon Variants mod. Best source of "why we do X" — most recipes have a CHANGELOG entry behind every load-bearing rule.
- `character_weapon_variants/CODE_REVIEW.md` — snapshot architectural review for CWV. (Per-doc currency/staleness is tracked in `PROJECT_STANDARDS.md` §7.1, the canonical doc index — not version-stickered here, since those stickers drift.)
- `character_weapon_variants/TODO.md` — feature roadmap for cross-character weapon variants
- `cosmetics_tweaker/TODO.md` — feature roadmap for cosmetics-specific work
- `dynamic_cosmetic_portraits/CLAUDE.md` — **READ THIS BEFORE TOUCHING PORTRAITS.** Workflow guardrails + the canonical asset-generation script.
- `dynamic_cosmetic_portraits/tools/add_portrait.ps1` — the only correct way to generate a new portrait's `.png` / `.texture` / `.material` files. Call it as `.\tools\add_portrait.ps1 -SourcePng "<110x130 PNG>" -HatKey "kruber_<key>"`. Free-handing the assets has broken multiple shipped versions; do not skip the script.
- `dynamic_cosmetic_portraits/CHANGELOG.md` — version history. v0.1.0 → v0.1.3 documents every variant of the asset-pipeline mistake — read before reinventing.
- `dynamic_cosmetic_portraits/DEVELOPMENT.md` — full portrait-authoring workflow + career_settings swap architecture + dead ends not to retry.
- `dynamic_cosmetic_portraits/TODO.md` — portrait roadmap (which hats/careers/characters are next).
- `dynamic_cosmetic_portraits/CHARACTER_COSMETIC_CATALOG.md` — every `slot_hat`/`slot_skin` item key → in-game display name across all 5 characters (sourced from `cosmetics_tweaker/_cos_probe.txt`). **Consult this whenever wiring a new portrait — it's the only reliable mapping from a key to a player-facing name.**
- `event_tweaker/CHANGELOG.md` — version history for the Tweaker: Events mod.
- `event_tweaker/DEVELOPMENT.md` — architecture (3 hooks: `get_special_events` / `get_active_events` / `get_level_variation_data`), how to add a new mutator or preset, sharp edges (special_events `name` field, hub-skip in `append_live_event_mutators`, keep-reload caveat).
