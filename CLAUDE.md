# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Project Overview

A modular set of **Vermintide 2** VMF (Vermintide Mod Framework) mods written in Lua 5.1. Originally a monolithic mod ("Tweaker"), now split into focused sub-mods. Runs on the Stingray engine. The VT2 decompiled source code lives at `c:\Users\danjo\source\repos\Vermintide-2-Source-Code` — use it as a reference for game APIs, class structures, and data tables.

## Mod Directory

| Mod | Internal ID | Workshop ID | Build System | Purpose |
|-----|-------------|-------------|--------------|---------|
| weapon_tweaker | `wt` | 3712896117 | **VMB** | Cross-career weapon unlocks, animation remapping, scale/offset |
| chaos_wastes_tweaker | `ct` | 3712929235 | **VMB** | CW economy, curses, boons, altars, traits |
| general_tweaker | `gt` | 3713619122 | **VMB** | 3rd person camera, debug/data dumps |
| cosmetics_tweaker | `cosmetics_tweaker` | 3715714222 | **VMB** | Hat/skin unlocks, weapon model tweaks, shield swaps, custom illusions |
| dynamic_cosmetic_portraits | `dynamic_cosmetic_portraits` | 3721036701 | **VMB** | Hat/outfit-aware HUD & hero-select character portraits (split from cosmetics_tweaker 2026-05-06) |
| career_tweaker | `crt` | 3716286199 | **VMB** | Talent/ability swapping (scaffolded) |
| enemy_tweaker | `enemy_tweaker` | 3716780252 | **VMB** | Enemy spawns, horde compositions, breed substitution |
<!-- REVIEW: character_weapon_variants is actually PUBLISHED (Workshop ID 3716869446). itemV2.cfg has published_id = 3716869446L; deploy_all.ps1 maps it; reference_build_deploy.md memory lists it. Update to 3716869446 (private). -->
| character_weapon_variants | `character_weapon_variants` | 3716869446 | **VMB** | New weapon items grafted from cross-character models (MoreItemsLibrary) |
| crafting_in_modded | `cim` | 3721038774 | **VMB** | Modded crafting menus — Athanor forge UI for crafting any career-eligible weapon. Split from `wt` 2026-05-05 |
| la_prefix_patch | `la_prefix_patch` | 3721067411 | **VMB** | Loads above Loremaster's Armoury: silently drops its three duplicate hook registrations to keep startup chat clean, and offers VMF toggles to suppress LA's quest markers and unread-letter notifications |
| event_tweaker | `event_tweaker` | 3721290755 | **VMB** | Host-side mutator picker (Workshop title "Tweaker: Events"). VMF dropdown for canonical event presets (Geheimnisnacht / Skulls — drives mutator + active_events string + keep-level swap) plus checkbox-per-mutator across difficulty / specials / hordes / atmosphere / objectives / winds / raw event categories. Three hooks: `BackendInterfaceLiveEventsPlayfab.get_special_events`, `get_active_events`, `BackendManagerPlayFab.get_level_variation_data`. Scaffolded 2026-05-06 |
| tweaker (legacy) | `t` | 3704660429 | Stingray SDK | Deprecated — split into above mods |

<!-- REVIEW: This entire SDK block is now relevant ONLY for the legacy /tweaker source. After the 2026-05-01 VMB migration, every active mod (wt/ct/gt/crt/cosmetics_tweaker/enemy_tweaker/character_weapon_variants) is built via VMB. Consider collapsing this section to a single line ("legacy /tweaker only — see old-backup/ scripts") and putting the VMB block first. As-is, an AI agent skimming this file will see the SDK commands and may assume they apply to active mods. -->
## Build Commands

### SDK mods (legacy `tweaker` only)

```powershell
$sdk = "C:\Program Files (x86)\Steam\steamapps\common\Vermintide 2 SDK"
$root = "C:\Users\danjo\source\repos\vermintide-2-tweaker"
$mod = "weapon_tweaker"   # change per mod
$modDir = "$root\$mod"
$dataDir = "$modDir\.build\data"
$bundleDir = "$modDir\.build\bundle"
$outDir = "$modDir\.build\OUT"

New-Item -ItemType Directory -Force -Path $outDir | Out-Null
& "$sdk\bin\stingray_win64_dev_x64.exe" --compile-for win32 --source-dir $modDir --data-dir $dataDir --bundle-dir $bundleDir --map-source-dir core $sdk

Start-Sleep -Seconds 1

Get-ChildItem $bundleDir -File | Where-Object { $_.Extension -eq '' } | ForEach-Object {
    Copy-Item $_.FullName (Join-Path $outDir $_.Name) -Force
}
Get-ChildItem $bundleDir -Filter "*.stream" -ErrorAction SilentlyContinue | Copy-Item -Destination $outDir -Force
Get-ChildItem $modDir -Filter "*.mod" | Copy-Item -Destination $outDir -Force
Copy-Item "$sdk\ugc_uploader\sample_item\content\e7852992f40eb619.mod_bundle" -Destination "$outDir\e7852992f40eb619" -Force
```

