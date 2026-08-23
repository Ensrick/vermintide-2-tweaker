-- Source-pinned Ranald's Gift catalogue and document normalizer (#1360).
--
-- The public Firestore documents store compact integer ids.  This module is
-- deliberately engine-free: it owns the current upstream id vocabulary,
-- converts one decoded document into a bounded semantic build, and supplies a
-- deterministic client-side sort.  Runtime code must still validate every
-- resolved key against the live ItemMasterList/trait/property tables before it
-- mutates inventory state.

local M = {}

M.SOURCE_REPOSITORY = "https://github.com/ranaldsgift/ranalds.gift"
M.SOURCE_COMMIT = "50f8ca93ecc74f95f806e424827c30b6b107cc1f"
M.SOURCE_REVISION_DATE = "2026-08-23"
M.PAGE_SIZE = 5

M.CAREERS = {
    [1] = "es_mercenary", [2] = "es_huntsman", [3] = "es_knight",
    [4] = "dr_ranger", [5] = "dr_ironbreaker", [6] = "dr_slayer",
    [7] = "we_waywatcher", [8] = "we_maidenguard", [9] = "we_shade",
    [10] = "wh_captain", [11] = "wh_bountyhunter", [12] = "wh_zealot",
    [13] = "bw_adept", [14] = "bw_scholar", [15] = "bw_unchained",
    [16] = "es_questingknight", [17] = "dr_engineer",
    [18] = "we_thornsister", [19] = "wh_priest", [20] = "bw_necro",
}

M.WEAPONS = {
    [1] = "bw_1h_mace", [2] = "bw_dagger", [3] = "bw_flame_sword",
    [4] = "bw_sword", [5] = "dr_1h_axe", [6] = "dr_1h_hammer",
    [7] = "dr_2h_axe", [8] = "dr_2h_hammer", [9] = "dr_2h_pick",
    [10] = "dr_dual_wield_axes", [11] = "dr_shield_axe",
    [12] = "dr_shield_hammer", [13] = "es_1h_flail", [14] = "es_1h_mace",
    [15] = "es_1h_sword", [16] = "es_2h_hammer", [17] = "es_2h_sword",
    [18] = "es_2h_sword_executioner", [19] = "es_halberd",
    [20] = "es_mace_shield", [21] = "es_sword_shield", [22] = "we_1h_sword",
    [23] = "we_2h_axe", [24] = "we_2h_sword", [25] = "we_dual_wield_daggers",
    [26] = "we_dual_wield_sword_dagger", [27] = "we_dual_wield_swords",
    [28] = "we_spear", [29] = "wh_1h_axe", [30] = "wh_1h_falchion",
    [31] = "wh_2h_sword", [32] = "wh_fencing_sword",
    [33] = "es_dual_wield_hammer_sword", [34] = "es_2h_heavy_spear",
    [35] = "we_1h_axe", [36] = "we_1h_spears_shield",
    [37] = "dr_dual_wield_hammers", [38] = "wh_dual_wield_axe_falchion",
    [39] = "wh_2h_billhook", [40] = "bw_1h_crowbill",
    [41] = "bw_1h_flail_flaming", [42] = "es_sword_shield_breton",
    [43] = "es_bastard_sword", [44] = "dr_2h_cog_hammer",
    [45] = "bw_skullstaff_beam", [46] = "bw_skullstaff_fireball",
    [47] = "bw_skullstaff_flamethrower", [48] = "bw_skullstaff_geiser",
    [49] = "bw_skullstaff_spear", [50] = "dr_crossbow",
    [51] = "dr_drake_pistol", [52] = "dr_drakegun", [53] = "dr_handgun",
    [54] = "dr_rakegun", [55] = "es_blunderbuss", [56] = "es_handgun",
    [57] = "es_longbow", [58] = "es_repeating_handgun",
    [59] = "we_crossbow_repeater", [60] = "we_longbow", [61] = "we_shortbow",
    [62] = "we_shortbow_hagbane", [63] = "wh_brace_of_pistols",
    [64] = "wh_crossbow", [65] = "wh_crossbow_repeater",
    [66] = "wh_repeating_pistols", [67] = "dr_1h_throwing_axes",
    [68] = "dr_steam_pistol", [69] = "es_deus_01", [70] = "dr_deus_01",
    [71] = "we_deus_01", [72] = "wh_deus_01", [73] = "bw_deus_01",
    [74] = "we_life_staff", [75] = "we_javelin", [76] = "wh_1h_hammer",
    [77] = "wh_2h_hammer", [78] = "wh_hammer_shield",
    [79] = "wh_dual_hammer", [80] = "wh_hammer_book",
    [81] = "wh_flail_shield", [82] = "bw_reaper", [83] = "bw_soulsteal",
}

