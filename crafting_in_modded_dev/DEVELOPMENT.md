# crafting_in_modded_dev - development reference

Architectural/module reference for the ACTIVE dev stream `cim_dev` (friends-only
Workshop 3733366851). The engine contact surface (every hooked vanilla
`(Class, method)` + the paid-for dead ends) lives in `ENGINE_SURFACE.md`; this
doc is the code-layout map. Stable `crafting_in_modded/` is its read-only public
twin - all in-flight work happens here (repo `CLAUDE.md` dev/stable split).

## Module map (v0.8.93-dev, Phase 2 regression split)

`crafting_in_modded_dev.lua` is still the primary file (~6,150 lines) - this is an
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
| `crafting_in_modded_dev.lua` (entry) | MOD_VERSION (launcher parses it here - never move it), the boot banner + rehook-warning interceptor, the settings fingerprint/dump, the `/cim_regression_test` harness (`_RT_CHECKS`, `_rt_register`, runner), four initialization-time identity/contract checks that must remain beside their local helpers, the ordered dofile manifest, and everything NOT yet extracted: the craft-store + backend mirror (`_forge_*`, `_forged_weapons`, `mod._cim_register_craft`/`_get_craft`/`_is_modded_*`), cross-peer wire safety (issue 278/371, `sync_loadout_slot` + `cim_modded_slot` RPC), the LA equip-capture (dormant), the modded-loadout store + restore, the Athanor opener (`open_forge`/`open_standard_crafting`) + the whole Athanor UI + `~25` `BackendInterfaceWeavesPlayFab` economy hooks (gated on `_custom_forge_active`), the amulet/accessory craft buttons, bubble-cap math, the forge-freedom picker widener, and the remaining `forge_dump*` / manual `/forge*` commands. Keeps the issue-88 `HeroView.on_enter` inventory-access hook (shares the entry-local `_cim_open_standard_inv_pending`). |
| `_cim_regression_checks.lua` | The 78-check late `/cim_regression_test` block, in its frozen registration order. Loaded once at the end of the entry after production hooks/helpers exist. Receives narrow function/state accessors for entry locals that are reassigned; checks still consume the established flat `mod._cim_*` runtime API. |
| `_cim_bulk_cleanup_core.lua` + `_cim_bulk_cleanup_command.lua` | Issue #277 exact-owner cleanup. The pure core classifies/fingerprints candidates and clears persistence references; the one-time command adapter owns `/forge_delete_all` and receives narrow accessors for the entry's reassigned craft store plus backend interfaces. Destructive scope comes only from `_cim_synthetic_item_contract.lua` and fails closed on unreadable identity or equip state. |
| `modded_rarities.lua` | Custom "modded" rarity registration (Colors/UISettings/RaritySettings/NetworkLookup table contacts), `_G.Localize` supply, deus weapon-pool scrub, Jewellery->Accessories relabel. Pre-existing. |
| `standard_forge.lua` | The standard Keep crafting bench: material-clean craft/salvage/reroll synth into the backend mirror, the EAC choke-point `craft`/`_get_valid_recipe`/`enqueue` hooks, CraftPage requirement forcing, jewelry-slot pin, and manifest owner for the salvage-button extension. Pre-existing. |
| `_cim_synthetic_item_contract.lua` | Pure #628 ownership boundary shared by Athanor, standard forge, SaveWeapon import, persistence/restore, inventory, and salvage. Validates eligible CWV/WOC provider definitions before UI; resolves one canonical acquisition identity and makes normalization consume that same resolver; normalizes one schema-versioned exact CIM instance; builds its mirror payload; preserves vanilla salvage exclusions; partitions exact-owned ids for the #277 deletion transaction. Provider definitions remain provider-owned and blacksmith selectors never become acquired instances. |
| `_cim_external_trait_policy.lua` | Pure #655 optional-provider boundary. Reserves exact external trait keys to their owner, validates exact provider capabilities, partitions unavailable traits into parked persistence, and inserts eligible traits into the Adventure pool idempotently. |
| `_cim_cw_trait_residency.lua` | Issue #947 exact Morris gameplay-package lease for Chaos Wastes traits persisted into Adventure. Owns one private session-long async reference, retries only on lifecycle edges, exposes bounded state diagnostics, and has no action/per-frame load or unload path. |
| `_cim_salvage_modded_button.lua` + `_cim_salvage_autofill_core.lua` | Issue #618 desktop/console salvage definition extension and input/animation hooks. Reuses vanilla's bounded rarity-fill paths; the pure core derives the fifth and sixth positions from vanilla's own rare-to-exotic spacing and is engine-free tested. The fifth control uses CIM's dedicated `store_tag_icon_weapon_modded` crossed-swords texture; `icon_bg_modded` remains item-card presentation only. |
| `_cim_trait_slot_policy.lua` | Pure #414 mapping of vanilla's three melee and six ranged Chaos Wastes trait categories to exact `slot_type`; shared by standard rerolls and the Athanor picker. |
| `_cim_property_value_policy.lua` | Pure #244 symmetric conversion between absolute Athanor/Weave bubble values and normalized two-endpoint Adventure property storage. |
| `_cim_template_catalog.lua` + `_cim_template_selector.lua` | Pure #524 standard Craft Item selector policy. Ordinary helper aliases collapse by stable `slot_type + item_type`; provider `cim_craft_family` is an explicit override; authored CWV keys remain exact and distinct. The catalog chooses a deterministic real row and the selector compacts/reconciles session rows by the same family identity. `_cim_synthetic_item_contract.lua` supplies exact key plus selector/instance role, and the final picker seam rejects crafted instances without deleting or merging their persistent inventory records. |
| `_cim_keep_forge_interaction.lua` | Issue #624 data-registry adapter for `InteractionDefinitions.forge_access.client.can_interact`. Restores the native world-object interaction only for `eac-untrusted` sessions in a live hub, stores the original predicate once for reload safety, and leaves the native stop/prompt/controller flow untouched. |
| `_cim_athanor_icon_policy.lua` | Pure #617 fail-closed resource policy for Athanor selector icons. Resolves the atlas material variant required by the widget's exact masked/saturated flags, proves it against the live top Gui, and substitutes only renderer-proven provider/base/vanilla fallbacks without mutating ItemMasterList. |
| `_cim_forge_widget_material_policy.lua` | Pure #83 dynamic-widget closure. Walks post-construction scrollbar widgets, renderer-proofs every texture-bearing pass, and clone-on-write disables only an unsafe pass so shared definitions, safe siblings, and later Keep instances remain unchanged. |
| `illusion_swap.lua` | Modded-realm weapon-skin apply (migrated from cosmetics_tweaker v0.8.49); synthetic skin ids, Apply-button eac-clear, unlocked-skin marking. Pre-existing. |
| `saveweapon_import.lua` | One-shot SaveWeapon-mod importer command. Pre-existing. |
| `_accessory_craft_panel.lua` | The 3-per-slot accessory craft-button overlay (own scenegraph). Pre-existing. |
| `cim_debug.lua` | `mod._cim_autodump_*` helpers (no-op when `debug_mode` OFF) + the `HeroWindowWeaveProperties.on_enter` HDR/skilltree re-suppression (calls `_cim_mission_forge_safety`'s helpers at runtime). Pre-existing. |
| `_diag_probe.lua` | Issue 174 passive loadout-attribution printf probe. Pre-existing. |
| **`_cim_inventory_filter.lua`** (NEW, 186 ln) | The modded-realm inventory/salvage grid filters: `BackendInterfaceItemPlayfab.get_filtered_items` (versus-twin re-hide + modded-only filter + `can_craft_with` template injection) and `BackendInterfaceCommon.filter_items` (salvage surfacing), plus the `_cim_is_versus_key` / `_cim_is_leaked_versus_twin` discriminators (published on `mod._cim_*`) and `_WEAPON_SLOT_TYPES`. Consumes `mod._cim_is_modded_backend_id`/`_is_modded_item`/`_inject_templates`/`_standard_forge_active`/`_autodump_filtered_items` from the entry at RUNTIME. |
| **`_cim_mission_forge_safety.lua`** | Every mid-mission render-safety guard that lets the Athanor + gear-icon customization preview open without crashing when NOT in the keep: shading-env substitution, preview-level strip + blend-variation pin, dynamic `_setup_weapon_stats` list-material closure, gamepad-GUI guard, HeroView HDR-gui skip + renderer fallback, and the HDR-glow / skilltree-ring / bloom-pulse / upgrade-anim draw suppressors. All gate on `_is_in_keep()` (published as `mod._cim_is_in_keep`); keep path byte-unchanged. |
| **`_cim_dump_commands.lua`** (NEW, 171 ln) | The two read-only diagnostic chat commands `/cim_dump_active_window` and `/craft_dump` (engine reads only; no cim state). |
| `_cim_tab_preview.lua` + `_cim_tab_preview_core.lua` | Issue #246 Hold-Tab weapon-icon reconciliation. Reads the exact skin already synchronized into live inventory equipment, updates only melee/ranged player-list presentation, and exposes a pure fail-closed resolver for offline coverage. |

### Where new code goes

- **New mid-mission render-safety guard** (shading-env, HDR, a keep-only-material crash
  in the forge/customization view) -> `_cim_mission_forge_safety.lua`; gate on
  `_is_in_keep()`; grep ALL files for an existing hook on the `(Class, method)` first
  (VMF drops the second - NON-NEGOTIABLE 8).
- **New inventory/salvage grid filter behavior** -> `_cim_inventory_filter.lua`.
- **New synthetic-item field, provider adapter, mirror payload, or salvage eligibility rule** -> `_cim_synthetic_item_contract.lua`; all creation paths must normalize before `add_item` and register the same normalized record after a successful add.
- **New standard Salvage autofill presentation/input behavior** -> `_cim_salvage_modded_button.lua`; keep layout transformation in the pure `_cim_salvage_autofill_core.lua` and delegate selection to vanilla's fill paths.
- **New standard Craft Item selector identity/filter behavior** -> `_cim_template_catalog.lua` for catalog construction and `_cim_template_selector.lua` for live-row reconciliation. Never dedupe by localized display text.
- **New Athanor selector icon/provider support** -> `_cim_athanor_icon_policy.lua`. Register an explicit provider fallback, but retain exact-Gui material proof; package residency or an atlas entry alone is not renderability.
- **New dynamically produced Athanor list widget/material** -> `_cim_forge_widget_material_policy.lua` plus the narrow producer hook in `_cim_mission_forge_safety.lua`. Never rely only on static `create_ui_elements` arrays, and clone shared pass definitions before suppression.
- **New physical Keep forge availability rule** -> `_cim_keep_forge_interaction.lua`; preserve the native stop and HUD callbacks and delegate every non-CIM boundary to the stored vanilla predicate.
- **New CW trait/category eligibility rule** -> `_cim_trait_slot_policy.lua`; keep it engine-free and cover exact vanilla category names offline.
- **New persisted trait with a string-resolved native particle** -> prove the owning vanilla package from source plus bundle inventory, then extend `_cim_cw_trait_residency.lua` with one private idempotent lease. Never load at the hit/action seam and never guess a unit path is a package.
- **New Athanor property value/range rule** -> `_cim_property_value_policy.lua`; keep it engine-free, symmetric, and preserve the entry's special discrete-property paths.
- **New read-only diagnostic dump command** with no cim-state dependency ->
  `_cim_dump_commands.lua`. A dump that reads `_custom_forge_active` / `_forged_weapons`
  stays in the entry until those locals are promoted (Phase 2).
- **New regression check** -> add `_rt_register("name", fn)` in
  `_cim_regression_checks.lua` in the existing registration order. A check that SOURCE-SCANS a module's file
  must anchor `debug.getinfo` on a function DEFINED in that module (e.g.
  `mod._cim_sweep_leaked_hdr_worlds`), never on `_rt_register` (entry).
- **New cross-file value** -> publish `mod._cim_<name>` in the owning module and reference
  it via the namespace at RUNTIME (call-time), so dofile order stays free. If an entry
  regression body must reference a moved local by its bare name, keep a
  `local <name> = mod._cim_<name>` alias in the entry (as `_is_in_keep` does).

The regression installer is the one exception to the ordinary public surface:
entry-local mutable stores are supplied through getter/setter closures so tests
cannot retain stale tables after `_forge_load` or `_modded_loadout_load` reassigns
them. Those closures are private installer context, not new `mod._cim_*` API.

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