### cosmetics_tweaker (VMB — different pipeline)

```powershell
Set-Location "C:\Users\danjo\source\repos\vermintide-2-tweaker"
node C:/Users/danjo/source/repos/vmb/vmb.js build cosmetics_tweaker --no-workshop --cwd
```

Output goes to `cosmetics_tweaker/bundleV2/` (NOT `.build/OUT/`).

### character_weapon_variants (VMB — same pipeline as cosmetics_tweaker)

```powershell
Set-Location "C:\Users\danjo\source\repos\vermintide-2-tweaker"
node C:/Users/danjo/source/repos/vmb/vmb.js build character_weapon_variants --no-workshop --cwd
```

Output goes to `character_weapon_variants/bundleV2/`.

### chaos_wastes_tweaker, weapon_tweaker, general_tweaker, career_tweaker (VMB — migrated from SDK; same Workshop IDs)

```powershell
Set-Location "C:\Users\danjo\source\repos\vermintide-2-tweaker"
node C:/Users/danjo/source/repos/vmb/vmb.js build chaos_wastes_tweaker --no-workshop --cwd
node C:/Users/danjo/source/repos/vmb/vmb.js build weapon_tweaker --no-workshop --cwd
node C:/Users/danjo/source/repos/vmb/vmb.js build general_tweaker --no-workshop --cwd
node C:/Users/danjo/source/repos/vmb/vmb.js build career_tweaker --no-workshop --cwd
node C:/Users/danjo/source/repos/vmb/vmb.js build crafting_in_modded --no-workshop --cwd
node C:/Users/danjo/source/repos/vmb/vmb.js build dynamic_cosmetic_portraits --no-workshop --cwd
node C:/Users/danjo/source/repos/vmb/vmb.js build event_tweaker --no-workshop --cwd
```

Output goes to `<mod>/bundleV2/`. Internal mod IDs preserved (`"ct"`, `"wt"`, `"gt"`, `"crt"`) so existing user settings are unaffected. `deploy_all.ps1` auto-detects VMB vs SDK layout.

### Deploy to Workshop folder (all mods)

SDK mods and chaos_wastes_tweaker (VMB):
```powershell
& "$root\deploy_all.ps1" -Mods @("weapon_tweaker", "chaos_wastes_tweaker")
```

cosmetics_tweaker (manual — not in deploy_all.ps1):
```powershell
$wsDir = "C:\Program Files (x86)\Steam\steamapps\workshop\content\552500\3715714222"
Get-ChildItem "cosmetics_tweaker\bundleV2" -File | ForEach-Object { Copy-Item $_.FullName (Join-Path $wsDir $_.Name) -Force }
```

### Version bumping

**Always increment `MOD_VERSION` before every build** — the version string is echoed in-game on load, confirming the correct build is running. Without a bump, you can't visually confirm the new code deployed.

<!-- REVIEW: This dichotomy is no longer accurate. Post-2026-05-01 VMB migration, NO active mod uses the SDK layout. The SDK layout (.build/OUT, settings.ini, lua_preprocessor_defines.config, upload/content/) survives only in /tweaker (legacy reference). Every active mod uses the VMB layout shown below. The "SDK mods" subsection should either be removed or relabeled "legacy `tweaker` only". The active wt/ct/gt/crt mods retained their short internal IDs but use the VMB on-disk layout. -->
## Mod File Structure

Each mod follows one of two patterns:

**SDK mods** (short internal IDs like `wt`, `ct`, `gt`):
```
<mod_name>/
├── <id>.mod                    # VMF entry point (e.g. wt.mod)
├── settings.ini
├── resource_packages/<mod_name>.package
├── scripts/mods/<mod_name>/
│   ├── <mod_name>.lua          # Main logic
│   ├── <mod_name>_data.lua     # VMF settings widgets
│   ├── <mod_name>_localization.lua
│   └── <mod_name>_backend.lua  # (optional) backend hooks
├── .build/OUT/                 # Compiler output
└── upload/content/             # Deploy staging
```

