return function(H, repo_root)
    local root = repo_root
        .. "/general_tweaker_dev/scripts/mods/general_tweaker_dev/"
    local policy = dofile(root .. "_gt_necro_keep_policy.lua")
    local trace_core = dofile(root .. "_gt_necro_keep_trace_core.lua")

    H.test("GT #659 keep-pet truth table preserves human and bot ownership", function()
        H.equal(policy.should_clear(false, false, true), true)
        H.equal(policy.should_clear(false, true, true), true)
        H.equal(policy.should_clear(true, true, true), true)
        H.equal(policy.should_clear(true, false, true), false)
        H.equal(policy.should_clear(false, true, false), false)
    end)

    H.test("GT #659 reconciles an initialized human extension idempotently", function()
        local extension = {
            _player = { bot_player = false },
            _pets_forbidden_in_level = true,
        }
        local changed, before, after, owner = policy.reconcile(extension, false)
        H.equal(changed, true)
        H.equal(before, true)
        H.equal(after, false)
        H.equal(owner, "human")

        changed, before, after, owner = policy.reconcile(extension, false)
        H.equal(changed, false)
        H.equal(before, false)
        H.equal(after, false)
        H.equal(owner, "human")
    end)

    H.test("GT #659 keeps bot gating and missing-owner behavior fail-closed", function()
        local bot = {
            _player = { bot_player = true },
            _pets_forbidden_in_level = true,
        }
        local changed, before, after, owner = policy.reconcile(bot, false)
        H.equal(changed, false)
        H.equal(before, true)
        H.equal(after, true)
        H.equal(owner, "bot")

        changed, before, after, owner = policy.reconcile(bot, true)
        H.equal(changed, true)
        H.equal(before, true)
        H.equal(after, false)
        H.equal(owner, "bot")

        changed, before, after, owner = policy.reconcile({}, true)
        H.equal(changed, false)
        H.equal(before, nil)
        H.equal(after, nil)
        H.equal(owner, "unknown")
    end)

    H.test("GT #659 owns one hook per passive lifecycle method", function()
        local file = assert(io.open(root .. "_gt_bots_keep.lua", "rb"))
        local source = file:read("*a")
        file:close()
        H.equal(select(2, source:gsub(
            'mod:hook_safe%("PassiveAbilityNecromancerCharges", "_on_talents_changed"', '')), 1)
        H.equal(select(2, source:gsub(
            'mod:hook_safe%("PassiveAbilityNecromancerCharges", "extensions_ready"', '')), 1)
        H.truthy(source:find('_bik_necro_reconcile(self, "extensions_ready")', 1, true))
    end)

    H.test("GT #659 trace is local-human hub only and independently bounded", function()
        H.equal(trace_core.should_trace(true, true, false), true)
        H.equal(trace_core.should_trace(true, true, true), false)
        H.equal(trace_core.should_trace(true, false, false), false)
        H.equal(trace_core.should_trace(false, true, false), false)

        local state = trace_core.new()
        for i = 1, trace_core.LIMITS.target do
            local allowed, count = trace_core.take(state, "target")
            H.equal(allowed, true)
            H.equal(count, i)
        end
        H.equal(trace_core.take(state, "target"), false)

        local allowed, count = trace_core.take(state, "finish")
        H.equal(allowed, true)
        H.equal(count, 1)
        H.equal(trace_core.take(state, "unknown"), false)
    end)

    H.test("GT #659 finish classification mirrors vanilla's three-way spawn gate", function()
        H.equal(trace_core.classify_finish(false, "new_interupting_action", "spawn_summon_area"),
            "target-invalid")
        H.equal(trace_core.classify_finish(true, "action_complete", "spawn_summon_area"),
            "finish-reason")
        H.equal(trace_core.classify_finish(true, "new_interupting_action", "default"),
            "finish-sub-action")
        H.equal(trace_core.classify_finish(true, "new_interupting_action", "spawn_summon_area"),
            "spawn-branch")
    end)

    H.test("GT #659 trace owns each activation-to-spawn hook once", function()
        local file = assert(io.open(root .. "_gt_necro_keep_trace.lua", "rb"))
        local source = file:read("*a")
        file:close()

        local expected = {
            'mod:hook("ActionCareerBWNecromancerRaiseDeadTargeting", "_get_projectile_position"',
            'mod:hook_safe("ActionCareerBWNecromancerRaiseDeadTargeting", "finish"',
            'mod:hook_safe("PassiveAbilityNecromancerCharges", "spawn_pet"',
            'mod:hook("PassiveAbilityNecromancerCharges", "_spawn_pet_server"',
        }
        for _, needle in ipairs(expected) do
            H.equal(select(2, source:gsub(needle:gsub("([^%w])", "%%%1"), "")), 1)
        end
        H.truthy(source:find("[gt:659] phase=%s sample=%d/%d", 1, true))
        H.truthy(source:find("GT_NECRO_KEEP_TRACE_MARKER_659", 1, true))
        H.truthy(source:find("issue659_necromancer_keep_trace_armed", 1, true))
    end)
end
