-- ============================================================
-- Material-Hijack (patched) — embedded into cosmetics_tweaker (v0.9.3.3+)
-- ============================================================
-- Forked from material_hijack_patched/material_hijack_patched.lua. Same six
-- hooks (Unit.set_unit_visibility, set_visibility, set_mesh_visibility,
-- GearUtils.create_equipment, UnitSpawner.spawn_local_unit,
-- HeroPreviewer._spawn_item_unit), same defensive `Application.can_get`
-- pre-flights to avoid the `[Script Error]: Unit not found #ID[...]` C-level
-- fatal when a hook gets handed a non-resolvable unit name.
--
-- Source archived at:
--   C:/Users/danjo/source/repos/misc-vermintide-mods/material_hijack_patched_archive/
-- Standalone Workshop mod (3727311798) keeps existing for back-compat.
--
-- Cross-compatibility / load-order: this embed is GUARDED against two
-- conflict states. If either is present, the embed goes inert (no hook
-- registration) and the active copy wins:
--
--   1. Standalone `material_hijack_patched` (id 3727311798) is enabled.
--      The standalone is the active MH; this embed defers.
--   2. Original `Material-Hijack` (id 2771980886) is enabled.
--      The original hooks the SAME six methods and is INCOMPATIBLE with
--      either patched fork running alongside (double-hook → 2x texture
--      load → renderer deadlock on NVIDIA, per v0.1.3 of the standalone).
--      Embed bails and chat-warns the user to disable the original.
--
-- Cross-mod sentinel `_G._cos_mh_embed_owner`: if a sibling tweaker mod
-- (e.g. character_weapon_variants) is ALSO embedding MH, only the FIRST
-- mod to load activates the embed. The sentinel is written once and
-- checked by every subsequent embed. This keeps multi-tweaker-mod stacks
-- from double-hooking.
--
-- No "must load before X" constraint: MH only hooks global classes
-- (Unit / GearUtils / UnitSpawner / HeroPreviewer). All loaded at VT2
-- boot before any VMF mod fires. Hooks land in time regardless of which
-- tweaker mod owns the embed.

local mod = get_mod("cosmetics_tweaker")
-- v0.9.5: when the embed is dormant (cosmetics_tweaker missing, sibling owner,
-- or standalone enabled), still return a consistent shape so the cosmetics_
-- tweaker.lua loader can call MH_EMBED.replace_textures(...) without nil-check
-- gymnastics. Dormant exports are no-ops.
local _DORMANT_EXPORTS = {
    replace_textures      = function() end,
    add_particles         = function() end,
    attach_anim_extension = function() end,
    dormant               = true,
}
if not mod then return _DORMANT_EXPORTS end

-- Cross-mod sentinel: first embed to activate claims ownership; later
-- sibling embeds detect and skip. Survives the file being copy-pasted
-- byte-identically into character_weapon_variants or any other tweaker.
if _G._cos_mh_embed_owner then
    mod:info("[mh_embed] sibling embed (%s) already active; this copy stays dormant",
        tostring(_G._cos_mh_embed_owner))
    return _DORMANT_EXPORTS
end

-- Conflict guard #1: standalone patched MH (Workshop 3727311798).
do
    local standalone_patched = get_mod("material_hijack_patched")
    if standalone_patched then
        local enabled = true
        if type(standalone_patched.is_enabled) == "function" then
            enabled = standalone_patched:is_enabled()
        end
        if enabled then
            mod:info("[mh_embed] standalone material_hijack_patched is enabled; embed dormant")
            return _DORMANT_EXPORTS
        end
    end
end

