# VT2 networking reference for cosmetics/visuals

Source code paths below are absolute against `C:\Users\danjo\source\repos\Vermintide-2-Source-Code\`. Verified 2026-05-19 against the current VT2 source dump.

## 1. Vanilla item-equip flow (in-mission)

The "what visual unit gets spawned on each machine" pipeline has six observable hand-offs. The key insight: **item identity + skin travel as separate channels** and the *units themselves are never sent over the wire* — every peer spawns its own local copy after looking up unit paths by name.

### 1a. Local equip (owner side)

1. **`SimpleInventoryExtension.add_equipment` — `scripts/unit_extensions/default_player_unit/inventory/simple_inventory_extension.lua:858`**
   Resolves `item_units` via `BackendUtils.get_item_units(item_data, nil, nil, career_name)` which calls `backend_items:get_skin(backend_id)` to fetch the equipped skin **from the local backend mirror** (`scripts/managers/backend/backend_utils.lua:144-189`).
   Calls `GearUtils.create_equipment` to spawn 1P+3P weapon units locally.
   Then:
   - `CosmeticUtils.update_cosmetic_slot(player, slot_name, item_name, slot_equipment_data.skin)` → writes `slot_melee_skin` / `slot_ranged_skin` / etc. into `PlayerSyncData` (a game-object replicated to all peers).
   - `LoadoutUtils.sync_loadout_slot(player, slot_name, item)` → broadcasts `rpc_sync_loadout_slot` (carries item_key, rarity, power_level, properties, traits — **no skin field**).

2. **`SimpleInventoryExtension.game_object_initialized` — `simple_inventory_extension.lua:249-292`**
   On player-unit go_id creation (or hot-join), iterates `equipment.slots` and broadcasts `rpc_add_equipment(unit_go_id, slot_id, item_id, weapon_skin_id)` per slot. Skin is encoded via `NetworkLookup.weapon_skins[slot_data.skin or "n/a"]`. Then sends `rpc_wield_equipment` for the wielded slot.

3. **`GearUtils.spawn_inventory_unit` — `scripts/unit_extensions/default_player_unit/inventory/gear_utils.lua:155-277`**
   Per-hand: `Managers.state.unit_spawner:spawn_local_unit_with_extensions(weapon_unit_3p_name, …)` then `spawn_local_unit_with_extensions(weapon_unit_name, …)` for 1P. These are **local-only spawns** — they never go through the unit_storage GameObject system. After spawning, `GearUtils.apply_material_settings(unit, material_settings_name)` paints emissive glow / colors on the local instance.

### 1b. Remote receive (other peers' machines)

4. **`InventorySystem.rpc_add_equipment` — `scripts/entity_system/systems/inventory/inventory_system.lua:282-308`**
   Server relays to other clients (`send_rpc_clients_except`), then calls `inventory_extension:add_equipment(slot_name, item_name, skin_name)` on the local unit's inventory ext — which for any non-local player is `SimpleHuskInventoryExtension`.

5. **`SimpleHuskInventoryExtension.add_equipment` — `simple_husk_inventory_extension.lua:185-222`**
   Does NOT spawn units. Just records `slot.skin = skin_name` and `slot.item_template_name` in `_equipment.slots[slot_name]`. No visual change.

6. **`SimpleHuskInventoryExtension._wield_slot` — `simple_husk_inventory_extension.lua:641-770`**
   Triggered by `rpc_wield_equipment`. Reads `slot.skin` and calls `BackendUtils.get_item_units(item_data, nil, slot.skin, self._career_name)` — passing the husk's stored skin overrides the (missing) local backend lookup. Calls `GearUtils.spawn_inventory_unit` to spawn 3P units (no 1P, `owner_unit_1p` is nil). Inside spawn_inventory_unit, `GearUtils.apply_material_settings` paints the 3P unit's emissive glow.

### Hat / portrait frame / character-skin equip

- **Hats**: `AttachmentSystem.rpc_create_attachment(unit_go_id, slot_id, item_name_id)` — `scripts/entity_system/systems/attachment/attachment_system.lua:64-75`. Server-relayed; receiver calls `attachment_extension:create_attachment(slot_name, item_data)` — local class is `PlayerUnitAttachmentExtension`, remote-husk class is `PlayerHuskAttachmentExtension` (`scripts/unit_extensions/default_player_unit/attachment/player_husk_attachment_extension.lua`).
- **Portrait frames**: `CosmeticSystem.rpc_set_equipped_frame` — `scripts/entity_system/systems/cosmetic/cosmetic_system.lua:68-83`.
- **Character skin / hero color / weapon skin (display in keep)**: NOT sent via RPC — broadcast through `PlayerSyncData` game object (`scripts/managers/player/player_sync_data.lua:23-32`). Other peers' UI/HUD reads the synced field via `player:get_data(slot)` for player-list portraits etc.

### The role of BackendInterfaceItem / get_loadout_item

`BackendUtils.get_item_units(item_data, backend_id, skin, career_name)` — `backend_utils.lua:144`:
- If a `skin` argument is supplied (the husk path, line 662 of husk wield), `WeaponSkins.skins[skin]` overrides every unit field (left/right_hand_unit, ammo_unit, projectile_units_template, pickup_template_name, icon, material_settings_name).
- If no skin arg, queries `Managers.backend:get_interface("items"):get_skin(backend_id)` — only the LOCAL player's backend mirror has the skin lookup table; **husks never call this path because their `item_data.backend_id` is the remote player's backend id, which doesn't exist in the local mirror**. That's why skin must travel as an explicit `rpc_add_equipment` parameter.

## 2. Husk pipeline

### The extension pair

`scripts/network/unit_extension_templates.lua` declares the four player-unit lists per extension template:

- `self_owned_extensions` (lines 8-37) — used for the local player + bots owned by the local machine
- `self_owned_extensions_server` (lines 38-69) — used for self-owned units on dedicated-server hosts
- `husk_extensions` (lines 70-88) — used for remote players viewed locally
- `husk_extensions_server` (lines 89+) — used for remote players on the host

Confirmed husk-twin pairs for cosmetics/inventory:
- `SimpleInventoryExtension` ↔ `SimpleHuskInventoryExtension`
- `PlayerUnitAttachmentExtension` ↔ `PlayerHuskAttachmentExtension`
- `GenericUnitInteractorExtension` ↔ `GenericHuskInteractorExtension`
- `PlayerUnitLocomotionExtension` ↔ `PlayerHuskLocomotionExtension`

**Same on both lists (shared classes; one hook suffices):**
- `BuffExtension`, `CareerExtension`, `PlayerUnitHealthExtension`, `PlayerUnitCosmeticExtension`, `GenericUnitInteractableExtension`, `PlayerUnitFadeExtension`, `PlayerUnitDarknessExtension`, `StatisticsExtension`.

Class inheritance does NOT bridge the gap. VT2's `foundation/scripts/util/class.lua:51-57` copies parent methods into the child at definition time; there is no `__index` chain. `SimpleHuskInventoryExtension` is a separate root class, not a subclass of `SimpleInventoryExtension`. So `mod:hook("SimpleInventoryExtension", method, …)` never fires for remote-player units (this is the recurring trap documented in `feedback_vt2_husk_extension_class_pair.md`).

### Package-preload requirement (the crash window)

`Managers.state.unit_spawner:spawn_local_unit_with_extensions(unit_name, …)` requires the unit's package to be already loaded. The vanilla preload pipeline is:

1. `Managers.backend:get_skinned_inventory_packages_for_career(career_name)` builds a set of unit paths from the equipped items + weapon skins.
2. The set is shipped to other peers via the SharedState `peer.inventory_list` key (`scripts/game_state/components/network_state_spec.lua:638-661`). Encoded with `LibDeflate` after lookup via `NetworkLookup.inventory_packages` (`scripts/network_lookup/network_lookup.lua:2315-2320` referencing `scripts/network_lookup/inventory_package_list.lua` — 1513 entries).
3. Each peer loads its own ProfileSynchronizer-driven package set asynchronously before spawning the player unit. `loaded_inventory_id` (peer key, lines 653-661) tells the server when each peer is ready.

**The crash window:** if `GearUtils.spawn_inventory_unit` is called with a unit_name that the local machine's package set didn't include, the call fails (`Resource not found` engine fatal). This bypasses `pcall`. Custom-mesh weapons must therefore appear in `inventory_package_list.lua` OR be force-loaded through `Managers.package:load(path, ...)` BEFORE the husk's `_wield_slot` runs.

Note (per `DEVELOPMENT.md § Force-load only paths in inventory_package_list.lua`): `Managers.package:load` succeeds synchronously but async fatals "Resource not found" if the path isn't in `inventory_package_list.lua`. The fatal bypasses pcall. Display units typically are not listed. The only fully safe path for cross-peer custom meshes is to ship vanilla unit paths (the Loremaster's Armoury `data.mat_to_use` overlay pattern) — see `character_weapon_variants/RECIPES.md § Custom-mesh add-on — LA-style pattern`.

## 3. Per-unit visuals — what is per-instance vs shared

### Per-instance (safe to mutate freely; no global side effect)

- `Unit.set_color_for_materials(unit, var, Quaternion(a,r,g,b))` — per-unit instance. Only touches that unit's material binding.
- `Unit.set_vector3_for_materials(unit, var, Vector3)` — per-unit instance. Used by `GearUtils.apply_material_settings` for HDR emissive colors (`gear_utils.lua:137-142`).
- `Unit.set_color_for_materials_in_unit_and_childs(unit, var, ...)` — per-unit + per-child instance (still local).
- `Unit.set_texture_for_materials(unit, var, texture_name)` — per-unit instance. Used by LA-pattern paint pipelines.
- `Unit.set_scalar_for_materials`, `set_vector2_for_materials`, `set_vector4_for_materials`, `set_matrix4x4_for_materials` — all per-unit.
- `Unit.set_flow_variable`, `Unit.set_unit_visibility`, `Unit.flow_event`, `Unit.animation_event`, `Unit.set_data` — per-unit-instance.

### Shared (mutation has global side effects)

- `MaterialSettingsTemplates[name]` global lookup table populated at module-load by four files:
  - `scripts/settings/equipment/weapon_material_settings_templates.lua`
  - `scripts/settings/equipment/skin_material_settings_templates.lua`
  - `scripts/settings/equipment/cosmetic_material_settings_templates.lua`
  - `scripts/settings/equipment/pickup_material_settings_templates.lua`
  Mutating a template entry affects every subsequent spawn that reads it (this is what `cosmetics_tweaker`'s glow override does — temporarily mutates the template inside `apply_material_settings` hooks, applies, restores).
- `WeaponSkins.skins`, `ItemMasterList` — global item registries.
- `NetworkLookup.weapon_skins`, `NetworkLookup.item_names`, `NetworkLookup.inventory_packages`, `NetworkLookup.equipment_slots` — global index tables. Mutating these mid-session is unsafe; they fold into combined_hash.

### MaterialSettingsTemplates application is per-instance

`GearUtils.apply_material_settings(unit, material_settings_name)` — `gear_utils.lua:107-153` — reads the global template and applies each variable via `Unit.set_*_for_materials(unit, …)`. So **the template is shared but the side effect is per-unit-instance**. Hooking `apply_material_settings` and mutating template fields before delegating is the safe way to override (the cosmetics_tweaker pattern). Hooking and re-painting via post-call overlay does NOT work reliably for 1P units (vanilla's writes paint 1P; second writes through the same API silently fail to render — see `reference_vt2_weapon_glow_system.md`).

## 4. Late-join handshake

When a client joins mid-mission, three layers fire in order:

### 4a. SharedState bulk sync (pre-spawn)

`scripts/network/shared_state.lua` synchronizes a typed state table across peers. Spec at `scripts/game_state/components/network_state_spec.lua`. The relevant keys for cosmetics:

- `peer.inventory_list` (lines 638-661) — per-peer-and-local-player-id encoded inventory package set (LibDeflate-compressed byte array of NetworkLookup.inventory_packages indices for first_person + third_person package groups).
- `peer.loaded_inventory_id` — tells the server when each peer finished loading the package set.
- `peer.peer_hot_join_synced` (line 469) — tells the rest of the cluster a peer has completed full SharedState sync.

Mid-mission joiners receive the full SharedState before their player unit is spawned. `STRING_CHUNK_SIZE = 500` (line 21) — strings are chunked to 500-byte RPC parameters and reassembled on the receiver via the `complete` flag (lines 298-303).

### 4b. Per-system hot_join_sync RPCs (post-spawn)

`EntitySystemBag.hot_join_sync(peer_id)` walks every system and calls its `hot_join_sync(peer_id)` if defined (`scripts/entity_system/entity_system_bag.lua:77-80`). Cosmetics-relevant implementations:

- **`GearUtils.hot_join_sync` — `gear_utils.lua:462-514`**: invoked from `SimpleInventoryExtension.hot_join_sync` (line 1108) AND `SimpleHuskInventoryExtension.hot_join_sync` (line 578). Re-sends `rpc_add_equipment(channel, go_id, slot_id, item_id, weapon_skin_id)` per equipped weapon slot, then `rpc_wield_equipment` (gated on profile_synchronizer's `is_peer_all_synced(peer_id)` — the late-joiner must have finished loading packages, otherwise we just log a crash warning). Skin survives the late-join via this RPC parameter.
- **`AttachmentUtils.hot_join_sync` — `scripts/helpers/attachment_utils.lua:81-114`**: re-sends `rpc_create_attachment` per attached hat / accessory + buff state.
- **`CosmeticSystem.hot_join_sync` — `cosmetic_system.lua:122-132`**: replays any active emote anim_event + show_inventory state.
- **`LoadoutUtils.hot_join_sync(peer_id)` — `scripts/helpers/loadout_utils.lua:47-68`**: host-only. Iterates every player's stored `Managers.player:player_loadouts()` and re-sends `rpc_sync_loadout_slot` per loadout-bearing slot (melee, ranged, necklace, ring, trinket_1). This is the wire format for backend-stats (rarity / power level / properties / traits / item_key) — separate from the weapon-skin propagation path.

### 4c. PlayerSyncData GameObject auto-replicates on connect

The `player_sync_data` game object created in `PlayerSyncData.init` (`scripts/managers/player/player_sync_data.lua:10-42`) holds the slot_melee_skin / slot_ranged_skin / slot_hat / slot_frame / slot_skin / slot_pose fields. GameSession auto-replicates current field values to new joiners — no explicit hot_join_sync call needed for these.

## 5. Mod-author primitives (VMF)

### `mod:network_send` / `mod:network_register`

VMF wraps `ModManager.network_send(destination_peer_id, port, payload)` — `scripts/managers/mod/mod_manager.lua:595-605`. The underlying RPC is `RPC.rpc_mod_user_data(channel_id, src, dst, port, payload)`, where `payload` is a **single string parameter**.

VMF packs every user argument (the rpc_name_id + the args you passed) into one JSON-encoded string before calling `network_send`. This collapses to Stingray's hardcoded RPC string-parameter limit. The cap manifests as:

```
mod_manager.lua:627: Failed to pack parameter 3, too many characters in string with max length 500
```

The 500-byte cap is engine-side, hardcoded, unaffected by `max_upload_speed = 512` (bandwidth throttle, unrelated) or `small_network_packets = 576` (MTU, unrelated). The error fires inside VMF's safe-hook wrapper, so it **never surfaces as a crash** — the broadcast silently no-ops and clients never receive anything. Symptom is silence, not a crash.

### The chunked-send fix (mirror SharedState's pattern)

`SharedState` splits strings at `STRING_CHUNK_SIZE = 500` and sends each chunk with a `complete` boolean. Mod-side replication of this pattern lives in `chaos_wastes_tweaker.lua` (ct v0.7.59-alpha): `cjson.encode` the payload, split at 400 chars (extra headroom for VMF's `[mod_id, rpc_id]` envelope plus JSON wrapper `[session, seq, total, "<chunk>"]`), send `(session, seq, total, chunk_str)` per chunk via `mod:network_send`. Receiver buffers per-sender on `session`; a different `session` id resets the buffer. Decodes when `received == total`.

`cjson` is a VT2 global (no require needed). `Application.time_since_launch()` produces a monotonic float suitable as a session id.

### `mod:network_register("rpc_name", function(sender, ...))`

String-keyed RPCs (no NetworkLookup writes) — forward-compatible because peers without the mod silently drop unknown ports. No hash impact. Safe pattern for shipping new behavior cross-peer without worrying about lobby `combined_hash` desync (see `reference_vt2_lobby_combined_hash.md`).

### shared_state.lua intent (vanilla)

`scripts/network/shared_state.lua` is intended for **stateful, typed, replicated key-value tables** with per-peer scope. Spec-driven (encode/decode functions per key), supports late-join (full sync request via `rpc_shared_state_request_sync`), supports atomic multi-write transactions (`rpc_shared_state_start_atomic_set_server` / `end_atomic_set_server`). The vanilla spec at `network_state_spec.lua` carries inventory package lists, breed maps, pickup maps, mutator maps, DLC unlocks.

Mods can read SharedState via `Managers.state.network:network_state():_shared_state:get_key(...)` but writing requires going through the spec system. In practice, mods that need cross-peer state replication build their own RPC + chunking layer on top of `mod:network_send`, not SharedState.

## 6. Common pitfalls (anti-patterns that cause desync)

1. **Hooking the local class but not the husk twin.** `mod:hook("SimpleInventoryExtension", "wield", …)` only fires for the local player + local bots. Remote players' wield events go through `SimpleHuskInventoryExtension.wield` and are invisible to that hook. Burned twice in `weapon_tweaker` (v0.12.35, v0.12.37). Fix: register the same hook body on both classes, or hook a function both call (e.g. `GearUtils.spawn_inventory_unit`).

2. **Reading local mod settings on a husk-spawn path.** When the husk's `_wield_slot` fires on the local viewer's machine for a remote player, `mod:get("setting")` returns the LOCAL VIEWER's settings, not the remote owner's. For host-controlled behavior (e.g. ct boons), broadcast the resolved value from host → clients explicitly (see `reference_ct_graph_snapshot_rpc.md`). For per-player toggles, sync via VMF chunked RPC or attach the setting to the player's `PlayerSyncData` field.

3. **Re-painting unit materials post-call via `mod:hook_safe` overlay.** Empirically, `mod:hook_safe(GearUtils, "apply_material_settings", ...)` post-call writes via `Unit.set_vector3_for_materials` paint 3P reliably but silently no-op on 1P units. Use `mod:hook` (full wrapper) and mutate the global `MaterialSettingsTemplates[name]` table before delegating to vanilla, then restore. This is the cosmetics_tweaker v0.8.16+ pattern.

4. **`mod:network_send` payload > ~10 keys or any string field > ~100 chars.** Silent failure. The receiver gets nothing. No crash, no log on the receiver side. Symptom: "sync seems to do nothing on clients." Burned in ct v0.7.55-v0.7.58 (3 versions). Always log the encoded payload length before sending; chunk if > 400 chars.

5. **Mutating global lookups gated on per-user toggles at module-load.** `BuffTemplates`, `NetworkLookup.*`, `DeusPowerUpBuffTemplates`, `LEVEL_AVAILABILITY` — any insert/append that depends on a per-peer setting will diverge sequential indices across peers. Crash on `rpc_add_buff` or wrong template applied. Always pre-register unconditionally in sorted order; gate the offering pool only. (`feedback_vt2_gated_registration_diverges.md`, `feedback_vt2_dormant_buff_template_dual_register.md`)

6. **Force-loading custom-mesh paths via `Managers.package:load`.** Synchronous call appears to succeed; async engine fatal "Resource not found" if the path isn't in `scripts/network_lookup/inventory_package_list.lua`. Bypasses `pcall`. Custom meshes must piggyback vanilla paths (LA `data.mat_to_use` overlay pattern, `reference_la_custom_mesh_pattern.md`).

7. **Forgetting that `Managers.player:owner(unit)` returns nil during mission-spawn equip flow.** Use `ScriptUnit.has_extension(unit, "career_system"):career_name()` — `CareerExtension` exists on both self-owned and husk units and inits race-free. `inventory_system._career_name` is race-prone on husk init.

8. **Reading `_career_name` from `SimpleInventoryExtension` for a husk unit.** Husks have `SimpleHuskInventoryExtension._career_name` and it's set on `init` from `extension_init_data.player:career_name()` — but `player` can be nil on some bot/init paths. Prefer the `career_system` extension lookup instead.

9. **Skipping the explicit `weapon_skin_id` parameter in custom equip RPCs.** Husks don't have access to the remote owner's backend mirror. If you bypass `rpc_add_equipment`'s skin parameter (or send "n/a"), the husk's `_wield_slot` won't paint glow / load custom-mesh skin — visual diverges from owner. Always carry `NetworkLookup.weapon_skins[slot.skin or "n/a"]` on the wire when you broadcast equip events from a mod.

10. **Assuming `class()` chains.** No `__index` chain to parent. Hooks must target the runtime class, not the base. Check `Grep` for `ClassName = class(ClassName,` — if there's a derived class, hook the derived one. Known affected pairs: `PlayFabMirrorBase` → `PlayFabMirrorAdventure`/`PlayFabMirrorDedicated`, `HeroPreviewer` → `MenuWorldPreviewer`. (`feedback_vt2_class_hook_derived.md`)
