# Athanor Amulet (Adventure-Mode Jewellery & Talent Editor)

## Goal

Repurpose the central viewport of the B-hotkey Athanor (the Amulet-of-Ashur slot, currently hidden) into a unified editor for the player's three adventure-mode accessories (**necklace**, **charm**, **trinket**) plus their adventure-mode **talents**.

Modeled on Winds of Magic's Amulet of Ashur, which combines all three accessory slots into one editor for weave runs. Our version is for campaign play.

## Workflow

Player presses **B** in the Keep → Athanor opens with the central viewport now active → click viewport → sub-window opens with three subsections (necklace, charm, trinket) plus a talent row → edit bubbles / pick trait / pick talents → press **Apply**, **Craft**, or back out.

### Apply button

Mutates the **currently equipped** necklace / charm / trinket items in-place via the local backend mirror. Same pattern as the existing weapon-edit Athanor flow:

- Commit-blocked, so changes never reach PlayFab → reverts on game restart for vanilla items.
- For modded crafted items (`_forged_weapons`), changes also write through to the save layer so they survive restart.
- Greyed out / unavailable when **any** of the three equipped jewellery items is non-modded (vanilla or blacksmith template). Rationale: applying changes to a vanilla item is a session-only illusion; the user should `Craft` instead.
- Only modifies items whose subsection the user actually edited this session.

### Craft button

Creates new modded items (`promo` rarity) for slots whose subsection was edited, equips them, persists them in `_forged_weapons`. Slots not edited keep their existing items.

Examples:
- User edits trinket only → new modded trinket crafted + equipped, necklace and charm untouched.
- User edits all three → three new modded items.
- User edits nothing → Craft is a no-op (button could be greyed).

Available even when the equipped items are non-modded (blacksmith templates / vanilla).

### Default (back out without Apply or Craft)

No changes applied. Edits discarded.

## UI shape: three subsections

The sub-window stacks three subsections vertically (or in tabs if vertical space is tight):

| Subsection | Property pool | Trait pool | Slots (bubbles) |
|---|---|---|---|
| **Necklace** | `WeaponProperties.combinations.defence_accessory` | `WeaponTraits.combinations.defence_accessory` | 3 (matches vanilla necklace property count) |
| **Charm** | `WeaponProperties.combinations.offence_accessory` | `WeaponTraits.combinations.offence_accessory` | 2 |
| **Trinket** | `WeaponProperties.combinations.utility_accessory` | `WeaponTraits.combinations.utility_accessory` | 2 |

Each subsection has its own bubble grid, its own trait dropdown/picker, and its own dirty-state flag (`_dirty_necklace`, `_dirty_charm`, `_dirty_trinket`).

Bubble grid mechanics match the existing weapon editor: click a property → fill that property's bubbles up to its slot count → can mix and match across the available property pool, exactly like WoM weapons are allowed to in this UI.

### Initial population

On sub-window enter, read the player's current equipped necklace / charm / trinket via `backend_items:get_loadout_item_id(career_name, slot_name)`. Pre-fill each subsection's bubble grid + trait selector with the corresponding item's existing properties and traits. If the item is a default-rarity blacksmith template, the subsection starts empty.

## Talent row

Reuses the Athanor's existing weave-talent UI structure. Adventure-mode career talents are 6 rows × 3 picks; the existing UI may need to scale to accommodate.

**Persistence**: write-through to the vanilla `BackendInterfaceTalents`. Picks made here become the player's actual adventure career talents (no separate cim save layer). career_tweaker can still rewrite the *available* talent list above this layer; no conflict.

## Backend hooks

- `BackendInterfaceWeavesPlayFab.get_loadout_item_id` — already hooked. Extend the slot mapping so `slot_necklace`, `slot_charm`, `slot_trinket` resolve via the items interface (same as melee/ranged) when the amulet sub-window is open.
- `BackendInterfaceWeavesPlayFab.get_loadout_properties` / `get_loadout_traits` — extend `_forge_seed_item` to map the right WeaponProperties/WeaponTraits pool per slot type.
- `BackendInterfaceWeavesPlayFab.set_loadout_property` / `remove_loadout_property` / `set_loadout_trait` / `remove_loadout_trait` — already wired into `_forge_apply_to_item`; extend to mark the relevant subsection as dirty.

## Edge cases

- **Player has no jewellery equipped**: shouldn't happen — the player always has at least the blacksmith template. If somehow nil, treat the subsection as empty + craftable (Apply unavailable).
- **CWV jewellery items**: covered as modded (cwv_* prefix), Apply works on them.
- **Property exists in multiple pools**: e.g. `crit_chance` is in both melee combinations and accessory combinations. Resolved by the subsection: clicking the bubble in the necklace subsection only ever affects the necklace.
- **Switching career mid-edit**: discards in-progress edits (consistent with vanilla forge behavior).

## Implementation phases

**Phase A** — accessories editor:
1. Un-hide `viewport_2` / `viewport_button_2` / `viewport_button_highlight_2` widgets in `_forge_apply_ui_polish`.
2. Wire viewport_2 click to enter a new sub-window (or repurpose the existing weave Properties window with three subsections injected).
3. Build the three subsections (bubble grids + trait pickers) seeded from current equipped items.
4. Per-subsection dirty flags.
5. Apply button (greyed-out logic).
6. Craft button (per-dirty-slot synthesis via `mirror:add_item` + `_cim_register_craft`).
7. Equip newly crafted items via `backend_items:set_loadout_item`.

**Phase B** — talents:
1. Talent row in the same sub-window.
2. Read current adventure talent picks from `BackendInterfaceTalents`.
3. Write picks through to `BackendInterfaceTalents:set_talent` on selection.
4. UI scale-up to 6 rows × 3 picks if needed.

## Open questions

None as of 2026-05-08 — design confirmed with user. Phase A starts next.
