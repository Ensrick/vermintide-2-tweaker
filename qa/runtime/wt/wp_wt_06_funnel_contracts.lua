-- WP-WT-06: the funnel's decision moved into the pure _wt_anim_resolver.lua.
-- The in-mod funnel contracts must still PASS on the new build. The WP-WT-05
-- hero cases (qa/runtime/wt/issue_948_anim_targets_<hero>.lua) cover the
-- skeleton side once they land.
return {
	card = "WP-WT-06",
	issue = 0,
	class = "R",
	arena = "keep",
	mods = { "wt" },
	timeout = 60,
	run = function(T)
		local wt = get_mod("wt")
		T.require(wt ~= nil and type(wt._wt) == "table", "wt is loaded")
		local function expect_rt(name)
			if T.expect_rt then return T.expect_rt("wt", name) end
			local verdict
			for _, row in ipairs(wt._wt.run_regression()) do
				if row.name == name then verdict = row end
			end
			T.expect(verdict ~= nil, name .. " is registered")
			T.expect_eq(verdict and verdict.result, "PASS", name .. ": " .. tostring(verdict and verdict.detail))
		end
		T.step("funnel contracts")
		expect_rt("issue290_billhook_kruber_effective_3p_complete")
		expect_rt("issue112_remap_identity_includes_receiver_career")
	end,
}
