local mod = get_mod("character_dialogue")
local MOD_VERSION = "0.1.7-dev"
-- Fatshark keeps DialogueQueries local to dialogue_system.lua; it is not a
-- global like TagQueryDatabase.  Resolve the canonical module before asking
-- VMF to install the hook, otherwise VMF receives nil and emits a startup
-- error on every launch.
local DialogueQueries = require("scripts/entity_system/systems/dialogues/dialogue_queries")
local Policy = mod:dofile("scripts/mods/character_dialogue/_cd_policy")
local Browser = mod:dofile("scripts/mods/character_dialogue/_cd_browser")
local PreviewPolicy = mod:dofile("scripts/mods/character_dialogue/_cd_preview_policy")
local PreviewResidency = mod:dofile("scripts/mods/character_dialogue/_cd_preview_residency")

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

local preview = {
    world = nil, playing_id = nil, event = nil, paused = false,
    elapsed = 0, duration = 0,
}
local preview_residency = PreviewResidency.new_state()
local catalogue_cache
local catalogue_index_cache
local catalogue_index
local browser_group_cache = { query = nil, groups = nil }

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

local function release_preview_package(keep_package)
    local package_name = preview_residency.package
    if not package_name or package_name == keep_package or not preview_residency.acquired then return true end
    local package_manager = Managers and Managers.package
    if not package_manager then return false end
    local ok_loaded, loaded = pcall(package_manager.has_loaded, package_manager,
        package_name, PreviewResidency.REFERENCE)
    local ok_loading, loading = pcall(package_manager.is_loading, package_manager,
        package_name, PreviewResidency.REFERENCE)
    if not ((ok_loaded and loaded) or (ok_loading and loading)) then return true end
    local ok, err = pcall(package_manager.unload, package_manager,
        package_name, PreviewResidency.REFERENCE)
    printf("[cd:881] package_release package=%s ok=%s error=%s",
        package_name, tostring(ok), tostring(err))
    if not ok then
        printf("[cd:881] package_release_retry package=%s reason=unload_failed", package_name)
    end
    return ok
end

local function finish_package_release(released, keep_package)
    if released then
        PreviewResidency.cancel(preview_residency, keep_package)
    else
        -- Clear stale click ownership but retain the exact package/reference so
        -- a later stop/disable/unload boundary can retry the symmetric release.
        PreviewResidency.cancel(preview_residency, preview_residency.package)
    end
end

local function stop_preview(keep_package)
    if preview.playing_id and preview.world and WwiseWorld then
        pcall(WwiseWorld.stop_event, preview.world, preview.playing_id)
    end
    local next_state = PreviewPolicy.transition(preview, "stop")
    preview.world, preview.playing_id = nil, nil
    preview.event, preview.paused = next_state.event, next_state.paused
    preview.elapsed, preview.duration = 0, 0
    finish_package_release(release_preview_package(keep_package), keep_package)
    return true
end

local function trigger_preview(event)
    local next_state, _, validation_error = PreviewPolicy.transition(preview, "play", event)
    if validation_error then return false, validation_error end
    local _, wwise_world = level_wwise_world()
    if not wwise_world then
        printf("[character_dialogue:preview] no_audio_world event=%s", tostring(event))
        return false, "level audio world is unavailable"
    end
    local ok, playing_id = pcall(WwiseWorld.trigger_event, wwise_world, event)
    if not ok or not playing_id or playing_id == 0 then
        printf("[character_dialogue:preview] unavailable event=%s error=%s", event, tostring(playing_id))
        return false, "sound event is not resident in this game state"
    end
    preview.world, preview.playing_id = wwise_world, playing_id
    preview.event, preview.paused = next_state.event, next_state.paused
    local fallback = DialogueSettings and DialogueSettings.sound_event_default_length or 4.5
    preview.elapsed = 0
    preview.duration = Browser.duration_for(catalogue_index(), event, fallback)
    printf("[character_dialogue:preview] play event=%s id=%s", event, tostring(playing_id))
    return true
end

local function package_status(package_name)
    local package_manager = Managers and Managers.package
    if not package_manager or not package_name then return package_manager, false, false end
    local ok_loaded, loaded = pcall(package_manager.has_loaded, package_manager,
        package_name, PreviewResidency.REFERENCE)
    local ok_loading, loading = pcall(package_manager.is_loading, package_manager,
        package_name, PreviewResidency.REFERENCE)
    return package_manager, ok_loaded and loaded == true, ok_loading and loading == true
end

local function trigger_owned_preview(event)
    local ok, err = trigger_preview(event)
    if not ok then
        finish_package_release(release_preview_package(nil), nil)
    end
    return ok, err
end

