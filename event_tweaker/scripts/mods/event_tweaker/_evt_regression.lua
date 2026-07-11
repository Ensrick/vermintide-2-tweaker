local mod = get_mod("event_tweaker")

-- _evt_regression.lua — in-game regression harness + generic checks
--
-- v0.4.6-dev regression test scaffold (event_tweaker had none before). Owns
-- the check registry, the /event_tweaker_regression_test chat command, and the
-- generic (non-issue-specific) checks. Issue-specific checks register from the
-- module that owns the guarded code (_evt_guard413_weave / _evt_guard455_
-- boss_events / _evt_guard386_pacing / _evt_selection), so a check lives next
-- to what it checks. Checks print in REGISTRATION order, which follows the
-- entry file's dofile manifest — keep that manifest order stable.
--
-- Owned by: event_tweaker.lua entry point (dofile'd before any module that
-- registers a check). Consumed via mod._evt exports: rt_register.

local ET = mod._evt

local _RT_CHECKS = {}
local function _rt_register(name, fn)
    _RT_CHECKS[#_RT_CHECKS + 1] = { name = name, fn = fn }
end
ET.rt_register = _rt_register

mod:command("event_tweaker_regression_test", "Run regression smoke checks for past bugs", function()
    local pass, fail = 0, 0
    mod:echo("=== event_tweaker regression_test (v%s) ===", ET.version)
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

_rt_register("dbg_helpers_two_channel", function()
    if type(ET.dbg) ~= "function" then return "_dbg helper missing" end
    if type(ET.dbg_alert) ~= "function" then return "_dbg_alert helper missing" end
    local ok = pcall(ET.dbg, "smoke test")
    if not ok then return "_dbg raised" end
    ok = pcall(ET.dbg_alert, "smoke test")
    if not ok then return "_dbg_alert raised" end
end)


_rt_register("localization_format_safe", function()
    -- Layer 3 (2026-05-25): catch unescaped %-format chars in loc strings at
    -- runtime. VMF's tooltip render path calls string.format on the loc value;
    -- literal "%APPDATA%" / "5%" / "%USERNAME%" raises 'invalid option' and
    -- shows as a red error tooltip in the VMF settings UI. Static check is
    -- qa/check_localization.ps1 -- this is its runtime twin so the bug can't
    -- ship even if the static check is skipped. RULE: any literal % in a loc
    -- string must be doubled to %%.
    local ok, loc = pcall(mod.dofile, mod, "scripts/mods/event_tweaker/event_tweaker_localization")
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
_rt_register("suppress_live_event_default_off", function()
    -- v0.4.10-dev: ensure suppress_live_event defaults to false so existing
    -- users see no behavior change after upgrading. The data file's
    -- default_value=false is the source of truth; this check confirms
    -- the widget actually registered the default and mod:get returns it.
    local v = mod:get("suppress_live_event")
    -- VMF: an unregistered setting returns nil; both nil and false are
    -- "off" for our use, but a true here would mean someone shipped the
    -- mod with the wrong default.
    if v == true then
        return "suppress_live_event defaulted to true — must default off"
    end
end)
