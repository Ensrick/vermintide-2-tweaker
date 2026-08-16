local mod = get_mod("event_tweaker")

-- _evt_missions.lua - issue 626 mission-menu availability adapter
--
-- The Feast of Grimnir reference mod proves that current event levels become
-- selectable when the stock `celebrate` area is visible. Event Tweaker keeps
-- the useful boundary: the area flag is changed only for the duration of
-- vanilla's widget build, then restored even if that build raises, and mission
-- lists are rebuilt on each view entry from the exact two-entry allowlist.
-- The visibility gate requires ONLY the tables the menus read (AreaSettings /
-- ActSettings / LevelSettings); the issue 626 defect was gating on four
-- NetworkLookup tables the menus never read, which fail-closed the whole
-- feature into "toggle on, nothing shows". If vanilla's boot registration
-- genuinely missed a level, the load-time fallback below idempotently appends
-- it to the LOCAL campaign tables (UnlockableLevels / GameActs /
-- MapPresentationActs) the way vanilla registers it
-- (level_unlock_settings.lua:100-135). NetworkLookup is NEVER touched: the
-- wire tables were built from LevelSettings at boot
-- (network_lookup.lua:1239-1248) and modded NetworkLookup keys on vanilla
-- RPCs CTD non-mod peers (issue 278, issue 371).
-- VMF automatically disables these four hooks with the mod, so reload,
-- disable/re-enable, controller/desktop re-entry, and other mods' area state do
-- not need persistent snapshots or cleanup callbacks.
--
-- Issue 941 adds the Prologue as a PROJECTED entry. It is the only allowlisted
-- level that does not live in act_celebrate, so the catalog hands the menu a
-- view-only copy (Missions.project_level) and leaves LevelSettings.prologue,
-- UnlockableLevels, GameActs, and MapPresentationActs exactly as vanilla built
-- them. Because vanilla refuses multiplayer prologue sessions outright -- remote
-- peers are disconnected with `host_plays_prologue` (peer_states.lua:67-71) --
-- this adapter also owns two launch-side hooks that keep the feature solo:
-- StartGameStateSettingsOverview.play refuses a launch while other lobby members
-- are present, and MatchmakingManager.find_game forces the search onto the
-- private always-host path before vanilla clones it. Co-op is not a missing
-- feature here; it is an engine ruling, so the mod never offers it.

local ET = mod._evt
local Missions = require("scripts/mods/event_tweaker/event_tweaker_missions")

local function _get(setting_id)
    return mod:get(setting_id)
end

local function _contract()
    return Missions.validate_contract(LevelSettings, AreaSettings, ActSettings)
end

-- Campaign registration fallback: runs unconditionally at mod load (never
-- toggle-gated), so every Event Tweaker peer applies the identical idempotent
-- append at the identical time. On a healthy install this is a no-op.
local _campaign_appended = Missions.ensure_campaign_registration(
    rawget(_G, "LevelSettings"),
    rawget(_G, "UnlockableLevels"),
    rawget(_G, "GameActs"),
    rawget(_G, "MapPresentationActs"))

local function _campaign_status()
    if #_campaign_appended == 0 then
        return "vanilla"
    end
    return table.concat(_campaign_appended, ",")
end

if #_campaign_appended > 0 then
    pcall(printf, "[event-missions:626] campaign fallback appended: %s", _campaign_status())
end

local _last_contract_error
local _area_hook_calls = 0
local _mission_hook_calls = 0
local _area_signatures = {}
local _mission_signatures = {}
local _copy_signatures = {}
local _last_area_proof = "not-called"
local _last_mission_proof = "not-called"

local function _report_contract_failure(problems)
    local detail = table.concat(problems or {}, "; ")
    if detail ~= _last_contract_error then
        _last_contract_error = detail
        pcall(printf, "[event-missions:626] blocked: %s", detail ~= "" and detail or "unknown contract failure")
    end
end

local function _with_celebrate_area_exposed(func, self, surface)
    if not Missions.any_enabled(_get) then return func(self) end

    local ok, problems = _contract()
    if not ok then
        _report_contract_failure(problems)
        return func(self)
    end

    -- Both vanilla methods have the source-verified `(self)` signature and no
    -- return value. The pure helper restores the exact stock area descriptor
    -- identity even on a Lua error, records call_ok=false without inspecting
    -- stale widgets, and returns the original error for propagation below.
    local call_ok, call_error, should_emit, proof = Missions.run_area_setup(
        func, self, surface, AreaSettings, _area_signatures)
    _area_hook_calls = _area_hook_calls + 1
    _last_area_proof = proof
    if should_emit then
        local marker = call_ok and "area observed" or "area setup failed"
        pcall(printf, "[event-missions:626] %s: calls=%d %s",
            marker, _area_hook_calls, _last_area_proof)
    end

    if not call_ok then error(call_error) end
