-- Fixture for qa/check_runtime_scripts.ps1 -SelfTest: T.note is a real helper that this fixture's API.md does not list.
return {
	issue = 0,
	arena = "keep",
	class = "R",
	timeout = 10,
	run = function(T)
		T.step("a")
		T.note("k", "v")
	end,
}
