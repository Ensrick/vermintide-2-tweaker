# Crafting in Modded — To-Do

## Import items from "SaveWeapon" mod

Add a chat command + VMF settings-menu button that imports every weapon the
player previously saved with the **SaveWeapon** mod (workshop ID `1687843693`,
internal mod-id `SaveWeapon`, source at `<workshop>\1687843693\source\scripts\mods\SaveWeapon\SaveWeapon.lua`)
into cim's modded inventory. Each imported item lands in `_forged_weapons` (so
it survives a restart via `_athanor_inject_all`) with `rarity = "modded"`,
properties/traits/skin preserved from the SaveWeapon entry.

### UX
* `/cim_import_saved_weapons` — runs the import, echoes a count
* VMF settings group "Import" → button widget calling the same helper

### Source schema (verified from SaveWeapon.lua)

SaveWeapon persists via VMF: `get_mod("SaveWeapon"):get("saved_items")` returns
a dict where:

* **Key** (`save_id`) — `<item_key>_<numeric_id>` (e.g. `es_1h_mace_21932`).
  Strip the trailing `_<digits>` to recover the vanilla `ItemMasterList` key.
* **Value** (`savestring`) — slash-separated:
  - `[1]` favorite flag (`"true"` / `"false"`)
  - `[2]` skin key, or `"nil"` for default
  - `[3]` trait key
  - `[4..N]` property keys (typically 2; theoretically up to N)

  Property values aren't stored — SaveWeapon writes them at fixed `1.0` (max)
  during recreation (SaveWeapon.lua:561-564). Match that on import.

  Example savestring: `"true/es_1h_mace_skin_02/parry/attack_speed/crit_chance"`

### Recreation reference

SaveWeapon's `create_saved_item` (SaveWeapon.lua:545-662) is the canonical
re-creator. It builds an entry with `rarity = mod:get("displayed_rarity")`,
`power_level = 300`, properties = `{[prop_key] = 1, ...}`, traits as an array,
and hands it to `MoreItemsLibrary:add_mod_items_to_local_backend`. For cim we
skip MIL and use `_athanor_inject_item` / `_cim_register_craft` instead so the
items go through cim's standard `via_mirror = true` persistence path.

### Translation map (SaveWeapon → cim `_forged_weapons` entry)
| SaveWeapon field | cim field |
|---|---|
| `<item_key>` (parsed from save_id) | `weapon_data.item_key` |
| `savestring[3]` (trait) | `weapon_data.traits = { trait }`, `weapon_data.trait = trait` |
| `savestring[4..N]` (properties) | `weapon_data.properties = { [k] = 1.0, ... }` |
| `savestring[2]` (skin) or nil | `weapon_data.skin = skin or nil` |
| (fixed) | `weapon_data.power_level = 300` |
| (fixed) | `weapon_data.rarity = "modded"` |
| (fixed) | `weapon_data.via_mirror = true` |

Generate a fresh `Application.guid()` per import — don't reuse SaveWeapon's
backend_id (theirs has the `_from_GiveWeapon` suffix and is a MoreItemsLibrary
key, not compatible with cim's backend_mirror UUID format).

### Implementation gates / open questions
* **DLC gate.** Skip items whose `item_key` requires DLC the user doesn't own
  — use the existing `_item_requires_unowned_dlc` helper in `standard_forge.lua`.
* **Property value normalization.** SaveWeapon writes every property at 1.0.
  v0.7.14 introduced per-property bubble caps (stamina cap = 2 → max value 1.0,
  movespeed cap = 1 → max value 1.0). At 1.0 both caps land at "max bubbles"
  so this is actually fine without renormalization, but document explicitly so
  future-cim doesn't break the import when more caps are added.
* **Idempotency.** Dedupe by `(item_key, sorted(properties), sorted(traits), skin)`
  triple before inserting. If the user runs the import twice, the second pass
  should be a no-op (echo "N already imported, 0 new").
* **`item_key` parsing.** SaveWeapon's `get_item_name_from_save_id`
  (SaveWeapon_utilities.lua) handles the special cases (Bretonnian sword
  vs. regular sword, volley crossbow vs. crossbow). Reuse that function via
  `get_mod("SaveWeapon"):get_item_name_from_save_id(save_id)` instead of
  reinventing the parsing — the v1.2.5 changelog explicitly mentions this is a
  pitfall area.
* **Trait/property validity check.** Some SaveWeapon entries might reference
  trait/property keys that aren't in the item's `trait_table_name` /
  `property_table_name`. Validate against `WeaponTraits.combinations[...]` and
  `WeaponProperties.combinations[...]` before accepting; on mismatch, drop the
  invalid trait/property and echo a warning (don't refuse the whole item).
* **Favorite flag** (`savestring[1]`). Currently ignored — cim doesn't yet have
  a favorite-marker system. Document the field but pass-through nil.
* **No-skin case.** When `savestring[2] == "nil"`, leave `weapon_data.skin = nil`.
  cim's existing item-render code handles nil-skin (uses default appearance).
* **No mod-installed check.** If `get_mod("SaveWeapon")` is nil, the chat
  command and VMF button should echo "SaveWeapon mod not installed — nothing to
  import" instead of crashing.
