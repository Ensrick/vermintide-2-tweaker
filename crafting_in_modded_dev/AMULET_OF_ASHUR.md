# Athanor Amulet (Adventure-Mode Jewellery & Talent Editor)

## Goal

Repurpose the central viewport of the B-hotkey Athanor (the Amulet-of-Ashur slot) into a unified editor for the player's three adventure-mode accessories (**necklace**, **charm**, **trinket**) plus their adventure-mode **talents**.

Modeled on Winds of Magic's Amulet of Ashur, which combines all three accessory slots into one editor for weave runs. Our version is for campaign play.

## Status (as of 2026-05-10)

| Feature | State |
|---|---|
| Amulet viewport visible | ✅ |
| Click → 3-section editor opens | ✅ (vanilla `amulet_slot_layout` renders automatically when `selected_item == nil`) |
| Bubble grid pre-populates from current accessories | ✅ |
| Bubble edits auto-apply to equipped items | ✅ (session-only for vanilla, persisted for modded) |
| Talent picker shows current adventure picks | ✅ |
| Talent changes write through to vanilla career talents | ✅ |
| CRAFT button — make new modded items only for edited slots | ✅ |

## Big architectural insight

`HeroWindowWeaveProperties.on_enter` (`hero_window_weave_properties.lua:167-196`) auto-selects between two pre-built layouts based on `_selected_item()`:

| selected_item | Layout used | Bubbles |
|---|---|---|
| **non-nil** (a weapon) | `weapon_slot_layout` | 1 trait + 10 properties |
| **nil** (the amulet) | `amulet_slot_layout` | 3 traits + 30 properties (3 layers) + 6 talents |

The amulet viewport's `data.item` is naturally nil (vanilla never puts an item there), so a click flows through to `weave_properties` with `selected_item = nil` and the WoM-style 3-section UI renders automatically. **We don't override the click anymore** — letting vanilla handle it gives us the right UI for free.

## Slot order (do not change)

`WeaveCareerProgression` (`weave_loadout_settings.lua:282-295`) hardcodes the slot order by accessory pool:

| Amulet slot index | Pool | Adventure slot name | Display name |
|---|---|---|---|
| 1 | `offence_accessory` | `slot_ring` | Charm |
| 2 | `defence_accessory` | `slot_necklace` | Necklace |
| 3 | `utility_accessory` | `slot_trinket_1` | Trinket |

The picker reads its `category` field per slot from `WeaveCareerProgression`. If we feed slot 1 with necklace data, the picker for slot 1 still renders offence_accessory options — visible mismatch. **Both seed and apply iterate `_AMULET_SLOT_BY_INDEX` so we stay aligned.**

VT2's `career_settings` uses legacy slot names: `slot_ring` (not `slot_charm`) and `slot_trinket_1` (not `slot_trinket`). Using the wrong names returns `nil` from `get_loadout_item_id`.

## Workflow

Player presses **B** → Athanor opens with the central amulet viewport visible → click amulet → vanilla's `weave_properties` window opens with the 3-section amulet layout → bubbles + traits pre-filled with current accessory state, talent slots show current career picks → player edits.

### Edits auto-apply on each bubble click

`_forge_apply_to_amulet` runs on every property/trait set/remove. It groups bubble fills by layer, computes per-accessory property values, and writes to the equipped item's `item.properties` / `item.traits` in the local mirror. Modded saved crafts also flush to `_forged_weapons`. Talent picks write through to `BackendInterfaceTalentsPlayfab:set_talents`.

This means there is **no separate Apply button** — every bubble click already applies. For modded crafts, the changes persist via the save layer. For vanilla items, they revert on game restart (commit-blocked).

### CRAFT button (repurposed `upgrade_button`)

Hijacks `HeroWindowWeaveProperties._upgrade_magic_level`. In the amulet case (no `selected_item`), iterates the three accessory slots and creates a new modded item for each whose bubbles were edited this session. Per-slot dirty tracking lives in `_amulet_dirty = { false, false, false }` — set by hooks on `set_loadout_property` / `remove_loadout_property` / `set_loadout_trait` / `remove_loadout_trait` whenever they fire with `item_backend_id == nil` (the amulet case).

Workflow:

