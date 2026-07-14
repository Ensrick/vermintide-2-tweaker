# cosmetics_tweaker - engine contact surface

What vanilla VT2/Stingray does at every seam `cosmetics_tweaker` touches, and why
the mod is there. This is the per-mod companion to the subsystem set in
`docs/engine/` (read `docs/engine/README.md` for house style). It does **not**
re-explain a subsystem the engine docs own - it names the seam, cites the vanilla
behavior, and links out. Where a seam is byte-shared with `cwv`, this doc reuses
`character_weapon_variants/ENGINE_SURFACE.md`'s vanilla citations and keeps the
"why" column cosmetics-specific. Decompile paths are relative to
`C:\Users\danjo\source\repos\Vermintide-2-Source-Code`; `cos` line numbers are
`cosmetics_tweaker.lua` unless a `_*.lua` module is named. `§N` = a
`docs/BUG_CLASSES.md` class; `#N` / "issue N" = a GitHub issue. Grep-verified
2026-07-11 against the decompile and the mod source.

`cosmetics_tweaker` is a wide, not deep, engine-contact mod: it recolours and
re-meshes hats, weapon skins, shields and glow **without** minting new item
templates (that is `cwv`'s job). So it hooks the same display and wire seams `cwv`
does, plus five subsystems `cwv` never touches: the Loremaster's Armoury (LA)
clone-backend bridge, the MaterialSettingsTemplates glow pipeline, the embedded
Material-Hijack texture/package hijack, the `CosmeticUtils` GameSession cosmetic
sync channel, and hat/attachment unit spawning.

## Hook table

≈70 behavioral registration sites across six runtime modules
(`cosmetics_tweaker.lua`, `_la_bridge.lua`, `_material_hijack_embedded[_anim].lua`,
`_la_prefix_embedded.lua`, `_la_okri.lua`, `_moreitemslibrary_embedded.lua`,
`_la_persistence.lua`, `_tpe.lua`), plus diagnostic-only hooks in `_ui_dump.lua` /
`_cos_diag_lasync.lua` (not covered here). Grouped below into 10 rows-of-concern.
`[hook]` = full wrapper (`mod:hook`); `[safe]` = `mod:hook_safe` (post-callback,
no override); `[tbl]` = table-form hook against a plain table (nil-guarded).

> **v0.9.77-dev Phase 1 OOP split.** The three unlock/illusion hooks moved into new
> modules now cite the OWNING FILE instead of a `cosmetics_tweaker.lua:NNNN` line:
> `get_unlocked_weapon_skins` + `_G.Localize` -> `_cos_illusions.lua`;
> `_create_fake_inventory_items` + `get_unlocked_cosmetics` -> `_cos_unlocks.lua`.
> File-name-only (no line) was chosen deliberately because later decomposition
> phases will churn line numbers again — match these by function name. The
> `cosmetics_tweaker.lua:NNNN` line refs on the ROWS THAT DID NOT MOVE predate the
> split (the entry lost ~1,060 lines above them), so those too are now approximate;
> match by function name until a later phase reconciles them. See
> `DEVELOPMENT.md` "Module map".
>
> **v0.9.78-dev Phase 2 OOP split.** No HOOK moved this phase, so every row below
> still names the same owning file/line as before (all `cosmetics_tweaker.lua`,
> now ~144 lines shorter above these rows — approximate, match by function name).
> What moved is the non-hook render-path scale/grip APPLY layer
> (`_scale_units` / `_offset_units` / `_apply_unit_path_scale_hand` + the
> `_unit_path_scale_overrides` / `_weapon_grip_offsets` tables + `_is_unit`) →
> `_cos_render.lua`. The `create_equipment`, `_spawn_item*` and
> `LootItemUnitPreviewer.spawn_units` rows keep their hooks in the entry; the
> "offhand mesh override + scale + LA paint + glow" work those rows describe now
> reaches the scale/grip step via `mod._cos.{scale_units,offset_units,apply_unit_path_scale_hand}`.

> **v0.9.79-dev Phase 3 OOP split.** Two hook SITES moved from the entry to
> `_cos_glow.lua` (those rows now name that file, not an entry line — match by
> method name): the `apply_material_settings` x3 template-mutation hook and the
> `GearUtils.spawn_inventory_unit` glow-template-injection hook. The
> `create_equipment` / `_spawn_item*` / `LootItemUnitPreviewer.spawn_units` render
> hooks STAY in the entry; their glow apply step now calls
> `mod._cos.apply_glow_override` / `mod._cos.glow_owner_peer_for_unit` (the glow
> read/paint pipeline moved to `_cos_glow.lua`). The per-peer `cos_glow_apply`
> broadcast RPC layer and the `/glow_status` + `/glow_trace` commands stay in the entry.

### Items / gear / inventory spawn - owner path (owner doc: `docs/engine/06`)

Seams shared with `cwv`; vanilla behavior cited there. cosmetics uses them for
shield-mesh override, LA paint and glow, never for a cloned template.

| Class.method (kind) | Vanilla behavior at the seam | Why cosmetics hooks it | Trap / invariant |
|---|---|---|---|
| `GearUtils.create_equipment` [hook] `:5212` | Builds the equipment record and spawns 1p/3p units for a slot [src: `gear_utils.lua:7`] | In-game render path for offhand mesh override + LA texture paint + glow re-key (`:5212`); reads `result.skin` to gate has_skin (DEVELOPMENT "Render paths") | Multi-return collapse (`docs/VMF_RECIPES.md` §2); hot-reload unsafe (CLAUDE.md); single registration shared with the folded MH work (`_material_hijack_embedded.lua:405`) |
| `GearUtils.spawn_inventory_unit` [hook] `_cos_glow.lua` | Spawns one hand's inventory unit from `item_template`+`item_units` [src: `gear_utils.lua:155`] | Inject the `_cosmetics_tweaker_glow` template for non-templated `_runed_01`/`_magic_01` meshes when global glow override is on (`_cos_glow.lua`; inert today — the global toggle was removed) | Read career from `inventory_system._career_name`, not `player:owner()`, at mission-spawn timing (CLAUDE.md in-mission caveat) |
| `BackendUtils.get_item_units` [hook,tbl] `:4081` | Resolves per-hand unit paths: skin entry first, else `item_data.right_hand_unit`; `backend_id = item_data.backend_id or backend_id` [src: `backend_utils.lua:144`,`:156`] | Force the picked offhand/illusion mesh when a skin is equipped and the package is resident (`:4081`); the one mesh seam all four render paths ride. Husk branch swaps the REMOTE wearer's offhand mesh from the synced stores: LA armoury via `_la_equips_by_peer` (kind="unit"), and #416 VANILLA meshes via the parallel `mod._offhand_mesh_by_peer` (offhand_unit sync) | Fires for EVERY caller incl. all 4 previewers - cannot see its context (LA_SYNC §6.4, DEVELOPMENT "has_skin gate"); `_override_package_ready` must confirm both `<unit>`+`<unit>_3p` loaded first (LA_SYNC §6.5, #416 husk vanilla swap); VMF can't string-resolve the plain `BackendUtils` table, hook post-LA ref (`:4058` memo) |

### Owner + husk inventory extension - wield + husk identity (owner docs: `docs/engine/02`, `docs/engine/06`)

| Class.method (kind) | Vanilla behavior | Why cosmetics hooks it | Trap / invariant |
|---|---|---|---|
| `UIUtils.get_ui_information_from_item` [hook,tbl] | Receives the exact backend item and returns inventory icon, display name, description, and store icon; weapon icons resolve from `item.skin` [src: `scripts/helpers/ui_utils.lua:219-260`] | Replace only the inventory-icon return when that backend id has a persisted LA illusion/offhand, using LA's authored `SKIN_LIST[armoury_key].icons[vanilla_skin]` mapping (#376) | Preserve all four returns; missing item/metadata fails closed. Never mutate `WeaponSkins.skins[*].inventory_icon` or `ItemMasterList[*].inventory_icon` globally (v0.9.9.0 rollback) |
| `SimpleInventoryExtension._wield_slot` [safe] `:9875` | Shows/hides 1p/3p units for the wielded slot [src: `simple_inventory_extension.lua:1926`] | Re-apply per-item glow at the moment a unit becomes visible (never touch sheathed units) (`:9875`, GLOW_SYSTEM §3) | Self-owned class only; husk is a separate root (below) |
| `SimpleHuskInventoryExtension._wield_slot` [hook] `:8121` | Husk-side wield: attaches 1p/3p units for a REMOTE player's view [src: `simple_husk_inventory_extension.lua:641`] | Re-key husk offhand mesh + re-paint LA texture on the freshly spawned remote units (`:8121`) | Chosen over `SimpleHuskInventoryExtension.wield` because `_tpe.lua:511` already reserves `wield` and VMF drops the second `hook_safe` (LA_SYNC §6.8); husk resolves the BASE `item_data` (memory `reference_vt2_husk_resolves_base_item_data`); guard `Unit.has_node` for hot-join skeleton readiness (memory `reference_vt2_husk_attachment_skeleton_readiness`) |
| `SimpleHuskInventoryExtension.init` [safe] `:6874` | Constructs the remote-view inventory extension [src: `simple_husk_inventory_extension.lua:314`] | Seed per-husk state (wearer peer, cosmetic cache) before the first husk wield (`:6874`) | Husk class is a separate root from the owner - hooking one never covers the other (CLAUDE.md "Self-owned vs husk") |

### Cross-peer wire safety - LA backend_ids + `ct_*` custom skins (owner: `docs/engine/03`, §31)

Cosmetics registers LA clones into `NetworkLookup.item_names` and `ct_*` skins into
`NetworkLookup.weapon_skins` as local index-appends, so their ids are peer-local. A
non-mod (or differently-loaded) peer cold-decodes an id it lacks and fatals in the
strict `__index` [src: `network_lookup.lua:2521`]. Every SENDER substitutes the
vanilla equivalent (or nulls to `"n/a"`) UNCONDITIONALLY, never behind a toggle
(memory `reference_vt2_wire_safety_never_toggle_gated`; project
`project_vt2_cross_peer_wire_safety`).

The mod's OWN cross-peer cosmetic state travels a separate, crash-immune path: the
VMF mod RPC channel (`cos_la_apply` / `cos_la_apply_req` / `cos_la_state_req`,
`COS_RPC_SCHEMA`-versioned). VMF delivers a mod's RPCs ONLY to peers running that mod,
so a non-mod peer never decodes them - they cannot touch the #421 floor above. This is
why per-hand cosmetic picks that vanilla can't encode (independent left/right illusions,
#416 vanilla offhand meshes and #483 individualized CWV dual-weapon mounts) ride the mod channel and carry plain STRINGS (unit paths),
never `NetworkLookup` indices. #416 added the additive `offhand_unit` field (a unit path,
or `""` = clear) + the parallel `mod._offhand_mesh_by_peer` store; a non-mod peer simply
sees the base offhand (acceptable degrade, never a crash). See LA_SYNC §6.9.

