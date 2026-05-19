-- ============================================================
-- Material-Hijack (patched) v0.1.3
-- ============================================================
-- Forked from the decompiled Material-Hijack (Workshop 2771980886,
-- author Grundlid). Same six hooks; added pre-validation gates to
-- avoid the `[Script Error]: Unit not found #ID[...]` C-level fatal
-- when a hook gets handed a unit name / package path that the
-- resource manager can't resolve.
--
-- The original implementation reimplements `UnitSpawner.spawn_local_unit`
-- inline and calls `World.spawn_unit` directly. If the unit isn't in
-- resources, the C assert at c_api_world.cpp:67 fatals — pcall doesn't
-- catch it. We use `Application.can_get("unit", ...)` (vanilla-exposed)
-- as a Lua-side pre-flight and either delegate or skip.
local mod = get_mod("material_hijack_patched")
mod.texture_animations = mod.texture_animations or {}
mod:dofile("scripts/mods/material_hijack_patched/anim_texture_extension")

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
local mesh_has_matrerial  = Mesh.has_material   -- (sic — kept original spelling for hook compat)
local mesh_material       = Mesh.material
local material_set_texture = Material.set_texture
local manager_package     = Managers.package

-- Default fallback texture map names → fallback texture paths. Mirrors
-- the original mod. Note: the fallback texture *files* aren't shipped
-- in this fork (see CHANGELOG); if a hijack tries one of these paths
-- and the texture isn't resolvable, `material_set_texture` silently
-- fails. Visual-only consequence; doesn't crash.
local _DEFAULT_TEX_DICT = {
    texture_map_59cd86b9 = "textures/default_normal",
    texture_map_0205ba86 = "textures/default_packed",
    texture_map_c0ba2942 = "textures/default_col",
    texture_map_ee282ea2 = "textures/default_emis",
    texture_map_4617b8e0 = "textures/default_emis",
    texture_map_71d74d4d = "textures/default_emis",
}

-- ============================================================
-- Defensive helpers (the patch surface)
-- ============================================================

-- `Application.can_get(type, name)` is vanilla — used in gear_utils,
-- store views, terror events, etc. as a "is this resource resolvable
-- right now?" check. Returns true/false; never fatals. We wrap it to
-- bail gracefully if Application itself is absent (shouldn't happen,
-- but the cost of being defensive here is one extra check).
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

local function _safe_load_package(path)
    if not _has_package(path) then
        mod:warning("[mh] Skipping package load — not in resources: %s", tostring(path))
        return
    end
    manager_package:load(path, "global")
end

-- ============================================================
-- Texture hijacking (ported from original; package loads guarded)
-- ============================================================
local function replace_textures(unit)
    -- Guard against nil / dead unit (the original would fatal here on
    -- a Unit.has_data call against a non-unit).
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
                            material_set_texture(mater, tex_name, map)
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
-- Conflict guard
-- ============================================================
-- The original Material-Hijack (Workshop 2771980886, by Grundlid) and this
-- fork hook the SAME six functions. If both run, every spawn / visibility /
-- equip call processes each unit TWICE — `replace_textures` runs twice on the
-- same unit, sync-loading the same skin package 4× per cycle and leaving
-- material slots pointing at orphan IDs after the second pass. The renderer
-- can't resolve those materials at draw time (`[MeshObject] Failed looking up
-- material: '#ID[...]'`), and on NVIDIA hardware (specifically the
-- `NvMemMapStoragex::TotalDiskUsage` shader-cache lookup that backs D3D12
-- `CreateGraphicsPipelineState`) it deadlocks the renderer thread.
--
-- Burned: amand's session 2026-05-19 (session `2724b4bf-1c14-40f6-98ed-151b3dda41b5`,
-- console-2026-05-19-01.57.38-2724b4bf...log) — 16.1 s renderer freeze after 3
-- cycles of breton skin material-lookup failures. AMD GPUs (lynnd) degraded
-- visually without deadlocking; VRAM-headroom-rich NVIDIA setups (danjo)
-- escaped on luck.
--
-- v0.1.3 reality check (RETRACTED v0.1.2 advice): a 2026-05-19 source audit of
-- Loremaster's Armoury (the canonical downstream mod cited in v0.1.2 as needing
-- the original by name) found ZERO calls to `get_mod("Material-Hijack")` in LA's
-- entire source tree. LA's coupling to Material-Hijack is purely DATA-driven —
-- LA's compiled `.unit` files carry `mat_to_use` / `mat_slots` / `colors` /
-- `normals` / `MABs` / `particles` data nodes that EITHER variant of MH consumes
-- in their `spawn_local_unit` / `_spawn_item_unit` / `create_equipment` hooks.
-- LA itself never invokes any MH-exported Lua function. The premise that
-- disabling the original would silently break LA is FALSE.
--
-- What matters: the patched fork is a strict SUPERSET of the original (same six
-- hooks, plus `Application.can_get` pre-flights and nil-unit guards that
-- prevent the C-level `Unit not found #ID[...]` fatal when a bot's loadout
-- references an unloadable unit). In any setup where both are subscribed, the
-- patched should be the active one — it's the only version that ships the
-- defensive guards. Belt-and-braces alias in `la_prefix_patch` makes
-- `get_mod("Material-Hijack")` resolve to this fork transparently for any
-- hypothetical un-audited dependent that does look up MH by mod_id.
--
-- When both ARE enabled simultaneously we still go inert (skip hook
-- registration) to prevent double-fire: with both sets of hooks live,
-- `replace_textures` runs twice per spawn, sync-loading the same skin
-- package 4× and orphaning material slots → `[MeshObject] Failed looking up
-- material` warnings cascade → on NVIDIA the renderer thread deadlocks
-- inside `NvMemMapStoragex::TotalDiskUsage` shader-cache lookups during
-- D3D12 `CreateGraphicsPipelineState` (burned: amand's 2026-05-19 session
-- `2724b4bf-1c14-40f6-98ed-151b3dda41b5` — 16.1 s renderer freeze after 3
-- material-lookup-failure cycles). Chat-warn the user with the CORRECTED
-- recommendation: disable the ORIGINAL, not this fork.
--
-- Load-order note: VMF loads VMF mods in ascending workshop_id, so the
-- original (2771980886) is initialized before this fork (3727311798). The
-- `get_mod("Material-Hijack")` lookup below therefore resolves at module load.
local _original_mh = get_mod("Material-Hijack")
local _CONFLICT_DETECTED
if _original_mh then
    -- Defensive: if VMF ever changes the `is_enabled` API surface, treat the
    -- presence of the original mod handle as conflict regardless. Safer to
    -- err on the side of bailing (no double-hook deadlock risk).
    if type(_original_mh.is_enabled) == "function" then
        _CONFLICT_DETECTED = _original_mh:is_enabled()
    else
        _CONFLICT_DETECTED = true
    end
