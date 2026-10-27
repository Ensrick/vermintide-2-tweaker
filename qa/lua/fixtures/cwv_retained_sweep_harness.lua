-- Actual complete native caller/Sweep + VMF dispatch, explicit engine ledger.
-- Required tracked source fixture; no native checkout or ignored review path.
-- Does not emulate physics, Stingray ABI, action assertions or rendered assets.
return function(T, H, root, config)
    config = config or {}
    local native = dofile(root .. "/qa/lua/fixtures/cwv_retained_sweep_native_6_13.lua")
    local p = { ledger = { start_proc=0,sweep_proc=0,flow=0,attack_anim=0,buff_remove=0,rig_enable=0,send=0,enter=0,hook_attempts=0 } }
    local ext, selected
    local c = T.installed(function(c)
        local env, ledger = c.env, p.ledger
        p.env, p.c = env, c
        local owner, weapon, fpunit, world = {}, {}, {}, {}
        local Vec = {}; Vec.__index = Vec
        function Vec.__add(a,b) return setmetatable({x=(a.x or 0)+(b.x or 0),y=(a.y or 0)+(b.y or 0),z=(a.z or 0)+(b.z or 0)},Vec) end
        function Vec.__sub(a,b) return Vec.__add(a,{x=-(b.x or 0),y=-(b.y or 0),z=-(b.z or 0)}) end
        function Vec.__mul(a,b) if type(a)=="number" then a,b=b,a end;return setmetatable({x=(a.x or 0)*b,y=(a.y or 0)*b,z=(a.z or 0)*b},Vec) end
        local function vec(x,y,z) return setmetatable({x=x or 0,y=y or 0,z=z or 0},Vec) end
        local function box(value) return {value=value,store=function(self,v)self.value=v end,unbox=function(self)return self.value end} end
        env.Vector3=setmetatable({},{__call=function(_,...)return vec(...) end})
        env.Vector3Box=function(v)return box(v)end;env.QuaternionBox=function(v)return box(v)end
        env.Quaternion={up=function()return vec(0,0,1)end,right=function()return vec(1,0,0)end,forward=function()return vec(0,1,0)end,
            multiply=function(a)return a end,axis_angle=function()return {} end}
        env.math=setmetatable({degrees_to_radians=function(v)return v*math.pi/180 end},{__index=math})
        env.Unit=setmetatable({alive=function(unit)return not unit.dead end,box=function()return vec(),vec(1,1,1)end,
            world_position=function()return vec()end,world_rotation=function()return {} end,local_rotation=function()return {} end,
            flow_event=function(_,event)if event=="sfx_swing_started" then ledger.flow=ledger.flow+1 end end,
            node=function()return 0 end,has_node=function()return false end,
            animation_event=function(_,event)if tostring(event):find("attack_swing",1,true) then ledger.attack_anim=ledger.attack_anim+1 end end,
            animation_find_variable=function()return 1 end},{__index=function()return function()end end})
        env.Actor={node=function()return 0 end};env.POSITION_LOOKUP={[weapon]=vec()}
        env.World={get_data=function()return {} end,spawn_unit=function()return {} end,link_unit=function()end,unlink_unit=function()end}
        env.PhysicsWorld={immediate_raycast=function()return nil end}
        env.Development={parameter=function()return false end};env.script_data={}
        env.require=function()end;env.DLCUtils={require_list=function()end,map=function()end}
        env.class=function(existing,parent)
            local cls=existing or {};cls.super=parent;setmetatable(cls,{__index=parent})
            function cls:new(...)local o=setmetatable({},{__index=self});o:init(...);return o end
            return cls
        end
        env.Application={user_setting=function(key)if key=="weapon_trails" then return "none" end;return false end}
        env.Script={new_table=function()return {} end};env.WeaponSkins={skins={}}
        env.NetworkConstants={animation_variable_float={min=0,max=10}}
        env.IS_WINDOWS=true;env.LEVEL_EDITOR_TEST=false;env.global_is_inside_inn=false
        env.HEALTH_ALIVE={};env.Cleave={min=1,max=10};env.MIN_POWER_LEVEL=0;env.MAX_POWER_LEVEL=1000
        env.math.clamp=function(v,a,b)return math.max(a,math.min(b,v))end
        local fp={set_weapon_sway_settings=function()end,increase_aim_assist_multiplier=function()end,animation_set_variable=function()end,
            current_rotation=function()return {} end,current_position=function()return vec()end,disable_rig_movement=function()end,
            enable_rig_movement=function()
                ledger.rig_enable=ledger.rig_enable+1
                if config.cleanup_error then error(config.cleanup_error,0) end
                if config.reenter then ext:stop_action("interrupted") end
            end,play_hud_sound_event=function()end,reset_aim_assist_multiplier=function()end}
        local hud={show_critical_indication=true};p.hud=hud
        local buff={apply_buffs_to_value=function(_,v)return v end,has_buff_perk=function()return false end,
            trigger_procs=function(_,event,action)
                if event=="on_start_action" then ledger.start_proc=ledger.start_proc+1
                    if config.on_start then config.on_start(c,action) end
                    if config.proc_error then error(config.proc_error,0) end
                elseif event=="on_sweep" then ledger.sweep_proc=ledger.sweep_proc+1 end
            end}
        local input={reset_release_input=function()ledger.enter=ledger.enter+1 end,reset_release_input_with_delay=function()ledger.enter=ledger.enter+1 end}
        local status={set_blocking=function()end};local locomotion={is_stood_still=function()return false end}
        local extensions={buff_system=buff,hud_system=hud,first_person_system=fp,status_system=status,locomotion_system=locomotion,input_system=input}
        env.ScriptUnit={extension=function(_,system)
            if system=="weapon_system" then return assert(ext) end
            return assert(extensions[system],"unavailable engine extension "..tostring(system))
        end,has_extension=function(_,system)return extensions[system] end}
        local player={bot_player=false,remote=false,is_player_controlled=function()return true end}
        env.Managers={player={owner=function()return player end,unit_owner=function()return player end},world={wwise_world=function()return {} end},
            time={time=function()return 100 end},state={network={network_transmit={is_server=true,send_rpc_clients=function()end,send_rpc_server=function()end}},
                unit_storage={go_id=function()return 1 end},difficulty={get_difficulty=function()return "normal" end},event={register=function()end},
                controller_features={add_effect=function()end}}}
        env.ActionUtils={get_action_time_scale=function()return 1 end,scale_power_levels=function(v)return v end,
            is_critical_strike=function()return false end,get_melee_boost=function()return false end,init_action_buff_data=function()end,
            remove_action_buff_data=function()ledger.buff_remove=ledger.buff_remove+1 end,update_action_buff_data=function()end}
        T.run(native.utils,env,"exact-native-cleave-and-selector-functions")
        env.WeaponUtils={get_weapon_template=function(name)return assert(env.Weapons[name])end}
        env.table.clear=function(t)for k in pairs(t)do t[k]=nil end end
        env.table.contains=function(t,v)for _,x in pairs(t)do if x==v then return true end end;return false end
        -- Reset the constructor-only class shapes before executing all3 modules.
        env.ActionBase,env.ActionSweep,env.WeaponUnitExtension=nil,nil,nil
        T.run(native.base,env,"complete-native-action-base")
        T.run(native.sweep,env,"complete-native-action-sweep")
        T.run(native.weapon,env,"complete-native-weapon-unit-extension")
        local original_helper=env.ActionSweep._get_damage_profile_name
        env.ActionSweep._get_damage_profile_name=function(...)
            ledger.helper=(ledger.helper or 0)+1;return original_helper(...)
        end
        if config.before_effective then
            local populate=env.ActionSweep._populate_sweep_action_data
            env.ActionSweep._populate_sweep_action_data=function(self,...)
                populate(self,...);config.before_effective(c,self)
            end
        end
        if config.tuples then
            local start,finish=env.WeaponUnitExtension.start_action,env.ActionSweep.finish
            env.WeaponUnitExtension.start_action=function(...)start(...);return nil,"start",nil,4 end
            env.ActionSweep.finish=function(...)finish(...);return nil,"finish",nil,4 end
        end
        if config.missing_method then env.ActionSweep._update_sweep=nil end
        local vmf={check_wrong_argument_type=function(_,_,_,value,...)
            for _,kind in ipairs({...})do if type(value)==kind then return false end end
            return true
        end,safe_call_nr=function(_,_,fn,...)return fn(...)end}
        env.VMFMod={};env.get_mod=function(name)if name=="VMF"then return vmf end end
        T.run(native.vmf,env,"complete-VMF-hook-dispatch")
        local mod,prior=c.mod,c.mod.hook
        mod.is_enabled=function()return true end;mod.get_internal_data=function()return false end;mod.get_name=function()return "cwv-test" end
        mod.hook=function(self,target,method,fn)
            if type(target)~="table" then return prior(self,target,method,fn) end
            ledger.hook_attempts=ledger.hook_attempts+1
            if config.partial_install==ledger.hook_attempts then error("injected hook install error",0) end
            if config.disconnect==method or config.disconnect=="all" then return nil end
            local result=env.VMFMod.hook(self,target,method,fn)
            H.equal(result,nil,"successful actual VMF registration returns nil")
            return result
        end
        if config.degraded then env.DamageProfileTemplates.cwv_old_musket_melee_heavy_slashing_tank={foreign=true} end
        if config.alter then config.alter(c) end
        p.finish_setup=function()
            local template=assert(env.Weapons.old_musket_template_melee)
            local anims={attack_speed=1};local count=1
            for _,group in pairs(template.actions)do for _,row in pairs(group)do if type(row)=="table"then
                for _,field in ipairs({"anim_event","anim_event_1p","anim_event_3p","anim_end_event","anim_end_event_1p","anim_end_event_3p","pre_action_anim_event"})do
                    local value=row[field];if type(value)=="string"and not anims[value]then count=count+1;anims[value]=count end
                end
            end end end
            env.NetworkLookup.anims=setmetatable(anims,{__index=function(_,key)error("unbound detached animation "..tostring(key))end})
            local donor=env.table.clone(env.Weapons.two_handed_heavy_spears_template,true)
            T.run(native.weapons,setmetatable({Weapons={two_handed_heavy_spears_template=donor},ActionAssertFuncs={},
                fassert=function(ok,message,...)assert(ok,string.format(message,...))end},{__index=env}),"complete-native-finalizer-control")
            p.native_actions=donor.actions
            selected=template.actions.action_one[config.name or "light_attack_left"]
            env.ItemMasterList.cwv_es_musket_old={template="old_musket_template_melee"}
            ext=setmetatable({},{__index=env.WeaponUnitExtension})
            ext:init({world=world},weapon,{owner_unit=owner,item_name="cwv_es_musket_old",first_person_rig=fpunit,
                attach_nodes={{source="j_rightweaponattach"}},weapon_system={send_rpc_attack_hit=function()ledger.send=ledger.send+1 end}})
            ext:extensions_ready(world,weapon)
            env.ItemMasterList.cwv_es_musket_old=nil -- constructor-only native init input, not a published owned item.
            p.ext,p.action,p.template,p.lookup=ext,selected,template,c.lookup
            p.start=function(hand)return ext:start_action("action_one",config.name or "light_attack_left",template.actions,100,650,
                hand~=nil and {action_hand=hand} or nil)end
            p.queue=function(id)
                local sweep=assert(ext.actions.sweep);sweep._send_delayed_hit_rpc=true
                sweep._stored_attack_data={damage_source_id=1,attacker_unit_id=1,hit_unit_id=2,hit_zone_id=1,
                    hit_position=box(vec()),attack_direction=box(vec()),damage_profile_id=id or rawget(c.lookup,selected.damage_profile),optional_parameters={}}
                return sweep
            end
            p.release=function()ext=nil;selected=nil;p.ext=nil;p.action=nil;p.start=nil;p.queue=nil;p.finish_setup=nil end
        end
    end)
    p.finish_setup()
    local checks={};c.capsule.register_sweep_check(function(name,fn)checks[name]=fn end)
    p.check=assert(checks.issue428_old_musket_retained_sweep)
    return p
end
