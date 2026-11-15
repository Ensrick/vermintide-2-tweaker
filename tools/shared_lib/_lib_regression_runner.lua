-- ============================================================================
-- SHARED LIBRARY -- regression runner with engine printf verdicts (WP-T-01)
-- ----------------------------------------------------------------------------
-- MASTER SOURCE: tools/shared_lib/_lib_regression_runner.lua
-- DO NOT EDIT COPIES. Consumers are declared in tools/shared_lib/manifest.psd1
-- and synchronized by sync-shared-libs.ps1. The file is copied into each mod so
-- every Workshop bundle remains fully standalone; it is never a runtime
-- dependency on another mod.
-- ============================================================================
-- API (frozen; evolve additively per PROJECT_STANDARDS.md section 9a):
--   local runner = Runner.new({ prefix = "gt", version = MOD_VERSION,
--                               emit = <function(line)> or nil,
--                               echo = <function(fmt, ...)> or nil })
--   runner.register(name, fn, check_opts)   -- check_opts.known_defect optional
--   local summary = runner.run()
--   runner.count()                          -- registered checks
--
-- A check returns nil on success. run() calls every check in registration
-- order under pcall and maps its result to one verdict:
--   PASS      returned nil
--   SKIP      returned a string starting "skip:" (the check cannot run here)
--   FAIL      returned any other string or value, or raised an error
--   BADSHAPE  returned a boolean (checks must return nil on success, #1153)
--   XFAIL     check_opts.known_defect is set and the check failed
--   XPASS     check_opts.known_defect is set and the check passed
-- fail counts FAIL, XPASS and BADSHAPE; xfail counts XFAIL. For every check
-- run() emits exactly one line
--   [<prefix>:rt] <check> <VERDICT> <detail>
-- (no detail for PASS; the detail is one line, at most 300 characters) and
-- after the loop
--   [<prefix>:rt] done pass=<n> fail=<n> skip=<n> xfail=<n> total=<n> v=<version>
-- The default emit is engine printf, which reaches console-*.log with mod
-- logging off (Vermintide-2-Source-Code/foundation/scripts/util/misc_util.lua:29);
-- tools/harness/sweep-formats.psd1 (Log) parses these lines. When echo is set,
-- run() also echoes one chat summary line in the shape the rig sweep reads
-- from chat. emit and echo are called under pcall: a raising sink never stops
-- the loop. run() returns
--   { pass, fail, skip, xfail, total, results = { { name, verdict, detail }, ... } }
-- Pure: the only engine global is printf, read when the default emit runs.
-- luacheck: globals printf
-- ============================================================================

local M = { VERSION = 1 }

local DETAIL_LIMIT = 300

local function one_line(text)
    local flat = tostring(text):gsub("\r\n", " "):gsub("[\r\n]", " ")
    if #flat > DETAIL_LIMIT then flat = flat:sub(1, DETAIL_LIMIT) end
    return flat
end

local function default_emit(line)
    pcall(printf, "%s", line)
end

-- ok, result of pcall(check) -> verdict, detail (before known_defect mapping)
local function classify(has_fn, ok, result)
    if not has_fn then return "FAIL", "check has no function" end
    if not ok then return "FAIL", tostring(result) end
    if result == nil then return "PASS", nil end
    if type(result) == "boolean" then
        return "BADSHAPE", "returned boolean " .. tostring(result) .. "; checks must return nil on success"
    end
    if type(result) == "string" and result:sub(1, 5) == "skip:" then return "SKIP", result end
    return "FAIL", tostring(result)
end

function M.new(opts)
    opts = type(opts) == "table" and opts or {}
    local prefix = tostring(opts.prefix or "mod")
    local version = tostring(opts.version or "?")
    local emit = type(opts.emit) == "function" and opts.emit or default_emit
    local echo = type(opts.echo) == "function" and opts.echo or nil
    local tag = "[" .. prefix .. ":rt] "
    local checks = {}
    local runner = {}

    function runner.register(name, fn, check_opts)
        local defect = type(check_opts) == "table" and check_opts.known_defect or nil
        checks[#checks + 1] = { name = tostring(name), fn = fn, known_defect = defect }
    end

    function runner.count()
        return #checks
    end

    function runner.run()
        local summary = { pass = 0, fail = 0, skip = 0, xfail = 0, total = 0, results = {} }
        for i = 1, #checks do
            local check = checks[i]
            local has_fn = type(check.fn) == "function"
            local ok, result = true, nil
            if has_fn then ok, result = pcall(check.fn) end
            local verdict, detail = classify(has_fn, ok, result)
            if check.known_defect ~= nil then
                if verdict == "PASS" then
                    verdict, detail = "XPASS", "known defect " .. tostring(check.known_defect)
                        .. " no longer reproduces; verify the fix or drop known_defect"
                elseif verdict == "FAIL" then
                    verdict = "XFAIL"
                end
            end
            if verdict == "PASS" then
                summary.pass = summary.pass + 1
            elseif verdict == "SKIP" then
                summary.skip = summary.skip + 1
            elseif verdict == "XFAIL" then
                summary.xfail = summary.xfail + 1
            else
                summary.fail = summary.fail + 1
            end
            summary.total = summary.total + 1
            if detail ~= nil then detail = one_line(detail) end
            summary.results[#summary.results + 1] = { name = check.name, verdict = verdict, detail = detail }
            local line = tag .. check.name .. " " .. verdict
            if detail ~= nil and detail ~= "" then line = line .. " " .. detail end
            pcall(emit, line)
        end
        pcall(emit, string.format("%sdone pass=%d fail=%d skip=%d xfail=%d total=%d v=%s",
            tag, summary.pass, summary.fail, summary.skip, summary.xfail, summary.total, version))
        if echo then
            pcall(echo, "=== %d passed, %d failed, %d xfail (known defects), %d skipped ===",
                summary.pass, summary.fail, summary.xfail, summary.skip)
        end
        return summary
    end

    return runner
end

return M
