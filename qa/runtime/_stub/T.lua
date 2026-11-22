-- qa/runtime/_stub/T.lua: offline stub of the rig's script helper table T (WP-H-13).
--
-- Every helper a test script may call exists here and only records the call. It proves the SHAPE of a script
-- (qa/check_runtime_scripts.ps1 uses it to reject an unknown T.<name>); it never proves that a behaviour
-- passed, and must never be used to claim one did. The real helpers are in tools/harness/driver/vt2_rig_driver.lua
-- and tools/harness/driver/lib/*.lua; the documented list is tools/harness/API.md (qa/check_runtime_scripts.ps1
-- fails when a name here is missing there).
--
-- Usage: local new_T = dofile("qa/runtime/_stub/T.lua"); local T, calls = new_T()
local NAMES = {
    -- implemented by the driver today
    "step", "note", "wait", "frames", "wait_until", "require", "expect", "expect_eq", "expect_near",
    "find_mod", "local_player", "local_hero", "level_key", "bots", "ext", "cmd", "commands",
    "shield", "shared",
    "main", "spawn", "kill", "teleport", "invincible", "end_level", "return_to_keep", "expect_rt",
    -- helper groups in tools/harness/driver/lib/ (WP-H-06)
    "set", "shot", "career", "equip", "loadout", "backend_items", "open_view", "close_view", "widget", "press",
    "first_bot_unit", "as_bot", "pickup", "transmit_spy",
    -- planned helpers (tools/harness/API.md, status planned) are not listed: a case must not call them
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
