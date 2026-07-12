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
-- banner); exports mod._wt.rt_register.

local mod = get_mod("wt")
local WT = mod._wt
local MOD_VERSION = WT.MOD_VERSION

local _RT_CHECKS = {}
local function _rt_register(name, fn)
    _RT_CHECKS[#_RT_CHECKS + 1] = { name = name, fn = fn }
end
mod:command("wt_regression_test", "Run regression smoke checks for past bugs", function()
    local pass, fail, skip = 0, 0, 0
    mod:echo("=== wt regression_test (v%s) ===", MOD_VERSION)
    for _, c in ipairs(_RT_CHECKS) do
        local ok, err = pcall(c.fn)
        if ok and err == nil then
            mod:echo("  PASS: %s", c.name); pass = pass + 1
            mod:info("[regression] PASS %s", c.name)
        elseif ok and type(err) == "string" and err:sub(1, 5) == "skip:" then
            -- v0.12.117 (Issue #74): tests return "skip: <reason>" when their
            -- preconditions (game tables, sibling mods) aren't loaded; that's
            -- neither PASS nor FAIL and must not pollute the failure count.
            mod:echo("  SKIP: %s -- %s", c.name, err); skip = skip + 1
            mod:info("[regression] SKIP %s: %s", c.name, err)
        else
            local msg = (not ok and tostring(err)) or tostring(err)
            mod:echo("  FAIL: %s -- %s", c.name, msg); fail = fail + 1
            mod:warning("[regression] FAIL %s: %s", c.name, msg)
        end
    end
    mod:echo("=== %d passed, %d failed, %d skipped ===", pass, fail, skip)
end)
mod:info("[regression-test-command] registered as /wt_regression_test")

WT.rt_register = _rt_register
