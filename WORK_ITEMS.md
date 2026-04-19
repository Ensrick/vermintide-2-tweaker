# Tweaker — Work Items

Last updated: 2026-04-19

---

## ✅ Confirmed Working

| Feature | Notes |
|---|---|
| Coin pickup multiplier | Settings slider, applies on pickup |
| Starting coins | Applies at run init |
| Shrine boon count (1–5) | Arc layout stable |
| Chest boon count (1–5) | Items overflow background panel visually but no crash |
| Disable individual curses (9) | All confirmed |
| `t win` command | Completes current map |
| Friendly fire toggle | Ranged + melee |
| Duplicate career allowance | All 3 hooks in place |
| Kruber cross-career melee unlocks | 1h axe, hammer, mace, shield variants — all animate correctly (generic `to_1h_*` events present on all skeletons) |
| Bardin cross-career melee unlocks | Same — generic wield anims, all work |
| Saltzpyre melee unlocks for Kruber/Bardin | Same |
| Elf longbow for non-Waystalker careers | Waystalker natively has `to_longbow`; other elf careers get it via unlock |
| **Elf + Falchion** (`wh_1h_falchion`) | `wield_anim = to_1h_sword` — works on all careers with no patching needed |
| **Elf + Flail** (`es_1h_flail`) | Works with standard animations — confirmed same rule as 1h sword/axe/mace |
| **Elf + Rapier & Pistol** (`wh_fencing_sword`) | `Unit.animation_event` fallback fires `to_fencing_sword → to_sword_and_dagger/to_1h_sword` — confirmed working |
| Curse disable — node/course curse hooks | Working |
| Crowbill item key fix | `bw_crowbill` → `bw_1h_crowbill` in weapon map, settings, and localization |
| Camera Lua ordering fix | `_tp_inst_patched` / `_try_patch_tp_camera` forward-declared before `on_game_state_changed` |

**General rule (confirmed):** Any weapon with `wield_anim` of `to_1h_sword`, `to_1h_axe`, or `to_1h_mace` works cross-career with no animation patching. All skeletons have these events.

**Animation hook rule:** Never put an event in `_wield_anim_prefer` if that event exists natively on ANY career's skeleton. The prefer list fires before the original for ALL units — it will redirect a career's own native weapon to a wrong animation. Use a career-aware special-case function (`_fencing_sword_anim`, `_longbow_anim`, etc.) instead.

---

## 🔄 In Progress / Needs Testing

### Saltzpyre + Longbow: 3P Model Swap (implemented, needs test)
- **Status:** `BackendUtils.get_item_units` hook now swaps `left_hand_unit` to crossbow model path when Saltzpyre equips any `ww_longbow` item type with the unlock enabled.
- **Test:** Enable longbow unlock for any Saltzpyre career, load a level, check if 3P shows crossbow model.
- **Known limitation:** Wield anim works (crossbow fallback). Aim/fire/reload animations will still look wrong — those are driven by the weapon action system, not `Unit.animation_event`.

---

## ❌ Known Broken — No Fix Yet

### Saltzpyre + Longbow: Wrong 3P Model + Attack Animations
- **Symptom:** Crossbow *wield* animation plays (fallback working). But: longbow model shows in 3P, aiming doesn't animate, shooting doesn't animate.
- **Root cause (3P model):** All crossbow `unit_3p` fields in `Weapons` global are `nil`. Model comes from `ItemMasterList[item_key].right_hand_unit`. Correct hook is `BackendUtils.get_item_units` — swap `units.right_hand_unit` to crossbow path when Saltzpyre equips a longbow.
- **Root cause (attack/aim anims):** Driven by weapon action system (`CharacterStateHelper`), not `Unit.animation_event`. No mod has solved this. Very complex.
- **Next step (model):** `t dump_item wh_crossbow` in-game → get `right_hand_unit` path → implement `BackendUtils.get_item_units` hook.
- **probe_3p data (elf skeleton):** `to_longbow` ✅ | `to_crossbow_loaded` ❌ | all other ranged ❌

