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
    local function runtime_harness()
        local hooks = {}
        local updates = {}
        local hit_count = 0
        local player = { name = "remote_player" }
        local other_player = { name = "other_remote_player" }
        local proxy = { name = "player_proxy" }
        local enemy = { name = "enemy" }
        local other_enemy = { name = "other_enemy" }
        local blackboards = {
            [enemy] = {
                breed = { name = "skaven_slave" },
                attack_anim = "attack",
            },
            [other_enemy] = {
                breed = { name = "skaven_clan_rat" },
                attack_anim = "attack",
            },
        }
        local status = {
            is_disabled = function() return false end,
            get_is_dodging = function() return false end,
        }
        local owner = {
            bot_player = false,
            peer_id = "remote_peer",
            remote = true,
        }
        local network = {
            is_server = true,
            ping_by_peer = function() return 0.2 end,
        }
        local mod = {
            get = function(_, key)
                if key == "gt_host_lag_comp" then return true end
                if key == "gt_host_lag_comp_max_ms" then return 250 end
                return nil
            end,
            dofile = function()
                return policy
            end,
            hook = function(_, class_name, method_name, wrapper)
                hooks[class_name .. "." .. method_name] = wrapper
            end,
            hook_safe = function(_, class_name, method_name, wrapper)
                hooks[class_name .. "." .. method_name] = wrapper
            end,
            command = function() end,
            echo = function() end,
            _gt_register_update = function(name, update)
                updates[name] = update
            end,
            _gt_rt_register = function() end,
        }
        local env = setmetatable({
            get_mod = function() return mod end,
            Unit = {
                alive = function(unit)
                    return unit ~= nil and unit.alive ~= false
                end,
            },
            ScriptUnit = {
                has_extension = function(unit, extension_name)
                    if unit == player and extension_name == "status_system" then
                        return status
                    end
                    return nil
                end,
            },
            Network = {
                peer_id = function() return "host_peer" end,
            },
            DamageUtils = {
                check_block = function() return false end,
            },
            AiUtils = {},
            BLACKBOARDS = blackboards,
            Managers = {
                player = {
                    owner = function(_, unit)
                        if unit == player then return owner end
                        return nil
                    end,
                },
                state = {
                    network = network,
                },
            },
            printf = function() end,
        }, { __index = _G })

        local chunk = assert(loadfile(root .. "_gt_host_lag_comp.lua"))
        setfenv(chunk, env)
        chunk()

        local hit_hook = assert(
            hooks["BTMeleeOverlapAttackAction.hit_player"]
        )
        local stagger_hook = assert(hooks["AiUtils.stagger"])
        local update = assert(updates.host_lag_comp)
        local action = {
            damage = 10,
            fatigue_type = "blocked",
            attack_directions = {
                attack = "left",
            },
        }

        return {
            player = player,
            other_player = other_player,
            proxy = proxy,
            enemy = enemy,
            other_enemy = other_enemy,
            blackboards = blackboards,
            queue = function(attacking_enemy)
                local unit = attacking_enemy or enemy
                hit_hook(
                    function()
                        hit_count = hit_count + 1
                    end,
                    {},
                    unit,
                    blackboards[unit],
                    player,
                    action,
                    {}
                )
            end,
            accept_stagger = function(staggered_enemy, source)
                local bb = blackboards[staggered_enemy]
                stagger_hook(
                    function()
                        bb.stagger = (bb.stagger or 0) + 1
                    end,
                    staggered_enemy,
                    bb,
                    source
                )
            end,
            reject_stagger = function(staggered_enemy, source)
                stagger_hook(
                    function() end,
                    staggered_enemy,
                    blackboards[staggered_enemy],
                    source
                )
            end,
            advance = function(dt)
                update(dt or 1)
            end,
            hits = function()
                return hit_count
            end,
        }
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

    H.test("GT lag compensation cancels only an accepted exact-pair stagger", function()
        local harness = runtime_harness()
        harness.queue(harness.enemy)
        harness.accept_stagger(harness.enemy, harness.player)
        harness.advance()
        H.equal(0, harness.hits())
    end)

    H.test("GT lag compensation ignores unrelated enemy and player staggers", function()
        local different_enemy = runtime_harness()
        different_enemy.queue(different_enemy.enemy)
        different_enemy.accept_stagger(
            different_enemy.other_enemy,
            different_enemy.player
        )
        different_enemy.advance()
        H.equal(1, different_enemy.hits())

        local different_player = runtime_harness()
        different_player.queue(different_player.enemy)
        different_player.accept_stagger(
            different_player.enemy,
            different_player.other_player
        )
        different_player.advance()
        H.equal(1, different_player.hits())
    end)

    H.test("GT lag compensation ignores rejected and preexisting staggers", function()
        local rejected = runtime_harness()
        rejected.queue(rejected.enemy)
        rejected.reject_stagger(rejected.enemy, rejected.player)
        rejected.advance()
        H.equal(1, rejected.hits())

        local preexisting = runtime_harness()
        preexisting.accept_stagger(preexisting.enemy, preexisting.player)
        preexisting.queue(preexisting.enemy)
        preexisting.advance()
        H.equal(1, preexisting.hits())
    end)

    H.test("GT lag compensation cannot cancel an already applied hit", function()
        local harness = runtime_harness()
        harness.queue(harness.enemy)
        harness.advance()
        H.equal(1, harness.hits())

        harness.accept_stagger(harness.enemy, harness.player)
        harness.advance()
        H.equal(1, harness.hits())
    end)

    H.test("GT lag compensation does not infer proxy ownership", function()
        local harness = runtime_harness()
        harness.queue(harness.enemy)
        harness.accept_stagger(harness.enemy, harness.proxy)
        harness.advance()
        H.equal(1, harness.hits())
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
