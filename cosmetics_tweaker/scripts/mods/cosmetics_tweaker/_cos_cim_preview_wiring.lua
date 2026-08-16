-- Engine wiring for the engine-free exact CIM preview adapter (#481).
--
-- Keeping this composition out of the size-capped entry makes the resource,
-- identity, and material dependencies explicit without giving the policy
-- module engine globals or hook ownership.

return function(mod, get_mod_fn, get_offhand_options, session_state,
        offhand_selection, resolve_variant, apply_exact, is_unit, la_bridge)
    -- EquipmentAssembly deliberately preserves its first registered callbacks
    -- for the lifetime of the VMF session.  Keep the adapter identity equally
    -- stable across a live mod reload so that those callbacks and the refreshed
    -- PreviewRuntime state cannot split generation records or package leases.
    if type(mod._cos_cim_preview) == "table" then
        return mod._cos_cim_preview
    end
    local adapter = mod:dofile(
        "scripts/mods/cosmetics_tweaker/_cos_cim_preview").new({
        get_mod = get_mod_fn,
        get_application = function() return Application end,
        get_package_manager = function()
            return Managers and Managers.package
        end,
        get_offhand_options = get_offhand_options,
        migrate_selection = session_state.migrate_legacy,
        offhand_selection = offhand_selection,
        instance_policy = mod._la_instance_policy,
        resolve_variant = resolve_variant,
        apply_exact = apply_exact,
        is_unit = is_unit,
        la_bridge = la_bridge,
        now = os.clock,
        log = function(fmt, ...)
            pcall(printf, fmt, ...)
        end,
    })
    mod._cos_cim_preview = adapter
    return adapter
end
