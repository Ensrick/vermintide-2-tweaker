local function install(mod, ctx)
	local _om = assert(ctx.om, "cwv identity transport owner requires om")
	local _find_def = assert(ctx.find_def,
		"cwv identity transport owner requires find_def")
	local _custom_skin_keys = assert(ctx.custom_skin_keys,
		"cwv identity transport owner requires custom_skin_keys")

	-- ============================================================
	-- issue 278: net-safe loadout sync for cwv variant keys
	-- ============================================================
	-- `SimpleInventoryExtension.add_equipment` (simple_inventory_extension.lua:885)
	-- and `LoadoutUtils.hot_join_sync` (loadout_utils.lua:62) broadcast
	-- `rpc_sync_loadout_slot` with `item_id = NetworkLookup.item_names[item.key]`
	-- (loadout_utils.lua:25). For a cwv_* key that numeric id is a LOCAL
	-- index-append (`#tbl + 1` in `_auto_register_all`), so its value depends on
	-- every other mod that appended to item_names on THIS peer before us —
	-- e.g. Loremaster's Armoury clone entries (appended by cosmetics_tweaker's
	-- `_la_bridge.register_all` only on peers where LA is enabled). Host with LA
	-- + client without LA = the host's cwv id (3243 in the issue-278 crash log)
	-- doesn't exist on the client, and the receiving peer's decode
	-- (`NetworkLookup.item_names[item_id]`, loadout_utils.lua:72) hits the strict
	-- __index error metamethod (network_lookup.lua:2521) -> client CTD.
	--
	-- Fix (same shape as cosmetics_tweaker's LA net-safe substitution,
	-- cosmetics_tweaker.lua v0.8.60-dev): substitute a SHADOW item whose `.key`
	-- is the variant's `base_weapon` (a vanilla ItemMasterList key with an
	-- identical, boot-time-stable item_names index on every peer) before the RPC
	-- encodes. Local state is untouched (the shadow lives only for this call);
	-- remote peers' `PlayerManager._player_loadouts` (inspect/Tab UI) show the
	-- base weapon — consistent with what the husk already renders for cwv items
	-- (husk equipment syncs by the inherited base `.name`, see issue 280 notes).
	--
	-- LoadoutUtils is a PLAIN TABLE (`LoadoutUtils = LoadoutUtils or {}`), so
	-- table-form hook with a nil guard (same BackendUtils pitfall, CLAUDE.md
	-- "Hooking"). Sole CWV hook on (LoadoutUtils, sync_loadout_slot) — verified
	-- by pre-flight grep; cosmetics_tweaker/cim hook the same function from THEIR
	-- mod registrations, which VMF chains fine across mods.
	if rawget(_G, "LoadoutUtils") and LoadoutUtils.sync_loadout_slot then
		mod:hook(LoadoutUtils, "sync_loadout_slot", function(func, player, slot_name, item, sync_to_specific_peer_id)
			local key = item and item.key
			if type(key) == "string" and key:sub(1, 4) == "cwv_" then
				local def = _find_def(key)
				local base_key = def and def.base_weapon
				if base_key and rawget(ItemMasterList, base_key)
						and NetworkLookup and NetworkLookup.item_names
						and rawget(NetworkLookup.item_names, base_key) then
					local shadow = {}
					for k, v in pairs(item) do shadow[k] = v end
					shadow.key = base_key
					shadow.ItemId = base_key
					printf("[cwv:278] sync_loadout_slot net-safe: %s -> %s (slot=%s)",
						key, base_key, tostring(slot_name))
					return func(player, slot_name, shadow, sync_to_specific_peer_id)
				end
				-- No safe fallback key: better to skip the sync (remote loadout
				-- panel shows the previous item) than to CTD every peer whose
				-- item_names table diverges from ours.
				printf("[cwv:278] ALERT sync_loadout_slot SKIPPED for %s (no vanilla base_weapon fallback resolvable)",
					tostring(key))
				return
			end
			return func(player, slot_name, item, sync_to_specific_peer_id)
		end)
		_cwv_net_safe_loadout_hook_installed = true
	end

	-- WIRE-SAFETY: weapon_skin_id axis of issue 278 / issue 371; issue 741 retires
	-- the issue-495 parity exception. A cwv-registered NetworkLookup.weapon_skins
	-- key is undefined on a peer without cwv: any sender that encodes
	-- weapon_skin_id = NetworkLookup.weapon_skins[<live slot skin>] onto
	-- rpc_add_equipment fatals that peer on decode (inventory_system.lua:300 -> strict
	-- __index, network_lookup.lua:2362). THREE vanilla senders read live slot data
	-- (the same set cosmetics covers for issue 421):
	--   * SimpleInventoryExtension.game_object_initialized (initial spawn,
	--     simple_inventory_extension.lua:258-264)
	--   * SimpleInventoryExtension._spawn_resynced_loadout (every mid-session
	--     (re)equip, :1443-1457, encode :1451)
	--   * GearUtils.hot_join_sync (host replays worn slots to each joining peer,
	--     gear_utils.lua:462-488, encode :484)
	-- UNCONDITIONAL FALLBACK (issue 741 / BUG_CLASSES 31, 64): same-mod presence and
	-- schema agreement do not prove numeric NetworkLookup parity. Another
	-- skin-appending mod can shift weapon_skins indexes between two CWV peers. Every
	-- CWV skin is therefore nulled to vanilla "n/a" for all three vanilla senders,
	-- without consulting the roster. The real skin travels as a stable string key on
	-- cwv_item_identity and remote husks consume that reconstructed descriptor.
	-- Key set: _om._skin_keys (base variant skins) + _custom_skin_keys
	-- (pairing/illusion registrations) + the cwv_ name prefix as belt-and-suspenders
	-- (every cwv-injected weapon_skins key is cwv_-prefixed; no vanilla key is).
	-- Sole cwv hooks on all three methods (grep-verified 2026-07-12). No item_id
	-- concern: cwv keeps item_data.name = base_weapon, a universal vanilla index.
	-- do-block: cwv's main chunk sits at the Lua 5.1 200-local ceiling -- these
	-- helpers must not cost enduring top-level slots.
	do
		-- Single source of truth for the cwv-skin predicate: the same pure module
		-- that drives the update_cosmetic_slot sender null (below). Behavior is
		-- identical to the pre-v0.1.447 inline form (base key set / custom key set /
		-- cwv_ prefix) -- see _cwv_cosmetic_skin_wire.is_cwv_skin.
		local function _wire_skin(skin)
			return _om.cosmetic_skin_wire.is_cwv_skin(skin, _om._skin_keys, _custom_skin_keys)
		end
		_om._wire_skin_predicate = _wire_skin   -- exported for /cwv_regression_test

		-- The presence-only `_wire_parity_live` predicate that used to live here was
		-- removed with the #423 exact-catalog conversion: its one consumer (the
		-- damage-profile send gate) now reads mod._cwv_damage_wire_safe, which
		-- requires the exact catalog on top of the same committed applied_state.
		-- Appearance never needed it -- #741 forbids numeric CWV skin ids on the
		-- vanilla wire in every lobby shape.

		-- #396 positive owner identity. Vanilla equipment RPCs deliberately encode a
		-- CWV clone as its stable base item name, so the receiver cannot distinguish
		-- an Imperial Longsword from a native Bretonnian Longsword when the selected
		-- skin is nil/vanilla-looking. Carry only the missing item-key axis over VMF's
		-- same-mod channel; the ordinary vanilla RPC remains authoritative for slot and
		-- wield timing, while this descriptor is authoritative for CWV skin/units. The
		-- side channel is absence-safe for non-CWV
		-- peers and bounded to equip/resync/parity edges (never per-frame).
		local _IDENTITY_SCHEMA = _om.appearance_lifecycle_policy.SCHEMA
		mod._cwv_identity_surfaces = {
			network = true,
			owner_spawn = true,
			bot_spawn = true,
			remote_husk = true,
			husk_wield = true,
		}

		local lifecycle = _om.appearance_lifecycle_policy.new({
			resolve_local = function(slot_data, slot_name)
				local item_data = slot_data and slot_data.item_data
				local base_name = item_data and item_data.name
				if not item_data then return nil, base_name end
				local backend_id = item_data.backend_id
					or (item_data.mod_data and item_data.mod_data.backend_id)
				local key = _om._cwv_key_for_item(backend_id, item_data)
				if not key then return nil, base_name end
				local skin = slot_data.skin
				local offhand_skin
				local cosmetics = get_mod and get_mod("cosmetics_tweaker")
				local provider = cosmetics and cosmetics._cos
					and cosmetics._cos.cwv_offhand_identity
				if type(provider) == "function" and backend_id then
					local ok, value = pcall(provider, backend_id, key,
						"left_hand_unit")
					if ok and type(value) == "string" and value ~= "" then
						offhand_skin = value
					end
				end
				local descriptor = _om._cwv_resolve_world_descriptor(item_data, skin,
					nil, key, backend_id, offhand_skin)
				return descriptor, base_name
			end,
			resolve_remote = function(payload, sender_peer_id)
				local def = type(payload.item_key) == "string" and _find_def(payload.item_key)
				if not def or def.skin_only or def.base_weapon ~= payload.base_item_key then
					return nil, "item_or_base"
				end
				local skin = payload.skin_key ~= "" and payload.skin_key or nil
				local offhand_skin = payload.offhand_skin_key ~= ""
					and payload.offhand_skin_key or nil
				local descriptor, _, reason = _om._cwv_resolve_world_descriptor(
					{ name = def.base_weapon }, skin, nil, def.item_key,
					tostring(sender_peer_id) .. ":" .. tostring(payload.slot),
					offhand_skin)
				return descriptor, reason
			end,
			send = function(recipient, schema, payload, edge)
				-- #474: stance rides the delivering channel. Stamped only on Old
				-- Musket payloads so every other item's wire shape is unchanged;
				-- receivers without this build ignore the extra field.
				if payload and payload.item_key == "cwv_es_musket_old"
						and _om._old_musket_mode_for_local_slot then
					local ok_mode, mode = pcall(_om._old_musket_mode_for_local_slot, payload.slot)
					if ok_mode and (mode == "melee" or mode == "ranged") then
						payload.musket_mode = mode
					end
				end
				-- #786 B1: the Combat Style axis rides the SAME delivering channel,
				-- generalized from the #474 stance rider. Stamped only when the live
				-- local slot is this payload's exact item, so a NATIVE style member
				-- (most of them are) publishes its style though item_key is "".
				if payload and _om.combat_styles then
					local ok_style, rider = pcall(_om.combat_styles.local_style_rider,
						_om.combat_styles, payload.slot,
						payload.item_key ~= "" and payload.item_key or payload.base_item_key)
					if ok_style and rider then payload.style = rider end
				end
				local ok = pcall(mod.network_send, mod, "cwv_item_identity",
					recipient, schema, payload)
				if ok then
					pcall(printf,
						"[cwv:660] lifecycle=%s adapter=identity_send recipient=%s slot=%s descriptor=%s",
						tostring(edge), tostring(recipient), tostring(payload.slot),
						tostring(payload.fingerprint ~= "" and payload.fingerprint or "native"))
				end
				return ok
			end,
		})
		_om._appearance_lifecycle = lifecycle

		_om._cwv_identity_payloads = function(slots)
			local payloads = {}
			for _, slot_name in ipairs({ "slot_melee", "slot_ranged" }) do
				local payload = lifecycle:payload_for(slot_name,
					type(slots) == "table" and slots[slot_name] or nil)
				if payload then payloads[#payloads + 1] = payload end
			end
			return payloads
		end

		_om._cwv_accept_identity = function(sender_peer_id, schema, payload)
			return lifecycle:accept(sender_peer_id, schema, payload)
		end

		_om._cwv_identity_descriptor_for_peer = function(peer_id, slot_name, base_name)
			return lifecycle:descriptor(peer_id, slot_name, base_name)
		end

		mod._cwv_peer_appearance = { schema = 1, resolve_peer = _om._cwv_identity_descriptor_for_peer }

		_om._cwv_identity_def_for_peer = function(peer_id, slot_name, base_name)
			local descriptor, state = lifecycle:descriptor(peer_id, slot_name, base_name)
			local def = descriptor and _find_def(descriptor.variant_key)
			return def, state
		end

		local _identity_peer_log_once = {}
		_om._husk_identity_descriptor = function(owner_unit_3p, slot_name, base_name,
				hinted_player)
			if not owner_unit_3p then return nil, "none" end
			local wield_ctx = _om._appearance_husk_wield_context
			if not hinted_player and wield_ctx
					and wield_ctx.owner_unit_3p == owner_unit_3p then
				hinted_player = wield_ctx.player
			end
			local player, source = _om.peer_resolver.husk_owner(
				Managers and Managers.player, owner_unit_3p, hinted_player)
			local peer_id = _om.peer_resolver.player_peer_id(player)
			if not peer_id then
				local log_key = tostring(owner_unit_3p) .. "|" .. tostring(slot_name)
				if not _identity_peer_log_once[log_key] then
					_identity_peer_log_once[log_key] = true
					pcall(printf,
						"[cwv:914] lifecycle=husk_wield adapter=peer_resolution slot=%s source=%s peer=none",
						tostring(slot_name), tostring(source))
				end
			end
			return lifecycle:descriptor(peer_id, slot_name, base_name)
		end

		_om._husk_identity_def = function(owner_unit_3p, slot_name, base_name)
			local descriptor, state = _om._husk_identity_descriptor(owner_unit_3p, slot_name, base_name)
			return descriptor and _find_def(descriptor.variant_key) or nil, state
		end

		local function _send_identity_slots(slots, context, force, recipient, partial)
			local sent = lifecycle:publish(slots, context, recipient or "others", force, partial)
			if sent > 0 then
				pcall(printf, "[cwv:396/660] exact identity replay: context=%s recipient=%s slots=%d",
					tostring(context), tostring(recipient or "others"), sent)
			end
			return sent
		end
		_om._cwv_send_identity_slots = _send_identity_slots

		local peer_pull = _om.identity_peer_pull.bind(lifecycle, _send_identity_slots, _om.appearance_lifecycle_policy, printf)
		_om._cwv_request_peer_identities = peer_pull.request
		_om.identity_peer_cleanup.install(mod, lifecycle,
			rawget(_G, "PlayerManager"), _om.peer_resolver, printf, function()
				return Network and Network.peer_id and Network.peer_id()
			end)

		-- Named live receiver boundary (#579).  The VMF registration and the
		-- executable regression call this exact function, so a future refactor
		-- cannot leave the network channel registered to stale/partial logic while
		-- helper-only tests continue to pass.
		_om._cwv_receive_identity = function(sender_peer_id, schema, payload)
			-- #474: the Old Musket shot report rides this channel (the dedicated
			-- mode channel never delivered in the 2026-07-18 paired logs). The
			-- sentinel slot fails valid_slot() in accept() on builds without this
			-- code, so mixed-version lobbies drop it safely.
			if type(payload) == "table" and payload.slot == "cwv_musket_fire" then
				if schema == _IDENTITY_SCHEMA and _om._old_musket_play_remote_fire then
					_om._old_musket_play_remote_fire(sender_peer_id, payload.fire_event,
						"identity_channel")
				end
				return
			end
			if type(payload) == "table"
					and payload.slot == _om.appearance_lifecycle_policy.REQUEST_SLOT then
				peer_pull.accept(sender_peer_id, schema, payload)
				return
			end
			-- #660 cold-join delivery acknowledgement. A targeted send from inside
			-- GearUtils.hot_join_sync can be accepted by the sender before the joining
			-- peer's VMF handler is ready. The sender retries only the two semantic
			-- identity slots on a bounded cadence until this ACK proves receipt.
			if type(payload) == "table"
					and payload.slot == _om.appearance_lifecycle_policy.ACK_SLOT then
				local accepted = lifecycle:accept_ack(sender_peer_id, schema, payload)
				if accepted then
					pcall(printf,
						"[cwv:660] lifecycle=hot_join_retry adapter=identity_ack peer=%s slot=%s descriptor=%s pending=%d",
						tostring(sender_peer_id), tostring(payload.ack_slot),
						tostring(payload.fingerprint), lifecycle:pending_delivery_count())
				end
				return
			end
			local changed, descriptor, reason = _om._cwv_accept_identity(sender_peer_id, schema, payload)
			-- #474: apply stance BEFORE the changed-gate. A stance toggle changes
			-- musket_mode while the identity signature stays identical, so the
			-- accept() dedupe must not swallow it.
			if type(payload) == "table" and payload.item_key == "cwv_es_musket_old"
					and (payload.musket_mode == "melee" or payload.musket_mode == "ranged")
					and _om._old_musket_accept_mode then
				_om._old_musket_accept_mode(sender_peer_id, payload.slot,
					payload.musket_mode, nil, "identity_channel")
			end
			-- #786 B3: apply the style axis BEFORE the changed-gate, for the same
			-- reason as the stance rider above -- a style switch leaves the identity
			-- signature byte-identical, so accept()'s dedupe would swallow it. Both
			-- channels converge on ONE state; this path owns the guarded re-wield.
			local style_owned = false
			if type(payload) == "table" and _om.combat_styles then
				local fam, sid = _om.combat_style_policy.decode_style_rider(payload.style)
				if fam then style_owned = _om.combat_styles:accept_style_edge(
					sender_peer_id, payload.slot, fam, sid, "identity") == true end
			end
			-- ACK both a first delivery and a duplicate retry. `descriptor` is non-nil
			-- only after this peer reconstructed the exact local resources, so the ACK
			-- never falsely confirms an unavailable/fingerprint-mismatched appearance.
			if descriptor then
				local ack = lifecycle:ack_payload(payload)
				if ack then
					pcall(mod.network_send, mod, "cwv_item_identity",
						sender_peer_id, _IDENTITY_SCHEMA, ack)
				end
			end
			if not changed then return end
			pcall(printf, "[cwv:396/660] exact identity received: peer=%s slot=%s key=%s descriptor=%s state=%s",
				tostring(sender_peer_id), tostring(payload and payload.slot),
				tostring(payload and payload.item_key),
				tostring(descriptor and descriptor.fingerprint or "vanilla"), tostring(reason))
			-- Rebuild the currently wielded husk once, DEFERRED through the per-wearer
			-- coalescer (#1145: one re-wield per wearer per frame, husk game object
			-- re-checked at drain). Arrival ordering converges without polling; the
			-- resolution and both gates live in the coalescer module.
			-- #786: skip when the style ledger already queued THIS (peer, slot) --
			-- the coalescer keeps newest-wins, so an unverified duplicate would
			-- replace the ledger's verifying executor and strand its verdict.
			if not style_owned then
				mod._cwv_rewield.request_peer_rewield(sender_peer_id, payload and payload.slot)
			end
		end
		mod:network_register("cwv_item_identity", _om._cwv_receive_identity)

		-- Issues #476/#741 diagnostic. The vanilla decision is now invariant: NULL.
		-- Exact remote appearance is independently observable on the semantic
		-- cwv_item_identity lifecycle logs, so a failed illusion can be assigned to the
		-- descriptor/husk consumer without ever re-enabling an unsafe numeric replay.
		_om._probe_476_logged = {}
		_om._probe_476 = function(context, skin)
			local key = tostring(context) .. "|" .. tostring(skin)
			if _om._probe_476_logged[key] then return end
			_om._probe_476_logged[key] = true
			pcall(printf,
				"[cwv:476/741] husk illusion transport (%s): skin=%s vanilla_wire=NULL identity_channel=cwv_item_identity",
				tostring(context), tostring(skin))
		end

		local _null_logged = {}
		local function _wire_null_skins(slots, send_fn, context)
			return _om.cosmetic_skin_wire.with_safe_slots(
				slots, _om._skin_keys, _custom_skin_keys, send_fn,
				function(_, skin)
					_om._probe_476(context, skin)
					local lk = tostring(context) .. "|" .. tostring(skin)
					if not _null_logged[lk] then
						_null_logged[lk] = true
						pcall(printf,
							"[cwv:741] wire skin null (%s): %s -> n/a (exact identity via cwv_item_identity)",
							tostring(context), tostring(skin))
					end
				end)
		end
		_om._wire_null_skins = _wire_null_skins   -- exported for /cwv_regression_test

		mod._cwv_skin_wire_surfaces = {}

		mod:hook("SimpleInventoryExtension", "game_object_initialized", function(func, self, unit, unit_go_id)
			local slots = self and self._equipment and self._equipment.slots
			if not slots then
				return func(self, unit, unit_go_id)
			end
			_send_identity_slots(slots, "game_object_initialized", true)
			local r1, r2, r3, r4 = _wire_null_skins(slots, function()
				return func(self, unit, unit_go_id)
			end, "game_object_initialized")
			if _om._exact_pair_publish_inventory then
				_om._exact_pair_publish_inventory(self, "game_object_initialized")
			end
			-- Fatshark initializes and sends the complete vanilla equipment snapshot
			-- inside the wrapped function.  Request exact peer identities only after
			-- that boundary, and only for this VM's local human unit.
			peer_pull.request(unit, "game_object_initialized_ready")
			return r1, r2, r3, r4
		end)
		mod._cwv_skin_wire_surfaces.game_object_initialized = true
		mod._cwv_identity_surfaces.game_object_initialized = true
		mod._cwv_identity_surfaces.mission_transition = true
		mod._cwv_identity_surfaces.mission_transition_peer_pull = true

		mod:hook("SimpleInventoryExtension", "_spawn_resynced_loadout", function(func, self, equipment_to_spawn, skip_wield)
			if equipment_to_spawn and equipment_to_spawn.slot_id then
				-- #476 Defect B: single-slot resync = PARTIAL publish; no native record for the absent slot (see lifecycle module).
				_send_identity_slots({ [equipment_to_spawn.slot_id] = equipment_to_spawn },
					"spawn_resynced_loadout", false, nil, true)
			end
			if not (equipment_to_spawn and equipment_to_spawn.skin) then
				return func(self, equipment_to_spawn, skip_wield)
			end
			-- Single slot-shaped table; wrap in a one-element array for the helper.
			local r1, r2, r3, r4 = _wire_null_skins({ equipment_to_spawn }, function()
				return func(self, equipment_to_spawn, skip_wield)
			end, "spawn_resynced_loadout")
			if _om._exact_pair_publish_inventory then
				_om._exact_pair_publish_inventory(self, "spawn_resynced_loadout")
			end
			return r1, r2, r3, r4
		end)
		mod._cwv_skin_wire_surfaces.spawn_resynced_loadout = true
		mod._cwv_identity_surfaces.spawn_resynced_loadout = true

		mod:hook("GearUtils", "hot_join_sync", function(func, peer_id, unit, equipment, additional_items)
			local slots = equipment and equipment.slots
			if not slots then
				return func(peer_id, unit, equipment, additional_items)
			end
			-- #660: target the exact semantic descriptor to the joining CWV peer
			-- before vanilla's base-id equipment replay. VMF drops this channel for a
			-- peer without CWV; vanilla still receives only the safe base item/skin.
			-- Track exact slots BEFORE the first attempt so a very fast receiver ACK
			-- cannot race ahead of the pending ledger. The 2026-07-18 paired logs prove
			-- this first attempt may be dropped mid-handshake; the bounded retry below
			-- closes that readiness gap without weakening the vanilla fallback.
			local tracked = lifecycle:track_delivery(peer_id, slots, "hot_join_retry")
			_send_identity_slots(slots, "hot_join_sync", true, peer_id)
			if tracked > 0 then
				pcall(printf,
					"[cwv:660] lifecycle=hot_join_sync adapter=identity_delivery_tracked peer=%s slots=%d interval=%.1fs max_attempts=%d",
					tostring(peer_id), tracked,
					_om.appearance_lifecycle_policy.RETRY_INTERVAL,
					_om.appearance_lifecycle_policy.MAX_RETRY_ATTEMPTS)
			end
			local r1, r2, r3, r4 = _wire_null_skins(slots, function()
				return func(peer_id, unit, equipment, additional_items)
			end, "hot_join_sync")
			if _om._exact_pair_publish_local then
				_om._exact_pair_publish_local("hot_join_sync")
			end
			return r1, r2, r3, r4
		end)
		mod._cwv_skin_wire_surfaces.hot_join_sync = true
		mod._cwv_identity_surfaces.hot_join_sync = true

		-- #423 FOURTH sender (profile-sync / scoreboard channel). The three hooks
		-- above cover only rpc_add_equipment. CosmeticUtils.update_cosmetic_slot is a
		-- SEPARATE skin sender: SimpleInventoryExtension.add_equipment
		-- (simple_inventory_extension.lua:880) calls it on every (re)equip with
		-- slot_equipment_data.skin; vanilla encodes weapon_skins[skin] and
		-- player:set_data(slot.."_skin", id) into GameSession player-sync data
		-- broadcast to EVERY peer (cosmetic_utils.lua:244-250). A peer WITHOUT cwv
		-- decodes it on the scoreboard / playerlist read path (get_weapon_skin_name,
		-- cosmetic_utils.lua:168-178) and fatals -- the 2026-07-18 crash was
		-- weapon_skins index 924 (cwv_es_musket_old_skin) via
		-- rpc_sync_players_session_score at mission end. Husk rendering never reads
		-- this field, so the null is UNCONDITIONAL (never parity-gated) -- mirrors
		-- cosmetics' ct_* null at cosmetics_tweaker.lua:6200 (issue 421). CosmeticUtils
		-- is a plain table -> table-form hook + nil guard (CLAUDE.md "Hooking").
		-- cosmetics/cim hook the same function from THEIR mod ids; VMF chains those.
		if CosmeticUtils then
			mod:hook(CosmeticUtils, "update_cosmetic_slot", function(func, player, slot, item_name, skin_name)
				local safe, subbed = _om.cosmetic_skin_wire.wire_safe_skin(
					skin_name, _om._skin_keys, _custom_skin_keys)
				if subbed then
					local lk = "update_cosmetic_slot|" .. tostring(skin_name)
					if not _null_logged[lk] then   -- once per skin; no equip-spam
						_null_logged[lk] = true
						-- Log the LOCAL weapon_skins index so this apply-site line
						-- correlates with the [gut:272] pre-crash probe, which reports the
						-- divergent numeric index ("weapon_skins does not contain key: 924").
						local nl = rawget(_G, "NetworkLookup")
						local idx = nl and nl.weapon_skins and rawget(nl.weapon_skins, skin_name)
						pcall(printf, "[cwv:skin-wire] wire skin null (update_cosmetic_slot %s): %s (local weapon_skins idx=%s) -> n/a",
							tostring(slot), tostring(skin_name), tostring(idx))
					end
				end
				return func(player, slot, item_name, safe)
			end)
			mod._cwv_skin_wire_surfaces.update_cosmetic_slot = true
		end

		-- #741: a numeric vanilla skin replay can never be made safe by mod presence.
		-- Exact appearance recovery instead uses the acknowledged, bounded semantic
		-- identity delivery already stepped below.
		mod._cwv_skin_wire_surfaces.vanilla_skin_replay_retired = true
		mod._cwv_identity_surfaces.peer_ready = true

		local previous_update = mod.update
		mod.update = function(dt)
			if previous_update then previous_update(dt) end
			if _om._cwv_durable_crowbill_owner then
				_om._cwv_durable_crowbill_owner:step()
			end
			if _om.combat_styles and _om.combat_styles.step then
				_om.combat_styles:step(dt)
			end
			local identity_sent, identity_expired = lifecycle:step_deliveries(dt)
			peer_pull.step(dt)
			if identity_sent > 0 then
				pcall(printf,
					"[cwv:660] lifecycle=hot_join_retry adapter=identity_send attempts=%d pending=%d",
					identity_sent, lifecycle:pending_delivery_count())
			end
			if identity_expired > 0 then
				pcall(printf,
					"[cwv:660] lifecycle=hot_join_retry adapter=identity_timeout expired=%d pending=%d",
					identity_expired, lifecycle:pending_delivery_count())
			end
		end
	end
	_om._skin_wire_hook_installed = true

	-- ============================================================================
	-- issue 423 (BUG_CLASSES 31 + 64, GAMEPLAY axis): cwv damage-profile SEND-gate.
	-- ----------------------------------------------------------------------------
	-- rpc_attack_hit is client->server (weapon_system.lua:182). A cwv CLIENT landing
	-- a hit with a profile-cloning variant would ship the cwv (out-of-vanilla-range)
	-- NetworkLookup.damage_profiles index to the HOST, whose strict decode
	-- (weapon_system.lua:243 -- NetworkLookup.damage_profiles[id], NO rawget) fatals
	-- when the host lacks cwv -> lobby drop (issue 278 / BUG_CLASSES 31 class).
	-- Unconditional registration only buys cwv<->cwv index parity, and #423 showed
	-- that same-mod presence still does not prove the INTEGERS agree.
	--
	-- The hook, the exact catalog and the send state machine now live in
	-- _cwv_exact_wire_runtime.install_damage -- the sole cwv registration on
	-- WeaponSystem.send_rpc_attack_hit; do NOT re-add one here. It must run LAST:
	-- capture() finalizes the whole cwv_* profile namespace, so every
	-- _record_cwv_dp_source producer above has to have run first.
	_om.exact_wire_runtime.install_damage(mod, _om)
end

return install
