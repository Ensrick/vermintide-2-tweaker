-- #629: Cosmetics-authored Grail Knight Purpure/Azure set.
--
-- Geometry is deliberately 100% vanilla. The Pureheart helmet, Gallant of
-- Parravon body attachments, and Shield of Honour Renewed units retain their
-- native skeletons, animation controllers, fade enrollment, attachment nodes,
-- and preview behavior. Only per-instance texture bindings are changed.

local mod = get_mod("cosmetics_tweaker")
local RESIDENCY = mod and type(mod.dofile) == "function"
    and mod:dofile("scripts/mods/cosmetics_tweaker/_lib_resource_residency")
    or nil
local M = {}

local MAX_OUTFIT_PROVIDERS = 16
local MAX_APPLY_DIAGNOSTICS = 32
local MAX_RESIDENCY_DIAGNOSTICS = 24
local MAX_DIAGNOSTIC_VALUE_BYTES = 160

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

-- #658: the authored set remains native to Grail Knight, while these three
-- default-off settings may independently extend its inventory availability to
-- Kruber's base careers. Keep this an ordered array so ItemMasterList
-- `can_wield` output is deterministic and does not acquire duplicates.
M.SHARED_CAREERS = {
    { career = "es_mercenary", setting_id = "cos_gk_purpure_azure_share_mercenary" },
    { career = "es_huntsman", setting_id = "cos_gk_purpure_azure_share_huntsman" },
    { career = "es_knight", setting_id = "cos_gk_purpure_azure_share_foot_knight" },
}

-- Vanilla career defaults used only on the network fallback path. These are
-- the exact base_skin/default hat pairs from career_settings.lua for Huntsman
-- (:306/:342), Foot Knight (:387/:423), and Mercenary (:468/:504); Grail
-- Knight keeps the lake-authored donor fallback already used by the set.
M.CAREER_WIRE_FALLBACKS = {
    es_questingknight = { hat = M.HAT_BASE_KEY, skin = M.SKIN_VANILLA_FALLBACK },
    es_mercenary = { hat = "mercenary_hat_0000", skin = "skin_es_mercenary" },
    es_huntsman = { hat = "huntsman_hat_0000", skin = "skin_es_huntsman" },
    es_knight = { hat = "knight_hat_0000", skin = "skin_es_knight" },
}

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
    cos_gk_purpure_azure_hat_name = "Couronne de la Lune",
    cos_gk_purpure_azure_hat_description = "Its silvered crest recalls moonrise over Couronne, where Grail Knights keep vigil beneath the Lady's gaze and remember the vows that raised them above mortal knighthood.",
    cos_gk_purpure_azure_skin_name = "Midnight Purpure and Azure",
    cos_gk_purpure_azure_skin_description = "Once worn by a Bretonnian knight whose ardour burned brighter than good sense. Mortally wounded, he bequeathed his colours to Kruber, declaring the Grail Knight of Ubersreik worthy to bear them.",
    cos_gk_purpure_azure_shield_name = "The Blood-Bloomed Bouclier",
    cos_gk_purpure_azure_shield_description = "Kruber claims the blazon's four roses commemorate four maidens rescued, its gouttes de sang the blood spilled in their defence. The Ubersreik Five suspect the tale grows taller with every telling, but know better than to question his honesty within earshot.",
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
M._diag_count = 0
M._residency_diag_seen = {}
M._residency_diag_count = 0
M._outfit_providers = {}
M._outfit_provider_ids = {}
M.PREVIEW_REPLAY_CONTRACT = {
    apply_after_visibility = true,
    invalidate_while_hidden = true,
    cache_identity = "mesh_unit+variant_key",
    score_uses_same_visibility_boundary = true,
}

