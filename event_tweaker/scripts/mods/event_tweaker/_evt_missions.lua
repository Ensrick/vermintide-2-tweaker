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
local _last_area_signature
local _last_area_proof = "not-called"
local function _report_contract_failure(problems)
    local detail = table.concat(problems or {}, "; ")
    if detail ~= _last_contract_error then
        _last_contract_error = detail
        pcall(printf, "[event-missions:626] blocked: %s", detail ~= "" and detail or "unknown contract failure")
    end
end

local function _has_assigned_area_widget(self)
    local function is_target(widget)
        return type(widget) == "table" and type(widget.content) == "table"
            and widget.content.area_name == Missions.AREA_KEY
    end
    if type(self) ~= "table" then return false end
    if type(self._widgets_by_name) == "table" and is_target(self._widgets_by_name.main_campaign) then
        return true
    end
    if type(self._area_widgets) == "table" then
        for _, widget in pairs(self._area_widgets) do
            if is_target(widget) then return true end
        end
    end
    return false
end

local function _with_celebrate_area_exposed(func, self, surface)
    _area_hook_calls = _area_hook_calls + 1
    if not Missions.any_enabled(_get) then return func(self) end

    local ok, problems = _contract()
    if not ok then
        _report_contract_failure(problems)
        return func(self)
    end

    local snapshot, proof = Missions.apply_area_presentation(LevelSettings, AreaSettings)
    if not snapshot then
        _report_contract_failure({ proof })
        return func(self)
    end

    -- Both vanilla methods have the source-verified `(self)` signature and no
    -- return value. pcall exists only so the temporary global bit is restored
    -- on a Lua error; the original error is then propagated.
    local call_ok, call_error = pcall(func, self)
    local assigned = _has_assigned_area_widget(self)
    Missions.restore_area_presentation(snapshot)
    local ids = Missions.enabled_ids(_get)
    local signature = table.concat({
        tostring(surface), table.concat(ids, ","), tostring(assigned),
        tostring(proof.visible_count), tostring(proof.sort_order), tostring(proof.display_name),
    }, "|")
    _last_area_proof = signature
    if signature ~= _last_area_signature then
        _last_area_signature = signature
        pcall(printf,
            "[event-missions:626] area applied: surface=%s missions=[%s] widget_assigned=%s visible=%s sort=%s label=%s",
            tostring(surface), table.concat(ids, ","), tostring(assigned),
            tostring(proof.visible_count), tostring(proof.sort_order), tostring(proof.display_name))
    end
    if not call_ok then error(call_error) end
end

local function _replace_celebrate_levels(func, self, ...)
    _mission_hook_calls = _mission_hook_calls + 1
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
    return _with_celebrate_area_exposed(func, self, "desktop")
end)

mod:hook("StartGameWindowAreaSelectionConsoleV2", "_setup_area_widgets", function(func, self)
    return _with_celebrate_area_exposed(func, self, "console")
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
    mod:echo("[event missions] selected={%s} contract=%s campaign=%s area_hooks=%d mission_hooks=%d",
        table.concat(ids, ","), detail, _campaign_status(), _area_hook_calls, _mission_hook_calls)
    pcall(printf,
        "[event-missions:626] probe selected=[%s] contract=%s campaign=%s area_hooks=%d mission_hooks=%d last_area=%s",
        table.concat(ids, ","), detail, _campaign_status(), _area_hook_calls, _mission_hook_calls,
        _last_area_proof)
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
