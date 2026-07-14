# character_weapon_variants - engine contact surface

What vanilla VT2/Stingray does at every seam `cwv` touches, and why the mod is
there. This is the per-mod companion to the subsystem set in `docs/engine/`
(read `docs/engine/README.md` for house style). It does **not** re-explain a
subsystem the engine docs own - it names the seam, cites the vanilla behavior,
and links out. Decompile paths are relative to
`C:\Users\danjo\source\repos\Vermintide-2-Source-Code`; `cwv` line numbers are
`character_weapon_variants.lua` unless noted. `§N` = a `docs/BUG_CLASSES.md`
class; `#N` = a GitHub issue. Grep-verified 2026-07-11 against the decompile.

`cwv` is the highest engine-contact mod in the monorepo: it clones cross-character
base templates into brand-new MoreItemsLibrary items, so it has to intercept every
path that resolves an item to a mesh, a template, an animation event, a network id,
or a preview unit - on the owner, on the husk, in four preview surfaces, and across
the wire.

## Hook table

53 registration sites, grouped below into 8 logical rows-of-concern. `[hook]` =
full wrapper (`mod:hook`, can rewrite args/returns); `[safe]` = `mod:hook_safe`
(post-callback, no override); `[tbl]` = table-form hook (plain-table target, nil-guarded).

### Items / gear / inventory spawn - owner path (owner doc: `docs/engine/06`)

| Class.method (kind) | Vanilla behavior at the seam | Why cwv hooks it | Trap / invariant |
|---|---|---|---|
| `GearUtils.create_equipment` [hook] `:10711` | Builds the in-world equipment record and spawns 1p/3p units for a slot [src: `scripts/unit_extensions/default_player_unit/inventory/gear_utils.lua:7`] | Supply cwv variant's `override_item_template` / `override_item_units` at keep+mission spawn (`:10711`) | Multi-return collapse (`docs/VMF_RECIPES.md` §2); career must come from `inventory_system._career_name`, not `player:owner()` (CLAUDE.md in-mission caveat) |
| `GearUtils.spawn_inventory_unit` [hook] `:4741` | Spawns one hand's inventory unit from `item_template`+`item_units`, attaches `ammo_unit` if `ammo_data.ammo_hand` matches [src: `gear_utils.lua:155`] | Force cwv per-hand mesh + grip/scale on the spawned unit (`:4741`) | `ammo_unit` fassert: only mirror held mesh as ammo when `base.ammo_unit` exists (DEVELOPMENT "ammo_unit trap", #`2df233ae`) |
| `GearUtils.destroy_wielded` [hook] `:5152` | Destroys the currently-wielded unit on unwield/swap [src: `gear_utils.lua:332`] | Tear down cwv carrier visuals / linked pickups alongside the weapon (`:5152`) | - |
| `GearUtils.link_units` [hook] `:5543` | Attaches source->target units by `attachment_node_linking`, via `Unit.node` per link [src: `gear_utils.lua:293`] | Guard character-specific unwielded bones inherited from a cross-character clone (`:5543`) | `j_leftweaponattach` / `a_unwielded_brw_mace` class - missing node is an uncatchable fatal (`J_LEFTWEAPONATTACH_INVESTIGATION.md`; DEVELOPMENT "Attachment node linking") |
| `BackendUtils.get_item_units` [hook,tbl] | Resolves per-hand unit paths for an item: skin entry first, else `item_data` fallback; the husk calls it with `backend_id=nil`, wire skin, and career immediately before branching on the returned hand fields [src: `backend_utils.lua:144-208`; `simple_husk_inventory_extension.lua:662-670`] | Force cwv override mesh for backend-identified skinless owner/preview items; for a skinless unambiguous husk `(base,career)`, preselect the variant's authored hands before vanilla chooses which spawn calls exist (#478) | Fires for EVERY caller incl. all 4 previewers. Husk preselection requires no backend id, no skin, and shared resolver reason `base_career`; explicit skin/native/ambiguous pairs pass through. The later per-hand residency suppression remains the crash floor. |
| `BackendUtils.get_item_template` [hook,tbl] `:3938` | Resolves the `weapon_template` for an item id [src: `backend_utils.lua:136`] | Return the cwv clone's template for cwv keys (`:3938`) | Table-form; nil-guard the cold `_G.BackendUtils` vs post-LA ref (CLAUDE.md) |

