-- #1684/#573: exact MP daily UI; no native account-protection flag changes.
-- The ordinary native row builder filters/dims completion under read-only
-- backend before creating widgets (6.13 hero_view_state_achievements:608-917).
-- MP supports only its current unclaimed, plain Silver Shilling daily rows.
local M = { CHECK_NAME = "issue1684_owned_daily_ui" }
local MAX_ROWS = 16 -- Defensive ceiling; actual membership comes from MP's roster.

local function capture(...) return { n = select("#", ...), ... } end
local function plain(value) return type(value) == "table" and getmetatable(value) == nil end
local function finite(value) return type(value) == "number" and value == value and value ~= math.huge and value ~= -math.huge end
local function array(value)
    if not plain(value) then return nil end
    local count, last = 0, 0
    for key in pairs(value) do
        if not finite(key) or key < 1 or key ~= math.floor(key) or key > MAX_ROWS then return nil end
        count, last = count + 1, math.max(last, key)
    end
    if count ~= last then return nil end
    local result, seen = {}, {}
    for i = 1, count do
        local id = rawget(value, i)
        if type(id) ~= "string" or seen[id] then return nil end
        seen[id], result[i] = true, id
    end
    return result
end

local function native_ui()
    local definition
    return {
        widget = function()
            if not definition then
                definition = local_require("scripts/ui/views/hero_view/states/definitions/hero_view_state_achievements_definitions").quest_entry_definition
            end
            return UIWidget.init(definition)
        end,
        parse = function(needle, query)
            return SearchUtils.extract_queries(needle, UISettings.achievement_search_definitions, query)
        end,
        matches = function(needle, text) return SearchUtils.simple_search(needle, text) end,
        currency = function(code, amount) return BackendUtils.get_fake_currency_item(code, amount) end,
        background = function(rarity) return UISettings.item_rarity_textures[rarity] end,
        dim = function(widget)
            local style = widget.style
            Colors.darker(style.icon.color, 1.94)
            for _, key in ipairs({ "progress_bar", "progress_bar_background", "icon_background",
                "reward_background", "side_detail_left", "side_detail_right" }) do
                Colors.darker(style[key].color, 1.43)
            end
        end,
    }
end

