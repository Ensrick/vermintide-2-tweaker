-- Pure data policy for Loremaster's Armour shield availability.
local M = {}

-- Keep this complete catalogue as the single source of truth consumed by
-- bridge code, runtime diagnostics, and offline QA.
M.KRUBER_SHIELD_ITEM_TYPES = {
    "es_1h_sword_shield",
    "es_1h_mace_shield",
    "es_1h_sword_shield_breton",
    "es_deus_01",
    "cwv_es_axe_shield",
    "cwv_es_longsword_shield",
    "cwv_es_warpriest_hammer_shield",
}

-- Mesh-family provenance is load-bearing for texture-only LA variants.
-- Bretonnian textures are authored for the heater-shield UVs and cannot be
-- painted onto an Empire shield. Custom-unit variants carry their own mesh and
-- may still fan out across the complete Kruber catalogue.
M.KRUBER_SHIELD_FAMILIES = {
    empire = {
        "es_1h_sword_shield",
        "es_1h_mace_shield",
        "es_deus_01",
        "cwv_es_axe_shield",
        "cwv_es_longsword_shield",
        "cwv_es_warpriest_hammer_shield",
    },
    breton = {
        "es_1h_sword_shield_breton",
    },
}

-- Weavebound (_magic*) and glow-event/Shyish (_runed*) shield skins use
-- dedicated units whose emissive material does not expose Loremasters' normal
-- diffuse slot (confirmed v0.7.99; LA_SYNC_MODEL.md section 6.5).  When a
-- texture-only LA heraldry is selected, route that unit to the geometrically
-- identical plain receiver in the SAME UV family (same unit directory, suffix
-- stripped).  Keep this an exact allow-list: guessing from a generic suffix
-- risks painting Bretonnian heraldry onto an Empire mesh (the #204/#266
-- regression).  Issue #373: rows enumerated from the decompile's skin tables;
-- every citation is scripts/settings/... in Vermintide-2-Source-Code.
local MAGIC_TEXTURE_RECEIVERS = {
    breton = {
        -- weave: equipment/weapon_skins_lake.lua:192 -> :178
        ["units/weapons/player/wpn_emp_gk_shield_01/wpn_emp_gk_shield_01_magic_01"] =
            "units/weapons/player/wpn_emp_gk_shield_01/wpn_emp_gk_shield_01",
        -- glow: weapon_skins_lake.lua:148, dlcs/gotwf/weapon_skins_gotwf_2026.lua:46 -> lake:106
        ["units/weapons/player/wpn_emp_gk_shield_02/wpn_emp_gk_shield_02_runed_01"] =
            "units/weapons/player/wpn_emp_gk_shield_02/wpn_emp_gk_shield_02",
    },
    empire = {
        -- weave: equipment/weapon_skins_scorpion.lua:558
        ["units/weapons/player/wpn_empire_shield_04/wpn_emp_shield_04_magic_01"] =
            "units/weapons/player/wpn_empire_shield_04/wpn_emp_shield_04",
        -- weave: equipment/weapon_skins_morris.lua:254 -> :165
        ["units/weapons/player/wpn_es_deus_shield_02/wpn_es_deus_shield_02_magic"] =
            "units/weapons/player/wpn_es_deus_shield_02/wpn_es_deus_shield_02",
        -- glow: weapon_skins_morris.lua:201, dlcs/gotwf/weapon_skins_gotwf_2025.lua:79 -> morris:151
        ["units/weapons/player/wpn_empire_shield_02/wpn_emp_shield_02_runed_01"] =
            "units/weapons/player/wpn_empire_shield_02/wpn_emp_shield_02",
        -- glow: dlcs/geheimnisnacht_2021/weapon_skins_geheimnisnacht_2021.lua:229 -> equipment/weapon_skins.lua:4008
        ["units/weapons/player/wpn_empire_shield_03/wpn_emp_shield_03_runed_01"] =
            "units/weapons/player/wpn_empire_shield_03/wpn_emp_shield_03",
        -- glow: weapon_skins_morris.lua:216 -> :165
        ["units/weapons/player/wpn_es_deus_shield_02/wpn_es_deus_shield_02_runed"] =
            "units/weapons/player/wpn_es_deus_shield_02/wpn_es_deus_shield_02",
        -- glow: weapon_skins_morris.lua:231 -> :179
        ["units/weapons/player/wpn_es_deus_shield_03/wpn_es_deus_shield_03_runed"] =
            "units/weapons/player/wpn_es_deus_shield_03/wpn_es_deus_shield_03",
    },
    dwarf = {
        -- weave: equipment/weapon_skins_scorpion.lua:473 -> equipment/weapon_skins.lua (wpn_dw_shield_04)
        ["units/weapons/player/wpn_dw_shield_04_t1/wpn_dw_shield_04_magic_01"] =
            "units/weapons/player/wpn_dw_shield_04_t1/wpn_dw_shield_04",
        -- glow: dlcs/gotwf/weapon_skins_gotwf_2025.lua:28 -> equipment/weapon_skins.lua:2569
        ["units/weapons/player/wpn_dw_shield_02_t1/wpn_dw_shield_02_runed_01"] =
            "units/weapons/player/wpn_dw_shield_02_t1/wpn_dw_shield_02",
        -- glow: equipment/weapon_skins.lua:2979 -> :2574
        ["units/weapons/player/wpn_dw_shield_02_t1/wpn_dw_e_shield_02_runed_01"] =
            "units/weapons/player/wpn_dw_shield_02_t1/wpn_dw_e_shield_02",
        -- glow: dlcs/geheimnisnacht_2021/weapon_skins_geheimnisnacht_2021.lua:193 -> equipment/weapon_skins.lua:3076
        ["units/weapons/player/wpn_dw_shield_05_t1/wpn_dw_shield_05_runed_01"] =
            "units/weapons/player/wpn_dw_shield_05_t1/wpn_dw_shield_05",
        -- glow: dlcs/geheimnisnacht_2021/weapon_skins_geheimnisnacht_2021.lua:199 -> equipment/weapon_skins.lua:3081
        ["units/weapons/player/wpn_dw_shield_05_t1/wpn_dw_e_shield_05_runed_01"] =
            "units/weapons/player/wpn_dw_shield_05_t1/wpn_dw_e_shield_05",
    },
    wood_elf = {
        -- weave: equipment/weapon_skins_scorpion.lua:941 -> equipment/weapon_skins_anvil.lua:176
        ["units/weapons/player/wpn_we_shield_02/wpn_we_shield_02_magic_01"] =
            "units/weapons/player/wpn_we_shield_02/wpn_we_shield_02",
        -- glow: dlcs/gotwf/weapon_skins_gotwf_2026.lua:31, equipment/weapon_skins_anvil.lua:161 -> :147
        ["units/weapons/player/wpn_we_shield_01/wpn_we_shield_01_runed_01"] =
            "units/weapons/player/wpn_we_shield_01/wpn_we_shield_01",
    },
    imperial = {
        -- weave: dlcs/bless/weapon_skins_bless.lua:292 -> :204
        ["units/weapons/player/wpn_wh_shield_01/wpn_wh_shield_01_t1_magic"] =
            "units/weapons/player/wpn_wh_shield_01/wpn_wh_shield_01_t1",
        -- glow: dlcs/bless/weapon_skins_bless.lua:218 -> :204
        ["units/weapons/player/wpn_wh_shield_01/wpn_wh_shield_01_t1_runed"] =
            "units/weapons/player/wpn_wh_shield_01/wpn_wh_shield_01_t1",
    },
}

