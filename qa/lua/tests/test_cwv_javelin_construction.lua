-- #428 exact Javelin installer/profile transaction/admission contracts.
-- Required tracked native inputs and the in-memory reconstructed prior owner;
-- no external checkout, ignored review path or optional green SKIP.
return function(H, root)
    local F = dofile(root .. "/qa/lua/fixtures/cwv_javelin_construction_harness.lua")
    local function new(config) return F.new(H, root, config) end
    local function canonical(value, seen)
        if type(value) == "function" then return "<callback>" end
        if type(value) ~= "table" then return value end
        seen = seen or {}; assert(not seen[value], "fixture graph cycle")
        seen[value] = true
        local result = {}; for key, child in pairs(value) do result[key] = canonical(child, seen) end
        seen[value] = nil; return result
    end
    local function callbacks(c)
        local transcript, count = {}, 0
        for group_name, group in pairs(c.template.actions) do
            if type(group) == "table" then for action_name, action in pairs(group) do
                if type(action) == "table" then for name, callback in pairs(action) do
                    if type(callback) == "function" then
                        local row = {}; count = count + 1
                        if name == "anim_end_event_condition_func" then
                            for _, reason in ipairs({ "new_interupting_action", "action_complete", "interrupted" }) do row[#row + 1] = callback({}, reason) end
                        elseif name == "enter_function" then
                            local input = { reset_release_input = function() row[#row + 1] = "reset"; return "release" end,
                                clear_input_buffer = function() row[#row + 1] = "clear" end }
                            row.result = callback({}, input)
                        elseif name == "condition_func" or name == "chain_condition_func" then
                            row.nil_ammo = callback({}, {}, nil)
                            for _, state in ipairs({ {0,false}, {3,false}, {3,true}, {10,false} }) do
                                local ammo = { total_remaining_ammo = function() return state[1] end,
                                    max_ammo = function() return 10 end, is_reloading = function() return state[2] end }
                                row[#row + 1] = callback({}, {}, ammo)
                            end
                        elseif name == "zoom_condition_function" then row[1] = callback({})
                        elseif name == "unzoom_condition_function" then
                            row[1], row[2], row[3] = callback("exit", nil), callback("exit", {new_action="action_one"}), callback("exit", {new_action="action_two"})
                        else error("native callback must be exercised, not ignored: " .. name) end
                        transcript[group_name .. "." .. action_name .. "." .. name] = row
                    end
                end end
            end end
        end
        H.truthy(count >= 30, "complete native callback closure exercised")
        local recoil = c.template.actions.action_one.throw_charged.recoil_settings
        H.equal(recoil.climb_function, c.env.math.easeInCubic); H.equal(recoil.restore_function, c.env.math.ease_out_quad)
        return transcript
    end
    local function observed(c)
        local profiles, custom_ids = {}, {}
        for _, name in ipairs(c.names) do
            profiles[name] = c.env.DamageProfileTemplates["cwv_tj_" .. name]
            custom_ids[name] = c.lookup["cwv_tj_" .. name]
        end
        local source = {}; for key, value in next, c.state._cwv_damage_profile_wire_source do source[key] = value end
        return { template = canonical(c.template), profiles = canonical(profiles), custom_ids = custom_ids,
            lookup = c.lookup, generation = c.state._cwv_damage_profile_generation, first = c.state._cwv_wire_fallback_profile_id,
            source = source, audit = canonical(c.audit()), donor = canonical(c.env.Weapons.javelin_template),
            callbacks = callbacks(c), packages = c.ledger.packages, wire = c.ledger.wire,
            fenced = c.ledger.fenced_pickup, command = c.commands.cwv_tj_diag and c.commands.cwv_tj_diag.description }
    end
    H.test("#428 Javelin actual complete old new installer math order audit baked cells callbacks equivalent", function()
        local old = new({ prior = true }):install(); local current = new():install()
        H.truthy(old.template); H.truthy(current.template, current.owner.check())
        H.deep_equal(current.audit(),old.audit(),"private live audit contribution preserved")
        H.deep_equal(observed(current), observed(old), "complete healthy producer output and callbacks preserved")
        H.equal(#old.events, 7); H.equal(current.state._cwv_damage_profile_generation - current.before.generation, 7)
        H.equal(current.audit().profiles, 6); H.equal(current.audit().comparisons, 26)
        H.equal(current.template.ammo_data.max_ammo, 10)
        H.equal(current.template.attack_meta_data.minimum_charge_time, 1.1)
        local native = current.env.Weapons.javelin_template
        local thrown = current.template.actions.action_one.throw_charged
        H.equal(thrown.speed, native.actions.action_one.throw_charged.speed * 0.9)
        H.equal(thrown.total_time, native.actions.action_one.throw_charged.total_time * 2)
        H.equal(thrown.lookup_data.item_template_name, "javelin_template", "do not silently refinalize inherited identity")
        H.equal(current.owner.check(), nil)
    end)
    H.test("#428 Javelin preserves earlier live audit failure first fallback and later valid append", function()
        for _, failure in ipairs({ false, "prior-family-failure" }) do
            local function before(c)
                c.core.clone_damage_profile(c.names[1], "cwv_prior_", { damage = 1.25 })
                c.audit().failure = failure
                c.env.Weapons.javelin_template.wield_anim_career_3p = { we_waywatcher = "native", es_mercenary = "prior" }
            end
            local old = new({prior=true,before=before}):install(); local current = new({before=before}):install()
            H.deep_equal(observed(current), observed(old))
            H.equal(rawget(current.audit(), "failure"), failure)
            local id = #current.lookup + 1
            current.lookup[id], current.lookup.unrelated = "unrelated", id
            current.state._cwv_damage_profile_generation = current.state._cwv_damage_profile_generation + 1
            current.state._cwv_damage_profile_wire_source.unrelated = "shot_sniper"
            H.equal(current.owner.check(), nil, "unrelated later producer does not invalidate family proof")
        end
    end)
    local tags = { "generation", "fallback", "template", "preview_root", "audit:profiles", "audit:comparisons", "audit:failure" }
    for _, name in ipairs({ "medium_javelin_smiter_stab", "medium_javelin_smiter_stab_bleed", "heavy_javelin_smiter_stab_bleed", "thrown_javelin" }) do
        for _, kind in ipairs({ "source", "profile", "numeric", "reverse" }) do tags[#tags + 1] = kind .. ":" .. name end
    end
    for _, career in ipairs({ "es_mercenary", "es_huntsman", "es_knight", "es_questingknight", "wh_captain", "wh_bountyhunter", "wh_zealot", "wh_priest" }) do tags[#tags + 1] = "preview:" .. career end
    local function snapshots(c)
        local graph = c.graph
        return { profiles = graph.capture(c.env.DamageProfileTemplates, 8192, 65536),
            lookup = c.T.shape(c.lookup), source = graph.capture(c.env.Weapons.javelin_template, 4096, 32768),
            map = c.T.shape(c.state._cwv_damage_profile_wire_source), levels = c.T.shape(c.env.PowerLevelTemplates),
            audit = c.T.shape(c.audit()), generation = c.state._cwv_damage_profile_generation,
            fallback = rawget(c.state, "_cwv_wire_fallback_profile_id") }
    end
    local function restored(c, before)
        H.truthy(c.graph.intact(before.profiles)); H.truthy(c.graph.intact(before.source))
        c.T.unchanged(before.lookup); c.T.unchanged(before.map); c.T.unchanged(before.levels); c.T.unchanged(before.audit)
        H.equal(c.state._cwv_damage_profile_generation, before.generation)
        H.equal(rawget(c.state, "_cwv_wire_fallback_profile_id"), before.fallback)
        H.equal(rawget(c.env.Weapons, "tuskgor_javelin_template"), nil)
        H.truthy(c.owner.check()); H.equal(c.owner.admit({item_key="cwv_es_javelin",template="tuskgor_javelin_template"}),false)
    end
    for _, tag in ipairs(tags) do for _, mode in ipairs({ "write", "readback" }) do
        local selected, edge = tag, mode
        H.test("#428 Javelin atomic raw rollback " .. selected .. " " .. edge, function()
            local seen, before = false
            local c = new({ before = function(context)
                rawset(context.state, "_cwv_wire_fallback_profile_id", nil)
                setmetatable(context.lookup, {__index={forbidden="inherited"}})
                before = snapshots(context)
            end, options = function(options)
                if edge == "write" then options.write = function(t,k,v,label)
                    rawset(t,k,v); if label==selected then seen=true; error("injected attempted publication") end
                end else options.read = function(t,k,label)
                    if label==selected then seen=true; return "rejected readback" end; return rawget(t,k)
                end end
            end }):install()
            H.truthy(seen, "actual journal edge must execute"); restored(c,before)
        end)
    end end
    H.test("#428 Javelin existing preview cells rollback without replacing their table", function()
        local prior, before
        local c = new({before=function(context)
            prior={es_mercenary="prior",we_waywatcher="native"};context.env.Weapons.javelin_template.wield_anim_career_3p=prior
            before=snapshots(context)
        end,options=function(options)options.write=function(t,k,v,tag)
            rawset(t,k,v);if tag=="audit:failure" then error("last write rejected") end
        end end}):install()
        restored(c,before);H.equal(c.env.Weapons.javelin_template.wield_anim_career_3p,prior)
    end)
    local rejects = {
        missing_profile=function(c)c.env.DamageProfileTemplates[c.names[1]]=nil end,
        missing_native_id=function(c)c.lookup[c.names[1]]=nil end,
        mismatched_pair=function(c)c.lookup[c.lookup[c.names[1]]]="foreign" end,
        partial_pair=function(c)c.lookup["cwv_tj_"..c.names[1]]=#c.lookup+1 end,
        foreign_profile=function(c)c.env.DamageProfileTemplates["cwv_tj_"..c.names[1]]={} end,
        foreign_source=function(c)c.state._cwv_damage_profile_wire_source["cwv_tj_"..c.names[1]]=c.names[1] end,
        foreign_template=function(c)c.env.Weapons.tuskgor_javelin_template={foreign=true} end,
        malformed_native=function(c)c.env.DamageProfileTemplates.thrown_javelin={} end,
        invalid_generation=function(c)c.state._cwv_damage_profile_generation=0/0 end,
        invalid_fallback=function(c)c.state._cwv_wire_fallback_profile_id=999999 end,
        custom_fallback=function(c)c.state._cwv_wire_fallback_profile_id=c.lookup.cwv_old_musket_shot end,
        missing_donor=function(c)c.env.Weapons.javelin_template=nil end,
    }
    for name, alter in pairs(rejects) do
        H.test("#428 Javelin source admission rejects "..name,function()
            local before
            local c=new({before=function(context)alter(context);before={profiles=context.T.shape(context.env.DamageProfileTemplates),lookup=context.T.shape(context.lookup),map=context.T.shape(context.state._cwv_damage_profile_wire_source),template=context.env.Weapons.tuskgor_javelin_template} end}):install()
            H.truthy(c.env.Weapons.tuskgor_javelin_template==before.template,"never newly publish/adopt a rejected template")
            H.truthy(c.owner.check());H.equal(c.owner.admit({item_key="cwv_es_javelin",template="tuskgor_javelin_template"}),false)
            c.T.unchanged(before.profiles);c.T.unchanged(before.lookup);c.T.unchanged(before.map)
            H.equal(c.env.Weapons.tuskgor_javelin_template,before.template,"never adopt/delete a foreign existing template")
        end)
    end
    local prep_failures = {
        error=function()error("prepare failed")end,
        false_result=function()return false end,
        generation=function(c)c.state._cwv_damage_profile_generation=c.state._cwv_damage_profile_generation+1 end,
        fallback=function(c)c.state._cwv_wire_fallback_profile_id=c.lookup[c.names[1]] end,
        map_root=function(c)c.state._cwv_damage_profile_wire_source={} end,
        profile_root=function(c)c.env.DamageProfileTemplates={} end,
        level_root=function(c)c.env.PowerLevelTemplates={} end,
        weapon_root=function(c)c.env.Weapons={} end,
        donor_cell=function(c)c.env.DamageProfileTemplates[c.names[1]].default_target.power_distribution.attack=123 end,
        audit=function(c)c.audit().comparisons=c.audit().comparisons+1 end,
    }
    for name, alter in pairs(prep_failures) do
        H.test("#428 Javelin prepare boundary denies source/audit race "..name,function()
            local c=new({owner=function(owner,context)
                local construct=owner.construct
                owner.construct=function(prepare,wields)return construct(function(...)
                    local result=prepare(...);local changed=alter(context)
                    if changed==false then return false end;return result
                end,wields)end
            end}):install()
            H.truthy(c.owner.check());H.equal(c.owner.admit({item_key="cwv_wh_javelin",template="tuskgor_javelin_template"}),false)
            H.equal(rawget(c.lookup,"cwv_tj_thrown_javelin"),nil)
        end)
    end
    H.test("#428 Javelin aliasing clone and throwing roots deny without source mutation",function()
        for _,kind in ipairs({"alias","throw","reader"})do
            local before
            local c=new({before=function(context)before=snapshots(context)end,options=function(options)
                if kind=="alias"then options.clone=function(v)return v end
                elseif kind=="throw"then options.clone=function()error("clone failed")end
                else options.profiles=function()error("root unreadable")end end
            end}):install()
            restored(c,before)
        end
    end)
    H.test("#428 Javelin private actual builder and seed admit both exact keys and retain by-value authority",function()
        local c=new({after_bind=function(context)
            context.runtime.admit_javelin=function()return true end
            context.runtime.check_javelin=function()return nil end
        end}):install()
        local defs,build,checks=c.items();H.equal(checks.issue428_tuskgor_javelin_construction(),nil)
        for _,def in ipairs(defs)do
            local entry=assert(build(def));H.equal(entry.template,def.template)
            local seed=assert(c.mod._cwv_acquisition.build_seed(def,build,function(v)return c.env.table.clone(v,true)end,function()return false end))
            H.equal(seed.mod_data.power_level,5)
        end
        local saved={backend_id="persisted-user-item",value="untouched"};c.state.saved_exact=saved
        c.env.DamageProfileTemplates.cwv_tj_thrown_javelin=nil
        for _,def in ipairs(defs)do
            if def.item_key=="cwv_es_musket_old"then H.truthy(build(def),"Old Musket unaffected")
            else
                H.equal(build(def),nil);H.equal(c.mod._cwv_acquisition.build_seed(def,build,function(v)return c.env.table.clone(v,true)end,function()return false end),nil)
            end
        end
        H.truthy(checks.issue428_tuskgor_javelin_construction());H.equal(c.state.saved_exact,saved);H.equal(saved.value,"untouched")
    end)
    H.test("#428 Javelin current managed template profile pair and preview tamper deny fresh admission",function()
        local changes={
            function(c)c.env.Weapons.tuskgor_javelin_template={}end,
            function(c)c.template.actions.action_one.stab_01.damage_profile="shot_sniper"end,
            function(c)c.lookup.cwv_tj_thrown_javelin=1 end,
            function(c)c.env.DamageProfileTemplates.cwv_tj_thrown_javelin.default_target.power_distribution_near.attack=7 end,
            function(c)c.env.Weapons.javelin_template.wield_anim_career_3p.es_mercenary="foreign"end,
        }
        for _,change in ipairs(changes)do
            local c=new():install();H.equal(c.owner.check(),nil);change(c)
            H.truthy(c.owner.check());H.equal(c.owner.admit({item_key="cwv_es_javelin",template="tuskgor_javelin_template"}),false)
        end
    end)
    H.test("#428 Javelin exact canonical career extension allowed foreign prefix extension rejected",function()
        local c=new():install();local defs,build=c.items();local def
        for _,row in ipairs(defs)do if row.item_key=="cwv_es_javelin"then def=row end end
        local entry=assert(build(def));c.env.ItemMasterList[def.item_key]=entry
        local value={default={kind="career_skill"}};local key="action_career_test"
        c.env.ActionTemplates[key]=value
        local settings={};for _,career in ipairs(entry.can_wield)do settings[career]={activated_ability={{action_name=key}}}end
        local adapter=c.load("_cwv_career_weapon_actions")
        local integration=c.T.run(c.T.read(root.."/tools/shared_lib/_lib_career_weapon_actions.lua"),c.env,"actual-career-integration")
        local effective=c.T.run(c.T.read(root.."/tools/shared_lib/_lib_effective_weapon_templates.lua"),c.env,"actual-effective-template-planner")
        local report=adapter.install({{def=def,entry=entry}},c.env.ItemMasterList,c.env.Weapons,settings,c.env.ActionTemplates,integration,effective,"character_weapon_variants")
        H.truthy(report.ok);H.equal(report.template_count,1);H.equal(c.template.actions[key],value)
        H.equal(c.owner.check(),nil)
        c.template.actions.action_career_foreign={kind="career_skill"};H.truthy(c.owner.check())
    end)
    H.test("#428 Javelin manifest binds helper graph scalar and admission by value",function()
        local c=new({options=function(_,context)
            context.capsule.network_lookup.register=function()error("mutable helper reread")end
            for _,name in ipairs({"capture","intact","disjoint","commit"})do context.graph[name]=function()error("mutable mechanics reread")end end
            context.core.detached_scalar_factory=function()error("mutable core factory reread")end
        end}):install()
        H.equal(c.owner.check(),nil);H.truthy(c.template)
    end)
    H.test("#428 Javelin retained preview captures values not mutable policy or foreign metatable",function()
        local policy
        local c=new({owner=function(owner)
            local construct=owner.construct
            owner.construct=function(prepare,wields)policy=wields;return construct(prepare,wields)end
        end}):install()
        policy.es_mercenary="foreign policy edit"
        H.equal(c.owner.check(),nil,"retained committed values do not reread mutable preparation policy")
        setmetatable(c.env.Weapons.javelin_template.wield_anim_career_3p,{__index=function()error("foreign preview reader")end})
        H.truthy(c.owner.check(),"changed preview metatable is not authority")
    end)
    H.test("#428 Javelin actual CIM restore preserves rejected exact saved records pending",function()
        local c=new({before=function(context)context.env.DamageProfileTemplates.thrown_javelin=nil end}):install()
        local defs,build=c.items();local def
        for _,row in ipairs(defs)do if row.item_key=="cwv_es_javelin"then def=row end end
        H.equal(build(def),nil);H.equal(rawget(c.env.ItemMasterList,def.item_key),nil)
        local saved={item_key=def.item_key,via_mirror=true,mod_data={custom="unchanged"},untouched={}}
        local shape,md=c.T.shape(saved),c.T.shape(saved.mod_data)
        local source=c.T.read(root.."/crafting_in_modded_dev/scripts/mods/crafting_in_modded_dev/crafting_in_modded_dev.lua")
        local a=assert(source:find("local function _athanor_inject_item(weapon_data, backend_id)",1,true))
        local b=assert(source:find("\nlocal _DIRECT_CRAFT_OWNER =",a,true));local inject=source:sub(a,b-1)
        a=assert(source:find("local _pending_inject = {}",b,true))
        b=assert(source:find("\n-- v0.7.28",a,true)or source:find("\nlocal _cim_loadout_restore_timer",a,true))
        local factory=c.T.run("return function(mod,_forge_state)\nlocal _athanor_inject_all\n"..inject.."\n"..source:sub(a,b-1)
            .."\nreturn _athanor_inject_all,_athanor_retry_pending,function()return _pending_inject end end",c.env,"actual-CIM-Javelin-missing-master-restore")
        local adds=0;c.env.Managers={backend={get_backend_mirror=function()return{_inventory_items={},add_item=function()adds=adds+1 end}end}}
        local mod={info=function()end,echo=function()end,warning=function()end,get=function()return true end}
        local restore,retry,pending=factory(mod,{get_forged_weapons=function()return{persisted=saved}end})
        restore();retry();H.equal(pending().persisted,saved);H.equal(adds,0)
        c.T.unchanged(shape);c.T.unchanged(md);H.truthy(mod._cim_restore_failures.persisted:find("not in ItemMasterList",1,true))
    end)
    H.test("#428 Javelin complete installed existing init keeps native Outrider and Javelin last-writer boundaries",function()
        local c=new():install();local om,env=c.state,c.env
        local donor={speed=1,impact_data={damage_profile="shot_sniper"},projectile_info={kind="donor"}}
        local tuned={speed=2,impact_data={damage_profile="cwv_musket_shot"},projectile_info={kind="grenade"}}
        env.Weapons.outrider_grenade_launcher_template={actions={action_one={default=tuned}}}
        env.ItemMasterList.launcher_base={template="launcher_donor"}
        om.variant_catalog={definitions={{item_key="cwv_es_outrider_grenade_launcher",base_weapon="launcher_base",template="outrider_grenade_launcher_template"}}}
        local slot={master_item={name="launcher_base"},skin="plain"}
        env.ScriptUnit={has_extension=function()return{equipment=function()return{wielded_slot="slot_ranged"}end,get_slot_data=function()return slot end}end}
        om._cwv_key_for_item=function()return"cwv_es_outrider_grenade_launcher"end
        local hook=assert(c.hooks["PlayerProjectileUnitExtension:init"])
        local projectile={_current_action=donor,action_lookup_data={action_name="action_one",sub_action_name="default"}}
        hook(projectile,{}, {},{item_name="launcher_base",owner_unit={}})
        H.equal(projectile._current_action,tuned);H.equal(projectile._impact_data,tuned.impact_data)
        H.equal(projectile._impact_damage_profile_id,c.lookup.cwv_musket_shot)
        om._cwv_key_for_item=function()return nil end;om._cwv_renamed_template_overrides=nil
        slot={master_item={name="we_javelin"},skin="native_javelin"}
        local elf={_current_action=donor,action_lookup_data={action_name="action_one",sub_action_name="throw_charged"}}
        hook(elf,{}, {},{item_name="we_javelin",owner_unit={}});H.equal(elf._current_action,donor)
        slot.skin="cwv_es_javelin_skin"
        hook(elf,{}, {},{item_name="we_javelin",owner_unit={}})
        H.equal(elf._current_action,c.template.actions.action_one.throw_charged)
        H.equal(elf._impact_damage_profile_id,c.lookup.cwv_tj_thrown_javelin)
    end)
    H.test("#428 Javelin mandatory identity gate remains before ordinary suite and disconnected call rejects",function()
        local file=assert(io.open(root.."/qa/check_lua_unit_tests.ps1","rb"));local source=file:read("*a");file:close()
        local function wired(text)
            text = text:gsub("\r\n", "\n")
            local guard = text:find("$exitCode = 2\ntry {\n", 1, true)
            local create = text:find("[void][IO.Directory]::CreateDirectory($inventoryRoot)", 1, true)
            local call=text:find("Assert-JavelinPriorRuntimeIdentity -LuaExecutable $luaExe -Exporter $exporter -Repository (Split-Path -Parent $PSScriptRoot)",1,true)
            local suite=text:find("& $luaExe @arguments",1,true)
            return guard and call and create and suite and guard<call and call<create and create<suite
        end
        H.truthy(wired(source));H.truthy(source:find("if (-not $SelfTest) {",1,true))
        H.truthy(source:find("09f5ff3e8378bb9ef81780e69f6b410a09be3ad72dcad01f13bdd3ba07608d92",1,true))
        local disconnected=source:gsub("Assert%-JavelinPriorRuntimeIdentity %-LuaExecutable %$luaExe %-Exporter %$exporter %-Repository %(Split%-Path %-Parent %$PSScriptRoot%)","# disconnected actual preflight call",1)
        H.equal(wired(disconnected),nil)
    end)
    local function legacy(c)
        for _,name in ipairs({c.names[1],c.names[2],c.names[3]})do
            local profile=c.env.DamageProfileTemplates[name]
            for _,field in ipairs({"cleave_distribution","default_target","targets"})do
                local key="javelin_legacy_"..name.."_"..field
                c.env.PowerLevelTemplates[key],profile[field]=profile[field],key
            end
        end
    end
    H.test("#428 Javelin named-reference compatibility uses same legacy scalar math and live audit",function()
        local old=new({prior=true,before=legacy}):install();local current=new({before=legacy}):install()
        H.truthy(current.template,current.owner.check());H.deep_equal(observed(current),observed(old))
        H.deep_equal(current.env.PowerLevelTemplates,old.env.PowerLevelTemplates)
    end)
    for _,mode in ipairs({"write","readback"})do
        local selected=mode
        H.test("#428 Javelin named-reference power publication rollback "..selected,function()
            local before,seen
            local c=new({before=function(context)legacy(context);before=snapshots(context)end,options=function(options)
                if selected=="write"then options.write=function(t,k,v,tag)
                    rawset(t,k,v);if tag:sub(1,6)=="power:"then seen=true;error("power write failed")end
                end else options.read=function(t,k,tag)
                    if tag:sub(1,6)=="power:"then seen=true;return "bad readback"end;return rawget(t,k)
                end end
            end}):install()
            H.truthy(seen);restored(c,before)
        end)
    end
    local function named_default(context)
        local profile = context.env.DamageProfileTemplates[context.names[1]]
        context.env.PowerLevelTemplates.review_legacy_default_target = profile.default_target
        profile.default_target = "review_legacy_default_target"
    end
    H.test("#428 Javelin prepare-time power collision denies both real items", function()
        for _, foreign in ipairs({ false, { power_distribution = { attack = 999, impact = 999 } } }) do
            local key = "cwv_tj_review_legacy_default_target"
            local generation, lookup_count, first
            local c = new({ before = function(context)
                generation, lookup_count = context.state._cwv_damage_profile_generation, #context.lookup
                first = rawget(context.state, "_cwv_wire_fallback_profile_id")
                named_default(context)
            end, owner = function(owner, context)
                local construct = owner.construct
                owner.construct = function(prepare, wields)
                    return construct(function(...)
                        local result = prepare(...)
                        context.env.PowerLevelTemplates[key] = foreign
                        return result
                    end, wields)
                end
            end }):install()
            H.equal(rawget(c.env.PowerLevelTemplates, key), foreign, "never overwrite intervening foreign destination")
            H.equal(c.template, nil); H.truthy(c.owner.check())
            H.equal(#c.lookup, lookup_count); H.equal(c.state._cwv_damage_profile_generation, generation)
            H.equal(rawget(c.state, "_cwv_wire_fallback_profile_id"), first)
            local definitions, build = c.items()
            for _, definition in ipairs(definitions) do
                if definition.item_key == "cwv_es_javelin" or definition.item_key == "cwv_wh_javelin" then
                    H.equal(c.owner.admit(definition), false); H.equal(build(definition), nil)
                end
            end
            for _, name in ipairs(c.names) do
                H.equal(rawget(c.env.DamageProfileTemplates, "cwv_tj_" .. name), nil)
                H.equal(rawget(c.lookup, "cwv_tj_" .. name), nil)
                H.equal(rawget(c.state._cwv_damage_profile_wire_source, "cwv_tj_" .. name), nil)
            end
        end
    end)
    H.test("#428 Javelin named power retains exact object and rejects replacement", function()
        local key = "cwv_tj_review_legacy_default_target"
        local written, writes = nil, 0
        local c = new({ before = named_default, options = function(options)
            options.write = function(target, cell, value, tag)
                if cell == key and tag == "power:" .. key then written, writes = value, writes + 1 end
                rawset(target, cell, value)
            end
        end }):install()
        H.truthy(c.template, c.owner.check()); H.equal(c.owner.check(), nil)
        local selected = c.env.DamageProfileTemplates.cwv_tj_medium_javelin_smiter_stab
        H.equal(selected.default_target, key)
        local committed = assert(rawget(c.env.PowerLevelTemplates, key))
        H.equal(writes, 1, "prepared destination is always journaled once")
        H.equal(committed, written, "retained proof pins the exact journaled object")
        local replacement = c.env.table.clone(committed, true)
        H.deep_equal(replacement, committed)
        c.env.PowerLevelTemplates[key] = replacement
        H.truthy(c.owner.check(), "equal-shaped foreign objects are not committed identity")
        H.equal(c.owner.admit({ item_key = "cwv_es_javelin", template = "tuskgor_javelin_template" }), false)
        H.equal(rawget(c.env.PowerLevelTemplates, key), replacement)
    end)
    H.test("#428 Javelin late power collision rolls back without erasing foreign", function()
        local key, foreign, injected = "cwv_tj_review_legacy_default_target", {}, false
        local c = new({ before = named_default, options = function(options, context)
            options.write = function(target, cell, value, tag)
                rawset(target, cell, value)
                if not injected then injected = true; context.env.PowerLevelTemplates[key] = foreign end
            end
        end }):install()
        H.truthy(injected); H.equal(c.template, nil); H.equal(rawget(c.env.PowerLevelTemplates, key), foreign)
        H.truthy(c.owner.check())
        for _, name in ipairs(c.names) do H.equal(rawget(c.env.DamageProfileTemplates, "cwv_tj_" .. name), nil) end
    end)
    H.test("#428 Javelin reverse source delta rejects missing corruption and numeric drift",function()
        local file=assert(io.open(root.."/character_weapon_variants/scripts/mods/character_weapon_variants/_cwv_javelin_runtime_owner.lua","rb"))
        local source=file:read("*a");file:close()
        local deltafile=assert(io.open(root.."/qa/lua/fixtures/cwv_javelin_construction_prior.reverse.patch","rb"))
        local delta=deltafile:read("*a");deltafile:close()
        H.truthy(#F.reconstruct(source,delta)>80000)
        H.equal(pcall(F.reconstruct,source,""),false)
        H.equal(pcall(F.reconstruct,source,delta:gsub("@@ %-(%d+)","@@ -999999",1)),false)
        local at=assert(delta:find("\n-",1,true))
        local line_end=assert(delta:find("\n",at+2,true))
        local corrupt=delta:sub(1,at+1).."corrupted consumed preimage"..delta:sub(line_end)
        H.equal(pcall(F.reconstruct,source,corrupt),false)
    end)
    H.test("#428 Javelin complete private fixture preserves host raw global and metatable shapes",function()
        local saved={}
        for _,target in ipairs({_G,table,math,io,os,package,package.loaded,arg})do
            local row={target=target,meta=getmetatable(target),cells={}}
            for key,value in next,target do row.cells[key]=value end
            saved[#saved+1]=row
        end
        local c=new():install();c.items();H.equal(c.owner.check(),nil)
        for _,row in ipairs(saved)do
            H.equal(getmetatable(row.target),row.meta)
            for key,value in next,row.cells do H.equal(rawget(row.target,key),value,"host prior raw field preserved")end
            for key,value in next,row.target do H.equal(rawget(row.cells,key),value,"no introduced host raw field")end
        end
    end)
end
