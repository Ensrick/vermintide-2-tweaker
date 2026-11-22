-- WP-T-01: the shared regression runner (tools/shared_lib/_lib_regression_runner.lua)
-- prints one "[<prefix>:rt] <check> <VERDICT> <detail>" line per check and a
-- "[<prefix>:rt] done ..." summary, the format tools/harness/sweep-formats.psd1
-- (Log) parses. The exact text of every line is asserted here.

return function(H, repo_root)
    local path = repo_root .. "/tools/shared_lib/_lib_regression_runner.lua"

    local function load_runner()
        local chunk, err = loadfile(path)
        assert(chunk, "shared regression runner library is missing: " .. tostring(err))
        local M = chunk()
        assert(type(M) == "table" and type(M.new) == "function", "the library must return a table with new()")
        return M
    end

    local function new_runner(extra)
        local lines = {}
        local opts = { prefix = "gt", version = "0.2.301-dev", emit = function(line) lines[#lines + 1] = line end }
        for key, value in pairs(extra or {}) do opts[key] = value end
        return load_runner().new(opts), lines
    end

    H.test("shared regression runner: exact line for each of the six verdicts and the summary", function()
        local runner, lines = new_runner()
        runner.register("gt_pass", function() return nil end)
        runner.register("gt_fail", function() return "value was 3" end)
        runner.register("gt_skip", function() return "skip: no mission" end)
        runner.register("gt_badshape", function() return true end)
        runner.register("gt_xfail", function() return "still broken" end, { known_defect = "#1234" })
        runner.register("gt_xpass", function() return nil end, { known_defect = "#1235" })
        runner.run()
        H.equal(#lines, 7, "one line per check plus the summary")
        H.equal(lines[1], "[gt:rt] gt_pass PASS")
        H.equal(lines[2], "[gt:rt] gt_fail FAIL value was 3")
        H.equal(lines[3], "[gt:rt] gt_skip SKIP skip: no mission")
        H.equal(lines[4], "[gt:rt] gt_badshape BADSHAPE returned boolean true; checks must return nil on success")
        H.equal(lines[5], "[gt:rt] gt_xfail XFAIL still broken")
        H.equal(lines[6], "[gt:rt] gt_xpass XPASS known defect #1235 no longer reproduces; verify the fix or drop known_defect")
        H.equal(lines[7], "[gt:rt] done pass=1 fail=3 skip=1 xfail=1 total=6 v=0.2.301-dev")
    end)

    H.test("shared regression runner: run returns the counts and every result in order", function()
        local runner = new_runner()
        runner.register("a", function() return nil end)
        runner.register("b", function() return "nope" end)
        runner.register("c", function() return "skip: absent" end)
        runner.register("d", function() return "broken" end, { known_defect = 7 })
        runner.register("e", function() return false end)
        H.equal(runner.count(), 5)
        local summary = runner.run()
        H.equal(summary.pass, 1)
        H.equal(summary.fail, 2, "FAIL and BADSHAPE")
        H.equal(summary.skip, 1)
        H.equal(summary.xfail, 1)
        H.equal(summary.total, 5)
        H.deep_equal(summary.results, {
            { name = "a", verdict = "PASS", detail = nil },
            { name = "b", verdict = "FAIL", detail = "nope" },
            { name = "c", verdict = "SKIP", detail = "skip: absent" },
            { name = "d", verdict = "XFAIL", detail = "broken" },
            { name = "e", verdict = "BADSHAPE", detail = "returned boolean false; checks must return nil on success" },
        })
    end)

    H.test("shared regression runner: a raising check does not stop the loop", function()
        local runner, lines = new_runner()
        local ran = 0
        runner.register("first", function() ran = ran + 1; error("kaput", 0) end)
        runner.register("second", function() ran = ran + 1 end)
        local summary = runner.run()
        H.equal(ran, 2)
        H.equal(lines[1], "[gt:rt] first FAIL kaput")
        H.equal(lines[2], "[gt:rt] second PASS")
        H.equal(summary.fail, 1)
        H.equal(summary.pass, 1)
    end)

    H.test("shared regression runner: detail is one line cut at 300 characters", function()
        local runner, lines = new_runner()
        runner.register("long", function() return string.rep("x", 299) .. "\r\nyz" .. string.rep("w", 50) end)
        runner.register("lines", function() return "one\ntwo\rthree\r\nfour" end)
        local summary = runner.run()
        local detail = string.rep("x", 299) .. " "
        H.equal(#detail, 300)
        H.equal(lines[1], "[gt:rt] long FAIL " .. detail)
        H.equal(summary.results[1].detail, detail)
        H.equal(lines[2], "[gt:rt] lines FAIL one two three four")
    end)

    H.test("shared regression runner: a raising emit or echo never stops the run", function()
        local ran, echoed = 0, 0
        local M = load_runner()
        local runner = M.new({ prefix = "ct", version = "1",
            emit = function() error("emit broke") end,
            echo = function() echoed = echoed + 1; error("echo broke") end })
        runner.register("a", function() ran = ran + 1 end)
        runner.register("b", function() ran = ran + 1 end)
        local summary = runner.run()
        H.equal(ran, 2)
        H.equal(summary.pass, 2)
        H.equal(echoed, 1)
    end)

    H.test("shared regression runner: echo gets one chat summary in the sweep's echo shape", function()
        local echoed = {}
        local runner = new_runner({ echo = function(fmt, ...) echoed[#echoed + 1] = string.format(fmt, ...) end })
        runner.register("a", function() return nil end)
        runner.register("b", function() return "skip: absent" end)
        runner.register("c", function() return "x" end, { known_defect = "#1" })
        runner.run()
        H.deep_equal(echoed, { "=== 1 passed, 0 failed, 1 xfail (known defects), 1 skipped ===" })
    end)

    H.test("shared regression runner: the default emit is engine printf", function()
        local printed = {}
        local saved = rawget(_G, "printf")
        rawset(_G, "printf", function(fmt, ...) printed[#printed + 1] = string.format(fmt, ...) end)
        local ok, err = pcall(function()
            local runner = load_runner().new({ prefix = "wt", version = "9" })
            runner.register("only", function() return nil end)
            runner.run()
        end)
        rawset(_G, "printf", saved)
        assert(ok, err)
        H.deep_equal(printed, { "[wt:rt] only PASS", "[wt:rt] done pass=1 fail=0 skip=0 xfail=0 total=1 v=9" })
    end)

    H.test("shared regression runner: no checks, and a registration without a function", function()
        local runner, lines = new_runner()
        local empty = runner.run()
        H.equal(empty.total, 0)
        H.deep_equal(lines, { "[gt:rt] done pass=0 fail=0 skip=0 xfail=0 total=0 v=0.2.301-dev" })
        local bad, bad_lines = new_runner()
        bad.register("no_fn", nil)
        local summary = bad.run()
        H.equal(summary.fail, 1)
        H.equal(bad_lines[1], "[gt:rt] no_fn FAIL check has no function")
    end)
end