end

local function _present_event_area_copy(func, self, surface, area_name, ...)
    local is_event = Missions.any_enabled(_get) and area_name == Missions.AREA_KEY
    -- Let vanilla resolve its own localization keys first. The controller's
    -- description pass is switched to direct-string mode only after that call,
    -- then restored before every later non-event call.
    Missions.prepare_area_copy(self, surface, false)
    func(self, area_name, ...)

    if not is_event then return end
    Missions.prepare_area_copy(self, surface, true)
    local title = mod:localize("event_mission_area_name")
    local description = mod:localize("event_mission_area_description")
    local applied = Missions.apply_event_area_copy(
        self, surface, title, description)
    local signature = table.concat({ tostring(area_name), tostring(applied) }, "|")
    if Missions.should_emit_for_surface(_copy_signatures, surface, signature) then
        pcall(printf,
            "[event-missions:802] Events presentation: surface=%s area=%s applied=%s campaign=untouched",
            tostring(surface), tostring(area_name), tostring(applied))
    end
end

local function _replace_celebrate_levels(func, self, surface, ...)
    func(self, ...)
    if not Missions.any_enabled(_get) then return end

    local ok, problems = _contract()
    if not ok then
        _report_contract_failure(problems)
        return
    end

    -- Vanilla reads the selected area through `self.parent` on desktop
    -- (start_game_window_mission_selection.lua:46) and `self._parent` on
    -- console (start_game_window_mission_selection_console.lua:45). Resolve
    -- those two source-verified shapes only; an unknown shape fails closed and
    -- leaves vanilla's mission map untouched.
    local area_name = Missions.selected_area_name(self)
    local filter_applied, assigned, assigned_levels = Missions.apply_levels_for_area(
        self, area_name, LevelSettings, _get)

    _mission_hook_calls = _mission_hook_calls + 1
    local proof_ok, observed = pcall(Missions.celebrate_level_proof, assigned_levels)
    if not proof_ok then
        observed = "probe-error=" .. tostring(observed)
    end
    local assignment = filter_applied and tostring(assigned) or "not-requested"
    local signature = table.concat({ tostring(area_name), tostring(filter_applied), assignment, observed }, "|")
    _last_mission_proof = string.format("surface=%s area=%s filter_applied=%s assigned=%s %s",
        tostring(surface), tostring(area_name), tostring(filter_applied), assignment, observed)
    if Missions.should_emit_for_surface(_mission_signatures, surface, signature) then
        pcall(printf, "[event-missions:626] mission observed: calls=%d %s",
            _mission_hook_calls, _last_mission_proof)
    end

    if not filter_applied or not assigned then
        return
    end

    local ids = Missions.enabled_ids(_get)
    pcall(printf, "[event-missions:626,802] menu applied: area=%s act=%s missions=[%s] unrelated_acts=untouched",
        Missions.AREA_KEY, Missions.ACT_KEY, table.concat(ids, ","))
end

-- Hook pre-flight (2026-07-15): event_tweaker had no hooks on either area-
-- selection or mission-selection class/method pair before issue 626.
mod:hook("StartGameWindowAreaSelection", "_setup_area_widgets", function(func, self)
    return _with_celebrate_area_exposed(func, self, "desktop")
end)

mod:hook("StartGameWindowAreaSelectionConsoleV2", "_setup_area_widgets", function(func, self)
    return _with_celebrate_area_exposed(func, self, "controller")
end)

-- Source pre-flight: no other Event Tweaker module hooks either presentation
-- method. These wrappers alter only the view-local copy after vanilla has
-- populated it; AreaSettings.helmgart and its Campaign widget are never read or
-- written by the adapter.
mod:hook("StartGameWindowAreaSelection", "_set_area_presentation_info", function(func, self, area_name, ...)
    return _present_event_area_copy(func, self, "desktop", area_name, ...)
end)

