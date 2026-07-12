> [!WARNING]
> ⚠ **SUPERSEDED** — this snapshot is from 2026-05-19 (53 days old).
> Recent state may differ. Kept for historical context — verify against current
> code before acting on findings. Remove this banner manually after a refresh
> or move the doc to `_archive/audits/2026-05-19/`.
# Cosmetics Tweaker × Loremaster's Armoury — Host/Client Audit

Snapshot: v0.8.67-dev, 2026-05-19. Research-only — no code changed.

## 1. Code map

### Files

| File | Purpose |
|---|---|
| `cosmetics_tweaker/scripts/mods/cosmetics_tweaker/cosmetics_tweaker.lua` (4288 lines) | Main mod. Hooks: glow, offhand picker UI, LA peer sync RPCs (`cos_la_apply`, `cos_la_apply_req`), LA bridge driver, `_offhand_selection`, `_local_la_equips`, vanilla→LA shadow substitution on all known sync paths. |
| `cosmetics_tweaker/scripts/mods/cosmetics_tweaker/_la_bridge.lua` (1473 lines) | LA bridge module. Clones LA SKIN_LIST hat/armor variants as MIL items, registers `NetworkLookup.inventory_packages` paths for `kind="unit"` variants, builds the per-character offhand pool, owns the LA `apply_new_skin_from_texture` gate (`install_apply_gate`), provides `apply_offhand_to_unit` (paint LA textures onto a single shield unit). |
| `cosmetics_tweaker/scripts/mods/cosmetics_tweaker/cosmetics_tweaker_data.lua` | VMF widget tree (settings UI). Glow toggle + preset + advanced per-channel colors/multipliers + TPE + LA bridge enable. |
| `cosmetics_tweaker/CHANGELOG.md` | v0.8.58 → v0.8.67 chronicle of the host/client desync work: substitute hooks, cos_la_apply, server-authoritative routing. |

### Key globals in `cosmetics_tweaker.lua`

| Symbol | Line | Scope | Description |
|---|---|---|---|
| `_offhand_selection` | 1705 | module local | `[backend_id] -> { unit?, intended_unit?, la_armoury_key?, vanilla_skin?, ... }`. **Per-peer LOCAL only.** Authoritatively read in `BackendUtils.get_item_units` and `_apply_la_offhand_to_units`. |
| `_local_la_equips` | 1719 | weak-keyed (`__mode="k"`) `player_unit -> { [slot] -> la_backend_id }` | Records the LA cosmetics the local player has equipped. Used by `AttachmentUtils.hot_join_sync` to replay LA paints to joining peers. |
| `_active_customization_backend_id` | 1731 | module local | Stashed by `_setup_illusions`; falls back to it in `BackendUtils.get_item_units` and `spawn_units` when callers don't pass a backend_id (preview-cycle path). |
| `_send_la_apply` | 1712 → 3468 | forward-decl local | Host: records into `_la_equips_by_peer` and broadcasts `cos_la_apply` to "all". Client: sends `cos_la_apply_req` to "server". |
| `_la_equips_by_peer` | 3430 | module local **(host only)** | `[wearer_peer_id][slot] -> { kind, armoury_key, vanilla_key }`. Authoritative server-side record of every peer's LA equips. |
| `_la_pending_apply` | 3434 | module local | Late-spawn replay queue. `{ wearer_peer_id, slot, kind, ak, vk, expires_at }`. Drained on `mod.update`, dropped after 5 s. |
| `mod.loadout_cache` | 3087 | mod-attribute | `[career_name][slot_name] = la_backend_id`. Un-rewritten LA bid cache populated by `set_loadout_item` hook for `slot_hat`/`slot_skin`. Consulted by `find_active_clone_for_unit_path` (in `_la_bridge.lua`) BEFORE vanilla loadout — added in v0.8.66 to fix "wearer sees vanilla on themselves". |

### Key globals in `_la_bridge.lua`