local function play_preview(event)
    local _, _, validation_error = PreviewPolicy.transition(preview, "play", event)
    if validation_error then
        printf("[character_dialogue:preview] rejected event=%s reason=%s", tostring(event), validation_error)
        return false, validation_error
    end

    local tuple = catalogue_index().by_event[event]
    local source = tuple and tuple[4]
    local package_name = PreviewResidency.package_for_source(source)
    stop_preview(package_name)

    if not package_name then return trigger_preview(event) end

    local package_manager, owned_loaded, owned_loading = package_status(package_name)
    local action, direct_event = PreviewResidency.request(preview_residency, event, source,
        owned_loaded, owned_loading)
    if owned_loaded or owned_loading then preview_residency.acquired = true end

    if action == "load" then
        if not package_manager then
            PreviewResidency.cancel(preview_residency)
            return false, "package manager is unavailable"
        end
        local ok, err = pcall(package_manager.load, package_manager, package_name,
            PreviewResidency.REFERENCE, nil, true, false)
        if not ok then
            printf("[cd:881] package_queue_failed event=%s source=%s package=%s error=%s",
                event, tostring(source), package_name, tostring(err))
            PreviewResidency.cancel(preview_residency)
            return false, "dialogue soundbank could not be queued"
        end
        preview_residency.acquired = true
        local _, loaded_after = package_status(package_name)
        if loaded_after then
            PreviewResidency.cancel(preview_residency, package_name)
            printf("[cd:881] package_ready event=%s source=%s package=%s path=synchronous",
                event, tostring(source), package_name)
            return trigger_owned_preview(event)
        end
        printf("[cd:881] package_queued event=%s source=%s package=%s",
            event, tostring(source), package_name)
        return true, "loading dialogue soundbank"
    end
    if action == "pending" then
        printf("[cd:881] package_wait event=%s source=%s package=%s",
            event, tostring(source), package_name)
        return true, "loading dialogue soundbank"
    end
    return trigger_owned_preview(direct_event)
end

local function poll_preview_residency(dt)
    if not preview_residency.pending_event then return end
    local package_name = preview_residency.package
    local _, owned_loaded, owned_loading = package_status(package_name)
    local action, event, err = PreviewResidency.poll(preview_residency, dt,
        owned_loaded, owned_loading)
    if action == "ready" then
        printf("[cd:881] package_ready event=%s package=%s path=asynchronous",
            tostring(event), tostring(package_name))
        local ok, trigger_err = trigger_owned_preview(event)
        if not ok then
            printf("[cd:881] retry_unavailable event=%s package=%s error=%s",
                tostring(event), tostring(package_name), tostring(trigger_err))
        end
    elseif action == "failed" then
        printf("[cd:881] package_load_failed event=%s package=%s error=%s",
            tostring(event), tostring(package_name), tostring(err))
        finish_package_release(release_preview_package(nil), nil)
    end
end

local function pause_preview()
    local next_state, _, validation_error = PreviewPolicy.transition(preview, "pause")
    if not preview.playing_id or validation_error then return false, validation_error or "nothing is playing" end
    local ok = pcall(WwiseWorld.pause_event, preview.world, preview.playing_id)
    if ok then preview.paused = next_state.paused end
    return ok
end

local function resume_preview()
    local next_state, _, validation_error = PreviewPolicy.transition(preview, "resume")
    if not preview.playing_id or validation_error then return false, validation_error or "nothing is paused" end
    local ok = pcall(WwiseWorld.resume_event, preview.world, preview.playing_id)
    if ok then preview.paused = next_state.paused end
    return ok
end