<!-- REVIEW: This subsection only mentions cosmetics_tweaker but the same VMB layout applies to ALL active mods now (chaos_wastes_tweaker, weapon_tweaker, general_tweaker, career_tweaker, cosmetics_tweaker, enemy_tweaker, character_weapon_variants). The "long internal ID" qualifier is misleading — wt/ct/gt/crt also live under VMB layouts but kept their short internal IDs in new_mod() registration. -->
**VMB mods** (cosmetics_tweaker — long internal ID):
```
cosmetics_tweaker/
├── cosmetics_tweaker.mod       # VMF entry point
├── bundleV2/                   # Build output (VMB)
├── itemV2.cfg                  # Workshop upload config
├── resource_packages/cosmetics_tweaker/cosmetics_tweaker.package
└── scripts/mods/cosmetics_tweaker/
    ├── cosmetics_tweaker.lua
    ├── cosmetics_tweaker_data.lua
    ├── cosmetics_tweaker_localization.lua
    └── _cosmetic_unlocks.lua   # Auto-generated unlock maps
```

## Architecture

### VMF Mod Pattern

Every mod registers via `new_mod(id, { mod_script, mod_data, mod_localization })`. The three files serve distinct roles:
- **`_data.lua`**: Returns a widget tree defining the VMF settings UI (checkboxes, sliders, dropdowns, groups)
- **`_localization.lua`**: Returns a table mapping setting IDs to `{ en = "Display Text" }` entries
- **`<mod>.lua`**: Main logic — hooks, commands, runtime data

Settings are read via `mod:get("setting_id")` and return the current value. Widget `setting_id` must match across data and localization files.

<!-- REVIEW: This hook section is good but missing a few items captured elsewhere: (a) the BackendUtils hook for set_loadout_item must be on BackendUtils (table) not on the items_iface (the dispatch goes through get_loadout_interface_by_slot — see CROSS_MOD_ARCHITECTURE.md "LA bridge" section), (b) rawget guidance for ItemMasterList / NetworkLookup.weapon_skins to avoid crashify on unknown keys (this IS in DEVELOPMENT.md "Known Errors", but missing from this hooking summary). Consider cross-linking. -->
### Hooking

VMF provides `mod:hook(class, method, func)` and `mod:hook_safe(class, method, func)`:
- **String-form** `mod:hook("ClassName", "method", ...)` — lazy resolution, safe if class isn't loaded yet. **Use this by default.**
- **Table-form** `mod:hook(ClassTable, "method", ...)` — immediate resolution, required for plain tables like `BackendUtils` that aren't hookable by string. **Guard with nil check.**
- `mod:hook_safe` fires after the original function returns (no wrapping, no return value override).
- `_G` can be used to hook global functions: `mod:hook(_G, "Localize", ...)`

**Do NOT hook `BackendUtils.can_wield_item`** — it is not hookable from Workshop mods. Modify `ItemMasterList[key].can_wield` directly instead.

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

### Custom Illusion Injection (cosmetics_tweaker)

To add new selectable weapon skins at runtime, inject into three tables:
1. `ItemMasterList[skin_key]` — weapon_skin entry with `matching_item_key`
2. `WeaponSkins.skins[skin_key]` — unit paths and visual data
3. `WeaponSkins.skin_combinations[table_name]` — add to appropriate rarity tier

Then hook `BackendInterfaceCraftingPlayfab.get_unlocked_weapon_skins` to mark custom skins as unlocked, and hook `_G.Localize` for display names.

## Lua Environment

