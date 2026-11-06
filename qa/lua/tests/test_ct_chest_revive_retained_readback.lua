-- #299: execute the actual installed chest-completion callback, not a copied
-- rescue implementation. Optional load_candidate binds ignored-overlay evidence;
-- normal QA loads the actual production Dev owner and unchanged policy.
-- Native teleport_to writes position immediately (player_unit_locomotion_extension
-- :1005-1022; husk :431-443); collision adjustments within 3m remain accepted.
return function(H, repo_root, load_candidate)
    local prefix = "chaos_wastes_tweaker_dev/scripts/mods/chaos_wastes_tweaker_dev/"
    local function load(name, env)
        local relative = prefix .. name .. ".lua"
        local result, path
        if load_candidate then
            result, path = load_candidate(relative, env)
        else
            path = repo_root .. "/" .. relative
            local chunk = assert(loadfile(path))
            setfenv(chunk, env)
            result = chunk()
        end
        local normalized = type(path) == "string" and path:gsub("\\", "/")
        assert(normalized and normalized:sub(-#relative) == relative,
            "CT retained-readback test requires the actual production source path")
        return result
    end
    local function environment()
        local env = setmetatable({}, {__index = _G})
        env._G = env
        env.printf = function() end
        return env
    end

    local function rescue_fixture(options)
        options = options or {}
        local env, events, marks, hooks = environment(), {}, {}, {}
        local rescue = {p={x=100,y=0,z=0}, alive=true}
        local near = {p={x=1,y=2,z=0}, alive=true}
        local far = {p={x=50,y=0,z=0}, alive=true}
        rescue.status = {
            is_ready_for_assisted_respawn=function() return true end,
            is_knocked_down=function() return false end,
            is_disabled_by_pact_sworn=function() return false end,
            is_disabled=function() return true end,
        }
        near.status = {is_disabled=function() return false end}
        far.status = {is_disabled=function() return false end}
        rescue.loco = {teleport_to=function(_, pos)
            events[#events+1] = "move"
            if options.throw_move then error("move denied") end
            if not options.drift then
                rescue.p = {x=pos.x+(options.collision_shift or 0),y=pos.y,z=pos.z}
            end
            rescue.move_attempted = true
        end}
        local player = {player_unit=rescue}
        local slot = {peer_id="peer",local_player_id=2,
            game_mode_data={health_state=options.dead and "dead" or "respawning"}}
        local controller = {}
        env.Managers = {
            player={is_server=options.client ~= true,
                player=function() return player end,
                human_and_bot_players=function()
                    return {player,{player_unit=near},{player_unit=far}}
                end},
            time={time=function() return options.now or 10 end},
            party={get_player_status=function() return slot end},
            state={game_mode={force_respawn_dead_players=function() end},
                side={get_side_from_name=function()
                    return {party={occupied_slots={slot}}}
                end},
                network={unit_game_object_id=function()
                    if options.no_go then return nil end
                    return 5
                end,
                    network_transmit={send_rpc_clients=function(_, rpc, id)
                        assert(rpc == "rpc_teleport_unit_to" and id == 5)
                        if options.network_error then error("network denied") end
                        events[#events+1] = "network"
                    end}}},
        }
        env.Unit = {alive=function(unit) return unit.alive end,
            world_position=function(unit)
                if unit == rescue and unit.move_attempted then
                    if options.position_error then error("position unavailable") end
                    if options.missing_readback then return nil end
                end
                return unit.p
            end,
            local_rotation=function() return {} end}
        env.ScriptUnit = {has_extension=function(unit, system)
            if system == "status_system" then return unit.status end
            if system == "locomotion_system" then return unit.loco end
        end}
        env.Vector3 = function(x,y,z) return {x=x,y=y,z=z} end
        env.LocomotionUtils = {disable_linked_movement=function(unit)
            assert(unit == rescue); events[#events+1] = "unlink"
        end}
        env.StatusUtils = {set_respawned_network=function(unit)
            assert(unit == rescue); events[#events+1] = "free"
        end}
        env.POSITION_LOOKUP = options.missing_lookup and {} or {[rescue]={old=true}}
        local mod = {}
        function mod:hook(class, method, callback)
            hooks[class.."."..method] = callback
        end
        mod.hook_safe = mod.hook
        function mod:dofile(path)
            return load(path:match("([^/]+)$"), env)
        end
        local install = load("_ct_chest_revive_owner", env)
        local owner = install(mod, {
            effective_setting=function() return options.enabled ~= false end,
            mark_dead_respawn=function(peer) marks[peer]=true end,
        })
        owner = owner or {on_state=assert(hooks["DeusCursedChestExtension._set_state"]),
            tick=assert(mod._ct_chest_teleport_tick)}
        return owner, mod, env, rescue, slot, events, marks, controller
    end

    H.test("CT #299 actual completion callback moves and broadcasts before free", function()
        local owner, mod, _, rescue, slot, events = rescue_fixture()
        owner.on_state({_unit={alive=true,p={x=0,y=0,z=0}}}, 3)
        assert(table.concat(events, ",") == "unlink,move,network,free")
        assert(rescue.p.x == 1 and rescue.p.y == 2)
        local job = assert(mod._ct_pending_team_teleport["peer/2"])
        assert(job.moved and job.freed and job.anchor.x == 0)
        slot.game_mode_data.health_state = "alive"
        owner.tick(0.1)
        assert(next(mod._ct_pending_team_teleport) == nil)
    end)

    H.test("CT #299 NEW readback hardening refuses to free a silently unmoved unit", function()
        local owner, mod, _, _, _, events = rescue_fixture({drift=true})
        owner.on_state({_unit={alive=true,p={x=0,y=0,z=0}}}, 3)
        assert(table.concat(events, ",") == "unlink,move,network")
        local job = assert(mod._ct_pending_team_teleport["peer/2"])
        assert(job.moved == false and job.freed == false and job.errors == 1)
        for _=1,3 do owner.tick(0.1) end
        assert(next(mod._ct_pending_team_teleport) == nil)
        for _, event in ipairs(events) do assert(event ~= "free") end
    end)

    H.test("CT #299 native move/network failures retain disabled state", function()
        for _, options in ipairs({{throw_move=true},{no_go=true},{network_error=true}}) do
            local owner, mod, _, _, _, events = rescue_fixture(options)
            owner.on_state({_unit={alive=true,p={x=0,y=0,z=0}}}, 3)
            local job = assert(mod._ct_pending_team_teleport["peer/2"])
            assert(not job.moved and not job.freed and job.errors == 1)
            for _, event in ipairs(events) do assert(event ~= "free") end
        end
    end)

    H.test("CT #299 collision correction inside native three-metre tolerance still frees", function()
        for _,shift in ipairs({0,2.9,3}) do
            local owner, mod, _, rescue, _, events = rescue_fixture({collision_shift=shift})
            owner.on_state({_unit={alive=true,p={x=0,y=0,z=0}}},3)
            assert(rescue.p.x==1+shift and table.concat(events,",")=="unlink,move,network,free")
            assert(mod._ct_pending_team_teleport["peer/2"].freed)
        end
    end)

    H.test("CT #299 absent or throwing position readback never frees", function()
        for _, options in ipairs({{missing_readback=true},{position_error=true}}) do
            local owner, mod, _, _, _, events = rescue_fixture(options)
            owner.on_state({_unit={alive=true,p={x=0,y=0,z=0}}},3)
            local job=assert(mod._ct_pending_team_teleport["peer/2"])
            assert(not job.moved and not job.freed and job.errors==1)
            for _,event in ipairs(events) do assert(event~="free") end
        end
    end)

    H.test("CT #299 once-alive drift allows only one corrective move", function()
        local owner, mod, _, rescue, slot, events = rescue_fixture()
        owner.on_state({_unit={alive=true,p={x=0,y=0,z=0}}},3)
        local job=assert(mod._ct_pending_team_teleport["peer/2"])
        rescue.p={x=100,y=0,z=0}; slot.game_mode_data.health_state="alive"
        owner.tick(0.1)
        assert(job.corrections==1 and rescue.p.x==1)
        rescue.p={x=100,y=0,z=0}
        owner.tick(0.1)
        assert(next(mod._ct_pending_team_teleport)==nil)
        local moves=0
        for _,event in ipairs(events) do if event=="move" then moves=moves+1 end end
        assert(moves==2)
    end)

    H.test("CT #299 never seeds missing POSITION_LOOKUP and bounds timeout", function()
        local owner, mod, env, rescue = rescue_fixture({missing_lookup=true})
        owner.on_state({_unit={alive=true,p={x=0,y=0,z=0}}}, 3)
        assert(env.POSITION_LOOKUP[rescue] == nil)
        mod._ct_pending_team_teleport["peer/2"].deadline = 0
        owner.tick(0.1)
        assert(next(mod._ct_pending_team_teleport) == nil)
    end)

    H.test("CT #299 only server OPEN and enabled control arm rescue", function()
        for _, options in ipairs({{client=true},{enabled=false}}) do
            local owner, mod, _, _, _, events = rescue_fixture(options)
            owner.on_state({_unit={alive=true,p={x=0,y=0,z=0}}}, 3)
            assert(next(mod._ct_pending_team_teleport) == nil and #events == 0)
        end
        local owner, mod = rescue_fixture()
        owner.on_state({_unit={alive=true,p={x=0,y=0,z=0}}}, 4)
        assert(next(mod._ct_pending_team_teleport) == nil)
    end)

    H.test("CT #299 same-peer local player jobs remain distinct", function()
        local _, mod = rescue_fixture()
        mod._ct299_arm("peer", 1, {}, {x=0,y=0,z=0}, false)
        mod._ct299_arm("peer", 2, {}, {x=0,y=0,z=0}, false)
        assert(mod._ct_pending_team_teleport["peer/1"])
        assert(mod._ct_pending_team_teleport["peer/2"])
    end)

end
