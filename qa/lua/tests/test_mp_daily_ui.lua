return function(H, repo_root, runtime_path, entry_source)
local root = repo_root or "."
runtime_path = runtime_path or root .. "/modded_progression/scripts/mods/modded_progression/_mp_daily_ui_runtime.lua"
local function copy(value)
    if type(value) ~= "table" then return value end
    local result = {}
    for k,v in pairs(value) do result[k] = copy(v) end
    return result
end
local function pack(...) return { n=select("#", ...), ... } end
local protection_reads, protection_writes = 0, 0
local protection = setmetatable({}, {
    __index=function() protection_reads=protection_reads+1; error("account protection read") end,
    __newindex=function() protection_writes=protection_writes+1; error("account protection write") end,
})
local environment = setmetatable({ GameSettingsDevelopment=protection, script_data=protection }, {__index=_G})
environment._G=environment
local chunk=assert(loadfile(runtime_path)); setfenv(chunk,environment)
local Runtime=chunk()
local CREATE="HeroViewStateAchievements._create_entries"
local ALL="HeroViewStateAchievements._handle_claim_all_challenges"
local ONE_CLAIM="HeroViewStateAchievements._claim_quest_reward"
local MANY_CLAIM="HeroViewStateAchievements._claim_multiple_quest_rewards"

local function row(id,progress)
    return { id=id, progress=progress or 0, target=2, claimed=false }
