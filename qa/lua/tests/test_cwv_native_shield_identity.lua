return function(H, root, candidate)
local cwv = root.."/character_weapon_variants/scripts/mods/character_weapon_variants/"
local cos = root.."/cosmetics_tweaker/scripts/mods/cosmetics_tweaker/"
local function path(name)
    if candidate then return candidate.."/"..name end
    return (name:sub(1,5)=="_cos_" and cos or cwv)..name
end
local Native = dofile(path("_cos_native_shield_identity.lua"))
local State = dofile(path("_cos_offhand_state_runtime.lua"))
local Exact = dofile(path("_cwv_exact_appearance.lua"))
local Appearance = dofile(path("_cwv_combat_style_appearance.lua"))
local Planner = dofile(path("_cwv_identity_descriptor_planner.lua"))
local Styles = dofile(path("_cwv_combat_styles.lua"))
local Lifecycle = dofile(cwv.."_cwv_appearance_lifecycle.lua")
local Descriptor = dofile(root.."/tools/shared_lib/_lib_appearance_descriptor.lua")
local function copy(x)
    if type(x)~="table" then return x end
    local y={}; for k,v in pairs(x) do y[k]=copy(v) end; return y
end
local function read(path)
    local f=assert(io.open(path,"rb"));local s=f:read("*a");f:close();return (s:gsub("\r\n","\n"))
