-- Runs every loaded mod's /<mod>_regression_test command and records its output.
-- The orchestrator-side parser turns the OUT lines into per-check results.
return {
	issue = 0,
	timeout = 240,
	run = function(T)
		local names = T.commands("")
		local suites = {}
		for i = 1, #names do
			if names[i]:find("regression_test", 1, true) then
				suites[#suites + 1] = names[i]
			end
		end
		T.note("suites", table.concat(suites, ","))
		T.expect(#suites > 0, "at least one regression suite command is registered")
		for i = 1, #suites do
			T.step("run /" .. suites[i])
			local lines = T.cmd(suites[i])
			T.note("lines:" .. suites[i], #lines)
			T.wait(2)
		end
	end,
}