| Symbol | Line | Description |
|---|---|---|
| `backend_to_armoury` / `backend_to_vanilla` / `armoury_to_backend` | 27-30 | LA-clone backend_id ↔ armoury_key ↔ vanilla key cross-maps. |
| `unit_path_to_clones` | 29 | `[vanilla_unit_path] -> [our_backend_id, ...]` |
| `la_offhand_options_by_weapon_type` | 41 | Per-weapon-type LA shield pool, merged into `_offhand_options` by `_merge_la_offhand_options` at runtime. |
| `la_kind_unit_parent_packages` | 942 | `[armoury_key] -> vanilla parent unit path` (always `wpn_empire_handgun_02_t2` for the current 20-entry set) — driver for `Unit.set_all_materials` swap in customization preview. |
| `la_kind_unit_preview_scale` | 976 | Per-variant preview-only scale multiplier (default 2.0). |
| `la_path_to_parent_package` | 984 | Reverse-built (`la_mesh_path -> parent`) for the `load_package` previewer hook. |
| `_bridge_active` | 696 | Gate flag the `apply_gate` (LA's `apply_new_skin_from_texture`) checks. When `true`, lets the call through; when `false`, blocks LA-managed armoury_keys. **Cross-cuts every peer-replay path**: every `pcall(la.apply_new_skin_from_texture, ...)` and `pcall(LA_BRIDGE.apply_offhand_to_unit, ...)` MUST bracket itself with `_bridge_active = true / false`. |
| `apply_gate` (installed by `install_apply_gate`) | 699-716 | Monkey-patches `LA.apply_new_skin_from_texture` to no-op when an LA-managed armoury_key is requested with `_bridge_active=false`. This is how the bridge prevents LA's own `mod.update` loop from re-stomping on our managed cosmetics. |

## 2. Hook inventory

Only hooks/RPCs touching LA, materials, glow, or network sync. Excludes unrelated UI/portrait hooks.

| Class / table | Method | Type | File:line | Purpose | Local-only? Networks? |
|---|---|---|---|---|---|
| `BackendInterfaceCraftingPlayfab` | `get_unlocked_weapon_skins` | `hook_safe` | `cosmetics_tweaker.lua:1040` | Marks custom + vanilla illusions unlocked in local mirror. | Local mirror only. |
| `_G.Localize` | (global fn) | `mod:hook` | `cosmetics_tweaker.lua:1070` | Returns mod loc strings for LA + custom-illusion display names. | Local only. |
| `PlayFabMirrorAdventure` | `_create_fake_inventory_items` | `hook` | `cosmetics_tweaker.lua:1133` | Adds custom items into the local mirror. | Local only. |
| `BackendInterfaceItemPlayfab` | `get_weapon_skin_from_skin_key` | `hook` | `cosmetics_tweaker.lua:1240` | Maps custom skin_key → backend_id. | Local only. |
| `HeroWindowItemCustomization` | `_enable_craft_button`, `_on_illusion_index_pressed`, `_update_state_craft_button`, `_setup_illusions`, `_state_draw_overview`, `on_exit` | `hook` / `hook_safe` | `1266, 1290, 1322, 1829, 1970, 1733` | UI surface for the offhand picker. Sets `_active_customization_backend_id`. | Local UI only. |
| `BackendInterfaceCraftingPlayfab` | `craft`, `update` | `hook` / `hook_safe` | `1336, 1393` | Modded illusion-swap recipe. | Local backend. |
| `BackendUtils` (plain table) | `get_item_units` | `hook` (table-form) | `2153` | **Substitutes `result.left_hand_unit` to the user's `_offhand_selection` mesh.** Reads `_offhand_selection[effective_backend_id]` — **LOCAL state ONLY.** Falls back to `_active_customization_backend_id`. | **LOCAL — runs on every machine when spawning their OWN units AND when spawning REMOTE husk units.** |
| `BackendUtils` | `set_loadout_item` | `hook` (table-form) | `3100` | Caches LA clone equips into `mod.loadout_cache`, scrubs cache on vanilla equips. | Local cache. |
| `items_iface` | `get_loadout`, `get_loadout_item_id`, `get_item_rarity` | `hook` | `3115, 3145, 3165` | Rewrites LA bids to vanilla for net-safety; re-injects cache on top. | Local-read, fed into outgoing sync paths. |
| `CosmeticUtils` (plain table) | `update_cosmetic_slot` | `hook` (table-form) | `3225` | **Substitutes LA `item_name` and `skin_name` → vanilla** before vanilla's `player:set_data` sync. **Also emits `cos_la_apply` for `kind="armor"` / `kind="illusion"`.** | Outbound: vanilla payload over `set_data` SyncData. Also network_send `cos_la_apply_req` to host. |
| `LoadoutUtils` (plain table) | `sync_loadout_slot` | `hook` (table-form) | `3332` | Substitutes `item.key` LA → vanilla on the `rpc_sync_loadout_slot` RPC. | Outbound RPC — substitutes only. No `cos_la_apply` emit here. |
| `PlayerUnitAttachmentExtension` | `game_object_initialized` | `hook` | `3709` | Substitutes `slot_data.item_data.name` LA→vanilla, then emits `cos_la_apply` for `kind="hat"`. | Outbound `rpc_create_attachment` (vanilla) + `cos_la_apply_req` (ours). |
| `PlayerUnitAttachmentExtension` | `spawn_resynced_loadout` | `hook` | `3746` | Same as above, mid-mission resync. | Same. |
| `AttachmentUtils` (plain table) | `hot_join_sync` | `hook` (table-form) | `3772` | Substitutes per-slot LA names → vanilla; AFTER vanilla, replays `_local_la_equips` to joining peer via `_send_la_apply`. Includes the local player's currently-wielded offhand pick. | Outbound substitute + cos_la_apply_req replay flood. |
| `GearUtils` | `apply_material_settings` | `hook` | `2497` (`_hook_apply_with_template_mutation("GearUtils", "gear")` on 2548) | **Glow override**: mutates `MaterialSettingsTemplates[name]` before vanilla reads, restores after. | **LOCAL ONLY. Reads `mod:get("glow_override_enable")` + preset + per-channel — these are LOCAL VMF settings, not networked.** |
| `_G.apply_material_settings` | (flow-callback global) | `hook` | `2550` | Same glow override on the flow path. | LOCAL. |
| `CosmeticUtils.apply_material_settings` | | `hook` | `2555` | Same glow override on hat/armor materials. | LOCAL. |
| `GearUtils` | `spawn_inventory_unit` | `hook` | `2595` | Injects custom `_cosmetics_tweaker_glow` template when mesh suffix is `_runed_01` or `_magic_01` AND override on. | LOCAL. |
| `GearUtils` | `create_equipment` | `hook` | `2722` | After spawn: `_scale_units`, `_offset_units`, `_apply_la_offhand_to_units({left_unit_3p, left_unit_1p}, has_skin, "ingame")`, `_apply_glow_override({all 4 hand units})`. | LOCAL — runs once per equip per machine. **Reads `_offhand_selection` and `mod:get("glow_*")` which are PER-MACHINE-LOCAL.** |
| `MenuWorldPreviewer` / `HeroPreviewer` | `equip_item` | `hook` | `2804, 2833` | Captures skin into `_equip_skin_by_item` so the spawn hook can resolve `has_skin`. For LA-clone items: rewrites `item_key` → `backend_id` so vanilla previewer code spawns the LA mesh. | LOCAL preview only. |
| `MenuWorldPreviewer` / `HeroPreviewer` | `_spawn_item` | `hook` (wrapper) | `2940, 2941` | After spawn: `_spawn_item_post` paints LA offhand + scale + glow on each slot's hands. | LOCAL preview. |
| `LootItemUnitPreviewer` | `load_package` | `hook` | `2978` | Short-circuits engine-resident LA mesh paths (gates `_loaded_packages[path]=true`); sync-loads the LA `kind="unit"` parent material package (`wpn_empire_handgun_02_t2`). | LOCAL. |
| `LootItemUnitPreviewer` | `spawn_units` | `hook` (NOT hook_safe — captures the returned units array) | `3033` | After spawn: paint LA offhand on `units[1]` with context `"loot_previewer"`; scale + glow on both hands. | LOCAL preview. |
| `MenuWorldPreviewer` / `HeroPreviewer` | `_spawn_item_unit` | `hook_safe` | `4174, 4175` | LA-bridge hand-off: if previewer is currently spawning a clone, call `LA_BRIDGE.queue_unit_direct`. Else: `maybe_queue_unit` by unit_name. | LOCAL preview. |
| `AttachmentUtils` (plain table) | `link` | `hook_safe` (table-form) | `4133` | LA-bridge hand-off: on every linked attachment, `maybe_queue_unit` so equipped LA clones get LA's texture pipeline. | LOCAL spawn path. |
| `World.link_unit` | (global fn) | `hook_safe` | `4145` | Same idea for hats linked via World API. | LOCAL. |
| `mod.update` | (mod tick) | direct | `3880` | Drives LA bridge init, drains `_la_pending_apply` queue (5-second TTL per entry). | LOCAL. |

### RPC inventory

| RPC name | Direction | Registered at | Receiver behavior |
|---|---|---|---|
| `cos_la_apply_req` | Clients → host (`"server"`) | `cosmetics_tweaker.lua:3647` | Host validates `armoury_key ∈ LA_BRIDGE.armoury_to_backend`, records `_la_equips_by_peer[sender_peer_id][slot] = {kind, ak, vk}`, broadcasts `cos_la_apply` to `"all"`. |
| `cos_la_apply` | Host → all (`"all"`) | `cosmetics_tweaker.lua:3675` | Receiver auth-gates `sender_peer_id == _host_peer_id()`. Resolves wearer's unit via `Managers.player:players_at_peer(wearer_peer_id)`. Calls `_apply_la_on_unit(unit, slot, kind, ak, vk)`. On failure, queues into `_la_pending_apply` (5 s TTL). |

`_apply_la_on_unit` branches on `kind`:

* `"hat"` — `attachment_ext:create_attachment(slot, cloned_IML_with_la_unit)`. Despawns the vanilla hat that PUAE substituted in, respawns LA mesh.
* `"armor"` — `pcall(la.apply_new_skin_from_texture, armoury_key, level_world, vanilla_key, owner_unit)`. **Brackets with `LA_BRIDGE._bridge_active = true/false`** — without this the apply_gate would block the call on receivers that also have cosmetics_tweaker.
* `"offhand"` — paints `equipment.left_hand_wielded_unit_3p` via `LA_BRIDGE.apply_offhand_to_unit(world, left_unit, ak, vk, "network_husk")`. Returns `false` if husk isn't currently wielding the shield → caller re-queues.
* `"illusion"` — paints both `right_hand_wielded_unit_3p` and `left_hand_wielded_unit_3p` via `la.apply_new_skin_from_texture` per unit.

## 3. Per-axis trace

### Axis 1 — "LA items selected in CT don't show up properly on the OTHER side"

This is the host/client-fidelity bug, and it currently has TWO orthogonal failure paths.

**A. The hat / armor path (slot_hat, slot_skin).** Author: user clicks the LA-clone item in the inventory grid. `BackendUtils.set_loadout_item` hook (3100) caches `[career][slot_hat]=la_bid` into `mod.loadout_cache`. `SimpleInventoryExtension.add_equipment` is called by vanilla equip code, which triggers `CosmeticUtils.update_cosmetic_slot` and `LoadoutUtils.sync_loadout_slot`. Both have substitute hooks (3225, 3332) that swap `item_name`/`item.key` LA→vanilla so the vanilla RPC carries a key every peer knows.

The CosmeticUtils hook ADDITIONALLY emits `cos_la_apply_req` to host with `kind="hat"` for slot_hat (only when `la_item_subbed`; see line 3274-3287). It uses the LOCAL helper `_send_la_apply`. For hat: PUAE.game_object_initialized hook (3709) also emits, AS DOES PUAE.spawn_resynced_loadout (3746) AND AttachmentUtils.hot_join_sync (3772). That's FOUR emit sites for the same hat equip. Host receives, broadcasts `cos_la_apply` to all. Receivers call `_apply_la_on_unit` → `attachment_ext:create_attachment`.

Host machine path: host equips LA hat → `_send_la_apply` short-circuits (line 3481) → broadcasts directly to "all" (which includes self) → receiver self-applies to its own unit.

**Divergence points:**
1. **The CosmeticUtils emit for `kind="hat"` is ABSENT.** Lines 3274-3287 only fire when `kind ∈ {"hat", "armor"}` AND `la_item_subbed`. `slot_hat` IS handled — `kind = "hat"`. So in theory hat fires. **But PUAE.game_object_initialized + spawn_resynced_loadout ALSO fire for the same slot_hat.** That means a single hat equip can emit `cos_la_apply_req` 3× (CosmeticUtils, PUAE.gameobjinit, and AttachmentUtils.hot_join_sync for any joiner). For the local equip flow, CosmeticUtils + PUAE both fire — the host overwrites `_la_equips_by_peer[wearer][slot]` and broadcasts twice. Twice-applied is mostly idempotent but the second cycle may race with the first apply (vanilla create_attachment respawns the attachment unit each time).
2. **`kind="armor"` (slot_skin) is NOT routed through PUAE because slot_skin is "cosmetic" category, not "attachment".** Only CosmeticUtils + AttachmentUtils.hot_join_sync emit for armor. The hot_join path emits via `_local_la_equips[unit][slot_skin]` which is set in CosmeticUtils.update_cosmetic_slot (3282-3284). If a player career-switches mid-session, `_local_la_equips` is keyed by `player_unit` — on career switch the unit is destroyed and respawned. The weak-keyed map drops the old unit's entry. **The new unit needs a fresh CosmeticUtils.update_cosmetic_slot call to re-record.** Vanilla DOES fire update_cosmetic_slot on career switch (via `add_equipment`), so this is likely fine — but it's worth verifying.
3. **`find_active_clone_for_unit_path` in `_la_bridge.lua:646` consults `mod.loadout_cache` first, then `items_iface:get_loadout()`.** The vanilla `get_loadout` hook (3115) rewrites LA bids to vanilla but ALSO re-injects from `loadout_cache` on top (3136-3140). When applying on the LOCAL machine (the wearer), this works. When applying on a REMOTE machine (cos_la_apply receiver), the receiver does NOT have the wearer's `loadout_cache` — it has its OWN cache for ITS OWN local player. So the lookup on remote machines goes through `items_iface:get_loadout()` which returns the remote viewer's loadout. **For a remote husk hat, this is bypassed entirely** because cos_la_apply receiver calls `_apply_la_on_unit` which constructs the IML clone from `armoury_key` directly — it does NOT consult `find_active_clone_for_unit_path`. Good. But `LA_BRIDGE.maybe_queue_unit` (which fires on `AttachmentUtils.link` hook) DOES call `find_active_clone_for_unit_path`, on EVERY linked unit on EVERY peer. On a remote husk, the link fires, `find_active_clone_for_unit_path` queries the LOCAL viewer's loadout (NOT the wearer's), so it never finds a match, returns nil, and bails. **This is correct** — remote husks shouldn't apply via the local loadout. But it's load-bearing: any change that makes `maybe_queue_unit` apply opportunistically would re-introduce "client sees their own picks on remote husks".

