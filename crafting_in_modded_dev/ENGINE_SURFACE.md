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
MOD_VERSION `0.8.128-dev`, friends-only Workshop 3733366851), the ACTIVE working
stream. `crafting_in_modded/` (`cim`, public Workshop 3721038774) is its read-only
public twin; per repo `CLAUDE.md` all in-flight work happens in the dev dir and
promotion is a separate user-triggered action (`tools/promote/promote.ps1`), so
this doc cites only `cim_dev` line numbers. Every module resolves `get_mod("cim_dev")`,
so any cross-mod consumer resolving `get_mod("cim")` will NOT see the dev clone.
cim's own render-rescue for CWV crafts, by contrast, keys on the `cwv_` backend_id
prefix, which is stream-agnostic.

**Verification split (honest).** Re-verified against the 2026-08-23 `cim_dev`
module source: every hook signature (grep-confirmed, **87 `mod:hook`, 35
`mod:hook_safe`, and 1 `mod:network_register`**), the full body of `standard_forge.lua`,
`illusion_swap.lua`, `modded_rarities.lua`, the forged-item state owner
(`_cim_forge_state_owner.lua`), the wire-safety owner
(`_cim_loadout_wire_owner.lua`), LA equip-capture in
`_cim_modded_loadout_owner.lua`, the `_cim_inventory_filter.lua` item filter,
and the entry-owned Athanor opener plus `_cim_mission_forge_safety.lua` shading
environment substitution. The `[src:]` citations INTO the decompile
(`loadout_utils.lua`, `network_lookup.lua`, `backend_utils.lua`,
`hero_window_item_customization.lua`, `craft_page_*`, `world_hero_previewer.lua`,
etc.) are carried from the cited `cim_dev` module comments + `CHANGELOG.md` +
`docs/BUG_CLASSES.md` + the line-verified sibling `character_weapon_variants` and
`cosmetics_tweaker` `ENGINE_SURFACE.md` docs, which cite the decompile in turn.

**Module split (v0.8.90-dev).** Three concerns were lifted verbatim out
of the entry into `_cim_*` modules (see `DEVELOPMENT.md` module map): the inventory/
salvage grid filters -> **`_cim_inventory_filter.lua`**; every mid-mission render-safety
guard (shading-env, HDR, glow/skilltree/bloom/upgrade-anim suppressors, gamepad/HDR
renderer guards) -> **`_cim_mission_forge_safety.lua`**; the read-only dump commands ->
`_cim_dump_commands.lua`. Issue #628 adds the engine-free
**`_cim_synthetic_item_contract.lua`** as the canonical provider-definition,
canonical-acquisition-identity, acquired-instance, mirror-payload,
salvage-eligibility, and deletion-partition policy. Its
**`_cim_salvage_local_boundary.lua` -> `_cim_owned_deletion.lua`** path owns one
atomic selected-set transaction for persisted CIM and foreign session-only
Salvage rows, including exact mirror/new-marker compensation, and is consumed
by both craft surfaces and the inventory adapter. Rows below cite the owning
module for moved hooks. Match crash logs by function name rather than old entry
line numbers.

**Structural completion (v0.8.121-dev).** The final high-coupling entry regions
now have explicit owners. `_cim_bootstrap_runtime.lua` owns boot telemetry,
settings dumps, debug channels, and the sole regression registry/runner.
`_cim_forge_state_owner.lua` owns the forged-item registry, persistence
migration, provider partition, MIL/mirror item adapters, and the ordered
`BackendManagerPlayFab._create_interfaces` restore seam. Its getter/setter API
prevents consumers retaining the registry table that load replaces.
`_cim_loadout_wire_owner.lua` owns the issue #278/#371/#598 sender substitution,
schema-gated side channel, post-decode presentation restore, and unknown-item-id
predecode guard. Hook/RPC cardinality is unchanged; engine-free owner tests drive
reload replacement, callback order, schema refusal, and wire/local separation.

Issue #959 adds `_cim_accessory_property_policy.lua` (pure category/layer
arithmetic, write admission, and capacity policy) and
`_cim_accessory_property_runtime.lua` (the single owner of the four
property-picker hooks). The entry's existing backend mutation hook consumes the
same policy, so display and storage cannot disagree about accessory identity.
This keeps the frozen entry size from growing and prevents same-class/method
hook duplication.

The Phase 5 `_cim_weave_economy.lua` owner now installs the 18 read-only
`BackendInterfaceWeavesPlayFab` progression/economy hooks at their original
entry boundary. It receives `_custom_forge_active` and the forward-declared
bubble-cap resolver through call-time accessors. Offline coverage locks
registration order, idempotence, all active facade values, native fallthrough
arity, and the five existing protected fallbacks.