mod:hook("StartGameWindowAreaSelectionConsoleV2", "_set_area_presentation_info", function(func, self, area_name, ...)
    return _present_event_area_copy(func, self, "controller", area_name, ...)
end)

mod:hook("StartGameWindowMissionSelection", "_setup_level_acts", function(func, self, ...)
    return _replace_celebrate_levels(func, self, "desktop", ...)
end)

mod:hook("StartGameWindowMissionSelectionConsole", "_setup_level_acts", function(func, self, ...)
    return _replace_celebrate_levels(func, self, "controller", ...)
end)

-- ============================================================
-- Issue 941: projected-mission description
-- ============================================================
-- Resolve ONCE the game string id vanilla should localize for the projected
-- mission's description panel. The mod's own loc table is invisible to the
-- engine's Localize, so the mod string is published into the localization
-- manager's backend table (localization_manager.lua:69-75) under a mod-prefixed
-- id. If that manager is unavailable the level's own display_name id is used:
-- a duplicated title is a far better outcome than handing the engine localizer
-- a nil id, which is exactly what this transaction exists to prevent.
local _description_id_resolved = false
local _description_id

local function _projected_description_id()
    if _description_id_resolved then return _description_id end
    _description_id_resolved = true

    local localizer = rawget(_G, "Managers") and Managers.localizer
    if localizer and localizer.append_backend_localizations then
        local ok = pcall(localizer.append_backend_localizations, localizer, {
            [Missions.PROJECTED_DESCRIPTION_KEY] = mod:localize("mission_prologue_description"),
        })
        if ok then
            _description_id = Missions.PROJECTED_DESCRIPTION_KEY
            return _description_id
        end
    end

    local level_settings = rawget(_G, "LevelSettings")
    local level = type(level_settings) == "table" and rawget(level_settings, "prologue")
    _description_id = type(level) == "table" and level.display_name or nil
    return _description_id
end

local _presentation_signatures = {}

local function _present_projected_mission(func, self, surface, level_id)
    -- Resolve the description id only for a projected selection. The window
    -- also calls this with no level on entry, and the resolver memoizes, so an
    -- eager call could freeze the fallback in before the localizer is up.
    local entry = Missions.entry_for(level_id)
    local description_id = entry and entry.projected and _projected_description_id() or nil
    local applied, restored = Missions.run_presentation_info(
        func, self, level_id, rawget(_G, "LevelSettings"), description_id)
    if not applied then return end

    local signature = table.concat({ tostring(level_id), tostring(restored) }, "|")
    if Missions.should_emit_for_surface(_presentation_signatures, surface, signature) then
        pcall(printf,
            "[event-missions:941] projected description: surface=%s mission=%s id=%s restored=%s",
            tostring(surface), tostring(level_id), tostring(_description_id), tostring(restored))
    end
end

-- Source pre-flight: no other Event Tweaker module hooks either mission
-- presentation method.
mod:hook("StartGameWindowMissionSelection", "_set_presentation_info", function(func, self, level_id)
    return _present_projected_mission(func, self, "desktop", level_id)
end)

mod:hook("StartGameWindowMissionSelectionConsole", "_set_presentation_info", function(func, self, level_id)
    return _present_projected_mission(func, self, "controller", level_id)
end)

-- ============================================================
-- Issue 941: solo-only launch enforcement
-- ============================================================
-- Hook pre-flight (2026-08-16): event_tweaker had no hook on either
-- StartGameStateSettingsOverview.play or MatchmakingManager.find_game before
-- issue 941, so these are the mod's first and only wrappers on those pairs.

local _solo_blocked_calls = 0
local _solo_hardened_calls = 0
local _last_solo_proof = "not-called"

local function _lobby_member_count(view)
    -- Vanilla reads the same chain to compute its own is_alone flag
    -- (start_game_state_settings_overview.lua:1034-1040). An unreadable shape
    -- returns nil, which the policy reports as allow_unverified rather than
    -- turning a menu-shape change into a refusal to launch anything.
    local ok, count = pcall(function()
        return view._network_lobby:members():get_member_count()
    end)
    if ok and type(count) == "number" then return count end
end