**B. The weapon-illusion path (LA-cloned weapon skin, equipped via `slot_skin` row-1 illusion picker).** When a clone illusion is equipped, `CosmeticUtils.update_cosmetic_slot` fires with `skin_name = la_bid` (NOT `item_name`). The hook substitutes `skin_name` → vanilla (line 3253-3265), then if `la_skin_subbed AND NOT la_item_subbed` emits `cos_la_apply` with `kind="illusion"` (line 3297-3308). Receiver paints both wielded weapon units.

**Divergence points:**
1. Hot_join replay for illusions iterates `_local_la_equips[unit][slot_name]` (line 3818-3833). The slot names recorded there for illusions are whatever the cosmetic slot is (likely the cosmetic slot identifier, e.g. `slot_melee` / `slot_ranged`). The hot_join replay routes the right kind: `kind="armor"` if `slot_skin`, `kind="illusion"` otherwise. **This assumes the slot name correctly identifies the slot. If `update_cosmetic_slot` is fired with `slot = slot_hat`, kind="hat" should be used — but the hot_join path only sets kind to "armor" or "illusion".** Lines 3820-3826 explicitly skip `slot_hat` because hats flow through AttachmentUtils. OK.
2. The illusion kind paints `wielded_unit_3p` — only the currently-wielded weapon. If the LA-illusion'd weapon is sheathed (carrying melee but ranged is wielded), the paint is skipped (line 3613 returns false → caller queues). **Re-paint should fire on every wield event, but no `Inventory:wield` hook exists.** The pending-queue (5 s TTL) catches the immediate post-equip race but not long-term sheathe/unwield cycling. A player who equips an LA illusion on melee, then carries ranged the entire mission, then wields melee 30 s later → peers see vanilla.

