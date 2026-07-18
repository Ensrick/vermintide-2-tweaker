-- _cwv_old_musket_wire.lua
-- Old Musket stance + shot-report wire (#474).
--
-- Owns the bounded `cwv_old_musket_mode_v1` VMF channel (state / query / fire
-- ops) AND the shared acceptors that the delivering `cwv_item_identity`
-- channel routes into (see the identity register + send adapter in the entry).
-- The 2026-07-18 paired logs proved the dedicated mode channel never delivered
-- while the identity channel did, so stance rides identity payloads
-- (`musket_mode`) and the shot mirrors as a sentinel `cwv_musket_fire` payload;
-- this channel stays registered as belt-and-suspenders for the same schema.
--
-- Exports (all on ctx.om): _old_musket_modes_by_owner/_by_backend,
-- _old_musket_bid_for_item, _old_musket_valid_bid, _old_musket_mode_for_owner,
-- _old_musket_mode_for_local_slot, _old_musket_record_and_publish,
-- _old_musket_publish_local_loadout, _old_musket_request_states,
-- _old_musket_publish_fire, _old_musket_accept_mode,
-- _old_musket_play_remote_fire, _old_musket_resolve_husk_wield_event,
-- _old_musket_apply_husk_stance, _old_musket_mode_channel/_schema.
--
-- Load-time deps: none beyond (mod, ctx.om). Runtime deps resolved lazily via
-- _om: _cwv_key_for_item, _cwv_send_identity_slots, appearance_lifecycle_policy,
-- _track_old_musket_unit, _apply_old_musket_textures, _apply_old_musket_transform,
-- _old_musket_transform_components.
return function(mod, ctx)
local _om = ctx.om
	local CHANNEL, SCHEMA = "cwv_old_musket_mode_v1", 1
	local modes_by_owner = setmetatable({}, { __mode = "k" })
	local stance_by_owner = setmetatable({}, { __mode = "k" })
	local modes_by_peer = {}
	local modes_by_backend = {}
	local diag_seen, diag_count, DIAG_MAX = {}, 0, 48
	_om._old_musket_modes_by_owner = modes_by_owner
	_om._old_musket_modes_by_backend = modes_by_backend

	local function old_bid(item_data)
		local bid = item_data and (item_data.backend_id or item_data.ItemInstanceId
			or (item_data.mod_data and item_data.mod_data.backend_id))
		local key = item_data and _om._cwv_key_for_item
			and _om._cwv_key_for_item(bid, item_data)
		if key ~= "cwv_es_musket_old" then
			local template = item_data and item_data.template
			if template ~= "old_musket_template" and template ~= "old_musket_template_melee" then
				return nil
			end
		end
		return type(bid) == "string" and bid ~= "" and bid or nil
	end

	local function valid_bid(bid)
		return type(bid) == "string" and bid ~= "" and #bid <= 128
	end
	-- Runtime-regression handles for #484. These are pure identity checks; they
	-- do not send traffic or mutate presentation state.
	_om._old_musket_bid_for_item = old_bid
	_om._old_musket_valid_bid = valid_bid

	local function diag_once(key, fmt, ...)
		if diag_seen[key] or diag_count >= DIAG_MAX then return end
		diag_seen[key], diag_count = true, diag_count + 1
		pcall(printf, "[cwv:474] " .. fmt, ...)
	end

	local function send(recipient, op, slot_name, mode, bid)
		if type(mod.network_send) ~= "function" then return false end
		local ok = pcall(function()
			mod:network_send(CHANNEL, recipient or "others", SCHEMA, op,
				slot_name or "", mode or "", bid or "")
		end)
		return ok
	end

	local function owner_slot(owner_unit)
		if not owner_unit or not Unit.alive(owner_unit) then return nil end
		local ok, inv = pcall(ScriptUnit.extension, owner_unit, "inventory_system")
		if not ok or not inv or not inv.equipment then return nil end
		local equipment = inv:equipment()
		return equipment and equipment.wielded_slot, equipment, inv
	end

	-- Mirror SimpleHuskInventoryExtension._wield_slot's career-aware resolver
	-- (vanilla source lines 637/709-724) against the selected Old Musket
	-- template. The wire item deliberately remains es_handgun for lookup safety,
	-- so vanilla always resolves `to_handgun`; melee mode must replay the
	-- receiver-native polearm wield after vanilla returns.
	local function resolve_husk_wield_event(mode, career_name)
		if mode ~= "melee" and mode ~= "ranged" then return nil, "invalid_mode" end
		local weapons = rawget(_G, "Weapons")
		local template = weapons and (mode == "melee"
			and weapons.old_musket_template_melee or weapons.old_musket_template)
		if type(template) ~= "table" then return nil, "template_unavailable" end
		local wield = template.wield_anim
		local by_career = template.wield_anim_career
		if type(by_career) == "table" then wield = by_career[career_name] or wield end
		local wield_3p = template.wield_anim_3p
		local by_career_3p = template.wield_anim_career_3p
		if type(by_career_3p) == "table" then
			wield_3p = by_career_3p[career_name] or wield_3p
		end
		return wield_3p or wield, wield_3p and "3p" or "fallback"
	end
	_om._old_musket_resolve_husk_wield_event = resolve_husk_wield_event

	local function apply_husk_stance(owner_unit, slot_name, weapon_unit, mode, surface)
		if not owner_unit or not Unit.alive(owner_unit)
				or not weapon_unit or not Unit.alive(weapon_unit) then
			return false, "unit_unavailable"
		end
		local _, _, inventory = owner_slot(owner_unit)
		local career_name = inventory and inventory._career_name
		local event_name, event_source = resolve_husk_wield_event(mode, career_name)
		if not event_name then return false, event_source end
		local slots = stance_by_owner[owner_unit]
		if not slots then slots = {}; stance_by_owner[owner_unit] = slots end
		local prior = slots[slot_name]
		if prior and prior.weapon_unit == weapon_unit and prior.mode == mode
				and prior.event_name == event_name then
			return true, "deduped"
		end
		-- Match vanilla's post-spawn body transition. Both events are compiled
		-- vanilla animation names; no custom NetworkLookup entry is introduced.
		local flow_ok = pcall(Unit.flow_event, owner_unit, "lua_wield")
		local anim_ok = pcall(Unit.animation_event, owner_unit, event_name)
		if not anim_ok then return false, "animation_rejected" end
		slots[slot_name] = {
			weapon_unit = weapon_unit,
			mode = mode,
			event_name = event_name,
		}
		diag_once("stance:" .. tostring(owner_unit) .. ":" .. tostring(slot_name)
				.. ":" .. tostring(weapon_unit) .. ":" .. mode,
			"husk stance dispatched_unverified owner=%s slot=%s surface=%s mode=%s career=%s anim=%s source=%s flow=%s",
			tostring(owner_unit), tostring(slot_name), tostring(surface), mode,
			tostring(career_name), tostring(event_name), tostring(event_source), tostring(flow_ok))
		return true, "dispatched_unverified"
	end
	_om._old_musket_apply_husk_stance = apply_husk_stance

	local function apply_owner(owner_unit, slot_name, mode, surface)
		local wielded_slot, equipment = owner_slot(owner_unit)
		if wielded_slot ~= slot_name or not equipment then return false end
		local unit = equipment.right_hand_wielded_unit_3p
		if not unit or not Unit.alive(unit) then return false end
		_om._track_old_musket_unit(unit, "3p", mode)
		_om._apply_old_musket_textures(unit)
		_om._apply_old_musket_transform(unit, "3p", mode)
		apply_husk_stance(owner_unit, slot_name, unit, mode, surface)
		local pos, _, scale = _om._old_musket_transform_components("3p", mode)
		diag_once("apply:" .. tostring(owner_unit) .. ":" .. slot_name .. ":" .. mode .. ":" .. surface,
			"presentation owner=%s slot=%s surface=%s mode=%s final_pos=(%.3f,%.3f,%.3f) final_scale=(%.3f,%.3f,%.3f)",
			tostring(owner_unit), slot_name, surface, mode,
			pos[1], pos[2], pos[3], scale[1], scale[2], scale[3])
		return true
	end

	local function peer_for_owner(owner_unit)
		local pm = Managers and Managers.player
		local ok, player = pm and pcall(pm.owner, pm, owner_unit)
		player = ok and player or nil
		if not player then return nil end
		if type(player.peer_id) == "string" then return player.peer_id end
		local nok, peer_id = pcall(player.network_id, player)
		return nok and peer_id or nil
	end

	_om._old_musket_mode_for_owner = function(owner_unit, slot_name)
		local slots = owner_unit and modes_by_owner[owner_unit]
		if not slots then slots = modes_by_peer[peer_for_owner(owner_unit)] end
		if not slots then return "ranged" end
		if not slot_name then slot_name = owner_slot(owner_unit) end
		return slots[slot_name] or "ranged"
	end

	_om._old_musket_record_and_publish = function(owner_unit, slot_name, item_data, mode, reason, recipient)
		local bid = old_bid(item_data)
		if not bid or (mode ~= "melee" and mode ~= "ranged") then return false end
		modes_by_backend[bid] = mode
		if owner_unit then
			local slots = modes_by_owner[owner_unit] or {}
			modes_by_owner[owner_unit], slots[slot_name] = slots, mode
		end
		send(recipient, "state", slot_name, mode, bid)
		-- #474 (2026-07-18): paired logs prove this channel's sends never arrive
		-- (state tx on both peers, zero state rx either direction) while the
		-- sibling cwv_item_identity channel delivered in the same minute. Replay
		-- the owner's slots over THAT channel with the stance stamped into the
		-- payload (see the identity send adapter). One bounded send per edge.
		if _om._cwv_send_identity_slots and owner_unit then
			local _, equipment = owner_slot(owner_unit)
			if equipment and equipment.slots then
				pcall(_om._cwv_send_identity_slots, equipment.slots, "musket_mode", true)
			end
		end
		diag_once("tx:" .. tostring(owner_unit) .. ":" .. slot_name .. ":" .. mode .. ":" .. tostring(reason),
			"state tx owner=%s slot=%s mode=%s bid=%s reason=%s",
			tostring(owner_unit), slot_name, mode, bid, tostring(reason))
		return true
	end

	-- Owner-side stance for one of the LOCAL player's slots. Consumed by the
	-- cwv_item_identity send adapter so stance rides the delivering channel.
	_om._old_musket_mode_for_local_slot = function(slot_name)
		local pm = Managers and Managers.player
		local ok, player = pm and pcall(pm.local_player, pm, 1)
		player = ok and player or nil
		local owner_unit = player and player.player_unit
		local _, equipment = owner_slot(owner_unit)
		local slot_data = equipment and equipment.slots and equipment.slots[slot_name]
		local item_data = slot_data and slot_data.item_data
		local mode = item_data and item_data.mod_data and item_data.mod_data.cwv_musket_stance
		if mode ~= "melee" and mode ~= "ranged" then
			local bid = old_bid(item_data)
			mode = (bid and modes_by_backend[bid]) or "ranged"
		end
		return mode
	end

	_om._old_musket_publish_local_loadout = function(recipient, reason)
		local pm = Managers and Managers.player
		local ok, player = pm and pcall(pm.local_player, pm, 1)
		player = ok and player or nil
		local owner_unit = player and player.player_unit
		local _, equipment = owner_slot(owner_unit)
		local slots = equipment and equipment.slots
		if type(slots) ~= "table" then return 0 end
		local n = 0
		for slot_name, slot_data in pairs(slots) do
			local item_data = slot_data and slot_data.item_data
			if old_bid(item_data) then
				local mode = item_data.mod_data and item_data.mod_data.cwv_musket_stance or "ranged"
				if _om._old_musket_record_and_publish(owner_unit, slot_name, item_data,
						mode, reason, recipient) then n = n + 1 end
			end
		end
		return n
	end

	_om._old_musket_request_states = function(reason)
		send("others", "query")
		_om._old_musket_publish_local_loadout(nil, reason or "state_boundary")
	end

	_om._old_musket_publish_fire = function(owner_unit, event_name)
		local slot_name, equipment = owner_slot(owner_unit)
		local slot_data = equipment and equipment.slots and equipment.slots[slot_name]
		local bid = old_bid(slot_data and slot_data.item_data)
		if not bid or event_name ~= "player_combat_weapon_rifle_fire" then return false end
		local ok_mode_channel = send("others", "fire", slot_name, event_name, bid)
		-- #474 (2026-07-18): mirror the shot on the delivering cwv_item_identity
		-- channel. The sentinel slot fails the receiver's valid_slot() on builds
		-- without this code, so mixed-version lobbies ignore it safely.
		local ok_identity = false
		if type(mod.network_send) == "function" then
			local schema = (_om.appearance_lifecycle_policy
				and _om.appearance_lifecycle_policy.SCHEMA) or 2
			ok_identity = pcall(mod.network_send, mod, "cwv_item_identity", "others", schema, {
				slot = "cwv_musket_fire",
				provider = "cwv",
				item_key = "cwv_es_musket_old",
				base_item_key = "es_handgun",
				skin_key = "",
				fingerprint = "",
				fire_event = event_name,
			})
		end
		return ok_mode_channel or ok_identity
	end

	-- #474 (2026-07-18): shared acceptors. Stance and shot reports now arrive on
	-- TWO wires: this bounded mode channel (kept registered; it never delivered
	-- in the paired 2026-07-18 logs, cause undetermined at the VMF layer) and
	-- the proven cwv_item_identity channel. Both route here so there is exactly
	-- one implementation of "apply a remote stance" / "play a remote shot".
	local function accept_mode(sender_peer_id, slot_name, mode, bid, source)
		if (mode ~= "melee" and mode ~= "ranged") or type(slot_name) ~= "string" then
			return false
		end
		local peer_slots = modes_by_peer[sender_peer_id] or {}
		modes_by_peer[sender_peer_id], peer_slots[slot_name] = peer_slots, mode
		if bid and valid_bid(bid) then modes_by_backend[bid] = mode end
		local pm = Managers and Managers.player
		local ok, player = pm and pcall(pm.player_from_peer_id, pm, sender_peer_id)
		player = ok and player or nil
		local owner_unit = player and player.player_unit
		if owner_unit then
			local slots = modes_by_owner[owner_unit] or {}
			modes_by_owner[owner_unit], slots[slot_name] = slots, mode
			apply_owner(owner_unit, slot_name, mode, "remote_event:" .. tostring(source))
		end
		diag_once("rx:" .. tostring(sender_peer_id) .. ":" .. slot_name .. ":" .. mode .. ":" .. tostring(source),
			"state rx peer=%s owner=%s slot=%s mode=%s source=%s",
			tostring(sender_peer_id), tostring(owner_unit), slot_name, mode, tostring(source))
		return true
	end
	_om._old_musket_accept_mode = accept_mode

	local function play_remote_fire(sender_peer_id, event_name, source)
		if event_name ~= "player_combat_weapon_rifle_fire" then return false end
		local pm = Managers and Managers.player
		local ok, player = pm and pcall(pm.player_from_peer_id, pm, sender_peer_id)
		player = ok and player or nil
		local owner_unit = player and player.player_unit
		local world = rawget(_G, "Application") and Application.main_world()
		if owner_unit and Unit.alive(owner_unit) and world and rawget(_G, "WwiseUtils") then
			local played = pcall(WwiseUtils.trigger_unit_event, world, event_name, owner_unit, 0)
			diag_once("fire:" .. tostring(sender_peer_id) .. ":" .. tostring(source),
				"remote fire peer=%s owner=%s source=%s played=%s",
				tostring(sender_peer_id), tostring(owner_unit), tostring(source), tostring(played))
			return played and true or false
		end
		return false
	end
	_om._old_musket_play_remote_fire = play_remote_fire

	if type(mod.network_register) == "function" then
		pcall(function()
			mod:network_register(CHANNEL, function(sender_peer_id, schema, op, slot_name, mode, bid)
				if schema ~= SCHEMA then return end
				if op == "query" then
					_om._old_musket_publish_local_loadout(sender_peer_id, "query_reply")
					return
				end
				if op == "fire" then
					if valid_bid(bid) then play_remote_fire(sender_peer_id, mode, "mode_channel") end
					return
				end
				if op ~= "state" or not valid_bid(bid) then return end
				accept_mode(sender_peer_id, slot_name, mode, bid, "mode_channel")
			end)
		end)
	end
	_om._old_musket_mode_channel = CHANNEL
	_om._old_musket_mode_schema = SCHEMA
end
