<!--
REVIEW (2026-05-01):
- "Last updated: 2026-04-27" — predates the 2026-05-01 VMB migration. CHANGELOG.md and
  per-mod CHANGELOG entries from 2026-04-29 to 2026-05-01 have not been reflected here.
  Bump this to 2026-05-01 and audit:
  - "weapon_tweaker (v0.9.57-dev)" — CHANGELOG.md root has v0.10.6-dev entries, so the
    version sticker here is stale by ~1 minor.
  - "general_tweaker (v0.2.8-dev)" — confirm current dev version.
  - "chaos_wastes_tweaker (v0.2.1-dev)" — confirm.
  - "career_tweaker (v0.1.0-dev)" — confirm.
  Should the per-mod CHANGELOG.md (root + per-mod) be the authoritative version and this
  file just track features w/o per-mod version badges? Otherwise these go stale silently.
- Cosmetics_tweaker, enemy_tweaker, character_weapon_variants are entirely missing from
  the "Confirmed Working" sections. The cosmetics_tweaker DLC unlock pipeline (v0.6.38, v0.7.0
  per CHANGELOG) and the LA Bridge belong here.
- Sample-check: "Cross-Character 3P Animation Status" content is consistent with
  WEAPON_CATALOG.md.
-->
# Tweaker — Work Items

Last updated: 2026-04-27

---

## ✅ Confirmed Working

### weapon_tweaker (v0.9.57-dev)
| Feature | Notes |
|---|---|
| Cross-career 1H melee unlocks | All `to_1h_sword`, `to_1h_axe`, `to_1h_hammer`, `to_1h_flail` weapons work on all skeletons — universal wield events |
| Cross-career shield weapons | `to_1h_sword_shield`, `to_1h_hammer_shield` — work on Kruber/Saltz/Bardin/Kerillian (not WPriest or Sienna) |
| Spear/Polearm/Billhook cross-career | `to_spear` and `to_polearm` universal; billhook redirects to polearm on non-Saltz/Sienna. Billhook on Kruber: full light+heavy+push+special chain confirmed working |
| Elf greatsword on Kruber | Redirects `to_2h_sword_we` → `to_bastard_sword` with template attack remaps |
| Elf greatsword on Saltzpyre | Redirects `to_2h_sword_we` → `to_1h_sword` (falchion anims) with attack remaps, normal scale |
| Bardin greataxe on Kruber | Template remap: 3 attack events remapped to 2h_hammer equivalents |
| Elf longbow on Kruber | Uses Kruber's native `to_es_longbow` — looks better than elf anims would |
| Career-aware animation redirects | Phantom events redirect by career prefix; WPriest gets special handling |
| Suffix-based animation redirects | Weapon-suffix swapping (e.g. `_2h_sword_we` → `_bastard_sword`) |
| Template-based 3P attack remaps | Tracks weapon template via `SimpleInventoryExtension.wield` hook (reads BEFORE func to prevent stale template); remaps attack events that lack transitions in the target skeleton's wield state |
| Remap persistence across re-wield | Remap only resets on actual weapon switch (template change), not on re-wield events from push/block/ability. Prevents mid-combat remap loss. |
| Live weapon unlock toggle | Toggling weapons on/off in VMF settings takes effect immediately — no restart needed. Strips mod-managed careers from `can_wield` and re-adds only enabled ones. UI filter rebuilt before item grid populates. Backend loadout cache cleared for disabled weapons. |
| Weapon scale overrides | Cross-character weapons scaled per career (elf sword, Sienna sword, etc.) |
| Weapon grip offsets | Per-career position offset system (infrastructure ready) |
| Career action injection | Injects career ability actions into non-native weapon templates |
| `wt dump`, `wt dump_actions`, `wt status`, `wt animlog`, `wt sm_probe`, `wt force3p` | Debug/inspection commands. `force3p` fires on local `player_unit` (3P body). |

### Cross-Character 3P Animation Status (v0.9.57-dev)

