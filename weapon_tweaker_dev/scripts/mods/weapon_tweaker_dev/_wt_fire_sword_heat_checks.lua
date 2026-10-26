-- Read-only installed-owner checks and private pure-protocol proof.
-- Full synthetic engine/catalog fixtures live only in qa/lua/fixtures.
local M = {}

local function private_protocol(load)
    local Heat, Proof = load("_wt_fire_sword_heat"), load("_wt_fire_sword_heat_config_proof")
    local queue, peers = {}, {}
    local function add(id, other)
        local config = {enabled=true,armor=true,cleave=.02,damage=.01,threshold=25}
        local protocol = Proof.new({
            epoch="check942-"..id,
            read_config=function() return config end,
            read_peers=function() return {[other]=true},true end,
            send=function(to, packet)
                assert(Proof.validate_packet(packet), "#942 private packet invalid")
                queue[#queue+1]={from=id,to=to,packet=packet}
            end,
            changed=function() end,
        })
        peers[id]={protocol=protocol,config=config}
        return peers[id]
    end
    local a,b=add("host","client"),add("client","host")
    local function pump(now)
        local count=0
        while #queue>0 do
            count=count+1;assert(count<100,"#942 private proof traffic unbounded")
            local packet=table.remove(queue,1)
            peers[packet.to].protocol:receive(packet.from,packet.packet,now)
        end
    end
    a.protocol:tick(0);b.protocol:tick(0);pump(0)
    assert(a.protocol:allows(a.config,0) and b.protocol:allows(b.config,0),
        "#942 private equal configuration failed")
    b.config.damage=.02;b.protocol:settings_changed(1);pump(1)
    assert(not a.protocol:allows(a.config,1) and not b.protocol:allows(b.config,1),
        "#942 private mismatch stayed active")
    local unit={}
    assert(Heat.heat(unit,function()
        return {current_overcharge_status=function() return 30,25,40 end}
    end,function(value) return value==unit end)==30,"#942 private heat reader wrong")
    assert(Heat.heat(unit,function() error("private unreadable extension") end,
        function() return true end)==0,"#942 unreadable heat did not fail closed")
end

function M.run(load, mod, owner, deps)
    assert(type(load)=="function" and type(deps)=="table","#942 check dependencies missing")
    assert(type(owner)=="table" and rawget(mod,"_wt942_owner")==owner
        and owner.prepared==true and owner.committed==true and not owner.terminal,
        "#942 installed owner missing or unhealthy")
    local Heat=load("_wt_fire_sword_heat")
    assert(deps.get_weapons()==owner.weapons
        and rawget(owner.weapons,Heat.TEMPLATE)==owner.template,"#942 installed template replaced")
    for _,key in ipairs({"damage","sweep","slam","utils","join"}) do
        assert(owner.hooks[key]==true,"#942 installed hook missing: "..key)
    end
    local parity=rawget(mod,"_wt_peer_parity")
    assert(parity and parity:is_installed()==true
        and rawget(mod,"_wt431_disconnect_epoch_guard")==true
        and type(rawget(mod,"_wt431_profiles_allowed"))=="function",
        "#942 installed catalog lifecycle missing")
    local state=owner.runtime and owner.runtime.state
    assert(state and state.profiles==deps.profiles and #state.rows>0,
        "#942 installed profile state missing")
    for source,choice in pairs(state.clones) do
        for _,key in pairs(choice) do
            local profile=rawget(deps.profiles,key)
            local owned=profile and state.owned[profile]
            assert(owned and owned.profile==profile and owned.source==source
                and rawget(deps.fallbacks,key)==source,"#942 installed profile ownership lost")
        end
    end
    for _,row in ipairs(state.rows) do
        assert(state.actions[row.action]==true and state.clones[row.source].normal==row.key,
            "#942 installed action ownership lost")
    end
    local transport=owner.transport
    assert(transport and not transport.poisoned and transport.protocol,
        "#942 installed configuration transport missing")
    local inspected=transport.protocol:inspect()
    assert(inspected.fatal==false,"#942 installed configuration protocol failed")
    private_protocol(load)
end

return M
