local mod = get_mod("sample_forward_ref_mod")

-- Synthetic test fixture: real forward-ref bug pattern from cosmetics_tweaker
-- v0.7.51 (`_collect_all_guis` defined later than `_check_portrait_materials_ready`).

local function _check_portrait_materials_ready(portrait)
    -- Bug: _collect_all_guis is referenced here but defined later in the file,
    -- WITHOUT a forward declaration. When this function is invoked (deferred,
    -- e.g. on portrait update), Lua resolves the bare name as `_ENV._collect_all_guis`
    -- = nil, crashing with `attempt to call a nil value`.
    local guis = _collect_all_guis()
    return guis and guis[portrait]
end

-- Hook closure that ALSO references the later-defined helper.
mod:hook_safe("Portrait", "update", function(self)
    if _check_portrait_materials_ready(self.key) then
        self:apply()
    end
    -- And this directly:
    local guis = _collect_all_guis()
end)

-- _collect_all_guis defined here, AFTER the references. Lua doesn't hoist
-- locals.
local function _collect_all_guis()
    return {}
end