-- Conflict guard #2: original Material-Hijack (Workshop 2771980886).
-- Running both = double-hook on the same six methods → texture replace
-- twice per spawn, 4× redundant package loads, orphaned material slots,
-- renderer thread deadlock on NVIDIA hardware (v0.1.3 of standalone, ref
-- amand's session 2026-05-19 — 16.1s renderer freeze).
do
    local original_mh = get_mod("Material-Hijack")
    if original_mh then
        local enabled = true
        if type(original_mh.is_enabled) == "function" then
            enabled = original_mh:is_enabled()
        end
        if enabled then
            mod:echo("[cosmetics_tweaker] Material-Hijack (original, Workshop 2771980886) is ENABLED. DISABLE it in the F4 launcher — our embedded Material-Hijack (patched) is a drop-in superset with defensive guards against the 'Unit not found' fatal. Embed staying dormant to avoid double-hook renderer deadlock.")
            mod:warning("[mh_embed] original Material-Hijack enabled; embed dormant to prevent double-hook deadlock")
            return _DORMANT_EXPORTS
        end
    end
end

mod:info("[mh_embed] activating (no conflict detected)")
_G._cos_mh_embed_owner = "cosmetics_tweaker"

mod.texture_animations = mod.texture_animations or {}
mod:dofile("scripts/mods/cosmetics_tweaker/_material_hijack_embedded_anim")

local unit_alive          = Unit.alive
local unit_has_data       = Unit.has_data
local unit_get_data       = Unit.get_data
local unit_set_data       = Unit.set_data
local unit_set_material   = Unit.set_material
local unit_num_meshes     = Unit.num_meshes
local unit_mesh           = Unit.mesh
local unit_world          = Unit.world
local unit_world_pos      = Unit.world_position
local mesh_num_materials  = Mesh.num_materials
local mesh_has_matrerial  = Mesh.has_material   -- (sic — kept original spelling)
local mesh_material       = Mesh.material
local material_set_texture = Material.set_texture
local manager_package     = Managers.package

local _DEFAULT_TEX_DICT = {
    texture_map_59cd86b9 = "textures/default_normal",
    texture_map_0205ba86 = "textures/default_packed",
    texture_map_c0ba2942 = "textures/default_col",
    texture_map_ee282ea2 = "textures/default_emis",
    texture_map_4617b8e0 = "textures/default_emis",
    texture_map_71d74d4d = "textures/default_emis",
}

-- ============================================================
-- Defensive helpers
-- ============================================================
local function _has_unit(path)
    if not path or type(path) ~= "string" then return false end
    if not rawget(_G, "Application") or not Application.can_get then return true end
    return Application.can_get("unit", path) and true or false
end

local function _has_package(path)
    if not path or type(path) ~= "string" then return false end
    if not rawget(_G, "Application") or not Application.can_get then return true end
    return Application.can_get("package", path) and true or false
end

-- v0.9.50-dev (#199): this MH fork inherited the standalone's hardcoded fallback
-- texture paths (textures/T_Texture_NR normal / T_Texture_MOS MAB at lines ~181)
-- which were NEVER shipped — the standalone's own CHANGELOG flags them as
-- missing, and the correct defaults live in the dead/unused _DEFAULT_TEX_DICT
-- above. Setting a non-existent texture is an engine-level fatal: equipping the
-- CWV custom musket (mat_to_use convention, no per-slot normals.slotN) falls
-- back to T_Texture_NR and crashes. Preflight the texture like units/packages so
-- a missing one is SKIPPED, not fatal. Skipping is also the right visual — the
-- unit keeps whatever real texture its mat_to_use material already carries
-- instead of a flat default.
local function _has_texture(path)
    if not path or type(path) ~= "string" then return false end
    if not rawget(_G, "Application") or not Application.can_get then return true end
    return Application.can_get("texture", path) and true or false
end

local function _safe_load_package(path)
    if not _has_package(path) then
        mod:warning("[mh_embed] Skipping package load — not in resources: %s", tostring(path))
        return
    end
    manager_package:load(path, "global")
end

-- ============================================================
-- Texture hijacking (ported from MH-patched)
-- ============================================================
local function replace_textures(unit)
    if not unit or not unit_alive(unit) then return end

    if unit_has_data(unit, "mat_to_use") then
        local mat_slots   = {}
        local colors      = {}
        local normals     = {}
        local MABs        = {}
        local emis_colors = {}
        local emis_details = {}
        local mat = unit_get_data(unit, "mat_to_use")
        local package_to_use = mat

        if unit_has_data(unit, "mat_package") then
            package_to_use = unit_get_data(unit, "mat_package")
        end

        _safe_load_package(package_to_use)

        local count = 1
        while unit_get_data(unit, "mat_slots", "slot" .. tostring(count)) do
            mat_slots[count] = unit_get_data(unit, "mat_slots", "slot" .. tostring(count))
            count = count + 1
        end

        local num_mats = count - 1
        local dict = {}

        for i = 1, num_mats, 1 do
            colors[i]       = "textures/default_col"
            normals[i]      = "textures/T_Texture_NR"
            MABs[i]         = "textures/T_Texture_MOS"
            emis_colors[i]  = "textures/default_emis"
            emis_details[i] = "textures/default_emis"
            dict[mat_slots[i]] = {}

            if unit_has_data(unit, "colors", "slot" .. tostring(i)) then
                colors[i] = unit_get_data(unit, "colors", "slot" .. tostring(i))
                dict[mat_slots[i]].color_slot = unit_get_data(unit, "colors", "slot" .. tostring(i))
            else
                dict[mat_slots[i]].color_slot = colors[i]
            end

            if unit_has_data(unit, "normals", "slot" .. tostring(i)) then
                normals[i] = unit_get_data(unit, "normals", "slot" .. tostring(i))
                dict[mat_slots[i]].norm_slot = unit_get_data(unit, "normals", "slot" .. tostring(i)) or "texture_map"
            else
                dict[mat_slots[i]].norm_slot = normals[i]
            end

            if unit_has_data(unit, "MABs", "slot" .. tostring(i)) then
                MABs[i] = unit_get_data(unit, "MABs", "slot" .. tostring(i))
                dict[mat_slots[i]].MAB_slot = unit_get_data(unit, "MABs", "slot" .. tostring(i)) or "texture_map"
            else
                dict[mat_slots[i]].MAB_slot = MABs[i]
            end

            if unit_has_data(unit, "emis_colors", "slot" .. tostring(i)) then
                emis_colors[i] = unit_get_data(unit, "emis_colors", "slot" .. tostring(i))
                dict[mat_slots[i]].emis_col_slot = unit_get_data(unit, "emis_colors", "slot" .. tostring(i)) or "texture_map"
            end

            if unit_has_data(unit, "emis_details", "slot" .. tostring(i)) then
                emis_details[i] = unit_get_data(unit, "emis_details", "slot" .. tostring(i))
                dict[mat_slots[i]].emis_det_slot = unit_get_data(unit, "emis_details", "slot" .. tostring(i)) or "texture_map"
            end
        end

        for mat_slot, texture in pairs(dict) do
            unit_set_material(unit, mat_slot, mat)
            local num_meshes = unit_num_meshes(unit)
            for i = 0, num_meshes - 1, 1 do
                local mesh = unit_mesh(unit, i)
                local num_mats_m = mesh_num_materials(mesh)
                for j = 0, num_mats_m - 1, 1 do
                    if mesh_has_matrerial(mesh, mat_slot) then
                        local mater = mesh_material(mesh, mat_slot)
                        for text_slot, map in pairs(texture) do
                            local tex_name = unit_get_data(unit, text_slot) or "texture_map"
                            if _has_texture(map) then
                                material_set_texture(mater, tex_name, map)
                            else
                                mod:warning("[mh_embed] #199: skipped missing texture '%s' (slot '%s') — kept material's existing map", tostring(map), tostring(tex_name))
                            end
                        end
                    end
                end
            end
        end
    end

    if unit_has_data(unit, "mat_list") then
        local num_mats = unit_get_data(unit, "num_mats")
        for i = 1, num_mats, 1 do
            local mat_slot = unit_get_data(unit, "mat_slots", "slot" .. tostring(i))
            local mat      = unit_get_data(unit, "mat_list", "slot" .. tostring(i))
            unit_set_material(unit, mat_slot, mat)
        end
    end
end

local function add_particles(unit, world)
    if not unit or not unit_alive(unit) then return end

    if unit_has_data(unit, "particles") then
        local node_part_pairs = unit_get_data(unit, "particles", "node_part_pairs")
        for i = 1, node_part_pairs, 1 do
            local pacakge = unit_get_data(unit, "particles", tostring(i), "package")
            if pacakge then
                _safe_load_package(pacakge)
            end

            local fx   = unit_get_data(unit, "particles", tostring(i), "fx")
            local node = unit_get_data(unit, "particles", tostring(i), "node")
            local translation_rotation = Matrix4x4.identity()

            if unit_has_data(unit, "particles", tostring(i), "offset") then
                local x = unit_get_data(unit, "particles", tostring(i), "offset", "x")
                local y = unit_get_data(unit, "particles", tostring(i), "offset", "y")
                local z = unit_get_data(unit, "particles", tostring(i), "offset", "z")
                Matrix4x4.set_element(translation_rotation, 4, 1, x)
                Matrix4x4.set_element(translation_rotation, 4, 2, y)
                Matrix4x4.set_element(translation_rotation, 4, 3, z)
            end

            local particle_id = World.create_particles(world, fx, Vector3(0, 0, 0))
            World.link_particles(world, particle_id, unit, node, translation_rotation, "destroy")
            unit_set_data(unit, "has_linked_particles", particle_id)
        end
    end
end

-- ============================================================
-- Hooks (six total, registered on cosmetics_tweaker's mod handle)
-- ============================================================
mod:hook(Unit, "set_unit_visibility", function (func, unit, visibility)
    local world = unit_world(unit)
    if unit_get_data(unit, "inactive_particles") and visibility then
        add_particles(unit, world)
        unit_set_data(unit, "inactive_particles", false)
    end
    if unit_has_data(unit, "has_linked_particles") and not visibility then
        World.destroy_particles(world, unit_get_data(unit, "has_linked_particles"))
        unit_set_data(unit, "inactive_particles", true)
    end
    return func(unit, visibility)
end)

mod:hook(Unit, "set_visibility", function (func, unit, group, visibility)
    local world = unit_world(unit)
    if unit_get_data(unit, "inactive_particles") and visibility then
        add_particles(unit, world)
        unit_set_data(unit, "inactive_particles", false)
    end
    if unit_has_data(unit, "has_linked_particles") and not visibility then
        World.destroy_particles(world, unit_get_data(unit, "has_linked_particles"))
        unit_set_data(unit, "inactive_particles", true)
    end
    return func(unit, group, visibility)
end)

mod:hook(Unit, "set_mesh_visibility", function (func, unit, mesh, visibility, context)
    local world = unit_world(unit)
    if unit_get_data(unit, "inactive_particles") and visibility then
        add_particles(unit, world)
        unit_set_data(unit, "inactive_particles", false)
    end
    if unit_has_data(unit, "has_linked_particles") and not visibility then
        World.destroy_particles(world, unit_get_data(unit, "has_linked_particles"))
        unit_set_data(unit, "inactive_particles", true)
    end
    return func(unit, mesh, visibility, context)
end)

-- v0.9.5: GearUtils.create_equipment hook REMOVED from MH embed.
-- cosmetics_tweaker.lua already has a `mod:hook("GearUtils", "create_equipment",
-- ...)` registration via the same mod handle (line ~3331) — double registration
-- produced VMF `Attempting to rehook active hook` warning at boot. To eliminate
-- the warning, the MH texture/particle work is now folded into cosmetics_tweaker's
-- existing hook via the module exports at the bottom of this file
-- (replace_textures + add_particles). Functionally equivalent; one hook
-- registration instead of two.

-- The patched UnitSpawner.spawn_local_unit: pre-validates via
-- Application.can_get before calling World.spawn_unit, refusing the spawn
-- if the unit isn't in resources. Prevents the C-level fatal that pcall
-- can't catch.
mod:hook("UnitSpawner", "spawn_local_unit", function (func, self, unit_name, position, rotation, material)
    if not _has_unit(unit_name) then
        -- issue #270 (crash A): DO NOT delegate to native here. Vanilla
        -- UnitSpawner.spawn_local_unit calls World.spawn_unit(self.world,
        -- unit_name, ...) UNCONDITIONALLY (unit_spawner.lua:294), which C-asserts
        -- (`can_get(unit_type, unit_name)`, c_api_world.cpp:67) on a non-resident
        -- unit and hard-crashes the client -- bypassing pcall. The old
        -- `return func(...)` here therefore DID crash: the "refusing to spawn" log
        -- was misleading (it refused our texture work but still called native, so
        -- a non-resident headpiece on a viewer machine CTD'd them). Returning nil
        -- skips the spawn entirely. Every mod-side caller that can feed a
        -- non-resident headpiece here is guarded to tolerate a nil/absent unit:
        -- AttachmentUtils.create_attachment has a residency gate and
        -- AttachmentUtils.link has a Unit.has_node guard (both cosmetics_tweaker.lua).
        -- Log-only via mod:info (reaches the console log with mod logging OFF; no
        -- chat spam, unlike the old mod:warning).
        mod:info("[cos-hat] SKIP non-resident spawn unit=%s (would C-assert in World.spawn_unit)",
            tostring(unit_name))
        return nil
    end

    local unit = World.spawn_unit(self.world, unit_name, position, rotation, material)
    local unit_unique_id = self.unit_unique_id
    self.unit_unique_id = unit_unique_id + 1

    unit_set_data(unit, "unique_id", unit_unique_id)
    unit_set_data(unit, "unit_name", unit_name)

    POSITION_LOOKUP[unit] = unit_world_pos(unit, 0)

    replace_textures(unit)
    add_particles(unit, self.world)

    local new = AnimTextureExtension:new(unit)
    if new.unit_time then
        mod.texture_animations[unit] = new
    end

    return unit
end)

-- v0.9.5: HeroPreviewer._spawn_item_unit hook REMOVED from MH embed.
-- cosmetics_tweaker.lua already has a `mod:hook_safe("HeroPreviewer",
-- "_spawn_item_unit", _spawn_item_unit_la_hook)` (line ~5697) via the same
-- mod handle. VMF warns on mod:hook + mod:hook_safe registered on the
-- same Class+method via the same mod. Folded the MH logic into
-- cosmetics_tweaker's existing _spawn_item_unit_la_hook path via the
-- module exports below (replace_textures + add_particles + new
-- attach_anim_extension helper). Functionally equivalent.
local function attach_anim_extension(unit)
    if not unit or not unit_alive(unit) then return end
    local new = AnimTextureExtension:new(unit)
    if new.unit_time then
        mod.texture_animations[unit] = new
    end
end

mod:info("[mh_embed] hooks installed (4) — embedded Material-Hijack (patched) active. create_equipment + _spawn_item_unit folded into cosmetics_tweaker's existing hooks (v0.9.5 de-dupe).")

-- v0.9.5: module exports for cosmetics_tweaker.lua to call from its own hooks.
return {
    replace_textures      = replace_textures,
    add_particles         = add_particles,
    attach_anim_extension = attach_anim_extension,
}