### Axis 2 — "Custom-mesh LA items sometimes crash"

This is the `kind="unit"` path. LA's `SKIN_LIST` distinguishes `kind="texture"` (paint onto a vanilla mesh) from `kind="unit"` (custom LA mesh).

Crash paths historically encountered (per CHANGELOG):

* **NetworkLookup.inventory_packages key miss** (v0.8.66). Two peers had different `idx = #ip + 1` assignments because `_la_bridge.build_offhand_options` filtered via `_is_supported_variant` (which calls `Application.can_get("unit", path)`, timing-dependent). Fixed by `pre_register_la_inventory_packages` which iterates SKIN_LIST in sorted order and registers every kind="unit" variant unconditionally. **Status: probably fixed if both peers are on v0.8.66+. Verify by checking both peers run the same LA + CT version.**
* **`Unit.set_texture_for_materials` AV at address 0x8** (v0.8.34, v0.8.43-44). LA's compiled `.unit` references `wpn_empire_handgun_02_t2` material; the customization preview's render world doesn't scope it. Fix: `Unit.set_all_materials(unit, parent_path)` in `loot_previewer` context only, BEFORE the texture paint. This swap only runs in `context == "loot_previewer"` (line 1176) — for in-game and inventory mannequin, the kind="unit" path early-returns. LA's own hook handles those.

