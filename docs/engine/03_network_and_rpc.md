# Engine reference 03 - Network, RPC and NetworkLookup

Provenance: every `file:line` below was grep-verified 2026-07-11 against the decompiled
vanilla source at `C:\Users\danjo\source\repos\Vermintide-2-Source-Code` (paths written
relative to that repo) or against this monorepo (paths relative to repo root). Anything
not verifiable is tagged `[unverified]`. Cross-refs: `docs/BUG_CLASSES.md` (classes 4, 9,
15, 19, 27, 31), `docs/VMF_RECIPES.md` sections 1/2/10, `tools/shared_lib/_lib_peer_parity.lua`.

Scope: the wire layer only - lookup registration, RPC send/dispatch, game objects and
game session, profile/inventory sync, husk vs owner. Not covered here: VMF's own
`network_send` implementation internals (see VMF_RECIPES section 10) and package loading
beyond what ProfileSynchronizer drives.

---

## 1. Architecture map

One row per file; each has exactly one job.

| File (vanilla) | Class / global | Single responsibility |
|---|---|---|
| `scripts/network_lookup/network_lookup.lua` | `NetworkLookup` | Builds every string<->index table that rides an RPC. Loaded once from boot (`scripts/boot.lua:1320`). `create_lookup` (:38-47) appends keys of a settings table; `init` (:2346-2370) runs over EVERY sub-table (:2386-2388): mirrors array index -> name into name -> index (:2348-2355, `ferror` on duplicates :2353) and installs a strict `__index` metatable that ERRORS on any missing key (:2360-2367). |
| `scripts/network_lookup/network_constants.lua` | `NetworkConstants` | Boot-time budget enforcement: `check_bounderies` (:5-16) fasserts `#NetworkLookup[t] <= Network.type_info(v).max` for each wire type; `#ItemMasterList` vs `weapon_id` (:50-52); `#damage_sources` vs `damage_source_id` (:58-63). Runs ONCE at boot - runtime appends are never re-checked. |
| `scripts/network/network_event_delegate.lua` | `NetworkEventDelegate` | The RPC receive dispatch table. `register(object, ...)` (:35-59) maps callback-name -> list of registered system objects; the generated `rpc_callback` (:45-54) resolves `object[callback_name]` at DISPATCH time, which is why `mod:hook` on a receiver method works (memory `reference_vt2_rpc_dispatch_dynamic_hookable`). `event_table.__index` (:20-29) prints/asserts `RPC not registered %q` for unknown RPC names. `_cleanup` fasserts everything unregistered at destroy (:111-121). |
| `scripts/network/network_transmit.lua` | `NetworkTransmit` | Every send path: `send_rpc` (:169), `send_rpc_server` (:185), `send_rpc_clients` (:431), `send_rpc_clients_except` (:455), `send_rpc_all` (:508), party/side variants (:220-506). Sends to self are queued (`queue_local_rpc` :99-121) and replayed next frame through the SAME `event_table` with `channel_to_self = 0` (`transmit_local_rpcs` :123-163) - local host receives its own RPCs through the identical receiver code path. Client->clients sends fassert (:432 etc.): clients may only talk to the server. |
| `scripts/managers/network/game_network_manager.lua` | `GameNetworkManager` (`Managers.state.network`) | Owns the engine-side `GameSession` (C API: `Network.create_game_session()` :19, host :27, client join :31-45). Pumps receive: `update_receive` calls `Network.update_receive(dt, self._event_delegate.event_table)` (:146-147). Hosts the `game_object_created_*` / `game_object_destroyed_*` callbacks named by go templates (player_unit :689-698, generic :728-730). `game_object_or_level_unit` / `unit_game_object_id` (:308-352) are the unit<->id bridges. |
| `scripts/network/game_object_templates.lua` | template table | Declares each `go_type`: which created/destroyed callback fires on peers (:4-10 `player_unit`) and which transform fields the engine auto-syncs (`syncs_position`, `syncs_pitch_yaw`). |
| `scripts/network/game_object_initializers_extractors.lua` | initializers / extractors | The game-object field codec. Initializer (owner side) builds the `data_table` with NetworkLookup INDICES baked in - e.g. `husk_unit = NetworkLookup.husks[husk_unit]`, `skin_name = NetworkLookup.cosmetics[skin_name]` (:86-89). Extractor (husk side) decodes indices back to names (:2123-2124) and emits `extension_init_data` with `is_husk = true` scattered through it (:2148-2231). |
| `scripts/network/unit_spawner.lua` | `UnitSpawner` | Owner path: `spawn_network_unit` (:336-352) spawns the local unit, marks `is_husk=false` (:341), runs the go initializer and `GameSession.create_game_object` (:346). Husk path: `spawn_unit_from_game_object` (:470-490) marks `is_husk=true` (:474), runs the extractor, builds extensions. Destruction: `world_delete_units` (:422-445) destroys the game object + `NetworkUnit.remove_unit`. |
| `scripts/network/network_unit.lua` | `NetworkUnit` | Per-unit network metadata store (go_id, go_type, owner peer, is_husk) :13-74. `is_husk_unit` (:68-70) is THE owner-vs-husk predicate. WARNING: `set_owner_peer_id` writes `.owner` (:56-58) but `owner_peer_id` reads `.peer_id` (:60-62) - the getter ALWAYS returns nil (latent vanilla bug). Resolve owners via `Managers.player:owner(unit)` or `unit_storage` instead. |
| `scripts/game_state/components/profile_synchronizer.lua` | `ProfileSynchronizer` | Profile/career reservation plus inventory PACKAGE synchronization - it syncs which resource packages each peer must load for everyone's loadout, NOT the items themselves. `profile_packages` (:71-161) walks `BackendUtils.get_loadout_item` per slot; the package set is hashed (`hash_inventory` :182-189) and versioned by `inventory_id` (:191-209); `update_local_packages` (:280-369) loads/unloads via `Managers.package`. `hot_join_sync` (:413-430) replays `rpc_assign_peer_to_profile` (sole RPC, :391-399) to a joining peer. `all_synced` gating (:222-273) blocks spawn until every peer loaded every inventory. |
| `scripts/helpers/loadout_utils.lua` | `LoadoutUtils` (plain table) | Loadout METADATA sync (inspect/Tab panel): `sync_loadout_slot` (:13-41) encodes `item_id = NetworkLookup.item_names[item_key]` (:25) and `rarity_id = NetworkLookup.rarities[rarity]` (:26) onto `rpc_sync_loadout_slot`; decode at :72-73. `hot_join_sync` (:62) re-sends per new peer. |
| `scripts/entity_system/systems/inventory/inventory_system.lua` | `InventorySystem` | Equipment RPC receivers, registered as an RPCS list (:11-16). `rpc_add_equipment` (:282-308) decodes slot/item/skin ids (:298-300) and - server side - RELAYS the same args to all other clients (`send_rpc_clients_except` :283-287). `rpc_wield_equipment` (:382-394) same shape. |
| `scripts/unit_extensions/default_player_unit/inventory/simple_inventory_extension.lua` | `SimpleInventoryExtension` | Owner-side equipment broadcast. `game_object_initialized` (:249-292) fires once the player game object exists and sends one `rpc_add_equipment` per slot with `item_id = NetworkLookup.item_names[item_data.name]` and `weapon_skin_id = NetworkLookup.weapon_skins[slot_data.skin or "n/a"]` (:255-264), then `rpc_wield_equipment` (:276-283). `add_equipment` also calls `LoadoutUtils.sync_loadout_slot` (:885). |

