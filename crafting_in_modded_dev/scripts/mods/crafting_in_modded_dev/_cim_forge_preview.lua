-- Runtime owner for CIM's exact Athanor preview context (#481) and the
-- properties-preview placement correction (#882).
--
-- LootItemUnitPreviewer resolves BackendUtils.get_item_units synchronously
-- INSIDE each window's _create_item_previewer constructor.  A marker attached
-- only to the returned previewer is therefore too late for Cosmetics' unit
-- resolver.  This owner publishes both halves of one contract:
--
--   * a stack-scoped context while the real constructor is executing; and
--   * the same context on the exact returned previewer for later spawn/update.
--
-- All three native Athanor constructors are wrapped.  Nothing is inferred from
-- the item or from the shared LootItemUnitPreviewer class, and wrappers created
-- while CIM's custom forge is inactive remain completely native.
local M = {}

local CONTRACT = "cim_preview_context_v1"
local unpack_values = unpack

local function pack(...)
    return { n = select("#", ...), ... }
end

local function item_identity(item)
    local data = type(item) == "table" and item.data or nil
    local backend_id = type(item) == "table"
        and (item.backend_id or item.ItemInstanceId) or nil
    local skin = type(item) == "table" and item.skin or nil
    if backend_id == "" then backend_id = nil end
    if skin == "" then skin = nil end
    return backend_id,
        type(item) == "table" and (item.key or (data and data.key)) or nil,
        data and data.item_type or nil,
        skin
end

local function new_context(state, constructor, item)
    state.generation = (state.generation or 0) + 1
    local backend_id, item_key, item_type, skin = item_identity(item)
    return {
        contract = CONTRACT,
        surface = "cim_preview",
        provider = "cim_dev",
        constructor = constructor,
        generation = state.generation,
        backend_id = backend_id,
        item_key = item_key,
        item_type = item_type,
        skin = skin,
        exact_backend_identity = backend_id ~= nil,
    }
end

-- Return pcall's packed result (status at index 1).  Keeping the explicit
-- count preserves nil holes in both constructor arguments and return values.
local function invoke_scoped(state, constructor, func, self, ...)
    local args = pack(...)
    if not state.deps.is_active() then
        return pack(true, func(self, unpack_values(args, 1, args.n)))
    end

    local context = new_context(state, constructor, args[2])
    local stack = state.context_stack
    stack[#stack + 1] = context
    local result = pack(pcall(function()
        return func(self, unpack_values(args, 1, args.n))
    end))
    -- Stack cleanup happens before either returning or rethrowing.  A nested
    -- constructor therefore restores its caller's exact context, and an error
    -- can never leave a stale identity visible to a later generic previewer.
    if stack[#stack] == context then
        stack[#stack] = nil
    else
        -- Corruption is fail-closed: clear every scoped context rather than
        -- exposing an identity whose nesting can no longer be proven.
        for index = #stack, 1, -1 do stack[index] = nil end
    end

    if not result[1] then error(result[2], 0) end
    local previewer = result[2]
    if type(previewer) == "table" then
        previewer._cim_preview_context = context
    end
    return result
end

-- The Overview constructor already has the mission-safety/#882 wrapper. That
-- owner calls this public dispatcher so one (Class, method) pair still has one
-- VMF registration. Weapons and Properties are registered by install below.
function M.invoke_constructor(mod, constructor, func, self, ...)
    local state = type(mod) == "table"
        and mod._cim_forge_preview_runtime_state or nil
    if not state or type(state.deps) ~= "table"
            or type(state.deps.is_active) ~= "function" then
        return func(self, ...)
    end
    local result = invoke_scoped(state, constructor, func, self, ...)
    return unpack_values(result, 2, result.n)
end

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
        state = { generation = 0, context_stack = {} }
        deps.mod._cim_forge_preview_runtime_state = state
    end
    state.context_stack = state.context_stack or {}
    state.deps = deps

    deps.mod._cim_preview_context_contract = CONTRACT
    deps.mod._cim_preview_context_current = function()
        local stack = state.context_stack
        return stack[#stack]
    end
    deps.mod._cim_preview_context_for = function(previewer)
        local context = type(previewer) == "table"
            and previewer._cim_preview_context or nil
        if type(context) == "table" and context.contract == CONTRACT
                and context.surface == "cim_preview" then
            return context
        end
        return nil
    end

    -- The installed VMF wrapper is a stable dispatcher. Re-executing this
    -- module refreshes both the callback body and its dependencies without
    -- attempting to register the same (Class, method) pair twice.
    state.properties_callback = function(func, self, viewport_widget, item, ...)
        local current = state.deps
        local result = invoke_scoped(state, "properties", func, self,
            viewport_widget, item, ...)
        local previewer = result[2]
        if not current.is_active() or not previewer then
            return unpack_values(result, 2, result.n)
        end

        local data = item and item.data
        local native_position = previewer._spawn_position
        local target = current.policy.properties_preview_position(
            data and data.slot_type, native_position)
        if not target then return unpack_values(result, 2, result.n) end

        local link_unit = previewer._link_unit
        if not (link_unit and current.unit_api.alive(link_unit)) then
            return unpack_values(result, 2, result.n)
        end

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
            return unpack_values(result, 2, result.n)
        end
        local adjusted = current_position + delta
        local box_ok, adjusted_box = pcall(current.vector3_box, adjusted)
        if not box_ok or adjusted_box == nil then
            current.printf("[cim:404] ranged preview correction skipped key=%s reason=vector3_box_constructor",
                tostring((data and data.key) or (item and item.key) or "<?>"))
            return unpack_values(result, 2, result.n)
        end

        current.unit_api.set_local_position(link_unit, 0, adjusted)
        previewer._spawn_position = target
        previewer._unit_start_position_boxed = adjusted_box
        current.printf(
            "[cim:404] ranged properties preview centered key=%s native_x=%.3f target_x=%.3f",
            tostring((data and data.key) or (item and item.key) or "<?>"),
            tonumber(native_position[1]) or 0, target[1])

        return unpack_values(result, 2, result.n)
    end

    state.weapons_callback = function(func, self, ...)
        local result = invoke_scoped(state, "weapons", func, self, ...)
        return unpack_values(result, 2, result.n)
    end

    if state.installed then return true, "refreshed" end

    deps.mod:hook("HeroWindowWeaveForgeWeapons", "_create_item_previewer",
        function(...)
            return state.weapons_callback(...)
        end)
    deps.mod:hook("HeroWindowWeaveProperties", "_create_item_previewer",
        function(...)
            return state.properties_callback(...)
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
