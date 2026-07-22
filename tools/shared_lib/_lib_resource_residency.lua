-- _lib_resource_residency.lua -- native-resource preflight contract.
--
-- Issue #749: borrowed preview/renderer worlds can crash below Lua when asked
-- to bind a texture/material/shading environment that is not resident in that
-- render scope. Owned Tweaker resources use the strict helpers and fail closed;
-- global wrappers use the tri-state/filter helpers and preserve unknown
-- vanilla or third-party arguments. This distinction is load-bearing for
-- Pusfume and other mods whose resources Tweaker does not own. -- pusfume-compat-reviewed: unknown global resources pass through unchanged.
--
-- Canonical source: tools/shared_lib/_lib_resource_residency.lua. Consumer
-- copies are synchronized by tools/shared_lib/sync-shared-libs.ps1; never edit
-- a copy locally.

local M = {
    VERSION = 2,
    STATE_RESIDENT = "resident",
    STATE_ABSENT = "absent",
    STATE_UNKNOWN = "unknown",
}

local function log_once(logger, reason, resource_type, path, slot, context)
    if type(logger) == "function" then
        pcall(logger, reason, resource_type, path, slot, context)
    end
end

function M.live_unit(unit, unit_api, logger, context)
    if unit == nil then
        log_once(logger, "missing_unit", "unit", nil, nil, context)
        return false, "missing_unit"
    end
    if type(unit) ~= "userdata" then
        log_once(logger, "malformed_unit", "unit", tostring(unit), nil, context)
        return false, "malformed_unit"
    end
    if type(unit_api) ~= "table" or type(unit_api.alive) ~= "function" then
        log_once(logger, "missing_unit_api", "unit", tostring(unit), nil, context)
        return false, "missing_unit_api"
    end

    local ok, alive = pcall(unit_api.alive, unit)
    if not ok then
        log_once(logger, "unit_alive_error", "unit", tostring(unit), nil, context)
        return false, "unit_alive_error"
    end
    if alive ~= true then
        log_once(logger, "dead_unit", "unit", tostring(unit), nil, context)
        return false, "dead_unit"
    end

    return true, "resident"
end

-- Tri-state global resource probe. `false` means the engine positively proved
-- absence. Missing/throwing probe APIs are `unknown`, not absence: global
-- wrappers must preserve vanilla and third-party inputs in that case.
function M.probe(resource_type, path, application, logger, context)
    if type(resource_type) ~= "string" or resource_type == "" then
        log_once(logger, "malformed_resource_type", resource_type, path, nil, context)
        return M.STATE_UNKNOWN, "malformed_resource_type"
    end
    if type(path) ~= "string" or path == "" then
        log_once(logger, "malformed_path", resource_type, path, nil, context)
        return M.STATE_UNKNOWN, "malformed_path"
    end

    local can_get = application and application.can_get
    if type(can_get) ~= "function" then
        log_once(logger, "missing_can_get", resource_type, path, nil, context)
        return M.STATE_UNKNOWN, "missing_can_get"
    end

    local ok, resident = pcall(can_get, resource_type, path)
    if not ok then
        log_once(logger, "can_get_error", resource_type, path, nil, context)
        return M.STATE_UNKNOWN, "can_get_error"
    end
    if resident == true then return M.STATE_RESIDENT, "resident" end
    if resident == false then
        log_once(logger, "not_resident", resource_type, path, nil, context)
        return M.STATE_ABSENT, "not_resident"
    end

    log_once(logger, "indeterminate_can_get", resource_type, path, nil, context)
    return M.STATE_UNKNOWN, "indeterminate_can_get"
end

-- Strict proof for a Tweaker-owned native call. Unknown is intentionally false.
function M.resource_resident(resource_type, path, application, logger, context)
    local state, reason = M.probe(resource_type, path, application, logger, context)
    return state == M.STATE_RESIDENT, reason
end

function M.material_resident(path, application, logger, context)
    return M.resource_resident("material", path, application, logger, context)
end

function M.shading_environment_resident(path, application, logger, context)
    return M.resource_resident(
        "shading_environment", path, application, logger, context)
end

