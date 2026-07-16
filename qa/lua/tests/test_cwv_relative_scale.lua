return function(H, repo_root)
	local policy = dofile(repo_root
		.. "/character_weapon_variants/scripts/mods/character_weapon_variants/_cwv_relative_scale.lua")

	H.test("CWV relative scale captures baseline once and returns absolute targets", function()
		local reads = 0
		local unit = {}
		local owner = policy.new({
			read_scale = function()
				reads = reads + 1
				return { 0.2, 0.4, 0.6 }
			end,
		})
		local target, baseline = owner:resolve(unit, { 0.5, 0.5, 0.5 })
		H.deep_equal(target, { 0.1, 0.2, 0.3 })
		H.deep_equal(baseline, { 0.2, 0.4, 0.6 })
		local replay = owner:resolve(unit, { 0.5, 0.5, 0.5 })
		H.deep_equal(replay, target)
		H.equal(reads, 1)
	end)

	H.test("CWV relative scale fails closed on invalid input", function()
		local owner = policy.new({ read_scale = function() return { 1, 1, 1 } end })
		H.equal(owner:resolve({}, { 0.5, 0.5 }), nil)
		H.equal(owner:resolve(nil, { 0.5, 0.5, 0.5 }), nil)
	end)
end
