-- #2 actual private entry/VMF/State/View handoff. No renderer/ABI simulation.
return function(H, root, options)
    options = options or {}
    local F = assert(loadfile(root .. "/qa/lua/fixtures/gut_view_pending_harness.lua"))()
    local REL = "gui_tweaker_dev/scripts/mods/gui_tweaker_dev/"
    local function pack(...) return { n = select("#", ...), ... } end
    local function read(path)
        local f = assert(io.open(root .. "/" .. path, "rb"), path)
        local s = f:read("*a"); f:close(); return (s:gsub("\r\n", "\n"))
    end
    local function count(text, needle)
        local n, at = 0, 1
        while true do local i = text:find(needle, at, true); if not i then return n end; n, at = n + 1, i + #needle end
    end
    local function nodes(...)
        local out = { { mod_name = "gt", readable_mod_name = "Live General" } }
        for _, id in ipairs({...}) do out[#out + 1] = { setting_id = id, type = "checkbox", depth = 1 } end
        return out
    end
    local function new(opts)
        opts = opts or {}; opts.native_class = true
        if options.control == "noop_state" then opts.noop_state = true end
        if options.control == "factory_false" then opts.factory_return = { value = false } end
        if options.control == "disconnect_state" then opts.disconnect_state = true end
        local f = F.new(H, root, opts)
        f.mods, f.live_queries, f.controller = {}, {}, {}
        f.vmf.options_widgets_data = { nodes("live_setting") }
        f.env.get_mod = function(id)
            if id == "gut_dev" then return f.mod end
            f.live_queries[#f.live_queries + 1] = id
            if id == "VMF" then return f.vmf end
            return f.mods[id]
        end
        f.mod.mod_tweaker.list_categories = function() return f.controller end
        return f
    end
    local function state(f, prior)
        local value = f.state_instance(prior); value:_rebuild(); return value
    end
    local function view(f)
        local value = f.instance(); value._layout_tabs = function() end
        value:_rebuild(); return value
    end
    local function healthy(f)
        local status = f.load_state(); H.equal(status, true)
        local result = state(f)
        H.equal(#result._all_categories, 1, "actual State categories must be installed")
        H.equal(result._all_categories[1].mod_id, "gt", "private binding cannot silently become controller fallback")
        H.equal(result._all_categories[1].widgets, f.vmf.options_widgets_data[1])
        H.equal(result.built, result._all_categories[1])
        return result
    end
    H.test("GUT shared catalog actual State healthy private handoff has real categories", function()
        local f = new(); healthy(f)
    end)
    H.test("GUT shared catalog one root owner and independent State then View closures", function()
        local f = new(); H.equal(f.load_state(), true)
        local state_disabled_sections = f.modules._mod_tweaker_disabled_sections
        H.equal(type(state_disabled_sections), "table", "independent State-load module ledger")
        local v = f.instance()
        H.equal(#f.live_queries, 0, "parent loading/binding must not discover VMF")
        H.equal(f.state_catalog_factory, f.view_catalog_factory)
        H.truthy(f.state_catalog_function ~= f.view_catalog_function)
        H.equal(f.state_catalog_deps.mod, f.mod); H.equal(f.view_catalog_deps.mod, f.mod)
        H.truthy(f.state_catalog_deps.nf ~= f.view_catalog_deps.nf)
        H.equal(f.state_catalog_deps.printf, f.view_catalog_deps.printf)
        H.equal(f.state_catalog_deps.math, f.view_catalog_deps.math)
        H.equal(f.state_catalog_deps.disabled_sections, state_disabled_sections)
        H.equal(f.view_catalog_deps.disabled_sections, f.modules._mod_tweaker_disabled_sections)
        H.truthy(state_disabled_sections ~= f.modules._mod_tweaker_disabled_sections,
            "real VMF dofile re-evaluates each parent dependency independently")
        local seen = 0; for _, name in ipairs(f.module_trace) do if name == "_mod_tweaker_view_catalog" then seen = seen + 1 end end
        H.equal(seen, 1, "one real VMF catalog evaluation across both parents")
        H.equal(type(v.stage_set), "function"); H.equal(type(f.State.stage_set), "function")
    end)
    H.test("GUT shared catalog View first and fresh retries do not depend on State opening", function()
        local f = new(); local first = view(f)
        H.equal(first._all_categories[1].mod_id, "gt")
        H.equal(f.load_state(), true); healthy(f)
        local second = view(f)
        H.truthy(getmetatable(first) ~= getmetatable(second), "actual local native classes remain independent")
        H.equal(second._all_categories[1].widgets, first._all_categories[1].widgets)
        local seen = 0; for _, name in ipairs(f.module_trace) do if name == "_mod_tweaker_view_catalog" then seen = seen + 1 end end
        H.equal(seen, 1)
    end)
    H.test("GUT shared catalog complete prior State and current preserve category graph", function()
        local f = new(); H.equal(f.load_state(), true)
        local current, prior = state(f), state(f, true)
        H.deep_equal(current._all_categories, prior._all_categories)
        H.equal(current._all_categories[1].widgets, prior._all_categories[1].widgets)
        H.equal(current._tabs[1].content.text, prior._tabs[1].content.text)
        H.equal(f.State._rebuild, getmetatable(current)._rebuild)
    end)
    H.test("GUT shared catalog actual State keeps mixed folds raw nodes and profile exclusions", function()
        local f = new(); local gut = {
            {mod_name="gut_dev",readable_mod_name="GUI"},
            {setting_id="gut_hide_hud_ui_group",type="group",depth=1},
            {setting_id="hb_group",type="group",depth=2},
            {setting_id="old_hb",type="checkbox",depth=3},
            {setting_id="gut_uitweaks_integration_group",type="group",depth=3},
            {setting_id="sync",type="checkbox",depth=4},
        }
        local ckc = {setting_id="kill",type="checkbox",depth=5}
        local hb = {setting_id="live_hb",type="checkbox",depth=6}
        f.mods["Crosshair Kill Confirmation"], f.mods.HideBuffs = {}, { SETTING_NAMES = {old_hb="old_hb"} }
        f.vmf.options_widgets_data = {gut,
            {{mod_name="Crosshair Kill Confirmation"},ckc},{{mod_name="HideBuffs"},hb}}
        H.equal(f.load_state(), true)
        local current, prior = state(f), state(f, true)
        H.deep_equal(current._all_categories, prior._all_categories)
        local cat = current._all_categories[1]
        H.deep_equal(cat._owner_mod_ids, {"gut_dev","Crosshair Kill Confirmation","HideBuffs"})
        H.equal(cat._profile_excluded_owners.HideBuffs,true)
        H.equal(cat._owners.kill.mod_obj,f.mods["Crosshair Kill Confirmation"])
        H.equal(cat._owners.live_hb.mod_obj,f.mods.HideBuffs)
        H.equal(#gut,6);H.equal(gut[4].setting_id,"old_hb");H.equal(ckc.depth,5);H.equal(hb.depth,6)
    end)
    H.test("GUT shared catalog actual State reads late providers and retains controller fallback", function()
        local f = new(); healthy(f)
        local replacement = nodes("late_setting"); replacement[1].readable_mod_name = "Late"
        f.vmf.options_widgets_data = {replacement}
        local value = state(f);H.equal(value._all_categories[1].label,"Late")
        local fallback = {mod_id="controller",label="Fallback",widgets={}}
        f.controller={fallback};local token={}
        f.env.get_mod=function(id)if id=="VMF"then error(token,0)end;return f.mod end
        local raw=pack(pcall(f.state_catalog_function));H.equal(raw[1],false);H.equal(raw[2],token)
        value=state(f);H.equal(value._all_categories[1],fallback);H.equal(value.built,fallback)
    end)
    H.test("GUT shared State VMF empty and nil tuples remain distinct without false notice", function()
        local f=new()
        for _,case in ipairs({{n=1,fn=function()end},{n=2,fn=function()return nil end},
                {n=3,fn=function()return nil,nil end},{n=5,fn=function()return false,nil,"tail",nil end}})do
            f.state_raw_return=case.fn
            local before=pack(pcall(f.mod.dofile,f.mod,"scripts/mods/gui_tweaker_dev/_mod_tweaker_state"))
            local after=pack(f.catalog.bind_state_result(unpack(before,1,before.n)))
            H.equal(after.n,case.n);H.equal(after.n,before.n)
            for i=1,before.n do H.equal(after[i],before[i])end
            local logcount=#f.trace;local status=f.load_state();H.equal(status,true)
            for i=logcount+1,#f.trace do
                H.truthy(f.trace[i][1]~="captured_print" or not tostring(f.trace[i][2]):find("state load/bind failed",1,true))
            end
        end
    end)
    H.test("GUT shared State adapter consumes only private binder and preserves extra holes", function()
        local f=new();local marker,meta,calls={},{},0
        f.state_raw_return=function()return meta,function(bind)
            H.equal(bind,f.catalog.bind);calls=calls+1
        end,nil,marker,nil end
        local result=pack(f.catalog.bind_state_result(pcall(f.mod.dofile,f.mod,"scripts/mods/gui_tweaker_dev/_mod_tweaker_state")))
        H.equal(result.n,5);H.equal(result[1],true);H.equal(result[2],meta)
        H.equal(result[3],nil);H.equal(result[4],marker);H.equal(result[5],nil);H.equal(calls,1)
    end)
    H.test("GUT shared State missing binder has observable refusal and same next loads", function()
        local f=new({disconnect_state=true});local result=pack(f.load_state())
        H.equal(result[1],false);H.equal(result[2],"private state category binder unavailable")
        local notices=0
        for _,row in ipairs(f.trace)do if row[1]=="captured_print" and row[2]=="[gut:2] Mod Tweaker state load/bind failed: %s"then
            notices=notices+1;H.equal(row[3],result[2])
        end end
        H.equal(notices,1);H.equal(#f.vmf_logs,0)
        local last={};for _,name in ipairs(f.module_trace)do
            if name=="_ba_compendium_state"or name=="_ba_heroview_inject"or name=="_ba_compendium"then last[#last+1]=name end
        end
        H.deep_equal(last,{"_ba_heroview_inject","_ba_compendium"})
        H.truthy(f.env.HeroViewStateModTweaker,"class is intentionally not quarantined")
        f.controller={{mod_id="controller",label="Fallback",widgets={}}}
        H.equal(state(f)._all_categories[1],f.controller[1])
    end)
    H.test("GUT shared State throwing binder preserves error and one neutral diagnostic", function()
        local token={};local f=new({state_bind_error=token});local result=pack(f.load_state())
        H.equal(result[1],false);H.equal(result[2],token);H.equal(#f.vmf_logs,0)
        local notices=0;for _,row in ipairs(f.trace)do
            if row[1]=="captured_print"and row[2]:find("state load/bind failed",1,true)then
                notices=notices+1;H.equal(row[3],tostring(token))
            end
        end;H.equal(notices,1)
    end)
    H.test("GUT shared State getter failure remains outside native pcall and notice", function()
        local f=new();local token={};f.getter_error=token
        local before=#f.trace;local result=pack(pcall(f.load_state))
        H.equal(result[1],false);H.equal(result[2],token);H.equal(#f.vmf_logs,0)
        H.equal(#f.trace,before)
    end)
    H.test("GUT shared State native false is neutral load refusal not fake VMF logging", function()
        local f=new();local token={}
        rawset(f.mod,"dofile",function(_,path)
            if path:find("_mod_tweaker_state",1,true)then error(token,0)end
        end)
        local result=pack(f.load_state());H.equal(result[1],false);H.equal(result[2],token)
        H.equal(#f.vmf_logs,0)
        local found=0;for _,row in ipairs(f.trace)do if row[1]=="captured_print"then
            found=found+1;H.equal(row[3],tostring(token))
        end end;H.equal(found,1)
    end)
    H.test("GUT shared State no-throw disconnected factories fail the same real category oracle", function()
        for _,opts in ipairs({{noop_state=true},{factory_return={value=nil}},
                {factory_return={value=false}},{factory_return={value="not-a-function"}}})do
            local f=new(opts);local ok=pcall(healthy,f)
            H.equal(ok,false,"no thrown binder does not establish complete category binding")
        end
    end)
    H.test("GUT shared State portable inverse requires full span and original whole length", function()
        local fixture=assert(loadfile(root.."/qa/lua/fixtures/gut_category_state_source.lua"))()
        local current=read(REL.."_mod_tweaker_state.lua")
        local prior=F.prior_state(current,fixture)
        H.equal(#prior,fixture.state_normalized_bytes);H.equal(count(prior,fixture.state_span),1)
        H.equal(pcall(F.prior_state,current,{state_span="missing",state_normalized_bytes=1}),false)
    end)
    H.test("GUT shared catalog keeps host raw fields and metatables exact", function()
        local rows={};for _,t in ipairs({_G,table,math,io,os,package,package.loaded})do
            local r={target=t,meta=getmetatable(t),cells={}};for k,v in next,t do r.cells[k]=v end;rows[#rows+1]=r
        end
        local f=new();healthy(f);view(f)
        for _,r in ipairs(rows)do H.equal(getmetatable(r.target),r.meta)
            for k,v in next,r.cells do H.equal(rawget(r.target,k),v)end
            for k,v in next,r.target do H.equal(rawget(r.cells,k),v)end
        end
    end)
end
