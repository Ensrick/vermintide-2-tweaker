return function(H, repo_root)
    local function read(path)
        local file = assert(io.open(path, "rb"))
        local source = file:read("*a")
        file:close()
        return source
    end

    local root = repo_root .. "/general_tweaker_dev/scripts/mods/general_tweaker_dev/"
    local policy = dofile(root .. "_gt_host_lag_comp_policy.lua")
    local runtime = read(root .. "_gt_host_lag_comp.lua")
    local main = read(root .. "general_tweaker_dev.lua")
    local data = read(root .. "general_tweaker_dev_data.lua")
    local localization = read(root .. "general_tweaker_dev_localization.lua")
    local function near(actual, expected)
        H.truthy(math.abs(actual - expected) < 0.0001,
            "expected " .. tostring(expected) .. ", got " .. tostring(actual))
    end

    H.test("GT host lag compensation is default on and wired once", function()
        H.truthy(data:find('setting_id    = "gt_host_lag_comp"', 1, true))
        H.truthy(data:find("default_value = true", data:find("gt_host_lag_comp", 1, true), true))
        H.truthy(main:find('mod:dofile("scripts/mods/general_tweaker_dev/_gt_host_lag_comp")', 1, true))

        local _, damage_hooks = runtime:gsub('mod:hook%("AiUtils", "damage_target"', "")
        local _, stagger_hooks = runtime:gsub('mod:hook%("AiUtils", "stagger"', "")
        local _, whole_hit_hooks = runtime:gsub(
            'mod:hook%("BTMeleeOverlapAttackAction", "hit_player"', ""
        )
        H.equal(1, damage_hooks)
        H.equal(1, stagger_hooks)
        H.equal(1, whole_hit_hooks)
        local _, block_rpc_hooks = runtime:gsub(
            'mod:hook_safe%("StatusSystem", "rpc_set_blocking"', ""
        )
        local _, dodge_rpc_hooks = runtime:gsub(
            'mod:hook_safe%("StatusSystem", "rpc_status_change_bool"', ""
        )
        H.equal(1, block_rpc_hooks)
        H.equal(1, dodge_rpc_hooks)
        H.truthy(localization:find("Host%-side Melee Latency Compensation"))
    end)

    H.test("GT host lag compensation smooths host ping under a hard cap", function()
        local first, state = policy.smooth_ping_seconds(nil, 0.2, 250)
        near(first, 0.2)
        near(state, 0.2)

        local second = policy.smooth_ping_seconds(state, 0.3, 250)
        -- The raw 300 ms sample is capped to 250 ms before the EMA:
        -- 200 + (250 - 200) * 0.2 = 210 ms.
        near(second, 0.21)

        local capped = policy.smooth_ping_seconds(nil, 5, 9999)
        near(capped, 0.35)
        H.equal(nil, policy.smooth_ping_seconds(nil, -1, 250))
    end)

    H.test("GT host lag compensation eligibility excludes unsafe damage classes", function()
        local base = {
            enabled = true,
            is_server = true,
            target_is_remote_human = true,
            attacker_is_ai = true,
            action_has_fatigue = true,
            action_unblockable = false,
            already_blocked_damage = false,
            target_disabled = false,
        }
        H.truthy(policy.is_eligible(base))

        local keys = {
            "enabled", "is_server", "target_is_remote_human",
            "attacker_is_ai", "action_has_fatigue",
        }
        for _, key in ipairs(keys) do
            local changed = {}
            for k, value in pairs(base) do changed[k] = value end
            changed[key] = false
            H.equal(false, policy.is_eligible(changed), key)
        end

        for _, key in ipairs({
            "action_unblockable", "already_blocked_damage", "target_disabled",
        }) do
            local changed = {}
            for k, value in pairs(base) do changed[k] = value end
            changed[key] = true
            H.equal(false, policy.is_eligible(changed), key)
        end
    end)

    H.test("GT host lag compensation recognizes all authoritative defenses", function()
        local base = {
            target_alive = true,
            attacker_alive = true,
            attacker_staggered_by_target = false,
            target_dodging = false,
            target_blocked = false,
        }
        H.equal(nil, policy.cancel_reason(base))

        local expected = {
            attacker_staggered_by_target = "stagger",
            target_dodging = "dodge",
            target_blocked = "block",
        }
        for key, reason in pairs(expected) do
            local changed = {}
            for k, value in pairs(base) do changed[k] = value end
            changed[key] = true
            H.equal(reason, policy.cancel_reason(changed), key)
        end

        local dead_attacker = {}
        for k, value in pairs(base) do dead_attacker[k] = value end
        dead_attacker.attacker_alive = false
        H.equal("attacker_dead", policy.cancel_reason(dead_attacker))
    end)

    H.test("GT host lag compensation keeps bounded fail-open runtime markers", function()
        H.equal(256, policy.MAX_PENDING)
        H.truthy(runtime:find("#_pending >= Policy.MAX_PENDING", 1, true))
        H.truthy(runtime:find("return func(target_unit, attacker_unit, action, damage, damage_source)", 1, true))
        H.truthy(runtime:find("return _pass_whole_hit(", 1, true))
        H.truthy(runtime:find("_resolving = true", 1, true))
        H.truthy(runtime:find("DamageUtils.check_block(", 1, true))
        H.truthy(runtime:find("whole_hit = true", 1, true))
        H.truthy(runtime:find('_resolve_target_defense(unit, "block")', 1, true))
        H.truthy(runtime:find('_resolve_target_defense(unit, "dodge")', 1, true))
        H.truthy(runtime:find("blackboard.stagger ~= before", 1, true))
        H.truthy(runtime:find("player.peer_id == local_peer", 1, true))
        H.truthy(runtime:find("player.bot_player", 1, true))
        H.truthy(runtime:find("action.fatigue_type", 1, true))
    end)
end
