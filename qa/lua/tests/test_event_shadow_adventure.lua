return function(H, repo_root)
    local policy_path = repo_root
        .. "/event_tweaker/scripts/mods/event_tweaker/event_tweaker_shadow_policy.lua"
    local Policy = assert(loadfile(policy_path))()

    local function read(path)
        local file = assert(io.open(path, "rb"))
        local content = file:read("*a")
        file:close()
        return content
    end

    H.test("Event Tweaker Shadow policy preserves native Weaves", function()
        H.equal(Policy.plan(true, true, false, false), "native_weave")
    end)

    H.test("Event Tweaker Shadow adapter requires code and capability parity", function()
        H.equal(Policy.plan(true, false, true, true), "adventure_adapter")
        H.equal(Policy.plan(true, false, false, true), "drop_peer_capability")
        H.equal(Policy.plan(true, false, true, false), "drop_adapter_unavailable")
        H.equal(Policy.plan(false, false, false, false), "passthrough")
        H.equal(Policy.ADVENTURE_RADIUS, 6)
        H.equal(Policy.ADVENTURE_DAMAGE_TAKEN, -0.8)
    end)

    -- Issues 413 + 1123: load the REAL adapter module in a sandbox and drive
    -- the in-game-reachable session transitions. The shared vanilla buff table
    -- must never be mutated; the Adventure value lives on a private clone that
    -- is swapped in per session and restored on stop / disable.
    local adapter_path = repo_root
        .. "/event_tweaker/scripts/mods/event_tweaker/_evt_shadow_adventure.lua"

    local function build_sandbox()
        local sub_buff = {
            name = "mutator_shadow_damage_reduction",
            stat_buff = "damage_taken",
            wind_mutator = true,
        }
        local vanilla_template = { buffs = { sub_buff } }
        local counters = { server_start = 0, server_stop = 0, client_stop = 0 }
        local shadow_template = {
            server = { stop_function = function()
                counters.server_stop = counters.server_stop + 1
            end },
            client = { stop_function = function()
                counters.client_stop = counters.client_stop + 1
            end },
            server_start_function = function()
                counters.server_start = counters.server_start + 1
            end,
            server_update_function = function() end,
            client_start_function = function() end,
            client_update_function = function() end,
            client_player_respawned_function = function() end,
        }
        local globals = {
            MutatorTemplates = { shadow = shadow_template },
            BuffTemplates = { mutator_shadow_damage_reduction = vanilla_template },
        }
        local state = { weave = false }
        local mod = {
            _evt = {
                rt_register = function() end,
                weave_wind_active = function() return state.weave end,
                peer_feature_wire_safe = function() return true end,
            },
            dofile = function() error("peer-parity lib is out of scope offline") end,
            echo = function() end,
        }
        local env = {
            get_mod = function() return mod end,
            require = function(path)
                if path == "scripts/mods/event_tweaker/event_tweaker_shadow_policy" then
                    return Policy
                end
                error("unexpected require: " .. tostring(path))
            end,
            _G = globals,
            rawget = rawget, pairs = pairs, ipairs = ipairs, type = type,
            tostring = tostring, pcall = pcall, printf = function() end,
            string = string, table = table, math = math,
            Vector3 = { distance_squared = function() return 0 end },
            ScriptUnit = { has_extension = function() return nil end },
            Unit = { alive = function() return false end },
        }
        local chunk = assert(loadfile(adapter_path))
        setfenv(chunk, env)
        chunk()
        return {
            mod = mod, state = state, counters = counters,
            globals = globals, vanilla = vanilla_template, sub = sub_buff,
            shadow = globals.MutatorTemplates.shadow,
        }
    end

    H.test("Event Tweaker Shadow boot leaves the shared vanilla buff table untouched", function()
        local sb = build_sandbox()
        H.truthy(sb.globals.BuffTemplates.mutator_shadow_damage_reduction == sb.vanilla)
        H.equal(sb.sub.multiplier, nil)
    end)

    H.test("Event Tweaker Shadow session swaps in a clone and restores vanilla on stop", function()
        local sb = build_sandbox()
        local data = {}
        sb.shadow.server_start_function({}, data)
        local live = sb.globals.BuffTemplates.mutator_shadow_damage_reduction
        H.truthy(live ~= sb.vanilla)
        H.truthy(live.buffs[1] ~= sb.sub)
        H.equal(live.buffs[1].multiplier, Policy.ADVENTURE_DAMAGE_TAKEN)
        H.equal(sb.sub.multiplier, nil)
        sb.shadow.server.stop_function({}, data, false)
        H.truthy(sb.globals.BuffTemplates.mutator_shadow_damage_reduction == sb.vanilla)
        H.equal(sb.sub.multiplier, nil)
        H.equal(sb.counters.server_stop, 1)
    end)

    H.test("Event Tweaker Shadow native Weave path delegates without swapping", function()
        local sb = build_sandbox()
        sb.state.weave = true
        sb.shadow.server_start_function({}, {})
        H.equal(sb.counters.server_start, 1)
        H.truthy(sb.globals.BuffTemplates.mutator_shadow_damage_reduction == sb.vanilla)
        H.equal(sb.sub.multiplier, nil)
    end)

    H.test("Event Tweaker Shadow restores vanilla when the mod is disabled mid-session", function()
        local sb = build_sandbox()
        local data = {}
        sb.shadow.client_start_function({}, data)
        H.truthy(sb.globals.BuffTemplates.mutator_shadow_damage_reduction ~= sb.vanilla)
        H.equal(type(sb.mod.on_disabled), "function")
        sb.mod.on_disabled()
        H.truthy(sb.globals.BuffTemplates.mutator_shadow_damage_reduction == sb.vanilla)
        H.equal(sb.sub.multiplier, nil)
    end)

    H.test("Event Tweaker Shadow never clobbers a third party's template replacement", function()
        local sb = build_sandbox()
        local data = {}
        sb.shadow.server_start_function({}, data)
        local foreign = { buffs = { { name = "mutator_shadow_damage_reduction" } } }
        sb.globals.BuffTemplates.mutator_shadow_damage_reduction = foreign
        sb.shadow.server.stop_function({}, data, false)
        H.truthy(sb.globals.BuffTemplates.mutator_shadow_damage_reduction == foreign)
        H.equal(sb.sub.multiplier, nil)
        H.equal(sb.counters.server_stop, 1)
    end)

    H.test("Event Tweaker Shadow adapter never spawns weave-only assets", function()
        local runtime = read(repo_root
            .. "/event_tweaker/scripts/mods/event_tweaker/_evt_shadow_adventure.lua")
        H.equal(runtime:find('World%.spawn_unit%('), nil)
        H.equal(runtime:find('Unit%.light%('), nil)
        H.truthy(runtime:find('mutator_shadow_damage_reduction', 1, true))
        H.truthy(runtime:find('set_min_fade', 1, true))
        H.truthy(runtime:find('remove_ping_from_unit', 1, true))
        H.truthy(runtime:find('et_shadow_adventure_v1', 1, true))
    end)

    H.test("Event Tweaker Shadow selection gates before stock RPC activation", function()
        local entry = read(repo_root
            .. "/event_tweaker/scripts/mods/event_tweaker/event_tweaker.lua")
        local selection = read(repo_root
            .. "/event_tweaker/scripts/mods/event_tweaker/_evt_selection.lua")
        local guard = read(repo_root
            .. "/event_tweaker/scripts/mods/event_tweaker/_evt_guard430_curse_parity.lua")

        local adapter_at = assert(entry:find('_evt_shadow_adventure', 1, true))
        local selection_at = assert(entry:find('_evt_selection', adapter_at, true))
        H.truthy(adapter_at < selection_at)
        H.truthy(selection:find('decision == "adventure_adapter"', 1, true))
        H.truthy(selection:find('set_shadow_requested(true)', 1, true))
        H.truthy(guard:find('_shadow_requested or _shadow_active', 1, true))
        H.truthy(guard:find('ET.peer_feature_wire_safe', 1, true))
    end)
end