### Talent Swap UI Not Updating
- **Symptom:** `apply_talent_swaps()` mutates `TalentTrees` and `CareerSettings` but the in-game talent picker UI doesn't refresh to show the swapped talents.
- **Root cause:** Unknown — need to find the UI refresh function for the talent panel.
- **Also:** Swapping a career whose ability is a weapon (e.g. GK's blessed blade) to a career that doesn't support it causes a crash. Needs pcall protection in `apply_talent_swaps`.
- **Next step:** Find and hook the talent UI refresh function. Add pcall around ability swaps.

### BH Career Ability with Non-Native Ranged Weapons
- **Root cause (confirmed from source):** BH's ability is triggered by `input_override = "action_career"` on the career skill weapon slot. This input binding only exists on native Saltzpyre weapons and structurally analogous ones (dwarf 1h axe works; longbow doesn't). Non-native ranged weapons lack `action_career` in their allowed input map — button press is silently ignored. `wh_2` has no `activation_requirements` field; the previous patch was a no-op and has been removed.
- **Fix required:** Hook `CharacterStateHelper` to inject `action_career` processing regardless of current weapon. Complex — not yet implemented.

### Talent Swap UI Not Updating
- **Symptom:** `apply_talent_swaps()` mutates live tables but the talent picker UI doesn't refresh.
- **Also:** Swapping a career with a weapon-ability (e.g. GK blessed blade) to another career crashes. Needs pcall protection.
- **Next step:** Find the talent UI refresh function and hook it. Add pcall around ability swaps.

### Chest of Trials Background Panel Clipping
- **Symptom:** When boon count > 3, items extend beyond the background panel (visual only, no crash).
- **Next step:** Run `t dump_chest_view`, then open a chest → share the scenegraph output → scale background node to match expanded arc.

### Bretonnian Sword & Shield for Non-GK Kruber
- **Status:** `es_sword_shield` has no `can_wield` field — `apply_weapon_unlocks` does nothing with it. The GK-exclusive Bretonnian item uses a different key (unknown).
- **From source:** Template `one_handed_sword_shield_template_2`, wield_anim `to_1h_sword_shield_breton` exists. Item key unknown.
- **Next step:** `t dump_item es_sword_shield` in-game to confirm it has no `can_wield`. Then search source for `to_1h_sword_shield_breton` to find the correct item key.

---

## 📋 Actions Needed From You (Testing)

1. **Saltzpyre + longbow 3P model** — does the model now show as crossbow in third person?
2. **`t dump_chest_view` then open a chest** — needed for background panel fix
3. **Bretonnian S&S** — run `t dump_item es_sword_shield` to confirm it has no `can_wield`
4. **Talent swap crash** — if you try swapping a career with a weapon-ability (e.g. GK) to another career, note the error

---

## 🗑️ Confirmed Dead — Animation

### Rapier & Pistol (`wh_fencing_sword`) on Elf — Sword & Dagger animations
- **Status:** DEAD END. Log confirmed elf has `to_fencing_sword` as a skeleton event but it maps to the generic 1h sword set — NOT sword & dagger. Five S&D event name variants were tried (`to_sword_and_dagger`, `to_dagger_sword`, `to_sword_dagger`, `to_we_sword_dagger`, `to_dagger`) and none exist on elf skeletons.
- **Final result:** `to_fencing_sword → to_1h_sword` fallback is the only option. Elf will use 1h sword animations when wielding a rapier. Do not retry.

---

## 🗑️ Approaches Confirmed Dead (do not retry)

| Approach | Why |
|---|---|
| `wield_anim_career_3p` custom field | Game never reads this field. Fully removed. |
| `unit_template.unit_3p` swap in GearUtils hook | `unit_template.unit_3p` is always `nil` at hook time. Removed. |
| `to_es_longbow` fallback on Saltzpyre | Saltzpyre skeleton has no bow animations. Removed from fallback table. |
| `_crossbow_3p_path` via Weapons global | All crossbow templates have `unit_3p = nil`. Model is in ItemMasterList. |
| Career-naive `_wield_anim_prefer` for `to_fencing_sword` | Ran for all careers — redirected WHC away from his own native animation. Any event that exists natively on some careers must use a career-aware special-case function, not a global prefer table. |
| `first_person_mode_active` patching for TP camera | Only controls arm mesh visibility. Camera position is not affected. |