Engine-side (C, not in Lua source): `GameSession.*` (create/destroy game objects,
`game_object_field` / `set_game_object_field`), `Network.*`, the global `RPC` table of
generated senders, and `PEER_ID_TO_CHANNEL` / `CHANNEL_TO_PEER_ID`. RPC signatures and
field bit widths come from `global.network_config` [unverified - config file not present
in the decompile; referenced by the fassert text at `network_constants.lua:15`].

---

## 2. Lifecycle and data flow

Ordered by when it happens.

1. **Boot (before any mod loads).** `network_lookup.lua` is required from boot
   (`scripts/boot.lua:1320`); every table is appended in deterministic source order, then
   mirrored and sealed by `init` (`network_lookup.lua:2386-2388`). `network_constants.lua`
   fasserts budgets. Consequence: every VANILLA key has an identical index on every peer,
   forever. That boot-stability is what makes "substitute a vanilla key" a valid wire-safety
   move. Conversely, any entry appended AFTER boot has a PER-PEER index defined by that
   peer's mod set and registration order.

2. **State setup.** Each game state builds one `NetworkEventDelegate`
   (`state_ingame.lua:183-185`, `state_loading.lua:2143-2145`,
   `state_dedicated_server.lua:61`). Systems hand it their RPCS lists
   (`inventory_system.lua:11-16` -> `NetworkEventDelegate.register`;
   `profile_synchronizer.lua:391-399`). `GameNetworkManager.init` creates/joins the
   GameSession (`game_network_manager.lua:16-45`); `post_init` gives the session to
   `NetworkTransmit` (:111).

