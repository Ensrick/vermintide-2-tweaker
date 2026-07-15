-- #629: Cosmetics-authored Grail Knight Purpure/Azure set.
--
-- Geometry is deliberately 100% vanilla. The Pureheart helmet, Gallant of
-- Parravon body attachments, and Shield of Honour Renewed units retain their
-- native skeletons, animation controllers, fade enrollment, attachment nodes,
-- and preview behavior. Only per-instance texture bindings are changed.

local mod = get_mod("cosmetics_tweaker")
local M = {}

M.HAT_ITEM_KEY = "cos_gk_purpure_azure_hat"
M.HAT_VARIANT_KEY = "cos_gk_purpure_azure_hat_variant"
M.HAT_BASE_KEY = "questing_knight_hat_0001"
M.HAT_BASE_UNIT = "units/beings/player/empire_soldier_breton/headpiece/es_gk_hat_02"

M.SKIN_ITEM_KEY = "cos_gk_purpure_azure_skin"
M.SKIN_VARIANT_KEY = "cos_gk_purpure_azure_skin_variant"
M.SKIN_BASE_KEY = "skin_es_questingknight_white"
M.SKIN_VANILLA_FALLBACK = "skin_es_questingknight"
M.SKIN_FP_UNIT = "units/beings/player/empire_soldier_breton/first_person_base/chr_first_person_mesh"
M.SKIN_TP_UNIT = "units/beings/player/empire_soldier_breton/third_person_base/chr_third_person_mesh"

M.SHIELD_SKIN_KEY = "cos_gk_purpure_azure_shield"
M.SHIELD_VARIANT_KEY = "cos_gk_purpure_azure_shield_variant"
M.SHIELD_BASE_KEY = "es_sword_shield_breton_skin_03"
M.SHIELD_BASE_UNIT = "units/weapons/player/wpn_emp_gk_shield_05/wpn_emp_gk_shield_05"
M.SHIELD_BASE_UNIT_3P = M.SHIELD_BASE_UNIT .. "_3p"

M.ICONS = {
    hat = "icon_cos_gk_purpure_azure_hat",
    skin = "icon_cos_gk_purpure_azure_skin",
    shield = "icon_cos_gk_purpure_azure_shield",
}

M.TEXTURES = {
    hat = {
        "textures/cosmetics_tweaker/grail_knight_set/gk_hat_diffuse",
        "textures/cosmetics_tweaker/grail_knight_set/gk_hat_combined",
        "textures/cosmetics_tweaker/grail_knight_set/gk_hat_normal",
    },
    skin_1p = {
        "textures/cosmetics_tweaker/grail_knight_set/gk_outfit_1p_diffuse",
        "textures/cosmetics_tweaker/grail_knight_set/gk_outfit_1p_combined",
        "textures/cosmetics_tweaker/grail_knight_set/gk_outfit_1p_normal",
    },
    skin_3p = {
        "textures/cosmetics_tweaker/grail_knight_set/gk_outfit_3p_diffuse",
        "textures/cosmetics_tweaker/grail_knight_set/gk_outfit_3p_combined",
        "textures/cosmetics_tweaker/grail_knight_set/gk_outfit_3p_normal",
    },
    shield = {
        "textures/cosmetics_tweaker/grail_knight_set/gk_shield_diffuse",
        "textures/cosmetics_tweaker/grail_knight_set/gk_shield_combined",
        "textures/cosmetics_tweaker/grail_knight_set/gk_shield_normal",
    },
}

M.ITEM_LOCALIZATION = {
    cos_gk_purpure_azure_hat_name = "Pureheart Helm (Purpure and Azure)",
    cos_gk_purpure_azure_hat_description = "The Pureheart helm in purpure, azure, white, and blackened silver.",
    cos_gk_purpure_azure_skin_name = "Gallant of Parravon (Purpure and Azure)",
    cos_gk_purpure_azure_skin_description = "A Grail Knight panoply in purpure, azure, white, and blackened silver.",
    cos_gk_purpure_azure_shield_name = "Shield of Honour Renewed (Purpure and Azure)",
    cos_gk_purpure_azure_shield_description = "The Shield of Honour Renewed bearing matching purpure and azure heraldry.",
}

