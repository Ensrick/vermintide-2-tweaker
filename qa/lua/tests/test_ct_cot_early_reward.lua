return function(H, repo_root)
    local root = repo_root
        .. "/chaos_wastes_tweaker_dev/scripts/mods/chaos_wastes_tweaker_dev/"
    local Core = assert(loadfile(root .. "_ct_cot_early_reward_core.lua"))()

    H.test("Chest early reward is opt-in and RUNNING-only", function()
        H.equal(Core.reward_available(true, Core.RUNNING, false), true)
        H.equal(Core.reward_available(false, Core.RUNNING, false), false)
        H.equal(Core.reward_available(true, Core.WAITING, false), false)
        H.equal(Core.reward_available(true, Core.OPEN, false), false)
        H.equal(Core.reward_available(true, Core.RUNNING, true), false)
    end)

    H.test("Chest early presentation and looted restore are one-shot", function()
        local state = {}
        H.equal(Core.after_update(state, true, Core.WAITING, false), nil)
        H.equal(Core.after_update(state, true, Core.RUNNING, false), "open_presentation")
        H.equal(Core.after_update(state, true, Core.RUNNING, false), nil)
        -- Cleanup remains required if the host disables the option after the
        -- early reward was claimed but before vanilla completion.
        H.equal(Core.after_update(state, false, Core.OPEN, true), "restore_looted")
        H.equal(Core.after_update(state, true, Core.OPEN, true), nil)
        H.equal(Core.rt_checks[1].fn(), nil)
    end)

    H.test("Chest early reward hooks do not write completion state", function()
        local file = assert(io.open(root .. "_ct_cot_early_reward.lua", "rb"))
        local source = file:read("*a")
        file:close()
        H.truthy(string.find(source, 'Unit.flow_event(self._unit, "state_OPEN")', 1, true))
        H.truthy(string.find(source, 'Unit.flow_event(self._unit, "state_LOOTED")', 1, true))
        H.equal(string.find(source, "self:_set_state", 1, true), nil)
        H.equal(string.find(source, "record_cursed_chest_purified", 1, true), nil)
        H.equal(string.find(source, "finish_cursed_chest", 1, true), nil)
        for _, method in ipairs({ "update", "can_interact", "get_interaction_length",
                "get_interaction_action", "on_client_interact" }) do
            H.truthy(string.find(source, '"DeusCursedChestExtension", "' .. method .. '"', 1, true))
        end
    end)
end
