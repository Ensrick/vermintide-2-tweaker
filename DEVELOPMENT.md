# Vermintide 2 Tweaker - Development Notes

## Project Overview

A modular set of Vermintide 2 VMF mods split from the original monolithic **"Tweaker"**.

| Mod | Internal ID | VMF Console Prefix | Workshop ID | Visibility | Build Pipeline |
| :--- | :--- | :--- | :--- | :--- | :--- |
| Chaos Wastes Tweaker | `ct` | `ct <command>` | **3712929235** | public | VMB |
| Weapon Tweaker | `wt` | `wt <command>` | **3712896117** | private | VMB |
| General Tweaker | `gt` | `gt <command>` | **3713619122** | private | VMB |
| Career Tweaker | `crt` | `crt <command>` | **3716286199** | private | VMB |
| Cosmetics Tweaker | `cosmetics_tweaker` | `cos <command>` | **3715714222** | private | VMB |
| Enemy Tweaker | `enemy_tweaker` | `enemy_tweaker et_*` | **3716780252** | private | VMB |
<!-- REVIEW: character_weapon_variants is published. itemV2.cfg published_id = 3716869446L; deploy_all.ps1 lists 3716869446. Update both Workshop ID and Visibility (visibility="private" per cfg). -->
| Character Weapon Variants | `character_weapon_variants` | (n/a) | **3716869446** | private | VMB |
| ~~Tweaker (legacy)~~ | `t` | `t <command>` | 3704660429 | n/a | SDK (kept as reference) |

## Directory Structure

```
vermintide-2-tweaker/
├── weapon_tweaker/                 <- Weapon Tweaker mod source (VMB layout)
│   ├── weapon_tweaker.mod          <- VMF entry point (still calls new_mod("wt", ...))
│   ├── itemV2.cfg                  <- Workshop upload config (read directly by ugc_tool)
│   ├── preview.jpg                 <- Workshop preview image
│   ├── resource_packages/
│   │   └── weapon_tweaker/
│   │       └── weapon_tweaker.package   <- VMB-syntax package (mod / package / lua blocks)
│   ├── scripts/mods/weapon_tweaker/
│   │   ├── weapon_tweaker.lua
│   │   ├── weapon_tweaker_backend.lua
│   │   ├── weapon_tweaker_data.lua
│   │   └── weapon_tweaker_localization.lua
│   └── bundleV2/                   <- VMB build output (generated)
├── chaos_wastes_tweaker/           <- same VMB layout as above
├── general_tweaker/                <- same VMB layout as above
├── career_tweaker/                 <- same VMB layout as above
├── cosmetics_tweaker/              <- same VMB layout (also has materials/, gui/ for cosmetic textures)
├── enemy_tweaker/                  <- same VMB layout
├── character_weapon_variants/      <- same VMB layout
├── tweaker/                        <- LEGACY -- original monolithic mod, kept as reference (still SDK)
├── old-backup/                     <- pre-VMB SDK build/upload scripts and artifacts
├── deploy_all.ps1                  <- deploys all mods to Workshop content folders (auto-detects VMB vs SDK)
├── deploy_ct.ps1, deploy_wt.ps1    <- per-mod wrappers around deploy_all.ps1
└── upload_ct.ps1, upload_wt.ps1    <- per-mod uploaders (call ugc_tool with itemV2.cfg directly)
```

## Dev Workflow: Build -> Deploy -> Restart

The game loads mods from the real Workshop content folder (`552500/<workshop_id>`).

### Quick iteration loop

```powershell
# 1. Build via VMB (Stingray compiler is wrapped by VMB)
Set-Location "C:\Users\danjo\source\repos\vermintide-2-tweaker"
node C:/Users/danjo/source/repos/vmb/vmb.js build weapon_tweaker --no-workshop --cwd

# 2. Deploy to Workshop content folder (cleans stale .mod / .mod_bundle first)
& .\deploy_all.ps1 -Mods @("weapon_tweaker")

# 3. Restart the game
#    Hot-reload (Ctrl+Shift+R) is NOT safe for weapon_tweaker or cosmetics_tweaker -- see Important Constraints in CLAUDE.md
```

### Build

```powershell
node C:/Users/danjo/source/repos/vmb/vmb.js build <mod_name> --no-workshop --cwd
```

