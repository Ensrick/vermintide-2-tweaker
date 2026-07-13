# crafting_in_modded_dev - engine contact surface

What vanilla VT2/Stingray does at every seam `cim_dev` touches, and why the mod is
there. This is the per-mod companion to the subsystem set in `docs/engine/`
(read `docs/engine/README.md` for house style). It does **not** re-explain a
subsystem the engine docs own - it names the seam, cites the vanilla behavior,
and links out. Decompile paths are relative to
`C:\Users\danjo\source\repos\Vermintide-2-Source-Code`; `cim` line numbers are in
the named `crafting_in_modded_dev/scripts/mods/crafting_in_modded_dev/*.lua`
module. `§N` = a `docs/BUG_CLASSES.md` class; `#N` / "issue N" = a GitHub issue.

**Dev/stable relationship.** This documents `crafting_in_modded_dev` (`cim_dev`,
MOD_VERSION `0.8.54-dev`, friends-only Workshop 3733366851), the ACTIVE working
stream. `crafting_in_modded/` (`cim`, public Workshop 3721038774) is its read-only
public twin; per repo `CLAUDE.md` all in-flight work happens in the dev dir and
promotion is a separate user-triggered action (`tools/promote/promote.ps1`), so
this doc cites only `cim_dev` line numbers. Every module resolves `get_mod("cim_dev")`,
so any cross-mod consumer resolving `get_mod("cim")` will NOT see the dev clone.
cim's own render-rescue for CWV crafts, by contrast, keys on the `cwv_` backend_id
prefix, which is stream-agnostic.

**Verification split (honest).** Line-verified against the 2026-07-12 `cim_dev`
module source: every hook signature (grep-confirmed, **107 `mod:hook`/`hook_safe`
sites + 1 `mod:network_register`**), the full body of `standard_forge.lua`,
`illusion_swap.lua`, `modded_rarities.lua`, and the main-file craft-record shape
(`:282-582`), wire-safety core (`:753-903`), LA equip-capture (`:1543-1576`),
item-filter (`:1701-1818`), and Athanor opener + shading-env substitution
(`:1825-2055`, `:3088-3218`). The `[src:]` citations INTO the decompile
(`loadout_utils.lua`, `network_lookup.lua`, `backend_utils.lua`,
`hero_window_item_customization.lua`, `craft_page_*`, `world_hero_previewer.lua`,
etc.) are carried from the cited `cim_dev` module comments + `CHANGELOG.md` +
`docs/BUG_CLASSES.md` + the line-verified sibling `character_weapon_variants` and
`cosmetics_tweaker` `ENGINE_SURFACE.md` docs, which cite the decompile in turn.

**Module split (v0.8.55-dev, Phase 1 OOP).** Three concerns were lifted verbatim out
of the entry into `_cim_*` modules (see `DEVELOPMENT.md` module map): the inventory/
salvage grid filters -> **`_cim_inventory_filter.lua`**; every mid-mission render-safety
guard (shading-env, HDR, glow/skilltree/bloom/upgrade-anim suppressors, gamepad/HDR
renderer guards) -> **`_cim_mission_forge_safety.lua`**; the read-only dump commands ->
`_cim_dump_commands.lua`. Rows below cite the module file (name only) for moved hooks;
everything else still lives in `crafting_in_modded_dev.lua`. Match crash logs by function
name, not line - the module line numbers are fresh.

`cim` is a **UI-heavy backend mod**: it makes the vanilla Keep crafting benches
work in the modded realm (where the player has no crafting materials and the EAC
anti-tamper path is dead), synthesizes crafted items locally into the backend
mirror, and repurposes the entire vanilla **weave forge** (the Athanor) as a
second, richer crafting surface. Its engine contact clusters into the five
surfaces below.

## Hook table

**107 hook sites** (`mod:hook`/`mod:hook_safe`) + **1 VMF RPC channel**
(`mod:network_register("cim_modded_slot")`) + a set of engine-**table** contacts
(rarity registration, template-cache injection - see Surface 1/5 notes). Grouped
below into rows-of-concern. `[hook]` = full wrapper (`mod:hook`, can rewrite
args/returns); `[safe]` = `mod:hook_safe` (post-callback, no override); `[tbl]` =
table-form hook against a plain-table target (nil-guarded); `[rpc]` =
`mod:network_register`. Where a `(Class, method)` carries multiple concerns they
are **consolidated** into one hook body - VMF silently drops a second hook on the
same pair from the same mod (repo `CLAUDE.md` non-negotiable 8; §1), flagged in
the trap column.

### Surface 1 - Standard crafting bench: material-clean craft/salvage/reroll + backend mirror (owner: `docs/engine/11`, `/09`; `standard_forge.lua`, `crafting_in_modded_dev.lua`)

