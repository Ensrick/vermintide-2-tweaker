-- API self-test, T.set restore (WP-H-06 step 3): runs after api_set.lua; the option that case changed is back to the
-- value it held before (nil: the marker id is new to every profile), so T.set's cleanup ran with the mod's own setter.
return {
	issue = 0,
	arena = "keep",
	class = "R",
	timeout = 30,
	run = function(T)
		local vmf = T.find_mod("VMF")
		T.require(vmf ~= nil, "VMF loaded")
		T.expect_eq(vmf:get("vt2_rig_api_selftest"), nil, "the option T.set changed in api-set is restored")
	end,
}
