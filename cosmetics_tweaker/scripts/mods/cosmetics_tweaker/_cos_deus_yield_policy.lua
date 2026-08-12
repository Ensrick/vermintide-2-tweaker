-- _cos_deus_yield_policy.lua - Chaos Wastes weapon-cosmetic precedence.
--
-- Deus-generated mission weapons own their rolled skin. Keep-instance LA and
-- authored weapon-side cosmetics therefore yield only inside an active `deus`
-- mission, never in the Pilgrimage Chamber (`inn_deus`) or route map
-- (`map_deus`). Hats and armor are outside this weapon-only policy.

local DeusYieldPolicy = {}

function DeusYieldPolicy.install(mod, deps)
    deps = deps or {}
    local _get_managers = assert(deps.get_managers, "get_managers is required")
    local _printf = deps.printf

    mod._la_weapon_yield_for_context = function(mechanism_name, game_mode_key)
        return mechanism_name == "deus" and game_mode_key == "deus"
    end

    mod._la_deus_weapon_yield = function()
        local managers = _get_managers()
        local mm = managers and managers.mechanism
        if not (mm and mm.current_mechanism_name) then return false end
        local mechanism_ok, mechanism_name = pcall(mm.current_mechanism_name, mm)
        if not mechanism_ok or mechanism_name ~= "deus" then return false end

        local game_mode_key
        local gm = managers and managers.state and managers.state.game_mode
        if gm and gm.game_mode_key then
            local ok, value = pcall(gm.game_mode_key, gm)
            if ok then game_mode_key = value end
        end
        local lth = managers and managers.level_transition_handler
        if not game_mode_key and lth and lth.get_current_game_mode then
            local ok, value = pcall(lth.get_current_game_mode, lth)
            if ok then game_mode_key = value end
        end
        if not game_mode_key and lth and lth.get_current_level_key then
            local ok, level_key = pcall(lth.get_current_level_key, lth)
            if ok and level_key == "morris_hub" then
                game_mode_key = "inn_deus"
            elseif ok and level_key == "dlc_morris_map" then
                game_mode_key = "map_deus"
            elseif ok and level_key then
                game_mode_key = "deus"
            end
        end

        local should_yield = mod._la_weapon_yield_for_context(
            mechanism_name, game_mode_key)
        if not should_yield and _printf then
            mod._la_deus_context_seen = mod._la_deus_context_seen or {}
            local seen_key = tostring(mechanism_name) .. "/" .. tostring(game_mode_key)
            if not mod._la_deus_context_seen[seen_key] then
                mod._la_deus_context_seen[seen_key] = true
                _printf("[la-state] DEUS-YIELD bypass mechanism=%s game_mode=%s (LA weapon cosmetics remain live)",
                    tostring(mechanism_name), tostring(game_mode_key))
            end
        end
        return should_yield
    end

    return true
end

return DeusYieldPolicy
