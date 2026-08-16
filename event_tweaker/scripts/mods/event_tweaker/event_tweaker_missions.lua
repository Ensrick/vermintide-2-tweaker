-- Pure mission-availability contract for issue 626.
--
-- This module is require'd by both the early VMF data file and the runtime
-- mission-menu adapter, so it must stay engine-free: no get_mod, Managers, or
-- direct global reads. The runtime module supplies the current LevelSettings,
-- AreaSettings, ActSettings, and campaign tables explicitly.

local M = {}

M.AREA_KEY = "celebrate"
M.ACT_KEY = "act_celebrate"
M.EVENT_ICON = "level_image_dlc_dwarf_fest"
local PARENT_FIELDS = { "parent", "_parent" }

-- Presentation order stamped on a projected descriptor whose source level has
-- none. LevelSettings.prologue ships no act_presentation_order
-- (level_settings.lua:1379-1417) while both celebrate levels do
-- (level_settings_celebrate.lua:5), and the native list comparator dereferences
-- the field unconditionally (start_game_window_mission_selection.lua:10-15).
-- Vanilla sorts each act BEFORE this adapter swaps the celebrate list, so no
-- live sort sees the gap today; stamping it keeps a third-party re-sort of
-- _levels_by_act from turning a nil compare into a menu crash, and sorts the
-- projection last among the audited event levels.
M.PROJECTED_PRESENTATION_ORDER = 99

-- Deliberately closed. A future event level must be source-audited and added
-- here before Event Tweaker will expose it; sharing act_celebrate is not enough.
--
-- `projected` entries (issue 941) are levels that do NOT live in act_celebrate
-- and must never be moved there. The Prologue is the first: LevelSettings.prologue
-- is act "prologue" + game_mode "tutorial" (level_settings.lua:1380-1387) and the
-- engine rejects multiplayer prologue sessions outright -- PeerStates.Connecting
-- disconnects every remote peer with `host_plays_prologue`
-- (peer_states.lua:67-71), MatchmakingManager.lobby_match refuses a prologue
-- lobby as a match candidate (matchmaking_manager.lua:1621-1625), and
-- StateLoading force-clears the lobby's matchmaking flag
-- (state_loading.lua:2589-2592). So the entry is `solo_only` and the adapter
-- shows a view-only COPY under Events: the canonical descriptor keeps its own
-- act, and the campaign tables (UnlockableLevels / GameActs / MapPresentationActs)
-- are never touched for it.
M.ALLOWLIST = {
    {
        id = "dlc_dwarf_fest",
        setting_id = "mission_dlc_dwarf_fest",
    },
    {
        id = "dlc_celebrate_crawl",
        setting_id = "mission_dlc_celebrate_crawl",
    },
    {
        id = "prologue",
        setting_id = "mission_prologue",
        projected = true,
        source_act = "prologue",
        source_game_mode = "tutorial",
        solo_only = true,
    },
}

local function _contains(list, value)
    if type(list) ~= "table" then return false end
    for i = 1, #list do
        if list[i] == value then return true end
    end
    return false
end

function M.entry_for(level_id)
    for i = 1, #M.ALLOWLIST do
        if M.ALLOWLIST[i].id == level_id then return M.ALLOWLIST[i] end
    end
end

-- True only for an allowlisted mission the engine refuses to run with other
-- peers present. Callers use it to harden the launch, never to hide the tile.
function M.is_solo_only(level_id)
    local entry = M.entry_for(level_id)
    return entry ~= nil and entry.solo_only == true
end

function M.any_enabled(get)
    for i = 1, #M.ALLOWLIST do
        if get(M.ALLOWLIST[i].setting_id) == true then return true end
    end
    return false
end