3. **Per frame.** Receive: `GameNetworkManager.update_receive` ->
   `Network.update_receive(dt, event_table)` (`game_network_manager.lua:147`) - the engine
   calls `event_table[rpc_name](event_table, channel_id, ...)`, which fans out to every
   registered system object (`network_event_delegate.lua:45-54`). Send-to-self: RPCs queued
   by `NetworkTransmit.queue_local_rpc` are replayed through the same `event_table` with
   channel 0 (`network_transmit.lua:123-163`) - so hooking a RECEIVER also intercepts the
   local host's own actions.

4. **Player unit spawn (owner).** `UnitSpawner.spawn_network_unit`
   (`unit_spawner.lua:336-352`): local unit + extensions, `is_husk=false`, then the
   `player_unit` initializer (`game_object_initializers_extractors.lua:36-109`) encodes
   profile/career/skin/husk-unit/buffs into the `data_table` - lookup INDICES, not strings
   (:86-89, buffs :65-73) - and `GameSession.create_game_object` replicates it.

5. **Player unit spawn (every other peer = husk).** Engine fires the template's created
   callback (`game_object_templates.lua:5`) -> `game_object_created_player_unit`
   (`game_network_manager.lua:689-698`) -> `UnitSpawner.spawn_unit_from_game_object`
   (`unit_spawner.lua:470-490`): `is_husk=true` (:474), extractor decodes fields via
   `GameSession.game_object_field` + reverse lookups
   (`game_object_initializers_extractors.lua:2088-2143`) and builds HUSK extensions
   (`is_husk = true` init data, :2148-2231). Husk and owner run DIFFERENT extension classes
   with no inheritance (BUG_CLASSES 5). The husk's inventory is rebuilt from the BASE
   `item_data.name` that arrives over `rpc_add_equipment` - a modded clone's identity never
   crosses the wire (BUG_CLASSES 27).

6. **Equipment sync.** Once the go exists, the owner's
   `SimpleInventoryExtension.game_object_initialized` sends `rpc_add_equipment` per slot +
   `rpc_wield_equipment` (`simple_inventory_extension.lua:249-283`). Receivers decode at
   `inventory_system.lua:298-306`. If the sender was a client, the SERVER receiver relays
   the identical args to all other clients (`inventory_system.lua:283-287`) - so one bad
   index poisons every peer, not just the host.

7. **Loadout metadata sync.** `add_equipment` -> `LoadoutUtils.sync_loadout_slot`
   (`simple_inventory_extension.lua:885`) -> `rpc_sync_loadout_slot`
   (`loadout_utils.lua:25-41`); replayed to hot-joiners (:62). Stored in
   `PlayerManager._player_loadouts` on peers; feeds the inspect/Tab UI only.

8. **Profile / package sync.** `ProfileSynchronizer` versions each player's package SET
   (`inventory_id` counter + `Application.make_hash`, `profile_synchronizer.lua:182-209`),
   distributes it through the shared `network_state`, and every peer async-loads what it
   is missing (:280-369). Spawn gates on `all_synced` (:222-273). Hot join: server replays
   profile assignments (:413-430).

9. **Teardown.** Systems MUST `unregister` from the delegate before destroy - `_cleanup`
   fasserts on leftovers (`network_event_delegate.lua:111-121`). Session disconnect runs
   per-object disconnect callbacks and nils the spawner's session
   (`game_network_manager.lua:745-755`).

---

## 3. Hookable seams

Rules that apply to EVERY seam here: grep for an existing hook on the (class, method)
first (VMF drops the second registration silently - CLAUDE.md non-negotiable 8); a later
mod's hook wraps OUTERMOST, so its early return silences yours (memory
`reference_vt2_crossmod_hook_shadowing`); thread every vanilla parameter through.

