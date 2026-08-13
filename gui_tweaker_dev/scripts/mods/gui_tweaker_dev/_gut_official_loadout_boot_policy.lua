-- Pure policy for issue #402's official-loadout boot boundary.
-- Kept engine-free so the realm and continuation decisions can be proven under Lua 5.1.

local M = {}

function M.realm_is_modded(backend_realm, eac_untrusted)
    if backend_realm == "modded" then return true end
    if backend_realm == "official" then return false end
    return eac_untrusted == true
end

function M.guard_active(is_modded, characters_data_key, adventure_data_key)
    return is_modded == true and characters_data_key == adventure_data_key
end

function M.decrement_pending(value)
    if type(value) ~= "number" then return 0 end
    return math.max(0, value - 1)
end

function M.fix_continuation(num_items_granted)
    return type(num_items_granted) == "number" and num_items_granted > 0
        and "inventory" or "default_gear"
end

function M.allow_verify_bootstrap(has_official_snapshot)
    return has_official_snapshot ~= true
end

return M
