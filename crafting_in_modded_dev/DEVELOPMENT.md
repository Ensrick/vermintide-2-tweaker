# crafting_in_modded_dev - development reference

Architectural/module reference for the ACTIVE dev stream `cim_dev` (friends-only
Workshop 3733366851). The engine contact surface (every hooked vanilla
`(Class, method)` + the paid-for dead ends) lives in `ENGINE_SURFACE.md`; this
doc is the code-layout map. Stable `crafting_in_modded/` is its read-only public
twin - all in-flight work happens here (repo `CLAUDE.md` dev/stable split).

## Module map (v0.8.120-dev, Phase 5 owner splits)

`crafting_in_modded_dev.lua` is still the primary file (2,353 nonblank lines) - this is an
IN-PROGRESS decomposition (PROJECT_STANDARDS 2.2a), not a finished one. It is,
however, the first contracted entry in the repo to land under 2.1's 2,500-line
HARD limit, which is why it no longer carries a `qa/baselines/file_sizes.json`
row; `qa/decomposition_contracts.psd1` owns its ratchet from here. The contract
state stays `partial` because `complete` additionally requires the 1,500-line
TARGET. Phase 1 carved out the three cleanest self-contained concerns; the
craft-store + backend mirror and the cross-peer wire-safety region (issue
278/371) still live in the entry, pending later phases (they are coupled to the
entry-mutable `_forged_weapons` local - see "Deferred" below). The persisted
modded-loadout store and the LA equip-capture moved out at v0.8.119-dev; the
mutable Athanor/Weaves loadout store followed at v0.8.120-dev.

Every module is `mod:dofile`'d EXACTLY ONCE from the entry manifest (VMF
`mod:dofile` is NOT a singleton - each call re-executes the file - so modules never
dofile each other). Cross-file surface is the established flat `mod._cim_*`
namespace (NOT a `mod._cim` table; the established flat names survive as-is per
2.2a point 3). The `.package` globs `scripts/mods/crafting_in_modded_dev/*`, so a
new module needs only its manifest dofile line + a row here.

