-- #1692: the #607 loot diagnostic's emit gate must follow the realm the game
-- actually publishes. Game 6.12.0+ sets only the boolean global MODDED_REALM
-- (application_parameter.lua:150-152 at 6.13.0) and no longer writes
-- script_data["eac-untrusted"] (written at :150 up to 6.11.3). The gate used
-- to read that raw flag, so nothing was captured on 6.12+.
--
-- Each case installs the real runtime with BOTH the retired `realm_state`
-- seam (pointed at the layout's script_data) and the new `is_modded_realm`
-- query evaluated from the exact wiring expression shipped in
-- modded_progression.lua. A runtime that still reads the raw flag captures
-- nothing on the 6.12+ layout, which is the reported symptom.
return function(H, repo_root)
local MP = "/modded_progression/scripts/mods/modded_progression/"

local function load_module()
    return dofile(repo_root .. MP .. "_mp_loot_diag.lua")
end

local function load_runtime()
    return dofile(repo_root .. MP .. "_mp_loot_diag_runtime.lua")
end

local function load_authority()
    return dofile(repo_root .. MP .. "_lib_modded_realm_authority.lua")
end

local function read_source(relative_path)
    local file = assert(io.open(repo_root .. relative_path, "rb"))
    local source = file:read("*a")
    file:close()
    return source
end

local function count_plain(value, needle)
    local count, start = 0, 1
    while true do
        local found = value:find(needle, start, true)
        if not found then return count end
        count = count + 1
        start = found + #needle
    end
end

-- The shipped dependency expression, compiled with its free names supplied as
-- chunk parameters (no environment rewrite): LootDiag, rawget, _G, _is_mp_realm.
local function shipped_realm_query()
    local main = read_source(MP .. "modded_progression.lua")
    local expr = main:match("is_modded_realm = (function%(%) return LootDiag%.realm_is_modded%b() end),")
    assert(expr, "modded_progression.lua does not wire is_modded_realm through LootDiag.realm_is_modded")
    local chunk = assert(loadstring(
        "local LootDiag, rawget, _G, _is_mp_realm = ...\nreturn (" .. expr .. ")()",
        "=mp1692_wiring"))
    return function(D, globals, legacy)
        return chunk(D, rawget, globals, legacy)
    end
end

-- One game layout: the engine globals, script_data, Development, and MP's
-- bracket depth. `legacy` mirrors mod.is_modded_realm (modded_progression.lua).
local function layout(spec)
    local Authority = load_authority()
    local script_data = spec.script_data or {}
    local function legacy()
        return Authority.is_modded(script_data, spec.depth or 0, spec.development)
    end
    return { globals = spec.globals or {}, script_data = script_data, legacy = legacy }
end

local function install(world)
    local D = load_module()
    local hooks, commands, checks, saved, logs, echoes = {}, {}, {}, {}, {}, {}
    local mod = {}
    function mod:hook(class_name, method_name, callback)
        hooks[class_name .. "." .. method_name] = callback
    end
    function mod:command(name, _, callback) commands[name] = callback end
    function mod:get(key) return saved[key] end
    function mod:set(key, value) saved[key] = value end
    function mod:echo(fmt, ...) echoes[#echoes + 1] = string.format(fmt, ...) end
    -- Resolved lazily so a runtime that never asks the query (the pre-fix
    -- raw-flag gate) fails on the missing receipt, not on this wiring lookup.
    local wired, wiring = pcall(shipped_realm_query)
    load_runtime().install(mod, {
        loot_diag = D,
        get_inventory_store = function() return {} end,
        rt_register = function(name, callback) checks[name] = callback end,
        realm_state = function() return world.script_data end,
        is_modded_realm = function()
            if not wired then error(wiring, 0) end
            return wiring(D, world.globals, world.legacy)
        end,
        print_log = function(fmt, ...) logs[#logs + 1] = string.format(fmt, ...) end,
        item_master_list = function() return {} end,
        now = function() return 1 end,
    })
    local end_hook = assert(hooks["BackendInterfaceLootPlayfab.generate_end_of_level_loot"])
    local function finish_mission()
        return end_hook(function() return "native" end, {}, true, false, "hard",
            "level_key", "empire_soldier", 1, 2, 3, 4, "profile", nil, nil,
            "adventure", 10, {})
    end
    return {
        D = D, saved = saved, logs = logs, echoes = echoes, checks = checks,
        commands = commands, finish_mission = finish_mission,
    }
end

local function captured_end_level(rig)
    local ledger = rig.saved.issue607_loot_diag_v1
    local records = ledger and ledger.records or {}
    return records[1] and records[1].event == "end_level"
        and table.concat(rig.logs, "\n"):find("[mp:607] event=end_level", 1, true) ~= nil
        or false
end

H.test("MP #1692 realm query: MODDED_REALM decides, legacy answers only pre-6.12", function()
    local D = load_module()
    H.equal(type(D.realm_is_modded), "function", "LootDiag.realm_is_modded missing")
    local function yes() return true end
    local function no() return false end
    -- 6.12+: the boolean global wins in both directions.
    H.equal(D.realm_is_modded(true, no), true)
    H.equal(D.realm_is_modded(true, nil), true)
    H.equal(D.realm_is_modded(false, yes), false)
    -- Pre-6.12 (global absent): the legacy query answers, fail-closed.
    H.equal(D.realm_is_modded(nil, yes), true)
    H.equal(D.realm_is_modded(nil, no), false)
    H.equal(D.realm_is_modded(nil, nil), false)
    H.equal(D.realm_is_modded(nil, function() return 1 end), false)
    H.equal(D.realm_is_modded(nil, function() return "true" end), false)
    H.equal(D.realm_is_modded(nil, function() error("planted legacy read") end), false)
    -- A present malformed modern value is denied, not reclassified as an old game.
    H.equal(D.realm_is_modded("true", no), false)
    H.equal(D.realm_is_modded(1, yes), false)
end)

H.test("MP #1692 malformed modern authority cannot revive legacy capture", function()
    local rig = install(layout({
        globals = { MODDED_REALM = "true" },
        script_data = { ["eac-untrusted"] = true },
        depth = 1,
    }))
    H.equal(rig.finish_mission(), "native")
    H.equal(rig.saved.issue607_loot_diag_v1, nil)
    H.equal(#rig.logs, 0)
end)

H.test("MP #1692 game 6.12+ modded realm (MODDED_REALM only) captures end_level", function()
    -- Exactly the 6.13.0 shape: no raw flag, and no launch parameter either,
    -- so the capture can only come from MODDED_REALM.
    local rig = install(layout({ globals = { MODDED_REALM = true } }))
    H.equal(rig.finish_mission(), "native")
    H.equal(captured_end_level(rig), true,
        "6.12+ modded realm produced no [mp:607] end_level receipt")
    rig.commands.mp_loot_diag()
    H.truthy(rig.echoes[1]:find("gate=open", 1, true), "summary does not report gate=open")
end)

H.test("MP #1692 game 6.12+ official realm captures nothing even if legacy says modded", function()
    local rig = install(layout({
        globals = { MODDED_REALM = false },
        script_data = { ["eac-untrusted"] = true },
        depth = 1,
    }))
    H.equal(rig.finish_mission(), "native")
    H.equal(rig.saved.issue607_loot_diag_v1, nil)
    H.equal(#rig.logs, 0)
    rig.commands.mp_loot_diag()
    H.truthy(rig.echoes[1]:find("gate=closed", 1, true), "summary does not report gate=closed")
end)

H.test("MP #1692 pre-6.12 layout still captures through the legacy authority", function()
    -- Raw flag true, global absent (6.11.3 shape).
    local flagged = install(layout({ script_data = { ["eac-untrusted"] = true } }))
    flagged.finish_mission()
    H.equal(captured_end_level(flagged), true, "pre-6.12 raw-flag layout lost capture")
    -- Inside an MP EAC-off bracket the raw flag reads nil; the depth answers.
    local bracketed = install(layout({ script_data = {}, depth = 1 }))
    bracketed.finish_mission()
    H.equal(captured_end_level(bracketed), true, "pre-6.12 bracketed call lost capture")
    -- Pre-6.12 official realm: flag false, no launch parameter, depth 0.
    local official = install(layout({ script_data = { ["eac-untrusted"] = false } }))
    official.finish_mission()
    H.equal(official.saved.issue607_loot_diag_v1, nil)
end)

H.test("MP #1692 in-game check passes in the modded realm and fails on a closed gate", function()
    local open = install(layout({ globals = { MODDED_REALM = true } }))
    local check = open.checks.issue1692_loot_diag_gate_open_in_modded_realm
    H.equal(type(check), "function", "issue1692_loot_diag_gate_open_in_modded_realm not registered")
    H.equal(check(), nil)
    local closed = install(layout({ globals = { MODDED_REALM = false } }))
    H.equal(type(closed.checks.issue1692_loot_diag_gate_open_in_modded_realm()), "string")
    H.equal(closed.checks.issue607_local_loot_layer_diagnostic_contract(), nil)
end)

H.test("MP #1692 no loot-diag source reads the raw realm flag", function()
    local runtime = read_source(MP .. "_mp_loot_diag_runtime.lua")
    local main = read_source(MP .. "modded_progression.lua")
    H.equal(runtime:find("eac-untrusted", 1, true), nil)
    H.equal(runtime:find("realm_state", 1, true), nil)
    H.equal(main:find("realm_state =", 1, true), nil)
    H.equal(count_plain(main, 'LootDiag.realm_is_modded(rawget(_G, "MODDED_REALM"), _is_mp_realm)'), 1)
end)
end
