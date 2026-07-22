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
    session_resident_paths = function() return {} end,
    reference_summary     = function()
        return { held = 0, exact = 0, over = 0, missing = 0 }
    end,
    loaded_packages       = {},               -- #282: empty registry when dormant
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
local RESIDENCY = mod:dofile("scripts/mods/cosmetics_tweaker/_lib_resource_residency")

local unit_alive          = Unit.alive
local unit_has_data       = Unit.has_data
local unit_get_data       = Unit.get_data
local unit_set_data       = Unit.set_data
local unit_set_material   = Unit.set_material
local unit_num_meshes     = Unit.num_meshes
local unit_mesh           = Unit.mesh
local unit_world          = Unit.world
local unit_world_pos      = Unit.world_position
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
-- #696: parallel material-residency guard. replace_textures binds vanilla
-- `mat_to_use` / `mat_list` materials via Unit.set_material with unit,
-- package, and texture (issue 199) all preflighted but never the material
-- itself; when the owning vanilla package is outside the unit's spawn-time
-- resource scope the engine warns ("Failed looking up material") and renders
-- fallback. Use the strict shared proof: skip the set and keep the unit's
-- current material. The skip line is bounded to once per unit+slot+material so it
-- also serves as the diagnostic separating this emitter from engine-side
-- baked-material resolution at husk spawn (which logs with no [cos:696]).
local function _has_material(path)
    return RESIDENCY.material_resident(
        path, Application, nil, "material_hijack_material") == true
end

local _mh_mat_skip_logged = {}
local function _mat_resident_or_log(unit, mat_slot, mat)
    if _has_material(mat) then return true end
    local k = tostring(unit) .. "|" .. tostring(mat_slot) .. "|" .. tostring(mat)
    if not _mh_mat_skip_logged[k] then
        _mh_mat_skip_logged[k] = true
        pcall(printf, "[cos:696] skipped non-resident material '%s' (slot '%s') on unit %s - kept current material",
            tostring(mat), tostring(mat_slot), tostring(unit))
    end
    return false
end

-- #696 follow-up diagnostics. The residency guard proved that a resource can
-- be globally gettable while Unit.set_material still reports a lookup miss in
-- the spawned unit's material manager. Put bounded brackets around that exact
-- native boundary so the next log identifies the binding convention, authored
-- unit path, slot and material preceding an engine MeshObject warning. Do not use
-- tostring(unit) as the dedupe identity: it changes on every respawn and would
-- turn a transition loop into unbounded logging.
local MH_MAT_BIND_TRACE_CAP = 24
local _mh_mat_bind_trace_count = 0
local _mh_mat_bind_trace_logged = {}

local function _material_trace_unit_name(unit)
    local ok_has, has_name = pcall(unit_has_data, unit, "unit_name")
    if ok_has and has_name then
        local ok_name, name = pcall(unit_get_data, unit, "unit_name")
        if ok_name and name then return tostring(name) end
    end

    if Unit.debug_name then
        local ok_debug, debug_name = pcall(Unit.debug_name, unit)
        if ok_debug and debug_name then return tostring(debug_name) end
    end

    return "<unknown>"
end

local function _material_trace_meshes(unit, mat_slot)
    local ok_count, count = pcall(unit_num_meshes, unit)
    if not ok_count or type(count) ~= "number" then return -1, -1 end

    local matching = 0
    for i = 0, count - 1 do
        local ok_mesh, mesh = pcall(unit_mesh, unit, i)
        if ok_mesh and mesh then
            local ok_has, has_slot = pcall(mesh_has_matrerial, mesh, mat_slot)
            if ok_has and has_slot then matching = matching + 1 end
        end
    end
    return count, matching
end