The Phase 5 `_cim_weave_loadout_owner.lua` owner (v0.8.120-dev) installs the
matching WRITE half at ITS original boundary: the ten mutable
`BackendInterfaceWeavesPlayFab` loadout hooks, the amulet slot map, the
per-property bubble-cap math (#86/#244), the write-path slot-array cap and the
read-chokepoint trim, the `movespeed_2pct_mode` buff-template patch, and the
seed/apply pass. The split is read vs write on the same vanilla class with zero
duplicate registrations: the economy facade installs ABOVE this seam and
resolves `_bubble_cap` at callback time, which is the reason the entry keeps
exactly one forward declaration. All four reassigned entry stores
(`_custom_forge_active`, `_forge_item_props`, `_forged_weapons`,
`_amulet_dirty`) cross as call-time accessors. The `BackendManagerPlayFab.commit`
suppression is NOT part of this owner - it stays in the entry immediately below
the seam because it is anti-tamper crash safety covering both craft surfaces.
Offline coverage locks the seam position, the ten-hook order and cardinality,
accessor liveness across a rebind, idempotence, reload rebinding, the bubble
caps and their key normalization, and the layer-aware #86 trim.

The Phase 5 `_cim_forge_preview_owner.lua` owner installs the complete Athanor
weapon-preview lifecycle at its original boundary. Decompiled
`loot_item_unit_previewer.lua:246-350,453-566` proves the load-package,
display-unit spawn, attached-unit spawn, and retained update seams. The owner
keeps its six-hook order and composes the Overview constructor into
`_cim_mission_forge_safety.lua`'s existing #882 wrapper rather than registering
the same pair twice. While the mutable Athanor-active flag is true, each constructor
publishes one stack-safe exact context during synchronous unit resolution and
marks only the returned previewer with the same generation; inactive, nested,
and throwing calls cannot leak identity. The owner resolves the flag at callback
time and owns no backend, loadout, forge-store, or network mutation.

The Phase 5 `_cim_forge_ui_owner.lua` owner installs the presentation-only
`HeroWindowWeaveProperties._draw` and `HeroViewStateWeaveForge.update` hooks in
their original order. It owns the Athanor accessory overlay, legacy disabled
button builders, tooltip, and per-frame widget polish. Reload refreshes the
forge-active/background/manager/profile dependencies behind one stable holder;
it cannot duplicate hooks and performs no backend, loadout, or wire writes. The
accessory overlay callback is republished onto each fresh panel before the
idempotence guard, and the one draw hook resolves that current panel at call
time, so a missing first-load panel can recover without retaining a stale one.

The `/cim_regression_test` harness and initialization-time contract checks
remain in the entry. The frozen late stream is composed from
`_cim_regression_cleanup.lua`, `_cim_regression_checks.lua`, and
`_cim_regression_forge_surfaces.lua`; all three chunks load before the first
installer runs, and the core passes its exact loadout-sandbox helper to the
forge-surface suffix.
Source-reading checks resolve an anchor published by the owner module they
inspect, never the entry-owned registrar (#1227), and fail if that ownership
anchor is missing. The #414 slot-family check also runs an independent census
over live `WeaponTraits.combinations` plus `traits[*].crafting_disabled`; any
boon-bearing family absent from the explicit slot map fails deterministically
before production filtering can hide the drift (#1122).

`cim` is a **UI-heavy backend mod**: it makes the vanilla Keep crafting benches
work in the modded realm (where the player has no crafting materials and the EAC
anti-tamper path is dead), synthesizes crafted items locally into the backend
mirror, and repurposes the entire vanilla **weave forge** (the Athanor) as a
second, richer crafting surface. Its engine contact clusters into the five
surfaces below.

## Hook table

**139 hook sites** (`mod:hook`/`mod:hook_safe`) + **1 VMF RPC channel**
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
| `{CraftPageSalvage, CraftPageSalvageConsole}.{_handle_input, _update_animations}` [hook/safe] `_cim_salvage_modded_button.lua` | Desktop dispatches rarity buttons into `_fill_by_rarity`, which stops at `CraftingSettings.NUM_SALVAGE_SLOTS`; console publishes the selected rarity through the overview state [src: `craft_page_salvage.lua:164-276`; `craft_page_salvage_console.lua:153-181`; `crafting_recipes.lua:4`] | Add the fifth `modded` rarity control to both definition tables, animate it with the existing icon-button helper, and delegate the press to the matching vanilla bounded fill route | Definition transform is idempotent and derives direction/spacing from rare -> exotic. Clear moves one step to sixth. The dedicated `store_tag_icon_weapon_modded` crossed-swords material is packaged and renderer-injected independently from the `icon_bg_modded` item-card background. No custom item-selection or salvage transaction path. Runtime check: `issue618_modded_salvage_autofill`. |
| `BackendInterfaceCraftingPlayfab.craft` [hook] `standard_forge.lua:1586` | Enqueues an `ExecuteCloudScript` PlayFab request with `send_eac_challenge=true`; recipe resolved via `_get_valid_recipe` [src: `backend_interface_crafting_playfab.lua`, queue at `playfab_request_queue.lua:44`] | THE choke point: short-circuit PlayFab and dispatch to local `synth[recipe.name]`. `_cim_craft_dispatch.lua` records the public result and dirtifies presentation only when the synth's internal `committed` result is not false. | CONSOLIDATED (illusion-apply intercept runs FIRST, then `_is_active` gate). NEVER fall through to `func` in modded realm - it triggers the EAC kick (reason 511). Public compatibility remains the non-nil `(id, recipe)` pair even for a refused transaction, preventing press-and-hold refire; the internal failure bit suppresses presentation invalidation. |
| `BackendInterfaceCraftingPlayfab._get_valid_recipe` [hook] `standard_forge.lua:433` | Validates recipe + material ingredients against the player's inventory [src: `backend_interface_crafting_playfab.lua`] | Bypass material validation; synthesize a shim recipe for cim-only names (`craft_necklace`/`craft_charm`/`craft_trinket`) vanilla's `_crafting_recipes_by_name` lacks | Only fires under `_is_active()`; returns `(recipe, valid_ids)` with `amount=1` per bid |
| `PlayFabRequestQueue.enqueue` [hook] `standard_forge.lua:1589` | Enqueues any PlayFab cloud-function request [src: `playfab_request_queue.lua`] | Defense-in-depth: drop every `crafting*` FunctionName before it reaches the EAC path, even if the `craft` hook is bypassed | Gated on `_is_active()` + `request.FunctionName` prefix; leaves non-craft traffic (achievements/quests) untouched |
| `BackendManagerPlayFab.commit` [hook] `crafting_in_modded_dev.lua:4998` | Diffs the mirror against PlayFab and pushes changes upstream [src: `backend_manager_play_fab.lua`; `docs/engine/11` commit/diff engine] | Block ALL commits while the forge UI is open - mutating an existing inventory item otherwise triggers "Backend rejected the challenge response -1" (this crashed v0.2.0) | Gated on `_cim_standard_forge_active` / `_custom_forge_active`; mutations are session-only (PlayFab restores canonical inventory on restart) |
| `BackendInterfaceItemPlayfab.get_item_from_id` [hook] `standard_forge.lua:1350` | Resolves a backend_id to its item record from the mirror [src: `backend_interface_item_playfab.lua:351`] | Resolve synthetic `cim_template_*` bids back to their `_template_cache` entry so the craft synth reads `.key` and clones the right weapon | Templates are UI-session-only, never in the mirror; a caller that queries the mirror directly bypasses this and templates vanish |
| `BackendInterfaceItemPlayfab.get_filtered_items` [hook] `_cim_inventory_filter.lua` | Returns backend items matching a filter string for inventory/craft grids [src: `backend_interface_item_playfab.lua:627`] | (a) re-hide leaked Versus twins on the Adventure grid; (b) drop vanilla weapons when `show_only_modded`/forge is active; (c) inject blacksmith templates for `can_craft_with` | `_cim_synthetic_item_contract.lua` owns exact identity plus the selector/instance row role. `_cim_template_catalog.lua` groups ordinary helper/preview/Versus aliases by `slot_type + item_type`, while every authored CWV `cwv_key` remains exact. `_cim_template_selector.lua` compacts live rows by that same family identity and fails closed by removing any crafted instance at the final acquisition seam. Localization is not identity; vanilla `can_craft_with` admits only `default` rarity [src: `backend_interface_common.lua:498-508`] |
| `InteractionDefinitions.forge_access.client.can_interact` [table replacement] `_cim_keep_forge_interaction.lua` | Vanilla returns `not script_data["eac-untrusted"]`; on success its untouched `stop` callback transitions to `hero_view_force` with `menu_sub_state_name="forge"` and the HUD callback supplies the native prompt [src: `scripts/unit_extensions/generic/interactions.lua:2196-2217`] | Restore the physical Keep forge only for an untrusted/modded session in a live hub, where CIM's standard-forge lifecycle already owns every craft mutation | Stores the original predicate once and delegates official/non-Keep results. No VMF hook, new transition, input override, or backend call. The native stop/HUD/controller flow is untouched; repeated module install does not nest wrappers (#624). |
| `BackendInterfaceCommon.filter_items` [hook] `_cim_inventory_filter.lua` | Receives the inventory as a backend-id keyed map and enumerates it with `pairs`; applies the recipe infix to produce an array [src: `backend_interface_common.lua:648-669`]. Vanilla `can_salvage` admits weapon/accessory slots only when rarity is not default/promo/magic, the item is unequipped, and it is not favorited; the recipe also excludes every saved loadout [src: `backend_interface_common.lua:404-423`; `crafting_recipes.lua:13`]. `BackendInterfaceItemPlayfab.equipped_by` scans active career loadouts, while `is_equipped_by_any_loadout` scans every cached career row [src: `backend_interface_item_playfab.lua:747-801`]. | Enumerate the raw keyed map with `pairs`, then re-admit only an exact persisted CIM instance through `_cim_synthetic_item_contract.is_salvage_eligible` when every vanilla safety guard passes. While #628 remains open, emit a fingerprint-deduplicated, 96-line-capped `[cim:628] salvage_state` witness for each exact CIM instance. | Treating the raw map as a dense array makes the adapter silently visit zero items; offline coverage locks the `pairs(items)` boundary. Fail closed if equipped/favorite/loadout queries fail. The witness records result, verdict/reason, active careers, saved rows, favorite, and backend-dirty state so aggregate grid counts cannot conceal the rejecting guard. Normalization, selection, and salvage consume the contract's same canonical identity ladder. Definition/Blacksmith rows, rarity-only lookalikes and unpersisted `cwv_`/`woc_` ids are never ownership. Runtime checks: `issue628_saved_instance_contract`, `issue628_identity_resolvers_unified`, `issue628_salvage_state_diagnostic`. |
| `PlayFabMirrorBase` inventory/new-marker state [direct local transaction] `_cim_salvage_local_boundary.lua` -> `crafting_in_modded_dev.lua` -> `_cim_owned_deletion.lua` | Vanilla `remove_item` unmarks the exact id from `PlayerData.new_item_ids` and every `new_item_ids_by_career[career][slot]`, autosaving through `ItemHelper`, then clears `_inventory_items[id]` [src: `item_helper.lua:128-192`; `playfab_mirror_base.lua:2547-2555`]. `add_item` is not an inverse: it normalizes data, evaluates power, fires inventory-added/skin routing, marks new, and may autosave [src: `playfab_mirror_base.lua:2494-2545`]. The item interface's eager `_refresh` also normalizes skins, unmarks missing new/favorite ids, and autosaves [src: `backend_interface_item_playfab.lua:37-105`]. | One transaction serves `/forge_delete`, bulk cleanup, and standard Salvage. It snapshots exact row references and marker values, partitions persisted owned rows from foreign session-only rows, then commits all selected rows plus owned persistence/loadout/illusion cleanup or compensates the complete set with direct table restoration. On success, the deletion transaction dirtifies cache flags; `synth.salvage` returns internal `committed=true`, allowing the enclosing `_cim_craft_dispatch` invalidation. Refusal returns `committed=false`, so neither layer dirtifies. | Selected owned ids must exist in `_forged_weapons` and pass the shared owner/schema/provider contract; ordinary Salvage ids enter only as the boundary's foreign partition. Rollback uses `rawset` on the original table owners and never calls `add_item`, `remove_item`, eager `_refresh`, `ItemHelper`, an official request, or commit. The wrapper regression plants a second-foreign failure and requires exact restoration plus zero transaction invalidation, outer dirtification, refresh, ItemHelper-like, or autosave effects while retaining the public `(id, recipe)` completion shape. |
| `HeroWindowItemCustomization._update_state_craft_button` [hook] `standard_forge.lua:144` | Computes `disable_button = force_disable or not has_all_requirements or script_data["eac-untrusted"]` [src: `hero_window_item_customization.lua:1928`] | CONSOLIDATED: (a) clear `eac-untrusted` around `apply_weapon_skin` so the Apply button enables; (b) post-write override drops the eac term for the standard forge | Migrated the eac-clear IN from `illusion_swap.lua` to avoid a duplicate `mod:hook` on this pair (§1); `script_data["eac-untrusted"]=true` is the modded-realm marker |
| `HeroWindowItemCustomization._update_property_option` [hook] `standard_forge.lua:192` | Iterates stored properties, writing `content["button_hotspot_"..N].disable_button` per property [src: `hero_window_item_customization.lua:1213`] | Replace with a bounded version that SKIPS writes for missing widget slots (the widget ships only hotspots 1-2; a 3rd+ property is a nil-index fatal) | `button_hotspot_3` nil-index family (§ item-customization nil-index; same as #150 `:2392`); cosmetic-only, extra props still apply to the buff system (memory `reference_cim_weave_slot_occupancy_array_not_display`) |
| `{HeroWindowItemCustomization, HeroWindowCrafting, HeroWindowCraftingConsole}.on_enter` [hook] `standard_forge.lua` / `.on_exit` [safe] | Enter/exit the desktop or inventory-tab/gamepad crafting window; both crafting classes call `_change_recipe_page` inside `on_enter` [src: `hero_window_crafting.lua:66-105`, `hero_window_crafting_console.lua:71-116`] | PRE-ENTER: flip `_cim_standard_forge_active` and rebuild the exact-career acquisition-selector cache before vanilla builds the initial recipe page. POST-ENTER: autodump the completed UI. | CONSOLIDATED per class. This must remain a wrapping hook: `hook_safe` runs after the original and therefore misses the initial `can_craft_with` query, hiding every synthetic CWV Blacksmith row (#524/class 46). The inventory craft TAB is always the Console class regardless of input device. |
| `_MATERIAL_GATED_PAGES.setup_recipe_requirements` [safe] `standard_forge.lua:296` (12 CraftPage classes) | Reports `_has_all_requirements=false` when materials are short, disabling the craft button [src: `craft_page_craft_item.lua:62-78`] | Force `_has_all_requirements=true`, hide material-cost widgets; pin jewelry slot to a per-slot synth (`craft_necklace`/`_charm`/`_trinket`) + relabel the button | CONSOLIDATED: the jewelry-pin block lives INSIDE this body (a sibling `hook_safe` on the two `CraftPageCraftItem` classes was silently dropped, §1); `synth` is forward-declared so the closure binds the upvalue |
| `_FEEDBACK_PAGES._update_craft_items` [safe] `standard_forge.lua:379` (6 Console CraftPages) | Ticks the craft page; plays the completion sound only on a truthy vanilla craft return [src: `craft_page_*_console.lua`] | Emit `play_gui_craft_forge_button_completed` when a craft finishes (the local synth short-circuit skips vanilla's sound path) | `rawget`-guarded per class (§1b); one-shot `_cim_played_complete` flag |
| `HeroWindowCraftingInventoryConsole._update_crafting_material_panel` [safe] `standard_forge.lua:410` (+ non-Console if present) | Writes the "Scrap: 0 / Dust: 0..." material stat row [src: `hero_window_crafting_inventory_console.lua`] | Hide the material panel (modded play has no materials) | `rawget`-guard the non-Console variant (it doesn't exist in current builds, §1b) |
| `HeroWindowCrafting.update` [safe] `standard_forge.lua:1730` | Per-frame window tick [src: `hero_window_crafting.lua`] | Per-frame lazy-build/show/probe for the cim accessory craft buttons | DISABLED (`_STD_FORGE_BTNS_ENABLED=false`, v0.7.67); helpers stay defined but the driver no-ops |
| `BackendManagerPlayFab._create_interfaces` [safe] `_cim_forge_state_owner.lua` | Fires once when backend interfaces are constructed (post-LA-bridge) [src: `backend_manager_play_fab.lua`] | Load the persistent craft save, re-inject saved crafts, restore the modded loadout; one-shot >10-property trim | CONSOLIDATED (the property-trim was migrated in from `standard_forge.lua`, §1); backend is nil at mod init so this is the earliest ready point. The owner invokes late-bound Athanor injection and loadout restore callbacks in the original order. |

### Surface 2 - The Athanor: the vanilla weave forge repurposed as a modded crafting UI (owner: `docs/engine/09`, `/10`; `crafting_in_modded_dev.lua`, `cim_debug.lua`)

`cim` transitions `hero_view_force` into the `weave_forge` menu state and drives the
vanilla `HeroViewStateWeaveForge` / `HeroWindowWeaveProperties` / `HeroWindowWeaveForgeWeapons`
/ `HeroWindowWeaveForgeOverview` as an editor for ANY career-eligible weapon,
gated on `_custom_forge_active`. `docs/engine/09` owns the view/material model.

| Class.method (kind) | Vanilla behavior | Why cim hooks it | Trap / invariant |
|---|---|---|---|
| `BackendInterfaceWeavesPlayFab.{get_forge_level, get_essence, get_maximum_essence, get_property_mastery_costs, get_trait_mastery_cost, get_*_required_forge_level, magic_item_cost, ...}` [hook] `_cim_weave_economy.lua` (18 read hooks); `get_loadout_properties/traits/talents` moved to `_cim_weave_loadout_owner.lua` at v0.8.120-dev | The Weaves economy: forge level, essence balance, per-upgrade costs, current loadout property/trait/talent sets [src: `backend_interface_weaves_playfab.lua`] | Under `_custom_forge_active` return "everything is free / fully unlocked" (essence 999999, required level 0, cost 0) so the modded forge treats every property/trait as affordable without indexing weave keys | Read-only progression/economy hooks are one idempotent owner and preserve their original order. Each is gated on the injected call-time active-state accessor and returns the vanilla value when the forge is not cim-open. Mutable loadout reads/writes are the sibling `_cim_weave_loadout_owner.lua`, which installs BELOW this facade and supplies the bubble-cap function it resolves. |
| `BackendInterfaceWeavesPlayFab.{set_loadout_property, remove_loadout_property, set_loadout_trait, remove_loadout_trait, set_loadout_talent, remove_loadout_talent}` [hook] `_cim_weave_loadout_owner.lua` (mutable Weaves loadout owner, moved from the entry at v0.8.120-dev) | Writes a weave property/trait/talent into the career's weave loadout, fasserts via `WeavePropertiesByCareer`/`WeaveTraitsByCareer` [src: `backend_interface_weaves_playfab.lua`] | The store path is FULLY cim-owned under the modded forge: write into `_forge_loadout` + the mirror item, never call vanilla, so the `Weave*ByCareer` fassert never fires | Only a DISPLAY stub in `WeaveTraits.traits`/`WeaveProperties.properties` is needed to surface a key (no `Weave*ByCareer` injection) - memory `reference_cim_two_craft_surfaces_and_freedom_toggles` |
| `_value_for_bubbles` / `_bubbles_for_value` [conversion] + `_cim_property_value_policy.lua` | The Athanor formats `amount / #costs * weave_max` as an absolute value [src: `scripts/helpers/ui_utils.lua:115-135`], while ordinary item description and buff paths treat the stored number as a normalized interpolation parameter [src: `scripts/helpers/ui_utils.lua:137-173`; `scripts/unit_extensions/default_player_unit/buffs/buff_extension.lua:207-237`] | Convert absolute picker values to normalized two-endpoint Adventure storage and invert that conversion when seeding the bubble grid (#244) | Normalized zero is a valid present low-end property. Stamina, movement speed, scalar values, and discrete tables retain their existing special paths; conversion is pure, bounded, and adds no hook. |
| `HeroWindowWeaveProperties._setup_menu_options` [hook] `_cim_forge_picker_owner.lua` | Builds the trait/property/talent pickers via `ipairs(WeaveTraits.categories[cat])` etc. [src: `hero_window_weave_properties.lua:346,370,531`] | SEED empty `{}` pools for unknown (deus/adventure) categories BEFORE vanilla runs (`_cim_ensure_weave_category_pools`); then `_cim_apply_forge_freedom` ALWAYS seeds the weapon's OWN native pool into each category (#404) + the freedom-toggle extras on top | The picker owner captures each exact category-table target and original value. Forge exit restores those same targets; reinstall settles any outstanding old transaction before dependency replacement, so a fresh globals map cannot receive an old backup. `cat == item.trait_table_name/property_table_name`, so the native pool is `WeaponTraits.combinations[cat]` / `WeaponProperties.combinations[cat].exotic`. Native seed runs regardless of toggle state; hooks install once in exact order. |
| `HeroWindowWeaveProperties._sync_backend_loadout` [hook] `_cim_forge_picker_owner.lua` | Syncs the picker to the backend loadout; builds a talent tooltip `title .. " - " .. slot_type_strings[cat]` and calls `_populate_menu_widgets` at the END (`:1753`) to set each row's title/icon (`:626-636`) [src: `hero_window_weave_properties.lua:~1701`] | `pcall`-wrap under the modded forge - the tooltip string tables are PER-CALL locals (not seedable), so an unknown deus category nil-concats. On a guarded throw, COMPLETE `_populate_menu_widgets` so seeded rows still render title/icon (#404), and `printf [cim:404]` (mod:warning is logging-off invisible) | Property/trait bubbles sync before the failing talent-tooltip section, so editing still works. The same stable owner registers `_setup_menu_options` then this hook exactly once and refreshes its active-state/log dependencies on reload. |
| `HeroWindowWeaveProperties._create_unit_previewer` [hook] entry; `.{_set_essence_upgrade_cost,on_exit}` [safe] and `._upgrade_magic_level` [hook] `_cim_temper_runtime.lua`; `._draw` [safe] `_cim_forge_ui_owner.lua` | Preview unit spawn, essence-cost display, editor lifecycle, magic-level upgrade, and per-frame draw [src: `hero_window_weave_properties.lua`; `UIWidgets.create_athanor_upgrade_button` in `ui_widgets_honduras.lua:16787` gates both fixed-left `icon` passes on `content.icon`, while its three title styles use centered `size[1]-40` rectangles] | Route preview/cost/upgrade through CIM's local store; classify weapon Apply/Craft transactions; in accessory state suppress the shared native-arrow predicate and restore centered title offsets (#1117); the presentation owner drives the accessory panel | The exact original `content.icon` is retained on the widget and restored for weapon state. Accessory -> weapon -> accessory is covered offline, while normal/hover/disabled/click rendering across UI scales remains an in-game check. `_draw` is the sole presentation-owner hook and is gated through the call-time active accessor. |
| `HeroWindowWeaveProperties.{_populate_menu_option_widget, _find_slot_by_key, _can_clear_slots, _clear_slots}` [hook/safe] `_cim_accessory_property_runtime.lua`; `BackendInterfaceWeavesPlayFab.set_loadout_property` [hook] `_cim_weave_loadout_owner.lua` `_store_property_slot` | Vanilla property-row usage counts the full key array; `_find_slot_by_key` ignores the category argument; clear membership is key-based. CIM's widened accessory store formerly capped that same aggregate array, so native `_add_key_to_slot` could play its sound after the backend hook rejected the write [src: `hero_window_weave_properties.lua:718-740,2402-2460,2483-2501,2540-2664`] | Preserve #239's hidden fake-cost presentation and use `_cim_accessory_property_policy.lua` for usage, write admission, per-key and distinct-key capacity, right-click removal, and Clear after CIM widens one key into multiple accessory categories (#959) | Accessory layers are offence 1-10 (Charm), defence 11-20 (Necklace), utility 21-30 (Trinket) [src: `hero_window_weave_properties.lua:24-65`]. Weapon/single-item editing retains its global cap and vanilla Weaves fall through untouched. One extracted adapter owns the complete picker hook set; the existing backend hook emits at most 24 one-shot `[cim:959]` store outcomes. |
| `HeroWindowWeaveForgeWeapons.{_setup_weapon_list, _sync_backend_loadout, _present_item, _set_presentation_locked_state, _update_equip_button_status, _on_list_index_selected, _equip_item}` [hook] `crafting_in_modded_dev.lua` + `_cim_athanor_icon_policy.lua` | The weapon-selection column of the Athanor: list build, present, lock state, equip [src: `hero_window_weave_forge_weapons.lua`; list widgets draw on `self._ui_top_renderer` inherited from `ingame_ui_context` at `:38,1005-1058`] | Repopulate with CIM-craftable weapons. Every enumerated row routes the issue 628 REGISTERED provider gate (`contract.gate_enumerated_row("athanor_list", ...)`); excluded rows (e.g. the immutable WOC relic `woc_blightreaper`, issues 682/793) are logged capped as `provider rejected before UI surface=athanor_list` plus the unrouted-walk self-report. Before list population, resolve the exact masked+saturated atlas material and prove it exists in that live Gui. Retain CWV's paired Dual Axes icon when its `ingame_ui` provider capability and live material proof both pass (#787); otherwise substitute a renderer-proven provider/base/vanilla icon or omit the row fail-closed (#617). Craft into the selected primary/secondary slot and optionally auto-equip the exact bid (#562). Vanilla `_sync_backend_loadout` stamps `content.locked = not backend_id` from a backend-items OWNERSHIP lookup (`hero_window_weave_forge_weapons.lua:555/:565`); CWV rows are registration-only (never owned), so the consolidated hook clears the lock for provider=cwv keys only via the issue 628 `provider_for` ladder (#703). | Package load, provider declaration, and `UIAtlasHelper` membership do not prove the required material variant. The exact live Gui proof remains authoritative. Synthetic base/Blacksmith rows have no exact backend-instance identity, so they retain the provider's static authored icon and do not consume Cosmetics #650's instance-specific primary/offhand/glow compositor. No custom resource identifier is sent to peers, ItemMasterList is not mutated, and non-CWV users retain vanilla icons. `_sync_backend_loadout` remains hooked on both distinct weapon/property classes. |
| `HeroWindowWeaveForgeWeapons._setup_weapon_stats` [hook] `_cim_mission_forge_safety.lua` + `_cim_forge_widget_material_policy.lua` | Dynamically creates block/stamina/ammo/property/trait widgets after `create_ui_elements`, stores them in `_scrollbars.stats.list_widgets`, and `_draw` submits them to `self._ui_top_renderer` [src: `hero_window_weave_forge_weapons.lua:1435-1643,950-975`] | After vanilla construction, mission-only renderer-proof every texture-bearing pass in every scrollbar list; disable only non-resident passes instance-locally (#83) | Static array pruning cannot cover late producers. Clone-on-write is mandatory because `UIWidget.init` retains the definition's pass array; Keep skips the policy entirely. Never move this to a broad `_draw`/`UIRenderer` hook. |
| `HeroWindowWeaveForgeOverview._initialize_viewports` [hook] `crafting_in_modded_dev.lua:5539` / `{Overview, Weapons, Properties}._create_viewport_definition` [hook] and `Overview._create_item_previewer` [hook] `_cim_mission_forge_safety.lua` | Build three forge viewports. Overview gives both weapon previews x=-0.8, marks viewport 3/`slot_ranged` with `invert_rendering`, and selects `environment/ui_weave_forge_preview_inverted` for it [src: `hero_window_weave_forge_overview.lua:202-221,332-348,385-397`] | Mid-mission: retain the native mirrored-viewport role, rewrite the returned shading environment to a mission-resident fallback, and mirror only that secondary preview's x coordinate (#882). The role producer and previewer consumer both call `_cim_forge_preview_policy` helpers, and the named runtime check drives that same handoff. | Undefined shading-env VARIATION is an uncatchable AV (§22); the substitute is residency-probed (`_cim_pick_mission_env`: ui_store_preview -> ui_hdr -> blank). Never infer overview role from `item.data.slot_type`: dual-melee careers and cross-slot loadouts legitimately put a melee item in `slot_ranged`. Keep behavior remains untouched. |
| `HeroWindowItemCustomization.{_create_item_preview_widget_definition, _register_object_sets, _update_environment}` [hook] `_cim_mission_forge_safety.lua` | Build the gear-icon preview widget + apply the shading-env VARIATION for the item [src: `hero_window_item_customization.lua`] | Skip the un-loaded preview level mid-mission; PIN the variation so `ShadingEnvironment.blend` never sees an undefined variation | `_update_environment` is the sole VARIATION writer on this surface - the §22 AV fix (issue #83/#228/#235). Do NOT route the in-mission flow onto this view (pulls `levels/ui_store_preview/world`, gt #50 crash class) |
| `HeroView.{_setup_hdr_gui, hdr_renderer, hdr_top_renderer}` [hook] `_cim_mission_forge_safety.lua` (`on_enter` #88 stays in the entry) / `HeroViewStateWeaveForge.{_setup_gamepad_gui, get_ui_renderer, set_fullscreen_effect_enable_state}` [hook/safe] `_cim_mission_forge_safety.lua`; `.update` [safe] `_cim_forge_ui_owner.lua`; `.on_exit` [safe] entry | HeroView/weave-forge-state lifecycle + HDR renderer wiring [src: `hero_view.lua:323` reads `_fetch_initial_loadout_index`; `hero_view_state_weave_forge.lua:145`] | One-shot `inventory_loadout_access` flip for the standard-crafting open (issue #88); mid-mission HDR suppression (Fix B - no HDR worlds in mission); presentation-only per-frame polish in its bounded owner | The loadout-access flip is a save->vanilla-read->restore ONE-SHOT (`_cim_open_standard_inv_pending`); a persistent flip leaked the loadout onto the ESC-menu backout mid-mission. The UI owner reads active/background state through explicit accessors. |
| `LootItemUnitPreviewer.{_spawn_link_unit, _load_item_units}` [hook] `_cim_forge_preview_owner.lua` | `_load_item_units` resolves held units and calls `load_package`; `_spawn_link_unit` directly spawns the display unit [src: `loot_item_unit_previewer.lua:246-350,453-502`] | Return early for unsafe deus/custom items under the modded forge so the preview renders empty instead of faulting; `_load_item_units` also emits the bounded #481 path/residency intake | One idempotent owner, call-time active gate, and fail-closed resource policy. No forge-store or network state. |
| `{HeroWindowWeaveForgeOverview, HeroWindowWeaveForgeWeapons, HeroWindowWeaveProperties}._create_item_previewer` [hook] shared dispatcher in `_cim_forge_preview.lua`; Overview registration remains in `_cim_mission_forge_safety.lua`, while Weapons/Properties install through `_cim_forge_preview_owner.lua`; `LootItemUnitPreviewer.spawn_units` [hook] + `.update` [safe] remain in the preview owner | Each real Athanor constructor calls `LootItemUnitPreviewer:new`, which synchronously resolves `BackendUtils.get_item_units` and queues `load_package` before returning. Properties authors every preview at `{-0.85,3,0}` while the sibling native weapon browser uses centered x=0 [src: the three `hero_window_weave_*.lua` constructors; `loot_item_unit_previewer.lua:7-30,246-305`] | #481 exposes `cim_preview_context_v1` on a stack for the synchronous Cosmetics resolver and attaches the same generation to only the returned previewer for package/spawn/update reconcile. #882 still corrects only CIM ranged properties previews to native x=0; existing bounded intake/post-Cosmetics diagnostics remain. | There is exactly one registration per constructor: Overview's #882 wrapper delegates its adjusted arguments through `invoke_constructor`; the preview owner registers Weapons then Properties between its two load guards and spawn/update diagnostics. Wrappers preserve argument/return nil holes, nesting, and error cleanup. The context contains exact backend/item/type evidence; it performs no Cosmetics call or backend write. `spawn_units` stays a full hook; `update` stays read-only one-shot `hook_safe`. |
| `{bloom-window}._set_background_bloom_intensity` [hook] `_cim_mission_forge_safety.lua` / `{upgrade-anim}._start_transition_animation` [hook] `_cim_mission_forge_safety.lua` | Background bloom intensity + forge upgrade transition animation [src: weave-forge window defs] | Full `mod:hook` (SKIP the vanilla body, not run-after) to suppress the mid-mission bloom/transition that references keep-only materials | Class resolved by `rawget` at install; `[hook]` deliberately does not call `func` |
| `HeroViewStateWeaveForge.on_exit` [safe] `crafting_in_modded_dev.lua`; restore dispatcher in `_cim_forge_picker_owner.lua` | Leaves the weave-forge state [src: `hero_view_state_weave_forge.lua`] | Clear `_custom_forge_active`; restore the widened freedom-toggle category arrays | The ONLY reset point for `_custom_forge_active`. The entry keeps the complete forge reset and calls the picker owner's stable restore dispatcher; no second exit hook or duplicate reset owner is introduced. |

### Surface 3 - Loadout equip-capture via the LA dispatch (DORMANT) (owner: `docs/engine/11`, `/06`; `_cim_modded_loadout_owner.lua`)

Both captures moved out of the entry into `_cim_modded_loadout_owner.lua` at
v0.8.119-dev (#1159), byte-identical. The independent
`_cim_loadout_wire_owner.lua` owns `PlayerManager.rpc_sync_loadout_slot` and
force-resets the retired persistence gate before this owner installs, so
sender/receiver crash safety (#278/#371) can never sit behind that gate.

| Class.method (kind) | Vanilla behavior | Why cim hooks it | Trap / invariant |
|---|---|---|---|
| `BackendUtils.set_loadout_item` [hook,tbl] `_cim_modded_loadout_owner.lua:830` | The STABLE outer equip entry point; dispatches to `get_loadout_interface_by_slot(slot):set_loadout_item(...)` [src: `backend_utils.lua:22`] | Capture every MENU equip BEFORE the LA dispatch (with Loremaster's Armoury active the inner interface is an LA CLONE that bypasses the class hook) | Table-form on the post-LA `BackendUtils` ref, installed DEFERRED from `mod.update` once interfaces exist (memory `reference_cim_equip_capture_la_dispatch`); a `_restoring` flag gates capture OFF during cim's own restore writes |
| `BackendInterfaceItemPlayfab.set_loadout_item` [safe] `_cim_modded_loadout_owner.lua:805` | Direct interface loadout write (restore path, or a bot's designated loadout) [src: `backend_interface_item_playfab.lua`] | Capture direct/data writes; record under the `optional_loadout_index` (4th arg) so a non-selected-index write lands on that index | `from_live_equip=false` (a bare data write does not re-spawn the unit) |
| `PlayerManager.rpc_sync_loadout_slot` [hook] `_cim_loadout_wire_owner.lua` | RECEIVER: decodes a synced loadout slot, `NetworkLookup.item_names[item_id]` on the numeric wire id, stores under `_player_loadouts` [src: `player_manager.lua:69`, relay at `:83`] | CONSOLIDATED: (1) #278 PRE-decode guard - `rawget(names, item_id)==nil` drops the RPC before the strict `__index` fatal; (2) post-decode "modded" rarity restore for cim clients | Thread EVERY vanilla param through unchanged (dropping trailing args corrupts the relay re-send, §19); remains a full `mod:hook` because the guard must run BEFORE vanilla decode. |

**DORMANT.** Loadout persistence is force-OFF (`_cim_loadout_wire_owner.lua`
performs `mod:set("persist_modded_loadouts", false)`, no menu toggle remains).
The capture/sync/restore machinery stays wired but no-ops - a bot gets its
DESIGNATED vanilla loadout, byte-identical to not having cim. Replacement lands
in `gut`. The `_capture_loadout_equip` + `_restore_modded_loadout` bodies still
exist so the regression sandbox can exercise the round-trip.

### Surface 4 - Illusion swap: modded-realm weapon skin apply (owner: `docs/engine/06`; `illusion_swap.lua`)

Migrated from `cosmetics_tweaker` v0.8.49; cosmetics_tweaker yields when `get_mod("cim")`
resolves, so both can co-install without doubled hooks. `docs/engine/06` owns the
`BackendUtils.get_item_units` mesh seam; see `cosmetics_tweaker/ENGINE_SURFACE.md`
for the shared skin/illusion seams this mirrors.

| Class.method (kind) | Vanilla behavior | Why cim hooks it | Trap / invariant |
|---|---|---|---|
| `BackendInterfaceItemPlayfab.get_weapon_skin_from_skin_key` [hook] `illusion_swap.lua:64` | Resolves an owned skin to `(backend_id, item)`; nil for unowned [src: `backend_interface_item_playfab.lua`] | Mint a synthetic `cim_fake_<skin_key>` id for any skin the player does not own so the illusion grid can reference it | Gated on `script_data["eac-untrusted"]` + a real IML entry + DLC gate; `rawget(ItemMasterList, ...)` because `__index` Crashifies unknown keys (§4; `item_master_list.lua:133`) |
| `HeroWindowItemCustomization._enable_craft_button` [hook] `illusion_swap.lua:86` | Enables/disables the Apply button, baking in the `eac-untrusted` gate [src: `hero_window_item_customization.lua`] | Clear `eac-untrusted` around the enable for `apply_weapon_skin`; force-clear hotspot held flags on disable to kill the fast-completion sound loop | Distinct method from `_update_state_craft_button` (that one is consolidated in `standard_forge.lua`, §1) |
| `HeroWindowItemCustomization._on_illusion_index_pressed` [hook] `illusion_swap.lua` | Handles an illusion-grid click; a locked widget keeps Apply disabled [src: `hero_window_item_customization.lua`] | Clear `content.locked=false` and retain the latest clicked skin as window-local, unpersisted #563 commit intent | Only when `not ignore_item_spawn`; still calls `func`. Preview/cancel never persists; the intent is consumed only by successful completion. |
| `BackendInterfaceCraftingPlayfab.craft` (via helper `mod._cim_try_illusion_apply`, `illusion_swap.lua`) | (see Surface 1 craft) | Write `item.skin` directly on the local backend mirror; persist CIM crafts in their forge record and server-owned items in a local map keyed by exact backend instance ID (#563) | NOT a second `craft` hook - exposed as a helper the Surface 1 `craft` hook calls FIRST (§1). Sets `bypass_skin_ownership_check` on the mirror item; never key vanilla overrides by weapon template |
| `HeroWindowItemCustomization._apply_weapon_skin_craft_complete` [safe] `illusion_swap.lua` | Semantic completion for every successful Apply Skin craft: resolves the now-current item, equips/presents it, and marks its illusion selected [src: `hero_window_item_customization.lua:2502-2547`] | Atomically replace the exact-ID saved override from the retained explicit intent (fallback: resolved final skin), including when Cosmetics Tweaker owned the local craft bypass (#563 reopened) | Persist at completion, not grid click: preview/cancel is not user commit. Retained intent prevents a ready-edge stale-A rewrite during async craft from becoming authoritative. Helper is idempotent with CIM's immediate save and logs only transitions. |
| `BackendInterfaceCraftingPlayfab.update` [safe] `illusion_swap.lua:198` | Per-frame backend interface tick [src: `backend_interface_crafting_playfab.lua`] | Deferred (one-frame) completion of the local skin apply to match vanilla async timing | Consumes `_pending_local_craft` for this interface instance |
| `BackendInterfaceCraftingPlayfab.get_unlocked_weapon_skins` [safe] `illusion_swap.lua:218` | Returns the unlocked-skin set the customization grid treats as available [src: `backend_interface_crafting_playfab.lua`] | Mark every `WeaponSkins.skins` entry unlocked on the local mirror (except unowned-DLC skins) so locked illusions become selectable | DLC gate before the `mirror._unlocked_weapon_skins[k]=true` write (CLAUDE.md "DLC Ownership Gate" place 2) |

Issue #563 also reads `BackendManagerPlayFab:is_mirror_ready()` from `mod.update`
(no additional hook). Vanilla reports ready only after the mirror has finished loading
and has no current/queued commit [src: `backend_manager_playfab.lua:1166-1171`].
`PlayFabMirrorBase.inventory_request_cb` clears/repopulates the inventory and
`_update_data` derives `item.skin` from server `CustomData.skin`
[src: `playfab_mirror_base.lua:1420-1461`, `:1723-1779`]. CIM reapplies exact-ID
local overrides on each ready edge and prunes IDs absent from the completed mirror.
The saved map is copy-on-write. An explicit successful Apply publishes the entire
next map in one `mod:set`, so a later ready edge can observe either the prior map
or the completed new map, never an intermediate delete/write. CIM forge-owned
IDs clear this separate vanilla map because their craft record is authoritative.

### Surface 5 - Custom rarity registration + cross-peer wire safety + CW compat (owner: `docs/engine/03`, `/11`; `modded_rarities.lua`, `_cim_loadout_wire_owner.lua`)

| Class.method (kind) | Vanilla behavior | Why cim hooks it | Trap / invariant |
|---|---|---|---|
| `LoadoutUtils.sync_loadout_slot` [hook,tbl] `_cim_loadout_wire_owner.lua` | SENDER: encodes a slot as `rpc_sync_loadout_slot` with rarity/properties/traits mapped through local `NetworkLookup` tables [src: `loadout_utils.lua:13-42`] | UNCONDITIONALLY coerce `rarity="modded"` -> `"unique"` on the wire (restore host-local after), so a non-cim client can decode it; external providers remain responsible for shadow-stripping their protected keys | Wire safety is NEVER toggle-gated (#278/#371, §31). A custom external trait is parked while its provider is absent, so it never reaches the live item or this encoder; WOC additionally strips its active keys for peers without WOC. |
| `[rpc] cim_modded_slot` (`mod:network_register`, `_cim_loadout_wire_owner.lua`) | - | CIM-only presentation side-channel: fire alongside each `sync_loadout_slot` so the receiver can restore or clear Modded chrome after vanilla's decode; prime the identical tri-state locally because `"others"` excludes the sender | VMF delivers only to peers with the same mod-id + handler; a vanilla client has no handler and retains the safe `unique` wire rarity. Schema-gated on `CIM_RPC_SCHEMA`. The per-(wearer,slot) value is tri-state: `true` = Modded, `false` = explicitly ordinary, `nil` = not received. Never collapse false to nil (#598/#921). No icon/model/material resource name crosses this channel. |
| `DeusRunController.get_weapon_pool` [hook] `modded_rarities.lua:243` | Iterates `pool_excludes` and nils `weapon_pool[pool_rarity][group]` [src: `deus_run_controller.lua`] | Pre-hook: scrub any `pool_excludes` rarity key absent from the base deus weapon pool (cim's "modded" rarity order=4 pollutes it, then `weapon_pool["modded"]` is nil -> index crash on the NEXT chest) | Idempotent (re-runs every chest); repairs already-contaminated runs. This is why a custom rarity must never leak into `RarityUtils.get_lower_rarities` output on the CW path |
| `_G.Localize` [hook] `modded_rarities.lua:154` | Global loc-key -> string lookup; the customization option requests `upgrade_description_text_<rarity>` [src: `hero_window_item_customization.lua:1255`] | Supply `rarity_display_name_modded`, `upgrade_description_text_modded`, and "Craft Accessories"/"Reroll Accessory *" recipe titles | VMF `_localization.lua` is NOT registered into global `Localize` (memory `reference_vmf_localize_before_registration`) |
| `HeroWindowItemCustomization._state_setup_upgrade` [safe] `modded_rarities.lua` | Creates the detailed upgrade widgets, then returns before populating them for every rarity outside the four vanilla upgrade branches [src: `hero_window_item_customization.lua:2348-2390`] | For a current `modded` item only, copy the same description into the detailed-state widget after vanilla setup | Text-only: no recipe, lock, cost, craft-button, or rarity-transition write (#263) |
| `HeroWindowLoadoutInventory.on_enter` [safe] `modded_rarities.lua:177` / `HeroWindowInventory.on_enter` [safe] `:204` | Enter the loadout/forge inventory grid; the category header reads a LITERAL "Jewellery" string, not a loc key [src: `hero_window_loadout_definitions.lua:602`] | Rewrite `self._categories[*].display_name` "Jewellery" -> "Accessories" (Localize can't catch a literal) | SINGLE `HeroWindowLoadoutInventory.on_enter` hook_safe in cim - a duplicate in `cim_debug.lua` produced a rehook warning and dropped one (§1); the autodump probe is invoked from THIS body |
| **Table contact (NOT hooks):** `modded_rarities.lua` writes `Colors.color_definitions`, `UISettings.item_rarity_order/_rarities/_textures`, `RaritySettings`, `RarityIndex`, `ORDER_RARITY`, `NetworkLookup.rarities` (append) | Rarity chrome + the strict `NetworkLookup.rarities` reverse-lookup on equip sync | Register the "modded" rarity so the grid renderer's `RaritySettings[item.rarity].order` and the equip-sync lookup don't crash | `NetworkLookup.rarities` is an APPEND (`#t+1`), so vanilla ids 1..N are unchanged - which is exactly what makes the "modded"->"unique" wire coercion above safe for every client |

### Surface 6 - Hold-Tab weapon presentation (owner: `docs/engine/03`, `/06`, `/09`; `_cim_tab_preview.lua`)

| Hook / table touched | Vanilla behavior | cim substitution | Guard / trap |
|---|---|---|---|
| `IngamePlayerListUI._update_dynamic_widget_information` [safe] `_cim_tab_preview.lua` | Hold-Tab renders `Managers.player:player_loadouts()` and calls `UIUtils.get_ui_information_from_item(item)`; remote items were reconstructed by `rpc_sync_loadout_slot`, whose payload has no skin id [src: `ingame_player_list_ui_v2.lua:1444-1539`, `loadout_utils.lua:4-42,72-91`] | After vanilla refresh, copy only melee/ranged skin identity and icon from the same player's live `inventory_system:equipment().slots[slot]`; `rpc_add_equipment` already synchronized the exact `weapon_skin_id` into `slot.skin`. Resolve rarity from the exact local boolean state and repair `slot_name .. "_rarity_texture"` in the same post-hook cycle (#598) [src: `simple_inventory_extension.lua:252-266`, `simple_husk_inventory_extension.lua:181-221`] | No custom resource identity is networked. Missing equipment/slot/skin registry fails closed; unknown exact skin logs once per key. The loadout item receives `skin` so vanilla's existing hover tooltip resolves the same illusion (#246). Rarity changes only when an exact boolean is known; absent state preserves vanilla. |

### Surface 7 - Ranald's Gift read and local build import (owner: `docs/engine/09`, `/11`; `_cim_ranalds_*.lua`)

| Engine/API contact | Vanilla behavior | cim use | Guard / invariant |
|---|---|---|---|
| `Managers.curl:post` (direct API, no hook) | `CurlManager.post` forwards the URL, body, headers, callback, userdata, and options into one asynchronous `POST` request [src: `scripts/managers/curl/curl_manager.lua:104-151`] | Read the public Ranald's Gift Firestore `builds` collection with a career filter and 16-field mask | Read-only external request; 100-document cursor pages, 800 accepted-build cap, 512 KiB per response, 4 MiB aggregate, generation cancellation, and no callback mutation. Every returned id is untrusted until live-table preflight. |
| `HeroViewStateWeaveForge.update` [hook] `_cim_forge_ui_owner.lua` | Vanilla obtains `window_input_service()` and updates/draws forge windows; `_input_blocked` selects `FAKE_INPUT_SERVICE` [src: `scripts/ui/views/hero_view/states/hero_view_state_weave_forge.lua:313-314,613-649`] | Drive the hook-free community-build scenegraph from the existing single update seam | While the modal is open only, vanilla child windows receive blocked input and the modal receives the real input service. Exact prior `_input_blocked` state is restored before return or rethrow; no second `(Class,method)` hook exists. |
| `BackendInterfaceItemPlayfab.set_loadout_item` + mirror `get_character_data` (direct local calls) | Vanilla writes an exact item id to a career slot/loadout index and the mirror exposes indexed character data [src: `scripts/managers/backend_playfab/backend_interface_item_playfab.lua:635-669`, `scripts/managers/backend_playfab/playfab_mirror_base.lua:1909-1925`] | Commit five newly synthesized CIM ids to the selected loadout and read each slot back | Complete preflight precedes mutation. The forged-item owner persists one candidate registry before publication; every slot write is checked. Any failure restores the prior five slots and deletes the exact new rows. No PlayFab craft request or new RPC is introduced. |
| `BackendInterfaceTalentsPlayfab.get_talent_tree/get_talents/set_talents` (direct local calls) | The backend interface exposes the six-row career tree and stores talent picks for an optional loadout index [src: `scripts/managers/backend_playfab/backend_interface_talents_playfab.lua:309-349`] | Validate six picks against live rows, snapshot prior picks, write the imported picks, and verify readback | Invalid/missing rows reject before mutation. A throw or mismatched readback restores the old six picks and the complete old equipment snapshot. One final live equipment refresh occurs only after all persisted writes succeed. |

## Subsystem notes (how the vanilla flow runs end-to-end, for cim's cases)

Each note is the minimum needed to read the hooks above; the owning `docs/engine`
doc carries the full architecture.

### The craft backend + what a cim-crafted item's backend record looks like (owner: `docs/engine/11`)

In modded realm the player has zero `crafting_material` items and the EAC client is
unavailable, so every real PlayFab `craft` request is rejected with the "Backend
rejected the challenge response -1" / `playfab_eac_error` (reason 511) kick. cim
replaces the whole roundtrip: the `craft` hook (`standard_forge.lua:1586`) resolves
`synth[recipe.name]`, then `_cim_craft_dispatch.execute` stashes the public result
in `_craft_requests[id]` so vanilla's `is_craft_complete(id)` poll immediately
returns true. Synths return an internal committed bit; only a successful local
transaction dirtifies presentation, while a refused transaction preserves the
public `(id, recipe)` completion shape without invalidation. Commits are BLOCKED
while the forge is open so no mutation reaches PlayFab.

Since 0.8.101-dev every acquisition enumerator and record boundary routes the
contract's REGISTERED provider gate (issues 628/682): `gate_item` for
enumerator rows (athanor_list, blacksmith_list, random_craft), `gate_record`
for record writes (mirror_injection, mirror_restore), with salvage registered
by its adapter. `cw_conversion` is explicitly classified as a non-enumerator:
the compatibility hook only scrubs unsupported rarity keys from a Chaos Wastes
exclusion map and never walks provider items. `gate_record` guarantees a
non-nil classified rejection reason - the `contract and
contract.normalize_record(...)` and/or collapse that produced 682's
`reason=nil` is forbidden by `test_cim_provider_gate.lua` and runtime check
`issue682_provider_gate_routing`.

A cim-crafted item's backend record is a bare additive item, NOT a native PlayFab
entry: `{ ItemId = <item_key>, ItemInstanceId = <backend_id>, CustomData = {
power_level, rarity="modded", properties=<cjson>, traits=<cjson> } }`. The
`backend_id` is `Application.guid()` for normal crafts, but a `cwv_<key>_NNN` string
(instance band 100..999) when the input key is a `character_weapon_variants` clone
(`cwv_variant==true`) - because CWV's render-rescue hooks key on that exact pattern
(issue #390; class 27). Persistence lives in cim's own `forged_weapons` VMF save,
NOT PlayFab - `_cim_forge_state_owner.lua` loads it at `_create_interfaces` and
`add_item`s each `via_mirror` entry back on session restore. The per-entry save
shape carries `item_key`, `properties`
(dict), `traits` (active array), `external_traits` (parked provider-owned array),
`skin`, `power_level`, `rarity`, `rerolled_*_indices`
(shuffle-bag state), and an OPAQUE `custom_glow` pass-through slot that
`cosmetics_tweaker` owns and cim never interprets. Contrast a NATIVE item, whose
identity/props/skin live in the PlayFab mirror and re-sync from the server on launch
(`docs/engine/11` bid->key->wire degrade). This is the CRAFT side of the #279/#474
husk-identity vector: the crafted item exists only in the local mirror + cim save,
so a remote peer's husk resolves the BASE `item_data` (class 27) unless a net-safe
signal reaches it.

Issue #655's provider boundary is deliberately save/load asymmetric. On load,
CIM merges active and parked traits and admits a provider-owned key only when
the exact owner and capability are registered and available; otherwise the key
stays in `external_traits` and is omitted from the live mirror payload. When WOC
registers `woc.poison_trait.v1`, CIM re-partitions existing records, updates only
newly activated exact instances, and adds the poison trait to the melee pool
once. Removing a trait through Athanor or reroll clears its parked copy so it
cannot resurrect later.

### Chaos Wastes trait particle residency

CIM can deliberately persist vanilla Morris traits outside the Chaos Wastes.
Some of those buffs resolve particle names only when their proc executes, so the
weapon or trait table does not establish a package dependency. In particular,
`deus_ranged_crit_explosion` calls `DamageUtils.create_explosion` with
`fx/cw_enemy_explosion`; every vanilla Chaos Wastes level loads
`resource_packages/dlcs/morris_ingame`, while an Adventure level does not.

`_cim_cw_trait_residency.lua` therefore owns one private
`cim_dev_cw_trait_fx` reference to that exact package for the CIM session. It
loads asynchronously at initialization (or the next game-state edge if the
package manager was not ready), guards both `has_loaded` and `is_loading`, and
never acquires from an attack, proc, or update loop. The reference is not
released while CIM is active because a persisted equipped item can retain the
trait independently of the current menu setting. `[cim:947]` reports only state
transitions. This is the class-70 native particle-residency boundary; Lua pcall
cannot contain the later `WorldApi` assertion if the resource is absent.

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
boon-filtered). The `weave_` bridge in `_forge_apply_to_item`
(`_cim_weave_loadout_owner.lua` since v0.8.120-dev) strips the leading
`weave_` to get the bare adventure key the item actually receives. The v0.8.44-dev
freedom toggles (`allow_cw_traits`, `allow_any_trait_property`) widen both surfaces,
read LIVE so `weapon_tweaker`'s runtime `WeaponTraits`/`WeaponProperties` mutation is
always reflected. For `allow_cw_traits`, `_cim_trait_slot_policy.lua` maps the exact
vanilla CW combination families to `melee`/`ranged`; the standard pool receives
`master.slot_type`, while the Athanor hook receives the selected item's
`data.slot_type`. Accessories fail closed with no CW extras; traits duplicated by
vanilla in both families remain universal. Athanor slot occupancy is capped by the distinct-property ceiling
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
cim<->cim `cim_modded_slot` side-channel restores the "modded" chrome on CIM
receivers, while the sender records the identical boolean locally because the
`others` target excludes it (#598). A vanilla client has no handler and drops the
payload harmlessly. The payload never contains an icon, model, material, or other
custom resource identifier.

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

## #749 borrowed-renderer residency boundary

The Athanor icon policy proves the resolved masked/saturated material against the
exact live Gui through `_lib_resource_residency.lua` V2. The mission forge's
shading-environment chooser uses the same strict contract; absent or unknown
owned resources select the existing safe fallback and never reach a native draw.

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
