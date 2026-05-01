# Cosmetics Tweaker — Feature To-Do

## In Progress
- [ ] **Independent offhand illusion swap** — second row of illusion buttons on the weapon customization screen for independently swapping left-hand (shield/offhand) models. Currently working: UI renders, button icons show rarity glow, scenegraph guards prevent crashes. Remaining: per-option rarity assignment, offhand selection persistence across sessions, hover/tooltip polish.

## Cosmetic Unlocks
- [ ] **Cosmetic unlocks** — enable cosmetics (hats, skins) across careers within the same character (no cross-character; skip wh_priest), like weapon_tweaker unlocks weapons by patching `can_wield`/item filters. **In progress in `cosmetics_tweaker` mod (Workshop 3715714222, private).** Started v0.2.0 with `cos probe_cosmetics` runtime probe to enumerate items + native career allow-lists; next pass populates static unlock maps and the nested settings UI.
- [ ] **Per-hat character portraits (future)** — when the cosmetic-unlocks UI is in, layer a portrait-override system on top: for every hat a character can wear, generate a matching character portrait via Photoshop + AI character-consistency tools so the lobby/HUD portrait swaps to match the equipped hat. Static asset pipeline (one portrait per hat × character), runtime side just patches the active portrait based on equipped hat.
- [ ] **Cross-character hat unlocks (investigation)** — figure out which hat→character combos are skeleton-compatible. Currently `cosmetics_tweaker` is intra-character only because cross-character would crash on skeleton-attachment-node mismatch (e.g. Kruber wearing Kerillian's hat). Some pairs may share enough headpiece rigging to work — needs per-pair empirical testing.

## Recolored / Cleaned Cosmetics
- [ ] **Cloned + recolored cosmetics ("matching hats")** — generate new hat/outfit variants by cloning an existing item with recolored textures so no vanilla matching combo is missing (concrete example: white GK hat to pair with the Purified Chaos Wastes outfit). Investigated 2026-04-28; pure-Lua color tinting is **not feasible** (VT2 hat shaders expose zero standard color/tint variables — probed 30 candidate parameter names, none matched; `Material.num_parameters`/`parameter_name` enumerator APIs hard-crash this build). Real path uses two existing community mods + asset-authoring work:
  - **Dependencies:**
    - [Material-Hijack](https://github.com/dalokraff/Material-Hijack) — hooks `GearUtils.create_equipment`, `UnitSpawner.spawn_local_unit`, `HeroPreviewer._spawn_item_unit`. When a unit's `.unit` file has data keys `mat_to_use`/`mat_slots`/`colors`/`normals`/`MABs`, calls `Material.set_texture(material, slot_name, "<our texture path>")` to swap. This is the only working runtime texture-replace API in this build.
    - [MoreItemsLibrary](https://steamcommunity.com/sharedfiles/filedetails/?id=1422758813) — registers new entries in `ItemMasterList` so a recolored variant shows up in inventory as a separate equippable item (used by Loremaster's Armoury for shield illusions).
  - **Per-cosmetic asset work (not Lua):**
    1. Custom `.unit` file in our mod referencing the existing mesh + adding the Material-Hijack data block (`mat_slots`, `colors = { ... = "our/path/white_albedo" }`).
    2. Recolored albedo DDS authored in Photoshop / GIMP (one per cosmetic), packaged via `.texture` + `.package` declarations.
    3. `MoreItemsLibrary.register_mod_item(clone_key, base_item, our_unit_path)` at mod load.
  - **Lua side (what `cosmetics_tweaker` would do):**
    1. Add Material-Hijack + MoreItemsLibrary as VMF dependencies.
    2. On boot, register the cloned ItemMasterList entry for each shipped recolor.
    3. Add unlock toggles per character (same pattern as the existing per-career hat unlock UI) so users can enable/disable individual recolored variants.
  - **Reference implementation:** [Loremaster's Armoury](https://github.com/dalokraff/Loremasters-Armoury) does exactly this for shield illusions and weapon skins.
- [ ] **Remove dirt/stains from "Purified" white outfits** — the Chaos Wastes "Purified" cosmetic skins (white recolors awarded from CW challenges) have visible dirt, grime, and stain overlays baked into their diffuse textures, making them look grimy rather than pristine. Goal: create cleaned versions with the dirt layer removed or replaced with a clean albedo.
  - **Loremaster's Armoury does NOT do this.** Repo cloned to `c:\Users\danjo\source\repos\Loremasters-Armoury` ([GitHub](https://github.com/dalokraff/Loremasters-Armoury)). It has "Clean" shield variants (custom heraldry shields without battle damage) and one `Purified` helm retexture (Kerillian HornOfKurnous), but does not touch character body/outfit textures for the vanilla Purified white skins at all.
  - **Approach — same pipeline as "Cloned + recolored cosmetics" item above:**
    1. Extract vanilla Purified outfit diffuse textures via `vt2_bundle_unpacker`.
    2. Edit in Photoshop/GIMP to remove the dirt/stain layer from the albedo (likely a multiply/overlay layer or painted directly — need to inspect the DDS to determine).
    3. Package cleaned diffuse as `.texture` + `.package` in cosmetics_tweaker.
    4. Create `.unit` files with Material-Hijack data keys (`mat_slots`, `colors`) pointing to the cleaned textures, referencing the original mesh.
    5. Register as new `ItemMasterList` entries via MoreItemsLibrary so they appear as separate equippable variants (e.g. "Purified (Clean)" alongside the vanilla "Purified").
    6. Add unlock toggles in cosmetics_tweaker settings UI.
  - **Dependencies:** Material-Hijack, MoreItemsLibrary (same as recolored cosmetics).
  - **Key reference:** Loremaster's Armoury `utils/funcs.lua` — `apply_new_skin_from_texture()` uses `Material.set_texture(mat, slot_hash, texture_resource)` with three slots: diffuse (`texture_map_c0ba2942` / `texture_map_64cc5eb8`), combined/MAB (`texture_map_0205ba86` / `texture_map_abb81538`), normal (`texture_map_59cd86b9` / `texture_map_861dbfdc`). Armor uses the second set of hashes.
  - **Open questions:**
    - Which characters have Purified outfits? Need to enumerate via `cos probe_cosmetics` or search `ItemMasterList` for "purified" skin keys.
    - Is the dirt painted directly into the diffuse, or is it a separate texture channel (e.g. combined/MAB map)? Inspect extracted DDS to determine editing strategy.
    - Can we swap just the diffuse and leave normal/combined unchanged, or does the dirt appear in multiple maps?

## Illusions & Icons
- [ ] **Custom illusion icons** — all custom illusions (`ct_es_mace_gk_shield_01`, `ct_we_spear_shield_es_*`, `ct_es_deus_we_*`, `ct_es_heavy_spear_deus_*`) use placeholder generic icons (`weapon_generic_icon_staff_3` / `icon_wpn_empire_shield_01_t1_mace`). Need to extract vanilla weapon icons from the game to understand the format/resolution, then create unique icons for each custom illusion. Investigate how icons are referenced (`hud_icon` vs `inventory_icon`), what atlas they live in, and whether runtime injection of new icon textures is possible or if we need to reuse existing icon keys.
- [ ] **Free weapon illusion/skin swap from inventory** — let the inventory menu pick any illusion/skin available to the weapon type without going through Okri's "apply illusion" flow (and without consuming a one-time illusion). Show all illusions for that weapon as selectable options inline on the weapon card.

## Glow Maps
- [ ] **Glow map control for weapon illusions** — VT2 weapons have two distinct glow systems, both controlled via `material_settings_name` on weapon skins (NOT automatic by rarity):
  - **Type 1: Rune/emissive glow** — per-skin named templates in `weapon_material_settings_templates.lua`. Uses `rune_emissive_color` (vector3 RGB, values >1 for HDR bloom). Predefined templates: `"purple_glow"` ({3,1,9}), `"golden_glow"` ({8,5,1.5}), `"deep_crimson"` ({7,0,0.1}), `"life_green"` ({7,9,0.1}), `"lileath"` ({5.8,6.3,9}).
  - **Type 2: Weave-forged (Winds of Magic)** — `rarity = "magic"` skins in `weapon_skins_lake.lua`. Cyan/turquoise glow ({0,211,178}). Also uses `material_settings_name` — just a different template.
  - **Application path:** `GearUtils.apply_material_settings()` (gear_utils.lua:107-152) loops through `MaterialSettingsTemplates[name]` and calls `Unit.set_vector3_for_materials()` / `Unit.set_color_for_materials()` / `Unit.set_scalar_for_materials()`. Also applied via `PlayerUnitCosmeticExtension.change_skin_material_settings()` for 1P/3P.
  - **UI rarity glow colors** (in `hero_view_state_loot.lua` `glow_rarity_colors` table) are loot-chest-presentation-only, NOT applied to 3D weapon models.
  - **Goal:** Add an RGB color picker widget and enable/disable toggle on the weapon customization screen. At runtime, call `Unit.set_vector3_for_materials(unit, "rune_emissive_color", Vector3(r, g, b))` on the spawned weapon unit to apply custom glow. Need to hook all three render paths (in-game, inventory preview, illusion browser). Also add a dropdown to select from predefined glow presets (purple, gold, crimson, green, lileath, weave) or "Custom RGB".
  - **Versus glow** uses additional params: `color_glow_high`, `color_glow_low`, `color_smoke_high`, `color_smoke_low`, `color_dots` — potentially useful for more dramatic effects.

## Other
- [ ] **3rd person mod** — enable 3rd person camera view so players can see their character model and cosmetics in gameplay
