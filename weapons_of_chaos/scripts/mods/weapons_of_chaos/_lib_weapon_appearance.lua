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
        matrix4x4 = rawget(_G, "Matrix4x4"),
    }
end

local function _triplet(value)
    return type(value) == "table"
        and type(value[1]) == "number"
        and type(value[2]) == "number"
        and type(value[3]) == "number"
end

local function _bounded_error(value)
    local text = tostring(value or "unknown-error"):gsub("[%c]+", " ")
    return #text > 160 and text:sub(1, 160) or text
end

function M.new(injected)
    local api = injected or _default_api()
    local unit_api = api.unit
    local vector_new = api.vector_new
    local vector_to_elements = api.vector_to_elements
    local quaternion = api.quaternion
    local matrix4x4 = api.matrix4x4
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

    local function transform_node(spec_or_node)
        local node = type(spec_or_node) == "table" and spec_or_node.node
            or spec_or_node
        if type(node) == "number" and node >= 0 and node == math.floor(node) then
            return node
        end
        return 0
    end

    local function offset_was_applied(unit, node)
        local nodes = offset_applied[unit]
        return type(nodes) == "table" and nodes[node] == true
    end

    local function mark_offset_applied(unit, node)
        local nodes = offset_applied[unit]
        if type(nodes) ~= "table" then
            nodes = {}
            offset_applied[unit] = nodes
        end
        nodes[node] = true
    end

    local function read_channel(method, unit, node)
        if type(method) ~= "function" then return nil end
        local ok, value = pcall(method, unit, node)
        return ok and value or nil
    end

    -- Linked weapon roots are a single local-pose contract. Stingray can accept
    -- an individual set_local_* call while retaining only some channels on that
    -- root, so a three-setter sequence is not atomic evidence. Vanilla itself
    -- restores linked gear through Unit.set_local_pose (GearUtils.restore_scene_graph).
    local function apply_atomic_pose(unit, spec)
        if type(matrix4x4) ~= "table"
                or type(matrix4x4.from_quaternion_position_scale) ~= "function"
                or type(unit_api.set_local_pose) ~= "function" then
            return nil, "atomic-api-unavailable"
        end

        local node = transform_node(spec)

        local position
        if spec.position ~= nil then
            position = vector(spec.position)
            if not position then return false, "invalid-position" end
        else
            position = read_channel(unit_api.local_position, unit, node)
        end
        local offset_pending = spec.position == nil and spec.offset ~= nil
            and not offset_was_applied(unit, node)
        if offset_pending then
            if not _triplet(spec.offset) or not position
                    or type(vector_to_elements) ~= "function"
                    or type(vector_new) ~= "function" then
                return false, "invalid-offset"
            end
            local ok, x, y, z = pcall(vector_to_elements, position)
            if not ok then return false, "offset-read-rejected" end
            ok, position = pcall(vector_new,
                x + spec.offset[1], y + spec.offset[2], z + spec.offset[3])
            if not ok then return false, "offset-build-rejected" end
        end

        local scale
        if spec.scale ~= nil then
            scale = vector(spec.scale)
            if not scale then return false, "invalid-scale" end
        else
            scale = read_channel(unit_api.local_scale, unit, node)
        end
        local rotation
        if spec.rotation ~= nil then
            rotation = quaternion_value(spec.rotation)
            if not rotation then return false, "invalid-rotation" end
        else
            rotation = read_channel(unit_api.local_rotation, unit, node)
        end
        if not position or not scale or not rotation then
            return false, "pose-read-rejected"
        end

        local ok, pose = pcall(
            matrix4x4.from_quaternion_position_scale, rotation, position, scale)
        if not ok or pose == nil then return false, "pose-build-rejected" end
        local write_ok, write_error = pcall(unit_api.set_local_pose, unit, node, pose)
        if write_ok and offset_pending then mark_offset_applied(unit, node) end
        if write_ok then return true, nil end
        return false, _bounded_error(write_error)
    end

    function WA.apply_scale(unit, value, node)
        node = transform_node(node)
        local resolved = vector(value)
        if not resolved or not alive(unit)
                or type(unit_api.set_local_scale) ~= "function" then return false end
        return pcall(unit_api.set_local_scale, unit, node, resolved)
    end

    function WA.apply_offset(unit, value, node)
        node = transform_node(node)
        if not _triplet(value) or not alive(unit) or offset_was_applied(unit, node)
                or type(unit_api.local_position) ~= "function"
                or type(unit_api.set_local_position) ~= "function"
                or type(vector_to_elements) ~= "function"
                or type(vector_new) ~= "function" then return false end
        local ok, current = pcall(unit_api.local_position, unit, node)
        if not ok then return false end
        local elements_ok, x, y, z = pcall(vector_to_elements, current)
        if not elements_ok then return false end
        local target_ok, target = pcall(
            vector_new, x + value[1], y + value[2], z + value[3])
        if not target_ok then return false end
        local applied = pcall(unit_api.set_local_position, unit, node, target)
        if applied then mark_offset_applied(unit, node) end
        return applied
    end

    function WA.apply_position(unit, value, node)
        node = transform_node(node)
        local resolved = vector(value)
        if not resolved or not alive(unit)
                or type(unit_api.set_local_position) ~= "function" then return false end
        return pcall(unit_api.set_local_position, unit, node, resolved)
    end

    function WA.apply_rotation(unit, value, node)
        node = transform_node(node)
        local resolved = quaternion_value(value)
        if not resolved or not alive(unit)
                or type(unit_api.set_local_rotation) ~= "function" then return false end
        return pcall(unit_api.set_local_rotation, unit, node, resolved)
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

    function WA.apply_report(unit, spec)
        local report = {
            ok = false,
            requested = 0,
            channels = {},
            transform_mode = "none",
        }
        if type(spec) ~= "table" or not alive(unit) then return report end
        report.transform_node = transform_node(spec)

        local has_transform = spec.scale ~= nil or spec.position ~= nil
            or spec.offset ~= nil or spec.rotation ~= nil
        if has_transform then
            local requested = {}
            if spec.scale ~= nil then requested[#requested + 1] = "scale" end
            if spec.position ~= nil then requested[#requested + 1] = "position"
            elseif spec.offset ~= nil then requested[#requested + 1] = "offset" end
            if spec.rotation ~= nil then requested[#requested + 1] = "rotation" end
            report.requested = report.requested + #requested

            local atomic, atomic_error = apply_atomic_pose(unit, spec)
            if atomic ~= nil then
                report.transform_mode = "atomic-local-pose"
                report.transform_error = atomic_error
                for _, channel in ipairs(requested) do
                    report.channels[channel] = atomic
                end
            else
                report.transform_mode = "per-channel-fallback"
                local node = report.transform_node
                if spec.scale ~= nil then
                    report.channels.scale = WA.apply_scale(unit, spec.scale, node)
                end
                if spec.position ~= nil then
                    report.channels.position = WA.apply_position(unit, spec.position, node)
                elseif spec.offset ~= nil then
                    -- A previously applied offset is an idempotent success for a
                    -- complete descriptor even though the direct primitive keeps
                    -- its historical false-on-second-call return contract.
                    report.channels.offset = offset_was_applied(unit, node)
                        or WA.apply_offset(unit, spec.offset, node)
                end
                if spec.rotation ~= nil then
                    report.channels.rotation = WA.apply_rotation(unit, spec.rotation, node)
                end
            end
        end

        if spec.textures ~= nil then
            report.requested = report.requested + 1
            local ok, writes = WA.apply_textures(unit, spec.textures)
            report.channels.textures = ok
            report.texture_writes = writes
        end

        local all_ok = report.requested > 0
        for _, ok in pairs(report.channels) do all_ok = all_ok and ok == true end
        report.ok = all_ok
        return report
    end

    function WA.apply(unit, spec)
        local report = WA.apply_report(unit, spec)
        return report.ok, report
    end

    return WA
end

return M
