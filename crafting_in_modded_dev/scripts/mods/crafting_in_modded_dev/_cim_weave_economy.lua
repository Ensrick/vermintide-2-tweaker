-- _cim_weave_economy.lua -- CIM-dev Athanor progression/economy facade.
--
-- Behavior-neutral extraction from the entry. This owner retains the exact
-- BackendInterfaceWeavesPlayFab read-hook order and delegates mutable forge
-- state and property-cap policy through narrow injected functions. Installing
-- twice is a no-op because VMF does not provide singleton hook registration.
local function source_anchor() end

return function(ctx)
    assert(type(ctx) == "table", "CIM weave economy requires context")

    local mod = assert(ctx.mod, "CIM weave economy requires mod")
    mod._cim_weave_economy_source_anchor = source_anchor
    local is_active = assert(ctx.is_active,
        "CIM weave economy requires active-state accessor")
    local bubble_cap = assert(ctx.bubble_cap,
        "CIM weave economy requires bubble-cap resolver")
    local build_zero_mastery_costs = assert(ctx.build_zero_mastery_costs,
        "CIM weave economy requires zero-cost builder")

    local state = mod._cim_weave_economy_state
    if not state then
        state = {}
        mod._cim_weave_economy_state = state
    end
    state.is_active = is_active
    state.bubble_cap = bubble_cap
    state.build_zero_mastery_costs = build_zero_mastery_costs

    if state.installed then
        return false
    end
    state.installed = true
    mod._cim_weave_economy_installed = true

    local function _is_active()
        return state.is_active()
    end

    -- These hooks fake Weaves progression only while CIM owns the Athanor.
    -- Outside that bounded state, each hook preserves its original fallback.
    mod:hook("BackendInterfaceWeavesPlayFab", "get_forge_level", function(func, self)
        if _is_active() then return 999 end
        return func(self)
    end)

    mod:hook("BackendInterfaceWeavesPlayFab", "get_essence", function(func, self)
        if _is_active() then return 999999 end
        return func(self)
    end)

    mod:hook("BackendInterfaceWeavesPlayFab", "get_maximum_essence", function(func, self)
        if _is_active() then return 999999 end
        return func(self)
    end)

    mod:hook("BackendInterfaceWeavesPlayFab", "get_total_essence", function(func, self)
        if _is_active() then return 999999 end
        return func(self)
    end)

    mod:hook("BackendInterfaceWeavesPlayFab", "get_property_required_forge_level", function(func, self, property_name)
        if _is_active() then return 0 end
        return func(self, property_name)
    end)

    mod:hook("BackendInterfaceWeavesPlayFab", "get_property_mastery_costs", function(func, self, property_name)
        if _is_active() then
            -- #costs = cap (`total_uses` in hero_window_weave_properties.lua);
            -- #959: reads PAST the array resolve to 0 - the amulet paint indexes
            -- costs with the GLOBAL per-key use count (up to cap*3 across layers,
            -- :1594-1637) and the old nil aborted the sibling accessory's repaint.
            return state.build_zero_mastery_costs(
                state.bubble_cap(property_name))
        end
        return func(self, property_name)
    end)

    mod:hook("BackendInterfaceWeavesPlayFab", "get_trait_required_forge_level", function(func, self, trait_key)
        if _is_active() then return 0 end
        return func(self, trait_key)
    end)

    -- Issue #71: adventure talents have no Weaves progression entry, so the
    -- native lookup nil-indexes. The active CIM forge mirrors property/trait
    -- guards and treats the talent as already unlocked.
    mod:hook("BackendInterfaceWeavesPlayFab", "get_talent_required_forge_level", function(func, self, talent_name)
        if _is_active() then return 0 end
        return func(self, talent_name)
    end)

    mod:hook("BackendInterfaceWeavesPlayFab", "get_trait_mastery_cost", function(func, self, trait_key)
        if _is_active() then return 0 end
        return func(self, trait_key)
    end)

    mod:hook("BackendInterfaceWeavesPlayFab", "get_talent_mastery_cost", function(func, self, talent_name)
        if _is_active() then return 0 end
        return func(self, talent_name)
    end)

    mod:hook("BackendInterfaceWeavesPlayFab", "get_career_magic_level", function(func, self, career_name)
        if _is_active() then return 999 end
        local ok, result = pcall(func, self, career_name)
        if ok then return result end
        return 0
    end)

    mod:hook("BackendInterfaceWeavesPlayFab", "get_item_magic_level", function(func, self, item_backend_id)
        if _is_active() then return 999 end
        local ok, result = pcall(func, self, item_backend_id)
        if ok then return result end
        return 0
    end)

    mod:hook("BackendInterfaceWeavesPlayFab", "max_magic_level", function(func, self)
        if _is_active() then return 999 end
        return func(self)
    end)

    mod:hook("BackendInterfaceWeavesPlayFab", "forge_magic_level_cap", function(func, self)
        if _is_active() then return 999 end
        return func(self)
    end)

    mod:hook("BackendInterfaceWeavesPlayFab", "magic_item_cost", function(func, self, item_key)
        if _is_active() then return 0 end
        return func(self, item_key)
    end)

    mod:hook("BackendInterfaceWeavesPlayFab", "get_average_power_level", function(func, self, career_name)
        if _is_active() then return 300 end
        local ok, result = pcall(func, self, career_name)
        if ok then return result end
        return 300
    end)

    mod:hook("BackendInterfaceWeavesPlayFab", "magic_item_upgrade_cost", function(func, self, num_levels, item_backend_id)
        if _is_active() then return 0 end
        local ok, result = pcall(func, self, num_levels, item_backend_id)
        if ok then return result end
        return 0
    end)

    mod:hook("BackendInterfaceWeavesPlayFab", "career_upgrade_cost", function(func, self, num_levels, career_name)
        if _is_active() then return 0 end
        local ok, result = pcall(func, self, num_levels, career_name)
        if ok then return result end
        return 0
    end)

    return true
end
