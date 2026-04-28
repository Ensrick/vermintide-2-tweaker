# Vermintide 2 Tweaker - Development Notes

## Project Overview

A modular set of Vermintide 2 VMF mods split from the original monolithic **"Tweaker"**.

| Mod | Internal ID | VMF Console Prefix | Workshop ID | Status |
| :--- | :--- | :--- | :--- | :--- |
| Chaos Wastes Tweaker | `ct` | `ct <command>` | **3712929235** | Uploaded |
| Weapon Tweaker | `wt` | `wt <command>` | **3712896117** | Uploaded |
| General Tweaker | `gt` | `gt <command>` | **3713619122** | Uploaded |
| Career Tweaker | `crt` | `crt <command>` | TBD | Scaffolded |
| ~~Tweaker (legacy)~~ | `t` | `t <command>` | 3704660429 | Deprecated -- split into above |

## Directory Structure

```
vermintide-2-tweaker/
├── weapon_tweaker/                 <- Weapon Tweaker mod source
│   ├── wt.mod                      <- VMF entry point (internal ID: "wt")
│   ├── settings.ini
│   ├── resource_packages/
│   │   └── weapon_tweaker.package
│   ├── scripts/mods/weapon_tweaker/
│   │   ├── weapon_tweaker.lua
│   │   ├── weapon_tweaker_backend.lua
│   │   ├── weapon_tweaker_data.lua
│   │   └── weapon_tweaker_localization.lua
│   ├── upload/
│   │   ├── item.cfg                <- Workshop upload config (NOT used directly -- see Upload section)
│   │   ├── preview.jpg
│   │   └── content/               <- deploy target for built bundles
│   └── .build/OUT/                 <- compiler output (generated)
├── chaos_wastes_tweaker/           <- Chaos Wastes Tweaker mod source (same structure as above)
├── general_tweaker/                <- General Tweaker mod source (same structure as above)
├── career_tweaker/                 <- Career Tweaker (future)
├── tweaker/                        <- LEGACY -- original monolithic mod (deprecated)
├── upload/                         <- LEGACY -- original tweaker's upload staging
├── _run_build.bat                  <- primary build script
├── build.bat                       <- alternate build script
├── deploy.ps1                      <- legacy deploy (tweaker only)
├── deploy_all.ps1                  <- deploys all mods to Workshop folders + upload/content
├── upload.ps1                      <- legacy upload (tweaker only)
├── upload_all.ps1                  <- uploads all mods to Workshop (NEEDS FIX)
└── install_local.bat               <- local install without Workshop
```

## Dev Workflow: Build -> Deploy -> Hot Reload

The game loads mods from the real Workshop content folder (`552500/<workshop_id>`).
Fake local IDs (e.g. `9000000002` via `install_local.bat`) do NOT work for separately-published Workshop mods.

### Quick iteration loop

```powershell
# 1. Build
Set-Location "C:\Users\danjo\source\repos\vermintide-2-tweaker"
echo "Y" | cmd /c ".\build.bat weapon_tweaker"

# 2. Deploy to Workshop folder + upload/content
powershell -ExecutionPolicy Bypass -File deploy_all.ps1 -Mods "weapon_tweaker"

# 3. Hot reload in-game (Ctrl+Shift+R or toggle mod off/on in F4 menu)
```

### Build

```powershell
powershell -Command "& 'C:\Users\danjo\source\repos\vermintide-2-tweaker\_run_build.bat'"
```

