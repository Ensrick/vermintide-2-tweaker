return function(H, repo_root)
	local module = dofile(repo_root
		.. "/character_weapon_variants/scripts/mods/character_weapon_variants/_cwv_durable_transform.lua")

	H.test("CWV durable transform owner reapplies live records and prunes dead units", function()
		local live, writes, after = {}, {}, {}
		local a, b = {}, {}
		live[a], live[b] = true, true
		local owner = module.new({
			alive = function(unit) return live[unit] == true end,
			apply = function(unit, spec)
				writes[#writes + 1] = { unit = unit, marker = spec.marker }
				return true
			end,
			after_all = function(applied, tracked)
				after[#after + 1] = { applied, tracked }
			end,
		})
		H.equal(owner:track(a, { marker = "dawi" }), true)
		H.equal(owner:track(b, { marker = "imperial" }), true)
		local applied, tracked = owner:step()
		H.equal(applied, 2)
		H.equal(tracked, 2)
		H.equal(#writes, 2)
		H.equal(#after, 1)
		H.equal(after[1][1], 2)
		H.equal(after[1][2], 2)

		live[a] = false
		applied, tracked = owner:step()
		H.equal(applied, 1)
		H.equal(tracked, 1)
		H.equal(owner:count(), 1)
		owner:forget(b)
		H.equal(owner:count(), 0)
	end)

	H.test("Crowbill presentation can replay all tracked identities after base pose", function()
		local presentation = dofile(repo_root
			.. "/character_weapon_variants/scripts/mods/character_weapon_variants/_cwv_crowbill_presentation.lua")
		local writes = {}
		local owner = presentation.new({
			alive = function() return true end,
			mode_for = function(identity)
				return identity == "hammer-id" and "hammer" or "pick"
			end,
			rotation_ops = {
				identity = function() return "identity" end,
				axis_angle = function() return "flip" end,
				multiply = function(base, delta) return base .. "+" .. delta end,
			},
			write_rotation = function(unit, rotation)
				writes[unit] = rotation
				return true
			end,
		})
		local pick, hammer = {}, {}
		H.equal(owner:apply(pick, "pick-id", "owner_3p", "base-pick"), true)
		H.equal(owner:apply(hammer, "hammer-id", "owner_3p", "base-hammer"), true)
		writes[pick], writes[hammer] = nil, nil
		H.equal(owner:reapply_all(), 2)
		H.equal(writes[pick], "base-pick")
		H.equal(writes[hammer], "base-hammer+flip")
	end)

	H.test("CWV durable lifecycle samples next tick before repair and after final presentation", function()
		local events = {}
		local unit = {}
		local owner = module.new({
			alive = function() return true end,
			before_apply = function(_, spec)
				events[#events + 1] = "pre:" .. tostring(spec.generation)
			end,
			apply = function()
				events[#events + 1] = "repair"
				return true
			end,
			after_all = function() events[#events + 1] = "presentation" end,
			after_final = function(_, spec)
				events[#events + 1] = "final:" .. tostring(spec.generation)
			end,
		})
		local tracked, generation, created = owner:track(unit, {
			model_key = "dawi_01", unit_name = "unit/dawi", surface = "remote_husk",
			perspective = "3p", hand = "right",
		})
		H.equal(tracked, true)
		H.equal(generation, 1)
		H.equal(created, true)
		H.equal(#events, 0)
		owner:step()
		H.deep_equal(events, { "pre:1", "repair", "presentation", "final:1" })

		events = {}
		owner:step()
		H.deep_equal(events, { "repair", "presentation" })
	end)

	H.test("CWV durable generations invalidate by exact model and clean teardown respawn", function()
		local live, forgotten = {}, {}
		local unit, respawn = {}, {}
		live[unit], live[respawn] = true, true
		local owner = module.new({
			alive = function(value) return live[value] == true end,
			on_forget = function(value, spec, reason)
				forgotten[#forgotten + 1] = {
					unit = value, model = spec.model_key, generation = spec.generation, reason = reason,
				}
			end,
		})
		local _, first = owner:track(unit, { model_key = "dawi_01", unit_name = "unit/dawi" })
		local _, same, recreated = owner:track(unit, { model_key = "dawi_01", unit_name = "unit/dawi" })
		H.equal(first, same)
		H.equal(recreated, false)
		local _, changed = owner:track(unit, { model_key = "imperial_05", unit_name = "unit/imperial" })
		H.truthy(changed > first)
		H.equal(forgotten[1].reason, "identity_changed")
		H.equal(forgotten[1].model, "dawi_01")

		owner:forget(unit, "preview_teardown")
		H.equal(forgotten[2].reason, "preview_teardown")
		local _, rebuilt = owner:track(respawn, { model_key = "dawi_01", unit_name = "unit/dawi" })
		H.truthy(rebuilt > changed)
		live[respawn] = false
		owner:step()
		H.equal(forgotten[3].reason, "dead")
		H.equal(forgotten[3].generation, rebuilt)
	end)

	H.test("CWV relative scale waits for settled next-tick state and recaptures on model change", function()
		local relative = dofile(repo_root
			.. "/character_weapon_variants/scripts/mods/character_weapon_variants/_cwv_relative_scale.lua")
		local unit, live = {}, true
		local state = { 1, 1, 1 }
		local reads, targets = 0, {}
		local scale_owner = relative.new({
			read_scale = function()
				reads = reads + 1
				return { state[1], state[2], state[3] }
			end,
		})
		local durable = module.new({
			alive = function() return live end,
			apply = function(value, spec)
				local target = scale_owner:resolve(value, spec.multiplier, spec.identity_token)
				targets[#targets + 1] = target
				return true
			end,
			on_forget = function(value) scale_owner:forget(value) end,
		})
		durable:track(unit, { model_key = "dawi_01", unit_name = "unit/dawi",
			multiplier = { 0.5, 0.5, 0.5 } })
		state = { 0.4, 0.6, 0.8 }
		durable:step()
		H.deep_equal(targets[1], { 0.2, 0.3, 0.4 })
		H.equal(reads, 1)

		state = { 0.8, 1.0, 1.2 }
		durable:track(unit, { model_key = "imperial_05", unit_name = "unit/imperial",
			multiplier = { 0.5, 0.5, 0.5 } })
		durable:step()
		H.deep_equal(targets[2], { 0.4, 0.5, 0.6 })
		H.equal(reads, 2)
	end)

	H.test("CWV #747 crowbill runtime replays from retained state with readback proofs", function()
		local old_unit, old_vector, old_quaternion = _G.Unit, _G.Vector3, _G.Quaternion
		local ok, err = pcall(function()
			local unit = {}
			local state = { scale = { 1, 1, 1 }, position = { 0, 0, 0 },
				rotation = { 0, 0, 0, 1 } }
			_G.Unit = {
				alive = function(value) return value == unit end,
				has_node = function() return true end,
				local_scale = function() return { state.scale[1], state.scale[2], state.scale[3] } end,
				local_position = function() return { state.position[1], state.position[2], state.position[3] } end,
				local_rotation = function() return { state.rotation[1], state.rotation[2],
					state.rotation[3], state.rotation[4] } end,
			}
			_G.Vector3 = { to_elements = function(v) return v[1], v[2], v[3] end }
			_G.Quaternion = { to_elements = function(q) return q[1], q[2], q[3], q[4] end }

			local applies, foreign_calls, logs = {}, {}, {}
			local appearance = setmetatable({
				to_quaternion = function() return { 0, 0, 0, 1 } end,
				apply = function(value, spec)
					applies[#applies + 1] = { unit = value, node = spec.node,
						scale = spec.scale, position = spec.position }
					state.scale = { spec.scale[1], spec.scale[2], spec.scale[3] }
					state.position = { spec.position[1], spec.position[2], spec.position[3] }
					return true, { transform_mode = "atomic-local-pose" }
				end,
			}, { __index = function(_, key)
				foreign_calls[#foreign_calls + 1] = key
				return nil
			end })

			local runtime_lib = dofile(repo_root
				.. "/character_weapon_variants/scripts/mods/character_weapon_variants/_cwv_crowbill_transform_runtime.lua")
			local runtime = runtime_lib.new({
				om = {},
				appearance = appearance,
				durable_library = module,
				relative_library = dofile(repo_root
					.. "/character_weapon_variants/scripts/mods/character_weapon_variants/_cwv_relative_scale.lua"),
				evidence_library = dofile(repo_root
					.. "/character_weapon_variants/scripts/mods/character_weapon_variants/_cwv_transform_evidence.lua"),
				emit = function(fmt, ...) logs[#logs + 1] = string.format(fmt, ...) end,
			})
			local function proofs(phase)
				local count = 0
				for _, line in ipairs(logs) do
					if line:find("[cwv:747] retained-proof phase=" .. phase, 1, true) then
						count = count + 1
					end
				end
				return count
			end

			runtime.durable:track(unit, {
				model_key = "imperial_05", unit_name = "unit/imperial",
				surface = "remote_husk", perspective = "3p", hand = "right",
				scale = { 2, 2, 2 },
				position = { unbox = function() return { 0.1, 0.2, 0.3 } end },
			})
			-- Tick 1: drift from the native pose -> ONE atomic write, readback
			-- retained. No per-channel setter (apply_scale/apply_position/...)
			-- may be reached: that is the class-58 shape this migration removes.
			local applied = runtime.durable:step()
			H.equal(applied, 1)
			H.equal(#applies, 1)
			H.equal(applies[1].node, 0)
			H.deep_equal(applies[1].scale, { 2, 2, 2 })
			H.deep_equal(applies[1].position, { 0.1, 0.2, 0.3 })
			H.equal(#foreign_calls, 0)
			H.equal(proofs("initial-retained"), 1)

			-- Tick 2: retained -> NO write, one bounded retention proof.
			applied = runtime.durable:step()
			H.equal(applied, 0)
			H.equal(#applies, 1)
			H.equal(proofs("next-frame-retained"), 1)

			-- Anim-tick stomp -> measured drift, one repair write, one proof.
			state.scale = { 1, 1, 1 }
			applied = runtime.durable:step()
			H.equal(applied, 1)
			H.equal(#applies, 2)
			H.equal(proofs("drift-repaired"), 1)

			-- Settled again: quiet, no further writes or proof lines.
			local before_logs = #logs
			applied = runtime.durable:step()
			H.equal(applied, 0)
			H.equal(#applies, 2)
			H.equal(#logs, before_logs)
		end)
		_G.Unit, _G.Vector3, _G.Quaternion = old_unit, old_vector, old_quaternion
		if not ok then error(err) end
	end)

	H.test("CWV #747 crowbill runtime reports an unrepaired write as a miss, never a pass", function()
		local old_unit, old_vector, old_quaternion = _G.Unit, _G.Vector3, _G.Quaternion
		local ok, err = pcall(function()
			local unit = {}
			local state = { scale = { 1, 1, 1 }, position = { 0, 0, 0 },
				rotation = { 0, 0, 0, 1 } }
			_G.Unit = {
				alive = function(value) return value == unit end,
				has_node = function() return true end,
				local_scale = function() return { state.scale[1], state.scale[2], state.scale[3] } end,
				local_position = function() return { state.position[1], state.position[2], state.position[3] } end,
				local_rotation = function() return { state.rotation[1], state.rotation[2],
					state.rotation[3], state.rotation[4] } end,
			}
			_G.Vector3 = { to_elements = function(v) return v[1], v[2], v[3] end }
			_G.Quaternion = { to_elements = function(q) return q[1], q[2], q[3], q[4] end }
			local logs = {}
			local runtime_lib = dofile(repo_root
				.. "/character_weapon_variants/scripts/mods/character_weapon_variants/_cwv_crowbill_transform_runtime.lua")
			local runtime = runtime_lib.new({
				om = {},
				-- Setter-success lie: apply RETURNS true but retains nothing.
				appearance = {
					to_quaternion = function() return { 0, 0, 0, 1 } end,
					apply = function() return true, { transform_mode = "per-channel-fallback" } end,
				},
				durable_library = module,
				relative_library = dofile(repo_root
					.. "/character_weapon_variants/scripts/mods/character_weapon_variants/_cwv_relative_scale.lua"),
				evidence_library = dofile(repo_root
					.. "/character_weapon_variants/scripts/mods/character_weapon_variants/_cwv_transform_evidence.lua"),
				emit = function(fmt, ...) logs[#logs + 1] = string.format(fmt, ...) end,
			})
			runtime.durable:track(unit, {
				model_key = "dawi_01", unit_name = "unit/dawi",
				surface = "owner_3p", perspective = "3p", hand = "right",
				scale = { 1.4, 1.4, 2 },
			})
			runtime.durable:step()
			local miss = 0
			for _, line in ipairs(logs) do
				if line:find("[cwv:747] retained-proof phase=initial-miss", 1, true) then
					miss = miss + 1
				end
				if line:find("phase=initial-retained", 1, true) then
					error("a setter-success write must never read as retained")
				end
			end
			H.equal(miss, 1)
		end)
		_G.Unit, _G.Vector3, _G.Quaternion = old_unit, old_vector, old_quaternion
		if not ok then error(err) end
	end)

	H.test("CWV Crowbill evidence is dedicated bounded and keyed by model unit generation", function()
		local evidence = dofile(repo_root
			.. "/character_weapon_variants/scripts/mods/character_weapon_variants/_cwv_transform_evidence.lua")
		local emitted = {}
		local owner = evidence.new({ total_limit = 4, per_model_limit = 2,
			emit = function(row) emitted[#emitted + 1] = row end })
		local function row(model, unit_id, generation)
			return { phase = "post_final", surface = "remote_husk", model_key = model,
				unit_name = "unit/" .. model, unit_id = unit_id, generation = generation,
				fingerprint = "same" }
		end
		H.equal(owner:observe({ phase = "post_final" }), false)
		H.equal(owner:observe(row("dawi", "u1", 1)), true)
		local accepted, reason = owner:observe(row("dawi", "u1", 1))
		H.equal(accepted, false)
		H.equal(reason, "duplicate")
		H.equal(owner:observe(row("dawi", "u2", 1)), true)
		accepted, reason = owner:observe(row("dawi", "u1", 2))
		H.equal(accepted, false)
		H.equal(reason, "model_limit")
		H.equal(owner:observe(row("imperial", "u1", 1)), true)
		H.equal(owner:observe(row("imperial", "u1", 2)), true)
		accepted, reason = owner:observe(row("third", "u3", 1))
		H.equal(accepted, false)
		H.equal(reason, "total_limit")
		local stats = owner:stats()
		H.equal(stats.count, 4)
		H.equal(stats.per_model.dawi, 2)
		H.equal(stats.per_model.imperial, 2)
		H.equal(#emitted, 4)
	end)
end
