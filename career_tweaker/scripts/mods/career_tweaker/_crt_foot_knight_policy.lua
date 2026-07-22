-- _crt_foot_knight_policy.lua — Engine-free Foot Knight capability policy.
--
-- Classifies live weapon-template capabilities instead of enumerating item keys,
-- so vanilla weapons and compatible WT/CWV clones share one behavior.  It also
-- owns the deterministic enemy-category multiplier used by the runtime module.
--
-- Owned by: career_tweaker.lua. Consumed via: _crt_foot_knight.lua and QA tests.

local M = {}

local SETTING_AURA_RANGE = "rework_es_knight_protective_presence_10m_rock_20m"
local SETTING_ROCK_SHIELD = "rework_es_knight_rock_shield_offense"
local SETTING_TEAMWORK_GREAT = "rework_es_knight_teamwork_great_weapon_offense"

M.ROCK_DESCRIPTION_KEY = "markus_knight_passive_block_cost_aura_desc_2"
M.TEAMWORK_DESCRIPTION_KEY = "markus_knight_damage_taken_ally_proximity_desc_2"

local GREAT_WEAPON_TYPES = {
    AXE_2H = true,
    MACE_2H = true,
    PICK_2H = true,
    SWORD_2H = true,
}

local POLEARM_NAME_MARKERS = {
    "billhook",
    "glaive",
    "halberd",
    "scythe",
    "spear",
}

function M.is_shield_type(weapon_type, template_name)
    if type(weapon_type) == "string" and weapon_type:find("_SHIELD$", 1, false) ~= nil then
        return true
    end
    -- Warrior Priest's Flail & Shield is authored as FLAIL_1H rather than a
    -- *_SHIELD weapon_type. Template identity closes that native exception and
    -- naturally includes WT/CWV clones whose names retain "shield".
    return type(template_name) == "string"
        and template_name:lower():find("shield", 1, true) ~= nil
end

function M.is_non_polearm_great_type(weapon_type, template_name)
    if GREAT_WEAPON_TYPES[weapon_type] ~= true then return false end
    local name = type(template_name) == "string" and template_name:lower() or ""
    for i = 1, #POLEARM_NAME_MARKERS do
        if name:find(POLEARM_NAME_MARKERS[i], 1, true) then return false end
    end
    return true
end

