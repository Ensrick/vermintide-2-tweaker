-- _cos_composite_icon_catalog.lua -- authored layered weapon-icon catalog.
--
-- Data only. Exact primary and offhand identities map to independently authored
-- 80x80 layers. Missing mappings intentionally fail closed to the native icon.
--
-- Owned by: cosmetics_tweaker.lua. Consumed by: _cos_composite_icons.lua.

return {
    layer_order = {
        "native_background",
        "primary_weapon",
        "offhand",
        "glow_mask",
        "native_frame",
    },
    compatible_item_types = {
        es_1h_mace_shield = true,
    },
    primary_by_skin = {
        -- #650 proof: apply the first live picker primary (skin_02) to the
        -- user-authored mace cutout. The skin_03 entries retain the same proof
        -- layer for the exact mesh family used during the reported test.
        es_1h_mace_shield_skin_02 = "icon_cos_empire_mace_shield_primary_01",
        es_1h_mace_shield_skin_02_runed_01 = "icon_cos_empire_mace_shield_primary_01",
        es_1h_mace_shield_skin_03 = "icon_cos_empire_mace_shield_primary_01",
        es_1h_mace_shield_skin_03_runed_01 = "icon_cos_empire_mace_shield_primary_01",
        es_1h_mace_shield_skin_03_runed_02 = "icon_cos_empire_mace_shield_primary_01",
        -- GOTWF 2026 reuses the exact skin_03 mace mesh. The first proof
        -- omitted this live skin even though it is the variant used in the
        -- reported verification session (backend 6F7F2C25A71FCC47).
        es_1h_mace_shield_skin_03_runed_05 = "icon_cos_empire_mace_shield_primary_01",
    },
    offhand_by_unit = {
        ["units/weapons/player/wpn_emp_gk_shield_03/wpn_emp_gk_shield_03"] = {
            texture = "icon_cos_breton_shield_01",
        },
        -- Rune eligibility is exact identity, never inferred from the shared
        -- Bretonnian family or merely from the presence of saved rune RGB.
        ["units/weapons/player/wpn_emp_gk_shield_02/wpn_emp_gk_shield_02_runed_01"] = {
            texture = "icon_cos_breton_shield_02",
            glow_style = "breton_rune",
        },
        ["units/weapons/player/wpn_emp_gk_shield_02/wpn_emp_gk_shield_02"] = {
            texture = "icon_cos_breton_shield_02",
        },
        ["units/weapons/player/wpn_emp_gk_shield_01/wpn_emp_gk_shield_01"] = {
            texture = "icon_cos_breton_shield_03",
        },
        ["units/weapons/player/wpn_emp_gk_shield_04/wpn_emp_gk_shield_04"] = {
            texture = "icon_cos_breton_shield_04",
        },
    },
    offhand_by_armoury = {
        Kruber_Grail_Knight_Bastonne02 = { texture = "icon_cos_breton_shield_bastonne_01" },
        Kruber_bret_shield_hero1_Alberic01 = { texture = "icon_cos_breton_shield_alberic_01" },
        Kruber_bret_shield_basic3_Lothar01 = { texture = "icon_cos_breton_shield_lothar_01" },
        Kruber_bret_shield_basic2_Luidhard01 = { texture = "icon_cos_breton_shield_luidhard_01" },
        Kruber_bret_shield_basic1_Reynard01 = { texture = "icon_cos_breton_shield_reynard_01" },
    },
    glow_styles = {
        breton_rune = {
            texture = "icon_cos_breton_shield_rune_glow",
            component = "rune",
            material_variable = "rune_emissive_color",
            material_brightness = 9,
        },
    },
}
