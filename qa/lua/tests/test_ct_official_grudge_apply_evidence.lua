return function(H, root)
    root=root:gsub("\\","/"):gsub("/$","")
    local base=os.getenv("VT2_CT_GRUDGE_EVIDENCE_OVERLAY_ROOT")
    if base then
        base=base:gsub("\\","/"):gsub("/$","")
        assert(base==root.."/.temp/public-promotion-20261105/ct-card-drafts/grudge107-addon"
            or base==root.."/.temp/public-promotion-20261105/ct-card-drafts/grudge107-addon-02")
    else base=root end
    local prefix="chaos_wastes_tweaker/scripts/mods/chaos_wastes_tweaker/"
    local function pack(...) return {n=select("#",...),...} end
    local function fixture(settings)
        local f={settings=settings or {},hooks={},rows={}}
        local env=setmetatable({}, {__index=_G}); env._G=env; f.env=env
        env.Managers={player={is_server=true},state={},mechanism={game_mechanism=function() return nil end}}
        env.TerrorEventUtils={}; env.printf=function(fmt,...) f.rows[#f.rows+1]=string.format(fmt,...) end
        local mod={}; f.mod=mod
        local function load(name)
            local file=(name=="_ct_official_verify_runtime" and base or root).."/"..prefix..name..".lua"
            local fn=assert(loadfile(file)); setfenv(fn,env); return fn()
        end
        function mod:get(key) return f.settings[key] end
        function mod:dofile(path) return load(assert(path:match("/([%w_]+)$"))) end
        function mod:hook(target,name,cb)
            local key=tostring(target)..":"..name; assert(not f.hooks[key]); f.hooks[key]=cb
            if target==env.TerrorEventUtils and name=="apply_breed_enhancements" then f.callback=cb end
        end
        mod.hook_safe=mod.hook
        function mod:network_register() end
        function mod:command() end
        function mod:echo() end
        local ctx={effective_setting=function(key) return f.settings[key] end,rt_register=function() end,rpc_schema=2,altar_uses=function() return 0 end}
        f.runtime=load("_ct_official_verify_runtime")(mod,ctx); ctx.runtime=f.runtime
        f.evidence=load("_ct_diag_official_apply_evidence")(mod,ctx); mod._ct_apply_evidence=f.evidence
        assert(type(f.callback)=="function")
        return f
    end
    H.test("CT107 actual singleton callback records scalar filter counts and preserves complete native tuple and data identity",function()
        local f=fixture({ban_all_grudge_marks=true,ban_grudge_mark_commander=true})
        local base_entry={name="base"}; local data={name_index=7,enhancements={base_entry,{name="commander"},{name="elite_base"}}}; local original=data.enhancements
        local r=pack(f.callback(function(unit,breed,passed)
            assert(passed==data and passed.name_index==7 and #passed.enhancements==2 and passed.enhancements[1]==base_entry)
            return nil,"two",nil,"four",nil
        end,{}, {name="champion"},data))
        assert(r.n==5 and r[2]=="two" and r[4]=="four" and #original==3)
        local row=assert(f.rows[1]); assert(row:find("incoming=3",1,true) and row:find("kept=2",1,true) and row:find("removed=1",1,true))
        assert(row:find("authority=host",1,true) and row:find("master=true",1,true) and row:find("breed=champion",1,true))
    end)
    H.test("CT107 client authority false preserves original enhancement array and logs no removal",function()
        local f=fixture({ban_all_grudge_marks=true,ban_grudge_mark_commander=true}); f.env.Managers.player.is_server=false
        local list={{name="commander"}}; local data={enhancements=list}
        f.callback(function(_,_,passed) assert(passed==data and passed.enhancements==list) end,{},nil,data)
        assert(f.rows[1]:find("removed=0",1,true) and f.rows[1]:find("authority=client",1,true))
    end)
    H.test("CT107 no evidence owner does not change native returns or error identity",function()
        local f=fixture(); f.mod._ct_apply_evidence=nil
        local data={enhancements={{name="base"}}}; local list=data.enhancements
        local r=pack(f.callback(function(_,_,passed) assert(passed.enhancements==list); return "a",nil,"c",nil end,{}, {},data))
        assert(r.n==4 and r[1]=="a" and r[3]=="c")
        local marker={}; local ok,err=pcall(f.callback,function() error(marker,0) end,{}, {},data)
        assert(not ok and err==marker and #f.rows==0)
    end)
    H.test("CT107 protected real evidence owner swallows printer and recorder faults before native pass through",function()
        local f=fixture(); f.env.printf=function() error("printer") end
        local called=0; local native=function() called=called+1; return nil,9,nil end
        local r=pack(f.callback(native,{}, {},{enhancements={{name="base"}}})); assert(r.n==3 and r[2]==9 and called==1)
        f.evidence.record=function() error("recorder") end
        r=pack(f.callback(native,{}, {},{enhancements={{name="base"}}})); assert(r.n==3 and r[2]==9 and called==2)
    end)
    H.test("CT107 existing receipt owner bounds changed rows to24 and preserves native errors",function()
        local f=fixture({ban_grudge_mark_commander=true}); local calls=0
        for i=1,40 do
            local data={enhancements={{name="base"},{name="commander"}}}
            f.callback(function() calls=calls+1 end,{}, {name="champion"..i},data)
        end
        assert(calls==40 and #f.rows==24)
        local marker={}; local ok,err=pcall(f.callback,function() error(marker,0) end,{}, {},{enhancements={{name="base"}}})
        assert(not ok and err==marker and #f.rows==24)
    end)
    H.test("CT107 malformed or absent enhancement payload remains native with no synthetic receipt",function()
        local f=fixture(); for _,data in ipairs({{}, {enhancements=false}}) do
            local r=pack(f.callback(function(_,_,passed) assert(passed==data); return 1,nil,3 end,{}, {},data))
            assert(r.n==3 and r[3]==3)
        end
        assert(#f.rows==0)
    end)
    H.test("CT107 evidence-only master getter fault cannot suppress native base application with or without owner",function()
        for _,owner in ipairs({true,false}) do
            local settings=setmetatable({}, {__index=function(_,key)
                if key=="ban_all_grudge_marks" then error("evidence master getter") end
            end})
            local f=fixture(settings); if not owner then f.mod._ct_apply_evidence=nil end
            local data={enhancements={{name="base"}}}; local list=data.enhancements; local called=0
            local r=pack(f.callback(function(_,_,passed) called=called+1; assert(passed==data and passed.enhancements==list); return nil,2,nil,4,nil end,{}, {},data))
            assert(called==1 and r.n==5 and r[2]==2 and r[4]==4 and #f.rows==0)
        end
    end)
    H.test("CT107 evidence-only breed getter fault cannot suppress native callback with or without owner",function()
        for _,owner in ipairs({true,false}) do
            local f=fixture(); if not owner then f.mod._ct_apply_evidence=nil end
            local breed=setmetatable({}, {__index=function(_,key) if key=="name" then error("evidence breed getter") end end})
            local data={enhancements={{name="base"}}}; local called=0
            local r=pack(f.callback(function(_,passed_breed,passed) called=called+1; assert(passed_breed==breed and passed==data); return "a",nil,"c",nil end,{},breed,data))
            assert(called==1 and r.n==4 and r[1]=="a" and r[3]=="c" and #f.rows==0)
        end
    end)
end