local function _set_material_traced(unit, mat_slot, mat, convention)
    if not _mat_resident_or_log(unit, mat_slot, mat) then return false end

    local unit_name = _material_trace_unit_name(unit)
    local source = tostring(convention or "unknown")
    local key = source .. "|" .. unit_name .. "|" .. tostring(mat_slot) .. "|" .. tostring(mat)
    local trace = not _mh_mat_bind_trace_logged[key]
        and _mh_mat_bind_trace_count < MH_MAT_BIND_TRACE_CAP

    if trace then
        _mh_mat_bind_trace_logged[key] = true
        _mh_mat_bind_trace_count = _mh_mat_bind_trace_count + 1
        local mesh_count, matching = _material_trace_meshes(unit, mat_slot)
        pcall(printf,
            "[cos:696] bind-start source=%s unit_name='%s' unit=%s slot='%s' material='%s' resident=true meshes=%d matching=%d trace=%d/%d",
            source, unit_name, tostring(unit), tostring(mat_slot), tostring(mat),
            mesh_count, matching, _mh_mat_bind_trace_count, MH_MAT_BIND_TRACE_CAP)
    end

    unit_set_material(unit, mat_slot, mat)

    if trace then
        pcall(printf, "[cos:696] bind-end source=%s unit_name='%s' slot='%s' material='%s'",
            source, unit_name, tostring(mat_slot), tostring(mat))
    end
    return true
end

