local mod = get_mod("ct_dev")
local Core = mod:dofile("scripts/mods/chaos_wastes_tweaker_dev/_ct_cot_early_reward_core")

-- Vanilla owns the network state and completion lifecycle. The server alone moves
-- WAITING -> RUNNING in on_server_interact and RUNNING -> OPEN after the terror event
-- disappears. Every peer consumes that replicated RUNNING state plus CT's host-broadcast
-- effective setting; no client writes chest state or completion data.
local function _enabled()
    local get = mod._ct_effective_setting
    return type(get) == "function" and get("cot_open_at_trial_start") == true
end

local function _state(self)
    local ok, value = pcall(self._get_state, self)
    return ok and value or nil
end

local function _available(self)
    return Core.reward_available(_enabled(), _state(self), self._reward_collected)
end

-- Vanilla update first observes replicated RUNNING, starts `cursed_chest_prototype`,
-- triggers all `cursed_chest_running` procs and the start sound, then stores
-- `_prev_state = RUNNING`. Only after that transition do we open presentation once.
mod:hook_safe("DeusCursedChestExtension", "update", function(self)
    self._ct350_state = self._ct350_state or {}
    local network_state = _state(self)
    local action = Core.after_update(self._ct350_state, _enabled(), network_state,
        self._reward_collected)
    if action == "open_presentation" then
        Unit.flow_event(self._unit, "state_OPEN")
        pcall(printf, "[ct:350] early reward opened after authoritative RUNNING transition is_server=%s",
            tostring(self._is_server))
    elseif action == "restore_looted" then
        -- Real OPEN just made a completion marker although this peer already claimed
        -- early. Use the extension's symmetric cleanup and leave final visuals looted.
        if self._objective_unit and self._clear_objective_unit then
            self:_clear_objective_unit()
        end
        Unit.flow_event(self._unit, "state_LOOTED")
        pcall(printf, "[ct:350] actual completion preserved; early claimant restored to LOOTED is_server=%s",
            tostring(self._is_server))
    end
end)

mod:hook("DeusCursedChestExtension", "can_interact", function(func, self, ...)
    local vanilla = func(self, ...)
    if vanilla then return vanilla end
    return _available(self)
end)

mod:hook("DeusCursedChestExtension", "get_interaction_length", function(func, self, ...)
    if _available(self) then return 0 end
    return func(self, ...)
end)

mod:hook("DeusCursedChestExtension", "get_interaction_action", function(func, self, ...)
    if _available(self) then return "deus_cursed_chest_get_reward_hud_desc" end
    local cost_action = mod._ct_cot_cost_action_key
    if type(cost_action) == "function" then
        local key = cost_action(self)
        if key then return key end
    end
    return func(self, ...)
end)

mod:hook("DeusCursedChestExtension", "on_client_interact", function(func, self,
        world, interactor_unit, interactable_unit, data, config, t, result)
    if not _available(self) then
        return func(self, world, interactor_unit, interactable_unit, data, config, t, result)
    end
    -- Exact vanilla OPEN reward path, made reachable while authoritative state is RUNNING.
    Managers.ui:handle_transition("deus_cursed_chest", {
        interactable_unit = interactable_unit,
    })
    local inventory_extension = ScriptUnit.extension(interactor_unit, "inventory_system")
    inventory_extension:check_and_drop_pickups("deus_cursed_chest")
end)

return { core = Core, rt_checks = Core.rt_checks }