function M.texture_bind_resident(slot, texture, application, logger, context)
    if type(slot) ~= "string" or slot == "" then
        log_once(logger, "malformed_slot", "texture", texture, slot, context)
        return false, "malformed_slot"
    end
    if type(texture) ~= "string" or texture == "" then
        log_once(logger, "malformed_path", "texture", texture, slot, context)
        return false, "malformed_path"
    end

    local ok, reason = M.resource_resident(
        "texture", texture, application, nil, context)
    if not ok then log_once(logger, reason, "texture", texture, slot, context) end
    return ok, reason
end

-- Atomic texture-set preflight. No native write should start until every slot
-- and texture in the set has passed this proof.
function M.texture_set_resident(bindings, application, logger, context)
    if type(bindings) ~= "table" then
        log_once(logger, "malformed_texture_set", "texture", nil, nil, context)
        return false, "malformed_texture_set", 0
    end

    -- Prove the container shape before probing any resource. Lua 5.1's length
    -- operator is undefined for sparse arrays; accepting a sparse or hybrid
    -- table could silently omit a later binding and defeat atomic preflight.
    local numeric_count, numeric_max, map_count = 0, 0, 0
    for key in pairs(bindings) do
        if type(key) == "number" then
            if key < 1 or key ~= math.floor(key) then
                log_once(logger, "malformed_texture_set", "texture", nil, nil, context)
                return false, "malformed_texture_set", 0
            end
            numeric_count = numeric_count + 1
            if key > numeric_max then numeric_max = key end
        else
            map_count = map_count + 1
        end
    end
    if (numeric_count > 0 and map_count > 0)
            or (numeric_count > 0 and numeric_count ~= numeric_max) then
        log_once(logger, "malformed_texture_set", "texture", nil, nil, context)
        return false, "malformed_texture_set", 0
    end

    local count = 0
    if numeric_count > 0 then
        for i = 1, numeric_max do
            local row = bindings[i]
            if type(row) ~= "table" then
                log_once(logger, "malformed_texture_binding", "texture", nil, nil, context)
                return false, "malformed_texture_binding", count
            end
            local ok, reason = M.texture_bind_resident(
                row.slot, row.texture, application, logger, context)
            if not ok then return false, reason, count end
            count = count + 1
        end
    else
        for slot, texture in pairs(bindings) do
            local ok, reason = M.texture_bind_resident(
                slot, texture, application, logger, context)
            if not ok then return false, reason, count end
            count = count + 1
        end
    end

    if count < 1 then
        log_once(logger, "empty_texture_set", "texture", nil, nil, context)
        return false, "empty_texture_set", 0
    end
    return true, "resident", count
end

