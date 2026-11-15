-- Fixture for qa/check_runtime_scripts.ps1 -SelfTest: a well-formed rig case.
return {
	issue = 0,
	arena = "keep",
	class = "R",
	timeout = 30,
	run = function(T)
		T.step("read")
		T.expect(T.local_player() ~= nil, "local player")
	end,
}
