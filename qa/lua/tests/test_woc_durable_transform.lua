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
		local target = module.resolve({ position = { 1, 2, 3 } }, transform_spec(),
			{ 0.5, -0.5, -0.5, 0.5 })
		H.deep_equal(target.position, { 1, 2, 2.7 })
		H.deep_equal(target.scale, { 0.9, 0.9, 0.9 })
		H.deep_equal(target.apply_spec.rotation, { -90, -90, -90 })
		H.equal(target.node, 2)
		H.equal(target.apply_spec.node, 2)
		H.equal(module.CONTRACT.attachment_node, 0)
		H.equal(module.CONTRACT.target_node, "authored_render_node")
		H.equal(module.CONTRACT.target_node_name, policy.TRANSFORM_NODE_NAME)
		H.equal(module.CONTRACT.position, "render_baseline_plus_offset")
		H.equal(module.CONTRACT.scale, "absolute")
		H.equal(module.CONTRACT.rotation, "absolute_euler_xyz")
		H.equal(module.CONTRACT.write_mode, "atomic_local_pose")
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
end
