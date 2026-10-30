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
	local function check_fixture(opts)
		opts = opts or {}
		local lines = {}
		local stats = { owner = 0, observer = 0 }
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
		local descriptor = { variant_key = IMPERIAL, right_hand_unit = opts.hand_unit or model.right_hand_unit,
			fingerprint = "fp:719" }
		om._husk_identity_descriptor = function(unit, slot_name, base)
			if unit == husk and slot_name == SLOT and base == family.SOURCE_ITEM then
				stats.observer = stats.observer + 1
				if opts.remote_state then return nil, opts.remote_state end
				return descriptor, "exact"
			end
			return nil, "none"
		end
		if opts.evidence_name ~= nil then
			om._husk_observed_unit_evidence = function() return opts.evidence_name end
		end
		if opts.display_mode ~= nil then
			local record = om.crowbill_presentation_owner.record
			om.crowbill_presentation_owner.record = function(self, observed_weapon)
				local row = record(self, observed_weapon)
				if row then row.mode = opts.display_mode end
				return row
			end
		end

		local owner_item = { backend_id = "imperial-719", cwv_key = IMPERIAL,
			name = family.SOURCE_ITEM }
		local owner_inv = { _equipment = { slots = { [SLOT] = { item_data = owner_item } } } }
		function owner_inv:equipment() return self._equipment end
		local owner_unit = { alive = true, inventory = owner_inv }
		om._cwv_identity_payloads = function(slots)
			stats.owner = stats.owner + 1
			local item_data = slots[SLOT] and slots[SLOT].item_data
			return { { slot = SLOT, fingerprint = "fp:owner",
				item_key = opts.collapsed and family.SOURCE_ITEM or item_data.cwv_key } }
		end

		local remote_player = { remote = true, peer_id = "peer-host", player_unit = husk }
		local owner_player = { peer_id = "peer-local", player_unit = owner_unit }
		local players = {}
		if not opts.no_remote then
			players[#players + 1] = remote_player
		end
		if not opts.no_owner then
			players[#players + 1] = owner_player
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
		local fixture = { players = players, owner_player = owner_player, remote_player = remote_player,
			lines = lines, stats = stats, om = om, env = env, descriptor = descriptor }
		function fixture.invoke() return check(descriptor, family, model, "es_mercenary") end
		function fixture.run()
			for index = #lines, 1, -1 do lines[index] = nil end
			stats.owner, stats.observer = 0, 0
			local err = fixture.invoke()
			return err, table.concat(lines, "\n")
		end
		return fixture
	end
	local function check_world(opts)
		return check_fixture(opts).run()
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

	local function roster(f, count, kind, keyed)
		for key in pairs(f.players) do f.players[key] = nil end
		local original = kind == "observer" and f.remote_player or f.owner_player
		for index = 1, count do
			local player = {}
			for key, value in pairs(original) do player[key] = value end
			player.peer_id = "budget-peer-" .. index
			f.players[keyed and ("entry-" .. index) or index] = player
		end
	end
	local function bounded(f, err)
		H.truthy(err == nil or (type(err) == "string" and #err <= 2048), "#719 result exceeds 2048 bytes")
		if err then H.equal(err:find("[^ -~]"), nil, "#719 result must be printable ASCII") end
		H.truthy(#f.lines <= 33, "#719 emits at most 33 lines per invocation")
		local bytes = 0
		for _, line in ipairs(f.lines) do
			H.truthy(#line <= 768, "#719 sink line exceeds 768 bytes")
			H.equal(line:find("[^ -~]"), nil, "#719 sink must be printable ASCII")
			bytes = bytes + #line
		end
		H.truthy(bytes <= 25344, "#719 formatted sink budget exceeds 25344 bytes")
	end

	H.test("#719 diagnostic roster budget is 32, not a four-player gameplay cap", function()
		for _, keyed in ipairs({ false, true }) do
			for _, count in ipairs({ 5, 32, 33 }) do
				local f = check_fixture({ no_remote = true })
				roster(f, count, "owner", keyed)
				local before = {}; for key, value in pairs(f.players) do before[key] = value end
				local err = f.run()
				if count <= 32 then H.equal(err, nil)
				else H.truthy(is_skip(err, "reason=diagnostic_budget"), "33 entries must SKIP, never PASS") end
				H.equal(f.stats.owner, math.min(count, 32), "only 32 roster entries may be observed")
				for key, value in pairs(before) do H.equal(rawequal(rawget(f.players, key), value), true) end
				for key, value in pairs(f.players) do H.equal(rawequal(rawget(before, key), value), true) end
				bounded(f, err)
			end
		end
	end)

	H.test("#719 malformed and dead roster entries spend the diagnostic budget", function()
		for _, keyed in ipairs({ false, true }) do
			local f = check_fixture({ no_remote = true })
			for key in pairs(f.players) do f.players[key] = nil end
			for index = 1, 33 do
				local value
				if index % 2 == 0 then value = false
				else value = { peer_id = "dead", player_unit = { alive = false } } end
				f.players[keyed and ("dead-" .. index) or index] = value
			end
			local err = f.run()
			H.truthy(is_skip(err, "reason=diagnostic_budget"), "dead entries cannot evade the scan cap")
			H.equal(f.stats.owner + f.stats.observer, 0)
			bounded(f, err)
			f.players[keyed and "one-holder" or 34] = f.owner_player
			err = f.run()
			H.truthy(is_skip(err, "reason=diagnostic_budget"), "a partial roster can never PASS")
			bounded(f, err)
		end
	end)

	H.test("#719 lossy fields SKIP, but huge and opaque genuine failures still FAIL safely", function()
		local huge = string.rep("x", 4096) .. "\n%\000\255"
		local f = check_fixture({ no_remote = true })
		f.owner_player.peer_id = huge
		local err = f.run()
		H.truthy(is_skip(err, "reason=diagnostic_text_budget"), "lossy peer evidence cannot PASS")
		bounded(f, err)
		f = check_fixture({ no_owner = true, remote_state = huge })
		err = f.run(); H.truthy(is_skip(err, "reason=diagnostic_text_budget")); bounded(f, err)
		local stringifications = 0
		local opaque = setmetatable({}, { __tostring = function()
			stringifications = stringifications + 1; error("complex diagnostic tostring ran")
		end })
		f = check_fixture({ no_owner = true, remote_state = opaque })
		err = f.run(); H.truthy(is_skip(err, "reason=diagnostic_text_budget")); bounded(f, err)
		for _, fingerprint in ipairs({ huge, opaque }) do
			f = check_fixture({ no_remote = true }); f.descriptor.fingerprint = fingerprint
			err = f.run(); H.truthy(is_skip(err, "reason=diagnostic_text_budget")); bounded(f, err)
		end
		for _, mode in ipairs({ huge, opaque }) do
			f = check_fixture({ no_owner = true, display_mode = mode })
			err = f.run()
			H.truthy(type(err) == "string" and not is_skip(err, "")
				and err:find("face while its owner chose", 1, true), "a genuine mode mismatch remains FAIL")
			bounded(f, err)
		end
		f = check_fixture({ no_owner = true, evidence_name = "bad\000%\255unit" })
		err = f.run()
		H.truthy(type(err) == "string" and err:find("#719 observer renders ", 1, true) == 1)
		bounded(f, err)
		H.equal(stringifications, 0, "complex fields must never invoke __tostring")
		f = check_fixture({ no_owner = true })
		f.om._husk_identity_descriptor = function() error(opaque, 0) end
		local ok, failure = pcall(f.run)
		H.equal(ok, false); H.equal(rawequal(failure, opaque), true,
			"an uncaught live-leg error must retain its raw shape")
		H.equal(stringifications, 0)
	end)

	H.test("#719 model comparisons use raw fields, never equal clipped prefixes", function()
		local prefix = string.rep("a", 200)
		local f = check_fixture({ no_owner = true, hand_unit = prefix .. "expected",
			evidence_name = prefix .. "observed_3p" })
		local err = f.run()
		H.truthy(type(err) == "string" and not is_skip(err, "")
			and err:find("#719 observer renders ", 1, true) == 1, "raw model mismatch must remain FAIL")
		bounded(f, err)
	end)

	H.test("#719 a real observer FAIL wins before the roster budget ends", function()
		local f = check_fixture({ no_owner = true, destroyed = true })
		roster(f, 33, "observer", true) -- every possible first entry has the real defect
		for _, player in pairs(f.players) do player.peer_id = string.rep("p", 200) end
		local err = f.run()
		H.truthy(type(err) == "string" and err:find("lost the remote " .. IMPERIAL .. " slot", 1, true),
			"lossy diagnostics and an oversized roster cannot suppress an encountered FAIL")
		H.equal(f.stats.observer, 1)
		bounded(f, err)
	end)

	H.test("#719 bounded unproven samples cannot hide incomplete observer legs", function()
		local f = check_fixture({ not_wielded = true })
		roster(f, 31, "observer", true)
		f.players.owner = f.owner_player
		local err = f.run()
		H.truthy(is_skip(err, "unproven=31"), "omitted observer samples must still SKIP")
		H.truthy(tonumber(err:match(" omitted=(%d+)")) > 0, "fixture must exhaust the sample budget")
		H.equal(f.stats.owner, 1); H.equal(f.stats.observer, 31)
		bounded(f, err)
	end)

	H.test("#719 budgets reset on the same callback and stay separate during reentry", function()
		local f = check_fixture({ no_remote = true })
		roster(f, 33, "owner", true)
		local first = f.run()
		H.truthy(is_skip(first, "reason=diagnostic_budget"))
		H.equal(f.run(), first, "same callback repeats the honest budget verdict")
		roster(f, 1, "owner", false)
		H.equal(f.run(), nil, "a prior depleted budget must not survive the invocation")
		f.players[1] = f.owner_player
		f.owner_player.peer_id = string.rep("outer", 100)
		local plan, entered, inner_err = f.om._cwv_identity_payloads, false, "not-called"
		f.om._cwv_identity_payloads = function(slots)
			if not entered then
				entered = true
				local outer = f.owner_player.peer_id
				f.owner_player.peer_id = "inner"
				inner_err = f.invoke() -- SAME actual child closure; no test reset between invocations
				f.owner_player.peer_id = outer
			end
			return plan(slots)
		end
		local err = f.run()
		H.equal(inner_err, nil, "outer lossy state must not leak into reentrant invocation")
		H.truthy(is_skip(err, "reason=diagnostic_text_budget"), "inner success cannot clear outer loss")
		bounded(f, err)
	end)

	H.test("#719 missing or throwing evidence sinks cannot produce PASS and can recover", function()
		local f = check_fixture({ no_remote = true })
		roster(f, 32, "owner", true)
		local healthy = f.env.printf
		f.env.printf = false -- explicit ctx.env value, never fall through to a host/global logger
		local err = f.run()
		H.truthy(is_skip(err, "reason=diagnostic_text_budget"), "missing sink must SKIP a completed proof")
		H.equal(f.stats.owner, 32, "missing evidence must not suppress actual holder checks")
		H.equal(#f.lines, 0)
		bounded(f, err)
		f.env.printf = healthy
		H.equal(f.run(), nil, "same closure can PASS after the evidence sink is restored")
		H.equal(f.stats.owner, 32); H.equal(#f.lines, 32); bounded(f, nil)

		local attempts, stringifications = {}, 0
		local opaque = setmetatable({}, { __tostring = function()
			stringifications = stringifications + 1; error("opaque sink error stringified")
		end })
		local function throwing(fmt, ...)
			attempts[#attempts + 1] = string.format(fmt, ...)
			error(opaque, 0)
		end
		f.env.printf = throwing
		err = f.run()
		H.truthy(is_skip(err, "reason=diagnostic_text_budget"), "throwing sink must SKIP a completed proof")
		H.equal(f.stats.owner, 32, "throwing evidence must not suppress actual holder checks")
		H.equal(#attempts, 33, "32 holder attempts plus one bounded terminal attempt")
		H.equal(#f.lines, 0)
		bounded({ lines = attempts }, err) -- guards bytes/ASCII for EVERY attempted sink call
		H.equal(stringifications, 0, "sink error objects must never invoke __tostring")
		f.env.printf = healthy
		H.equal(f.run(), nil, "same closure must recover after an opaque sink error")
		H.equal(f.stats.owner, 32); H.equal(#f.lines, 32); bounded(f, nil)
		H.equal(#attempts, 33, "restored sink must replace, not retain, the throwing closure")

		for _, sink in ipairs({ false, throwing }) do
			attempts = {}
			local broken = check_fixture({ no_owner = true, destroyed = true })
			broken.env.printf = sink
			err = broken.run()
			H.truthy(type(err) == "string" and not is_skip(err, "")
				and err:find("lost the remote " .. IMPERIAL .. " slot", 1, true),
				"a genuine observer FAIL must outrank a missing/throwing evidence sink")
			H.equal(broken.stats.observer, 1)
			bounded(broken, err); bounded({ lines = attempts }, err)
		end
		H.equal(stringifications, 0)
	end)

	H.test("#719 actual display projection handles every byte with an independent numeric oracle", function()
		local f = check_fixture({ no_remote = true })
		for byte = 0, 255 do
			f.owner_player.peer_id = "peer-" .. string.char(byte) .. "-end"
			local err = f.run()
			if byte >= 32 and byte <= 126 then
				H.equal(err, nil, "printable byte must retain complete evidence")
			else
				H.truthy(is_skip(err, "reason=diagnostic_text_budget"),
					"nonprintable byte must require SKIP")
			end
			H.equal(f.stats.owner, 1, "every byte reaches the actual owner leg")
			bounded(f, err)
			for _, line in ipairs(f.lines) do
				for index = 1, #line do
					local actual = line:byte(index)
					H.truthy(actual >= 32 and actual <= 126,
						"actual projected byte must be printable ASCII")
				end
			end
		end
	end)
end
