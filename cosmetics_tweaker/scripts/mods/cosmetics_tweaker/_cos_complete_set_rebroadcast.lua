-- Complete durable local-appearance replay for peer/session-ready edges (#629).
-- Keeps engine access behind injected adapters; the policy owns composition and
-- positive queued/emitted acknowledgement.

local M = {}

function M.new(deps)
    assert(type(deps) == "table" and type(deps.policy) == "table",
        "complete-set rebroadcast requires policy")
    assert(type(deps.local_player) == "function"
        and type(deps.unit_alive) == "function"
        and type(deps.inventory_for) == "function",
        "complete-set rebroadcast requires player/inventory adapters")

    local now = type(deps.now) == "function" and deps.now or os.clock
    local retry_delay = tonumber(deps.retry_delay) or 0.25
    local retry_at = nil

    return function()
        if not deps.pending() then
            retry_at = nil
            return false, "idle"
        end
        local current = now()
        if retry_at and current < retry_at then return false, "backoff" end

        local player = deps.local_player()
        local unit = player and player.player_unit
        if not (unit and deps.unit_alive(unit)) then
            retry_at = current + retry_delay
            return false, "unit"
        end

        local inventory = deps.inventory_for(unit)
        local career_name = deps.career_for(player)
        local saved_offhands = deps.saved_offhands()
        local selections = deps.offhand_selection()
        local slots = inventory and inventory._equipment
            and inventory._equipment.slots
        for _, slot_name in ipairs({ "slot_melee", "slot_ranged" }) do
            local item_data = slots and slots[slot_name]
                and slots[slot_name].item_data
            if item_data and item_data.backend_id then
                deps.migrate_selection(item_data.backend_id)
            end
        end

        local snapshot, reason = deps.policy.compose_local_snapshot({
            unit = unit,
            inventory = inventory,
            career_name = career_name,
            bridge_ready = deps.bridge_ready(),
            loadout_ready = deps.loadout_ready(),
            offhand_restore_ready = deps.offhand_restore_ready(),
            loadout_cache = deps.loadout_cache(),
            backend_to_armoury = deps.backend_to_armoury(),
            saved_offhands = saved_offhands,
            offhand_selection = selections,
        })
        if not snapshot then
            retry_at = current + retry_delay
            return false, reason
        end

        -- Replace only the managed cosmetic slots in one assignment. Weapon
        -- illusion entries in this unit-keyed cache survive unchanged.
        deps.policy.replace_cosmetic_equips(
            deps.equips_by_unit(), unit, deps.loadout_cache(), career_name,
            deps.backend_to_armoury())

        local result = deps.policy.publish_local_snapshot(snapshot, {
            send_la = deps.send_la,
            send_mesh = deps.send_mesh,
            send_custom = deps.send_custom,
            vanilla_fallback = deps.vanilla_fallback,
        })
        if not result.complete then
            retry_at = current + retry_delay
            return false, "publish", result
        end

        retry_at = nil
        deps.clear_pending()
        if result.accepted > 0 then
            deps.log(result.accepted)
        end
        return true, "complete", result
    end
end

return M