-- Authored body variants share the same replay/surface machinery.  Providers
-- register identities and texture contracts here; callers resolve one
-- canonical variant instead of adding inventory, husk, and score hooks per
-- outfit.  The module name remains for compatibility with existing #629 code.
function M.add_outfit_provider(provider)
    if type(provider) ~= "table" then return false end
    local provider_id = rawget(provider, "PROVIDER_ID")
    if type(provider_id) ~= "string" or provider_id == ""
        or #provider_id > 96 or M._outfit_provider_ids[provider_id] ~= nil
        or #M._outfit_providers >= MAX_OUTFIT_PROVIDERS then
        return false
    end
    for _, method in ipairs({ "resolve_variant", "resolve_skin_variant", "register_all", "sync_toggle" }) do
        if type(provider[method]) ~= "function" then return false end
    end
    local localization = provider.ITEM_LOCALIZATION
    if type(localization) ~= "table" then return false end
    for key, value in pairs(localization) do
        if type(key) ~= "string" or key == "" or type(value) ~= "string"
            or (M.ITEM_LOCALIZATION[key] ~= nil and M.ITEM_LOCALIZATION[key] ~= value) then
            return false
        end
    end
    M._outfit_providers[#M._outfit_providers + 1] = provider
    M._outfit_provider_ids[provider_id] = provider
    for key, value in pairs(localization) do M.ITEM_LOCALIZATION[key] = value end
    return true
end

function M.has_outfit_provider(provider_id)
    return type(provider_id) == "string" and M._outfit_provider_ids[provider_id] ~= nil
end

local function enabled()
    if not (mod and type(mod.get) == "function") then return true end
    local ok, value = pcall(mod.get, mod, "cos_gk_purpure_azure_enabled")
    return not ok or value ~= false
end

local function share_enabled(setting_id)
    if not (mod and type(mod.get) == "function") then return false end
    local ok, value = pcall(mod.get, mod, setting_id)
    return ok and value == true
end

function M.can_wield_careers()
    if not enabled() then return {} end
    local careers = { "es_questingknight" }
    for _, row in ipairs(M.SHARED_CAREERS) do
        if share_enabled(row.setting_id) then
            careers[#careers + 1] = row.career
        end
    end
    return careers
end

function M.is_availability_setting(setting_id)
    if setting_id == "cos_gk_purpure_azure_enabled" then return true end
    for _, row in ipairs(M.SHARED_CAREERS) do
        if setting_id == row.setting_id then return true end
    end
    return false
end

function M.is_item_key(item_key)
    return item_key == M.HAT_ITEM_KEY
        or item_key == M.SKIN_ITEM_KEY
        or item_key == M.SHIELD_SKIN_KEY
end

function M.vanilla_fallback_for_career(item_key, career_name)
    if item_key == M.SHIELD_SKIN_KEY then return M.SHIELD_BASE_KEY end
    if item_key ~= M.HAT_ITEM_KEY and item_key ~= M.SKIN_ITEM_KEY then return nil end
    -- A missing/unknown career is not permission to publish Grail Knight's
    -- fallback onto another Kruber body. Every outgoing owner resolves an
    -- exact player/unit career; fail closed if that identity is unavailable.
    local fallback = M.CAREER_WIRE_FALLBACKS[career_name]
    if not fallback then return nil end
    return item_key == M.HAT_ITEM_KEY and fallback.hat or fallback.skin
end

function M.wire_fallback(bridge, original_name, career_name)
    if type(bridge) ~= "table" or bridge.registered ~= true or not original_name then return nil end
    local armoury = bridge.backend_to_armoury
    if type(armoury) ~= "table" or not armoury[original_name] then return nil end
    local vanilla = type(bridge.backend_to_vanilla) == "table"
        and bridge.backend_to_vanilla[original_name] or nil
    if M.is_item_key(original_name) then
        return M.vanilla_fallback_for_career(original_name, career_name) or vanilla
    end
    return vanilla
end

function M.career_for_player(player, persistence)
    if persistence and type(persistence._career_name_for_player) == "function" then
        local ok, career = pcall(persistence._career_name_for_player, player)
        if ok and career then return career end
    end
    if player and type(player.career_name) == "function" then
        local ok, career = pcall(player.career_name, player)
        if ok then return career end
    end
    return nil
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
    item.can_wield = M.can_wield_careers()
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
        if item then item.can_wield = M.can_wield_careers() end
    end
    for _, provider in ipairs(M._outfit_providers) do
        pcall(provider.sync_toggle)
    end
end

function M.resolve_variant(key)
    if key == M.HAT_VARIANT_KEY then
        return { kind = "texture", swap_hand = "hat", new_units = { M.HAT_BASE_UNIT }, textures = M.TEXTURES.hat,
            variant_key = M.HAT_VARIANT_KEY, issue = 629, cos_authored = true }
    elseif key == M.SKIN_VARIANT_KEY then
        return { kind = "texture", swap_hand = "armor", new_units = { M.SKIN_TP_UNIT }, textures = M.TEXTURES.skin_3p,
            textures_fps = M.TEXTURES.skin_1p, fps_units = { M.SKIN_FP_UNIT },
            variant_key = M.SKIN_VARIANT_KEY, issue = 629, cos_authored = true }
    elseif key == M.SHIELD_VARIANT_KEY then
        -- HeroPreviewer/GearUtils receive the base 1P path and spawn its explicit
        -- `_3p` sibling for inventory heroes, local bodies, and remote husks.
        -- Declaring the 1P path twice makes the shared mesh-safety guard reject
        -- the real `_3p` unit before paint, even though the texture preview works.
        return { kind = "texture", swap_hand = "left_hand_unit",
            new_units = { M.SHIELD_BASE_UNIT, M.SHIELD_BASE_UNIT_3P },
            textures = M.TEXTURES.shield, variant_key = M.SHIELD_VARIANT_KEY,
            issue = 629, cos_authored = true }
    end
    for _, provider in ipairs(M._outfit_providers) do
        local ok, variant = pcall(provider.resolve_variant, key)
        if ok and type(variant) == "table" then return variant end
    end
    return nil
end

function M.resolve_skin_variant(skin_data)
    local cosmetics = rawget(_G, "Cosmetics")
    local custom = cosmetics and cosmetics[M.SKIN_ITEM_KEY]
    if custom and skin_data and (skin_data == custom or skin_data.name == M.SKIN_ITEM_KEY) then
        return M.SKIN_VARIANT_KEY
    end
    for _, provider in ipairs(M._outfit_providers) do
        local ok, key = pcall(provider.resolve_skin_variant, skin_data)
        if ok and type(key) == "string" and key ~= "" then return key end
    end
    return nil
end

-- Reusable row-2 component record.  The caller inserts a fresh copy into each
-- compatible Kruber shield family so primary and offhand choices stay
-- independent and no weapon family owns the component exclusively.
function M.offhand_option()
    return {
        name = M.ITEM_LOCALIZATION.cos_gk_purpure_azure_shield_name,
        localization_key = "cos_gk_purpure_azure_shield_name",
        description = M.ITEM_LOCALIZATION.cos_gk_purpure_azure_shield_description,
        description_key = "cos_gk_purpure_azure_shield_description",
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

local function diagnostic_value(value)
    local result = tostring(value == nil and "nil" or value)
    if #result > MAX_DIAGNOSTIC_VALUE_BYTES then
        return result:sub(1, MAX_DIAGNOSTIC_VALUE_BYTES) .. "..."
    end
    return result
end

local function residency_diag(reason, resource_type, path, slot, context)
    local token = table.concat({
        diagnostic_value(reason or "unknown"),
        diagnostic_value(resource_type or "resource"),
        diagnostic_value(path),
        diagnostic_value(slot),
        diagnostic_value(context or "unknown"),
    }, "|")
    if M._residency_diag_seen[token]
        or M._residency_diag_count >= MAX_RESIDENCY_DIAGNOSTICS then return end
    M._residency_diag_seen[token] = true
    M._residency_diag_count = M._residency_diag_count + 1
    local engine_printf = rawget(_G, "printf")
    if engine_printf then
        pcall(engine_printf, "[cos:629] residency SKIP reason=%s type=%s slot=%s path=%s context=%s evidence=%d/%d",
            diagnostic_value(reason or "unknown"),
            diagnostic_value(resource_type or "resource"),
            diagnostic_value(slot), diagnostic_value(path),
            diagnostic_value(context or "unknown"),
            M._residency_diag_count, MAX_RESIDENCY_DIAGNOSTICS)
    end
end

local function textures_ready(slots, textures, context)
    if not (RESIDENCY and type(RESIDENCY.texture_set_resident) == "function") then
        residency_diag("missing_residency_helper", "texture", nil, nil, context)
        return false
    end
    if type(slots) ~= "table" or type(textures) ~= "table"
        or slots[4] ~= nil or textures[4] ~= nil then
        residency_diag("malformed_texture_set", "texture", nil, nil, context)
        return false
    end
    local bindings = {}
    for i = 1, 3 do
        bindings[i] = { slot = slots[i], texture = textures[i] }
    end
    return RESIDENCY.texture_set_resident(
        bindings, Application, residency_diag, context) == true
end

-- The Grail Knight 3P attachment contains outfit, face, eyes, teeth, and hair
-- meshes. Their material instances can expose the same hashed texture parameter
-- names, so Unit.set_texture_for_materials paints Markus's face as collateral.
-- Target only the two outfit materials proven by the extracted Gallant 1P/3P
-- donor scenes. Census first and write second: any scene/material drift fails
-- closed without partially repainting the character.
local function apply_armor_materials(unit, slots, textures, material_names)
    if not (Unit and Unit.num_meshes and Unit.mesh
        and Mesh and Mesh.has_material and Mesh.material
        and Material and Material.set_texture) then
        return false
    end
    local ok_count, mesh_count = pcall(Unit.num_meshes, unit)
    if not ok_count or type(mesh_count) ~= "number" then return false end
    material_names = material_names or ARMOR_MATERIAL_NAMES
    if type(material_names) ~= "table" or #material_names < 1 or #material_names > 4 then return false end
    local targets, seen = {}, {}
    for mesh_index = 0, mesh_count - 1 do
        local ok_mesh, mesh = pcall(Unit.mesh, unit, mesh_index)
        if not ok_mesh or not mesh then return false end
        for _, material_name in ipairs(material_names) do
            local ok_has, has = pcall(Mesh.has_material, mesh, material_name)
            if not ok_has then return false end
            if has then
                local ok_material, material = pcall(Mesh.material, mesh, material_name)
                if not ok_material or not material then return false end
                local ok_identity, identity = pcall(tostring, material)
                if not ok_identity or not identity
                        or identity:find("#ID[00000000]", 1, true) then return false end
                targets[#targets + 1] = material
                seen[material_name] = true
            end
        end
    end
    for _, material_name in ipairs(material_names) do
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
    if not (variant and unit and Unit and type(Unit.alive) == "function") then return false end
    local alive_ok, alive = pcall(Unit.alive, unit)
    if not alive_ok or alive ~= true then return false end
    local textures = variant.textures
    local slots = DEFAULT_SLOTS
    local material_names = ARMOR_MATERIAL_NAMES
    if variant.swap_hand == "armor" then
        local is_1p = surface == "first_person"
        if not is_1p and Unit.has_data and Unit.has_data(unit, "unit_name") then
            local ok, name = pcall(Unit.get_data, unit, "unit_name")
            is_1p = ok and name == M.SKIN_FP_UNIT
        end
        textures = is_1p and variant.textures_fps or variant.textures
        slots = is_1p and (variant.armor_slots_1p or ARMOR_1P_SLOTS)
            or (variant.armor_slots_3p or ARMOR_3P_SLOTS)
        material_names = is_1p and (variant.armor_materials_1p or ARMOR_MATERIAL_NAMES)
            or (variant.armor_materials_3p or ARMOR_MATERIAL_NAMES)
    end
    local issue = tonumber(variant.issue) or 629
    local variant_key = diagnostic_value(variant.variant_key or ("issue" .. tostring(issue)))
    local context = "authored_outfit:" .. variant_key .. ":" .. diagnostic_value(surface or "unknown")
    if not textures_ready(slots, textures, context) then return false end
    if variant.swap_hand == "armor" then
        if not apply_armor_materials(unit, slots, textures, material_names) then return false end
    else
        if not (RESIDENCY and type(RESIDENCY.unit_materials_resident) == "function") then
            residency_diag("missing_residency_helper", "unit_material", nil, nil, context)
            return false
        end
        local material_ready = RESIDENCY.unit_materials_resident(
            unit, Unit, Mesh, residency_diag, context)
        if material_ready ~= true then return false end
        for i = 1, 3 do
            local ok = pcall(Unit.set_texture_for_materials, unit, slots[i], textures[i])
            if not ok then return false end
        end
    end
    local token = table.concat({ tostring(issue), variant_key,
        diagnostic_value(variant.swap_hand), diagnostic_value(surface or "unknown") }, "|")
    if not M._diag_seen[token] and M._diag_count < MAX_APPLY_DIAGNOSTICS then
        M._diag_seen[token] = true
        M._diag_count = M._diag_count + 1
        local engine_printf = rawget(_G, "printf")
        if engine_printf then
            pcall(engine_printf, "[cos:%s] applied variant=%s kind=%s surface=%s vanilla_geometry=true evidence=%d/%d",
                tostring(issue), variant_key, diagnostic_value(variant.swap_hand),
                diagnostic_value(surface or "unknown"), M._diag_count, MAX_APPLY_DIAGNOSTICS)
        end
    end
    return true
end

function M.apply_armor_to_owner(owner_unit, surface, armoury_key)
    if not (owner_unit and ScriptUnit and ScriptUnit.has_extension) then return false end
    local ext = ScriptUnit.has_extension(owner_unit, "cosmetic_system")
    if not ext then return false end
    local variant_key = armoury_key or M.SKIN_VARIANT_KEY
    local variant = M.resolve_variant(variant_key)
    if not variant or variant.swap_hand ~= "armor" then return false end
    local applied = false
    local tp = ext.get_third_person_mesh_unit and ext:get_third_person_mesh_unit()
    if tp then applied = M.apply_variant_to_unit(variant, tp, surface or "third_person") or applied end
    local fp_ext = ScriptUnit.has_extension(owner_unit, "first_person_system")
    local fp = fp_ext and fp_ext.get_first_person_mesh_unit and fp_ext:get_first_person_mesh_unit()
    if fp then applied = M.apply_variant_to_unit(variant, fp, "first_person") or applied end
    return applied
end

-- Inventory character previews do not have PlayerUnitCosmeticExtension, so
-- their body mesh must be painted from HeroPreviewer's own canonical skin data.
-- Vanilla spawns the mesh hidden, then `_set_character_visibility(true)` applies
-- `skin_data.material_changes` on the following update. Painting and caching on
-- the spawn frame therefore loses our textures to that later vanilla write.
-- Wait until the mesh is visible, and invalidate the mesh cache while hidden so
-- any later hide/show cycle replays after vanilla restores its donor materials.
local function apply_armor_to_visible_preview(previewer, variant_key, mesh_cache_field,
        variant_cache_field, surface)
    if not previewer or type(variant_key) ~= "string" then return false end
    local mesh = previewer.mesh_unit
    if not (mesh and Unit and Unit.alive and Unit.alive(mesh)) then
        previewer[mesh_cache_field] = nil
        previewer[variant_cache_field] = nil
        return false
    end
    if previewer.character_unit_hidden_after_spawn or previewer.character_unit_visible ~= true then
        previewer[mesh_cache_field] = nil
        previewer[variant_cache_field] = nil
        return false
    end
    if previewer[mesh_cache_field] == mesh
        and previewer[variant_cache_field] == variant_key then return true end
    local applied = M.apply_variant_to_unit(variant_key, mesh, surface)
    if applied then
        previewer[mesh_cache_field] = mesh
        previewer[variant_cache_field] = variant_key
    end
    return applied
end

function M.apply_armor_to_hero_preview(previewer)
    if not previewer then return false end
    local loading = previewer._hero_loading_package_data
    local skin_data = previewer.character_unit_skin_data or (loading and loading.skin_data)
    local variant_key = M.resolve_skin_variant(skin_data)
    if not variant_key then return false end
    return apply_armor_to_visible_preview(previewer, variant_key,
        "_cos_gk_armor_applied_mesh", "_cos_authored_armor_variant", "hero_preview")
end

-- TeamPreviewer's callback receives a spawned but still-hidden HeroPreviewer.
-- Retain the exact authored provider key there, then share the inventory
-- preview's visible-mesh/variant cache boundary after post_update (#730).
function M.apply_armor_to_score_preview(previewer, variant_key)
    local variant = M.resolve_variant(variant_key)
    if not (variant and variant.swap_hand == "armor") then return false end
    return apply_armor_to_visible_preview(previewer, variant_key,
        "_cos_gk_score_armor_applied_mesh", "_cos_score_applied_armor_variant",
        "score_preview")
end

function M.register_all(bridge)
    if M.registered then
        for _, provider in ipairs(M._outfit_providers) do
            pcall(provider.register_all, bridge)
        end
        M.sync_toggle()
        return true
    end
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
    for _, provider in ipairs(M._outfit_providers) do
        pcall(provider.register_all, bridge)
    end
    local engine_printf = rawget(_G, "printf")
    if engine_printf then pcall(engine_printf, "[cos:629] registered set hat=%s skin=%s shield=%s enabled=%s", M.HAT_ITEM_KEY, M.SKIN_ITEM_KEY, M.SHIELD_SKIN_KEY, tostring(enabled())) end
    return true
end

return M
