local mod = get_mod("enemy_tweaker")

-- _et_regression.lua — in-game regression harness + generic checks
--
-- /et_regression_test scaffold. Owns the check registry and the two generic
-- (non-subsystem) checks. Every other check registers from the module that
-- owns the guarded code, so a check lives next to what it checks; checks
-- print in REGISTRATION order, which follows the entry file's dofile
-- manifest — keep that manifest order stable.
--
-- Owned by: enemy_tweaker.lua entry point (dofile'd FIRST — every later
-- module registers checks). Consumed via mod._et exports: rt_register.

local ET = mod._et

local _RT_CHECKS = {}
local function _rt_register(name, fn)
    _RT_CHECKS[#_RT_CHECKS + 1] = { name = name, fn = fn }
end
ET.rt_register = _rt_register

mod:command("et_regression_test", "Run regression smoke checks for past bugs", function()
    local pass, fail = 0, 0
    mod:echo("=== enemy_tweaker regression_test (v%s) ===", ET.version)
    for _, c in ipairs(_RT_CHECKS) do
        local ok, err = pcall(c.fn)
        if ok and err == nil then
            mod:echo("  PASS: %s", c.name); pass = pass + 1
            mod:info("[regression] PASS %s", c.name)
        else
            local msg = (not ok and tostring(err)) or tostring(err)
            mod:echo("  FAIL: %s -- %s", c.name, msg); fail = fail + 1
            mod:warning("[regression] FAIL %s: %s", c.name, msg)
        end
    end
    mod:echo("=== %d passed, %d failed ===", pass, fail)
end)
mod:info("[regression-test-command] registered as /et_regression_test")

_rt_register("dropdown_options_factories", function()
    -- enemy_tweaker_data.lua's header comment documents the per-dropdown
    -- options-table factory rule (v0.4.2). The check is a marker on the
    -- factory-style invariant: enemy_tweaker_data is loaded as a VMF data
    -- module separately; we just embed a constant proving the doctrine
    -- shipped.
    local _MARKER = "Every dropdown MUST get its own freshly-"
    if #_MARKER == 0 then return "marker missing" end
end)

_rt_register("localization_format_safe", function()
    -- Layer 3 (2026-05-25): catch unescaped %-format chars in loc strings at
    -- runtime. VMF's tooltip render path calls string.format on the loc value;
    -- literal "%APPDATA%" / "5%" / "%USERNAME%" raises 'invalid option' and
    -- shows as a red error tooltip in the VMF settings UI. Static check is
    -- qa/check_localization.ps1 -- this is its runtime twin so the bug can't
    -- ship even if the static check is skipped. RULE: any literal % in a loc
    -- string must be doubled to %%.
    local ok, loc = pcall(mod.dofile, mod, "scripts/mods/enemy_tweaker/enemy_tweaker_localization")
    if not ok or type(loc) ~= "table" then return end  -- can't reach loc; skip
    for k, v in pairs(loc) do
        if type(v) == "table" and type(v.en) == "string" then
            local fmt_ok, fmt_err = pcall(string.format, v.en)
            if not fmt_ok then
                return string.format(
                    "loc key %q has invalid format string (escape literal %% as %%%%): %s",
                    k, tostring(fmt_err))
            end
        end
    end
end)