| Seam | Why it works / safe pattern | Known traps |
|---|---|---|
| **RPC receivers** (`InventorySystem.rpc_add_equipment`, `PlayerManager.rpc_sync_loadout_slot`, any name in a system's RPCS list) | Dispatch resolves `object[callback_name]` per call (`network_event_delegate.lua:45-54`), so a class-method hook intercepts network AND local-loopback deliveries. Pattern: full `mod:hook` wrap; validate ids with `rawget` BEFORE calling `func`; returning early = silently dropping the RPC for this peer only. Reference implementation: cim's consolidated guard `crafting_in_modded_dev/scripts/mods/crafting_in_modded_dev/crafting_in_modded_dev.lua:873-903`. | (a) A receiver-side guard runs only on peers that HAVE your mod - it can never protect a vanilla peer (BUG_CLASSES 31, diagnosis 3). (b) Server receivers often RELAY their args (`inventory_system.lua:286`, `player_manager.lua:83` [unverified line, cited from cim comment]); dropping a trailing param corrupts the relay for everyone downstream. |
| **Sender helpers** (`LoadoutUtils.sync_loadout_slot`) | `LoadoutUtils` is a PLAIN table - table-form hook with an existence guard (`rawget(_G, "LoadoutUtils") and LoadoutUtils.sync_loadout_slot`), exactly as cwv does at `character_weapon_variants/scripts/mods/character_weapon_variants/character_weapon_variants.lua:10381-10408`. Pattern: substitute a SHADOW copy of the item (or swap-and-restore one field, cim `crafting_in_modded_dev.lua:764-800`) so local state is untouched and only the wire sees the vanilla key. | Cross-mod: cwv, cim and cosmetics all hook this function from their own registrations - fine (VMF chains across mods), but each must tolerate already-substituted input. |
| **Encode-site extension methods** (`SimpleInventoryExtension.game_object_initialized`) | Hook the method that gathers values INTO the RPC and null/swap the modded value around `func`, restoring after: cwv skin-null hook `character_weapon_variants.lua:10424-10447`. Capture ALL return values (r1..r4 pattern) - multi-return collapse is BUG_CLASSES 2. | Only covers THIS send site; other encoders of the same RPC exist (`interactions.lua:1244`, `inventory_system.lua:235/335`) - see section 5 candidate 3. |
| **Networked control functions with trailing sync params** (`AnimationSystem.anim_event` :119, `anim_event_with_variable_float` :139 in `scripts/entity_system/systems/animation/animation_system.lua`) | Pattern: NAME every vanilla param including the trailing `skip_sync` and pass it through unchanged - wt's fixed hook `weapon_tweaker/scripts/mods/weapon_tweaker/weapon_tweaker.lua:4585-4592`. | THE skip_sync trap (BUG_CLASSES 19): vanilla gates its re-broadcast on `if not skip_sync and Managers.state.network:game()` (:120, :140) and the RPC receiver replays with `skip_sync=true`; a hook that omits the param collapses it to nil, the husk replay re-broadcasts, and every peer's husks freeze in an RPC feedback loop. No error, no log; solo is immune. |
| **NetworkLookup tables (injection)** | Writing is allowed - the metatable defines only `__index` (`network_lookup.lua:2361-2365`), no `__newindex`. Manifested consumers use `tools/shared_lib/_lib_network_lookup.lua`: it reads with `rawget`/`next`, proves the complete numeric side is dense `1..N`, proves every forward/reverse pair, rejects non-finite/non-positive/non-integral indices without mutation, and only then appends both directions with `rawset`. Current consumer copies are CWV, Career, Cosmetics, Enemy, both WT streams, and WOC. | Injection makes the entry exist LOCALLY only. Local structural validity does not prove peer parity, wire capacity, or mod presence. The moment its index rides a vanilla RPC, every peer without the identical append set is exposed (section 4, class 31). Never restore the old `#tbl + 1` shortcut; read cold keys with `rawget` (BUG_CLASSES 4/91). |
| **VMF mod-to-mod channel** (`mod:network_send` / `mod:network_register`) | Delivered only to peers running the SAME mod id with a matching handler - absence of reply proves absence of the mod. This is the transport for the peer-parity beacon (`tools/shared_lib/_lib_peer_parity.lua:26-33`) and for side-channels like cim's `cim_modded_slot` (`crafting_in_modded_dev.lua:714-720`): vanilla peers drop the packet silently, never crash. | `"server"` recipient is silently dropped (BUG_CLASSES 15); 500-char string cap; version your payload with a leading schema int and drop mismatches (BUG_CLASSES 9, VMF_RECIPES section 10, gt's `GT_LOBBY_RPC_SCHEMA` precedent). |
| **NOT a seam: `NetworkTransmit.send_rpc*`** | Technically hookable but wrong altitude: it is the hot transport path, fasserts on unknown rpc names (:172, :188), and carries no domain context to decide substitutions. Hook the semantic encode site instead (rows above). | - |