Output goes to `<mod>\.build\OUT\`.

### Deploy

```powershell
powershell -ExecutionPolicy Bypass -File "C:\Users\danjo\source\repos\vermintide-2-tweaker\deploy_all.ps1"
```

Copies bundles to each mod's `upload\content\` directory (with `.mod_bundle` extension) AND directly to the Workshop content folder for hot reload.

### Verifying the right build is running

Each mod logs its version on init:
```
[MOD][wt][INFO] Weapon Tweaker v0.2.1-dev loaded
```
And echoes it to in-game chat. If you don't see the expected version after hot reload, the deploy didn't land -- check the Workshop folder file sizes match the build output.

## Workshop Upload -- THE PROVEN METHOD

> **CRITICAL**: The ugc_tool resolves relative paths from the **config file's parent directory**, but ONLY when the tool's working directory is the SDK's `ugc_uploader` folder. This is the single most important fact about uploading.

### Step-by-step (proven working 2026-04-23):

1. **Stage files** into the SDK's sample_item directory:
   ```powershell
   $sdk = 'C:\Program Files (x86)\Steam\steamapps\common\Vermintide 2 SDK\ugc_uploader\sample_item'
   Remove-Item "$sdk\content\*" -Force
   Copy-Item 'weapon_tweaker\upload\content\*' "$sdk\content\" -Force
   ```

2. **Write the item.cfg** in the SDK's sample_item folder:
   ```ini
   title = "Weapon Tweaker";
   description = "Weapon unlock and runtime experimentation for Vermintide 2. Requires VMF.";
   preview = "preview.jpg";
   content = "content";
   language = "english";
   visibility = "public";
   published_id = 3712896117L;
   apply_for_sanctioned_status = false;
   ```
   - `preview` and `content` are **relative** to the config file location
   - `published_id` uses the `L` suffix (64-bit integer literal)
   - Semicolons required on every line (parsed by `libconfig.dll`)
   - For a **new** item, set `published_id = 0L;` -- the tool will populate it after creation

3. **Run the upload** from the SDK directory:
   ```powershell
   Set-Location 'C:\Program Files (x86)\Steam\steamapps\common\Vermintide 2 SDK\ugc_uploader'
   'Y' | & .\ugc_tool.exe -c sample_item\item.cfg -x
   ```

4. **Verify** on the Workshop page that **File Size is non-zero** (~1.3 MB expected).

### Why this works (and nothing else did)

- The tool loads `libconfig.dll` and `steam_api.dll` from its own directory. It must be run with the SDK folder as its working directory.
- Relative paths in the config are resolved from the config file's parent directory -- but only when the above condition is met.
- Absolute paths from other directories fail silently with misleading `0x9` errors.
- Previously-deleted Workshop item IDs become permanently invalid -- always use `published_id = 0L;` for new items.
- The tool adds `tags = [ ];` automatically after a successful upload -- do NOT add it manually.

### ALWAYS verify after uploading

After every upload, check the Workshop page and confirm the **File Size is non-zero** (~1.3 MB expected). ugc_tool prints "Upload finished" even when content fails to transfer -- the only reliable confirmation is the file size shown on the Workshop item page. A 0-byte item means subscribers get nothing.

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

Tracks which weapons have been tested cross-career and what animation workarounds are in place. Every enabled cross-career weapon should appear here. **Untested** = unlockable but animations not verified in-game.

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
| Elf Spear & Shield | `we_1h_spears_shield` | Kruber (all) | **Untested** | No redirect yet. Crashes hero previewer on non-elf |
| Kruber Spear & Shield | `es_deus_01` | Kerillian (all) | **Untested** | No redirect yet |

### Greatswords

| Weapon | Key | On Career(s) | Status | Notes |
| :--- | :--- | :--- | :--- | :--- |
| Elf Greatsword | `we_2h_sword` | Kruber (all) | **Untested** | Elf uses different anims than es/wh. Redirect expected to work |
| Elf Greatsword | `we_2h_sword` | Saltzpyre (WHC/BH/Zealot) | **Untested** | Same as above |
| Kruber Greatsword | `es_2h_sword` | Saltzpyre (WHC/BH/Zealot) | **Untested** | es/wh share anims — may just work |
| Kruber Greatsword | `es_2h_sword` | Kerillian (all) | **Untested** | Elf stance differs — needs redirect |
| Saltzpyre Greatsword | `wh_2h_sword` | Kruber (all) | **Untested** | es/wh share anims — may just work |
| Saltzpyre Greatsword | `wh_2h_sword` | Kerillian (all) | **Untested** | Elf stance differs — needs redirect |

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
| Bardin Hammer | `dr_1h_hammer` | Kruber (all), Kerillian (all), Saltzpyre (all) | **Untested** | |
| Kruber Mace | `es_1h_mace` | Bardin (all), Kerillian (all), Saltzpyre (all), Sienna (all) | **Untested** | |
| Saltzpyre Hammer | `wh_1h_hammer` | Kruber (all), Bardin (all), Kerillian (all), Sienna (all) | **Untested** | |

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
- Upload staging: `{SDK}\ugc_uploader\sample_item\` (the tool's native staging area)
- `apply_for_sanctioned_status = false` is valid and should be kept
- `tags = [ ];` is added automatically by the tool -- do NOT add it manually before first upload
- Semicolons are REQUIRED on every line in item.cfg (parsed by libconfig)
- The `L` suffix is REQUIRED on `published_id` (64-bit integer literal)
- Build output files have no extension but the game requires `.mod_bundle` -- deploy scripts handle the rename

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
- **Fix:** Use `install_local.bat` (fake ID `9000000001`, bypasses certificate check via `developer_mode`). Once Steam review clears and the item is downloadable, unsubscribe + re-subscribe to get a clean certified download.

### Game crash: bundle hash not found (e.g. `05a4cebb8c3c93bf.mod_bundle not found`)

- **Cause:** Build output files have no extension, but the game requires `.mod_bundle` extension.
- **Fix:** When copying to Workshop folder or upload/content, rename each bundle file from `{hash}` to `{hash}.mod_bundle`. The `.mod` file is copied as-is.

### deploy_all.ps1: variables null inside foreach loop

- **Cause:** PowerShell 5.1 scoping -- variables defined outside a `foreach` loop can be clobbered or invisible inside it.
- **Fix:** Refactor into a function (`Deploy-ToDir`) so variables are passed as parameters rather than relying on outer scope.

## Useful Paths

- **Game Logs**: `%APPDATA%\Fatshark\Vermintide 2\console_logs`
- **Workshop Content**: `C:\Program Files (x86)\Steam\steamapps\workshop\content\552500\`
- **Local Mod Folder**: `C:\Program Files (x86)\Steam\steamapps\common\Warhammer Vermintide 2\mods` (used by `install_local.bat`)
- **SDK**: `C:\Program Files (x86)\Steam\steamapps\common\Vermintide 2 SDK\`
- **AnyWeapon reference mod**: `C:\Users\danjo\source\repos\vermintide-mods\AnyWeapon\` (reference for weapon unlock pattern)