end
local catalog=read(cos.."_cos_offhand_catalog.lua")
local first=assert(catalog:find("local _SHIELD_POOLS_BY_ITEM_TYPE = ",1,true))
local a=assert(catalog:find("{",first,true))
local b=assert(catalog:find("\n    }\n",a,true))+6
local pools=assert(loadstring("return "..catalog:sub(a,b),"@actual-native-shield-pool"))()
local units={
    empire=pools.es_1h_sword_shield[1].unit,
    round=pools.es_1h_sword_shield[2].unit,
    blue=pools.es_1h_sword_shield[6].unit,
    blessed=pools.es_1h_sword_shield[11].unit,
    ambiguous=pools.es_1h_sword_shield[8].unit,
}
local function fixture(item_key)
    item_key=item_key or "es_sword_shield"
    local s={ style=item_key=="es_sword_shield" and "bretonnian" or "empire",
        saved={}, allowed=true, sent={}, hooks={}, network={}, rewields=0, accepted={} }
    local items={
        es_sword_shield={item_type="es_1h_sword_shield",right_hand_unit="units/empire_primary",left_hand_unit=units.empire},
        es_sword_shield_breton={item_type="es_1h_sword_shield_breton",right_hand_unit="units/breton_primary",left_hand_unit=units.blue,required_dlc="lake"},
        es_deus_01={item_type="es_deus_01",required_dlc="grass"},
    }
    local skins={}
    local function skin(key,donor,unit,dlc)
        items[key]={item_type="weapon_skin",matching_item_key=donor,left_hand_unit=unit,required_dlc=dlc}
        skins[key]={right_hand_unit="units/primary_"..key,left_hand_unit=unit}
    end
    skin("es_1h_sword_shield_skin_01","es_sword_shield",units.empire)
    skin("es_1h_sword_shield_skin_02","es_sword_shield",units.round)
    skin("es_sword_shield_breton_skin_05","es_sword_shield_breton",units.blue,"lake")
    skin("es_sword_shield_breton_skin_04","es_sword_shield_breton",units.blessed,"lake")
    s.items,s.skins=items,skins
    local options={
        es_1h_sword_shield={left_hand_unit=copy(pools.es_1h_sword_shield)},
        es_1h_sword_shield_breton={left_hand_unit=copy(pools.es_1h_sword_shield)},
    }
    s.options=options
    local cos_mod={info=function()end}
    s.selection={}
    s.cos=cos_mod
    State.install(cos_mod,{
        native_shield_identity=Native,
        get_weapon_skins=function()return s.skins end,
        la_bridge={registered=false},
        la_persist={ get_saved_offhands=function()return s.saved end,
            get_saved_offhands_for=function(id) if s.saved_error then error("saved reader") end;return s.saved[id] end },
        offhand_names={},decorate_shield_option=function()end,
        offhand_options=options,offhand_selection=s.selection,
        preload_offhand_package=function()end,preload_offhand_for_option=function()end,
        get_mod=function()end,
        get_managers=function() if s.unlock_error then error("unlock reader") end
            return {unlock={is_dlc_unlocked=function()return s.allowed end}} end,
        get_item_master_list=function()return s.items end,
    })
    local om={
        exact_appearance=Exact,combat_style_appearance=Appearance,
        appearance_lifecycle_policy=Lifecycle,appearance_descriptor=Descriptor,
        combat_style_policy=Styles,
        _skin_keys={},cosmetic_skin_wire={is_cwv_skin=function()return false end},
        _cwv_key_for_item=function()return nil end,
        identity_peer_pull=dofile(cwv.."_cwv_identity_peer_pull.lua"),
        identity_peer_cleanup=dofile(cwv.."_cwv_identity_peer_cleanup.lua"),
        peer_resolver={},exact_wire_runtime={install_damage=function()end},
    }
    om.combat_styles={
        describe=function(_,item)
            local family=Styles.member(item.name)
            return {item_key=item.name,identity="bid-657",family_id=family,style_id=s.style,
                package=Styles.package(item.name,s.style)}
        end,
        accept_style_edge=function(_,peer,slot,family,style,route,descriptor)
            if descriptor then s.accepted[#s.accepted+1]=descriptor;return true end
            return false
        end,
    }
    local mod={
        _cwv_rewield={request_peer_rewield=function()s.rewields=s.rewields+1 end},
        hook=function(_,class,method,callback) s.hooks[tostring(class).."."..method]=callback end,
        network_register=function(_,name,callback)s.network[name]=callback end,
        network_send=function(_,name,recipient,schema,payload)
            s.sent[#s.sent+1]={name,recipient,schema,payload}
        end,
        dofile=function(_,path)
            if path:find("_cwv_outrider_projectile_wire",1,true) then return {install=function()end} end
            if path:find("_lib_network_lookup",1,true) then return {} end
            if path:find("_cwv_identity_descriptor_planner",1,true) then return Planner end
            error("unexpected dofile "..path)
        end,
    }
    local env=setmetatable({ItemMasterList=items,WeaponSkins={skins=skins},
        LoadoutUtils=false,CosmeticUtils=false,PlayerManager=false,NetworkLookup={},
        get_mod=function() if s.cos_error then error("provider lookup") end;return s.cos end,
        printf=function()end},{__index=_G})
    env._G=env
    local chunk=assert(loadfile(path("_cwv_item_identity_transport_owner.lua")));setfenv(chunk,env)
    chunk()(mod,{om=om,find_def=function()return nil end,custom_skin_keys={}})
    s.om,s.mod=om,mod
    s.slot={item_data={name=item_key,backend_id="bid-657"},skin=item_key=="es_sword_shield"
        and "es_1h_sword_shield_skin_01" or "es_sword_shield_breton_skin_05"}
    s.saved["bid-657"]={left_hand_unit={unit_path=item_key=="es_sword_shield" and units.blue or units.empire}}
    function s.payload()return om._cwv_identity_payloads({slot_melee=s.slot})[1]end
    function s.receive(payload,peer)
        s.network.cwv_item_identity(peer or "peer-657",Lifecycle.SCHEMA,payload)
        return om._cwv_identity_descriptor_for_peer(peer or "peer-657","slot_melee",item_key)
    end
    return s
end

for _,key in ipairs({"es_sword_shield","es_sword_shield_breton"}) do
H.test("657 actual committed provider planner payload registered receiver "..key,function()
    local s=fixture(key)
    H.equal(s.network.cwv_item_identity,s.om._cwv_receive_identity)
    local saved_before=copy(s.saved)
    local payload=s.payload()
    H.equal(payload.provider,Appearance.PROVIDER)
    H.equal(payload.offhand_skin_key,key=="es_sword_shield" and "es_sword_shield_breton_skin_05" or "es_1h_sword_shield_skin_01")
    H.equal(payload.skin_key,s.slot.skin)
    H.equal(payload.right_hand_unit,nil);H.equal(payload.left_hand_unit,nil)
    local remote,state=s.receive(payload)
    H.equal(state,"exact");H.equal(remote.fingerprint,payload.fingerprint)
    H.equal(remote.offhand_skin,payload.offhand_skin_key)
    H.equal(remote.right_hand_unit.unit,s.skins[s.slot.skin].right_hand_unit)
    H.equal(remote.left_hand_unit.unit,s.saved["bid-657"].left_hand_unit.unit_path)
    H.equal(#s.accepted,1);H.equal(s.rewields,0)
    H.equal(s.saved["bid-657"].left_hand_unit.vanilla_key,nil)
    H.equal(s.saved["bid-657"].left_hand_unit.unit_path,saved_before["bid-657"].left_hand_unit.unit_path)
end)
end
H.test("657 exact offhand changes fingerprint and per-route delivery dedupe",function()
    local s=fixture()
    local first=s.payload()
    H.equal(s.om._cwv_send_identity_slots({slot_melee=s.slot},"first",false,nil,true),1)
    H.equal(s.om._cwv_send_identity_slots({slot_melee=s.slot},"same",false,nil,true),0)
    s.saved["bid-657"].left_hand_unit.unit_path=units.blessed
    local second=s.payload();H.truthy(second.fingerprint~=first.fingerprint)
    H.equal(second.offhand_skin_key,"es_sword_shield_breton_skin_04")
    H.equal(s.om._cwv_send_identity_slots({slot_melee=s.slot},"changed",false,nil,true),1)
    local remote=s.receive(second);H.equal(remote.left_hand_unit.unit,units.blessed)
end)
H.test("657 saved source-key and legacy unit-only records normalize identically",function()
    local s=fixture();local first=s.payload()
    s.saved["bid-657"].left_hand_unit.vanilla_key=first.offhand_skin_key
    H.equal(s.payload().fingerprint,first.fingerprint)
end)
H.test("657 hover and unapplied selection never replace committed component",function()
    local s=fixture();local before=s.payload()
    s.selection["bid-657"]={left_hand_unit={unit=units.blessed}}
    s.selection.es_1h_sword_shield={left_hand_unit={unit=units.blessed}}
    local after=s.payload()
    H.equal(after.fingerprint,before.fingerprint)
    H.equal(after.offhand_skin_key,before.offhand_skin_key)
end)
H.test("657 no Cosmetics and no committed offhand preserve primary follow behavior",function()
    local s=fixture();s.saved={}
    H.equal(s.payload().offhand_skin_key,"")
    s.cos=nil
    local p=s.payload();H.equal(p.provider,Appearance.PROVIDER);H.equal(p.offhand_skin_key,"")
    H.truthy(s.receive(p))
end)
local denials={
    foreign_unit=function(s)s.saved["bid-657"].left_hand_unit.unit_path="units/foreign"end,
    foreign_key=function(s)s.saved["bid-657"].left_hand_unit.vanilla_key="foreign_skin"end,
    mismatched_unit=function(s)s.saved["bid-657"].left_hand_unit.vanilla_key="es_1h_sword_shield_skin_01"end,
    ambiguous_material=function(s)s.saved["bid-657"].left_hand_unit.unit_path=units.ambiguous end,
    missing_dlc=function(s)s.allowed=false end,
    unreadable_dlc=function(s)s.unlock_error=true end,
    unreadable_saved=function(s)s.saved_error=true end,
    throwing_mod_lookup=function(s)s.cos_error=true end,
    unready_provider=function(s)s.cos._cos.cwv_offhand_identity=nil end,
    throwing_provider=function(s)s.cos._cos.cwv_offhand_identity=function()error("provider")end end,
    pool_removed=function(s)s.options.es_1h_sword_shield.left_hand_unit={}end,
    wrong_matching_item=function(s)s.items.es_sword_shield_breton_skin_05.matching_item_key="wh_1h_axe"end,
    wrong_item_type=function(s)s.items.es_sword_shield.item_type="es_sword_shield"end,
    missing_registry=function(s)s.skins.es_sword_shield_breton_skin_05=nil end,
    unknown_primary_skin=function(s)s.slot.skin="unknown_primary_skin"end,
    changed_registered_unit=function(s)s.skins.es_sword_shield_breton_skin_05.left_hand_unit="units/foreign"end,
}
for name,change in pairs(denials)do
H.test("657 native committed sender denies "..name,function()
    local s=fixture();change(s)
    H.equal(s.payload().provider,"")
    H.equal(s.om._cwv_local_style_descriptor_by_slot.slot_melee,nil)
end)
end
H.test("657 receiver independently denies sender-only admission",function()
    local s=fixture();local p=s.payload()
    s.cos._cos.cwv_native_shield_identity=nil
    H.equal(s.receive(p),nil);H.equal(#s.accepted,0);H.equal(#s.sent,0)
end)
H.test("657 receiver independently denies changed local DLC and pool",function()
    local s=fixture();local p=s.payload();s.allowed=false
    H.equal(s.receive(p),nil);H.equal(#s.sent,0)
    s.allowed=true;s.options.es_1h_sword_shield.left_hand_unit={}
    H.equal(s.receive(p,"peer-other"),nil)
end)
H.test("657 current receiver invalidates prior exact proof after registry replacement",function()
    local s=fixture();local p=s.payload()
    H.truthy(s.receive(p));H.equal(#s.sent,1)
    s.skins.es_sword_shield_breton_skin_05={left_hand_unit="units/foreign"}
    local remote,state=s.receive(p)
    H.equal(remote,nil);H.equal(state,"unavailable")
    H.equal(#s.sent,1);H.equal(#s.accepted,1)
end)
H.test("657 wrong-hand unknown and foreign native admission is denied",function()
    local s=fixture();local api=s.cos._cos.cwv_native_shield_identity
    H.equal(api.admit("es_sword_shield","es_1h_sword_shield","right_hand_unit","es_sword_shield_breton_skin_05"),nil)
    H.equal(api.admit("es_mace_shield","es_1h_mace_shield","left_hand_unit","es_sword_shield_breton_skin_05"),nil)
    H.equal(api.admit("es_sword_shield","es_1h_sword_shield","left_hand_unit","unknown"),nil)
end)
H.test("657 tampered semantic fields never earn an ACK or descriptor",function()
    for _,axis in ipairs({"skin_key","offhand_skin_key","item_key","base_item_key","style","fingerprint"})do
        local s=fixture();local p=s.payload();p[axis]="foreign"
        H.equal(s.receive(p),nil,axis);H.equal(#s.accepted,0,axis);H.equal(#s.sent,0,axis)
    end
end)
H.test("657 native callback cannot relax stamped CWV variant ownership",function()
    local s=fixture()
    local descriptor,reason=Exact.resolve_spawn_descriptor({provider="cwv_style_world",
        variant={item_key="cwv_fake",base_weapon="es_sword_shield"},base_item_key="es_sword_shield",
        base=s.items.es_sword_shield,explicit_offhand_skin="es_sword_shield_breton_skin_05",
        item_master=s.items,weapon_skins=s.skins,native_offhand_unit=function()return units.blue end})
    H.equal(descriptor,nil);H.equal(reason,"offhand_skin_unresolved")
    s.items.es_sword_shield_breton_skin_05.cwv_owner_item_type="cwv_fake"
    descriptor=Exact.resolve_spawn_descriptor({provider="cwv",variant={item_key="cwv_fake"},
        explicit_offhand_skin="es_sword_shield_breton_skin_05",item_master=s.items,weapon_skins=s.skins})
    H.truthy(descriptor);H.equal(descriptor.left_hand_unit,units.blue)
end)
H.test("657 source installs one shared planner and leaves delivery body unchanged",function()
    local s=read(path("_cwv_item_identity_transport_owner.lua"))
    H.truthy(s:find("resolve_local = planner.resolve_local",1,true))
    H.truthy(s:find("resolve_remote = planner.resolve_remote",1,true))
    H.truthy(s:find('mod:network_register("cwv_item_identity", _om._cwv_receive_identity)',1,true))
end)
H.test("657 named detached check exercises the installed planner without live state",function()
    local s=fixture()
    H.equal(Planner.check_native_shield({om=s.om,get_mod=function()return s.cos end,
        get_item_master=function()return s.items end,get_weapon_skins=function()return s.skins end}),nil)
    H.equal(Planner.check_native_shield({om=s.om,get_mod=function()return nil end,
        get_item_master=function()return s.items end,get_weapon_skins=function()return s.skins end}),nil)
    H.equal(s.saved["bid-657"].left_hand_unit.vanilla_key,nil)
    H.equal(s.om._cwv_local_style_descriptor_by_slot.slot_melee,nil)
    H.equal(#s.sent,0);H.equal(#s.accepted,0)
end)
H.test("657 named detached check fails on unready or unreadable installed capability",function()
    local s=fixture()
    local ctx={om=s.om,get_mod=function()error("lookup")end,
        get_item_master=function()return s.items end,get_weapon_skins=function()return s.skins end}
    H.truthy(Planner.check_native_shield(ctx))
    ctx.get_mod=function()return {_cos={}}end
    H.truthy(Planner.check_native_shield(ctx))
    ctx.get_item_master=function()return {}end
    H.truthy(Planner.check_native_shield(ctx))
end)
for _,key in ipairs({"es_sword_shield","es_sword_shield_breton"})do
for _,mode in ipairs({"commit","denied_prepare","failed_wield"})do
H.test("657 actual native style transaction "..key.." "..mode,function()
    local s=fixture(key)
    local counts={prepare=0,destroy=0,add=0,wield=0,persist=0}
    local equipment={wielded_slot="slot_melee",slots={slot_melee=s.slot}}
    local inventory={equipment=function()return equipment end,
        destroy_slot=function()counts.destroy=counts.destroy+1 end,
        add_equipment=function()counts.add=counts.add+1 end,
        wield=function()counts.wield=counts.wield+1;if mode=="failed_wield"then error("wield")end end}
    s.mod.get=function()end
    s.mod.set=function()counts.persist=counts.persist+1 end
    local runtime
    runtime=Styles.install(s.mod,{
        local_equipment=function()return inventory end,
        owns_dlc=function()return true end,
        acquire_style_resource=function(_,complete)complete(true);return true end,
        style_descriptor_family=Appearance.supports_family,
        prepare_style_descriptor=function(slots,identity,desired)
            counts.prepare=counts.prepare+1
            local payload=s.om._cwv_identity_payloads(slots)[1]
            local retained=s.om._cwv_local_style_descriptor_by_slot.slot_melee
            return payload.provider==Appearance.PROVIDER and retained
                and retained.identity==identity and retained.descriptor.style_id==desired
        end,
        send_identity_slots=s.om._cwv_send_identity_slots,
    })
    s.om.combat_styles=runtime
    local original=runtime:describe(s.slot.item_data).style_id
    if mode=="denied_prepare"then s.saved["bid-657"].left_hand_unit.unit_path=units.ambiguous end
    local completed,result,detail=0
    local accepted,status=runtime:cycle_item(s.slot.item_data,nil,"detached657",true,function(ok,err)
        completed=completed+1;result,detail=ok,err
    end)
    H.equal(accepted,true);H.equal(status,"transition pending")
    H.equal(completed,1)
    local changed,reason=result,detail
    H.equal(counts.prepare,1)
    if mode=="commit"then
        H.equal(changed,true,reason);H.equal(counts.persist,1)
        H.equal(counts.destroy,1);H.equal(counts.add,1);H.equal(counts.wield,1)
        H.truthy(runtime:describe(s.slot.item_data).style_id~=original)
        H.truthy(#s.sent>0 and #s.sent<=3)
    else
        H.equal(changed,false)
        H.equal(runtime:describe(s.slot.item_data).style_id,original)
        H.equal(s.slot.item_data.mod_data.cwv_combat_style,original)
        H.equal(#s.sent,0)
        if mode=="denied_prepare"then
            H.equal(reason,"appearance descriptor unavailable")
            H.equal(counts.persist,0);H.equal(counts.destroy,0)
            H.equal(counts.add,0);H.equal(counts.wield,0)
        else
            H.equal(reason,"rebuild failed");H.equal(counts.persist,1)
            H.equal(counts.destroy,2);H.equal(counts.add,2);H.equal(counts.wield,2)
        end
    end
end)
end
end

-- Admission is resolved before any live-slot, action, store or model-data write.
local function admission_fixture(key, provider, with_metadata)
    local counts={provider=0,equipment=0,prepare=0,destroy=0,add=0,wield=0,persist=0,network=0}
    local item={backend_id="admission:"..key,key=key}
    if with_metadata then item.mod_data={retained="untouched"} end
    local equipment={wielded_slot="slot_melee",slots={slot_melee={item_data=item}}}
    local inventory={
        equipment=function()counts.equipment=counts.equipment+1;return equipment end,
        destroy_slot=function()counts.destroy=counts.destroy+1 end,
        add_equipment=function()counts.add=counts.add+1 end,
        wield=function()counts.wield=counts.wield+1 end,
    }
    local mod={get=function()end,set=function()counts.persist=counts.persist+1 end,
        network_send=function()counts.network=counts.network+1 end}
    local predicate=provider
    if type(provider)=="function"then
        predicate=function(...)counts.provider=counts.provider+1;return provider(...)end
    end
    local runtime=Styles.install(mod,{
        local_equipment=function()counts.equipment=counts.equipment+1;return inventory end,
        owns_dlc=function()return true end,
        acquire_style_resource=function(_,complete)complete(true);return true end,
        style_descriptor_family=predicate,
        prepare_style_descriptor=function()counts.prepare=counts.prepare+1;return true end,
        send_identity_slots=function()counts.network=counts.network+1 end,
    })
    local before={store=copy(runtime.store),item=copy(item)}
    local store,items,metadata=runtime.store,runtime.store.items,rawget(item,"mod_data")
    local function unchanged()
        H.deep_equal(runtime.store,before.store);H.deep_equal(item,before.item)
        H.equal(runtime.store,store);H.equal(runtime.store.items,items)
        H.equal(rawget(item,"mod_data"),metadata)
        H.equal(counts.equipment,0);H.equal(counts.prepare,0)
        H.equal(counts.destroy,0);H.equal(counts.add,0);H.equal(counts.wield,0)
        H.equal(counts.persist,0);H.equal(counts.network,0)
    end
    return runtime,item,counts,unchanged
end
local unknown_predicates={
    {"throws",function()error("unreadable capability")end},
    {"nonfunction",true},
    {"callable nonfunction",setmetatable({calls=0},{__call=function(self)self.calls=self.calls+1;return true end})},
    {"nil return",function()end},
    {"string return",function()return "supported" end},
    {"numeric return",function()return 1 end},
}
for _,key in ipairs({"es_sword_shield","es_sword_shield_breton","es_2h_sword"})do
    for _,spec in ipairs(unknown_predicates)do
        for _,metadata in ipairs({false,true})do
            local item_key,label,provider,with_metadata=key,spec[1],spec[2],metadata
            H.test("657 actual cycle refuses unknown family before writes "..item_key.." "..label.." metadata="..tostring(with_metadata),function()
                local runtime,item,counts,unchanged=admission_fixture(item_key,provider,with_metadata)
                local completions,result,reason=0
                local accepted,status=runtime:cycle_item(item,nil,"admission657",true,function(ok,err)
                    completions=completions+1;result,reason=ok,err
                end)
                H.equal(accepted,true);H.equal(status,"transition pending")
                H.equal(completions,1);H.equal(result,false)
                H.equal(reason,"appearance family unavailable")
                H.equal(counts.provider,type(provider)=="function"and 1 or 0)
                if type(provider)=="table"then H.equal(provider.calls,0,"nonfunction predicate was executed")end
                unchanged()
            end)
        end
    end
    for _,kind in ipairs({"absent","explicit false","explicit true"})do
        local item_key,mode=key,kind
        H.test("657 actual cycle preserves known family policy "..item_key.." "..mode,function()
            local provider
            if mode=="explicit false"then provider=function()return false end end
            if mode=="explicit true"then provider=function()return true end end
            local runtime,item,counts=admission_fixture(item_key,provider,true)
            local original=runtime:describe(item).style_id
            local completions,result,reason=0
            local accepted,status=runtime:cycle_item(item,nil,"admission657",true,function(ok,err)
                completions=completions+1;result,reason=ok,err
            end)
            H.equal(accepted,true);H.equal(status,"transition pending")
            H.equal(completions,1);H.equal(result,true,reason)
            H.equal(counts.provider,provider and 1 or 0)
            H.equal(counts.prepare,(mode=="explicit true"or(mode=="absent"and item_key=="es_2h_sword"))and 1 or 0)
            H.equal(counts.destroy,1);H.equal(counts.add,1);H.equal(counts.wield,1)
            H.equal(counts.persist,1);H.equal(counts.network,2)
            H.truthy(runtime:describe(item).style_id~=original)
        end)
    end
    local item_key=key
    H.test("657 unsupported style wins before unreadable family "..item_key,function()
        local runtime,item,counts,unchanged=admission_fixture(item_key,function()error("must not query")end,false)
        local ok,reason=runtime:set_item_style(item,nil,"foreign-style","admission657",true)
        H.equal(ok,false);H.equal(reason,"unsupported style")
        H.equal(counts.provider,0);unchanged()
    end)
end

local native_root=root.."/../Vermintide-2-Source-Code/"
local function optional_read(path)
    local f=io.open(path,"rb");if not f then return nil end
    local s=f:read("*a");f:close();return (s:gsub("\r\n","\n"))
end
local native_exported=optional_read(native_root.."scripts/settings/equipment/item_master_list_exported.lua")
local native_skin_items=optional_read(native_root.."scripts/settings/equipment/item_master_list_weapon_skins.lua")
local native_lake=optional_read(native_root.."scripts/settings/dlcs/lake/item_master_list_lake.lua")
local native_morris=optional_read(native_root.."scripts/settings/equipment/item_master_list_morris.lua")
local skin_base=optional_read(native_root.."scripts/settings/equipment/weapon_skins.lua")
local skin_lake=optional_read(native_root.."scripts/settings/equipment/weapon_skins_lake.lua")
local skin_morris=optional_read(native_root.."scripts/settings/equipment/weapon_skins_morris.lua")
local json_source=optional_read(native_root.."PlayFab/json.lua")
local native_present=not not (native_exported and native_skin_items and native_lake and native_morris
    and skin_base and skin_lake and skin_morris)
local function literal(text,marker)
    local at=assert(text:find(marker,1,true),marker)
    local first=assert(text:find("{",at,true))
    local depth,quote,escaped=0,nil,false
    for i=first,#text do
        local ch=text:sub(i,i)
        if quote then
            if escaped then escaped=false elseif ch=="\\"then escaped=true elseif ch==quote then quote=nil end
        elseif ch=='"' or ch=="'"then quote=ch
        elseif ch=="{"then depth=depth+1
        elseif ch=="}"then depth=depth-1;if depth==0 then
            return assert(loadstring("return "..text:sub(first,i),"@source-qualified-literal"))()
        end end
    end
    error("unterminated native literal")
end
local specifications=literal(read(path("_cos_native_shield_identity.lua")),"local SOURCES =")
for key,spec in pairs(specifications)do
H.test_if(native_present,"657 exact native source mapping "..key,function()
    local items={
        es_sword_shield=literal(native_exported,"ItemMasterList.es_sword_shield ="),
        es_sword_shield_breton=literal(native_lake,"ItemMasterList.es_sword_shield_breton ="),
        es_deus_01=literal(native_morris,"\n\tes_deus_01 ="),
    }
    local iml,skin_text,marker
    if key:find("^es_sword_shield_breton_")then
        iml,skin_text,marker=native_lake,skin_lake,"ItemMasterList."..key.." ="
    elseif key:find("^es_deus_")then
        iml,skin_text,marker=native_morris,skin_morris,"\n\t"..key.." ="
    else
        iml,skin_text,marker=native_skin_items,skin_base,"ItemMasterList."..key.." ="
    end
    items[key]=literal(iml,marker)
    local skins={[key]=literal(skin_text,'name = "'..key..'"')}
    local saved={left_hand_unit={unit_path=spec[2]}}
    local owner=Native.new({get_item_master=function()return items end,
        get_weapon_skins=function()return skins end,
        get_saved=function()return saved end,
        get_pool=function()return pools.es_1h_sword_shield end,
        dlc_owned=function()return true end})
    for _,target in ipairs({"es_sword_shield","es_sword_shield_breton"})do
        local proof,reason=owner.admit(target,items[target].item_type,"left_hand_unit",key)
        H.truthy(proof,reason);H.equal(proof.unit,spec[2]);H.equal(proof.source_item_key,spec[1])
        H.equal(owner.committed("native-source",items[target].item_type,"left_hand_unit"),key)
    end
end)
end
H.test_if(native_present,"657 exact native aliases prove legacy runed material ambiguity",function()
    local blue=literal(skin_lake,'name = "es_sword_shield_breton_skin_03_runed_01"')
    local purple=literal(skin_lake,'name = "es_sword_shield_breton_skin_03_runed_02"')
    H.equal(blue.left_hand_unit,purple.left_hand_unit)
    H.equal(blue.material_settings_name,"blue_glow")
    H.equal(purple.material_settings_name,"purple_glow")
    for _,spec in pairs(specifications)do H.truthy(spec[2]~=blue.left_hand_unit)end
end)
H.test_if(json_source~=nil,"657 exact semantic VMF argument envelope stays below native limit",function()
    -- Source-language adapter only: engine LuaJIT accepts hexadecimal string
    -- escapes; stock Lua 5.1 needs the equivalent decimal escapes. Exact count
    -- assertions prevent this narrow adapter from masking other source changes.
    local source=json_source:gsub("^\239\187\191","")
    local low,high
    source,low=source:gsub("\\x01","\\001")
    source,high=source:gsub("\\x1F","\\031")
    H.equal(low,1);H.equal(high,1)
    local json=assert(loadstring(source,"@native-PlayFab-json"))()
    for _,key in ipairs({"es_sword_shield","es_sword_shield_breton"})do
        local s=fixture(key);local payload=s.payload()
        local wire=json.encode({Lifecycle.SCHEMA,payload})
        H.truthy(#wire<500,"semantic args bytes="..#wire)
        H.equal(wire:find("units/",1,true),nil)
    end
end)
end
