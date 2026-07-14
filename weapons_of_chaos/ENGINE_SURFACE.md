# weapons_of_chaos - engine contact surface

What vanilla VT2/Stingray does at every seam `weapons_of_chaos` (`WOC`) touches,
and why the mod is there. This is the per-mod companion to the subsystem set in
`docs/engine/` (read `docs/engine/README.md` for house style). It does **not**
re-explain a subsystem the engine docs own, and it does **not** duplicate the
mod's `DEVELOPMENT.md` (enemy-mesh catalog, keep-trophy paths, the full
duplicate-weapon crash post-mortem) - it names each engine seam, cites the
vanilla behavior, and links out. Decompile paths are relative to
`C:\Users\danjo\source\repos\Vermintide-2-Source-Code`; `WOC` line numbers are
`weapons_of_chaos.lua` unless noted. `§N` = a `docs/BUG_CLASSES.md` class; `#N` /
"issue N" = a GitHub issue. Grep-verified 2026-07-12 against the decompile.

`WOC` lets player characters wield ENEMY weapons and named keep-trophy artifacts
via the duplicate-item approach modeled on `character_weapon_variants`: it clones
a player base weapon template into a new MoreItemsLibrary item and swaps the held
mesh to a different `.unit`. As of v0.1.11-dev there is ONE item - the Blightreaper
(Kruber 1H sword, all careers), rendered on an interim base-Empire-sword mesh
because the intended keep-trophy prop is not runtime-loadable (see dead ends). Its
engine contact is small: a display-name `Localize` hook, a registration-timing
hook, and the single wire-safety hook that keeps a non-WOC peer from crashing -
plus direct `ItemMasterList` / `NetworkLookup` table appends done outside any hook.

## Hook table

3 registration sites. `[hook]` = full wrapper (`mod:hook`, can rewrite
args/returns); `[safe]` = `mod:hook_safe` (post-callback, no override); `[tbl]` =
table-form hook (plain-table target, nil-guarded). The item and NetworkLookup
registration itself is NOT a hook - it is direct `rawset`/assignment inside the
`_register_blightreaper` chokepoint (`:230`), covered in the subsystem notes.

### Item resolution + display naming (owner docs: `docs/engine/06`, `docs/engine/09`)

| Class.method (kind) | Vanilla behavior at the seam | Why WOC hooks it | Trap / invariant |
|---|---|---|---|
| `_G.Localize` [hook,tbl] `:168` | Global loc-key -> string lookup; the inventory UI Localizes an item's `display_name` / `description` / `item_type` keys | Supply the Blightreaper display name/description/type labels for `woc_*` keys (`:168`) | VMF `_localization.lua` is NOT auto-registered into the global `Localize` (`docs/VMF_RECIPES.md`); a raw pass-through for every non-`woc_` key. `item_type` is set to `ITEM_KEY` so `Localize(item_type)` yields the item's display label, not the base weapon's |

### Registration timing (owner doc: `docs/engine/08`)

| Class.method (kind) | Vanilla behavior at the seam | Why WOC hooks it | Trap / invariant |
|---|---|---|---|
| `StateInGameRunning.on_enter` [safe] `:275` | Fires on entering the keep AND each mission load [src: `scripts/game_state/state_ingame/state_ingame_running.lua` on_enter] | Run `_register_blightreaper()` - the backend + `ItemMasterList` + `NetworkLookup` injection, deferred here because the backend is nil at mod init (`:275`) | One-shot `_registered` guard makes re-fires a no-op (CWV registration-timing pattern); registration is also gated on the `enable_blightreaper` setting and on `MoreItemsLibrary` being present |

### Wire safety - never crash a non-WOC peer (row-of-concern: issue 422 / issue 278) (owner doc: `docs/engine/03`)

