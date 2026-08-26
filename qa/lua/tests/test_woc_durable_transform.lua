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

	H.test("WOC #613 production tracking policy separates event previews from gameplay polling", function()
		for _, surface in ipairs({
			"owner-spawn", "husk-spawn", "character-preview", "item-preview",
			"cim-preview", "lobby-preview", "score-preview",
		}) do
			H.equal(module.should_track_surface(surface), true, surface)
		end
		H.equal(module.should_track_surface("unknown-preview"), false)
		H.equal(module.should_poll_record({ surface = "owner-spawn" }), true)
		H.equal(module.should_poll_record({ surface = "husk-spawn" }), true)
		for _, surface in ipairs({
			"character-preview", "item-preview", "cim-preview",
			"lobby-preview", "score-preview",
		}) do
			H.equal(module.should_poll_record({ surface = surface }), false, surface)
		end
		H.equal(module.should_poll_record(nil), false)
	end)

	local function fixture(surface, should_yield, track_preview)
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
				H.deep_equal(value, { -180, -90, -90 })
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
					or track_preview == true
			end,
			should_poll = function(record)
				return record.surface == "owner-spawn"
					or record.surface == "husk-spawn"
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
		H.deep_equal(target.apply_spec.rotation, { -180, -90, -90 })
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

	H.test("WOC #712 audit exposes retained state and tuner ownership without writing", function()
		local owner, unit, _, _, _, writes = fixture("owner-spawn", true)
		H.equal(owner:apply(unit, transform_spec(), "3p", "owner-spawn"), true)
		local before = writes()
		local report = owner:audit(1)
		H.equal(writes(), before)
		H.equal(report.live, 1)
		H.equal(report.truncated, 0)
		H.equal(#report.rows, 1)
		H.equal(report.rows[1].retained, true)
		H.equal(report.rows[1].tuner_claims, true)
		H.equal(report.rows[1].surface, "owner-spawn")
		H.equal(report.rows[1].perspective, "3p")
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

	H.test("WOC #613 polls husks but retains preview targets for event replay", function()
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
			fixture("character-preview", false, true)
		H.truthy(preview:apply(preview_unit, transform_spec(), "3p", "character-preview"))
		preview_stomp()
		applied, tracked = preview:step()
		H.equal(applied, 0)
		H.equal(tracked, 1)
		H.equal(preview_writes(), 1)
		local retained, reason = preview:reapply(
			preview_unit, "preview-post-animation:trigger_pose_animation")
		H.truthy(retained)
		H.equal(reason, "retained")
		H.equal(preview_writes(), 2)
		H.equal(preview:forget(preview_unit), true)
		H.equal(preview:count(), 0)
		H.equal(preview:reapply(preview_unit, "late-edge"), false)
	end)

	H.test("WOC #613 event reapply contains rejected throwing and lying adapters", function()
		local unit, mode, read_throws = {}, "retain", false
		local state = {
			position = { 1, 2, 3 }, scale = { 1, 1, 1 },
			rotation = { 0, 0, 0, 1 },
		}
		local expected_rotation = { 0.5, -0.5, -0.5, 0.5 }
		local function copy_state()
			if read_throws then error("planted read failure") end
			return {
				position = copy(state.position), scale = copy(state.scale),
				rotation = { state.rotation[1], state.rotation[2],
					state.rotation[3], state.rotation[4] },
			}
		end
		local owner = module.new({
			alive = function(value) return value == unit end,
			read = function() return copy_state() end,
			rotation_components = function() return expected_rotation end,
			apply = function(_, spec)
				if mode == "throw" then error("planted apply failure") end
				if mode == "reject" then return false, { ok = false } end
				if mode == "retain" then
					state.position = copy(spec.position)
					state.scale = copy(spec.scale)
					state.rotation = { expected_rotation[1], expected_rotation[2],
						expected_rotation[3], expected_rotation[4] }
				end
				return true, { ok = true }
			end,
			should_track = function() return true end,
			diagnostic = function() error("planted diagnostic failure") end,
		})
		H.truthy(owner:apply(unit, transform_spec(), "3p", "lobby-preview"))

		state.position = { 9, 9, 9 }
		mode = "reject"
		local retained, reason = owner:reapply(unit, "rejected")
		H.equal(retained, false)
		H.equal(reason, "apply-rejected")

		mode = "throw"
		retained, reason = owner:reapply(unit, "throwing")
		H.equal(retained, false)
		H.equal(reason, "apply-error")

		mode = "lie"
		retained, reason = owner:reapply(unit, "lying-setter")
		H.equal(retained, false)
		H.equal(reason, "readback-mismatch")

		mode, read_throws = "retain", true
		retained, reason = owner:reapply(unit, "throwing-reader")
		H.equal(retained, false)
		H.equal(reason, "readback-unavailable")
		H.equal(owner:count(), 1,
			"contained adapter failures must not orphan the durable record")
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
			position = { 0, 0, -0.3 }, rotation = { -180, -90, -90 },
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

	H.test("WOC #712/#835 raw callable-table constructor reaches atomic pose", function()
		local lib = dofile(lib_path)
		local globals, pose_writes = retail_fakes()
		local wa = lib.new({
			unit = globals.Unit, vector_new = globals.Vector3,
			vector_to_elements = globals.Vector3.to_elements,
			quaternion = globals.Quaternion, matrix4x4 = globals.Matrix4x4,
		})
		local ok, report = wa.apply({}, {
			node = 2, scale = { 0.9, 0.9, 0.9 },
			position = { 0, 0, -0.3 }, rotation = { -180, -90, -90 },
		})
		H.equal(ok, true)
		H.equal(report.transform_mode, "atomic-local-pose")
		H.equal(#pose_writes, 1)
		H.equal(pose_writes[1].node, 2)
	end)

	H.test("WOC #712/#613/#278 production wiring pins", function()
		local path = repo_root
			.. "/weapons_of_chaos/scripts/mods/weapons_of_chaos/weapons_of_chaos.lua"
		local file = assert(io.open(path, "rb"))
		local source = file:read("*a")
		file:close()
		local registration_path = repo_root
			.. "/weapons_of_chaos/scripts/mods/weapons_of_chaos/_woc_relic_registration_owner.lua"
		local registration_file = assert(io.open(registration_path, "rb"))
		local registration = registration_file:read("*a")
		registration_file:close()
		local preview_owner_path = repo_root
			.. "/weapons_of_chaos/scripts/mods/weapons_of_chaos/_woc_issue613_preview_owner.lua"
		local preview_owner_file = assert(io.open(preview_owner_path, "rb"))
		local preview_owner = preview_owner_file:read("*a")
		preview_owner_file:close()
		H.truthy(source:find("_appearance_lib.new(_appearance.appearance_api(_G))", 1, true))
		H.equal(source:find("_appearance_lib.new()", 1, true), nil)
		H.truthy(source:find("expects_first_person_unit(owner_unit_1p)", 1, true))
		H.truthy(source:find("not-expected vanilla-3p-only gear_utils.lua:276", 1, true))
		H.truthy(source:find("_log_skip_caller(item, slot_name)", 1, true))
		H.truthy(source:find("[WOC:278] skip caller item=%s slot=%s frames=%s", 1, true))
		H.truthy(source:find('mod:command("woc_pose_audit"', 1, true))
		H.truthy(source:find("if ok and value ~= nil then return value end", 1, true))
		H.equal(source:find("return ok and value ~= nil and value or fallback", 1, true), nil)
		H.truthy(preview_owner:find("transform.rotation[1] ~= -180", 1, true))
		H.truthy(preview_owner:find("transform_1p.scale[1] ~= 0.8", 1, true))
		H.truthy(registration:find("_moveset.item_has_trait(live, _moveset.POISON_TRAIT)", 1, true))
		H.truthy(registration:find("live.properties[_moveset.CRIT_PROPERTY] == 1", 1, true))
		H.equal(registration:find("_moveset.item_has_trait(entry, _moveset.POISON_TRAIT)",
			1, true), nil)
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

	-- ============ issue 712 tuner: retarget from stored baselines ============

	H.test("WOC #712 retarget rebuilds from stored baselines with per-perspective scale", function()
		local unit_3p, unit_1p = { "u3" }, { "u1" }
		local states = {
			[unit_3p] = { position = { 1, 1, 1 }, scale = { 100, 100, 100 },
				rotation = { 0.7071, 0, 0, -0.7071 } },
			[unit_1p] = { position = { 2, 2, 2 }, scale = { 100, 100, 100 },
				rotation = { 0.7071, 0, 0, -0.7071 } },
		}
		local function copy3(v) return { v[1], v[2], v[3] } end
		local rotation_q = { 0, 0.7071, 0, -0.7071 }
		local events = {}
		local owner = module.new({
			alive = function(u) return states[u] ~= nil end,
			read = function(u)
				local s = states[u]
				return { position = copy3(s.position), scale = copy3(s.scale),
					rotation = { s.rotation[1], s.rotation[2], s.rotation[3], s.rotation[4] } }
			end,
			rotation_components = function() return { rotation_q[1], rotation_q[2],
				rotation_q[3], rotation_q[4] } end,
			apply = function(u, spec)
				local s = states[u]
				s.position = copy3(spec.position)
				s.scale = copy3(spec.scale)
				s.rotation = { rotation_q[1], rotation_q[2], rotation_q[3], rotation_q[4] }
				return true, { ok = true }
			end,
			should_track = function() return true end,
			diagnostic = function(kind) events[#events + 1] = kind end,
		})
		local spec = { node = 2, scale = { 0.9, 0.9, 0.9 }, offset = { 0, 0, -0.3 },
			rotation = { -180, -90, -90 } }
		H.equal(owner:apply(unit_3p, spec, "3p", "owner-spawn"), true)
		local spec_1p = { node = 2, scale = { 0.8, 0.8, 0.8 }, offset = spec.offset,
			rotation = spec.rotation }
		H.equal(owner:apply(unit_1p, spec_1p, "1p", "owner-spawn"), true)
		H.deep_equal(states[unit_3p].scale, { 90, 90, 90 })
		H.deep_equal(states[unit_1p].scale, { 80, 80, 80 })

		-- Retarget with new values: 3P scale 0.7, 1P scale 0.6, new offset.
		-- Both units must resolve from their STORED baselines (positions 1,1,1
		-- and 2,2,2 plus the new offset - never compounding the old -0.3).
		local retargeted, live = owner:retarget({
			scale = { 0.7, 0.7, 0.7 },
			scale_1p = { 0.6, 0.6, 0.6 },
			offset = { 0, 0, -0.5 },
			rotation = { -180, -90, -90 },
		})
		H.equal(retargeted, 2)
		H.equal(live, 2)
		H.deep_equal(states[unit_3p].scale, { 70, 70, 70 })
		H.deep_equal(states[unit_1p].scale, { 60, 60, 60 })
		H.deep_equal(states[unit_3p].position, { 1, 1, 0.5 })
		H.deep_equal(states[unit_1p].position, { 2, 2, 1.5 })
		H.equal(events[#events], "retargeted")

		-- Dead units prune instead of counting as live.
		states[unit_1p] = nil
		local retargeted2, live2 = owner:retarget({
			scale = { 0.9, 0.9, 0.9 },
			offset = { 0, 0, -0.3 },
			rotation = { -180, -90, -90 },
		})
		H.equal(retargeted2, 1)
		H.equal(live2, 1)
	end)
end