<!-- REVIEW: "No `goto` in SDK mods" is now only relevant for the legacy /tweaker mod. Every active mod is VMB and supports `goto`. Phrasing implies this is still a per-mod concern. -->
- **Lua 5.1** — use `unpack()`, NOT `table.unpack()`. No `goto` in SDK mods (available in VMB-built mods, including chaos_wastes_tweaker now that it's VMB).
- Game globals: `ItemMasterList`, `WeaponSkins`, `Weapons`, `BackendUtils`, `GearUtils`, `Managers`, `Unit`, `World`, `Vector3`, `Quaternion`, `Material`, `Color`
- Console commands registered via `mod:command("name", "description", function(...) end)` — invoked in-game as `<prefix> <command>` (e.g. `wt dump`, `cos probe_hat`)

## Important Constraints

- **Hot-reload crashes**: Ctrl+Shift+R is NOT safe for weapon_tweaker or cosmetics_tweaker — both hook unit creation paths (`GearUtils.create_equipment`, `BackendUtils.get_item_units`) and cosmetics_tweaker has non-Lua resources (materials/textures). The engine holds C++-level locks on spawned units that cannot be released from Lua. Always do a full game restart for these mods. chaos_wastes_tweaker, general_tweaker, and career_tweaker are Lua-only and may survive hot-reload, but a restart is still safest.
- **Never clean `.build/` unless file lock errors** — incremental builds work. Cleaning forces recovery.
- **Verify bundle output before deploying** — the compiler shows minimal console output; check the bundle dir for files.
- **Workshop upload verification**: `ugc_tool` prints "Upload finished" even when content fails to transfer. Always check Workshop page file size after upload.
<!-- REVIEW: This is no longer accurate. deploy_all.ps1 has cosmetics_tweaker (3715714222) and character_weapon_variants (3716869446) entries in $workshopIds, and the auto-detection (Test-Path bundleV2) handles both. The default -Mods list at the top of deploy_all.ps1 is just (chaos_wastes_tweaker, weapon_tweaker, general_tweaker), but you can pass either mod via -Mods @("cosmetics_tweaker") and it will deploy correctly. The DEVELOPMENT.md "Cosmetics — Build & Deploy" section confirms this works. -->
- **`deploy_all.ps1` auto-detects VMB layout** for every active mod (looks for `bundleV2/` first, falls back to `.build/OUT/`). After the 2026-05-01 VMB migration, the script handles all active mods including cosmetics_tweaker, enemy_tweaker, and character_weapon_variants — pass them via `-Mods @("...")` or rely on the default list.

## Key Reference Files

- `DEVELOPMENT.md` — detailed technical reference (hooking rules, animation system, shield swap architecture, known errors)
- `WORK_ITEMS.md` — current status of all working features and animation remap tables
- `TODO.md` — feature roadmap across all mods
- `ITEM_LIST.md` — full weapon key catalog from ItemMasterList
- `ANIMATION_RESEARCH.md` — skeleton event probe results
- `CROSS_MOD_ARCHITECTURE.md` — weapon sharing & cosmetics architecture across weapon_tweaker, cosmetics_tweaker, and character_weapon_variants
- `character_weapon_variants/DEFINITION_OF_DONE.md` — **MANDATORY GATE BEFORE DECLARING ANY CWV VARIANT COMPLETE.** Universal checklist (IML verified, build-from-ground-up integrity, scale/grip, icons, loc, forward-ref audit, build hygiene, live verification matrix) plus trait-gated checklists (G-DUAL, G-RANGED, G-THROWN, G-CROSS-CHAR, G-BLACKSMITH, G-MESH-FAMILY, G-3P-ANIM, G-STANCE, G-CUSTOM-ILLUSION). Variant CHANGELOG entries must end with the `**DoD:**` footer naming which gates were walked and any explicit deferrals. The repeated bug class of "looks right, breaks on equip / fire / forge / preview / dual-wield" is exactly what this file catches.
- `character_weapon_variants/RECIPES.md` — **READ THIS BEFORE ADDING A NEW VARIANT.** Decision tree (single-melee / 2H / shield / identical-mesh dual / mixed-mesh dual / ranged-ammo / skin-only / cross-access / custom illusion) plus per-archetype copy-paste recipes referencing shipped variants as canon, plus pre-deploy checklist and verification matrix. Each archetype has its own gotchas (dual-wield needs `_force_display_unit`, ranged ammo needs full skin-mirror + custom Pickups + projectile init hook, fire-DoT removal is a 3-step swap, etc.) — the recipes spell them out so you don't rediscover them. The DoD gate (above) supersedes the pre-deploy checklist and verification matrix in this file.
- `character_weapon_variants/DEVELOPMENT.md` — architectural reference for variant creation: rarity system, blacksmith template pattern, skin system, icon atlases, properties/traits, registration timing, custom templates / stat modifications, model scaling, base-weapon catalog. Cross-references RECIPES.md and ANIMATION_FIX_PLAYBOOK.md.
- `character_weapon_variants/ANIMATION_FIX_PLAYBOOK.md` — 9-step closed-vocabulary procedure for fixing 3P animations on cross-character variants. Read before touching `anim_event_3p`, `wield_anim_3p`, or any `_cross_access_action_remap` entry.
- `character_weapon_variants/J_LEFTWEAPONATTACH_INVESTIGATION.md` — post-mortem for the ~20-version dual-wield rig saga. Read once before adding any dual-wield variant.
- `character_weapon_variants/CHANGELOG.md` — version history for the Character Weapon Variants mod. Best source of "why we do X" — most recipes have a CHANGELOG entry behind every load-bearing rule.
- `character_weapon_variants/CODE_REVIEW.md` — STALE point-in-time review at v0.1.56-dev. Historical context only.
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