M.PROPERTIES = {
    melee = {
        [1] = "attack_speed", [2] = "stamina", [3] = "block_cost",
        [4] = "crit_chance", [5] = "crit_boost", [6] = "push_block_arc",
        [7] = "power_vs_skaven", [8] = "power_vs_chaos",
    },
    ranged = {
        [1] = "crit_chance", [2] = "crit_boost", [3] = "power_vs_skaven",
        [4] = "power_vs_chaos", [5] = "power_vs_unarmoured",
        [6] = "power_vs_armoured", [7] = "power_vs_frenzy",
        [8] = "power_vs_large",
    },
    necklace = {
        [1] = "stamina", [2] = "block_cost", [3] = "health",
        [4] = "push_block_arc", [5] = "protection_skaven",
        [6] = "protection_chaos", [7] = "protection_aoe",
    },
    ring = {
        [1] = "attack_speed", [2] = "crit_boost", [3] = "power_vs_skaven",
        [4] = "power_vs_chaos", [5] = "power_vs_unarmoured",
        [6] = "power_vs_armoured", [7] = "power_vs_frenzy",
        [8] = "power_vs_large",
    },
    trinket = {
        [1] = "ability_cooldown_reduction", [2] = "crit_chance",
        [3] = "curse_resistance", [4] = "movespeed", [5] = "respawn_speed",
        [6] = "revive_speed", [7] = "fatigue_regen",
    },
}

M.TRAITS = {
    melee = {
        [1] = "melee_shield_on_assist", [2] = "melee_increase_damage_on_block",
        [3] = "melee_counter_push_power", [4] = "melee_timed_block_cost",
        [5] = "melee_reduce_cooldown_on_crit", [6] = "melee_attack_speed_on_crit",
    },
    ranged_ammo = {
        [1] = "ranged_consecutive_hits_increase_power",
        [2] = "ranged_replenish_ammo_headshot",
        [3] = "ranged_increase_power_level_vs_armour_crit",
        [4] = "ranged_restore_stamina_headshot",
        [5] = "ranged_reduce_cooldown_on_crit",
        [6] = "ranged_replenish_ammo_on_crit",
    },
    ranged_heat = {
        [1] = "ranged_consecutive_hits_increase_power",
        [2] = "ranged_remove_overcharge_on_crit",
        [3] = "ranged_increase_power_level_vs_armour_crit",
        [4] = "ranged_restore_stamina_headshot",
        [5] = "ranged_reduce_cooldown_on_crit", [6] = "ranged_reduced_overcharge",
    },
    ranged_energy = {
        [1] = "ranged_consecutive_hits_increase_power",
        [3] = "ranged_increase_power_level_vs_armour_crit",
        [4] = "ranged_restore_stamina_headshot",
        [5] = "ranged_reduce_cooldown_on_crit",
    },
    defence_accessory = {
        [1] = "necklace_damage_taken_reduction_on_heal",
        [2] = "necklace_heal_self_on_heal_other",
        [3] = "necklace_not_consume_healing",
        [4] = "necklace_no_healing_health_regen",
        [5] = "necklace_increased_healing_received",
    },
    offence_accessory = {
        [1] = "ring_all_potions", [2] = "ring_potion_duration",
        [3] = "ring_not_consume_potion", [4] = "ring_potion_spread",
    },
    utility_accessory = {
        [1] = "trinket_increase_grenade_radius",
        [2] = "trinket_not_consume_grenade",
        [3] = "trinket_grenade_damage_taken",
    },
}