---

## 4. Traps and crash classes

| # | Trap | Mechanism | Cross-ref |
|---|---|---|---|
| 1 | **Strict `__index` on every NetworkLookup table** | Any read of a missing key ERRORS: `"Table X does not contain key"` (`network_lookup.lua:2360-2367`). Fires on the SENDER at encode (unknown key) or the RECEIVER at decode (unknown index). Cold reads must be `rawget`. | BUG_CLASSES 4; CLAUDE.md "rawget for fragile globals" |
| 2 | **Index-parity divergence (the issue 371 crash)** | Modded appends are per-peer `#tbl + 1`; the numeric id depends on every other mod that appended first on THAT peer (LA clones, load order). A foreign index decoded at `loadout_utils.lua:72` or `inventory_system.lua:299-300` fatals via trap 1, or decodes to nil and a downstream deref fatals (`RaritySettings[nil].order`). The non-mod peer dies; the mod-haver is fine; solo never reproduces. | BUG_CLASSES 31; issues #278, #371, #422; memory `reference_vt2_wire_safety_never_toggle_gated` |
| 3 | **Wire safety gated by a toggle** | Sender-side substitution MUST be unconditional. cim v0.8.15 bundled the rarity rewrite behind default-OFF `persist_modded_loadouts` and every vanilla client of a default cim host CTD'd. Fix shape: a PURE coercion helper that takes no toggle argument (`crafting_in_modded_dev.lua:758-762`), asserted ungated by the regression suite. | BUG_CLASSES 31 fix template |
| 4 | **Receiver guards cannot protect non-mod peers** | Your guard code only exists on peers running your mod. Receiver-side `rawget` guards (cim `crafting_in_modded_dev.lua:874-882`) are a SECOND layer protecting your own users from other peers' divergence - never the primary fix. | BUG_CLASSES 31 diagnosis 3 |
| 5 | **skip_sync hook drop -> RPC re-broadcast loop** | Vanilla `AnimationSystem.anim_event_with_variable_float(self, unit, event, var, val, skip_sync)` re-broadcasts unless `skip_sync` (`animation_system.lua:139-153`); receiver replays with `skip_sync=true`. Hook omitting the 6th param = nil = infinite husk-animation loop in any 2+ human game. Symptomless in logs; A/B the mod to confirm. | BUG_CLASSES 19; memory `reference_vmf_hook_drops_skip_sync_rpc_loop` |
| 6 | **Server-relay arg corruption** | Server receivers re-send their argument list to other clients (`inventory_system.lua:286, :370, :386`). A wrap hook that drops or reorders trailing args corrupts the relayed copy for every downstream peer even when the local decode looked fine. Thread all params (cim `crafting_in_modded_dev.lua:884-887`). | BUG_CLASSES 19 (variant) |
| 7 | **Husk resolves BASE item_data** | Equipment reaches peers as `item_data.name` / base indices; a modded clone's identity never crosses. Owner-path logic (hooks keyed on your item key) is structurally unreachable for husks - re-key husk visuals from base+career instead. | BUG_CLASSES 27; memories `reference_vt2_husk_resolves_base_item_data`, `reference_vt2_husk_base_career_rekey` (#392) |
| 8 | **Husk skeleton readiness / hot-join** | Husk attachment work at hot-join must guard `Unit.has_node` - the skeleton may not be ready. | memory `reference_vt2_husk_attachment_skeleton_readiness` |
| 9 | **Unknown RPC name = assert** | Sending a name not in `RPC` fasserts on the sender (`network_transmit.lua:172`); receiving a name nobody registered hits the delegate's `visual_assert` + no-op (`network_event_delegate.lua:25-28`). Mods cannot add NEW vanilla RPC types - only new NetworkLookup VALUES or VMF channels. | - |
| 10 | **Boot-only budget asserts** | `network_constants.lua` checks lookup sizes against wire bit widths ONCE at boot (:39-73). Runtime appends silently pass; overflow behavior at send time is engine-defined [unverified]. See section 5 candidate 1. | - |
| 11 | **`NetworkUnit.owner_peer_id` always nil** | Setter writes `.owner`, getter reads `.peer_id` (`network_unit.lua:56-62`). Use `Managers.player:owner(unit)` / `unit_storage:go_id`. | - |
| 12 | **Peer-keyed caches wiped on level transitions** | `PlayerManager.remove_player` fires on map change, not just disconnect. | BUG_CLASSES 24 |
| 13 | **AI-takeover / despawn POSITION_LOOKUP nil frame** | One-frame nil deref window on despawn; every peer needs the fix, not just the host. | memory `reference_vt2_ai_takeover_despawn_poslookup_crash` |
| 14 | **Modded NetworkLookup key on a vanilla RPC is NEVER acceptable, even "just cosmetic"** | The doctrine (issue 371): cosmetic axes get sender-side SUBSTITUTION to a boot-stable vanilla key; gameplay axes (where a substitute would change behavior) must go INERT until peer parity is positively confirmed. | memory `project_vt2_cross_peer_wire_safety`; section 5 below |

