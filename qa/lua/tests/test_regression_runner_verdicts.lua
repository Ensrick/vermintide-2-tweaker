-- Issue #1156: the runners are the last thing that decides whether a suite reads green, so a
-- verdict they render wrongly is a lying instrument that hides every check beneath it
-- (BUG_CLASSES 85). Three verdicts beyond plain PASS/FAIL now exist across the repo and none
-- was locked offline:
--   * ct  SKIP       -- a check that cannot run in the current context (5.1d rule 2)
--   * cwv XFAIL/XPASS-- a known-open defect, and the loud failure when it stops reproducing
--                       (5.1d rule 4)
--   * gt  BAD-SHAPE  -- a check that returns boolean instead of nil/string (5.1d rule 3, #1153)
--
-- These cases run the REAL runner bodies. The command block is lifted verbatim out of each
-- production entry file and executed against a fake mod table and a synthetic check list, so
-- the assertions bind to the shipped source rather than to a paraphrase of it: reword the
-- rendering or drop a counter and these fail.
return function(H, repo_root)
    local function read(path)
        local file = assert(io.open(repo_root .. "/" .. path, "rb"))
        local source = file:read("*a")
        file:close()
        return source
    end

    -- Lift `mod:command("<name>", ..., function() ... end)` out of an entry file: from the
    -- command line through the first line that is exactly `end)`. Both are column-anchored in
    -- every entry, so this stays a whole-block extraction and never a partial one.
    local function extract_command(source, command_name)
        local start_pat = 'mod:command("' .. command_name .. '"'
        local from = source:find(start_pat, 1, true)
        H.truthy(from, command_name .. " command block not found in its entry file")
        local line_start = source:sub(1, from):match("()[^\n]*$")
        local block_end = source:find("\nend)\n", from, true)
        H.truthy(block_end, command_name .. " command block has no column-anchored end)")
        return source:sub(line_start, block_end + 5)
    end

    -- Run an extracted runner over `checks`, returning every line it echoed plus the printf
    -- and warning channels it used. Verdict lines go to chat; the runner is expected to also
    -- emit on a log channel, which is what a tester actually greps.
    local function run_runner(block, checks, opts)
        opts = opts or {}
        local echoes, printfs, warnings, infos = {}, {}, {}, {}
        local function fmt(f, ...)
            if select("#", ...) == 0 then return tostring(f) end
            return string.format(tostring(f), ...)
        end
        local command_fn
        local mod = {
            command = function(_, _, _, fn) command_fn = fn end,
            echo = function(_, f, ...) echoes[#echoes + 1] = fmt(f, ...) end,
            warning = function(_, f, ...) warnings[#warnings + 1] = fmt(f, ...) end,
            info = function(_, f, ...) infos[#infos + 1] = fmt(f, ...) end,
        }
        local saved_printf = _G.printf
        _G.printf = function(f, ...) printfs[#printfs + 1] = fmt(f, ...) end
        local chunk = assert(loadstring(
            "local mod, _RT_CHECKS, MOD_VERSION, _dbg = ...\n" .. block,
            "@" .. (opts.chunk_name or "runner")))
        chunk(mod, checks, opts.version or "0.0.0-test", function() end)
        H.equal(type(command_fn), "function", "runner command body was never registered")
        command_fn()
        _G.printf = saved_printf
        return echoes, printfs, warnings, infos
    end

    local function find_line(lines, needle)
        for _, line in ipairs(lines) do
            if line:find(needle, 1, true) then return line end
        end
        return nil
    end

    H.test("CT runner scores a wrong-context check as SKIP, never FAIL", function()
        local block = extract_command(
            read("chaos_wastes_tweaker_dev/scripts/mods/chaos_wastes_tweaker_dev/chaos_wastes_tweaker_dev.lua"),
            "ct_regression_test")
        local echoes, printfs, warnings = run_runner(block, {
            { name = "healthy", fn = function() return nil end },
            { name = "wrong_context", fn = function() return "skip: BuffTemplates not loaded (run in-keep)" end },
            { name = "broken", fn = function() return "marker reverted" end },
        }, { chunk_name = "ct_runner" })

        H.truthy(find_line(echoes, "PASS: healthy"))
        H.truthy(find_line(echoes, "SKIP: wrong_context"))
        H.truthy(find_line(echoes, "FAIL: broken"))
        -- The skip must carry its reason, with the `skip:` sentinel stripped from the render.
        local skip_line = find_line(echoes, "SKIP: wrong_context")
        H.truthy(skip_line:find("BuffTemplates not loaded", 1, true))
        H.equal(skip_line:find("skip:", 1, true), nil)
        -- A skip is not a pass and not a failure: its own column, counted separately.
        H.truthy(find_line(echoes, "=== 1 passed, 1 failed, 1 skipped ==="))
        -- Needle is engine printf so it survives with mod logging off (5.1d rule 5), and a
        -- skip must not be routed to the warning channel that real failures use.
        H.truthy(find_line(printfs, "[regression] SKIP wrong_context"))
        H.equal(find_line(warnings, "wrong_context"), nil)
        H.truthy(find_line(warnings, "FAIL broken"))
    end)

    H.test("CT runner cannot be made green by an all-skip run", function()
        local block = extract_command(
            read("chaos_wastes_tweaker_dev/scripts/mods/chaos_wastes_tweaker_dev/chaos_wastes_tweaker_dev.lua"),
            "ct_regression_test")
        local echoes = run_runner(block, {
            { name = "a", fn = function() return "skip: not in keep" end },
            { name = "b", fn = function() return "skip: not in keep" end },
        }, { chunk_name = "ct_runner" })
        H.truthy(find_line(echoes, "=== 0 passed, 0 failed, 2 skipped ==="))
        H.equal(find_line(echoes, "PASS:"), nil)
    end)

    H.test("CT runner keeps a raised error and a plain reason on the FAIL path", function()
        local block = extract_command(
            read("chaos_wastes_tweaker_dev/scripts/mods/chaos_wastes_tweaker_dev/chaos_wastes_tweaker_dev.lua"),
            "ct_regression_test")
        local echoes = run_runner(block, {
            { name = "raised", fn = function() error("boom") end },
            { name = "reason", fn = function() return "reverted" end },
            -- A message that merely mentions skipping is NOT the sentinel; only the prefix is.
            { name = "mentions_skip", fn = function() return "we had to skip: nothing" end },
        }, { chunk_name = "ct_runner" })
        H.truthy(find_line(echoes, "FAIL: raised"))
        H.truthy(find_line(echoes, "FAIL: reason"))
        H.truthy(find_line(echoes, "FAIL: mentions_skip"))
        H.truthy(find_line(echoes, "=== 0 passed, 3 failed, 0 skipped ==="))
    end)

    H.test("CWV runner renders XFAIL for an open defect and XPASS as a failure", function()
        local block = extract_command(
            read("character_weapon_variants/scripts/mods/character_weapon_variants/character_weapon_variants.lua"),
            "cwv_regression_test")
        local echoes, printfs, warnings = run_runner(block, {
            { name = "healthy", fn = function() return nil end },
            { name = "still_broken", fn = function() return "reproduces" end, defect = "719" },
            { name = "no_longer_broken", fn = function() return nil end, defect = "579" },
            { name = "regressed", fn = function() return "reverted" end },
        }, { chunk_name = "cwv_runner" })

        H.truthy(find_line(echoes, "PASS: healthy"))
        -- Known-open defect that still reproduces: expected, so it must not inflate fail.
        local xfail_line = find_line(echoes, "XFAIL: still_broken")
        H.truthy(xfail_line)
        H.truthy(xfail_line:find("719", 1, true))
        -- Rule 4: an XFAIL that passes is a LOUD failure demanding the annotation be resolved.
        local xpass_line = find_line(echoes, "XPASS: no_longer_broken")
        H.truthy(xpass_line)
        H.truthy(xpass_line:find("579", 1, true))
        H.truthy(xpass_line:find("verify the fix or drop known_defect", 1, true))
        -- One real failure plus the XPASS; the XFAIL is counted apart from both.
        H.truthy(find_line(echoes, "=== 1 passed, 2 failed, 1 xfail (known defects) ==="))
        H.truthy(find_line(printfs, "[regression] XPASS no_longer_broken"))
        H.truthy(find_line(printfs, "[regression] XFAIL still_broken"))
        H.truthy(find_line(warnings, "FAIL regressed"))
    end)

    H.test("CWV runner never lets an annotated defect suppress a genuine failure count", function()
        local block = extract_command(
            read("character_weapon_variants/scripts/mods/character_weapon_variants/character_weapon_variants.lua"),
            "cwv_regression_test")
        local echoes = run_runner(block, {
            { name = "xpass_only", fn = function() return nil end, defect = "1156" },
        }, { chunk_name = "cwv_runner" })
        H.truthy(find_line(echoes, "=== 0 passed, 1 failed, 0 xfail (known defects) ==="))
    end)

    H.test("GT runner gives a boolean return its own BAD-SHAPE verdict", function()
        local block = extract_command(
            read("general_tweaker_dev/scripts/mods/general_tweaker_dev/general_tweaker_dev.lua"),
            "gt_regression_test")
        local echoes, _, warnings = run_runner(block, {
            { name = "healthy", fn = function() return nil end },
            { name = "wrong_shape", fn = function() return true end },
            { name = "broken", fn = function() return "reverted" end },
        }, { chunk_name = "gt_runner" })

        H.truthy(find_line(echoes, "PASS: healthy"))
        local bad = find_line(echoes, "BAD-SHAPE: wrong_shape")
        H.truthy(bad)
        H.truthy(bad:find("checks must return nil on success", 1, true))
        H.equal(find_line(echoes, "PASS: wrong_shape"), nil)
        H.truthy(find_line(echoes, "=== 1 passed, 2 failed ==="))
        H.truthy(find_line(warnings, "BAD-SHAPE wrong_shape"))
    end)
end