Output goes to `<mod>\bundleV2\`. The `--no-workshop` flag allows building without an existing Workshop ID; itemV2.cfg's `published_id` is what the eventual upload targets.

### Deploy

```powershell
& .\deploy_all.ps1                                              # all configured mods
& .\deploy_all.ps1 -Mods @("weapon_tweaker", "general_tweaker") # selected mods
& .\deploy_ct.ps1                                                # convenience wrapper for chaos_wastes_tweaker
& .\deploy_wt.ps1                                                # convenience wrapper for weapon_tweaker
```

`deploy_all.ps1` auto-detects whether the mod is VMB (`bundleV2/` exists) or legacy SDK (`.build/OUT/` exists) and handles each accordingly. It also runs `Clean-StaleBundles` against the Workshop content folder before copying — important because the Lua bundle hash changes between SDK and VMB builds, and leaving an old bundle alongside the new one would cause duplicate `new_mod()` registration crashes.

### Verifying the right build is running

Each mod logs its version on init:
```
[MOD][wt][INFO] Weapon Tweaker v0.2.1-dev loaded
```
And echoes it to in-game chat. Always bump `MOD_VERSION` before every build so the running version is visually verifiable.

## Workshop Upload (VMB pipeline)

After the 2026-05-01 migration, every active mod uploads via `ugc_tool` reading `itemV2.cfg` directly from the mod's source folder. No SDK staging is needed; the ugc_tool resolves `content` and `preview` paths relative to the config file's parent directory.

### Per-mod itemV2.cfg

```ini
title = "Tweaker: Weapons";
description = "Weapon unlock and runtime experimentation for Vermintide 2. Requires VMF.";
preview = "preview.jpg";
content = "bundleV2";
language = "english";
visibility = "private";
published_id = 3712896117L;
apply_for_sanctioned_status = false;
tags = [ ];
```

- `preview` and `content` are **relative to the cfg file's parent directory**.
- `content = "bundleV2"` points at VMB's build output folder.
- `published_id` uses the `L` suffix (64-bit integer literal).
- Semicolons required on every line (parsed by `libconfig.dll`).
- **`visibility`**: do NOT set or change without explicit user direction. Two mods were once flipped to `"public"` by an automated change; both got flagged and "removed from community", which is irreversible. Default new mods to `"private"`. Per-mod intended visibility is recorded in `feedback_workshop_metadata_user_dictates.md` in memory.
- For a **new** Workshop item, set `published_id = 0L;` — the tool populates it on first upload.

### Convenience scripts

```powershell
& .\upload_ct.ps1   # uploads chaos_wastes_tweaker (visibility=public, intentional)
& .\upload_wt.ps1   # uploads weapon_tweaker (aborts if itemV2.cfg has visibility="public")
```

<!-- REVIEW: There is no upload_*.ps1 for general_tweaker, career_tweaker, cosmetics_tweaker, enemy_tweaker, or character_weapon_variants. The "For other mods, run ugc_tool directly via bash" paragraph below covers this, but consider adding a one-liner here pointing to the bash workaround (or warning that "creating an upload_<x>.ps1 must include the visibility=public abort guard for any mod whose intended visibility is private"). -->
<!-- REVIEW: STEAM REMOVAL WARNING. Two mods were once flipped to "public" by an automated change; both got flagged and "removed from community", which is irreversible (per memory feedback_workshop_metadata_user_dictates.md). The DEVELOPMENT.md note in the itemV2.cfg section captures this, but the irreversibility deserves bolder emphasis here in the upload section since this is where it bites. -->


For other mods, run ugc_tool directly via bash so the `echo y |` EULA workaround works (PowerShell `&` does not pipe stdin reliably to ugc_tool):

```bash
cd "<mod_dir>" && echo y | "/c/Program Files (x86)/Steam/steamapps/common/Vermintide 2 SDK/ugc_uploader/ugc_tool.exe" -c "<absolute path to itemV2.cfg>" -x
```

### ALWAYS verify after uploading

ugc_tool prints "Upload finished" even when content fails to transfer. The only reliable confirmation is the **File Size** shown on the Workshop item page (~1.3 MB expected). A 0-byte item means subscribers get nothing. Compare against the local `bundleV2/` total bytes.

## Weapon Unlocks

### How it works

1. **`weapon_unlock_map`** in `weapon_tweaker.lua` -- lists which weapons each career can unlock
2. **`apply_weapon_unlocks()`** -- adds the career to `ItemMasterList[weapon_key].can_wield` directly
3. **`ItemGridUI._on_category_index_change` hook** -- patches inventory filter strings so unlocked weapons appear in the UI
4. **Backend hooks** (`set_loadout_item`, `get_loadout`, `get_loadout_item_id`) -- intercept loadout save/load so the game doesn't reject cross-career weapon selections

### Do NOT hook `BackendUtils.can_wield_item`

This method is not hookable from separately-loaded Workshop mods. The old monolithic tweaker could hook it due to load-order timing, but split-out mods cannot -- regardless of whether the hook is at init time, deferred in `mod.update`, or uses string-form class names. Modifying `can_wield` lists on `ItemMasterList` directly is the correct approach (confirmed by AnyWeapon reference mod).

### Adding weapons incrementally

Add one weapon at a time to `weapon_unlock_map` and verify in-game before adding more. Adding all weapons at once risks crashes from animation/model mismatches that are hard to diagnose in bulk.

When adding a weapon:
1. Add the weapon key to the career's list in `weapon_unlock_map`
2. Add a checkbox widget in `weapon_tweaker_data.lua`
3. Add a localization entry in `weapon_tweaker_localization.lua`
4. Build, deploy, hot reload, test

### Weapon key reference

- `es_sword_shield_breton` -- Bretonnian Sword & Shield
- `es_bastard_sword` -- Bretonnian Longsword
- `es_sword_shield` -- Sword & Shield (Empire)
- `es_deus_01` -- Kruber's Spear & Shield (DLC "grass"). NOT named `es_spear_shield` -- uses Chaos Wastes DLC naming convention.
- `dr_1h_throwing_axes` -- Bardin's Throwing Axes (DLC "scorpion"). Native to Slayer + Ranger Veteran.
- `dr_crossbow` -- Bardin's Crossbow. Native to Ironbreaker + Ranger Veteran (NOT Engineer).
- `we_1h_spears_shield` -- Kerillian's Spear & Shield. Do NOT use on non-elf careers -- crashes hero previewer.
- See `ITEM_LIST.md` for the full catalog dumped from `ItemMasterList`

### DLC weapon naming conventions

DLC weapons sometimes use `<prefix>_deus_01` (Chaos Wastes / "grass" DLC) instead of descriptive names. Always use `wt dump` in-game or check the source code `item_master_list_*.lua` files to confirm weapon keys -- don't guess from the weapon's display name.

## Animation System Architecture

### The Two Units: Understanding 1P vs 3P

VT2 uses two separate units for the local player:

| Unit | How to identify | What it renders | What it receives |
| :--- | :--- | :--- | :--- |
| `player.player_unit` | `_is_local_player_unit(unit) == true` | **3P body** (visible to other players) | `anim_event_3p` from weapon action data |
| Non-player unit | `_is_local_player_unit(unit) == false` | **1P hands** (visible to you) | `anim_event` from weapon action data |

**This is counterintuitive.** Despite being called `player_unit`, it is the third-person body. The first-person hands/weapon view is a separate unit that is NOT `player_unit`.

Evidence: the billhook's `default_stab` action defines `anim_event = attack_swing_charge_stab` and `anim_event_3p = attack_swing_stab_charge`. In practice, `player_unit` receives `attack_swing_stab_charge` (the 3P value) and the non-player unit receives `attack_swing_charge_stab` (the 1P value). Confirmed via `wt dump_actions billhook` + `wt animlog`.

### Weapon Action Data: anim_event vs anim_event_3p

Each weapon action in the `Weapons` global table has two animation event fields:

```lua
-- From wt dump_actions billhook:
action_one.default_stab   1P=attack_swing_charge_stab   3P=attack_swing_stab_charge
action_one.default_left   1P=attack_swing_charge_down    3P=attack_swing_charge_left_diagonal
action_one.heavy_attack_stab  1P=attack_swing_heavy_stab  3P=-    (no override, both units get anim_event)
```

- `anim_event` → sent to the 1P hands unit. Also used as fallback for player_unit if no `anim_event_3p` exists.
- `anim_event_3p` → sent to `player_unit` (3P body), overriding `anim_event` on that unit.

Many weapons (e.g., elf spear, Kruber's heavy spear) have **no `anim_event_3p` fields at all** — both units receive `anim_event`. This is fine for the native career but breaks when the weapon is equipped cross-career, because the 3P body can't play those events in a different weapon stance.

### Three Layers of Animation Fixes for Cross-Career Weapons

#### Layer 1: Stance Redirect (`to_` events)

Sets the 3P body's idle/walk/block stance to match the target weapon. Without this, the character holds the weapon wrong.

```lua
-- Career-aware: elf spear on Saltzpyre → use billhook stance
to_spear → to_2h_billhook   (via _career_anim_redirect overrides)
```

This alone fixes idle, walking, blocking, and push animations — anything driven by the stance blend tree. Attack animations still won't work because the attack events don't match.

#### Layer 2: 1P Event Redirect (`_anim_redirect`)

Fixes missing 1P events on `player_unit` (which is actually the 3P body, but these events affect the fallback animations). Only fires when the event is MISSING on the unit's skeleton.

```lua
attack_swing_down_left_axe → attack_swing_down_left   (axe diagonal doesn't exist on all skeletons)
push_stab                  → attack_swing_stab         (push follow-up missing on some skeletons)
```

#### Layer 3: 3P Body Attack Remap (`_3p_weapon_remap`)

The key system for making cross-career weapons animate in 3rd person. Intercepts attack events on `player_unit` and replaces them with the target weapon's `anim_event_3p` values.

```lua
-- Elf spear on Saltzpyre: remap spear anim_event → billhook anim_event_3p
local _3p_remap_spear_to_billhook = {
    attack_swing_charge_right  = "attack_swing_stab_charge",         -- billhook default_stab 3P
    attack_swing_charge_left   = "attack_swing_charge_left_diagonal", -- billhook default_left 3P
    attack_swing_down_right    = "attack_swing_stab",                 -- billhook light_attack_stab_2 3P
    attack_swing_down_left_axe = "attack_swing_left_diagonal",        -- billhook light_attack_bopp 3P
    attack_swing_heavy         = "attack_swing_heavy_stab",           -- billhook heavy (no 3P override)
    push_stab                  = "attack_swing_left_diagonal",        -- billhook push follow-up
}
```

The remap MUST target `is_local` (player_unit = 3P body) and use `anim_event_3p` values from the target weapon. Using `anim_event` values will send events to the wrong animation layer.

**Activated by:** the career redirect sets `_3p_weapon_remap` when a `to_` event triggers a career override (e.g., `to_spear` on Saltzpyre → `to_2h_billhook`).

**Cleared by:** weapon switches only. Must NOT be cleared by non-weapon `to_` events.

### Non-Weapon `to_` Events (Trap)

The game fires many `to_` events that are NOT weapon switches:

| Event | Trigger |
| :--- | :--- |
| `to_crouch` / `to_uncrouch` | Crouching |
| `to_onground` | Landing after a jump |
| `to_zoom` / `to_unzoom` | Ranged weapon zoom |

If `_3p_weapon_remap` is cleared on these, the 3P remap silently stops mid-combat. The fix: whitelist actual weapon events instead of checking `event_name:sub(1, 3) == "to_"`.

### Animation "Corruption"

Forcing a fallback animation (e.g., using 1H Sword anims for a Rapier) can overwrite a character's native animations.

Always verify if the unit already possesses the animation event before applying a redirection:
```lua
if Unit.has_animation_event(unit, event_name) then
    return func(unit, event_name, ...)
end
-- Only then apply fallback...
```

### Debug Commands

- `wt animlog` -- toggles animation event logging; tags each event as "1P" (player_unit / 3P body) or "3P" (1P hands); shows `[MISSING]`, `REDIR ->`, and `3P REMAP ->` markers
- `wt dump_actions [pattern]` -- dumps all `Weapons` template actions matching pattern (or ALL templates if no pattern), showing `anim_event` (1P hands) and `anim_event_3p` (3P body) fields; output goes to both in-game chat and mod log file; sorted alphabetically; essential for building remap tables
- `wt force3p <event>` -- forces an animation event on the last-seen non-player unit (for testing if events exist/play)
- `wt dump` -- dumps equipped item data to log

### Building a New 3P Remap Table

1. Run `wt dump_actions <source_weapon>` and `wt dump_actions <target_weapon>` in-game
2. For each source weapon action, map its `anim_event` value to the target weapon's `anim_event_3p` value (or `anim_event` if no 3P override exists for that action)
3. Create a Lua table with these mappings
4. Add it to `_3p_remap_triggers` keyed by the source weapon's `to_` event name
5. Add the source weapon's `to_` event to `_career_anim_redirect` with the target weapon's `to_` event as the override
6. Verify with `wt animlog` — every attack should show a `3P REMAP ->` line on `player_unit`

## Cross-Career Weapon Animation Status

**Moved to [WEAPON_CATALOG.md](WEAPON_CATALOG.md)** — comprehensive per-weapon reference with attack chains, animation events, cross-career status tables, and data collection gaps.

The tables below are kept for historical reference but **WEAPON_CATALOG.md is the authoritative source**.

Legend: **OK** = tested working | **Redirect** = stance redirect in place | **Remap** = 3P remap table built | **Untested** = needs in-game verification

### Polearms / Spears / Billhook

| Weapon | Key | On Career(s) | Status | Notes |
| :--- | :--- | :--- | :--- | :--- |
| Elf Spear | `we_spear` | Saltzpyre (WHC/BH/Zealot) | **OK** — Redirect + Remap | `to_spear`→`to_2h_billhook`, `_3p_remap_spear_to_billhook`. Fully working v0.7.1 |
| Elf Spear | `we_spear` | Saltzpyre (Priest) | **Redirect only** | `to_spear`→`to_1h_hammer`. Untested |
| Elf Spear | `we_spear` | Kruber (all) | **Redirect only** | Native `to_spear` exists. Untested |
| Kruber Heavy Spear | `es_2h_heavy_spear` | Saltzpyre (WHC/BH/Zealot) | **Redirect only** | `to_polearm`→`to_2h_billhook`, shares spear remap. Untested — may need own remap table |
| Kruber Heavy Spear | `es_2h_heavy_spear` | Saltzpyre (Priest) | **Redirect only** | `to_polearm`→`to_1h_hammer`. Untested |
| Kruber Heavy Spear | `es_2h_heavy_spear` | Kerillian (all) | **Redirect only** | `to_polearm`→`to_spear`. Untested |
| Halberd | `es_halberd` | Kerillian (all) | **Untested** | No redirect yet |
| Halberd | `es_halberd` | Saltzpyre (WHC/BH/Zealot) | **Untested** | No redirect yet |
| Halberd | `es_halberd` | Saltzpyre (Priest) | **Untested** | No redirect yet |
| Billhook | `wh_2h_billhook` | Kruber (all) | **Redirect only** | `to_2h_billhook`→`to_polearm`. Untested |
| Billhook | `wh_2h_billhook` | Saltzpyre (Priest) | **Redirect only** | `to_2h_billhook`→`to_1h_hammer`. Untested |
| Elf Spear & Shield | `we_1h_spears_shield` | Kruber (all) | **Redirect + Remap** | `to_1h_spear_shield`→`to_es_deus_01`. Crashes hero previewer on non-elf |
| Kruber Spear & Shield | `es_deus_01` | Kerillian (all) | **OK — Redirect + Remap** | `to_es_deus_01`→`to_1h_spear_shield`. H2 works natively. v0.10.21 |

### Greatswords

| Weapon | Key | On Career(s) | Status | Notes |
| :--- | :--- | :--- | :--- | :--- |
| Elf Greatsword | `we_2h_sword` | Kruber (all) | **Untested** | Elf uses different anims than es/wh. Redirect expected to work |
| Elf Greatsword | `we_2h_sword` | Saltzpyre (WHC/BH/Zealot) | **Untested** | Same as above |
| Kruber Greatsword | `es_2h_sword` | Saltzpyre (WHC/BH/Zealot) | **Untested** | es/wh share anims — may just work |
| Kruber Greatsword | `es_2h_sword` | Kerillian (all) | **OK — Redirect + Remap** | `to_2h_sword`→`to_2h_sword_we`, template remap for diagonals + push. Grip `-0.085`. v0.10.16+ |
| Saltzpyre Greatsword | `wh_2h_sword` | Kruber (all) | **Untested** | es/wh share anims — may just work |
| Saltzpyre Greatsword | `wh_2h_sword` | Kerillian (all) | **OK — Redirect + Remap** | Same as es_2h_sword. v0.10.16+ |

### Greataxe / Greathammers

| Weapon | Key | On Career(s) | Status | Notes |
| :--- | :--- | :--- | :--- | :--- |
| Bardin Greataxe | `dr_2h_axe` | Kruber (all) | **Untested** | Analogous to Kruber's greathammer — no redirect expected |
| Bardin Greathammer | `dr_2h_hammer` | Kruber (all) | **Untested** | Should share stance with Kruber's greathammer |
| Kruber Greathammer | `es_2h_hammer` | Bardin (all) | **Untested** | Should share stance with Bardin's greathammer |
| Saltzpyre Greathammer | `wh_2h_hammer` | Saltzpyre (WHC/BH/Zealot) | **Untested** | Priest-native; same model expected on WHC/BH/Zealot |
| Saltzpyre Dual Hammers | `wh_dual_hammer` | Saltzpyre (WHC/BH/Zealot) | **Untested** | Priest-native; analogous stance expected |
| Saltzpyre Dual Hammers | `wh_dual_hammer` | Bardin (all) | **Untested** | Should share stance with Bardin's dual hammers |
| Bardin Dual Hammers | `dr_dual_wield_hammers` | Saltzpyre (all) | **Untested** | Should share stance with Saltzpyre's dual hammers |
| Bardin Dual Hammers | `dr_dual_wield_hammers` | Bardin (non-native) | **Untested** | Enabling on careers that don't have it natively |

### 1H Swords

| Weapon | Key | On Career(s) | Status | Notes |
| :--- | :--- | :--- | :--- | :--- |
| Kruber Sword | `es_1h_sword` | Bardin (all), Kerillian (all), Saltzpyre (all), Sienna (all) | **Untested** | Likely shared `to_1h_sword` stance |
| Sienna Sword | `bw_sword` | Kruber (all), Bardin (all), Kerillian (all exc. Maiden), Saltzpyre (all) | **Untested** | |
| Kerillian Sword | `we_1h_sword` | Kruber (all), Bardin (all), Saltzpyre (all), Sienna (all) | **Untested** | |

### 1H Axes

| Weapon | Key | On Career(s) | Status | Notes |
| :--- | :--- | :--- | :--- | :--- |
| Bardin Axe | `dr_1h_axe` | Kruber (Merc), Kerillian (all exc. Maiden), Saltzpyre (WHC/BH/Zealot/Priest), Sienna (all) | **Untested** | Redirect for Priest: `to_1h_axe`→`to_1h_hammer` |
| Saltzpyre Axe | `wh_1h_axe` | Kruber (all), Kerillian (all), Sienna (all) | **Untested** | |

### 1H Hammers / Maces

| Weapon | Key | On Career(s) | Status | Notes |
| :--- | :--- | :--- | :--- | :--- |
| Bardin Hammer | `dr_1h_hammer` | Kerillian (all) | **OK** — Redirect | `to_1h_hammer`→`to_1h_sword`. No attack remap needed. v0.10.10 |
| Bardin Hammer | `dr_1h_hammer` | Kruber (all), Saltzpyre (all) | **Untested** | `to_1h_hammer` native on es/wh skeletons |
| Kruber Mace | `es_1h_mace` | Kerillian (all) | **OK** — Redirect | Same `to_1h_hammer` redirect. Confirmed working v0.10.10 |
| Kruber Mace | `es_1h_mace` | Bardin (all), Saltzpyre (all), Sienna (all) | **Untested** | Same `to_1h_hammer` wield_anim |
| Saltzpyre Hammer | `wh_1h_hammer` | Kerillian (all) | **OK** — Redirect | Same `to_1h_hammer` redirect. Confirmed working v0.10.10 |
| Saltzpyre Hammer | `wh_1h_hammer` | Kruber (all), Bardin (all), Sienna (all) | **Untested** | Same `to_1h_hammer` wield_anim |

### Falchion / Crowbill

| Weapon | Key | On Career(s) | Status | Notes |
| :--- | :--- | :--- | :--- | :--- |
| Falchion | `wh_1h_falchion` | Kruber (all), Bardin (all), Kerillian (all), Sienna (all) | **Untested** | Redirect for Priest: `to_1h_falchion`→`to_1h_hammer` |
| Crowbill | `bw_1h_crowbill` | Kruber (all), Bardin (all), Kerillian (all), Saltzpyre (all) | **Untested** | Redirect: `to_1h_crowbill`→`to_1h_sword` (Priest→`to_1h_hammer`) |

### Shields

| Weapon | Key | On Career(s) | Status | Notes |
| :--- | :--- | :--- | :--- | :--- |
| Bretonnian S&S | `es_sword_shield_breton` | Kruber (Merc) | **Untested** | |
| Bardin Hammer & Shield | `dr_shield_hammer` | Kruber (all exc. Merc), Saltzpyre (Priest) | **Untested** | |
| Saltzpyre Hammer & Shield | `wh_hammer_shield` | Kruber (all), Bardin (all) | **Untested** | |
| Kruber Mace & Shield | `es_mace_shield` | Bardin (all), Saltzpyre (Priest) | **Untested** | |

### Flails

| Weapon | Key | On Career(s) | Status | Notes |
| :--- | :--- | :--- | :--- | :--- |
| Saltzpyre Flail | `es_1h_flail` | Kruber (all exc. Huntsman), Saltzpyre (Priest), Sienna (all) | **Untested** | |
| Sienna Flaming Flail | `bw_1h_flail_flaming` | Kruber (all), Saltzpyre (WHC/BH/Zealot/Priest) | **Untested** | |

### Ranged

| Weapon | Key | On Career(s) | Status | Notes |
| :--- | :--- | :--- | :--- | :--- |
| Kerillian Longbow | `we_longbow` | Kruber (all) | **Redirect only** | `to_longbow`→`to_es_longbow`. Untested |
| Kruber Longbow | `es_longbow` | Kerillian (all), Grail Knight | **Untested** | |
| Kerillian Volley Xbow | `we_crossbow_repeater` | Kerillian (native careers), Saltzpyre (all) | **Redirect only** | `to_repeating_crossbow_elf`→`to_repeating_crossbow`. Untested |
| Saltzpyre Volley Xbow | `wh_crossbow_repeater` | Kerillian (all) | **Untested** | |
| Saltzpyre Crossbow | `wh_crossbow` | Bardin (Ranger/Slayer/Engineer) | **Untested** | |
| Bardin Crossbow | `dr_crossbow` | Saltzpyre (WHC/BH/Zealot), Bardin (Engineer) | **Untested** | |
| Bardin Throwing Axes | `dr_1h_throwing_axes` | Bardin (IB/Engineer) | **Untested** | |
| Bardin Trollhammer | `dr_deus_01` | Bardin (Ranger/Slayer) | **Untested** | |
| Kruber Handgun | `es_handgun` | Grail Knight | **Untested** | |
| Kruber Repeating Handgun | `es_repeating_handgun` | Grail Knight | **Untested** | |
| Kruber Blunderbuss | `es_blunderbuss` | Grail Knight | **Untested** | |
| Bardin Handgun | `dr_handgun` | Bardin (Slayer), Kruber (all) | **Untested** | Analogous to Kruber's handgun |
| Kruber Handgun | `es_handgun` | Grail Knight, Bardin (all) | **Untested** | Analogous to Bardin's handgun |
| Bardin Grudge-Raker | `dr_rakegun` | Bardin (Slayer) | **Untested** | |
| Bardin Steam Pistol | `dr_steam_pistol` | Bardin (Slayer) | **Untested** | |
| Bardin Dual Axes | `dr_dual_wield_axes` | Bardin (Ranger/IB/Engineer) | **Untested** | |
| Bardin Axe & Shield | `dr_shield_axe` | Bardin (Slayer) | **Untested** | |

### Testing checklist for new cross-career weapons

1. Equip weapon, check stance event in animlog (`to_` event on wield)
2. Verify 1P attack animations play (first-person hands)
3. Check 3P body animations with another player or `wt animlog` — look for `[MISSING]` on `player_unit`
4. If 3P attacks show no animation, build a remap table using `wt dump_actions`
5. Test crouch, jump, weapon swap, push-attack — confirm remap doesn't break
6. Note: `we_1h_spears_shield` crashes the hero previewer on non-elf careers — this is a known issue but gameplay may still work

## VMF Hook Timing

- **Globals** (`ItemGridUI`, etc.) -- hook at the top level of `M.install()`, during mod init
- **Backend instances** (`items_interface:set_loadout_item`, etc.) -- defer inside `mod.update` behind `Managers.backend` check
- **`BackendUtils.can_wield_item`** -- don't hook it at all (see above)
- **String-form hooks** (`mod:hook("ClassName", ...)`) -- use when the class isn't loaded yet at mod init; VMF resolves lazily

## Key Technical Facts

### Lua / VMF

- Lua 5.1: use `unpack()` not `table.unpack()`
- Commands: `mod:command("win", "description", function() ... end)` -- called as `wt win` in VMF console
- Hook with return: `mod:hook(Class, "method", function(func, self, ...) ... return func(self, ...) end)`
- Hook without return: `mod:hook_safe(Class, "method", function(self, ...) ... end)`
- Settings: `mod:get("setting_id")` reads current value
- Logging: `mod:info(...)` logs to console file only; `mod:echo(...)` shows in in-game chat
- VMF localization: every `setting_id` in `_data.lua` must have a matching key in `_localization.lua` or raw IDs show in the menu

### Chaos Wastes Internals

- Chaos Wastes = "deus" mode internally
- Coin system: `DeusRunController:on_soft_currency_picked_up(amount, unit)` -- amount is `args[1]`, NOT `args[2]`
- Boon selection: `DeusPowerUpUtils.generate_random_power_ups(...)` -- default count 4 for shrines, 3 for chests
- Curses/mutators: `Mutator:activate()` -- name in `self._name`, `self:name()`, or `self.mutator_name`
- Win trigger: `Managers.state.game_mode:complete_level()`
- Run init: `DeusRunController:init()`

### Workshop / Build

- Steam App ID: 552500
- SDK: `C:\Program Files (x86)\Steam\steamapps\common\Vermintide 2 SDK\`
- ugc_tool: `{SDK}\ugc_uploader\ugc_tool.exe`
- Build compiler: `{SDK}\bin\stingray_win64_dev_x64.exe`
<!-- REVIEW: Upload staging is now obsolete for active mods. ugc_tool reads itemV2.cfg directly from the per-mod source dir; content="bundleV2" resolves relative to the cfg parent. Only the legacy /tweaker mod still uses sample_item staging (and it's effectively frozen). The line below is fine as a "where the SDK puts its sample" note, but should be marked legacy. -->
- Upload staging: `{SDK}\ugc_uploader\sample_item\` (the tool's native staging area)
- `apply_for_sanctioned_status = false` is valid and should be kept
- `tags = [ ];` is added automatically by the tool -- do NOT add it manually before first upload
- Semicolons are REQUIRED on every line in item.cfg (parsed by libconfig)
- The `L` suffix is REQUIRED on `published_id` (64-bit integer literal)
- VMB build output (`bundleV2/`) already includes the `.mod_bundle` extension; only the legacy SDK pipeline produced extensionless files that `deploy_all.ps1` had to rename

## Known Errors & Fixes

### VMF hook error: `trying to hook function or method that doesn't exist: [BackendUtils.can_wield_item]`

- **Cause:** `BackendUtils.can_wield_item` is not hookable from separately-loaded Workshop mods. The old monolithic tweaker could hook it due to load-order timing, but split-out mods cannot -- regardless of whether the hook is at init time, deferred in `mod.update`, or uses string-form class names.
- **Fix:** Don't hook `BackendUtils.can_wield_item` at all. Instead, modify `ItemMasterList[weapon_key].can_wield` directly (add the career name to the list). This is how AnyWeapon (reference mod) handles it. Use `ItemGridUI._on_category_index_change` for inventory filter patching.

### VMF hook error: `argument 'obj' should have the 'string/table' type, not 'nil'`

- **Cause:** Passing the class directly (e.g. `mod:hook(DeusRunController, ...)`) when the class isn't loaded yet at mod init time.
- **Fix:** Always pass the class name as a string: `mod:hook("DeusRunController", ...)`. VMF resolves it lazily when the hook fires.

### Lua crash: `attempt to call field 'unpack' (a nil value)`

- **Cause:** Vermintide 2 uses Lua 5.1 which has global `unpack()`, not `table.unpack()`.
- **Fix:** Always use `unpack(args)`, never `table.unpack(args)`.

### Coin multiplier not working (wrong argument index)

- **Cause:** `on_soft_currency_picked_up(amount, unit)` -- the amount is `args[1]`, not `args[2]`.
- **Fix:** Read and multiply `args[1]`.

### 3P remap stops working mid-combat (animations revert)

- **Cause:** Non-weapon `to_` events (`to_onground`, `to_crouch`, `to_zoom`, etc.) were clearing `_3p_weapon_remap`. These fire on jumps, crouches, and zoom but are NOT weapon switches.
- **Fix:** Don't clear `_3p_weapon_remap` on all `to_` events. Whitelist only actual weapon switch events: keys in `_career_anim_redirect`, `to_crossbow_loaded`, `to_grenade`, `to_2h_billhook`.

### 3P remap events firing but no visual animation

- **Cause:** Remap was targeting the wrong unit. `player_unit` (tagged "1P" in animlog) is actually the 3P body. The remap was running on `not is_local` (1P hands) instead of `is_local` (3P body). Also, remap values used `anim_event` names instead of `anim_event_3p` names.
- **Fix:** Flip to `is_local` and use target weapon's `anim_event_3p` values. Use `wt dump_actions` to find correct values.

### ItemMasterList crashify on unknown keys

- **Cause:** `ItemMasterList` has a `__index` metamethod that calls `crashify` (engine crash reporter) for any key not in the table. Doing `ItemMasterList[key]` on a key from another source (e.g. `WeaponSkins.skins` which includes Loremaster's Armoury entries) triggers a crash exception.
- **Fix:** Always use `rawget(ItemMasterList, key)` when the key might not exist. Same applies to `NetworkLookup.weapon_skins` and similar guarded tables.

### VMF localization crash: `Invalid string format for string "..."`

- **Cause:** VMF runs `string.format` on localization strings. A literal `%` followed by a non-format character (e.g. `"Horde Size (%)"`) is an invalid format specifier in Lua.
- **Fix:** Escape percent signs as `%%` in localization strings: `"Horde Size (%%)"`.

### VMF setting slider shows `<x>` / localization failure

- **Cause:** `unit_text = "x"` is treated as a localization key by VMF and fails lookup.
- **Fix:** Remove `unit_text` and `tooltip` fields from widget definitions.

### Wrong package path in .mod file

- **Cause:** Extra subdirectory in package path (`resource_packages/tweaker/tweaker` instead of `resource_packages/tweaker`).
- **Fix:** The package path should match the `.package` filename without extension.

### Workshop upload: "file not found; invalid workshop item" (0x9)

- **Cause 1:** The `published_id` references a deleted or non-existent Workshop item.
- **Fix:** Set `published_id = 0L;` to create a new item.
- **Cause 2:** Running the tool from any directory other than the SDK's `ugc_uploader` folder.
- **Fix:** Always `Set-Location` to the SDK folder before running. See Upload section.
- **Cause 3:** `preview.jpg` or `content/` directory doesn't exist at the resolved path.
- **Fix:** Verify files exist. Use relative paths from the config file's location inside the SDK `sample_item` folder.

### Workshop upload: "generic failure (probably empty content directory)" (0x2)

- **Cause:** The tool found the config but couldn't resolve the `content` path to an actual directory with files.
- **Fix:** Stage content into `SDK/ugc_uploader/sample_item/content/` and use `content = "content";` (relative).

### Workshop upload: "invalid param" (0x8)

- **Cause:** Game was running while uploading, or Steam session stale.
- **Fix:** Close the game. Run upload from user's own terminal (not automated).

### Workshop upload: "access denied" (0xf) on item creation

- **Cause:** Game was running, blocking the Steam app session.
- **Fix:** Close the game before running ugc_tool.

### Mod shows in launcher but not in VMF F4 menu -- "not found in the workshop folder"

- **Cause:** Workshop item is pending Steam's automated review. Steam hasn't synced the download yet, so `mod.bin` and `mod.cer` (EAC certificates required by ModManager) are missing from the Workshop folder. Manually placing bundle files there is not enough.
- **Fix:** Wait for Steam review to clear, then unsubscribe + re-subscribe to get a clean certified download. (Historical workaround `install_local.bat` was moved to `old-backup/` during the VMB migration; it relied on the now-retired SDK pipeline.)

### Game crash: bundle hash not found (e.g. `05a4cebb8c3c93bf.mod_bundle not found`)

- **Cause:** Build output files have no extension, but the game requires `.mod_bundle` extension.
- **Fix:** When copying to Workshop folder or upload/content, rename each bundle file from `{hash}` to `{hash}.mod_bundle`. The `.mod` file is copied as-is.

### deploy_all.ps1: variables null inside foreach loop

- **Cause:** PowerShell 5.1 scoping -- variables defined outside a `foreach` loop can be clobbered or invisible inside it.
- **Fix:** Refactor into a function (`Deploy-ToDir`) so variables are passed as parameters rather than relying on outer scope.

## Cosmetics Tweaker — Weapon Model & Shield Swap System

### Overview

The `cosmetics_tweaker` mod (Workshop 3715714222, internal ID `cosmetics_tweaker`) handles visual-only weapon modifications: per-axis scaling, grip offsets, hat tinting, cosmetic unlocks, and shield model swaps. It is built with **VMB** (not the raw Stingray compiler used by the other mods).

### Build & Deploy

```powershell
# Build (from vermintide-2-tweaker/ root)
Set-Location "C:\Users\danjo\source\repos\vermintide-2-tweaker"
node C:/Users/danjo/source/repos/vmb/vmb.js build cosmetics_tweaker --no-workshop --cwd

# Deploy
& .\deploy_all.ps1 -Mods @("cosmetics_tweaker")
```

Output goes to `cosmetics_tweaker/bundleV2/`. The `deploy_all.ps1` script auto-detects the VMB layout (after the 2026-05-01 migration of all Stingray-SDK mods to VMB, the auto-detection covers cosmetics_tweaker too).

**Hot-reload crashes (Ctrl+Shift+R):** weapon_tweaker and cosmetics_tweaker are NOT safe to hot-reload. Both hook unit creation paths (`GearUtils.create_equipment`, `BackendUtils.get_item_units`), and cosmetics_tweaker bundles non-Lua resources (materials/textures). The Stingray engine holds C++-level locks on spawned unit and material resources that cannot be released from Lua — `Mod.release_resource_package` triggers `ensure_unlocked` and crashes. Attempted workarounds (hooking `ModManager.unload_mod`, clearing `loaded_packages` in `on_reload`) either failed to fire (VMF's mod object is not `mod.object` in ModManager) or caused worse cascading failures (wiping third-party atlas handles, increasing lock counts). **Always do a full game restart** after deploying weapon_tweaker or cosmetics_tweaker changes. chaos_wastes_tweaker, general_tweaker, and career_tweaker are Lua-only and may survive hot-reload, but a restart is safest.

**`UIRenderer._injected_material_sets` poisoning:** Adding a custom material to `UIRenderer._injected_material_sets` is DANGEROUS. If the engine can't resolve the material path when `UIRenderer.create` runs, it silently poisons the **entire** Gui material loading pass — ALL materials (including VMF's `vmf_atlas` and other mods' atlases) fail to load on every UIRenderer created after that. Symptoms: VMF options crash with `Material 'vmf_atlas' not found in Gui`, NewsFeedUI crash with `armoury_atlas not found`, blank settings panel. The poisoning persists for the entire session. Do NOT inject materials into `_injected_material_sets` unless the resource package is confirmed loaded and the material is verified resolvable. Prefer per-renderer injection over global injection.

### Shield & Weapon Unit Architecture

VT2 shield weapons use **two independent units**:
- **Right hand** (`right_unit_1p` / `right_unit_3p`): the weapon (sword, mace, axe, etc.)
- **Left hand** (`left_unit_1p` / `left_unit_3p`): the shield

They are spawned separately, attached to different skeleton nodes (`j_rightweaponattach` / `j_leftweaponattach`), and can be scaled, offset, or swapped independently.

### Three Rendering Paths

Any visual override must cover **all three** places weapon units are rendered:

| Path | Hook Target | What It Renders | How Units Are Accessed |
| :--- | :--- | :--- | :--- |
| **In-game** (keep/mission) | `GearUtils.create_equipment` | Actual gameplay model | `result.left_unit_1p`, `result.right_unit_1p`, `result.left_unit_3p`, `result.right_unit_3p` — separate unit objects per hand |
| **Inventory character preview** | `HeroPreviewer._spawn_item` | Full character in inventory screen | `self._equipment_units[slot_idx].left` / `.right` — separate unit objects per hand |
| **Illusion/skin browser** | `LootItemUnitPreviewer.spawn_units` | Weapon close-up in skin selection UI | `self._spawned_units` array — left (shield) at index 1, right (weapon) at index 2. Spawn order matches `_load_item_units` which always appends left then right |

Key differences:
- `GearUtils` and `HeroPreviewer` provide explicit left/right separation
- `LootItemUnitPreviewer` uses spawn order (left=1, right=2) — identified via `spawn_data` entries
- The old `MenuWorldPreviewer._spawn_item_unit` hook is **NOT usable** for per-hand targeting — it fires once per unit with no hand indicator. Use `HeroPreviewer._spawn_item` instead (MenuWorldPreviewer extends HeroPreviewer)

### Weapon Scale Overrides (`_unit_path_scale_overrides`)

cosmetics_tweaker scales weapon models based on the **resolved unit path** (the actual model the engine loads), not on the item template key. This way a custom item that uses a base weapon's template but a different model (e.g. character_weapon_variants Imperial Longsword on `bastard_sword_template` with `wpn_2h_sword_*` model) is correctly ignored, while ANY item — vanilla or modded — that loads a flagged model gets scaled.

```lua
local _unit_path_scale_overrides = {
    {
        pattern = "wpn_emp_gk_sword_",   -- substring match (string.find ..., 1, true)
        factor  = _breton_sword_thiccc,  -- function(get) | {x,y,z} | number
        hand    = "right",                -- "right" | "left" | nil (both)
    },
}
```

Schema:
- **`pattern`**: literal substring matched against the unit path returned by `BackendUtils.get_item_units`. If the equipped item has a skin, the skin's `right_hand_unit` is checked; otherwise `item_data.right_hand_unit`.
- **`factor`**: a `function(get)` returning `{x,y,z}|number|nil` (toggle off → return nil), a literal `{x,y,z}` table, or a uniform number. Functions are called every apply, so live setting toggles take effect on next equip.
- **`hand`**: restricts to one hand. `"right"` only scales the weapon hand (used to keep paired shields at native scale); `"left"` only the shield/offhand; `nil` scales both.

#### Coverage across the three rendering paths

The scale system runs in **all three** hooks (see "Three Rendering Paths" above):
1. `GearUtils.create_equipment` — `_scale_units(result, item_data, result.skin)`
2. `HeroPreviewer._spawn_item` / `MenuWorldPreviewer._spawn_item` — `_spawn_item_post` walks `self._item_info_by_slot`, looks up `slot_index` from each entry's `spawn_data[1]`, and calls `_apply_unit_path_scale_hand` per slot
3. `LootItemUnitPreviewer.spawn_units` — applies to spawn-order indices `units[2]` (right) and `units[1]` (left)

The two menu paths (#2, #3) additionally gate on `not item_data.cwv_variant` for defence-in-depth. The in-game path doesn't — its unit-path matching alone is sufficient.

#### Grip-offset overrides (`_weapon_grip_offsets`)

Separate table, **item-name-keyed** (NOT unit-path). Currently empty; kept as the extension point for future grip tweaks. Z is along the blade — sign convention per `feedback_grip_offset_sign.md` (+Z lowers grip toward the hilt, -Z raises grip toward the blade tip). Grip-offset runs only in the in-game `GearUtils` hook by intentional design — preview paths show the un-offset weapon.

### Shield Model Swaps (`_shield_swap_map` + `BackendUtils.get_item_units` hook)

```lua
local _shield_swap_map = {
    es_mace_shield = {
        setting_id = "es_mace_shield_gk_shield",
        left_hand_unit = "units/weapons/player/wpn_emp_gk_shield_03/wpn_emp_gk_shield_03",
    },
}
```

The swap hooks `BackendUtils.get_item_units` to replace `left_hand_unit` in the returned table **before** the unit is spawned. This is the cleanest approach because:
1. It runs before package loading — the game loads the correct package for the swapped unit
2. It covers all three rendering paths automatically (they all call `BackendUtils.get_item_units`)
3. No destroy/respawn complexity

**Important:** Hook `BackendUtils` by table reference (`mod:hook(BackendUtils, "get_item_units", ...)`), NOT by string name (`mod:hook("BackendUtils", ...)`). Guard with a nil check since `BackendUtils` may not be loaded at mod init time on some code paths.

### Available Shield Unit Paths

| Shield | Unit Path (under `units/weapons/player/`) |
| :--- | :--- |
| Empire (Kruber default) | `wpn_empire_shield_01_t1/wpn_emp_shield_01_t1` |
| Empire round (Deus) | `wpn_empire_shield_02/wpn_emp_shield_02` |
| Bretonnian GK (base) | `wpn_emp_gk_shield_03/wpn_emp_gk_shield_03` |
| Bretonnian GK (skin 01) | `wpn_emp_gk_shield_02/wpn_emp_gk_shield_02` |
| Bretonnian GK (skin 04) | `wpn_emp_gk_shield_04/wpn_emp_gk_shield_04` |
| Bretonnian GK (skin 05) | `wpn_emp_gk_shield_05/wpn_emp_gk_shield_05` |
| Bardin | `wpn_dw_shield_01_t1/wpn_dw_shield_01` |
| Kerillian | `wpn_we_shield_02/wpn_we_shield_02` |
| Warrior Priest | `wpn_wh_shield_01/wpn_wh_shield_01_t1` |
| Deus round | `wpn_es_deus_shield_02/wpn_es_deus_shield_02` |
| Deus alt | `wpn_es_deus_shield_03/wpn_es_deus_shield_03` |

Most also have `_runed_01`, `_runed_02`, and `_magic_01` variants. GK shields require the `lake` DLC package to be available.

### Shield Weapons (all weapons with a left-hand shield)

| Weapon Key | Character | Default Shield |
| :--- | :--- | :--- |
| `es_sword_shield` | Kruber | Empire |
| `es_sword_shield_breton` | Kruber (GK) | Bretonnian GK |
| `es_mace_shield` | Kruber | Empire |
| `es_deus_01` | Kruber | Empire round |
| `dr_shield_hammer` | Bardin | Bardin |
| `dr_shield_axe` | Bardin | Bardin |
| `we_1h_spears_shield` | Kerillian | Kerillian |
| `wh_hammer_shield` | Saltzpyre (WP) | Warrior Priest |
| `wh_flail_shield` | Saltzpyre (WP) | Warrior Priest |

### Illusion Browser: Resolving Skin Keys

When browsing illusions in `LootItemUnitPreviewer`, `self._item.data` is the skin's ItemMasterList entry (e.g. `es_bastard_sword_skin_01`), not the weapon. For the new unit-path scale system this doesn't need resolution — the skin's `right_hand_unit` IS the model being rendered, so `_resolve_render_unit_path(item_data, skin, "right_hand_unit")` reads it directly and pattern-matches.

The historic resolution `ItemMasterList[skin_key].matching_item_key → base_weapon_key` is still relevant for any system that genuinely needs the weapon-template identity (e.g. LA offhand selection). Use `rawget(ItemMasterList, key)` per CLAUDE.md.

### Adding a New Shield Swap

1. Add an entry to `_shield_swap_map` in `cosmetics_tweaker.lua`:
   ```lua
   es_sword_shield = {
       setting_id = "es_sword_shield_gk_shield",
       left_hand_unit = "units/weapons/player/wpn_emp_gk_shield_03/wpn_emp_gk_shield_03",
   },
   ```
2. Add a checkbox widget in `cosmetics_tweaker_data.lua` under `weapon_model_group`
3. Add localization entries (`<setting_id>` and `<setting_id>_tooltip`) in `cosmetics_tweaker_localization.lua`
4. Build with VMB, deploy to Workshop folder, full game restart (no hot-reload)

### Adding a New Weapon Scale Override

1. Identify the **unit path substring** that uniquely matches the model family you want to scale. Substrings should be specific enough to NOT collide (e.g. `wpn_emp_gk_sword_` is safe; `wpn_emp_` would also catch Empire shields and is too broad).
2. Append to `_unit_path_scale_overrides` in `cosmetics_tweaker.lua`:
   ```lua
   { pattern = "wpn_xxx_yyy_", factor = _my_factor_fn, hand = "right" }
   ```
3. If the scale should be toggle-gated, define a `function(get) -> {x,y,z}|nil` factor that reads the setting and returns nil when off (mirroring `_breton_sword_thiccc`).
4. Add the corresponding setting widget in `cosmetics_tweaker_data.lua` and localization entries in `cosmetics_tweaker_localization.lua`.
5. Build, deploy, restart. No code changes needed in the hooks — they all read this table.

## Useful Paths

- **Game Logs**: `%APPDATA%\Fatshark\Vermintide 2\console_logs`
- **Workshop Content**: `C:\Program Files (x86)\Steam\steamapps\workshop\content\552500\`
- **Local Mod Folder**: `C:\Program Files (x86)\Steam\steamapps\common\Warhammer Vermintide 2\mods` (used by the legacy `install_local.bat` flow, now in `old-backup/`)
- **SDK**: `C:\Program Files (x86)\Steam\steamapps\common\Vermintide 2 SDK\`
- **AnyWeapon reference mod**: `C:\Users\danjo\source\repos\vermintide-mods\AnyWeapon\` (reference for weapon unlock pattern)