| Class.method (kind) | Vanilla behavior at the seam | Why cim hooks it | Trap / invariant |
|---|---|---|---|
| `BackendInterfaceCraftingPlayfab.craft` [hook] `standard_forge.lua:1446` | Enqueues an `ExecuteCloudScript` PlayFab request with `send_eac_challenge=true`; recipe resolved via `_get_valid_recipe` [src: `backend_interface_crafting_playfab.lua`, queue at `playfab_request_queue.lua:44`] | THE choke point: short-circuit PlayFab, dispatch to a local `synth[recipe.name]`, write results into the backend mirror | CONSOLIDATED (illusion-apply intercept runs FIRST, then `_is_active` gate). NEVER fall through to `func` in modded realm - it triggers the EAC kick (reason 511). Must return a non-nil `(id, recipe)` even on silent-drop or the press-and-hold refires every frame (log spam) |
| `BackendInterfaceCraftingPlayfab._get_valid_recipe` [hook] `standard_forge.lua:433` | Validates recipe + material ingredients against the player's inventory [src: `backend_interface_crafting_playfab.lua`] | Bypass material validation; synthesize a shim recipe for cim-only names (`craft_necklace`/`craft_charm`/`craft_trinket`) vanilla's `_crafting_recipes_by_name` lacks | Only fires under `_is_active()`; returns `(recipe, valid_ids)` with `amount=1` per bid |
| `PlayFabRequestQueue.enqueue` [hook] `standard_forge.lua:1589` | Enqueues any PlayFab cloud-function request [src: `playfab_request_queue.lua`] | Defense-in-depth: drop every `crafting*` FunctionName before it reaches the EAC path, even if the `craft` hook is bypassed | Gated on `_is_active()` + `request.FunctionName` prefix; leaves non-craft traffic (achievements/quests) untouched |
| `BackendManagerPlayFab.commit` [hook] `crafting_in_modded_dev.lua:4998` | Diffs the mirror against PlayFab and pushes changes upstream [src: `backend_manager_play_fab.lua`; `docs/engine/11` commit/diff engine] | Block ALL commits while the forge UI is open - mutating an existing inventory item otherwise triggers "Backend rejected the challenge response -1" (this crashed v0.2.0) | Gated on `_cim_standard_forge_active` / `_custom_forge_active`; mutations are session-only (PlayFab restores canonical inventory on restart) |
| `BackendInterfaceItemPlayfab.get_item_from_id` [hook] `standard_forge.lua:1350` | Resolves a backend_id to its item record from the mirror [src: `backend_interface_item_playfab.lua:351`] | Resolve synthetic `cim_template_*` bids back to their `_template_cache` entry so the craft synth reads `.key` and clones the right weapon | Templates are UI-session-only, never in the mirror; a caller that queries the mirror directly bypasses this and templates vanish |
| `BackendInterfaceItemPlayfab.get_filtered_items` [hook] `_cim_inventory_filter.lua` | Returns backend items matching a filter string for inventory/craft grids [src: `backend_interface_item_playfab.lua:627`] | (a) re-hide leaked Versus twins on the Adventure grid; (b) drop vanilla weapons when `show_only_modded`/forge is active; (c) inject blacksmith templates for `can_craft_with` | Versus re-hide runs ALWAYS (independent of the show-only toggle); `item.data` is a SHARED IML ref, so re-hide is at the display layer, keyed on the `vs_` prefix (memory `reference_vt2_versus_items_hidden_in_adventure`) |
| `BackendInterfaceCommon.filter_items` [hook] `_cim_inventory_filter.lua` | Applies a filter infix to an item list (salvage/craft eligibility) [src: `backend_interface_common.lua:498`] | Surface modded crafts in the salvage grid REGARDLESS of equip/loadout state (vanilla `can_salvage` excludes equipped items) | Post-hook; only augments the `can_salvage` filter; modded crafts are throwaway by design so the equip exclusion is intentionally dropped |
| `HeroWindowItemCustomization._update_state_craft_button` [hook] `standard_forge.lua:144` | Computes `disable_button = force_disable or not has_all_requirements or script_data["eac-untrusted"]` [src: `hero_window_item_customization.lua:1928`] | CONSOLIDATED: (a) clear `eac-untrusted` around `apply_weapon_skin` so the Apply button enables; (b) post-write override drops the eac term for the standard forge | Migrated the eac-clear IN from `illusion_swap.lua` to avoid a duplicate `mod:hook` on this pair (§1); `script_data["eac-untrusted"]=true` is the modded-realm marker |
| `HeroWindowItemCustomization._update_property_option` [hook] `standard_forge.lua:192` | Iterates stored properties, writing `content["button_hotspot_"..N].disable_button` per property [src: `hero_window_item_customization.lua:1213`] | Replace with a bounded version that SKIPS writes for missing widget slots (the widget ships only hotspots 1-2; a 3rd+ property is a nil-index fatal) | `button_hotspot_3` nil-index family (§ item-customization nil-index; same as #150 `:2392`); cosmetic-only, extra props still apply to the buff system (memory `reference_cim_weave_slot_occupancy_array_not_display`) |
| `{HeroWindowItemCustomization, HeroWindowCrafting, HeroWindowCraftingConsole}.on_enter` [safe] `standard_forge.lua:224` / `.on_exit` [safe] `:236` | Enter/exit the desktop or inventory-tab/gamepad crafting window [src: `hero_window_crafting.lua`] | Flip `_cim_standard_forge_active`, rebuild the template cache, autodump | CONSOLIDATED per class (autodump lives in the same body); the inventory craft TAB is always the Console class regardless of input device (missing it let the EAC kick through) |
| `_MATERIAL_GATED_PAGES.setup_recipe_requirements` [safe] `standard_forge.lua:296` (12 CraftPage classes) | Reports `_has_all_requirements=false` when materials are short, disabling the craft button [src: `craft_page_craft_item.lua:62-78`] | Force `_has_all_requirements=true`, hide material-cost widgets; pin jewelry slot to a per-slot synth (`craft_necklace`/`_charm`/`_trinket`) + relabel the button | CONSOLIDATED: the jewelry-pin block lives INSIDE this body (a sibling `hook_safe` on the two `CraftPageCraftItem` classes was silently dropped, §1); `synth` is forward-declared so the closure binds the upvalue |
| `_FEEDBACK_PAGES._update_craft_items` [safe] `standard_forge.lua:379` (6 Console CraftPages) | Ticks the craft page; plays the completion sound only on a truthy vanilla craft return [src: `craft_page_*_console.lua`] | Emit `play_gui_craft_forge_button_completed` when a craft finishes (the local synth short-circuit skips vanilla's sound path) | `rawget`-guarded per class (§1b); one-shot `_cim_played_complete` flag |
| `HeroWindowCraftingInventoryConsole._update_crafting_material_panel` [safe] `standard_forge.lua:410` (+ non-Console if present) | Writes the "Scrap: 0 / Dust: 0..." material stat row [src: `hero_window_crafting_inventory_console.lua`] | Hide the material panel (modded play has no materials) | `rawget`-guard the non-Console variant (it doesn't exist in current builds, §1b) |
| `HeroWindowCrafting.update` [safe] `standard_forge.lua:1730` | Per-frame window tick [src: `hero_window_crafting.lua`] | Per-frame lazy-build/show/probe for the cim accessory craft buttons | DISABLED (`_STD_FORGE_BTNS_ENABLED=false`, v0.7.67); helpers stay defined but the driver no-ops |
| `BackendManagerPlayFab._create_interfaces` [safe] `crafting_in_modded_dev.lua:605` | Fires once when backend interfaces are constructed (post-LA-bridge) [src: `backend_manager_play_fab.lua`] | Load the persistent craft save (`_forge_load`), re-inject saved crafts, restore the modded loadout; one-shot >10-property trim | CONSOLIDATED (the property-trim was migrated in from `standard_forge.lua`, §1); backend is nil at mod init so this is the earliest ready point |

### Surface 2 - The Athanor: the vanilla weave forge repurposed as a modded crafting UI (owner: `docs/engine/09`, `/10`; `crafting_in_modded_dev.lua`, `cim_debug.lua`)

`cim` transitions `hero_view_force` into the `weave_forge` menu state and drives the
vanilla `HeroViewStateWeaveForge` / `HeroWindowWeaveProperties` / `HeroWindowWeaveForgeWeapons`
/ `HeroWindowWeaveForgeOverview` as an editor for ANY career-eligible weapon,
gated on `_custom_forge_active`. `docs/engine/09` owns the view/material model.

| Class.method (kind) | Vanilla behavior | Why cim hooks it | Trap / invariant |
|---|---|---|---|
| `BackendInterfaceWeavesPlayFab.{get_forge_level, get_essence, get_maximum_essence, get_property_mastery_costs, get_trait_mastery_cost, get_*_required_forge_level, magic_item_cost, get_loadout_properties/traits/talents, ...}` [hook] `crafting_in_modded_dev.lua:4092-4790` (~25 methods) | The Weaves economy: forge level, essence balance, per-upgrade costs, current loadout property/trait/talent sets [src: `backend_interface_weaves_playfab.lua`] | Under `_custom_forge_active` return "everything is free / fully unlocked" (essence 999999, required level 0, cost 0) so the modded forge treats every property/trait as affordable without indexing weave keys | Read-mostly freebies, each gated on `_custom_forge_active`; return the vanilla value when the forge is not cim-open. These are what let deus/adventure weapons (no weave progression) edit without a cost lookup crashing |
| `BackendInterfaceWeavesPlayFab.{set_loadout_property, remove_loadout_property, set_loadout_trait, remove_loadout_trait, set_loadout_talent, remove_loadout_talent}` [hook] `crafting_in_modded_dev.lua:4776-4983` | Writes a weave property/trait/talent into the career's weave loadout, fasserts via `WeavePropertiesByCareer`/`WeaveTraitsByCareer` [src: `backend_interface_weaves_playfab.lua`] | The store path is FULLY cim-owned under the modded forge: write into `_forge_loadout` + the mirror item, never call vanilla, so the `Weave*ByCareer` fassert never fires | Only a DISPLAY stub in `WeaveTraits.traits`/`WeaveProperties.properties` is needed to surface a key (no `Weave*ByCareer` injection) - memory `reference_cim_two_craft_surfaces_and_freedom_toggles` |
| `HeroWindowWeaveProperties._setup_menu_options` [hook] `crafting_in_modded_dev.lua:3304` | Builds the trait/property/talent pickers via `ipairs(WeaveTraits.categories[cat])` etc. [src: `hero_window_weave_properties.lua:346,370,531`] | SEED empty `{}` pools for unknown (deus/adventure) categories BEFORE vanilla runs (`_cim_ensure_weave_category_pools`); then `_cim_apply_forge_freedom` ALWAYS seeds the weapon's OWN native pool into each category (#404) + the freedom-toggle extras on top | `cat == item.trait_table_name/property_table_name` (vanilla `:178/186`), so the native pool is `WeaponTraits.combinations[cat]` / `WeaponProperties.combinations[cat].exotic` (`_cim_native_bares_for`, surfaced as `weave_` twins). Native seed runs REGARDLESS of the toggles (both default OFF) - an empty category array renders a ZERO-row picker (#404). Widened arrays RESTORED on `on_exit` so real Weaves play is never polluted |
| `HeroWindowWeaveProperties._sync_backend_loadout` [hook] `crafting_in_modded_dev.lua:3331` | Syncs the picker to the backend loadout; builds a talent tooltip `title .. " - " .. slot_type_strings[cat]` and calls `_populate_menu_widgets` at the END (`:1753`) to set each row's title/icon (`:626-636`) [src: `hero_window_weave_properties.lua:~1701`] | `pcall`-wrap under the modded forge - the tooltip string tables are PER-CALL locals (not seedable), so an unknown deus category nil-concats. On a guarded throw, COMPLETE `_populate_menu_widgets` so seeded rows still render title/icon (#404), and `printf [cim:404]` (mod:warning is logging-off invisible) | Property/trait bubbles sync BEFORE the failing talent-tooltip section, so editing still works; only the unknown-category tooltip degrades (memory `reference_cim_deus_weapon_weave_ui_crashes`) |
| `HeroWindowWeaveProperties.{_create_unit_previewer, _populate_menu_option_widget, _set_essence_upgrade_cost, _upgrade_magic_level, _draw}` [hook/safe] `crafting_in_modded_dev.lua:2956-5661` | Preview unit spawn, per-option widget fill, essence-cost display, magic-level upgrade, per-frame draw [src: `hero_window_weave_properties.lua`] | Route preview/cost/upgrade through cim's local store; drive the amulet accessory panel | `_draw` gated on `_AMULET_PANEL_ENABLED and _custom_forge_active`; VMF numeric widget has no `step` field (memory `reference_vmf_numeric_widget_no_step`) |
| `HeroWindowWeaveForgeWeapons.{_setup_weapon_list, _sync_backend_loadout, _present_item, _set_presentation_locked_state, _update_equip_button_status, _on_list_index_selected, _equip_item}` [hook] `crafting_in_modded_dev.lua:5005-5456` | The weapon-selection column of the Athanor: list build, present, lock state, equip [src: `hero_window_weave_forge_weapons.lua`] | Repopulate with cim-craftable weapons; route equip through the modded loadout | `_sync_backend_loadout` is hooked on BOTH this class AND `HeroWindowWeaveProperties` (distinct classes, no dup); each degrades independently for deus weapons |
| `HeroWindowWeaveForgeOverview._initialize_viewports` [hook] `crafting_in_modded_dev.lua:5539` / `{Overview, Weapons, Properties}._create_viewport_definition` [hook] `_cim_mission_forge_safety.lua` | Build the forge viewport, hardcoding `shading_environment="environment/ui_weave_forge_preview"` (a keep-only resource) [src: `hero_window_weave_forge_*.lua`] | Mid-mission: rewrite the returned `style.viewport.shading_environment` to a mission-RESIDENT env when not in the keep | Undefined shading-env VARIATION is an uncatchable AV (§22); the substitute is residency-probed (`_cim_pick_mission_env`: ui_store_preview -> ui_hdr -> blank) |
| `HeroWindowItemCustomization.{_create_item_preview_widget_definition, _register_object_sets, _update_environment}` [hook] `_cim_mission_forge_safety.lua` | Build the gear-icon preview widget + apply the shading-env VARIATION for the item [src: `hero_window_item_customization.lua`] | Skip the un-loaded preview level mid-mission; PIN the variation so `ShadingEnvironment.blend` never sees an undefined variation | `_update_environment` is the sole VARIATION writer on this surface - the §22 AV fix (issue #83/#228/#235). Do NOT route the in-mission flow onto this view (pulls `levels/ui_store_preview/world`, gt #50 crash class) |
| `HeroView.{_setup_hdr_gui, hdr_renderer, hdr_top_renderer}` [hook] `_cim_mission_forge_safety.lua` (`on_enter` #88 stays in `crafting_in_modded_dev.lua:2515`) / `HeroViewStateWeaveForge.{_setup_gamepad_gui, get_ui_renderer, set_fullscreen_effect_enable_state}` [hook/safe] `_cim_mission_forge_safety.lua` (`on_exit`/`update` stay in `crafting_in_modded_dev.lua`) | HeroView/weave-forge-state lifecycle + HDR renderer wiring [src: `hero_view.lua:323` reads `_fetch_initial_loadout_index`; `hero_view_state_weave_forge.lua:145`] | One-shot `inventory_loadout_access` flip for the standard-crafting open (issue #88); mid-mission HDR suppression (Fix B - no HDR worlds in mission) | The loadout-access flip is a save->vanilla-read->restore ONE-SHOT (`_cim_open_standard_inv_pending`); a persistent flip leaked the loadout onto the ESC-menu backout mid-mission |
| `LootItemUnitPreviewer.{_spawn_link_unit, _load_item_units}` [hook] `crafting_in_modded_dev.lua:3055-3060` | Spawns/loads the illusion-browser preview units [src: `loot_item_unit_previewer.lua`] | Return early for unsafe (deus/CW) items under the modded forge so the preview renders empty instead of faulting; `_load_item_units` also dumps (forge-only) each queued `spawn_data` entry's unit path + package/unit residency (`printf [cim:481]`, the issue-481 LA first-open-miss intake probe) | Gated on `_custom_forge_active and _forge_preview_unsafe(item)`; `LootItemUnitPreviewer.spawn_units` must be full `mod:hook` not `hook_safe` (repo CLAUDE.md; `_spawned_units` is nil at safe time) |
| `LootItemUnitPreviewer.spawn_units` [hook] + `LootItemUnitPreviewer.update` [safe] `crafting_in_modded_dev.lua` | Spawns + links each weapon hand unit to the spin-pivot link unit at `item_template.<hand>_hand_attachment_node_linking.third_person.display` [src: `loot_item_unit_previewer.lua:292/310,557`]; `update` drives the pending spawn (`:95` -> `_spawn_items` assigns `_spawned_units` at `:532`) | issue-404/481 DIAGNOSTIC: `printf [cim:404]` EVERY forge spawn (per-key latch dropped - it masked issue 481's first-open vs re-select delta) with each unit's `spawn_data` path + world position + delta from the pivot; the `update` hook_safe takes a one-shot POST-COSMETICS snapshot (`printf [cim:481]`: final position, pivot delta, local scale) because cosmetics_tweaker's outermost `spawn_units` wrapper applies LA paint + kind-unit 2x preview scale AFTER cim's body | Full `mod:hook` on spawn_units (reads the returned units; singleton, no prior cim hook); `update` is `hook_safe`, read-only, one-shot per previewer (`_cim481_snapped`), no prior cim hook (cosmetics' update hook is a different mod, VMF chains cross-mod). Both gated on `_custom_forge_active` (Athanor only); spawn dump also surfaces `n_units=0` if a preview is being stripped. The far-left root: uniform `preview_position {-0.85,3,0}` (`hero_window_weave_properties.lua:2954`) puts the pivot center-ish, but a long 2H ranged mesh orbits WIDE of it |
| `{bloom-window}._set_background_bloom_intensity` [hook] `_cim_mission_forge_safety.lua` / `{upgrade-anim}._start_transition_animation` [hook] `_cim_mission_forge_safety.lua` | Background bloom intensity + forge upgrade transition animation [src: weave-forge window defs] | Full `mod:hook` (SKIP the vanilla body, not run-after) to suppress the mid-mission bloom/transition that references keep-only materials | Class resolved by `rawget` at install; `[hook]` deliberately does not call `func` |
| `HeroViewStateWeaveForge.on_exit` [safe] `crafting_in_modded_dev.lua:2936` | Leaves the weave-forge state [src: `hero_view_state_weave_forge.lua`] | Clear `_custom_forge_active`; restore the widened freedom-toggle category arrays | The ONLY reset point for `_custom_forge_active` - a leaked flag makes every later BackendInterfaceWeavesPlayFab read return freebies |

### Surface 3 - Loadout equip-capture via the LA dispatch (DORMANT) (owner: `docs/engine/11`, `/06`; `crafting_in_modded_dev.lua`)

| Class.method (kind) | Vanilla behavior | Why cim hooks it | Trap / invariant |
|---|---|---|---|
| `BackendUtils.set_loadout_item` [hook,tbl] `crafting_in_modded_dev.lua:1568` | The STABLE outer equip entry point; dispatches to `get_loadout_interface_by_slot(slot):set_loadout_item(...)` [src: `backend_utils.lua:22`] | Capture every MENU equip BEFORE the LA dispatch (with Loremaster's Armoury active the inner interface is an LA CLONE that bypasses the class hook) | Table-form on the post-LA `BackendUtils` ref, installed DEFERRED from `mod.update` once interfaces exist (memory `reference_cim_equip_capture_la_dispatch`); a `_restoring` flag gates capture OFF during cim's own restore writes |
| `BackendInterfaceItemPlayfab.set_loadout_item` [safe] `crafting_in_modded_dev.lua:1543` | Direct interface loadout write (restore path, or a bot's designated loadout) [src: `backend_interface_item_playfab.lua`] | Capture direct/data writes; record under the `optional_loadout_index` (4th arg) so a non-selected-index write lands on that index | `from_live_equip=false` (a bare data write does not re-spawn the unit) |
| `PlayerManager.rpc_sync_loadout_slot` [hook] `crafting_in_modded_dev.lua:873` | RECEIVER: decodes a synced loadout slot, `NetworkLookup.item_names[item_id]` on the numeric wire id, stores under `_player_loadouts` [src: `player_manager.lua:69`, relay at `:83`] | CONSOLIDATED: (1) #278 PRE-decode guard - `rawget(names, item_id)==nil` drops the RPC before the strict `__index` fatal; (2) post-decode "modded" rarity restore for cim clients | Thread EVERY vanilla param through unchanged (dropping trailing args corrupts the relay re-send, §19); became a full `mod:hook` (was `hook_safe`) because the guard must run BEFORE vanilla decode |

**DORMANT.** Loadout persistence is force-OFF (`mod:set("persist_modded_loadouts", false)` at `:745`, no menu toggle remains). The capture/sync/restore machinery stays wired but no-ops - a bot gets its DESIGNATED vanilla loadout, byte-identical to not having cim. Replacement lands in `gut`. The `_capture_loadout_equip` + `_restore_modded_loadout` bodies still exist so the regression sandbox can exercise the round-trip.

### Surface 4 - Illusion swap: modded-realm weapon skin apply (owner: `docs/engine/06`; `illusion_swap.lua`)

Migrated from `cosmetics_tweaker` v0.8.49; cosmetics_tweaker yields when `get_mod("cim")`
resolves, so both can co-install without doubled hooks. `docs/engine/06` owns the
`BackendUtils.get_item_units` mesh seam; see `cosmetics_tweaker/ENGINE_SURFACE.md`
for the shared skin/illusion seams this mirrors.

| Class.method (kind) | Vanilla behavior | Why cim hooks it | Trap / invariant |
|---|---|---|---|
| `BackendInterfaceItemPlayfab.get_weapon_skin_from_skin_key` [hook] `illusion_swap.lua:64` | Resolves an owned skin to `(backend_id, item)`; nil for unowned [src: `backend_interface_item_playfab.lua`] | Mint a synthetic `cim_fake_<skin_key>` id for any skin the player does not own so the illusion grid can reference it | Gated on `script_data["eac-untrusted"]` + a real IML entry + DLC gate; `rawget(ItemMasterList, ...)` because `__index` Crashifies unknown keys (§4; `item_master_list.lua:133`) |
| `HeroWindowItemCustomization._enable_craft_button` [hook] `illusion_swap.lua:86` | Enables/disables the Apply button, baking in the `eac-untrusted` gate [src: `hero_window_item_customization.lua`] | Clear `eac-untrusted` around the enable for `apply_weapon_skin`; force-clear hotspot held flags on disable to kill the fast-completion sound loop | Distinct method from `_update_state_craft_button` (that one is consolidated in `standard_forge.lua`, §1) |
| `HeroWindowItemCustomization._on_illusion_index_pressed` [hook] `illusion_swap.lua:104` | Handles an illusion-grid click; a locked widget keeps Apply disabled [src: `hero_window_item_customization.lua`] | Clear `content.locked=false` on the clicked widget for skins the player has not earned (DLC-gated skins excluded) | Only when `not ignore_item_spawn`; still calls `func` |
| `BackendInterfaceCraftingPlayfab.craft` (via helper `mod._cim_try_illusion_apply`, `illusion_swap.lua:135`) | (see Surface 1 craft) | Write `item.skin` directly on the local backend mirror; persist to the cim forge save when the target is a modded craft | NOT a second `craft` hook - exposed as a helper the Surface 1 `craft` hook calls FIRST (§1). Sets `bypass_skin_ownership_check` on the mirror item |
| `BackendInterfaceCraftingPlayfab.update` [safe] `illusion_swap.lua:198` | Per-frame backend interface tick [src: `backend_interface_crafting_playfab.lua`] | Deferred (one-frame) completion of the local skin apply to match vanilla async timing | Consumes `_pending_local_craft` for this interface instance |
| `BackendInterfaceCraftingPlayfab.get_unlocked_weapon_skins` [safe] `illusion_swap.lua:218` | Returns the unlocked-skin set the customization grid treats as available [src: `backend_interface_crafting_playfab.lua`] | Mark every `WeaponSkins.skins` entry unlocked on the local mirror (except unowned-DLC skins) so locked illusions become selectable | DLC gate before the `mirror._unlocked_weapon_skins[k]=true` write (CLAUDE.md "DLC Ownership Gate" place 2) |

### Surface 5 - Custom rarity registration + cross-peer wire safety + CW compat (owner: `docs/engine/03`, `/11`; `modded_rarities.lua`, `crafting_in_modded_dev.lua`)

| Class.method (kind) | Vanilla behavior | Why cim hooks it | Trap / invariant |
|---|---|---|---|
| `LoadoutUtils.sync_loadout_slot` [hook,tbl] `crafting_in_modded_dev.lua:765` | SENDER: encodes a slot as `rpc_sync_loadout_slot` with `rarity_id=NetworkLookup.rarities[item.rarity]` [src: `loadout_utils.lua:13-42`] | UNCONDITIONALLY coerce `rarity="modded"` -> `"unique"` on the wire (restore host-local after), so a non-cim client can decode it | Wire safety is NEVER toggle-gated (#278/#371, §31; memory `reference_vt2_wire_safety_never_toggle_gated`). Bundling this behind `persist_modded_loadouts` (v0.8.15) crashed every vanilla client by default (#278, fixed v0.8.54-dev) |
| `[rpc] cim_modded_slot` (`mod:network_register`, `crafting_in_modded_dev.lua:838`) | - | cim<->cim side-channel: fire alongside each `sync_loadout_slot` so a cim CLIENT can restore "modded" chrome AFTER vanilla's decode | VMF delivers only to peers with the same mod-id + handler; a vanilla client has no handler and drops it silently. Schema-gated on `CIM_RPC_SCHEMA` (drop on mismatch, § rpc schema / VMF_RECIPES §10). Gated by `persist_modded_loadouts` (persistence-only, contributes nothing to wire safety) |
| `DeusRunController.get_weapon_pool` [hook] `modded_rarities.lua:243` | Iterates `pool_excludes` and nils `weapon_pool[pool_rarity][group]` [src: `deus_run_controller.lua`] | Pre-hook: scrub any `pool_excludes` rarity key absent from the base deus weapon pool (cim's "modded" rarity order=4 pollutes it, then `weapon_pool["modded"]` is nil -> index crash on the NEXT chest) | Idempotent (re-runs every chest); repairs already-contaminated runs. This is why a custom rarity must never leak into `RarityUtils.get_lower_rarities` output on the CW path |
| `_G.Localize` [hook] `modded_rarities.lua:153` | Global loc-key -> string lookup [src: engine] | Supply `rarity_display_name_modded`, "Craft Accessories"/"Reroll Accessory *" recipe titles | VMF `_localization.lua` is NOT registered into global `Localize` (memory `reference_vmf_localize_before_registration`) |
| `HeroWindowLoadoutInventory.on_enter` [safe] `modded_rarities.lua:177` / `HeroWindowInventory.on_enter` [safe] `:204` | Enter the loadout/forge inventory grid; the category header reads a LITERAL "Jewellery" string, not a loc key [src: `hero_window_loadout_definitions.lua:602`] | Rewrite `self._categories[*].display_name` "Jewellery" -> "Accessories" (Localize can't catch a literal) | SINGLE `HeroWindowLoadoutInventory.on_enter` hook_safe in cim - a duplicate in `cim_debug.lua` produced a rehook warning and dropped one (§1); the autodump probe is invoked from THIS body |
| **Table contact (NOT hooks):** `modded_rarities.lua` writes `Colors.color_definitions`, `UISettings.item_rarity_order/_rarities/_textures`, `RaritySettings`, `RarityIndex`, `ORDER_RARITY`, `NetworkLookup.rarities` (append) | Rarity chrome + the strict `NetworkLookup.rarities` reverse-lookup on equip sync | Register the "modded" rarity so the grid renderer's `RaritySettings[item.rarity].order` and the equip-sync lookup don't crash | `NetworkLookup.rarities` is an APPEND (`#t+1`), so vanilla ids 1..N are unchanged - which is exactly what makes the "modded"->"unique" wire coercion above safe for every client |

## Subsystem notes (how the vanilla flow runs end-to-end, for cim's cases)

Each note is the minimum needed to read the hooks above; the owning `docs/engine`
doc carries the full architecture.

### The craft backend + what a cim-crafted item's backend record looks like (owner: `docs/engine/11`)

In modded realm the player has zero `crafting_material` items and the EAC client is
unavailable, so every real PlayFab `craft` request is rejected with the "Backend
rejected the challenge response -1" / `playfab_eac_error` (reason 511) kick. cim
replaces the whole roundtrip: the `craft` hook (`standard_forge.lua:1446`) resolves
`synth[recipe.name]` and each synth writes results LOCALLY via
`self._backend_mirror:add_item(bid, item)`, then stashes `_craft_requests[id]` so
vanilla's `is_craft_complete(id)` poll immediately returns true and the UI plays
its completion animation. Commits are BLOCKED while the forge is open so no mutation
reaches PlayFab.

A cim-crafted item's backend record is a bare additive item, NOT a native PlayFab
entry: `{ ItemId = <item_key>, ItemInstanceId = <backend_id>, CustomData = {
power_level, rarity="modded", properties=<cjson>, traits=<cjson> } }`. The
`backend_id` is `Application.guid()` for normal crafts, but a `cwv_<key>_NNN` string
(instance band 100..999) when the input key is a `character_weapon_variants` clone
(`cwv_variant==true`) - because CWV's render-rescue hooks key on that exact pattern
(issue #390; class 27). Persistence lives in cim's own `_forged_weapons` save
(`mod:set("forged_weapons")`), NOT PlayFab - `_forge_load` reads it at
`_create_interfaces` and `add_item`s each `via_mirror` entry back on session
restore. The per-entry save shape (`:296-320`) carries `item_key`, `properties`
(dict), `traits` (array), `skin`, `power_level`, `rarity`, `rerolled_*_indices`
(shuffle-bag state), and an OPAQUE `custom_glow` pass-through slot that
`cosmetics_tweaker` owns and cim never interprets. Contrast a NATIVE item, whose
identity/props/skin live in the PlayFab mirror and re-sync from the server on launch
(`docs/engine/11` bid->key->wire degrade). This is the CRAFT side of the #279/#474
husk-identity vector: the crafted item exists only in the local mirror + cim save,
so a remote peer's husk resolves the BASE `item_data` (class 27) unless a net-safe
signal reaches it.

### The Athanor = the vanilla weave forge, repurposed (owner: `docs/engine/09`, `/10`)

`open_forge` transitions `hero_view_force` into the `weave_forge` menu state -
i.e. cim drives Fatshark's Winds-of-Magic weave forge as a general weapon editor.
Two facts make this work. First, the WEAVES ECONOMY is faked: ~25
`BackendInterfaceWeavesPlayFab` reads return "free/unlocked" under
`_custom_forge_active`, and the six `set/remove_loadout_*` writes are fully
cim-owned (never call vanilla), so the `WeavePropertiesByCareer`/`WeaveTraitsByCareer`
fasserts never fire and no weave-key cost lookup can crash. Second, the picker only
needs a DISPLAY STUB in `WeaveTraits.traits`/`WeaveProperties.properties` to offer
a key - there are TWO craft surfaces with DIFFERENT pools (memory
`reference_cim_two_craft_surfaces_and_freedom_toggles`): the Athanor bubble picker
reads the WEAVE tables (`WeaveTraits.categories[cat]`), while the standard bench
(Surface 1) reads the ADVENTURE tables (`WeaponTraits.combinations[cat]`,
boon-filtered). The `weave_` bridge in `_forge_apply_to_item` strips the leading
`weave_` to get the bare adventure key the item actually receives. The v0.8.44-dev
freedom toggles (`allow_cw_traits`, `allow_any_trait_property`) widen both surfaces,
read LIVE so `weapon_tweaker`'s runtime `WeaponTraits`/`WeaponProperties` mutation is
always reflected. Athanor slot occupancy is capped by the distinct-property ceiling
(`MAX_DISTINCT_PROPERTIES`, raised 2->10 in v0.8.32-dev) + a per-property bubble cap
(default 5) - NOT array length (memory `reference_cim_weave_slot_occupancy_array_not_display`).

### Cross-peer wire safety: the "modded" rarity on the loadout RPC (owner: `docs/engine/03`)

Every cim craft carries `rarity="modded"`, which cim appends to
`NetworkLookup.rarities` at load (`modded_rarities.lua`). When the host equips a
crafted item, `LoadoutUtils.sync_loadout_slot` encodes the loadout RPC with
`rarity_id = NetworkLookup.rarities["modded"]` - an id defined ONLY on peers that
run cim. A vanilla client reverse-looks-up nil at
`create_loadout_item_from_rpc_data` (`loadout_utils.lua:72-73`), stores
`item.rarity=nil`, and the next `RaritySettings[nil].order`
(`deus_chest_extension.lua:232`, `reward_popup_ui.lua:451`) fatals. Because cim only
APPENDS to `rarities` (vanilla ids 1..N unchanged), the fix is an UNCONDITIONAL
sender-side coercion "modded"->"unique" on the wire, restoring the host-local value
after the encode - a crash-safety invariant that takes no persistence argument, so
it can never be toggle-gated (§31, #278/#371). The receiver side adds a second layer:
the consolidated `PlayerManager.rpc_sync_loadout_slot` hook drops any RPC whose
`item_names` id is unknown on THIS peer (the item_names axis, e.g. a host with LA
clones the client lacks - CWV covers that axis sender-side in cwv 0.1.365+). The
cim<->cim `cim_modded_slot` side-channel then restores the "modded" chrome on cim
clients only; a vanilla client has no handler and drops it harmlessly.

### Loadout equip-capture through the LA dispatch (owner: `docs/engine/11`, `/06`)

With Loremaster's Armoury installed, a menu equip runs
`HeroViewStateOverview._set_loadout_item` -> `BackendUtils.set_loadout_item` ->
`get_loadout_interface_by_slot(slot):set_loadout_item(...)`, where the inner
interface is an LA CLONE, not `BackendInterfaceItemPlayfab`. So a class hook on the
inner interface NEVER fires for real equips - cim must hook the STABLE outer
`BackendUtils.set_loadout_item` (a plain table, so table-form), installed deferred
from `mod.update` once interfaces exist (memory `reference_cim_equip_capture_la_dispatch`;
the general LA dispatch model is in `docs/CROSS_MOD_ARCHITECTURE.md` and
`cosmetics_tweaker/ENGINE_SURFACE.md`). A `_restoring` flag gates capture OFF during
cim's own restore writes or it mutates `_modded_loadout` mid-iteration and starves
the live re-equip. This whole surface is DORMANT (persistence force-OFF), documented
here because the hooks are still installed.

## What the engine will NOT let us do (dead ends, already paid for)

Distilled from `CHANGELOG.md`, `AUDIT_2026_05_22.md`, the cim memory docs, and
`docs/BUG_CLASSES.md` - do not re-discover these.

- **Cannot fall through to vanilla `craft()` in modded realm.** The original
  enqueues an EAC-challenged PlayFab request; with no EAC client the response is
  `playfab_eac_error` reason 511 -> kick. Every drop path must synthesize locally or
  return a no-op craft id - never call `func`. The same is true for `commit`
  (blocked while the forge is open) and every `crafting*` `PlayFabRequestQueue.enqueue`.
- **A modded craft intercept must NOT assume `recipe_override` is non-nil.** The
  console/gamepad "Craft Item" page calls `parent:craft(items)` with NO recipe
  (`craft_page_craft_item_console.lua:325`) and relies on backend auto-detection;
  the PC page passes `self._recipe_name` (`craft_page_craft_item.lua:322`). A hook
  that early-drops on `not recipe_override` kills every gamepad craft. cim re-derives
  the recipe from the dropped item's `slot_type` (#407, class 30, v0.8.53-dev).
- **Deus/CW weapons crash the weave UI one `on_enter` helper at a time.** Any
  Adventure/Chaos-Wastes weapon whose `property_table_name`/`trait_table_name`/talent
  category is NOT a weave category nil-crashes each unguarded `HeroWindowWeaveProperties`
  lookup IN SEQUENCE (fixing one reveals the next). Decide by where the missing data
  lives: MODULE-level category tables -> SEED an empty `{}` pool
  (`_cim_ensure_weave_category_pools`); PER-CALL local string tables -> `pcall`-wrap
  the vanilla fn under `_custom_forge_active`. Degraded-but-functional (stat editing
  works, no weave-picker rows / no 3D model) is the accepted outcome
  (memory `reference_cim_deus_weapon_weave_ui_crashes`).
- **Opening the Athanor mid-mission is an ACCESS VIOLATION, not a clean fatal, if
  the shading-env variation is undefined.** The weave-forge windows hardcode
  `shading_environment="environment/ui_weave_forge_preview"` (keep-only). A missing
  env RESOURCE is a catchable fatal, but `ShadingEnvironment.blend` on an env that
  lacks the requested VARIATION is an uncatchable AV (§22). Both layers are closed by
  a residency-probed env picker (`_cim_pick_mission_env`) + a variation pin in
  `_update_environment` (issue #83/#228/#235). `open_forge` stays opt-in.
- **The 2-distinct-property ceiling was NEVER the #86 slot-blockage cause.** Three
  independent enforcers pinned it at 2 (add-time gate, load-time trimmer, per-property
  bubble cap); the fix was raising the distinct ceiling to 10, NOT touching the bubble
  cap (default 5 - lowering it to 1 killed per-property value scaling, v0.8.32->.33
  regression). >2 distinct is now crash-safe because the `button_hotspot_3` nil-index
  is guarded in `_update_property_option` (memory `reference_cim_weave_slot_occupancy_array_not_display`).
- **A cim-crafted CWV variant re-renders as its BASE weapon unless the backend_id
  matches `cwv_<key>_NNN`.** CWV's clone inherits the base `name`, so the vanilla
  equip/preview path re-resolves `item_data` off `item_data.name`
  (`world_hero_previewer.lua:674`) to the base mesh + attachments. A bare
  `Application.guid()` bid matches none of CWV's render hooks. cim mints the matching
  pattern + a `BackendUtils.get_item_units` safety net (issue #390, class 27); grip/
  scale still need CWV's own widened pattern. `skin_only` CWV defs are never in
  ItemMasterList, so they stay correctly non-craftable.
- **Vanilla-item mutations cannot be persisted in modded realm.** The commit-block
  keeps PlayFab from learning about a salvage/reroll/skin change, so PlayFab restores
  the canonical item on next launch. Only cim-owned modded crafts (in `_forged_weapons`)
  survive a restart. Loadout persistence was removed entirely (2026-06-30, replaced by
  gut) after never working reliably.

## Doc maintenance

Follows `docs/engine/README.md` maintenance rules: if a cim hook moves, a guard is
added, or a cited vanilla line drifts after a game patch, edit the affected row in
the SAME commit. Line numbers are against the 2026-07-12 `cim_dev` module source and
the carried decompile citations - match crash logs by function name, not line. This
documents `crafting_in_modded_dev` (the active dev stream); never cite stable
`crafting_in_modded/` line numbers - promotion is user-triggered
(`tools/promote/promote.ps1`) and the two streams drift. `AUDIT_2026_05_22.md` is a
SUPERSEDED snapshot whose line ranges predate the file-size growth; its findings
stand, its line numbers do not. Structural template is
`character_weapon_variants/ENGINE_SURFACE.md`; keep the section shape (hook table ->
subsystem notes -> dead ends) stable.
