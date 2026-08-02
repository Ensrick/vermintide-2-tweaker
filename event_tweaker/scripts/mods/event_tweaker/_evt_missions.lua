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
end)

ET.rt_register("issue626_event_mission_allowlist_contract", function()
    if #Missions.ALLOWLIST ~= 2 then return "allowlist must contain exactly two audited missions" end
    if Missions.ALLOWLIST[1].id ~= "dlc_dwarf_fest"
       or Missions.ALLOWLIST[2].id ~= "dlc_celebrate_crawl" then
        return "allowlist contents/order drifted"
    end
    local ok, problems = _contract()
    if not ok then return table.concat(problems, "; ") end
    -- Post-fallback invariant: both allowlisted levels must sit in the local
    -- campaign tables (vanilla-registered or appended at load).
    local unlockable = rawget(_G, "UnlockableLevels")
    local game_acts = rawget(_G, "GameActs")
    for i = 1, #Missions.ALLOWLIST do
        local id = Missions.ALLOWLIST[i].id
        if type(unlockable) ~= "table" or not table.find(unlockable, id) then
            return "UnlockableLevels lacks " .. id
        end
        local act_levels = type(game_acts) == "table" and game_acts[Missions.ACT_KEY]
        if type(act_levels) ~= "table" or not table.find(act_levels, id) then
            return "GameActs." .. Missions.ACT_KEY .. " lacks " .. id
        end
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
