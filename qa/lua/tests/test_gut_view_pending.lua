-- #2 closed standalone pending/profile owner and real VMF return transport.
return function(H, root)
    local F = assert(loadfile(root .. "/qa/lua/fixtures/gut_view_pending_harness.lua"))()
    local REL = "gui_tweaker_dev/scripts/mods/gui_tweaker_dev/"
    local function read(path)
        local file = assert(io.open(root .. "/" .. path, "rb")); local text = file:read("*a"); file:close(); return text
    end
    local function pack(...) return { n = select("#", ...), ... } end
    local function new(options) return F.new(H, root, options) end
    local function count(text, needle)
        local n, at = 0, 1
        while true do local found = text:find(needle, at, true); if not found then return n end; n, at = n + 1, found + #needle end
    end
    local function events(f)
        local values = {}; for _, row in ipairs(f.trace) do values[#values + 1] = row[1] end; return values
    end
    H.test("GUT pending exact published cluster has one private entry owner and no new surface", function()
        local fixture = assert(loadfile(root .. "/qa/lua/fixtures/gut_view_pending_source.lua"))()
        local owner, view = read(REL .. "_mod_tweaker_view_pending.lua"), read(REL .. "_mod_tweaker_view.lua")
        local entry = read(REL .. "gui_tweaker_dev.lua")
        H.equal(count(owner, fixture.published_span), 1, "complete322-line span is verbatim")
        H.equal(count(entry, 'mod:dofile("scripts/mods/gui_tweaker_dev/_mod_tweaker_view_pending")'), 1)
        H.equal(count(view, "function ModTweakerView:stage_set"), 0)
        H.equal(count(view, "return ModTweakerView, function(install)"), 1)
        H.equal(count(entry, 'return pcall(mod.dofile, mod, "scripts/mods/gui_tweaker_dev/_mod_tweaker_view")'), 1)
        for _, forbidden in ipairs({ "mod:dofile(", "mod:hook", "mod:command", "function mod.update", "function mod.on_" }) do
            H.equal(count(owner, forbidden), 0, "pending owner must not own " .. forbidden)
        end
        H.equal(owner:find("mod%._[%w_]+%s*="), nil, "legacy late reads must not become new mod fields")
    end)
    H.test("GUT pending real VMF complete view installs after children and before actual attach constructor", function()
        local f = new()
        local ui = { views = {}, ingame_ui_context = { ui_renderer = {} } }
        H.equal(f.attach(ui), true); H.equal(f.constructed, 1)
        H.equal(type(ui.views.mod_tweaker_view.apply_pending), "function")
        H.equal(#f.staged_during_install, 3)
        for _, row in ipairs(f.staged_during_install) do H.equal(row[2], nil, row[1] .. " must only define consumers before binder") end
        local loads = 0; for _, name in ipairs(f.module_trace) do if name == "_mod_tweaker_view_pending" then loads = loads + 1 end end
        H.equal(loads, 1, "inert dependency loads once per entry binding, not per view retry")
        H.equal(f.attach(ui), true); H.equal(f.constructed, 1, "attached view remains idempotent")
        H.equal(f.deps.mod, f.mod)
        H.equal(type(f.deps.cat_set), "function"); H.equal(type(f.deps.commit_keybind), "function")
    end)
    H.test("GUT pending actual VMF preserves zero return versus nil and all trailing holes", function()
        local f = new()
        local cases = {
            { fn = function() end, n = 1 },
            { fn = function() return nil end, n = 2 },
            { fn = function() return nil, nil end, n = 3 },
            { fn = function() return false, nil, "tail", nil end, n = 5 },
        }
        for _, case in ipairs(cases) do
            f.raw_return = case.fn
            local calls = f.getter_calls
            local before = pack(f.legacy_load())
            H.equal(f.getter_calls, calls + 1, "original supplier evaluates dofile getter once")
            local after = pack(f.load_view())
            H.equal(f.getter_calls, calls + 2, "private supplier evaluates the same late getter once")
            H.equal(before.n, case.n); H.equal(after.n, before.n)
            for index = 1, before.n do H.equal(after[index], before[index]) end
        end
        local class, marker, installed = {}, {}, 0
        f.raw_return = function()
            return class, function(install) installed = installed + 1; return install(class, {}) end, nil, marker, nil
        end
        local result = pack(f.load_view())
        H.equal(result.n, 5); H.equal(result[1], true); H.equal(result[2], class)
        H.equal(result[3], nil); H.equal(result[4], marker); H.equal(result[5], nil); H.equal(installed, 1)
    end)
    H.test("GUT pending VMF chunk failure remains exact one-value true and does not expose error", function()
        local f, token = new(), {}
        f.chunk_error = { error = token }
        local before, after = pack(f.legacy_load()), pack(f.load_view())
        H.equal(before.n, 1); H.equal(after.n, 1); H.equal(before[1], true); H.equal(after[1], true)
        H.equal(#f.vmf_logs, 4)
        H.equal(f.vmf_logs[4][1], "error"); H.equal(f.vmf_logs[4][3], "(dofile)")
        H.equal(f.vmf_logs[4][4], token, "actual VMF unwraps the table error, then swallows its return tuple")
        local ui = { views = {}, ingame_ui_context = { ui_renderer = {} } }
        H.equal(f.attach(ui), false); H.equal(ui.views.mod_tweaker_view, nil); H.equal(f.constructed, nil)
    end)
    H.test("GUT pending late dofile getter failure remains outside original pcall", function()
        local f, token = new(), {}
        f.getter_error = token
        local old, current = pack(pcall(f.legacy_load)), pack(pcall(f.load_view))
        H.equal(old.n, 2); H.equal(current.n, 2)
        H.equal(old[1], false); H.equal(current[1], false); H.equal(old[2], token); H.equal(current[2], token)
        H.equal(#f.vmf_logs, 0, "argument lookup never entered VMF safe_call")
    end)
    H.test("GUT pending overridden throwing dofile preserves original error object and exact tuple", function()
        local f, token = new(), {}
        rawset(f.mod, "dofile", function() error(token, 0) end)
        local before, after = pack(f.legacy_load()), pack(f.load_view())
        H.equal(before.n, 2); H.equal(after.n, 2)
        H.equal(before[1], false); H.equal(after[1], false); H.equal(before[2], token); H.equal(after[2], token)
        H.equal(#f.vmf_logs, 0)
    end)
    H.test("GUT pending new binder failure is private and failed attach retries a fresh installed class", function()
        local token = {}
        local options = { installer = function() error(token, 0) end }
        local f = new(options)
        local result = pack(f.load_view()); H.equal(result.n, 2); H.equal(result[1], false); H.equal(result[2], token)
        H.equal(#f.vmf_logs, 0, "new binder errors are not claimed as VMF dofile logging")
        local ui = { views = {}, ingame_ui_context = { ui_renderer = {} } }
        H.equal(f.attach(ui), false); H.equal(ui.views.mod_tweaker_view, nil)
        options.installer = nil
        H.equal(f.attach(ui), true); H.equal(f.constructed, 1)
        local owner_loads = 0; for _, name in ipairs(f.module_trace) do if name == "_mod_tweaker_view_pending" then owner_loads = owner_loads + 1 end end
        H.equal(owner_loads, 1)
    end)
    H.test("GUT pending disconnected binder refuses constructor instead of publishing incomplete view", function()
        local f = new({ disconnect_binder = true })
        local ui = { views = {}, ingame_ui_context = { ui_renderer = {} } }
        H.equal(f.attach(ui), false); H.equal(ui.views.mod_tweaker_view, nil); H.equal(f.constructed, nil)
        local result = pack(f.load_view()); H.equal(result[1], false)
        H.equal(result[2], "private staged-view binder unavailable")
        for _, invalid in ipairs({ "not-a-binder", false, {} }) do
            f.raw_return = function() return {}, invalid end
            result = pack(f.load_view()); H.equal(result.n, 2); H.equal(result[1], false)
            H.equal(result[2], "private staged-view binder unavailable")
        end
    end)
    H.test("GUT pending staged false is owner-qualified and late provider reads remain live", function()
        local f = new(); local view = f.instance()
        view:stage_set(f.category, "setting", false)
        H.equal(view:get_staged(f.category, "setting", true), false)
        H.equal(f.values.setting, true); H.equal(view._dirty, nil)
        local other_values = { setting = "late" }
        local category = { mod_id = "equipment", _owners = { setting = { mod_id = "other", mod_obj = {
            get = function(_, id) return other_values[id] end,
        } } } }
        H.equal(view:get_staged(category, "setting", "read-live"), "read-live")
        view:stage_set(category, "setting", false)
        H.equal(view._pending.other.setting, false); H.equal(view._pending.equipment, nil)
    end)
    H.test("GUT pending actual single-owner apply keeps keybind persist order capture and sound", function()
        local f = new(); local view = f.instance(); local order = {}
        f.provider.on_settings_batch_changed = function() order[#order + 1] = "batch" end
        local set = f.provider.set
        f.provider.set = function(self, id, value, notify) order[#order + 1] = notify and "set-notify" or "set-silent"; return set(self,id,value,notify) end
        f.vmf.add_mod_keybind = function(_, id, data) order[#order + 1] = "register-key"; H.equal(id,"binding"); H.equal(data.keys[1],"k") end
        f.vmf.generate_keybinds = function() order[#order + 1] = "generate" end
        view._rows = { { _is_keybind = true, _setting_id = "binding", _category = f.category, content = {} } }
        view._profile_capture = function() order[#order + 1] = "capture" end
        view._build_rows = function() order[#order + 1] = "rebuild" end
        view:stage_set(f.category,"binding",{"k"})
        f.env.printf = function() order[#order + 1] = "late-batch-log" end
        view:apply_pending(f.category)
        H.deep_equal(order,{"set-silent","batch","late-batch-log","register-key","set-notify","generate","rebuild","capture"})
        H.equal(next(view._pending[f.category.mod_id]),nil); H.equal(view._dirty,true)
        H.equal(f.trace[#f.trace][1],"debug")
        local sound = false; for _, row in ipairs(f.trace) do if row[1]=="sound" and row[2]=="Play_hud_select" then sound=true end end
        H.truthy(sound)
    end)
    H.test("GUT pending complete actual VMF harness preserves host raw and metatable shapes", function()
        local saved={}
        for _,target in ipairs({_G,table,math,io,os,package,package.loaded}) do
            local row={target=target,meta=getmetatable(target),cells={}}
            for key,value in next,target do row.cells[key]=value end; saved[#saved+1]=row
        end
        local f=new(); f.instance()
        for _,row in ipairs(saved) do
            H.equal(getmetatable(row.target),row.meta)
            for key,value in next,row.cells do H.equal(rawget(row.target,key),value) end
            for key,value in next,row.target do H.equal(rawget(row.cells,key),value) end
        end
    end)
    H.test("GUT pending merged partial apply keeps failed owner and captures only successful retry", function()
        local f = new(); local view = f.instance(); local order, fail, captures = {}, true, 0
        local function provider(id)
            return { get = function() return false end,
                set = function(_, key, value, notify) order[#order + 1] = id .. ":set:" .. tostring(notify) end,
                on_settings_batch_changed = function()
                    order[#order + 1] = id .. ":batch"
                    if id == "b" and fail then error("retry-b", 0) end
                end }
        end
        local a,b = provider("a"),provider("b")
        local category = { mod_id = "equipment", _owner_mod_ids = { "a", "b" },
            _owners = { one = {mod_id="a",mod_obj=a}, two = {mod_id="b",mod_obj=b} } }
        view._categories,view._selected={category},1
        view._profile_capture=function()captures=captures+1;order[#order+1]="capture"end
        view._build_rows=function()order[#order+1]="rebuild"end
        view:stage_set(category,"one",true);view:stage_set(category,"two",false)
        view:apply_pending(category)
        H.equal(next(view._pending.a),nil);H.equal(view._pending.b.two,false)
        H.equal(captures,0);H.equal(view._dirty,true)
        H.deep_equal(order,{"a:set:false","a:batch","b:set:false","b:batch","rebuild"})
        fail=false;view:apply_pending(category)
        H.equal(next(view._pending.b),nil);H.equal(captures,1)
        H.deep_equal(order,{"a:set:false","a:batch","b:set:false","b:batch","rebuild","b:set:false","b:batch","rebuild","capture"})
    end)
    H.test("GUT pending reseed-only defaults retain intent until late reset owner accepts", function()
        local f = new(); local view = f.instance(); local calls,captures=0,0
        local category={mod_id="wt_dev",mod_obj=f.provider}
        view._categories,view._selected,view._build_category={category},1,category
        view._profile_capture=function()captures=captures+1 end
        view:reset_to_defaults()
        H.equal(view:_active_category_dirty(),true);H.equal(next(view._pending),nil)
        f.mod._gut_reset_modded_loadouts=function(reason)calls=calls+1;H.equal(reason,"mod_tweaker_default");return false,"try later"end
        view:apply_pending(category);H.equal(calls,1);H.equal(view:_active_category_dirty(),true)
        f.mod._gut_reset_modded_loadouts=function(reason)calls=calls+1;H.equal(reason,"mod_tweaker_default");return true end
        view:apply_pending(category);H.equal(calls,2);H.equal(view:_active_category_dirty(),false);H.equal(captures,0)
    end)
    H.test("GUT pending actual profile replay keeps slot and draft through failure then emits once", function()
        local f = new();local view=f.instance();local fail,emissions=true,0
        view._build_nodes={{type="checkbox",setting_id="setting",default_value=false}}
        f.values.setting=false
        H.equal(view:_profile_ensure(f.category),true)
        local profiles=f.deps.profiles
        local member=profiles.member_key(f.category.mod_id,"setting")
        H.equal(profiles.load(f.mod,f.category.mod_id,1)[member],false)
        profiles.save(f.mod,f.category.mod_id,2,{[member]=true})
        f.provider.on_settings_batch_changed=function()if fail then error("profile-retry",0)end end
        f.mod.mod_tweaker.emit_profile_diagnostic=function(_,id,phase)
            emissions=emissions+1;H.equal(id,f.category.mod_id);H.equal(phase,"profile_switch")
        end
        view:_switch_profile(2)
        local replay=view._profile_replay;H.truthy(replay);H.equal(replay.slot,2)
        H.equal(profiles.get_active(f.mod,f.category.mod_id),1)
        H.equal(view._pending[f.category.mod_id].setting,true);H.equal(emissions,0)
        fail=false;view:apply_pending(f.category)
        H.equal(view._profile_replay,nil);H.equal(profiles.get_active(f.mod,f.category.mod_id),2)
        H.equal(profiles.load(f.mod,f.category.mod_id,2)[member],true);H.equal(emissions,1)
        H.equal(next(view._pending[f.category.mod_id]),nil)
    end)
    H.test("GUT pending Dialogue refusal retains draft before any transaction or default staging", function()
        local f=new();local view=f.instance();local reads=0
        local category={mod_id="character_dialogue",widgets={{type="dialogue_browser"}}}
        view._build_category=category;view._build_nodes={{type="checkbox",setting_id="auto_isolation",default_value=false}}
        view._pending.character_dialogue={auto_isolation=true}
        local get_mod=f.env.get_mod
        f.env.get_mod=function(id)if id=="character_dialogue"then reads=reads+1;return nil end;return get_mod(id)end
        view:apply_pending(category);view:reset_to_defaults()
        H.equal(reads,1);H.equal(view._pending.character_dialogue.auto_isolation,true)
        H.equal(view._dirty,nil);H.equal(view._official_reseed_pending,nil)
    end)
    H.test("GUT pending popup missing throwing cancel confirm and disappearance preserve order", function()
        local f=new();local view=f.instance();local order={}
        view.reset_to_defaults=function()order[#order+1]="reset"end
        f.env.Managers=nil;view:_queue_reset_popup();H.deep_equal(order,{"reset"})
        f.env.Managers={popup={queue_popup=function()error("popup-unavailable",0)end}}
        view:_queue_reset_popup();H.deep_equal(order,{"reset","reset"})
        local result,queued=nil,0
        f.env.Managers.popup={queue_popup=function(_,text,topic,yes,yes_label,no,no_label)
            queued=queued+1;H.equal(yes,"reset_values");H.equal(no,"revert_changes");return queued
        end,query_result=function(_,id)return result end,cancel_popup=function(_,id)order[#order+1]="cancel:"..id end}
        view:_queue_reset_popup();view:_queue_reset_popup();H.equal(queued,1)
        view:_check_reset_popup();H.equal(view._reset_popup_id,1)
        result="revert_changes";view:_check_reset_popup();H.equal(view._reset_popup_id,nil)
        H.deep_equal(order,{"reset","reset","cancel:1"})
        view:_queue_reset_popup();result="reset_values";view:_check_reset_popup()
        H.deep_equal(order,{"reset","reset","cancel:1","cancel:2","reset"})
        view:_queue_reset_popup();f.env.Managers={};view:_check_reset_popup()
        H.equal(view._reset_popup_id,nil);H.equal(#order,5)
    end)
    H.test("GUT pending popup query errors remain ordinary and retain the pending id", function()
        local f,token=new(),{};local view=f.instance()
        view._reset_popup_id=7;f.env.Managers={popup={query_result=function()error(token,0)end}}
        local ok,err=pcall(view._check_reset_popup,view)
        H.equal(ok,false);H.equal(err,token);H.equal(view._reset_popup_id,7)
    end)
    H.test("GUT pending exclusive enforcement reads current controller and foreign provider late", function()
        local f=new();local view=f.instance();local calls=0
        f.mod.mod_tweaker={get_exclusive_group_id=function()return"group"end,
            get_exclusive_members=function()return{{mod_id=f.category.mod_id,setting_id="setting"},{mod_id="foreign",setting_id="other"}}end}
        local get_mod=f.env.get_mod
        f.env.get_mod=function(id)
            if id=="foreign"then calls=calls+1;return{get=function(_,key)H.equal(key,"other");return true end}end
            return get_mod(id)
        end
        H.equal(view:_enforce_exclusive(f.category,"setting"),true)
        H.equal(view._pending.foreign.other,false);H.equal(calls,1)
        H.equal(view:_enforce_exclusive(f.category,"setting"),false);H.equal(calls,1,"staged false bypasses live provider")
    end)
    H.test("GUT pending reconstructed full old view and real suppliers retain healthy functional trace", function()
        local function exercise(prior)
            local f=new({prior=prior});local view=f.instance()
            view._build_nodes={{type="checkbox",setting_id="setting",default_value=false}}
            H.equal(view:_profile_ensure(f.category),true)
            view:stage_set(f.category,"setting",false)
            H.equal(view:get_staged(f.category,"setting",true),false)
            view:apply_pending(f.category)
            H.equal(f.values.setting,false);H.equal(view._dirty,true)
            H.equal(next(view._pending[f.category.mod_id]),nil)
            local installed={}
            for _,row in ipairs(f.staged_during_install)do installed[#installed+1]=type(row[2])end
            return {trace=f.trace,settings=f.settings,values=f.values,pending=view._pending},installed
        end
        local old,old_installed=exercise(true);local current,current_installed=exercise(false)
        H.deep_equal(current,old,"whole actual old/new view, helper calls, profile persistence and sound/log order")
        H.deep_equal(old_installed,{"function","function","function"})
        H.deep_equal(current_installed,{"nil","nil","nil"},"retained installers define consumers without calling deferred methods")
    end)
    H.test("GUT pending fixed old-view inverse requires complete fixture and exact current anchors", function()
        local fixture=assert(loadfile(root.."/qa/lua/fixtures/gut_view_pending_source.lua"))()
        local current=read(REL.."_mod_tweaker_view.lua")
        local prior=F.prior_view(current,fixture)
        H.equal(#prior,94085,"complete published source length; outside proof also binds full SHA")
        H.equal(count(prior,fixture.published_span),1)
        H.equal(prior:sub(-#"return ModTweakerView\n"),"return ModTweakerView\n")
        H.equal(pcall(F.prior_view,current:gsub("return ModTweakerView, function%(install%)","return ModTweakerView, function(disconnected)",1),fixture),false)
        H.equal(pcall(F.prior_view,current,{}),false)
    end)
    H.test("GUT pending capture identities preserve early logger function but late bare batch logger", function()
        local changed_logger,early_logger
        local f=new({child_install=function(name,class,deps,context)
            if name=="_mod_tweaker_view_interaction"then
                early_logger=deps.printf
                changed_logger=function(...)context.trace[#context.trace+1]={"late_print",...}end
                context.env.printf=changed_logger
            end
        end})
        local view=f.instance()
        H.equal(f.deps.printf,early_logger);H.truthy(f.deps.printf~=changed_logger)
        for key,module in pairs({transactions="_mod_tweaker_transaction",default_reset="_mod_tweaker_default_reset",
                profiles="_mod_tweaker_profiles",profile_runtime="_mod_tweaker_profile_runtime",DialogueUI="_mod_tweaker_dialogue"})do
            H.equal(f.deps[key],f.modules[module],key.." keeps exact captured table")
        end
        local commits=0;local commit=f.deps.transactions.commit
        f.deps.transactions.commit=function(...)commits=commits+1;return commit(...)end
        f.provider.on_settings_batch_changed=function()end
        view._profile_capture=function()end
        local replacement_sound_calls=0
        f.sound.play=function()replacement_sound_calls=replacement_sound_calls+1 end
        view:stage_set(f.category,"setting",false);view:apply_pending(f.category)
        H.equal(commits,1,"captured module table still reads its current method")
        H.equal(replacement_sound_calls,0,"captured play-click function retains its original play reference")
        local batch=false
        for _,row in ipairs(f.trace)do if row[1]=="late_print" and row[2]:find("[gut:560]",1,true)then batch=true end end
        H.truthy(batch,"bare printf is intentionally late")
    end)
end
