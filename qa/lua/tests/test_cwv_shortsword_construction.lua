-- #428 closed Shortsword construction/admission, actual source/native closure.
return function(H, root)
    local F = dofile(root .. "/qa/lua/fixtures/cwv_shortsword_construction_harness.lua")
    local function new(config) return F.new(H, root, config) end
    local names = { "medium_slashing_linesman", "medium_slashing_smiter_stab", "light_fencer_stab",
        "dagger_1h_light_linesman", "dagger_1h_light_smiter_stab" }
    local function canonical(value, seen)
        if type(value) == "function" then return string.dump(value) end
        if type(value) ~= "table" then return value end
        seen = seen or {}; assert(not seen[value], "fixture graph cycle"); seen[value] = true
        local result = {}; for key, child in next, value do result[key] = canonical(child, seen) end
        seen[value] = nil; return result
    end
    local function upvalue(fn, key)
        for index = 1, 30 do local name, value = debug.getupvalue(fn, index)
            if name == key then return value end; if not name then break end end
        error("required private upvalue missing " .. key)
    end
    local function callbacks(c)
        local transcript, count = {}, 0
        c.env.ScriptUnit = { extension = function(_, system)
            H.equal(system, "status_system"); return { fatigued = function() return c.fatigued end }
        end }
        for group_name, group in pairs(c.template.actions) do if type(group) == "table" then
            for action_name, action in pairs(group) do if type(action) == "table" then
                for key, callback in pairs(action) do if type(callback) == "function" then
                    local row = {}; count = count + 1
                    if key == "anim_end_event_condition_func" then
                        for _, reason in ipairs({ "new_interupting_action", "interrupted", "action_complete" }) do row[#row + 1] = callback({}, reason) end
                    elseif key == "enter_function" or key == "chain_condition_func" then
                        local input = { reset_release_input = function() row[#row + 1] = "reset"; return "release" end,
                            reset_release_input_with_delay = function(_, delay) row[#row + 1] = delay; return "delayed" end }
                        c.fatigued = false; row.first = callback({}, input, 0.75)
                        c.fatigued = true; row.second = callback({}, input, 0.5)
                    else error("complete native callback must be exercised: " .. key) end
                    transcript[group_name .. "." .. action_name .. "." .. key] = row
                end end
            end end
        end end
        H.equal(count, 19, "complete source-qualified native callbacks")
        return transcript
    end
    local function observed(c)
        local profiles = {}; for _, name in ipairs(names) do profiles[name] = c.env.DamageProfileTemplates["cwv_shortsword_" .. name] end
        return { template = canonical(c.template), profiles = canonical(profiles), lookup = canonical(c.lookup),
            map = canonical(c.state._cwv_damage_profile_wire_source), generation = c.state._cwv_damage_profile_generation,
            first = c.state._cwv_wire_fallback_profile_id, audit = canonical(c.audit()),
            donor = canonical(c.env.Weapons.one_handed_daggers_template_1), callbacks = callbacks(c),
            old_musket = canonical(c.env.Weapons.old_musket_template), regular_musket = canonical(c.env.Weapons.musket_template) }
    end
    local function raw_observed(c)
        local profiles, sources = {}, {}
        for _,name in ipairs(names)do profiles[name]=c.env.DamageProfileTemplates["cwv_shortsword_"..name];sources[name]=c.env.DamageProfileTemplates[name]end
        return {template=c.template,profiles=profiles,sources=sources,powers=c.env.PowerLevelTemplates,
            lookup=c.lookup,map=c.state._cwv_damage_profile_wire_source,audit=c.audit(),donor=c.env.Weapons.one_handed_daggers_template_1}
    end
    local function equivalent(a,b)
        local ab,ba={},{}
        local function visit(left,right,path)
            H.equal(type(left),type(right),path.." type")
            if type(left)=="function"then H.equal(string.dump(left),string.dump(right),path.." callback bytecode");return end
            if type(left)~="table"then H.equal(left,right,path.." scalar/false");return end
            if ab[left]then H.equal(ab[left],right,path.." alias");H.equal(ba[right],left,path.." reverse alias");return end
            H.equal(ba[right],nil,path.." duplicate alias");ab[left],ba[right]=right,left
            H.equal(getmetatable(left),getmetatable(right),path.." exact metatable")
            local one,two=0,0
            for key,value in next,left do one=one+1;visit(value,rawget(right,key),path.."."..tostring(key))end
            for _ in next,right do two=two+1 end;H.equal(one,two,path.." raw shape")
        end
        visit(a,b,"complete-prior-core")
    end
    H.test("#428 Shortsword complete actual prior/current core template math IDs audit callbacks equivalent", function()
        local prior, current = new({prior=true}), new()
        H.truthy(prior.template); H.truthy(current.template, current.owner.check())
        H.deep_equal(observed(current), observed(prior))
        equivalent(raw_observed(current),raw_observed(prior))
        H.deep_equal(current.core_order, {"core", "musket"})
        local events = current.proof().events
        local old = {}; for _, row in ipairs(prior.construction_source_events) do
            if row[1]:sub(1,#"cwv_shortsword_") == "cwv_shortsword_" then old[#old + 1] = row end
        end
        H.equal(#events, 7); H.deep_equal(events, old, "actual legacy encounter order retained privately")
        H.equal(current.owner.check(), nil); H.equal(current.state._cwv_profile_multiplier_check(), nil)
    end)
    H.test("#428 Shortsword complete prior oracle catches alias callback and metatable disconnections",function()
        local prior,current=new({prior=true}),new();equivalent(raw_observed(current),raw_observed(prior))
        local profile=current.env.DamageProfileTemplates.light_fencer_stab
        local original=profile.cleave_distribution;profile.cleave_distribution=current.env.table.clone(original,true)
        H.equal(pcall(equivalent,raw_observed(current),raw_observed(prior)),false);profile.cleave_distribution=original
        local action=current.template.actions.action_two.default;local callback=action.enter_function
        action.enter_function=function()return "not native"end
        H.equal(pcall(equivalent,raw_observed(current),raw_observed(prior)),false);action.enter_function=callback
        setmetatable(action,{});H.equal(pcall(equivalent,raw_observed(current),raw_observed(prior)),false);setmetatable(action,nil)
    end)
    H.test("#428 Shortsword actual helper once load private identities and publisher order", function()
        local c = new(); local counts, positions = {}, {}
        for index, name in ipairs(c.loads_order) do counts[name] = (counts[name] or 0) + 1; positions[name] = index end
        for _, name in ipairs({"_lib_network_lookup", "_cwv_profile_graph_transaction", "_cwv_shortsword_construction_owner", "_cwv_core_templates", "_cwv_old_musket_shot_owner"}) do H.equal(counts[name], 1, name) end
        H.truthy(positions._lib_network_lookup < positions._cwv_core_templates)
        H.truthy(positions._cwv_profile_graph_transaction < positions._cwv_core_templates)
        H.truthy(positions._cwv_core_templates < positions._cwv_old_musket_shot_owner)
        H.equal(c.capsule.network_lookup, c.helper); H.equal(c.owner.check(), nil)
    end)
    local function audit(options) return upvalue(options.scalar_factory, "live_audit") end
    local function snapshot(c, options)
        return { profiles=c.graph.capture(c.env.DamageProfileTemplates,8192,65536), powers=c.graph.capture(c.env.PowerLevelTemplates,8192,65536),
            lookup=c.T.shape(c.lookup), map=c.T.shape(c.state._cwv_damage_profile_wire_source), source=c.graph.capture(c.env.Weapons.one_handed_daggers_template_1,4096,32768),
            audit=c.T.shape(audit(options)), generation=c.state._cwv_damage_profile_generation, first=rawget(c.state,"_cwv_wire_fallback_profile_id") }
    end
    local function restored(c, prior)
        H.truthy(c.graph.intact(prior.profiles));H.truthy(c.graph.intact(prior.powers));H.truthy(c.graph.intact(prior.source))
        c.T.unchanged(prior.lookup);c.T.unchanged(prior.map);c.T.unchanged(prior.audit)
        H.equal(c.state._cwv_damage_profile_generation,prior.generation);H.equal(rawget(c.state,"_cwv_wire_fallback_profile_id"),prior.first)
        H.equal(rawget(c.env.Weapons,"shortsword_template"),nil)
    end
    local tags={"generation","fallback","template","audit:profiles","audit:comparisons","audit:failure"}
    for _, name in ipairs(names) do for _, kind in ipairs({"source","profile","numeric","reverse"}) do tags[#tags+1]=kind..":"..name end end
    for _, tag in ipairs(tags) do for _, mode in ipairs({"write","readback"}) do
        local target, edge = tag, mode
        H.test("#428 Shortsword every journal cell rollback "..target.." "..edge,function()
            local seen, prior = false
            local c = new({before=function(context)rawset(context.state,"_cwv_wire_fallback_profile_id",nil)end,
                options=function(options,context)
                    prior=snapshot(context,options)
                    if edge=="write" then options.write=function(t,k,v,label)rawset(t,k,v);if label==target then seen=true;error("attempted-write rejection")end end
                    else options.read=function(t,k,label)if label==target then seen=true;return "rejected"end;return rawget(t,k)end end
                end,after_core=function(context)H.truthy(seen,"journal edge executed");restored(context,prior)end})
            H.truthy(c.owner.check());local _,entry,seed=c.items();H.equal(entry,nil);H.equal(seed,nil)
        end)
    end end
    local function rejected(c)
        H.truthy(c.owner.check());local _,entry,seed=c.items();H.equal(entry,nil);H.equal(seed,nil)
        H.truthy(c.checks.issue428_shortsword_construction())
    end
    H.test("#428 Shortsword foreign-prefix constructor builder seed falsifier",function()
        local foreign, prior
        local c=new({before=function(context)
            foreign={foreign_marker={}};context.env.DamageProfileTemplates.cwv_shortsword_dagger_1h_light_linesman=foreign
        end,options=function(options,context)prior=snapshot(context,options)end,
            after_core=function(context)restored(context,prior)end})
        H.equal(c.env.DamageProfileTemplates.cwv_shortsword_dagger_1h_light_linesman,foreign);rejected(c)
    end)
    local rejects={
        missing_profile=function(c)c.env.DamageProfileTemplates.light_fencer_stab=nil end,
        missing_native_id=function(c)c.lookup.light_fencer_stab=nil end,
        mismatched_pair=function(c)c.lookup[c.lookup.light_fencer_stab]="foreign"end,
        partial_custom_pair=function(c)c.lookup.cwv_shortsword_light_fencer_stab=#c.lookup+1 end,
        foreign_source=function(c)c.state._cwv_damage_profile_wire_source.cwv_shortsword_light_fencer_stab="light_fencer_stab"end,
        foreign_template=function(c)c.env.Weapons.shortsword_template={foreign=true}end,
        invalid_generation=function(c)c.state._cwv_damage_profile_generation=0/0 end,
        invalid_fallback=function(c)c.state._cwv_wire_fallback_profile_id=999999 end,
        malformed_native=function(c)c.env.DamageProfileTemplates.light_fencer_stab={}end,
    }
    for name,alter in pairs(rejects)do H.test("#428 Shortsword exact admission rejects "..name,function()
        local c=new({before=alter});rejected(c)
    end)end
    local races={
        throw=function()error("preparation throws")end, false_result=function()return false end,
        generation=function(c)c.state._cwv_damage_profile_generation=c.state._cwv_damage_profile_generation+1 end,
        fallback=function(c)c.state._cwv_wire_fallback_profile_id=c.lookup.light_fencer_stab end,
        map_root=function(c)c.state._cwv_damage_profile_wire_source={}end,
        profiles_root=function(c)c.env.DamageProfileTemplates={}end,
        powers_root=function(c)c.env.PowerLevelTemplates={}end,
        weapons_root=function(c)c.env.Weapons={}end,
        donor_cell=function(c)c.env.DamageProfileTemplates.light_fencer_stab.default_target.power_distribution.attack=123 end,
        template_source=function(c)c.env.Weapons.one_handed_daggers_template_1.actions.action_two.default.total_time=123 end,
    }
    for name,alter in pairs(races)do H.test("#428 Shortsword preparation race fail closed "..name,function()
        local c=new({owner=function(owner,context)local original=owner.construct;owner.construct=function(prepare)
            return original(function(...)local result=prepare(...);if alter(context)==false then return false end;return result end)
        end end})
        H.equal(c.lookup.cwv_shortsword_light_fencer_stab,nil);rejected(c)
    end)end
    H.test("#428 Shortsword detached clone and scalar/audit failures leave all family cells unmodified",function()
        for _,mode in ipairs({"alias","clone_throw","reader","scalar_throw","audit_false","audit_throw"})do
            local prior
            local c=new({options=function(options,context)
                prior=snapshot(context,options)
                if mode=="alias"then options.clone=function(v)return v end
                elseif mode=="clone_throw"then options.clone=function()error("clone")end
                elseif mode=="reader"then options.profiles=function()error("reader")end
                else local scalar=options.scalar_factory;options.scalar_factory=function(input)
                    if mode=="scalar_throw"then error("scalar")end
                    local planner=scalar(input);planner.append_live_audit_changes=function()if mode=="audit_throw"then error("audit")end;return false end
                    return planner
                end end
            end,after_core=function(context)restored(context,prior)end});rejected(c)
        end
    end)
    local function legacy(c)
        local profile=c.env.DamageProfileTemplates.light_fencer_stab
        c.env.PowerLevelTemplates.review_legacy_default_target=profile.default_target
        profile.default_target="review_legacy_default_target"
    end
    H.test("#428 Shortsword named PowerLevel actual old/new compatibility and retained replacement",function()
        local old,current=new({prior=true,before=legacy}),new({before=legacy})
        H.deep_equal(observed(current),observed(old));H.equal(current.owner.check(),nil)
        local key="cwv_shortsword_review_legacy_default_target"
        H.truthy(current.env.PowerLevelTemplates[key]);current.env.PowerLevelTemplates[key]={}
        rejected(current)
    end)
    H.test("#428 Shortsword prepared legacy destination collision preserves exact foreign cell",function()
        local foreign={power_distribution={attack=999,impact=999}}
        local c=new({before=legacy,owner=function(owner,context)local construct=owner.construct;owner.construct=function(prepare)
            return construct(function(...)local result=prepare(...);context.env.PowerLevelTemplates.cwv_shortsword_review_legacy_default_target=foreign;return result end)
        end end})
        H.equal(c.env.PowerLevelTemplates.cwv_shortsword_review_legacy_default_target,foreign)
        H.equal(c.lookup.cwv_shortsword_light_fencer_stab,nil);rejected(c)
    end)
    for _,edge in ipairs({"write","readback"})do H.test("#428 Shortsword prepared legacy power journal rollback "..edge,function()
        local prior,seen
        local c=new({before=legacy,options=function(options,context)
            prior=snapshot(context,options)
            if edge=="write"then options.write=function(t,k,v,tag)rawset(t,k,v);if tag=="power:cwv_shortsword_review_legacy_default_target"then seen=true;error("power write")end end
            else options.read=function(t,k,tag)if tag=="power:cwv_shortsword_review_legacy_default_target"then seen=true;return false end;return rawget(t,k)end end
        end,after_core=function(context)H.truthy(seen);restored(context,prior)end});rejected(c)
    end)end
    H.test("#428 Shortsword later owned/source/template/root tamper blocks actual fresh admission",function()
        local alters={function(c)c.template.actions.action_one.light_attack_left.damage_profile="shot_sniper"end,
            function(c)c.env.DamageProfileTemplates.cwv_shortsword_light_fencer_stab={}end,
            function(c)c.lookup.cwv_shortsword_light_fencer_stab=1 end,
            function(c)c.state._cwv_damage_profile_wire_source.cwv_shortsword_light_fencer_stab="shot_sniper"end,
            function(c)c.env.DamageProfileTemplates.light_fencer_stab.default_target.power_distribution.attack=123 end,
            function(c)setmetatable(c.env.DamageProfileTemplates,{})end,
            function(c)c.env.Weapons.shortsword_template={}end}
        for _,alter in ipairs(alters)do local c=new();H.equal(c.owner.check(),nil);alter(c);rejected(c)end
    end)
    H.test("#428 Shortsword unrelated later append and prior false audit shape remain accepted",function()
        local c=new({options=function(options)audit(options).failure=false end});H.equal(rawget(c.audit(),"failure"),false)
        local id=#c.lookup+1;c.lookup[id],c.lookup.unrelated="unrelated",id
        c.state._cwv_damage_profile_generation=c.state._cwv_damage_profile_generation+1
        c.state._cwv_damage_profile_wire_source.unrelated="shot_sniper"
        H.equal(c.owner.check(),nil);local _,entry,seed=c.items();H.truthy(entry);H.truthy(seed)
    end)
    H.test("#428 Shortsword canonical career installer allowed foreign prefix extension rejected",function()
        local c=new();local def,entry=c.items();c.env.ItemMasterList[def.item_key]=entry
        local key,value="action_career_review",{default={kind="career_skill"}};c.env.ActionTemplates[key]=value
        local settings={};for _,career in ipairs(entry.can_wield)do settings[career]={activated_ability={{action_name=key}}}end
        local adapter=c.load("_cwv_career_weapon_actions")
        local integration=c.T.run(c.T.read(root.."/tools/shared_lib/_lib_career_weapon_actions.lua"),c.env,"actual-career-integration")
        local effective=c.T.run(c.T.read(root.."/tools/shared_lib/_lib_effective_weapon_templates.lua"),c.env,"actual-effective-template-planner")
        H.truthy(adapter.install({{def=def,entry=entry}},c.env.ItemMasterList,c.env.Weapons,settings,c.env.ActionTemplates,integration,effective,"character_weapon_variants").ok)
        H.equal(c.template.actions[key],value);H.equal(c.owner.check(),nil)
        c.template.actions.action_career_foreign={default={}};rejected(c)
    end)
    H.test("#428 Shortsword private bootstrap captures admission/check by value and saved records untouched",function()
        local c=new({after_item_bind=function(context)
            context.core.shortsword_construction.admit_shortsword=function()return true end
            context.core.shortsword_construction.check_shortsword=function()return nil end
        end})
        local _,entry,seed=c.items();H.truthy(entry);H.truthy(seed)
        local saved={backend_id="persisted-short",mod_data={custom=true}};local raw=c.T.shape(saved);local data=c.T.shape(saved.mod_data)
        c.env.DamageProfileTemplates.cwv_shortsword_light_fencer_stab=nil;rejected(c)
        c.T.unchanged(raw);c.T.unchanged(data)
    end)
    H.test("#428 Shortsword existing foreign master row never overwritten",function()
        local c=new();local row={foreign={}};c.env.ItemMasterList.cwv_es_shortsword=row
        local _,entry,seed=c.items();H.equal(entry,nil);H.equal(seed,nil);H.equal(c.env.ItemMasterList.cwv_es_shortsword,row)
    end)
    H.test("#428 Shortsword private helper graph scalar captures survive later mutable export edits",function()
        local saved={}
        local c=new({owner=function(owner,context)
            saved.register=context.helper.register;context.helper.register=function()error("late helper read")end
            for _,key in ipairs({"capture","intact","disjoint","commit"})do saved[key]=context.graph[key];context.graph[key]=function()error("late graph read")end end
        end,after_core=function(context)
            context.helper.register=saved.register
            for _,key in ipairs({"capture","intact","disjoint","commit"})do context.graph[key]=saved[key]end
        end})
        H.equal(c.owner.check(),nil);local _,entry,seed=c.items();H.truthy(entry);H.truthy(seed)
    end)
    H.test("#428 Shortsword missing private factory or admission handoff never becomes public readiness",function()
        local c=new({after_core=function(context)context.core.shortsword_construction={}end})
        H.truthy(c.template);local _,entry,seed=c.items();H.equal(entry,nil);H.equal(seed,nil)
        H.truthy(c.checks.issue428_shortsword_construction())
    end)
    H.test("#428 Shortsword actual CIM saved exact record remains pending when admission is denied",function()
        local c=new({before=function(context)context.env.DamageProfileTemplates.light_fencer_stab=nil end})
        local def,entry=c.items();H.equal(entry,nil);H.equal(rawget(c.env.ItemMasterList,def.item_key),nil)
        local saved={item_key=def.item_key,via_mirror=true,mod_data={custom="untouched"}};local shape,data=c.T.shape(saved),c.T.shape(saved.mod_data)
        local source=c.T.read(root.."/crafting_in_modded_dev/scripts/mods/crafting_in_modded_dev/crafting_in_modded_dev.lua")
        local a=assert(source:find("local function _athanor_inject_item(weapon_data, backend_id)",1,true))
        local b=assert(source:find("\nlocal _DIRECT_CRAFT_OWNER =",a,true));local inject=source:sub(a,b-1)
        a=assert(source:find("local _pending_inject = {}",b,true))
        b=assert(source:find("\n-- v0.7.28",a,true)or source:find("\nlocal _cim_loadout_restore_timer",a,true))
        local factory=c.T.run("return function(mod,_forge_state)\nlocal _athanor_inject_all\n"..inject.."\n"..source:sub(a,b-1)
            .."\nreturn _athanor_inject_all,_athanor_retry_pending,function()return _pending_inject end end",c.env,"actual-CIM-Shortsword-pending-restore")
        local adds=0;c.env.Managers={backend={get_backend_mirror=function()return{_inventory_items={},add_item=function()adds=adds+1 end}end}}
        local mod={info=function()end,echo=function()end,warning=function()end,get=function()return true end}
        local restore,retry,pending=factory(mod,{get_forged_weapons=function()return{persisted=saved}end})
        restore();retry();H.equal(pending().persisted,saved);H.equal(adds,0)
        c.T.unchanged(shape);c.T.unchanged(data)
    end)
    H.test("#428 Shortsword mandatory complete identity gate wired inside blocking catch before suite",function()
        local file=assert(io.open(root.."/qa/check_lua_unit_tests.ps1","rb"));local source=file:read("*a");file:close();source=source:gsub("\r\n","\n")
        local function wired(text)
            local guard=text:find("$exitCode = 2\ntry {\n",1,true)
            local call=text:find("Assert-ShortswordPriorCoreIdentity -LuaExecutable $luaExe -Exporter $shortswordExporter -Repository (Split-Path -Parent $PSScriptRoot)",1,true)
            local create=text:find("[void][IO.Directory]::CreateDirectory($inventoryRoot)",1,true)
            local suite=text:find("& $luaExe @arguments",1,true)
            return guard and call and create and suite and guard<call and call<create and create<suite
        end
        H.truthy(wired(source));H.truthy(source:find("db221e2396ba9054475ce730cce9880785d47e334ea3b26b8dc3f0bd1a9cb35a",1,true))
        H.truthy(source:find("d9a9b62746679ee6bfd5eefff02213ecb29ac82047d8e1f775ff6f8d3aeeaf53",1,true))
        local disconnected=source:gsub("Assert%-ShortswordPriorCoreIdentity %-LuaExecutable %$luaExe %-Exporter %$shortswordExporter %-Repository %(Split%-Path %-Parent %$PSScriptRoot%)","# disconnected",1)
        H.equal(wired(disconnected),nil)
    end)
    H.test("#428 Shortsword strict prior reconstruction rejects corrupt/missing source hunks",function()
        local read=function(p)local f=assert(io.open(p,"rb"));local s=f:read("*a");f:close();return s end
        local current=read(root.."/character_weapon_variants/scripts/mods/character_weapon_variants/_cwv_core_templates.lua")
        local delta=read(root.."/qa/lua/fixtures/cwv_shortsword_history_prior.reverse.patch")
        H.equal(#F.reconstruct(current,delta),66493)
        H.equal(pcall(F.reconstruct,current,delta:gsub("@@ %-(%d+)","@@ -999999",1)),false)
        H.equal(pcall(F.reconstruct,current,""),false)
    end)
    H.test("#428 Shortsword isolated complete installer preserves host raw/metatable shapes",function()
        -- Capture at test EXECUTION, after the real runner restores require.
        local shape=function(t)local row={target=t,meta=getmetatable(t),cells={}};for k,v in next,t do row.cells[k]=v end;return row end
        local before={shape(_G),shape(table),shape(io),shape(math),shape(package)}
        local c=new();c.items();callbacks(c)
        for _,row in ipairs(before)do c.T.unchanged(row)end
    end)
    return { new=new, observed=observed, rejected=rejected }
end