**Current state:** No active crash on `kind="unit"` for HOSTED clients per CHANGELOG up to v0.8.67. But the audit surfaces several risks:

1. **`_register_la_path_in_network_lookup` mutates `NetworkLookup.inventory_packages` via `rawset` at boot.** If LA's load order isn't deterministic relative to CT, or if the SKIN_LIST changes between sessions (LA version mismatch between peers), `pre_register_la_inventory_packages` still appends in sorted order but two peers running DIFFERENT LA versions get different sorted-key sets → different indices → ProfileSynchronizer crash on the receiver.
2. **`_apply_la_on_unit kind="armor"` and `kind="illusion"`** unconditionally call `pcall(la.apply_new_skin_from_texture, ...)` even on receivers where the LA `SKIN_LIST` doesn't have that armoury_key (different LA version). `_resolve_la_variant` (line 3507) returns nil and `_apply_la_on_unit` bails with a log line — no crash, but the cosmetic silently doesn't appear. The CHANGELOG documents this as "armoury_key sidesteps la_backend_id lookup miss". But there is no telemetry surfacing version mismatch to the user.
3. **`apply_offhand_to_unit` with `context="network_husk"` for `kind="unit"` variants is explicitly deferred** (line 1176-1182): "kind=unit husk variants are deferred (vanilla mesh stays)". So a player who picks a kind="unit" LA shield → remote viewers see a VANILLA-mesh-with-no-LA-paint shield. This is documented as a known limitation, NOT a crash, but it IS a host/client visual divergence by design.

