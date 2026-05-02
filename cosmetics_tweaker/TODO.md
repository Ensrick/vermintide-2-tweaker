# Cosmetics Tweaker — Feature To-Do

## Open investigation
- [ ] **`unlock_all_frames` toggle reported broken** (user, 2026-05-02). Hook lives at `cosmetics_tweaker.lua:1550-1561`:
  ```lua
  mod:hook_safe("PlayFabMirrorBase", "get_unlocked_cosmetics", function(self)
      if not mod:get("unlock_all_frames") or not script_data["eac-untrusted"] then return end
      local cosmetics = self._unlocked_cosmetics
      if not cosmetics then return end
      for key, data in pairs(ItemMasterList) do
          if data.item_type == "frame" and not cosmetics[key] then
              if not _skin_requires_unowned_dlc(key) then
                  cosmetics[key] = true
              end
          end
      end
  end)
  ```
  Setting registered correctly in `cosmetics_tweaker_data.lua:18` and `_localization.lua:18`. Code path traced and looks correct on paper:
  - `playfab_mirror_base.lua:1470` calls `self:get_unlocked_cosmetics()` → returns `self._unlocked_cosmetics` (table reference).
  - VMF `hook_safe` fires after the original returns and mutates `self._unlocked_cosmetics` in place. Local `unlocked_cosmetics` shares the reference, so mutations are visible.
  - `playfab_mirror_base.lua:1479` passes the (now-mutated) table to `_create_fake_inventory_items(cosmetics)`. That generates fake `_inventory_items` + `_fake_inventory_items` entries with new GUIDs.
  - `BackendInterfaceItemPlayfab._refresh_items` later refreshes `self._items` from `_inventory_items` — fakes survive.
  - UI filter chain: `available_in_current_mechanism` (passes — frames are cosmetic), `can_wield_by_current_hero` (passes — IML frames have `can_wield = CanWieldAllItemTemplates`), `slot_type == frame` (passes).
  - DLC gate (`_skin_requires_unowned_dlc`) defined at `cosmetics_tweaker.lua:37` — uses `rawget` and `Managers.unlock:is_dlc_unlocked`, fine.
  - `unlock_all_illusions` uses a different hook target (`BackendInterfaceCraftingPlayfab.get_unlocked_weapon_skins`) — fires every time the illusion UI opens, so toggling at runtime works there. `unlock_all_frames` depends on `_create_fake_inventory_items` which only runs once at PlayFab login, so toggling at runtime does NOTHING without a full restart. CHANGELOG v0.7.0-dev: "Requires restart after toggling."
  - Deployed bundles at `C:\Program Files (x86)\Steam\steamapps\workshop\content\552500\3715714222` match `bundleV2/` build output (timestamps 2026-05-01 22:16) — not a stale-deploy issue.

  **Most likely failure modes (need user repro detail):**
  1. User toggled at runtime without full game restart (Ctrl+Shift+R won't pick it up — cosmetics_tweaker is in the hot-reload-unsafe list).
  2. User in Official realm — `script_data["eac-untrusted"]` early return swallows the hook.
  3. Mod-load ordering — cosmetics_tweaker loads after PlayFab mirror init for the first call. Subsequent `get_unlocked_cosmetics` calls re-fire but `_create_fake_inventory_items` doesn't re-run, so no fake items get made.

  **Next-session checklist before changing code:**
  1. Confirm with user: full restart? In modded realm? What does the Frames inventory tab actually show (empty / vanilla-only / partial)?
  2. If user confirms restart + modded but still broken: add a one-line `mod:info` at top of the hook to verify it's firing, and at bottom to log how many keys were added. Repro and read `Console.log`.
  3. If hook fires but frames don't appear: walk forward — log `_unlocked_cosmetics` size, `_inventory_items` size after init, `get_filtered_items` result for the frames category. The issue is downstream of the hook.
  4. If failure mode 3 (mod-load ordering): switch hook target to something the cosmetics inventory UI calls every time it opens (analogous to how `unlock_all_illusions` works), or call `_create_fake_inventory_items` ourselves on first frame after init when the toggle is on.
  5. Consider making the toggle work without restart by re-running `_create_fake_inventory_items({"cosmetics"})` on `on_setting_changed("unlock_all_frames")` — but verify it doesn't break vanilla cosmetics that already have fake IDs assigned.

- [ ] **Decode crash unit hash `9405eeb80a227a76` and re-enable LA Imperial Hero mesh swap.** Crashed `World.spawn_unit` consistently across v0.7.81–v0.7.85 when the user clicked an Imperial LA shield (e.g. `Kruber_empire_shield_hero1_Ostermark01`, `_Kotbs01`) on a Bret sword + shield in the customization menu. Workaround in v0.7.86: `_la_bridge._resolve_intended_unit` always returns `nil`, so LA textures paint onto the user's current shield mesh — Imperial LA UVs land on Bret GK shields imperfectly but it doesn't crash. **Diagnostic build (v0.7.92-dev)** added a `[SPAWN_TRACE]` hook on `World.spawn_unit` and re-enabled the mesh swap to capture the failing unit name in `Console.log`. **Next step:** ask user to repro on v0.7.92, share the last 10–20 `[SPAWN_TRACE]` lines around the crash. The actual unit name (decoded from the hash) will tell us whether to:
  - preload the resource_package that contains the failing unit (likely some weapons-bundle, NOT `wastes_common` as v0.7.85 assumed), or
  - filter affected LA variants out of the picker pool when their packages aren't engine-resident, or
  - swap to a different reliably-loaded shield mesh that's UV-compatible.
- [ ] Once the diagnostic data lands and the fix is in, **remove the `[SPAWN_TRACE]` hook and the `cos spawn_trace_reset` command** from `cosmetics_tweaker.lua` (the diagnostic block is clearly marked `TEMP DIAGNOSTIC`).
- [ ] Notes from prior investigation (don't redo):
  - `Application.can_get("unit", path)` returned **true** for the failing unit but `World.spawn_unit` still asserted. So `can_get` checks resource registry availability, NOT spawn-readiness.
  - LA's bootstrap loads `resource_packages/levels/dlcs/morris/wastes_common` and four similar globals at LA mod init. The deus shield 3p variants don't appear to be reliably available in keep contexts — LA's normal flow assumes the user has a CW Bret weapon equipped (which loads them via the loadout chain).
  - `Managers.package:load("units/.../wpn_es_deus_shield_03", ...)` on a non-existent standalone package writes `self._packages[path]` anyway (Application.resource_package returns a handle regardless), so `has_loaded` lied. v0.7.85 switched the gate to `can_get("unit", ...)`, which fixed the phantom-load issue but not the underlying spawn failure.

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
