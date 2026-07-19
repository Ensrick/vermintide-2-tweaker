return function(H, repo_root)
	local module = dofile(repo_root
		.. "/weapons_of_chaos/scripts/mods/weapons_of_chaos/_woc_durable_transform.lua")
	local policy = dofile(repo_root
		.. "/weapons_of_chaos/scripts/mods/weapons_of_chaos/_woc_appearance_policy.lua")

	local function copy(value)
		local out = {}
		for i = 1, #value do out[i] = value[i] end
		return out
	end
	local function transform_spec()
		return {
			node = 2,
			scale = policy.TRANSFORM.scale,
			offset = policy.TRANSFORM.offset,
			rotation = policy.TRANSFORM.rotation,
		}
	end

	local function fixture(surface, should_yield)
		local unit = {}
		local live = true
		local writes, events = 0, {}
		local base = {
			position = { 1, 2, 3 },
			scale = { 1, 1, 1 },
			rotation = { 0, 0, 0, 1 },
		}
		local state = {
			position = copy(base.position),
			scale = copy(base.scale),
			rotation = copy(base.rotation),
		}
		local expected_rotation = { 0.5, -0.5, -0.5, 0.5 }
		local owner = module.new({
			alive = function(value) return value == unit and live end,
			read = function(_, node)
				H.equal(node, 2)
				return {
					position = copy(state.position), scale = copy(state.scale),
					rotation = copy(state.rotation),
				}
			end,
			rotation_components = function(value)
				H.deep_equal(value, { -90, -90, -90 })
				return copy(expected_rotation)
			end,
			apply = function(_, spec)
				H.equal(spec.node, 2)
				writes = writes + 1
				state.position = copy(spec.position)
				state.scale = copy(spec.scale)
				state.rotation = copy(expected_rotation)
				return true, {
					ok = true, transform_mode = "atomic-local-pose",
					channels = { scale = true, position = true, rotation = true },
				}
			end,
			should_track = function(value)
				return value == "owner-spawn" or value == "husk-spawn"
			end,
			should_yield = function() return should_yield == true end,
			diagnostic = function(kind) events[#events + 1] = kind end,
		})
		local function stomp()
			state.position = copy(base.position)
			state.scale = copy(base.scale)
			state.rotation = copy(base.rotation)
		end
		return owner, unit, state, base, stomp, function() return writes end,
			events, function() live = false end, surface or "owner-spawn"
	end

	H.test("WOC #712 resolves the exact canonical authored-render-node pose", function()
		-- Retail 0.1.33 proof captured native scale {100,100,100} on the
		-- named visible node. The authored 0.9 value means 10% smaller, so the
		-- absolute pose passed to WeaponAppearance must be {90,90,90}; writing
		-- {0.9,0.9,0.9} made the model effectively invisible.
		local target = module.resolve({
			position = { 1, 2, 3 }, scale = { 100, 100, 100 },
		}, transform_spec(),
			{ 0.5, -0.5, -0.5, 0.5 })
		H.deep_equal(target.position, { 1, 2, 2.7 })
		H.deep_equal(target.scale, { 90, 90, 90 })
		H.deep_equal(target.apply_spec.scale, { 90, 90, 90 })
		H.deep_equal(target.apply_spec.rotation, { -90, -90, -90 })
		H.equal(target.node, 2)
		H.equal(target.apply_spec.node, 2)
		H.equal(module.CONTRACT.attachment_node, 0)
		H.equal(module.CONTRACT.target_node, "authored_render_node")
		H.equal(module.CONTRACT.target_node_name, policy.TRANSFORM_NODE_NAME)
		H.equal(module.CONTRACT.position, "render_baseline_plus_offset")
		H.equal(module.CONTRACT.scale, "render_baseline_multiplier")
		H.equal(module.CONTRACT.rotation, "absolute_euler_xyz")
		H.equal(module.CONTRACT.write_mode, "atomic_local_pose")
	end)

	H.test("WOC #712 scale multiplier preserves nonuniform authored baselines", function()
		local target = module.resolve({
			position = { 0, 0, 0 }, scale = { 100, 50, 25 },
		}, {
			node = 2,
			scale = { 0.9, 0.8, 0.4 },
			offset = { 0, 0, 0 },
			rotation = { 0, 0, 0 },
		}, { 0, 0, 0, 1 })
		H.deep_equal(target.scale, { 90, 40, 10 })
		H.deep_equal(target.apply_spec.scale, { 90, 40, 10 })
	end)

	H.test("WOC #712 fails closed without a captured native render scale", function()
		H.equal(module.resolve({ position = { 0, 0, 0 } }, transform_spec(),
			{ 0, 0, 0, 1 }), nil)
	end)

	H.test("WOC #613 tracks only positively identified gameplay spawns", function()
		H.equal(module.classify_surface({}, {}), "owner-spawn")
		H.equal(module.classify_surface(nil, {}), "husk-spawn")
		H.equal(module.classify_surface(nil, nil), "preview-spawn")
	end)

	H.test("WOC #613 preserves one-shot tuner poses with live apply off", function()
		local values = {
			wt_dev_hp_enabled = true,
			wt_dev_hp_live_apply = false,
			wt_dev_hp_target_slot = "slot_melee",
			wt_dev_hp_enable_3p = true,
			wt_dev_hp_rh_offset_z = -0.2,
		}
		local function setting(key, fallback)
			local value = values[key]
			return value == nil and fallback or value
		end
		H.equal(module.dev_tuner_claims({
			surface = "owner-spawn", perspective = "3p",
		}, setting), true)
		values.wt_dev_hp_rh_offset_z = 0
		H.equal(module.dev_tuner_claims({
			surface = "owner-spawn", perspective = "3p",
		}, setting), false)
	end)

	H.test("WOC #613 repairs animation-stomped owner 1P and 3P poses", function()
		for _, perspective in ipairs({ "1p", "3p" }) do
			local owner, unit, state, _, stomp, writes, events = fixture()
			H.equal(owner:apply(unit, transform_spec(), perspective, "owner-spawn"), true)
			H.equal(owner:count(), 1)
			H.deep_equal(state.position, { 1, 2, 2.7 })
			local applied, tracked = owner:step()
			H.equal(applied, 0, perspective)
			H.equal(tracked, 1, perspective)
			H.equal(writes(), 1, perspective)
			stomp()
			applied, tracked = owner:step()
			H.equal(applied, 1, perspective)
			H.equal(tracked, 1, perspective)
			H.equal(writes(), 2, perspective)
			H.deep_equal(state.position, { 1, 2, 2.7 })
			H.deep_equal(state.scale, { 0.9, 0.9, 0.9 })
			H.equal(events[2], "next-frame-retained")
			H.equal(events[3], "drift-repaired")
		end
	end)

	H.test("WOC #613 tracks husks, prunes dead units, and leaves previews one-shot", function()
		local husk, unit, _, _, stomp, writes, _, kill = fixture("husk-spawn")
		H.truthy(husk:apply(unit, transform_spec(), "3p", "husk-spawn"))
		stomp()
		H.equal(husk:step(), 1)
		kill()
		local applied, tracked = husk:step()
		H.equal(applied, 0)
		H.equal(tracked, 0)
		H.equal(husk:count(), 0)

		local preview, preview_unit, _, _, preview_stomp, preview_writes =
			fixture("character-preview")
		H.truthy(preview:apply(preview_unit, transform_spec(), "3p", "character-preview"))
		preview_stomp()
		applied, tracked = preview:step()
		H.equal(applied, 0)
		H.equal(tracked, 0)
		H.equal(preview_writes(), 1)
	end)

	H.test("WOC #613 yields to an intentional live dev-tuner edit", function()
		local owner, unit, state, _, stomp, writes = fixture("owner-spawn", true)
		H.truthy(owner:apply(unit, transform_spec(), "3p", "owner-spawn"))
		stomp()
		state.position = { 8, 8, 8 }
		local applied, tracked = owner:step()
		H.equal(applied, 0)
		H.equal(tracked, 1)
		H.deep_equal(state.position, { 8, 8, 8 })
		H.equal(writes(), 1)
	end)

	H.test("WOC #613 quaternion comparison accepts equivalent negative signs", function()
		local target = {
			position = { 0, 0, -0.3 }, scale = { 0.9, 0.9, 0.9 },
			rotation = { 0.5, -0.5, -0.5, 0.5 },
		}
		local snapshot = {
			position = { 0, 0, -0.3 }, scale = { 0.9, 0.9, 0.9 },
			rotation = { -0.5, 0.5, 0.5, -0.5 },
		}
		H.equal(module.matches(snapshot, target), true)
	end)

	H.test("WOC #613 production diagnostics retain the shared write report", function()
		local path = repo_root
			.. "/weapons_of_chaos/scripts/mods/weapons_of_chaos/weapons_of_chaos.lua"
		local file = assert(io.open(path, "rb"))
		local source = file:read("*a")
		file:close()
		H.truthy(source:find("record.write_report", 1, true))
		H.truthy(source:find("mode=%s ok=%s node=%s error=%s scale=%s position=%s offset=%s rotation=%s",
			1, true))
	end)

	-- ================= issue 712: callable-table Vector3 constructor =================

	local lib_path = repo_root
		.. "/weapons_of_chaos/scripts/mods/weapons_of_chaos/_lib_weapon_appearance.lua"

	local function callable_vector3()
		return setmetatable({
			to_elements = function(v) return v[1], v[2], v[3] end,
		}, {
			__call = function(_, x, y, z) return { x, y, z, kind = "vec" } end,
		})
	end

	local function retail_fakes()
		local pose_writes = {}
		local unit_api = {
			alive = function() return true end,
			set_local_pose = function(unit, node, pose)
				pose_writes[#pose_writes + 1] = { unit = unit, node = node, pose = pose }
			end,
			local_position = function() return { 0, 0, 0, kind = "vec" } end,
			local_scale = function() return { 1, 1, 1, kind = "vec" } end,
			local_rotation = function() return { 0, 0, 0, 1, kind = "quat" } end,
		}
		local quaternion = {
			from_euler_angles_xyz = function(x, y, z)
				return { x, y, z, kind = "quat" }
			end,
		}
		local matrix4x4 = {
			from_quaternion_position_scale = function(rotation, position, scale)
				return { rotation = rotation, position = position, scale = scale }
			end,
		}
		return {
			Vector3 = callable_vector3(), Unit = unit_api,
			Quaternion = quaternion, Matrix4x4 = matrix4x4,
		}, pose_writes
	end

	H.test("WOC #712 appearance api wraps retail callable-table Vector3", function()
		H.equal(policy.appearance_api(nil), nil)
		H.equal(policy.appearance_api({}), nil)
		local globals = retail_fakes()
		local api = policy.appearance_api(globals)
		H.equal(type(api.vector_new), "function")
		local vec = api.vector_new(1, 2, 3)
		H.deep_equal({ vec[1], vec[2], vec[3] }, { 1, 2, 3 })
		H.equal(api.vector_to_elements, globals.Vector3.to_elements)
		local plain = policy.appearance_api({
			Vector3 = function(x, y, z) return { x, y, z } end,
		})
		H.equal(type(plain.vector_new), "function")
		H.equal(plain.vector_to_elements, nil)
	end)

	H.test("WOC #712 atomic pose lands through wrapped constructor", function()
		local lib = dofile(lib_path)
		local globals, pose_writes = retail_fakes()
		local wa = lib.new(policy.appearance_api(globals))
		local unit = {}
		local ok, report = wa.apply(unit, {
			node = 2, scale = { 0.9, 0.9, 0.9 },
			position = { 0, 0, -0.3 }, rotation = { -90, -90, -90 },
		})
		H.equal(ok, true)
		H.equal(report.transform_mode, "atomic-local-pose")
		H.equal(#pose_writes, 1)
		H.equal(pose_writes[1].node, 2)
		H.deep_equal({ pose_writes[1].pose.position[1], pose_writes[1].pose.position[2],
			pose_writes[1].pose.position[3] }, { 0, 0, -0.3 })
		H.deep_equal({ pose_writes[1].pose.scale[1], pose_writes[1].pose.scale[2],
			pose_writes[1].pose.scale[3] }, { 0.9, 0.9, 0.9 })
	end)

	H.test("WOC #712 raw callable-table constructor reproduces invalid-position", function()
		local lib = dofile(lib_path)
		local globals, pose_writes = retail_fakes()
		local wa = lib.new({
			unit = globals.Unit, vector_new = globals.Vector3,
			vector_to_elements = globals.Vector3.to_elements,
			quaternion = globals.Quaternion, matrix4x4 = globals.Matrix4x4,
		})
		local ok, report = wa.apply({}, {
			node = 2, scale = { 0.9, 0.9, 0.9 },
			position = { 0, 0, -0.3 }, rotation = { -90, -90, -90 },
		})
		H.equal(ok, false)
		H.equal(report.transform_error, "invalid-position")
		H.equal(#pose_writes, 0)
	end)

	H.test("WOC #712/#613/#278 production wiring pins", function()
		local path = repo_root
			.. "/weapons_of_chaos/scripts/mods/weapons_of_chaos/weapons_of_chaos.lua"
		local file = assert(io.open(path, "rb"))
		local source = file:read("*a")
		file:close()
		H.truthy(source:find("_appearance_lib.new(_appearance.appearance_api(_G))", 1, true))
		H.equal(source:find("_appearance_lib.new()", 1, true), nil)
		H.truthy(source:find("expects_first_person_unit(owner_unit_1p)", 1, true))
		H.truthy(source:find("not-expected vanilla-3p-only gear_utils.lua:276", 1, true))
		H.truthy(source:find("_log_skip_caller(item, slot_name)", 1, true))
		H.truthy(source:find("[WOC:278] skip caller item=%s slot=%s frames=%s", 1, true))
	end)

	H.test("WOC #613 husk spawns do not owe a first-person unit", function()
		H.equal(module.expects_first_person_unit({}), true)
		H.equal(module.expects_first_person_unit(nil), false)
	end)

	local wire = dofile(repo_root
		.. "/weapons_of_chaos/scripts/mods/weapons_of_chaos/_woc_wire_policy.lua")
	local SELF_MARKERS = { "weapons_of_chaos", "vmf/modules", "[C]" }

	H.test("WOC #278 caller frames filter plumbing and cap output", function()
		local trace = table.concat({
			"stack traceback:",
			"[string \"scripts/mods/weapons_of_chaos/weapons_of_chaos.lua\"]:1699",
			"[C]: in function 'pcall'",
			"[string \"scripts/helpers/loadout_utils.lua\"]:62",
			"[string \"scripts/managers/player/player_manager.lua\"]:400",
			"[string \"scripts/mods/gui_tweaker/gui_tweaker.lua\"]:99",
			"[string \"scripts/game_state/state_ingame.lua\"]:12",
		}, "\n")
		local frames = wire.caller_frames(trace, SELF_MARKERS, 3)
		H.equal(frames,
			"[string \"scripts/helpers/loadout_utils.lua\"]:62"
			.. " <- [string \"scripts/managers/player/player_manager.lua\"]:400"
			.. " <- [string \"scripts/mods/gui_tweaker/gui_tweaker.lua\"]:99")
	end)

	H.test("WOC #278 caller frames fail closed and retain fallback", function()
		local trace = "stack traceback:\n"
			.. "[string \"scripts/mods/weapons_of_chaos/weapons_of_chaos.lua\"]:10\n"
			.. "[string \"scripts/mods/vmf/modules/core/hooks.lua\"]:20"
		local frames = wire.caller_frames(trace, SELF_MARKERS, 3)
		H.truthy(frames:find("weapons_of_chaos.lua", 1, true))
		H.equal(wire.caller_frames(nil, SELF_MARKERS, 3), nil)
		H.equal(wire.caller_frames("", SELF_MARKERS, 3), nil)
		H.equal(wire.caller_frames("stack traceback:", SELF_MARKERS, 3), nil)
	end)
end