| Class.method (kind) | Vanilla behavior | Why cosmetics hooks it | Trap / invariant |
|---|---|---|---|
| `CosmeticUtils.update_cosmetic_slot` [hook,tbl] `:5862` | Encodes cosmetic + skin ids and writes them into the player's `player_sync_data` GameSession object (`set_data`) for hat/skin/pose slots [src: `cosmetic_utils.lua:230-251`] | Substitute LA item/skin backend_ids to vanilla, null `ct_*` skins to `"n/a"`, before the sync write (`:5862`, #421, crash fa479a72) | Third wire axis, a GameSession channel not an RPC; a peer decodes on the inspect/playerlist read path [src: `cosmetic_utils.lua:168-178`]; `CosmeticUtils` is a plain table (`= CosmeticUtils or {}` [src: `cosmetic_utils.lua:3`]) - must use table-form (`:5855` memo) |
| `LoadoutUtils.sync_loadout_slot` [hook,tbl] `:6095` | Encodes an item as `rpc_sync_loadout_slot`, `item_id = NetworkLookup.item_names[item.key]` [src: `loadout_utils.lua:13`,`:25`] | Send a `backend_to_vanilla` shadow item for LA clones so the peer decodes a known id (`:6095`) | Plain table (`= LoadoutUtils or {}`); table-form + nil guard; also re-invoked by `LoadoutUtils.hot_join_sync` per new peer |
| `SimpleInventoryExtension.game_object_initialized` [hook] `:6172` | First loadout broadcast once the GO id is ready; encodes `weapon_skin_id = NetworkLookup.weapon_skins[slot.skin or "n/a"]`, broadcasts `rpc_add_equipment` [src: `simple_inventory_extension.lua:249`,`:258-264`] | Null every `_custom_skin_keys` skin on the wire, then restore the slot's real skin after the send so the local owner still spawns the custom illusion (`:6172`, #421) | Null-and-restore is the shared pure helper `mod._cos_wire_null_custom_skins` (`:6146`); regression check `wire_skin_null_all_senders` asserts all three skin senders are hooked (§31) |
| `SimpleInventoryExtension._spawn_resynced_loadout` [hook] `:6207` | Re-encodes + rebroadcasts on every mid-session (re)equip [src: `simple_inventory_extension.lua:1443`] | Same null-and-restore on the "on equip" leak; local re-derives the skin in `create_equipment` via backend, not the nulled field (`:6207`, #421) | One of the three `_custom_skin_keys` senders; distinct from the LA-name path which hooks the attachment extension |
| `GearUtils.hot_join_sync` [hook] `:6220` | Host replays every worn slot to a joining peer, encoding `weapon_skin_id` [src: `gear_utils.lua:462`] | Null `ct_*` skins on the join replay so a non-mod joiner does not fatal before finishing load (`:6220`, #421) | Distinct table from `AttachmentUtils.hot_join_sync` below - both must be covered |
| `PlayerUnitAttachmentExtension.game_object_initialized` [hook] `:8554` | First attachment broadcast, encodes `attachment_id = NetworkLookup.item_names[slot.name]` [src: `player_unit_attachment_extension.lua:55`] | Substitute LA hat/armor clone item names to vanilla before the encode (`:8554`) | The LA-NAME axis; the skin axis rides `SimpleInventoryExtension` (a different class) |
| `PlayerUnitAttachmentExtension.spawn_resynced_loadout` [hook] `:8591` | Re-encodes an attachment on resync [src: `player_unit_attachment_extension.lua:295`] | Same LA-name substitution on the attachment resync path (`:8591`) | - |
| `AttachmentUtils.hot_join_sync` [hook,tbl] `cosmetics_tweaker.lua` | Replays attachments to a joiner via `rpc_create_attachment`, `attachment_id = NetworkLookup.item_names[slot_data.name]` [src: `attachment_utils.lua:81`,`:99-102`] | Substitute LA clone names and attempt targeted cosmetic/glow replay | Plain-table dispatcher; table-form hook. This callback can precede joiner ingame membership, so glow correctness comes from the joiner's acknowledged `cos_la_state_req` pull-on-ready; the host reuses existing `cos_glow_apply` replies, then the receiver performs bounded local material rehydrate (40 attempts/10s, no network retry) |

### Attachment / hat unit spawning + link guards (owner: `docs/engine/06`, §22)

| Class.method (kind) | Vanilla behavior | Why cosmetics hooks it | Trap / invariant |
|---|---|---|---|
| `AttachmentUtils.create_attachment` [hook,tbl] `:9427` | Spawns `item_units.unit` for a hat/attachment slot via `UnitSpawner.spawn_local_unit` -> `World.spawn_unit`, then links it [src: `attachment_utils.lua:5`,`:16`] | Skip cleanly when the swapped headpiece package is not resident on a viewer, returning vanilla's empty `{unit=nil,...}` slot_data shape [src: `attachment_utils.lua:38-44`] (`:9427`, #270) | `item_units.unit` == `item_data.unit` (skin block only overrides hand/ammo units, [src: `backend_utils.lua:153`]) - gate on `item_data.unit`; non-resident spawn is a `World.spawn_unit` C-assert that bypasses `pcall` (`c_api_world.cpp:67`) |
| `AttachmentUtils.link` [hook,tbl] `:9450` | Links source->target by `node_linking` via `Unit.node` per link [src: `attachment_utils.lua:66-73`] | Pre-validate every source/target node with `Unit.has_node`, abort the link if any is missing (`:9450`, #270 crash B); post-step queues the unit for LA re-paint | `Unit.node` on an absent node is an engine C-assert (`c_api_unit.cpp:74`) that bypasses `pcall` (CLAUDE.md Lua quirks); a nil target from a skipped spawn also faults here |
| `PlayerHuskAttachmentExtension.create_attachment` [hook] `:8346` | Husk-side hat spawn; `remove_attachment` first if the slot has old data [src: `player_husk_attachment_extension.lua:45`,`:94`] | Pre-patch `item_data.unit = la_unit_path` from `_la_equips_by_peer` BEFORE delegating, then paint, so the late vanilla `rpc_create_attachment` is idempotent with cosmetics' earlier `cos_la_apply` (`:8346`, LA_SYNC §6.7, v0.9.0.9) | `slot_hat`-only today; `_la_equips_by_peer` must be populated on CLIENTS, not just host (v0.9.0.7 mirror write) |
| `World.link_unit` [safe,tbl] `:9490` | Engine C-API: links child unit/node to parent unit/node | Cover hats linked via the low-level `World` API (bypassing `AttachmentUtils`) - queue them for LA re-paint (`:9490`) | Fires for EVERY link in the world; gate on `Unit.has_data(child,"unit_name")` + `LA_BRIDGE.registered` before acting |
| `UnitSpawner.spawn_local_unit` [hook] `_material_hijack_embedded.lua:418` | Vanilla spawns `World.spawn_unit(self.world, unit_name, ...)` UNCONDITIONALLY [src: `unit_spawner.lua:294`] | Refuse the spawn (return nil, do not delegate) when the unit is non-resident, else the C-assert CTDs the viewer (`:418`, #270 crash A); on success run MH `replace_textures`/`add_particles` | Returning `func(...)` still crashes - vanilla calls native regardless; every mod caller tolerates a nil unit (the two `AttachmentUtils` guards above) |

### Material / glow overrides (owner: `GLOW_SYSTEM.md`; `docs/engine/06`)

| Class.method (kind) | Vanilla behavior | Why cosmetics hooks it | Trap / invariant |
|---|---|---|---|
| `apply_material_settings` [hook] x3: `GearUtils.` / `_G.` / `CosmeticUtils.` `_cos_glow.lua` | Reads `MaterialSettingsTemplates[name]` and pushes each var into `Unit.set_*_for_materials` [src: `gear_utils.lua:107`; `flow_callbacks_foundation.lua:896`; `cosmetic_utils.lua:29`] | TEMPLATE MUTATION: save the template's `x/y/z`, overwrite with the per-item/preset glow RGB, call vanilla (it is the only writer that paints 1p), restore (`_cos_glow.lua`, GLOW_SYSTEM §12) | Three independent copies exist - hook all three (`_cos_glow.lua` loop over class ids); post-call overlay never paints 1p (GLOW_SYSTEM §12); `Vector3` is frame-allocated, never cache (GLOW_SYSTEM §Stingray gotcha); never call `Material.num_parameters/parameter_name` - pcall-bypassing fault (`:435-438` memo) |
| `Unit.set_unit_visibility` / `set_visibility` / `set_mesh_visibility` [hook,tbl] `_material_hijack_embedded.lua:366`/`:379`/`:392` | Engine C-API: toggles unit / group / mesh visibility | MH particle lifecycle: spawn linked particles when a `mat_to_use` unit becomes visible, destroy them when hidden (`:366`+) | Hot path on every visibility flip; guarded by `Unit.has_data` markers set at spawn |

### Backend / unlock / MoreItemsLibrary / loadouts (owner: `docs/engine/11`)

| Class.method (kind) | Vanilla behavior | Why cosmetics hooks it | Trap / invariant |
|---|---|---|---|
| `BackendInterfaceCraftingPlayfab.get_unlocked_weapon_skins` [safe] `_cos_illusions.lua` | Returns the unlocked-skin set the forge treats as available [src: `backend_interface_crafting_playfab.lua:138`] | Mark cosmetics' custom illusions unlocked so they appear in the picker (`_cos_illusions.lua`) | Backing store is `PlayFabMirrorBase.get_unlocked_weapon_skins`; never commit to PlayFab (`docs/engine/11`); DLC gate before write (CLAUDE.md "DLC Ownership Gate") |
| `PlayFabMirrorAdventure._create_fake_inventory_items` [hook] `_cos_unlocks.lua` / `get_unlocked_cosmetics` [safe] `_cos_unlocks.lua` | Builds the local fake-inventory + unlocked-cosmetics tables the menus read [src: `playfab_mirror_adventure.lua`] | Inject cosmetics' hat/skin unlocks into the mirror so vanilla browsers render them (`_cos_unlocks.lua`) | Filter unowned-DLC entries before the `_unlocked_*` write (CLAUDE.md three-places checklist) |
| `BackendInterfaceItemPlayfab.get_weapon_skin_from_skin_key` [hook] `:1743` | Maps a skin key to its backend id [src: `backend_interface_item_playfab.lua`] | Resolve cosmetics' custom `ct_*` skin keys (`:1743`) | - |
| `BackendInterfaceCraftingPlayfab.craft` [hook] `:1895` / `update` [safe] `:1952` | Runs a craft recipe / polls craft completion [src: `backend_interface_crafting_playfab.lua`] | Intercept the apply-illusion "craft" so custom illusions equip without a real backend commit (`:1895`) | Modded-realm isolation - never write to PlayFab (`docs/engine/11`, issue #402) |
| `BackendInterfaceItemPlayfab.set_loadout_item` [safe] `:5682` + `BackendUtils.set_loadout_item` [hook,tbl] `:5719` | Persists an equipped item to a career loadout [src: `backend_interface_item_playfab.lua`] | Capture equip events to drive LA persistence + cache (`:5682`); table-form for the LA-clone dispatch path | Hook the post-LA `BackendUtils` ref, not cold `_G` (memory `reference_cim_equip_capture_la_dispatch`) |
| `items_iface.get_loadout` / `get_loadout_item_id` / `get_item_rarity` [hook,tbl] `:5744`/`:5774`/`:5802` | Backend item-interface reads the menus/husk use [src: `backend_interface_item_playfab.lua`] | Surface LA-clone + custom items with correct rarity/loadout membership (`:5744`+) | `items_iface` is the resolved interface instance, hooked table-form; LA reassigns these at runtime (CLAUDE.md "LA bridge") |
| `backend_mirror.get_all_inventory_items` [hook,tbl] `_moreitemslibrary_embedded.lua:234` + `BackendInterfaceItemPlayfab.init` [hook,tbl] `:378` | MIL captures the backend_mirror instance at interface init and merges mod items into the inventory result [src: `backend_interface_item_playfab.lua` init] | Register LA-clone cosmetics as first-class inventory items via the embedded MoreItemsLibrary (`:234`,`:378`) | Cosmetic item_types must also be written into `backend_mirror._unlocked_cosmetics` or browsers hide them (`:247-248`) |
| `SimpleInventoryExtension.extensions_ready` [safe] `_la_persistence.lua:256` | Fires once the owner inventory extension is committed [src: `simple_inventory_extension.lua`, extensions_ready] | Re-apply the player's saved LA illusion/hat choices once the loadout exists (`:256`) | Backend nil at mod init; this is the ready point |
| `_G.Localize` [hook] `_cos_illusions.lua` | Global loc-key -> string lookup | Supply display names for LA-clone + `ct_*` keys (`_cos_illusions.lua`) | VMF `_localization.lua` is NOT auto-registered into global `Localize` (`docs/VMF_RECIPES.md`) |

### UI - previewers + illusion customization window (owner docs: `docs/engine/09`, `docs/engine/06`)

Four preview surfaces resolve items differently; see the previewers subsystem note.
The customization-window suite drives the two-row offhand picker and the glow popup.

| Class.method (kind) | Vanilla behavior | Why cosmetics hooks it | Trap / invariant |
|---|---|---|---|
| `MenuWorldPreviewer.equip_item` [hook] `:5327` + `HeroPreviewer.equip_item` [hook] `:5363` | Equips an item into a preview slot; `item_name` is the WEAPON master key, `skin` is a separate arg [src: `world_hero_previewer.lua:649`] | Capture the `skin` arg into `_equip_skin_by_item` (weak-keyed) + `_cos_current_equip_backend_id` so `_spawn_item*` can gate has_skin and thread glow (`:5327`, DEVELOPMENT "Render paths"); the base hook also swaps/paints the score-lineup LA hat after TeamPreviewer stamps a verified wearer (#513) | Hook DERIVED and base independently - `class()` copies methods at load [src: `class.lua:51-57`]; the keep previewer is `MenuWorldPreviewer` (CLAUDE.md) |
| `TeamPreviewer._spawn_hero` [hook] + `cb_hero_unit_spawned_skin_preview` [safe] `:4083`/`:4130` | Requests each end-lineup hero from `hero_data`, then equips its preview items after spawn [src: `team_previewer.lua:99-126`]; `LevelEndView._get_hero_from_score` preserves profile/career but drops peer/local identity [src: `level_end_view_v2.lua:259-288`] | Resolve a human score row to the synced per-peer LA store before the preview spawns, then paint its hat/outfit (#513) | `ScoreboardHelper` assigns bots their owner's `peer_id` and separately records `is_player_controlled` [src: `scoreboard_helper.lua:352,360,393-398`]. Require exact profile+career + player-controlled + complete peer/local tuple; bot/untrusted rows fail closed in `_cos_score_identity.lua` |
| `HeroPreviewer._spawn_item` + `MenuWorldPreviewer._spawn_item` [hook] `:5472`/`:5473` | Spawns a single preview unit for an item [src: `world_hero_previewer.lua:895` / `menu_world_previewer.lua:635`] | Force offhand mesh + LA paint on the inventory mannequin via the captured skin (`:5472`) | String-keyed `_item_info_by_slot` vs numeric `_equipment_units` - bridge on `spawn_data[1].slot_index` (CLAUDE.md) |
| `HeroPreviewer._spawn_item_unit` + `MenuWorldPreviewer._spawn_item_unit` [hook] `:9543`/`:9544` | Spawns one unit, no hand indicator | MH `replace_textures`/`add_particles` + glow re-key + LA re-paint queue on preview units (`:9543`) | No per-hand context - never use for per-hand ops (CLAUDE.md); folds the removed MH `_spawn_item_unit` hook (`_material_hijack_embedded.lua:459`) |
| `LootItemUnitPreviewer.spawn_units` [hook] `:5602` + `load_package` [hook] `:5516` + `destroy` [safe] `:5577` + `update` [hook] `:5657` | Illusion browser spawns display units, writing `self._spawned_units` in the CALLER after return [src: `loot_item_unit_previewer.lua:538`,`:504`] | Read the returned `units` to apply offhand mesh + LA paint in the cosmetic picker; force-load parent packages (`:5602`, LA_SYNC §6.4) | MUST be `[hook]` not `[safe]` - `_spawned_units` is nil at safe time (CLAUDE.md); kind="unit" needs per-context `Unit.set_all_materials` or AV 0x8 (LA_SYNC §6.4) |
| `HeroWindowItemCustomization._setup_illusions` [hook] `:3354` | Builds the illusion grid for the selected item [src: `hero_window_item_customization.lua:1518`] | Inject the offhand (shield) picker row-2 + auto-select the equipped illusion (`:3354`, DEVELOPMENT "Auto-select") | Console variant is a separate class; skin lookup chain is `item.skin` -> `get_skin(backend_id)` -> `default_skins` -> template default (DEVELOPMENT) |
| `HeroWindowItemCustomization` picker/craft/draw suite [hook]/[safe] `:1769`,`:1793`,`:1881`,`:1978`,`:2009`,`:2660`,`:2768`,`:2802`,`:3611`,`:3629`,`:9748`,`:9754` + `HeroWindowCosmeticsLoadout.on_exit`/`update`/`draw` [safe] `:9728`/`:9733`/`:9739` | The customization window's craft-button, illusion-index, preview-widget, environment, input and draw callbacks | Wire the offhand picker interaction + glow popup lifecycle + apply-illusion into the modded flow (each cited line) | One consolidated hook per `(Class, method)` - grep before adding (CLAUDE.md NON-NEGOTIABLE 8); menu strings carry raw loc keys (NON-NEGOTIABLE 11) |

### LA prefix / okri UI bridge + player lifecycle (owner: `LA_SYNC_MODEL.md`, `docs/CROSS_MOD_ARCHITECTURE.md`)

| Class.method (kind) | Vanilla behavior | Why cosmetics hooks it | Trap / invariant |
|---|---|---|---|
| `NewsFeedUI.init` [hook] `_la_prefix_embedded.lua:191` | Builds the keep news-feed UI + its template condition funcs [src: `news_feed_ui.lua`] | Suppress LA's `LA_unread_letter` quest-letter banner behind a default-off toggle (`:191`) | ONE hook on this method - LA registers a duplicate that VMF would drop; the embedded prefix-patch de-dupes LA's known double registrations (module header) |
| `AchievementManager.outline` [hook] `_la_okri.lua:133` | Returns the Book-of-Grudges outline (categories) the achievement menu renders [src: `achievement_manager.lua`] | Return a shallow-cloned outline omitting LA's quest category, behind `la_disable_okri_challenges` (default on) (`:133`, #186) | Act at the vanilla READ point, never intercept LA's version-varying direct table writes; keep templates inert-in-place (callable `completed`), never nil the global key (module header) |
| `PlayerManager.remove_player` [safe,tbl] `:7692` / `add_remote_player` [safe,tbl] `:7706` | Adds/removes a remote player record | Maintain `_la_equips_by_peer` / peer caches as players join and leave (`:7692`) | Table-form against the manager instance |
| `rawset(NetworkLookup.item_names, idx/key)` [tbl] `_la_bridge.lua:644-645` | - | Register LA-clone item keys into the network lookup, forward + reverse, as index-appends | Registration is UNCONDITIONAL at boot, never per-user-toggle gated, or peers diverge (LA_SYNC §5 gated-registration row); strict `__index` on reads means every consumer uses `rawget` |

### Third-person equipment (experimental; `_tpe.lua`)

Off by default; reuses the spawn/link/visibility machinery to show sheathed weapons
on the 3P body. All `[safe]`, all lifecycle taps, no override.

| Class.method (kind) | Vanilla behavior | Why cosmetics hooks it | Trap / invariant |
|---|---|---|---|
| `PlayerUnitFirstPerson.set_first_person_mode` [safe] `_tpe.lua:501` | Flips 1P/3P camera mode | Show/hide the TPE back-attachments with camera mode (`:501`) | - |
| `SimpleInventoryExtension.wield` / `destroy_slot` / `destroy` [safe] `_tpe.lua:507`/`:516`/`:520` and `SimpleHuskInventoryExtension.wield` / `destroy_slot` / `destroy` [safe] `_tpe.lua:511`/`:524`/`:528` | Wield/teardown of an equipment slot (owner + husk) [src: `simple_inventory_extension.lua`] | Respawn/refresh the sheathed-weapon attachments on wield and tear them down on slot destroy (`:507`+) | `_tpe.lua:511` RESERVES `SimpleHuskInventoryExtension.wield` for the whole mod - any later `hook_safe` on it is silently dropped (LA_SYNC §6.8); the husk mesh re-key uses `_wield_slot` for exactly this reason |
| `PlayerUnitHealthExtension.die` [safe] `_tpe.lua:533` | Player death | Clear TPE attachments on death (`:533`) | - |

### Cosmetic projectile FX

| Class.method (kind) | Vanilla behavior | Why cosmetics hooks it | Trap / invariant |
|---|---|---|---|
| `PlayerProjectileUnitExtension` / `PlayerProjectileHuskExtension` `.hit_enemy` / `.hit_level_unit` / `.hit_non_level_unit` [safe] `:10767` | Resolves a fired projectile's impact [src: `player_projectile_unit_extension.lua`] | Spawn a decorative Moonfire-arrow impact puff for `we_deus_01*` arrows behind `cos_moonfire_cosmetic_puff` (`:10767`) | Defers to `wt`'s AOE revert if that already puffs (no double-up); FX package rides the equipped Moonfire Bow, so `create_particles` is safe on hit (`:10740` memo) |

## Subsystem notes (how the vanilla flow runs, for cosmetics' cases)

Each note is the minimum needed to read the hooks above; the owning doc carries the
full architecture. Shared-with-`cwv` seams (item->mesh resolution, owner vs husk,
the four previewers, network id-append) are documented in
`character_weapon_variants/ENGINE_SURFACE.md` and `docs/engine/03`,`/06`,`/09` - not
repeated here. The five notes below are the surfaces `cwv` does not cover.

### LA-bridge dispatch model (owner: `LA_SYNC_MODEL.md`)

`BackendUtils`, `CosmeticUtils`, `LoadoutUtils` and `AttachmentUtils` are **plain
tables** (`X = X or {}`), not classes [src: `attachment_utils.lua:3`,
`cosmetic_utils.lua:3`]. Their functions are frequently reassigned at runtime by
Loremaster's Armoury's clone-backend pattern, so VMF's string-form
`mod:hook("BackendUtils", ...)` silently misses the LA-routed calls. cosmetics hooks
the TABLE form against the post-LA reference with a nil guard (`:4058`,`:5855` memos;
CLAUDE.md "LA bridge"). The bridge in `_la_bridge.lua` clones each LA `SKIN_LIST`
hat/armor variant into its own `ItemMasterList` entry
(`build_clone_entry`, `_la_bridge.lua:100`), registers it via the embedded
MoreItemsLibrary (`add_mod_items_to_local_backend`, `:637`), and appends the key to
`NetworkLookup.item_names` (`:644`). LA itself does **no** peer sync of visuals
(LA_SYNC §1) - cosmetics owns all cross-peer cosmetic state, which is why the wire
axes above exist. Load order: LA must be enabled AFTER cosmetics in the F4 launcher
so the embedded prefix-patch installs its VMFMod de-dupe first
(`_la_prefix_embedded.lua` header).

LA shield availability is data-driven by `_la_shield_parity.lua`. Its single Kruber
catalogue fans every armoury key out to the four native and three current CWV shield
item types; `_la_bridge.lua` still resolves and carries the variant-authored
`new_units[1]` mesh. This adds no engine hook or per-weapon apply branch.

### MaterialSettingsTemplates / glow (owner: `GLOW_SYSTEM.md`)

Weapon glow is applied at spawn: `GearUtils.spawn_inventory_unit` calls
`apply_material_settings`, which reads `MaterialSettingsTemplates[name]` (populated by
four `require`d files) and pushes each shader var into `Unit.set_*_for_materials`
(GLOW_SYSTEM §12; [src: `gear_utils.lua:107`]). Two glow families: RUNE (one var,
`rune_emissive_color`) and MAGIC (`versus` template, five vars). The override works by
**mutating the template** before vanilla reads it and restoring after - a post-call
overlay reliably fails to paint 1p even though every write returns ok (GLOW_SYSTEM
§12). Three copies of `apply_material_settings` exist (`GearUtils.`, `_G.`,
`CosmeticUtils.`); all three are hooked (`:4857`). `Vector3` is frame-allocated - never
cache one across frames (GLOW_SYSTEM §Stingray gotcha); `Material.num_parameters` /
`parameter_name` trigger a pcall-bypassing `resource_manager.cpp` fault and must never
be called (`:435-438` memo).

### Offhand package residency + issue-565 async startup queue (owner: `docs/engine/05`)

The offhand/illusion catalog can touch dozens of unit packages. A synchronous
`PackageManager.load` calls `ResourcePackage.load` and immediately
`ResourcePackage.flush` [src: `package_manager.lua:69-76`]; the July 13 four-log audit
found 74 Cosmetics-owned sync loads per launch and a repeatable ~1.58 s
`Application::update` stall. The bulk preload now passes `asynchronous=true`, which
uses PackageManager's serialized async queue [src: `package_manager.lua:47-66`,
`:274-292`]. Safety comes from `_override_package_ready`: both `<unit>` and
`<unit>_3p` must pass `Application.can_get` before `BackendUtils.get_item_units`
exposes the override, otherwise vanilla's base mesh remains in use. Each queued path
takes one `cosmetics_tweaker` reference; `_release_offhand_packages` balances those
references from `mod.on_unload` (#565).

### Material-Hijack embedded package loading + issue-282 refcount lifecycle (owner: `docs/engine/05`)

`_material_hijack_embedded.lua` recolours units carrying a `mat_to_use` data block by
loading the referenced material package and painting slots. `PackageManager.load`
INCREMENTS a per-(package, reference-name) refcount on every call
[src: `package_manager.lua:26-27`] and `unload` decrements by one
[src: `package_manager.lua:196-238`]. The old per-call `load(path, "global")` -
invoked from `replace_textures`/`add_particles` on EVERY hijacked wield/spawn -
accumulated 90+ references per session with no unload, so shutdown walked the count
down one-by-one ("Package still referenced, NOT unloaded" cascades) and ended in the
deadlock-warning block on both peers (#282/#477). The fix (`_safe_load_package`,
`:191`): load exactly once per path under a mod-owned reference name
(`"cosmetics_tweaker_mh"`), tracked in `_mh_loaded_packages`; `release_packages`
(`:215`) drops the single reference on the `("exit","StateIngame")` game-state
notification (which fires BEFORE `StateIngame.on_exit` destroys units and the level
world, [src: `state_ingame.lua:1924-1929`,`:1939`]) and on `mod.on_unload`. Releasing
while units may still use the material is engine-safe: `unload` frees the resource only
once NO reference under ANY name remains, and even then routes a still-in-use package
through the delayed-unload queue instead of freeing it live
[src: `package_manager.lua:213-224`, the `can_unload` gate]. The release wiring lives in
`cosmetics_tweaker.lua` (not this module) because the module is `dofile`'d before
`mod.on_game_state_changed`/`mod.on_unload` are defined (`:158-186` memo).

### CosmeticUtils.update_cosmetic_slot GameSession sync channel (owner: `docs/engine/03`, `/11`)

`update_cosmetic_slot` is a distinct wire axis from the `rpc_add_equipment` /
`rpc_create_attachment` RPCs: it encodes cosmetic + weapon-skin ids and writes them
directly into the player's `player_sync_data` GameSession object via `set_data` for
hat/skin/pose slots [src: `cosmetic_utils.lua:230-251`]. Every peer that opens the
inspect/playerlist read path decodes those ids back through the strict lookup
(`get_cosmetic_slot` -> `get_weapon_skin_name`, [src: `cosmetic_utils.lua:168-178`]),
so a locally-appended LA backend_id or `ct_*` skin id fatals a non-mod peer there
(#421, the same crash class as the `rpc_add_equipment` axis on a different channel,
crash fa479a72). cosmetics substitutes LA ids to their vanilla equivalent and nulls
`ct_*` skins to `"n/a"` before the write (`:5862`). The hook also carries the LA
persistence injection: on the first `update_cosmetic_slot` of a session it swaps the
saved LA choice in (PlayFab can only store the vanilla substitute) so the local visual
paints LA while the wire stays vanilla-safe (`:5863-5900`).

### Attachment / hat unit spawning: kind=texture vs kind=unit (owner: `docs/engine/06`, `LA_SYNC_MODEL.md` §6.2)

Hats/attachments spawn through `AttachmentUtils.create_attachment` ->
`UnitSpawner.spawn_local_unit` -> `World.spawn_unit` [src: `attachment_utils.lua:16`],
which C-asserts on a non-resident unit (`c_api_world.cpp:67`) - the reason the mod
gates on residency at both `AttachmentUtils.create_attachment` (`:9427`) and
`UnitSpawner.spawn_local_unit` (`_material_hijack_embedded.lua:418`), and guards every
node with `Unit.has_node` at `AttachmentUtils.link` (`:9450`, #270). LA hats come in
two flavours (LA_SYNC §6.2): `kind="unit"` ships a fully custom mesh (visually correct
after `create_attachment` alone), while `kind="texture"` reuses a vanilla mesh and
needs an explicit `apply_new_skin_from_texture` on the receiver AFTER the spawn or the
hat appears in vanilla colours on peers. The husk hat path additionally races the
vanilla `rpc_create_attachment`, fixed by pre-patching `item_data.unit` in the
`PlayerHuskAttachmentExtension.create_attachment` hook (`:8346`, LA_SYNC §6.7).

## What the engine will NOT let us do (dead ends, already paid for)

Distilled from `DEVELOPMENT.md`, `LA_SYNC_MODEL.md` §2/§5/§6, and `GLOW_SYSTEM.md` -
do not re-discover these.

- **No per-peer visual choice by piggybacking on LA.** LA writes globally via
  `Material.set_texture` on shared materials and mutates global skin tables; whatever
  the VIEWER picked is what the viewer sees on everyone (LA_SYNC §1, §2). Per-player
  visuals require cosmetics' own VMF shared-state keyed by peer+career - which is what
  the `cos_la_apply` / `cos_glow_apply` broadcasts are.
- **No restore-on-deselect for shared-material paint.** Once `Material.set_texture`
  writes, the original binding is unrecoverable until engine reload -
  `Material.reset_texture`, `Material.get_texture`, `Material.has_variable` do NOT exist
  in this build (LA_SYNC §4, §6.4). Use `Unit.set_texture_for_materials` (per-unit
  instance override, dropped automatically on unit destruction) for anything reversible.
- **kind="unit" LA shields cannot go through LA's helpers.** Calling LA's
  `re_apply_illusion`/`swap_units_new` from outside LA's own update loop races its tick
  and hits a strict `inventory_packages` `__index` that `error()`s on miss (LA_SYNC §6.3,
  crash 60180105). Use cosmetics' own kind="unit" pipeline with `rawget` everywhere and
  a per-context `Unit.set_all_materials` bind (LA_SYNC §6.4).
- **kind="unit" paint AVs in the loot previewer without a real material bind.** The
  previewer's per-world material graph resolves the reference to `#ID[00000000]`, and
  `Unit.set_texture_for_materials` AVs at offset 0x8 dereferencing the null material.
  Loading more packages does not fix it (v0.8.39); bind the vanilla parent material with
  `Unit.set_all_materials` first, and ONLY in the `loot_previewer` context - running the
  swap in-game or in the hero previewer overwrites correct bindings and breaks scale
  (LA_SYNC §6.4, v0.8.47).
- **Glow cannot be added to a weapon whose material lacks the uniform.** `rune_emissive_color`
  / `color_glow_*` only produce output if the `.unit`/`.material` asset exposes them;
  `Unit.set_vector3_for_materials` on a non-glow weapon silently no-ops (GLOW_SYSTEM
  §"Adding glow"). The `_magic_01` rarity-magic animated swirl is baked into its mesh's
  material and no template can recreate it on another mesh (GLOW_SYSTEM §"magic rarity").
- **Glow override only paints on fresh spawns.** Toggling a preset does not live-repaint
  a spawned weapon; live re-paint by walking inventory slots destabilised adjacent unit
  state and was reverted (GLOW_SYSTEM §Activation, v0.8.10). Paint at the wield/visibility
  moment instead (`:9875`).
- **Never call `LA.apply_new_skin_from_texture` for offhand paint.** It mutates
  `WeaponSkins.skins[skin].inventory_icon` / `ItemMasterList[skin].inventory_icon`
  permanently, leaking LA heraldics into vanilla inventory grids globally (LA_SYNC §6.5,
  DEVELOPMENT). Use `_paint_offhand_textures_locally`.
- **Never gate a NetworkLookup append or a wire substitution on a per-user toggle.**
  Registration must be unconditional at boot or peers diverge on ids (LA_SYNC §5); the
  sender-side null/substitution takes no toggle argument by construction (§31 never-crash
  mandate, `:6146`).

## Doc maintenance

Follows `docs/engine/README.md` maintenance rules: if a cosmetics hook moves, a guard is
added, or a cited vanilla line drifts after a game patch, edit the affected row in the
SAME commit. Line numbers are against the 2026-07-11 decompile and mod source - match
crash logs by function name, not line. Structural template is
`character_weapon_variants/ENGINE_SURFACE.md`; keep the section shape (hook table ->
subsystem notes -> dead ends) stable.
