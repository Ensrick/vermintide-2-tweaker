local mod = get_mod("ct_dev")
local Policy = mod:dofile("scripts/mods/chaos_wastes_tweaker_dev/_ct_cot_cost_policy")

-- Issue #63. The stock WAITING -> RUNNING transition is already server-owned and
-- carries the true interactor unit. Gate and debit there: no new RPC and no
-- client-authored buyer identity. The host-effective setting channel supplies
-- both values to every peer for matching interaction text.

local function _effective(name)
    local get = mod._ct_effective_setting
    return type(get) == "function" and get(name) or mod:get(name)
end

local function _enabled()
    return _effective("cot_cost_enabled") == true
end

local function _cost()
    return Policy.sanitize_cost(_effective("cot_cost_amount"))
end

local function _state(self)
    local ok, value = pcall(self._get_state, self)
    return ok and value or nil
end

local function _log_reject(self, peer_id, reason, balance, cost)
    self._ct63_reject_count = self._ct63_reject_count or 0
    if self._ct63_reject_count >= 8 then return end
    local now = os.clock()
    local last = self._ct63_last_reject
    if last and last.peer_id == peer_id and last.reason == reason and now - last.at < 1 then return end
    self._ct63_last_reject = { peer_id = peer_id, reason = reason, at = now }
    self._ct63_reject_count = self._ct63_reject_count + 1
    pcall(printf, "[ct:63] reject peer=%s reason=%s balance=%s cost=%s",
        tostring(peer_id), tostring(reason), tostring(balance), tostring(cost))
end

mod._ct_cot_cost_action_key = function(self)
    if _enabled() and _state(self) == Policy.WAITING then return "ct_cot_cost_action" end
end

mod._ct_cot_cost_action_text = function()
    local cost = _cost()
    local controller_ok, controller = pcall(function()
        local mechanism = Managers.mechanism and Managers.mechanism:game_mechanism()
        return mechanism and mechanism.get_deus_run_controller
            and mechanism:get_deus_run_controller()
    end)
    if controller_ok and controller then
        local peer_ok, peer_id = pcall(controller.get_own_peer_id, controller)
        local balance_ok, balance = false, nil
        if peer_ok then
            balance_ok, balance = pcall(controller.get_player_soft_currency, controller, peer_id)
        end
        if balance_ok and type(balance) == "number" and balance < cost then
            return string.format("Need %d Pilgrim's Coins to activate Chest of Trials", cost)
        end
    end
    return string.format("Activate Chest of Trials (%d Pilgrim's Coins)", cost)
end

mod:hook("DeusCursedChestExtension", "on_server_interact", function(func, self,
        world, interactor_unit, interactable_unit, data, config, t, result)
    if not (Managers.player and Managers.player.is_server) then
        return func(self, world, interactor_unit, interactable_unit, data, config, t, result)
    end
    local before_state = _state(self)
    if not _enabled() or before_state ~= Policy.WAITING then
        return func(self, world, interactor_unit, interactable_unit, data, config, t, result)
    end

    local player_manager = Managers.player
    local player = player_manager and player_manager:owner(interactor_unit)
    local peer_id = player and not player.bot_player and player.peer_id
    local controller = self._deus_run_controller
    local run_state = controller and controller._run_state
    if not peer_id or not run_state or type(run_state.set_player_soft_currency) ~= "function" then
        _log_reject(self, peer_id, "authority_unavailable", nil, _cost())
        return
    end

    local balance_ok, balance = pcall(controller.get_player_soft_currency, controller, peer_id)
    if not balance_ok then
        _log_reject(self, peer_id, "balance_unavailable", nil, _cost())
        return
    end
    local allowed, charge, reason = Policy.activation_plan(true, before_state, balance, _cost())
    if not allowed then
        _log_reject(self, peer_id, reason, balance, _cost())
        return
    end

    -- Reserve before vanilla. If vanilla throws or does not transition, restore
    -- the exact prior balance; only the successful WAITING -> RUNNING edge commits.
    local debit_ok, debit_err = pcall(run_state.set_player_soft_currency,
        run_state, peer_id, 1, balance - charge)
    if not debit_ok then
        _log_reject(self, peer_id, "debit_failed:" .. tostring(debit_err), balance, charge)
        return
    end
    local ok, a, b, c = pcall(func, self, world, interactor_unit, interactable_unit,
        data, config, t, result)
    local after_state = _state(self)
    -- A successful vanilla body necessarily called _set_state(RUNNING); if the
    -- immediate read is temporarily unavailable, keep the reservation rather
    -- than opening a paid chest for free. A readable unchanged state refunds.
    local committed = ok and (after_state == nil
        or Policy.transition_committed(before_state, after_state))
    if not committed then
        local refund_ok, refund_err = pcall(run_state.set_player_soft_currency,
            run_state, peer_id, 1, balance)
        if not refund_ok then
            pcall(printf, "[ct:63] REFUND FAILED peer=%s cost=%d err=%s",
                tostring(peer_id), charge, tostring(refund_err))
        end
        if not ok then error(a, 0) end
        return a, b, c
    end

    if type(controller._add_coin_tracking_entry) == "function" then
        pcall(controller._add_coin_tracking_entry, controller, peer_id, 1,
            -charge, "cursed chest activation")
    end
    pcall(printf, "[ct:63] charged peer=%s cost=%d balance=%d->%d",
        tostring(peer_id), charge, balance, balance - charge)
    return a, b, c
end)

local rt_checks = {
    {
        name = "issue63_cot_cost_transaction",
        fn = function()
            local allow, charge = Policy.activation_plan(true, Policy.WAITING, 100, 100)
            if not allow or charge ~= 100 then return "exact-balance activation rejected" end
            if Policy.activation_plan(true, Policy.WAITING, 99, 100) ~= false then
                return "insufficient balance accepted"
            end
            if not Policy.transition_committed(Policy.WAITING, 2) then
                return "WAITING-to-RUNNING commit not recognized"
            end
        end,
    },
}

return { policy = Policy, rt_checks = rt_checks }
