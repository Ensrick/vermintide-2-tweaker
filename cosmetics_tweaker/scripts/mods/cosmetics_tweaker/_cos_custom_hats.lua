-- Cosmetics-authored hats which preserve a vanilla donor unit exactly and
-- change only per-instance texture bindings. Registration is unconditional;
-- the setting controls availability and painting, never NetworkLookup shape.

local mod = get_mod("cosmetics_tweaker")
local RESIDENCY = mod and type(mod.dofile) == "function"
    and mod:dofile("scripts/mods/cosmetics_tweaker/_lib_resource_residency")
    or nil
local M = {}

M.ITEM_KEY = "cos_encarmine_hat"
M.VARIANT_KEY = "cos_custom_encarmine_hat"
M.BASE_KEY = "knight_hat_0006"
M.BASE_UNIT = "units/beings/player/empire_soldier_knight/headpiece/es_k_hat_07"
M.CUSTOM_UNIT = M.BASE_UNIT

-- #612: do not re-export Laurel. The donor's compiled unit is the behavioral
-- contract: 8 meshes, three LOD steps, its authored normals/tangents, two
-- shadow proxies, 13-bone plume rig, animation controller, and native fade
-- registration. Replacing the unit dropped those contracts and caused the
-- faceted armor, alpha-card haze, missing jiggle, and camera-fade regression.
M.RENDER_MODE = "vanilla_laurel_material_instance_override"
M.DONOR_MATERIALS = {
    armor = {
        slot = "1903313B",
        resource = "units/beings/player/empire_soldier_knight/headpiece/es_k_hat_base",
    },
    plume = {
        slot = "BD15BFF9",
        resource = "units/beings/player/empire_soldier_knight/headpiece/es_k_hat_feather",
    },
    shadow = {
        slot = "5ED8F236",
        resource = "shaders/characters/character_shadow",
    },
}
-- Unit.mesh order is NOT geometry-array order. Each runtime mesh stores a
-- one-based geometry_index; the donor's mesh list references geometries in
-- reverse. Resolve the role through geometry_index -> geometry material slot,
-- never by visually guessing a contiguous numeric range.
M.DONOR_MESH_BINDINGS = {
    [0] = { geometry_index = 8, role = "shadow", material_slot = "5ED8F236" },
    [1] = { geometry_index = 7, role = "armor",  material_slot = "1903313B" },
    [2] = { geometry_index = 6, role = "armor",  material_slot = "1903313B" },
    [3] = { geometry_index = 5, role = "armor",  material_slot = "1903313B" },
    [4] = { geometry_index = 4, role = "plume",  material_slot = "BD15BFF9" },
    [5] = { geometry_index = 3, role = "plume",  material_slot = "BD15BFF9" },
    [6] = { geometry_index = 2, role = "plume",  material_slot = "BD15BFF9" },
    [7] = { geometry_index = 1, role = "shadow", material_slot = "5ED8F236" },
}
local function mesh_indices_for(role)
    local indices = {}
    for mesh_index = 0, 7 do
        local binding = M.DONOR_MESH_BINDINGS[mesh_index]
        if binding and binding.role == role then indices[#indices + 1] = mesh_index end
    end
    return indices
end
M.LAUREL_SCENE_CONTRACT = {
    mesh_count = 8,
    armor_mesh_indices = mesh_indices_for("armor"),
    plume_mesh_indices = mesh_indices_for("plume"),
    shadow_mesh_indices = mesh_indices_for("shadow"),
    lod_steps = 3,
    rig_bones = 13,
    dynamic_plume_bones = 6,
}

-- These are the exact variable names exposed by both native Laurel materials.
-- Mesh indices distinguish armor from plume because both materials deliberately
-- use the same texture-variable names. Material.set_texture receives the
-- material instance returned by Mesh.material; it does not replace the native
-- shader graph or mutate ItemMasterList's shared donor resource.
M.TEXTURE_SLOTS = {
    diffuse = "texture_map_c0ba2942",
    normal = "texture_map_59cd86b9",
    combined = "texture_map_b788717c",
}
M.ARMOR_TEXTURES = {
    diffuse = "textures/cosmetics_tweaker/encarmine_hat/encarmine_armored_diffuse",
    normal = "textures/cosmetics_tweaker/encarmine_hat/encarmine_armored_normal",
    combined = "textures/cosmetics_tweaker/encarmine_hat/encarmine_armored_combined",
}
M.PLUME_TEXTURES = {
    diffuse = "textures/cosmetics_tweaker/encarmine_hat/encarmine_cloth_diffuse",
    normal = "textures/cosmetics_tweaker/encarmine_hat/encarmine_cloth_normal",
    combined = "textures/cosmetics_tweaker/encarmine_hat/encarmine_cloth_combined",
}
M.MATERIAL_RESPONSE_REVISION = 6
M.DONOR_ALPHA_CONTRACT = true
M.DONOR_NORMAL_TANGENT_CONTRACT = true
M.DONOR_CONTROLLER_CONTRACT = true
M.DONOR_FADE_CONTRACT = true

M.registered = false
M._painted_units = setmetatable({}, { __mode = "k" })
M._paint_diag_seen = {}

local ITEM_LOCALIZATION = {
    cos_encarmine_hat_name = "Encarmine Helmet",
    cos_encarmine_hat_description =
        "A red-and-gold Foot Knight helm with a black plume, created for Tweaker: Cosmetics.",
}
M.ITEM_LOCALIZATION = ITEM_LOCALIZATION

local enabled

enabled = function()
    if not mod or type(mod.get) ~= "function" then return true end
    local ok, value = pcall(mod.get, mod, "cos_encarmine_hat_enabled")
    return not ok or value ~= false
end

local function texture_bindings()
    local rows = {}
    for _, textures in ipairs({ M.ARMOR_TEXTURES, M.PLUME_TEXTURES }) do
        rows[#rows + 1] = { slot = M.TEXTURE_SLOTS.diffuse, texture = textures.diffuse }
        rows[#rows + 1] = { slot = M.TEXTURE_SLOTS.normal, texture = textures.normal }
        rows[#rows + 1] = { slot = M.TEXTURE_SLOTS.combined, texture = textures.combined }
    end
    return rows
end

function M.runtime_resources_ready(application)
    local bindings = texture_bindings()
    if RESIDENCY and type(RESIDENCY.texture_set_resident) == "function" then
        return RESIDENCY.texture_set_resident(
            bindings, application, nil, "encarmine_hat")
    end
    -- Unit-test fallback only. Production always consumes the synchronized
    -- shared contract; the fallback keeps this pure module independently testable.
    local can_get = application and application.can_get
    if type(can_get) ~= "function" then return false end
    for i = 1, #bindings do
        local ok, ready = pcall(can_get, "texture", bindings[i].texture)
        if not ok or ready ~= true then return false end
    end
    return true
end

local function unit_materials_ready(unit, surface)
    if RESIDENCY and type(RESIDENCY.unit_materials_resident) == "function" then
        return RESIDENCY.unit_materials_resident(
            unit, Unit, Mesh, nil, surface or "encarmine_hat")
    end
    -- Unit-test fallback only; mirror the complete closure rather than trusting
    -- pcall around Material.set_texture, whose native faults bypass Lua.
    if not (Unit and Unit.alive and Unit.num_meshes and Unit.mesh
            and Mesh and Mesh.num_materials and Mesh.material) then return false end
    local ok_n, mesh_count = pcall(Unit.num_meshes, unit)
    if not ok_n or type(mesh_count) ~= "number" or mesh_count < 1 then return false end
    local total = 0
    for mesh_index = 0, mesh_count - 1 do
        local ok_mesh, mesh = pcall(Unit.mesh, unit, mesh_index)
        if not ok_mesh or not mesh then return false end
        local ok_m, material_count = pcall(Mesh.num_materials, mesh)
        if not ok_m or type(material_count) ~= "number" or material_count < 1 then return false end
        for material_index = 0, material_count - 1 do
            local ok_material, material = pcall(Mesh.material, mesh, material_index)
            local ok_text, identity = false, nil
            if ok_material and material then
                ok_text, identity = pcall(tostring, material)
            end
            if not ok_material or not material or not ok_text or not identity
                    or identity:find("#ID[00000000]", 1, true) then return false end
            total = total + 1
        end
    end
    return total > 0
end

local function paint_meshes(unit, indices, textures)
    for _, mesh_index in ipairs(indices) do
        local mesh = Unit.mesh(unit, mesh_index)
        local material_count = Mesh.num_materials(mesh)
        for material_index = 0, material_count - 1 do
            local material = Mesh.material(mesh, material_index)
            Material.set_texture(material, M.TEXTURE_SLOTS.diffuse, textures.diffuse)
            Material.set_texture(material, M.TEXTURE_SLOTS.normal, textures.normal)
            Material.set_texture(material, M.TEXTURE_SLOTS.combined, textures.combined)
        end
    end
end

function M.apply_surface(unit, surface)
    if not enabled() then return false, "disabled" end
    if not (unit and Unit and Unit.alive and Unit.alive(unit)) then
        return false, "dead_unit"
    end
    if M._painted_units[unit] == M.MATERIAL_RESPONSE_REVISION then
        return true, "already_applied"
    end
    if not M.runtime_resources_ready(Application) then
        return false, "textures_unavailable"
    end

    local mesh_count = Unit.num_meshes(unit)
    if mesh_count ~= M.LAUREL_SCENE_CONTRACT.mesh_count then
        return false, "donor_mesh_count_" .. tostring(mesh_count)
    end
    if not unit_materials_ready(unit, surface) then
        return false, "unit_materials_unavailable"
    end

    local ok, err = pcall(function()
        paint_meshes(unit, M.LAUREL_SCENE_CONTRACT.armor_mesh_indices, M.ARMOR_TEXTURES)
        paint_meshes(unit, M.LAUREL_SCENE_CONTRACT.plume_mesh_indices, M.PLUME_TEXTURES)
    end)
    if not ok then
        local key = tostring(surface or "unknown") .. "|" .. tostring(err)
        if not M._paint_diag_seen[key] then
            M._paint_diag_seen[key] = true
            mod:info("[cos:612] Laurel material-instance override failed surface=%s err=%s",
                tostring(surface or "unknown"), tostring(err))
        end
        return false, tostring(err)
    end

    M._painted_units[unit] = M.MATERIAL_RESPONSE_REVISION
    return true, "applied"
end

function M.is_custom_identity(item_or_variant_key)
    return item_or_variant_key == M.ITEM_KEY or item_or_variant_key == M.VARIANT_KEY
end

-- Compatibility for existing spawn call sites. Returning the donor every time
-- is intentional: package-facing and rendered identity must be identical.
function M.spawn_unit(_application, _surface)
    return M.BASE_UNIT, false
end

-- Compatibility no-ops while callers migrate. The exact donor already owns
-- its controller and participates in vanilla FadeSystem registration.
function M.install_native_plume_controller(unit)
    return unit and Unit and Unit.alive and Unit.alive(unit) or false
end

function M.register_fade_link(owner_unit, attachment_unit)
    return owner_unit and attachment_unit and Unit and Unit.alive
        and Unit.alive(owner_unit) and Unit.alive(attachment_unit) or false
end

function M.refresh_runtime_resources(application)
    M.CUSTOM_UNIT = M.BASE_UNIT
    local entry = ItemMasterList and rawget(ItemMasterList, M.ITEM_KEY)
    if entry then entry.unit = M.BASE_UNIT end
    return M.runtime_resources_ready(application)
end

function M.tick(_dt)
    -- No package probing or controller installation is required. The vanilla
    -- donor package is loaded through the ordinary hat item path.
end

function M.is_enabled()
    return enabled()
end

function M.resolve_variant(key)
    if key ~= M.VARIANT_KEY then return nil end
    local active = enabled()
    return {
        kind = "vanilla_donor_texture_override",
        swap_hand = "hat",
        new_units = { M.BASE_UNIT },
        is_vanilla_unit = true,
        cos_authored = true,
        enabled = active,
    }
end

local function build_entry()
    local original = ItemMasterList and rawget(ItemMasterList, M.BASE_KEY)
    if type(original) ~= "table" then return nil end
    local entry = table.clone(original)
    entry.key = M.ITEM_KEY
    entry.name = M.ITEM_KEY
    entry.display_name = "cos_encarmine_hat_name"
    entry.description = "cos_encarmine_hat_description"
    entry.localized_name = ITEM_LOCALIZATION.cos_encarmine_hat_name
    entry.localized_description = ITEM_LOCALIZATION.cos_encarmine_hat_description
    entry.inventory_icon = "icon_knight_hat_0006_encarmine"
    entry.unit = M.BASE_UNIT
    entry.rarity = "exotic"
    entry.required_dlc = nil
    entry.can_wield = enabled() and { "es_knight" } or {}
    entry.cos_authored = true
    entry.cos_vanilla_fallback = M.BASE_KEY
    entry.mod_data = {
        backend_id = M.ITEM_KEY,
        ItemInstanceId = M.ITEM_KEY,
        key = M.ITEM_KEY,
        ItemId = M.ITEM_KEY,
        CustomData = { rarity = "exotic" },
        rarity = "exotic",
    }
    return entry
end

function M.sync_toggle()
    local entry = ItemMasterList and rawget(ItemMasterList, M.ITEM_KEY)
    if not entry then return false end
    entry.unit = M.BASE_UNIT
    entry.can_wield = enabled() and { "es_knight" } or {}
    return true
end

function M.register_all(bridge)
    M.bridge = bridge or M.bridge
    if M.registered then
        M.sync_toggle()
        return true
    end
    if not (ItemMasterList and NetworkLookup and NetworkLookup.item_names) then return false end
    if not (mod and type(mod.add_mod_items_to_masterlist) == "function"
            and type(mod.add_mod_items_to_local_backend) == "function") then
        return false
    end

    local entry = build_entry()
    if not entry then return false end
    mod:add_mod_items_to_masterlist({ entry })
    mod:add_mod_items_to_local_backend({ entry }, "cosmetics_tweaker")

    if bridge then
        bridge.backend_to_armoury[M.ITEM_KEY] = M.VARIANT_KEY
        bridge.backend_to_vanilla[M.ITEM_KEY] = M.BASE_KEY
        bridge.armoury_to_backend[M.VARIANT_KEY] = M.ITEM_KEY
        -- Never alias BASE_UNIT in unit_path_to_clones: ordinary Laurel hats
        -- share this donor and must remain unpainted.
        bridge.custom_variants = bridge.custom_variants or {}
        bridge.custom_variants[M.VARIANT_KEY] = true
        bridge.registered = true
    end

    M.registered = true
    mod:info("[cos:encarmine] registered %s -> exact Laurel donor (enabled=%s)",
        M.ITEM_KEY, tostring(enabled()))
    return true
end

return M
