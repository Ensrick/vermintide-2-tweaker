-- test_rig_deus.lua: offline tests of the rig's Chaos Wastes arenas (driver 0.4.9, WP-H-05), the write shield's drop
-- of deusRunStarted and its faked success reply, and the helper group lib/deus.lua.
--
-- A stub game: loading morris_hub switches the mechanism to deus when it arrives (LevelSettings.morris_hub.mechanism);
-- in the deus mechanism, loading a run level sets up a run, whose start runs BackendInterfaceDeusPlayFab.deus_run_started
-- (DeusMechanism._setup_run, deus_mechanism.lua:1213; backend_interface_deus_playfab.lua:100-116): the client
-- prediction, then deusRunStarted on the backend request queue with a callback that hands the result to a copy of
-- PlayFabMirrorBase.handle_deus_result (playfab_mirror_base.lua:2668-2687, which indexes result.FunctionResult);
-- loading inn_level switches back to adventure.
-- This proves the driver's arena sequence, the drop and the helpers' control flow only, never the game's behaviour.
return function(H, repo_root)
    local E = assert(loadfile(repo_root .. "/qa/lua/tests/_rig_driver_env.lua"))()(H, repo_root)
    local tag, first, count = E.tag, E.first, E.count

    local function deus_world(env, opts)
        opts = opts or {}
        local w = { level = "inn_level", mechanism = "adventure", loads = {}, sent = {}, coins = 40, power_ups = {}, handled = {}, tick_no = 0 }
        local hero = env.Managers.player:local_player().player_unit
        local queue = {}
        function queue.enqueue(_, request)
            w.sent[#w.sent + 1] = request.FunctionName
            return #w.sent
        end
        local mirror = { _request_queue = queue, _characters_data_key = "characters_data", _career_data = {}, _career_data_mirror = {},
            _user_data = {}, _user_data_mirror = {}, _read_only_data_mirror = {}, _inventory_items = {},
            _deus_rolled_over_soft_currency = 25 }
        w.mirror = mirror
        -- PlayFabMirrorBase.handle_deus_result (playfab_mirror_base.lua:2668-2687)
        function mirror.handle_deus_result(self, result)
            local function_result = result.FunctionResult
            local deus_journey_cycle_data = function_result.deus_journey_cycle_data
            local deus_rolled_over_soft_currency = function_result.deus_rolled_over_soft_currency
            if deus_rolled_over_soft_currency then
                self._deus_rolled_over_soft_currency = deus_rolled_over_soft_currency
            end
            if deus_journey_cycle_data then
                w.cycle_data_set = true
            end
            w.handled[#w.handled + 1] = { at = w.tick_no, in_coroutine = coroutine.running() ~= nil }
        end
        env.Managers.backend = { get_backend_mirror = function() return mirror end }
        local controller = {
            _run_state = { set_player_soft_currency = function(_, peer, local_id, coins) w.coins_set = peer .. ":" .. local_id; w.coins = coins end },
            get_own_peer_id = function() return "peer1" end,
            get_player_soft_currency = function(_, peer) return peer == "peer1" and w.coins or nil end,
            add_power_ups = function(_, list, local_id, present)
                for _, p in ipairs(list) do w.power_ups[#w.power_ups + 1] = p.name .. "/" .. p.rarity .. "/" .. tostring(local_id) .. "/" .. tostring(present) end
            end,
            has_power_up_by_name = function(_, peer, name, rarity)
                for _, p in ipairs(w.power_ups) do
                    if p:find("^" .. name .. "/" .. rarity .. "/") and peer == "peer1" then return true end
                end
                return false
            end,
        }
        env.DeusPowerUpTemplates = { attack_speed = {} }
        env.DeusPowerUpUtils = { generate_specific_power_up = function(name, rarity) return { name = name, rarity = rarity } end }
        local player = { player_unit = hero, local_player_id = function() return 1 end, career_name = function() return "es_mercenary" end }
        env.Managers.player.local_player = function() return player end
        w.health = { is_invincible = false }
        env.ScriptUnit = { has_extension = function(unit, system) if unit == hero and system == "health_system" then return w.health end end }
        env.Managers.mechanism = {
            current_mechanism_name = function() return w.mechanism end,
            game_mechanism = function() return { get_deus_run_controller = function() return w.run and controller or nil end } end,
            debug_load_level = function(_, level)
                w.loads[#w.loads + 1] = level .. "@" .. w.mechanism
                if w.mechanism == "deus" and level ~= "morris_hub" and level ~= "inn_level" then
                    -- DeusMechanism.debug_load_level for a run level: _setup_run ends with deus_run_started
                    -- (backend_interface_deus_playfab.lua:100-116): predict, then enqueue with cb -> handle_deus_result
                    local m = env.Managers.backend:get_backend_mirror()
                    m._deus_rolled_over_soft_currency = 0
                    local cb = function(result)
                        if opts.callback_raises then
                            error("planted callback error")
                        end
                        m:handle_deus_result(result)
                    end
                    w.enqueued_at = w.tick_no
                    w.enqueue_id = m._request_queue:enqueue({ FunctionName = "deusRunStarted", FunctionParameter = {} }, (not opts.no_callback) and cb or nil)
                    w.handled_at_enqueue = #w.handled
                    w.run = true
                end
                w.pending = { level = level, left = 12 }
            end,
        }
        env.Managers.state.game_mode = { level_key = function() return w.level end }
        function w.tick(object)
            w.tick_no = w.tick_no + 1
            local p = w.pending
            if p then
                p.left = p.left - 1
                if p.left == 8 then E.callback(object, "on_game_state_changed", "enter", "StateLoading") end
                if p.left == 0 then
                    w.level = p.level
                    w.pending = nil
                    if p.level == "morris_hub" then w.mechanism = "deus" elseif p.level == "inn_level" then w.mechanism = "adventure"; w.run = nil end
                    E.callback(object, "on_game_state_changed", "enter", "StateIngame")
                end
            end
        end
        return w
    end

    local function run_deus(cases, arenas, opts)
        local plan = E.make_plan(cases, { arenas = arenas, libs = { E.lib_entry("deus") } })
        local object, env, lines = E.boot(plan)
        local w = deus_world(env, opts)
        E.callback(object, "on_game_state_changed", "enter", "StateIngame")
        for _ = 1, 30000 do
            w.tick(object)
            E.callback(object, "update", 0.1)
            if env.Boot.quit_game then break end
        end
        H.truthy(env.Boot.quit_game, "the driver asked the game to quit")
        return lines, w
    end

    local function case(id, file)
        return { id = id, src = E.read(repo_root .. "/qa/runtime/_rig/" .. file) }
    end

    H.test("rig deus arenas: keep, hub, a run level, back to the keep; the selftest cases pass and deusRunStarted is dropped", function()
        local lines, w = run_deus({ case("deus-hub", "deus_hub.lua"), case("deus-level", "deus_level.lua") },
            { "keep", "deus", "deus:pat_mountain_wastes_path1", "keep" })
        H.equal(table.concat(w.loads, ","), "morris_hub@adventure,pat_mountain_wastes_path1@deus,inn_level@deus",
            "the hub from the keep, the run level from the hub (deus mechanism), the keep from the run")
        H.truthy(first(lines, tag .. "LOAD arena=deus:pat_mountain_wastes_path1 level=pat_mountain_wastes_path1 from=morris_hub$"), "the run level arena starts in the hub, so it loads directly")
        H.truthy(first(lines, tag .. "CASE END id=deus%-hub verdict=PASS"), "deus-hub passes: " .. tostring(first(lines, tag .. "CASE END id=deus%-hub")))
        H.truthy(first(lines, tag .. "CASE END id=deus%-level verdict=PASS"), "deus-level passes: " .. tostring(first(lines, tag .. "CASE END id=deus%-level")))
        H.equal(#w.sent, 0, "deusRunStarted never reached the backend request queue")
        H.equal(count(lines, tag .. "SHIELD blocked=deusRunStarted"), 1, "the shield names the dropped request once")
        H.equal(w.power_ups[1], "attack_speed/rare/1/false", "the boon went through add_power_ups for local player 1, not as a present")
        H.equal(w.coins, 40, "the run's coins restored at cleanup")
        H.equal(w.coins_set, "peer1:1", "coins set for the own peer and real player id 1")
        H.truthy(first(lines, tag .. "DEUS COINS RESTORE id=deus%-level value=40"), "coin restore line")
        H.equal(w.health.is_invincible, false, "invincibility restored")
        -- the faked reply: the game's callback answered once, as playfab_request_success_cb answers it
        H.truthy(w.enqueue_id < 0, "the dropped request got a negative id")
        H.equal(w.handled_at_enqueue, 0, "the callback was not called inside the enqueue")
        H.equal(#w.handled, 1, "the callback answered exactly once")
        H.truthy(w.handled[1].at > w.enqueued_at, "on a later update than the enqueue")
        H.equal(w.handled[1].in_coroutine, false, "in the driver's update, not inside a case coroutine")
        H.equal(w.mirror._deus_rolled_over_soft_currency, 0, "the mirror keeps the client's own prediction")
        H.equal(w.cycle_data_set, nil, "no invented journey cycle data")
        H.equal(count(lines, tag .. "SHIELD blocked=deusRunStarted case=%- reply=next%-update$"), 1, "the drop names the reply")
        H.equal(count(lines, tag .. 'SHIELD replied=deusRunStarted ok=true err="" '), 1, "one SHIELD replied line, ok")
    end)

    H.test("rig deus shield: a raising game callback is reported and counted, the run goes on; no callback, no reply", function()
        local lines, w = run_deus({ case("deus-level", "deus_level.lua") }, { "deus", "deus:pat_mountain_wastes_path1" }, { callback_raises = true })
        H.equal(#w.sent, 0, "still dropped")
        H.truthy(first(lines, tag .. 'SHIELD replied=deusRunStarted ok=false err=".*planted callback error'), "the error is named")
        H.truthy(first(lines, tag .. "CASE END id=deus%-level verdict=FAIL .*the shield answered deusRunStarted without an error"),
            "deus_level sees the reply error: " .. tostring(first(lines, tag .. "CASE END id=deus%-level")))
        H.truthy(first(lines, tag .. "RUN END"), "the run finished")
        local none, w2 = run_deus({ { id = "x", arena = "deus:pat_mountain_wastes_path1", src = "return { arena = 'deus:pat_mountain_wastes_path1', run = function(T) T.expect(true, 'x') end }" } },
            { "deus", "deus:pat_mountain_wastes_path1" }, { no_callback = true })
        H.equal(#w2.sent, 0, "dropped without a callback too")
        H.truthy(first(none, tag .. "SHIELD blocked=deusRunStarted case=%- reply=none$"), "reply=none")
        H.equal(count(none, tag .. "SHIELD replied="), 0, "nothing to answer")
    end)

    H.test("rig deus arenas: already in the deus mechanism a run level loads directly; helpers outside a run are INCONCLUSIVE", function()
        local lines, w = run_deus({
            { id = "hub-no-run", arena = "deus", src = "return { arena = 'deus', run = function(T) T.deus_run_controller() end }" },
            { id = "unknown-boon", arena = "deus:sig_crag_khorne_path2", src = "return { arena = 'deus:sig_crag_khorne_path2', run = function(T) T.grant_boon('no_such_boon') end }" },
        }, { "deus", "deus:sig_crag_khorne_path2" })
        H.equal(table.concat(w.loads, ","), "morris_hub@adventure,sig_crag_khorne_path2@deus", "no second hub load once the mechanism is deus")
        H.truthy(first(lines, tag .. "CASE END id=hub%-no%-run verdict=INCONCLUSIVE .*a Chaos Wastes run is active"), "no run in the hub")
        H.truthy(first(lines, tag .. "CASE END id=unknown%-boon verdict=INCONCLUSIVE .*boon no_such_boon exists"), "unknown boon")
        H.equal(#w.sent, 0, "nothing reached the queue")
    end)

    H.test("rig deus arenas: from the keep a run level goes through the hub; backend_shield false sends deusRunStarted", function()
        local plan = E.make_plan({ { id = "x", arena = "deus:pat_tower_nurgle_path1", src = "return { arena = 'deus:pat_tower_nurgle_path1', run = function(T) T.expect(true, 'x') end }" } },
            { arenas = { "deus:pat_tower_nurgle_path1" }, backend_shield = false })
        local object, env, lines = E.boot(plan)
        local w = deus_world(env)
        E.callback(object, "on_game_state_changed", "enter", "StateIngame")
        for _ = 1, 30000 do
            w.tick(object)
            E.callback(object, "update", 0.1)
            if env.Boot.quit_game then break end
        end
        H.equal(table.concat(w.loads, ","), "morris_hub@adventure,pat_tower_nurgle_path1@deus", "from the keep a run level arena goes through the hub first")
        H.truthy(first(lines, tag .. "LOAD arena=deus:pat_tower_nurgle_path1 level=morris_hub from=inn_level then=pat_tower_nurgle_path1"), "LOAD names the hub as the way in")
        H.truthy(first(lines, tag .. "LOAD arena=deus:pat_tower_nurgle_path1 level=pat_tower_nurgle_path1 from=morris_hub mechanism=deus"), "then the run level from the hub")
        H.truthy(first(lines, tag .. "CASE END id=x verdict=PASS"), "the case in the run level ran")
        H.equal(table.concat(w.sent, ","), "deusRunStarted", "with the shield off the request is sent")
        H.equal(count(lines, tag .. "SHIELD blocked="), 0, "nothing blocked")
        H.equal(count(lines, tag .. "SHIELD replied="), 0, "and nothing faked")
    end)
end