function M.magic_texture_receiver(authored_family, unit_path)
    local family = MAGIC_TEXTURE_RECEIVERS[authored_family]
    return family and family[unit_path] or nil
end

-- #373 boot-time self-report for the "hand-enumerated tables with no
-- validation" corpus cluster: walk the live WeaponSkins tables and flag any
-- shield skin whose left unit looks magic/runed, belongs to a mapped shield
-- family, and has NO receiver row - the exact dead-end that made weave paint
-- silently no-op. Pure (tables and functions in, gap list out); log-only and
-- capped at the caller.
--   weapon_skins:        WeaponSkins.skins (or a fake in tests)
--   family_for_item_type: item_type -> family key ("breton"/"empire"/...)
--   item_type_for_skin:  skin_key -> item_type (caller derives from
--                        ItemMasterList or the skin-key prefix)
function M.find_receiver_gaps(weapon_skins, family_for_item_type, item_type_for_skin)
    local gaps = {}
    if type(weapon_skins) ~= "table" then return gaps end
    for skin_key, skin in pairs(weapon_skins) do
        local data = type(skin) == "table" and (skin.data or skin) or nil
        local unit = data and data.left_hand_unit
        if type(unit) == "string"
                and (unit:find("_magic", 1, true) or unit:find("_runed", 1, true)) then
            local item_type = item_type_for_skin and item_type_for_skin(skin_key)
            local family = item_type and family_for_item_type
                and family_for_item_type(item_type)
            if family and not M.magic_texture_receiver(family, unit) then
                gaps[#gaps + 1] = {
                    skin = tostring(skin_key),
                    unit = unit,
                    family = tostring(family),
                }
            end
        end
    end
    table.sort(gaps, function(a, b) return a.skin < b.skin end)
    return gaps
end

function M.add_compatible_targets(character, variant_kind, authored_family,
        weapon_types, has_canonical_unit)
    if character ~= "Kruber" then return false end
    -- A texture variant with an explicit canonical unit owns both its UVs and
    -- model just like a unit variant.  It can safely fan out because the shared
    -- resolver swaps that model before paint.  Pure-paint variants remain
    -- family-restricted.
    local targets = (variant_kind == "unit" or has_canonical_unit)
        and M.KRUBER_SHIELD_ITEM_TYPES
        or M.KRUBER_SHIELD_FAMILIES[authored_family]
    if not targets then return false end
    for _, item_type in ipairs(targets) do
        weapon_types[item_type] = true
    end
    return true
end

return M
