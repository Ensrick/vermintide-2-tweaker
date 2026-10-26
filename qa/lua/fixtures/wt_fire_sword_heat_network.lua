-- Offline-only synthetic network: private factory environments are permitted
-- here, never in deployed Lua. Actual catalog/config protocols and owners.
local M = {}
local function pack(...) return {n=select("#",...),...} end
local function clone(v)
    if type(v) ~= "table" then return v end
    local out = {}; for k,x in pairs(v) do out[k]=clone(x) end; return out
end
function M.network(load, codec)
    local net = { nodes = {}, queue = {}, history = {}, now = 0 }
    local Heat, App = load("_wt_fire_sword_heat"), load("_wt_fire_sword_heat_runtime")
    local Proof, Transport = load("_wt_fire_sword_heat_config_proof"), load("_wt_fire_sword_heat_transport")
    local Heavy, Owner = load("_wt_fire_sword"), load("_wt_fire_sword_owner")
    local Contract, Lookup = load("_wt431_wire_contract"), load("_lib_network_lookup")
    function net:add(id, options)
        options = options or {}
        local n = { id=id, humans={{peer_id=id}}, heat=30, maximum=40, enabled=true,
            settings={ [Heat.ENABLED]=true, [Heat.ARMOR]=true }, packets=0, calls={} }
        self.nodes[id]=n
        local function send(channel, target, ...)
            local args={...}
            if codec then args=codec.decode(codec.encode(args)) end
            local function queue(to)
                local row={from=id,to=to,channel=channel,args=clone(args)}
                net.queue[#net.queue+1]=row;net.history[#net.history+1]=clone(row)
            end
            if target=="others" then for to in pairs(net.nodes) do if to~=id then queue(to) end end
            else queue(target) end
        end
        local profiles={}
        for _,name in ipairs({"direct","target"}) do
            profiles[name]={charge_value="light_attack",armor_modifier={attack={1,0,1},impact={1,.2,1}},
                cleave_distribution={attack=1,impact=1},default_target={}}
        end
        profiles.aoe={no_damage=true,charge_value="heavy_attack",default_target={}}
        local weapons={[Heat.TEMPLATE]={actions={action_one={
            default={allowed_chain_actions={}},
            heavy_attack_left={kind="sweep",damage_profile="direct"},
            heavy_attack_spell={kind="shield_slam",damage_profile="direct",damage_profile_target="target",
                damage_profile_aoe="aoe",anim_time_scale=1,allowed_chain_actions={}},
        }}}}
        local lookup={};for _,key in ipairs({"direct","target","aoe"}) do assert(Lookup.register(lookup,key)) end
        n.profiles,n.weapons,n.lookup,n.unit=profiles,weapons,lookup,{}
        local classes={ utils={get_max_targets=function(_,power) return power,nil,"tail" end},
            damage={calculate_damage=function(...) n.native_damage={n=select("#",...),...};return 10,nil,"tail",nil end},
            network={hot_join_sync=function(_,peer,...)
                if n.on_join then n.on_join(peer) end
                return peer,nil,...
            end,remove_peer=function() end},sweep={},slam={} }
        classes.sweep.client_owner_start_action=function(self_action,action,...)
            self_action.seen=action
            return classes.utils.get_max_targets(profiles[action.damage_profile],100),nil,"sweep",...
        end
        classes.slam.client_owner_start_action=function(self_action,action,...)
            self_action.seen=action
            return action.damage_profile,action.damage_profile_target,action.damage_profile_aoe,nil,...
        end
        n.classes=classes
        local receivers={};n.receivers=receivers
        n.checks={}
        local mod={_wt={rt_register=function(name,callback) assert(not n.checks[name]);n.checks[name]=callback end},
            get=function(_,key) if n.read_error then error(n.read_error) end;return n.settings[key] end,
            get_name=function() return "wt" end, debug=function() end, echo=function() end,
            localize=function(_,key) return key end, network_send=function(_,...) return send(...) end,
            network_register=function(_,channel,callback) receivers[channel]=callback end,
            update=function(...) n.calls.update={n=select("#",...),...};return nil,"update",nil end,
            on_game_state_changed=function(...) n.calls.state={n=select("#",...),...};return nil,"state",nil end,
            on_disabled=function(...) return nil,"disabled",nil,... end,
            on_enabled=function(...) return nil,"enabled",nil,... end }
        n.mod=mod
        local hook_count=0
        local function hook(class,method,callback)
            assert(type(class)=="table" and type(class[method])=="function")
            hook_count=hook_count+1
            local native=class[method]
            class[method]=function(...) return callback(native,...) end
            if options.hook_throw==hook_count then error("retained hook failure") end
        end
        local deps={load=load,heat=Heat,application=App,protocol=Proof,transport=Transport,
            get_weapons=function() return n.weapons end,profiles=profiles,fallbacks={},
            armor_reference={attack={1,.3,1}},clone=clone,
            register=function(key) assert(Lookup.register(lookup,key)) end,
            alive=function(unit) return unit==n.unit and not n.dead end,
            extension=function() if n.extension_error then error("extension") end
                return {current_overcharge_status=function() return n.heat,25,n.maximum end} end,
            humans=function() if n.roster_error then error("roster") end;return n.humans end,
            local_peer=function() return id end,
            guid=function() return options.guid or string.format("%032x",#net.history+#id+(id=="host" and 1 or 100)) end,
            enabled=function() return n.enabled end,breed=function() return {} end,
            multiplier=function() return "headshot" end,log=function() end,classes=classes,hook=hook,
            register_receiver=function(channel,callback)
                receivers[channel]=callback
                if options.register_throw then error("retained receiver failure") end
            end,send=send}
        if options.change_deps then options.change_deps(deps,n) end
        if options.mod_setup then options.mod_setup(mod,n) end
        n.deps=deps
        local balance={scale_executioner_headshot_damage=function(damage) return damage end}
        n.owner=options.install and options.install(mod,Heavy,balance,deps,n) or Owner.install(mod,Heavy,balance,deps)
        n.adapter_update=mod.update
        n.hook_count=function() return hook_count end
        n.native=weapons[Heat.TEMPLATE].actions.action_one
        function n:damage(profile)
            return classes.damage.calculate_damage("output",self.unit,self.unit,"head",600,nil,1,false,profile,nil,"extra",nil)
        end
        if options.prepare_only then return n end
        -- Actual existing exact-catalog transport and parity factory, not a
        -- synthetic authorization Boolean. Only the fresh factory environment
        -- points at this fixture's humans/peer, never a live global mutation.
        local factory=load("_lib_peer_parity")
        local environment=setmetatable({Managers={player={human_players=function() return n.humans end}},
            Network={peer_id=function() return id end}},{__index=_G})
        setfenv(factory,environment)
        local identity=assert(Contract.build_wire_identity(deps.fallbacks,lookup,profiles))
        n.catalog_identity=identity
        local snapshot=assert(Contract.capture_catalog(deps.fallbacks,lookup,profiles))
        local proxy=assert(Contract.wrap_parity_transport(mod,identity,{schema=2,session_epoch="catalog-"..id}))
        local parity=assert(factory(proxy,{channel="wt_damage_profiles_exact_v2",schema=2}))
        proxy:_bind_parity_instance(parity);assert(parity:install())
        mod._wt_peer_parity=parity
        mod._wt431_profiles_allowed=function()
            return parity:is_installed() and parity:applied_state()=="enabled"
                and Contract.catalog_intact(snapshot,deps.fallbacks,lookup,profiles)==true
        end
        hook(classes.network,"remove_peer",function(func,manager,peer,...)
            local values=pack(func(manager,peer,...))
            parity:forget_peer(peer);n.owner:disconnect(peer)
            return unpack(values,1,values.n)
        end)
        mod._wt431_disconnect_epoch_guard=true
        parity:register_gated_feature("fixture942",{on_enable=function() n.owner:reconcile() end,
            on_disable=function() n.owner:reconcile() end})
        if n.owner.finish_install then n.owner:finish_install() end
        return n
    end
    function net:connect(a,b)
        self.nodes[a].humans={{peer_id=a},{peer_id=b}}
        self.nodes[b].humans={{peer_id=a},{peer_id=b}}
        assert(self.nodes[a].catalog_identity==self.nodes[b].catalog_identity,"fixture catalogs differ")
        -- Deliver the existing catalog install announcement before its next
        -- periodic query replaces the outstanding nonce. #942's own packets
        -- remain available for separate reorder/loss adversarial tests.
        self:pump()
    end
    function net:pump()
        local count=0
        while #self.queue>0 do
            count=count+1;assert(count<500,"unbounded fixture traffic: "
                ..tostring(net.history[#net.history].channel).." from "..tostring(net.history[#net.history].from)
                .." identity="..tostring(net.history[#net.history].args[3]))
            local message=table.remove(self.queue,1)
            local node=self.nodes[message.to]
            local receiver=node and node.receivers[message.channel]
            if receiver and (not self.intercept or self.intercept(message) ~= false) then
                receiver(message.from,unpack(message.args,1,#message.args))
            end
        end
    end
    function net:step(dt)
        self.now=self.now+dt
        for _,node in pairs(self.nodes) do node.mod.update(dt) end
        self:pump()
    end
    function net:settle() for _=1,8 do self:step(.5) end end
    return net
end
function M.run(load)
    local net=M.network(load)
    local host,client=net:add("host"),net:add("client")
    net:connect("host","client");net:settle()
    assert(host.owner.committed and client.owner.committed,"#942 adapter not committed")
    for _,node in ipairs({host,client}) do
        local key=node.native.heavy_attack_left.damage_profile
        assert(key=="wt942_direct_direct","#942 installed profile projection missing")
        assert(node:damage(node.profiles[key])==13,"#942 installed damage result wrong")
        local action={owner_unit=node.unit}
        local cleave=node.classes.sweep.client_owner_start_action(action,node.native.heavy_attack_left)
        assert(cleave==160,"#942 installed cleave result wrong")
    end
    client.settings.wt_fire_sword_heat_damage_percent=2
    client.owner:settings_changed("wt_fire_sword_heat_damage_percent")
    net:pump();net:settle()
    assert(host:damage(host.profiles.wt942_direct_direct)==10
        and client:damage(client.profiles.wt942_direct_direct)==10,"#942 mismatch stayed active")
end
return M
