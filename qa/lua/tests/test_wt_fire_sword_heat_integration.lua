return function(H, root)
    local prefix=root.."/weapon_tweaker/scripts/mods/weapon_tweaker/"
    local function load(name) return assert(loadfile(prefix..name..".lua"))() end
    local Fixture=assert(loadfile(root.."/qa/lua/fixtures/wt_fire_sword_heat_network.lua"))()
    local Json=assert(loadfile(root.."/qa/lua/fixtures/restricted_json.lua"))()
    local function pack(...) return {n=select("#",...),...} end
    local function pair()
        local net=Fixture.network(load,Json)
        local a,b=net:add("host"),net:add("client")
        net:connect("host","client");net:settle()
        return net,a,b
    end
    local function direct(node) return node.profiles.wt942_direct_direct end

    H.test("WT #942 named detached proof executes actual owners and both real protocols",function()
        Fixture.run(load)
    end)
    H.test("WT #942 both complete catalog lifecycle modules compile before execution",function()
        for _,namespace in ipairs({"weapon_tweaker","weapon_tweaker_dev"}) do
            local path=root.."/"..namespace.."/scripts/mods/"..namespace.."/_wt431_damage_profile_parity.lua"
            local chunk,problem=loadfile(path)
            H.equal(type(chunk),"function",path..": "..tostring(problem))
        end
    end)
    H.test("WT #942 complete catalog boot commits lifecycle before actual thermal finalization",function()
        for _,namespace in ipairs({"weapon_tweaker","weapon_tweaker_dev"}) do
            local net=Fixture.network(load,Json)
            local function boot(node)
                local mod=node.mod
                H.equal(rawget(mod,"_wt_peer_parity"),nil)
                H.equal(rawget(mod,"_wt431_disconnect_epoch_guard"),nil)
                H.equal(node.owner.prepared,true);H.equal(node.owner.committed,false)
                local environment=setmetatable({},{__index=_G})
                environment._G=environment
                environment.get_mod=function(id)
                    if id==(namespace=="weapon_tweaker" and "wt" or "wt_dev") then return mod end
                end
                environment.printf=function() end
                environment.DamageProfileTemplates=node.profiles
                environment.NetworkLookup={damage_profiles=node.lookup}
                environment.Managers={player={human_players=function() return node.humans end}}
                environment.Network={peer_id=function() return node.id end}
                local catalog_prefix=root.."/"..namespace.."/scripts/mods/"..namespace.."/"
                mod.dofile=function(_,path)
                    local name=assert(path:match("/([%w_]+)$"))
                    local chunk=assert(loadfile(catalog_prefix..name..".lua"))
                    setfenv(chunk,environment)
                    return chunk()
                end
                local wire={send_rpc_attack_hit=function(...) return ... end}
                mod.hook=function(_,class,method,callback)
                    H.equal(class,"WeaponSystem");H.equal(method,"send_rpc_attack_hit")
                    node.deps.hook(wire,method,callback)
                end
                mod.hook_safe=function(_,class,method,callback)
                    H.equal(class,"GameNetworkManager");H.equal(method,"remove_peer")
                    node.deps.hook(node.classes.network,method,function(func,...)
                        local values=pack(func(...));callback(...)
                        return unpack(values,1,values.n)
                    end)
                end
                local finish=node.owner.finish_install
                local finalized=0
                node.owner.finish_install=function(owner)
                    finalized=finalized+1
                    H.equal(type(mod._wt_peer_parity),"table")
                    H.equal(mod._wt_peer_parity:is_installed(),true)
                    H.equal(mod._wt431_disconnect_epoch_guard,true)
                    H.equal(mod._wt431_wire_floor_installed,true)
                    H.equal(mod._wt431_parity_gated,true)
                    H.equal(mod._wt_peer_parity:feature_count(),1)
                    H.equal(type(mod._wt431_profiles_allowed),"function")
                    return finish(owner)
                end
                local chunk=assert(loadfile(catalog_prefix.."_wt431_damage_profile_parity.lua"))
                setfenv(chunk,environment)
                H.equal(type(chunk()),"table")
                H.equal(finalized,1,"actual catalog module must reach thermal finalization")
                H.equal(node.owner.committed,true)
                node.catalog_identity=mod._wt431_wire_catalog_identity
            end
            local a,b=net:add("host",{prepare_only=true}),net:add("client",{prepare_only=true})
            boot(a);boot(b)
            net:connect("host","client");net:settle()
            H.equal(a:damage(direct(a)),13);H.equal(b:damage(direct(b)),13)
            a.on_join=function(id)
                H.equal(a.owner.transport.pending[id],true)
                H.equal(a.mod._wt_peer_parity:applied_state(),"disabled")
                H.equal(a:damage(direct(a)),10)
            end
            a.classes.network.hot_join_sync({},"late")
            a.classes.network.remove_peer({},"late")
            H.equal(a.owner.transport.pending.late,nil)
        end
    end)
    H.test("WT #942 actual default dependencies install exact literal targets and VMF channel",function()
        local net=Fixture.network(load,Json)
        local function install(mod,heavy,balance,deps,node)
            local environment=setmetatable({},{__index=_G})
            environment._G=environment
            environment.Weapons=node.weapons
            environment.DamageProfileTemplates=node.profiles
            environment.NetworkLookup={damage_profiles=node.lookup}
            environment.PowerLevelTemplates={armor_modifier_linesman_H=deps.armor_reference}
            environment.ALIVE={[node.unit]=true}
            environment.ScriptUnit={has_extension=deps.extension}
            environment.Managers={player={human_players=deps.humans}}
            environment.Network={peer_id=deps.local_peer}
            environment.Application={guid=deps.guid}
            environment.AiUtils={unit_breed=deps.breed}
            environment.DamageUtils=node.classes.damage
            environment.DamageUtils.get_breed_damage_multiplier_type=deps.multiplier
            environment.ActionSweep=node.classes.sweep
            environment.ActionShieldSlam=node.classes.slam
            environment.ActionUtils=node.classes.utils
            environment.GameNetworkManager=node.classes.network
            environment.table=setmetatable({clone=deps.clone},{__index=table})
            environment.printf=deps.log
            mod._wt431_custom_profile_fallback=deps.fallbacks
            mod.is_enabled=function() return node.enabled end
            mod.dofile=function(_,path)
                local name=assert(path:match("^scripts/mods/weapon_tweaker/([%w_]+)$"))
                return load(name)
            end
            local installed={}
            mod.hook=function(_,class,method,callback)
                installed[#installed+1]={class,method}
                return deps.hook(class,method,callback)
            end
            local chunk=assert(loadfile(prefix.."_wt_fire_sword_owner.lua"))
            setfenv(chunk,environment)
            local owner_module=chunk()
            local owner=owner_module.install(mod,heavy,balance)
            H.equal(#installed,5)
            H.deep_equal(installed,{{node.classes.damage,"calculate_damage"},
                {node.classes.sweep,"client_owner_start_action"},
                {node.classes.slam,"client_owner_start_action"},
                {node.classes.utils,"get_max_targets"},{node.classes.network,"hot_join_sync"}})
            H.equal(owner_module.install(mod,heavy,balance),owner)
            H.equal(#installed,5,"default installation must never retry")
            H.equal(type(node.receivers.wt_fire_sword_heat_config_v1),"function")
            return owner
        end
        local a,b=net:add("host",{install=install}),net:add("client",{install=install})
        net:connect("host","client");net:settle()
        H.equal(a.owner.committed,true);H.equal(b.owner.committed,true)
        H.equal(a:damage(direct(a)),13);H.equal(b:damage(direct(b)),13)
    end)
    H.test("WT #942 installed pair applies damage and cleave and preserves tuples",function()
        local _,a,b=pair()
        for _,node in ipairs({a,b}) do
            H.truthy(node.mod._wt431_profiles_allowed())
            H.deep_equal(pack(node:damage(direct(node))),{n=4,13,nil,"tail",nil})
            H.deep_equal(pack(node.classes.sweep.client_owner_start_action({owner_unit=node.unit},
                node.native.heavy_attack_left,7,nil,600,nil,"extra")),
                {n=8,160,nil,"sweep",7,nil,600,nil,"extra"})
            H.equal(node.native.heavy_attack_spell.damage_profile_aoe,"aoe")
            H.equal(node.native.heavy_attack_spell.anim_time_scale,1)
        end
    end)
    H.test("WT #942 pre-roster join fences heat and existing catalog inside native sync",function()
        local _,a=pair()
        H.equal(a:damage(direct(a)),13)
        a.on_join=function(id)
            H.equal(id,"late")
            H.equal(a.owner.transport.pending.late,true)
            H.equal(a.mod._wt_peer_parity:applied_state(),"disabled")
            H.equal(a.native.heavy_attack_left.damage_profile,"direct")
            H.equal(a:damage(direct(a)),10)
        end
        H.deep_equal(pack(a.classes.network.hot_join_sync({},"late",nil,"tail")),
            {n=4,"late",nil,nil,"tail"})
        a.owner:reconcile()
        H.equal(a.native.heavy_attack_left.damage_profile,"direct","unseen pending peer must not become solo")
    end)
    H.test("WT #942 config changes on either role and change-back require fresh exchanges",function()
        local net,a,b=pair()
        for _,node in ipairs({a,b}) do
            local generation=node.owner.transport.protocol:inspect().generation
            node.settings.wt_fire_sword_heat_damage_percent=2
            node.mod._wt942_on_setting_changed("wt_fire_sword_heat_damage_percent")
            H.equal(node:damage(direct(node)),10)
            node.settings.wt_fire_sword_heat_damage_percent=1
            node.mod._wt942_on_setting_changed("wt_fire_sword_heat_damage_percent")
            H.truthy(node.owner.transport.protocol:inspect().generation>=generation+2)
            H.equal(node:damage(direct(node)),10)
            net:pump();net:settle()
            H.equal(a:damage(direct(a)),13);H.equal(b:damage(direct(b)),13)
        end
    end)
    H.test("WT #942 armor uses resolved owned tables and strict threshold",function()
        local _,a=pair()
        local function start()
            local actor={owner_unit=a.unit}
            a.classes.sweep.client_owner_start_action(actor,a.native.heavy_attack_left)
            return a.profiles[actor.seen.damage_profile]
        end
        a.heat=25;H.equal(start().armor_modifier.attack[2],0)
        a.heat=25.1;H.equal(start().armor_modifier.attack[2],.3)
        H.equal(a.profiles.direct.armor_modifier.attack[2],0)
        a.dead=true;H.equal(a:damage(direct(a)),10)
        a.dead=false;a.extension_error=true;H.equal(a:damage(direct(a)),10)
    end)
    H.test("WT #942 no heat, offhand, no-damage and foreign profiles stay native",function()
        local _,a=pair()
        a.heat=0;H.equal(a:damage(direct(a)),10)
        a.heat=100;H.equal(a:damage(direct(a)),14)
        a.maximum=60;H.equal(a:damage(direct(a)),16)
        H.equal(a:damage(a.profiles.aoe),10)
        H.equal(a:damage({charge_value="light_attack"}),10)
        local actor={owner_unit=a.unit}
        H.equal(a.classes.sweep.client_owner_start_action(actor,a.native.heavy_attack_left,0,nil,600,{action_hand="left"}),100)
        H.equal(actor.seen.damage_profile,"direct")
    end)
    H.test("WT #942 retained receiver failure is terminal inert and never retries",function()
        local net=Fixture.network(load,Json)
        local a=net:add("host",{register_throw=true})
        H.equal(a.owner.committed,false);H.equal(a.owner.terminal,true)
        H.equal(a.native.heavy_attack_left.damage_profile,"direct")
        local count=a.hook_count()
        H.equal(load("_wt_fire_sword_owner").install(a.mod,load("_wt_fire_sword"),{},a.deps),a.owner)
        H.equal(a.hook_count(),count)
        local pending=#net.queue
        a.humans={{peer_id="host"},{peer_id="client"}}
        a.receivers.wt_fire_sword_heat_config_v1("client",1,"q","other",1,"",0,"c1","",1,1,"0","0","0")
        H.equal(#net.queue,pending)
        H.deep_equal(pack(a:damage(direct(a))),{n=4,10,nil,"tail",nil})
    end)
    H.test("WT #942 retained hook failure preserves native start and damage tuples",function()
        local net=Fixture.network(load,Json)
        local a=net:add("host",{hook_throw=2})
        H.equal(a.owner.committed,false)
        H.deep_equal(pack(a.classes.sweep.client_owner_start_action({owner_unit=a.unit},
            a.native.heavy_attack_left,nil,"tail")),{n=5,100,nil,"sweep",nil,"tail"})
        H.deep_equal(pack(a:damage(direct(a))),{n=4,10,nil,"tail",nil})
    end)
    H.test("WT #942 stored-then-throw callback assignment restores exact raw shape",function()
        local inherited
        local net=Fixture.network(load,Json)
        local a=net:add("host",{prepare_only=true,mod_setup=function(mod)
            inherited=mod.update;mod.update=nil
            setmetatable(mod,{__index={update=inherited},__newindex=function(t,key,value)
                rawset(t,key,value);if key=="update" then error("stored update") end
            end})
        end})
        H.equal(a.owner.committed,false);H.equal(a.owner.terminal,true)
        H.equal(rawget(a.mod,"update"),nil);H.equal(a.mod.update,inherited)
        H.deep_equal(pack(a.mod.update(.25,nil,"tail")),{n=3,nil,"update",nil})
    end)
    H.test("WT #942 profile registration is independent of toggles and GUID failure",function()
        local net=Fixture.network(load,Json)
        local a=net:add("host",{guid="broken",change_deps=function(_,n) n.settings.wt_fire_sword_heat=false end})
        H.truthy(a.lookup.wt942_direct_direct)
        H.truthy(a.lookup.wt942_armored_direct)
        H.equal(a.owner.committed,false);H.equal(a.native.heavy_attack_left.damage_profile,"direct")
    end)
    H.test("WT #942 GUID encoding preserves all bits and refuses malformed/truncated inputs",function()
        local T=load("_wt_fire_sword_heat_transport")
        H.equal(T.epoch("00000000000000000000000000000000"),"AAAAAAAAAAAAAAAAAAAAAA")
        H.equal(T.epoch("ffffffffffffffffffffffffffffffff"),"_____________________w")
        H.equal(T.epoch("{00112233-4455-6677-8899-aabbccddeeff}"),T.epoch("00112233445566778899AABBCCDDEEFF"))
        local seen={}
        for nibble=1,32 do for digit=1,15 do
            local value=string.rep("0",nibble-1)..string.format("%x",digit)..string.rep("0",32-nibble)
            local encoded=T.epoch(value);H.equal(#encoded,22);H.equal(seen[encoded],nil);seen[encoded]=true
        end end
        for _,bad in ipairs({"", "x",string.rep("0",31),string.rep("0",33),string.rep("-",36)}) do H.equal(T.epoch(bad),nil) end
    end)
    H.test("WT #942 clock never resets with worlds and invalid dt poisons only the feature",function()
        local net,a=pair();local before=a.owner.transport.clock
        H.deep_equal(pack(a.mod.on_game_state_changed("exit","StateIngame")),{n=3,nil,"state",nil})
        H.equal(a:damage(direct(a)),10)
        H.equal(a.owner.transport.clock,before)
        a.mod.on_game_state_changed("enter","StateIngame");net:settle()
        H.truthy(a.owner.transport.clock>before);H.equal(a:damage(direct(a)),13)
        H.deep_equal(pack(a.adapter_update(0/0,nil,"tail")),{n=3,nil,"update",nil})
        H.equal(a.owner.transport.poisoned,true);H.equal(a:damage(direct(a)),10)
        H.truthy(a.checks.issue942_fire_sword_heat_boundary():find("healthy",1,true))
    end)
    H.test("WT #942 disable and re-enable invalidate proof without setting writes",function()
        local net,a=pair();local generation=a.owner.transport.protocol:inspect().generation
        H.deep_equal(pack(a.mod.on_disabled("tail")),{n=4,nil,"disabled",nil,"tail"})
        H.equal(a:damage(direct(a)),10);H.equal(a.settings.wt_fire_sword_heat,true)
        a.mod.on_enabled();H.equal(a:damage(direct(a)),10)
        H.truthy(a.owner.transport.protocol:inspect().generation>=generation+2)
        net:settle();H.equal(a:damage(direct(a)),13)
    end)
    H.test("WT #942 missing/throwing roster fails closed and recovers with fresh proof",function()
        local net,a=pair()
        a.roster_error=true;a.owner:reconcile();H.equal(a:damage(direct(a)),10)
        a.roster_error=false;H.equal(a:damage(direct(a)),10)
        net:settle();H.equal(a:damage(direct(a)),13)
        a.humans={};a.owner:reconcile();H.equal(a:damage(direct(a)),10)
    end)
    H.test("WT #942 post-catalog template replacement becomes inert without late registration",function()
        local _,a=pair();local count=#a.lookup
        a.weapons={flaming_sword_template_1={actions={}}}
        a.owner:reconcile();H.equal(a.owner.committed,false);H.equal(#a.lookup,count)
        H.equal(a:damage(direct(a)),10)
    end)
    H.test("WT #942 per-hit queries emit no packets and foreign/count malformed callbacks are inert",function()
        local net,a=pair();local count=#net.history
        for _=1,100 do H.equal(a:damage(direct(a)),13) end
        H.equal(#net.history,count)
        local receiver=a.receivers.wt_fire_sword_heat_config_v1
        H.equal(receiver("foreign",1,"q","x",1,"",0,"c1","",1,1,"0","0","0"),false)
        H.equal(receiver("client",1,"q"),false)
        H.equal(#net.history,count)
    end)
    H.test("WT #942 real adapter retries lost config packets and rejects replay after settings change",function()
        local net,a,b=pair()
        local dropped=false
        net.intercept=function(message)
            if not dropped and message.channel=="wt_fire_sword_heat_config_v1" then dropped=true;return false end
        end
        for _,node in ipairs({a,b}) do
            node.settings.wt_fire_sword_heat_damage_percent=2
            node.owner:settings_changed("wt_fire_sword_heat_damage_percent")
        end
        net:settle();H.equal(dropped,true)
        H.equal(a:damage(direct(a)),16);H.equal(b:damage(direct(b)),16)
        local history={};for _,message in ipairs(net.history) do
            if message.channel=="wt_fire_sword_heat_config_v1" then history[#history+1]=message end
        end
        a.settings.wt_fire_sword_heat_damage_percent=1;a.owner:settings_changed("wt_fire_sword_heat_damage_percent")
        for _,message in ipairs(history) do
            net.nodes[message.to].receivers[message.channel](message.from,unpack(message.args))
        end
        H.equal(a:damage(direct(a)),10)
    end)
    H.test("WT #942 pending join allocation is capped and over-cap becomes terminal",function()
        local _,a=pair()
        for i=1,40 do a.classes.network.hot_join_sync({},"pending"..i) end
        local count=0;for _ in pairs(a.owner.transport.pending) do count=count+1 end
        H.equal(count,32);H.equal(a.owner.terminal,true);H.equal(a.owner.committed,false)
        H.equal(a:damage(direct(a)),10)
    end)
    H.test("WT #942 native start/damage errors retain identity and clear temporary context",function()
        local marker={}
        local net=Fixture.network(load,Json)
        local a=net:add("host",{mod_setup=function(_,node)
            node.classes.sweep.client_owner_start_action=function() error(marker) end
            node.classes.damage.calculate_damage=function() error(marker) end
        end})
        local b=net:add("client");net:connect("host","client");net:settle()
        local ok,error_value=pcall(a.classes.sweep.client_owner_start_action,{owner_unit=a.unit},a.native.heavy_attack_left)
        H.equal(ok,false);H.equal(error_value,marker);H.equal(a.owner.runtime.context,nil)
        ok,error_value=pcall(a.damage,a,direct(a));H.equal(ok,false);H.equal(error_value,marker)
    end)
    H.test("WT #942 failed lifecycle callback stays inert and rethrows exact error",function()
        local marker={};local net=Fixture.network(load,Json)
        local a=net:add("host",{mod_setup=function(mod) mod.on_game_state_changed=function() error(marker) end end})
        local b=net:add("client");net:connect("host","client");net:settle()
        local ok,value=pcall(a.mod.on_game_state_changed,"enter","StateIngame")
        H.equal(ok,false);H.equal(value,marker);H.equal(a.owner.suspended,true)
        H.equal(a:damage(direct(a)),10)
    end)
    H.test("WT #942 latched armor returns to donor after terminal owner failure",function()
        local _,a=pair();local actor={owner_unit=a.unit}
        a.classes.sweep.client_owner_start_action(actor,a.native.heavy_attack_left)
        local armored=a.profiles[actor.seen.damage_profile]
        H.equal(armored.armor_modifier.attack[2],.3)
        a.weapons={};a.owner:reconcile()
        H.equal(a.owner.terminal,true);H.equal(a:damage(armored),10)
        H.equal(a.native_damage[9],a.profiles.direct,"failed owner must not pass latched armor to native")
    end)
    H.test("WT #942 named real registration reads installed owner and missing dependency fails",function()
        local _,a=pair()
        H.equal(a.checks.issue942_fire_sword_heat_boundary(),nil)
        a.deps.load=function() return nil end
        H.truthy(a.checks.issue942_fire_sword_heat_boundary():find("runtime check missing",1,true))
    end)
    H.test("WT #942 named check never rewrites installed or global state",function()
        local _,a=pair()
        local seen,records={},{}
        local function capture(value)
            if type(value)~="table" or seen[value] then return end
            seen[value]=true
            local row={target=value,meta=getmetatable(value),fields={}}
            records[#records+1]=row
            for key,item in next,value do
                row.fields[key]=item;capture(key);capture(item)
            end
        end
        capture(a.mod);capture(a.deps);capture(a.lookup)
        local globals={}
        for _,key in ipairs({"Managers","Network","printf","setfenv","getfenv"}) do
            globals[key]={rawget(_G,key)}
        end
        H.equal(a.checks.issue942_fire_sword_heat_boundary(),nil)
        for _,row in ipairs(records) do
            H.equal(getmetatable(row.target),row.meta)
            for key,item in next,row.fields do H.equal(rawget(row.target,key),item) end
            for key in next,row.target do H.equal(rawget(row.fields,key),rawget(row.target,key)) end
        end
        for key,item in pairs(globals) do H.equal(rawget(_G,key),item[1]) end
    end)
    for _,namespace in ipairs({"weapon_tweaker","weapon_tweaker_dev"}) do
        local checks=assert(loadfile(root.."/"..namespace.."/scripts/mods/"..namespace
            .."/_wt_fire_sword_heat_checks.lua"))()
        for _,failure in ipairs({"owner","template","hook","catalog","profile","fallback","action","protocol"}) do
            H.test(namespace.." #942 installed diagnostic rejects lost "..failure,function()
                local _,a=pair()
                if failure=="owner" then a.mod._wt942_owner={}
                elseif failure=="template" then a.weapons["flaming_sword_template_1"]={}
                elseif failure=="hook" then a.owner.hooks.join=false
                elseif failure=="catalog" then a.mod._wt431_disconnect_epoch_guard=nil
                elseif failure=="profile" then a.profiles.wt942_direct_direct={}
                elseif failure=="fallback" then a.deps.fallbacks.wt942_direct_direct="foreign"
                elseif failure=="action" then a.owner.runtime.state.rows[1].key="foreign"
                else a.owner.transport.protocol={inspect=function() return {fatal=true} end} end
                local ok=pcall(checks.run,load,a.mod,a.owner,a.deps)
                H.equal(ok,false,"lost installed dependency must fail the diagnostic")
            end)
        end
    end
    H.test("WT #942 runtime check still executes private protocol mismatch oracle",function()
        local _,a=pair()
        local checks=load("_wt_fire_sword_heat_checks")
        local real=load("_wt_fire_sword_heat_config_proof")
        local function disconnected(name)
            if name~="_wt_fire_sword_heat_config_proof" then return load(name) end
            return setmetatable({new=function(deps)
                local protocol=real.new(deps)
                protocol.allows=function() return true end
                return protocol
            end},{__index=real})
        end
        local ok,problem=pcall(checks.run,disconnected,a.mod,a.owner,a.deps)
        H.equal(ok,false)
        H.truthy(tostring(problem):find("mismatch stayed active",1,true))
    end)
    H.test("WT #942 original restricted JSON fixture round trips exact protocol shapes",function()
        for _,packet in ipairs({{1,"q","a",1000000000,"",0,"c1000000000","",1,0,"0","0","0"},
            {1,"r","b",1000000000,"a",1000000000,"c1","c2",0,1,"4503599627370496e-2","4503599627370496e-2","7036874417766400e7"},
            {1,"a","b",1,"a",1,"","c1",1,1,"0","0","0"}}) do
            local encoded=Json.encode(packet);H.deep_equal(Json.decode(encoded),packet);H.truthy(#encoded<500)
        end
        for _,bad in ipairs({"[1,]","[01]",'["\\n"]',"[1]tail","{\"a\":1}","[1.5]"}) do
            H.equal(pcall(Json.decode,bad),false)
        end
    end)
    H.test("WT #942 actual settings owner dispatches heat edits and one final owner batch apply",function()
        local _,a=pair();local applies=0
        local original_apply=a.owner.runtime.apply
        a.owner.runtime.apply=function(...)
            applies=applies+1;return original_apply(...)
        end
        a.mod.set=function(_,key,value) a.settings[key]=value end
        local Master=load("_wt_rework_master_policy")
        local Rework=load("_wt_rework_master_runtime").new(a.mod,Master,function()
            a.mod._wt_apply_fire_sword(nil,false)
        end)
        local noop=function() end
        load("_wt_settings_runtime").install({mod=a.mod,rework_runtime=Rework,
            master_toggles={reconcile_batch=noop},backend={refresh_on_setting_change=noop},
            apply_weapon_unlocks=noop,patch_career_actions=noop,apply_trait_filters=noop,
            bolt_runtime={apply=noop},bolt_policy={SETTING_ID="unrelated"},balance_policy={},
            fire_sword_policy=load("_wt_fire_sword")})
        a.settings.wt_fire_sword_heat_damage_percent=2
        a.mod.on_setting_changed("wt_fire_sword_heat_damage_percent")
        H.equal(applies,1);H.equal(a:damage(direct(a)),10)
        applies=0
        a.settings.wt_fire_sword_heat_damage_percent=1
        a.mod.on_settings_batch_changed({"wt_fire_sword_heat_damage_percent","wt_fire_sword_heat_armor"})
        H.equal(applies,1,"owner batch must not project once per setting or twice via callbacks")
        applies=0;a.settings.wt_rework_master_ensrick=false
        a.mod.on_setting_changed("wt_rework_master_ensrick")
        H.equal(applies,1);H.equal(a.settings.wt_fire_sword_heat,false)
    end)
    H.test("WT #942 catalog mutation independently closes damage despite matching configuration",function()
        local _,a=pair()
        H.equal(a:damage(direct(a)),13)
        local index=a.lookup.wt942_direct_direct
        a.lookup.wt942_direct_direct=index+100
        H.equal(a:damage(direct(a)),10)
        H.equal(a.mod._wt431_profiles_allowed(),false)
    end)
    H.test("WT #942 null or throwing GUID and missing native seam are inert without retry",function()
        for _,options in ipairs({{guid=string.rep("0",32)},
            {change_deps=function(d) d.guid=function() error("guid reader") end end},
            {change_deps=function(d) d.classes.sweep.client_owner_start_action=nil end}}) do
            local net=Fixture.network(load,Json);local node=net:add("host",options)
            H.equal(node.owner.committed,false);H.equal(node.owner.terminal,true)
            H.truthy(node.lookup.wt942_direct_direct,"complete registration precedes GUID/seam failure")
            H.equal(node:damage(direct(node)),10)
        end
    end)

    local function local_capture_player(node)
        for _, player in pairs(node.humans) do
            if player.peer_id == node.id then
                player.player_unit, player.local_player = node.unit, true
            end
        end
    end
    H.test("WT #942 actual owner arm is bounded local-only and stops on existing lifecycle", function()
        local net,a=pair();local_capture_player(a)
        local packets=#net.history
        H.equal(a.owner:capture("arm"),true)
        H.equal(a:damage(direct(a)),13)
        local data=assert(a.owner:capture("dump"))
        H.equal(data.count,1);H.truthy(data.header:find("owner_committed_at_arm=1",1,true))
        H.equal(#net.history,packets,"arm/sample/dump cannot add protocol traffic")
        H.equal(a.owner:capture("arm"),true);a:damage(direct(a))
        a.mod.on_game_state_changed("exit","StateIngame")
        data=assert(a.owner:capture("dump"))
        H.equal(data.count,1);H.truthy(data.header:find("reason=settings-changed",1,true))
        H.equal(a.owner:capture("arm"),false)
        a.humans={};H.equal(a.owner:capture("arm"),false)
    end)
    H.test("WT #942 actual owner refuses ambiguous dead and foreign capture identities", function()
        for _,fault in ipairs({"split","dead","foreign","over-cap","lost-owner"}) do
            local _,a=pair();local_capture_player(a)
            if fault=="split" then a.humans[#a.humans+1]={peer_id=a.id,player_unit=a.unit,local_player=true}
            elseif fault=="dead" then a.dead=true
            elseif fault=="foreign" then a.humans[1].peer_id="not-the-local-peer"
            elseif fault=="over-cap" then for index=1,5 do a.humans[index]={peer_id="other"..index} end
            else a.mod._wt942_owner={} end
            H.equal(a.owner:capture("arm"),false)
            H.equal(a.owner:capture("dump"),nil)
        end
    end)
    H.test("WT #942 actual diagnostics owns one finite dump and closed command actions", function()
        local _,a=pair();local_capture_player(a)
        local commands,logs={},{}
        a.mod.command=function(_,name,_,callback) commands[name]=callback end
        local env=setmetatable({get_mod=function(id) if id=="wt" then return a.mod end end,
            printf=function(format,...) logs[#logs+1]=string.format(format,...) end},{__index=_G})
        env._G=env
        local chunk=assert(loadfile(prefix.."_wt_diagnostics.lua"));setfenv(chunk,env);chunk()
        local command=assert(commands.wt_heat_capture)
        command("arm","extra");H.equal(#logs,0)
        command("dump");H.equal(#logs,0)
        command("arm");H.equal(a:damage(direct(a)),13)
        command("dump");H.equal(#logs,3)
        H.truthy(logs[1]:find("[wt:942:capture] begin ",1,true)==1)
        H.truthy(logs[2]:find("pre_942_calculated_damage=10",1,true))
        H.truthy(logs[2]:find("post_942_calculated_damage=13",1,true))
        H.equal(logs[3],"[wt:942:capture] end count=1")
        command("dump");command("clear");H.equal(#logs,3,"explicit dump is one shot")
        local bytes=0;for _,line in ipairs(logs) do H.truthy(#line+1<=1024);bytes=bytes+#line+1 end
        H.truthy(bytes<=10240)
    end)

    -- Actual owner/runtime/protocols, plus a native result-recording boundary.
    -- The optional fixture installer supplies the REAL #664 policy, never an
    -- identity/healthy substitute for a production WT module.
    local function captured_pair(namespace, executioner_marker)
        local stream_prefix = root .. "/" .. namespace .. "/scripts/mods/" .. namespace .. "/"
        local function stream_load(name) return assert(loadfile(stream_prefix .. name .. ".lua"))() end
        local net = Fixture.network(stream_load, Json)
        local options = {
            change_deps = function(_, node)
                if executioner_marker then node.profiles.direct._wt_executioner_light_headshot_multiplier = 1.3 end
            end,
            mod_setup = function(_, node)
                node.native_results, node.native_calls = pack(40, nil, "tail", nil), 0
                node.classes.damage.calculate_damage = function(...)
                    node.native_calls = node.native_calls + 1; node.native_damage = pack(...)
                    if node.native_error then error(node.native_error, 0) end
                    return unpack(node.native_results, 1, node.native_results.n)
                end
            end,
            install = function(mod, heavy, _, deps)
                return stream_load("_wt_fire_sword_owner").install(mod, heavy, stream_load("_wt_axe_balance"), deps)
            end,
        }
        local a, b = net:add("host", options), net:add("client", options)
        net:connect("host", "client"); net:settle()
        local_capture_player(a); local_capture_player(b)
        return net, a, b, stream_prefix
    end
    local function capture_contains(row, field)
        H.truthy(type(row) == "string" and row:find(field, 1, true), "capture field absent: " .. field)
    end
    local function capture_number(row, key)
        local value = assert(row:match(" " .. key .. "=([^ ]+)"), "numeric capture field absent: " .. key)
        return tonumber(value) -- keep assert's diagnostic message out of tonumber's optional base.
    end
    local function near(actual, expected)
        H.truthy(type(actual) == "number" and math.abs(actual - expected) < 1e-9, "actual calculated capture value differs")
    end
    local function command_capture(node, stream_prefix)
        local commands, logs = {}, {}
        node.mod.command = function(_, name, _, callback) commands[name] = callback end
        local env = setmetatable({ get_mod = function() return node.mod end,
            printf = function(fmt, ...) logs[#logs + 1] = string.format(fmt, ...) end }, { __index = _G })
        env._G = env
        local namespace = assert(stream_prefix:match("/scripts/mods/([^/]+)/$"))
        node.mod.dofile = function(_, path)
            local name = assert(path:match("^scripts/mods/" .. namespace .. "/([%w_]+)$"),
                "command fixture refused a foreign stream module")
            local helper = assert(loadfile(stream_prefix .. name .. ".lua"))
            setfenv(helper, env)
            return helper()
        end
        local chunk = assert(loadfile(stream_prefix .. "_wt_diagnostics.lua")); setfenv(chunk, env); chunk()
        return assert(commands.wt_heat_capture), logs
    end
    local function clear_logs(logs) for index = #logs, 1, -1 do logs[index] = nil end end
    local function numeric_ascii_lines(logs)
        local bytes = 0
        H.truthy(#logs <= 10, "explicit dump exceeds ten lines")
        for _, line in ipairs(logs) do
            H.truthy(#line + 1 <= 1024, "explicit dump line exceeds1024 bytes")
            bytes = bytes + #line + 1
            for index = 1, #line do
                local byte = line:byte(index)
                H.truthy(byte >= 32 and byte <= 126, "explicit dump contains a nonprintable byte")
            end
        end
        H.truthy(bytes <= 10240, "explicit dump exceeds10KiB")
    end

    H.test("WT #942 actual singleton captures strict normal armor donor and delegated664 values", function()
        for _, namespace in ipairs({ "weapon_tweaker", "weapon_tweaker_dev" }) do
            local net, a, b = captured_pair(namespace)
            local token = {}; a.native_results = pack(40, nil, token, nil)
            -- Literal independently authored expected cells, not a recomputation
            -- through state:damage_profile or the capture's own numeric formatter.
            for _, cell in ipairs({
                { threshold = 0, heat = 0, key = "direct", post = 40 },
                { threshold = 0, heat = 12.5, key = "wt942_armored_direct", post = 45 },
                { threshold = 25, heat = 24, key = "wt942_direct_direct", post = 49.6 },
                { threshold = 25, heat = 25, key = "wt942_direct_direct", post = 50 },
                { threshold = 25, heat = 26, key = "wt942_armored_direct", post = 50.4 },
            }) do
                for _, node in ipairs({ a, b }) do
                    node.settings.wt_fire_sword_heat_armor_threshold = cell.threshold
                    node.owner:settings_changed("wt_fire_sword_heat_armor_threshold")
                end
                net:settle(); a.heat = cell.heat; a.native_calls = 0
                local packets = #net.history
                H.equal(a.owner:capture("arm"), true)
                local out = pack(a:damage(a.profiles.wt942_armored_direct)) -- deliberately latched armor input
                H.equal(out.n, 4); near(out[1], cell.post)
                H.equal(out[2], nil); H.equal(rawequal(out[3], token), true); H.equal(out[4], nil)
                H.equal(a.native_calls, 1)
                H.equal(rawequal(a.native_damage[9], a.profiles[cell.key]), true)
                H.equal(a.native_damage[5], 600)
                local data = assert(a.owner:capture("dump")); H.equal(data.count, 1)
                capture_contains(data.rows[1], "selected_profile=" .. cell.key)
                capture_contains(data.rows[1], "action_context=none action=unknown")
                near(capture_number(data.rows[1], "heat_raw"), cell.heat)
                near(capture_number(data.rows[1], "pre_942_calculated_damage"), 40)
                near(capture_number(data.rows[1], "post_942_calculated_damage"), cell.post)
                H.equal(#net.history, packets, "observing a settled calculation must not send extra packets")
            end
            local _, marked = captured_pair(namespace, true)
            marked.heat = 12.5; H.equal(marked.owner:capture("arm"), true)
            near(marked:damage(direct(marked)), 58.5)
            local data = assert(marked.owner:capture("dump"))
            near(capture_number(data.rows[1], "pre_942_calculated_damage"), 52)
            near(capture_number(data.rows[1], "post_942_calculated_damage"), 58.5)
        end
    end)

    H.test("WT #942 actual singleton retains zero nonnumeric nonfinite tuples and opaque errors", function()
        for _, namespace in ipairs({ "weapon_tweaker", "weapon_tweaker_dev" }) do
            local _, a = captured_pair(namespace); a.heat = 12.5
            local token = {}
            local cells = { { value = 0, ratio = "zero-input" }, { missing = true, ratio = "unavailable" },
                { value = false, ratio = "unavailable" }, { value = "native-result", ratio = "unavailable" },
                { value = math.huge, ratio = "unavailable" }, { value = 0/0, ratio = "unavailable", nan = true } }
            for _, cell in ipairs(cells) do
                a.native_results = pack(cell.value, nil, token, nil); a.native_calls = 0
                H.equal(a.owner:capture("arm"), true)
                local out = pack(a:damage(direct(a)))
                H.equal(out.n, 4)
                if cell.nan then H.truthy(type(out[1]) == "number" and out[1] ~= out[1])
                else H.equal(out[1], cell.value) end
                H.equal(out[2], nil); H.equal(rawequal(out[3], token), true); H.equal(out[4], nil)
                H.equal(a.native_calls, 1)
                local data = assert(a.owner:capture("dump")); H.equal(data.count, 1)
                capture_contains(data.rows[1], "observed_damage_ratio=" .. cell.ratio)
                local rendered = cell.value == 0 and "0" or "unavailable"
                capture_contains(data.rows[1], "pre_942_calculated_damage=" .. rendered)
                capture_contains(data.rows[1], "post_942_calculated_damage=" .. rendered)
            end
            local opaque = setmetatable({}, { __tostring = function() error("opaque damage error stringified") end })
            a.native_error = opaque; a.native_calls = 0; H.equal(a.owner:capture("arm"), true)
            local ok, failure = pcall(a.damage, a, direct(a))
            H.equal(ok, false); H.equal(rawequal(failure, opaque), true); H.equal(a.native_calls, 1)
            local data = assert(a.owner:capture("dump")); H.equal(data.count, 0,
                "a thrown calculation must not manufacture an after-record")
        end
    end)

    H.test("WT #942 actual command validates every byte with an independent numeric oracle", function()
        for _, namespace in ipairs({ "weapon_tweaker", "weapon_tweaker_dev" }) do
            local _, a, _, stream_prefix = captured_pair(namespace)
            local command, logs = command_capture(a, stream_prefix)
            local actual_capture, selected_byte = a.owner.capture, 0
            -- Corrupt only a COPY returned by the real capture, after its real
            -- one-shot token is consumed. No healthy owner/source shim is used.
            a.owner.capture = function(self, action)
                local data, status = actual_capture(self, action)
                if action == "dump" and type(data) == "table" then
                    H.equal(data.count, 1, "real capture row required before adversarial byte")
                    data.rows[1] = data.rows[1] .. " byte=" .. string.char(selected_byte)
                end
                return data, status
            end
            for byte = 0, 255 do
                selected_byte = byte; clear_logs(logs)
                command("arm"); a:damage(direct(a)); command("dump")
                if byte >= 32 and byte <= 126 then
                    H.equal(#logs, 3, "printable evidence byte must retain one complete real dump")
                else H.equal(#logs, 0, "nonprintable evidence byte must be refused before the first emission") end
                numeric_ascii_lines(logs)
                local count = #logs; command("dump")
                H.equal(#logs, count, "malformed or valid data cannot replay a consumed real capture")
            end
        end
    end)

    H.test("WT #942 actual command emits one full capped dump and labels zero observations", function()
        for _, namespace in ipairs({ "weapon_tweaker", "weapon_tweaker_dev" }) do
            local net, a, _, stream_prefix = captured_pair(namespace)
            local command, logs = command_capture(a, stream_prefix)
            local packets = #net.history
            command("arm")
            for _ = 1, 9 do a:damage(direct(a)) end
            command("dump"); H.equal(#logs, 10)
            H.equal(logs[10], "[wt:942:capture] end count=8"); numeric_ascii_lines(logs)
            command("dump"); H.equal(#logs, 10)
            clear_logs(logs); command("arm"); command("dump")
            H.equal(#logs, 2); capture_contains(logs[1], "count=0/8")
            H.equal(logs[2], "[wt:942:capture] end count=0"); numeric_ascii_lines(logs)
            H.equal(#net.history, packets, "command dump and arm do not create protocol traffic")
        end
    end)

    local function unchanged_capture_native(node, profile, token)
        local calls = node.native_calls
        local out = pack(node:damage(profile))
        H.equal(out.n, 4); H.equal(out[1], 40); H.equal(out[2], nil)
        H.equal(rawequal(out[3], token), true); H.equal(out[4], nil)
        H.equal(node.native_calls, calls + 1, "observer loss cannot duplicate or skip the native calculation")
        local args = node.native_damage
        H.equal(args.n, 12); H.equal(args[1], "output")
        H.equal(rawequal(args[2], node.unit), true); H.equal(rawequal(args[3], node.unit), true)
        H.equal(args[4], "head"); H.equal(args[5], 600); H.equal(args[6], nil)
        H.equal(args[7], 1); H.equal(args[8], false); H.equal(rawequal(args[9], profile), true)
        H.equal(args[10], nil); H.equal(args[11], "extra"); H.equal(args[12], nil)
    end

    H.test("WT #942 actual owner freezes post-arm identity loss with the old unit still alive", function()
        for _, namespace in ipairs({ "weapon_tweaker", "weapon_tweaker_dev" }) do
            for _, fault in ipairs({ "replacement", "foreign-peer", "foreign-local", "split",
                    "malformed-row", "malformed-roster", "throwing-roster", "over-budget" }) do
                local net, a, b = captured_pair(namespace)
                local old, replacement, token, profile = a.unit, {}, {}, {}
                local row, roster = a.humans[1], a.humans
                H.equal(rawget(row, "peer_id"), a.id)
                local reads, throwing, stringified, indexed = 0, false, 0, 0
                local opaque = setmetatable({}, { __tostring = function()
                    stringified = stringified + 1; error("roster error must not be stringified")
                end })
                -- Runtime retains the original fixture alive reader (old==a.unit).
                -- The owner reader explicitly proves BOTH raw units alive, so
                -- replacement cannot pass merely because the new unit is dead.
                a.deps.alive = function(unit) return rawequal(unit, old) or rawequal(unit, replacement) end
                a.deps.humans = function()
                    reads = reads + 1
                    if throwing then error(opaque, 0) end
                    return a.humans
                end
                a.native_results = pack(40, nil, token, nil)
                local packets, hooks = #net.history, a.hook_count()
                H.equal(a.owner:capture("arm"), true); H.equal(reads, 1, "arm uses one shared resolver")
                unchanged_capture_native(a, profile, token)
                H.equal(reads, 2, "one armed boundary performs one bounded resolver call")
                if fault == "replacement" then
                    local alias = { __eq = function() return true end }
                    setmetatable(old, alias); setmetatable(replacement, alias)
                    H.equal(old == replacement, true); H.equal(rawequal(old, replacement), false)
                    row.player_unit = replacement
                elseif fault == "foreign-peer" then row.peer_id = "foreign"
                elseif fault == "foreign-local" then roster[2].local_player = true
                elseif fault == "split" then roster[3] = { peer_id = a.id, local_player = true, player_unit = old }
                elseif fault == "malformed-row" then
                    a.humans = { setmetatable({}, { __index = function()
                        indexed = indexed + 1; error(opaque, 0)
                    end }) }
                elseif fault == "malformed-roster" then a.humans = false
                elseif fault == "throwing-roster" then throwing = true
                else
                    a.humans = { row, { peer_id = "other1" }, { peer_id = "other2" },
                        { peer_id = "other3" }, { peer_id = "other4" } }
                end
                H.equal(a.deps.alive(old), true); H.equal(a.deps.alive(replacement), true)
                unchanged_capture_native(a, profile, token)
                H.equal(reads, 3, "identity loss is checked at the next existing boundary")
                H.equal(stringified, 0); H.equal(indexed, 0, "capture identity fields must remain raw")
                local data = assert(a.owner:capture("dump"))
                H.equal(data.count, 1, "lost identity must freeze exactly the prior observation")
                capture_contains(data.header, "reason=owner-or-unit-lost")
                capture_contains(data.rows[1], "phase=damage action_context=none")
                H.equal(a.owner:capture("dump"), nil, "identity-loss evidence remains one-shot")
                -- Repairing the roster does not silently resume the old arm.
                throwing = false
                a.humans = { { peer_id = a.id, local_player = true, player_unit = old }, { peer_id = b.id } }
                unchanged_capture_native(a, profile, token)
                H.equal(reads, 3, "stopped capture neither retains a live observer nor polls the roster")
                H.equal(a.owner:capture("dump"), nil)
                local native_calls = a.native_calls
                a.native_error = opaque
                local ok, failure = pcall(a.damage, a, profile)
                a.native_error = nil
                H.equal(ok, false); H.equal(rawequal(failure, opaque), true)
                H.equal(a.native_calls, native_calls + 1); H.equal(reads, 3)
                H.equal(a.owner:capture("arm"), true); H.equal(reads, 4)
                unchanged_capture_native(a, profile, token)
                data = assert(a.owner:capture("dump")); H.equal(data.count, 1)
                capture_contains(data.header, "reason=dumped")
                H.equal(a.owner.committed, true); H.equal(a.owner.terminal, false)
                H.equal(a.hook_count(), hooks); H.equal(#net.history, packets)
                H.equal(stringified, 0)
            end
        end
    end)

    H.test("WT #942 actual owner revalidates replacement at start cleave and dump boundaries", function()
        for _, namespace in ipairs({ "weapon_tweaker", "weapon_tweaker_dev" }) do
            for _, boundary in ipairs({ "start", "cleave", "dump" }) do
                local net, a = captured_pair(namespace)
                local old, replacement, token, profile = a.unit, {}, {}, {}
                local row, reads = a.humans[1], 0
                a.deps.alive = function(unit) return rawequal(unit, old) or rawequal(unit, replacement) end
                a.deps.humans = function() reads = reads + 1; return a.humans end
                a.native_results = pack(40, nil, token, nil)
                local packets, data = #net.history, nil
                H.equal(a.owner:capture("arm"), true)
                if boundary ~= "cleave" then unchanged_capture_native(a, profile, token) end
                if boundary == "start" then
                    row.player_unit = replacement
                    local action = { kind = "shield_slam", damage_profile = "direct",
                        damage_profile_target = "target", damage_profile_aoe = "aoe" }
                    local actor = { owner_unit = old }
                    local out = pack(a.classes.slam.client_owner_start_action(actor, action, nil, token, nil))
                    H.equal(out.n, 7); H.equal(out[1], "direct"); H.equal(out[2], "target")
                    H.equal(out[3], "aoe"); H.equal(out[4], nil); H.equal(out[5], nil)
                    H.equal(rawequal(out[6], token), true); H.equal(out[7], nil)
                    H.equal(rawequal(actor.seen, action), true, "unindexed native action remains raw")
                elseif boundary == "cleave" then
                    local actual, calls = a.classes.utils.get_max_targets, 0
                    -- One-hop adversarial boundary, not a WT module substitute:
                    -- the actual installed helper hook and native run once.
                    a.classes.utils.get_max_targets = function(...)
                        calls = calls + 1; row.player_unit = replacement
                        return actual(...)
                    end
                    local out = pack(a.classes.sweep.client_owner_start_action({ owner_unit = old },
                        a.native.heavy_attack_left, token, nil))
                    a.classes.utils.get_max_targets = actual
                    H.equal(calls, 1); H.equal(out.n, 5); H.equal(out[1], 160)
                    H.equal(out[2], nil); H.equal(out[3], "sweep")
                    H.equal(rawequal(out[4], token), true); H.equal(out[5], nil)
                else
                    row.player_unit = replacement
                    data = assert(a.owner:capture("dump"))
                end
                H.equal(a.deps.alive(old), true); H.equal(a.deps.alive(replacement), true)
                H.equal(a.owner.runtime.context, nil)
                data = data or assert(a.owner:capture("dump"))
                H.equal(data.count, 1, "existing boundary preserves only the honest pre-loss row")
                capture_contains(data.header, "reason=owner-or-unit-lost")
                capture_contains(data.rows[1], boundary == "cleave" and "phase=start" or "phase=damage")
                H.equal(a.owner:capture("dump"), nil)
                local stopped_reads = reads
                row.player_unit = old
                unchanged_capture_native(a, profile, token)
                H.equal(reads, stopped_reads, "replacement stop cannot resume without an explicit new arm")
                H.equal(a.owner:capture("arm"), true)
                unchanged_capture_native(a, profile, token)
                data = assert(a.owner:capture("dump")); H.equal(data.count, 1)
                capture_contains(data.header, "reason=dumped")
                H.equal(#net.history, packets)
            end
        end
    end)

    H.test("WT #942 throwing weapon-registry reader is distinguished from template replacement",function()
        local _,a=pair();a.deps.get_weapons=function() error("unavailable") end
        a.owner:reconcile();H.equal(a.owner.committed,false)
        H.equal(a.owner.error,"Weapons reader failed");H.equal(a:damage(direct(a)),10)
    end)
end
