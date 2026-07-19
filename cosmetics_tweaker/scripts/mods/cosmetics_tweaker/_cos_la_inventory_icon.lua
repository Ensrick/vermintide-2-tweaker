-- Exact-instance Loremaster inventory icon provider (#883).
-- Keeps policy/diagnostic state out of the root mod chunk. The injected emit
-- function is `printf` in game and a capture spy in regression tests.

local M = {}

function M.new(policy, emit, cap)
    local seen = {}
    local count = 0
    cap = tonumber(cap) or 32

    local provider = {}

    function provider.resolve(item, saved_illusion, saved_offhands,
            backend_to_armoury, backend_to_vanilla, skin_list, ownership)
        local icon, reason, armoury_key, resolved_skin =
            policy.resolve_inventory_icon_detailed(item, saved_illusion,
                saved_offhands, backend_to_armoury, backend_to_vanilla,
                skin_list, ownership)
        local backend_id = type(item) == "table"
            and (item.backend_id or item.ItemInstanceId) or nil
        local saved_left = type(saved_offhands) == "table"
            and saved_offhands.left_hand_unit or nil
        if backend_id and (saved_illusion or type(saved_left) == "table") then
            local selected_key = type(saved_left) == "table"
                and (saved_left.armoury_key or saved_left.la_armoury_key
                    or saved_left.unit_path or saved_left.inventory_icon) or nil
            local key = table.concat({
                tostring(backend_id), tostring(item.skin), tostring(ownership),
                tostring(saved_illusion), tostring(selected_key), tostring(icon),
                tostring(reason),
            }, "|")
            if not seen[key] and count < cap then
                seen[key] = true
                count = count + 1
                if type(emit) == "function" then
                    emit("[cos:883] inventory-icon bid=%s ownership=%s exact_skin=%s selected=%s result=%s icon=%s armoury=%s resolved_skin=%s",
                        tostring(backend_id), tostring(ownership or "compat"),
                        tostring(item.skin), tostring(selected_key or saved_illusion),
                        tostring(reason), tostring(icon), tostring(armoury_key),
                        tostring(resolved_skin))
                end
            end
        end
        return icon
    end

    return provider
end

return M