local DEFAULT_SLOTS = {
    "texture_map_c0ba2942", -- diffuse
    "texture_map_0205ba86", -- combined/MAB
    "texture_map_59cd86b9", -- normal
}
local ARMOR_3P_SLOTS = {
    "texture_map_64cc5eb8", -- diffuse
    "texture_map_abb81538", -- combined/MAB
    "texture_map_861dbfdc", -- normal
}
local ARMOR_1P_SLOTS = {
    "texture_map_64cc5eb8", -- diffuse
    "texture_map_b788717c", -- combined/MAB
    "texture_map_861dbfdc", -- normal
}
local ARMOR_MATERIAL_NAMES = {
    "mtr_outfit",
    "mtr_outfit_ds",
}

M.registered = false
M._diag_seen = {}

local function enabled()
    if not (mod and type(mod.get) == "function") then return true end
    local ok, value = pcall(mod.get, mod, "cos_gk_purpure_azure_enabled")
    return not ok or value ~= false
end

local function clone_item(base_key, item_key, display_key, description_key, icon)
    local base = ItemMasterList and rawget(ItemMasterList, base_key)
    if type(base) ~= "table" then return nil end
    local item = table.clone(base)
    item.key = item_key
    item.name = item_key
    item.display_name = display_key
    item.description = description_key
    item.localized_name = M.ITEM_LOCALIZATION[display_key]
    item.localized_description = M.ITEM_LOCALIZATION[description_key]
    item.inventory_icon = icon
    item.rarity = "exotic"
    item.can_wield = enabled() and { "es_questingknight" } or {}
    item.cos_authored = true
    item.cos_vanilla_fallback = base_key
    item.mod_data = {
        backend_id = item_key,
        ItemInstanceId = item_key,
        key = item_key,
        ItemId = item_key,
        CustomData = { rarity = "exotic" },
        rarity = "exotic",
    }
    return item
end