### Axis 3 — "Custom-colored LA hats don't show for all players"

This is the slot_hat path. The substitution stack (CosmeticUtils + LoadoutUtils + PUAE.gameobjinit + PUAE.spawn_resynced_loadout + AttachmentUtils.hot_join_sync) is described in axis 1.

**Trace on the wearer's machine:**
1. Click hat in inventory grid → vanilla equips, fires CosmeticUtils.update_cosmetic_slot.
2. Our hook substitutes item_name LA→vanilla, calls vanilla, then emits `cos_la_apply_req` to host with `kind="hat"`.
3. PUAE.game_object_initialized fires next, substitutes `slot_data.item_data.name` LA→vanilla, calls vanilla (which sends `rpc_create_attachment` for vanilla), restores `.name`, then emits `cos_la_apply_req` AGAIN.
4. Host receives both → broadcasts cos_la_apply twice → receivers apply twice. Twice-applied = idempotent in the create_attachment path (the second call replaces the first attachment unit).
5. Wearer's own receiver: `_apply_la_on_unit kind="hat"` calls `ext:create_attachment(slot, item_data_with_la_unit)`. This replaces the vanilla hat unit with the LA mesh on the wearer's body.

**Failure points:**
1. **The wearer sees their own hat as vanilla until cos_la_apply returns from the host.** This is the documented v0.8.67 tradeoff. Host latency = visible flicker.
2. **If the host doesn't have cosmetics_tweaker, the request is silently dropped at the host's VMF dispatcher.** Documented as known limitation (v0.8.67 entry). NO peer ever sees LA — they all see vanilla.
3. **`_apply_la_on_unit kind="hat"` validates `armoury_key ∈ LA_BRIDGE.armoury_to_backend`** (line 3655, in `cos_la_apply_req` receiver). If a host has CT but no LA, `armoury_to_backend` is empty → host rejects the request. Receivers without LA bail at `_resolve_la_variant`.
4. **The hat path also writes via `ext:create_attachment` directly using a clone of `ItemMasterList[armoury_key]` or `ItemMasterList[vanilla_key]`** (line 3553-3563). On receivers that have CT but NOT LA, `ItemMasterList[armoury_key]` may not exist — only ItemMasterList[vanilla_key] does. Code uses an `or` cascade so falls back to vanilla_key. Cloning IML[vanilla_key] then setting `item_data.unit = la_unit_path` — but `la_unit_path` is `variant.new_units[1]`, and `variant` came from `_resolve_la_variant` which already bailed if LA isn't loaded. So this branch is unreachable without LA — good.
5. **Receivers without `Application.can_get("unit", la_unit_path)` returning true for either 1P or 3P bail with `mod:info` — no crash, no visual.** "LA hats invisible on peers" was the exact symptom v0.8.62-v0.8.64 fixed. **If a peer has a STALE LA version where the hat's mesh path was renamed or removed, the bail still fires.** This is silent (only `mod:info` log) — no chat warning to the user.

### Axis 4 — "Glow settings should be per-peer"

This is the BIGGEST GAP in the codebase.

`_glow_override_enable`, `glow_override_preset`, `glow_color_*`, `glow_mult_*` — all read via `mod:get(...)` (lines 2393-2445). `mod:get` returns the LOCAL machine's VMF setting.

The glow override is applied via three independent hooks (lines 2497-2557), all calling `_hook_apply_with_template_mutation`. The mutation reads `_glow_main_rgb()` → `mod:get("glow_override_enable")` and `mod:get("glow_override_preset")` — STRICTLY LOCAL READS.

`GearUtils.apply_material_settings`, `_G.apply_material_settings`, and `CosmeticUtils.apply_material_settings` all fire when a weapon is equipped — INCLUDING when a REMOTE husk's weapon is equipped on the local machine (the host or other clients see the husk equip via vanilla sync, which spawns a unit and applies its material). The hook MUTATES the SHARED MaterialSettingsTemplates global, calls vanilla apply, then restores. **During the apply window, the wearer's glow color is the LOCAL VIEWER's glow color** (because mutation reads viewer's settings) — NOT the wearer's choice. The user's complaint is exactly this: "host should see the client's chosen glow on the client's weapon".

