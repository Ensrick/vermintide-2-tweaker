return function(H, repo_root, runtime_path, entry_source)
local source_path = runtime_path or (repo_root
    .. "/modded_progression/scripts/mods/modded_progression/_mp_daily_reroll_runtime.lua")
local protection_reads, protection_writes = 0, 0
local protection = setmetatable({}, {
    __index = function() protection_reads = protection_reads + 1; error("native protection read") end,
    __newindex = function() protection_writes = protection_writes + 1; error("native protection write") end,
})
local environment = setmetatable({
    GameSettingsDevelopment = protection, script_data = protection,
}, { __index = _G })
environment._G = environment
local runtime_chunk = assert(loadfile(source_path))
setfenv(runtime_chunk, environment)
local Runtime = runtime_chunk()

local function pack(...) return { n = select("#", ...), ... } end

local function install(query, print_log)
    local hooks, counts, checks, logs = {}, {}, {}, {}
    Runtime.install({ hook = function(_, class, method, fn)
        local key = class .. "." .. method
        counts[key] = (counts[key] or 0) + 1
        assert(counts[key] == 1, "duplicate installed hook " .. key)
        hooks[key] = fn
    end }, {
        is_modded_realm = query,
        rt_register = function(name, fn) checks[name] = fn end,
        print_log = print_log or function(fmt, ...) logs[#logs + 1] = string.format(fmt, ...) end,
    })
    return { hooks = hooks, checks = checks, logs = logs }
end

local CAN = "BackendInterfaceQuestsPlayfab.can_refresh_daily_quest"
local REROLL = "BackendInterfaceQuestsPlayfab.refresh_daily_quest"
local UI = "HeroViewStateAchievements._on_achievement_pressed"
local function row(id, hovered)
    return { content = { id = id, can_close = true,
        close_button_hotspot = { is_hover = hovered } } }
end

H.test("MP #1684 installs exactly the availability action and stale-row boundaries", function()
    local r = install(function() return true end)
    local count = 0
    for _ in pairs(r.hooks) do count = count + 1 end
    H.equal(count, 3)
    H.equal(type(r.checks[Runtime.CHECK_NAME]), "function")
    H.equal(r.checks[Runtime.CHECK_NAME](), nil)
end)

H.test("MP #1684 modded daily availability does not read native account state", function()
    local r = install(function() return true end)
    local native = function() error("official availability reader entered") end
    H.equal(r.hooks[CAN](native, setmetatable({}, { __index = native })), false)
end)

for _, case in ipairs({
    { name = "owned", id = "mp_daily_v2_20647_1_daily_collect_tomes" },
    { name = "foreign", id = "daily_collect_tomes" },
    { name = "unknown", id = "not_a_quest" },
    { name = "malformed", id = {} },
    { name = "missing" },
}) do
    local spec = case
    H.test("MP #1684 direct modded " .. spec.name .. " reroll never enters backend", function()
        local r = install(function() return true end)
        local backend = { _id = 12, _refresh_requests = {}, _dirty = false }
        local called = 0
        local result = pack(r.hooks[REROLL](function()
            called = called + 1
            error("official refreshQuest write entered")
        end, backend, spec.id, nil, "tail"))
        H.equal(called, 0)
        H.equal(result.n, 1)
        H.equal(result[1], nil)
        H.equal(backend._id, 12)
        H.deep_equal(backend._refresh_requests, {})
        H.equal(backend._dirty, false)
    end)
    H.test("MP #1684 stale " .. spec.name .. " reroll row cannot block UI or write", function()
        local r = install(function() return true end)
        local widget = row(spec.id, true)
        local native_calls = 0
        local self = { _quest_refresh_poll_id = nil, blocked = false }
        r.hooks[UI](function()
            native_calls = native_calls + 1
            self.blocked = true
            error("native reroll UI entered")
        end, self, widget)
        H.equal(widget.content.can_close, false)
        H.equal(native_calls, 0)
        H.equal(self.blocked, false)
        H.equal(self._quest_refresh_poll_id, nil)
    end)
end

for _, value in ipairs({ { name = "throw", query = function() error("private reader failure") end },
    { name = "nil", query = function() return nil end },
    { name = "truthy string", query = function() return "false" end },
    { name = "number", query = function() return 0 end } }) do
    local spec = value
    H.test("MP #1684 " .. spec.name .. " realm reader fails closed at every action", function()
        local r = install(spec.query)
        local calls = 0
        local native = function() calls = calls + 1; error("official action entered") end
        H.equal(r.hooks[CAN](native, {}), false)
        H.equal(r.hooks[REROLL](native, {}, "daily_collect_tomes"), nil)
        H.equal(r.hooks[UI](native, {}, row("daily_collect_tomes", true)), nil)
        H.equal(calls, 0)
        H.equal(table.concat(r.logs, "\n"):find("private reader failure", 1, true), nil)
    end)
end

for _, key in ipairs({ CAN, REROLL, UI }) do
    local method = key
    H.test("MP #1684 official " .. method .. " preserves all arguments and nil holes", function()
        local r = install(function() return false end)
        local self, widget, token = {}, row("daily_collect_tomes", true), {}
        local seen
        local result = pack(r.hooks[method](function(...)
            seen = pack(...)
            return token, nil, 3, nil
        end, self, widget, nil, "tail", nil))
        H.equal(seen.n, 5)
        H.equal(seen[1], self)
        H.equal(seen[2], widget)
        H.equal(seen[3], nil)
        H.equal(seen[4], "tail")
        H.equal(result.n, 4)
        H.equal(result[1], token)
        H.equal(result[2], nil)
        H.equal(result[3], 3)
        H.equal(result[4], nil)
        H.equal(widget.content.can_close, true)
        H.equal(widget.content.close_button_hotspot.is_hover, true)
        H.equal(#r.logs, 0)
    end)
    H.test("MP #1684 official " .. method .. " preserves native exceptions", function()
        local r = install(function() return false end)
        local token = {}
        local ok, failure = pcall(r.hooks[method], function() error(token) end, {})
        H.equal(ok, false)
        H.equal(failure, token)
    end)
end

H.test("MP #1684 normal modded row actions delegate after reroll affordance removal", function()
    local r = install(function() return true end)
    local widget = row("mp_daily_v2_20647_1_daily_collect_tomes", false)
    local token, calls = {}, 0
    local values = pack(r.hooks[UI](function(_, received, ...)
        calls = calls + 1
        H.equal(received, widget)
        H.equal(received.content.can_close, false)
        H.equal(select("#", ...), 2)
        return token, nil, 7, nil
    end, {}, widget, "tail", nil))
    H.equal(calls, 1)
    H.equal(values.n, 4)
    H.equal(values[1], token)
    H.equal(values[3], 7)
end)

H.test("MP #1684 missing or metamethod-only UI rows cannot enter native actions", function()
    local r = install(function() return true end)
    local native = function() error("native UI entered") end
    H.equal(r.hooks[UI](native, {}, nil), nil)
    H.equal(r.hooks[UI](native, {}, setmetatable({}, {
        __index = function() error("private row reader") end,
    })), nil)
    H.equal(r.hooks[UI](native, {}, { content = "malformed" }), nil)
end)

for _, kind in ipairs({ "claim", "expand" }) do
    for _, initial in ipairs({ "denied close", "already hidden" }) do
        local action, origin = kind, initial
        H.test("MP #1684 " .. origin .. " cannot swallow later " .. action, function()
            local r = install(function() return true end)
            local widget = row("mp_daily_v2_probe", true)
            if origin == "denied close" then
                r.hooks[UI](function() error("denied close reached native") end, {}, widget)
                H.equal(widget.content.close_button_hotspot.is_hover, false)
            else
                widget.content.can_close = false
            end
            -- An invisible pass may retain (or be handed) a stale hover. Its
            -- state must not count as a new close intent when can_close=false.
            widget.content.close_button_hotspot.is_hover = true
            local calls, token = 0, {}
            local result = pack(r.hooks[UI](function(_, received, ...)
                calls = calls + 1
                H.equal(received, widget)
                H.equal(received.content.can_close, false)
                H.equal(received.content.close_button_hotspot.is_hover, false)
                H.equal(select("#", ...), 2)
                return token, nil, 9, nil
            end, {}, widget, action, nil))
            H.equal(calls, 1)
            H.equal(result.n, 4)
            H.equal(result[1], token)
            H.equal(result[3], 9)
        end)
    end
end

H.test("MP #1684 contained denial logging is bounded and never changes protection", function()
    local queries, writes, log_calls = 0, 0, 0
    local native = function() writes = writes + 1; error("official request entered") end
    local r = install(function() queries = queries + 1; return true end, function()
        log_calls = log_calls + 1
        error("injected log failure")
    end)
    for _ = 1, 5 do
        r.hooks[REROLL](native, {}, "foreign_quest")
        r.hooks[UI](native, {}, row("foreign_quest", true))
    end
    H.equal(queries, 10)
    H.equal(writes, 0)
    H.equal(log_calls, 2)
    H.equal(protection_reads, 0)
    H.equal(protection_writes, 0)
    H.equal(next(protection), nil)
    H.equal(rawget(environment, "MODDED_REALM"), nil)
    H.equal(rawget(environment, "GameSettingsDevelopment"), protection)
    H.equal(rawget(environment, "script_data"), protection)
end)

-- Optional source provenance: execute the real 6.13 request producer and UI
-- handler in isolated environments. The mandatory tests above do not depend
-- on having the native source checkout on CI.
local native_root = repo_root .. "/../Vermintide-2-Source-Code/"
local function read(path)
    local file = io.open(path, "rb")
    if not file then return nil end
    local source = file:read("*a"); file:close()
    return (source:gsub("\r\n", "\n"))
end
local entry = entry_source or assert(read(repo_root
    .. "/modded_progression/scripts/mods/modded_progression/modded_progression.lua"))
local install_expression = assert(entry:match(
    '(mod:dofile%("scripts/mods/modded_progression/_mp_daily_reroll_runtime"%)%.install%b())'),
    "entry-to-reroll-owner install missing")
local wiring = assert(loadstring(
    "local mod, _is_mp_realm, _rt_register, printf, rawget, _G, type = ...\nreturn "
        .. install_expression, "=mp1684_actual_entry_install"))

for _, value in ipairs({
    { name = "native modded", native = true, legacy = false, allowed = false },
    { name = "native official", native = false, legacy = true, allowed = true },
    { name = "malformed native", native = "false", legacy = false, allowed = false },
    { name = "legacy modded", legacy = true, allowed = false },
    { name = "legacy official", legacy = false, allowed = true },
}) do
    local spec = value
    H.test("MP #1684 actual entry install respects " .. spec.name .. " authority", function()
        local hooks, legacy_calls, dofiles, writes = {}, 0, 0, 0
        local mod = {
            dofile = function(_, path)
                dofiles = dofiles + 1
                H.equal(path, "scripts/mods/modded_progression/_mp_daily_reroll_runtime")
                return Runtime
            end,
            hook = function(_, class, method, fn) hooks[class .. "." .. method] = fn end,
        }
        wiring(mod, function() legacy_calls = legacy_calls + 1; return spec.legacy end,
            function() end, function() end, rawget, { MODDED_REALM = spec.native }, type)
        H.equal(dofiles, 1)
        hooks[REROLL](function() writes = writes + 1 end, {}, "foreign_daily")
        H.equal(writes, spec.allowed and 1 or 0)
        H.equal(legacy_calls, spec.native == nil and 1 or 0)
    end)
end

local backend_source = read(native_root
    .. "scripts/managers/backend_playfab/backend_interface_quests_playfab.lua")
local ui_source = read(native_root
    .. "scripts/ui/views/hero_view/states/hero_view_state_achievements.lua")
H.test_if(backend_source ~= nil and ui_source ~= nil,
    "MP #1684 exact native producer enqueues locally unless installed guard denies", function()
    local producer = assert(backend_source:match(
        "BackendInterfaceQuestsPlayfab%.refresh_daily_quest = (function.-)\n\nBackendInterfaceQuestsPlayfab%.refresh_quest_cb"))
    local handler = assert(ui_source:match(
        "HeroViewStateAchievements%._on_achievement_pressed = (function.-)\n\nHeroViewStateAchievements%._claim_reward"))
    local native_chunk = assert(loadstring("return " .. producer, "=native_6_13_reroll"))
    setfenv(native_chunk, { callback = function() return function() end end })
    local native_reroll = native_chunk()
    local ui_chunk = assert(loadstring("return " .. handler, "=native_6_13_reroll_ui"))
    setfenv(ui_chunk, {})
    local native_ui = ui_chunk()
    local native_requests = {}
    local backend = {
        _new_id = function(self) self.serial = self.serial + 1; return self.serial end,
        serial = 0,
        _backend_mirror = { request_queue = function() return {
            enqueue = function(_, request, _, eac)
                native_requests[#native_requests + 1] = { request = request, eac = eac }
            end,
        } end },
    }
    -- Positive control proves the real producer is connected to the fake queue.
    H.equal(native_reroll(backend, "daily_collect_tomes"), 1)
    H.equal(native_requests[1].request.FunctionName, "refreshQuest")
    H.equal(native_requests[1].eac, false)
    local r = install(function() return true end)
    H.equal(r.hooks[REROLL](native_reroll, backend, "daily_collect_tomes"), nil)
    H.equal(backend.serial, 1)
    H.equal(#native_requests, 1)
    local blocked = false
    local self = { _quest_manager = { refresh_daily_quest = function(_, id)
        return r.hooks[REROLL](native_reroll, backend, id)
    end }, block_input = function() blocked = true end,
        play_sound = function() end }
    local widget = row("daily_collect_tomes", true)
    -- Positive UI control: backend-only denial leaves native UI blocked while
    -- its poll id is nil. This is why the stale-row action wrapper is required.
    native_ui(self, widget)
    H.equal(blocked, true)
    H.equal(self._quest_refresh_poll_id, nil)
    H.equal(#native_requests, 1)
    blocked = false
    r.hooks[UI](native_ui, self, widget)
    H.equal(blocked, false)
    H.equal(self._quest_refresh_poll_id, nil)
    H.equal(#native_requests, 1)
end, "optional source checkout unavailable")

for _, kind in ipairs({ "claim", "expand" }) do
    for _, initial in ipairs({ "denied close", "already hidden" }) do
        local action, origin = kind, initial
        H.test_if(ui_source ~= nil,
            "MP #1684 exact native " .. action .. " survives " .. origin, function()
            local handler = assert(ui_source:match(
                "HeroViewStateAchievements%._on_achievement_pressed = (function.-)\n\nHeroViewStateAchievements%._claim_reward"))
            local chunk = assert(loadstring("return " .. handler, "=native_6_13_normal_quest_action"))
            -- Geometry is a declared numeric boundary, not rendered-layout
            -- verification. The actual native handler owns all branch logic.
            setfenv(chunk, { math = math, ACHIEVEMENT_WINDOW_HEIGHT = 400,
                ACHIEVEMENT_DEFAULT_HEIGHT = 50 })
            local native_ui = chunk()
            local r = install(function() return true end)
            local claims, scrolls, blocked = 0, 0, 0
            local self = {
                total_scroll_height = 1000, scroll_value = 0,
                _quest_manager = { refresh_daily_quest = function()
                    error("native reroll entered during normal action")
                end },
                block_input = function() blocked = blocked + 1 end,
                play_sound = function() end,
                _claim_reward = function() claims = claims + 1 end,
                _get_achievement_entries_height = function() return 1400 end,
                _update_achievements_scroll_height = function() scrolls = scrolls + 1 end,
            }
            local widget = row("mp_daily_v2_probe", true)
            widget.style, widget.offset = {}, { 0, 0, 0 }
            widget.content.progress_button_hotspot = { is_hover = false }
            widget.content.expandable, widget.content.expanded = true, false
            widget.content.expand_height = 100
            if origin == "denied close" then
                r.hooks[UI](native_ui, self, widget)
                H.equal(widget.content.close_button_hotspot.is_hover, false)
                H.equal(claims + scrolls + blocked, 0)
            else
                widget.content.can_close = false
            end
            widget.content.close_button_hotspot.is_hover = true
            widget.content.progress_button_hotspot.is_hover = action == "claim"
            r.hooks[UI](native_ui, self, widget)
            H.equal(blocked, 0)
            H.equal(claims, action == "claim" and 1 or 0)
            H.equal(scrolls, action == "expand" and 1 or 0)
            H.equal(widget.content.expanded, action == "expand")
            H.equal(widget.content.close_button_hotspot.is_hover, false)
            H.equal(widget.content.progress_button_hotspot.is_hover, false)
        end, "optional source checkout unavailable")
    end
end
end
