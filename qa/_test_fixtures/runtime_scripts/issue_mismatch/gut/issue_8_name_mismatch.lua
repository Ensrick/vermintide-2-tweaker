-- Fixture for qa/check_runtime_scripts.ps1 -SelfTest: the file name says 8, the issue field says 9.
return {
	issue = 9,
	arena = "keep",
	class = "R",
	timeout = 30,
	run = function(T)
		T.step("x")
	end,
}
