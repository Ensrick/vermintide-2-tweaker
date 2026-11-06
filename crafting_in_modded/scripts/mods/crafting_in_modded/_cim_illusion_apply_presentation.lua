-- Owned by: Dev entry local Apply installation closure (#1465).
-- Consumed via: one ordered entry load/bind; no child dependency loads.
local M = {}
local function pack(...)
    return { n = select("#", ...), ... }
end

function M.bind(mod, Shared)
    assert(type(mod) == "table", "CIM Apply bind requires mod")
    assert(type(Shared) == "table" and type(Shared.new) == "function", "CIM Apply bind requires shared owner")
    local bound_mod = mod
    local schema = Shared.SCHEMA
    local bound = { VERSION = Shared.VERSION, SCHEMA = schema, new = Shared.new }
    local forge_complete, forge_attempt = false, nil

    local function forge_state_handler(func, self, recipe_name, ...)
        local owner = mod._cim_illusion_apply_presentation_owner
        local results
        if owner and type(owner.on_state_update) == "function" then
            results = pack(owner.on_state_update(func, self, recipe_name, ...))
        else
            results = pack(func(self, recipe_name, ...))
        end
        if mod._cim_standard_forge_active and recipe_name ~= "apply_weapon_skin" then
            local btn = self._widgets_by_name and self._widgets_by_name.craft_button
            if btn then
                local has_all = self._has_all_crafting_requirements
                if has_all == nil then has_all = true end
                local force_disable = select(3, ...)
                btn.content.button_hotspot.disable_button = force_disable or not has_all or false
            end
        end
        return unpack(results, 1, results.n)
    end

    -- A handoff is not registration proof: VMF returns nil for success and
    -- nonthrowing rejection. Only private installer completion is certified.
    function bound.install_forge_state()
        local attempt = forge_attempt
        assert(attempt, "Forge state handoff outside active installer")
        attempt.handoffs = attempt.handoffs + 1
        assert(attempt.handoffs == 1, "duplicate Forge state handoff")
        mod:hook("HeroWindowItemCustomization", "_update_state_craft_button", forge_state_handler)
        attempt.handler = forge_state_handler
    end

    -- Keep the original entry pcall evaluation outside this function. Forward
    -- invalid/empty/false tuples exactly; they never complete this prerequisite.
    function bound.install_forge_loaded(...)
        forge_complete = false
        local loaded, install = ...
        if not loaded or type(install) ~= "function" then
            forge_attempt = nil
            return ...
        end
        local attempt = { handoffs = 0 }
        forge_attempt = attempt
        local results = pack(pcall(install, bound))
        forge_complete = rawequal(forge_attempt, attempt) and results[1] == true
            and attempt.handoffs == 1 and rawequal(attempt.handler, forge_state_handler)
        forge_attempt = nil
        return unpack(results, 1, results.n)
    end

    function bound.install_loaded(...)
        local loaded, install = ...
        if loaded and type(install) == "function" then return pcall(install, bound) end
        return ...
    end

    function bound.install(mod, owner, register_check)
        assert(type(mod) == "table" and type(mod.hook) == "function",
            "#1465 Apply owner requires a hook registrar")
        assert(type(owner) == "table"
            and type(owner.on_enable) == "function"
            and type(owner.on_pressed) == "function"
            and type(owner.on_state_update) == "function"
            and type(owner.owns_illusion_swap) == "function"
            and type(owner.runtime_check) == "function",
            "#1465 Apply owner is incomplete")
        assert(type(register_check) == "function",
            "#1465 Apply owner requires a runtime-check registrar")

        assert(rawequal(mod, bound_mod), "#1465 Apply owner belongs to another mod")
        assert(forge_complete, "required Forge installer incomplete")

        mod:hook("HeroWindowItemCustomization", "_enable_craft_button", owner.on_enable)
        mod:hook("HeroWindowItemCustomization", "_on_illusion_index_pressed", owner.on_pressed)
        register_check("issue1465_illusion_apply_presentation", owner.runtime_check)

        local provider = {
            schema = schema,
            owns_illusion_swap = owner.owns_illusion_swap,
            presentation_owner = owner,
        }
        mod._cim_illusion_apply_presentation_owner = owner
        mod._cim_illusion_swap_provider = provider
        return provider
    end

    return bound
end

return M
