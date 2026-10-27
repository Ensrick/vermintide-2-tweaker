-- #428 supported shared career install/release across native and clone roles.
return function(H,root)
    local Short=dofile(root.."/qa/lua/fixtures/cwv_shortsword_construction_harness.lua")
    local Javelin=dofile(root.."/qa/lua/fixtures/cwv_javelin_construction_harness.lua")
    local CLAIMS,CLONE="__vt2_tweaker_career_action_claims","__vt2_tweaker_career_action_clone_source"
    local KEY="action_career_wh_2"
    local function context(kind,options)
        options=options or {};local mods,throwing={},false
        local resolve=function(id)if throwing then error("resolver unavailable")end;return mods[id]end
        local before=options.before
        local config={get_mod=resolve,before=function(c)
            c.mods=mods;c.env.CareerSettings={}
            c.env.ActionTemplates[KEY]={default={kind="career_dummy"}}
            c.env.CareerSettings.wh_bountyhunter={activated_ability={{action_name=KEY}}}
            c.native_key=kind=="short"and"bw_dagger"or"we_javelin"
            c.source=kind=="short"and c.env.Weapons.one_handed_daggers_template_1 or c.env.Weapons.javelin_template
            if kind=="javelin"then c.env.ItemMasterList.we_javelin={name="we_javelin",item_type="we_javelin",template="javelin_template",slot_type="ranged",can_wield={}}end
            if before then before(c)end
        end}
        local c=kind=="short"and Short.new(H,root,config)or Javelin.new(H,root,config):install()
        c.mods=mods;mods.character_weapon_variants=c.mod
        c.resolver_failure=function(value)throwing=value end
        c.kind=kind
        c.integration=c.T.run(c.T.read(root.."/tools/shared_lib/_lib_career_weapon_actions.lua"),c.env,"actual-shared-career-install-release")
        local cached_defs,cached_build
        function c.fresh()
            if kind=="short"then local def,entry,seed=c.items();c.def=def;return entry,seed end
            if not cached_build then cached_defs,cached_build=c.items()end
            local defs,build=cached_defs,cached_build;local def
            for _,row in ipairs(defs)do if row.item_key=="cwv_es_javelin"then def=row end end
            c.def=assert(def);local entry=build(def)
            local seed=c.mod._cwv_acquisition.build_seed(def,build,function(v)return c.env.table.clone(v,true)end,function()return false end)
            return entry,seed
        end
        return c
    end
    local function shared(c,template,owner)
        local result=c.integration.install(template,{"wh_bountyhunter"},c.env.CareerSettings,c.env.ActionTemplates,owner)
        H.truthy(result.ok);H.equal(template.actions[KEY],c.env.ActionTemplates[KEY]);return result
    end
    local function healthy(c)
        H.equal(c.owner.check(),nil);local item,seed=c.fresh();H.truthy(item);H.truthy(seed)
    end
    local function denied(c)
        H.truthy(c.owner.check());local item,seed=c.fresh();H.equal(item,nil);H.equal(seed,nil)
    end
    local function wt(c,id,template)
        local folder=id=="wt"and"weapon_tweaker"or"weapon_tweaker_dev"
        local mod={_wt={},get=function(_,name)return name=="unlock_wh_bountyhunter_"..c.native_key end,
            info=function()end,error=function(_,format,...)error(string.format(format,...))end}
        c.mods[id]=mod
        mod.dofile=function(_,name)return c.T.run(c.T.read(root.."/"..folder.."/"..name..".lua"),c.env,name)end
        -- Exact full public/dev unlock and availability owners are executed.
        -- Inert career/action table is a supported identity collaborator only:
        -- native wh_2 names action_career_wh_2, not native ability ABI proof.
        local data=mod:dofile("scripts/mods/"..folder.."/wt_unlock_data")
        mod._wt.weapon_unlock_map,mod._wt.cwv_conditional_managed=data.weapon_unlock_map,data.cwv_conditional_managed
        local found=false;for _,key in ipairs(data.weapon_unlock_map.wh_bountyhunter)do if key==c.native_key then found=true end end
        H.truthy(found,"actual native WT row reachable")
        mod:dofile("scripts/mods/"..folder.."/_wt_availability")
        if template==c.source then mod._wt.patch_career_actions_on_weapons()
        else
            -- Public function uses the SAME captured shared installer/owner at
            -- the native/cross-provider last-mile seam (no fake ready predicate).
            local entry=assert(c.fresh());entry.can_wield={"wh_bountyhunter"}
            local report=mod._wt.reconcile_effective_career_actions(entry,template,"wh_bountyhunter",c.def.item_key)
            H.truthy(report and report.ok)
        end
        H.equal(template.actions[KEY],c.env.ActionTemplates[KEY])
        return mod,"weapon_tweaker:"..tostring(mod)
    end
    for _,kind in ipairs({"short","javelin"})do for _,id in ipairs({"wt","wt_dev"})do
        for _,role in ipairs({"source","target"})do
            local family,provider,surface=kind,id,role
            H.test("#428 envelope actual "..family.." "..provider.." "..surface.." install release after construction",function()
                local c=context(family);healthy(c)
                local template=surface=="source"and c.source or c.template
                local mod,owner=wt(c,provider,template);healthy(c)
                c.integration.release(template,owner);healthy(c)
                H.equal(rawget(template.actions,KEY),nil)
                H.truthy(mod)
            end)
        end
    end end
    for _,kind in ipairs({"short","javelin"})do
        local family=kind
        H.test("#428 envelope "..family.." canonical injected source before construction clone and release",function()
            local provider={};local owner="weapon_tweaker:"..tostring(provider)
            local c=context(family,{before=function(c)
                c.mods.wt_dev=provider
                local integration=c.T.run(c.T.read(root.."/tools/shared_lib/_lib_career_weapon_actions.lua"),c.env,"actual-preconstruction-shared-installer")
                H.truthy(integration.install(c.source,{"wh_bountyhunter"},c.env.CareerSettings,c.env.ActionTemplates,owner).ok)
            end})
            healthy(c)
            local entry=assert(c.fresh());entry.can_wield={"wh_bountyhunter"}
            local registry={[c.def.item_key]=entry,[c.def.base_weapon]=c.env.ItemMasterList[c.def.base_weapon]}
            local adapter=c.load("_cwv_career_weapon_actions")
            local effective=c.T.run(c.T.read(root.."/tools/shared_lib/_lib_effective_weapon_templates.lua"),c.env,"actual-CWV-effective-plan")
            H.truthy(adapter.install({{def=c.def,entry=entry}},registry,c.env.Weapons,c.env.CareerSettings,c.env.ActionTemplates,c.integration,effective,"character_weapon_variants").ok)
            healthy(c);c.integration.release(c.source,owner);healthy(c)
            c.integration.release(c.template,"character_weapon_variants");healthy(c)
            H.equal(c.template.actions[KEY],c.env.ActionTemplates[KEY],"prepared inherited baseline retained")
        end)
        H.test("#428 envelope "..family.." actual CWV then WT coownership release preserves remaining provider",function()
            local c=context(family);local entry=assert(c.fresh());entry.can_wield={"wh_bountyhunter"}
            local registry={[c.def.item_key]=entry,[c.def.base_weapon]=c.env.ItemMasterList[c.def.base_weapon]}
            local adapter=c.load("_cwv_career_weapon_actions")
            local effective=c.T.run(c.T.read(root.."/tools/shared_lib/_lib_effective_weapon_templates.lua"),c.env,"actual-CWV-coowner-plan")
            H.truthy(adapter.install({{def=c.def,entry=entry}},registry,c.env.Weapons,c.env.CareerSettings,c.env.ActionTemplates,c.integration,effective,"character_weapon_variants").ok)
            local mod,owner=wt(c,"wt_dev",c.template);healthy(c)
            c.integration.release(c.template,"character_weapon_variants");healthy(c);H.equal(c.template.actions[KEY],c.env.ActionTemplates[KEY])
            c.integration.release(c.template,owner);healthy(c);H.equal(c.template.actions[KEY],nil);H.truthy(mod)
        end)
        H.test("#428 envelope "..family.." unchanged unclaimed native rows stay pinned not invented canonical",function()
            local c=context(family,{before=function(c)c.source.actions.action_career_native_private={default={kind="native_private"}}end})
            healthy(c);local row=c.source.actions.action_career_native_private
            shared(c,c.source,"character_weapon_variants");healthy(c)
            row.default.kind="foreign";denied(c)
        end)
        H.test("#428 envelope "..family.." missing throwing and replaced resolver fail closed only on dynamic WT owner",function()
            local c=context(family);c.resolver_failure(true);healthy(c);c.resolver_failure(false)
            local mod,owner=wt(c,"wt_dev",c.source);healthy(c)
            c.resolver_failure(true);denied(c);c.resolver_failure(false);healthy(c)
            c.mods.wt_dev=nil;denied(c);c.env.get_mod=function()return mod end;denied(c)
            c.mods.wt_dev=mod;healthy(c);H.equal(c.source[CLAIMS][KEY].owners[owner],true)
        end)
        H.test("#428 envelope "..family.." exact canonical claim owner meta and unrelated graph adversaries",function()
            local alterations={
                function(c)c.source.actions[KEY]={default={}}end,
                function(c)c.source[CLAIMS][KEY].value={}end,
                function(c)c.source[CLAIMS][KEY].owners["weapon_tweaker:foreign"]=true end,
                function(c)c.source[CLAIMS][KEY].owners.extra=false end,
                function(c)c.source[CLAIMS][KEY].baseline_present="false"end,
                function(c)c.source[CLAIMS][KEY].extra=true end,
                function(c)setmetatable(c.source[CLAIMS][KEY],{})end,
                function(c)setmetatable(c.source[CLAIMS][KEY].owners,{})end,
                function(c)setmetatable(c.source[CLAIMS],{})end,
                function(c)c.source[CLONE]="forged<-native"end,
                function(c)c.source.actions.action_career_unclaimed={default={}}end,
                function(c)c.source.actions.action_two.default.total_time=123 end,
                function(c)c.source.attack_meta_data.review_foreign=true end,
                function(c)c.source.wield_anim_career_3p={foreign="preview"}end,
            }
            for _,alter in ipairs(alterations)do local c=context(family);wt(c,"wt_dev",c.source);healthy(c);alter(c);denied(c)end
        end)
        H.test("#428 envelope "..family.." target-only foreign claims canonical replacement and provenance refused",function()
            local alterations={
                function(c)c.template[CLAIMS][KEY].owners["character_weapon_variants_foreign"]=true end,
                function(c)c.template[CLAIMS][KEY].baseline_present=true end,
                function(c)c.env.ActionTemplates[KEY]={default={}}end,
                function(c)c.env.ActionTemplates={}end,
                function(c)c.template[CLONE]="foreign<-source"end,
            }
            for _,alter in ipairs(alterations)do local c=context(family);wt(c,"wt_dev",c.template);healthy(c);alter(c);denied(c)end
        end)
        H.test("#428 envelope "..family.." LIMIT current canonical career body remains delegated not gameplay proof",function()
            local c=context(family);wt(c,"wt_dev",c.template);healthy(c)
            local canonical=c.env.ActionTemplates[KEY]
            c.template.actions[KEY].default.kind="changed-in-canonical-registry"
            H.equal(c.template.actions[KEY],canonical);H.equal(c.env.ActionTemplates[KEY],canonical)
            healthy(c) -- identity authority only; does not validate this action body.
        end)
        H.test("#428 envelope "..family.." actual public and dev WT source install before construction",function()
            for _,provider in ipairs({"wt","wt_dev"})do
                local owner
                local c=context(family,{before=function(context)local _,token=wt(context,provider,context.source);owner=token end})
                healthy(c);c.integration.release(c.source,owner);healthy(c)
            end
        end)
        H.test("#428 envelope "..family.." CWV public and dev WT three-owner exact coownership",function()
            local c=context(family)
            shared(c,c.template,"character_weapon_variants")
            local _,public=wt(c,"wt",c.template);local _,dev=wt(c,"wt_dev",c.template);healthy(c)
            local owners=c.template[CLAIMS][KEY].owners
            H.equal(owners.character_weapon_variants,true);H.equal(owners[public],true);H.equal(owners[dev],true)
            c.integration.release(c.template,public);healthy(c);c.integration.release(c.template,dev);healthy(c)
            c.integration.release(c.template,"character_weapon_variants");healthy(c);H.equal(c.template.actions[KEY],nil)
        end)
        H.test("#428 envelope "..family.." exact private policy references survive mutable export replacement",function()
            local c=context(family);local envelope=c.career_envelope
            envelope.capture=function()error("late policy capture read")end
            envelope.intact=function()error("late policy validator read")end
            healthy(c)
        end)
    end
    H.test("#428 envelope manifested once private both-family binds and detached getter contract",function()
        local function read(path)local file=assert(io.open(root.."/"..path,"rb"));local text=file:read("*a");file:close();return(text:gsub("\r\n","\n"))end
        local prefix="character_weapon_variants/scripts/mods/character_weapon_variants/"
        local entry=read(prefix.."character_weapon_variants.lua")
        local token='mod:dofile("scripts/mods/character_weapon_variants/_cwv_career_envelope")'
        local at=assert(entry:find(token,1,true));H.equal(entry:find(token,at+#token,true),nil)
        H.truthy(entry:find('_cwv_profile_graph, function() return ActionTemplates end, get_mod)',at,true))
        H.truthy(entry:find('_cwv_network_lookup, _cwv_profile_graph, _cwv_career_envelope)',at,true))
        H.truthy(entry:find('_core_template_construction.detached_scalar_factory, _cwv_career_envelope)',at,true))
        for _,name in ipairs({"_cwv_shortsword_construction_owner.lua","_cwv_javelin_construction_owner.lua"})do
            local source=read(prefix..name)
            H.truthy(source:find('local career_capture, career_intact = assert(envelope.capture), assert(envelope.intact)',1,true))
            H.equal(source:gsub('%-%-[^\n]*',''):find('mod:dofile',1,true),nil)
        end
        local source=read(prefix.."_cwv_career_envelope.lua")
        H.truthy(source:find('{ "wt", "wt_dev" }',1,true));H.truthy(source:find('pcall(resolve_mod, id)',1,true))
        H.equal(source:find('get_mod(',1,true),nil)
    end)
    return {context=context,wt=wt,healthy=healthy,denied=denied,shared=shared}
end