There is NO `cos_la_apply` analogue for glow. There is NO per-peer glow state. There is NO RPC carrying the wearer's glow choice. **This is unimplemented.**

Additionally, `GearUtils.create_equipment` (2722) calls `_apply_glow_override({all 4 hand units})` after vanilla equip. This runs on EVERY machine that spawns the unit, INCLUDING remote husk spawns. Reads `mod:get(...)` — LOCAL. Same defect.

The glow template mutation has a SHARED-RESOURCE side effect: `MaterialSettingsTemplates[name]` is the engine-global template table. The mutation saves the original values, applies the user's RGB, calls vanilla, restores. **If two consecutive vanilla apply_material_settings calls run inside the same frame (e.g. weapon switch + remote husk spawn) the second call's "save" might capture mutated values if restore hasn't run yet.** The code is synchronous within a single Lua-thread, so this is unlikely, but worth noting.

## 4. Hot suspects (ranked)

### Suspect 1. Glow is a pure-local-read system. **All four "glow per-peer" complaints are real and unaddressed.**
`cosmetics_tweaker.lua:2393-2445` reads `mod:get("glow_*")` directly. `_hook_apply_with_template_mutation` (2497) fires for every machine's apply, every unit, every hand, including remote husks. **There is no RPC for glow; there is no per-peer glow state.** The user explicitly asked for "host should see the client's chosen glow on the client's weapon" — that requires:
* Wearer broadcasts a "my glow settings" RPC on settings-change OR on every equip.
* Receivers store `[wearer_peer_id] -> {enable, preset, per_channel_*, mults}`.
* `_hook_apply_with_template_mutation` looks up the wearer from the unit, reads the wearer's settings, mutates.

The single existing analogue is the `cos_la_apply` system, but it covers LA hats/armor/illusion/offhand only. Glow has no equivalent.

### Suspect 2. `_offhand_selection` is per-machine-local for VANILLA-mesh shields. LA-mesh shield selections are synced via `cos_la_apply kind="offhand"`, but VANILLA-mesh shield picks (e.g. "GK Shield Blue" on Bret longsword) are not.
`cosmetics_tweaker.lua:2032-2044` only sends `cos_la_apply` when `opt.la_armoury_key` is set. Vanilla mesh picks (the original row-2 picker) have `opt.unit` set instead. So if a client picks "GK Shield Blue" on their Bret weapon → host sees the original Bret heater shield. The host's `BackendUtils.get_item_units` hook reads ITS OWN `_offhand_selection`, which is empty for the client's backend_id. **The existing system silently DOES NOT cover vanilla-mesh offhand picks across peers.** Documented as a comment ("vanilla-mesh offhands ... still go unsynced") in line 2027-2031 but not in CHANGELOG as a known limitation.

### Suspect 3. Quadruple-emit of `cos_la_apply_req` per single hat equip can cause apply-race / visible flicker.
`CosmeticUtils.update_cosmetic_slot` (3287), `PUAE.game_object_initialized` (3740), `PUAE.spawn_resynced_loadout` (3759), and `AttachmentUtils.hot_join_sync` (3809) all emit for slot_hat. For a single local hat equip, the first three fire in rapid succession. Host receives three requests, broadcasts three cos_la_apply, each one re-runs `_apply_la_on_unit kind="hat"` which calls `ext:create_attachment` which DESTROYS the prior attachment and respawns. Three re-spawns of the hat in <1 frame may be visible as a flicker or cause an unstable end state if `create_attachment` is asynchronous.

### Suspect 4. `_apply_la_on_unit` kind="armor" calls `la.apply_new_skin_from_texture` which **mutates `WeaponSkins.skins[skin].inventory_icon` and `ItemMasterList[skin].inventory_icon` globally** (per the comment at `_la_bridge.lua:766-772`).
LA's apply has documented side effects on global icon tables. The bridge's local apply path goes through `Unit.set_texture_for_materials` instead, specifically to avoid these mutations. **But the cos_la_apply receiver `kind="armor"` (3577) calls LA's vanilla function directly** because the goal is to paint the player_unit body texture, not a weapon. **This will leak LA icons into vanilla inventory UI on receivers** every time a remote armor equip arrives. Same applies to `kind="illusion"` (3624).

### Suspect 5. `hook_safe` vs `hook` consistency: the doctrine memo flagged `LootItemUnitPreviewer.spawn_units` (which IS using `mod:hook`, correctly).
But other previewer hooks (`_spawn_item_unit`) use `hook_safe`. If a future caller depended on knowing the units that were spawned, the hook_safe wouldn't see them. **AttachmentUtils.link is `hook_safe`** (line 4133) — fine for the bridge hand-off but means we cannot block vanilla link behaviour. The CHANGELOG also notes "After host-migration kick, `[LA fix kind=unit] set_all_materials` step stops firing" as a v0.8.66 known-issue tracked for v0.8.67. Open in the current dev cut.

