local mod = get_mod("event_tweaker")

-- _evt_missions.lua - issue 626 mission-menu availability adapter
--
-- The Feast of Grimnir reference mod proves that current event levels become
-- selectable when the stock `celebrate` area is visible. Event Tweaker keeps
-- the useful boundary and discards the legacy broad writes: no GameActs,
-- UnlockableLevels, UnlockableLevelsByGameMode, MapPresentationActs, or
-- NetworkLookup mutation. The area flag is changed only for the duration of
-- vanilla's widget build, then restored even if that build raises. Mission
-- lists are rebuilt on each view entry from the exact two-entry allowlist.
-- VMF automatically disables these four hooks with the mod, so reload,
-- disable/re-enable, controller/desktop re-entry, and other mods' area state do
-- not need persistent snapshots or cleanup callbacks.

local ET = mod._evt
local Missions = require("scripts/mods/event_tweaker/event_tweaker_missions")

local function _get(setting_id)
    return mod:get(setting_id)
end

local function _contract()
    return Missions.validate_contract(LevelSettings, AreaSettings, ActSettings, NetworkLookup)
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

    self._levels_by_act = Missions.filter_levels_by_act(self._levels_by_act, LevelSettings, _get)
    local ids = Missions.enabled_ids(_get)
    pcall(printf, "[event-missions:626] menu applied: area=%s act=%s missions=[%s] unrelated_acts=untouched",
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
    mod:echo("[event missions] selected={%s} contract=%s", table.concat(ids, ","), detail)
    pcall(printf, "[event-missions:626] probe selected=[%s] contract=%s", table.concat(ids, ","), detail)
end)

ET.rt_register("issue626_event_mission_allowlist_contract", function()
    if #Missions.ALLOWLIST ~= 2 then return "allowlist must contain exactly two audited missions" end
    if Missions.ALLOWLIST[1].id ~= "dlc_dwarf_fest"
       or Missions.ALLOWLIST[2].id ~= "dlc_celebrate_crawl" then
        return "allowlist contents/order drifted"
    end
    local ok, problems = _contract()
    if not ok then return table.concat(problems, "; ") end
end)