function M.install(mod, deps)
    assert(type(mod) == "table" and type(mod.hook) == "function", "MP hook owner missing")
    assert(type(deps) == "table" and type(deps.is_modded_realm) == "function", "MP realm reader missing")
    local daily, claim = assert(deps.dailies), assert(deps.local_claim)
    local ui = deps.ui or native_ui()
    local legacy_create, legacy_all = deps.legacy_create_entries, deps.legacy_claim_all
    assert(legacy_create == nil or type(legacy_create) == "function", "MP nonquest row delegate invalid")
    assert(legacy_all == nil or type(legacy_all) == "function", "MP nonquest claim-all delegate invalid")
    local owners, busy = setmetatable({}, { __mode = "k" }), setmetatable({}, { __mode = "k" })
    local warned = {}

    local function denied(stage, reason)
        if warned[stage] then return end
        warned[stage] = true
        if type(deps.print_log) == "function" then
            pcall(deps.print_log, "[mp:1684] daily_ui_denied stage=%s reason=%s backend=none", stage, tostring(reason))
        end
    end

    local function realm()
        local ok, value = pcall(deps.is_modded_realm)
        if ok and type(value) == "boolean" then return value end
        return nil
    end

    local function pending(view)
        return busy[view] or rawget(view, "_reward_poll_id")
            or rawget(view, "_reward_poll_claim_all_id") or rawget(view, "_quest_refresh_poll_id")
    end

    local function row_data(id)
        local entry = daily.find_by_id(id)
        if not plain(entry) or entry.id ~= id or entry.claimed ~= false
                or not finite(entry.target) or entry.target < 1
                or not finite(entry.progress) or entry.progress < 0 then return nil end
        local data = daily.quest_data(id)
        local reward = type(data) == "table" and data.reward
        if not plain(data) or data.id ~= id or data.claimed ~= false
                or type(data.name) ~= "string" or type(data.desc) ~= "string"
                or data.completed ~= (entry.progress >= entry.target)
                or data.requirements ~= nil or data.required_dlc ~= nil or data.required_dlc_extra ~= nil
                or not plain(reward) or reward.reward_type ~= "currency"
                or reward.currency_code ~= "SM" or reward.currency_code ~= daily.REWARD_KIND
                or reward.amount ~= daily.REWARD_AMOUNT or not finite(reward.amount) or reward.amount < 1
                or not plain(data.progress) or data.progress[1] ~= math.min(entry.progress, entry.target)
                or data.progress[2] ~= entry.target then return nil end
        return data
    end

    local function hide_claim_all(view)
        local widgets = rawget(view, "_additional_quest_widgets_by_name")
        local button = type(widgets) == "table" and rawget(widgets, "claim_all_quests")
        local content = type(button) == "table" and rawget(button, "content")
        if type(content) == "table" then rawset(content, "visible", false) end
        return content
    end

    local function clear(view, reason)
        owners[view] = nil
        rawset(view, "_achievement_widgets", {})
        rawset(view, "_claimable_challenge_widgets", {})
        rawset(view, "_has_claimable_filtered_challenges", nil)
        rawset(view, "_achievement_scroll_value", nil)
        hide_claim_all(view)
        if type(view._show_empty_entries_warning) == "function" then pcall(view._show_empty_entries_warning, view) end
        denied("rows", reason)
    end

    local function build(view, supplied, entry_subtype)
        if entry_subtype ~= nil and entry_subtype ~= "daily" then
            assert(type(supplied) == "table" and next(supplied) == nil, "foreign quest category")
        end
        local ids = assert(array(supplied), "invalid daily id array")
        local rows = {}
        for i, id in ipairs(ids) do rows[i] = assert(row_data(id), "foreign or stale daily") end
        local search = assert(rawget(view, "_search_widgets_by_name"), "search widgets missing")
        local filters = assert(search.filters and search.filters.content, "search filters missing")
        local original_query = assert(filters.query, "search query missing")
        assert(plain(original_query), "search query must be plain")
        local query = {}
        for key, value in pairs(original_query) do query[key] = value end
        local needle = assert(rawget(view, "_search_query"), "search text missing")
        assert(type(needle) == "string", "invalid search text")
        needle = ui.parse(needle, query)
        assert(type(needle) == "string", "invalid parsed search text")
        local all, available, other, authored = {}, {}, {}, {}
        for i, data in ipairs(rows) do
            local reward = data.reward
            local fake_data = assert(ui.currency(reward.currency_code, reward.amount), "currency metadata unavailable")
            local background = assert(ui.background(fake_data.rarity), "currency background unavailable")
            local reward_type = fake_data.slot_type or fake_data.item_type
            assert(type(background) == "string" and type(fake_data.icon) == "string", "currency presentation unavailable")
            local show = (ui.matches(needle, data.name) or ui.matches(needle, data.desc))
                and (query.completed == nil or query.completed == data.completed)
                and (query.claimed == nil or query.claimed == false)
                and (query.locked == nil or query.locked == false)
                and (query.reward == nil or query.reward == reward_type)
                and (query.rarity == nil or query.rarity == background:gsub("^icon_bg_", ""))
            if show then
                local widget = assert(ui.widget(), "quest widget unavailable")
                local content, style = assert(widget.content), assert(widget.style)
                content.reward_item = { data = fake_data }
                content.reward_icon, content.reward_icon_background = fake_data.icon, background
                content.locked, content.can_close, content.completed, content.claimed = false, false, data.completed, false
                content.id, content.achievement_id, content.original_order_index = data.id, data.id, i
                content.title, content.description = data.name, data.desc
                content.icon = data.icon or "icons_placeholder"
                content.expandable, content.expand_height, content.claiming = false, 10, false
                content.draw_bar = not data.completed
                style.reward_icon.saturated = false
                if not data.completed then
                    view:_set_widget_bar_progress(widget, data.progress[1], data.progress[2])
                    ui.dim(widget)
                end
                authored[widget] = data.id
                local target = data.completed and available or other
                target[#target + 1] = widget
            end
        end
        for _, widget in ipairs(available) do all[#all + 1] = widget end
        for _, widget in ipairs(other) do all[#all + 1] = widget end
        -- Reject rollover/replacement that occurred during synchronous construction.
        for i, id in ipairs(ids) do
            local live = assert(row_data(id), "daily roster changed during construction")
            assert(live.completed == rows[i].completed and live.progress[1] == rows[i].progress[1]
                and live.progress[2] == rows[i].progress[2], "daily progress changed during construction")
        end
        for key in pairs(original_query) do original_query[key] = nil end
        for key, value in pairs(query) do original_query[key] = value end
        view._achievement_widgets, view._claimable_challenge_widgets = all, available
        view._has_claimable_filtered_challenges = #available > 0 or nil
        view._achievement_scroll_value = nil
        owners[view] = { widgets = all, authored = authored }
        view:_update_achievements_scroll_height()
        view:_setup_achievement_entries_animations()
        if #all > 0 then view:_hide_empty_entries_warning() else view:_show_empty_entries_warning() end
    end

    mod:hook("HeroViewStateAchievements", "_create_entries", function(func, view, entries, kind, subtype, ...)
        local is_modded = realm()
        if kind ~= "quest" then
            if legacy_create then return legacy_create(func, view, entries, kind, subtype, ...) end
            return func(view, entries, kind, subtype, ...)
        end
        if is_modded == false then return func(view, entries, kind, subtype, ...) end
        if type(view) ~= "table" then return nil end
        if is_modded ~= true then clear(view, "realm_unavailable"); return nil end
        local ok, reason = pcall(build, view, entries, subtype)
        if not ok then clear(view, reason) end
        return nil
    end)

    mod:hook("HeroViewStateAchievements", "_handle_claim_all_challenges", function(func, view, ...)
        local is_modded = realm()
        if type(view) ~= "table" or view._achievement_layout_type ~= "quest" then
            if legacy_all then return legacy_all(func, view, ...) end
            return func(view, ...)
        end
        if is_modded == false then return func(view, ...) end
        local button = hide_claim_all(view)
        local owner = owners[view]
        if is_modded ~= true or not owner or view._achievement_widgets ~= owner.widgets then return nil end
        -- Native single-claim completion rebuilds rows, then deletes its old
        -- widget from the new claim list with index -1 (:1491-1505). Re-derive
        -- from authored visible rows at this existing final callback instead.
        local ok, reason = pcall(function()
            local available = {}
            for _, widget in ipairs(owner.widgets) do
                local id = owner.authored[widget]
                local content = widget.content
                local data = id and row_data(id)
                if data and data.completed == true and content.id == id and content.completed == true and content.claimed == false then
                    available[#available + 1] = widget
                end
            end
            view._claimable_challenge_widgets = available
            view._has_claimable_filtered_challenges = #available > 0 or nil
            if button and view._active_tab and #available > 0 and not pending(view) then button.visible = true end
        end)
        if not ok then
            view._claimable_challenge_widgets, view._has_claimable_filtered_challenges = {}, nil
            denied("claim_all", reason)
        end
        return nil
    end)

    local function release_failed_rows(view, ids)
        local owner = owners[view]
        if not owner or view._achievement_widgets ~= owner.widgets then return end
        local requested = {}
        -- A rejected duplicate/sparse array can still follow native pre-marks.
        -- Inspect only bounded raw members, never a foreign iterator/metatable.
        if type(ids) == "table" then
            for i = 1, MAX_ROWS do
                local id = rawget(ids, i)
                if type(id) == "string" then requested[id] = true end
            end
        end
        for _, widget in ipairs(owner.widgets) do
            local id = owner.authored[widget]
            if requested[id] and widget.content.id == id then widget.content.claiming = false end
        end
    end

    local function local_claim(view, supplied)
        local ids = array(supplied)
        local was_pending = type(view) == "table" and pending(view)
        local engaged = false
        local ok, result = pcall(function()
            assert(type(view) == "table" and ids and #ids > 0, "invalid claim id array")
            assert(not was_pending, "daily claim already pending")
            for _, id in ipairs(ids) do
                local data = assert(row_data(id), "foreign or stale daily claim")
                assert(data.completed == true, "daily quest is incomplete")
            end
            busy[view] = true
            engaged = true
            return capture(claim(ids))
        end)
        if engaged then busy[view] = nil end
        if not ok or not result[1] then
            if type(view) == "table" and not was_pending then release_failed_rows(view, supplied) end
            denied("claim", ok and result[2] or result)
            return nil, ok and result[2] or "Local daily claim unavailable."
        end
        return unpack(result, 1, result.n)
    end

    mod:hook("HeroViewStateAchievements", "_claim_quest_reward", function(func, view, id, ...)
        local is_modded = realm()
        if is_modded == false then return func(view, id, ...) end
        if is_modded ~= true then return nil, "Local daily realm unavailable." end
        return local_claim(view, { id })
    end)

    mod:hook("HeroViewStateAchievements", "_claim_multiple_quest_rewards", function(func, view, ids, ...)
        local is_modded = realm()
        if is_modded == false then return func(view, ids, ...) end
        if is_modded ~= true then
            if type(view) == "table" and not pending(view) then release_failed_rows(view, ids) end
            return nil, "Local daily realm unavailable."
        end
        return local_claim(view, ids)
    end)

    if type(deps.rt_register) == "function" then deps.rt_register(M.CHECK_NAME, M.runtime_check) end
end

function M.runtime_check()
    -- Detached callbacks only: no live native classes, globals or quest state.
    local hooks, claims = {}, 0
    local data = { id = "mp_daily_v2_probe", claimed = false, completed = true,
        name = "Daily", desc = "Description", progress = { 1, 1 },
        reward = { reward_type = "currency", currency_code = "SM", amount = 5 } }
    local daily = { REWARD_KIND = "SM", REWARD_AMOUNT = 5,
        find_by_id = function(id) if id == data.id then return { id=id, claimed=false, progress=1, target=1 } end end,
        quest_data = function(id) return id == data.id and data or nil end }
    M.install({ hook = function(_, class, method, fn) hooks[class .. "." .. method] = fn end }, {
        is_modded_realm = function() return true end, dailies = daily,
        local_claim = function() claims = claims + 1; return "mp_local_daily_claim_probe" end,
        ui = { widget = function() return { content={}, style={reward_icon={}} } end,
            parse=function(s) return s end, matches=function() return true end,
            currency=function() return {icon="shillings",rarity="common",item_type="chips",slot_type="chips"} end,
            background=function() return "icon_bg_common" end, dim=function() end },
    })
    local view = { _achievement_layout_type="quest", _active_tab={}, _search_query="",
        _search_widgets_by_name={filters={content={query={completed=true}}}},
        _additional_quest_widgets_by_name={claim_all_quests={content={}}},
        _update_achievements_scroll_height=function() end, _setup_achievement_entries_animations=function() end,
        _hide_empty_entries_warning=function() end, _show_empty_entries_warning=function() end }
    local function native() error("native daily UI entered") end
    hooks["HeroViewStateAchievements._create_entries"](native,view,{data.id},"quest",nil)
    if #view._achievement_widgets ~= 1 or view._achievement_widgets[1].content.can_close ~= false then
        return "completed local row was hidden or exposed unsupported reroll"
    end
    view._claimable_challenge_widgets = { [-1] = view._achievement_widgets[1] }
    hooks["HeroViewStateAchievements._handle_claim_all_challenges"](native,view)
    if #view._claimable_challenge_widgets ~= 1 or view._claimable_challenge_widgets[-1] ~= nil then
        return "native stale completion list was not reconciled"
    end
    local poll = hooks["HeroViewStateAchievements._claim_quest_reward"](native,view,data.id)
    if poll ~= "mp_local_daily_claim_probe" or claims ~= 1 then return "owned daily did not use local transaction" end
    hooks["HeroViewStateAchievements._claim_quest_reward"](native,view,"foreign_daily")
    if claims ~= 1 then return "foreign daily reached local transaction" end
end

return M
