-- _gut_spawn_weapon_recovery.lua -- consumer-boundary loadout recovery (#1637).
--
-- A mirror read can observe a backend id that disappears during the following
-- item-interface refresh. SimpleInventoryExtension then consumes nil and aborts
-- while wielding the default melee slot. This adapter is deliberately separate
-- from the already-frozen native-loadouts owner: it runs only after vanilla's
-- BackendUtils.get_loadout_item returned nil, delegates candidate selection to
-- the pure policy, and never writes the modded loadout store.
local M = {}

function M.new(Policy, adventure_mode, mode_store)
    local logged = {}

    return function(career_name, slot_name, is_bot)
        local managers = rawget(_G, "Managers")
        local backend = managers and managers.backend
        local iface = backend and backend._interfaces and backend._interfaces.items
        if not iface or adventure_mode(iface) ~= mode_store then return nil end

        local item, source, backend_id = Policy.recover_missing_weapon({
            native_item = nil,
            mode = mode_store,
            mode_store = mode_store,
            mirror = iface._backend_mirror,
            career_name = career_name,
            slot_name = slot_name,
            is_bot = is_bot,
            get_defaults = function(owner, career)
                return owner:get_default_loadouts(career)
            end,
            resolve = function(id)
                return iface:get_item_from_id(id)
            end,
        })

        if item ~= nil then
            local token = tostring(career_name) .. "\0" .. tostring(slot_name)
                .. "\0" .. tostring(backend_id)
            if not logged[token] then
                logged[token] = true
                local printf_fn = rawget(_G, "printf")
                if type(printf_fn) == "function" then
                    pcall(printf_fn,
                        "[gut:1637] recovered missing spawn weapon career=%s slot=%s bot=%s source=%s backend_id=%s",
                        tostring(career_name), tostring(slot_name), tostring(is_bot),
                        tostring(source), tostring(backend_id))
                end
            end
        end
        return item
    end
end

return M
