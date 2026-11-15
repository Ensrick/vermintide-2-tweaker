-- Fixture for qa/check_runtime_scripts.ps1 -SelfTest: engine access at the top level.
local mirror = Managers.backend
return {
	issue = 0,
	arena = "keep",
	class = "R",
	timeout = 30,
	run = function(T)
		T.note("mirror", tostring(mirror))
	end,
}
