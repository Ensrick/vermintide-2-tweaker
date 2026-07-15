local mod = get_mod("character_dialogue")
local MOD_VERSION = "0.1.0-dev"
local Policy = mod:dofile("scripts/mods/character_dialogue/_cd_policy")

local function log(fmt, ...)
    mod:debug("[cd:dbg] " .. fmt, ...)
end

local function warn(fmt, ...)
    mod:warning("[cd] " .. fmt, ...)
end

mod:info("[character_dialogue:LOAD] v%s enabled OK", MOD_VERSION)
mod:echo(string.format("[character_dialogue] v%s loaded", MOD_VERSION))

-- Sparse persistent tri-state overrides: true=force eligible, false=disable,
-- absent=vanilla. Stable Wwise event names are the keys, so catalogue reordering
-- and regenerated metadata cannot invalidate user choices.
local overrides = mod:get("line_overrides")
if type(overrides) ~= "table" then overrides = {} end

local preview = { world = nil, playing_id = nil, event = nil, paused = false }
local catalogue_cache
local options_cache

local function clone_table(source)
    local out = {}
    for k, v in pairs(source or {}) do out[k] = v end
    return out
end

local function set_override(event, state)
    if type(event) ~= "string" or event == "" then return false, "no dialogue selected" end
    if state ~= nil and type(state) ~= "boolean" then return false, "state must be true, false, or nil" end
    local next_overrides = clone_table(overrides)
    next_overrides[event] = state
    overrides = next_overrides
    mod:set("line_overrides", overrides)
    log("override event=%s state=%s entries=%d", event, tostring(state), table.size(overrides))
    return true
end

local function level_wwise_world()
    if not Managers or not Managers.world then return nil, nil end
    local world = Managers.world:world("level_world")
    if not world then return nil, nil end
    local ok, wwise_world = pcall(Managers.world.wwise_world, Managers.world, world)
    if not ok then return nil, nil end
    return world, wwise_world
end

local function stop_preview()
    if preview.playing_id and preview.world and WwiseWorld then
        pcall(WwiseWorld.stop_event, preview.world, preview.playing_id)
    end
    preview.world, preview.playing_id, preview.event, preview.paused = nil, nil, nil, false
    return true
end

local function play_preview(event)
    stop_preview()
    if type(event) ~= "string" or event == "" then return false, "no dialogue selected" end
    local _, wwise_world = level_wwise_world()
    if not wwise_world then return false, "level audio world is unavailable" end
    local ok, playing_id = pcall(WwiseWorld.trigger_event, wwise_world, event)
    if not ok or not playing_id or playing_id == 0 then
        printf("[character_dialogue:preview] unavailable event=%s error=%s", event, tostring(playing_id))
        return false, "sound event is not resident in this game state"
    end
    preview.world, preview.playing_id, preview.event, preview.paused = wwise_world, playing_id, event, false
    printf("[character_dialogue:preview] play event=%s id=%s", event, tostring(playing_id))
    return true
end

local function pause_preview()
    if not preview.playing_id or preview.paused then return false, "nothing is playing" end
    local ok = pcall(WwiseWorld.pause_event, preview.world, preview.playing_id)
    if ok then preview.paused = true end
    return ok
end

local function resume_preview()
    if not preview.playing_id or not preview.paused then return false, "nothing is paused" end
    local ok = pcall(WwiseWorld.resume_event, preview.world, preview.playing_id)
    if ok then preview.paused = false end
    return ok
end

