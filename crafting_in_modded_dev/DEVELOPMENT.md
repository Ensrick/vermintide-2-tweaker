# crafting_in_modded_dev - development reference

Architectural/module reference for the ACTIVE dev stream `cim_dev` (friends-only
Workshop 3733366851). The engine contact surface (every hooked vanilla
`(Class, method)` + the paid-for dead ends) lives in `ENGINE_SURFACE.md`; this
doc is the code-layout map. Stable `crafting_in_modded/` is its read-only public
twin - all in-flight work happens here (repo `CLAUDE.md` dev/stable split).

## Module map (v0.8.55-dev, Phase 1 OOP split)

`crafting_in_modded_dev.lua` is still the primary file (~7,007 lines) - this is an
IN-PROGRESS decomposition (PROJECT_STANDARDS 2.2a), not a finished one. Phase 1
carved out the three cleanest self-contained concerns; the craft-store + backend
mirror, the cross-peer wire-safety region (issue 278/371), the LA equip-capture,
and the whole Athanor UI + Weaves economy still live in the entry, pending later
phases (they are coupled to the entry-mutable `_forged_weapons` /
`_custom_forge_active` / `_modded_loadout` locals - see "Deferred" below).

Every module is `mod:dofile`'d EXACTLY ONCE from the entry manifest (VMF
`mod:dofile` is NOT a singleton - each call re-executes the file - so modules never
dofile each other). Cross-file surface is the established flat `mod._cim_*`
namespace (NOT a `mod._cim` table; the established flat names survive as-is per
2.2a point 3). The `.package` globs `scripts/mods/crafting_in_modded_dev/*`, so a
new module needs only its manifest dofile line + a row here.

