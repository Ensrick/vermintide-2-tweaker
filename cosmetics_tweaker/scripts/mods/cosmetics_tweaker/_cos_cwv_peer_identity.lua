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

-- #476: store-read candidates for a husk entry the WEARER emitted under
-- owner-local CWV keys (`entry.weapon_key` = the CWV variant item_type,
-- `entry.template_key` = that variant's template). The observer's husk item
-- is the vanilla BASE, so every candidate derived from it misses both keys.
-- Resolve the wearer's exact variant through the fingerprint-validated
-- provider (same trust anchor as resolve_husk) and return the variant key
-- plus its LOCAL ItemMasterList template. Fails closed to nil - vanilla
-- family candidates only - on any provider, descriptor, or registration
-- doubt, and NEVER surfaces the shared vanilla base template: that key would
-- match a native wielder of the same family (#514 collision class).
function M.husk_variant_candidates(cwv_mod, husk_wield, item_data, item_master_list)
    item_master_list = item_master_list or rawget(_G, "ItemMasterList")
    if type(item_master_list) ~= "table" then return nil, "no_item_master" end
    item_data = item_data or {}
    -- Admission set for resolve_item_type's plain-table membership contract:
    -- exactly "a locally registered cwv_* clone row", resolved per key so it
    -- can never drift from CWV's live catalog the way a static list would.
    local allowed = setmetatable({}, { __index = function(_, key)
        if type(key) ~= "string" or string.sub(key, 1, 4) ~= "cwv_" then
            return nil
        end
        local row = rawget(item_master_list, key)
        return (type(row) == "table" and type(row.template) == "string")
            or nil
    end })
    local variant_key, state = M.resolve_husk(nil, cwv_mod, husk_wield,
        item_data, allowed)
    if state ~= "exact" or not variant_key then return nil, state end
    local row = rawget(item_master_list, variant_key)
    local template = row and row.template
    if template == item_data.template then template = nil end
    return { variant_key = variant_key, template = template }, state
end

return M
