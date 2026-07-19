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
local function _report_contract_failure(problems)
    local detail = table.concat(problems or {}, "; ")
    if detail ~= _last_contract_error then
        _last_contract_error = detail
        pcall(printf, "[event-missions:626] blocked: %s", detail ~= "" and detail or "unknown contract failure")
    end
end

local function _with_celebrate_area_exposed(func, self)
    if not Missions.any_enabled(_get) then return func(self) end

    local ok, problems = _contract()
    if not ok then
        _report_contract_failure(problems)
        return func(self)
    end

    local area = AreaSettings[Missions.AREA_KEY]
    local previous = area.exclude_from_area_selection
    area.exclude_from_area_selection = false

    -- Both vanilla methods have the source-verified `(self)` signature and no
    -- return value. pcall exists only so the temporary global bit is restored
    -- on a Lua error; the original error is then propagated.
    local call_ok, call_error = pcall(func, self)
    area.exclude_from_area_selection = previous
    if not call_ok then error(call_error) end
end

local function _replace_celebrate_levels(func, self, ...)
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
    local levels_by_act, applied = Missions.filter_levels_for_area(
        area_name, self._levels_by_act, LevelSettings, _get)
    if not applied then
        return
    end

    self._levels_by_act = levels_by_act
    local ids = Missions.enabled_ids(_get)
    pcall(printf, "[event-missions:626,802] menu applied: area=%s act=%s missions=[%s] unrelated_acts=untouched",
        Missions.AREA_KEY, Missions.ACT_KEY, table.concat(ids, ","))
end

-- Hook pre-flight (2026-07-15): event_tweaker had no hooks on either area-
-- selection or mission-selection class/method pair before issue 626.
mod:hook("StartGameWindowAreaSelection", "_setup_area_widgets", function(func, self)
    return _with_celebrate_area_exposed(func, self)
end)

mod:hook("StartGameWindowAreaSelectionConsoleV2", "_setup_area_widgets", function(func, self)
    return _with_celebrate_area_exposed(func, self)
end)

mod:hook("StartGameWindowMissionSelection", "_setup_level_acts", function(func, self, ...)
    return _replace_celebrate_levels(func, self, ...)
end)

mod:hook("StartGameWindowMissionSelectionConsole", "_setup_level_acts", function(func, self, ...)
    return _replace_celebrate_levels(func, self, ...)
end)

mod:command("event_mission_probe", "Inspect the issue-626 event-mission availability contract", function()
    local ok, problems = _contract()
    local ids = Missions.enabled_ids(_get)
    local detail = ok and "OK" or table.concat(problems, "; ")
    mod:echo("[event missions] selected={%s} contract=%s campaign=%s", table.concat(ids, ","), detail, _campaign_status())
    pcall(printf, "[event-missions:626] probe selected=[%s] contract=%s campaign=%s", table.concat(ids, ","), detail, _campaign_status())
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