end
local function fixture(query,overrides)
    local rows={ a=row("mp_daily_v2_a",2), b=row("mp_daily_v2_b",0), c=row("mp_daily_v2_c",2) }
    local state={ rows=rows, native_calls=0, claims=0, balance=0, logs={}, reads=0 }
    local function find(id)
        for _,entry in pairs(rows) do if entry.id==id then return entry end end
    end
    local daily={ REWARD_KIND="SM",REWARD_AMOUNT=5 }
    daily.find_by_id=function(id) state.reads=state.reads+1; local e=find(id); return e and copy(e) end
    daily.quest_data=function(id)
        local e=find(id)
        if not e then return nil end
        return { id=id,claimed=e.claimed,completed=e.progress>=e.target,
            name="Name "..id,desc="Description "..id,icon="daily_icon",
            progress={math.min(e.progress,e.target),e.target},
            reward={reward_type="currency",currency_code="SM",amount=5} }
    end
    if overrides and overrides.dailies then daily=overrides.dailies end
    state.daily=daily
    local ui={
        widget=function()
            state.widgets=(state.widgets or 0)+1
            return {content={},style={reward_icon={},progress_bar={default_size={100},texture_size={100}}}}
        end,
        parse=function(needle,filters)
            if needle=="completed:true" then filters.completed=true; return "" end
            return needle:lower()
        end,
        matches=function(needle,text) return text:lower():find(needle,1,true) end,
        currency=function(code,amount) assert(code=="SM" and amount==5); return {icon="shilling_icon",rarity="common",item_type="chips",slot_type="chips"} end,
        background=function(rarity) assert(rarity=="common"); return "icon_bg_common" end,
        dim=function(widget) widget.dimmed=true end,
    }
    state.ui=ui
    local realm_value=true
    state.set_realm=function(value) realm_value=value end
    local hooks,counts,checks={},{},{}
    local function local_claim(ids)
        state.claims=state.claims+1
        if state.claim_behavior then return state.claim_behavior(ids,state) end
        for _,id in ipairs(ids) do
            local e=assert(find(id))
            assert(not e.claimed and e.progress>=e.target)
        end
        for _,id in ipairs(ids) do find(id).claimed=true; state.balance=state.balance+5 end
        return "mp_local_daily_claim_"..state.claims,nil,"tail",nil
    end
    local passed_ui=ui
    if overrides and overrides.omit_ui then passed_ui=nil end
    local runtime=overrides and overrides.runtime or Runtime
    runtime.install({hook=function(_,class,method,fn)
        local key=class.."."..method
        counts[key]=(counts[key] or 0)+1; assert(counts[key]==1,"duplicate hook")
        hooks[key]=fn
    end},{is_modded_realm=query or function() return realm_value end,
        dailies=daily,local_claim=overrides and overrides.local_claim or local_claim,ui=passed_ui,
        print_log=function(fmt,...) state.logs[#state.logs+1]=string.format(fmt,...) end,
        rt_register=function(name,fn) checks[name]=fn end})
    state.hooks,state.counts,state.checks=hooks,counts,checks
    local view={ _achievement_layout_type="quest",_active_tab={},_search_query="",
        _search_widgets_by_name={filters={content={query={}}}},
        _additional_quest_widgets_by_name={claim_all_quests={content={visible=true}}} }
    view._update_achievements_scroll_height=function() state.scroll=(state.scroll or 0)+1 end
    view._setup_achievement_entries_animations=function() state.animations=(state.animations or 0)+1 end
    view._show_empty_entries_warning=function() state.empty=true end
    view._hide_empty_entries_warning=function() state.empty=false end
    view._set_widget_bar_progress=function(_,widget,current,target)
        widget.content.progress_text=current.."/"..target
        widget.style.progress_bar.texture_size[1]=100*current/target
    end
    state.view=view
    state.ids={rows.a.id,rows.b.id,rows.c.id}
    state.native=function() state.native_calls=state.native_calls+1; error("native daily UI/backend entered") end
    state.build=function(ids,kind,subtype)
        return hooks[CREATE](state.native,view,ids or state.ids,kind or "quest",subtype)
    end
    state.reconcile=function() return hooks[ALL](state.native,view) end
    state.button=view._additional_quest_widgets_by_name.claim_all_quests.content
    return state
end

H.test("MP daily UI installs exactly four existing hook seams and detached runtime proof",function()
    local f=fixture()
    local n=0; for _ in pairs(f.hooks) do n=n+1 end
    H.equal(n,4); H.equal(f.checks[Runtime.CHECK_NAME](),nil)
end)

H.test("MP daily row builder preserves completed-first order and native progress/finalizers",function()
    local f=fixture(); f.build()
    local w=f.view._achievement_widgets
    H.equal(#w,3); H.equal(#f.view._claimable_challenge_widgets,2)
    H.equal(w[1].content.id,f.rows.a.id); H.equal(w[2].content.id,f.rows.c.id); H.equal(w[3].content.id,f.rows.b.id)
    H.equal(w[1].content.completed,true); H.equal(w[1].content.can_close,false)
    H.equal(w[1].content.draw_bar,false); H.equal(w[1].content.expandable,false); H.equal(w[1].dimmed,nil)
    H.equal(w[3].content.progress_text,"0/2"); H.equal(w[3].content.draw_bar,true); H.equal(w[3].dimmed,true)
    H.equal(w[1].content.reward_item.data.item_type,"chips")
    H.equal(w[1].content.reward_item.data.slot_type,"chips")
    H.equal(w[1].content.reward_icon,"shilling_icon"); H.equal(w[1].content.reward_icon_background,"icon_bg_common")
    H.equal(f.scroll,1); H.equal(f.animations,1); H.equal(f.empty,false)
    H.truthy(w~=f.view._claimable_challenge_widgets)
end)

for _,spec in ipairs({
    {name="completed true",key="completed",value=true,want=2},
    {name="completed false",key="completed",value=false,want=1},
    {name="claimed true",key="claimed",value=true,want=0},
    {name="claimed false",key="claimed",value=false,want=3},
    {name="locked true",key="locked",value=true,want=0},
    {name="locked false",key="locked",value=false,want=3},
    {name="Silver Shillings",key="reward",value="chips",want=3},
    {name="foreign reward",key="reward",value="weapon",want=0},
    {name="matching rarity",key="rarity",value="common",want=3},
    {name="foreign rarity",key="rarity",value="unique",want=0},
}) do
    local case=spec
    H.test("MP daily filters "..case.name.." before widget construction",function()
        local f=fixture(); f.view._search_widgets_by_name.filters.content.query[case.key]=case.value
        f.build(); H.equal(#f.view._achievement_widgets,case.want); H.equal(f.widgets or 0,case.want)
        H.equal(f.empty,case.want==0)
    end)
end

H.test("MP daily typed filter is extracted once and stored in the actual filter widget",function()
    local f=fixture(); f.view._search_query="completed:true"; f.build()
    H.equal(#f.view._achievement_widgets,2)
    H.equal(f.view._search_widgets_by_name.filters.content.query.completed,true)
end)

H.test("MP daily free-text search covers localized name and description",function()
    local f=fixture(); f.view._search_query="description "..f.rows.b.id; f.build()
    H.equal(#f.view._achievement_widgets,1); H.equal(f.view._achievement_widgets[1].content.id,f.rows.b.id)
end)

for _,spec in ipairs({
    {name="foreign",ids={"daily_collect_tomes"}},
    {name="stale namespace",ids={"mp_daily_v2_previous_day"}},
    {name="duplicate",ids={"mp_daily_v2_a","mp_daily_v2_a"}},
    {name="sparse",ids={[1]="mp_daily_v2_a",[3]="mp_daily_v2_c"}},
    {name="metadata key",ids={"mp_daily_v2_a",foreign=true}},
    {name="metatable",ids=setmetatable({"mp_daily_v2_a"},{})},
}) do
    local case=spec
    H.test("MP daily builder rejects "..case.name.." arrays without native/statistics fallback",function()
        local f=fixture(); f.build(); f.build(case.ids)
        H.equal(#f.view._achievement_widgets,0); H.equal(#f.view._claimable_challenge_widgets,0)
        H.equal(f.button.visible,false); H.equal(f.claims,0); H.equal(f.native_calls,0)
    end)
end

for _,spec in ipairs({
    {name="claimed",change=function(f) f.rows.a.claimed=true end},
    {name="removed",change=function(f) f.rows.a=nil end},
    {name="reader exception",change=function(f) f.daily.quest_data=function() error("stats unavailable") end end},
    {name="requirements",change=function(f)
        local old=f.daily.quest_data; f.daily.quest_data=function(id) local d=old(id); d.requirements={}; return d end
    end},
    {name="DLC-backed",change=function(f)
        local old=f.daily.quest_data; f.daily.quest_data=function(id) local d=old(id); d.required_dlc="paid"; return d end
    end},
    {name="non-SM reward",change=function(f)
        local old=f.daily.quest_data; f.daily.quest_data=function(id) local d=old(id); d.reward.currency_code="USD"; return d end
    end},
    {name="item reward",change=function(f)
        local old=f.daily.quest_data; f.daily.quest_data=function(id) local d=old(id); d.reward.reward_type="item"; return d end
    end},
    {name="wrong fixed amount",change=function(f)
        local old=f.daily.quest_data; f.daily.quest_data=function(id) local d=old(id); d.reward.amount=50; return d end
    end},
}) do
    local case=spec
    H.test("MP daily builder fails closed for "..case.name.." owner data",function()
        local f=fixture(); case.change(f); f.build()
        H.equal(f.hooks[ONE_CLAIM](f.native,f.view,f.ids[1]),nil)
        H.equal(f.hooks[MANY_CLAIM](f.native,f.view,{f.ids[1]}),nil)
        H.equal(#f.view._achievement_widgets,0); H.equal(f.native_calls,0); H.equal(f.claims,0)
    end)
end

H.test("MP daily builder contains construction/finalizer errors and bounded logs",function()
    for _,field in ipairs({"widget","currency","background","dim"}) do
        local f=fixture(); f.ui[field]=function() error("UI unavailable") end
        f.build(); f.build(); H.equal(#f.view._achievement_widgets,0); H.equal(#f.logs,1); H.equal(f.native_calls,0)
    end
    local f=fixture(); f.view._update_achievements_scroll_height=function() error("closing UI") end
    f.build(); H.equal(#f.view._achievement_widgets,0); H.equal(f.button.visible,false)
end)

H.test("MP daily search nil-subtype and empty weekly/event routes stay owned and empty",function()
    local f=fixture(); f.build(nil,"quest",nil); H.equal(#f.view._achievement_widgets,3)
    f.build({},"quest","weekly"); H.equal(#f.view._achievement_widgets,0)
    f.build({},"quest","event"); H.equal(#f.view._achievement_widgets,0); H.equal(f.native_calls,0)
end)

for _,key in ipairs({CREATE,ALL,ONE_CLAIM,MANY_CLAIM}) do
    local seam=key
    H.test("MP daily official passthrough preserves argument and return nil holes: "..seam,function()
        local f=fixture(); f.set_realm(false)
        local args={f.view,"arg1",nil,"arg3",nil,n=5}
        local got
        local native=function(...) got=pack(...); return 1,nil,3,nil end
        local result=pack(f.hooks[seam](native,unpack(args,1,args.n)))
        H.deep_equal(got,args); H.deep_equal(result,{1,nil,3,nil,n=4}); H.equal(f.reads,0); H.equal(f.claims,0)
        local marker={}
        local ok,err=pcall(f.hooks[seam],function() error(marker,0) end,f.view,"arg")
        H.equal(ok,false); H.truthy(err==marker)
    end)
end

for _,spec in ipairs({
    {name="missing",read=function() return nil end},
    {name="malformed",read=function() return "modded" end},
    {name="throwing",read=function() error("authority missing") end},
}) do
    local case=spec
    H.test("MP daily "..case.name.." authority never delegates quest UI or actions",function()
        local f=fixture(case.read); f.build()
        H.equal(#f.view._achievement_widgets,0)
        H.equal(f.hooks[ONE_CLAIM](f.native,f.view,f.rows.a.id),nil)
        H.equal(f.hooks[MANY_CLAIM](f.native,f.view,{f.rows.a.id}),nil)
        f.reconcile(); H.equal(f.button.visible,false); H.equal(f.native_calls,0); H.equal(f.claims,0)
    end)
end

H.test("MP daily claim-all re-derives native-corrupted list from exact authored visible widgets",function()
    local f=fixture(); f.build()
    local old=f.view._claimable_challenge_widgets
    f.view._claimable_challenge_widgets={[-1]=old[1]}
    f.reconcile()
    H.equal(#f.view._claimable_challenge_widgets,2); H.equal(f.view._claimable_challenge_widgets[-1],nil)
    H.equal(f.button.visible,true)
    f.view._achievement_widgets=copy(f.view._achievement_widgets)
    f.reconcile(); H.equal(f.button.visible,false)
end)

H.test("MP daily failed duplicate claim-all and unreadable authority release native pre-marks",function()
    local f=fixture(); f.build()
    local widget=f.view._achievement_widgets[1]
    widget.content.claiming=true
    H.equal(f.hooks[MANY_CLAIM](f.native,f.view,{widget.content.id,widget.content.id}),nil)
    H.equal(widget.content.claiming,false); H.equal(f.claims,0)
    widget.content.claiming=true; f.set_realm(nil)
    H.equal(f.hooks[MANY_CLAIM](f.native,f.view,{widget.content.id}),nil)
    H.equal(widget.content.claiming,false); H.equal(f.claims,0)
end)

H.test("MP daily roster/progress change during widget construction fails closed",function()
    for _,change in ipairs({"rollover","progress"}) do
        local mode=change; local f=fixture()
        local old=f.ui.widget
        f.ui.widget=function()
            if mode=="rollover" then f.rows.a=nil else f.rows.a.progress=0 end
            return old()
        end
        f.build(); H.equal(#f.view._achievement_widgets,0); H.equal(f.button.visible,false)
        H.equal(f.native_calls,0); H.equal(f.claims,0)
    end
end)

H.test("MP daily live membership and row identity are rechecked before claim-all enable",function()
    local f=fixture(); f.build(); f.rows.a.claimed=true
    f.view._achievement_widgets[2].content.id="foreign_daily"
    f.reconcile(); H.equal(#f.view._claimable_challenge_widgets,0); H.equal(f.button.visible,false)
end)

for _,key in ipairs({"_reward_poll_id","_reward_poll_claim_all_id","_quest_refresh_poll_id"}) do
    local field=key
    H.test("MP daily pending "..field.." disables affordance and refuses new claims",function()
        local f=fixture(); f.build(); f.view[field]="existing_pending"; f.reconcile()
        H.equal(f.button.visible,false)
        H.equal(f.hooks[ONE_CLAIM](f.native,f.view,f.rows.a.id),nil)
        H.equal(f.claims,0); H.equal(f.view[field],"existing_pending")
    end)
end

H.test("MP daily owned individual action uses exact local transaction once and preserves tuple",function()
    local f=fixture(); f.build()
    local result=pack(f.hooks[ONE_CLAIM](f.native,f.view,f.rows.a.id))
    H.deep_equal(result,{"mp_local_daily_claim_1",nil,"tail",nil,n=4}); H.equal(f.balance,5)
    H.equal(f.hooks[ONE_CLAIM](f.native,f.view,f.rows.a.id),nil)
    H.equal(f.balance,5); H.equal(f.claims,1); H.equal(f.native_calls,0)
end)

for _,spec in ipairs({
    {name="incomplete",ids={"mp_daily_v2_b"}},
    {name="foreign",ids={"daily_collect_tomes"}},
    {name="mixed",ids={"mp_daily_v2_a","daily_collect_tomes"}},
    {name="duplicate",ids={"mp_daily_v2_a","mp_daily_v2_a"}},
    {name="empty",ids={}},
}) do
    local case=spec
    H.test("MP daily "..case.name.." claim-all rejects before any grant",function()
        local f=fixture(); f.build()
        H.equal(f.hooks[MANY_CLAIM](f.native,f.view,case.ids),nil)
        H.equal(f.claims,0); H.equal(f.balance,0); H.equal(f.native_calls,0)
    end)
end

for _,behavior in ipairs({"refusal","exception"}) do
    local kind=behavior
    H.test("MP daily claim-all "..kind.." restores only adapter-authored claiming rows",function()
        local f=fixture(); f.build()
        f.claim_behavior=function() if kind=="exception" then error("storage unavailable") end return nil,"persistence rejected" end
        local first=f.view._achievement_widgets[1]
        local second=f.view._achievement_widgets[2]
        first.content.claiming=true; second.content.claiming=true
        H.equal(f.hooks[MANY_CLAIM](f.native,f.view,{first.content.id}),nil)
        H.equal(first.content.claiming,false); H.equal(second.content.claiming,true)
        f.claim_behavior=nil
        H.truthy(f.hooks[MANY_CLAIM](f.native,f.view,{first.content.id}))
        H.equal(f.balance,5); H.equal(f.native_calls,0)
    end)
end

H.test("MP daily reentrant rejection cannot release the outer transaction's busy ownership",function()
    local f=fixture(); f.build(); local attempts=0
    f.claim_behavior=function()
        for _=1,2 do
            attempts=attempts+1
            H.equal(f.hooks[ONE_CLAIM](f.native,f.view,f.rows.c.id),nil)
        end
        return "mp_local_daily_claim_reentrant"
    end
    H.equal(f.hooks[ONE_CLAIM](f.native,f.view,f.rows.a.id),"mp_local_daily_claim_reentrant")
    H.equal(attempts,2); H.equal(f.claims,1)
end)

H.test("MP daily implementation never reads or changes live account protection fields",function()
    H.equal(protection_reads,0); H.equal(protection_writes,0)
end)

local function read(path)
    local f=io.open(path,"rb"); if not f then return nil end
    local value=f:read("*a"); f:close(); return (value:gsub("\r\n","\n"))
end
local source=entry_source or read(root.."/modded_progression/scripts/mods/modded_progression/modded_progression.lua")
H.test("MP daily entry installs the module once and retires all four prior hook owners",function()
    H.truthy(source:find('mod:dofile("scripts/mods/modded_progression/_mp_daily_ui_runtime").install(mod, {',1,true))
    for _,name in ipairs({"_create_entries","_handle_claim_all_challenges","_claim_quest_reward","_claim_multiple_quest_rewards"}) do
        H.equal(source:find('mod:hook("HeroViewStateAchievements", "'..name..'"',1,true),nil)
    end
    H.truthy(source:find("dailies = Dailies, local_claim = _local_claim",1,true))
end)

H.test("MP daily default native adapter calls only existing widget/query/currency/color collaborators",function()
    local calls={definitions=0,widgets=0,metadata=0,parse=0,dim=0}
    local definition={native_quest_definition=true}
    local env=setmetatable({GameSettingsDevelopment=protection,script_data=protection,
        local_require=function(path)
            H.equal(path,"scripts/ui/views/hero_view/states/definitions/hero_view_state_achievements_definitions")
            calls.definitions=calls.definitions+1
            return {quest_entry_definition=definition}
        end,
        UIWidget={init=function(def)
            H.truthy(def==definition); calls.widgets=calls.widgets+1
            local style={reward_icon={}}
            for _,key in ipairs({"icon","progress_bar","progress_bar_background","icon_background",
                "reward_background","side_detail_left","side_detail_right"}) do
                style[key]={color={255,255,255,255},default_size={100},texture_size={100}}
            end
            return {content={},style=style}
        end},
        BackendUtils={get_fake_currency_item=function(code,amount)
            H.equal(code,"SM"); H.equal(amount,5); calls.metadata=calls.metadata+1
            return {icon="shilling_icon",rarity="common",item_type="chips",slot_type="chips"}
        end},
        SearchUtils={extract_queries=function(needle)
            calls.parse=calls.parse+1; return needle
        end,simple_search=function(needle,text) return text:find(needle,1,true) end},
        UISettings={achievement_search_definitions={},item_rarity_textures={common="icon_bg_common"}},
        Colors={darker=function(color,factor)
            calls.dim=calls.dim+1; color[2]=color[2]/factor
        end},
    },{__index=_G})
    env._G=env
    local load=assert(loadfile(runtime_path)); setfenv(load,env)
    local f=fixture(nil,{runtime=load(),omit_ui=true})
    f.build(); f.build()
    H.equal(#f.view._achievement_widgets,3)
    H.equal(calls.definitions,1); H.equal(calls.widgets,6); H.equal(calls.metadata,6)
    H.equal(calls.parse,2); H.equal(calls.dim,14)
    H.equal(f.view._achievement_widgets[1].style.icon.color[2],255)
    H.truthy(f.view._achievement_widgets[3].style.icon.color[2]<255)
end)

H.test("MP daily actual local transaction persists three exact-once claims with local poll rewards",function()
    local storage,templates,settings={},{},{stat_mappings={}}
    for _,name in ipairs({"daily_collect_grimoires","daily_collect_tomes","daily_collect_loot_die"}) do
        settings[name]=1
        templates[name]={name=name,desc=name.." description",stat_mappings={{qualifying_event=true}},
            completed=function() error("synthetic statistics must not run") end,
            progress=function() error("synthetic statistics must not run") end}
    end
    local env=setmetatable({QuestSettings=settings,printf=function() end,Localize=function(s) return s end,
        get_mod=function() return {get=function(_,key) return storage[key] end,
            set=function(_,key,value) storage[key]=value end} end,
        require=function(path)
            H.equal(path,"scripts/managers/quest/quest_templates")
            return {quests=templates}
        end}, {__index=_G})
    local load=assert(loadfile(root.."/modded_progression/scripts/mods/modded_progression/mp_dailies.lua"))
    setfenv(load,env); local daily=load()
    daily.ensure(); daily.increment(daily.quest_slice(),"qualifying_event")
    local ids={}; for _,entry in pairs(daily.quest_slice()) do ids[#ids+1]=entry.name end
    table.sort(ids); H.equal(#ids,3)
    local actual=assert(source:match("local function _local_claim%(ids%)(.-)\nend\n\n%-%- ==="),"actual local claim owner anchor")
    local factory=assert(loadstring("return function(Dailies) local _local_poll_serial=0; local _local_quest_rewards={};"
        .." local function _dbg_alert() end; local function _dbg() end; local function _local_claim(ids)"
        ..actual.."\nend; return _local_claim,_local_quest_rewards end","actual_mp_local_claim"))()
    local local_claim,rewards=factory(daily)
    local f=fixture(nil,{dailies=daily,local_claim=local_claim})
    f.build(ids)
    local first=f.hooks[ONE_CLAIM](f.native,f.view,ids[1])
    H.equal(first,"mp_local_daily_claim_1"); H.equal(daily.balance(),5)
    H.deep_equal(rewards[first].quest_key,{ids[1]}); H.equal(rewards[first].loot[1].amount,5)
    H.equal(f.hooks[ONE_CLAIM](f.native,f.view,ids[1]),nil); H.equal(daily.balance(),5)
    local final=f.hooks[MANY_CLAIM](f.native,f.view,{ids[2],ids[3]})
    H.equal(final,"mp_local_daily_claim_2"); H.equal(rewards[final].loot[1].amount,10)
    H.equal(daily.balance(),15); H.equal(next(daily.quest_slice()),nil)
    for _,id in ipairs(ids) do
        H.truthy(storage[daily.STATE_KEY].ledger.transactions[id])
        H.equal(settings.stat_mappings[id],nil)
    end
    H.equal(f.native_calls,0)
end)

local native_root="C:/Users/danjo/source/repos/Vermintide-2-Source-Code"
local native=read(native_root.."/scripts/ui/views/hero_view/states/hero_view_state_achievements.lua")
local native_table=read(native_root.."/foundation/scripts/util/table.lua")
local native_search=read(native_root.."/scripts/helpers/search_utils.lua")
local function exact(src,class,name,next_name,env)
    local body=assert(src:match(class.."%."..name.." = (function.-)\n\n"..class.."%."..next_name),name)
    local fn=assert(loadstring("return "..body,"exact_native_"..name)); setfenv(fn,env); return fn()
end

H.test_if(native~=nil and native_table~=nil,"MP daily exact native single-claim completion keeps both rebuilt claimable rows",function()
    local f=fixture(); f.rows.b.progress=2; f.build()
    local view=f.view
    local env=setmetatable({table=copy(table)}, {__index=_G})
    env.table.index_of=exact(native_table,"table","index_of","slice",env)
    env.table.swap_delete=exact(native_table,"table","swap_delete","array_remove_if",env)
    local complete=exact(native,"HeroViewStateAchievements","_on_reward_claimed","_on_all_rewards_claimed",env)
    view._setup_layout=function() end
    view._activate_tab=function()
        local ids={}; for _,id in ipairs(f.ids) do
            if not f.daily.find_by_id(id).claimed then ids[#ids+1]=id end
        end
        f.build(ids)
    end
    view._setup_reward_presentation=function() end
    view._update_new_status_for_current_tab=function() end
    view._update_buttons_new_status=function() end
    view._handle_claim_all_challenges=f.reconcile
    local old=view._achievement_widgets[1]
    H.truthy(f.hooks[ONE_CLAIM](f.native,view,old.content.id))
    view._reward_claim_widget=old
    complete(view,"mp_local_daily_claim_1","quest")
    H.equal(#view._achievement_widgets,2); H.equal(#view._claimable_challenge_widgets,2)
    H.equal(view._claimable_challenge_widgets[-1],nil); H.equal(f.balance,5)
end)

H.test_if(native~=nil,"MP daily exact native claim-all refusal releases pre-written claiming state",function()
    local f=fixture(); f.build(); local view=f.view
    local env=setmetatable({}, {__index=_G})
    local native_many=exact(native,"HeroViewStateAchievements","_claim_multiple_rewards","_claim_quest_reward",env)
    view._claim_multiple_quest_rewards=function(self,ids) return f.hooks[MANY_CLAIM](f.native,self,ids) end
    f.claim_behavior=function() return nil,"persistence rejected" end
    native_many(view,view._claimable_challenge_widgets)
    H.equal(view._reward_poll_claim_all_id,nil); H.equal(view._quest_rewards_fail_reason,"persistence rejected")
    for _,widget in ipairs(view._achievement_widgets) do H.equal(widget.content.claiming,false) end
    H.equal(f.balance,0); H.equal(f.native_calls,0)
end)

for _,mode in ipairs({"desktop","controller"}) do
    for _,action in ipairs({"one","all"}) do
        local device,kind=mode,action
        H.test_if(native~=nil,"MP daily native "..device.." cursor input routes "..kind.." claim locally",function()
            local f=fixture(); f.build(); local view=f.view
            local row=view._achievement_widgets[1]
            local claim_button=view._additional_quest_widgets_by_name.claim_all_quests
            local achievement_window={}
            local gamepad_queries,blocks=0,0
            local env=setmetatable({
                Managers={input={is_device_active=function(_,name)
                    H.equal(name,"gamepad"); gamepad_queries=gamepad_queries+1
                    return device=="controller"
                end}},
                UIUtils={is_button_hover_enter=function() return false end,
                    is_button_pressed=function(widget)
                        return kind=="one" and widget==row or kind=="all" and widget==claim_button
                    end,
                    is_button_hover=function(widget)
                        return widget==achievement_window or widget==row
                            or kind=="all" and widget==claim_button and claim_button.content.visible
                    end},
                UIWidgetUtils={animate_default_button=function() end},
                ACHIEVEMENT_PRESENTATION_AMOUNT=4,
            },{__index=_G})
            local input=exact(native,"HeroViewStateAchievements","_handle_input","_on_tab_list_pressed",env)
            local pressed=exact(native,"HeroViewStateAchievements","_on_achievement_pressed","_claim_reward",env)
            local claim_one=exact(native,"HeroViewStateAchievements","_claim_reward","_claim_multiple_rewards",env)
            local claim_many=exact(native,"HeroViewStateAchievements","_claim_multiple_rewards","_claim_quest_reward",env)
            local update=exact(native,"HeroViewStateAchievements","update","_has_active_level_vote",env)
            view._active_tab={content={list_content={}},style={list_style={num_draws=0}}}
            view._widgets_by_name={exit_button={},quests_button={},summary_button={},achievements_button={},achievement_window=achievement_window}
            view._summary_widgets_by_name={summary_right_window_button={},summary_left_window_button={}}
            view._additional_achievement_widgets_by_name={claim_all_achievements={}}
            view._achievement_draw_index=1
            view._category_scrollbar={update=function() end}; view._category_tab_widgets={}
            view._handle_gamepad_filter_input=function() return false end
            view.input_service=function() return {get=function() return false end} end
            view._handle_search_input=function() return false end
            view._handle_layout_buttons_hovered=function() end; view._animate_claim_button=function() end
            view._update_category_scroll_position=function() end; view._update_mouse_scroll_input=function() end
            view.play_sound=function() end; view.block_input=function() blocks=blocks+1 end
            view._on_achievement_pressed=pressed; view._claim_reward=claim_one
            view._claim_multiple_rewards=claim_many
            view._claim_quest_reward=function(self,id) return f.hooks[ONE_CLAIM](f.native,self,id) end
            view._claim_multiple_quest_rewards=function(self,ids) return f.hooks[MANY_CLAIM](f.native,self,ids) end
            for _,widget in ipairs(view._achievement_widgets) do
                widget.content.close_button_hotspot={is_hover=false}
                widget.content.progress_button_hotspot={is_hover=widget==row}
                widget.content.reward_button_hotspot={}
            end
            f.reconcile(); input(view,0.1,1)
            H.equal(gamepad_queries,1)
            if kind=="one" then
                H.equal(f.balance,5); H.equal(view._reward_poll_id,"mp_local_daily_claim_1")
                H.equal(blocks,1); H.equal(row.content.claiming,true)
            else
                H.equal(view._claim_all,true)
                view._transition_timer=1
                view.parent={transitioning=function() return false end}
                view._wanted_state=function() return nil end
                view._update_summary_quest_timers=function() end; view.draw=function() end
                view._update_transition_timer=function() end; view._handle_gamepad_activity=function() end
                view._handle_claim_all_challenges=f.reconcile
                update(view,0.1,2)
                H.equal(f.balance,10); H.equal(view._claim_all,false)
                H.equal(view._reward_poll_claim_all_id,"mp_local_daily_claim_1")
            end
            H.equal(f.claims,1); H.equal(f.native_calls,0)
        end)
    end
end

H.test_if(native_search~=nil,"MP daily native search parser preserves localized completion query extraction",function()
    local f=fixture()
    local source=assert(native_search:match("local function find_synonym_match.-\nlocal find, lower")):gsub("\nlocal find, lower$", "")
    local strings=copy(string)
    strings.remove=function(s,a,b) return s:sub(1,a-1)..s:sub(b+1) end
    strings.trim=function(s) return s:match("^%s*(.-)%s*$") end
    local env=setmetatable({SearchUtils={},Utf8={lower=string.lower},string=strings,
        Localize=function(key) return ({search_filter_completed="completed",truth="true,yes",falsity="false,no"})[key] or key end}, {__index=_G})
    local load=assert(loadstring(source,"exact_native_search")); setfenv(load,env); load()
    local defs={{key="completed",{true,"truth"},{false,"falsity"}}}
    f.ui.parse=function(needle,query) return env.SearchUtils.extract_queries(needle,defs,query) end
    f.view._search_query="completed: yes"
    f.build(); H.equal(#f.view._achievement_widgets,2)
    H.equal(f.view._search_widgets_by_name.filters.content.query.completed,true)
end)
for _,change in ipairs({"progress","target"}) do
    local kind=change
    H.test("MP daily live eligibility after "..kind.." changes",function()
        local f=fixture(); f.build({f.rows.a.id})
        H.equal(#f.view._claimable_challenge_widgets,1)
        H.equal(f.view._achievement_widgets[1].content.completed,true)
        if kind=="progress" then f.rows.a.progress=0 else f.rows.a.target=3 end
        H.equal(f.daily.quest_data(f.rows.a.id).completed,false)
        f.reconcile()
        H.equal(#f.view._claimable_challenge_widgets,0)
        H.equal(f.button.visible,false)
        H.equal(f.hooks[ONE_CLAIM](f.native,f.view,f.rows.a.id),nil)
        H.equal(f.claims,0)
    end)
end
H.test("MP daily real local reset keeps same IDs but revokes live completion",function()
    local storage,templates,settings={},{},{stat_mappings={}}
    for _,name in ipairs({"daily_collect_grimoires","daily_collect_tomes","daily_collect_loot_die"}) do
        settings[name]=1
        templates[name]={name=name,desc=name.." description",stat_mappings={{qualifying_event=true}}}
    end
    local env=setmetatable({QuestSettings=settings,printf=function() end,Localize=function(s) return s end,
        get_mod=function() return {get=function(_,key) return storage[key] end,
            set=function(_,key,value) storage[key]=value end} end,
        require=function(path) assert(path=="scripts/managers/quest/quest_templates"); return {quests=templates} end}, {__index=_G})
    local load=assert(loadfile("./modded_progression/scripts/mods/modded_progression/mp_dailies.lua"))
    setfenv(load,env); local daily=load()
    daily.ensure(); daily.increment(daily.quest_slice(),"qualifying_event")
    local id; for _,entry in pairs(daily.quest_slice()) do id=entry.name; break end
    local f=fixture(nil,{dailies=daily,local_claim=function() error("incomplete claim must not commit") end})
    f.build({id}); H.equal(#f.view._claimable_challenge_widgets,1)
    H.truthy(daily.reset()); H.truthy(daily.find_by_id(id),"same-day deterministic identity survives reset")
    H.equal(daily.quest_data(id).completed,false)
    f.reconcile()
    H.equal(#f.view._claimable_challenge_widgets,0); H.equal(f.button.visible,false)
    H.equal(f.hooks[ONE_CLAIM](f.native,f.view,id),nil)
end)
end
