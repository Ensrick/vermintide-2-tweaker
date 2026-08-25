local function register(Harness, repo_root)
    local core = dofile(repo_root .. "/general_tweaker_dev/scripts/mods/general_tweaker_dev/_gt_diag_chest_pickup_state.lua")

    local function read(path)
        local file = assert(io.open(path, "rb"))
        local source = file:read("*a")
        file:close()
        return source
    end

    local function count_literal(source, needle)
        local count, cursor = 0, 1
        while true do
            local found = source:find(needle, cursor, true)
            if not found then return count end
            count = count + 1
            cursor = found + #needle
        end
    end

    Harness.test("gt chest probe requires one explicit arm", function()
        local state = core.new()
        Harness.equal(core.take_classification(state, "pickup-a"), false)
        Harness.equal(core.record(state, "pickup-a", "available", {}), false)
        core.arm(state)
        Harness.truthy(core.take_classification(state, "pickup-a"))
        Harness.equal(core.take_classification(state, "pickup-a"), false)
    end)

    Harness.test("gt chest probe deduplicates lifecycle phases", function()
        local state = core.new()
        core.arm(state)
        Harness.truthy(core.record(state, "pickup-a", "nav", { result = false }))
        Harness.equal(core.record(state, "pickup-a", "nav", { result = true }), false)
        Harness.truthy(core.record(state, "pickup-a", "loot", { result = true }))
        Harness.equal(state.count, 2)
    end)

    Harness.test("gt chest probe caps records and classifications", function()
        local state = core.new()
        core.arm(state)
        for i = 1, core.MAX_CLASSIFICATIONS do
            Harness.truthy(core.take_classification(state, "pickup-" .. i))
        end
        Harness.equal(core.take_classification(state, "overflow"), false)

        for i = 1, core.MAX_RECORDS do
            Harness.truthy(core.record(state, "pickup-" .. i, "phase", {}))
        end
        Harness.equal(state.armed, false)
        Harness.equal(state.count, core.MAX_RECORDS)
        Harness.equal(core.record(state, "extra", "phase", {}), false)

        local old_path = repo_root
            .. "/general_tweaker_dev/scripts/mods/general_tweaker_dev/_gt_chest_pickup_probe_core.lua"
        local old = io.open(old_path, "rb")
        if old then old:close() end
        Harness.equal(old, nil, "legacy probe path must stay absent")

        local owner_path = repo_root
            .. "/general_tweaker_dev/scripts/mods/general_tweaker_dev/_gt_bot_pickups.lua"
        local owner = read(owner_path)
        local diagnostic_load =
            'mod:dofile("scripts/mods/general_tweaker_dev/_gt_diag_chest_pickup_state")'
        local ale_policy_load =
            'mod:dofile("scripts/mods/general_tweaker_dev/_gt_bot_ale_policy")'
        local state_constructor = "local _gt347_state = _gt347_core.new()"

        Harness.equal(count_literal(owner, diagnostic_load), 1)
        Harness.equal(count_literal(owner, "_gt_chest_pickup_probe_core"), 0)
        Harness.equal(count_literal(owner, state_constructor), 1)
        Harness.equal(count_literal(owner, 'mod:command("gt_chest_pickup_probe"'), 1)
        Harness.equal(count_literal(owner, "_gt347_core.arm(_gt347_state)"), 1)
        Harness.equal(count_literal(owner, "[gt:347] phase=%s "), 1)
        Harness.equal(count_literal(owner,
            "[gt:347] trace complete records=%d classifications=%d"), 1)
        Harness.equal(count_literal(owner,
            "[gt:347] ARMED max_records=%d max_classifications=%d"), 1)
        Harness.equal(count_literal(owner,
            'mod._gt_rt_register("issue347_closed_chest_pickup_diagnostics"'), 1)
        Harness.equal(count_literal(owner,
            'mod:hook("PlayerBotBase", "_find_pickup_position_on_navmesh"'), 1)
        Harness.equal(count_literal(owner,
            'mod:hook(BTConditions, "can_loot"'), 1)
        Harness.equal(count_literal(owner,
            'mod:hook_safe(InteractionDefinitions.pickup_object.server, "stop"'), 1)
        Harness.equal(count_literal(owner,
            'mod:hook_safe(InteractionDefinitions.chest.server, "stop"'), 1)

        local diagnostic_at = assert(owner:find(diagnostic_load, 1, true))
        local ale_policy_at = assert(owner:find(ale_policy_load, diagnostic_at, true))
        local state_at = assert(owner:find(state_constructor, ale_policy_at, true))
        Harness.truthy(diagnostic_at < ale_policy_at and ale_policy_at < state_at)
    end)
end

return register