function M.plan_secondary_slot(slot_types, enabled, owns_melee_entry)
    local planned = {}
    local has_melee = false
    local has_ranged = false
    for i = 1, #(slot_types or {}) do
        planned[#planned + 1] = slot_types[i]
        if slot_types[i] == "melee" then has_melee = true end
        if slot_types[i] == "ranged" then has_ranged = true end
    end

    local owns = owns_melee_entry == true
    if enabled and not has_melee then
        -- Match the native Slayer/Grail Knight contract exactly: melee first,
        -- ranged second. This preserves vanilla inventory-filter precedence.
        table.insert(planned, 1, "melee")
        owns = true
    elseif not enabled and owns then
        for i = #planned, 1, -1 do
            if planned[i] == "melee" then
                table.remove(planned, i)
                break
            end
        end
        owns = false
    end

    -- Foot Knight differs from native dual-melee careers: his secondary slot
    -- must continue accepting bows/guns. Repair a stale or independently
    -- replaced carrier instead of allowing the feature to collapse the slot
    -- to melee-only. `ranged` is the vanilla member, so it remains on restore.
    if enabled and not has_ranged then
        planned[#planned + 1] = "ranged"
    end
    return planned, owns
end

-- Discover every live table that can author Foot Knight's secondary-slot
-- filter.  `pairs` is deliberate: modded profile/career arrays may be sparse,
-- and Lua 5.1's `ipairs` stops at the first hole.  The optional menu career is
-- the exact object the inventory window is about to consume, closing the gap
-- when a late UI/DLC rebuild detached it from both global catalogues.
function M.secondary_slot_carriers(career_settings, profiles, menu_career, menu_label)
    local carriers = {}
    local seen = {}

    local function add(career, label, known_foot_knight)
        if type(career) ~= "table" then return end
        if not known_foot_knight and career ~= career_settings
            and career.name ~= "es_knight" then
            return
        end

        local slot_map = career.item_slot_types_by_slot_name
        local slot_types = slot_map and slot_map.slot_ranged
        if type(slot_types) == "table" and not seen[slot_types] then
            seen[slot_types] = true
            carriers[#carriers + 1] = { slot_types = slot_types, label = label }
        end
    end

    add(career_settings, "CareerSettings.es_knight", true)
    for profile_index, profile in pairs(profiles or {}) do
        for career_index, career in pairs(profile.careers or {}) do
            add(career, string.format("SPProfiles[%s].careers[%s]",
                tostring(profile_index), tostring(career_index)), false)
        end
    end
    add(menu_career, menu_label or "inventory.career", false)

    return carriers
end

local function _setting_enabled(settings, setting_id)
    if type(settings) == "function" then
        return settings(setting_id) == true
    end
    return type(settings) == "table" and settings[setting_id] == true
end

-- Returns nil for the all-off state. The Localize hook treats nil as an exact
-- instruction to delegate to vanilla, rather than attempting to duplicate a
-- translated stock string inside CRT.
function M.talent_description(key, settings)
    if key == M.ROCK_DESCRIPTION_KEY then
        local expanded = _setting_enabled(settings, SETTING_AURA_RANGE)
        local shield = _setting_enabled(settings, SETTING_ROCK_SHIELD)
        if not expanded and not shield then return nil end

        local range = expanded and 20 or 10
        local text = string.format(
            "Increases the range of Protective Presence to %d meters.", range)
        if shield then
            text = text .. " Reduces dodge distance by 10%%. While wielding a shield, grants 15%% power and 30%% more melee damage to Monsters and Berserkers."
        end
        return text
    end

    if key == M.TEAMWORK_DESCRIPTION_KEY
        and _setting_enabled(settings, SETTING_TEAMWORK_GREAT) then
        return "Nearby allies reduce damage taken by 5%% each, up to 3 stacks, within 10 meters. Removes Foot Knight's innate 10%% damage reduction. While wielding a non-polearm great weapon, each nearby ally also grants 5%% power and 10%% more melee damage to Armored enemies and Monsters."
    end

    return nil
end

function M.all_other_allies_dead(dead_flags)
    if type(dead_flags) ~= "table" or #dead_flags == 0 then return false end
    for i = 1, #dead_flags do
        if dead_flags[i] ~= true then return false end
    end
    return true
end

-- Source-scoped claim transition for a non-stacking aura result. Multiple
-- drivers may claim the same target, but the runtime materializes only the
-- first aggregate claim and removes it only after the final source leaves.
-- `source_key` is deliberately opaque so production can use the live driver
-- buff table while engine-free tests use strings.
function M.set_aura_claim(record, source_key, source_value, wants_claim)
    if type(record) ~= "table" or source_key == nil then return 0, nil, false end
    record.sources = record.sources or {}
    local had_claim = record.sources[source_key] ~= nil

    if wants_claim and not had_claim then
        local before = tonumber(record.claim_count) or 0
        record.sources[source_key] = source_value or true
        record.claim_count = before + 1
        return record.claim_count, before == 0 and "add" or nil, true
    elseif not wants_claim and had_claim then
        local before = tonumber(record.claim_count) or 1
        record.sources[source_key] = nil
        record.claim_count = math.max(0, before - 1)
        return record.claim_count, record.claim_count == 0 and "remove" or nil, true
    end

    return tonumber(record.claim_count) or 0, nil, false
end

function M.enemy_multiplier(rock_shield_active, teamwork_great_active, nearby_allies, breed)
    if type(breed) ~= "table" then return 1 end

    local multiplier = 1
    local armor = breed.primary_armor_category or breed.armor_category
    local is_monster = breed.boss == true
    local is_berserker = armor == 5
    local is_armored = armor == 2 or armor == 6

    if rock_shield_active and (is_monster or is_berserker) then
        multiplier = multiplier * 1.30
    end

    local ally_count = math.max(0, math.min(3, tonumber(nearby_allies) or 0))
    if teamwork_great_active and ally_count > 0 and (is_monster or is_armored) then
        multiplier = multiplier * (1 + 0.10 * ally_count)
    end

    return multiplier
end

return M
