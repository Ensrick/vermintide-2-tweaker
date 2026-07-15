-- _mod_tweaker_profiles.lua - bounded per-tab settings profile persistence.
--
-- Each visible tab owns one scalar active-slot key and at most ten independent
-- setting maps.  Keeping the maps separate is deliberate: VMF deep-clones a
-- value on mod:set, so changing one profile must never clone every tab/profile.
-- This module is engine-free so its key and copy contracts can be tested offline.

local Profiles = { MAX_SLOTS = 10 }

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

return Profiles
