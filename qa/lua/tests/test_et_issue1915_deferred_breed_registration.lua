-- #1915: Enemy Tweaker registers its two custom breeds once the network
-- capacity authority exists, not at mod load. Four groups: the trigger
-- timings (both hooks, the immediate try, and the update trigger that also
-- covers a VMF-disabled copy), a client registers before any NetworkState
-- decode, the load-time channel forwarder delivers to the library receiver,
-- and the custom-breed fence stays closed until the deferred install.
return function(H, repo_root)
    local base = repo_root .. "/enemy_tweaker/scripts/mods/enemy_tweaker/"
    local R = assert(loadfile(repo_root
        .. "/qa/lua/tests/fixtures/et_custom_breed_parity_runtime.lua"))()(H, repo_root)
    local with_runtime = R.with_runtime

    local INIT_NETWORK = "StateLoadingRestartNetwork._init_network"
    local GNM_INIT = "GameNetworkManager.init"
    local CAPS = {
        damage_source_id = "cap:16384",
        statistics_path_lookup = "cap:1024",
        damage_hotjoin_sync = "cap:16384",
    }
    local NO_CAPS = {
        damage_source_id = "damage_source_cap_unavailable",
        statistics_path_lookup = "statistics_path_cap_unavailable",
        damage_hotjoin_sync = "health_sync_cap_unavailable",
    }

    local function read(path)
        local handle = assert(io.open(path, "rb"))
        local source = handle:read("*a")
        handle:close()
        return source
    end

    local function count_plain(text, needle)
        local count, at = 0, 1
        while true do
            local found = text:find(needle, at, true)
            if not found then return count end
            count, at = count + 1, found + #needle
        end
    end

    local function fresh_scheduler()
        return assert(loadfile(base .. "_et_custom_breed_scheduler.lua"))()
    end

    local function named_jobs(order, results)
        local jobs = {}
        for _, name in ipairs({ "et_skaven_warlord", "et_chosen_greataxe" }) do
            jobs[#jobs + 1] = {
                spec = { name = name },
                on_result = function(ok, reason, trigger)
                    order[#order + 1] = name
                    results[name] = { ok = ok, reason = reason, trigger = trigger }
                end,
            }
        end
        return jobs
    end

    local function has_log(logs, needle)
        for i = 1, #logs do
            if logs[i]:find(needle, 1, true) then return true end
        end
        return false
    end

    -- ------------------------------------------------------------------
    -- Engine-free scheduler contract
    -- ------------------------------------------------------------------
    H.test("ET #1915 scheduler waits for all three caps and runs the queue once in order", function()
        local S = fresh_scheduler()
        H.equal(S.caps_ready(CAPS), true)
        H.equal(select(2, S.caps_ready(nil)), "verdicts_unavailable")
        local partial = { damage_source_id = "cap:16384",
            statistics_path_lookup = "cap:1024",
            damage_hotjoin_sync = "health_sync_cap_unavailable" }
        local ready, reason = S.caps_ready(partial)
        H.equal(ready, false)
        H.equal(reason, "damage_hotjoin_sync=health_sync_cap_unavailable")
        H.equal(S.caps_ready({ damage_source_id = "cap:x",
            statistics_path_lookup = "cap:1", damage_hotjoin_sync = "cap:1" }), false)

        local verdicts, calls, ready_calls, rows = NO_CAPS, {}, {}, {}
        local order, results = {}, {}
        local scheduler = S.new({
            registrar = {
                capacity_verdicts = function() return verdicts end,
                register = function(spec)
                    calls[#calls + 1] = spec.name
                    return true, "registered"
                end,
            },
            jobs = named_jobs(order, results),
            on_ready = function(trigger) ready_calls[#ready_calls + 1] = trigger end,
            log = function(fmt, ...) rows[#rows + 1] = string.format(fmt, ...) end,
        })
        H.equal(scheduler.try("load"), false)
        H.equal(scheduler.try("load"), false)
        H.equal(#calls, 0, "registered without capacities")
        H.equal(#rows, 1, "a repeated trigger logged twice")
        H.truthy(rows[1]:find("[et:451] custom-breed registration deferred trigger=load waiting=damage_source_id=damage_source_cap_unavailable", 1, true))

        verdicts = CAPS
        H.equal(scheduler.try("restart_network"), true)
        H.equal(table.concat(calls, ","), "et_skaven_warlord,et_chosen_greataxe",
            "the wire order must stay Warlord then Chosen")
        H.equal(table.concat(order, ","), "et_skaven_warlord,et_chosen_greataxe")
        H.equal(results.et_skaven_warlord.trigger, "restart_network")
        H.equal(results.et_chosen_greataxe.ok, true)
        H.equal(#ready_calls, 1)
        H.equal(ready_calls[1], "restart_network")
        H.equal(scheduler.done(), true)
        H.equal(scheduler.ran_trigger(), "restart_network")
        H.truthy(rows[#rows]:find("custom-breed registration ran trigger=restart_network jobs=2 ready=ok", 1, true))

        local ok, why = scheduler.try("game_network_manager")
        H.equal(ok, false)
        H.equal(why, "done")
        H.equal(#calls, 2, "a later trigger registered again")
        H.equal(#ready_calls, 1, "a later trigger re-installed parity")
    end)

    H.test("ET #1915 scheduler bounds wait rows and survives throwing jobs and ready", function()
        local S = fresh_scheduler()
        local rows, results = {}, {}
        local verdicts = NO_CAPS
        local scheduler = S.new({
            registrar = {
                capacity_verdicts = function()
                    if verdicts == "throw" then error("verdicts-threw") end
                    return verdicts
                end,
                register = function(spec)
                    if spec.name == "et_skaven_warlord" then error("register-threw") end
                    return nil, "damage_source_cap_exceeded"
                end,
            },
            jobs = named_jobs({}, results),
            on_ready = function() error("ready-threw") end,
            log = function(fmt, ...) rows[#rows + 1] = string.format(fmt, ...) end,
        })
        for i = 1, 9 do scheduler.try("trigger" .. i) end
        H.equal(#rows, S.WAIT_LOG_CAP)
        verdicts = "throw"
        H.equal(scheduler.try("throwing"), false)
        verdicts = CAPS
        H.equal(scheduler.try("restart_network"), true)
        H.equal(results.et_skaven_warlord.ok, nil)
        H.truthy(tostring(results.et_skaven_warlord.reason):find("register_threw:", 1, true))
        H.equal(results.et_chosen_greataxe.reason, "damage_source_cap_exceeded",
            "a throwing first job stopped the second")
        H.truthy(tostring(scheduler.ready_error()):find("ready-threw", 1, true))
        H.truthy(rows[#rows]:find("ready=error:", 1, true))
    end)

    -- ------------------------------------------------------------------
    -- Group 1: both trigger timings, and the immediate try
    -- ------------------------------------------------------------------
    H.test("ET #1915 cold boot defers, then the restart-network return registers once", function()
        local order, results = {}, {}
        with_runtime({ caps_at_load = false, jobs = named_jobs(order, results) },
            function(runtime)
                local ET = runtime.mod._et
                H.equal(#runtime.register_calls, 0, "registered at load without capacities")
                H.equal(ET.CustomBreedParity, nil)
                H.equal(ET.CustomBreedIdentitySnapshot, nil)
                H.equal(runtime.mod._et_custom_breed_peer_parity, nil)
                H.equal(ET.CustomBreedScheduler.done(), false)
                H.truthy(has_log(runtime.logs, "custom-breed registration deferred trigger=load"))
                local init_network = assert(runtime.safe_hooks[INIT_NETWORK],
                    "restart-network trigger missing")
                local gnm_init = assert(runtime.safe_hooks[GNM_INIT],
                    "GameNetworkManager backstop missing")

                runtime.caps.available = true
                init_network({})
                H.equal(#runtime.register_calls, 2)
                H.equal(runtime.register_calls[1].name, "et_skaven_warlord")
                H.equal(runtime.register_calls[2].name, "et_chosen_greataxe")
                H.equal(results.et_chosen_greataxe.trigger, "restart_network")
                H.equal(ET.CustomBreedScheduler.ran_trigger(), "restart_network")
                local parity = assert(ET.CustomBreedParity, "parity not installed after the trigger")
                H.equal(parity:is_installed(), true)
                H.equal(runtime.mod._et_custom_breed_peer_parity, parity)
                H.equal(type(ET.CustomBreedIdentitySnapshot), "table")
                H.truthy(has_log(runtime.logs, "exact custom-breed parity installed identity="))

                gnm_init({})
                init_network({})
                H.equal(#runtime.register_calls, 2, "a later trigger registered again")
                H.equal(ET.CustomBreedParity, parity, "a later trigger replaced parity")
            end)
    end)

    H.test("ET #1915 GameNetworkManager.init is the backstop when the restart return has no caps", function()
        with_runtime({ caps_at_load = false, jobs = named_jobs({}, {}) },
            function(runtime)
                local ET = runtime.mod._et
                runtime.safe_hooks[INIT_NETWORK]({})
                H.equal(#runtime.register_calls, 0)
                H.equal(ET.CustomBreedParity, nil)
                runtime.caps.available = true
                runtime.safe_hooks[GNM_INIT]({})
                H.equal(#runtime.register_calls, 2)
                H.equal(ET.CustomBreedScheduler.ran_trigger(), "game_network_manager")
                H.equal(ET.CustomBreedParity:is_installed(), true)
            end)
    end)

    H.test("ET #1915 a VMF-disabled copy registers on the first update after NetworkConstants appears", function()
        local previous_constants = rawget(_G, "NetworkConstants")
        local results = {}
        local ok, err = pcall(with_runtime,
            { caps_at_load = false, jobs = named_jobs({}, results) },
            function(runtime)
                local ET, mod = runtime.mod._et, runtime.mod
                rawset(_G, "NetworkConstants", nil)
                -- Disabled: VMF keeps hooks inactive (hooks.lua:125,147), so
                -- the restart and GameNetworkManager hooks are never called;
                -- VMF still calls mod.update (events.lua:44-51).
                mod.update(0.016)
                mod.update(0.016)
                H.equal(#runtime.register_calls, 0, "registered before NetworkConstants exists")
                H.equal(has_log(runtime.logs, "trigger=update"), false,
                    "the update trigger probed capacities before NetworkConstants existed")

                -- network_constants.lua ran, but a capacity is still unreadable.
                rawset(_G, "NetworkConstants", {})
                mod.update(0.016)
                mod.update(0.016)
                H.equal(#runtime.register_calls, 0)
                local waiting_rows = 0
                for i = 1, #runtime.logs do
                    if runtime.logs[i]:find("deferred trigger=update", 1, true) then
                        waiting_rows = waiting_rows + 1
                    end
                end
                H.equal(waiting_rows, 1, "the per-frame trigger logged more than once")

                runtime.caps.available = true
                mod.update(0.016)
                H.equal(#runtime.register_calls, 2)
                H.equal(results.et_skaven_warlord.trigger, "update")
                H.equal(ET.CustomBreedScheduler.ran_trigger(), "update")
                H.equal(ET.CustomBreedParity:is_installed(), true)
                for _ = 1, 5 do mod.update(0.016) end
                runtime.safe_hooks[INIT_NETWORK]({})
                runtime.safe_hooks[GNM_INIT]({})
                H.equal(#runtime.register_calls, 2, "registered twice")
            end)
        rawset(_G, "NetworkConstants", previous_constants)
        if not ok then error(err, 0) end
    end)

    H.test("ET #1915 immediate try registers at load when the network is already up", function()
        local results = {}
        with_runtime({ jobs = named_jobs({}, results) }, function(runtime)
            local ET = runtime.mod._et
            H.equal(#runtime.register_calls, 2)
            H.equal(results.et_skaven_warlord.trigger, "load")
            H.equal(ET.CustomBreedScheduler.ran_trigger(), "load")
            H.equal(ET.CustomBreedParity:is_installed(), true)
            runtime.safe_hooks[INIT_NETWORK]({})
            runtime.safe_hooks[GNM_INIT]({})
            H.equal(#runtime.register_calls, 2)
        end)
    end)

    -- ------------------------------------------------------------------
    -- Group 2: a client registers before any NetworkState decode
    -- ------------------------------------------------------------------
    H.test("ET #1915 a client registers on the restart return before any breed-map decode", function()
        local saved, lookup = {}, nil
        local function strict(tbl, name)
            return setmetatable(tbl, { __index = function(_, key)
                -- network_lookup.lua:2360-2364 strict __index
                error("[NetworkLookup.lua] Table " .. name .. " does not contain key: " .. tostring(key))
            end })
        end
        local function restore(name)
            local row = assert(saved[name], "no saved rows for " .. tostring(name))
            rawset(lookup.ctx.breeds, name, row.breed)
            for axis, index in pairs(row.ids) do
                rawset(lookup.ctx.network_lookup[axis], index, name)
                rawset(lookup.ctx.network_lookup[axis], name, index)
            end
            return true, "registered"
        end
        with_runtime({
            caps_at_load = false,
            jobs = named_jobs({}, {}),
            register = function(spec) return restore(spec.name) end,
        }, function(runtime)
            lookup = runtime
            local ctx = runtime.ctx
            -- A cold client: the custom breeds are not on any axis yet.
            for _, name in ipairs({ "et_skaven_warlord", "et_chosen_greataxe" }) do
                local row = { breed = ctx.breeds[name], ids = {} }
                for _, axis in ipairs({ "breeds", "damage_sources", "statistics_path_names" }) do
                    local index = ctx.network_lookup[axis][name]
                    row.ids[axis] = index
                    ctx.network_lookup[axis][index] = nil
                    ctx.network_lookup[axis][name] = nil
                end
                ctx.breeds[name] = nil
                saved[name] = row
            end
            strict(ctx.network_lookup.breeds, "breeds")
            runtime.managers.player.is_server = false
            runtime.managers.state.network = { is_server = false }

            -- NetworkState decode_breed_map indexes NetworkLookup.breeds by id
            -- (network_state_spec.lua:278-297): before registration it fails.
            local warlord_id = saved.et_skaven_warlord.ids.breeds
            H.equal(pcall(function() return ctx.network_lookup.breeds[warlord_id] end), false,
                "an undecodable breed id must hit the strict lookup")
            H.equal(pcall(function() return ctx.network_lookup.breeds.et_skaven_warlord end), false,
                "the strict reverse lookup must refuse an unregistered breed")

            -- StateLoadingRestartNetwork.on_enter -> _init_network (dofiles
            -- network_constants) -> hook_safe callback, all before any update.
            local function on_enter()
                runtime.caps.available = true -- state_loading_restart_network.lua:124/:161
                runtime.safe_hooks[INIT_NETWORK]({})
            end
            on_enter()
            H.equal(#runtime.register_calls, 2, "client did not register (no is_server gate)")
            H.equal(ctx.network_lookup.breeds[warlord_id], "et_skaven_warlord")
            H.equal(ctx.network_lookup.breeds.et_chosen_greataxe,
                saved.et_chosen_greataxe.ids.breeds)
            local parity = assert(runtime.mod._et.CustomBreedParity,
                "client parity not installed after registration")
            H.equal(parity:is_installed(), true)
            H.equal(type(runtime.mod._et.CustomBreedIdentitySnapshot.identity), "string")
        end)
    end)

    -- ------------------------------------------------------------------
    -- Group 3: the load-time channel forwarder delivers to the lib receiver
    -- ------------------------------------------------------------------
    H.test("ET #1915 load-time forwarder hands traffic to the deferred parity receiver", function()
        with_runtime({ caps_at_load = false, vmf_class_methods = true, jobs = named_jobs({}, {}) },
            function(runtime)
                local mod, ET = runtime.mod, runtime.mod._et
                H.equal(runtime.vmf.register_calls, 1, "channel not registered at load")
                H.equal(rawget(mod, "network_register"), nil)
                -- VMF builds its network dictionary once all mods load
                -- (vmf_loader.lua:66-70); later registrations are refused.
                runtime.vmf.network_initialized = true

                local sends_before = #runtime.sends
                runtime.receiver("early", 1, 0, "any-identity", "early-e1", "q", "")
                H.equal(#runtime.sends, sends_before, "forwarder answered before ready")
                H.equal(ET.CustomBreedParity, nil)

                local update_before = mod.update
                runtime.caps.available = true
                runtime.safe_hooks[INIT_NETWORK]({})
                local parity = assert(ET.CustomBreedParity,
                    "install fell through to the refused VMF register")
                H.equal(parity:is_installed(), true)
                H.equal(runtime.vmf.register_calls, 1, "install re-registered the channel")
                H.equal(rawget(mod, "network_register"), nil,
                    "the network_register shadow outlived install")
                H.equal(type(mod.network_register), "function")
                H.equal(type(mod.update), "function")
                H.equal(rawequal(mod.update, update_before), false,
                    "the library did not take its late mod.update tick")

                local identity = ET.CustomBreedIdentitySnapshot.identity
                runtime.receiver("p1", 1, 0, identity, "p1-e1", "remote-query", "")
                H.equal(parity:peer_has("p1"), true, "forwarded query did not reach the library")
                local reply = assert(runtime.latest.p1, "library reply missing")
                H.equal(reply.reply, 1)
                H.equal(reply.echo, "remote-query")
                H.equal(reply.identity, identity)

                runtime.receiver("p2", 1, 0, "wrong-identity", "p2-e1", "remote-query", "")
                H.equal(parity:peer_has("p2"), false)
            end)
    end)

    H.test("ET #1915 a failed deferred install leaves the forwarder inert", function()
        with_runtime({ caps_at_load = false, parity_unavailable = true, jobs = named_jobs({}, {}) },
            function(runtime)
                runtime.caps.available = true
                runtime.safe_hooks[INIT_NETWORK]({})
                H.equal(runtime.mod._et.CustomBreedParity, nil)
                local sends_before = #runtime.sends
                runtime.receiver("p1", 1, 0, "x", "p1-e1", "q", "")
                H.equal(#runtime.sends, sends_before)
                H.truthy(has_log(runtime.logs, "WARN exact custom-breed parity unavailable"))
            end)
    end)

    -- ------------------------------------------------------------------
    -- Group 4: the fence is closed until the deferred install
    -- ------------------------------------------------------------------
    H.test("ET #1915 custom spawns and hot joins stay fenced until parity is ready", function()
        with_runtime({
            caps_at_load = false,
            jobs = named_jobs({}, {}),
            live_counts = { et_chosen_greataxe = 1 },
        }, function(runtime)
            local ET = runtime.mod._et
            local safe, reason = ET.custom_breeds_exact_safe()
            H.equal(safe, false)
            H.equal(reason, "parity-unavailable")
            local donor, decision = ET.custom_breed_spawn_floor(
                runtime.ctx.breeds.et_chosen_greataxe, "pre-ready")
            H.equal(donor, runtime.ctx.breeds.chaos_warrior)
            H.equal(decision, "vanilla-donor")

            local sync = assert(runtime.hooks["GameNetworkManager.set_peer_synchronizing"])
            local synced = assert(runtime.hooks[
                "NetworkServer.is_network_state_fully_synced_for_peer"])
            local native_calls, kicks = 0, 0
            local manager = { network_server = { my_peer_id = "host",
                kick_peer = function() kicks = kicks + 1 end } }
            local function native() native_calls = native_calls + 1 end
            H.equal(sync(native, manager, "early"), nil)
            H.equal(native_calls, 0, "a remote peer synced while custom state is live and parity absent")
            H.equal(ET.custom_breed_hot_join_phase("early"), "pending")
            H.equal(synced(function() return true end, {}, "early"), false)
            H.equal(kicks, 0)

            runtime.caps.available = true
            runtime.safe_hooks[INIT_NETWORK]({})
            local parity = assert(ET.CustomBreedParity)
            H.equal(synced(function() return true end, {}, "early"), false,
                "ready alone admitted a peer without exact proof")
            local identity = ET.CustomBreedIdentitySnapshot.identity
            runtime.receiver("early", 1, 0, identity, "early-e1", "remote-query", "")
            H.equal(parity:peer_has("early"), true)
            H.equal(synced(function() return true end, {}, "early"), true)
            H.equal(native_calls, 1)
            H.equal(kicks, 0)
            H.equal(ET.custom_breed_hot_join_phase("early"), "admitted")
        end)
    end)

    -- ------------------------------------------------------------------
    -- Warlord donor: the deferred clone still gets the pristine Champion
    -- ------------------------------------------------------------------
    H.test("ET #1915 deferred Warlord clone restores the pristine Champion fields", function()
        local B = assert(loadfile(base .. "enemy_tweaker_breeds.lua"))()
        local Identity = assert(loadfile(base .. "_et_custom_breed_identity.lua"))()
        local champion = {
            name = "skaven_storm_vermin_champion", race = "skaven", boss = true,
            max_health = { 300, 350, 400, 500, 800, 800, 800, 800 },
            ai_strength = 6, ai_toughness = 3,
        }
        local ET = {
            CustomBreedIdentity = Identity,
            CustomBreedRegistrar = {},
            rt_register = function() end,
        }
        local mod = { _et = ET, echo = function() end }
        mod.hook = function() end
        local module_name = "scripts/mods/enemy_tweaker/enemy_tweaker_breeds"
        local keys = { "get_mod", "printf", "UISettings", "GrudgeMarkedNames", "Breeds" }
        local saved = {}
        for i = 1, #keys do saved[keys[i]] = rawget(_G, keys[i]) end
        local saved_module = package.loaded[module_name]
        local ok, err = pcall(function()
            rawset(_G, "get_mod", function() return mod end)
            rawset(_G, "printf", function() end)
            rawset(_G, "UISettings", { breed_textures = {} })
            rawset(_G, "GrudgeMarkedNames", {})
            rawset(_G, "Breeds", { skaven_storm_vermin_champion = champion })
            package.loaded[module_name] = B
            assert(loadfile(base .. "_et_skaven_warlord_breed.lua"))()
        end)
        for i = 1, #keys do rawset(_G, keys[i], saved[keys[i]]) end
        package.loaded[module_name] = saved_module
        if not ok then error(err, 0) end

        local job = assert(ET.CustomBreedJobs and ET.CustomBreedJobs[1], "Warlord job not queued")
        H.equal(#ET.CustomBreedJobs, 1)
        H.equal(job.spec.name, "et_skaven_warlord")
        H.equal(mod._et_warlord2_ready, false, "readiness published before registration")

        -- _et_champion_warlord.lua:100-103 retune, applied after this load.
        local vanilla_health = champion.max_health
        champion.max_health = { 52, 104, 156, 208, 260, 340, 420, 500 }
        champion.ai_strength, champion.ai_toughness = 10, 10
        champion.primary_armor_category = 6

        local clone = {}
        for key, value in pairs(champion) do clone[key] = value end
        clone.max_health = { unpack(champion.max_health) }
        job.spec.configure(clone)
        H.equal(clone.max_health[8], 800)
        H.equal(clone.max_health[1], 300)
        H.equal(clone.ai_strength, 6)
        H.equal(clone.ai_toughness, 3)
        H.equal(clone.primary_armor_category, nil)
        H.equal(clone.display_name, B.ET_SKAVEN_WARLORD_NAME_KEY)
        H.equal(job.spec.validate_breed(clone), true)
        H.equal(rawequal(clone.max_health, vanilla_health), false,
            "the clone shares the vanilla health table")
        clone.max_health[8] = 1
        H.equal(vanilla_health[8], 800, "configure aliased the recorded health")
        H.equal(champion.max_health[8], 500, "configure touched the shared Champion")
        H.equal(champion.ai_strength, 10)
    end)

    -- ------------------------------------------------------------------
    -- Wiring: one hook per pair, scheduler before the fences
    -- ------------------------------------------------------------------
    H.test("ET #1915 wiring: owners queue, parity owns the scheduler and both triggers", function()
        local parity = read(base .. "_et_custom_breed_parity.lua")
        local warlord = read(base .. "_et_skaven_warlord_breed.lua")
        local chosen = read(base .. "_et_boss_ideas.lua")
        local entry = read(base .. "enemy_tweaker.lua")
        H.equal(count_plain(parity, 'mod:dofile("scripts/mods/enemy_tweaker/_et_custom_breed_scheduler")'), 1)
        H.equal(entry:find("_et_custom_breed_scheduler", 1, true), nil,
            "the entry is at its decomposition ceiling")
        local register_at = assert(parity:find("pcall(mod.network_register, mod, CHANNEL, _forward_channel)", 1, true))
        local try_at = assert(parity:find('scheduler.try("load")', register_at, true))
        local restart_at = assert(parity:find('mod:hook_safe("StateLoadingRestartNetwork", "_init_network"', try_at, true))
        local backstop_at = assert(parity:find('mod:hook_safe("GameNetworkManager", "init"', restart_at, true))
        local fence_at = assert(parity:find('mod:hook("GameNetworkManager", "set_peer_synchronizing"', backstop_at, true))
        H.truthy(register_at < try_at and try_at < restart_at and restart_at < backstop_at
            and backstop_at < fence_at)
        local update_at = assert(parity:find(
            'if not scheduler.done() and rawget(_G, "NetworkConstants") ~= nil then', backstop_at, true))
        H.truthy(parity:find('scheduler.try("update")', update_at, true) ~= nil)
        H.equal(count_plain(parity, '"StateLoadingRestartNetwork", "_init_network"'), 1)
        H.equal(count_plain(parity, '"GameNetworkManager", "init"'), 1)
        for _, name in ipairs({ "_et_skaven_warlord_breed.lua", "_et_boss_ideas.lua",
                "_et_champion_warlord.lua", "_et_lifecycle.lua", "_et_director_hooks.lua" }) do
            local text = read(base .. name)
            H.equal(text:find('"StateLoadingRestartNetwork"', 1, true), nil, name .. " hooks the restart pair")
            H.equal(text:find('"GameNetworkManager", "init"', 1, true), nil, name .. " hooks GameNetworkManager.init")
        end
        local warlord_job = assert(warlord:find("jobs[#jobs + 1] = { spec = {", 1, true))
        H.truthy(warlord_job > 0)
        H.truthy(chosen:find("jobs[#jobs + 1] = { spec = {", 1, true) ~= nil)
        local warlord_at = assert(entry:find("_et_skaven_warlord_breed", 1, true))
        local chosen_at = assert(entry:find("_et_boss_ideas", warlord_at, true))
        local parity_at = assert(entry:find("_et_custom_breed_parity", chosen_at, true))
        H.truthy(warlord_at < chosen_at and chosen_at < parity_at,
            "queue order is the manifest order")
    end)
end