| Class.method (kind) | Vanilla behavior at the seam | Why WOC hooks it | Trap / invariant |
|---|---|---|---|
| `LoadoutUtils.sync_loadout_slot` [hook,tbl] | Encodes `item.key` as `NetworkLookup.item_names[item_key]` for direct, host-broadcast, client-to-server, and hot-join sync [src: `scripts/helpers/loadout_utils.lua:12-53`; decode at `:69-83`] | Observe the exact Blightreaper backend item for live #509 evidence; preserve its inherited vanilla identity, while `_woc_wire_policy.lua` substitutes any future explicit `woc_` key with a vanilla `BASE_WEAPON` shadow | ROW-OF-CONCERN. Native parsing stamps the cloned base entry `key/name = es_1h_sword` [src: `scripts/settings/equipment/item_master_list.lua:109-112`], and MIL uses `item.key` for backend `ItemId/key`, so the current item already sends a boot-stable identity. WOC still appends `ITEM_KEY` locally for explicit-key consumers; any future `woc_` item must never emit that order-dependent id. The policy is unconditional, shallow-copy/non-mutating, and fails closed if the base index is unavailable. |

## Subsystem notes (how the vanilla flow runs end-to-end, for WOC's cases)

Each note is the minimum needed to read the hooks above; the owning `docs/engine`
doc and `DEVELOPMENT.md` carry the full architecture.

### Item registration is direct table injection, not a hook (owner: `docs/engine/06`)

`_register_blightreaper` (`:230`) clones the base `es_1h_sword` `ItemMasterList`
entry via `_build_entry` (`:179`), hands it to
`MoreItemsLibrary:add_mod_items_to_local_backend`, then mirrors it into
`ItemMasterList[ITEM_KEY]` so vanilla equip/preview paths resolve it -
`HeroPreviewer.equip_item` does `ItemMasterList[item_name]` [src: engine], and the
missing-key `__index` on `ItemMasterList` throws, so the read/write both go through
`rawget`/direct assignment. The clone deliberately keeps the inherited
`entry.name` = `es_1h_sword` (clobbering it breaks the vanilla equip fallback
`ItemMasterList[item.name]`, the CWV clone-name lesson `feedback_cwv_clone_name_clobber`)
and strips `required_dlc = nil` (a new mod item reusing base-package meshes; the
per-career DLC gate is enforced by the game's own equip check - same intentional
strip as CWV `_build_entry`).

Native `parse_item_master_list` has already stamped that base row with both
`key` and `name` equal to `es_1h_sword` [src:
`scripts/settings/equipment/item_master_list.lua:109-112`]. MoreItemsLibrary's
backend conversion then selects `mod_data.key or item.key or default_item_name`
for both `ItemId` and `key` (`MoreItemsLibrary.lua:343-344`). WOC does not
override those `mod_data` fields, so the actual Blightreaper backend row is
vanilla-keyed even though its backend instance id and presentation are WOC-owned.
Runtime check `issue509_registered_blightreaper_wire_contract` asserts this
against the live backend mirror rather than relying only on static source.

### NetworkLookup append + the wire-safety consequence (owner: `docs/engine/03`)

Registration also appends `ITEM_KEY` into `NetworkLookup.item_names` as a local
index (`#tbl + 1`, `:264`), via `rawset` because the table has an error-throwing
`__index`. That append is per-peer and order-dependent, so the numeric id a
`woc_` key gets is not stable across peers - a host with WOC and a client without
it disagree, and the client's decode hits the strict `__index`
[src: `network_lookup.lua:2362`] -> CTD (issue 278 class). The `sync_loadout_slot`
hook (table above) is the defense-in-depth boundary: current MIL-created
Blightreaper rows pass through by identity because they inherit `es_1h_sword`;
any explicit present/future `woc_` row is substituted with a `BASE_WEAPON`
shadow before encode. `WOC` applies no skin and rarity `"default"` (a vanilla
index), so unlike CWV there is no skin/rarity axis to substitute, only the item-name axis
(`docs/engine/03` §31; project `project_vt2_cross_peer_wire_safety`).

### Held-mesh derivation (owner: `docs/engine/06`)

