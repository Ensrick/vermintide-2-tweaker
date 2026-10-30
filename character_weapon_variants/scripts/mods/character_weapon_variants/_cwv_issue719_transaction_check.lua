-- _cwv_issue719_transaction_check.lua -- isolated production-path regression.
--
-- The three legs behind /cwv_regression_test
-- `issue719_imperial_crowbill_remote_identity`, after its payload round-trip:
--   1. transaction: a synthetic copy of the retained Imperial descriptor
--      (fingerprint `rt719:<fp>`) through atomic hand preselection, the
--      production GearUtils husk transaction and the post-spawn presentation
--      adapter, with a stand-in native spawn. A husk wields with the template
--      BackendUtils resolves from the vanilla item row
--      (simple_husk_inventory_extension.lua:661-662,
--      backend_interface_item_playfab.lua:871-873); for bw_1h_crowbill that is
--      Sienna's one_handed_crowbill (item_master_list_paperweight.lua:37), so
--      the leg hands the transaction exactly that table and requires the native
--      spawn to receive the variant's declared template and the Imperial hand
--      unit. The model is the real proof: both Crowbill variants declare
--      Sienna's template on purpose (_cwv_variant_catalog.lua:948/973).
--      The transform and the #279/#579 probes are stand-ins, and the synthetic
--      fingerprint keys the one #660 preselect line, so a run never writes a
--      husk-spawn line, or spends a log-once key, that a real peer would share.
--      Every raw field it swaps is restored on success or error.
--   2. owner wire: the Weapon Special rebuild must re-add the slot through the
--      announced vanilla path (_cwv_crowbill_runtime.rebuild_slot), never a
--      destroy plus a local-only add that leaves observers without the slot.
--   3. live peers: each peer reads its OWN engine state, so the same command
--      means something on both machines of a co-op card. The owner proves its
--      equipped Crowbill publishes exact identity; an observer proves, for every
--      remote human holding a Crowbill, that the slot still exists, the wielded
--      3P unit is the descriptor's model (never Sienna's donor) and the retained
--      pick/hammer rotation is the presentation owner's last write.
-- Verdict: FAIL on any defect; PASS only when at least one Crowbill holder was
-- proven and none was left unproven; otherwise a `skip:` verdict (#1656 runner
-- sentinel) with bounded samples/counts, so a PASS row proves its leg ran and
-- the whole diagnostic roster budget completed. This is not a gameplay cap.
-- Diagnostics go through engine printf only; nothing here writes a global.
-- `ctx.env` is the offline seam: a table consulted before the engine global of
-- the same name (Managers, Unit, ScriptUnit, Quaternion, Weapons, printf).
return function(_, ctx)
	local _om = ctx.om
	local SLOT = "slot_melee"
	local MAX_ROSTER_ENTRIES, MAX_ATOM_BYTES = 32, 160
	local MAX_DETAIL_BYTES, MAX_LINE_BYTES, MAX_RESULT_BYTES = 512, 768, 2048
	local MAX_SAMPLE_BYTES, MAX_EMISSIONS = 1536, 33
	-- Raw _om fields leg 1 replaces for its duration and always restores.
	local SWAPPED = { "_appearance_husk_wield_context", "_husk_identity_descriptor",
		"_husk_apply_cwv_transform", "_probe_579_hand_compare", "_probe_279_spawn" }

	local function global(name)
		local env = ctx.env
		if type(env) == "table" and env[name] ~= nil then return env[name] end
		return rawget(_G, name)
	end

	-- Display only: never compare this projection as identity. Copy the bounded
	-- prefix before scanning bytes, and never invoke an engine object's tostring.
	-- Every mutable budget belongs to one returned-callback INVOCATION.
	local function bounded_text(value, limit, budget)
		local kind, raw = type(value), nil
		if kind == "string" then raw = value
		elseif kind == "number" or kind == "boolean" or kind == "nil" then raw = tostring(value)
		else raw = "<" .. kind .. ">"; budget.lossy = true end
		local clipped = #raw > limit
		local prefix = clipped and raw:sub(1, limit - 1) .. "~" or raw
		-- Keep the pattern itself NUL-free for the approved Lua 5.1 host.
		local clean, replaced = prefix:gsub("[^ -~]", "?")
		if clipped or replaced > 0 then budget.lossy = true end
		return clean
	end
	local function atom(value, budget) return bounded_text(value, MAX_ATOM_BYTES, budget) end

	local function emit(fmt, budget, ...)
		-- Literal formats stay at their existing call sites. The holder format
		-- has 48 fixed bytes + role<=8 + peer<=160 + verdict<=8 + detail<=512:
		-- <=736 bytes. Guard the actual formatted line as well, before the sink.
		if budget.emitted >= MAX_EMISSIONS then budget.lossy = true; return end
		budget.emitted = budget.emitted + 1
		local line = string.format(fmt, ...)
		if #line > MAX_LINE_BYTES or line:find("[^ -~]") then
			budget.lossy = true
			return
		end
		local sink = global("printf")
		if type(sink) ~= "function" then budget.lossy = true; return end
		local ok = pcall(sink, fmt, ...)
		if not ok then budget.lossy = true end
	end

	-- A copy whose fingerprint can never equal a real peer's, so the shared
	-- `660_preselect:<fingerprint>` log-once key and its text stay distinct.
	local function synthetic(descriptor, budget)
		local copy = {}
		for key, value in pairs(descriptor) do copy[key] = value end
		-- Only this synthetic diagnostic/log key is projected; real descriptor
		-- fields and all model/identity comparisons below remain raw.
		copy.fingerprint = "rt719:" .. atom(descriptor.fingerprint or descriptor.variant_key, budget)
		return copy
	end

	local function quiet() end

	local function transaction(descriptor, family, model, career, template_name, budget)
		local weapons = global("Weapons")
		template_name = template_name or family.SOURCE_TEMPLATE
		local item_template = type(weapons) == "table" and weapons[family.SOURCE_TEMPLATE] or nil
		local expected_template = type(weapons) == "table" and weapons[template_name] or nil
		if type(item_template) ~= "table" or type(expected_template) ~= "table" then
			return "#719 Crowbill weapon templates are not registered: "
				.. atom(family.SOURCE_TEMPLATE, budget) .. ", " .. atom(template_name, budget)
		end
		local probe = synthetic(descriptor, budget)
		local owner = {}
		local item_data = { name = family.SOURCE_ITEM }
		local item_units = { right_hand_unit = family.PLACEHOLDER_UNIT }
		local spawned = {}
		local selected_template, transform_calls
		local saved = {}
		for index, field in ipairs(SWAPPED) do saved[index] = rawget(_om, field) end
		rawset(_om, "_appearance_husk_wield_context", {
			owner_unit_3p = owner, slot_name = SLOT,
		})
		rawset(_om, "_husk_identity_descriptor", function(observed_owner,
				observed_slot, observed_base)
			if observed_owner == owner and observed_slot == SLOT
					and observed_base == family.SOURCE_ITEM then
				return probe, "exact"
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
		rawset(_om, "_probe_579_hand_compare", quiet)
		rawset(_om, "_probe_279_spawn", quiet)
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
			end, nil, "right", item_template, item_units, SLOT, item_data, nil,
				owner, nil, nil, nil, nil)
			if result ~= spawned then error("transaction lost the native spawn result") end
		end)
		for index, field in ipairs(SWAPPED) do rawset(_om, field, saved[index]) end
		if not transaction_ok then
			return "#719 production husk spawn transaction failed: "
				.. atom(transaction_error, budget)
		end
		if selected_template ~= expected_template then
			return "#719 production husk spawn handed vanilla a template other than the"
				.. " variant's declared " .. atom(template_name, budget)
		end
		if transform_calls ~= 1 then
			return "#719 post-spawn presentation adapter did not run exactly once"
		end
	end

	-- Leg 2: drive the production rebuild against a recording inventory. The
	-- only acceptable trace is the announced destroy followed by vanilla's own
	-- re-equip sender carrying the same item; a local add/wield is the defect.
	local function owner_wire(family, budget)
		local runtime = _om.crowbill_runtime
		if type(runtime) ~= "table" or type(runtime.rebuild_slot) ~= "function" then
			return "#719 Crowbill Weapon Special rebuild owner is not installed"
		end
		local calls, resynced = {}, nil
		local inv = {
			destroy_slot = function(_, slot_name, allow)
				calls[#calls + 1] = "destroy:" .. atom(slot_name, budget) .. ":" .. atom(allow, budget)
			end,
			add_equipment = function() calls[#calls + 1] = "local_add" end,
			wield = function() calls[#calls + 1] = "local_wield" end,
			_spawn_resynced_loadout = function(_, row, skip_wield)
				resynced = row
				calls[#calls + 1] = "resync:" .. atom(row and row.slot_id, budget)
					.. ":" .. atom(skip_wield, budget)
			end,
		}
		local item = { name = family.SOURCE_ITEM }
		local ok, why = runtime.rebuild_slot(inv, SLOT, item, nil)
		local trace = table.concat(calls, ",")
		if ok ~= true or trace ~= "destroy:" .. SLOT .. ":true,resync:" .. SLOT .. ":false"
				or not resynced or resynced.item_data ~= item then
			return "#719 Weapon Special rebuild does not re-add the slot for observers: "
				.. atom(why or trace, budget)
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

	-- Observers return (fail, detail, proven): `fail` is a defect, `detail`
	-- with proven=true is a completed leg, `detail` with proven=false is a
	-- Crowbill holder this peer could not prove, and (nil, nil) is no holder.
	local function observe_remote(player, unit, family, budget)
		local descriptor, state = nil, "none"
		if _om._husk_identity_descriptor then
			descriptor, state = _om._husk_identity_descriptor(unit, SLOT, family.SOURCE_ITEM, player)
		end
		local inv, equipment = inventory_of(unit)
		local slots = equipment and equipment.slots
		if state ~= "exact" or type(descriptor) ~= "table"
				or not family.is_family_key(descriptor.variant_key) then
			-- The sender proved the slot native, or it holds no Crowbill: nothing
			-- to prove. A vanilla Crowbill base with no exact identity is exactly
			-- the remote that would render Sienna's donor, so it is never a PASS.
			local held = type(slots) == "table" and slots[SLOT] and slots[SLOT].item_data
			if state ~= "native" and held and held.name == family.SOURCE_ITEM then
				return nil, atom(family.SOURCE_ITEM, budget) .. " held with identity state="
					.. atom(state, budget), false
			end
			return nil, nil, false
		end
		local key = descriptor.variant_key
		local label = atom(key, budget)
		local wielded = inv and (inv.wielded_slot or (equipment and equipment.wielded_slot))
		if wielded ~= SLOT then return nil, label .. " held, not wielded", false end
		if type(slots) ~= "table" or slots[SLOT] == nil then
			return "#719 observer lost the remote " .. label .. " slot while it is wielded"
				.. " (the Weapon Special rebuild never re-added it): weapon invisible"
		end
		local item_data = slots[SLOT].item_data
		if not (item_data and item_data.name == family.SOURCE_ITEM) then
			return nil, label .. " identity retained, slot holds "
				.. atom(item_data and item_data.name, budget), false
		end
		local weapon = equipment.right_hand_wielded_unit_3p
		if not alive(weapon) then
			return "#719 observer has no live 3P unit for the wielded remote " .. label
		end
		local hand_unit = _om.combat_style_appearance
			and type(_om.combat_style_appearance.hand_unit) == "function"
			and _om.combat_style_appearance.hand_unit(descriptor, "right")
			or descriptor.right_hand_unit
		local expected = type(hand_unit) == "string" and hand_unit .. "_3p" or nil
		local observed = observed_unit_name(weapon, unit, expected, family)
		if observed == family.PLACEHOLDER_UNIT .. "_3p" then
			return "#719 observer renders Sienna's donor Crowbill for the remote " .. label
		end
		if expected and observed ~= expected then
			return "#719 observer renders " .. atom(observed, budget) .. " for the remote "
				.. label .. ", expected " .. atom(expected, budget)
		end
		local presentation = _om.crowbill_presentation_owner
		local record = presentation and presentation.record and presentation:record(weapon)
		if not record or record.surface ~= "remote_husk" then
			return "#719 remote " .. label .. " spawned without the husk pick/hammer presentation"
		end
		local state_mode = _om.crowbill_mode_state and _om.crowbill_mode_state:mode(record.identity)
		if state_mode and record.mode ~= state_mode then
			return "#719 remote " .. label .. " shows the " .. atom(record.mode, budget)
				.. " face while its owner chose " .. atom(state_mode, budget)
		end
		local retained = rotation_retained(weapon, record.expected_rotation)
		if retained == false then
			return "#719 remote " .. label .. " lost its " .. atom(record.mode, budget)
				.. " rotation after the presentation write"
		end
		local detail = label .. " unit=" .. atom(observed, budget) .. " mode=" .. atom(record.mode, budget)
			.. " rotation=" .. (retained == nil and "unread" or "retained")
		return nil, detail, retained == true
	end

	local function observe_owner(unit, family, budget)
		local runtime = _om.crowbill_runtime
		local _, equipment = inventory_of(unit)
		local slot = equipment and equipment.slots and equipment.slots[SLOT]
		local key = slot and runtime and runtime.classify
			and runtime.classify(family, slot.item_data, nil, _om._cwv_key_for_item)
		-- No Crowbill, or Sienna's own native one: no CWV identity to prove.
		if not key or key == family.SOURCE_ITEM then return nil, nil, false end
		local payloads = _om._cwv_identity_payloads
			and _om._cwv_identity_payloads({ [SLOT] = slot }) or {}
		for _, payload in ipairs(payloads) do
			if payload.slot == SLOT and payload.item_key == key
					and type(payload.fingerprint) == "string" and payload.fingerprint ~= "" then
				return nil, atom(key, budget) .. " publishes exact identity", true
			end
		end
		return "#719 owner's equipped " .. atom(key, budget) .. " does not publish exact identity:"
			.. " every observer would fall back to Sienna's donor"
	end

	local function peer_observation(family, budget)
		local managers = global("Managers")
		local resolver = _om.peer_resolver
		local players = resolver and resolver.human_players(managers and managers.player)
		if type(players) ~= "table" then
			emit("[cwv:719] peer observation SKIP reason=no_player_manager", budget)
			return "skip: legs 1-2 passed; no player manager to observe peers"
				.. " (reason=no_player_manager)"
		end
		local proven, unproven_count, omitted, sample_bytes = 0, 0, 0, 0
		local samples, cursor, scanned, complete = {}, nil, 0, false
		-- A work budget, not a four-player or BTMP capacity assertion. Count
		-- every keyed entry; one lookahead below proves exact completion at 32.
		for scan_index = 1, 32 do
			local key, player = next(players, cursor)
			if key == nil then complete = true; break end
			cursor, scanned = key, scan_index
			local unit = type(player) == "table" and player.player_unit
			if alive(unit) then
				local role = player.remote and "observer" or "owner"
				local peer = atom(resolver.player_peer_id(player), budget)
				local err, detail, ok_leg
				if player.remote then
					err, detail, ok_leg = observe_remote(player, unit, family, budget)
				else
					err, detail, ok_leg = observe_owner(unit, family, budget)
				end
				if err then err = bounded_text(err, MAX_DETAIL_BYTES, budget) end
				if detail then detail = bounded_text(detail, MAX_DETAIL_BYTES, budget) end
				if err or detail then
					emit("[cwv:719] peer observation role=%s peer=%s verdict=%s %s",
						budget, role, peer, err and "FAIL" or (ok_leg and "ok" or "unproven"),
						err or detail)
				end
				-- An actually encountered defect outranks any diagnostic loss.
				if err then return err end
				if ok_leg then
					proven = proven + 1
				elseif detail then
					unproven_count = unproven_count + 1
					local sample = "role=" .. role .. " peer=" .. peer .. " " .. detail
					local extra = #sample + (#samples > 0 and 2 or 0)
					if sample_bytes + extra <= MAX_SAMPLE_BYTES then
						samples[#samples + 1], sample_bytes = sample, sample_bytes + extra
					else omitted = omitted + 1 end
				end
			end
		end
		if not complete then complete = next(players, cursor) == nil end
		if not complete then
			emit("[cwv:719] peer observation SKIP reason=diagnostic_budget", budget)
			return "skip: legs 1-2 passed; peer observation incomplete"
				.. " (reason=diagnostic_budget scanned=" .. scanned .. " limit=" .. MAX_ROSTER_ENTRIES
				.. " proven=" .. proven .. " unproven=" .. unproven_count .. ")"
		end
		if budget.lossy then
			emit("[cwv:719] peer observation SKIP reason=diagnostic_text_budget", budget)
			return "skip: legs 1-2 passed; diagnostic evidence was not fully representable"
				.. " (reason=diagnostic_text_budget scanned=" .. scanned
				.. " proven=" .. proven .. " unproven=" .. unproven_count .. ")"
		end
		if unproven_count > 0 then
			return "skip: legs 1-2 passed; Crowbill holder not proven ("
				.. table.concat(samples, "; ") .. ") sampled=" .. #samples .. " omitted=" .. omitted
				.. " unproven=" .. unproven_count .. " -- wield the Crowbill and rerun on both peers"
		end
		if proven == 0 then
			emit("[cwv:719] peer observation SKIP reason=no_crowbill_peer", budget)
			return "skip: legs 1-2 passed; no Crowbill holder observed (reason=no_crowbill_peer)"
				.. " -- equip and wield the Imperial or Dawi Crowbill on one peer, rerun on both"
		end
	end

	return function(descriptor, family, model, career, template_name)
		local budget = { lossy = false, emitted = 0 }
		local err = transaction(descriptor, family, model, career, template_name, budget)
		if err then return bounded_text(err, MAX_RESULT_BYTES, budget) end
		err = owner_wire(family, budget)
		if err then return bounded_text(err, MAX_RESULT_BYTES, budget) end
		err = peer_observation(family, budget)
		if err then return bounded_text(err, MAX_RESULT_BYTES, budget) end
	end
end
