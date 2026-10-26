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
    H.test("WT #942 throwing weapon-registry reader is distinguished from template replacement",function()
        local _,a=pair();a.deps.get_weapons=function() error("unavailable") end
        a.owner:reconcile();H.equal(a.owner.committed,false)
        H.equal(a.owner.error,"Weapons reader failed");H.equal(a:damage(direct(a)),10)
    end)
end
