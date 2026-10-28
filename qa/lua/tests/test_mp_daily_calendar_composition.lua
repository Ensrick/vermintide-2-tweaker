return function(H, repo)
    local dir = "/modded_progression/scripts/mods/modded_progression/"
    local function read(path)
        local f = assert(io.open(path, "rb")); local s = f:read("*a"); f:close()
        return (s:gsub("\r\n", "\n"))
    end
    local source = read(repo .. dir .. "modded_progression.lua")
    local Daily = assert(loadfile(repo .. dir .. "_mp_daily_ui_runtime.lua"))()
    local Calendar = assert(loadfile(repo .. dir .. "_mp_calendar_login_guard.lua"))()
    local Realm = assert(loadfile(repo .. dir .. "_lib_modded_realm_authority.lua"))()
    local function section(first, last)
        local at = assert(source:find(first, 1, true), "installer missing")
        local stop = assert(source:find(last, at, true), "installer end missing")
        assert(not source:find(first, at + #first, true), "duplicate installer")
        return source:sub(at, stop - 1)
    end
    local daily_block = section('mod:dofile("scripts/mods/modded_progression/_mp_daily_ui_runtime").install(mod, {',
        "-- #1684: exact plain-SM UI/action owner")
    local calendar_block = section("local CalendarLoginGuard = mod:dofile(", "-- Vanilla keep crafting bench:")
    local login_query_block = section("local function _progression_realm(", "local function _route_store_login_claim_for_realm(")
    local expected = {
        "HeroViewStateAchievements._create_entries",
        "HeroViewStateAchievements._handle_claim_all_challenges",
        "HeroViewStateAchievements._claim_quest_reward",
        "HeroViewStateAchievements._claim_multiple_quest_rewards",
        "HeroWindowGotwfOverview._claim_daily_reward",
    }
    local function setup(native, legacy, options)
        options = options or {}
        local state = { hooks={}, order={}, checks={}, check_order={}, loads={},
            claims=0, fallback=0, logs=0, brackets=0,
            legacy_flags={}, bracket_state={_mp_eac_depth=0,_mp_modded_depth=0} }
        rawset(state.legacy_flags,"eac-untrusted",options.flag)
        if options.metatable then setmetatable(state.legacy_flags,options.metatable) end
        local env = setmetatable({}, { __index=_G }); env._G=env; env.MODDED_REALM=native
        env.printf=function() state.logs=state.logs+1 end
        local mod = {
            dofile=function(_, path)
                state.loads[path]=(state.loads[path] or 0)+1
                if path=="scripts/mods/modded_progression/_mp_daily_ui_runtime" then return Daily end
                if path=="scripts/mods/modded_progression/_mp_calendar_login_guard" then return Calendar end
                error("unexpected module")
            end,
            hook=function(_, class, method, fn)
                local key=class.."."..method
                H.equal(state.hooks[key],nil,"duplicate installed owner")
                state.hooks[key]=fn; state.order[#state.order+1]=key
            end,
        }
        local chunk=assert(loadstring("return function(mod, Dailies, _local_claim, _is_mp_realm, _rt_register, FreshProfile, _with_eac_off)\n"
            ..login_query_block.."\n"..daily_block.."\n"..calendar_block.."\nend", "@actual-mp-two-slice-installers"))
        setfenv(chunk,env)
        chunk()(mod,{find_by_id=function() return nil end,quest_data=function() return nil end},
            function() state.claims=state.claims+1; error("unexpected local claim") end,
            function() state.fallback=state.fallback+1; return legacy end,
            function(name,fn)
                H.equal(state.checks[name],nil,"duplicate named registration")
                H.equal(type(fn),"function"); state.checks[name]=fn
                state.check_order[#state.check_order+1]=name
            end, {active=function() return options.fresh == true end}, function(func,self,...)
                state.brackets=state.brackets+1
                return Realm.with_eac_off(state.legacy_flags,state.bracket_state,func,self,nil,...)
            end)
        state.env=env
        return state
    end
    H.test("MP combined actual entry installs five unique callbacks and two exact named checks",function()
        local s=setup(true,false)
        H.equal(#s.order,#expected)
        for i,name in ipairs(expected) do H.equal(s.order[i],name); H.equal(type(s.hooks[name]),"function") end
        H.equal(s.loads["scripts/mods/modded_progression/_mp_daily_ui_runtime"],1)
        H.equal(s.loads["scripts/mods/modded_progression/_mp_calendar_login_guard"],1)
        H.equal(#s.check_order,2)
        H.equal(s.check_order[1],Daily.CHECK_NAME); H.equal(s.check_order[2],Calendar.CHECK_NAME)
        H.equal(s.checks[Daily.CHECK_NAME],Daily.runtime_check)
        H.equal(s.checks[Calendar.CHECK_NAME],Calendar.runtime_check)
        H.equal(s.claims,0); H.equal(s.fallback,0); H.equal(s.logs,0)
    end)
    H.test("MP combined actual entry named checks execute their installed production owners",function()
        local s=setup(true,false)
        H.equal(s.checks[Daily.CHECK_NAME](),nil)
        H.equal(s.checks[Calendar.CHECK_NAME](),nil)
        H.equal(s.claims,0); H.equal(s.fallback,0)
    end)
    H.test("MP combined explicit official authority preserves all five callback tuples and errors",function()
        local s=setup(false,true)
        local view,tail={},{}
        for _,name in ipairs(expected) do
            local function capture(...) return select("#",...),{...} end
            local count,values=capture(s.hooks[name](function(self,a,b,c)
                H.equal(self,view); H.equal(a,"head"); H.equal(b,nil); H.equal(c,tail)
                return "official",nil,tail,nil
            end,view,"head",nil,tail))
            H.equal(count,4); H.equal(values[1],"official"); H.equal(values[2],nil)
            H.equal(values[3],tail); H.equal(values[4],nil)
            local marker={}
            local ok,err=pcall(s.hooks[name],function() error(marker) end,view,"head",nil,tail)
            H.equal(ok,false); H.equal(err,marker)
        end
        H.equal(s.fallback,0); H.equal(s.claims,0); H.equal(s.env.MODDED_REALM,false)
    end)
    H.test("MP combined malformed native authority cannot fall back into either action owner",function()
        local s=setup("false",false)
        local native_calls=0
        local native=function() native_calls=native_calls+1 end
        H.equal(s.hooks[expected[3]](native,{},"foreign_daily"),nil)
        H.equal(s.hooks[expected[5]](native,{},0),nil)
        H.equal(native_calls,0); H.equal(s.claims,0); H.equal(s.fallback,0)
        H.equal(s.env.MODDED_REALM,"false")
    end)
    H.test("MP combined absent-native legacy authority remains shared and queried per action",function()
        local s=setup(nil,false)
        local native=function() return "official" end
        H.equal(s.hooks[expected[3]](native,{},"foreign_daily"),"official")
        H.equal(s.hooks[expected[5]](native,{},0),"official")
        H.equal(s.fallback,2); H.equal(s.claims,0); H.equal(rawget(s.env,"MODDED_REALM"),nil)
    end)
    H.test("MP combined authority is not captured at installation",function()
        local s=setup(true,false)
        local native_calls=0
        local native=function() native_calls=native_calls+1; return "official" end
        H.equal(s.hooks[expected[3]](native,{},"foreign_daily"),nil)
        H.equal(s.hooks[expected[5]](native,{},0),nil)
        s.env.MODDED_REALM=false
        H.equal(s.hooks[expected[3]](native,{},"foreign_daily"),"official")
        H.equal(s.hooks[expected[5]](native,{},0),"official")
        H.equal(native_calls,2); H.equal(s.fallback,0); H.equal(s.claims,0)
    end)
    -- Exact entry collaborators plus the actual shared bracket. These private
    -- tables are not the game's script_data or native account-protection state.
    for _, fresh in ipairs({false,true}) do
        for _, flag in ipairs({{name="nil"},{name="false",value=false},
                {name="true",value=true},{name="metatable"}}) do
            for _, method in ipairs({
                {name="rows",hook=expected[1],kind="achievements",direct_when_fresh=true},
                {name="unsupported_rows",hook=expected[1],direct_when_fresh=true},
                {name="claim_all",hook=expected[2],layout="achievements",direct_when_fresh=true},
                {name="unsupported_layout",hook=expected[2]},
            }) do
                local is_fresh,flag_case,method_case=fresh,flag,method
                H.test("MP combined preserves legacy nonquest "..method_case.name
                        .." fresh="..tostring(is_fresh).." flag="..flag_case.name,function()
                    local meta
                    if flag_case.name=="metatable" then
                        meta={__index=function(_,key) if key=="eac-untrusted" then return true end end,
                            __newindex=function() error("metatable intercepted legacy write") end}
                    end
                    local s=setup(true,false,{fresh=is_fresh,flag=flag_case.value,metatable=meta})
                    local view={_achievement_layout_type=method_case.layout}
                    local entries,marker={},{}
                    local bracketed=not(is_fresh and method_case.direct_when_fresh)
                    local wanted={n=2,marker,nil}
                    if method_case.hook==expected[1] then wanted={n=4,entries,method_case.kind,marker,nil} end
                    local function unchanged()
                        H.equal(rawget(s.legacy_flags,"eac-untrusted"),flag_case.value)
                        H.equal(getmetatable(s.legacy_flags),meta)
                        local count=0;for key in pairs(s.legacy_flags) do
                            count=count+1;H.equal(key,"eac-untrusted")
                        end
                        H.equal(count,flag_case.value~=nil and 1 or 0)
                        H.equal(s.bracket_state._mp_eac_depth,0);H.equal(s.bracket_state._mp_modded_depth,0)
                    end
                    local function observe(self,...)
                        H.equal(self,view);local got={n=select("#",...),...}
                        H.equal(got.n,wanted.n);for i=1,wanted.n do H.equal(got[i],wanted[i]) end
                        local expected_flag=flag_case.value
                        if bracketed then expected_flag=nil end
                        H.equal(rawget(s.legacy_flags,"eac-untrusted"),expected_flag)
                        H.equal(s.bracket_state._mp_eac_depth,bracketed and 1 or 0)
                        H.equal(s.bracket_state._mp_modded_depth,bracketed and flag_case.value==true and 1 or 0)
                    end
                    local function invoke(fn)
                        return s.hooks[method_case.hook](fn,view,unpack(wanted,1,wanted.n))
                    end
                    local function capture(...) return {n=select("#",...),...} end
                    local result=capture(invoke(function(self,...)
                        observe(self,...);return "native",nil,marker,nil
                    end))
                    H.equal(result.n,4);H.equal(result[1],"native");H.equal(result[2],nil)
                    H.equal(result[3],marker);H.equal(result[4],nil);unchanged()
                    local failure={};local ok,err=pcall(invoke,function(self,...)
                        observe(self,...);error(failure)
                    end)
                    H.equal(ok,false);H.equal(err,failure);unchanged()
                    H.equal(s.brackets,bracketed and 2 or 0);H.equal(s.claims,0)
                end)
            end
        end
    end
end