1. Player edits charm bubbles only → `_amulet_dirty[1] = true`. Necklace and trinket flags stay false.
2. Player presses CRAFT.
3. Loop iterates slots 1..3. Only slot 1 is dirty.
4. We read the equipped charm's current `properties` / `traits` (already mutated by auto-apply).
5. Create a new modded item with those values, `rarity = promo`, fresh `Application.guid()` backend_id.
6. Persist via `mod._cim_register_craft`.
7. `set_loadout_item(new_bid, career, "slot_ring")` — equips it.
8. `_amulet_dirty[1] = false` — slot now clean.

If no slot is dirty, CRAFT echoes "No accessory edits to craft" and does nothing. Pressing CRAFT with all-vanilla equipped accessories that the player edited produces three new modded items. Pressing it after editing only the trinket produces only a new trinket.

`_amulet_dirty` is reset in `HeroViewStateWeaveForge.on_exit`, so closing the forge starts the next session fresh.

## Talent integration

The amulet's talent picker runs against the WoM weave talent system, but `WeaveLoadoutSettings[career].talent_tree = TalentTrees[profile][talent_tree_index]` (literally — see `weave_loadout_settings_*.lua`). The talents the player sees in the picker ARE the same 6 rows × 3 columns as adventure mode.

Three hooks wire read/write:

- `get_loadout_talents(career)`: reads adventure picks via `Managers.backend:get_interface("talents"):get_talents(career)` (`{1, 3, 2, 1, 3, 2}` style — column choice per row), maps each row's pick to its talent name via `TalentTrees[profile][index][row][pick]`, returns `{[talent_name] = row}` — the format the bubble grid expects.
- `set_loadout_talent(career, talent_name, row)`: finds which column in that row owns `talent_name`, calls `talents:set_talents(career, picks)` with the updated array. **Write-through to vanilla** — the player's actual career talents change immediately and persist through the regular adventure save layer.
- `remove_loadout_talent`: no-op. The bubble grid emits remove→set pairs on each swap, but adventure rows always have one talent active so we just commit the new pick directly in set.

## Data flow summary

**Read (forge open)**:

```
HeroWindowWeaveProperties.on_enter
  → _selected_item() == nil → amulet_slot_layout
  → _setup_menu_options reads WeaveCareerProgression for slot category metadata
  → _sync_backend_loadout calls our hooks:
      get_loadout_properties(career, nil) → _forge_seed_item → reads 3 accessory items
      get_loadout_traits(career, nil)     → _forge_seed_item → same
      get_loadout_talents(career)         → reads BackendInterfaceTalentsPlayfab
```

**Write (each bubble / trait / talent click)**:

```
set_loadout_property(career, prop, slot, nil) → mark_amulet_property_dirty(slot)
                                              → _forge_apply_to_amulet
set_loadout_trait(career, trait, slot, nil)   → mark_amulet_trait_dirty(slot)
                                              → _forge_apply_to_amulet
set_loadout_talent(career, talent, row)       → BackendInterfaceTalentsPlayfab:set_talents
```

**Write (CRAFT button)**:

```
HeroWindowWeaveProperties._upgrade_magic_level
  → _selected_item() == nil → amulet branch
  → for each dirty slot: clone equipped item's state into new modded item, equip
```

## Resolved

- **✅ Accessory craft buttons — click/hover feedback + sound (v0.8.39-dev, 2026-07-01).** The three overlay buttons (CRAFT NECKLACE / CHARM / TRINKET) now flash a pressed colour while held, brighten on hover, play `Play_hud_hover` on hover-enter and `Play_hud_select` on release. Sound routes through the host window's own vanilla `_play_sound` (`HeroWindowWeaveProperties:_play_sound → self._parent:play_sound`), NOT a `music_world` wwise_world (that world is unregistered in the weave-forge UI context — the old path silently no-op'd, `has_music=false`). User-confirmed working in-game. See `_accessory_craft_panel.lua` and memory `reference_vt2_ui_button_sound_use_window_play_sound`.

## Open work

- The CRAFT button text doesn't currently re-label when entering the amulet from the standard weapon path (still says "CRAFT NEW WEAPON" for melee/ranged, "CRAFT" generic for amulet). Could be polished to read "CRAFT NEW JEWELLERY" or per-dirty-slot summary.
- Apply button greying when any equipped accessory is non-modded — moot in current design because there's no Apply button (auto-apply on click), but worth surfacing the implicit "vanilla accessory edits don't persist past restart" UX hint.
- Dirty tracking is conservative: any edit (including reverting a bubble back to its initial state) marks the slot dirty. CRAFT will then make a "duplicate" new item even though no net change happened. Acceptable — over-crafting is harmless.
