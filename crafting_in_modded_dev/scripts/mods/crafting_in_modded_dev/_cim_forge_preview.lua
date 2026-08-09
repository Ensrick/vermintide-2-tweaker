-- Runtime owner for CIM's Athanor preview-placement correction (#882).
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

    local state = deps.mod._cim_forge_preview_runtime_state
    if not state then
        state = {}
        deps.mod._cim_forge_preview_runtime_state = state
    end
    state.deps = deps

    -- The installed VMF wrapper is a stable dispatcher. Re-executing this
    -- module refreshes both the callback body and its dependencies without
    -- attempting to register the same (Class, method) pair twice.
    state.callback = function(func, self, viewport_widget, item)
        local current = state.deps
        local previewer = func(self, viewport_widget, item)
        if not current.is_active() or not previewer then return previewer end

        local data = item and item.data
        local native_position = previewer._spawn_position
        local target = current.policy.properties_preview_position(
            data and data.slot_type, native_position)
        if not target then return previewer end

        local link_unit = previewer._link_unit
        if not (link_unit and current.unit_api.alive(link_unit)) then return previewer end

        local current_position = current.unit_api.world_position(link_unit, 0)
        local dx = target[1] - (native_position[1] or target[1])
        local dy = target[2] - (native_position[2] or target[2])
        local dz = target[3] - (native_position[3] or target[3])
        -- Stingray exposes Vector3/Vector3Box as callable tables in retail,
        -- not ordinary Lua functions. Validate by calling them, and make no
        -- preview state writes if either constructor is unavailable.
        local vector_ok, delta = pcall(current.vector3, dx, dy, dz)
        if not vector_ok or delta == nil then
            current.printf("[cim:404] ranged preview correction skipped key=%s reason=vector3_constructor",
                tostring((data and data.key) or (item and item.key) or "<?>"))
            return previewer
        end
        local adjusted = current_position + delta
        local box_ok, adjusted_box = pcall(current.vector3_box, adjusted)
        if not box_ok or adjusted_box == nil then
            current.printf("[cim:404] ranged preview correction skipped key=%s reason=vector3_box_constructor",
                tostring((data and data.key) or (item and item.key) or "<?>"))
            return previewer
        end

        current.unit_api.set_local_position(link_unit, 0, adjusted)
        previewer._spawn_position = target
        previewer._unit_start_position_boxed = adjusted_box
        current.printf(
            "[cim:404] ranged properties preview centered key=%s native_x=%.3f target_x=%.3f",
            tostring((data and data.key) or (item and item.key) or "<?>"),
            tonumber(native_position[1]) or 0, target[1])

        return previewer
    end

    if state.installed then return true, "refreshed" end

    deps.mod:hook("HeroWindowWeaveProperties", "_create_item_previewer",
        function(...)
            return state.callback(...)
        end)
    state.installed = true

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
