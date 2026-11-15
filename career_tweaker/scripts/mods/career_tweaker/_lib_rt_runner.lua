-- ============================================================================
-- SHARED LIBRARY -- regression-suite runner, VERSION 1 (WP-CIM-05)
-- ----------------------------------------------------------------------------
-- MASTER SOURCE: tools/shared_lib/_lib_rt_runner.lua
-- DO NOT EDIT COPIES. Consumers are declared in tools/shared_lib/manifest.psd1
-- and synchronized by sync-shared-libs.ps1. The file is copied into each mod so
-- every Workshop bundle remains fully standalone; it is never a runtime
-- dependency on another mod.
-- ============================================================================
-- M.run(checks, emit) runs an array of { name = <string>, fn = <function> } in
-- order. Verdicts:
--   PASS  fn returned normally with nil
--   SKIP  fn returned a string starting "skip:" (detail = the rest, trimmed)
--   FAIL  anything else: an error (detail = its text), another string, or any
--         other value (detail = its tostring)
-- emit(verdict, name, detail) is called once per check under pcall, so a
-- raising emit never stops the run. Returns
--   { pass = n, fail = n, skip = n, results = { { name =, verdict =, detail = }, ... } }
-- Pure: no engine globals.
-- ============================================================================

local M = { VERSION = 1 }

local function classify(ok, result)
    if not ok then return "FAIL", tostring(result) end
    if result == nil then return "PASS", nil end
    if type(result) == "string" then
        if result:sub(1, 5) == "skip:" then
            return "SKIP", (result:sub(6):gsub("^%s+", ""):gsub("%s+$", ""))
        end
        return "FAIL", result
    end
    return "FAIL", tostring(result)
end

function M.run(checks, emit)
    local summary = { pass = 0, fail = 0, skip = 0, results = {} }
    if type(checks) ~= "table" then return summary end
    for i = 1, #checks do
        local check = checks[i]
        local name = type(check) == "table" and check.name or nil
        local fn = type(check) == "table" and check.fn or nil
        local verdict, detail
        if type(fn) ~= "function" then
            verdict, detail = "FAIL", "check has no function"
        else
            verdict, detail = classify(pcall(fn))
        end
        if verdict == "PASS" then
            summary.pass = summary.pass + 1
        elseif verdict == "SKIP" then
            summary.skip = summary.skip + 1
        else
            summary.fail = summary.fail + 1
        end
        summary.results[#summary.results + 1] = {
            name = tostring(name), verdict = verdict, detail = detail,
        }
        if type(emit) == "function" then
            pcall(emit, verdict, tostring(name), detail)
        end
    end
    return summary
end

return M
