-- _cim_keep_forge_interaction.lua -- restore the physical Keep forge in modded.
--
-- Vanilla disables `forge_access` whenever EAC marks the session untrusted.
-- CIM already owns the resulting standard-forge window and every craft write,
-- so this module re-enables only that authored interaction in a live hub. The
-- original predicate and stop callback remain authoritative everywhere else.
--
-- Owned by: crafting_in_modded_dev.lua entry point. Consumed via: mod:dofile.

local M = {}

function M.resolve(original_result, eac_untrusted, in_keep)
    if eac_untrusted == true and in_keep == true then return true end
    return original_result
end

function M.install(mod, interaction_definitions)
    local forge = interaction_definitions and interaction_definitions.forge_access
    local client = forge and forge.client
    if type(client) ~= "table" or type(client.can_interact) ~= "function" then
        return false, "forge_access unavailable"
    end

    local state = mod._cim_keep_forge_interaction_state
    if type(state) ~= "table" then
        state = { original_can_interact = client.can_interact }
        mod._cim_keep_forge_interaction_state = state
    end
    local original = state.original_can_interact
    if type(original) ~= "function" then return false, "original predicate unavailable" end
    if client.can_interact == state.installed_predicate then return true end

    -- Direct predicate replacement, not a VMF hook: InteractionDefinitions is
    -- a data registry. The original is stored once so hot reload never nests
    -- wrappers and official/non-Keep behavior remains byte-for-byte delegated.
    client.can_interact = function(interactor_unit, interactable_unit, data, config)
        local original_result = original(interactor_unit, interactable_unit, data, config)
        local is_modded = false
        if type(mod._cim_is_modded_realm) == "function" then
            local ok, resolved = pcall(mod._cim_is_modded_realm)
            is_modded = ok and resolved == true
        end
        local in_keep = mod._cim_is_in_keep and mod._cim_is_in_keep() == true
        local result = M.resolve(original_result, is_modded, in_keep)
        if result and is_modded and in_keep and not state.reported then
            state.reported = true
            printf("[cim:624] Keep forge interaction enabled; native forge transition retained")
        end
        return result
    end
    state.installed_predicate = client.can_interact
    return true
end

return M
