-- Detached real-module tests: no game units, flags, settings, RPC or global writes.
local function register(H, root)
    local function read(path)
        local file=assert(io.open(path,"rb"));local text=file:read("*a");file:close();return text
    end
    local function named_registration(entry)
        local at=assert(entry:find('_rt_register("issue1436_historical_weapon_patch_versions"',1,true))
        local open=assert(entry:find("(",at,true))
        return "_rt_register"..assert(entry:sub(open):match("^%b()"))
    end
    local function copy(value)
        if type(value)~="table" then return value end
        local result={};for k,v in next,value do result[k]=copy(v) end;return result
    end
    local function raw_shape(value)
        local fields={};for k,v in next,value do fields[k]=v end
        return {fields=fields,meta=getmetatable(value)}
    end
    local function assert_shape(value,before)
        H.equal(getmetatable(value),before.meta)
        for k,v in next,before.fields do H.equal(rawget(value,k),v,"restored raw field "..tostring(k)) end
        for k in next,value do H.truthy(rawget(before.fields,k)~=nil,"unexpected raw field "..tostring(k)) end
    end
    local function fixture(stream, options)
        options=options or {};stream=stream or "weapon_tweaker"
        local prefix=root.."/"..stream.."/scripts/mods/"..stream.."/"
        local env={};env._G=env;setmetatable(env,{__index=_G})
        local modules={};local calls={};local mod={}
        local function load(name)
            if modules[name]==nil or options.fresh_dofile then
                local chunk=assert(loadfile(prefix..name..".lua"));setfenv(chunk,env)
                local loaded=chunk()
                if options.fresh_dofile then return loaded end
                modules[name]=loaded
            end
            return modules[name]
        end
        function mod:dofile(path)
            local name=assert(path:match("([^/]+)$"));calls[#calls+1]=name
            if options.catalog_failure and name=="_wt_history_catalog" then
                return {load=function() return nil,"catalog unavailable" end}
            end
            return load(name)
        end
        local catalog=assert(load("_wt_history_catalog").load(mod))
        local natives={}
        for _,specs in pairs(catalog.profile_specs) do for native in pairs(specs) do natives[native]=true end end
        for _,specs in pairs(catalog.derived_profiles) do for native in pairs(specs) do natives[native]=true end end
        local names={};for name in pairs(natives) do names[#names+1]=name end;table.sort(names)
        local profiles,lookup={},{}
        for index,name in ipairs(names) do
            profiles[name]={native_marker=name,default_target={power_distribution={attack=3,impact=1}}}
            lookup[index],lookup[name]=name,index
        end
        local strict={__index=function(_,key) error("native strict missing "..tostring(key)) end}
        setmetatable(lookup,strict)
        env.DamageProfileTemplates,env.NetworkLookup=profiles,{damage_profiles=lookup}
        env.PowerLevelTemplates={sentinel={untouched=true}}
        env.Weapons={};env.BuffTemplates={};env.ExplosionTemplates={}
        env.PlayerUnitStatusSettings={};env.VortexTemplates={};env.printf=function() end
        env.Managers={player={is_server=true}}
        function mod:get(key) if options.get then return options.get(key,env,mod) end;return "current" end
        mod._wt431_profiles_allowed=function() return options.parity~=false end
        local transaction=load("_wt_history_profile_transaction")
        local helper=load("_lib_network_lookup")
        local policy=load("_wt_history_policy")
        local runtime=load("_wt_history_runtime")
        local f={env=env,mod=mod,catalog=catalog,profiles=profiles,lookup=lookup,calls=calls,
            helper=helper,transaction=transaction,policy=policy,runtime_module=runtime,load=load,prefix=prefix}
        function f.install(deps)
            deps=deps or {};deps.globals=env;deps.lookup=deps.lookup or helper
            return runtime.install({mod=mod,catalog=catalog,policy=policy,
                profile_transaction=transaction,profile_dependencies=deps,
                roots={Weapons=env.Weapons,BuffTemplates={},ExplosionTemplates={},PlayerUnitStatusSettings={},VortexTemplates={}}})
        end
        function f.owner() return load("_wt_history_owner").install({mod=mod,module_root="scripts/mods/"..stream.."/",
            profile_transaction=transaction,profile_dependencies={lookup=helper}}) end
        function f.expected()
            local result={}
            for _,specs in pairs(catalog.profile_specs) do for _,spec in pairs(specs) do result[#result+1]=spec.private_name end end
            for _,specs in pairs(catalog.derived_profiles) do for _,spec in pairs(specs) do result[#result+1]=spec.private_name end end
            table.sort(result);return result
        end
        return f
    end

    H.test("WT #428 actual history owner repeats without assuming VMF dofile singleton",function()
        local f=fixture(nil,{fresh_dofile=true})
        -- Retain the one actual owning module, as the original entry does.
        local owner_module=f.load("_wt_history_owner")
        local first,verify=owner_module.install({mod=f.mod,module_root="scripts/mods/weapon_tweaker/",
            profile_transaction=f.transaction,profile_dependencies={lookup=f.helper}})
        H.equal(verify(),nil);local before=#f.lookup
        local second,second_verify=owner_module.install({mod=f.mod,module_root="scripts/mods/weapon_tweaker/",
            profile_transaction=f.transaction,profile_dependencies={lookup=f.helper}})
        H.equal(second,first);H.equal(second_verify,verify);H.equal(#f.lookup,before)
    end)


    for _,stream in ipairs({"weapon_tweaker","weapon_tweaker_dev"}) do
        H.test("WT #428 entry owns new dependencies once and keeps named slot "..stream,function()
            local f=fixture(stream,{fresh_dofile=true})
            local initial_calls=#f.calls
            local entry=read(f.prefix..stream..".lua")
            local declaration=assert(entry:match('(local _wt_history_owner.-)\n%-%- Bret Sword'))
            local callback=named_registration(entry)
            local check_at=assert(entry:find(callback,1,true))
            local prior_at=assert(entry:find("_wt_runtime_checks.install(mod, _rt_register",1,true))
            H.truthy(prior_at<check_at,"named history check must retain its post-runtime-checks slot")
            local phase="manifest"
            local named
            f.env.mod=f.mod
            f.env._rt_register=function(name,fn)
                H.equal(phase,"checks","history installation must not register the check early")
                H.equal(name,"issue1436_historical_weapon_patch_versions")
                H.equal(named,nil,"named check must register once")
                named=fn
            end
            local code=declaration.."\nreturn function()\n"..callback.."\nend"
            local chunk=assert(loadstring(code));setfenv(chunk,f.env)
            local register_check=chunk()
            H.equal(named,nil)
            -- Fixture preparation and legacy catalog child loads are not new History dependencies.
            local owned_calls={}
            local names={_wt_history_owner=true,_wt_history_profile_transaction=true,_lib_network_lookup=true,
                _wt_history_catalog=true,_wt_history_policy=true,_wt_history_runtime=true}
            for i=initial_calls+1,#f.calls do
                if names[f.calls[i]] then owned_calls[#owned_calls+1]=f.calls[i] end
            end
            H.deep_equal(owned_calls,{"_wt_history_owner","_wt_history_profile_transaction","_lib_network_lookup",
                "_wt_history_catalog","_wt_history_policy","_wt_history_runtime"})
            phase="checks";register_check()
            H.equal(type(named),"function");H.equal(named(),nil)
            local runtime=f.mod._wt_history_runtime
            f.profiles[f.expected()[19]]={name="foreign"}
            runtime.verify=function() return nil end
            f.mod._wt_history_runtime={verify=function() return nil end}
            H.truthy(named(),"late public-method replacement must not forge the retained private check")
        end)

        H.test("WT #428 captured named wrapper preserves missing-runtime verdict "..stream,function()
            local f=fixture(stream,{catalog_failure=true})
            local entry=read(f.prefix..stream..".lua")
            local declaration=assert(entry:match('(local _wt_history_owner.-)\n%-%- Bret Sword'))
            local callback=named_registration(entry)
            local named;f.env.mod=f.mod;f.env._rt_register=function(_,fn) named=fn end
            local chunk=assert(loadstring(declaration.."\n"..callback));setfenv(chunk,f.env);chunk()
            f.mod._wt_history_runtime={verify=function() return nil end}
            H.equal(type(named),"function")
            H.equal(named(),"#1436: historical weapon runtime was not installed")
        end)
    end

    for _,stream in ipairs({"weapon_tweaker","weapon_tweaker_dev"}) do
        H.test("WT #428 entry rejects pre-check-install public method forgery "..stream,function()
            local changed=false
            local f=fixture(stream,{get=function(_,env,mod)
                if not changed then
                    changed=true
                    for name,profile in pairs(env.DamageProfileTemplates) do
                        if name:match("^wt_hist_") then env.DamageProfileTemplates[name]=copy(profile);break end
                    end
                    mod._wt_history_runtime={verify=function() return nil end}
                end
                return "current"
            end})
            local entry=read(f.prefix..stream..".lua")
            local declaration=assert(entry:match('(local _wt_history_owner.-)\n%-%- Bret Sword'))
            local callback=named_registration(entry)
            local checks={};f.env.mod=f.mod;f.env._rt_register=function(name,fn) checks[name]=fn end
            local chunk=assert(loadstring(declaration.."\n"..callback));setfenv(chunk,f.env);chunk()
            f.mod._wt_history_runtime.verify=function() return nil end
            H.truthy(assert(checks.issue1436_historical_weapon_patch_versions)())
        end)
    end

    for _,stream in ipairs({"weapon_tweaker","weapon_tweaker_dev"}) do
        H.test("WT #428 history actual composition publishes exact sorted19 "..stream,function()
            local f=fixture(stream);local before=#f.lookup
            local native_before=copy(f.profiles);local plt=f.env.PowerLevelTemplates
            local owner,verify=f.owner();local runtime=assert(owner.runtime)
            H.equal(runtime.fatal_error,nil);H.equal(type(verify),"function");H.equal(verify(),nil)
            H.equal(runtime.registration.count,19);H.equal(#f.lookup,before+19)
            H.deep_equal(runtime.registration.names,f.expected())
            for index,name in ipairs(f.expected()) do
                H.equal(f.lookup[before+index],name);H.equal(f.lookup[name],before+index)
                H.equal(f.profiles[name].name,name)
                local fallback=f.mod._wt431_custom_profile_fallback[name]
                H.truthy(native_before[fallback]);H.deep_equal(f.profiles[fallback],native_before[fallback])
            end
            H.equal(f.env.PowerLevelTemplates,plt);H.deep_equal(plt,{sentinel={untouched=true}})
            H.equal(next(runtime.ledgers),nil,"Current must create no gameplay ledger")
            local first={};for _,name in ipairs(f.expected()) do first[name]=f.profiles[name] end
            local again,again_verify=f.install();H.equal(again.fatal_error,nil);H.equal(again_verify(),nil)
            for name,profile in pairs(first) do H.equal(f.profiles[name],profile) end
            H.equal(#f.lookup,before+19)
            H.equal(f.mod._wt_history_runtime,runtime,"composition exports its first-return runtime")
        end)

        H.test("WT #428 actual entry captures trusted history verification "..stream,function()
            local f=fixture(stream)
            local entry=read(f.prefix..stream..".lua")
            H.truthy(loadstring(entry,"@complete-"..stream),"complete entry must compile under Lua5.1 local limit")
            local declaration=assert(entry:match('(local _wt_history_owner.-)\n%-%- Bret Sword'))
            local callback=named_registration(entry)
            local checks={};f.env.mod=f.mod;f.env._rt_register=function(name,fn) checks[name]=fn end
            local chunk=assert(loadstring(declaration.."\n"..callback));setfenv(chunk,f.env);chunk()
            local named=assert(checks.issue1436_historical_weapon_patch_versions)
            H.equal(named(),nil)
            local runtime=f.mod._wt_history_runtime
            local name=f.expected()[19];f.profiles[name]={name=name}
            runtime.verify=function() return nil end
            H.truthy(named(),"forged mutable runtime.verify must not forge named success")
            H.truthy(runtime:reapply()==nil,"reapply must not use corrupted tuple")
        end)
    end

    for _,failure in ipairs({"throw","discard","proxy"}) do
        for at=1,77 do
            H.test("WT #428 history exact batch rollback "..failure.." write"..at,function()
                local f=fixture();local fallback={unrelated=false}
                if at~=77 then f.mod._wt431_custom_profile_fallback=fallback end
                local targets={f.profiles,f.lookup,fallback,f.mod};local before={}
                for index,target in ipairs(targets) do before[index]=raw_shape(target) end
                local count=0
                local runtime=f.install({write=function(target,key,value)
                    count=count+1
                    if count==at then
                        if failure=="throw" then error("injected writer failure") end
                        if failure=="discard" then return end
                        if failure=="proxy" then setmetatable(target,{__index=function() return value end});return end
                    end
                    rawset(target,key,value)
                end})
                H.truthy(runtime.fatal_error,"fault at reachable write must fail closed")
                H.equal(count>=at,true)
                for index,target in ipairs(targets) do assert_shape(target,before[index]) end
                H.equal(next(runtime.ledgers),nil)
            end)
        end
    end

    for _,at in ipairs({1,5,73}) do
        H.test("WT #428 history profile content readback write"..at,function()
            local f=fixture();local a,b,c=raw_shape(f.profiles),raw_shape(f.lookup),raw_shape(f.mod)
            local count=0;local runtime=f.install({write=function(target,key,value)
                count=count+1;rawset(target,key,value)
                if count==at then value.default_target="corrupt" end
            end})
            H.truthy(runtime.fatal_error);assert_shape(f.profiles,a);assert_shape(f.lookup,b);assert_shape(f.mod,c)
        end)
    end

    local corruptions={
        sparse=function(f) f.lookup[#f.lookup+2]="hole";f.lookup.hole=#f.lookup end,
        half=function(f) f.lookup.foreign=900 end,
        zero=function(f) f.lookup[0]="foreign" end,
        foreign_profile=function(f) f.profiles[f.expected()[1]]={name=f.expected()[1]} end,
        foreign_pair=function(f) local name=f.expected()[1];local at=#f.lookup+1;f.lookup[at]=name;f.lookup[name]=at end,
        foreign_fallback=function(f) f.mod._wt431_custom_profile_fallback={[f.expected()[1]]="native"} end,
        malformed_fallback=function(f) f.mod._wt431_custom_profile_fallback=false end,
    }
    for name,corrupt in pairs(corruptions) do
        H.test("WT #428 history rejects before publication "..name,function()
            local f=fixture();corrupt(f)
            local a,b,c=raw_shape(f.profiles),raw_shape(f.lookup),raw_shape(f.mod)
            local runtime=f.install();H.truthy(runtime.fatal_error)
            assert_shape(f.profiles,a);assert_shape(f.lookup,b);assert_shape(f.mod,c)
        end)
    end

    for _,axis in ipairs({"profile","lookup-number","lookup-string","fallback","mapping","names","root","metatable","primitive"}) do
        H.test("WT #428 history retained verifier rejects "..axis,function()
            local f=fixture();local runtime,verify=f.install();H.equal(verify(),nil)
            local name=f.expected()[9];local index=f.lookup[name]
            if axis=="profile" then f.profiles[name]=copy(f.profiles[name])
            elseif axis=="lookup-number" then f.lookup[index]="other"
            elseif axis=="lookup-string" then f.lookup[name]=1
            elseif axis=="fallback" then f.mod._wt431_custom_profile_fallback[name]="other"
            elseif axis=="mapping" then runtime.registration.private_by_state_name={}
            elseif axis=="names" then runtime.registration.names={}
            elseif axis=="root" then f.env.NetworkLookup={damage_profiles=f.lookup}
            elseif axis=="metatable" then setmetatable(f.lookup,{})
            else f.helper.register=function() return index,false end end
            runtime.verify=function() return nil end
            H.truthy(verify());H.equal(runtime:reapply(),nil)
            local repeated=f.install();H.truthy(repeated.fatal_error)
        end)
    end

    H.test("WT #428 history content tuning is not publication identity tamper",function()
        local f=fixture();local runtime,verify=f.install()
        f.profiles[f.expected()[1]].ordinary_tuning={attack=1.15}
        H.equal(verify(),nil);H.equal(runtime:reapply().refused,0)
        local again,again_verify=f.install();H.equal(again.fatal_error,nil);H.equal(again_verify(),nil)
    end)

    for _,fault in ipairs({false,true}) do
        H.test("WT #428 protected original metatable retained fault="..tostring(fault),function()
            local f=fixture();setmetatable(f.profiles,{__metatable="protected-original"})
            local before=raw_shape(f.profiles)
            local runtime,verify=f.install({write=function(target,key,value)
                if fault and target==f.lookup then error("late protected rollback") end
                rawset(target,key,value)
            end})
            if fault then H.truthy(runtime.fatal_error);assert_shape(f.profiles,before)
            else H.equal(verify(),nil);H.equal(getmetatable(f.profiles),"protected-original") end
        end)
    end

    H.test("WT #428 history throwing root reader is contained before and after publication",function()
        local f=fixture();local throwing=false
        local runtime,verify=f.install({read=function(target,key) if throwing then error("reader") end;return rawget(target,key) end})
        H.equal(verify(),nil);throwing=true;H.truthy(verify());H.equal(runtime:reapply(),nil)
        local other=fixture();local failed=other.install({read=function() error("reader") end})
        H.truthy(failed.fatal_error);H.equal(next(failed.ledgers),nil)
    end)

    H.test("WT #428 history missing or disconnected canonical helper fails",function()
        for _,helper in ipairs({{}, {register=function() return 1,false end}}) do
            local f=fixture();local before=raw_shape(f.profiles)
            local failed=f.install({lookup=helper});H.truthy(failed.fatal_error);assert_shape(f.profiles,before)
        end
    end)

    for _,drift in ipairs({false,true}) do
    H.test("WT #428 history readiness loss preserves owned/drifted leaves drift="..tostring(drift),function()
        local f=fixture()
        local family=f.catalog.families[1]
        -- Use a real source-authored family: materialize only its exact native leaves.
        local state_id=family.state_order[1];local state=family.states[state_id]
        for _,op in ipairs(state.operations) do
            local parent=f.env[op.root]
            if op.root=="Weapons" then
                parent[op.template]=parent[op.template] or {};parent=parent[op.template]
            end
            for index=1,#op.path-1 do local key=op.path[index];parent[key]=parent[key] or {};parent=parent[key] end
            parent[op.path[#op.path]]=op.expected_present and copy(op.expected_current) or nil
        end
        function f.mod:get(key) return key==family.setting_id and state_id or "current" end
        local runtime,verify=f.install();H.equal(runtime.last_error,nil)
        local ledger=runtime.ledgers[family.id];H.truthy(#ledger>0);H.equal(verify(),nil)
        local foreign={third_party=true}
        if drift then rawset(ledger[1].parent,ledger[1].key,foreign) end
        local name=f.expected()[1];f.profiles[name]=copy(f.profiles[name])
        H.equal(runtime:reapply(),nil)
        if drift then
            H.equal(rawget(ledger[1].parent,ledger[1].key),foreign)
            H.equal(runtime.ledgers[family.id],ledger)
        else H.equal(#runtime.ledgers[family.id],0) end
        H.truthy(verify(),"restoring owned projection does not conceal lost registration")
    end)
    end
end
return register
