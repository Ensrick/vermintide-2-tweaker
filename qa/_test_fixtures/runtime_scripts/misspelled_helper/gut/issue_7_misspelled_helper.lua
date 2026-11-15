-- Fixture for qa/check_runtime_scripts.ps1 -SelfTest: T.exepct is a misspelled helper.
return {
	issue = 7,
	arena = "keep",
	class = "R",
	timeout = 30,
	run = function(T)
		T.exepct(true, "misspelled")
	end,
}
