# 3P Animation Research — Cross-Career Weapons

## Weapon Template Keys (confirmed from source)

| Item Key (ItemMasterList) | Template Key (Weapons global) | wield_anim | Notes |
|---|---|---|---|
| `wh_fencing_sword` | `fencing_sword_template_1` | `to_fencing_sword` | Rapier & Pistol. `dump_templates fencing` to inspect live. |
| `wh_1h_falchion` | `one_hand_falchion_template_1` | `to_1h_sword` | Falchion. Native wield_anim is already generic — elf likely has it. |
| `wh_flail_shield` | (unknown — `dump_templates flail_shield`) | `to_flail_shield` | Flail & Shield. No standalone Saltzpyre flail exists in ItemMasterList. |
| `we_longbow` | `longbow_template_1` | `to_longbow` | Elf longbow. Kruber has `to_es_longbow`; Saltzpyre has `to_crossbow_loaded`. |
| `es_longbow` | `longbow_empire_template` | `to_es_longbow` | Empire longbow. Saltzpyre's skeleton has NO bow animations. |
| `wh_crossbow` | (scan for `crossbow` in Weapons) | `to_crossbow_loaded` | Saltzpyre's native ranged. `dump_crossbow` command to find 3P unit path. |

## Approaches Tried — 3P Wield Animation

### 1. `wield_anim_career_3p` custom field ❌ DEAD
- **What:** Injected a custom `wield_anim_career_3p[career]` field into live `Weapons` template tables.
- **Why it fails:** The game never reads this field. It was invented — no code path in the engine consults it.
- **Status:** Fully removed.

### 2. `unit_template.unit_3p` swap in `GearUtils.create_equipment` ❌ DEAD
- **What:** Before calling `create_equipment`, temporarily replaced `unit_template.unit_3p` with the crossbow's 3P unit path, then restored it.
- **Why it fails:** `unit_template.unit_3p` is `nil` in this hook. The 3P model path is determined inside `create_equipment` from the item's `right_hand_unit` / skin data, not from the unit template.
- **Status:** Fully removed. Only the pcall safety wrapper (`_safe_create_equipment`) was kept.

### 3. `Unit.animation_event` fallback hook ⚠️ PARTIAL
- **What:** Intercepts every `Unit.animation_event` call. If the requested event doesn't exist on the unit's skeleton (`Unit.has_animation_event` returns false), tries a fallback chain.
- **What works:** `to_longbow → to_crossbow_loaded` — Saltzpyre wielding a longbow plays the crossbow wield animation.
- **What doesn't work:** Only covers the *wield* animation. Attack, aim, and reload animations are driven by the weapon action system (`CharacterStateHelper`), not by `animation_event`. Saltzpyre holding a longbow plays crossbow wield, then uses longbow attack/aim logic — he fires but the animation is wrong/missing.
- **Skeleton incompatibility confirmed:** Saltzpyre has no bow animations (`to_es_longbow` etc. don't exist on his skeleton). Empire longbow fallback to crossbow was removed.
- **Elf skeletons:** Unknown which wield events exist. Use `probe_3p` command on an elf character in-game to discover them.
- **Status:** Kept, trimmed to only confirmed-useful entries.

### 4. Empire longbow wield on Saltzpyre ❌ CONFIRMED BROKEN
- Tried redirecting `to_es_longbow` → `to_crossbow_loaded` via the fallback hook.
- Saltzpyre's skeleton has no compatible bow animation. Removed from fallback table.

## Approaches NOT YET TRIED

### `BackendUtils.get_item_units` hook (GiveWeapon mod pattern)
- GiveWeapon mod successfully swaps `units.right_hand_unit` (3P model path) inside this hook.
- This is likely the correct hook point for making Saltzpyre show a crossbow model instead of a longbow.
- Signature: `BackendUtils.get_item_units(item_data, career_name, item_skin)` → returns a `units` table with `right_hand_unit`, `left_hand_unit`, etc.
- **Next step:** Hook this, detect Saltzpyre + longbow item, swap `right_hand_unit` to crossbow path.
- **Blocker:** Need the correct crossbow 3P unit path. `dump_crossbow` command should log it when run in a level.

### Full attack/aim animation replacement
- The weapon action system (`CharacterStateHelper`) drives attacks. No mod has solved this.
- Would require intercepting `start_action` / `_get_chain_action_data` and substituting the action table with crossbow actions.
- Very complex; not attempted.

## General Animation Rule (confirmed)

Weapons whose `wield_anim` is a generic single-character event (`to_1h_sword`, `to_1h_axe`, `to_1h_mace`) work cross-career with **no fallback needed** — every career skeleton has these events. This covers:
- Falchion (`to_1h_sword`) ✅ confirmed working on elf with no patching
- Any 1h sword, 1h axe, 1h mace cross-career unlock will animate correctly by default

Only weapons with career-specific wield events (`to_fencing_sword`, `to_longbow`, `to_flail_shield`, etc.) need entries in `_wield_anim_fallbacks`.

## Rapier & Pistol on Elf (confirmed working)

The `Unit.animation_event` fallback hook IS working: `to_fencing_sword → to_sword_and_dagger / to_1h_sword` plays on elf. Animations confirmed working in-game.

## Item Key Bugs Fixed

| Was | Correct | Why Wrong |
|---|---|---|
| `wh_falchion` | `wh_1h_falchion` | `wh_falchion` does not exist in ItemMasterList |
| `wh_flail` | `es_1h_flail` | That key is the Empire/Saltzpyre flail; `wh_flail_shield` is Warrior Priest DLC only |

## Current Fallback Table (tweaker.lua)

```lua
to_longbow       → { "to_crossbow_loaded", "to_es_longbow" }   -- Saltzpyre/Kruber wield elf longbow
to_fencing_sword → { "to_sword_and_dagger", "to_1h_sword" }    -- elf wields rapier (unconfirmed)
to_1h_flail      → { "to_1h_sword" }                           -- elf wields flail (unconfirmed)
to_flail_shield  → { "to_1h_sword" }                           -- elf wields flail+shield (unconfirmed)
```

## Commands for Discovery

| Command | Purpose |
|---|---|
| `t probe_3p` | List which wield anim events exist on the local player's 3P unit skeleton |
| `t dump_templates fencing` | Inspect live `fencing_sword_template_1` — wield_anim, unit paths |
| `t dump_crossbow` | Log Saltzpyre crossbow template keys and 3P unit paths |
| `t dump_chest_view` | Arm a capture of DeusCursedChestView scenegraph on next chest open |

## Chest of Trials UI — Tracked Issue

When boon count > 3, arc expansion pushes items outside the background panel (clips visually but does not crash). Items are spaced correctly; only the background frame is too small.

**Next step:** Run `t dump_chest_view` then open a chest to capture scenegraph node names and sizes. Then scale the background node up proportionally. See `DeusShopView` for reference — its background is already sized for 4-5 items.
