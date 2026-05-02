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
| career_tweaker | `crt` | 3716286199 | **VMB** | Talent/ability swapping (scaffolded) |
| enemy_tweaker | `enemy_tweaker` | 3716780252 | **VMB** | Enemy spawns, horde compositions, breed substitution |
<!-- REVIEW: character_weapon_variants is actually PUBLISHED (Workshop ID 3716869446). itemV2.cfg has published_id = 3716869446L; deploy_all.ps1 maps it; reference_build_deploy.md memory lists it. Update to 3716869446 (private). -->
| character_weapon_variants | `character_weapon_variants` | 3716869446 | **VMB** | New weapon items grafted from cross-character models (MoreItemsLibrary) |
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
| In-game (keep/mission) | `GearUtils.create_equipment` | `result.left_unit_1p`, `.right_unit_1p`, `.left_unit_3p`, `.right_unit_3p` |
| Inventory character preview | `HeroPreviewer._spawn_item` | `self._equipment_units[slot].left` / `.right` |
| Illusion/skin browser | `LootItemUnitPreviewer.spawn_units` | `self._spawned_units` array (left=index 1, right=index 2) |

`MenuWorldPreviewer._spawn_item_unit` fires once per unit with **no hand indicator** — do not use it for per-hand operations.

### Shield/Weapon Unit Architecture

Shield weapons use **two independent units**: right hand (weapon) and left hand (shield). They attach to separate skeleton nodes and can be scaled, swapped, or offset independently. See `DEVELOPMENT.md` for unit paths and the `_weapon_scale_overrides` / `_custom_illusions` systems.

### Animation Remapping (weapon_tweaker)

VT2 uses two separate units for the local player:
- `player.player_unit` = **3P body** (receives `anim_event_3p`)
- Separate non-player unit = **1P hands** (receives `anim_event`)

Cross-career weapons need animation redirects because different character skeletons have different state machines. The system uses three layers:
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
- `character_weapon_variants/CHANGELOG.md` — version history for the Character Weapon Variants mod
- `character_weapon_variants/DEVELOPMENT.md` — how to add variant weapons (rarity pattern, skin system, icon atlases, traits/properties, registration timing)
- `character_weapon_variants/TODO.md` — feature roadmap for cross-character weapon variants
- `cosmetics_tweaker/TODO.md` — feature roadmap for cosmetics-specific work
