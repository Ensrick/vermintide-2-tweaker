-- qa/runtime/_stub/T.lua: offline stub of the rig's script helper table T (WP-H-13).
--
-- Every helper a test script may call exists here and only records the call. It proves the SHAPE of a script
-- (qa/check_runtime_scripts.ps1 uses it to reject an unknown T.<name>); it never proves that a behaviour
-- passed, and must never be used to claim one did. The real helpers are in tools/harness/driver/vt2_rig_driver.lua;
-- the documented list is docs/program/CONVENTIONS.md section 3.
--
-- Usage: local new_T = dofile("qa/runtime/_stub/T.lua"); local T, calls = new_T()
local NAMES = {
    -- implemented by the driver today
    "step", "note", "wait", "frames", "wait_until", "require", "expect", "expect_eq", "expect_near",
    "find_mod", "local_player", "local_hero", "level_key", "bots", "ext", "cmd", "commands",
    "shield", "shared",
    "main", "spawn", "kill", "teleport", "invincible", "end_level", "return_to_keep",
    -- documented in docs/program/CONVENTIONS.md section 3, landing with WP-H-03, WP-H-06 and WP-H-10
    "expect_rt", "first_bot_unit", "set", "pickup", "as_bot", "open_view", "widget", "shot",
}
local FIELDS = { "case_id", "nonce" }

return function()
    local T, calls = {}, {}
    for _, name in ipairs(NAMES) do
        T[name] = function(...)
            calls[#calls + 1] = { name = name, n = select("#", ...), args = { ... } }
            return nil
        end
    end
    T.case_id = "stub"
    T.nonce = "00000000"
    return T, calls, NAMES, FIELDS
end
