-- Fixture for qa/check_runtime_scripts.ps1 -SelfTest: API.md marks T.step planned although the driver defines it.
return {
	issue = 0,
	arena = "keep",
	class = "R",
	timeout = 10,
	run = function(T)
		T.step("a")
	end,
}
