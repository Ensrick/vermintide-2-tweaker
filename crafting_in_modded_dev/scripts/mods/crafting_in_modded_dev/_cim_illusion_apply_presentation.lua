-- Compatibility facade: one canonical owner is shared with Cosmetics.
-- Keep this private load path stable for the CIM composition root.
local mod = assert(get_mod("cim_dev"), "CIM Dev mod unavailable")
local Shared = mod:dofile("scripts/mods/crafting_in_modded_dev/_lib_local_illusion_apply")
local M = { VERSION = Shared.VERSION, SCHEMA = Shared.SCHEMA, new = Shared.new }

-- Register and advertise one complete owner. The caller invokes this only
-- after the rest of illusion_swap.lua has loaded, and publication follows
-- both hook registrations plus the named runtime check. A raised registration
-- error can therefore leave a partial VMF hook, but never a false capability
-- that tells Cosmetics to yield to it.
function M.install(mod, owner, register_check)
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

    mod:hook("HeroWindowItemCustomization", "_enable_craft_button", owner.on_enable)
    mod:hook("HeroWindowItemCustomization", "_on_illusion_index_pressed", owner.on_pressed)
    register_check("issue1465_illusion_apply_presentation", owner.runtime_check)

    local provider = {
        schema = M.SCHEMA,
        owns_illusion_swap = owner.owns_illusion_swap,
        presentation_owner = owner,
    }
    mod._cim_illusion_apply_presentation_owner = owner
    mod._cim_illusion_swap_provider = provider
    return provider
end

return M
