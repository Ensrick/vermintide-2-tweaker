-- Registration and cross-mod contract for CWV's Crowbill family.
--
-- Only the two CC-BY 4.0 models approved in issue #604 are declared here. Raw
-- archives remain outside the repository; derived resources are resident from
-- CWV's master package. The Free Standard Italian model is intentionally absent.
local M = {}

M.SOURCE_ITEM = "bw_1h_crowbill"
M.SOURCE_TEMPLATE = "one_handed_crowbill"
M.SOURCE_SKIN_TABLE = "bw_1h_crowbill_skins"
M.PLACEHOLDER_UNIT = "units/weapons/player/wpn_brw_crowbill_01/wpn_brw_crowbill_01"
M.PLACEHOLDER_ICON = "icon_bw_1h_crowbill_01"
M.HAMMER_MODE_FAMILY = "cwv_crowbill_hammer_mode"
M.PREVIEW_PACKAGE_ALIAS = M.PLACEHOLDER_UNIT .. "_3p"
M.NETWORK_PACKAGE_ALIAS_1P = M.PLACEHOLDER_UNIT
M.NETWORK_PACKAGE_ALIAS_3P = M.PREVIEW_PACKAGE_ALIAS

M.ALL_CAREERS = {
    "es_mercenary", "es_huntsman", "es_knight", "es_questingknight",
    "dr_ranger", "dr_ironbreaker", "dr_slayer", "dr_engineer",
    "we_waywatcher", "we_maidenguard", "we_shade", "we_thornsister",
    "wh_captain", "wh_bountyhunter", "wh_zealot", "wh_priest",
    "bw_adept", "bw_scholar", "bw_unchained", "bw_necromancer",
}

M.IMPERIAL_DEFAULTS = {
    "es_mercenary", "es_huntsman", "es_knight", "es_questingknight",
    "wh_captain", "wh_bountyhunter", "wh_zealot", "wh_priest",
}

M.DAWI_DEFAULTS = {
    "dr_ranger", "dr_ironbreaker", "dr_slayer", "dr_engineer",
}

-- Shared values consumed by the isolated hammer-mode implementation. The
-- family module declares the immutable design contract; it does not install
-- hooks, mutate templates, or implement the Weapon Special state machine.
M.HAMMER_MODE = {
    weapon_special_toggle = true,
    default_mode = "crowbill",
    model_flip_axis = { 0, 0, 1 },
    rotation_degrees = 180,
    same_moveset_and_timing = true,
    attack_cleave_multiplier = 1.60,
    impact_cleave_multiplier = 1.60,
    direct_damage_multiplier = 0.85,
    light_attacks_armor_piercing = false,
    vanilla_sienna_optional = true,
}

M.VARIANTS = {
    {
        key = "cwv_es_imperial_crowbill",
        display_name = "Imperial Crowbill",
        character = "empire_soldier",
        default_careers = M.IMPERIAL_DEFAULTS,
        crowbill_mode_family = M.HAMMER_MODE_FAMILY,
    },
    {
        key = "cwv_dr_dawi_crowbill",
        display_name = "Dawi Crowbill",
        character = "dwarf_ranger",
        default_careers = M.DAWI_DEFAULTS,
        crowbill_mode_family = M.HAMMER_MODE_FAMILY,
    },
}

