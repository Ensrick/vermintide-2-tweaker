return function(H, repo_root, json)
    json = json or assert(loadfile(repo_root .. "/qa/lua/fixtures/restricted_json.lua"))()
    assert(type(json)=="table" and type(json.encode)=="function" and type(json.decode)=="function", "#942 deterministic JSON fixture missing")
    local external=repo_root.."/weapon_tweaker/scripts/mods/weapon_tweaker"
    local P=dofile(external.."/_wt_fire_sword_heat_config_proof.lua")
    local function clone(value)
        if type(value)~="table" then return value end
        local out={};for k,v in pairs(value) do out[k]=clone(v) end;return out
    end
    local function count(t) local n=0;for _ in pairs(t) do n=n+1 end;return n end
    local function config(damage)
        return {enabled=true,armor=true,cleave=.02,damage=damage or .01,threshold=25}
    end
    local function network()
        local net={now=0,nodes={},queue={},history={}}
        function net:add(id,epoch,cfg)
            local n={id=id,config=cfg or config(),peers={},known=true,changes={}}
            self.nodes[id]=n
            n.protocol=P.new({epoch=epoch or id.."-session",
                read_config=function() if n.config_error then error("config") end;return n.config end,
                read_peers=function() if n.roster_error then error("roster") end;return n.peers,n.known end,
                changed=function(value,api)
                    H.equal(api:applied_state(),value,"state must precede callbacks")
                    n.changes[#n.changes+1]=value
                    if n.callback then n.callback(value,api) end
                    if n.callback_error then error("callback") end
                end,
                send=function(peer,packet)
                    if n.send_error then error("send") end
                    local encoded=json.encode(packet)
                    H.truthy(#encoded<=P.MAX_JSON,"actual encoded VMF-size floor")
                    local message={from=id,to=peer,packet=json.decode(encoded),encoded=encoded}
                    net.history[#net.history+1]=clone(message)
                    if n.synchronous then
                        if net.nodes[peer] then net.nodes[peer].protocol:receive(id,message.packet,net.now) end
                    else net.queue[#net.queue+1]=message end
                end})
            return n
        end
        function net:connect(a,b)
            self.nodes[a].peers[b]=true;self.nodes[b].peers[a]=true
        end
        function net:deliver(index)
            local message=table.remove(self.queue,index or 1)
            if not message then return end
            local n=self.nodes[message.to]
            if n then n.protocol:receive(message.from,clone(message.packet),self.now) end
            return message
        end
        function net:pump()
            local total=0
            while #self.queue>0 do total=total+1;assert(total<1000,"protocol feedback loop");self:deliver() end
            return total
        end
        function net:tick(dt)
            self.now=self.now+(dt or 0)
            for _,n in pairs(self.nodes) do n.protocol:tick(self.now) end
        end
        function net:allows(id) local n=self.nodes[id];return n.protocol:allows(n.config,self.now) end
        function net:replay(message)
            local n=self.nodes[message.to]
            return n and n.protocol:receive(message.from,clone(message.packet),self.now)
        end
        return net
    end
    local function pair(a_config,b_config)
        local n=network();local a=n:add("host",nil,a_config);local b=n:add("client",nil,b_config)
        n:connect("host","client");return n,a,b
    end
    local function handshake(n,a)
        a.protocol:tick(n.now);n:pump()
    end
    local function both(n)
        H.equal(n:allows("host"),true);H.equal(n:allows("client"),true)
    end

    H.test("#942 config exact finite canonicalization and binary round trip",function()
        for _,value in ipairs({0,.01,.02,.1,25,100,math.ldexp(1,-1074),1/3}) do
            local token=P.number_token(value);H.truthy(token)
            H.equal(P.token_number(token),value)
        end
        H.equal(P.number_token(-0),"0")
        for _,value in ipairs({-1,math.huge,-math.huge,0/0,".01",false}) do H.equal(P.number_token(value),nil) end
        local t,key=P.canonicalize(config());H.equal(#t,5);H.truthy(key)
        local changed=config();changed.damage=changed.damage+math.ldexp(1,-58)
        H.truthy(select(2,P.canonicalize(changed))~=key,"one representable difference cannot hash-collide")
        for _,bad in ipairs({"0e0","04503599627370496e-52","4503599627370496e+0",
                "4503599627370496e-9999","9007199254740992e1","nan","inf",string.rep("1",500)}) do
            H.equal(P.token_number(bad),nil)
        end
        for _,field in ipairs({"enabled","armor","cleave","damage","threshold"}) do
            local c=config();c[field]=nil;H.equal(P.canonicalize(c),nil)
        end
        local c=config();c.extra=true;H.equal(P.canonicalize(c),nil)
        c=config();c.damage=.10001;H.equal(P.canonicalize(c),nil)
        c=config();c.threshold=0/0;H.equal(P.canonicalize(c),nil)
    end)

    H.test("#942 canonical tokens and actual JSON are numeric-locale independent",function()
        local saved=os.setlocale(nil,"numeric")
        local ok,error_value=pcall(function()
            assert(os.setlocale("C","numeric"));local _,expected=P.canonicalize(config())
            local tested=0
            for _,locale in ipairs({"German_Germany.1252","French_France.1252"}) do
                if os.setlocale(locale,"numeric") then
                    tested=tested+1
                    H.equal(select(2,P.canonicalize(config())),expected)
                    local n,a=pair();handshake(n,a);both(n)
                end
            end
            H.truthy(tested>0,"non-C locale proof must execute, not silently pass untested")
        end)
        os.setlocale(saved,"numeric");if not ok then error(error_value) end
    end)

    H.test("#942 actual three-message exchange; query alone never authorizes",function()
        local n,a,b=pair()
        H.equal(n:allows("host"),false);H.equal(n:allows("client"),false)
        a.protocol:tick(0);H.equal(#n.queue,1);H.equal(n.queue[1].packet[2],"q")
        n:deliver();H.equal(n:allows("client"),false)
        H.equal(n.queue[1].packet[2],"r")
        n:deliver();H.equal(n:allows("host"),true);H.equal(n:allows("client"),false)
        H.equal(n.queue[1].packet[2],"a")
        n:deliver();both(n);H.equal(#n.history,3)
        -- Directional proof is not falsely described as instantaneous common
        -- knowledge. Before the final ACK, recipient-side effects stay inert.
        H.equal(#a.changes,1);H.equal(#b.changes,1)
    end)

    H.test("#942 crossed queries establish proof with bounded real messages",function()
        local n=pair();n:tick(0);n:pump();both(n)
        H.truthy(#n.history<=6);H.equal(#n.queue,0)
    end)

    H.test("#942 mismatched and one-bit-different settings cannot authorize",function()
        for _,field in ipairs({"enabled","armor","cleave","damage","threshold"}) do
            local ca,cb=config(),config()
            if type(cb[field])=="boolean" then cb[field]=not cb[field]
            else
                local _,exponent=math.frexp(cb[field])
                cb[field]=cb[field]+math.ldexp(1,exponent-53)
                H.truthy(cb[field]~=ca[field],"fixture must differ by one actual binary64 ULP")
            end
            local n,a=pair(ca,cb);handshake(n,a)
            H.equal(n:allows("host"),false);H.equal(n:allows("client"),false)
        end
    end)

    H.test("#942 either-side config change invalidates then fresh matching exchange recovers",function()
        for _,who in ipairs({"host","client"}) do
            local n,a=pair();handshake(n,a);both(n)
            local actor=n.nodes[who];n.now=.1;actor.config.damage=.015
            actor.protocol:settings_changed(n.now)
            H.equal(n:allows(who),false,"changing owner must synchronously become inert")
            n:pump();H.equal(n:allows("host"),false);H.equal(n:allows("client"),false)
            local other=n.nodes[who=="host" and "client" or "host"]
            n.now=.2;other.config.damage=.015;other.protocol:settings_changed(n.now)
            n:pump();both(n)
        end
    end)

    H.test("#942 changed-then-restored config rejects all old query/reply/ack evidence",function()
        local n,a=pair();handshake(n,a);local first=clone(n.history)
        n.now=.1;a.config.damage=.02;a.protocol:settings_changed(n.now);n:pump()
        local middle=clone(n.history)
        n.now=.2;a.config.damage=.01;a.protocol:settings_changed(n.now)
        n.queue={}
        for _,list in ipairs({first,middle}) do for _,message in ipairs(list) do n:replay(message) end end
        H.equal(n:allows("host"),false);H.equal(n:allows("client"),false)
        for step=1,3 do n:tick(1);n:pump() end
        both(n)
        local generation=a.protocol:inspect().generation
        H.truthy(generation>=3)
        for _,message in ipairs(first) do n:replay(message) end
        both(n)
    end)

    H.test("#942 simultaneous matching changes recover; differing changes stay inert",function()
        for _,same in ipairs({true,false}) do
            local n,a,b=pair();handshake(n,a);n.now=.1
            a.config.damage=.015;b.config.damage=same and .015 or .02
            a.protocol:settings_changed(n.now);b.protocol:settings_changed(n.now);n:pump()
            H.equal(n:allows("host"),same);H.equal(n:allows("client"),same)
        end
    end)

    H.test("#942 replayed replies require current challenge and exact addressing",function()
        local n,a=pair();a.protocol:tick(0);n:deliver();local old=clone(n.queue[1]);n.queue={}
        n.now=.1;a.config.armor=false;a.protocol:settings_changed(n.now)
        H.equal(n:replay(old),false);H.equal(n:allows("host"),false)
        local wrong=clone(old);wrong.packet[5]="other-session"
        H.equal(n:replay(wrong),false)
        wrong=clone(old);wrong.packet[8]="c99999";H.equal(n:replay(wrong),false)
        H.equal(n:allows("host"),false)
    end)

    H.test("#942 a fresh addressed reply still needs the exact outstanding nonce",function()
        local n,a=pair();a.protocol:tick(0);n:deliver()
        local reply=clone(n.queue[1]);n.queue={}
        local tampered=clone(reply);tampered.packet[8]="c99999"
        H.equal(n:replay(tampered),false);H.equal(n:allows("host"),false)
        H.equal(n:replay(reply),true);n:pump();both(n)
    end)

    H.test("#942 duplicate packets do not renew proof or create ACK feedback",function()
        local n,a,b=pair();handshake(n,a);local history=clone(n.history)
        local expiry=a.protocol:inspect().peers.client.expires
        n.now=.5
        for _=1,100 do for _,message in ipairs(history) do n:replay(message) end end
        H.equal(a.protocol:inspect().peers.client.expires,expiry)
        H.equal(#n.queue,0);H.equal(#n.history,3);both(n)
        n.now=2
        for _,message in ipairs(history) do n:replay(message) end
        n:pump();H.truthy(#n.history<=4)
        H.equal(b.protocol:inspect().peers.host.expires,30)
    end)

    H.test("#942 dropped query, response and final ACK heal with bounded retries",function()
        for _,kind in ipairs({"q","r","a"}) do
            local n,a=pair();a.protocol:tick(0)
            while #n.queue>0 and n.queue[1].packet[2]~=kind do n:deliver() end
            H.equal(n.queue[1].packet[2],kind);table.remove(n.queue,1)
            for _=1,4 do n:tick(1);n:pump() end
            both(n);H.truthy(#n.history<=20)
        end
    end)

    H.test("#942 absent peer cannot authorize; retry and traffic rates are bounded",function()
        local n,a=pair();n.nodes.client=nil
        for _=1,100 do n:tick(.5);n:pump() end
        H.equal(n:allows("host"),false)
        H.truthy(#n.history<=P.BURST+P.SEND_RATE*n.now)
        local detail=a.protocol:inspect().peers.client
        H.truthy(not detail.query_attempts or detail.query_attempts<=P.MAX_ATTEMPTS)
        H.truthy(detail.tokens>=0 and detail.tokens<=P.BURST)
    end)

    H.test("#942 proof expires without fresh response and no replay extends it",function()
        local n,a=pair();handshake(n,a);local old=clone(n.history)
        n.now=31
        for _,message in ipairs(old) do n:replay(message) end
        H.equal(n:allows("host"),false);H.equal(n:allows("client"),false)
        n:tick(0);n:pump();both(n)
    end)

    H.test("#942 actual disconnect/rejoin same peer ID requires a new session",function()
        local n,a,b=pair();handshake(n,a);local old=clone(n.history)
        a.protocol:disconnect("client",0)
        n:add("client","client-new-session");n:connect("host","client")
        for _,message in ipairs(old) do n:replay(message) end
        H.equal(n:allows("host"),false)
        n:tick(1);n:pump();both(n)
        H.equal(a.protocol:inspect().peers.client.epoch,"client-new-session")
        for _,message in ipairs(old) do n:replay(message) end
        both(n)
    end)

    H.test("#942 unproven stale session query never retires the current real session",function()
        local n,a,b=pair();handshake(n,a)
        local stale=clone(n.history[1]);stale.from="client";stale.to="host"
        stale.packet[3]="unseen-old-client";stale.packet[7]="c999"
        n:replay(stale);H.equal(n:allows("host"),false)
        n:tick(1);n:pump();both(n)
        H.equal(a.protocol:inspect().peers.client.epoch,"client-session")
    end)

    H.test("#942 temporary and long transition absences recover without reconnect",function()
        for _,duration in ipairs({5,11}) do
            local n,a,b=pair();handshake(n,a)
            a.peers={};a.protocol:tick(1);n.now=duration+1;a.protocol:tick(n.now)
            a.peers.client=true;n:tick(1);n:pump()
            for _=1,2 do n:tick(1);n:pump() end
            both(n);H.equal(a.protocol:inspect().peers.client.epoch,"client-session")
        end
    end)

    H.test("#942 reader errors, unknown roster and clock rollback fail closed then recover fresh",function()
        for _,kind in ipairs({"config_error","roster_error","unknown","clock"}) do
            local n,a=pair();handshake(n,a);local old=clone(n.history)
            n.now=1
            if kind=="unknown" then a.known=false elseif kind=="clock" then a.protocol:tick(2);n.now=1
            else a[kind]=true end
            H.equal(n:allows("host"),false)
            a.config_error,a.roster_error=false,false;a.known=true;n.now=3
            for _,message in ipairs(old) do n:replay(message) end
            H.equal(n:allows("host"),false)
            a.protocol:settings_changed(3);n:pump()
            for _=1,3 do n:tick(1);n:pump() end
            both(n)
        end
    end)

    H.test("#942 send errors and reentrant delivery cannot grant false proof",function()
        local n,a,b=pair();a.send_error=true;a.protocol:tick(0)
        H.equal(n:allows("host"),false)
        a.send_error=false;a.synchronous=true;b.synchronous=true
        n:tick(1);H.equal(n:allows("host"),false);H.equal(n:allows("client"),false)
        a.synchronous,b.synchronous=false,false
        for _=1,5 do n:tick(1);n:pump() end
        both(n)
    end)

    H.test("#942 callback error is terminal/inert and callbacks see committed state",function()
        local n,a=pair();a.callback_error=true;handshake(n,a)
        H.equal(n:allows("host"),false);H.equal(a.protocol:inspect().fatal,true)
        a.callback_error=false
        for _=1,3 do n:tick(1);n:pump() end
        H.equal(n:allows("host"),false)
    end)

    H.test("#942 reentrant callback delivery is rejected without recursion or stale state",function()
        local n,a=pair();local calls=0
        a.callback=function(value,api)
            calls=calls+1;H.equal(value,api:applied_state())
            H.equal(api:tick(n.now),false,"event processing cannot reenter its own callback")
            H.equal(api:receive("client",{},n.now),false)
            H.equal(api:allows(a.config,n.now),value)
        end
        handshake(n,a);both(n);H.equal(calls,1)
    end)

    H.test("#942 known solo is distinct from unreadable or pre-roster-pending topology",function()
        local n=network();local a=n:add("host")
        H.equal(n:allows("host"),true)
        a.known=false;H.equal(n:allows("host"),false)
        a.known=true;a.peers.client=true -- injected roster includes the pre-roster join fence
        H.equal(n:allows("host"),false)
        a.peers={};a.protocol:tick(0);a.protocol:tick(11);n.now=11
        H.equal(n:allows("host"),true)
    end)

    H.test("#942 malformed, foreign and oversized packets cannot authorize or grow state",function()
        local n,a,b=pair();a.protocol:tick(0);local valid=clone(n.queue[1].packet);n.queue={}
        for _,mutation in ipairs({
            function(p) p[1]=999 end,function(p) p[2]="x" end,function(p) p[3]=string.rep("e",1000) end,
            function(p) p[4]=0/0 end,function(p) p[7]="c01" end,function(p) p[9]=true end,
            function(p) p[11]="0e0" end,function(p) p[14]="extra" end,function(p) p[8]=nil end,
        }) do
            local p=clone(valid);mutation(p);H.equal(P.validate_packet(p),nil)
            H.equal(b.protocol:receive("host",p,0),false);H.equal(n:allows("client"),false)
        end
        for i=1,100 do b.protocol:receive("foreign"..i,valid,0) end
        H.equal(count(b.protocol:inspect().peers),1);H.equal(#n.history,1)
        local metatable=clone(valid);setmetatable(metatable,{});H.equal(P.validate_packet(metatable),nil)
    end)

    H.test("#942 explicit peer and retired-state caps remain bounded through churn",function()
        local n,a=pair();handshake(n,a)
        for i=1,40 do
            local peer="peer"..i;local b=n:add(peer,peer.."-epoch");a.peers={ [peer]=true };b.peers.host=true
            n.nodes.client=nil;n.now=n.now+11;a.protocol:tick(n.now);b.protocol:tick(n.now);n:pump()
            H.equal(a.protocol:inspect().peers[peer].epoch,peer.."-epoch","churn must actually authenticate before retiring")
            a.protocol:disconnect(peer,n.now);a.peers={};n.nodes[peer]=nil
            a.protocol:tick(n.now+11);n.now=n.now+11
        end
        local snap=a.protocol:inspect();H.truthy(snap.retired_peers<=P.MAX_RETIRED_PEERS)
        for _,epochs in pairs(snap.retired) do H.truthy(epochs<=P.MAX_RETIRED_EPOCHS) end
        a.peers={};for i=1,33 do a.peers["p"..i]=true end
        H.equal(a.protocol:allows(a.config,n.now),false)
        H.truthy(count(a.protocol:inspect().peers)<=P.MAX_PEERS)
    end)

    H.test("#942 maximum actual JSON packet stays below VMF payload limit",function()
        local tuple=assert(P.canonicalize({enabled=true,armor=true,cleave=.1,damage=.1,threshold=100}))
        local packet={P.SCHEMA,"r",string.rep("e",P.MAX_EPOCH),P.MAX_GENERATION,
            string.rep("f",P.MAX_EPOCH),P.MAX_GENERATION,"c1000000000","c1000000000",
            tuple[1],tuple[2],tuple[3],tuple[4],tuple[5]}
        local _,_,length=P.validate_packet(packet);H.truthy(length)
        H.equal(#json.encode(packet),length);H.truthy(length<P.MAX_JSON)
    end)

    H.test("#942 retained plus new roster cannot exceed the hard peer cap",function()
        local n=network();local a=n:add("host")
        for i=1,32 do a.peers["old"..i]=true end
        a.protocol:tick(0);H.equal(count(a.protocol:inspect().peers),32)
        a.peers={};for i=1,32 do a.peers["new"..i]=true end
        H.equal(a.protocol:allows(a.config,1),false)
        H.equal(count(a.protocol:inspect().peers),32)
        H.equal(a.protocol:allows(a.config,12),false)
        local peers=a.protocol:inspect().peers
        H.equal(count(peers),32);for id in pairs(peers) do H.truthy(id:find("new",1,true)==1) end
    end)

    H.test("#942 repeated same-ID sessions cap retired epochs and fresh proof recovers",function()
        local n,a=pair();handshake(n,a)
        for i=1,12 do
            n:add("client","client-epoch"..i);n:connect("host","client")
            n:tick(1);n:pump();both(n)
        end
        H.equal(a.protocol:inspect().retired.client,P.MAX_RETIRED_EPOCHS)
        local q=clone(n.history[1]);q.from="client";q.to="host"
        for i=1,100 do q.packet[3]="candidate"..i;q.packet[7]="c"..i;n:replay(q) end
        H.truthy(a.protocol:inspect().peers.client.queries<=P.MAX_QUERY_EPOCHS)
        n:tick(1);n:pump();both(n)
    end)

    H.test("#942 exhausted counters/generations never wrap or reuse proof",function()
        for _,field in ipairs({"initial_counter","initial_generation"}) do
            local deps={epoch="exhausted-session",read_config=config,
                read_peers=function() return {client=true},true end,
                send=function() error("exhausted state must not send") end,changed=function() end}
            deps[field]=field=="initial_counter" and P.MAX_CHALLENGE or P.MAX_GENERATION
            local protocol=P.new(deps);protocol:tick(0)
            H.equal(protocol:allows(config(),0),false);H.equal(protocol:inspect().fatal,true)
            H.truthy(protocol:inspect().counter<=P.MAX_CHALLENGE)
            H.truthy(protocol:inspect().generation<=P.MAX_GENERATION)
        end
    end)

    H.test("#942 injected real config protocol gates the actual application owner",function()
        local base=external:gsub("/config%-proof$","")
        local Policy=dofile(base.."/_wt_fire_sword_heat.lua")
        local Runtime=dofile(base.."/_wt_fire_sword_heat_runtime.lua")
        local n,a,b=pair()
        local applications={}
        for _,node in ipairs({a,b}) do
            local action={kind="sweep",damage_profile="light"}
            local profiles={light={charge_value="light_attack",armor_modifier={attack={1,0,2}},
                cleave_distribution={attack=.35,impact=.2},default_target={}}}
            local unit={heat=30}
            local mod={get=function(_,id)
                if id==Policy.ENABLED then return node.config.enabled end
                if id==Policy.ARMOR then return node.config.armor end
                if id==Policy.CLEAVE then return node.config.cleave*100 end
                if id==Policy.DAMAGE then return node.config.damage*100 end
                if id==Policy.THRESHOLD then return node.config.threshold end
            end}
            local runtime=Runtime.new(mod,{policy=Policy,
                weapons={[Policy.TEMPLATE]={actions={one={light=action}}}},profiles=profiles,
                clone=clone,register=function() end,fallbacks={},armor_reference={attack={1,.3,2}},
                catalog_allows=function() return true end, -- existing #431 is independently required
                configuration_agrees=function(c) return node.protocol:allows(c,n.now) end,
                alive=function(u) return u~=nil end,
                extension=function(u) return {current_overcharge_status=function() return u.heat,25,40 end} end})
            applications[node.id]={runtime=runtime,action=action,profiles=profiles,unit=unit}
            node.callback=function() runtime:apply(false) end
            runtime:apply(false);H.equal(action.damage_profile,"light")
        end
        handshake(n,a);both(n)
        local owner,authority=applications.client,applications.host
        local key=owner.action.damage_profile;H.equal(key,"wt942_direct_light")
        local function damage(profile)
            return authority.runtime:calculate_damage(function() return 10,nil,"tail" end,
                {},{},owner.unit,"torso",600,"curve",1,false,profile)
        end
        H.equal(damage(authority.profiles[key]),13)
        n.now=.1;b.config.damage=.015;b.protocol:settings_changed(n.now)
        H.equal(owner.action.damage_profile,"light")
        H.equal(damage(authority.profiles.light),10,"changing owner sends native donor while proof is pending")
        n:pump();H.equal(damage(authority.profiles.wt942_armored_light),10,"latched armor fails closed")
        n.now=.2;a.config.damage=.015;a.protocol:settings_changed(n.now);n:pump();both(n)
        H.equal(damage(authority.profiles.wt942_direct_light),14.5)
    end)

    H.test("#942 deterministic reordered/replayed network histories preserve safety and recover",function()
        for initial=1,8 do
            local seed=initial
            local function random(maximum) seed=(seed*16807)%2147483647;return seed%maximum+1 end
            local n,a=pair();local session=1
            for event=1,500 do
                local choice=random(7)
                if choice==1 then n:tick(.1)
                elseif choice==2 and #n.queue>0 then n:deliver(random(#n.queue))
                elseif choice==3 and #n.queue>0 then table.remove(n.queue,random(#n.queue))
                elseif choice==4 and #n.history>0 then n:replay(n.history[random(#n.history)])
                elseif choice==5 or choice==6 then
                    local node=n.nodes[choice==5 and "host" or "client"]
                    node.config.damage=({.01,.015,.02})[random(3)]
                    node.config.armor=random(2)==1
                    node.protocol:settings_changed(n.now)
                else
                    session=session+1;a.protocol:disconnect("client",n.now)
                    n:add("client","client-random-"..session);n:connect("host","client")
                end
                local aa,bb=n:allows("host"),n:allows("client")
                if aa and bb then
                    H.equal(select(2,P.canonicalize(n.nodes.host.config)),
                        select(2,P.canonicalize(n.nodes.client.config)),
                        "both directions must never authorize different current tuples")
                end
                for _,node in pairs(n.nodes) do
                    local snap=node.protocol:inspect()
                    H.truthy(count(snap.peers)<=P.MAX_PEERS)
                    H.truthy(snap.retired_peers<=P.MAX_RETIRED_PEERS)
                end
            end
            n.queue={}
            for _,node in pairs(n.nodes) do node.config=config();node.protocol:settings_changed(n.now) end
            for _=1,25 do n:tick(1);n:pump() end
            both(n)
        end
    end)
end
