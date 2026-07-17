-- Fail-closed bridge from CWV's exact remote appearance identity to
-- Cosmetics' dual-offhand compatibility validator (#583/#660).
--
-- Vanilla husk equipment deliberately carries the stable base item. A CWV
-- Dual Axes wearer therefore arrives here as `dr_dual_axes`, whose native
-- cosmetic pool cannot validate Saltzpyre/Kruber CWV axe meshes. CWV already
-- owns a fingerprint-validated, per-peer/per-slot descriptor. Consume that
-- semantic identity when available; never infer a CWV family from a unit path.
local M = { SCHEMA = 1 }

local function nonempty(value)
    return type(value) == "string" and value ~= "" and value or nil
end

function M.resolve_item_type(args)
    args = args or {}
    local fallback = nonempty(args.base_item_type)
    local provider = args.provider
    if type(provider) ~= "table" or provider.schema ~= M.SCHEMA
            or type(provider.resolve_peer) ~= "function" then
        return fallback, "provider_unavailable"
    end

    local ok, descriptor, state = pcall(provider.resolve_peer,
        args.wearer_peer, args.slot_name, args.base_item_key)
    if not ok then return fallback, "provider_error" end
    if state ~= "exact" or type(descriptor) ~= "table" then
        return fallback, state or "identity_unavailable"
    end

    local variant_key = nonempty(descriptor.variant_key)
    if descriptor.provider ~= "cwv" or not variant_key
            or descriptor.base_item_key ~= args.base_item_key then
        return fallback, "descriptor_mismatch"
    end
    if type(args.allowed_item_types) ~= "table"
            or args.allowed_item_types[variant_key] ~= true then
        return fallback, "unregistered_variant"
    end
    return variant_key, "exact"
end

function M.resolve_husk(base_item_type, cwv_mod, husk_wield, item_data, allowed_item_types)
    husk_wield = husk_wield or {}
    item_data = item_data or {}
    return M.resolve_item_type({
        base_item_type = base_item_type,
        provider = cwv_mod and cwv_mod._cwv_peer_appearance,
        wearer_peer = husk_wield.wearer_peer,
        slot_name = husk_wield.slot_name,
        base_item_key = item_data.name,
        allowed_item_types = allowed_item_types,
    })
end

return M
