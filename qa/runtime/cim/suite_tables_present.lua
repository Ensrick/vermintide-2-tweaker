-- qa/runtime/cim/suite_tables_present.lua
-- WP-CIM-05 rig case: the cim_dev and crt regression suites run through the
-- shared runner (tools/shared_lib/_lib_rt_runner.lua), print their LOAD and RT
-- lines to the engine log, and expose the last results as a table whose counts
-- add up. Class R; no issue closes (issue = 0).
--
-- The card also names mp. Its part is held: tools/verify/mp_login_source_contract.ps1
-- pins the full token stream of modded_progression.lua while the MP1684 override
-- is active, so the mp runner cannot change yet. Add mp back with that part:
--   { mod = "mp", command = "mp_regression_test", field = "_mp_rt_last" },
-- and "[mp:LOAD] v", "[mp:RT] SUMMARY" in host_expect_log.
--
-- Reads only the mods' own result tables; no engine state, no backend commit.

local SUITES = {
    { mod = "cim_dev", command = "cim_regression_test", field = "_cim_rt_last" },
    { mod = "crt", command = "crt_regression_test", field = "_crt_rt_last" },
}

return {
    issue = 0,
    class = "R",
    arena = "keep",
    mods = { "cim_dev", "crt" },
    timeout = 120,
    covers = "WP-CIM-05 RIG: cim_dev and crt suites expose consistent last-result tables (mp held)",

    host_expect_log = {
        "[cim:LOAD] v", "[crt:LOAD] v",
        "[cim:RT] SUMMARY", "[crt:RT] SUMMARY",
    },

    run = function(T)
        for _, suite in ipairs(SUITES) do
            local m = get_mod(suite.mod)
            T.require(m ~= nil, suite.mod .. " loaded")
            -- The boot sweep normally ran the suite already; run it here when not.
            if type(m[suite.field]) ~= "table" then
                T.step("run /" .. suite.command)
                T.cmd(suite.command)
            end
            local last = m[suite.field]
            T.expect(type(last) == "table", suite.field .. " is a table")
            if type(last) == "table" then
                local n = type(last.results) == "table" and #last.results or -1
                T.expect_eq((last.pass or 0) + (last.fail or 0) + (last.skip or 0), n,
                    suite.mod .. ": pass + fail + skip equals the result count")
                T.note(suite.mod .. "_counts", string.format("pass=%s fail=%s skip=%s",
                    tostring(last.pass), tostring(last.fail), tostring(last.skip)))
            end
        end
    end,
}