### Other observations worth flagging
* `_la_equips_by_peer` is host-only state. **It has no cleanup on peer disconnect.** Stale entries persist for the lifetime of the host session. Eventually accumulates entries from every player who has ever joined.
* `_local_la_equips` (weak-keyed by player_unit) is per-peer-local. **It is not cleared on slot_skin un-equip** — when the player swaps from an LA armor to a vanilla armor, the LA bid stays in the map. The next `CosmeticUtils.update_cosmetic_slot` hook (vanilla equip) will overwrite the LA bid via line 3284 because `equips[slot] = item_name` and `item_name` is now vanilla. Wait — actually `equips[slot] = item_name` is only inside the `la_item_subbed` branch (line 3284 is inside `if la_item_subbed and item_name ...`). So vanilla equips do NOT update the table. **A subsequent hot_join_sync (3818-3833) will replay the STALE LA bid, telling joiners to apply an LA armor the player no longer wears.**

## 5. Open questions

1. **Does `_send_la_apply`'s emit fire when host loops back its own broadcast?** The code short-circuits on host (line 3481) and broadcasts to "all" which includes self. But VMF's `mod:network_send("cos_la_apply", "all", payload)` — does the sender's own `mod:network_register` handler receive the broadcast, or only remote peers? If sender-excluded, the host never applies its own LA cosmetics on its own machine. (Code path looks like it relies on this happening; if it doesn't, the host shows vanilla on itself.)
2. **Does `Managers.player:players_at_peer(wearer_peer_id)` return the player object even if the wearer is on a loading screen?** If not, the pending-queue is the safety net. But 5 s TTL is tight for a slow loading screen.
3. **`create_attachment(slot, item_data)` — is this synchronous in respect to mesh-spawn?** If not, the four-fire flicker (suspect 3) is real. Worth probing in-game.
4. **`apply_new_skin_from_texture` on a remote husk (`kind="armor"` receiver, line 3577) — does LA expect this to fire on a non-local-player unit?** LA was authored against the local player only; applying to a husk may have unintended side effects (LA's own update loop might re-process the husk on subsequent ticks). The `_bridge_active=true` window prevents the apply_gate from blocking, but doesn't prevent LA's update loop from later seeing the husk in `level_queue` and stomping on it. The bridge `suppress_la_queue(unit)` clears that for our managed flow but the receiver path doesn't do this.
5. **Mesh-versioning across peers.** When peer A has LA v3.2 and peer B has LA v3.1, `SKIN_LIST` keys may differ. The substitute hooks keep peer B from crashing, but `cos_la_apply` armoury_keys may not resolve on peer B's `SKIN_LIST` — receiver bails. No telemetry/version handshake exists.
6. **Why does v0.8.66's "Patch 2" need `loadout_cache` consulted BEFORE vanilla loadout in `find_active_clone_for_unit_path`?** The comment says "the lookup missed, apply_direct never fired, the apply_gate stayed closed, LA's own update loop was blocked → local player saw vanilla on themselves." This works for steady-state but: is there ANY frame between `set_loadout_item` writing to `loadout_cache` and the next `find_active_clone_for_unit_path` call where the cache is correct but vanilla loadout isn't? If `find_active_clone_for_unit_path` is called from `AttachmentUtils.link` (which fires post-spawn), and `set_loadout_item` is called pre-spawn from the inventory equip code, then by the time link fires, the cache IS populated. So why was this broken pre-v0.8.66? Possibly the cache was being SCRUBBED somewhere mid-equip. Worth checking the `BackendUtils.set_loadout_item` hook (3100) — note line 3108-3111 explicitly clears the cache when a non-LA equip comes in, AND the hook returns without calling vanilla in the LA branch. Could an intermediate vanilla-equip call land between two LA equips and scrub?
7. **Does the `_offhand_selection` table get pre-seeded from the wearer's RPC on the receiver side for `kind="offhand"`?** Receiver of cos_la_apply kind="offhand" calls `LA_BRIDGE.apply_offhand_to_unit` directly with the wearer's `armoury_key` and `vanilla_skin` — it does NOT update `_offhand_selection`. So if the receiver re-spawns the husk (career switch on the husk side, late-loaded mesh), the spawn-path hooks won't know to re-apply because `_offhand_selection` on the receiver is empty. The next cos_la_apply broadcast would re-cover it, but if the wearer doesn't re-equip, there's no broadcast. **The pending-queue is the only thing keeping this from being a permanent desync after a husk respawn.** And the queue has a 5 s TTL.