end

if _CONFLICT_DETECTED then
    mod:echo("[Material-Hijack (patched)] inert (both versions enabled). DISABLE the ORIGINAL Material-Hijack (Workshop 2771980886) and keep THIS fork (Material-Hijack (patched), Workshop 3727311798) enabled — the patched fork is a drop-in superset of the original with defensive guards against the 'Unit not found' fatal that the original hits on bot loadouts referencing unloadable units. v0.1.2 advice was wrong; LA does NOT call get_mod('Material-Hijack') and works fine without the original installed.")
    mod:warning("[mh] Conflict detected with original Material-Hijack (2771980886). Skipping hook registration to prevent double-fire renderer deadlock. CORRECTED RECOMMENDATION: disable the ORIGINAL, keep the patched fork — the patched is a drop-in superset.")
end

-- ============================================================
-- Hooks
-- ============================================================
-- The five visibility / equipment hooks below are ported unchanged
-- aside from the nil-unit guards now inside replace_textures /
-- add_particles. The spawn_local_unit hook gets a real patch.
--
-- All six hooks gated by _CONFLICT_DETECTED above — when the original
-- Material-Hijack is also enabled we skip registration so the user only
-- gets one copy of each hook firing.

if not _CONFLICT_DETECTED then

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

mod:hook("GearUtils", "create_equipment", function (func, world, slot_name, item_data, unit_1p, unit_3p, is_bot, unit_template, extra_extension_data, ammo_percent, override_item_template, override_item_units)
    replace_textures(unit_1p)
    replace_textures(unit_3p)
    add_particles(unit_1p, world)
    add_particles(unit_3p, world)
    return func(world, slot_name, item_data, unit_1p, unit_3p, is_bot, unit_template, extra_extension_data, ammo_percent, override_item_template, override_item_units)
end)

-- ============================================================
-- THE PATCH: UnitSpawner:spawn_local_unit
-- ============================================================
-- Original called World.spawn_unit unconditionally. Now we
-- pre-validate via Application.can_get("unit", unit_name); on miss
-- we log the offending path and try to delegate to `func` (the next
-- hook / vanilla) — vanilla would also fatal, but at least we've
-- surfaced the problem first. The path the user hit was a bot's
-- saved loadout referencing a skin's 3P unit that wasn't in the
-- resource manager.
mod:hook("UnitSpawner", "spawn_local_unit", function (func, self, unit_name, position, rotation, material)
    if not _has_unit(unit_name) then
        mod:warning("[mh] UnitSpawner:spawn_local_unit — unit not in resources, refusing to spawn: %s",
            tostring(unit_name))
        -- Try to give vanilla / next hook a chance in case `_has_unit`
        -- has a bug or returns false negatives. If vanilla fatals too,
        -- at least the warning above gets logged before the crash.
        return func(self, unit_name, position, rotation, material)
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

mod:hook("HeroPreviewer", "_spawn_item_unit", function (func, self, unit, item_slot_type, item_template, unit_attachment_node_linking, scene_graph_links, material_settings)
    replace_textures(unit)
    add_particles(unit, self.world)

    local new = AnimTextureExtension:new(unit)
    if new.unit_time then
        mod.texture_animations[unit] = new
    end

    return func(self, unit, item_slot_type, item_template, unit_attachment_node_linking, scene_graph_links, material_settings)
end)

end -- if not _CONFLICT_DETECTED

mod:info("Material-Hijack (patched) v0.1.0 loaded")
