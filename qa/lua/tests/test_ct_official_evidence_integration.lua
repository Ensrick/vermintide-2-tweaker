-- Actual production-layer loader: owned additive files, frozen CT02 dependencies,
-- then repository only after application (no source substitution or ready stubs).
return function(H, root)
    root = root:gsub("\\", "/"):gsub("/$", "")
    local overlay = os.getenv("VT2_CT_EVIDENCE_OVERLAY_ROOT")
    local frozen = root .. "/.temp/public-promotion-20261105/overlays/ct"
    local owned = root .. "/.temp/public-promotion-20261105/ct-evidence-integration"
    if overlay then assert(overlay:gsub("\\", "/"):gsub("/$", "") == owned, "unowned evidence overlay") end
    local prefix = "chaos_wastes_tweaker/scripts/mods/chaos_wastes_tweaker/"
    local changed = { _ct_official_verify_runtime=true, _ct_diag_official_apply_evidence=true,
        _ct_official_chest_cap=true, _ct_official_boon_repairs=true }
    local function pack(...) return {n=select("#", ...), ...} end
    local function load(name, env)
        assert(name:match("^[%w_]+$"))
        local base = root
        if overlay then base = changed[name] and owned or frozen end
        local path = base .. "/" .. prefix .. name .. ".lua"
        local fn = assert(loadfile(path), "missing actual selected production path " .. path)
        setfenv(fn, env)
        return fn(), path
    end
    local function fixture(settings)
        settings = settings or {}
        local f = { settings=settings, logs={}, checks={}, commands={}, hooks={}, level="test_level" }
        local env = setmetatable({}, {__index=_G}); env._G=env; f.env=env
        env.printf=function(fmt, ...) f.logs[#f.logs+1]=string.format(fmt, ...) end
        env.Unit={alive=function(unit) return unit.alive ~= false end}
        env.LevelHelper={current_level_settings=function() return {level_id=f.level} end}
        env.Managers={player={is_server=true},state={},mechanism={game_mechanism=function() return {get_deus_run_controller=function() return f.rc end} end}}
        local mod={}; f.mod=mod
        function mod:get(key) return settings[key] end
        function mod:echo(fmt, ...) f.last_echo=string.format(fmt, ...) end
        function mod:command(name, _, cb) assert(not f.commands[name], "duplicate command "..name); f.commands[name]=cb end
        function mod:hook(target, name, cb)
            local key=tostring(target)..":"..name
            assert(not f.hooks[key], "duplicate hook "..key); f.hooks[key]=cb
        end
        mod.hook_safe=mod.hook
        function mod:network_register() end
        function mod:dofile(path) return load(assert(path:match("/([%w_]+)$")), env) end
        local ctx={effective_setting=function(key) return settings[key] end, rpc_schema=2,
            rt_register=function(name, cb) assert(not f.checks[name], name); f.checks[name]=cb end,
            altar_uses=function() return 2 end}
        f.runtime=load("_ct_official_verify_runtime", env)(mod,ctx); mod._ct_official_runtime=f.runtime
        ctx.runtime=f.runtime
        f.evidence=load("_ct_diag_official_apply_evidence",env)(mod,ctx); mod._ct_apply_evidence=f.evidence
        ctx.parry_policy=load("_ct_parry_cooldown_policy",env)
        f.repairs=load("_ct_official_boon_repairs",env)(mod,ctx); mod._ct_official_boon_repairs=f.repairs
        f.cap=load("_ct_official_chest_cap",env)(mod,ctx); mod._ct_official_chest_cap=f.cap
        f.rc={get_run_id=function() return "run1" end}
        function f.command(name) return f.commands[name]() end
        function f.rows(needle)
            local out={}; for _, row in ipairs(f.logs) do if row:find(needle,1,true) then out[#out+1]=row end end; return out
        end
        return f
    end
    local function main_slice(f, first, after)
        -- Execute the exact bounded production registration, with its lexical
        -- dependencies supplied by this fixture. This is not a whole-mod boot.
        local path=(overlay and owned or root).."/"..prefix.."chaos_wastes_tweaker.lua"
        local file=assert(io.open(path,"rb")); local source=file:read("*a"); file:close()
        local start=assert(source:find(first,1,true)); local finish=assert(source:find(after,start+#first,true))
        local chunk=assert(loadstring(source:sub(start,finish-1),"@"..path..":registration-slice"))
        f.env.mod=f.mod; f.env.MOD_VERSION="test"; f.env._dbg=function() end
        f.env.effective_setting=function(key) return f.settings[key] end
        setfenv(chunk,f.env); chunk()
    end
    H.test("CT main actual regression registration distinguishes legacy pass fail throw and structured skip",function()
        local f=fixture(); f.mod.warning=function() end
        main_slice(f,'local _RT_CHECKS = {}','pcall(printf, "[regression-test-command]')
        f.mod._ct_rt_register("pass",function() end)
        f.mod._ct_rt_register("fail",function() return "bad" end)
        f.mod._ct_rt_register("throw",function() error("bad") end)
        f.mod._ct_rt_register("skip",function() return {status="SKIP",reason="no live owner"} end)
        f.command("ct_regression_test"); assert(f.last_echo=="=== 1 passed, 2 failed, 1 skipped ===")
    end)
    H.test("CT main actual coin singleton callback preserves complete native tuple and effective zero reduction",function()
        local f=fixture({coin_multiplier=2,progressive_difficulty=true,progressive_coin_reduction=-100})
        f.rc._run_state={get_completed_level_count=function() return 2 end}
        local balance=0; f.rc.get_own_peer_id=function() return "self" end; f.rc.get_player_soft_currency=function() return balance end
        f.hooks["DeusRunController:on_soft_currency_picked_up"]=nil
        main_slice(f,'mod:hook("DeusRunController", "on_soft_currency_picked_up",','-- ============================================================')
        local callback=f.hooks["DeusRunController:on_soft_currency_picked_up"]
        local r=pack(callback(function(_,...) assert(select("#",...)==4); local args={...}; assert(args[1]==1 and args[3]==7); balance=1; return nil,"x",nil end,f.rc,5,nil,7,nil))
        assert(r.n==3 and r[2]=="x" and #f.rows("[ct:460credit]")==1)
    end)
    H.test("CT main actual Anath dispatch observes only after successful native add and preserves return nils",function()
        local f=fixture({tweak_home_brewer_potency=false})
        main_slice(f,'mod:hook("BuffExtension", "add_buff",','-- ============================================================')
        local callback=f.hooks["BuffExtension:add_buff"]
        local observed=0; f.evidence.anath_after=function() observed=observed+1 end
        local r=pack(callback(function() return nil,"second",nil,"fourth",nil end,{},"deus_ammo_pickup_reload_speed",{}))
        assert(r.n==5 and r[2]=="second" and r[4]=="fourth" and observed==1)
        local ok,err=pcall(callback,function() error("add-error",0) end,{},"deus_ammo_pickup_reload_speed",{})
        assert(not ok and err=="add-error" and observed==1)
        callback(function() return true end,{},"ordinary",{}); assert(observed==1)
    end)
    H.test("CT evidence actual layer and nine finite commands/checks no new hook owners",function()
        local f=fixture()
        for _, name in ipairs({"verify_ct_chest_cap","verify_ct_citadel","verify_ct_anath_raema","ct_verify_anath_raema",
            "verify_ct_ammo_bounds","verify_ct_linked_pickups","verify_ct_progression","verify_ct_altar_reroll","verify_ct_trial_placement"}) do assert(f.commands[name]) end
        local count=0; for _ in pairs(f.hooks) do count=count+1 end; assert(count==4)
        assert(f.checks.ct_meta_ammo_current_floor_256().status=="SKIP")
    end)
    H.test("CT evidence absent and throwing current context always SKIP not PASS",function()
        local f=fixture(); f.rc=nil
        for _, name in ipairs({"coins","ct_citadel","ct_anath_raema","ct_ammo_bounds","ct_linked_pickups","ct_progression","ct_chest_cap","ct_altar_reroll","ct_trial_placement"}) do
            assert(f.evidence.verify(name).status=="SKIP",name)
        end
        f.env.Managers.mechanism.game_mechanism=function() error("missing native owner") end
        assert(f.evidence.verify("coins").status=="SKIP")
    end)
    H.test("CT evidence bounded scalar receipts deduplicate and invalidate controller level and run",function()
        local f=fixture()
        for i=1,40 do f.evidence.record("252","prompt",{n=i,unit={}}) end
        assert(#f.rows("[ct:252]")==24)
        local r=f.evidence.verify("ct_altar_reroll"); assert(r.status=="SKIP" and r.fields.n==40 and r.fields.unit==nil)
        f.level="next"; assert(next(f.evidence.verify("ct_altar_reroll").fields)==nil)
        f.evidence.record("252","prompt",{n=1}); f.evidence.record("252","prompt",{n=1}); assert(#f.rows("[ct:252]")==25)
        f.rc={}; assert(next(f.evidence.verify("ct_altar_reroll").fields)==nil)
    end)
    H.test("CT912 actual setup exact zero baseline authority readback and spent balance separate",function()
        local f=fixture({starting_coins=0}); local balance=0
        f.rc.get_own_peer_id=function() return "self" end
        f.rc.get_player_soft_currency=function() return balance end
        local args={1,"hardest",nil,nil,175}; f.runtime.setup(f.rc,args); f.runtime.capture_coins(f.rc)
        local r=f.evidence.verify("coins"); assert(args[5]==0 and r.status=="PASS" and r.fields.incoming==175 and r.fields.actual_initial==0)
        balance=999; r=f.evidence.verify("coins"); assert(r.status=="PASS" and r.fields.current_spendable==999 and r.fields.actual_initial==0)
        assert(#f.rows("status=APPLIED")==1)
        args[5]=888; f.runtime.setup(f.rc,args); assert(f.evidence.verify("coins").status=="SKIP")
    end)
    H.test("CT912 missing throwing mismatch client and invalid settings do not manufacture applied",function()
        local f=fixture({starting_coins=324}); local args={1,"hardest",nil,nil,175}
        f.runtime.setup(f.rc,args); f.runtime.capture_coins(f.rc); assert(f.evidence.verify("coins").status=="SKIP")
        assert(f.runtime.coins_regression(f.rc).status=="SKIP")
        f.rc.get_own_peer_id=function() return "self" end; f.rc.get_player_soft_currency=function() return 323 end
        f.runtime.capture_coins(f.rc); assert(f.evidence.verify("coins").status=="FAIL")
        f.env.Managers.player.is_server=false; f.runtime.setup(f.rc,args); f.runtime.capture_coins(f.rc)
        assert(f.evidence.verify("coins").status=="SKIP" and f.runtime.coins_regression(f.rc).status=="SKIP")
        f.settings.starting_coins=false; args[5]=175; f.runtime.setup(f.rc,args); f.runtime.capture_coins(f.rc)
        assert(args[5]==175 and f.evidence.verify("coins").reason:find("PASS_THROUGH",1,true))
    end)
    H.test("CT460 actual credit dispatch preserves nil holes returns errors and verifies balance delta",function()
        local f=fixture(); local balance=10
        f.rc.get_own_peer_id=function() return "self" end; f.rc.get_player_soft_currency=function() return balance end
        local r=pack(f.runtime.credit_native(function(_,...) assert(select("#",...)==4); balance=15; return nil,"tail",nil end,f.rc,{5,nil,7,nil},4,10,10))
        assert(r.n==3 and r[1]==nil and r[2]=="tail" and r[3]==nil)
        assert(f.rows("[ct:460credit]")[1]:find("readback_matches=true",1,true))
        local ok,err=pcall(f.runtime.credit_native,function() error("native-credit",0) end,f.rc,{},0,1,15)
        assert(not ok and err=="native-credit" and #f.rows("[ct:460credit]")==1)
        f.evidence.coin_applied(f.rc,1,1,15); assert(f.rows("[ct:460credit]")[2]:find("readback_matches=false",1,true))
    end)
    H.test("CT146 actual graph mutation emits independent approach finale and curse membership",function()
        local f=fixture({finale_dominant_god=2,finale_approach_god=3})
        local graph={a={level="arena_citadel_nurgle_path1",level_type="A",level_seed=0},b={level="sig_citadel_nurgle_path2",level_type="B",level_seed=0}}
        f.rc._path_graph=graph
        f.runtime.force_finale(graph,{AVAILABLE_CURSES={A={tzeentch={"curseA"}},B={khorne={"curseB"}}}})
        assert(f.evidence.verify("ct_citadel").status=="PASS" and #f.rows("[ct:146]")==2)
        assert(f.rows("[ct:146]")[1]:find("curse_pool_member=true",1,true))
        graph.b.god="nurgle"; assert(f.evidence.verify("ct_citadel").status=="FAIL")
        f.rc._path_graph={ordinary={level="forest"}}; assert(f.evidence.verify("ct_citadel").status=="SKIP")
        f.settings.finale_dominant_god=false; assert(f.evidence.verify("ct_citadel").status=="SKIP")
    end)
    local function anath(f,count)
        local vanilla={buffs={{name="original",event="on_ammo_pickup"}}}
        f.env.BuffTemplates={deus_ammo_pickup_reload_speed=vanilla}
        f.env.WeaponTraits={buff_templates={deus_ammo_pickup_reload_speed={buffs={{name="independent"}}}}}
        f.repairs.apply_anath()
        local sub=f.env.BuffTemplates.deus_ammo_pickup_reload_speed.buffs[1]
        local ext={_buffs={},_num_buffs=count,num_buff_type=function() return count end,apply_buffs_to_value=function() return 0.5 end}
        for i=1,count do ext._buffs[i]={buff_template_name="deus_ammo_pickup_reload_speed",buff_type=sub.name,template=sub,
            multiplier=sub.multiplier,duration=sub.duration,bonus=sub.bonus} end
        f.env.Managers.player.local_player=function() return {player_unit={}} end
        f.env.ScriptUnit={has_extension=function() return ext end}
        return ext,vanilla
    end
    H.test("CT288 fresh active single child readback registry and native add tuple",function()
        local f=fixture({tweak_anath_raema_permanent=true}); local ext,original=anath(f,1)
        assert(f.command("ct_verify_anath_raema").status=="PASS")
        local r=pack(f.runtime.add_anath(function() return nil,2,nil,4,nil end,ext,"deus_ammo_pickup_reload_speed",{}))
        assert(r.n==5 and r[2]==2 and r[4]==4 and #f.rows("post-native add")>0)
        f.settings.tweak_anath_raema_permanent=false; f.repairs.revert_anath(); assert(f.env.BuffTemplates.deus_ammo_pickup_reload_speed==original)
        assert(f.evidence.verify("ct_anath_raema").status=="SKIP")
    end)
    for _,count in ipairs({0,2}) do H.test("CT288 active child count "..count.." is not a false pass",function()
        local f=fixture({tweak_anath_raema_permanent=true}); anath(f,count)
        assert(f.evidence.verify("ct_anath_raema").status==(count==0 and "SKIP" or "FAIL"))
    end) end
    H.test("CT288 malformed active template and native add fault remain honest",function()
        local f=fixture({tweak_anath_raema_permanent=true}); local ext=anath(f,1)
        ext._buffs[1].template={stat_buff="reload_speed",multiplier=-0.5,event="on_ammo_pickup"}
        assert(f.evidence.verify("ct_anath_raema").status=="FAIL")
        local n=#f.logs; local ok,err=pcall(f.runtime.add_anath,function() error("native-add",0) end,ext,"parent",{})
        assert(not ok and err=="native-add" and #f.logs==n)
    end)
    for _,case in ipairs({
        {name="resolved multiplier override",field="multiplier",value=0.5},
        {name="resolved timed duration",field="duration",value=10},
        {name="missing resolved multiplier",field="multiplier"},
        {name="resolved additive bonus",field="bonus",value=0.25},
    }) do
        H.test("CT288 actual active "..case.name.." cannot inherit template PASS",function()
            local f=fixture({tweak_anath_raema_permanent=true}); local ext=anath(f,1)
            ext._buffs[1][case.field]=case.value
            assert(ext._buffs[1].template.multiplier==-0.5 and ext._buffs[1].template.duration==nil)
            local r=f.evidence.verify("ct_anath_raema")
            assert(r.status=="FAIL" and r.fields.malformed==1)
        end)
    end
    local function ammo(current,reserve,shots,clip,max)
        return {_current_ammo=current,_available_ammo=reserve,_shots_fired=shots,_ammo_per_clip=clip,_max_ammo=max,
            ammo_count=function(self) return self._current_ammo-self._shots_fired end,clip_size=function(self) return self._ammo_per_clip end}
    end
    H.test("CT256 actual refresh clamp logs retained fields without capacity or shots writes",function()
        local f=fixture(); local ext=ammo(80,-4,0,60,60)
        f.runtime.clamp_ammo(ext)
        assert(ext._current_ammo==60 and ext._available_ammo==0 and ext._ammo_per_clip==60 and ext._shots_fired==0)
        assert(f.evidence.ammo_check(ext).status=="PASS")
        assert(f.rows("[ct:256]")[2]:find("before_current=80",1,true))
    end)
    for _,case in ipairs({{10,0,0,5,60},{4,-1,0,5,60},{0,0,1,5,60},{0/0,0,0,5,60},{math.huge,0,0,5,60}}) do
        H.test("CT256 invalid actual clip reserve or numeric bounds fail "..tostring(case[1])..":"..tostring(case[2])..":"..tostring(case[3]),function()
            local f=fixture(); assert(f.evidence.ammo_check(ammo(unpack(case))).status=="FAIL")
        end)
    end
    H.test("CT256 current ranged slot verifier resolves fresh and missing extension skips",function()
        local f=fixture(); local ext=ammo(4,40,1,5,60); local weapon={}
        f.env.Managers.player.local_player=function() return {player_unit={}} end
        f.env.ScriptUnit={has_extension=function(_,system)
            if system=="inventory_system" then return {get_slot_data=function() return {right_unit_1p=weapon} end} end
            return ext
        end}
        assert(f.command("verify_ct_ammo_bounds").status=="PASS")
        weapon.alive=false; assert(f.command("verify_ct_ammo_bounds").status=="SKIP")
    end)
    local function linked(f,name)
        local unit,owner={},{}; local id=42
        f.env.Managers.state.unit_storage={go_id=function() return id end,unit=function(_,value) return value==id and unit end}
        local map={[owner]={[unit]={}}}
        f.env.Managers.state.entity={system=function(_,name) assert(name=="projectile_linker_system"); return {linked_projectile_units=map} end}
        f.env.ScriptUnit={has_extension=function() return {pickup_name=name or "throwing_axe"} end}
        return unit,map
    end
    H.test("CT322 actual spawn returns preserve holes and do not claim linked state",function()
        local f=fixture(); local unit=linked(f)
        local r=pack(f.runtime.finish_pickup(function() return unit,42,nil,"tail",nil end,{}, {},"throwing_axe",1,nil,3,"test"))
        assert(r.n==5 and r[1]==unit and r[2]==42 and r[4]=="tail")
        assert(f.rows("[ct:322]")[1]:find("spawn-return (not linked proof)",1,true))
    end)
    H.test("CT322 each peer live map identity and recovered expired nonlinked controls",function()
        local f=fixture(); local unit,map=linked(f)
        for _,host in ipairs({true,false}) do f.env.Managers.player.is_server=host; assert(f.command("verify_ct_linked_pickups").status=="PASS") end
        f.env.Managers.state.unit_storage.unit=function() return {} end; assert(f.evidence.verify("ct_linked_pickups").status=="FAIL")
        for owner in pairs(map) do map[owner]={} end; assert(f.evidence.verify("ct_linked_pickups").status=="SKIP")
        linked(f,"ammo"); assert(f.evidence.verify("ct_linked_pickups").status=="SKIP")
    end)
    local function chests(f,count,options)
        options=options or {}; local units={}
        f.env.Managers.state.network={game=function() return {} end}
        f.env.Managers.state.unit_storage={go_id=function(_,unit) return unit end}
        f.env.GameSession={game_object_field=function(_,unit) if options.unknown then return nil end; return unit.state or 1 end}
        f.env.Managers.state.unit_spawner={mark_for_deletion=function(_,unit) if options.throw then error("denied") end; if not options.noop then unit.marked=true end end,
            is_marked_for_deletion=function(_,unit) if options.mark_throw then error("readback") end; return unit.marked==true end}
        f.env.Managers.state.entity={system=function() return {get_pickups_by_type=function() return options.loci or {} end} end}
        f.cap.begin(f.level)
        for i=1,count do local unit={}; units[i]=unit; f.cap.appeared(f.level,unit); if not options.nonpickup then f.cap.pickup_chest(unit) end end
        return units
    end
    H.test("CT60 queued marked deletion never equals drained removal and fresh postdrain passes",function()
        local f=fixture({cursed_chest_count=3}); local units=chests(f,4)
        f.cap.finalize(f.level,3,true); assert(f.evidence.verify("ct_chest_cap").status=="SKIP")
        assert(f.rows("[ct:60]")[1]:find("confirmed_marked=1",1,true))
        units[4].alive=false; assert(f.command("verify_ct_chest_cap").status=="PASS")
    end)
    for _,option in ipairs({"noop","throw","mark_throw"}) do H.test("CT60 deletion "..option.." cannot claim removal",function()
        local f=fixture({cursed_chest_count=3}); local opts={[option]=true}; chests(f,4,opts)
        f.cap.finalize(f.level,3,true)
        local r=f.evidence.verify("ct_chest_cap"); assert(r.status=="FAIL" and r.fields.confirmed_marked==0)
    end) end
    H.test("CT60 nonpickup activated unknown controls are not deleted or called baked",function()
        for _,kind in ipairs({"nonpickup","unknown","activated"}) do
            local f=fixture({cursed_chest_count=0}); local opts={[kind]=true}; local units=chests(f,1,opts)
            if kind=="activated" then units[1].state=2 end
            f.cap.finalize(f.level,0,true); assert(not units[1].marked)
            assert(f.evidence.verify("ct_chest_cap").status=="SKIP")
        end
    end)
    H.test("CT60 settled in-cap row locus uniqueness and replaced owner invalidation",function()
        local f=fixture({cursed_chest_count=3}); chests(f,2,{loci={{},{}}}); f.cap.finalize(f.level,3,true)
        assert(#f.rows("[ct:60]")==1 and f.evidence.verify("ct_chest_cap").status=="FAIL")
        f.rc={}; assert(f.evidence.verify("ct_chest_cap").status=="SKIP")
    end)
    local function placement(f,mode)
        local function box(v) return {unbox=function() return v end} end
        f.env.Vector3Box=box
        f.env.Managers.state.entity={system=function() return {nav_world=function() return {} end} end}
        local calls=0
        f.env.ConflictUtils={find_positions_around_position=function(_,accepted,_,_,_,want)
            calls=calls+1
            if mode=="throw" then error("finder fault") end
            if mode~="residual" then for _=1,want do accepted[#accepted+1]={} end end
        end}
        local element={spawn_counter_category="cursed_chest_enemies",amount=2,min_distance=6,max_distance=8,
            pre_spawn_unit_func=function() if mode=="telegraph" then error("decal") end end}
        local event={center_position=box({}),spawn_positions={box({})},spawn_table={1,2,3}}
        local r=pack(f.runtime.spawn_around(function() return "a",nil,"c",nil end,event,element,0))
        assert(r.n==4 and r[1]=="a" and r[3]=="c" and element.amount==2)
        return f.evidence.verify("ct_trial_placement"),calls
    end
    for _,mode in ipairs({"success","residual","throw","telegraph"}) do H.test("CT471 actual placement "..mode.." receipt remains historical not faux live pass",function()
        local f=fixture({cot_enemy_multiplier=3}); local r,calls=placement(f,mode)
        assert(r.status=="SKIP")
        assert(r.fields.requested==3 and r.fields.native_placed==1 and calls<=5)
        if mode=="success" then assert(r.fields.placed==3 and r.fields.residual==0) end
        if mode=="residual" then assert(r.fields.residual==2 and calls==5) end
        if mode=="throw" then assert(r.fields.topup_error:find("finder fault",1,true) and r.fields.residual==2) end
        if mode=="telegraph" then assert(r.fields.telegraph_errors==2) end
    end) end
    H.test("CT252 actual installed UI callback records only eligible prompt readback not transaction",function()
        local f=fixture(); local equipped={rarity="rare"}; local stored={rarity="rare"}
        local chest={_chest_type="upgrade",_go_id=7,get_stored_purchase=function() return stored end,get_purchase_cost=function() return 30 end}
        f.rc.get_own_loadout=function() return equipped,{} end; f.rc.get_own_peer_id=function() return "self" end; f.rc.get_player_soft_currency=function() return 50 end
        f.env.DEUS_CHEST_TYPES={upgrade="upgrade"}; f.env.ScriptUnit={has_extension=function() return chest end}
        f.env.RaritySettings={rare={order=3,display_name="Rare"},exotic={order=4}}
        f.env.Managers.state.network={profile_synchronizer={others_actually_ingame=function() return true end}}
        local info={content={},style={rarity={},cost_text={}}}; local view={_widgets_by_name={chest_content=info,weapon_tooltip={content={},style={item={}}}}}
        local callback=f.hooks["DeusUpgradeWeaponInteractionUI:_populate_widget"]
        callback(view,{},"slot_melee")
        local r=f.evidence.verify("ct_altar_reroll"); assert(r.status=="SKIP" and r.fields.prompt=="Reroll this weapon?" and r.fields.cost_text=="50/30")
        stored.rarity="exotic"; callback(view,{},"slot_melee"); assert(#f.rows("[ct:252]")==1)
    end)
    H.test("CT460 actual getter named readback sparse tier gap and host false controls",function()
        local f=fixture({progressive_difficulty=true,progressive_difficulty_increase=true,progressive_coin_reduction=-25})
        f.env.Difficulties={}; f.env.DifficultyLookup={}
        for i,key in ipairs(f.runtime.progressive.TIERS) do f.env.Difficulties[i]=key; f.env.DifficultyLookup[key]=i end
        local completed=4; f.rc._ct_progdiff_start="hardest"; f.rc._run_state={get_completed_level_count=function() return completed end}
        f.rc.get_run_difficulty=function(self) return f.hooks["DeusRunController:get_run_difficulty"](function() return "hardest" end,self) end
        assert(f.command("verify_ct_progression").status=="PASS" and f.runtime.coin_multiplier(2)==1.5)
        f.env.DifficultyLookup.cataclysm=nil; assert(f.rc:get_run_difficulty()=="hardest" and f.evidence.verify("ct_progression").status=="PASS")
        f.settings.progressive_difficulty=false; assert(f.rc:get_run_difficulty()=="hardest" and f.runtime.coin_multiplier(2)==2 and f.evidence.verify("ct_progression").status=="SKIP")
    end)
    H.test("CT evidence raw printer faults never suppress functional return state or tuple",function()
        local f=fixture({starting_coins=324}); f.env.printf=function() error("printer") end
        local unit={}; local r=pack(f.runtime.finish_pickup(function() return unit,7,nil,"x",nil end,{}, {},"ammo"))
        assert(r.n==5 and r[4]=="x")
        local args={1,"hardest",nil,nil,175}; f.runtime.setup(f.rc,args); f.runtime.capture_coins(f.rc); assert(args[5]==324)
    end)
end
