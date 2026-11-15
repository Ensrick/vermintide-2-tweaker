-- WP-CIM-05: the shared regression-suite runner (tools/shared_lib/_lib_rt_runner.lua)
-- reports PASS, FAIL or SKIP per check and never PASS for a check that did not run.

return function(H, repo_root)
    local path = repo_root .. "/tools/shared_lib/_lib_rt_runner.lua"

    local function load_runner()
        local chunk, err = loadfile(path)
        assert(chunk, "shared rt runner library is missing: " .. tostring(err))
        local M = chunk()
        assert(type(M) == "table", "shared rt runner must return a table")
        return M
    end

    H.test("shared rt runner: three verdicts, order kept, counts match", function()
        local M = load_runner()
        H.equal(M.VERSION, 1)
        local emitted = {}
        local summary = M.run({
            { name = "passes", fn = function() return nil end },
            { name = "skips", fn = function() return "skip:   backend not ready  " end },
            { name = "fails", fn = function() return "row missing" end },
            { name = "raises", fn = function() error("boom", 0) end },
            { name = "odd_value", fn = function() return false end },
            { name = "table_value", fn = function() return {} end },
        }, function(verdict, name, detail)
            emitted[#emitted + 1] = { verdict, name, detail }
        end)
        H.equal(summary.pass, 1)
        H.equal(summary.skip, 1)
        H.equal(summary.fail, 4)
        H.equal(#summary.results, 6)
        H.equal(summary.pass + summary.fail + summary.skip, #summary.results)
        local want = {
            { "PASS", "passes", nil },
            { "SKIP", "skips", "backend not ready" },
            { "FAIL", "fails", "row missing" },
            { "FAIL", "raises", "boom" },
            { "FAIL", "odd_value", "false" },
        }
        for i, row in ipairs(want) do
            H.equal(summary.results[i].verdict, row[1], "verdict " .. i)
            H.equal(summary.results[i].name, row[2], "name " .. i)
            H.equal(summary.results[i].detail, row[3], "detail " .. i)
            H.equal(emitted[i][1], row[1], "emit verdict " .. i)
            H.equal(emitted[i][2], row[2], "emit name " .. i)
            H.equal(emitted[i][3], row[3], "emit detail " .. i)
        end
        H.equal(summary.results[6].verdict, "FAIL", "a non-string value is FAIL")
        H.equal(#emitted, 6, "emit once per check")
    end)

    H.test("shared rt runner: a raising emit does not stop the run", function()
        local M = load_runner()
        local ran = 0
        local summary = M.run({
            { name = "a", fn = function() ran = ran + 1 end },
            { name = "b", fn = function() ran = ran + 1 end },
        }, function() error("emit broke") end)
        H.equal(ran, 2)
        H.equal(summary.pass, 2)
        H.equal(#summary.results, 2)
    end)

    H.test("shared rt runner: no checks and a missing function", function()
        local M = load_runner()
        local empty = M.run({}, nil)
        H.equal(empty.pass + empty.fail + empty.skip, 0)
        H.equal(#empty.results, 0)
        local bad = M.run({ { name = "no_fn" } })
        H.equal(bad.fail, 1)
        H.equal(bad.results[1].verdict, "FAIL")
    end)
end