local function catalogue()
    if not catalogue_cache then
        catalogue_cache = mod:dofile("scripts/mods/character_dialogue/character_dialogue_catalogue")
        log("catalogue loaded entries=%d", type(catalogue_cache) == "table" and #catalogue_cache or -1)
    end
    return catalogue_cache or {}
end

local function dialogue_options()
    if options_cache then return options_cache end
    local entries = catalogue()
    local out = {}
    for i = 1, #entries do
        local tuple = entries[i]
        local event, source = tuple[1], tuple[4]
        out[i] = { value = event, text = event .. "  [" .. tostring(source or "unknown") .. "]" }
    end
    options_cache = out
    return out
end

local function selected_event()
    for _, gut_id in ipairs({ "gut_dev", "gut" }) do
        local gut = get_mod(gut_id)
        local mt = gut and gut.mod_tweaker
        if mt and mt.get then
            local value = mt:get("character_dialogue", "selected_line")
            if type(value) == "string" and value ~= "" then return value end
        end
    end
    local entries = catalogue()
    return entries[1] and entries[1][1] or nil
end

local function action_result(action, ok, err)
    printf("[character_dialogue:ui] action=%s event=%s ok=%s detail=%s",
        action, tostring(selected_event()), tostring(ok), tostring(err or ""))
end

local function register_mod_tweaker()
    for _, gut_id in ipairs({ "gut_dev", "gut" }) do
        local gut = get_mod(gut_id)
        local mt = gut and gut.mod_tweaker
        if mt and mt.register_category and not mt:is_registered("character_dialogue") then
            local ok, err = mt:register_category({
                mod_id = "character_dialogue",
                label = "Dialogue",
                widgets = {
                    {
                        setting_id = "selected_line", type = "dropdown", label = "Dialogue line",
                        default = "", options_provider = dialogue_options,
                        tooltip = "Type while the list is open to search all extracted dialogue events.",
                    },
                    { setting_id = "play", type = "action", label = "Play", button_text = "PLAY", on_activate = function()
                        local ok2, err2 = play_preview(selected_event()); action_result("play", ok2, err2)
                    end },
                    { setting_id = "pause", type = "action", label = "Pause / Resume", button_text = "PAUSE", on_activate = function()
                        local ok2, err2 = preview.paused and resume_preview() or pause_preview(); action_result("pause_resume", ok2, err2)
                    end },
                    { setting_id = "stop", type = "action", label = "Stop", button_text = "STOP", on_activate = function()
                        action_result("stop", stop_preview())
                    end },
                    { setting_id = "enable", type = "action", label = "Enable selected line", button_text = "ENABLE", on_activate = function()
                        local ok2, err2 = set_override(selected_event(), true); action_result("enable", ok2, err2)
                    end },
                    { setting_id = "disable", type = "action", label = "Disable selected line", button_text = "DISABLE", on_activate = function()
                        local ok2, err2 = set_override(selected_event(), false); action_result("disable", ok2, err2)
                    end },
                    { setting_id = "inherit", type = "action", label = "Use game default", button_text = "DEFAULT", on_activate = function()
                        local ok2, err2 = set_override(selected_event(), nil); action_result("inherit", ok2, err2)
                    end },
                },
            })
            if ok then
                log("registered Dialogue tab with %s", gut_id)
                return true
            end
            warn("Dialogue tab registration failed: %s", tostring(err))
        end
    end
    return false
end

-- Host-authoritative natural selection. Preserve vanilla byte-for-byte when a
-- group has no user overrides. With overrides, inspect at most sound_events_n
-- candidates: explicit enable bypasses Fatshark's per-line filter, explicit
-- disable rejects, and inherited lines still use the vanilla filter.
mod:hook(DialogueQueries, "get_filtered_dialogue_event_index", function(func, dialogue, context, global_filters)
    local index, used = Policy.choose_index(dialogue, overrides,
        function() return DialogueQueries.get_dialogue_event_index(dialogue, true) end,
        function(i) return DialogueQueries.filter_sound_event(dialogue, i, context, global_filters) end)
    if not used then return func(dialogue, context, global_filters) end
    -- The all-explicitly-disabled case is removed at TagQueryDatabase below.
    -- Otherwise retain vanilla's historical fallback behavior and never pass a
    -- nil index into DialogueSystem's network/duration path.
    return index or 1
end)

mod:hook(TagQueryDatabase, "iterate_query", function(func, self, t)
    local query = func(self, t)
    if not query or not query.result then return query end
    local entity = Managers and Managers.state and Managers.state.entity
    local system = entity and entity:system("dialogue_system")
    local dialogue = system and system._dialogues and system._dialogues[query.result]
    if not dialogue then return query end
    if Policy.all_disabled(dialogue, overrides) then
        printf("[character_dialogue:natural] suppressed group=%s reason=all_lines_disabled", tostring(query.result))
        query.result = nil
        query.validated_rule = nil
    end
    return query
end)

mod.character_dialogue_api = {
    version = 1,
    catalogue = catalogue,
    dialogue_options = dialogue_options,
    get_line_state = function(event) return overrides[event] end,
    set_line_state = set_override,
    play = play_preview,
    pause = pause_preview,
    resume = resume_preview,
    stop = stop_preview,
    preview_state = function() return preview.event, preview.paused, preview.playing_id end,
}

mod:command("cd_play", "Preview a dialogue event locally. Usage: /cd_play <event>", function(event)
    local ok, err = play_preview(event); if not ok then mod:echo("Character Dialogue: " .. tostring(err)) end
end)
mod:command("cd_pause", "Pause or resume the local preview", function()
    local ok, err = preview.paused and resume_preview() or pause_preview(); if not ok then mod:echo("Character Dialogue: " .. tostring(err)) end
end)
mod:command("cd_stop", "Stop the local dialogue preview", stop_preview)
mod:command("cd_line", "Set a line: /cd_line <event> enable|disable|default", function(event, state)
    local value = state == "enable" and true or state == "disable" and false or nil
    local ok, err = set_override(event, value); if not ok then mod:echo("Character Dialogue: " .. tostring(err)) end
end)
mod:command("cd_regression_test", "Character Dialogue self-check", function()
    local failures = 0
    local entries = catalogue()
    local seen = {}
    for i = 1, #entries do
        local id = entries[i][1]
        if type(id) ~= "string" or id == "" or seen[id] then failures = failures + 1; break end
        seen[id] = true
    end
    mod:echo("Character Dialogue v%s: catalogue=%d overrides=%d failures=%d", MOD_VERSION, #entries, table.size(overrides), failures)
end)

mod.on_all_mods_loaded = function() register_mod_tweaker() end
mod.on_game_state_changed = function(status)
    stop_preview()
    if status == "enter" then register_mod_tweaker() end
end
mod.on_disabled = stop_preview
