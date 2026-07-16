# Vermintide 2 Tweaker - Development Notes

## Project Overview

A modular set of Vermintide 2 VMF mods split from the original monolithic **"Tweaker"**.

> **[SUPERSEDED 2026-07-07]** This 7-mod snapshot predates the dev/stable split (the repo now has 15+ mods across dev/stable streams). The canonical, current mod list is the repo-root `CLAUDE.md` "Mod Directory" table.

| Mod | Internal ID | VMF Console Prefix | Workshop ID | Visibility | Build Pipeline |
| :--- | :--- | :--- | :--- | :--- | :--- |
| Chaos Wastes Tweaker | `ct` | `ct <command>` | **3712929235** | public | VMB |
| Weapon Tweaker | `wt` | `/<command>` (e.g. `/dump`, `/animlog`) | **3712896117** | private | VMB |
| General Tweaker | `gt` | `/<command>` (e.g. `/tp`, `/god`) | **3713619122** | private | VMB |
| Career Tweaker | `crt` | `/ct_status` | **3716286199** | private | VMB |
| Cosmetics Tweaker | `cosmetics_tweaker` | `/<command>` (e.g. `/probe_hat`, `/la_force`) | **3715714222** | private | VMB |
| Enemy Tweaker | `enemy_tweaker` | `/et_*` (registered names start with `et_`) | **3716780252** | private | VMB |
| Character Weapon Variants | `character_weapon_variants` | `/cwv*` (registered names start with `cwv` / `cwv_`) | **3716869446** | private | VMB |
| ~~Tweaker (legacy)~~ | `t` | `/<command>` | 3704660429 | n/a | SDK (kept as reference) |

