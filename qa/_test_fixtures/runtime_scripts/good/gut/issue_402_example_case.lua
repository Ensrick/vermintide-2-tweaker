-- Fixture for qa/check_runtime_scripts.ps1 -SelfTest: a well-formed issue script (T.not_a_helper in a comment is ignored).
local LABEL = "official rows"
return {
	issue = 402,
	arena = "mission:military",
	class = "R",
	timeout = 90,
	not_covered = { "the co-op half" },
	run = function(T)
		local OM = T.shared("official_mirror")
		T.require(OM ~= nil, LABEL)
		T.expect_eq(1, 1, LABEL)
	end,
}