-- A globally resident texture is still unsafe when the spawned unit resolved
-- only null material handles (#742). This proves the live unit's complete mesh
-- material closure before Unit.set_texture_for_materials.
function M.unit_materials_resident(unit, unit_api, mesh_api, logger, context)
    if unit == nil then
        log_once(logger, "missing_unit", "unit_material", nil, nil, context)
        return false, "missing_unit", 0
    end
    if type(unit_api) ~= "table" or type(unit_api.alive) ~= "function"
            or type(unit_api.num_meshes) ~= "function"
            or type(unit_api.mesh) ~= "function" then
        log_once(logger, "missing_unit_material_api", "unit_material", nil, nil, context)
        return false, "missing_unit_material_api", 0
    end
    if type(mesh_api) ~= "table" or type(mesh_api.num_materials) ~= "function"
            or type(mesh_api.material) ~= "function" then
        log_once(logger, "missing_mesh_material_api", "unit_material", nil, nil, context)
        return false, "missing_mesh_material_api", 0
    end

    local alive_ok, alive = pcall(unit_api.alive, unit)
    if not alive_ok or alive ~= true then
        local reason = alive_ok and "dead_unit" or "unit_alive_error"
        log_once(logger, reason, "unit_material", nil, nil, context)
        return false, reason, 0
    end
    local count_ok, mesh_count = pcall(unit_api.num_meshes, unit)
    if not count_ok or type(mesh_count) ~= "number" or mesh_count < 1
            or mesh_count ~= math.floor(mesh_count) then
        log_once(logger, "unit_has_no_meshes", "unit_material", nil, nil, context)
        return false, "unit_has_no_meshes", 0
    end

    local total = 0
    for mesh_index = 0, mesh_count - 1 do
        local mesh_ok, mesh = pcall(unit_api.mesh, unit, mesh_index)
        if not mesh_ok or mesh == nil then
            local reason = "mesh_unresolved_" .. tostring(mesh_index)
            log_once(logger, reason, "unit_material", nil, nil, context)
            return false, reason, total
        end
        local materials_ok, material_count = pcall(mesh_api.num_materials, mesh)
        if not materials_ok or type(material_count) ~= "number" or material_count < 1
                or material_count ~= math.floor(material_count) then
            local reason = "mesh_has_no_materials_" .. tostring(mesh_index)
            log_once(logger, reason, "unit_material", nil, nil, context)
            return false, reason, total
        end
        for material_index = 0, material_count - 1 do
            local material_ok, material = pcall(
                mesh_api.material, mesh, material_index)
            if not material_ok or material == nil then
                local reason = string.format(
                    "material_unresolved_%d_%d", mesh_index, material_index)
                log_once(logger, reason, "unit_material", nil, nil, context)
                return false, reason, total
            end
            local text_ok, identity = pcall(tostring, material)
            if not text_ok or identity == nil
                    or identity:find("#ID[00000000]", 1, true) then
                local reason = string.format(
                    "material_null_%d_%d", mesh_index, material_index)
                log_once(logger, reason, "unit_material", nil, nil, context)
                return false, reason, total
            end
            total = total + 1
        end
    end
    if total < 1 then
        log_once(logger, "unit_has_no_materials", "unit_material", nil, nil, context)
        return false, "unit_has_no_materials", 0
    end
    return true, "resident", total
end

-- Exact renderer-local closure proof. Application.can_get is insufficient for
-- Gui.bitmap: UIRenderer bakes a fixed material set into each Gui at creation.
function M.gui_material_resident(renderer, material_name, gui_api, logger, context)
    if type(material_name) ~= "string" or material_name == "" then
        log_once(logger, "malformed_material_name", "gui_material",
            material_name, nil, context)
        return false, "malformed_material_name"
    end
    if type(renderer) ~= "table" or renderer.gui == nil then
        log_once(logger, "missing_renderer_gui", "gui_material",
            material_name, nil, context)
        return false, "missing_renderer_gui"
    end
    if type(gui_api) ~= "table" or type(gui_api.material) ~= "function" then
        log_once(logger, "missing_gui_material_api", "gui_material",
            material_name, nil, context)
        return false, "missing_gui_material_api"
    end
    local ok, material = pcall(gui_api.material, renderer.gui, material_name)
    if not ok then
        log_once(logger, "gui_material_error", "gui_material",
            material_name, nil, context)
        return false, "gui_material_error"
    end
    local identity_ok, identity = false, nil
    if material ~= nil then identity_ok, identity = pcall(tostring, material) end
    if material == nil or not identity_ok or identity == nil
            or identity:find("#ID[00000000]", 1, true) then
        log_once(logger, "gui_material_absent", "gui_material",
            material_name, nil, context)
        return false, "gui_material_absent"
    end
    return true, "resident", material
end

-- Pre-filters a UIRenderer.create argument vector. It drops only material
-- pairs whose absence is positively proved and preserves malformed/unknown
-- inputs byte-for-byte so Tweaker cannot suppress vanilla/Pusfume behavior. -- pusfume-compat-reviewed: docs/CROSS_MOD_ARCHITECTURE.md live matrix applies.
function M.filter_material_pairs(count, args, application, logger, context)
    if type(count) ~= "number" or count < 0 or count ~= math.floor(count)
            or type(args) ~= "table" then
        return nil, 0, { changed = false, dropped = {}, unknown = {} }
    end
    local out, out_count = {}, 0
    local report = { changed = false, dropped = {}, unknown = {} }
    local i = 1
    while i <= count do
        local token = args[i]
        if token == "material" and i < count and type(args[i + 1]) == "string" then
            local path = args[i + 1]
            local state, reason = M.probe("material", path, application, logger, context)
            if state == M.STATE_ABSENT then
                report.changed = true
                report.dropped[#report.dropped + 1] = path
            else
                out_count = out_count + 1; out[out_count] = token
                out_count = out_count + 1; out[out_count] = path
                if state == M.STATE_UNKNOWN then
                    report.unknown[#report.unknown + 1] = { path = path, reason = reason }
                end
            end
            i = i + 2
        else
            out_count = out_count + 1; out[out_count] = token
            i = i + 1
        end
    end
    return out, out_count, report
end

return M
