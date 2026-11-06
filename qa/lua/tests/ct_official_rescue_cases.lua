-- Selective CT rescue/cap/TAB cases; explicitly loaded by the primary suite.
-- load_production must resolve actual overlay source, never a test copy.
return function(H, load_production, rescue_owner_loader)
    local prefix = "chaos_wastes_tweaker/scripts/mods/chaos_wastes_tweaker/"
    local function load(name, env)
        local result, path = load_production(prefix .. name .. ".lua", env)
        assert(type(path) == "string" and path:gsub("\\", "/"):find("/chaos_wastes_tweaker/scripts/mods/chaos_wastes_tweaker/", 1, true),
            "rescue cases require actual overlay production source")
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
        local install = rescue_owner_loader and rescue_owner_loader(env)
            or load("_ct_official_chest_rescue", env)
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

    local function cap_fixture(options)
        options = options or {}
        local env, deleted = environment(), {}
        local mod = {}
        function mod:dofile(path) return load(path:match("([^/]+)$"), env) end
        env.Managers = {player={is_server=not options.client},
            mechanism={game_mechanism=function()
                return {get_deus_run_controller=function() return not options.adventure and {} or nil end}
            end}, state={network={game=function() return {} end},
                unit_storage={go_id=function(_, unit) return unit end},
                unit_spawner={mark_for_deletion=function(_, unit)
                    if options.delete_error then error("delete denied") end
                    deleted[#deleted+1]=unit
                end}}}
        env.Unit = {alive=function(unit) return unit.alive ~= false end}
        env.GameSession = {game_object_field=function(_, unit, field)
            assert(field == "deus_cursed_chest_state")
            if unit.read_error then error("missing replicated state") end
            return unit.state
        end}
        local owner = load("_ct_official_chest_cap", env)(mod, {
            effective_setting=function() return options.cap == nil and 1 or options.cap end,
        })
        owner.begin("level")
        return owner, deleted
    end

    H.test("CT #60 settled cap removes only latest pickup-origin WAITING units", function()
        local owner, deleted = cap_fixture()
        local baked, early, late, active = {state=1}, {state=1}, {state=1}, {state=2}
        for _, unit in ipairs({baked,early,late,active}) do owner.appeared("level",unit) end
        owner.appeared("level", late) -- one extension cannot count twice
        owner.pickup_chest(early); owner.pickup_chest(late); owner.pickup_chest(active)
        local plan = assert(owner.finalize("level",1,true))
        assert(plan.alive_n == 4 and plan.over_n == 3 and plan.unprunable_n == 1)
        assert(#deleted == 2 and deleted[1] == late and deleted[2] == early)
        assert(owner.finalize("level",1,true) == nil)
    end)

    H.test("CT #60 default/client/adventure/stale caps never authorize deletion", function()
        for _, options in ipairs({{cap=-1},{client=true},{adventure=true},{cap=2},{cap=0/0}}) do
            local owner, deleted = cap_fixture(options)
            local unit={state=1}; owner.appeared("level",unit); owner.pickup_chest(unit)
            owner.finalize("level",1,true)
            assert(#deleted == 0)
        end
    end)

    H.test("CT #60 failed or unknown WAITING proof never deletes and reset drops old units", function()
        local owner, deleted = cap_fixture({cap=0})
        local unknown={read_error=true}; owner.appeared("level",unknown); owner.pickup_chest(unknown)
        local plan=assert(owner.finalize("level",0,true))
        assert(plan.unprunable_n == 1 and #deleted == 0)
        owner.begin("next")
        assert(owner.finalize("level",0,true) == nil)
        plan=assert(owner.finalize("next",0,true))
        assert(plan.alive_n == 0 and #deleted == 0)
    end)

    local function collectibles_fixture(options)
        options = options or {}
        local env, hooks, drawn = environment(), {}, {}
        local controller = {
            get_own_peer_id=function() return "local-peer" end,
            get_cursed_chests_purified=function(_,peer) assert(peer=="local-peer"); return 2 end,
            get_player_soft_currency=function(_,peer) assert(peer=="local-peer"); return 17.8 end,
        }
        local mod = {}
        function mod:hook(class, method, callback)
            local key=class.."."..method; assert(not hooks[key]); hooks[key]=callback
        end
        mod.hook_safe=mod.hook
        function mod:dofile(path) return load(path:match("([^/]+)$"), env) end
        function mod:localize(key) return key end
        env.get_mod=function(id) assert(id=="ct"); return mod end
        env.Managers={mechanism={game_mechanism=function()
            return {get_deus_run_controller=function() return not options.adventure and controller or nil end}
        end}}
        env.UIAtlasHelper={get_atlas_settings_by_texture_name=function()
            if options.atlas_error then error("no resident atlas") end
            return {size={80,80}}
        end}
        env.UIWidget={init=function(widget) return widget end}
        env.Colors={get_table=function() return {255,255,255,255} end}
        env.UIUtils={get_text_width=function(_,_,title)
            return title=="ct_tab_chests_of_trials" and 120 or 200
        end}
        env.UIRenderer={begin_pass=function() drawn[#drawn+1]="begin" end,
            draw_widget=function(_,widget) drawn[#drawn+1]=widget end,
            end_pass=function() drawn[#drawn+1]="end" end}
        local module=load("_ct_official_collectibles",env)
        local ui={_is_in_inn=options.inn, _ui_renderer={},_ui_top_renderer={},
            _ui_scenegraph={loot_objective={position={20,0,0}},banner_right={size={660,1080}}},
            _input_manager={get_service=function() return {} end},_render_settings={}}
        return mod, hooks, ui, drawn, module
    end

    H.test("CT #571 real registered setup/draw callbacks build measured native counters", function()
        local _, hooks, ui, drawn = collectibles_fixture()
        local native=0
        hooks["IngamePlayerListUI._setup_mission_data"](function() native=native+1 end,ui,{})
        assert(native==0 and #ui._ct_deus_collectibles.rows==2)
        hooks["IngamePlayerListUI._draw"](ui,0.1)
        local rows=ui._ct_deus_collectibles.rows
        assert(rows[1].widget.content.counter_text=="x2")
        assert(rows[2].widget.content.counter_text=="x17")
        assert(rows[1].widget.offset[1]==0 and rows[1].widget.offset[2]==80)
        assert(rows[2].widget.offset[1]==300 and rows[2].widget.offset[2]==80)
        assert(drawn[1]=="begin" and drawn[#drawn]=="end")
    end)

    H.test("CT #571 draw recovery constructs once when a sibling suppresses setup", function()
        local _, hooks, ui = collectibles_fixture()
        hooks["IngamePlayerListUI._draw"](ui,0.1)
        local first=assert(ui._ct_deus_collectibles)
        hooks["IngamePlayerListUI._draw"](ui,0.1)
        assert(ui._ct_deus_collectibles==first)
        assert(first.layout_signature=="cw_tab_collectibles_exact_native_offsets")
    end)

    H.test("CT #571 outside Deus preserves native tuple including nil holes", function()
        local _, hooks, ui = collectibles_fixture({adventure=true})
        local function pack(...) return {n=select("#",...),...} end
        local result=pack(hooks["IngamePlayerListUI._setup_mission_data"](
            function(self,level) assert(self==ui and level.token); return "a",nil,"c",nil end,
            ui,{token=true}))
        assert(result.n==4 and result[1]=="a" and result[2]==nil and result[3]=="c")
        assert(ui._ct_deus_collectibles==nil)
    end)

    H.test("CT #571 build failure latches and falls back once without per-frame retries", function()
        local _, hooks, ui = collectibles_fixture({atlas_error=true})
        local native=0
        hooks["IngamePlayerListUI._setup_mission_data"](function() native=native+1 end,ui,{})
        assert(native==1 and ui._ct_deus_collectibles_build_failed)
        hooks["IngamePlayerListUI._draw"](ui,0.1)
        assert(ui._ct_deus_collectibles==nil)
    end)
end