### Inventory extension - owner + husk (owner docs: `docs/engine/02`, `docs/engine/06`)

| Class.method (kind) | Vanilla behavior | Why cwv hooks it | Trap / invariant |
|---|---|---|---|
| `SimpleInventoryExtension.wield` [safe] `:1519` | Sets the wielded slot, flips 1p/3p unit visibility, updates career/weapon state [src: `simple_inventory_extension.lua:627`] | Track local player's cross-access melee weapon+career, feeding the network-bound `_play_3p_anim` remap; also debug wield dump (`:1506-1551`) | CONSOLIDATED - `hook_safe` does not chain; a v0.1.336 duplicate silently shadowed this and broke 3P remap (`docs/VMF_RECIPES.md` §1; `_cwv_wield_hook_registration_count` guards it) |
| `SimpleInventoryExtension._wield_slot` [hook] `:5035` | Shows/hides the 1p/3p units for the slot being wielded [src: `simple_inventory_extension.lua:1926`] | Per-hand cwv fixups at wield time (`:5035`) | Self-owned class only - husk is a separate root (see husk rows) |
| `SimpleInventoryExtension.show_first_person_inventory` / `show_third_person_inventory` [safe] `:5106`/`:5118` | Toggles visibility of the equipped 1p / 3p units [src: `simple_inventory_extension.lua:917`] | Keep cwv scale/grip applied across 1p<->3p visibility flips (`:5106`) | - |
| `SimpleInventoryExtension.game_object_initialized` [hook] | First network broadcast of the loadout once the unit's GO id is ready, via `rpc_add_equipment` [src: `simple_inventory_extension.lua:249-282`] | Net-safe skin nulling plus same-mod `cwv_item_identity` owner marker; if transition-time parity is transiently unconfirmed, schedule a bounded post-confirmation replay (#396/#416/#483) | Never let a modded skin ride while parity is false. The item marker is absence-safe and validated against the received vanilla base before husk use. |
| `SimpleInventoryExtension._spawn_resynced_loadout` [hook] | Respawns and re-broadcasts one queued equipment slot [src: `simple_inventory_extension.lua:1429-1468`] | Same net-safe skin path plus changed-slot CWV owner marker on live resync (#396) | Marker sends are edge-deduplicated; native items emit an empty marker to clear stale ownership. |
| `SimpleHuskInventoryExtension._wield_slot` [safe] `:4634` | Husk-side wield: gets the unit table, then conditionally calls `spawn_inventory_unit` once per non-nil right/left field [src: `simple_husk_inventory_extension.lua:641,662-670`] | Re-key husk mesh+transform off base+career for cwv items (`:4634`, #392); upstream `get_item_units` preselection handles variants whose authored hand differs from the base (#478) | A correction inside `spawn_inventory_unit` is too late to create a hand call the earlier branch omitted. Husk resolves the BASE `item_data`; guard `Unit.has_node` for hot-join. |
| `SimpleHuskInventoryExtension.start_weapon_fx` [hook] `:4595` | Plays weapon fx on the remote/husk view [src: `simple_husk_inventory_extension.lua:790`] | Suppress/redirect fx that reference a bone the cross-character husk lacks (`:4595`) | Husk class is a separate root from the owner - hooking one does not cover the other (CLAUDE.md "Self-owned vs husk") |

### Weapon animation / spread / ammo (tangent to `docs/engine/10`)

| Class.method (kind) | Vanilla behavior | Why cwv hooks it | Trap / invariant |
|---|---|---|---|
| `WeaponUnitExtension._play_3p_anim` [hook] `:1618` | Resolves `event_3p`, encodes it through `NetworkLookup.anims`, sends the animation RPC, then fires the same event locally [src: `scripts/unit_extensions/weapons/weapon_unit_extension.lua:613`] | Substitute the receiver-career event before vanilla encodes it, keeping owner and husks on one animation/audio timeline (`:1618`, #398) | Never defer this to `Unit.animation_event`: that call is after the RPC and therefore owner-local only. Target must already exist in `NetworkLookup.anims`; decline safely otherwise. |
| `ActionHandgun.client_owner_post_update` [hook] | Simulates the owning peer's handgun shot; only calls `play_hud_sound_event` when the action declares `fire_sound_event` [src: `scripts/unit_extensions/weapons/actions/action_handgun.lua:67,180-184`] | On the exact Old Musket hip/ADS shot edge, send its source-verified vanilla rifle report through the native remote-husk audio RPC (#474) | Do not add `fire_sound_event` to the action: that would duplicate the custom mesh's owner-local compiled sound. Send only `play_remote_hud_sound_event`; event is vanilla `player_combat_weapon_rifle_fire`, never a local append. |
| `WeaponSpreadExtension.init` [safe] `:4240` / `update` [hook] `:4254` | Captures the spread template on spawn; recomputes spread each frame [src: `scripts/unit_extensions/weapons/spread/weapon_spread_extension.lua:7` / `:59`] | Patch spread data BEFORE vanilla's update runs for cwv ranged variants (full wrapper, `:4254`) | `update` must be `[hook]` not `[safe]` to land before vanilla reads it (`:4252` comment) |
| `GenericAmmoUserExtension.update` [hook] `:3903` / `add_ammo` [hook] `:3915` | Per-frame ammo/reload state; clamps added ammo to max [src: `scripts/unit_extensions/generic/generic_ammo_user_extension.lua:145` / `:345`] | Adjust ammo pools for cwv ranged variants cloned from a different base (`:3903`) | Consumption-side only - never mutate `_max_*` fields (memory `feedback_vt2_max_resource_consumption_side`) |

### Thrown-weapon projectiles + carried pickups (javelin / boar spear / throwing axe)

| Class.method (kind) | Vanilla behavior | Why cwv hooks it | Trap / invariant |
|---|---|---|---|
| `PlayerProjectileUnitExtension.init` [safe] `:6016` / `hit_level_unit` [safe] `:6082` / `_handle_linking` [hook] `:6112` / `_spawn_linked_pickup_projectile` [hook] `:6160` / `_spawn_pickup_projectile` [hook] `:6175` | Inits a fired/thrown projectile, resolves level-geometry impact, decides whether it links (sticks), and spawns the pickup it becomes [src: `scripts/unit_extensions/weapons/projectiles/player_projectile_unit_extension.lua:14`/`:948`/`:1161`/`:1327`/`:1362`] | Route cwv thrown-weapon variants through the pickup-projectile path so the thrown item is recoverable (`:6016`+) | Pickup-sampler total must stay `>= 1` (memory `reference_vt2_pickup_sampler_total_crash`); linked-pickup RPC overflow class (memory `reference_vt2_cw_boon_aoe_rpc_overflow_crash`) |
| `ProjectileSystem._get_projectile_units_names` [hook] `:6200` | Resolves the projectile's unit + template names from `projectile_info` [src: `scripts/entity_system/systems/projectile/projectile_system.lua:159`] | Substitute the cwv thrown unit/template names (`:6200`) | Husk has its own `_get_projectile_units_names` [src: `player_projectile_husk_extension.lua:727`] - cover both sides |
| `ProjectileSystem.rpc_spawn_pickup_projectile` [hook] `:6221` / `PickupSystem.rpc_spawn_linked_pickup` [hook] `:6206` | Receiver RPCs: spawn a (linked) pickup projectile from networked name ids [src: `projectile_system.lua:436` / `scripts/entity_system/systems/pickups/pickup_system.lua:1415`] | Decode cwv projectile/pickup ids that only exist as local appends on the sender (`:6221`) | RPC receivers ARE hookable (memory `reference_vt2_rpc_dispatch_dynamic_hookable`); modded `NetworkLookup` key CTDs a non-mod peer (`docs/engine/03`, §31) |
| `ProjectileLinkerSystem.link_pickup` [hook] `:6347` | Links a pickup unit to a hit unit's node [src: `scripts/entity_system/systems/projectile/projectile_linker_system.lua:202`] | Guard bone lookups when the linked cwv pickup targets a foreign rig (`:6347`) | Same `Unit.node` fatal class as `link_units` |
| `OutlineSystem.outline_unit` [hook] `:6331` | Applies/removes the interaction outline on a unit [src: `scripts/entity_system/systems/outlines/outline_system.lua:637`] | Keep the recoverable thrown-weapon pickup outlined like vanilla ammo (`:6331`) | Signature is `(self, unit, flag, color, ...)` in vanilla - match arg names |
| `LimitedOwnedPickupUnitExtension` / `LifeTimePickupUnitExtension` / `PlayerTeleportingPickupExtension` `.extensions_ready` [safe] `:6339-6341` + `.destroy` [safe] `:6342-6344` | The three carrier-pickup extension classes (all `class(X, PickupUnitExtension)` [src: `pickup_system.lua:6-8`]); base `extensions_ready` [src: `scripts/unit_extensions/pickups/pickup_unit_extension.lua:54`], `destroy` [src: `:100`] | Attach/detach the carried thrown-weapon visual on whichever carrier extension the pickup uses (`_attach_carrier_visual`/`_detach_carrier_visual`) | Three separate root classes - must hook all three, exactly the self-owned-vs-husk pattern (CLAUDE.md) |

### UI / previewers (owner docs: `docs/engine/09`, `docs/engine/06`)

| Class.method (kind) | Vanilla behavior | Why cwv hooks it | Trap / invariant |
|---|---|---|---|
| `MenuWorldPreviewer.equip_item` [safe] `:2922` | Keep-inventory previewer equips an item into a preview slot (body copied from `HeroPreviewer.equip_item`) [src: `scripts/ui/views/world_hero_previewer.lua:649`] | Apply cwv grip/scale and default-mesh correction on the inventory character preview (`:2922`) | Hook the DERIVED class, never the base - `class()` copies methods at load (CLAUDE.md; [src: `foundation/scripts/util/class.lua:51-57`]); slot keying is string vs numeric split; the copied callback can lose `skin`, so `info.skin_name` is the authoritative selected-illusion guard (#579) |
| `HeroPreviewer._spawn_item` [hook] `:10973` + `MenuWorldPreviewer._spawn_item` [hook] `:10981` | Spawns a single preview unit for an item [src: `world_hero_previewer.lua:895` / `scripts/ui/views/menu_world_previewer.lua:635`] | Bridge grip via `info.spawn_data[1].slot_index` and force cwv mesh in preview (`:10973`) | Both hooked because the base copy and derived copy are independent post-load (CLAUDE.md); v0.1.84 numeric-key fix |
| `LootItemUnitPreviewer.spawn_units` [hook] `:11001` | Illusion/skin browser spawns the display units, writing `self._spawned_units` AFTER return via `_spawn_items` [src: `scripts/ui/views/hero_view/loot_item_unit_previewer.lua:538`, `:504`] | Pre-pass `_om._cwv_browser_meshswap_apply` rewrites base-mesh spawn_data to the variant units (#419), then read spawned units to apply cwv scale in the cosmetic picker | MUST be `[hook]` not `[safe]` - `_spawned_units` is nil at safe-callback time (CLAUDE.md; DEVELOPMENT); `_load_item_units` rebinds item_data to the BASE IML entry (:254-255), so the #482 stamp rung is dead inside the `get_item_units` hook on this path - resolve against `self._item` instead; dual-rig `j_leftweaponattach` (see dead-ends) |
| `HeroWindowItemCustomization._setup_illusions` [hook] `:10931` | Builds the illusion grid for the selected item [src: `scripts/ui/views/hero_view/windows/hero_window_item_customization.lua:1518`] | Inject cwv cross-character illusions into the grid (`:10931`) | Console variant `HeroWindowCosmeticsLoadoutPoseInventoryConsole._setup_illusions` is a separate class if console support is added |
| `BackendInterfaceItemPlayfab.get_filtered_items` [hook] `:4180` | Returns backend items matching a filter for inventory/forge lists [src: `scripts/managers/backend_playfab/backend_interface_item_playfab.lua:627`] | Surface cwv variant items in the relevant lists (`:4180`) | DLC ownership gate - filter unowned-DLC entries before surfacing (CLAUDE.md "DLC Ownership Gate"); note `_build_entry` intentionally nils `required_dlc` on clones |
| `BackendInterfaceCraftingPlayfab.get_unlocked_weapon_skins` [safe] `:9056` | Returns the unlocked-skin set the forge treats as available [src: `scripts/managers/backend_playfab/backend_interface_crafting_playfab.lua:138`] | Mark cwv custom skins unlocked so illusions appear (`:9056`) | Backing store is `PlayFabMirrorBase.get_unlocked_weapon_skins` [src: `playfab_mirror_base.lua:2233`] - never commit to PlayFab (`docs/engine/11`) |
| `_G.Localize` [hook] `:7234` | Global loc-key -> string lookup | Supply display names/descriptions for `cwv_*` keys and `item_type` labels (`:7234`) | VMF `_localization.lua` is NOT auto-registered into global `Localize` (`docs/VMF_RECIPES.md`); item_type leak class (DEVELOPMENT "Naming flow") |

### Packages / residency + Unit C-API guards + lifecycle

| Class.method (kind) | Vanilla behavior | Why cwv hooks it | Trap / invariant |
|---|---|---|---|
| `PackageManager.load` / `unload` / `has_loaded` [hook,tbl] `:5338`/`:5343`/`:5348`; direct lease `:4443` | Refcounted package load/unload/state query [src: `foundation/scripts/managers/package/package_manager.lua:20`/`:196`/`:286`] | Treat the bundled Old Musket units as resident; hold the source-derived vanilla Dual Axes FP state-machine package across CWV equip/resync (`:4443`, #586) | A wield-time state-machine miss C-fatals at `PlayerUnitFirstPerson.set_state_machine` [src: `scripts/unit_extensions/default_player_unit/player_unit_first_person.lua:165`]; the #586 lease is synchronous, unique-ref, idempotent, and symmetrically released. Do not queue arbitrary mod unit paths (issue #403). |
| `Unit.node` / `has_node` / `flow_event` / `set_flow_variable` [hook] `:5459`/`:5466`/`:5481`/`:5490` | Engine C-API: node index lookup and flow-graph events on a unit; a missing node in `Unit.node` is an engine-level fatal, not a Lua error | Guard against missing bones / flow vars on cross-character rigs before the engine faults (`:5459`) | `Unit.node` errors bypass `pcall` - use `has_node` for existence (CLAUDE.md Lua quirks; J_LEFTWEAPONATTACH F2) |
| `StateInGameRunning.on_enter` [safe] `:9632` | Fires on entering keep/mission gameplay state [src: `scripts/game_state/state_ingame_running.lua:28`] | Run `_auto_register_all()` - backend is nil at mod init, ready here (`:9632`); after deferred owner rows enter `ItemMasterList`, invalidate vanilla's lazy weapon-skin reverse-index so custom associations rebuild (#567) | One-shot `_auto_registered` flag; registration-timing class (DEVELOPMENT "Registration Timing"). `WeaponSkins.matching_weapon_skin_item_key` snapshots owners/pools only when its private cache is nil [src: `weapon_skins.lua:7824-7855`] |
| `LoadoutUtils.sync_loadout_slot` [hook,tbl] `:10555` | Encodes an item as `rpc_sync_loadout_slot`, `item_id = NetworkLookup.item_names[item.key]` [src: `scripts/helpers/loadout_utils.lua:13`, id at `:25`] | Substitute a `base_weapon` shadow item so the cwv LOCAL-append id never desyncs a peer without the same append order (`:10555`, #278) | Plain table, table-form + nil guard; strict `__index` at [src: `network_lookup.lua:2521`] CTDs the decode; cross-peer wire-safety (`docs/engine/03`; project `project_vt2_cross_peer_wire_safety`) |
| `GearUtils.hot_join_sync` [hook] + peer-parity `on_enable` | Re-broadcasts a peer's equipment to a joining peer [src: `gear_utils.lua:462-495`]; parity enables after every peer acknowledges the same mod schema | Always-null the cwv skin during the join race, then replay the owner marker before the exact vanilla base+skin+wield sequence (#396/#425/#474/#579) | The marker carries only the missing owner key; vanilla remains authoritative for skin/units. Mixed peers never decode a local-append skin. |

### Same-mod network channels

| Channel | Payload | Purpose / safety |
|---|---|---|
| `cwv_item_identity` schema 1 | `{ slot, item_key }` | Positive owner identity for a vanilla-base equipment wire shape (#396). Only melee/ranged slots and real non-`skin_only` definitions are accepted; resolution also requires `def.base_weapon == received item_data.name`. Empty `item_key` clears the slot. VMF delivers the channel only to CWV peers. |

## Subsystem notes (how the vanilla flow runs end-to-end, for cwv's cases)

Each note is the minimum needed to read the hooks above; the owning `docs/engine`
doc carries the full architecture.

### Item -> mesh resolution (owner: `docs/engine/06`)

The one mesh seam is `BackendUtils.get_item_units` [src: `backend_utils.lua:144`]:
it resolves per-hand units from the skin entry when a skin is applied, otherwise
from `item_data.right_hand_unit`. cwv variants inherit `entry.name`/`entry.key`
from their clone (kept deliberately, per `feedback_cwv_clone_name_clobber`), so the
fallback path can land on the BASE entry's mesh - hence the cwv override hook forces
the variant mesh when `result.skin` is empty and the `backend_id` matches
`cwv_<key>_NNN` (`:10485`). In-world spawning runs through `GearUtils.create_equipment`
[src: `gear_utils.lua:7`] -> `spawn_inventory_unit` [src: `:155`] -> `link_units`
[src: `:293`], the last of which is where a cross-character clone's inherited
`a_unwielded_*` bone name faults. See `docs/engine/06` for the four-render-path
coverage matrix.

### Owner vs husk inventory (owner: `docs/engine/02`, `docs/engine/06`)

`SimpleInventoryExtension` (local/authoritative) and `SimpleHuskInventoryExtension`
(remote view) are separate root classes with no inheritance - a hook on one never
fires for the other [src: `simple_inventory_extension.lua:627` vs
`simple_husk_inventory_extension.lua:314`]. The husk resolves the inherited BASE
`item_data`, so a cwv item shows as its base weapon on a remote player unless the
husk `_wield_slot` hook re-keys mesh+transform off base+career (`:4634`, #392).
Because the husk mesh is spawned during hot-join before the skeleton is guaranteed
ready, every `Unit.node`-adjacent access must go through `has_node` first.

### Network lookups / RPC (owner: `docs/engine/03`)

cwv registers its item and skin keys into `NetworkLookup.item_names` /
`NetworkLookup.weapon_skins` as local index-appends (`#tbl + 1`), so a given key's
numeric id depends on which other mods appended before cwv on THAT peer (notably
Loremaster's Armoury clone entries, appended only where LA is enabled). A host
with LA and a client without it disagree on the id, and the receiver's decode hits
the strict error `__index` [src: `network_lookup.lua:2521`] -> client CTD (#278).
The fix substitutes a boot-stable `base_weapon` shadow before the encode on all
three live-slot senders (`game_object_initialized`, `_spawn_resynced_loadout`,
`LoadoutUtils.sync_loadout_slot`) plus the always-nulled hot-join replay. Wire
safety is unconditional, never behind a toggle (`docs/engine/03`, §31; memory
`reference_vt2_wire_safety_never_toggle_gated`).

### Previewers (owner: `docs/engine/09`)

Four preview surfaces resolve items differently. The keep inventory previewer is
`MenuWorldPreviewer`, whose methods are copies of `HeroPreviewer` taken at class
definition [src: `class.lua:51-57`] - so cwv hooks the derived class, and where a
method exists on both it hooks both (`_spawn_item` at `:10973`/`:10981`). The
illusion browser is `LootItemUnitPreviewer`; its `spawn_units` writes
`_spawned_units` only AFTER returning [src: `loot_item_unit_previewer.lua:504`,
`:538`], forcing a full `[hook]` wrapper. Grip offset bridges the string-keyed
`_item_info_by_slot` to the numeric-keyed `_equipment_units` via
`info.spawn_data[1].slot_index`. All three ride `BackendUtils.get_item_units`, so
the cwv mesh override there covers preview too (which is also why the dual-rig
crash below was so hard to isolate). A selected illusion is already recorded in
`info.skin_name`; that stored value outranks a nil post-hook argument and prevents
the default variant mesh correction from clobbering vanilla's selected spawn data.

### Packages / residency (owner: `docs/engine/05`)

Cross-character variants can also resolve a first-person state machine absent
from the receiver's native loadout. Vanilla adds that resource in
`WeaponUtils.get_weapon_packages` [src: `scripts/helpers/weapon_utils.lua:48-111`],
but `ProfileSynchronizer.profile_packages` derives its list from the backend
loadout visible at that instant [src:
`scripts/game_state/components/profile_synchronizer.lua:71-175`]. A later CWV
resync may therefore wield a different template against the stale package list.
Issue #586 holds the exact vanilla `.../melee/dual_axes` resource under one CWV
reference before wield; acquisition is synchronous because
`SimpleInventoryExtension._wield_slot` immediately calls
`PlayerUnitFirstPerson.set_state_machine` [src:
`simple_inventory_extension.lua:2096-2102`], whose engine blend-base-layer call
cannot be protected by `pcall` [src: `player_unit_first_person.lua:165-173`].
The lease remains stable across loadout/character changes and is released by
`on_disabled` / `on_unload`, then reacquired by `on_enabled`; gameplay-state
entry supplies an idempotent retry if PackageManager was cold at chunk load. See
`docs/engine/05` for the refcount + shutdown-leak model (#282).

## What the engine will NOT let us do (dead ends, already paid for)

Pulled from `DEVELOPMENT.md` and `J_LEFTWEAPONATTACH_INVESTIGATION.md` - do not
re-discover these.

- **No new animation clips.** System B can only pick from clips the target
  skeleton's state machine already authors; there is no path to ship animation
  files from a Workshop mod (DEVELOPMENT "Hard limits"). When Kruber's body lacks
  any clip for the donor's motion, the best available is the closest in-SM clip.
- **No per-career sub-action anim on a shared template.** The engine reads
  `anim_event_3p` directly with no career context [src:
  `weapon_unit_extension.lua:512`]. For cross-access on a vanilla item you cannot
  fix the foreign wielder without changing the native wielder, so the only options
  are a per-career variant item (System B) or the network-bound
  `WeaponUnitExtension._play_3p_anim` hook (`:1618`). Mutating the shared vanilla template's per-action
  events is wrong (DEVELOPMENT "cross-access").
- **No cross-sub-graph clip grafting.** Firing `to_<other_sm>` as
  `pre_action_anim_event` to borrow a clip from a foreign SM sub-graph does not
  cleanly route a single action - two reproducible failure modes (the switch clip
  eats the damage window; `anim_end_event_condition_func` strands the body in the
  new sub-graph). Confirmed v0.1.89 (DEVELOPMENT "Reaching clips that live in a
  different SM sub-graph"). Use the wield-commit pattern or accept the in-SM clip.
- **`force3p exists=true` is not proof a clip plays.** `Unit.has_animation_event`
  returns true whenever the master SM knows the name; the destination state in the
  current sub-graph may be a stub that animates nothing. Only visible motion counts
  (DEVELOPMENT "Discovery commands").
- **Display-rig node schema is invisible to Lua.** The `j_leftweaponattach`
  requirement only surfaces at runtime when the previewer's `Unit.node` lookup runs
  against the spawned `display_unit`. Single-sword rigs author only
  `j_rightweaponattach`; dual-wield variants must use a dual-attach rig
  (`display_dual_weapons` etc.) set on BOTH the `WeaponSkins.skins` and
  `ItemMasterList` skin entries, or the picker crashes on open/click
  (`J_LEFTWEAPONATTACH_INVESTIGATION.md`, ~20 versions to isolate).
- **`BackendUtils.get_item_units` cannot see its caller.** No clean way to
  distinguish "in-game equip" from "cosmetic picker" without fragile thread-local
  or stack-inspection hacks - a mirror there leaks across contexts. The durable fix
  is to populate the skin/IML entries correctly so no runtime mirror is needed
  (J_LEFTWEAPONATTACH L4).
- **The previewer reads the BASE template, not the cwv clone.** The character
  previewer resolves `ItemHelper.get_template_by_item_name(item_name)` on the
  inherited base name, so per-career wield poses and hand-attachment fields set on
  the clone are ignored - they must ALSO be patched onto the base template, scoped
  to cwv careers so vanilla wielders fall through (DEVELOPMENT "BASE template
  patching", crash `c847908d`).

## Doc maintenance

Follows `docs/engine/README.md` maintenance rules: if a cwv hook moves, a guard is
added, or a cited vanilla line drifts after a game patch, edit the affected row in
the SAME commit. Line numbers are against the 2026-07-11 decompile - match crash
logs by function name, not line. This doc is the template for the other mods'
`ENGINE_SURFACE.md`; keep the section shape (hook table -> subsystem notes ->
dead ends) stable.
