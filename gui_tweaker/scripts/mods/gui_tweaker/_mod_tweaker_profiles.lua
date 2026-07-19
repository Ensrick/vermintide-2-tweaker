-- _mod_tweaker_profiles.lua - bounded per-tab settings profile persistence.
--
-- Each visible tab owns one scalar active-slot key and at most ten independent
-- setting maps.  Keeping the maps separate is deliberate: VMF deep-clones a
-- value on mod:set, so changing one profile must never clone every tab/profile.
-- This module is engine-free so its key and copy contracts can be tested offline.

local Profiles = { MAX_SLOTS = 10, SCHEMA_VERSION = 1 }

local CT_PROFILE_TABS = { "ct", "ct_dev" }
local CT_PROFILE_OWNERS = { "ct", "ct_dev" }
local SCHEMA_KEY = "mt_profile_schema::ct_trial_cost_absolute"

local function _tab(tab_id)
    -- mod ids are already stable identifiers. Percent-escape the two bytes used
    -- by our key grammar so a synthesized tab can never alias another tab.
    return tostring(tab_id or "?"):gsub("%%", "%%25"):gsub(":", "%%3A")
end

local function _slot(slot)
    slot = tonumber(slot) or 1
    slot = math.floor(slot)
    if slot < 1 then slot = 1 end
    if slot > Profiles.MAX_SLOTS then slot = Profiles.MAX_SLOTS end
    return slot
end

function Profiles.active_key(tab_id)
    return "mt_profile_active::" .. _tab(tab_id)
end

function Profiles.slot_key(tab_id, slot)
    return string.format("mt_profile::%s::%d", _tab(tab_id), _slot(slot))
end

-- Length-prefix the owner. This stays serializer-safe (unlike a NUL separator)
-- and remains reversible even if either id contains punctuation.
function Profiles.member_key(owner_id, setting_id)
    local owner = tostring(owner_id or "?")
    return tostring(#owner) .. ":" .. owner .. tostring(setting_id or "?")
end

function Profiles.split_member_key(key)
    if type(key) ~= "string" then return nil end
    local colon = string.find(key, ":", 1, true)
    if not colon then return nil end
    local n = tonumber(string.sub(key, 1, colon - 1))
    if not n or n < 0 then return nil end
    local first = colon + 1
    local last = first + n - 1
    if last > #key then return nil end
    return string.sub(key, first, last), string.sub(key, last + 1)
end

local function _copy_map(value)
    if type(value) ~= "table" then return nil end
    local out = {}
    for k, v in pairs(value) do out[k] = v end
    return out
end

function Profiles.get_active(store, tab_id)
    local value = store:get(Profiles.active_key(tab_id))
    return _slot(value)
end

function Profiles.set_active(store, tab_id, slot)
    slot = _slot(slot)
    -- Profile bookkeeping is internal to Mod Tweaker; it is not a user-facing
    -- option and must not enter gut's on_setting_changed chain.
    store:set(Profiles.active_key(tab_id), slot, false)
    return slot
end

function Profiles.load(store, tab_id, slot)
    return _copy_map(store:get(Profiles.slot_key(tab_id, slot)))
end

function Profiles.save(store, tab_id, slot, values)
    local owned = _copy_map(values) or {}
    store:set(Profiles.slot_key(tab_id, slot), owned, false)
    return owned
end

function Profiles.reconcile(values, defaults)
    local merged = _copy_map(values) or {}
    local additions = {}
    local count = 0
    if type(defaults) == "table" then
        for key, value in pairs(defaults) do
            if merged[key] == nil and value ~= nil then
                merged[key] = value
                additions[key] = value
                count = count + 1
            end
        end
    end
    return merged, additions, count
end

local function _trial_cost(value)
    value = tonumber(value)
    if not value or value ~= value then value = 100 end
    value = math.floor(value / 25 + 0.5) * 25
    return math.max(0, math.min(1000, value))
end

function Profiles.migrate_ct_trial_cost_map(values)
    local migrated = _copy_map(values)
    if not migrated then return nil, false end
    local changed = false
    for i = 1, #CT_PROFILE_OWNERS do
        local owner = CT_PROFILE_OWNERS[i]
        local enabled_key = Profiles.member_key(owner, "cot_cost_enabled")
        local amount_key = Profiles.member_key(owner, "cot_cost_amount")
        local legacy_enabled = migrated[enabled_key]
        if legacy_enabled ~= nil then
            migrated[amount_key] = legacy_enabled == true
                and _trial_cost(migrated[amount_key]) or 0
            migrated[enabled_key] = nil
            changed = true
        end
    end
    return migrated, changed
end

function Profiles.migrate_all(store)
    if type(store) ~= "table" or type(store.get) ~= "function"
            or type(store.set) ~= "function" then
        return false, 0, "profile store unavailable"
    end
    local read_ok, schema = pcall(store.get, store, SCHEMA_KEY)
    if not read_ok then return false, 0, tostring(schema) end
    if (tonumber(schema) or 0) >= Profiles.SCHEMA_VERSION then return true, 0 end
    local changed = 0
    for i = 1, #CT_PROFILE_TABS do
        local tab_id = CT_PROFILE_TABS[i]
        for slot = 1, Profiles.MAX_SLOTS do
            local key = Profiles.slot_key(tab_id, slot)
            local slot_ok, values = pcall(store.get, store, key)
            if not slot_ok then return false, changed, tostring(values) end
            local migrated, dirty = Profiles.migrate_ct_trial_cost_map(values)
            if dirty then
                local ok, err = pcall(store.set, store, key, migrated, false)
                if not ok then return false, changed, tostring(err) end
                changed = changed + 1
            end
        end
    end
    local ok, err = pcall(store.set, store, SCHEMA_KEY, Profiles.SCHEMA_VERSION, false)
    if not ok then return false, changed, tostring(err) end
    return true, changed
end

return Profiles