local function catalogue()
    if not catalogue_cache then
        catalogue_cache = mod:dofile("scripts/mods/character_dialogue/character_dialogue_catalogue")
        log("catalogue loaded entries=%d", type(catalogue_cache) == "table" and #catalogue_cache or -1)
    end
    return catalogue_cache or {}
end

catalogue_index = function()
    if not catalogue_index_cache then
        catalogue_index_cache = Browser.build_index(catalogue())
        log("browser index built entries=%d", catalogue_index_cache.total or -1)
    end
    return catalogue_index_cache
end

local function toggle_pause(event)
    if preview.event ~= event then return play_preview(event) end
    return preview.paused and resume_preview() or pause_preview()
end

-- Poll exactly once per Mod Tweaker frame. Wwise returns elapsed milliseconds;
-- generated dialogue durations are seconds. While paused we intentionally do
-- not query is_playing because paused-event semantics are engine-owned and the
-- progress contract is simply to freeze the last trustworthy position.
local function poll_preview()
    if preview.playing_id and not preview.paused then
        if WwiseWorld.is_playing then
            local ok, playing = pcall(WwiseWorld.is_playing, preview.world, preview.playing_id)
            if ok and not playing then
                -- Near-zero elapsed against a real duration is the non-resident
                -- soundbank signature: trigger accepted, media never played.
                printf("[character_dialogue:preview] ended event=%s elapsed=%.2f duration=%.2f",
                    tostring(preview.event), preview.elapsed or 0, preview.duration or 0)
                stop_preview()
            end
        end
        if preview.playing_id and WwiseWorld.get_playing_elapsed then
            local ok, elapsed_ms = pcall(WwiseWorld.get_playing_elapsed, preview.world, preview.playing_id)
            if ok and type(elapsed_ms) == "number" and elapsed_ms >= 0 then
                preview.elapsed = math.min(preview.duration, elapsed_ms / 1000)
            end
        end
    end
    return preview.event, preview.paused, preview.playing_id,
        PreviewPolicy.progress(preview.elapsed, preview.duration),
        preview.duration, preview.elapsed
end

local function register_mod_tweaker()
    -- dialogue_browser is a bounded custom control introduced by Tweaker: GUI
    -- dev. Never fall back to stable GUT: it would render the control as unknown.
    local gut = get_mod("gut_dev")
    local mt = gut and gut.mod_tweaker
    if not mt or not mt.register_category or mt:is_registered("character_dialogue") then return false end
    local ok, err = mt:register_category({
        mod_id = "character_dialogue",
        label = "Dialogue",
        widgets = {{
            setting_id = "dialogue_browser", type = "dialogue_browser",
            label = "Character Dialogue",
            tooltip = "Search by event, subtitle, group, or source. Expand a character to browse lines.",
        }},
    })
    if ok then log("registered virtual Dialogue tab with gut_dev") else warn("Dialogue tab registration failed: %s", tostring(err)) end
    return ok and true or false
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
    version = 3,
    catalogue = catalogue,
    browser_groups = function(query)
        query = type(query) == "string" and query or ""
        if browser_group_cache.query ~= query then
            browser_group_cache.query = query
            browser_group_cache.groups = Browser.index_groups(catalogue_index(), query)
        end
        return browser_group_cache.groups
    end,
    browser_page = function(speaker, query, offset, limit)
        return Browser.index_page(catalogue_index(), speaker, query, offset, limit)
    end,
    browser_window = Browser.window,
    browser_reconcile_focus = Browser.reconcile_focus,
    browser_row_height = Browser.ROW_HEIGHT,
    browser_page_limit = Browser.PAGE_LIMIT,
    get_line_state = function(event) return overrides[event] end,
    set_line_state = set_override,
    play = play_preview,
    pause = pause_preview,
    resume = resume_preview,
    toggle_pause = toggle_pause,
    stop = stop_preview,
    preview_state = poll_preview,
}

mod:command("cd_play", "Preview a dialogue event locally. Usage: /cd_play <event>", function(event)
    local ok, err = play_preview(event); if not ok then mod:echo("Character Dialogue: " .. tostring(err)) end
end)
mod:command("cd_pause", "Pause or resume the local preview", function()
    local ok, err = preview.paused and resume_preview() or pause_preview(); if not ok then mod:echo("Character Dialogue: " .. tostring(err)) end
end)
mod:command("cd_stop", "Stop the local dialogue preview", stop_preview)
mod:command("cd_line", "Set a line: /cd_line <event> enable|disable|default", function(event, state)
    local value = Policy.parse_override_state(state)
    local ok, err = set_override(event, value); if not ok then mod:echo("Character Dialogue: " .. tostring(err)) end
end)
mod:command("cd_regression_test", "Character Dialogue self-check", function()
    local failures = 0
    if Policy.parse_override_state("enable") ~= true
       or Policy.parse_override_state("disable") ~= false
       or Policy.parse_override_state("default") ~= nil then
        failures = failures + 1
    end
    local entries = catalogue()
    local seen = {}
    for i = 1, #entries do
        local id = entries[i][1]
        if type(id) ~= "string" or id == "" or seen[id] then failures = failures + 1; break end
        seen[id] = true
    end
    local groups = Browser.groups(entries, "")
    local grouped = 0
    for i = 1, #groups do grouped = grouped + groups[i].count end
    local browsable, timed = 0, 0
    for i = 1, #entries do
        if Browser.is_browsable(entries[i]) then browsable = browsable + 1 end
        if type(entries[i][5]) == "number" and entries[i][5] > 0 then timed = timed + 1 end
    end
    if timed ~= #entries then failures = failures + 1 end
    if grouped ~= browsable then failures = failures + 1 end
    local page = Browser.page(entries, "kruber", "", 0, Browser.PAGE_LIMIT)
    if #page > Browser.PAGE_LIMIT then failures = failures + 1 end
    if PreviewResidency.package_for_source("hero_conversations_dlc_morris_ingame")
       ~= PreviewResidency.MORRIS_PACKAGE
       or PreviewResidency.package_for_source("hero_conversations_dlc_morris_pat_tower")
       ~= PreviewResidency.MORRIS_PACKAGE
       or PreviewResidency.package_for_source("hero_conversations_dlc_holly") ~= nil then
        failures = failures + 1
    end
    mod:echo("Character Dialogue v%s: catalogue=%d timed=%d browsable=%d grouped=%d visible_cap=%d overrides=%d failures=%d",
        MOD_VERSION, #entries, timed, browsable, grouped, #page, table.size(overrides), failures)
end)

mod.update = function(dt) poll_preview_residency(dt) end
mod.on_all_mods_loaded = function() register_mod_tweaker() end
mod.on_game_state_changed = function(status)
    stop_preview()
    if status == "enter" then register_mod_tweaker() end
end
mod.on_disabled = stop_preview
mod.on_unload = stop_preview