mod:hook("StartGameStateSettingsOverview", "play", function(func, self, t, vote_type, ...)
    local level_ok, level_id = pcall(function() return self._specific_level_id end)
    local members = _lobby_member_count(self)
    local verdict = Missions.solo_launch_verdict(
        vote_type, level_ok and level_id or nil, members)

    if verdict == "not_managed" then
        return func(self, t, vote_type, ...)
    end

    _last_solo_proof = string.format("vote_type=%s mission=%s members=%s verdict=%s",
        tostring(vote_type), tostring(level_ok and level_id or nil),
        tostring(members), verdict)

    if verdict == "blocked_not_solo" then
        _solo_blocked_calls = _solo_blocked_calls + 1
        mod:echo(mod:localize("event_mission_solo_only_blocked"))
        pcall(printf, "[event-missions:941] launch refused: %s", _last_solo_proof)
        return
    end

    pcall(printf, "[event-missions:941] solo launch allowed: %s", _last_solo_proof)
    return func(self, t, vote_type, ...)
end)

mod:hook("MatchmakingManager", "find_game", function(func, self, search_config, ...)
    -- Harden BEFORE the original runs: find_game clones search_config into its
    -- state context on the first lines (matchmaking_manager.lua:1013), so a
    -- post-hook edit would never reach the host state.
    local hardened, proof = Missions.harden_search_config(search_config)
    if hardened then
        _solo_hardened_calls = _solo_hardened_calls + 1
        _last_solo_proof = proof
        pcall(printf, "[event-missions:941] solo search hardened: %s", proof)
    end
    return func(self, search_config, ...)
end)

mod:command("event_mission_probe", "Inspect the issue-626 event-mission availability contract", function()
    local ok, problems = _contract()
    local ids = Missions.enabled_ids(_get)
    local detail = ok and "OK" or table.concat(problems, "; ")
    mod:echo("[event missions] selected={%s} contract=%s campaign=%s area_hooks=%d mission_hooks=%d",
        table.concat(ids, ","), detail, _campaign_status(), _area_hook_calls, _mission_hook_calls)
    pcall(printf,
        "[event-missions:626] probe selected=[%s] contract=%s campaign=%s area_hooks=%d mission_hooks=%d last_area={%s} last_mission={%s}",
        table.concat(ids, ","), detail, _campaign_status(), _area_hook_calls, _mission_hook_calls,
        _last_area_proof, _last_mission_proof)
    pcall(printf,
        "[event-missions:941] probe solo_blocked=%d solo_hardened=%d last_solo={%s}",
        _solo_blocked_calls, _solo_hardened_calls, _last_solo_proof)
end)

ET.rt_register("issue626_event_mission_allowlist_contract", function()
    if #Missions.ALLOWLIST ~= 3 then return "allowlist must contain exactly three audited missions" end
    if Missions.ALLOWLIST[1].id ~= "dlc_dwarf_fest"
       or Missions.ALLOWLIST[2].id ~= "dlc_celebrate_crawl"
       or Missions.ALLOWLIST[3].id ~= "prologue" then
        return "allowlist contents/order drifted"
    end
    local ok, problems = _contract()
    if not ok then return table.concat(problems, "; ") end
    -- Post-fallback invariant: every NATIVE allowlisted level must sit in the
    -- local campaign tables (vanilla-registered or appended at load), and no
    -- projected level may have been pushed into the event act.
    local unlockable = rawget(_G, "UnlockableLevels")
    local game_acts = rawget(_G, "GameActs")
    local act_levels = type(game_acts) == "table" and game_acts[Missions.ACT_KEY]
    for i = 1, #Missions.ALLOWLIST do
        local entry = Missions.ALLOWLIST[i]
        local id = entry.id
        if entry.projected then
            if type(act_levels) == "table" and table.find(act_levels, id) then
                return "GameActs." .. Missions.ACT_KEY .. " absorbed projected " .. id
            end
        else
            if type(unlockable) ~= "table" or not table.find(unlockable, id) then
                return "UnlockableLevels lacks " .. id
            end
            if type(act_levels) ~= "table" or not table.find(act_levels, id) then
                return "GameActs." .. Missions.ACT_KEY .. " lacks " .. id
            end
        end
    end
end)

