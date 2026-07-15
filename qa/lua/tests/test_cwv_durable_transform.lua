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
end