-- #749: prove one complete texture transaction and the exact spawned material
-- handles before Material.set_texture. This is intentionally separate from the
-- session package lease (#282): package residency does not establish renderer
-- closure for this unit.
local _mh_residency_skip_seen = {}
local _mh_residency_skip_count = 0
local MH_RESIDENCY_SKIP_CAP = 24

local function _residency_skip_once(reason, context)
    local key = tostring(reason) .. "|" .. tostring(context)
    if _mh_residency_skip_seen[key]
            or _mh_residency_skip_count >= MH_RESIDENCY_SKIP_CAP then return end
    _mh_residency_skip_seen[key] = true
    _mh_residency_skip_count = _mh_residency_skip_count + 1
    pcall(printf, "[cos:749] Material-Hijack texture SKIP reason=%s context=%s evidence=%d/%d chat=false",
        tostring(reason), tostring(context), _mh_residency_skip_count,
        MH_RESIDENCY_SKIP_CAP)
end

local function _texture_bindings(unit, texture)
    local bindings = {}
    for text_slot, map in pairs(texture or {}) do
        bindings[#bindings + 1] = {
            slot = unit_get_data(unit, text_slot) or "texture_map",
            texture = map,
        }
    end
    return bindings
end

local function _resident_material_targets(unit, mat_slot)
    local targets = {}
    local num_meshes = unit_num_meshes(unit)
    for i = 0, num_meshes - 1 do
        local mesh = unit_mesh(unit, i)
        if mesh_has_matrerial(mesh, mat_slot) then
            local material = mesh_material(mesh, mat_slot)
            local ok_identity, identity = pcall(tostring, material)
            if not material or not ok_identity or not identity
                    or identity:find("#ID[00000000]", 1, true) then
                return nil, "target_material_unresolved"
            end
            targets[#targets + 1] = material
        end
    end
    if #targets < 1 then return nil, "target_material_absent" end
    return targets, "resident"
end

-- v0.9.76-dev (issue #282): exactly-once package loading under a private
-- reference. PackageManager.load() INCREMENTS a per-(package,
-- reference_name) refcount on every call (package_manager.lua:26-27) and
-- unload() decrements by one (package_manager.lua:196-238), so the old
-- per-call `load(path, "global")` here - invoked from replace_textures /
-- add_particles on EVERY hijacked wield/spawn - accumulated 90+ references
-- per session with no unload anywhere in this file. Shutdown then walked the
-- count down one-by-one ("Package still referenced, NOT unloaded" cascades)
-- and ended in the crashify "not unloaded, this can potentially cause an
-- deadlock" block on both peers (#282 / #477 logs).
--
-- "global" is not magic: it is an arbitrary reference-name string (vanilla
-- uses it for boot-lifetime packages, boot.lua:1759-1764). A mod-owned name
-- keeps our references attributable (dump_reference_counter) and immune to
-- collisions with vanilla's / LA's "global" refs on the same packages.
--
-- Lifetime correction (v0.9.163-dev): retain exactly one mod-owned reference
-- for the process session and let PackageManager.destroy release it. Current
-- logs #927/#937/#940 prove that even a post-StateIngame unload can report
-- complete with an empty delayed queue while PatchedResourcePackage retirement
-- still stalls and the package survives application shutdown. This material
-- graph outlives Lua's observable world/unit teardown edge.
local MH_PKG_REF = "cosmetics_tweaker_mh"
local MH_LIFECYCLE = mod:dofile("scripts/mods/cosmetics_tweaker/_mh_package_lifecycle")
local _mh_lifecycle
local _mh_skip_logged = {}

local function _mh_lifecycle_event(event, path, reason, detail)
    if event == "first_load" then
        pcall(printf, "[cos:282] first-load ref=%s: %s", MH_PKG_REF, tostring(path))
    elseif event == "adopted" then
        pcall(printf, "[cos:282] adopted session ref=%s count=%s: %s",
            MH_PKG_REF, tostring(detail), tostring(path))
    elseif event == "load_failed" then
        mod:warning("[mh_embed] package load FAILED for %s: %s", tostring(path), tostring(detail))
    end
end

_mh_lifecycle = MH_LIFECYCLE.new(manager_package, MH_PKG_REF, _mh_lifecycle_event)
local _mh_loaded_packages = _mh_lifecycle.registry

local function _safe_load_package(path)
    if not _has_package(path) then
        mod:warning("[mh_embed] Skipping package load — not in resources: %s", tostring(path))
        return
    end
    if _mh_loaded_packages[path] == "held" then
        -- Once per path per hold: the dedupe-skip line proves the registry fired
        -- without spamming a line on every wield/visibility toggle for the rest
        -- of the session.
        if not _mh_skip_logged[path] then
            _mh_skip_logged[path] = true
            pcall(printf, "[cos:282] dedupe-skip (already referenced; further skips silent): %s", tostring(path))
        end
        return
    end
    _mh_lifecycle:load(path)
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

        local context = "material_hijack"
        local plans, all_bindings = {}, {}
        for mat_slot, texture in pairs(dict) do
            local bindings = _texture_bindings(unit, texture)
            plans[#plans + 1] = { mat_slot = mat_slot, bindings = bindings }
            for _, binding in ipairs(bindings) do
                all_bindings[#all_bindings + 1] = binding
            end
        end

        -- One transaction for the complete unit: no texture write occurs until
        -- every resource, material bind, spawned handle, and target slot passes.
        local textures_ready, reason = RESIDENCY.texture_set_resident(
            all_bindings, Application, nil, context)
        if textures_ready ~= true then
            _residency_skip_once(reason, context)
        else
            local materials_bound = true
            for _, plan in ipairs(plans) do
                if not _set_material_traced(
                        unit, plan.mat_slot, mat, "mat_to_use") then
                    materials_bound = false
                end
            end
            local closure_ready, closure_reason = RESIDENCY.unit_materials_resident(
                unit, Unit, Mesh, nil, context)
            if not materials_bound then
                _residency_skip_once("material_bind_unavailable", context)
            elseif closure_ready ~= true then
                _residency_skip_once(closure_reason, context)
            else
                local targets_ready = true
                for _, plan in ipairs(plans) do
                    plan.targets, reason = _resident_material_targets(
                        unit, plan.mat_slot)
                    if not plan.targets then
                        targets_ready = false
                        _residency_skip_once(reason, context .. ":" .. tostring(plan.mat_slot))
                    end
                end
                if targets_ready then
                    for _, plan in ipairs(plans) do
                        for _, target in ipairs(plan.targets) do
                            for _, binding in ipairs(plan.bindings) do
                                material_set_texture(target, binding.slot, binding.texture)
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
            _set_material_traced(unit, mat_slot, mat, "mat_list")
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
-- v0.9.163-dev (#282): read-only session-residency exports are consumed by
-- transition diagnostics and the runtime regression check. There is
-- deliberately no unload export; PackageManager.destroy owns final release.
return {
    replace_textures      = replace_textures,
    add_particles         = add_particles,
    attach_anim_extension = attach_anim_extension,
    session_resident_paths = function() return _mh_lifecycle:held_paths() end,
    reference_summary     = function() return _mh_lifecycle:reference_summary() end,
    loaded_packages       = _mh_loaded_packages,
}
