-- WP-WT-02: the in-mod wt regression suite runs clean on this build.
-- mod._wt.run_regression() returns one row per check and prints one
-- "[wt:RT] check=..." line per row plus a "[wt:RT] summary ..." line through
-- the engine printf (Vermintide-2-Source-Code/foundation/scripts/util/misc_util.lua:29).
return {
	card = "WP-WT-02",
	issue = 0,
	arena = "keep",
	mods = { "wt" },
	timeout = 120,
	host_expect_log = { "[wt:RT] summary" },
	run = function(T)
		local wt = get_mod("wt")
		T.require(wt ~= nil, "wt is loaded")
		T.require(type(wt._wt) == "table" and type(wt._wt.run_regression) == "function",
			"wt exposes run_regression")

		T.step("run the in-mod suite")
		local rows = wt._wt.run_regression()
		T.note("rows", #rows)
		T.expect(#rows >= 70, "suite size")
		local failing = 0
		for _, row in ipairs(rows) do
			if row.result == "FAIL" then
				failing = failing + 1
				T.note(row.name, row.detail)
			end
		end
		T.expect_eq(failing, 0, "no failing in-mod check")
	end,
}
