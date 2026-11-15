-- _wt_regression.lua -- /wt_regression_test smoke-check harness.
--
-- Owns the regression harness plumbing split out of the god file in the
-- v0.12.209-dev Phase 1 OOP decomposition: the `_RT_CHECKS` table, the
-- `rt_register` registrar, and the `/wt_regression_test` chat command. The
-- ~30 individual check bodies stay INLINE in weapon_tweaker.lua next to the
-- file-local state they probe (`_unit_state`, `weapon_unlock_map`,
-- `_suffix_career_map`, ...); the entry aliases `local _rt_register =
-- mod._wt.rt_register` so those call sites are byte-identical. No behavior
-- change from the pre-split god file.
--
-- Loads FIRST in the manifest (the et _et_regression precedent) so every
-- inline `_rt_register(...)` below the manifest binds against this table.
-- Registration order == in-game output order, so it is frozen surface.
--
-- Owned by: weapon_tweaker.lua entry point. Consumed via: mod:dofile.
-- Shared state: reads mod._wt.MOD_VERSION (the version echoed in the command
-- banner); exports mod._wt.rt_register and mod._wt.run_regression.

local mod = get_mod("wt")
local WT = mod._wt
local MOD_VERSION = WT.MOD_VERSION

local _RT_CHECKS = {}
local function _rt_register(name, fn)
    _RT_CHECKS[#_RT_CHECKS + 1] = { name = name, fn = fn }
end
-- WP-WT-02: the one runner, shared by the chat command and scripted callers
-- (the test rig). Each row also goes to the engine log through printf
-- (Vermintide-2-Source-Code/foundation/scripts/util/misc_util.lua:29), which
-- reaches the console log even with VMF mod logging off.
local function _run()
    local rows, pass, fail, skip = {}, 0, 0, 0
    local tag = "[" .. tostring(mod:get_name()) .. ":RT]"
    for _, c in ipairs(_RT_CHECKS) do
        local ok, err = pcall(c.fn)
        local row = { name = c.name }
        if ok and err == nil then
            row.result = "PASS"; pass = pass + 1
        elseif ok and type(err) == "string" and err:sub(1, 5) == "skip:" then
            -- v0.12.117 (Issue #74): tests return "skip: <reason>" when their
            -- preconditions (game tables, sibling mods) aren't loaded; that's
            -- neither PASS nor FAIL and must not pollute the failure count.
            row.result, row.detail = "SKIP", err; skip = skip + 1
        else
            row.result, row.detail = "FAIL", tostring(err); fail = fail + 1
        end
        rows[#rows + 1] = row
        if row.detail then
            pcall(printf, "%s check=%s result=%s detail=%s", tag, row.name, row.result,
                (row.detail:gsub("\r\n", " "):gsub("[\r\n]", " ")))
        else
            pcall(printf, "%s check=%s result=%s", tag, row.name, row.result)
        end
    end
    pcall(printf, "%s summary pass=%d fail=%d skip=%d total=%d version=%s",
        tag, pass, fail, skip, #rows, tostring(MOD_VERSION))
    return rows, pass, fail, skip
end
WT.run_regression = _run

mod:command("wt_regression_test", "Run regression smoke checks for past bugs", function()
    mod:echo("=== wt regression_test (v%s) ===", MOD_VERSION)
    local rows, pass, fail, skip = _run()
    for _, row in ipairs(rows) do
        if row.result == "PASS" then
            mod:echo("  PASS: %s", row.name)
            mod:info("[regression] PASS %s", row.name)
        elseif row.result == "SKIP" then
            mod:echo("  SKIP: %s -- %s", row.name, row.detail)
            mod:info("[regression] SKIP %s: %s", row.name, row.detail)
        else
            mod:echo("  FAIL: %s -- %s", row.name, row.detail)
            mod:warning("[regression] FAIL %s: %s", row.name, row.detail)
        end
    end
    mod:echo("=== %d passed, %d failed, %d skipped ===", pass, fail, skip)
end)
mod:info("[regression-test-command] registered as /wt_regression_test")

WT.rt_register = _rt_register

-- WP-WT-08: fails when wt swallowed any vanilla-path error this session.
_rt_register("wt_no_swallowed_errors", function()
    local s = WT.swallowed or {}
    if (s.create_equipment or 0) + (s.anim_event or 0) + (s.safe_hook or 0) > 0 then
        return string.format("swallowed errors: create_equipment=%d anim_event=%d safe_hook=%d",
            s.create_equipment or 0, s.anim_event or 0, s.safe_hook or 0)
    end
end)