M.MODELS = {
    {
        variant_key = "cwv_es_imperial_crowbill",
        key = "cwv_es_imperial_crowbill_skin",
        display_name = "Imperial Crowbill Model 01",
        description = "A provisional Imperial Crowbill model awaiting in-game pose review and final naming.",
        source_asset_id = "parelaxel_medieval_war_hammer",
        right_hand_unit = "units/cwv_crowbill/imperial_01/imperial_01",
        inventory_icon = M.PLACEHOLDER_ICON,
        hud_icon = "weapon_generic_icon_falken",
    },
    {
        variant_key = "cwv_dr_dawi_crowbill",
        key = "cwv_dr_dawi_crowbill_skin",
        display_name = "Dawi Crowbill Model 01",
        description = "A provisional Dawi Crowbill model awaiting in-game pose review and final naming.",
        source_asset_id = "soidev_war_hammer",
        right_hand_unit = "units/cwv_crowbill/dawi_01/dawi_01",
        inventory_icon = M.PLACEHOLDER_ICON,
        hud_icon = "weapon_generic_icon_falken",
        -- User-reviewed Hold-Pose tune for Dawi Model 01. The request was not
        -- perspective-limited: held 1P, owner/bot/husk 3P and every preview
        -- consume the same canonical transform.
        right_hand_scale = { 0.5, 0.5, 0.5 },
        right_hand_rotation = { -90, -90, -90 },
    },
    {
        variant_key = "cwv_es_imperial_crowbill",
        key = "cwv_es_imperial_crowbill_skin_02",
        display_name = "Imperial Crowbill Model 02",
        description = "A provisional Imperial Crowbill model awaiting in-game pose review and final naming.",
        right_hand_unit = "units/cwv_crowbill/imperial_02/imperial_02",
        inventory_icon = M.PLACEHOLDER_ICON,
        hud_icon = "weapon_generic_icon_falken",
    },
    {
        variant_key = "cwv_es_imperial_crowbill",
        key = "cwv_es_imperial_crowbill_skin_03",
        display_name = "Imperial Crowbill Model 03",
        description = "A provisional Imperial Crowbill model awaiting in-game pose review and final naming.",
        right_hand_unit = "units/cwv_crowbill/imperial_03/imperial_03",
        inventory_icon = M.PLACEHOLDER_ICON,
        hud_icon = "weapon_generic_icon_falken",
    },
    {
        variant_key = "cwv_es_imperial_crowbill",
        key = "cwv_es_imperial_crowbill_skin_04",
        display_name = "Imperial Crowbill Model 04",
        description = "A provisional Imperial Crowbill model awaiting in-game pose review and final naming.",
        right_hand_unit = "units/cwv_crowbill/imperial_04/imperial_04",
        inventory_icon = M.PLACEHOLDER_ICON,
        hud_icon = "weapon_generic_icon_falken",
    },
    {
        variant_key = "cwv_es_imperial_crowbill",
        key = "cwv_es_imperial_crowbill_skin_05",
        display_name = "Imperial Crowbill Model 05",
        description = "A provisional Imperial Crowbill model awaiting in-game pose review and final naming.",
        right_hand_unit = "units/cwv_crowbill/imperial_05/imperial_05",
        inventory_icon = M.PLACEHOLDER_ICON,
        hud_icon = "weapon_generic_icon_falken",
        -- User-reviewed Hold-Pose tune. The request was not perspective-
        -- limited, so the same model-space transform is canonical everywhere.
        right_hand_scale = { 0.45, 0.45, 0.45 },
        right_hand_offset = { 0, -0.03, -0.20 },
        right_hand_rotation = { -90, -90, -90 },
    },
}

function M.is_usable_model(model)
    return type(model) == "table"
        and type(model.variant_key) == "string" and model.variant_key ~= ""
        and type(model.display_name) == "string" and model.display_name ~= ""
        and type(model.right_hand_unit) == "string" and model.right_hand_unit ~= ""
end

function M.usable_models()
    local result = {}
    for _, model in ipairs(M.MODELS) do
        if M.is_usable_model(model) then result[#result + 1] = model end
    end
    return result
end

function M.model_for_variant(variant_key)
    for _, model in ipairs(M.MODELS) do
        if M.is_usable_model(model) and model.variant_key == variant_key then return model end
    end
    return nil
end

function M.preview_package_alias(package_name)
    if type(package_name) ~= "string" then return nil end
    for _, model in ipairs(M.MODELS) do
        local unit = model.right_hand_unit
        if package_name == unit or package_name == unit .. "_3p" then
            return M.PREVIEW_PACKAGE_ALIAS
        end
    end
    return nil
end

function M.collected_package_alias(package_name)
    if type(package_name) ~= "string" then return nil end
    for _, model in ipairs(M.MODELS) do
        local unit = model.right_hand_unit
        if package_name == unit then return M.NETWORK_PACKAGE_ALIAS_1P end
        if package_name == unit .. "_3p" then return M.NETWORK_PACKAGE_ALIAS_3P end
    end
    return nil
end

function M.alias_collected_packages(package_names)
    if type(package_names) ~= "table" then return package_names, 0 end
    local replaced = 0
    for index = 1, #package_names do
        local alias = M.collected_package_alias(package_names[index])
        if alias then
            package_names[index] = alias
            replaced = replaced + 1
        end
    end
    return package_names, replaced
end

function M.network_package_aliases()
    local result = {}
    for _, model in ipairs(M.MODELS) do
        if M.is_usable_model(model) then
            result[model.right_hand_unit] = M.NETWORK_PACKAGE_ALIAS_1P
            result[model.right_hand_unit .. "_3p"] = M.NETWORK_PACKAGE_ALIAS_3P
        end
    end
    return result
end

function M.install_network_package_aliases(inventory_lookup)
    if type(inventory_lookup) ~= "table" then return 0 end
    local installed = 0
    for custom_path, vanilla_path in pairs(M.network_package_aliases()) do
        local vanilla_index = rawget(inventory_lookup, vanilla_path)
        if type(vanilla_index) == "number" then
            inventory_lookup[custom_path] = vanilla_index
            installed = installed + 1
        end
    end
    return installed
end

local function as_set(values)
    local result = {}
    for _, value in ipairs(values or {}) do result[value] = true end
    return result
end

function M.conditional_careers(defaults)
    local authored = as_set(defaults)
    local result = {}
    for _, career in ipairs(M.ALL_CAREERS) do
        if not authored[career] then result[#result + 1] = career end
    end
    return result
end

function M.is_family_key(key)
    for _, variant in ipairs(M.VARIANTS) do
        if variant.key == key then return true end
    end
    return key == M.SOURCE_ITEM
end

return M