---

## 5. Implications for our mods

### 5.1 The codified safe patterns (copy these, do not reinvent)

**Injection recipe** - when registering a modded key into a standard dense,
bidirectional NetworkLookup table, load the manifested local copy once from the
mod entry and pass it to every registration owner:

```lua
local index, inserted, reason = NetworkLookupLib.register_named(
    NetworkLookup, "item_names", key)
if not index then
    -- Log the stable reason and leave the feature inert. No lookup byte changed.
    return false, reason
end
```

`inserted=false, reason="already_registered"` is a successful idempotent result.
All other non-index results fail closed. The helper validates the entire raw table
before trusting even an exact target pair, because Lua 5.1's length operator cannot
identify a safe append boundary in sparse state. Canonical consumers include Career's
two ordered `buff_templates` catalogs, CWV's Outrider projectile lookup, WOC's relic
item name, and Enemy's Warlord/Chosen `breeds` plus `damage_sources` pairs. Direct
legacy append owners remain migration work under #428; do not copy their pattern.

**Sender substitution (cosmetic axis)** - swap the modded key for a boot-stable vanilla
key around the encode, restore after; local state untouched:

- item key -> `base_weapon` shadow item: cwv `character_weapon_variants.lua:10381-10408`
  (issue 278), byte-identical port in WOC (`weapons_of_chaos.lua:272-289`, issue 422).
- rarity "modded" -> "unique": cim pure helper `_cim_wire_safe_rarity`
  (`crafting_in_modded_dev.lua:758-762`) called UNCONDITIONALLY on the send path; the
  helper takes no toggle argument BY CONSTRUCTION (trap 3).
- skin key -> nil (encodes vanilla `"n/a"` index): cwv
  `character_weapon_variants.lua:10424-10447` around
  `SimpleInventoryExtension.game_object_initialized`.

**Receiver pre-decode guard (second layer, protects OUR users from other peers)** - cim
`crafting_in_modded_dev.lua:873-903`: `rawget(NetworkLookup.item_names, item_id) == nil`
-> printf ALERT + drop the RPC; all vanilla params threaded through otherwise.

**Peer-parity gate (gameplay axis)** - `tools/shared_lib/_lib_peer_parity.lua` (copied
per mod, factory via `mod:dofile`): VMF-channel presence beacon; features initialize
DISABLED and enable only on positive all-peers-acked evidence; any beacon error
force-disables (fail-safe posture, :49-58). Use for any feature where substitution would
change gameplay outcomes on the wire.

**Enemy-side note:** Enemy Tweaker's runtime Warlord and Chosen clones explicitly
register their names in both `NetworkLookup.breeds` and `damage_sources` through the
same helper before publishing the clone into `Breeds`. That proves local structural
closure only. The same parity rules apply to breed indices on spawn RPCs [unverified
which RPCs carry breed ids at runtime; `go_types`/extractors carry breed NAME via
blackboard, spawn requests carry template ids `unit_spawner.lua:416`].

