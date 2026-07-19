-- #656: Reikland griffin heraldry for the Knights Encarmine Foot Knight body.
--
-- This is an authored texture variant, not a replacement mesh.  The item
-- clones the exact vanilla red Foot Knight skin and therefore keeps its
-- skeleton, cape simulation, camera fade, LODs, and material package.  Only
-- the per-instance outfit texture bindings are replaced by the shared
-- authored-outfit painter in _cos_grail_knight_set.lua.

local mod = get_mod("cosmetics_tweaker")
local M = {}

M.PROVIDER_ID = "issue656_reikland_griffin"
M.ITEM_KEY = "cos_fk_reikland_griffin_skin"
M.VARIANT_KEY = "cos_fk_reikland_griffin_skin_variant"
M.BASE_KEY = "skin_es_knight_red"
M.VANILLA_FALLBACK = "skin_es_knight_red"
M.FP_UNIT = "units/beings/player/empire_soldier_knight/first_person_base/chr_first_person_mesh"
M.TP_UNIT = "units/beings/player/empire_soldier_knight/third_person_base/chr_third_person_mesh"

M.TEXTURES = {
    skin_1p = {
        "textures/cosmetics_tweaker/reikland_griffin/fk_reikland_1p_diffuse",
        "textures/cosmetics_tweaker/reikland_griffin/fk_reikland_1p_combined",
        "textures/cosmetics_tweaker/reikland_griffin/fk_reikland_1p_normal",
    },
    skin_3p = {
        "textures/cosmetics_tweaker/reikland_griffin/fk_reikland_3p_diffuse",
        "textures/cosmetics_tweaker/reikland_griffin/fk_reikland_3p_combined",
        "textures/cosmetics_tweaker/reikland_griffin/fk_reikland_3p_normal",
    },
}

M.ITEM_LOCALIZATION = {
    cos_fk_reikland_griffin_skin_name = "Knights Encarmine — Reikland Griffin",
    cos_fk_reikland_griffin_skin_description = "The colours of the Knights Encarmine, bearing the griffin of Reikland upon the cape.",
}

-- The extracted Foot Knight red materials use b788717c for the packed map on
-- both body surfaces.  Grail Knight's body uses abb81538 in third person, so
-- the slot contract must travel with the variant rather than being guessed by
-- the shared painter.
local ARMOR_SLOTS = {
    "texture_map_64cc5eb8", -- diffuse
    "texture_map_b788717c", -- combined / packed
    "texture_map_861dbfdc", -- normal
}

M.registered = false

local function enabled()
    if not (mod and type(mod.get) == "function") then return true end
    local ok, value = pcall(mod.get, mod, "cos_fk_reikland_griffin_enabled")
    return not ok or value ~= false
end

local function clone_item()
    local base = ItemMasterList and rawget(ItemMasterList, M.BASE_KEY)
    if type(base) ~= "table" then return nil end
    local item = table.clone(base)
    item.key = M.ITEM_KEY
    item.name = M.ITEM_KEY
    item.display_name = "cos_fk_reikland_griffin_skin_name"
    item.description = "cos_fk_reikland_griffin_skin_description"
    item.localized_name = M.ITEM_LOCALIZATION.cos_fk_reikland_griffin_skin_name
    item.localized_description = M.ITEM_LOCALIZATION.cos_fk_reikland_griffin_skin_description
    item.can_wield = enabled() and { "es_knight" } or {}
    item.temporary_template = M.ITEM_KEY
    item.cos_authored = true
    item.cos_vanilla_fallback = M.VANILLA_FALLBACK
    item.mod_data = {
        backend_id = M.ITEM_KEY,
        ItemInstanceId = M.ITEM_KEY,
        key = M.ITEM_KEY,
        ItemId = M.ITEM_KEY,
        CustomData = { rarity = item.rarity or "promo" },
        rarity = item.rarity or "promo",
    }
    return item
end

function M.sync_toggle()
    local item = ItemMasterList and rawget(ItemMasterList, M.ITEM_KEY)
    if item then item.can_wield = enabled() and { "es_knight" } or {} end
end

function M.resolve_variant(key)
    if key ~= M.VARIANT_KEY then return nil end
    return {
        kind = "texture",
        swap_hand = "armor",
        new_units = { M.TP_UNIT },
        textures = M.TEXTURES.skin_3p,
        textures_fps = M.TEXTURES.skin_1p,
        fps_units = { M.FP_UNIT },
        armor_slots_3p = ARMOR_SLOTS,
        armor_slots_1p = ARMOR_SLOTS,
        armor_materials_3p = { "mtr_outfit", "mtr_outfit_ds" },
        armor_materials_1p = { "mtr_outfit" },
        variant_key = M.VARIANT_KEY,
        cos_authored = true,
        issue = 656,
    }
end

function M.resolve_skin_variant(skin_data)
    local cosmetics = rawget(_G, "Cosmetics")
    local custom = cosmetics and cosmetics[M.ITEM_KEY]
    if custom and skin_data and (skin_data == custom or skin_data.name == M.ITEM_KEY) then
        return M.VARIANT_KEY
    end
    return nil
end

function M.register_all(bridge)
    if M.registered then M.sync_toggle(); return true end
    local cosmetics = rawget(_G, "Cosmetics")
    local base_cosmetic = cosmetics and cosmetics[M.BASE_KEY]
    if not (cosmetics and type(base_cosmetic) == "table") then return false end
    if not (mod and type(mod.add_mod_items_to_masterlist) == "function"
        and type(mod.add_mod_items_to_local_backend) == "function") then
        return false
    end
    local item = clone_item()
    if not item then return false end

    cosmetics[M.ITEM_KEY] = table.clone(base_cosmetic)
    cosmetics[M.ITEM_KEY].name = M.ITEM_KEY
    mod:add_mod_items_to_masterlist({ item })
    mod:add_mod_items_to_local_backend({ item }, "cosmetics_tweaker")

    if bridge then
        bridge.custom_variants = bridge.custom_variants or {}
        bridge.backend_to_armoury[M.ITEM_KEY] = M.VARIANT_KEY
        bridge.backend_to_vanilla[M.ITEM_KEY] = M.VANILLA_FALLBACK
        bridge.armoury_to_backend[M.VARIANT_KEY] = M.ITEM_KEY
        bridge.custom_variants[M.VARIANT_KEY] = true
        bridge.registered = true
    end

    M.registered = true
    local engine_printf = rawget(_G, "printf")
    if engine_printf then
        pcall(engine_printf,
            "[cos:656] registered skin=%s donor=%s vanilla_geometry=true enabled=%s",
            M.ITEM_KEY, M.BASE_KEY, tostring(enabled()))
    end
    return true
end

return M
