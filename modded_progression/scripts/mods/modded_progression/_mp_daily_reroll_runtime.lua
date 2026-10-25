-- #1684/#573: MP owns rotation, but does not implement a local daily reroll.
-- Native 6.13 calls refreshQuest with no EAC challenge at
-- backend_interface_quests_playfab.lua:201-212. Do not expose that action.
-- No engine/account protection flag, quest, clock or ledger is changed here.
local M = { CHECK_NAME = "issue1684_daily_reroll_backend_boundary" }

function M.install(mod, deps)
    assert(type(mod) == "table" and type(mod.hook) == "function", "MP hook owner missing")
    assert(type(deps) == "table" and type(deps.is_modded_realm) == "function",
        "MP realm query missing")
    local warned = {}

    local function denied(stage, reason)
        if not warned[stage] then
            warned[stage] = true
            if type(deps.print_log) == "function" then
                pcall(deps.print_log,
                    "[mp:1684] daily_reroll_denied stage=%s reason=%s backend=none",
                    stage, reason)
            end
        end
    end

    -- Only an explicit, successfully read official realm may enter vanilla.
    -- A throwing or malformed ownership reader must not become permission.
    local function realm()
        local ok, value = pcall(deps.is_modded_realm)
        if ok and type(value) == "boolean" then return value end
        return nil
    end

    mod:hook("BackendInterfaceQuestsPlayfab", "can_refresh_daily_quest",
        function(func, self, ...)
            local is_modded = realm()
            if is_modded == false then return func(self, ...) end
            if is_modded == nil then denied("availability", "realm_unavailable") end
            return false
        end)

    mod:hook("BackendInterfaceQuestsPlayfab", "refresh_daily_quest",
        function(func, self, ...)
            local is_modded = realm()
            if is_modded == false then return func(self, ...) end
            denied("backend", is_modded and "local_reroll_unavailable" or "realm_unavailable")
            return nil
        end)

    -- Normally the backend availability answer makes native _create_entries
    -- set content.can_close=false. Also correct stale/already-created rows at
    -- their action boundary: native would block input even when the denied
    -- backend returned no poll id (hero_view_state_achievements.lua:1219-1228).
    mod:hook("HeroViewStateAchievements", "_on_achievement_pressed",
        function(func, self, widget, ...)
            local is_modded = realm()
            if is_modded == false then return func(self, widget, ...) end
            if is_modded == nil then
                denied("ui", "realm_unavailable")
                return nil
            end
            local content = type(widget) == "table" and rawget(widget, "content")
            if type(content) ~= "table" then
                denied("ui", "row_unavailable")
                return nil
            end
            local close = rawget(content, "close_button_hotspot")
            local reroll_hovered = rawget(content, "can_close")
                and type(close) == "table" and rawget(close, "is_hover")
            rawset(content, "can_close", false)
            -- Hidden hotspot passes need not run again to reset their hover.
            -- Consume only the original close intent; never let its stale hover
            -- swallow a later normal claim/expand action on this row.
            if type(close) == "table" then rawset(close, "is_hover", false) end
            if reroll_hovered then
                denied("ui", "local_reroll_unavailable")
                return nil
            end
            return func(self, widget, ...)
        end)

    if type(deps.rt_register) == "function" then
        deps.rt_register(M.CHECK_NAME, M.runtime_check)
    end
end

-- Executes the installed production callbacks in a detached owner; never
-- changes live realm flags, engine globals, native classes or player state.
function M.runtime_check()
    local hooks, calls, is_modded = {}, 0, true
    local owner = { hook = function(_, class, method, fn)
        hooks[class .. "." .. method] = fn
    end }
    M.install(owner, { is_modded_realm = function() return is_modded end })
    local function native() calls = calls + 1; return 1, nil, 3, nil end
    local can = hooks["BackendInterfaceQuestsPlayfab.can_refresh_daily_quest"]
    local reroll = hooks["BackendInterfaceQuestsPlayfab.refresh_daily_quest"]
    local ui = hooks["HeroViewStateAchievements._on_achievement_pressed"]
    if can(native, {}) ~= false or reroll(native, {}, "foreign_daily") ~= nil then
        return "modded daily reroll was not refused"
    end
    local row = { content = { can_close = true, close_button_hotspot = { is_hover = true } } }
    ui(native, {}, row)
    if calls ~= 0 or row.content.can_close ~= false
            or row.content.close_button_hotspot.is_hover ~= false then
        return "stale daily reroll entered native UI or kept its affordance"
    end
    ui(native, {}, row)
    if calls ~= 1 then return "denied close swallowed the next normal row action" end
    is_modded = false
    local count, values = (function(...) return select("#", ...), { ... } end)(reroll(native, {}))
    if calls ~= 2 or count ~= 4 or values[1] ~= 1 or values[2] ~= nil or values[3] ~= 3 then
        return "official daily reroll lost native delegation/return tuple"
    end
end

return M
