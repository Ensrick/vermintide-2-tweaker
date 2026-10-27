-- #428 retained local consumer: real owner/entry/VMF/native caller closure.
-- Required tracked exact sources, no external-native or ignored-path SKIP.
return function(H, root)
    local quiet=setmetatable({test=function()end,test_if=function()end},{__index=H})
    local T=dofile(root.."/qa/lua/tests/test_cwv_old_musket_shot_owner.lua")(quiet,root)
    local make=dofile(root.."/qa/lua/fixtures/cwv_retained_sweep_harness.lua")
    local prefix=root.."/character_weapon_variants/scripts/mods/character_weapon_variants/"
    local shapes
    local function new(config)
        config=config or {}
        config.disconnect=rawget(_G,"CWV_SWEEP_TEST_DISCONNECT") or config.disconnect
        return make(T,H,root,config)
    end
    local function test(name,fn)
        H.test(name:sub(1,5)=="#428 "and name or "#428 retained Sweep "..name,function()
            -- The real suite tracker restores require after registration.
            -- Capture runtime ownership immediately before our first body.
            if not shapes then
                shapes={T.shape(_G),T.shape(math),T.shape(table),T.shape(string),T.shape(package),T.shape(io)}
            end
            return fn()
        end)
    end
    local function pack(...)return {n=select('#',...),...}end
    local function tick(p,t)return p.ext:update(nil,nil,0.001,nil,t or 100.001)end
    local function skip(p)H.truthy(type(p.check())=="string"and p.check():sub(1,5)=="skip:")end
    local names={"heavy_attack_tank","heavy_attack_left","light_attack_left","light_attack_right","light_attack_stab_1","light_attack_stab_2","light_attack_bopp"}
    for _,name in ipairs(names)do
        local action_name=name
        test("actual installed complete native healthy "..name,function()
            local p=new({name=action_name});skip(p);p.start()
            local s=p.ext.actions.sweep
            H.equal(p.ledger.hook_attempts,4);H.equal(p.ledger.helper,1)
            H.equal(s._damage_profile,p.env.DamageProfileTemplates[p.action.damage_profile])
            H.equal(s._damage_profile_id,p.lookup[p.action.damage_profile]);H.equal(p.check(),nil)
            H.equal(p.ledger.sweep_proc,1);H.equal(p.ledger.flow,1)
            p.ext:stop_action("interrupted");H.equal(p.ext.current_action_settings,nil)
            H.equal(p.ledger.rig_enable,1);H.equal(p.ledger.buff_remove,1);skip(p)
        end)
        test("post-proc rejection unwinds full native caller "..name,function()
            local p=new({name=action_name,on_start=function(c,action)rawset(c.lookup,action.damage_profile,nil)end})
            p.start();H.equal(p.ledger.start_proc,1);H.equal(p.ledger.helper,nil,"unsafe selector is not invoked")
            H.equal(p.ledger.sweep_proc,0);H.equal(p.ledger.flow,0);H.equal(p.ledger.attack_anim,0);H.equal(p.ledger.enter,0)
            H.equal(p.ext.action_time_done,nil);H.equal(p.ext.current_action_settings,nil)
            H.equal(p.ext._currently_stopping_action,false);H.equal(p.ledger.buff_remove,1);H.equal(p.ledger.rig_enable,1)
            H.equal(p.hud.show_critical_indication,false);skip(p)
        end)
    end
    test("left right and nil hand use exact selector once",function()
        for _,hand in ipairs({"left","right","other"})do
            local p=new();p.start(hand);H.equal(p.ext.actions.sweep._action_hand,hand)
            H.equal(p.ledger.helper,1);H.equal(p.check(),nil);p.ext:stop_action("interrupted")
        end
    end)
    test("native degradation has independent real capability",function()
        local p=new({degraded=true});H.equal(p.action.damage_profile,"medium_spear_smiter_stab")
        H.truthy(p.c.capsule.admit_old_musket({item_key="cwv_es_musket_old",template="old_musket_template"}))
        p.c.state._cwv_damage_profile_wire_source={foreign=true};p.c.state._cwv_damage_profile_generation=0/0
        p.start();H.equal(p.check(),nil);p.queue();p.ext:stop_action("new_interupting_action",{})
        H.equal(p.ledger.send,1);H.equal(p.ext.current_action_settings,nil)
    end)
    test("actual ranged-first generation and first fallback remain valid",function()
        local p=new()
        H.equal(p.c.state._cwv_damage_profile_generation,9,"actual earlier constructors plus seven melee occurrences")
        H.equal(p.c.state._cwv_wire_fallback_profile_id,1,"ranged-first fallback is retained, not replaced by melee")
        H.equal(p.c.state._cwv_damage_profile_wire_source.cwv_old_musket_shot,"shot_sniper")
        H.equal(p.lookup.cwv_old_musket_shot,7,"actual ranged publisher precedes melee family")
        p.start();H.equal(p.check(),nil);p.queue();tick(p);H.equal(p.ledger.send,1)
    end)
    test("unproven effective and per-hand fields reject before original helper reads",function()
        local p=new({before_effective=function(_,sweep)sweep._overridable_settings={damage_profile="foreign"}end})
        p.start();H.equal(p.ledger.helper,nil);H.equal(p.ledger.sweep_proc,0);H.equal(p.ledger.rig_enable,1)
        local q=new({on_start=function(_,action)action.damage_profile_left="foreign"end})
        q.start("left");H.equal(q.ledger.helper,nil);H.equal(q.ledger.sweep_proc,0);H.equal(q.ledger.rig_enable,1)
        local r=new();r.action.weapon_mode_key="foreign";r.action.weapon_mode_overrides={}
        r.start();H.equal(r.ledger.start_proc,0);H.equal(r.ext.current_action_settings,nil)
    end)
    test("throwing retained private reader contains without registry repair",function()
        local p=new({alter=function(c)
            local original=c.mod.dofile
            c.mod.dofile=function(self,path)
                local value=original(self,path)
                if path:match("/_cwv_old_musket_melee_owner$")then
                    local bind=value.bind
                    return {bind=function(...)
                        local create=bind(...)
                        return function(opts)
                            local read=opts.profiles
                            opts.profiles=function()if c.reader_throw then error("private read unavailable")end;return read()end
                            return create(opts)
                        end
                    end}
                end
                return value
            end
        end})
        p.start();p.queue();local before=T.shape(p.lookup);p.c.reader_throw=true
        tick(p);H.equal(p.ledger.send,0);H.equal(p.ledger.rig_enable,1);T.unchanged(before)
    end)
    local drift={
        profile=function(p)p.env.DamageProfileTemplates[p.action.damage_profile]={}end,
        profile_cell=function(p)p.env.DamageProfileTemplates[p.action.damage_profile].cleave_distribution.attack=55 end,
        profile_meta=function(p)setmetatable(p.env.DamageProfileTemplates[p.action.damage_profile],{})end,
        profile_root=function(p)p.env.DamageProfileTemplates={}end,
        lookup_root=function(p)p.env.NetworkLookup.damage_profiles={}end,
        reverse=function(p)rawset(p.lookup,p.action.damage_profile,nil)end,
        numeric=function(p)rawset(p.lookup,p.lookup[p.action.damage_profile],"foreign")end,
        map_root=function(p)p.c.state._cwv_damage_profile_wire_source={}end,
        source=function(p)p.c.state._cwv_damage_profile_wire_source[p.action.damage_profile]="foreign"end,
        generation=function(p)p.c.state._cwv_damage_profile_generation=0 end,
        fallback=function(p)p.c.state._cwv_wire_fallback_profile_id=999 end,
        cached_profile=function(p)p.ext.actions.sweep._damage_profile={}end,
        cached_id=function(p)p.ext.actions.sweep._damage_profile_id=999 end,
        hand=function(p)p.ext.actions.sweep._action_hand="left"end,
        queued_id=function(p)p.ext.actions.sweep._stored_attack_data.damage_profile_id=999 end,
        action_path=function(p)p.template.actions.action_one.light_attack_left={}end,
    }
    for name,mutate in pairs(drift)do
        local change=mutate
        test("actual update blocks "..name.." before queued hit",function()
            local p=new();p.start();p.queue();change(p);H.truthy(p.check())
            tick(p);H.equal(p.ledger.send,0);H.equal(p.ext.current_action_settings,nil);H.equal(p.ledger.rig_enable,1)
            tick(p,100.002);H.equal(p.ledger.rig_enable,1);skip(p)
        end)
    end
    test("later valid append does not invalidate selected authority",function()
        local p=new();p.start();p.queue();local n=#p.lookup+1
        p.lookup[n],p.lookup.later_native="later_native",n
        p.c.state._cwv_damage_profile_generation=p.c.state._cwv_damage_profile_generation+1
        p.env.DamageProfileTemplates.later_native={unrelated=true}
        H.equal(p.check(),nil);tick(p);H.equal(p.ledger.send,1);H.equal(p.ledger.rig_enable,0)
    end)
    test("final native flush and direct same-hand cleanup compose",function()
        local p=new();p.start();p.queue();rawset(p.lookup,p.action.damage_profile,nil)
        local actions=p.env.Weapons.musket_template_melee.actions
        p.ext:start_action("action_one","light_attack_left",actions,100,650,nil)
        H.equal(p.ledger.send,0);H.equal(p.ledger.rig_enable,1);H.equal(p.ledger.buff_remove,1)
        H.equal(p.ext.current_action_settings,actions.action_one.light_attack_left);skip(p)
        p.ext:stop_action("interrupted")
    end)
    test("#428 retained Sweep healthy final native flush is not suppressed",function()
        local p=new();p.start();p.queue();p.ext:stop_action("new_interupting_action",{})
        H.equal(p.ledger.send,1);H.equal(p.ledger.rig_enable,1);H.equal(p.ext.current_action_settings,nil);skip(p)
    end)
    test("same Sweep object gets a fresh actual start epoch",function()
        local p=new();p.start();local s=p.ext.actions.sweep;p.ext:stop_action("interrupted")
        p.start();H.equal(p.ext.actions.sweep,s);H.equal(p.check(),nil);p.queue();tick(p)
        H.equal(p.ledger.send,1);H.equal(p.ledger.helper,2)
    end)
    test("denied incoming path preserves a healthy unmanaged predecessor",function()
        local p=new();p.ext:start_action("action_one","light_attack_left",p.native_actions,100,650,nil)
        local previous=p.ext.current_action_settings;rawset(p.lookup,p.action.damage_profile,nil)
        p.start();H.equal(p.ext.current_action_settings,previous);H.equal(p.ledger.buff_remove,0);skip(p)
    end)
    test("borrowed owned row and replaced known row are rejected before native",function()
        local p=new();local root={action_one={light_attack_left=p.action}}
        p.ext:start_action("action_one","light_attack_left",root,100,650,nil)
        H.equal(p.ext.current_action_settings,nil);H.equal(p.ledger.start_proc,0)
        p.template.actions.action_one.light_attack_left={kind="sweep"}
        p.start();H.equal(p.ext.current_action_settings,nil);H.equal(p.ledger.start_proc,0)
    end)
    test("ordinary proc error object is preserved and stale cache quarantined",function()
        local object={ordinary=true};local p=new({proc_error=object})
        local ok,err=pcall(p.start);H.equal(ok,false);H.equal(err,object);H.equal(p.ledger.buff_remove,0)
        H.truthy(p.check():find("terminal",1,true))
        local update_ok,update_error=pcall(tick,p)
        H.equal(update_ok,false);H.truthy(tostring(update_error):find("compare nil with number",1,true),
            "ordinary proc failure leaves the native caller timing incomplete before our Sweep seam")
        H.equal(p.ledger.send,0);H.equal(p.ledger.rig_enable,0)
    end)
    test("cleanup error retains latch and never retries",function()
        local object={cleanup=true};local p=new({cleanup_error=object});p.start();p.queue()
        rawset(p.lookup,p.action.damage_profile,nil)
        local ok,err=pcall(tick,p);H.equal(ok,false);H.equal(err,object)
        H.equal(p.ext._currently_stopping_action,true);H.equal(p.ext.current_action_settings,p.action)
        tick(p,100.002);H.equal(p.ledger.send,0);H.equal(p.ledger.rig_enable,1)
        H.truthy(p.check():find("terminal",1,true))
    end)
    test("#428 retained Sweep outer error after Sweep returns retains terminal without cleanup retry",function()
        local p=new();p.start();p.queue();rawset(p.lookup,p.action.damage_profile,nil)
        local object={outer=true};p.ext.anim_end_event=function()error(object,0)end
        local stops,original=0,p.ext.stop_action
        p.ext.stop_action=function(...)stops=stops+1;return original(...)end
        local ok,err=pcall(p.ext.stop_action,p.ext,"new_interupting_action",{})
        H.equal(ok,false);H.equal(err,object);H.equal(p.ext._currently_stopping_action,true)
        tick(p);tick(p,100.002);H.equal(stops,1);H.equal(p.ledger.rig_enable,1);H.equal(p.ledger.send,0)
        H.equal(p.ext.current_action_settings,p.action);H.truthy(p.check():find("terminal",1,true))
    end)
    test("native cleanup reentrancy still uses native latch once",function()
        local p=new({reenter=true});p.start();p.queue();rawset(p.lookup,p.action.damage_profile,nil);tick(p)
        H.equal(p.ledger.rig_enable,1);H.equal(p.ext._currently_stopping_action,false);H.equal(p.ledger.send,0);skip(p)
    end)
    test("active tuple mismatch is a defect not out-of-scope",function()
        local p=new();p.start();p.queue();p.ext.actions.sweep.current_action={}
        tick(p);H.equal(p.ledger.send,0);H.equal(p.ledger.rig_enable,0)
        H.truthy(p.check():find("terminal",1,true))
    end)
    test("unproven cleanup cells stay terminal without unsafe cleanup mutation",function()
        for _,mutate in ipairs({function(p)p.action.keep_block=true end,
            function(p)p.action.buff_data={}end,function(p)p.action.anim_end_event_condition_func=function()error("foreign callback")end end})do
            local p=new();p.start();p.queue();mutate(p)
            tick(p);H.equal(p.ledger.send,0);H.equal(p.ledger.rig_enable,0)
            H.equal(p.ext.current_action_settings,p.action);H.truthy(p.check():find("terminal",1,true))
            tick(p,100.002);H.equal(p.ledger.rig_enable,0)
        end
    end)
    test("foreign dispatch-kind mutation remains native pre-seam error not a repair claim",function()
        local p=new();p.start();p.queue();p.action.kind="dummy"
        local ok,err=pcall(tick,p)
        H.equal(ok,false);H.truthy(tostring(err):find("local 'action'",1,true))
        H.equal(p.ledger.send,0);H.equal(p.ledger.rig_enable,0);H.truthy(p.check())
        -- Directly reaching the installed inner fence still refuses unsafe
        -- cleanup; the real native outer caller failed BEFORE that fence.
        p.ext.actions.sweep:_update_sweep(0.001,100.001,p.action,0.001)
        H.equal(p.ledger.send,0);H.equal(p.ledger.rig_enable,0)
        H.truthy(p.check():find("terminal",1,true))
    end)
    test("real native Tuskgor and regular Musket stay unmanaged without prefix exemptions",function()
        for _,source in ipairs({"native","musket"})do
            local p=new();local actions=p.native_actions
            if source=="musket"then actions=p.env.Weapons.musket_template_melee.actions end
            p.ext:start_action("action_one","light_attack_left",actions,100,650,nil)
            H.equal(p.ledger.sweep_proc,1);H.equal(p.ledger.helper,1);skip(p)
            p.ext:stop_action("interrupted");H.equal(p.ledger.rig_enable,1)
        end
        local p=new();local borrowed={action_career_claim={light_attack_left=p.action}}
        p.ext:start_action("action_career_claim","light_attack_left",borrowed,100,650,nil)
        H.equal(p.ext.current_action_settings,nil);H.equal(p.ledger.start_proc,0,"career-looking name is no exemption")
    end)
    test("actual canonical career installer composition preserves bayonet capability",function()
        local p=new();local c=p.c
        local old,_,build,check=T.private_items(c)
        local entry=assert(build(old));c.env.ItemMasterList[old.item_key]=entry
        local canonical={default={kind="career-canonical-ledger"}}
        c.env.ActionTemplates.action_career_owned=canonical
        local settings={};for _,career in ipairs(entry.can_wield)do
            settings[career]={activated_ability={{action_name="action_career_owned"}}}
        end
        local adapter=c.load("_cwv_career_weapon_actions")
        local integration=T.run(T.read(root.."/tools/shared_lib/_lib_career_weapon_actions.lua"),c.env,"actual-career-integration")
        local effective=T.run(T.read(root.."/tools/shared_lib/_lib_effective_weapon_templates.lua"),c.env,"actual-effective-template-planner")
        local report=adapter.install({{def=old,entry=entry}},c.env.ItemMasterList,c.env.Weapons,settings,c.env.ActionTemplates,integration,effective,"character_weapon_variants")
        H.truthy(report.ok);H.equal(report.template_count,2);H.equal(check(),nil)
        p.start();H.equal(p.check(),nil);p.queue();tick(p);H.equal(p.ledger.send,1)
    end)
    test("tuple holes survive actual VMF start and finish",function()
        local p=new({tuples=true});local result=pack(p.start())
        H.equal(result.n,4);H.equal(result[1],nil);H.equal(result[2],"start");H.equal(result[3],nil);H.equal(result[4],4)
        local finish=pack(p.ext.actions.sweep:finish("interrupted"))
        H.equal(finish.n,4);H.equal(finish[2],"finish");H.equal(finish[4],4)
    end)
    test("partial registration and unavailable method deny admission without pretending success",function()
        for _,config in ipairs({{partial_install=3},{missing_method=true}})do
            local p=new(config)
            H.equal(p.c.capsule.admit_old_musket({item_key="cwv_es_musket_old",template="old_musket_template"}),false)
            H.truthy(p.check():find("not installed",1,true))
            H.equal(p.ledger.hook_attempts,config.missing_method and 0 or 3)
            if not config.missing_method then p.start();H.equal(p.ledger.sweep_proc,1,"partial wrappers stay passthrough")end
        end
    end)
    test("named check distinguishes active defect native exit and destroyed unit",function()
        local p=new();p.start();H.equal(p.check(),nil)
        p.ext.actions.sweep._damage_profile_id=999;H.truthy(p.check():find("active authority",1,true))
        p.ext.actions.sweep._damage_profile_id=p.lookup[p.action.damage_profile]
        p.ext:stop_action("interrupted");skip(p);p.start();p.ext.actions.sweep.weapon_unit.dead=true;skip(p)
    end)
    test("actual bootstrap captures installed registrar by value",function()
        local p=new();local text=T.read(prefix.."_cwv_variant_bootstrap_owner.lua")
        local stop=assert(text:find("\n\t-- ============================================================",1,true))
        local install=T.run(text:sub(1,stop-1).."\nreturn register_checks\nend\nreturn install",p.env,"exact-bootstrap-private-check-prefix")
        local register=install(p.c.mod,{om=p.c.state,variant_definitions={}},p.c.capsule)
        p.c.capsule.register_sweep_check=function()error("mutable capsule reread")end
        local checks={};register(function(name,fn)checks[name]=fn end)
        local check=assert(checks.issue428_old_musket_retained_sweep);p.start();H.equal(check(),nil)
        p.ext.actions.sweep._damage_profile_id=999;H.truthy(check())
    end)
    test("bounded graph readback preserves default and bounds foreign added keys",function()
        local calls=0;local env=setmetatable({next=function(...)calls=calls+1;return next(...)end},{__index=_G})
        local graph=T.run(T.read(prefix.."_cwv_profile_graph_transaction.lua"),env,"actual-bounded-graph")
        local root_value={a={b=1}};local snap=assert(graph.capture(root_value,4,8))
        H.equal(graph.intact(snap),true);H.equal(graph.intact(snap,true),true)
        for i=1,1000 do root_value[i]=true end
        calls=0;H.equal(graph.intact(snap,true),false);H.truthy(calls<=2,"captured count+1, no full added-key scan")
        calls=0;H.equal(graph.intact(snap),false);H.truthy(calls>1000,"default remains exact legacy census")
        local filtered=graph.capture({a=1,ignored=2},4,8,function(_,key)return key~="ignored"end)
        H.equal(graph.intact(filtered),true);H.equal(graph.intact(filtered,true),false)
    end)
    test("weak records do not retain Sweep extension cycle",function()
        local p=new();p.start();p.ext:stop_action("interrupted")
        local weak=setmetatable({p.ext,p.ext.actions.sweep},{__mode="v"})
        local env=p.env;p.release();p=nil;collectgarbage("collect");collectgarbage("collect")
        H.equal(weak[1],nil);H.equal(weak[2],nil);H.truthy(env.ActionSweep.finish,"guard factory stays loaded")
    end)
    test("host raw shapes unchanged",function()for _,shape in ipairs(shapes)do T.unchanged(shape)end end)
end