| Module | Owns / public surface |
|---|---|
| `crafting_in_modded_dev.lua` (entry) | MOD_VERSION (launcher parses it here - never move it), the boot banner + rehook-warning interceptor, the settings fingerprint/dump, the `/cim_regression_test` harness (`_RT_CHECKS` + `_rt_register` + all 57 check BODIES - they close over entry state / call the `mod._cim_*` helpers at runtime, the weapon_tweaker precedent), the dofile manifest, and everything NOT yet extracted: the craft-store + backend mirror (`_forge_*`, `_forged_weapons`, `mod._cim_register_craft`/`_get_craft`/`_is_modded_*`), cross-peer wire safety (issue 278/371, `sync_loadout_slot` + `cim_modded_slot` RPC), the LA equip-capture (dormant), the modded-loadout store + restore, the Athanor opener (`open_forge`/`open_standard_crafting`) + the whole Athanor UI + `~25` `BackendInterfaceWeavesPlayFab` economy hooks (gated on `_custom_forge_active`), the amulet/accessory craft buttons, bubble-cap math, the forge-freedom picker widener, and the `forge_dump*` / manual `/forge*` commands. Keeps the issue-88 `HeroView.on_enter` inventory-access hook (shares the entry-local `_cim_open_standard_inv_pending`). |
| `_cim_regression`... (see note) | The regression HARNESS is inline in the entry (not yet a module). |
| `modded_rarities.lua` | Custom "modded" rarity registration (Colors/UISettings/RaritySettings/NetworkLookup table contacts), `_G.Localize` supply, deus weapon-pool scrub, Jewellery->Accessories relabel. Pre-existing. |
| `standard_forge.lua` | The standard Keep crafting bench: material-clean craft/salvage/reroll synth into the backend mirror, the EAC choke-point `craft`/`_get_valid_recipe`/`enqueue` hooks, CraftPage requirement forcing, jewelry-slot pin. Pre-existing. |
| `_cim_trait_slot_policy.lua` | Pure #414 mapping of vanilla's three melee and six ranged Chaos Wastes trait categories to exact `slot_type`; shared by standard rerolls and the Athanor picker. |
| `_cim_property_value_policy.lua` | Pure #244 symmetric conversion between absolute Athanor/Weave bubble values and normalized two-endpoint Adventure property storage. |
| `illusion_swap.lua` | Modded-realm weapon-skin apply (migrated from cosmetics_tweaker v0.8.49); synthetic skin ids, Apply-button eac-clear, unlocked-skin marking. Pre-existing. |
| `saveweapon_import.lua` | One-shot SaveWeapon-mod importer command. Pre-existing. |
| `_accessory_craft_panel.lua` | The 3-per-slot accessory craft-button overlay (own scenegraph). Pre-existing. |
| `cim_debug.lua` | `mod._cim_autodump_*` helpers (no-op when `debug_mode` OFF) + the `HeroWindowWeaveProperties.on_enter` HDR/skilltree re-suppression (calls `_cim_mission_forge_safety`'s helpers at runtime). Pre-existing. |
| `_diag_probe.lua` | Issue 174 passive loadout-attribution printf probe. Pre-existing. |
| **`_cim_inventory_filter.lua`** (NEW, 186 ln) | The modded-realm inventory/salvage grid filters: `BackendInterfaceItemPlayfab.get_filtered_items` (versus-twin re-hide + modded-only filter + `can_craft_with` template injection) and `BackendInterfaceCommon.filter_items` (salvage surfacing), plus the `_cim_is_versus_key` / `_cim_is_leaked_versus_twin` discriminators (published on `mod._cim_*`) and `_WEAPON_SLOT_TYPES`. Consumes `mod._cim_is_modded_backend_id`/`_is_modded_item`/`_inject_templates`/`_standard_forge_active`/`_autodump_filtered_items` from the entry at RUNTIME. |
| **`_cim_mission_forge_safety.lua`** (NEW, 901 ln) | Every mid-mission render-safety guard that lets the Athanor + gear-icon customization preview open without crashing when NOT in the keep: shading-env substitution (`_cim_pick_mission_env`, the 3 `_create_viewport_definition` hooks), preview-level strip + blend-variation pin (`HeroWindowItemCustomization` `_create_item_preview_widget_definition`/`_register_object_sets`/`_update_environment`), gamepad-GUI guard (`HeroViewStateWeaveForge` `_setup_gamepad_gui`/`get_ui_renderer`), HeroView HDR-gui skip + renderer fallback (`_setup_hdr_gui`/`hdr_renderer`/`hdr_top_renderer`, `mod._cim_sweep_leaked_hdr_worlds`), and the HDR-glow / skilltree-ring / bloom-pulse / upgrade-anim draw suppressors (`create_ui_elements`/`_set_background_bloom_intensity`/`_start_transition_animation` loops). All gate on `_is_in_keep()` (published as `mod._cim_is_in_keep`); keep path byte-unchanged. |
| **`_cim_dump_commands.lua`** (NEW, 171 ln) | The two read-only diagnostic chat commands `/cim_dump_active_window` and `/craft_dump` (engine reads only; no cim state). |
| `_cim_tab_preview.lua` + `_cim_tab_preview_core.lua` | Issue #246 Hold-Tab weapon-icon reconciliation. Reads the exact skin already synchronized into live inventory equipment, updates only melee/ranged player-list presentation, and exposes a pure fail-closed resolver for offline coverage. |

### Where new code goes

- **New mid-mission render-safety guard** (shading-env, HDR, a keep-only-material crash
  in the forge/customization view) -> `_cim_mission_forge_safety.lua`; gate on
  `_is_in_keep()`; grep ALL files for an existing hook on the `(Class, method)` first
  (VMF drops the second - NON-NEGOTIABLE 8).
- **New inventory/salvage grid filter behavior** -> `_cim_inventory_filter.lua`.
- **New CW trait/category eligibility rule** -> `_cim_trait_slot_policy.lua`; keep it engine-free and cover exact vanilla category names offline.
- **New Athanor property value/range rule** -> `_cim_property_value_policy.lua`; keep it engine-free, symmetric, and preserve the entry's special discrete-property paths.
- **New read-only diagnostic dump command** with no cim-state dependency ->
  `_cim_dump_commands.lua`. A dump that reads `_custom_forge_active` / `_forged_weapons`
  stays in the entry until those locals are promoted (Phase 2).
- **New regression check** -> `_rt_register("name", fn)` inline in the entry next to the
  code it probes (the harness is inline there). A check that SOURCE-SCANS a module's file
  must anchor `debug.getinfo` on a function DEFINED in that module (e.g.
  `mod._cim_sweep_leaked_hdr_worlds`), never on `_rt_register` (entry).
- **New cross-file value** -> publish `mod._cim_<name>` in the owning module and reference
  it via the namespace at RUNTIME (call-time), so dofile order stays free. If an entry
  regression body must reference a moved local by its bare name, keep a
  `local <name> = mod._cim_<name>` alias in the entry (as `_is_in_keep` does).

### Deferred (why the big regions stayed in the entry)

Phase 1 was strictly VERBATIM function-bag moves (byte-compared). These regions could
not move verbatim because they close over entry-mutable locals that are REASSIGNED (so a
cross-file alias would go stale) or are load-bearing crash paths needing a coop re-verify:

- **Craft-store + backend mirror** (`_forged_weapons`, reassigned in `_forge_load`; 40
  refs across migration/apply/inject/diag/regression). Moving it needs a clear-in-place
  edit (not verbatim) or the whole Athanor to move with it.
- **Athanor UI + Weaves economy** (`~40` hooks gated on the entry-local
  `_custom_forge_active`, 60 refs, reassigned). Needs `_custom_forge_active` promoted to a
  namespace state field first.
- **Cross-peer wire safety** (issue 278/371) and **LA equip-capture** - wire-adjacent /
  crash-load-bearing; leave byte-intact until a coop re-verify window (ENGINE_SURFACE
  Surface 3/5).

Recommended Phase 2: promote `_custom_forge_active` (+ `_forged_weapons`) to a `mod._cim`
state table, then extract the Athanor UI, the Weaves economy hooks, and the craft-store.
