-- _lib_weapon_appearance.lua -- standalone-safe weapon unit appearance primitives.
--
-- Canonical source: tools/shared_lib/_lib_weapon_appearance.lua. Consumer copies
-- are synchronized by tools/shared_lib/sync-shared-libs.ps1; never edit a copy.
-- This library owns transform composition and per-unit texture writes only. It
-- does not infer item identity, hand, perspective, render path, or package state.

local M = {}

local function _default_api()
    local vector3 = rawget(_G, "Vector3")
    return {
        unit = rawget(_G, "Unit"),
        vector_new = vector3,
        vector_to_elements = vector3 and vector3.to_elements,
        quaternion = rawget(_G, "Quaternion"),
    }
end

local function _triplet(value)
    return type(value) == "table"
        and type(value[1]) == "number"
        and type(value[2]) == "number"
        and type(value[3]) == "number"
end

function M.new(injected)
    local api = injected or _default_api()
    local unit_api = api.unit
    local vector_new = api.vector_new
    local vector_to_elements = api.vector_to_elements
    local quaternion = api.quaternion
    local offset_applied = setmetatable({}, { __mode = "k" })
    local WA = {}

    local function alive(unit)
        if unit == nil or type(unit_api) ~= "table"
                or type(unit_api.alive) ~= "function" then return false end
        local ok, result = pcall(unit_api.alive, unit)
        return ok and result == true
    end

    local function vector(value)
        if not _triplet(value) or type(vector_new) ~= "function" then return nil end
        local ok, result = pcall(vector_new, value[1], value[2], value[3])
        return ok and result or nil
    end

    local function quaternion_value(value)
        if _triplet(value) and type(quaternion) == "table"
                and type(quaternion.from_euler_angles_xyz) == "function" then
            local ok, result = pcall(
                quaternion.from_euler_angles_xyz, value[1], value[2], value[3])
            return ok and result or nil
        end
        if type(value) == "table" and type(value.unbox) ~= "function" then
            return nil
        end
        local ok, result = pcall(function()
            return value and value.unbox and value:unbox() or value
        end)
        return ok and result or nil
    end

    -- Public for compatibility checks and callers that must validate a saved
    -- rotation before a unit exists. It performs no engine write.
    WA.to_quaternion = quaternion_value

    function WA.apply_scale(unit, value)
        local resolved = vector(value)
        if not resolved or not alive(unit)
                or type(unit_api.set_local_scale) ~= "function" then return false end
        return pcall(unit_api.set_local_scale, unit, 0, resolved)
    end

    function WA.apply_offset(unit, value)
        if not _triplet(value) or not alive(unit) or offset_applied[unit]
                or type(unit_api.local_position) ~= "function"
                or type(unit_api.set_local_position) ~= "function"
                or type(vector_to_elements) ~= "function"
                or type(vector_new) ~= "function" then return false end
        local ok, current = pcall(unit_api.local_position, unit, 0)
        if not ok then return false end
        local elements_ok, x, y, z = pcall(vector_to_elements, current)
        if not elements_ok then return false end
        local target_ok, target = pcall(
            vector_new, x + value[1], y + value[2], z + value[3])
        if not target_ok then return false end
        local applied = pcall(unit_api.set_local_position, unit, 0, target)
        if applied then offset_applied[unit] = true end
        return applied
    end

    function WA.apply_position(unit, value)
        local resolved = vector(value)
        if not resolved or not alive(unit)
                or type(unit_api.set_local_position) ~= "function" then return false end
        return pcall(unit_api.set_local_position, unit, 0, resolved)
    end

    function WA.apply_rotation(unit, value)
        local resolved = quaternion_value(value)
        if not resolved or not alive(unit)
                or type(unit_api.set_local_rotation) ~= "function" then return false end
        return pcall(unit_api.set_local_rotation, unit, 0, resolved)
    end

    -- `textures` accepts either `{ slot = path }` or an ordered array of
    -- `{ slot = "...", texture = "..." }`. Every write is unit-local; the
    -- banned shared-asset primitive Material.set_texture is intentionally absent.
    function WA.apply_textures(unit, textures)
        if not alive(unit) or type(textures) ~= "table"
                or type(unit_api.set_texture_for_materials) ~= "function" then
            return false, 0
        end
        local writes, all_ok = 0, true
        local function apply(slot, texture)
            if type(slot) ~= "string" or type(texture) ~= "string" then
                all_ok = false
                return
            end
            local ok = pcall(unit_api.set_texture_for_materials, unit, slot, texture)
            writes = writes + 1
            all_ok = all_ok and ok
        end
        if #textures > 0 then
            for _, row in ipairs(textures) do
                if type(row) == "table" then apply(row.slot, row.texture)
                else all_ok = false end
            end
        else
            for slot, texture in pairs(textures) do apply(slot, texture) end
        end
        return writes > 0 and all_ok, writes
    end

    function WA.apply(unit, spec)
        if type(spec) ~= "table" or not alive(unit) then return false end
        local attempted = false
        if spec.scale then attempted = WA.apply_scale(unit, spec.scale) or attempted end
        if spec.position then
            attempted = WA.apply_position(unit, spec.position) or attempted
        elseif spec.offset then
            attempted = WA.apply_offset(unit, spec.offset) or attempted
        end
        if spec.rotation then
            attempted = WA.apply_rotation(unit, spec.rotation) or attempted
        end
        if spec.textures then
            local ok = WA.apply_textures(unit, spec.textures)
            attempted = ok or attempted
        end
        return attempted
    end

    return WA
end

return M
