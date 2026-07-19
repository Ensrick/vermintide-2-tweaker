-- Runtime owner for CIM's Athanor preview-placement correction (#404).
-- The position decision remains engine-free in _cim_forge_preview_policy.lua;
-- this module owns only the VMF hook and Stingray unit update seam.
local M = {}

function M.install(deps)
    if type(deps) ~= "table" or type(deps.mod) ~= "table"
            or type(deps.mod.hook) ~= "function"
            or type(deps.policy) ~= "table"
            or type(deps.policy.properties_preview_position) ~= "function"
            or type(deps.is_active) ~= "function"
            or type(deps.unit_api) ~= "table"
            or deps.vector3 == nil
            or deps.vector3_box == nil
            or type(deps.printf) ~= "function" then
        return false, "dependencies_unavailable"
    end

    deps.mod:hook("HeroWindowWeaveProperties", "_create_item_previewer",
        function(func, self, viewport_widget, item)
            local previewer = func(self, viewport_widget, item)
            if not deps.is_active() or not previewer then return previewer end

            local data = item and item.data
            local native_position = previewer._spawn_position
            local target = deps.policy.properties_preview_position(
                data and data.slot_type, native_position)
            if not target then return previewer end

            local link_unit = previewer._link_unit
            if not (link_unit and deps.unit_api.alive(link_unit)) then return previewer end

            local current = deps.unit_api.world_position(link_unit, 0)
            local dx = target[1] - (native_position[1] or target[1])
            local dy = target[2] - (native_position[2] or target[2])
            local dz = target[3] - (native_position[3] or target[3])
            -- Stingray exposes Vector3/Vector3Box as callable tables in retail,
            -- not ordinary Lua functions. Validate by calling them, and make no
            -- preview state writes if either constructor is unavailable.
            local vector_ok, delta = pcall(deps.vector3, dx, dy, dz)
            if not vector_ok or delta == nil then
                deps.printf("[cim:404] ranged preview correction skipped key=%s reason=vector3_constructor",
                    tostring((data and data.key) or (item and item.key) or "<?>"))
                return previewer
            end
            local adjusted = current + delta
            local box_ok, adjusted_box = pcall(deps.vector3_box, adjusted)
            if not box_ok or adjusted_box == nil then
                deps.printf("[cim:404] ranged preview correction skipped key=%s reason=vector3_box_constructor",
                    tostring((data and data.key) or (item and item.key) or "<?>"))
                return previewer
            end

            deps.unit_api.set_local_position(link_unit, 0, adjusted)
            previewer._spawn_position = target
            previewer._unit_start_position_boxed = adjusted_box
            deps.printf(
                "[cim:404] ranged properties preview centered key=%s native_x=%.3f target_x=%.3f",
                tostring((data and data.key) or (item and item.key) or "<?>"),
                tonumber(native_position[1]) or 0, target[1])

            return previewer
        end)

    return true
end

function M.install_runtime(mod, policy, is_active)
    return M.install({
        mod = mod,
        policy = policy,
        is_active = is_active,
        unit_api = Unit,
        vector3 = Vector3,
        vector3_box = Vector3Box,
        printf = printf,
    })
end

return M