| Module | Owns / public surface |
|---|---|
| `crafting_in_modded_dev.lua` (entry) | MOD_VERSION (launcher parses it here - never move it), the boot banner + rehook-warning interceptor, the settings fingerprint/dump, the `/cim_regression_test` harness (`_RT_CHECKS`, `_rt_register`, runner), four initialization-time identity/contract checks that must remain beside their local helpers, the ordered dofile manifest, and everything NOT yet extracted: the craft-store + backend mirror (`_forge_*`, `_forged_weapons`, `mod._cim_register_craft`/`_get_craft`/`_is_modded_*`), cross-peer wire safety (issue 278/371, `sync_loadout_slot` + `cim_modded_slot` RPC), the Athanor opener (`open_forge`/`open_standard_crafting`) + mutable loadout write hooks, and bubble-cap math. Keeps the issue-88 `HeroView.on_enter` inventory-access hook (shares the entry-local `_cim_open_standard_inv_pending`) and calls the picker owner's restore dispatcher from the existing forge-exit reset. |
| `_cim_command_owner.lua` | Hook-free Phase 5 owner for the three `forge_dump*` diagnostics, seven manual `/forge*` transaction commands, `/salvage_debug`, `/forge_list`, `/forge_delete`, the flat `mod._cim277_delete_owned_ids` exact-owner transaction, and the existing `/forge_delete_all` adapter install. Owns the pending manual-forge state; consumes reassigned craft/loadout stores through getters so restore cannot leave a stale table. Registration order and the stable `standard_forge.lua` public API remain unchanged. |
| `_cim_weave_economy.lua` | Phase 5 owner for the 18 read-only `BackendInterfaceWeavesPlayFab` progression/economy hooks. Preserves their original registration order and active/inactive return behavior, resolves the forward-declared bubble-cap function at callback time through an injected accessor, and installs idempotently so reload cannot duplicate hooks. Mutable Weaves loadout writes belong to `_cim_weave_loadout_owner.lua`, which installs below it and now supplies that bubble-cap function. |
| `_cim_weave_loadout_owner.lua` | Phase 5 owner for the WRITE half of the Athanor bubble grid: the amulet slot map + per-slot CRAFT dirty marks, the per-property bubble-cap math (`_bubble_cap` / `_value_for_bubbles` / `_bubbles_for_value` and the `weave_`/`properties_` key normalizer, #86/#244), `_store_property_slot` and the #86 read-chokepoint `_cap_grid_property_arrays` trim, the `movespeed_2pct_mode` buff-template patch plus its settings-change re-apply, the seed/apply pass, and the TEN mutable `BackendInterfaceWeavesPlayFab` hooks in their original order. Installs at the exact former position (after `_cim_immutable_relic_ui`, before the EAC commit block, which stays in the entry). All four reassigned entry stores - `_custom_forge_active`, `_forge_item_props`, `_forged_weapons`, `_amulet_dirty` - arrive as call-time accessors; `_forge_save` is injected directly. Publishes no `mod._cim_*` field and returns the four names the entry re-binds. It owns no view lifecycle, no persistence store, and no wire state. |
| `_cim_forge_preview_owner.lua` | Phase 5 owner for the complete Athanor weapon-preview lifecycle: unsafe-resource guard, #404/#882 properties placement install, and bounded #481 intake/spawn/post-Cosmetics diagnostics. It preserves the exact `_spawn_link_unit`, `_load_item_units`, `_create_item_previewer`, `spawn_units`, `update` registration order; the mutable forge flag is read only through a call-time accessor. Reload refreshes dependencies without duplicate hooks. It owns no forge/loadout/backend/wire writes. |
| `_cim_forge_picker_owner.lua` | Phase 5 owner for the complete Athanor picker-category lifecycle: unknown adventure/CW category seeding, native and optional freedom twin construction, temporary category widening/restoration, and the ordered `_setup_menu_options` then `_sync_backend_loadout` hooks. Its stable private backup captures every exact category-table target and original value; reinstall settles any outstanding old transaction before refreshing seven dependencies, then exhaustively republishes exactly five operations into the replaceable public owner map plus the established flat regression adapters (PROJECT_STANDARDS 2.2a rule 10). It owns no inventory, loadout, backend-write, or wire state. |
| `_cim_forge_ui_owner.lua` | Phase 5 owner for Athanor presentation helpers, the disabled legacy accessory/overview button injectors, the active accessory overlay, item tooltip/panel polish, and the sole `HeroWindowWeaveProperties._draw` then `HeroViewStateWeaveForge.update` hooks. Its 805 physical / 742 nonblank lines remain below 1,500. Mutable forge-active and background-color state plus engine manager/profile tables are explicit call-time dependencies held behind one stable idempotent dispatcher. Every fresh accessory-panel instance receives the stable late-bound craft callback before the reinstall guard; an initially unavailable optional panel can recover without duplicating hooks. It owns no forge store, loadout persistence, backend write, or network behavior. |
| `_cim_modded_loadout_owner.lua` | Phase 5 owner for the entire persisted modded-loadout path: the index-aware `career -> loadout_index -> slot -> bid` store, its save/load helpers, the one-shot flat->indexed migration and its mirror-ready timing gate, the stale-entry purge, BOTH `set_loadout_item` captures (the `BackendInterfaceItemPlayfab` hook_safe and the deferred `BackendUtils` table hook that catches menu equips through a Loremaster's Armoury cloned interface, issue #22), the restore pass + live-avatar re-equip, the #562 auto-equip-on-craft helpers, the sibling-mod restore-callback list cosmetics_tweaker registers into, and `/cim_restore_loadout`, `/cim_craft_standard`, `/cim_dump_loadout` in their original order. The whole path stays dormant in production: the master `persist_modded_loadouts` gate is force-reset OFF in the entry and injected here, so this owner reads the gate but never decides it. The forge store arrives as a call-time accessor because `_forge_load` rebinds it on every `_create_interfaces` pass. Installs idempotently; publishes the unchanged flat `mod._cim_clear_modded_loadout_for_bid(s)` / `_cim_register_restore_callback` / `_cim_auto_equip_crafted_weapon` / `_cim_auto_equip_slot_type` surface and returns the six names the entry re-binds. It owns no Athanor view lifecycle and no wire state. |
| `_cim_regression_checks.lua` | The 79-check late `/cim_regression_test` block, in its frozen registration order. Loaded once at the end of the entry after production hooks/helpers exist. Receives narrow function/state accessors for entry locals that are reassigned; checks still consume the established flat `mod._cim_*` runtime API. Together with the four initialization-time registrations retained in the entry, the complete suite has 83 checks. |
| `_cim_bulk_cleanup_core.lua` + `_cim_bulk_cleanup_command.lua` | Issue #277 exact-owner cleanup. The pure core classifies/fingerprints candidates and clears persistence references; the one-time command adapter owns `/forge_delete_all` and receives narrow accessors for the entry's reassigned craft store plus backend interfaces. Destructive scope comes only from `_cim_synthetic_item_contract.lua` and fails closed on unreadable identity or equip state. |
| `modded_rarities.lua` | Custom "modded" rarity registration (Colors/UISettings/RaritySettings/NetworkLookup table contacts), `_G.Localize` supply, deus weapon-pool scrub, Jewellery->Accessories relabel. Pre-existing. |
| `standard_forge.lua` | The standard Keep crafting bench: material-clean craft/salvage/reroll synth into the backend mirror, the EAC choke-point `craft`/`_get_valid_recipe`/`enqueue` hooks, CraftPage requirement forcing, jewelry-slot pin, and manifest owner for the salvage-button extension. Pre-existing. |
| `_cim_synthetic_item_contract.lua` | Pure #628/#822 ownership boundary shared by Athanor, standard forge, SaveWeapon import, persistence/restore, inventory, and salvage. Validates eligible CWV provider definitions before UI and rejects every WOC trophy identity even before its live marker registers; resolves one canonical acquisition identity and makes normalization consume that same resolver; normalizes one schema-versioned exact CIM instance; builds its mirror payload; preserves vanilla salvage exclusions; partitions exact-owned ids for the #277 deletion transaction. Provider definitions remain provider-owned and blacksmith selectors never become acquired instances. |
| `_cim_custom_glow_notice.lua` | Pure #48 once-per-session fallback notice policy, byte-identical across stable/dev. Counts only non-nil opaque `custom_glow` blobs after normalization, suppresses itself while Cosmetics is present or provider lookup is unproven, and never interprets or renders the blob. |
| `_cim_immutable_relic_ui.lua` | #822 Athanor edit/loadout adapter. Rejects provider-owned WOC trophy ids from saved weave loadout state, Adventure-equipped fallback, and set-loadout writes, while leaving vanilla/CWV ids on the native path. |
| `_cim_external_trait_policy.lua` | Pure #655 optional-provider boundary. Reserves exact external trait keys to their owner, validates exact provider capabilities, partitions unavailable traits into parked persistence, and inserts eligible traits into the Adventure pool idempotently. |
| `_cim_cw_trait_residency.lua` | Issue #947 exact Morris gameplay-package lease for Chaos Wastes traits persisted into Adventure. Owns one private session-long async reference, retries only on lifecycle edges, exposes bounded state diagnostics, and has no action/per-frame load or unload path. |
| `_cim_salvage_modded_button.lua` + `_cim_salvage_autofill_core.lua` | Issue #618 desktop/console salvage definition extension and input/animation hooks. Reuses vanilla's bounded rarity-fill paths; the pure core derives the fifth and sixth positions from vanilla's own rare-to-exotic spacing and is engine-free tested. The fifth control uses CIM's dedicated `store_tag_icon_weapon_modded` crossed-swords texture; `icon_bg_modded` remains item-card presentation only. |
| `_cim_trait_slot_policy.lua` | Pure #414 mapping of vanilla's three melee and six ranged Chaos Wastes trait categories to exact `slot_type`; shared by standard rerolls and the Athanor picker. |
| `_cim_property_value_policy.lua` | Pure #244 symmetric conversion between absolute Athanor/Weave bubble values and normalized two-endpoint Adventure property storage. |
| `_cim_accessory_property_policy.lua` + `_cim_accessory_property_runtime.lua` | Issue #959 category identity boundary. The pure policy owns layer-aware display counts, write admission, per-key and distinct-key capacity, removal, Clear planning, the bounded zero-mastery-costs table (array part = cap entries, integer reads up to cap*3 resolve to 0 so vanilla's global-use-count slot paint never nil-aborts), and the amulet re-seed append/clamp helper (sibling accessories sharing a property key merge instead of overwriting). The runtime adapter owns the four picker hooks while the entry's existing backend mutation hook consumes the same policy. Ordinary weapon editing retains native/global capacity semantics. |
| `_cim_bulk_accessory_craft.lua` | Pure #1031/#1032 bulk-button policy. Attempts Charm, Necklace, and Trinket through the entry's established single-slot helper regardless of session dirty flags; returns only the successful count so one missing slot cannot suppress later crafts. |
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
- **New Athanor overview/properties presentation, tooltip, accessory overlay, or
  per-frame polish behavior** -> `_cim_forge_ui_owner.lua`. Keep its two hook
  registrations ordered and singular; read mutable entry state only through
  the injected call-time accessors.
- **New Athanor trait/property category seed, native option, or freedom-toggle
  widening rule** -> `_cim_forge_picker_owner.lua`. Preserve its stable backup
  transaction and restore every temporary global category replacement at forge exit.
- **New loadout capture, restore, persistence-schema, migration, purge, or
  auto-equip-on-craft behavior** -> `_cim_modded_loadout_owner.lua`. Read the
  forge store through the injected accessor, never a captured table. Anything
  that must run regardless of the `persist_modded_loadouts` gate does NOT belong
  here: sender-side wire safety stays in the entry above the seam (#278/#371).
- **New physical Keep forge availability rule** -> `_cim_keep_forge_interaction.lua`; preserve the native stop and HUD callbacks and delegate every non-CIM boundary to the stored vanilla predicate.
- **New CW trait/category eligibility rule** -> `_cim_trait_slot_policy.lua`; keep it engine-free and cover exact vanilla category names offline.
- **New persisted trait with a string-resolved native particle** -> prove the owning vanilla package from source plus bundle inventory, then extend `_cim_cw_trait_residency.lua` with one private idempotent lease. Never load at the hit/action seam and never guess a unit path is a package.
- **New Athanor property value/range rule** -> `_cim_property_value_policy.lua`; keep it engine-free, symmetric, and preserve the entry's special discrete-property paths.
- **New read-only diagnostic dump command** with no cim-state dependency ->
  `_cim_dump_commands.lua`. A dump that reads `_custom_forge_active` / `_forged_weapons`
  belongs in accessor-backed `_cim_command_owner.lua`.
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
- **Mutable Weaves loadout store** - RESOLVED at v0.8.120-dev. The ten mutable
  `BackendInterfaceWeavesPlayFab` hooks, the bubble-cap math, and the seed/apply
  pass are now `_cim_weave_loadout_owner.lua`, joining the read-only
  progression/economy facade, weapon-preview lifecycle, picker-category
  lifecycle, and Athanor presentation owners
  (`_cim_weave_economy.lua`, `_cim_forge_preview_owner.lua`,
  `_cim_forge_picker_owner.lua`, `_cim_forge_ui_owner.lua`). The reassigned
  `_custom_forge_active` / `_forge_item_props` locals cross the seam as
  call-time accessors, the same shape the command and loadout owners use. What
  remains of the Athanor in the entry is the opener, the view-lifecycle reset,
  the craft buttons, and the EAC commit block.
- **Cross-peer wire safety** (issue 278/371) - wire-adjacent / crash-load-bearing;
  leave byte-intact until a coop re-verify window (ENGINE_SURFACE Surface 3/5).
  It sits immediately ABOVE the `_cim_modded_loadout_owner` seam, and must stay
  there: it is sender-side crash safety that can never be allowed to fall behind
  the loadout owner's persistence gate.

The command owner proves reassigned stores can cross a module boundary through narrow
getter closures without inventing a second state table or widening the flat namespace.
`_cim_modded_loadout_owner` (v0.8.119-dev) extends that pattern to a whole store: the
persisted loadout table and both LA equip-captures now live behind one seam, taking
the reassigned `_forged_weapons` through a call-time accessor.
`_cim_weave_loadout_owner` (v0.8.120-dev) is the same shape at the largest scale
so far - four reassigned stores, ten hooks, and the entry's own forward
declarations - and it is the slice that carried the entry under the 2,500-line
hard limit. The remaining slices should apply the shape to the craft-store +
backend mirror; cross-peer wire safety remains separately review-gated.