The interim `HELD_UNIT` is the base Empire sword's `right_hand_unit` - always
resident with the player loadout and carrying a real `<unit>_3p` sibling, so
vanilla's 1P/3P derivation in `gear_utils.lua` (append `_3p` to `right_hand_unit`)
just works with no force-load and no special-case spawn. Pointing the held mesh at
a genuine enemy `.unit` later is where the residency and `_3p`-sibling problems in
the dead-ends section bite (`docs/engine/05`, `docs/engine/06`).

## What the engine will NOT let us do (dead ends, already paid for)

Pulled from `DEVELOPMENT.md` (the duplicate-weapon crash post-mortem) and the
in-file header - do not re-discover these.

- **The keep-trophy diorama prop is NOT runtime-loadable as a weapon mesh.**
  `units/props/inn/hub_trophy/hub_trophy_bogenhafen` has no standalone `.package`,
  is absent from the boot-loaded `resource_packages/dlcs/bogenhafen` and base
  `resource_packages/levels/inn` bundles (verified with `vt2_bundle_unpacker`),
  and is loaded on-demand only by the keep-decoration system.
  `Managers.package:load` on its UNIT path HARD-CRASHED on keep entry - an engine
  `resource_package()` C-fatal that bypasses the surrounding `pcall` (confirmed
  Blightreaper v0.1.1-dev). To wield it you must EXTRACT and author a real weapon
  `.unit` (its own `_3p` sibling + a loadable package). General rule: never
  `Managers.package:load` a unit path, only a real `.package` NAME you have
  verified contains the unit (memory
  `reference_vt2_package_load_needs_package_not_unit_path`).
- **Enemy weapon meshes have no `_3p` sibling and use a different attach rig.**
  Meshes under `units/weapons/enemy/...` are a single model with no first-person
  variant, and attach via `AttachmentNodeLinking.ai_1h_weapon` on an enemy
  skeleton [src: `scripts/settings/ai_inventory_templates.lua`], not the player
  weapon attach system. The cloned player `template` supplies the player-side
  attach, but grip offset / scale / rotation almost always need tuning, applied on
  3P units only (memory `feedback_cross_char_transforms_3p_only`).
- **A duplicate-item mod that copies the item layer but not the wire layer ships a
  latent non-peer CTD.** `WOC` reproduced CWV's `ItemMasterList` / MIL / display
  machinery yet omitted CWV's `sync_loadout_slot` net-safe hook; the result was
  issue 422 - a `woc_` id on the wire fataling every non-WOC peer at
  `network_lookup.lua:2362`. Wire safety is a mandatory, non-optional layer of the
  duplicate-item pattern, not a follow-up (`docs/engine/03` §31).
- **The keep display prop and the wieldable weapon share a name but are different
  units.** `Trophies.hub_trophy_*` [src: `scripts/settings/trophies.lua:46-81`]
  are posed statues/dioramas, NOT the weapon mesh; the wieldable artifact is the
  boss's enemy weapon `.unit` in `ai_inventory_templates.lua` (Nurgloth ->
  `wpn_chaos_sorcerer_scythe_01` at `:699`). Cloning the statue gets you a
  diorama, not a sword.

## Doc maintenance

Follows `docs/engine/README.md` maintenance rules: if a WOC hook moves, a guard is
added, or a cited vanilla line drifts after a game patch, edit the affected row in
the SAME commit. This doc complements, and must not duplicate, `DEVELOPMENT.md`
(the enemy-mesh catalog + full crash post-mortem) - when a new enemy weapon lands,
`DEVELOPMENT.md` is the primary and this doc gains rows only if the new item adds a
new engine seam (e.g. a package force-load once a real enemy `.unit` is authored).
The load-bearing wire-safety citations (`loadout_utils.lua:25/72`,
`network_lookup.lua:2362`) were re-verified this pass. `StateInGameRunning.on_enter`
interior line is `[unverified]` (class + method grep-confirmed via the CWV
precedent; the exact decompile line was not pinned this pass) - replace when next
touched. Line numbers are against the 2026-07-12 decompile - match crash logs by
function name, not line. Section shape (hook table -> subsystem notes -> dead
ends) matches `character_weapon_variants/ENGINE_SURFACE.md`. Reverse index:
`docs/engine/README.md` "Per-mod surface docs".