function M.enabled_ids(get)
    local ids = {}
    for i = 1, #M.ALLOWLIST do
        local entry = M.ALLOWLIST[i]
        if get(entry.setting_id) == true then
            ids[#ids + 1] = entry.id
        end
    end
    return ids
end

local function _shallow_copy(source)
    local copy = {}
    for key, value in pairs(source or {}) do
        copy[key] = value
    end
    return copy
end

-- Vanilla's hidden celebrate descriptor is not an Events tile. It has
-- sort_order=0 and reuses Bogenhafen's presentation, so merely unhiding it
-- makes the controller's special first widget look like Campaign while routing
-- that widget to act_celebrate. Build a transient view-only descriptor instead:
-- the routing key/acts stay stock, the event icon is the resident 168x168 Feast
-- level image, and the tile sorts after every already-visible area.
-- AreaSettings itself is swapped only for the duration of vanilla's build.
function M.event_area_presentation(area_settings)
    local stock = type(area_settings) == "table" and rawget(area_settings, M.AREA_KEY)
    if type(stock) ~= "table" then return nil, "celebrate area missing" end

    local highest_visible_order = 0
    for key, settings in pairs(area_settings) do
        if key ~= M.AREA_KEY and type(settings) == "table"
                and settings.exclude_from_area_selection ~= true
                and type(settings.sort_order) == "number"
                and settings.sort_order > highest_visible_order then
            highest_visible_order = settings.sort_order
        end
    end

    local presentation = _shallow_copy(stock)
    presentation.exclude_from_area_selection = false
    presentation.sort_order = highest_visible_order + 1
    presentation.level_image = M.EVENT_ICON

    return presentation, {
        stock = stock,
        sort_order = presentation.sort_order,
        level_image = presentation.level_image,
    }
end

-- Resolve only the two source-backed mission-view parent shapes. Keep every
-- access and callback contained: another mod may rebuild a view with a partial
-- proxy, and menu presentation must fail closed rather than turn that drift
-- into a selection-time crash.
function M.selected_area_name(view)
    for i = 1, #PARENT_FIELDS do
        local field = PARENT_FIELDS[i]
        local parent_ok, parent = pcall(function()
            return view and view[field]
        end)
        if parent_ok and parent then
            local getter_ok, getter = pcall(function()
                return parent.get_selected_area_name
            end)
            if getter_ok and type(getter) == "function" then
                local area_ok, area_name = pcall(getter, parent)
                if area_ok and type(area_name) == "string" then
                    return area_name
                end
            end
        end
    end
end

-- Returns true when a LevelSettings entry is complete enough to advertise and
-- register: keyed to itself, in the celebrate act, with a non-empty package
-- list for LevelTransitionHandler to load (level_transition_handler.lua:518-572).
-- A projected entry is deliberately rejected here: it is never registered into
-- the campaign tables, so the only gate it has to clear is the contract below.
local function _level_ok(level, id)
    return type(level) == "table"
        and level.level_id == id
        and level.act == M.ACT_KEY
        and type(level.packages) == "table"
        and #level.packages > 0
end

-- Build the view-only descriptor the mission menu renders for an allowlisted
-- level. A native entry is passed through by identity (the menu has always read
-- the live LevelSettings table). A projected entry gets a shallow COPY re-keyed
-- into act_celebrate so vanilla's per-act layout places it under Events; the
-- source table -- LevelSettings.prologue and its level_id, packages, game_mode,
-- mechanism -- is never written to, so the tutorial keeps its canonical
-- identity everywhere else in the game and the launch still resolves the real
-- level through mission_id.
function M.project_level(level, entry)
    if type(level) ~= "table" then return nil end
    if type(entry) ~= "table" or entry.projected ~= true then return level end

    local projected = _shallow_copy(level)
    projected.act = M.ACT_KEY
    if type(projected.act_presentation_order) ~= "number" then
        projected.act_presentation_order = M.PROJECTED_PRESENTATION_ORDER
    end
    return projected
end

-- Visibility gate (issue 626 fix): fail closed before advertising a mission,
-- but require ONLY the tables the menus actually read. Area selection reads
-- AreaSettings (start_game_window_area_selection.lua:91-95); mission selection
-- reads LevelSettings + ActSettings (with arithmetic on act sorting,
-- start_game_window_mission_selection.lua:108-134,156-160) and the acts listed
-- on the selected area. The previous gate also demanded four NetworkLookup
-- tables (level_keys / mission_ids / act_keys / unlockable_level_keys) that no
-- menu reads, so a lookup mismatch blocked both hooks with only a printf:
-- exactly "toggle on, nothing shows". NetworkLookup is deliberately neither
-- consulted nor mutated here: the vanilla wire tables already carry both
-- levels from boot (network_lookup.lua:1239-1248, built from LevelSettings),
-- and modded NetworkLookup keys on vanilla RPCs CTD non-mod peers
-- (issue 278, issue 371).
function M.validate_contract(level_settings, area_settings, act_settings)
    local problems = {}
    local area = type(area_settings) == "table" and rawget(area_settings, M.AREA_KEY)
    local act = type(act_settings) == "table" and rawget(act_settings, M.ACT_KEY)

    if type(area) ~= "table" then
        problems[#problems + 1] = "AreaSettings.celebrate missing"
    elseif not _contains(area.acts, M.ACT_KEY) then
        problems[#problems + 1] = "AreaSettings.celebrate lacks act_celebrate"
    end
    if type(act) ~= "table" then
        problems[#problems + 1] = "ActSettings.act_celebrate missing"
    elseif type(act.sorting) ~= "number" then
        problems[#problems + 1] = "ActSettings.act_celebrate.sorting not a number"
    end

    for i = 1, #M.ALLOWLIST do
        local entry = M.ALLOWLIST[i]
        local id = entry.id
        -- A projected entry must still live in ITS OWN act and game mode. That
        -- is the falsifier for "the descriptor was left alone": the moment
        -- LevelSettings.prologue reads act_celebrate, something mutated the
        -- canonical table and the adapter fails closed instead of advertising.
        local expected_act = entry.projected and entry.source_act or M.ACT_KEY
        local level = type(level_settings) == "table" and rawget(level_settings, id)
        if type(level) ~= "table" then
            problems[#problems + 1] = "LevelSettings." .. id .. " missing"
        else
            if level.level_id ~= id then
                problems[#problems + 1] = "LevelSettings." .. id .. ".level_id mismatch"
            end
            if level.act ~= expected_act then
                problems[#problems + 1] = "LevelSettings." .. id .. ".act mismatch"
            end
            if entry.source_game_mode and level.game_mode ~= entry.source_game_mode then
                problems[#problems + 1] = "LevelSettings." .. id .. ".game_mode mismatch"
            end
            if type(level.packages) ~= "table" or #level.packages == 0 then
                problems[#problems + 1] = "LevelSettings." .. id .. ".packages empty"
            end
        end
    end

    return #problems == 0, problems
end

-- Idempotent campaign-table registration fallback (issue 626). Vanilla's boot
-- pass already registers every valid celebrate level into UnlockableLevels,
-- GameActs, and MapPresentationActs (level_unlock_settings.lua:100-135), so on
-- a healthy install this appends nothing. It repairs only an install where
-- that pass genuinely missed an allowlisted level, mirroring the vanilla
-- registration shape. Per-peer safety: these are LOCAL campaign/presentation
-- tables; the wire tables (NetworkLookup.level_keys / mission_ids / act_keys /
-- unlockable_level_keys) were built from LevelSettings / GameActs /
-- UnlockableLevels at BOOT (network_lookup.lua:1239-1259), before any mod
-- loads, so appends here can never extend or reorder a NetworkLookup table.
-- The caller must run this unconditionally at mod load (never toggle-gated),
-- so every Event Tweaker peer applies the identical append at the same time.
function M.ensure_campaign_registration(level_settings, unlockable_levels, game_acts, map_presentation_acts)
    local appended = {}
    for i = 1, #M.ALLOWLIST do
        local entry = M.ALLOWLIST[i]
        local id = entry.id
        local level = type(level_settings) == "table" and rawget(level_settings, id)
        -- Only a well-formed stock definition may be registered; a missing or
        -- malformed LevelSettings entry stays fail-closed at the visibility gate.
        -- A projected entry is skipped outright: vanilla already registered the
        -- Prologue under its own act (level_unlock_settings.lua:101-136), and
        -- appending it to GameActs.act_celebrate would move a base-game level
        -- into the event act for every system that reads those tables.
        if not entry.projected and _level_ok(level, id) then
            if type(unlockable_levels) == "table" and not _contains(unlockable_levels, id) then
                unlockable_levels[#unlockable_levels + 1] = id
                appended[#appended + 1] = "UnlockableLevels+" .. id
            end
            if type(game_acts) == "table" then
                if type(game_acts[M.ACT_KEY]) ~= "table" then
                    game_acts[M.ACT_KEY] = {}
                end
                if not _contains(game_acts[M.ACT_KEY], id) then
                    game_acts[M.ACT_KEY][#game_acts[M.ACT_KEY] + 1] = id
                    appended[#appended + 1] = "GameActs." .. M.ACT_KEY .. "+" .. id
                end
            end
            if type(map_presentation_acts) == "table" and not _contains(map_presentation_acts, M.ACT_KEY) then
                map_presentation_acts[#map_presentation_acts + 1] = M.ACT_KEY
                appended[#appended + 1] = "MapPresentationActs+" .. M.ACT_KEY
            end
        end
    end
    return appended
end

-- Return a new outer map and replace only act_celebrate. Every unrelated act
-- table is retained by identity: the menu adapter never rewrites another
-- act's level list, and the view-local map never leaks back into globals.
function M.filter_levels_by_act(levels_by_act, level_settings, get)
    local filtered = {}
    for act_key, levels in pairs(levels_by_act or {}) do
        filtered[act_key] = levels
    end

    local selected = {}
    for i = 1, #M.ALLOWLIST do
        local entry = M.ALLOWLIST[i]
        if get(entry.setting_id) == true then
            local level = type(level_settings) == "table" and rawget(level_settings, entry.id)
            local descriptor = M.project_level(level, entry)
            if type(descriptor) == "table" then selected[#selected + 1] = descriptor end
        end
    end
    filtered[M.ACT_KEY] = selected
    return filtered
end

-- Scope the celebrate replacement to the celebrate area itself. Desktop and
-- console both build mission lists after reading the selected area from their
-- parent window; unrelated areas must retain the exact view-local map vanilla
-- built, including its outer-table identity.
function M.filter_levels_for_area(area_name, levels_by_act, level_settings, get)
    if area_name ~= M.AREA_KEY
            or type(levels_by_act) ~= "table"
            or type(level_settings) ~= "table"
            or type(get) ~= "function" then
        return levels_by_act, false
    end

    return M.filter_levels_by_act(levels_by_act, level_settings, get), true
end

-- Bounded, engine-free observation helpers for issue 626. Keeping the state
-- transition and its proof in this required module lets offline tests execute
-- the exact ordering used by the runtime hooks instead of checking for log
-- marker strings in _evt_missions.lua.
function M.area_widget_proof(view)
    local widgets = type(view) == "table" and view._active_area_widgets
    if type(widgets) ~= "table" then
        return "widgets=missing target=0 areas=[]"
    end

    local names = {}
    local target_count = 0
    local campaign_index
    local event_index
    for i = 1, #widgets do
        local widget = widgets[i]
        local content = type(widget) == "table" and widget.content
        local area_name = type(content) == "table" and content.area_name
        names[#names + 1] = tostring(area_name or "<nil>")
        if area_name == M.AREA_KEY then
            target_count = target_count + 1
            event_index = event_index or i
        elseif area_name == "helmgart" then
            campaign_index = campaign_index or i
        end
    end

    return string.format("widgets=%d target=%d campaign_index=%s event_index=%s areas=[%s]",
        #widgets, target_count, tostring(campaign_index or "missing"),
        tostring(event_index or "missing"), table.concat(names, ","))
end

function M.celebrate_level_proof(levels_by_act)
    local levels = type(levels_by_act) == "table" and levels_by_act[M.ACT_KEY]
    if type(levels) ~= "table" then
        return "count=missing ids=[]"
    end

    local ids = {}
    for i = 1, #levels do
        local level = levels[i]
        ids[#ids + 1] = tostring(type(level) == "table" and level.level_id or "<nil>")
    end
    return string.format("count=%d ids=[%s]", #levels, table.concat(ids, ","))
end

-- Each native UI surface owns its own previous signature. Alternating between
-- desktop and controller therefore cannot defeat deduplication for either one.
function M.should_emit_for_surface(signatures, surface, signature)
    local key = tostring(surface or "unknown")
    local changed = type(signatures) ~= "table" or signatures[key] ~= signature
    if type(signatures) == "table" then
        signatures[key] = signature
    end
    return changed
end

function M.area_observation(signatures, surface, call_ok, restored, view)
    -- A failed native build may leave _active_area_widgets from a prior view.
    -- Do not misreport that stale table as the result of the failed call.
    local observed = "widgets=skipped"
    if call_ok then
        local proof_ok, proof = pcall(M.area_widget_proof, view)
        observed = proof_ok and proof or "probe-error=" .. tostring(proof)
    end
    local proof = string.format("surface=%s call_ok=%s restored=%s %s",
        tostring(surface), tostring(call_ok), tostring(restored), observed)
    local signature = table.concat({ tostring(call_ok), tostring(restored), observed }, "|")
    return M.should_emit_for_surface(signatures, surface, signature), proof
end

-- Execute the exact temporary-descriptor transaction used by both area hooks.
-- The caller owns error propagation so diagnostics can be recorded first.
function M.run_area_setup(func, view, surface, area_settings, signatures)
    local presentation, metadata = M.event_area_presentation(area_settings)
    if not presentation then
        local problem = metadata or "event presentation unavailable"
        local should_emit, proof = M.area_observation(
            signatures, surface, false, true, view)
        return false, problem, should_emit, proof
    end

    local previous = metadata.stock
    area_settings[M.AREA_KEY] = presentation
    local call_ok, call_error = pcall(func, view)
    area_settings[M.AREA_KEY] = previous

    local restored = rawget(area_settings, M.AREA_KEY) == previous
    local should_emit, proof = M.area_observation(
        signatures, surface, call_ok, restored, view)
    proof = string.format("%s presentation_sort=%s presentation_icon=%s stock_identity=%s",
        proof, tostring(metadata.sort_order), tostring(metadata.level_image), tostring(restored))
    return call_ok, call_error, should_emit, proof
end

-- The stock celebrate descriptor also carries Bogenhafen's title and
-- description. Area-selection windows keep those strings in view-local widgets,
-- so replace only that visible copy after vanilla has completed. The controller
-- description pass normally localizes its content; our already-localized mod
-- string must explicitly opt out, and the next non-event selection restores the
-- vanilla mode before its original method runs.
function M.prepare_area_copy(view, surface, is_event)
    if surface ~= "controller" then return end
    local widgets = type(view) == "table" and view._widgets_by_name
    local area_desc = type(widgets) == "table" and widgets.area_desc
    local text_style = type(area_desc) == "table"
        and type(area_desc.style) == "table"
        and area_desc.style.text
    if type(text_style) == "table" then
        text_style.localize = not is_event
    end
end

function M.apply_event_area_copy(view, surface, title, description)
    local widgets = type(view) == "table" and view._widgets_by_name
    if type(widgets) ~= "table" then return false end

    local title_widget = widgets.area_title
    local description_widget = surface == "controller"
        and widgets.area_desc or widgets.description_text
    if type(title_widget) ~= "table" or type(title_widget.content) ~= "table"
            or type(description_widget) ~= "table"
            or type(description_widget.content) ~= "table" then
        return false
    end

    title_widget.content.text = title
    description_widget.content.text = description
    return title_widget.content.text == title
        and description_widget.content.text == description
end

-- Filter, assign, then return the value read back from the view. This order is
-- deliberate: diagnostics must describe self._levels_by_act after mutation,
-- not merely the candidate map returned by the filter.
function M.apply_levels_for_area(view, area_name, level_settings, get)
    local current = type(view) == "table" and view._levels_by_act
    local filtered, filter_applied = M.filter_levels_for_area(
        area_name, current, level_settings, get)
    if not filter_applied then
        return false, false, current
    end

    view._levels_by_act = filtered
    local assigned = view._levels_by_act
    return true, assigned == filtered, assigned
end

-- ============================================================
-- Issue 941: mission presentation for a projected level
-- ============================================================
-- Backend-localization id this adapter registers for the projected mission's
-- description. It must be a GAME string id, not a mod loc key: both presentation
-- windows call the engine's Localize on level_settings.description_text
-- (start_game_window_mission_selection.lua:391,396 and the console twin at
-- :279,296), which reads the game's localizers, and LocalizationManager consults
-- the backend table first (localization_manager.lua:50-55).
M.PROJECTED_DESCRIPTION_KEY = "evt_level_description_prologue"

-- LevelSettings.prologue ships display_name but NO description_text
-- (level_settings.lua:1379-1417), so selecting the tile would hand the engine
-- localizer a nil id. Run vanilla's presentation with a transient description id
-- in place and restore the exact prior value -- nil included -- even when the
-- native call raises, the same shape run_area_setup uses for AreaSettings.
-- Returns applied/restored so the caller can prove the transaction closed.
function M.run_presentation_info(func, view, level_id, level_settings, description_id)
    local entry = M.entry_for(level_id)
    local level = type(level_settings) == "table" and rawget(level_settings, level_id)
    if type(entry) ~= "table" or entry.projected ~= true
            or type(level) ~= "table"
            or level.description_text ~= nil
            or type(description_id) ~= "string" then
        func(view, level_id)
        return false, false
    end

    level.description_text = description_id
    local call_ok, call_error = pcall(func, view, level_id)
    level.description_text = nil

    local restored = rawget(level, "description_text") == nil
    if not call_ok then error(call_error) end
    return true, restored
end

-- ============================================================
-- Issue 941: solo-only launch policy for projected missions
-- ============================================================
-- The two vote types that actually consume the mission-selection level id
-- (start_game_state_settings_overview.lua:998 "adventure_mode" and :1049
-- "custom"). Quickplay / weave / deed builds ignore _specific_level_id, so a
-- stale Prologue selection must not be allowed to block them.
local SPECIFIC_LEVEL_VOTE_TYPES = {
    adventure_mode = true,
    custom = true,
}

function M.consumes_selected_level(vote_type)
    return SPECIFIC_LEVEL_VOTE_TYPES[vote_type] == true
end

-- Decide whether a launch may proceed. Returns one of:
--   "not_managed"      - not an allowlisted solo-only mission; never interfere.
--   "allow"            - solo-only mission and the lobby is provably one member.
--   "allow_unverified" - solo-only mission, member count unreadable. Vanilla's
--                        own prologue guards still apply, so allow and say so
--                        rather than fail the feature closed on a shape change.
--   "blocked_not_solo" - solo-only mission with other members present. Refusing
--                        here is strictly kinder than launching: the engine
--                        would disconnect every one of them mid-load with
--                        `host_plays_prologue` (peer_states.lua:67-71).
function M.solo_launch_verdict(vote_type, level_id, member_count)
    if not M.consumes_selected_level(vote_type) then return "not_managed" end
    if not M.is_solo_only(level_id) then return "not_managed" end
    if type(member_count) ~= "number" then return "allow_unverified" end
    if member_count > 1 then return "blocked_not_solo" end
    return "allow"
end

-- Force the matchmaking search for a solo-only mission onto the host path
-- before MatchmakingManager.find_game clones it into its state context
-- (matchmaking_manager.lua:1013). private_game + always_host select
-- MatchmakingStateHostGame (matchmaking_manager.lua:1049-1066), so the session
-- is never advertised and never searches for a peer lobby. Mutates in place --
-- vanilla's own clone must see the hardened values.
function M.harden_search_config(search_config)
    if type(search_config) ~= "table" then return false, "no search config" end
    if not M.is_solo_only(search_config.mission_id) then
        return false, "not a solo-only mission"
    end

    search_config.private_game = true
    search_config.always_host = true
    search_config.quick_game = false
    search_config.strict_matchmaking = false
    search_config.dedicated_server = false
    search_config.join_method = "solo"

    return true, string.format(
        "mission=%s private_game=%s always_host=%s quick_game=%s strict=%s dedicated=%s join_method=%s",
        tostring(search_config.mission_id), tostring(search_config.private_game),
        tostring(search_config.always_host), tostring(search_config.quick_game),
        tostring(search_config.strict_matchmaking),
        tostring(search_config.dedicated_server), tostring(search_config.join_method))
end

return M
