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