### 5.2 Improvement candidates

| Pri | Mod | Our file:line | Current behavior -> engine-idiomatic alternative | Impact |
|---|---|---|---|---|
| P2 | all injectors | `_lib_network_lookup` consumers plus remaining direct legacy owners | Runtime appends never check the wire-type budget the engine fasserts at boot (`network_constants.lua:5-16, :50-63`). -> Add an owner-supplied shared bound check `idx <= Network.type_info("<wire_type>").max` (weapon_id for item_names, lookup for weapon_skins, buff_lookup for buff_templates) at inject time; refuse + printf ALERT on overflow. | Prevents an undefined-behavior bit-width overflow as mod content grows; NetworkConstants already caches the maxima. |
| P2 | crt | `career_tweaker_tourney.lua:31-42`, `career_tweaker_big_rebalance.lua:112-135` | Stub pre-registration gives SAME-mod index determinism, but nothing protects a NON-crt peer if a new-template buff id ever encodes onto a vanilla buff RPC (`NetworkLookup.buff_templates[...]` on rpc buff sync); crt has no parity gate and no substitution. -> Verify whether trn/BR stub buffs ride networked buff paths; if yes, gate their APPLICATION behind `_lib_peer_parity` (gameplay axis - substitution impossible); if provably local-only, document that invariant next to the registration. | Closes the last unaudited class-31 axis in the repo (issue 371 axis map). |
| Resolved #741 | cwv | `character_weapon_variants.lua` wire-safety block + `_cwv_cosmetic_skin_wire.lua` | One exception-safe helper now unconditionally nulls every CWV skin around all three live-slot equipment senders (`game_object_initialized`, `_spawn_resynced_loadout`, `GearUtils.hot_join_sync`); profile sync separately uses the same predicate. Exact appearance travels only as string keys on `cwv_item_identity`; the old parity-gated numeric replay is removed. Interaction/pickup relays either originate from these safe records or relay already-decoded vanilla ids; keep sender-census tests when adding a new live-slot encoder. | Closes the residual class-31/64 surface without assuming same-mod numeric lookup parity. |
| P3 | cim | `crafting_in_modded_dev.lua:878-882` | Unknown item id -> whole `rpc_sync_loadout_slot` dropped (stale panel slot). -> Optionally decode to the reserved `"n/a"` sentinel (index 1 by construction, `network_lookup.lua:250-252`) so the slot updates with a placeholder instead of going stale. | Cosmetic-only polish; current drop is safe. |
| P3 | shared lib | `tools/shared_lib/_lib_peer_parity.lua:286-293` | `install()` wraps `mod.update` (BUG_CLASSES 8 layered-rewrap risk, self-documented). -> Enforce the documented contract (host with its own `mod.update` calls `inst:tick(dt)` itself) via a lint/regression check rather than a comment. | Prevents a silent tick drop when a host mod later adds its own update. |
| Resolved #1125 | cwv | `_cwv_regression_identity.lua` (`cwv_inherits_base_name`) | The live regression now requires every clone's `entry.name` to equal its exact authored vanilla `def.base_weapon`; nil, another vanilla base, and the CWV key all fail. The base key is therefore the same boot-captured `damage_sources` identity consumed by native attribution, while `entry.cwv_variant` remains the custom discriminator. | Turns CWV's formerly implicit invariant into an executable check with planted failures. |
| P3 | WOC | `weapons_of_chaos.lua:256-260` | Its direct `item_names` injector still does not mirror into `damage_sources` (MIL does, `_moreitemslibrary_embedded.lua:279-280`). -> Assert that every runtime-registered item keeps a vanilla name or is mirrored into `damage_sources`. | Closes the remaining non-CWV half of the original audit row. |
| P3 | repo docs | `network_unit.lua:56-62` (vanilla) | Nothing in our code reads `NetworkUnit.owner_peer_id` today [grep-verified 2026-07-11]. -> Keep it that way: the getter is broken in vanilla (reads `.peer_id`, setter writes `.owner`); resolve owners via `Managers.player:owner(unit)`. | Prevents a nil-owner bug class from ever entering. |