> Chat command syntax: every VT2 mod command (registered via `mod:command("name", ...)`) is invoked in chat as `/<name>` directly. The mod-id (e.g. `wt`, `cos`, `ct`) is the mod's internal identifier — it appears in code and in version-echo prefixes (`[wt v...]`), but NEVER as a chat prefix. Older docs that show `/<mod> <command>` are wrong.

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
└── tools/vmb-launcher/             <- VMBLauncher.exe — canonical build/deploy/upload entry point. Drive it via `tools\ship\ship.ps1` (build+deploy+upload+release+verify). The per-mod `upload_*.ps1` wrappers (removed 2026-07-07, archived to `../_vt2-tweaker-archive/`) and the `deploy_*.ps1` shims (removed 2026-05-21) are gone — use `ship.ps1` / `VMBLauncher.exe deploy <mod>` directly.
```

## Dev Workflow: Build -> Deploy -> Upload

> Owner docs for build/deploy/upload doctrine (consolidated 2026-07-08, issue #432):
> the repo-root `CLAUDE.md` section "Build Commands" (ship doctrine, verbs, post-ship
> verification) and `tools/vmb-launcher/CLAUDE.md` (launcher mechanics, itemV2.cfg
> format + visibility policy, first-upload sequence). Do not restate them here.

- Loop: `VMBLauncher.exe build <mod>` -> `deploy <mod>` (or `all <mod>`), then a FULL
  game restart (hot-reload is NOT safe for weapon_tweaker / cosmetics_tweaker - see
  CLAUDE.md "Important Constraints").
- Release path: `tools\ship\ship.ps1 -Mod <name>` per the CLAUDE.md ship doctrine.
- Upload verification: `workshop_log.txt` must show `Uploaded new content`
  (`ugc_tool` prints success even on failure) - see CLAUDE.md "Post-ship verification".
- itemV2.cfg field format, the visibility removal-risk warning, and the new-item
  `published_id` flow: `tools/vmb-launcher/CLAUDE.md`. Low-level cfg facts also in
  "Key Technical Facts / Workshop / Build" below.
- Always bump `MOD_VERSION` before every build (version echoes on init, e.g.
  `[MOD][wt][INFO] Weapon Tweaker v0.2.1-dev loaded`) so the running build is
  visually verifiable.

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

DLC weapons sometimes use `<prefix>_deus_01` (Chaos Wastes / "grass" DLC) instead of descriptive names. Always use `/dump` in-game or check the source code `item_master_list_*.lua` files to confirm weapon keys -- don't guess from the weapon's display name.

## Animation System Architecture

### Two parallel systems — pick by use case

The repo has two independent approaches for getting 3P animations to play correctly. They solve different problems and don't overlap.

| System | Lives in | Trigger | Use when |
| :--- | :--- | :--- | :--- |
| **A — Runtime hook** | `weapon_tweaker.lua` | `Unit.animation_event` is intercepted for every event on every unit | A vanilla weapon item is unlocked for a new career (`ItemMasterList[k].can_wield`) and we need to translate event names on the fly. Also the only path that reaches **husks** of remote players in coop. |
| **B — Template clone** | `character_weapon_variants.lua` | `table.clone` of `Weapons.<base_template>` at mod load; `anim_event_3p` rewritten per sub-action; clone stored as `Weapons.<variant_template>` | A new variant item we own end-to-end (e.g. `cwv_es_dual_swords`) where we control which template the item points at. |

**Decision rule:**
- New CWV variant → **System B**. Mechanics in `character_weapon_variants/DEVELOPMENT.md` ("Animation: System B").
- Vanilla item unlocked for a new career → **System A**.
- Husks of remote players → **System A** regardless (we can't clone a template they own).
- Deeper template control needed (timing, chain, sub-action restructure) → only System B can reach those — they're sub-action fields, not animation events.

The rest of this section documents System A. System B is documented at `character_weapon_variants/DEVELOPMENT.md`.

### The Two Units: Understanding 1P vs 3P

VT2 uses two separate units for the local player:

| Unit | How to identify | What it renders | What it receives |
| :--- | :--- | :--- | :--- |
| `player.player_unit` | `_is_local_player_unit(unit) == true` | **3P body** (visible to other players) | `anim_event_3p` from weapon action data |
| Non-player unit | `_is_local_player_unit(unit) == false` | **1P hands** (visible to you) | `anim_event` from weapon action data |

**This is counterintuitive.** Despite being called `player_unit`, it is the third-person body. The first-person hands/weapon view is a separate unit that is NOT `player_unit`.

Evidence: the billhook's `default_stab` action defines `anim_event = attack_swing_charge_stab` and `anim_event_3p = attack_swing_stab_charge`. In practice, `player_unit` receives `attack_swing_stab_charge` (the 3P value) and the non-player unit receives `attack_swing_charge_stab` (the 1P value). Confirmed via `/dump_actions billhook` + `/animlog`.

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

For a procedural playbook covering full **cross-character ports** (mesh + wield-stance + per-action remap + in-mission/preview unit swap), see `weapon_tweaker/CROSS_CHARACTER_PORT_RECIPE.md`. The two shipped examples (`_patch_brace_template_for_kruber` and `_patch_longbow_empire_template_for_saltzpyre`) are distilled there with line citations, failure modes, and a verification matrix.

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

- `/animlog` -- toggles animation event logging; tags each event as "1P" (player_unit / 3P body) or "3P" (1P hands); shows `[MISSING]`, `REDIR ->`, and `3P REMAP ->` markers
- `/dump_actions [pattern]` -- dumps all `Weapons` template actions matching pattern (or ALL templates if no pattern), showing `anim_event` (1P hands) and `anim_event_3p` (3P body) fields; output goes to both in-game chat and mod log file; sorted alphabetically; essential for building remap tables
- `/force3p <event>` -- forces an animation event on the last-seen non-player unit (for testing if events exist/play)
- `/dump` -- dumps equipped item data to log

### Building a New 3P Remap Table

1. Run `/dump_actions <source_weapon>` and `/dump_actions <target_weapon>` in-game
2. For each source weapon action, map its `anim_event` value to the target weapon's `anim_event_3p` value (or `anim_event` if no 3P override exists for that action)
3. Create a Lua table with these mappings
4. Add it to `_3p_remap_triggers` keyed by the source weapon's `to_` event name
5. Add the source weapon's `to_` event to `_career_anim_redirect` with the target weapon's `to_` event as the override
6. Verify with `/animlog` — every attack should show a `3P REMAP ->` line on `player_unit`

## Cross-Career Weapon Animation Status

**Moved to [docs/WEAPON_CATALOG.md](docs/WEAPON_CATALOG.md)** — comprehensive per-weapon reference with attack chains, animation events, cross-career status tables, and data collection gaps.

The tables below are kept for historical reference but **docs/WEAPON_CATALOG.md is the authoritative source**.

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
3. Check 3P body animations with another player or `/animlog` — look for `[MISSING]` on `player_unit`
4. If 3P attacks show no animation, build a remap table using `/dump_actions`
5. Test crouch, jump, weapon swap, push-attack — confirm remap doesn't break
6. Note: `we_1h_spears_shield` crashes the hero previewer on non-elf careers — this is a known issue but gameplay may still work

## VMF Hook Timing

> Owner doc for VMF hooking rules (hook_safe no-chain, multi-return collapse,
> nil-hole unpack, safe_hook/traced_hook wrappers): `docs/VMF_RECIPES.md` sections 1-2b.
> This section only covers WHEN to install a hook; don't restate the rules here.

- **Globals** (`ItemGridUI`, etc.) -- hook at the top level of `M.install()`, during mod init
- **Backend instances** (`items_interface:set_loadout_item`, etc.) -- defer inside `mod.update` behind `Managers.backend` check
- **`BackendUtils.can_wield_item`** -- don't hook it at all (see above)
- **String-form hooks** (`mod:hook("ClassName", ...)`) -- use when the class isn't loaded yet at mod init; VMF resolves lazily

## Key Technical Facts

### Lua / VMF

- Lua 5.1: use `unpack()` not `table.unpack()`
- Commands: `mod:command("win", "description", function() ... end)` -- called as `/win` in chat (the registered name is the slash-command name; no mod-id prefix)
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
- Upload staging (legacy `tweaker/` only): `{SDK}\ugc_uploader\sample_item\` — the SDK's native staging area. Active VMB-built mods bypass this entirely; `ugc_tool` reads `itemV2.cfg` directly from the per-mod source dir, and `content = "bundleV2"` resolves relative to the cfg's parent.
- `apply_for_sanctioned_status = false` is valid and should be kept
- `tags = [ ];` is added automatically by the tool -- do NOT add it manually before first upload
- Semicolons are REQUIRED on every line in item.cfg (parsed by libconfig)
- The `L` suffix is REQUIRED on `published_id` (64-bit integer literal)
- VMB build output (`bundleV2/`) already includes the `.mod_bundle` extension; only the legacy SDK pipeline produced extensionless files that the now-archived `deploy_all.ps1` had to rename (the launcher handles VMB directly)

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
- **Fix:** Flip to `is_local` and use target weapon's `anim_event_3p` values. Use `/dump_actions` to find correct values.

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

### deploy_all.ps1: variables null inside foreach loop (historical)

> Historical note: this entry refers to the legacy `deploy_all.ps1` shim, archived 2026-05-21 to `_archive/legacy_deploy_scripts/`. The active deploy path is `VMBLauncher.exe deploy <mod>`, which is a .NET binary not subject to PowerShell-5.1 scoping quirks. Kept for context in case anyone revives the script.

- **Cause:** PowerShell 5.1 scoping -- variables defined outside a `foreach` loop can be clobbered or invisible inside it.
- **Fix:** Refactor into a function (`Deploy-ToDir`) so variables are passed as parameters rather than relying on outer scope.

## Stingray / Lua engine quirks

> Owner doc for engine-level quirks (issue #432 consolidation): this section.
> `CLAUDE.md` "Lua Environment" carries the high-frequency SUMMARY and cites here;
> `docs/MECHANICS.md` points at these facts via provenance tags. Don't grow a
> third full copy anywhere.

Cross-cutting engine and Lua 5.1 / LuaJIT gotchas that bite every mod in this
repo at least once. Most of these are silent failure modes — code "looks
right", hook compiles, ships broken. The burn history justifies the depth.

For the VMF-side gotchas (hook_safe doesn't chain, multi-return collapse,
dropdown options mutation, etc.), see `docs/VMF_RECIPES.md`. This section is for
engine-level quirks (Stingray Lua API behavior, vanilla data-table timing,
husk/self-owned class pairs, etc.).

### Lua 5.1 — 200-local-variable limit per function (including the main chunk)

Lua 5.1 / LuaJIT have a hard **200-local-variable limit per function**,
**including the top-level "main chunk"**. Every `local function X` and
`local var = ...` at the top level of a `.lua` file counts. Large mod files
accumulate past this.

Symptom (Stingray compile error):
```
character_weapon_variants.lua:8654: main function has more than 200 local variables
Processed file has been written to .../*.lua.processed
[Compiler] Refusing to bundle due to compile errors.
```

The line number cited isn't the problem line — it's just where the 201st
local was declared. The fix is anywhere upstream.

**Fix:** wrap groups of helpers in `do ... end` scopes — locals release at
the closing `end`, freeing main-chunk slots:

```lua
-- BEFORE -- each helper consumes a top-level slot
local _MY_CONST = 1.5
local function _helper_one() ... end
local function _helper_two() ... end
local function _setup() ... end
_setup()

-- AFTER -- locals release at `end`, free up main-chunk slots
do
    local _MY_CONST = 1.5
    local function _helper_one() ... end
    local function _helper_two() ... end
    local function _setup() ... end
    _setup()
end
```

The scope still runs, the helpers are still callable inside it, and the
locals don't pollute the main chunk's slot count.

**When to do this:** any time you're adding a block of helpers + constants
that ONLY get used to construct vanilla data tables / templates at mod-init
time. Wrap it. Easy refactor, zero behavior change.

**Burned:** `character_weapon_variants` v0.1.304 (~line 8654) — Old Musket
template setup blocks (v0.1.300 / v0.1.301 / v0.1.304) each added 3-6
locals. The straws breaking the camel's back.

### `Unit.node` errors bypass `pcall` — use `Unit.has_node`

Stingray's `Unit.node(unit, name)` raises an **engine-level fatal** when the
name doesn't resolve, NOT a regular Lua error. The error string in the
crash log is just the node name itself (e.g. `[Script Error]: j_lock`).
Critically, this error bypasses Lua's protected mode — `pcall(Unit.node, ...)`
does **NOT** catch it.

**Why:** Stingray engine errors raised from C-side APIs can bypass Lua's
protected mode entirely. The user-facing crash log shows pcall on the stack,
but the script halts anyway.

**Fix:** use `Unit.has_node(unit, name)` for safe existence checks. It
returns a boolean — no protection needed. Verified vanilla pattern:

```lua
-- ai_bot_group_system.lua:190
local node = Unit.has_node(unit, node_name) and Unit.node(unit, node_name) or 0
```

Same pattern applies to any other Stingray API that "errors on not-found" —
prefer the `has_*` companion when it exists. **Don't assume pcall will save
you.** Burned in `character_weapon_variants` v0.1.290 → v0.1.291; v0.1.291
switched to `Unit.has_node` and works.

### `Unit.actor(unit, idx)` is 1-indexed, not 0-indexed

`Unit.actor(unit, index)` is **1-indexed**. Iterating with
`for i = 0, num_actors - 1` returns nil at index 0 and skips the final
actor. The bug is silent — `if actor then` is false for nil so the operation
no-ops cleanly, with no error.

Canonical vanilla iteration (`ai_inventory_extension.lua:432-441`,
`flow_callbacks_foundation.lua:1011`):

```lua
local num_actors = Unit.num_actors(unit)
for i = 1, num_actors do
    local actor = Unit.actor(unit, i)
    if actor then
        Actor.set_collision_enabled(actor, false)
        -- ...
    end
end
```

Related actor APIs (all 1-indexed when iterating):
- `Actor.set_collision_enabled(actor, enabled)` — physics character-
  controller block. Disable to let player walk through.
- `Actor.set_scene_query_enabled(actor, enabled)` — raycast scene query.
  Disabling BREAKS interaction prompts (raycast misses), so leave alone
  for objects that need to stay interactable.
- `Actor.set_kinematic(actor, kinematic)` — dynamic ↔ kinematic.

**Burned:** `chaos_wastes_tweaker` v0.6.16 → v0.6.19. Collision-disable
hook for CW altars/chests on injected adventure levels iterated 0-based,
no actors modified, players couldn't walk through. Fixed by switching to
1-based iteration.

### `Quaternion` / `Vector3` are stack temporaries — use `*Box` for storage

Stingray's raw `Quaternion` and `Vector3` types are **stack-allocated
temporaries**: the returned value is valid only within the current frame.
Storing the raw value in a Lua global, table field, or upvalue makes it
stale — by the next frame the memory has been reused by other
Quaternion/Vector3 operations, and your reference points at garbage. Often
the corruption resembles identity or some unrelated recent operation, so
the bug looks like the API returned the wrong value.

**Fix:** `QuaternionBox` / `Vector3Box` / `Matrix4x4Box` wrap the value for
storage. `:unbox()` at apply time returns a fresh single-frame-valid raw
value.

```lua
-- Vanilla patterns to mirror:
-- bt_attack_action.lua:99
blackboard.attack_rotation = QuaternionBox(rotation)

-- ai_bot_group_system.lua:460
blackboard.move_target_rotation = QuaternionBox(rotation)

-- bt_charge_attack_action.lua:70
blackboard.stored_rotation = QuaternionBox(Quaternion.identity())

-- ai_bot_group_system.lua:38
data.hold_position = Vector3Box(hold_position)
```

At use site:
```lua
local rot = boxed_rotation:unbox()  -- fresh raw Quaternion, single-frame valid
Unit.set_local_rotation(unit, 0, rot)
```

**Safe pattern without boxing:** if you create a Vector3/Quaternion and
immediately pass it to an API in the same statement, no box needed — both
temp and consumer are within the same frame:

```lua
-- Safe — created and consumed inline
Unit.set_local_position(unit, 0, Vector3(x, y, z))

-- Safe — pos stored as {x,y,z} table, Vector3 created at apply time
local saved_pos = { 1.0, 2.0, 3.0 }
-- ...later frame...
Unit.set_local_position(unit, 0, Vector3(saved_pos[1], saved_pos[2], saved_pos[3]))
```

**Rule of thumb:** if a Vector3/Quaternion/Matrix4x4 needs to survive past
the current function's return (stored in a global, table, upvalue, or
closure), box it. If used inline within one statement, leave it raw.

**Burned:** `character_weapon_variants` v0.1.297 → v0.1.298. Stored
`Quaternion.axis_angle(Vector3(1,1,-1), -π/2)` directly in a global.
Worked on the first frame after equip, then the gun appeared rotated to a
perpendicular orientation as the temp slot was reused. Fix:
`QuaternionBox(Quaternion.axis_angle(...))` for storage.

### `pl.player_unit` is a FIELD, not a method

`Managers.player:local_player().player_unit` is a **field** on the Player
object that holds the unit userdata directly. Do NOT call it as a method.

```lua
-- WRONG -- errors at runtime:
--   "attempt to call method 'player_unit' (a userdata value)"
local pu = pl:player_unit()

-- RIGHT:
local pu = pl.player_unit
```

`local_player()` IS a method (colon syntax). `player_unit` is NOT — it's a
plain field on the Player object. The pattern is verified across cosmetics
code (`cos probe_hat` works; `cos repaint_glow` shipped the call-as-method
bug in v0.8.7 / v0.8.8 and crashed at line 2098 immediately on first
invocation).

When accessing the local player's spawned unit anywhere in any VT2 mod,
write `Managers.player:local_player().player_unit` (chained field access).
Same likely applies to other Player object fields — when in doubt, look up
an existing working callsite before guessing.

### `REAL_PLAYER_LOCAL_ID` is a file-scope local, not a global

Every VT2 file that needs `REAL_PLAYER_LOCAL_ID` declares it as a
**file-scope local**:

```lua
local REAL_PLAYER_LOCAL_ID = 1
```

Seen in `deus_run_controller.lua`, `deus_chest_extension.lua:10`,
`deus_chest_preload_extension.lua:5`, `deus_spawning.lua:7`,
`adventure_spawning.lua:6`, `versus_mechanism.lua:32`, etc. It is **NOT**
a global — referencing the bare token from a mod resolves to
`_G.REAL_PLAYER_LOCAL_ID = nil`.

**Why this is silent:** the affected SharedState getters build their key
via `_shared_state:get_key("soft_currency", peer_id, local_player_id)`.
With `local_player_id = nil`, the key segment becomes a nil placeholder,
the lookup misses, and `get_server` returns 0 (or some default — does NOT
return nil for numeric keys). The caller compares against the cost, the
affordability guard rejects, and the purchase silently no-ops with no
error.

**Apply:** any mod that copy-pastes vanilla CW code referencing
`REAL_PLAYER_LOCAL_ID` MUST add `local REAL_PLAYER_LOCAL_ID = 1` near the
top of its own file. Don't assume it's in scope because vanilla code "uses
it everywhere."

Other vanilla file-locals with the same gotcha: `CHANNEL_TO_PEER_ID`,
`PEER_ID_TO_CHANNEL` (these are also locals in some files, globals in
others — verify per file).

**Burned:** ct v0.7.65 → v0.7.87 Miracle of Ulric / Miracle of Isha
purchase hook silently rejected every buy attempt as
`coins=0 < cost=100` even with hundreds of coins in SharedState (2026-05-22).
Host+client log diff showed SharedState's real balance was 894 while the
diagnostic showed 0 at the same buyer peer_id. Fixed v0.7.88 by adding
the local declaration.

### Upvalue capture at file load bypasses later `mod:hook` on the table entry

When a VT2 file does `local f = SomeTable.method` at the top of the file,
the local UPVALUE holds a direct reference to the original function
captured at file-load time. Any later `mod:hook("SomeTable", "method", ...)`
only replaces the table entry — every call site that goes through the
captured local **bypasses the wrapper**.

**Why:** VT2 settings/terror-event files load before mods. The boot-time
read freezes the function pointer into the local. Mods can mutate
`SomeTable.method` but not the existing local binding.

**Apply:** before authoring a `mod:hook("Class", "method", ...)` hook, grep
the codebase for `local <name> = Class.method` and `<field> = Class.method`
patterns. Every match is a call site that will bypass the hook. If any are
found, fall back to mutating the data the wrapped function READS at call
time (typically a global lookup the function dereferences inside its body)
— not the function itself.

**Confirmed cases:**
- `TerrorEventUtils.add_enhancements_for_difficulty` is captured as
  `local boss_pre_spawn_func` in every CW arena terror event
  (`terror_events_dlc_morris_arena_ruin.lua:4`, `arena_ice.lua:4`,
  `arena_citadel.lua:4`, `arena_cave.lua:5`, plus 5 entries in
  `arena_belakor.lua` 1847/1899/2751/2824/3517), and as
  `cursed_chest_enemy_pre_spawn_func` in `deus_generic_terror_events.lua:15`.
- The v0.7.76 grudge marks hook never fired. Re-fixed in v0.7.89 by
  mutating `_G.BossGrudgeMarks` directly (vanilla
  `add_enhancements_for_difficulty` reads it via global lookup at call
  time, so the mutation is picked up).

**Same shape as:** the mutator template `server_*_function` wrap below.
Whenever the hook target is reachable via a table field, grep for boot-
time captures of that field before assuming the hook will fire.

### Mutator template `server_*_function` is a dead field — hook the wrapped form

When hooking a mutator template's lifecycle functions in VT2, hook
**`template.server.start_function`** (or `template.client.start_function`,
etc.), NOT `template.server_start_function`.

**Why:** `mutator_templates.lua:236-269` runs at engine boot, BEFORE any
mod loads. It iterates every mutator template and wraps each
`server_*_function` field into a closure stored at `template.server.*_function`:

```lua
if template.server_start_function then
    local function start_function(context, data)
        default_start_function_server(context, data)
        template.server_start_function(context, data)  -- upvalue captured HERE
    end
    template.server.start_function = start_function
end
```

The wrapper closure captures `template.server_start_function` as an
**upvalue at wrap time**. After wrapping, the field name
`template.server_start_function` still exists but is **never read by the
engine** — `mutator_handler.lua:680-682` dispatches via
`server_template.start_function`. Replacing the dead field via
`mod:hook(template, "server_start_function", ...)` compiles cleanly, the
existential guards pass, the hook **silently no-ops every time**.

**Apply:**
- Hook `template.server.start_function` / `client.start_function` / etc.
  for lifecycle events.
- Per-frame mutator functions: hook `template.server.update_function`,
  `template.server.player_disabled_function`, etc. — same wrap pattern,
  all live under `template.server.*` / `template.client.*`.
- Confirmed-existing wrapped fields: `initialize_function`,
  `start_function`, `stop_function`, `update_function`,
  `player_disabled_function`, `player_hit_function`. Inspect
  `mutator_templates.lua:236-300+` for the full list.

**Burned:** ct v0.7.66 Isha-alternative mutator suppression. Hook
compiled, no behavior change shipped, would have let vanilla revive fire
alongside the new buff. Caught in pre-deploy QA.

### Self-owned vs husk extension classes — always check `unit_extension_templates.lua`

For any feature that needs to behave correctly when the **local viewer
watches a remote player**, audit whether the hooked class has a `Husk*`
sibling per `scripts/network/unit_extension_templates.lua`. The two
classes share **no method inheritance** — VT2's `class()` copies methods
at definition time, but `SimpleHuskInventoryExtension` is its own root
class, not a subclass of `SimpleInventoryExtension`.

**Why:** `unit_extension_templates.lua` lists `self_owned_extensions` and
`husk_extensions` as parallel arrays. The host applies `self_owned_extensions`
to its own player_unit + server-owned units, and `husk_extensions` to
remote players' units. So:

- Local player + bots → `SimpleInventoryExtension` (+ other self-owned)
- Remote players viewed from any other machine →
  `SimpleHuskInventoryExtension` (+ other husk classes)

A `mod:hook("SimpleInventoryExtension", "wield", ...)` will NEVER fire for
a remote player's wield action as observed from the local machine.

**Common pairs to audit:**

| Self-owned | Husk |
|---|---|
| `SimpleInventoryExtension` | `SimpleHuskInventoryExtension` |
| `GenericUnitInteractorExtension` | `GenericHuskInteractorExtension` |
| `PlayerUnitLocomotionExtension` | `PlayerHuskLocomotionExtension` |
| `PlayerUnitAttachmentExtension` | `PlayerHuskAttachmentExtension` |

**Apply:**
1. Whenever you hook a class method on a player-unit-related extension,
   check `unit_extension_templates.lua` for the husk twin.
2. If the husk twin exists, register the same hook body (or a shared
   helper) on the husk class too.
3. Alternatively, find a global function or unit-level extension both
   classes route through (e.g. `GearUtils.spawn_inventory_unit` is called
   by both `_wield_slot` paths — a global-function hook covers both).
4. For per-unit career/state lookups: prefer
   `ScriptUnit.has_extension(unit, "career_system")._career_name` over
   `inventory_system._career_name` — `CareerExtension` is present on
   BOTH self-owned and husk units (per templates.lua) and its init is
   race-free.

**Burned (weapon_tweaker):**
- v0.12.35 — per-unit animation remap state: wield hook missed husks →
  remote players' cross-career weapons animated with no remap on the
  host's screen. Fixed v0.12.37 by adding a parallel
  `mod:hook("SimpleHuskInventoryExtension", "wield", ...)`.
- v0.12.37 brace → repeater 3P swap diagnostics: confirmed
  `GearUtils.spawn_inventory_unit` IS called from both classes'
  `_wield_slot`, so a global-function hook covers both. The career
  detection bug was separate: husk inventory `_career_name` is race-prone
  because it depends on `extension_init_data.player:career_name()` being
  non-nil at husk init.

### Force-loading — only paths in `inventory_package_list.lua` are loadable

When force-loading vanilla assets via
`Managers.package:load(path, ref, nil, true, true)`, the path **MUST
appear** in `scripts/network_lookup/inventory_package_list.lua`. Trying to
force-load an "embedded" resource (one bundled inside a parent package,
not registered as standalone) produces:

```
Engine Error: Resource '#ID[<hash>]' was not found!
```

— fired **asynchronously during `_pop_queue`**, AFTER the surrounding
pcall has returned. **The pcall never catches it.**

**Why:** vanilla bundles ship resources in two flavors:
- (a) standalone per-asset packages registered in
  `inventory_package_list.lua`, individually loadable;
- (b) resources EMBEDDED inside larger packages, only available when the
  parent package loads.

State machines, sound banks, unit / material assets typically appear in
the list. Display units (`units/weapons/weapon_display/display_*`)
typically do NOT — they're bundled with their parent weapon template's
package.

**Apply:**
1. Before adding any `Managers.package:load(path, ...)`, grep
   `scripts/network_lookup/inventory_package_list.lua` for the exact path.
   If not present, the load WILL crash — find a different solution (force-
   load the parent package, or rely on vanilla's load timing).
2. When debugging an "Engine Error: Resource not found" crash with a hash,
   reverse the hash via the bundle unpacker
   (`reference_vt2_hash_reverse_lookup` in memory) to identify which path
   failed.

**Burned twice:**
- v0.1.224: dropped `display_2h_spears_wood_elf` from a force-load list
  — same crash.
- v0.1.289: dropped `display_shield_spear` from a force-load list — same
  crash.

Both times the symptom was: synchronous pcall logs success, engine fatals
later when `_pop_queue` processes the deferred load.

### Custom `ExplosionTemplates` need `.name` AND registration

Any mod that defines its own explosion template (a table consumed by
`DamageUtils.create_explosion`) and passes it through the vanilla AOE
damage pipeline must do BOTH or it crashes on the next frame after the
first AOE hit lands:

1. **Register the template into `_G.ExplosionTemplates`** under a unique
   name key.
2. **Set `.name` on the template table** to that same key.

**Why:** `scripts/settings/explosion_templates.lua` ends with:

```lua
for name, templates in pairs(ExplosionTemplates) do
    templates.name = name
end
```

That loop populates `.name` on every vanilla template — but it runs once
at engine boot, **before** any mod loads. Mod-defined templates miss it.

**The crash pipeline:** `DamageUtils.create_explosion` (line 1474 of
`damage_utils.lua`) calls
`area_damage_system:add_aoe_damage_target(..., explosion_template.name, ...)`
as the 17th positional arg. That `.name` is written onto a ring-buffer
entry as `aoe_damage_data.explosion_template_name`. Drained next frame
(or immediately on overflow) by `AreaDamageSystem._damage_unit`:

```lua
local explosion_template_name = aoe_damage_data.explosion_template_name  -- nil!
local explosion_template = ExplosionUtils.get_template(explosion_template_name)  -- nil
local explosion_data = explosion_template.explosion  -- CRASH: index nil
```

**Crash signature:**
```
scripts/entity_system/systems/area_damage/area_damage_system.lua:347:
    attempt to index local 'explosion_template' (a nil value)
```
(Line varies slightly by version; current release is 347, not 344.)

**Correct shape:**
```lua
local _MY_AOE_NAME = "<modid>_<descriptive_name>"
local _MY_AOE_TEMPLATE = {
    name = _MY_AOE_NAME,  -- required
    explosion = {
        damage_profile = "...",
        radius = ...,
        ...
    },
}
if rawget(_G, "ExplosionTemplates") then
    ExplosionTemplates[_MY_AOE_NAME] = _MY_AOE_TEMPLATE  -- required
end
```

**Burned:** weapon_tweaker v0.12.49-dev (Moonfire AOE revert). Host-side
fatal whenever the queue-overflow path or next-frame buffer drain ran
with a Moonfire arrow impact in flight. Fixed v0.12.51-dev — see
`weapon_tweaker.lua` `_MOONFIRE_AOE_TEMPLATE` block (~line 2257).

### Localize description strings run through `string.format` — escape `%` as `%%`

A `mod:hook(_G, "Localize", ...)` that returns a hand-written description
string for a boon / talent / property tooltip MUST escape literal `%` as
`%%`. The Localize result is downstream-formatted by
`UIUtils.format_localized_description` (`scripts/helpers/ui_utils.lua:69`):

```lua
local str = string.format(fmt_localized, unpack(VALUE_LIST, 1, num_defs))
```

— always runs through `string.format` with the template's
`description_values` as args. A literal `25%` becomes invalid format
syntax (`% H...`), and VMF substitutes the tooltip with
`[Invalid String Format]`.

**Apply:**
- Any time a mod hooks `_G.Localize` to override a boon / talent /
  ability / weapon-property / weave-trait description with a fixed
  literal, escape `%` → `%%`.
- If the upstream template has N `description_values` and you're
  shortening the description, the extra format args from `unpack` are
  harmless — Lua's `string.format` ignores trailing args beyond what the
  format string consumes. So 0 `%s` placeholders + N args still works
  after escaping `%`.
- If you're substituting dynamic text instead of a fixed literal, keep
  `%s` placeholders matching `description_values` count and only escape
  literal percents.
- HUD / interaction string overrides that hook `Localize` for keys NOT
  consumed by the description-values pipeline (e.g. action prompt
  strings) do NOT need this escaping — only descriptions formatted by
  `UIUtils.format_localized_description` /
  `get_talent_description` / `get_ability_description` /
  `get_property_description` are affected.

**Burned:** ct v0.5.2-dev modified Khaine's Fury (`deus_reckless_swings`)
override. A misleading code comment claimed Localize returns strings
"as-is" — that's true for the *Localize* call itself, but the *callers*
(UIUtils helpers, talent/ability/property/boon tooltips) post-format the
result. Comment near `RECKLESS_SWINGS_DESC_OVERRIDE` now points at
`ui_utils.lua:69` as the real format pipe.

### Gated registration diverges across peers (network indices, level keys)

Any mod-load registration into `_G.BuffTemplates`,
`DeusPowerUpBuffTemplates`, `DeusPowerUpTemplates`, any `NetworkLookup.*`
subtable, or `LevelSettings` post-boot **gated on a per-user setting**
(e.g. `effective_setting("enable_boon_x")`, `mod:get("activate_dormant_y")`,
`mod:get("inject_adventure_maps")`, per-mission `enable_adventure_<key>`)
will diverge across peers — wrong network indices, or missing-key crashes
on host-driven RPC / SharedState.

**Failure modes:**
- **NetworkLookup divergence (buff/power-up indices):** append-order
  differs → same name maps to different indices → host's
  `rpc_add_buff(unit, N)` resolves to a different buff (or missing →
  fatal `Table buff_templates does not contain key: N` at
  `network_lookup.lua:2514`) on the client.
- **LevelSettings divergence (post-boot level keys):** host advertises a
  level_key via SharedState; client's `LevelSettings[key]` returns nil →
  fatal `attempt to index local 'level_settings' (a nil value)` at
  `state_loading.lua:449`. Host-migration handoff is the worst-case
  trigger because the lobby-join hash check already passed.

**Why:** Stingray's NetworkLookup tables are frozen at engine boot; ct
and other mods append entries post-boot via
`register_buff_in_network_lookup` etc. Each peer's append order depends
on which entries they decide to register. Different decisions →
different orders → different indices for the same name. Runtime settings
sync (chunked or otherwise, see VMF Recipes §4) **cannot fix this** —
the network table is already frozen with wrong contents by the time sync
arrives.

`pairs()` over a string-keyed table is in practice deterministic when
called with the same key set on the same Lua VM build, but the set
differs once gates skip entries. Sorted iteration removes the variable.

**Apply:** Any registration into a network-replicated table at mod-load
**MUST be unconditional**. Iterate over the spec set in a **sorted
order** (string-sort on a stable key), call register-in-NetworkLookup +
write-to-BuffTemplates for every entry regardless of toggle. Gate the
OFFERING / POOL side separately (`DeusPowerUpRarityPool` / `DeusPowerUps` /
`DeusPowerUpsArray` / `DeusPowerUpsArrayByRarity` / `DeusPowerUpsLookup`)
by the toggle — those tables aren't NetworkLookup-replicated and per-peer
differences are harmless.

**Canonical fixes:**
- Dormant boons: `chaos_wastes_tweaker.lua:3321-3393`
  (`pre_register_dormant_lookups`), ct v0.7.60.
- Trait boons: `chaos_wastes_tweaker.lua:3709-3768`
  (`pre_register_trait_boon_lookups`), ct v0.7.61.
- Adventure-injected levels: `_adventure_pool.lua`
  (`register_mission_resolvables` + `pre_register_adventure_lookups`),
  ct v0.7.62. Same shape, but for `LevelSettings[<adv>_<theme>_path1]`
  + `NetworkLookup.level_keys` + `TerrorEventBlueprints` +
  `WeightedRandomTerrorEvents`. Pool side
  (`DEUS_MAP_POPULATE_SETTINGS.LEVEL_AVAILABILITY` +
  `IS_INJECTED_ADVENTURE_LEVEL`) stays toggle-gated.
- LA shield `kind="unit"` inventory_packages:
  `cosmetics_tweaker/_la_bridge.lua`
  (`pre_register_la_inventory_packages`), cosmetics_tweaker v0.8.66.
  Crash signature
  `NetworkLookup.lua:2514: Table inventory_packages does not contain key: <N>`
  during `rpc_shared_state_set_string` decode of `inventory_list` from a
  client who equipped an LA shield.

**Pre-register pattern (template):**
```lua
local function pre_register_xxx_lookups()
    local templates       = rawget(_G, "DeusPowerUpTemplates")
    local buff_templates  = rawget(_G, "BuffTemplates")
    local dpubt           = rawget(_G, "DeusPowerUpBuffTemplates")
    if not (templates and buff_templates and dpubt) then return end
    local sorted = {}
    for _, spec in ipairs(SPEC_LIST) do sorted[#sorted + 1] = spec end
    table.sort(sorted, function(a, b) return a.name < b.name end)
    for _, spec in ipairs(sorted) do
        -- 1) Build DeusPowerUpTemplate entry
        -- 2) Write buff template to DeusPowerUpBuffTemplates + _G.BuffTemplates
        -- 3) register_buff_in_network_lookup(buff_name)
        -- 4) register_power_up_in_network_lookup(spec.name)
    end
end
```

**Audit checklist when adding any new ct/VMF feature:** if it writes to
BuffTemplates / DeusPowerUpBuffTemplates / DeusPowerUpTemplates /
NetworkLookup, search the surrounding code for `mod:get` or
`effective_setting` in the same control-flow path. If found, split the
registration from the pool/offering side.

For the cross-mod variant of this (multiple tweaker mods registering the
same set of templates each shipping a byte-identical canonical list),
see `docs/CROSS_MOD_ARCHITECTURE.md` § Big Rebalance.

### LootItemUnitPreviewer.spawn_units — use `mod:hook`, NOT `hook_safe`

In `LootItemUnitPreviewer` (the cosmetic picker / illusion-browser
preview pane), the spawned weapon units are NOT assigned to
`self._spawned_units` from inside `spawn_units` — vanilla `_spawn_items`
(`loot_item_unit_previewer.lua:522`/`532`) does:

```lua
local units = self:spawn_units(units_to_spawn)   -- line 522
...
self._spawned_units = units                       -- line 532, AFTER
```

So a `mod:hook_safe("LootItemUnitPreviewer", "spawn_units", ...)` post-
callback fires AFTER `spawn_units` returns but **BEFORE** the caller
writes `self._spawned_units`. Reading `self._spawned_units` from inside
hook_safe gets nil. Any logic gated on `if not spawned then return end`
silently no-ops.

**Fix:** use `mod:hook` (full wrapper) and read units from the wrapped
call's return value:

```lua
mod:hook("LootItemUnitPreviewer", "spawn_units", function(func, self, spawn_data)
    local units = func(self, spawn_data)
    -- ... transform `units` here ...
    return units
end)
```

**Hit twice:**
- cosmetics_tweaker (bret-thinning scale): originally hook_safe, never
  applied scale to the picker preview, fixed by switching to `mod:hook`.
- character_weapon_variants v0.1.127: same bug — cwv scale rules never
  applied in the picker because the hook was `hook_safe` and
  `self._spawned_units` was nil.

**Apply:** Any new hook on `LootItemUnitPreviewer.spawn_units` MUST use
`mod:hook` (not `hook_safe`) and read units from the wrapped return.
Don't refactor back to `hook_safe` for "consistency" with hooks on other
methods — the assignment timing on this specific method makes it the
wrong choice.

### HeroPreviewer / MenuWorldPreviewer slot keying — string vs numeric

In `HeroPreviewer` and its subclass `MenuWorldPreviewer` (used by the
inventory character preview):

- `self._item_info_by_slot[<string slot_type>]` — keyed by `"melee"` or
  `"ranged"`. Vanilla `equip_item` writes here at
  `world_hero_previewer.lua:776`.
- `self._equipment_units[<numeric slot_index>]` — keyed by an integer
  (typically 1 = melee, 2 = ranged for the player profile, but treat it
  as opaque). Vanilla `equip_item` writes
  `equipment_units[slot_index].right = unit` at line 922.

The two tables describe the same slot but use **different keys**. Looking
up `equip_units[slot_type_string]` returns nil silently and any
downstream `slot.right` access also returns nil — the apply path no-ops
without erroring. Easy to miss; only diagnostic logs catch it.

**The bridge:** each `info.spawn_data[i]` entry vanilla writes also
carries the `slot_index` field
(`world_hero_previewer.lua:704` for left_hand, `:728` for right_hand).
Use `info.spawn_data[1].slot_index` to translate from the string-keyed
`info` back to the numeric `equip_units` key:

```lua
local slot_index = info and info.spawn_data and info.spawn_data[1]
                                            and info.spawn_data[1].slot_index
if not slot_index then return end
local slot = self._equipment_units[slot_index]
```

**Hit twice:** cosmetics_tweaker v0.7.88 (`_spawn_item_post` walked
`_item_info_by_slot` correctly but tried to look up `_equipment_units`
with the string slot_type), and character_weapon_variants v0.1.84
(`_cwv_spawn_item_post` had a fallback loop that stored the string
slot_type as `target_slot_id` and used it on `equip_units`). Both
produced the same silent failure: hooks fire, mod logs say "Preview
transform" or equivalent, but no scale/offset reaches the unit. User-
visible: in-game body shows the change, inventory character preview
does not.

**Apply:**
- Any new hook on `MenuWorldPreviewer._spawn_item` (or
  `MenuWorldPreviewer.equip_item`) that needs to reach
  `_equipment_units[slot]` MUST resolve the slot through
  `info.spawn_data[1].slot_index`. Don't iterate `_item_info_by_slot`
  and use the iterator key — that's the string slot_type.
- **Target `MenuWorldPreviewer`, NOT `HeroPreviewer`** for keep-inventory
  hooks. VT2's `class()` copies parent methods at definition time, so
  hooks on `HeroPreviewer` silently never fire on the keep inventory
  previewer instance. Burned in weapon_tweaker v0.12.16 → fixed v0.12.17.
  See `docs/WEAPON_APPEARANCE_STANDARD.md` §1 for the class-derivation
  rule and canonical path contract.
- A diagnostic log printing `slot.right` / `slot.left` value alongside
  the resolved `slot_index` catches this in one equip cycle. Skip-branch
  logging on each early-return is what made v0.1.84 obvious.
- `LootItemUnitPreviewer` does NOT have this split — it spawns into a
  single `self._spawned_units` array indexed by spawn order (left=1,
  right=2). Different system, different rules.

## Dead ends — do not retry

Research paths exhausted with negative results. Documenting so future-me
doesn't burn time rediscovering they don't work.

### Runtime cross-character animation grafting (CONCLUDED 2026-04-26)

**Not possible via the Stingray Lua API.** Every exposed animation API
was tested. None allow adding individual animation events or clips to an
existing 3P state machine at runtime. 3P state machines are baked into
binary `.unit` files at compile time.

**APIs tested (all dead ends):**
- `set_animation_state_machine` — CRASH on 3P (C++ level)
- `blend_base_layer` + 1P SM — skeleton collapses (bone mismatch)
- `blend_base_layer` + 3P path — CRASH (resource type mismatch, even
  with pre-load)
- `set_animation_merge_options` — AI-only, not applicable
- `animation_set_state` / `get_state` — states must exist in target SM,
  not transferable
- `animation_find_variable` / `set_variable` — variables only, can't add
  events
- Spawn hidden 3P unit + probe — WORKS but no API to copy animations
  from it
- Swap `Cosmetics[skin].third_person` at spawn — spawn works, events
  gained, but skin mesh crashes on bone mismatch (`j_skirt`)

**What this means:**
- Cross-career weapons with a reasonable animation equivalent work fine
  via redirects (`_anim_redirect` / `_3p_weapon_remap` — System A in this
  file).
- Weapons with NO equivalent on the target skeleton (bows on Saltzpyre,
  dual-wield anywhere) cannot be fixed via Lua modding. Either skip the
  cross-character port, or accept a degraded 3P render.
- Only theoretical path: offline binary editing of `.unit` files — far
  beyond Lua modding scope and not pursued.

**Don't retry animation grafting research.** Focus cross-career weapon
work on the redirect system (which covers the majority of cases). Accept
that some weapon/character combos will have missing or wrong 3P
animations.

## Cosmetics Tweaker — Weapon Model & Shield Swap System

### Overview

The `cosmetics_tweaker` mod (Workshop 3715714222, internal ID `cosmetics_tweaker`) handles visual-only weapon modifications: per-axis scaling, grip offsets, hat tinting, cosmetic unlocks, and shield model swaps. It is built with **VMB** (not the raw Stingray compiler used by the other mods).

### Build & Deploy

Standard pipeline - `VMBLauncher.exe build/deploy cosmetics_tweaker` (or `ship.ps1`).
Owner docs: repo-root `CLAUDE.md` "Build Commands" + `tools/vmb-launcher/CLAUDE.md`.

**Hot-reload crashes (Ctrl+Shift+R):** weapon_tweaker and cosmetics_tweaker are NOT safe to hot-reload. Both hook unit creation paths (`GearUtils.create_equipment`, `BackendUtils.get_item_units`), and cosmetics_tweaker bundles non-Lua resources (materials/textures). The Stingray engine holds C++-level locks on spawned unit and material resources that cannot be released from Lua — `Mod.release_resource_package` triggers `ensure_unlocked` and crashes. Attempted workarounds (hooking `ModManager.unload_mod`, clearing `loaded_packages` in `on_reload`) either failed to fire (VMF's mod object is not `mod.object` in ModManager) or caused worse cascading failures (wiping third-party atlas handles, increasing lock counts). **Always do a full game restart** after deploying weapon_tweaker or cosmetics_tweaker changes. chaos_wastes_tweaker, general_tweaker, and career_tweaker are Lua-only and may survive hot-reload, but a restart is safest.

**`UIRenderer._injected_material_sets` poisoning:** Adding a custom material to `UIRenderer._injected_material_sets` is DANGEROUS. If the engine can't resolve the material path when `UIRenderer.create` runs, it silently poisons the **entire** Gui material loading pass — ALL materials (including VMF's `vmf_atlas` and other mods' atlases) fail to load on every UIRenderer created after that. Symptoms: VMF options crash with `Material 'vmf_atlas' not found in Gui`, NewsFeedUI crash with `armoury_atlas not found`, blank settings panel. The poisoning persists for the entire session. Do NOT inject materials into `_injected_material_sets` unless the resource package is confirmed loaded and the material is verified resolvable. Prefer per-renderer injection over global injection.

### Shield & Weapon Unit Architecture

VT2 shield weapons use **two independent units**:
- **Right hand** (`right_unit_1p` / `right_unit_3p`): the weapon (sword, mace, axe, etc.)
- **Left hand** (`left_unit_1p` / `left_unit_3p`): the shield

They are spawned separately, attached to different skeleton nodes (`j_rightweaponattach` / `j_leftweaponattach`), and can be scaled, offset, or swapped independently.

### Weapon Appearance Path Ownership

> Owner doc: `docs/WEAPON_APPEARANCE_STANDARD.md` §1 (consolidated 2026-07-08,
> issue #432). It defines FOUR render paths - owner in-world, husk (remote),
> inventory preview, illusion browser - with hook targets, per-hand unit access,
> the presentation descriptor and UI adapters, and the load-bearing facts
> (derived-class hooking, string-vs-numeric slot keying, `_spawn_item_unit`
> no-hand-indicator, spawn-order, career-detection caveat). Do not restate the
> path table here; the subsections below describe only their historical hook
> coverage and must not be treated as the complete acceptance surface.

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
- **`pattern`**: literal substring matched against the resolved per-hand unit path. The two menu paths read this from `spawn_data[i].unit_name` (the truth-source path that vanilla `equip_item` / `_load_item_units` got back from `BackendUtils.get_item_units` and queued for spawn). The in-game path resolves it itself via `_resolve_render_unit_path(item_data, skin, hand_field)` because `GearUtils.create_equipment` doesn't expose a pre-resolved spawn_data array.
- **`factor`**: a `function(get)` returning `{x,y,z}|number|nil` (toggle off → return nil), a literal `{x,y,z}` table, or a uniform number. Functions are called every apply, so live setting toggles take effect on next equip.
- **`hand`**: restricts to one hand. `"right"` only scales the weapon hand (used to keep paired shields at native scale); `"left"` only the shield/offhand; `nil` scales both.

#### Historical scale-hook coverage

This scale subsystem installs the three hooks below. That is an implementation
inventory, not the canonical rendering-path count: remote-husk behavior and UI
presentation adapters remain separate acceptance cells in
`docs/WEAPON_APPEARANCE_STANDARD.md`.

1. `GearUtils.create_equipment` — `_scale_units(result, item_data, result.skin)` resolves paths via `_resolve_render_unit_path`.
2. `MenuWorldPreviewer._spawn_item` — `_spawn_item_post` walks `self._item_info_by_slot`, bridges to `_equipment_units` via `info.spawn_data[1].slot_index`, then reads `right_path`/`left_path` directly from `info.spawn_data[i].unit_name` (looking for `sd.right_hand` / `sd.left_hand` flags). No item_data lookup, no skin-resolution chain. **Hook MenuWorldPreviewer directly, NOT HeroPreviewer** — see the owner standard for the class-copy reason.
3. `LootItemUnitPreviewer.spawn_units` — reads paths from the `spawn_data` argument (`spawn_data[1].unit_name` = left, `spawn_data[2].unit_name` = right; spawn order is fixed by `_load_item_units`). No item_data lookup either.

**No `cwv_variant` gate is needed on the menu paths** because a cwv variant's `spawn_data.unit_name` is always its variant model, never the base weapon's path. The truth-source approach makes the gate redundant — see `feedback_cwv_clone_name_clobber.md`. The in-game `GearUtils` path also doesn't need the scale gate (unit-path matching alone is sufficient there too); but it DOES still gate offset/tint/LA-paint on `not item_data.cwv_variant` because those are item-name-keyed and a cwv item inherits the base's `name`.

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
2. It centralizes the three historical consumers listed above; this alone does not prove remote-husk or UI-presentation parity
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

When browsing illusions in `LootItemUnitPreviewer`, `self._item.data` is the skin's ItemMasterList entry (e.g. `es_bastard_sword_skin_01`), not the weapon. The scale hook doesn't need to resolve anything from `item.data`: vanilla `_load_item_units` already called `BackendUtils.get_item_units` and queued the resolved unit paths on the `spawn_data` argument we hook. We just read `spawn_data[1].unit_name` (left) / `spawn_data[2].unit_name` (right) and pattern-match.

The historic resolution `ItemMasterList[skin_key].matching_item_key → base_weapon_key` is still relevant for any system that genuinely needs the weapon-template identity (e.g. LA offhand selection, which still reads `item.data.item_type`). Use `rawget(ItemMasterList, key)` per CLAUDE.md.

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

## Remote VT2 automation (PowerShell)

Techniques for remotely launching VT2, navigating menus, running mod commands, and reading output via PowerShell automation. Used for in-game diagnostic dumps without forcing the user to drive the game by hand.

### Launching the game

- Launch via Steam protocol: `Start-Process "steam://rungameid/552500"`.
- VT2 launcher is a WebView-based WPF app — synthetic mouse clicks and keyboard input do **NOT** work.
- Click PLAY via `System.Windows.Automation.InvokePattern.Invoke()` on the WPF Button element.
- Must `Add-Type -AssemblyName UIAutomationClient, UIAutomationTypes` in every PowerShell call — types don't persist between Bash/PowerShell tool invocations.
- **Direct exe launch (`vermintide2.exe`) crashes with "Fatal Error!"** — always go through Steam.

### Gaining focus

- `SetForegroundWindow` alone returns False due to Windows UIPI.
- Fix: use `AttachThreadInput` to attach to the foreground thread *before* calling `SetForegroundWindow`.

### In-game input

- Games in fullscreen respond to `SendInput` with **scan codes** (`KEYEVENTF_SCANCODE = 0x0008`).
- For text typing (e.g. chat commands), use **Unicode input** (`KEYEVENTF_UNICODE = 0x0004`).
- Press `Y` to open chat, type `/command_name`, press `Enter` to execute mod commands.

### Reading output

- Console logs at: `%APPDATA%\Fatshark\Vermintide 2\console_logs\`.
- DX12 version (`vermintide2_dx12.exe`) only writes logs when launched through Steam properly.
- `mod:info(...)` writes to the console log file; `mod:echo(...)` writes to the in-game chat overlay.
- Use a `[DUMP:filename]` prefix pattern in `mod:info` to tag output for extraction back to the agent.

### Hot reload

- Ctrl+Shift+R triggers `VMF:ON_RELOAD()` — rebuild and deploy without restarting game.
- Requires `SendInput` with scan codes for Ctrl+Shift+R key combo.
- **Unsafe for `weapon_tweaker` and `cosmetics_tweaker`** — see Important Constraints in `CLAUDE.md`.

### Known issues

- `io` library is NOT available in VT2's Lua sandbox — use `mod:echo` / `mod:info` instead of file I/O.
- Each PowerShell tool call is a separate process — `Add-Type` definitions must be re-included on every call (types don't persist).

### Don't auto-launch without permission

Standing user rule: never start the game without explicit permission, even when remote-control docs make it possible. Diagnostic dumps from in-game logs are preferred over speculative bundle scans (`mod:info` dumps beat `scan_bundles.py` for finding VT2 data; the bundle scanner eats RAM).

## External tools

Tooling that lives outside the repo but is load-bearing for VT2 mod development.

### VT2 bundle unpacker — vanilla asset extraction

`C:\Tools\vt2_bundle_unpacker\target\release\unpacker.exe` — Rust unpacker built from <https://gitlab.com/qasikfwn/vt2_bundle_unpacker> (fork of `lschwiderski/vt2_bundle_unpacker`). Built with `cargo build --release` (~1m18s). Source clone at `C:\Tools\vt2_bundle_unpacker`.

Handles VT2's current bundle format: **0xf0000007** with **zstd compression + shared dictionary** (the engine's `compression.dictionary` next to the bundles is auto-discovered when extracting from the game directory). Older tools (VerminUnpacker / VerminReader_GUI3) don't work — they're stuck on the old `0xf0000006` zlib format.

**Bundle directory:** `C:\Program Files (x86)\Steam\steamapps\common\Warhammer Vermintide 2\bundle\`. Bundles are named by murmur64 hash (16 hex chars, no extension). Many have a `.stream` sidecar of the same name holding high-res texture mips that the engine memory-maps — the unpacker resolves these automatically.

**Common commands** (using Git Bash quoting, paths translated):

```sh
UNPACKER="/c/Tools/vt2_bundle_unpacker/target/release/unpacker.exe"
BUNDIR="/c/Program Files (x86)/Steam/steamapps/common/Warhammer Vermintide 2/bundle"

# List a bundle's contents (hash-named, types annotated)
"$UNPACKER" list "$BUNDIR/2f6172d4cd63f69a"

# Extract raw assets (.texture + .stream pairs preserved)
"$UNPACKER" extract "$BUNDIR/<hash>" "/c/Users/danjo/Downloads/<out_dir>"

# Extract AND decompile — produces actual usable .dds (large) + _small.dds (preview)
"$UNPACKER" extract -d "$BUNDIR/<hash>" "/c/Users/danjo/Downloads/<out_dir>"

# Compute a murmur64 hash from a path (to find which bundle holds an asset)
"$UNPACKER" murmur hash "units/beings/player/empire_soldier_breton/headpiece/es_gk_hat_01"

# Pattern-restricted extraction
"$UNPACKER" extract -i "*.texture" "$BUNDIR/<hash>" <out>
"$UNPACKER" extract -i "*.dds" -d "$BUNDIR/<hash>" <out>
```

The `dictionary.csv not found` warning at startup is harmless — it just means hash filenames stay as hashes instead of being humanized. Extraction works fine without it. **Bundle list** (not `extract`) requires `dictionary.csv` to exist (can be empty) — `touch dictionary.csv` and re-run.

**Finding which bundle holds an asset:**

Bundles store assets by hash, not path. Two ways:

1. **String scan** (works when path strings are embedded in unit/material files): use `C:\Tools\BundleReader\scan_bundles.py` — parallel zstd decompressor that greps decompressed blobs for substrings. Scans all 4661 bundles in ~12 minutes. Output: `<out>/scan.log` (progress) + `<out>/matches.txt` (hash → keyword).
2. **Hash match** (when only the hash is referenced): compute murmur64 of the path with `unpacker murmur hash <path>`, then scan bundles for that 8-byte sequence. Slower; not yet automated.

**Worked example: original GK hat 01 diffuse.** Bundle `2f6172d4cd63f69a` holds `units/beings/player/empire_soldier_breton/headpiece/es_gk_hat_01`. Extract with `-d` produces three texture pairs:

- `7CE448AFEB06EA84.dds` (1.4 MB) — likely diffuse (BC1)
- `D98206F6A4C5881E.dds` (1.4 MB) — likely mask (BC1)
- `83445C84C061F1DA.dds` (2.8 MB) — likely normal map (BC7, larger)

Plus `_small.dds` 64×32 streaming previews. Identify by opening in GIMP / Paint.NET.

**Mod bundle (`.mod_bundle`) format is different.** Workshop mod bundles (`C:\Program Files (x86)\Steam\steamapps\workshop\content\552500\<id>\*.mod_bundle`) use the OLDER **0xf0000006 + zlib** format — this unpacker may not handle them. For mod bundles use the simple Python script at `C:\Users\danjo\Downloads\gk_scan\dump_modbundle.py` (just iterates `78 9c` zlib magic and decompresses).

**Related local scripts:**

- `C:\Tools\BundleReader\dump_bundle.py` — quick zstd dump (raw bytes only, no asset structure).
- `C:\Tools\BundleReader\scan_bundles.py` — parallel substring scanner across all bundles.
- `C:\Users\danjo\Downloads\gk_scan\dump_modbundle.py` — zlib-based mod_bundle dumper.

### Hash reverse-lookup for `Resource '#ID[xxx]' not found` crashes

VT2 engine crashes like `[Engine Error]: Resource '#ID[0e9fc1f2f551a8e8]' was not found!` give you only a 64-bit hash. **Don't guess the cause** — reverse it.

**Tool:** `C:\Tools\vt2_bundle_unpacker\target\release\unpacker.exe murmur hash <path>` prints the murmur64 hash of a Stingray resource path. The shipped unpacker has no `dictionary.csv`, so `murmur lookup` always returns "Unknown hash" — but **forward hashing works without a dictionary**.

**Workflow:**

1. **Note the hash from the crash** (16 hex chars, lowercase). Example: `0e9fc1f2f551a8e8`.
2. **List candidate paths.** The path is usually one of:
   - One of YOUR mod's files (units, textures, materials, lua, packages) — these would have BEEN compiled and probably ARE in the bundle; if they're missing, the bundle build had a silent error.
   - A path **derived** from one of your authored values by convention. The big one: any `<right_hand_unit>` field auto-spawns `<right_hand_unit>_3p` for third-person. Other conventions to try: `<unit>_1p`, `<material>_decal`, `<texture>_alpha`.
   - A package or resource the game expects every weapon / career to ship.
3. **Hash each candidate:**

   ```bash
   for p in "units/<...>" "units/<...>_3p" "..." ; do
       echo "$(unpacker.exe murmur hash $p)  $p"
   done
   ```

   Match against the crash hash (case-insensitive — unpacker prints upper, crashes print lower).
4. **Verify the match.** Bundle list (`unpacker.exe list <bundle.mod_bundle>`) shows compiled resources by hash. If the missing-hash filename should be in the bundle but isn't, your `.package` glob may have missed it.

**Sharp edges:**

- The unpacker shows `ERROR: Failed to read dictionary file 'dictionary.csv'` even when only forward-hashing. The error is benign — hash output is still printed on the last line.
- Bundle list requires `dictionary.csv` to exist (can be empty). `touch dictionary.csv` and re-run.
- Some hash references in compiled units use NESTED / derived names not directly in your code. Scan for `_3p` siblings, `_1p` siblings, `<basename>` references first.
- **Resource TYPE matters as much as path.** Stingray identifies resources by `(type, name_hash)`. Two resources can share the same path hash but one is a `.unit` and the other a `.package`. If you ship the `.unit` but the engine wanted a `.package` at that path, you get the SAME hash error — because it failed to find the (`package`, `<hash>`) tuple, not the (`unit`, `<hash>`) one. Always check the console log's `<<Lua Stack>>` to see which loader is being called (`package:load` → expects `.package`; `World.spawn_unit` → expects `.unit`).

**Don't skip this step.** `character_weapon_variants` v0.1.272 was a wasted iteration because the fix was authored from speculation about what "Resource not found" meant. Hash reverse-lookup would have shown in 30 seconds that the missing resource was a `_3p` sibling unit, not a material.

**Rule:** before authoring fixes for a hashed-ID crash, reverse the hash. Speculation costs version bumps and user trust.

### Workshop Lua extract pipeline — bulk-decompile any subscribed mod

Pipeline lives at `C:\Users\danjo\source\repos\misc-vermintide-mods\_scratch\` (sibling repo):

- `extract_mod.ps1` — first pass. Args: `-WorkshopId <id> -OutDir <path>`. Uses the Rust unpacker above. Decompiles LuaJIT bytecode via `py -3 C:\Tools\BundleReader\ljd-vt2\main.py -f <file>`. (`BundleReader\VerminUnpacker.exe` is broken on workshop bundles — silently no-ops; don't use it.)
- `recover_mod.ps1` — second pass for mods where the `.mod` manifest passes a variable (`new_mod(file_name, ...)`) instead of a literal — extractor's first-pass regex misses these. Re-parses `local file_name = "X"` and re-hashes candidates.
- `mod_index.json` — Steam Workshop metadata for every installed mod (title, author SteamID, author display name) via `ISteamRemoteStorage/GetPublishedFileDetails/v1/` (no API key needed, batch of 50).
- `final_report.tsv`, `to_extract.tsv` — extraction worklist + per-mod status from the 2026-05-21 bulk run (86 non-Ensrick mods).

**Key file-naming detail:** Stingray bundles store files under murmur64 hash of the canonical path (without extension). The `.mod` manifest itself is hashed from the bare mod name, no path. Headers are 12 bytes for `.lua`, 16 bytes for `.mod` / `.package`; first 4 bytes of the entry = LE u32 content length, so `header_size = total - declared_length` is format-agnostic.

**Asset-only mods** (shader_library, material, texture, unit) often ship ~290 hash-named blobs with no Lua at all — this is a VMB workshop-uploader artifact, not custom content. Don't waste time trying to "recover" Lua from these.

## Useful Paths

- **Game Logs**: `%APPDATA%\Fatshark\Vermintide 2\console_logs`
- **Workshop Content**: `C:\Program Files (x86)\Steam\steamapps\workshop\content\552500\`
- **Local Mod Folder**: `C:\Program Files (x86)\Steam\steamapps\common\Warhammer Vermintide 2\mods` (used by the legacy `install_local.bat` flow, now in `old-backup/`)
- **SDK**: `C:\Program Files (x86)\Steam\steamapps\common\Vermintide 2 SDK\`
- **AnyWeapon reference mod**: `C:\Users\danjo\source\repos\vermintide-mods\AnyWeapon\` (reference for weapon unlock pattern)
- **VT2 bundle unpacker**: `C:\Tools\vt2_bundle_unpacker\target\release\unpacker.exe` (see § External tools)
- **Workshop Lua extract pipeline**: `C:\Users\danjo\source\repos\misc-vermintide-mods\_scratch\` (see § External tools)
