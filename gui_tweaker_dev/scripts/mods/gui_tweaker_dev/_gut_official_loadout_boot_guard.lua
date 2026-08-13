-- Issue #402: keep modded startup verification from rewriting official loadouts.
--
-- Vanilla has boot-time mutation paths outside set_character_data:
--   * _set_inital_career_data clears/rebuilds the local official rows and classifies
--     slots against live item tables that mods can legitimately extend or reshape;
--   * _fix_career_data / fix_career_data_request_cb can replace those rows with
--     starting gear and write the replacement back to characters_data;
--   * _verify_career_loadouts / verify_career_loadouts_cb invoke CloudScript and
--     write its returned characters_data before ordinary equip hooks exist.
-- In a modded Adventure session we still import the official snapshot as a seed, but
-- validation is read-only: no repair request is sent and no repair response is applied.

local mod = get_mod("gut_dev")
local Policy = mod:dofile("scripts/mods/gui_tweaker_dev/_gut_official_loadout_boot_policy")

local M = {}
local ADVENTURE_DATA_KEY = "characters_data"
local NO_VERIFY_SLOTS = {}

local function _backend_realm()
    local managers = rawget(_G, "Managers")
    local backend = managers and managers.backend
    local metadata = type(backend) == "table" and rawget(backend, "_metadata")
    local realm = type(metadata) == "table" and rawget(metadata, "realm")
    if realm == "modded" or realm == "official" then return realm end
end

function M.in_modded_realm()
    local sd = rawget(_G, "script_data")
    return Policy.realm_is_modded(_backend_realm(), sd and sd["eac-untrusted"])
end

function M.active(mirror)
    return Policy.guard_active(M.in_modded_realm(),
        mirror and mirror._characters_data_key, ADVENTURE_DATA_KEY)
end

local function _official_snapshot_present(self)
    if type(self) ~= "table" then return false end
    local value
    if type(self.get_read_only_data) == "function" then
        local ok, result = pcall(self.get_read_only_data, self, ADVENTURE_DATA_KEY)
        if ok then value = result end
    end
    if value ~= nil and value ~= "" then return true end
    local decoded = rawget(self, "_characters_data")
    return type(decoded) == "table" and next(decoded) ~= nil
end

local function _continue_after_fix(self, result)
    self.broken_slots_data = nil
    self._num_items_to_load = Policy.decrement_pending(self._num_items_to_load)
    local function_result = result and result.FunctionResult
    local next_step = Policy.fix_continuation(function_result and function_result.num_items_granted)
    if next_step == "inventory" and type(self._request_user_inventory) == "function" then
        return self:_request_user_inventory()
    end
    if type(self._verify_default_gear) == "function" then
        return self:_verify_default_gear()
    end
end

-- Preserve vanilla's exact snapshot import while making the verification set empty.
-- This avoids false broken-slot classification against mod-mutated item registries.
mod:hook("PlayFabMirrorAdventure", "_set_inital_career_data",
    function(func, self, career_name, character_data, slots_to_verify)
        if not M.active(self) then
            return func(self, career_name, character_data, slots_to_verify)
        end
        printf("[gut:402] boot snapshot imported without destructive slot verification career=%s",
            tostring(career_name))
        return func(self, career_name, character_data, NO_VERIFY_SLOTS)
    end)

-- Prevent both the ordinary broken-slot repair and the Adventure clear-inventory repair
-- from calling CloudScript in a modded session. Weaves uses a separate data contract and
-- remains on vanilla behavior.
mod:hook("PlayFabMirrorAdventure", "_fix_career_data",
    function(func, self, broken_slots_data, override_mechanism, override_cb_func)
        local repairs_adventure = override_mechanism == nil or override_mechanism == "adventure"
        if not M.active(self) or not repairs_adventure then
            return func(self, broken_slots_data, override_mechanism, override_cb_func)
        end
        printf("[gut:402] blocked official fixCareerData request in modded Adventure")
        if type(self._verify_default_gear) == "function" then
            return self:_verify_default_gear()
        end
    end)

-- A callback can already be queued before VMF finishes loading. Consume its bookkeeping
-- and continue boot without applying returned starting gear or writing characters_data.
mod:hook("PlayFabMirrorAdventure", "fix_career_data_request_cb", function(func, self, result)
    if not M.active(self) then return func(self, result) end
    printf("[gut:402] discarded in-flight official fixCareerData response in modded Adventure")
    return _continue_after_fix(self, result)
end)

-- Block the request as well as the callback: suppressing only the returned local write is
-- too late because verifyCareerLoadouts is itself a mutating CloudScript operation.
mod:hook("PlayFabMirrorAdventure", "_verify_career_loadouts", function(func, self)
    if not M.active(self) then return func(self) end
    if Policy.allow_verify_bootstrap(_official_snapshot_present(self)) then
        self._gut402_allow_verify_response = true
        printf("[gut:402] allowed one official verifyCareerLoadouts bootstrap (no snapshot exists)")
        return func(self)
    end
    printf("[gut:402] blocked official verifyCareerLoadouts request in modded Adventure")
    if type(self._verify_dlc_careers) == "function" then
        return self:_verify_dlc_careers()
    end
end)

mod:hook("PlayFabMirrorAdventure", "verify_career_loadouts_cb", function(func, self, result)
    if not M.active(self) then return func(self, result) end
    local allow_bootstrap = self._gut402_allow_verify_response == true or
        Policy.allow_verify_bootstrap(_official_snapshot_present(self))
    self._gut402_allow_verify_response = nil
    if allow_bootstrap then
        printf("[gut:402] accepted one official verifyCareerLoadouts bootstrap response")
        return func(self, result)
    end
    self._num_items_to_load = Policy.decrement_pending(self._num_items_to_load)
    printf("[gut:402] discarded in-flight official verifyCareerLoadouts response in modded Adventure")
    if type(self._verify_dlc_careers) == "function" then
        return self:_verify_dlc_careers()
    end
end)

M.HOOK_TARGETS = {
    { "PlayFabMirrorAdventure", "_set_inital_career_data" },
    { "PlayFabMirrorAdventure", "_fix_career_data" },
    { "PlayFabMirrorAdventure", "fix_career_data_request_cb" },
    { "PlayFabMirrorAdventure", "_verify_career_loadouts" },
    { "PlayFabMirrorAdventure", "verify_career_loadouts_cb" },
}

M.policy = Policy
M.official_snapshot_present = _official_snapshot_present
return M