ET.rt_register("issue941_prologue_solo_only_projection", function()
    local entry = Missions.entry_for("prologue")
    if not entry or not entry.projected or not entry.solo_only then
        return "prologue is not registered as a projected solo-only mission"
    end

    -- The canonical descriptor must still be the tutorial, in its own act, with
    -- a package list the transition handler can load. Read the LIVE globals: a
    -- passing check is evidence the adapter left them alone this session.
    local level_settings = rawget(_G, "LevelSettings")
    local live = type(level_settings) == "table" and rawget(level_settings, "prologue")
    if type(live) ~= "table" then return "LevelSettings.prologue missing" end
    if live.act ~= entry.source_act then
        return "LevelSettings.prologue.act was moved to " .. tostring(live.act)
    end
    if live.game_mode ~= entry.source_game_mode then
        return "LevelSettings.prologue.game_mode is " .. tostring(live.game_mode)
    end
    if type(live.packages) ~= "table" or #live.packages == 0 then
        return "LevelSettings.prologue has no packages to load"
    end

    local projected = Missions.project_level(live, entry)
    if projected == live then return "projection returned the canonical descriptor" end
    if projected.act ~= Missions.ACT_KEY then return "projection was not re-keyed into the event act" end
    if projected.level_id ~= "prologue" then return "projection lost the launch identity" end
    if type(projected.act_presentation_order) ~= "number" then
        return "projection left act_presentation_order unsortable"
    end
    if live.act ~= entry.source_act or live.act_presentation_order ~= nil then
        return "projecting mutated LevelSettings.prologue"
    end

    -- The presentation transaction must supply a description id and hand the
    -- canonical table back exactly as it found it. Without it both mission
    -- windows localize a nil id the moment the tile is selected.
    if type(_projected_description_id()) ~= "string" then
        return "no description id resolved for the projected mission"
    end
    local seen
    local applied, restored = Missions.run_presentation_info(
        function(_, id) seen = live.description_text; return id end,
        nil, "prologue", level_settings, _projected_description_id())
    if not applied then return "presentation transaction did not engage" end
    if type(seen) ~= "string" then return "vanilla would have localized a nil description" end
    if not restored or live.description_text ~= nil then
        return "presentation transaction left description_text behind"
    end

    -- Launch policy: other members refuse, solo proceeds, and the search config
    -- is forced onto the private always-host path.
    if Missions.solo_launch_verdict("custom", "prologue", 2) ~= "blocked_not_solo" then
        return "a multi-member lobby was allowed to launch the tutorial"
    end
    if Missions.solo_launch_verdict("custom", "prologue", 1) ~= "allow" then
        return "a solo lobby was refused"
    end
    if Missions.solo_launch_verdict("adventure", "prologue", 4) ~= "not_managed" then
        return "quickplay was blocked by a stale mission selection"
    end
    local config = { mission_id = "prologue", private_game = false, always_host = false, quick_game = true }
    local hardened = Missions.harden_search_config(config)
    if not hardened or config.private_game ~= true or config.always_host ~= true
            or config.quick_game ~= false then
        return "solo-only search config was not hardened"
    end
end)

ET.rt_register("issue802_event_mission_area_scope", function()
    local campaign = {
        name = "helmgart",
        sort_order = 1,
        acts = { "act_1" },
    }
    local stock_event = {
        name = Missions.AREA_KEY,
        sort_order = 0,
        exclude_from_area_selection = true,
        level_image = "area_icon_bogenhafen",
        acts = { Missions.ACT_KEY },
    }
    local areas = {
        helmgart = campaign,
        celebrate = stock_event,
        dwarf_fest = {
            exclude_from_area_selection = true,
            level_image = "area_icon_dwarf_fest",
            sort_order = 0,
        },
    }
    local event_copy = Missions.event_area_presentation(areas)
    if type(event_copy) ~= "table" then return "Events presentation was not built" end
    if event_copy.sort_order <= campaign.sort_order then return "Events can steal Campaign's first slot" end
    if event_copy.level_image == stock_event.level_image then return "Events still uses Bogenhafen presentation" end
    if areas.helmgart ~= campaign then return "Campaign descriptor identity changed" end
    if areas.celebrate ~= stock_event then return "stock celebrate descriptor changed outside transaction" end

    local control = { { level_id = "control" } }
    local original = { act_1 = control }
    local untouched, applied = Missions.filter_levels_for_area(
        "helmgart", original, {}, function() return true end)
    if applied then return "non-event area was filtered" end
    if untouched ~= original then return "non-event mission map identity changed" end

    local event_levels, event_applied = Missions.filter_levels_for_area(
        Missions.AREA_KEY, original, LevelSettings, _get)
    if not event_applied then return "celebrate area was not filtered" end
    if event_levels == original then return "celebrate area retained unfiltered outer map" end
    if event_levels.act_1 ~= control then return "unrelated act identity changed" end
end)
