-- #719 Crowbill Weapon Special on the vanilla equipment wire, plus the live
-- two-peer legs of `issue719_imperial_crowbill_remote_identity`.
--
-- The wire model below mirrors vanilla, cited per edge:
--   * SimpleInventoryExtension.destroy_slot announces the destroy
--     (simple_inventory_extension.lua:1181-1187); the observer's husk drops the
--     slot (simple_husk_inventory_extension.lua:247-259, gear_utils.lua:457);
--   * add_equipment is local only (simple_inventory_extension.lua:858-891);
--   * wield announces the wield (:715-720); a husk wield of a missing slot
--     spawns nothing (simple_husk_inventory_extension.lua:641-647);
--   * _spawn_resynced_loadout announces the add, then adds and wields locally
--     (simple_inventory_extension.lua:1443-1473).
-- Before the fix the toggle rebuilt with destroy + local add + wield, so the
-- observer kept no slot and the Crowbill vanished for every other player.
return function(H, repo_root)
	local mod_root = repo_root
		.. "/character_weapon_variants/scripts/mods/character_weapon_variants/"
	local SLOT = "slot_melee"
	local IMPERIAL = "cwv_es_imperial_crowbill"

	local function load_runtime() return dofile(mod_root .. "_cwv_crowbill_runtime.lua") end
	local family = dofile(mod_root .. "_cwv_crowbill_family.lua")
	local policy = dofile(mod_root .. "_cwv_crowbill_hammer_mode.lua")
	local presentation = dofile(mod_root .. "_cwv_crowbill_presentation.lua")
	local peer_resolver = dofile(mod_root .. "_cwv_peer_resolver.lua")
	local model = family.model_for_variant(IMPERIAL)

	local function clone(value, seen)
		if type(value) ~= "table" then return value end
		seen = seen or {}
		if seen[value] then return seen[value] end
		local copy = {}
		seen[value] = copy
		for key, child in pairs(value) do copy[clone(key, seen)] = clone(child, seen) end
		return copy
	end

	-- The runtime installer reads engine tables as globals; swap them for the
	-- duration of one body and always restore them.
	local GLOBALS = { "Weapons", "DamageProfileTemplates", "PowerLevelTemplates",
		"NetworkLookup", "Unit", "ScriptUnit", "Managers" }
	local function with_globals(values, body)
		local saved, saved_clone = {}, table.clone
		for _, key in ipairs(GLOBALS) do saved[key] = _G[key]; _G[key] = values[key] end
		table.clone = function(value) return clone(value) end
		local ok, err = pcall(body)
		for _, key in ipairs(GLOBALS) do _G[key] = saved[key] end
		table.clone = saved_clone
		if not ok then error(err, 0) end
	end

	local function engine_tables()
		local action_one, damage_profiles, power_levels = {}, {}, {}
		for action_name in pairs(policy.DIRECT_ACTIONS) do
			local profile = "fixture_" .. action_name
			action_one[action_name] = { kind = "sweep", damage_profile = profile,
				allowed_chain_actions = {} }
			damage_profiles[profile] = { cleave_distribution = "cleave_" .. profile,
				armor_modifier = "armor_" .. profile, default_target = "target_" .. profile,
				targets = "targets_" .. profile }
			power_levels["cleave_" .. profile] = { attack = 1, impact = 1 }
			power_levels["armor_" .. profile] = { attack = { 1, 0.5, 1, 1, 1, 0.5 } }
			power_levels["target_" .. profile] = { power_distribution = { attack = 1, impact = 1 } }
			power_levels["targets_" .. profile] = { { power_distribution = { attack = 1, impact = 1 } } }
		end
		return {
			Weapons = { one_handed_crowbill = { actions = { action_one = action_one } } },
			DamageProfileTemplates = damage_profiles,
			PowerLevelTemplates = power_levels,
			NetworkLookup = { damage_profiles = {} },
		}
	end

	-- Owner inventory + one observer husk joined by the vanilla wire rules.
	local function wire_world(opts)
		opts = opts or {}
		local wire, observer = {}, { slots = { [SLOT] = { item_name = family.SOURCE_ITEM } },
			visible = true }
		local function receive(op, slot_name, item_name)
			wire[#wire + 1] = op
			if op == "destroy" then
				observer.slots[slot_name] = nil
			elseif op == "add" then
				observer.slots[slot_name] = { item_name = item_name }
			elseif op == "wield" then
				observer.wielded = slot_name
				observer.visible = observer.slots[slot_name] ~= nil
			end
		end
		local item = { backend_id = "imperial-719", cwv_key = IMPERIAL,
			name = family.SOURCE_ITEM, template = family.SOURCE_TEMPLATE }
		local equipment = { wielded_slot = SLOT, slots = { [SLOT] = { item_data = item } } }
		local resync_failures = opts.resync_failures or 0
		local inv = { equipment = function() return equipment end }
		function inv:destroy_slot(slot_name)
			if equipment.slots[slot_name] == nil then return end
			receive("destroy", slot_name)
			equipment.slots[slot_name] = nil
		end
		function inv:add_equipment(slot_name, item_data)
			equipment.slots[slot_name] = { item_data = item_data }
		end
		function inv:wield(slot_name)
			if equipment.slots[slot_name] == nil then return false end
			equipment.wielded_slot = slot_name
			receive("wield", slot_name)
		end
		if not opts.no_resync then
			function inv:_spawn_resynced_loadout(row, skip_wield)
				if resync_failures > 0 then
					resync_failures = resync_failures - 1
					error("fixture resync failure")
				end
				receive("add", row.slot_id, row.item_data.name)
				self:add_equipment(row.slot_id, row.item_data)
				if not skip_wield then self:wield(row.slot_id) end
			end
		end
		return { wire = wire, observer = observer, item = item, inv = inv,
			equipment = equipment, owner_unit = { alive = true } }
	end

	local function toggle(world)
		local runtime = load_runtime()
		local tables = engine_tables()
		tables.Unit = { alive = function(unit) return unit == world.owner_unit end }
		tables.ScriptUnit = { extension = function() return world.inv end }
		with_globals(tables, function()
			local installed, err = runtime.install({}, {
				crowbill_hammer_mode = policy,
				crowbill_family = family,
				peer_resolver = peer_resolver,
				_record_cwv_dp_source = function() end,
				_cwv_key_for_item = function(_, item) return item and item.cwv_key end,
			})
			H.truthy(installed, err)
			_G.Weapons.cwv_crowbill_pick_template.actions.action_three.default
				.enter_function(world.owner_unit)
			world.template = runtime.resolve_template(world.item)
			world.hammer_template = _G.Weapons.cwv_crowbill_hammer_template
		end)
		return runtime
	end

	H.test("#719 Weapon Special toggle keeps the Crowbill slot on the observer", function()
		local world = wire_world()
		toggle(world)
		H.truthy(world.observer.slots[SLOT] ~= nil,
			"observer lost the slot: wire was " .. table.concat(world.wire, ","))
		H.equal(world.observer.visible, true, "observer wield found no slot")
		H.equal(table.concat(world.wire, ","), "destroy,add,wield")
		H.equal(world.item.mod_data.cwv_crowbill_mode, policy.MODE_HAMMER)
		H.equal(world.template, world.hammer_template)
		H.truthy(world.equipment.slots[SLOT] ~= nil, "owner slot must be re-added")
	end)

	H.test("#719 rebuild fails closed without the vanilla re-equip sender", function()
		local world = wire_world({ no_resync = true })
		local runtime = load_runtime()
		local ok, why = runtime.rebuild_slot(world.inv, SLOT, world.item, nil)
		H.equal(ok, false)
		H.equal(why, "resync_unavailable")
		H.equal(#world.wire, 0, "nothing may be destroyed when the slot cannot be re-added")
		toggle(world)
		H.equal(#world.wire, 0)
		H.equal(world.item.mod_data.cwv_crowbill_mode, policy.MODE_PICK,
			"a rejected rebuild must restore the previous face")
		H.truthy(world.equipment.slots[SLOT] ~= nil)
	end)

	H.test("#719 a failed re-equip restores the face and re-adds the slot for everyone", function()
		local world = wire_world({ resync_failures = 1 })
		toggle(world)
		H.equal(world.item.mod_data.cwv_crowbill_mode, policy.MODE_PICK)
		H.truthy(world.equipment.slots[SLOT] ~= nil, "owner slot repaired")
		H.equal(table.concat(world.wire, ","), "destroy,add,wield")
		H.equal(world.observer.visible, true)
	end)

	-- Presentation evidence: the record is recomposed from the RETAINED base.
	local ops = {
		identity = function() return { q = "identity" } end,
		axis_angle = function(axis, degrees) return { q = "axis", axis = axis, degrees = degrees } end,
		multiply = function(base, delta) return { q = "mul", left = base, right = delta } end,
	}
	local function same(a, b)
		if type(a) ~= "table" or type(b) ~= "table" then return a == b end
		for key, value in pairs(a) do if not same(value, b[key]) then return false end end
		for key in pairs(b) do if a[key] == nil then return false end end
		return true
	end

	local function presentation_owner(mode_state)
		return presentation.new({
			alive = function(unit) return unit.alive end,
			mode_for = function(identity) return mode_state:mode(identity) end,
			rotation_ops = ops,
			write_rotation = function(unit, rotation) unit.rotation = rotation; return true end,
		})
	end

	H.test("#719 presentation record exposes face and recomposed retained rotation", function()
		local state = policy.new()
		local owner = presentation_owner(state)
		local unit = { alive = true }
		local base = { q = "authored" }
		H.equal(owner:record(unit), nil)
		H.truthy(owner:apply(unit, "id-719", "remote_husk", base))
		local record = owner:record(unit)
		H.equal(record.surface, "remote_husk")
		H.equal(record.mode, policy.MODE_PICK)
		H.truthy(same(record.expected_rotation, base))
		state:set_mode("id-719", policy.MODE_HAMMER)
		H.equal(owner:reapply("id-719"), 1)
		record = owner:record(unit)
		H.equal(record.mode, policy.MODE_HAMMER)
		H.truthy(same(record.expected_rotation, unit.rotation))
		H.equal(record.expected_rotation.left, base, "hammer face composes on the retained base")
	end)

	-- Live legs of the named in-game check, driven through ctx.env only.
	local function check_world(opts)
		opts = opts or {}
		local lines = {}
		local mode_state = policy.new()
		local om = {
			crowbill_runtime = load_runtime(),
			peer_resolver = peer_resolver,
			crowbill_mode_state = mode_state,
			_cwv_key_for_item = function(_, item) return item and item.cwv_key end,
		}
		om.crowbill_presentation_owner = presentation_owner(mode_state)
		-- Transaction-leg stand-ins only (the production seam is covered by
		-- test_cwv_husk_adapter.lua); they must succeed so the live legs run.
		om._husk_preselect_units = function(units)
			units.right_hand_unit = model.right_hand_unit
			units.left_hand_unit = nil
			return true
		end
		om._husk_spawn_adapter_transaction = function(func, world, hand, template, units,
				slot_name, item_data, _, owner_unit)
			local spawned = func(world, hand, template, units)
			om._husk_apply_cwv_transform(hand, item_data, units, spawned, owner_unit, slot_name)
			return spawned
		end
		om._husk_apply_cwv_transform = function() end

		local expected_3p = model.right_hand_unit .. "_3p"
		local weapon = { alive = true, resource = opts.resource or expected_3p }
		local husk_inv = { wielded_slot = opts.not_wielded and "slot_ranged" or SLOT }
		husk_inv._equipment = {
			slots = opts.destroyed and {} or { [SLOT] = { item_data = { name = family.SOURCE_ITEM } } },
			right_hand_wielded_unit_3p = weapon,
		}
		function husk_inv:equipment() return self._equipment end
		local husk = { alive = true, inventory = husk_inv }
		local identity = IMPERIAL .. ":peer-host:" .. SLOT
		if not opts.no_presentation then
			om.crowbill_presentation_owner:apply(weapon, identity, "remote_husk", { q = "authored" })
		end
		if opts.owner_mode then mode_state:set_mode(identity, opts.owner_mode) end
		if opts.replay then om.crowbill_presentation_owner:reapply(identity, opts.owner_mode) end
		if opts.drifted then weapon.rotation = { q = "drifted" } end
		local descriptor = { variant_key = IMPERIAL, right_hand_unit = model.right_hand_unit,
			fingerprint = "fp:719" }
		om._husk_identity_descriptor = function(unit, slot_name, base)
			if unit == husk and slot_name == SLOT and base == family.SOURCE_ITEM then
				if opts.remote_state then return nil, opts.remote_state end
				return descriptor, "exact"
			end
			return nil, "none"
		end

		local owner_item = { backend_id = "imperial-719", cwv_key = IMPERIAL,
			name = family.SOURCE_ITEM }
		local owner_inv = { _equipment = { slots = { [SLOT] = { item_data = owner_item } } } }
		function owner_inv:equipment() return self._equipment end
		local owner_unit = { alive = true, inventory = owner_inv }
		om._cwv_identity_payloads = function(slots)
			local item_data = slots[SLOT] and slots[SLOT].item_data
			return { { slot = SLOT, fingerprint = "fp:owner",
				item_key = opts.collapsed and family.SOURCE_ITEM or item_data.cwv_key } }
		end

		local players = {}
		if not opts.no_remote then
			players[#players + 1] = { remote = true, peer_id = "peer-host", player_unit = husk }
		end
		if not opts.no_owner then
			players[#players + 1] = { peer_id = "peer-local", player_unit = owner_unit }
		end
		local env = {
			Managers = { player = { human_players = function() return players end } },
			Unit = {
				alive = function(unit) return type(unit) == "table" and unit.alive == true end,
				local_rotation = function(unit) return unit.rotation end,
				is_a = function(unit, name) return unit.resource == name end,
			},
			ScriptUnit = { has_extension = function(unit) return unit.inventory end },
			Quaternion = opts.unread and {} or { dot = function(a, b) return same(a, b) and 1 or 0 end },
			Weapons = { [family.SOURCE_TEMPLATE] = { id = "one_handed_crowbill" } },
			printf = function(fmt, ...) lines[#lines + 1] = string.format(fmt, ...) end,
		}
		local check = assert(loadfile(mod_root .. "_cwv_issue719_transaction_check.lua"))()(
			nil, { om = om, env = env })
		local err = check(descriptor, family, model, "es_mercenary")
		return err, table.concat(lines, "\n")
	end

	H.test("#719 live check passes both peers on the authored model and face", function()
		local err, log = check_world({ owner_mode = policy.MODE_PICK })
		H.equal(err, nil)
		H.truthy(log:find("role=observer peer=peer-host verdict=ok " .. IMPERIAL, 1, true), log)
		H.truthy(log:find("rotation=retained", 1, true), log)
		H.truthy(log:find("role=owner peer=peer-local verdict=ok " .. IMPERIAL
			.. " publishes exact identity", 1, true), log)
	end)

	H.test("#719 live check fails an observer whose remote Crowbill slot was destroyed", function()
		local err = check_world({ destroyed = true })
		H.truthy(type(err) == "string" and err:find("lost the remote " .. IMPERIAL .. " slot", 1, true), err)
	end)

	H.test("#719 live check fails an observer rendering Sienna's donor", function()
		local err = check_world({ resource = family.PLACEHOLDER_UNIT .. "_3p" })
		H.truthy(type(err) == "string" and err:find("Sienna's donor", 1, true), err)
	end)

	H.test("#719 live check accepts a replayed hammer face on the observer", function()
		local err, log = check_world({ owner_mode = policy.MODE_HAMMER, replay = true })
		H.equal(err, nil, log)
		H.truthy(log:find("mode=hammer rotation=retained", 1, true), log)
	end)

	H.test("#719 live check fails a stale face, a lost rotation and a missing presentation", function()
		-- The owner chose hammer but nothing re-applied the observer's unit.
		local err = check_world({ owner_mode = policy.MODE_HAMMER })
		H.truthy(type(err) == "string"
			and err:find("shows the pick face while its owner chose hammer", 1, true), err)
		err = check_world({ drifted = true })
		H.truthy(type(err) == "string" and err:find("rotation after the presentation write", 1, true), err)
		err = check_world({ no_presentation = true })
		H.truthy(type(err) == "string" and err:find("without the husk pick/hammer presentation", 1, true), err)
	end)

	H.test("#719 live check fails an owner whose Crowbill collapses to the donor on the wire", function()
		local err = check_world({ no_remote = true, collapsed = true })
		H.truthy(type(err) == "string" and err:find("does not publish exact identity", 1, true), err)
	end)

	local function is_skip(err, needle)
		return type(err) == "string" and err:sub(1, 5) == "skip:"
			and err:find(needle, 1, true) ~= nil
	end

	H.test("#719 live check SKIPs, never PASSes, when no peer holds a Crowbill", function()
		local err, log = check_world({ no_remote = true, no_owner = true })
		H.truthy(is_skip(err, "reason=no_crowbill_peer"), tostring(err))
		H.truthy(log:find("SKIP reason=no_crowbill_peer", 1, true), log)
	end)

	H.test("#719 live check SKIPs a remote vanilla Crowbill base without exact identity", function()
		for _, state in ipairs({ "none", "unavailable" }) do
			local err = check_world({ no_owner = true, remote_state = state })
			H.truthy(is_skip(err, "role=observer peer=peer-host bw_1h_crowbill held with identity state="
				.. state), tostring(err))
		end
		-- A sender-proven native slot is not a CWV Crowbill holder at all.
		local err = check_world({ no_owner = true, remote_state = "native" })
		H.truthy(is_skip(err, "reason=no_crowbill_peer"), tostring(err))
	end)

	H.test("#719 live check SKIPs an observer leg it could not finish", function()
		local err = check_world({ no_owner = true, not_wielded = true })
		H.truthy(is_skip(err, IMPERIAL .. " held, not wielded"), tostring(err))
		err = check_world({ no_owner = true, owner_mode = policy.MODE_PICK, unread = true })
		H.truthy(is_skip(err, "rotation=unread"), tostring(err))
	end)

	H.test("#719 live check PASSes the owner leg alone and never lets it hide an unproven observer", function()
		H.equal(check_world({ no_remote = true }), nil)
		local err = check_world({ remote_state = "none" })
		H.truthy(is_skip(err, "identity state=none"), tostring(err))
	end)
end
