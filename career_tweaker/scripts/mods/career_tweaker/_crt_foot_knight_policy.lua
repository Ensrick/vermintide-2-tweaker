-- _crt_foot_knight_policy.lua — Engine-free Foot Knight capability policy.
--
-- Classifies live weapon-template capabilities instead of enumerating item keys,
-- so vanilla weapons and compatible WT/CWV clones share one behavior.  It also
-- owns the deterministic enemy-category multiplier used by the runtime module.
--
-- Owned by: career_tweaker.lua. Consumed via: _crt_foot_knight.lua and QA tests.

local M = {}

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
    for i = 1, #(slot_types or {}) do
        planned[#planned + 1] = slot_types[i]
        if slot_types[i] == "melee" then has_melee = true end
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
    return planned, owns
end

function M.all_other_allies_dead(dead_flags)
    if type(dead_flags) ~= "table" or #dead_flags == 0 then return false end
    for i = 1, #dead_flags do
        if dead_flags[i] ~= true then return false end
    end
    return true
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