Below tracks the 3P animation quality for each weapon that has been enabled cross-character and requires animation remapping. Weapons using universal wield events (1H melee, shields) work natively and are not listed.

#### Elf Spear (`we_spear`) on Saltzpyre
- **Wield:** `to_spear` → redirected to `to_2h_billhook` (Saltz has billhook natively)
- **Remap table:** `_3p_remap_spear_to_billhook` — maps elf spear attack events to billhook equivalents
- **Lights L1-L3:** Via remap table (down_right→stab, down_left_axe→left_diagonal, right→left_diagonal, stab_lh→stab)
- **Heavy charges:** `charge_right→charge_left_diagonal`, `charge_left→stab_charge` (swapped in v0.9.54 to fix windup/strike mismatch)
- **Heavy releases:** `heavy_right→heavy_left_diagonal`, `heavy→heavy_stab` via remap table
- **Push follow-up:** `push_stab→left_diagonal`
- **Status:** ✅ Full light + heavy + push chain working. Charges match strikes.

#### Heavy Spear (`es_2h_heavy_spear`) on Saltzpyre
- **Wield:** `to_polearm` → redirected to `to_2h_billhook` (same as elf spear — shared remap table)
- **Remap table:** `_3p_remap_spear_to_billhook` (shared with elf spear — different events don't collide)
- **Lights L1-L3:** Via remap table
- **Light L4:** `attack_swing_stab_02` — **force-fire** via `_original_animation_event` → `left_diagonal`. Cannot use remap table (breaks entire SM chain).
- **Heavy charges:** `charge→stab_charge`, `charge_stab→charge_left_diagonal` via remap table. Windups match strikes visually (note: event names are inverted — `stab_charge` looks like swing, `charge_left_diagonal` looks like stab).
- **Heavy releases:** Force-fire `heavy_left→heavy_stab`, `heavy_stab→heavy_left_diagonal`. Force-fires only activate when `_3p_weapon_remap == _3p_remap_spear_to_billhook` to avoid interfering with other weapons.
- **Heavy combo order:** Swing then stab (determined by weapon template, not modifiable via animation remaps). User accepted.
- **Push follow-up:** Not yet tested (`light_attack_bopp`, 1P=`attack_swing_heavy_left`).
- **Status:** ✅ Lights L1-L4 + heavies H1-H2 with charges working.

#### Elf Spear+Shield (`we_1h_spears_shield`) on non-elf characters
- **Wield:** `to_1h_spear_shield` → redirected to `to_es_deus_01` (Kruber's bretonnian spear+shield)
- **Remap table:** `_3p_remap_spear_shield_to_deus` — maps `stab_lh→stab` (only difference)
- **Status:** ✅ Working on Kruber/Saltzpyre/Bardin (wherever `to_es_deus_01` exists on skeleton)

#### Kruber Spear+Shield (`es_deus_01`) on Elf
- **Wield:** `to_es_deus_01` → redirected to `to_1h_spear_shield` (elf has spear+shield natively)
- **Remap table:** `_3p_remap_deus_to_spear_shield` — reverse of above, maps deus events to elf spear+shield events
- **L2:** `attack_swing_up→attack_swing_stab_lh` (deus fires `up` for L2; elf skeleton's native L2 is `stab_lh`)
- **H3:** `attack_swing_heavy_down_right→attack_swing_heavy_down` (`heavy_down_right` doesn't exist on elf skeleton)
- **Status:** ✅ Full light + heavy chain working (v0.9.57).

#### Billhook (`wh_2h_billhook`) on non-Saltzpyre
- **Wield:** `to_2h_billhook` → redirected to `to_polearm` (universal)
- **Remap table:** `_3p_remap_billhook_to_polearm` — comprehensive remap of all billhook-specific events to polearm equivalents (charges, heavies, lights, push)
- **Status:** ✅ Full chain working on Kruber.

#### Elf Spear / Polearm on Kruber
- **Wield:** `to_spear` / `to_polearm` both native on Kruber
- **Remap table:** `_3p_remap_spear_to_polearm` — maps `down_left_axe→down_left`, `left→down_left`
- **Status:** ✅ Working.

### Wield-Event Remap Tables Summary

| Table | Direction | Used when | Key mappings |
|---|---|---|---|
| `_3p_remap_spear_to_billhook` | Spear/polearm events → billhook | Saltzpyre wielding elf spear or heavy spear | 12 entries covering lights, heavies, charges, push |
| `_3p_remap_spear_to_polearm` | Spear events → polearm | Kruber wielding elf spear | 2 entries (axe swing + left swing) |
| `_3p_remap_billhook_to_polearm` | Billhook events → polearm | Non-Saltz wielding billhook | 14 entries covering full billhook moveset |
| `_3p_remap_spear_shield_to_deus` | Elf spear+shield → deus | Non-elf wielding elf spear+shield | 1 entry (stab_lh→stab) |
| `_3p_remap_deus_to_spear_shield` | Deus → elf spear+shield | Elf wielding Kruber's spear+shield | 2 entries (up→stab_lh, heavy_down_right→heavy_down) |
| Plus: greataxe→hammer, elf GS→bastard/falchion, crowbill→sword, falchion→sword, flaming flail→flail | Various | Various cross-career combos | See code |

### general_tweaker (v0.2.8-dev)
| Feature | Notes |
|---|---|
| Third-person camera | Toggle via `gt tp` command or `tp_camera_enabled` setting; configurable distance/height/offset; persists across character switches (off→on cycle); zoom nodes patched for ranged |
| `gt dump_glossary`, `gt dump_cosmetics`, `gt dump_items_by_slot` | Data dump commands |

### chaos_wastes_tweaker (v0.2.1-dev)
| Feature | Notes |
|---|---|
| Coin pickup multiplier | Settings slider, applies on pickup |
| Starting coins | Applies at run init |
| Shrine boon count (1–5) | Arc layout stable |
| Chest boon count (1–5) | Items overflow background panel visually but no crash |
| Disable individual curses (14) | All confirmed |
| Weapon chest distribution | Custom upgrade/swap/power-up counts per chest |
| Trait filtering & banning | 20 individual trait bans + any-trait-any-weapon toggle |
| Force Belakor / dominant god | Finale controls |
| Pickup customization | Cursed chest count, arena ammo, campaign potions toggle |

### career_tweaker (v0.1.0-dev)
| Feature | Notes |
|---|---|
| Talent/ability swapping | 20 career dropdowns to swap talents from any career to another |
| Melee in ranged slot | Toggle to allow melee weapons in slot 2 |

**Animation rules (confirmed):**
- Any weapon with `to_1h_sword`, `to_1h_axe`, `to_1h_hammer`, `to_1h_flail`, `to_spear`, `to_polearm` works cross-career — all 6 skeletons have these.
- `to_dual_wield`, `to_2h_axe`, `to_1h_falchion` exist on NO skeleton — these weapon types cannot be wielded cross-career without animation grafting.
- Never put an event in a global redirect if it exists natively on ANY skeleton — use career-aware redirects instead.
- `player.player_unit` IS the 3P body. 1P arms are a separate first_person unit. Remapping `Unit.animation_event` on player_unit changes the 3P animation without affecting 1P arms. The `is_local` check in the remap is correct — do NOT change it to `not is_local`.
- 1P and 3P event names can differ — charge events often have swapped word order (e.g. `attack_swing_stab_charge` in 1P vs `attack_swing_charge_stab` in 3P). Remap tables must include BOTH variants to catch whichever name arrives on `player.player_unit`.
- `SimpleInventoryExtension.wield` hook must read the weapon template BEFORE calling `func()` — `func` fires the wield animation event internally, so reading after gives stale template → wrong remap on weapon switch.
- The game re-fires wield animation events (`to_polearm`, etc.) during push attacks, blocks, and other mid-combat actions. These use the REDIRECTED event name (e.g. `to_polearm`), not the original (e.g. `to_2h_billhook`). The remap clear logic must only reset on actual weapon switches (template change), not on re-wield. Otherwise push/block wipes the remap state mid-combat.
- `_current_weapon_template` can become nil during career ability or other non-weapon slot activations. The remap clear must guard against nil template to avoid false resets.
- Polearm charge event mapping on Kruber: `attack_swing_charge_right` = thrust windup, `attack_swing_charge` = overhead windup. Match charge events to the corresponding heavy release type (thrust or overhead).
- The billhook has a 3-light chain (stab → diagonal → stab → loop). `light_attack_bopp` is push follow-up, not L4. Weapons with 4+ lights need special handling for attacks beyond the billhook's chain length.
- When the remap table breaks the SM (e.g. `attack_swing_stab_02` → any target corrupts the entire chain), use `_original_animation_event` to force-fire the target event directly instead. This bypasses the hook/remap pipeline and works the same as `wt force3p`. The original event is suppressed (return early) and the forced event plays.
- Force-fire blocks must be scoped to the specific remap table they're designed for (e.g. `_3p_weapon_remap == _3p_remap_spear_to_billhook`). Without this guard, force-fires for one weapon (billhook) can hijack events on other weapons sharing the same event names.
- Bidirectional weapon pairs (e.g. spear+shield ↔ deus) need two remap tables — one per direction. Use career-prefix entries in `_3p_remap_triggers` to select the correct direction based on who is wielding.
- Billhook event names are visually inverted: `stab_charge` LOOKS like swing windup, `charge_left_diagonal` LOOKS like stab windup. Same for releases. When mapping charge→release pairs, matching visuals use opposite-named events.

---

## 🔬 Research — Cross-Skeleton Animation Grafting (CONCLUDED)

### Goal
Graft one character's 3P animations onto another skeleton so cross-character weapons play correct animations when no native equivalent exists (e.g. longbow on Saltzpyre — he has no bow weapon at all).

### Conclusion (2026-04-26)
**Not possible via the Stingray Lua API.** Every exposed animation API was tested. None allow adding individual animation events or clips to an existing 3P state machine at runtime. 3P state machines are baked into binary `.unit` files at compile time with no runtime modification path.

### What We Know
- **All 6 skeleton fingerprints probed** (2026-04-26) — see `reference_3p_skeleton_events.md` in memory for full table.
- Only 4 attack events differ across skeletons; all others are universal.
- Universal wield events: `to_spear`, `to_polearm`, `to_1h_sword`, `to_1h_hammer`, `to_1h_axe`, `to_1h_flail`
- Missing everywhere: `to_dual_wield`, `to_2h_axe`, `to_1h_falchion`
- Warrior Priest is the most stripped skeleton (only universal wilds + `to_2h_hammer`)
- Saltzpyre (non-Priest) is the richest (has `to_2h_billhook`, `to_2h_sword_we`, `to_bastard_sword` natively)

### Every Stingray Animation API Tested

| API | What it does | Result on 3P bodies |
|---|---|---|
| `Unit.set_animation_state_machine()` | Replace entire state machine | **CRASH** (C++ level, bypasses pcall). 3P SMs embedded in .unit files, no standalone resource path. |
| `Unit.set_animation_state_machine_blend_base_layer()` + 1P SM path | Blend a standalone SM onto base layer | No crash, but **skeleton collapses** — 1P bone hierarchy incompatible with 3P body. |
| `Unit.set_animation_state_machine_blend_base_layer()` + 3P unit path | Blend another character's 3P SM | **CRASH** — engine expects `.state_machine` resource type, 3P paths are `.unit` type. Pre-loading package doesn't help. |
| `Unit.set_animation_merge_options()` | AI breed animation blend weights | Not applicable — for AI locomotion blending, not event injection. |
| `Unit.animation_set_state()` | Force specific SM state index | States must already exist in target SM. Can't add new states. |
| `Unit.animation_get_state()` | Read current SM state index | Works (returns numeric index) but state indices are SM-specific, not transferable between units. |
| `Unit.animation_find_variable()` / `set_variable()` | Animation variables | Variables only — can't add events or clips. |
| `World.spawn_unit()` + probe | Spawn hidden 3P unit from another character | **WORKS** — can spawn, probe events, confirm state machine. But no API to copy animations from it. |
| Swap `Cosmetics[skin].third_person` at spawn | Redirect which .unit file the 3P body uses | Spawn works, target skeleton's events are gained, but **skin mesh crashes on bone mismatch** (`j_skirt` etc.) — skeletons have different bone sets per character. |
| Animation event redirects | Redirect missing events to existing ones | **WORKS** but limited to events already on the target skeleton. Cannot create new animation behaviors. |

### What This Means
- Cross-career weapons that have a reasonable animation equivalent on the target skeleton **work fine** via redirects (e.g. elf greatsword on Kruber -> bastard sword anims).
- Cross-career weapons with **no equivalent** on the target skeleton (e.g. longbow on Saltzpyre) **cannot be fixed** via Lua modding. The missing animations simply don't exist in the skeleton's state machine and there's no API to add them.
- The only theoretical path would be **offline binary editing of .unit files** to add states/events from one skeleton to another — far beyond Lua modding scope.

### Context
Some redirects work great and look BETTER than the original (Kruber using his own longbow anims for elf longbow). The existing redirect system handles the vast majority of cross-career weapons. The unfixable cases are limited to weapons with no equivalent category on the target character (bows on Saltzpyre/Bardin/Sienna, dual-wield on any character, etc.).

---

## 🔧 TODO

### Heavy Spear on Saltzpyre — Push Follow-up (weapon_tweaker)
- L1-L4 lights + H1-H2 heavies with charges all confirmed working (v0.9.55-dev).
- **Push follow-up** (`light_attack_bopp`): 1P=`attack_swing_heavy_left`. Not yet tested in 3P.

### Fix Inventory Access in Adventure Missions (general_tweaker)
- `mission_inventory_enabled` toggle added (v0.2.1-dev) but doesn't work yet.
- Patching `InventorySettings.inventory_loadout_access_supported_game_modes` alone is insufficient.
- Likely blocked by `game_mode:menu_access_allowed_in_state()` in `ingame_ui.lua` (~line 617).
- Needs investigation into all gates that prevent the inventory UI from opening mid-mission.

### Bretonnian Sword & Shield for Non-GK Kruber (weapon_tweaker)
- `es_sword_shield` has no `can_wield` field — `apply_weapon_unlocks` does nothing with it.
- From source: Template `one_handed_sword_shield_template_2`, wield_anim `to_1h_sword_shield_breton`.
- Need to find the correct item key.

### Chest of Trials Background Panel Clipping (chaos_wastes_tweaker)
- When boon count > 3, items extend beyond the background panel (visual only, no crash).
- Need to scale background node to match expanded arc.

---

## ❌ Known Broken — No Fix Yet

### Saltzpyre + Longbow: Wrong 3P Model + Attack Animations (weapon_tweaker)
- **Symptom:** Wield animation falls back to crossbow (working). But longbow model shows in 3P, aiming/shooting don't animate.
- **Root cause (model):** Crossbow `unit_3p` fields in `Weapons` are nil. Model comes from `ItemMasterList[item_key].right_hand_unit`. Hook `BackendUtils.get_item_units` to swap model.
- **Root cause (attack anims):** Driven by weapon action system (`CharacterStateHelper`), not `Unit.animation_event`. Very complex.
- **Blocked by:** Animation grafting research — Saltzpyre has no bow animations at all.

### BH Career Ability with Non-Native Ranged Weapons (career_tweaker)
- BH's ability uses `input_override = "action_career"` which only exists on native Saltzpyre weapons.
- Non-native ranged weapons lack `action_career` in their input map — button press silently ignored.
- Fix requires hooking `CharacterStateHelper` to inject `action_career` processing regardless of weapon.

### Talent Swap UI Not Updating (career_tweaker)
- `apply_talent_swaps()` mutates `TalentTrees` and `CareerSettings` but the talent picker UI doesn't refresh.
- Swapping a career whose ability is a weapon (e.g. GK blessed blade) to another career can crash (wrapped in pcall).

---

## 🗑️ Approaches Confirmed Dead (do not retry)

| Approach | Why |
|---|---|
| `Unit.set_animation_state_machine()` for 3P bodies | Crashes at C++ level. 3P state machines embedded in .unit files, no standalone resource path exists. |
| `Unit.set_animation_state_machine_blend_base_layer()` + 1P SM | No crash but skeleton collapses. 1P bone hierarchy incompatible with 3P body. |
| `Unit.set_animation_state_machine_blend_base_layer()` + 3P path | Crashes — engine expects `.state_machine` resource, 3P paths are `.unit` type. Pre-loading package doesn't help. |
| Swap `Cosmetics[skin].third_person` at spawn (skeleton swap) | Spawn works and events are gained, but skin mesh crashes on bone mismatch (`j_skirt` etc.). Skeletons have different bone sets per character. |
| `Unit.animation_set_state()` / `animation_get_state()` | States must exist in target SM. State indices are SM-specific, not transferable between units. |
| `Unit.set_animation_merge_options()` | AI breed locomotion blending only. Not applicable to player event injection. |
| Runtime animation grafting via any Stingray Lua API | **All APIs exhausted (2026-04-26).** No exposed API adds events/clips to an existing 3P state machine. |
| `wield_anim_career_3p` custom field | Game never reads this field. |
| `unit_template.unit_3p` swap in GearUtils hook | Always `nil` at hook time. |
| `_crossbow_3p_path` via Weapons global | All crossbow templates have `unit_3p = nil`. Model is in ItemMasterList. |
| Career-naive `_wield_anim_prefer` for events that exist natively on some skeletons | Redirects native careers away from their own correct animation. Must use career-aware redirects. |
| `first_person_mode_active` patching for TP camera | Only controls arm mesh visibility, not camera position. |
| 3P remap with `not is_local` condition | `player.player_unit` IS the 3P body. Using `not is_local` applies remap to wrong units (bots/enemies) and skips the actual 3P body. Must use `is_local`. |
| Firing remapped events on `_last_3p_unit` from 1P handler | `_last_3p_unit` is unreliable (could be any non-local unit). Suppressing 3P originals on non-local units breaks animations for bots/other players. |
| Clearing `_3p_weapon_remap` on every `to_` event unconditionally | Game re-fires wield events (`to_polearm`) during push/block/ability. The redirected name doesn't go through career redirect, so the remap never gets re-set. Must only clear on actual weapon template change. |
| Saving `original_can_wield` as `local` variables | On hot reload, locals reset to `{}`. The CURRENT (mod-modified) `can_wield` gets saved as "original", so restoring to "original" still includes mod additions. Weapons stay enabled even after toggling off. Fix: strip mod-managed careers directly from `can_wield` instead of save/restore. |
| Saving `original_can_wield` on `mod` object (persisted) | Persisting the corrupted originals across reloads makes it worse — the wrong baseline is permanent. Same root cause as above. |
| UI filter hook running AFTER `func()` in `_on_category_index_change` | `func` populates the item grid using the current (stale) filter. Cleaning up the filter after `func` only affects the NEXT call. Filter must be rebuilt BEFORE `func` runs. |
| `attack_swing_stab_02` in remap table (any target) | Adding `stab_02 → stab` or `stab_02 → left_diagonal` to `_3p_remap_spear_to_billhook` breaks ALL animations in the chain, not just L4. Cause unknown — possibly the billhook SM uses `stab_02` internally. Fix: use `_original_animation_event` force-fire instead of the remap table for this event. |
