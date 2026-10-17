-- _cwv_issue719_transaction_check.lua -- isolated production-path regression.
--
-- The three legs behind /cwv_regression_test
-- `issue719_imperial_crowbill_remote_identity`, after its payload round-trip:
--   1. transaction: the exact retained Imperial descriptor through atomic hand
--      preselection, the production GearUtils husk transaction and the
--      post-spawn presentation adapter (stand-in native spawn; every raw field
--      it swaps is restored on success or error).
--   2. owner wire: the Weapon Special rebuild must re-add the slot through the
--      announced vanilla path (_cwv_crowbill_runtime.rebuild_slot), never a
--      destroy plus a local-only add that leaves observers without the slot.
--   3. live peers: each peer reads its OWN engine state, so the same command
--      means something on both machines of a co-op card. The owner proves its
--      equipped Crowbill publishes exact identity; an observer proves, for every
--      remote human whose exact Crowbill identity it retains, that the slot
--      still exists, the wielded 3P unit is the descriptor's model (never
--      Sienna's donor) and the retained pick/hammer rotation is the
--      presentation owner's last write. With no Crowbill on either side the leg
--      logs a named SKIP and the check passes on legs 1 and 2.
-- Diagnostics go through engine printf only; nothing here writes a global.
-- `ctx.env` is the offline seam: a table consulted before the engine global of
-- the same name (Managers, Unit, ScriptUnit, Quaternion, printf).
return function(_, ctx)
	local _om = ctx.om
	local SLOT = "slot_melee"

	local function global(name)
		local env = ctx.env
		if type(env) == "table" and env[name] ~= nil then return env[name] end
		return rawget(_G, name)
	end

	local function emit(fmt, ...)
		local sink = global("printf")
		if type(sink) == "function" then pcall(sink, fmt, ...) end
	end

	local function transaction(descriptor, family, model, career)
		local owner = {}
		local item_data = { name = family.SOURCE_ITEM }
		local item_units = { right_hand_unit = family.PLACEHOLDER_UNIT }
		local spawned = {}
		local donor_template = {}
		local selected_template, transform_calls
		local prior_context = rawget(_om, "_appearance_husk_wield_context")
		local prior_identity = rawget(_om, "_husk_identity_descriptor")
		local prior_transform = rawget(_om, "_husk_apply_cwv_transform")
		rawset(_om, "_appearance_husk_wield_context", {
			owner_unit_3p = owner, slot_name = SLOT,
		})
		rawset(_om, "_husk_identity_descriptor", function(observed_owner,
				observed_slot, observed_base)
			if observed_owner == owner and observed_slot == SLOT
					and observed_base == family.SOURCE_ITEM then
				return descriptor, "exact"
			end
			return nil, "none"
		end)
		rawset(_om, "_husk_apply_cwv_transform", function(hand, observed_item,
				observed_units, observed_spawned, observed_owner, observed_slot)
			if hand == "right" and observed_item == item_data
					and observed_units == item_units and observed_spawned == spawned
					and observed_owner == owner and observed_slot == SLOT then
				transform_calls = (transform_calls or 0) + 1
			end
		end)
		local transaction_ok, transaction_error = pcall(function()
			local selected = _om._husk_preselect_units(item_units, item_data,
				nil, nil, career)
			if selected ~= true or item_units.right_hand_unit ~= model.right_hand_unit
					or item_units.left_hand_unit ~= nil then
				error("atomic hand preselection did not retain the Imperial model")
			end
			local result = _om._husk_spawn_adapter_transaction(function(_, _, template,
					observed_units)
				selected_template = template
				if observed_units ~= item_units
						or observed_units.right_hand_unit ~= model.right_hand_unit then
					error("native spawn did not receive the Imperial model")
				end
				return spawned, nil, nil, nil
			end, nil, "right", donor_template, item_units, SLOT, item_data, nil,
				owner, nil, nil, nil, nil)
			if result ~= spawned then error("transaction lost the native spawn result") end
		end)
		rawset(_om, "_appearance_husk_wield_context", prior_context)
		rawset(_om, "_husk_identity_descriptor", prior_identity)
		rawset(_om, "_husk_apply_cwv_transform", prior_transform)
		if not transaction_ok then
			return "#719 production husk spawn transaction failed: "
				.. tostring(transaction_error)
		end
		if type(selected_template) ~= "table" or selected_template == donor_template then
			return "#719 production husk spawn transaction retained the Sienna donor template"
		end
		if transform_calls ~= 1 then
			return "#719 post-spawn presentation adapter did not run exactly once"
		end
	end

	-- Leg 2: drive the production rebuild against a recording inventory. The
	-- only acceptable trace is the announced destroy followed by vanilla's own
	-- re-equip sender carrying the same item; a local add/wield is the defect.
	local function owner_wire(family)
		local runtime = _om.crowbill_runtime
		if type(runtime) ~= "table" or type(runtime.rebuild_slot) ~= "function" then
			return "#719 Crowbill Weapon Special rebuild owner is not installed"
		end
		local calls, resynced = {}, nil
		local inv = {
			destroy_slot = function(_, slot_name, allow)
				calls[#calls + 1] = "destroy:" .. tostring(slot_name) .. ":" .. tostring(allow)
			end,
			add_equipment = function() calls[#calls + 1] = "local_add" end,
			wield = function() calls[#calls + 1] = "local_wield" end,
			_spawn_resynced_loadout = function(_, row, skip_wield)
				resynced = row
				calls[#calls + 1] = "resync:" .. tostring(row and row.slot_id)
					.. ":" .. tostring(skip_wield)
			end,
		}
		local item = { name = family.SOURCE_ITEM }
		local ok, why = runtime.rebuild_slot(inv, SLOT, item, nil)
		local trace = table.concat(calls, ",")
		if ok ~= true or trace ~= "destroy:" .. SLOT .. ":true,resync:" .. SLOT .. ":false"
				or not resynced or resynced.item_data ~= item then
			return "#719 Weapon Special rebuild does not re-add the slot for observers: "
				.. tostring(why or trace)
		end
	end

	local function alive(unit)
		local unit_api = global("Unit")
		if unit == nil or type(unit_api) ~= "table" or type(unit_api.alive) ~= "function" then
			return false
		end
		local ok, value = pcall(unit_api.alive, unit)
		return ok and value == true
	end

	local function inventory_of(unit)
		local script_unit = global("ScriptUnit")
		if not alive(unit) or type(script_unit) ~= "table"
				or type(script_unit.has_extension) ~= "function" then
			return nil
		end
		local ok, inv = pcall(script_unit.has_extension, unit, "inventory_system")
		if not ok or type(inv) ~= "table" or type(inv.equipment) ~= "function" then return nil end
		local ok_equipment, equipment = pcall(inv.equipment, inv)
		return inv, ok_equipment and equipment or nil
	end

	local function observed_unit_name(weapon, owner_unit, expected, family)
		if _om._husk_observed_unit_evidence then
			local name = _om._husk_observed_unit_evidence(weapon, owner_unit, SLOT, "right")
			if name then return name end
		end
		-- No ledger row: ask the engine which resource the unit is.
		local unit_api = global("Unit")
		if type(unit_api) == "table" and type(unit_api.is_a) == "function" then
			for _, candidate in ipairs({ expected, family.PLACEHOLDER_UNIT .. "_3p" }) do
				local ok, is_a = pcall(unit_api.is_a, weapon, candidate)
				if ok and is_a == true then return candidate end
			end
		end
		return "unobserved"
	end

	-- true / false, or nil when this build cannot read rotations back.
	local function rotation_retained(unit, expected)
		local unit_api, quaternion = global("Unit"), global("Quaternion")
		if expected == nil or type(unit_api) ~= "table"
				or type(unit_api.local_rotation) ~= "function"
				or type(quaternion) ~= "table" or type(quaternion.dot) ~= "function" then
			return nil
		end
		local ok, actual = pcall(unit_api.local_rotation, unit, 0)
		if not ok or actual == nil then return nil end
		local ok_dot, dot = pcall(quaternion.dot, actual, expected)
		if not ok_dot or type(dot) ~= "number" then return nil end
		return math.abs(dot) >= 0.999
	end

	local function observe_remote(player, unit, family)
		local descriptor, state = nil, "none"
		if _om._husk_identity_descriptor then
			descriptor, state = _om._husk_identity_descriptor(unit, SLOT, family.SOURCE_ITEM, player)
		end
		if state ~= "exact" or type(descriptor) ~= "table"
				or not family.is_family_key(descriptor.variant_key) then
			return nil, nil, state
		end
		local key = descriptor.variant_key
		local inv, equipment = inventory_of(unit)
		local slots = equipment and equipment.slots
		local wielded = inv and (inv.wielded_slot or (equipment and equipment.wielded_slot))
		if wielded ~= SLOT then return nil, key .. " held, not wielded" end
		if type(slots) ~= "table" or slots[SLOT] == nil then
			return "#719 observer lost the remote " .. key .. " slot while it is wielded"
				.. " (the Weapon Special rebuild never re-added it): weapon invisible"
		end
		local item_data = slots[SLOT].item_data
		if not (item_data and item_data.name == family.SOURCE_ITEM) then
			return nil, key .. " identity retained, slot holds "
				.. tostring(item_data and item_data.name)
		end
		local weapon = equipment.right_hand_wielded_unit_3p
		if not alive(weapon) then
			return "#719 observer has no live 3P unit for the wielded remote " .. key
		end
		local hand_unit = _om.combat_style_appearance
			and type(_om.combat_style_appearance.hand_unit) == "function"
			and _om.combat_style_appearance.hand_unit(descriptor, "right")
			or descriptor.right_hand_unit
		local expected = type(hand_unit) == "string" and hand_unit .. "_3p" or nil
		local observed = observed_unit_name(weapon, unit, expected, family)
		if observed == family.PLACEHOLDER_UNIT .. "_3p" then
			return "#719 observer renders Sienna's donor Crowbill for the remote " .. key
		end
		if expected and observed ~= expected then
			return "#719 observer renders " .. tostring(observed) .. " for the remote "
				.. key .. ", expected " .. expected
		end
		local presentation = _om.crowbill_presentation_owner
		local record = presentation and presentation.record and presentation:record(weapon)
		if not record or record.surface ~= "remote_husk" then
			return "#719 remote " .. key .. " spawned without the husk pick/hammer presentation"
		end
		local state_mode = _om.crowbill_mode_state and _om.crowbill_mode_state:mode(record.identity)
		if state_mode and record.mode ~= state_mode then
			return "#719 remote " .. key .. " shows the " .. tostring(record.mode)
				.. " face while its owner chose " .. tostring(state_mode)
		end
		local retained = rotation_retained(weapon, record.expected_rotation)
		if retained == false then
			return "#719 remote " .. key .. " lost its " .. tostring(record.mode)
				.. " rotation after the presentation write"
		end
		return nil, key .. " unit=" .. tostring(observed) .. " mode=" .. tostring(record.mode)
			.. " rotation=" .. (retained == nil and "unread" or "retained")
	end

	local function observe_owner(unit, family)
		local runtime = _om.crowbill_runtime
		local _, equipment = inventory_of(unit)
		local slot = equipment and equipment.slots and equipment.slots[SLOT]
		local key = slot and runtime and runtime.classify
			and runtime.classify(family, slot.item_data, nil, _om._cwv_key_for_item)
		if not key then return nil, nil end
		if key == family.SOURCE_ITEM then return nil, "native Sienna Crowbill" end
		local payloads = _om._cwv_identity_payloads
			and _om._cwv_identity_payloads({ [SLOT] = slot }) or {}
		for _, payload in ipairs(payloads) do
			if payload.slot == SLOT and payload.item_key == key
					and type(payload.fingerprint) == "string" and payload.fingerprint ~= "" then
				return nil, key .. " publishes exact identity"
			end
		end
		return "#719 owner's equipped " .. key .. " does not publish exact identity:"
			.. " every observer would fall back to Sienna's donor"
	end

	local function peer_observation(family)
		local managers = global("Managers")
		local resolver = _om.peer_resolver
		local players = resolver and resolver.human_players(managers and managers.player)
		if type(players) ~= "table" then
			emit("[cwv:719] peer observation SKIP reason=no_player_manager")
			return nil
		end
		local seen = 0
		for _, player in pairs(players) do
			local unit = type(player) == "table" and player.player_unit
			if alive(unit) then
				local role = player.remote and "observer" or "owner"
				local err, detail, state
				if player.remote then
					err, detail, state = observe_remote(player, unit, family)
				else
					err, detail = observe_owner(unit, family)
				end
				if err or detail then
					seen = seen + 1
					emit("[cwv:719] peer observation role=%s peer=%s verdict=%s %s",
						role, tostring(resolver.player_peer_id(player)),
						err and "FAIL" or "ok", tostring(err or detail))
				elseif state and state ~= "none" then
					emit("[cwv:719] peer observation role=observer peer=%s state=%s -- no exact Crowbill identity retained",
						tostring(resolver.player_peer_id(player)), tostring(state))
				end
				if err then return err end
			end
		end
		if seen == 0 then
			emit("[cwv:719] peer observation SKIP reason=no_crowbill_peer"
				.. " -- equip the Imperial or Dawi Crowbill on one peer, rerun on both")
		end
	end

	return function(descriptor, family, model, career)
		local err = transaction(descriptor, family, model, career)
		if err then return err end
		err = owner_wire(family)
		if err then return err end
		return peer_observation(family)
	end
end