-- Ranald categorizes Trollhammer with ordinary ammunition weapons. The live
-- item has a narrower `trollhammer_torpedo` trait table; mapping the semantic
-- ids here and validating against that live table in the importer preserves
-- legal rows while safely rejecting site choices the game cannot represent.
M.TRAITS.trollhammer_torpedo = M.TRAITS.ranged_ammo

local function _integer(value)
    local number = tonumber(value)
    if not number or number == math.huge or number == -math.huge
            or number ~= math.floor(number) or math.abs(number) > 2147483647 then
        return nil
    end
    return number
end

local function _clean_text(value, limit, fallback)
    if type(value) ~= "string" then return fallback end
    value = value:gsub("[%c]", " "):gsub("%s+", " ")
    value = value:match("^%s*(.-)%s*$") or ""
    if value == "" then return fallback end
    if #value > limit then value = value:sub(1, limit - 3) .. "..." end
    return value
end

local function _slot(value, needs_weapon_id)
    if type(value) ~= "table" then return nil, "missing" end
    local result = {
        property1_id = _integer(value.property1Id),
        property2_id = _integer(value.property2Id),
        trait_id = _integer(value.traitId),
    }
    if needs_weapon_id then result.weapon_id = _integer(value.id) end
    if needs_weapon_id and not M.WEAPONS[result.weapon_id] then return nil, "weapon_id" end
    if not result.property1_id or not result.property2_id or not result.trait_id then
        return nil, "roll_ids"
    end
    if result.property1_id == result.property2_id then return nil, "duplicate_properties" end
    return result
end

function M.normalize_document(document)
    if type(document) ~= "table" or type(document.fields) ~= "table" then
        return nil, "document"
    end
    local fields = document.fields
    local career_id = _integer(fields.careerId)
    local career_name = M.CAREERS[career_id]
    if not career_name then return nil, "career_id" end

    local build = {
        document_id = _clean_text(type(document.name) == "string"
            and document.name:match("/builds/([^/]+)$") or nil, 128, "unknown"),
        career_id = career_id,
        career_name = career_name,
        name = _clean_text(fields.name, 96, "Unnamed build"),
        username = _clean_text(fields.username, 48, "Unknown author"),
        like_count = math.min(999999999,
            math.max(0, _integer(fields.likeCount) or 0)),
        date_modified = _clean_text(fields.dateModified, 48, ""),
        talents = {},
        slots = {},
    }
    for row = 1, 6 do
        local pick = _integer(fields["talent" .. row])
        if not pick or pick < 1 or pick > 3 then
            return nil, "talent" .. row
        end
        build.talents[row] = pick
    end

    local slot_specs = {
        { "slot_melee", "primaryWeapon", true },
        { "slot_ranged", "secondaryWeapon", true },
        { "slot_necklace", "necklace", false },
        { "slot_ring", "charm", false },
        { "slot_trinket_1", "trinket", false },
    }
    for i = 1, #slot_specs do
        local spec = slot_specs[i]
        local slot, reason = _slot(fields[spec[2]], spec[3])
        if not slot then return nil, spec[2] .. ":" .. tostring(reason) end
        slot.slot_name = spec[1]
        build.slots[spec[1]] = slot
    end
    return build
end

function M.property_key(kind, id)
    local values = M.PROPERTIES[kind]
    return values and values[_integer(id)] or nil
end

function M.trait_key(trait_table_name, id)
    local values = M.TRAITS[trait_table_name]
    return values and values[_integer(id)] or nil
end

function M.sort(builds, mode)
    local output = {}
    for i = 1, #(builds or {}) do output[i] = builds[i] end
    table.sort(output, function(a, b)
        if mode == "recent" then
            if a.date_modified ~= b.date_modified then
                return a.date_modified > b.date_modified
            end
            if a.like_count ~= b.like_count then return a.like_count > b.like_count end
        else
            if a.like_count ~= b.like_count then return a.like_count > b.like_count end
            if a.date_modified ~= b.date_modified then
                return a.date_modified > b.date_modified
            end
        end
        return tostring(a.document_id) < tostring(b.document_id)
    end)
    return output
end

return M