local function register_network_skin(key)
    local lookup = NetworkLookup and NetworkLookup.weapon_skins
    if not lookup or rawget(lookup, key) then return end
    lookup[#lookup + 1] = key
    lookup[key] = #lookup
end

local function register_cosmetics_template()
    local cosmetics = rawget(_G, "Cosmetics")
    if not cosmetics then return false end
    local base = cosmetics[M.SKIN_BASE_KEY] or cosmetics[M.SKIN_VANILLA_FALLBACK]
    if type(base) ~= "table" then return false end
    cosmetics[M.SKIN_ITEM_KEY] = table.clone(base)
    return true
end

function M.sync_toggle()
    for _, key in ipairs({ M.HAT_ITEM_KEY, M.SKIN_ITEM_KEY, M.SHIELD_SKIN_KEY }) do
        local item = ItemMasterList and rawget(ItemMasterList, key)
        if item then item.can_wield = enabled() and { "es_questingknight" } or {} end
    end
end

function M.resolve_variant(key)
    if key == M.HAT_VARIANT_KEY then
        return { kind = "texture", swap_hand = "hat", new_units = { M.HAT_BASE_UNIT }, textures = M.TEXTURES.hat, cos_authored = true }
    elseif key == M.SKIN_VARIANT_KEY then
        return { kind = "texture", swap_hand = "armor", new_units = { M.SKIN_TP_UNIT }, textures = M.TEXTURES.skin_3p,
            textures_fps = M.TEXTURES.skin_1p, fps_units = { M.SKIN_FP_UNIT }, cos_authored = true }
    elseif key == M.SHIELD_VARIANT_KEY then
        -- HeroPreviewer/GearUtils receive the base 1P path and spawn its explicit
        -- `_3p` sibling for inventory heroes, local bodies, and remote husks.
        -- Declaring the 1P path twice makes the shared mesh-safety guard reject
        -- the real `_3p` unit before paint, even though the texture preview works.
        return { kind = "texture", swap_hand = "left_hand_unit",
            new_units = { M.SHIELD_BASE_UNIT, M.SHIELD_BASE_UNIT_3P },
            textures = M.TEXTURES.shield, cos_authored = true }
    end
    return nil
end

-- Reusable row-2 component record.  The caller inserts a fresh copy into each
-- compatible Kruber shield family so primary and offhand choices stay
-- independent and no weapon family owns the component exclusively.
function M.offhand_option()
    return {
        name = M.ITEM_LOCALIZATION.cos_gk_purpure_azure_shield_name,
        la_armoury_key = M.SHIELD_VARIANT_KEY,
        vanilla_skin = M.SHIELD_BASE_KEY,
        intended_unit = M.SHIELD_BASE_UNIT,
        authored_family = "kruber_grail_knight_shield",
        variant_kind = "texture",
        inventory_icon = M.ICONS.shield,
        rarity = "promo",
        cos_authored = true,
    }
end

local function resources_ready(textures)
    if not (Application and type(Application.can_get) == "function") then return false end
    for _, path in ipairs(textures or {}) do
        local ok, value = pcall(Application.can_get, "texture", path)
        if not (ok and value == true) then return false end
    end
    return true
end

-- The Grail Knight 3P attachment contains outfit, face, eyes, teeth, and hair
-- meshes. Their material instances can expose the same hashed texture parameter
-- names, so Unit.set_texture_for_materials paints Markus's face as collateral.
-- Target only the two outfit materials proven by the extracted Gallant 1P/3P
-- donor scenes. Census first and write second: any scene/material drift fails
-- closed without partially repainting the character.
local function apply_armor_materials(unit, slots, textures)
    if not (Unit and Unit.num_meshes and Unit.mesh
        and Mesh and Mesh.has_material and Mesh.material
        and Material and Material.set_texture) then
        return false
    end
    local ok_count, mesh_count = pcall(Unit.num_meshes, unit)
    if not ok_count or type(mesh_count) ~= "number" then return false end
    local targets, seen = {}, {}
    for mesh_index = 0, mesh_count - 1 do
        local ok_mesh, mesh = pcall(Unit.mesh, unit, mesh_index)
        if not ok_mesh or not mesh then return false end
        for _, material_name in ipairs(ARMOR_MATERIAL_NAMES) do
            local ok_has, has = pcall(Mesh.has_material, mesh, material_name)
            if not ok_has then return false end
            if has then
                local ok_material, material = pcall(Mesh.material, mesh, material_name)
                if not ok_material or not material then return false end
                targets[#targets + 1] = material
                seen[material_name] = true
            end
        end
    end
    for _, material_name in ipairs(ARMOR_MATERIAL_NAMES) do
        if not seen[material_name] then return false end
    end
    for _, material in ipairs(targets) do
        for i = 1, 3 do
            local ok = pcall(Material.set_texture, material, slots[i], textures[i])
            if not ok then return false end
        end
    end
    return true
end

function M.apply_variant_to_unit(key_or_variant, unit, surface)
    local variant = type(key_or_variant) == "table" and key_or_variant or M.resolve_variant(key_or_variant)
    if not (variant and unit and Unit and Unit.alive and Unit.alive(unit)) then return false end
    local textures = variant.textures
    local slots = DEFAULT_SLOTS
    if variant.swap_hand == "armor" then
        local is_1p = surface == "first_person"
        if not is_1p and Unit.has_data and Unit.has_data(unit, "unit_name") then
            local ok, name = pcall(Unit.get_data, unit, "unit_name")
            is_1p = ok and name == M.SKIN_FP_UNIT
        end
        textures = is_1p and variant.textures_fps or variant.textures
        slots = is_1p and ARMOR_1P_SLOTS or ARMOR_3P_SLOTS
    end
    if not resources_ready(textures) then return false end
    if variant.swap_hand == "armor" then
        if not apply_armor_materials(unit, slots, textures) then return false end
    else
        for i = 1, 3 do
            local ok = pcall(Unit.set_texture_for_materials, unit, slots[i], textures[i])
            if not ok then return false end
        end
    end
    local token = tostring(variant.swap_hand) .. "|" .. tostring(surface or "unknown")
    if not M._diag_seen[token] then
        M._diag_seen[token] = true
        local engine_printf = rawget(_G, "printf")
        if engine_printf then pcall(engine_printf, "[cos:629] applied kind=%s surface=%s vanilla_geometry=true", tostring(variant.swap_hand), tostring(surface or "unknown")) end
    end
    return true
end

function M.apply_armor_to_owner(owner_unit, surface)
    if not (owner_unit and ScriptUnit and ScriptUnit.has_extension) then return false end
    local ext = ScriptUnit.has_extension(owner_unit, "cosmetic_system")
    if not ext then return false end
    local applied = false
    local tp = ext.get_third_person_mesh_unit and ext:get_third_person_mesh_unit()
    if tp then applied = M.apply_variant_to_unit(M.SKIN_VARIANT_KEY, tp, surface or "third_person") or applied end
    local fp_ext = ScriptUnit.has_extension(owner_unit, "first_person_system")
    local fp = fp_ext and fp_ext.get_first_person_mesh_unit and fp_ext:get_first_person_mesh_unit()
    if fp then applied = M.apply_variant_to_unit(M.SKIN_VARIANT_KEY, fp, "first_person") or applied end
    return applied
end

-- Inventory character previews do not have PlayerUnitCosmeticExtension, so
-- their body mesh must be painted from HeroPreviewer's own canonical skin data.
-- Cache the mesh identity, not a one-shot boolean: reopening the view or changing
-- careers creates a new mesh and therefore replays exactly once on that surface.
function M.apply_armor_to_hero_preview(previewer)
    if not previewer then return false end
    local cosmetics = rawget(_G, "Cosmetics")
    local custom = cosmetics and cosmetics[M.SKIN_ITEM_KEY]
    local loading = previewer._hero_loading_package_data
    local skin_data = previewer.character_unit_skin_data or (loading and loading.skin_data)
    if not (custom and skin_data and (skin_data == custom or skin_data.name == M.SKIN_ITEM_KEY)) then
        return false
    end
    local mesh = previewer.mesh_unit
    if not (mesh and Unit and Unit.alive and Unit.alive(mesh)) then return false end
    if previewer._cos_gk_armor_applied_mesh == mesh then return true end
    local applied = M.apply_variant_to_unit(M.SKIN_VARIANT_KEY, mesh, "hero_preview")
    if applied then previewer._cos_gk_armor_applied_mesh = mesh end
    return applied
end

function M.register_all(bridge)
    if M.registered then M.sync_toggle(); return true end
    if not (ItemMasterList and WeaponSkins and NetworkLookup and register_cosmetics_template()) then return false end
    if not (mod and type(mod.add_mod_items_to_masterlist) == "function" and type(mod.add_mod_items_to_local_backend) == "function") then return false end

    local hat = clone_item(M.HAT_BASE_KEY, M.HAT_ITEM_KEY, "cos_gk_purpure_azure_hat_name", "cos_gk_purpure_azure_hat_description", M.ICONS.hat)
    local skin = clone_item(M.SKIN_BASE_KEY, M.SKIN_ITEM_KEY, "cos_gk_purpure_azure_skin_name", "cos_gk_purpure_azure_skin_description", M.ICONS.skin)
    local shield = clone_item(M.SHIELD_BASE_KEY, M.SHIELD_SKIN_KEY, "cos_gk_purpure_azure_shield_name", "cos_gk_purpure_azure_shield_description", M.ICONS.shield)
    if not (hat and skin and shield) then return false end
    skin.temporary_template = M.SKIN_ITEM_KEY

    mod:add_mod_items_to_masterlist({ hat, skin, shield })
    mod:add_mod_items_to_local_backend({ hat, skin, shield }, "cosmetics_tweaker")

    WeaponSkins.skins[M.SHIELD_SKIN_KEY] = table.clone(WeaponSkins.skins[M.SHIELD_BASE_KEY] or shield)
    WeaponSkins.skins[M.SHIELD_SKIN_KEY].display_name = "cos_gk_purpure_azure_shield_name"
    WeaponSkins.skins[M.SHIELD_SKIN_KEY].description = "cos_gk_purpure_azure_shield_description"
    WeaponSkins.skins[M.SHIELD_SKIN_KEY].inventory_icon = M.ICONS.shield
    register_network_skin(M.SHIELD_SKIN_KEY)
    -- Do not append this to a whole-weapon skin combination.  The shield is
    -- offered by the independent offhand component row so the primary weapon
    -- illusion remains untouched and its icon can compose with the shield.
    if mod._cos and mod._cos.custom_skin_keys then mod._cos.custom_skin_keys[M.SHIELD_SKIN_KEY] = true end

    local mappings = {
        { M.HAT_ITEM_KEY, M.HAT_VARIANT_KEY, M.HAT_BASE_KEY },
        { M.SKIN_ITEM_KEY, M.SKIN_VARIANT_KEY, M.SKIN_VANILLA_FALLBACK },
        { M.SHIELD_SKIN_KEY, M.SHIELD_VARIANT_KEY, M.SHIELD_BASE_KEY },
    }
    if bridge then
        bridge.custom_variants = bridge.custom_variants or {}
        for _, row in ipairs(mappings) do
            bridge.backend_to_armoury[row[1]] = row[2]
            bridge.backend_to_vanilla[row[1]] = row[3]
            bridge.armoury_to_backend[row[2]] = row[1]
            bridge.custom_variants[row[2]] = true
        end
        bridge.registered = true
    end
    M.registered = true
    local engine_printf = rawget(_G, "printf")
    if engine_printf then pcall(engine_printf, "[cos:629] registered set hat=%s skin=%s shield=%s enabled=%s", M.HAT_ITEM_KEY, M.SKIN_ITEM_KEY, M.SHIELD_SKIN_KEY, tostring(enabled())) end
    return true
end

return M
