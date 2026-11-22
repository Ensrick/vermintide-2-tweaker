-- test_rig_api_actor.lua: offline tests of the rig's helper group lib/actor.lua (T.first_bot_unit, T.as_bot,
-- T.pickup) and of T.teleport's position forms (driver 0.4.7), WP-H-06 group "actor input".
--
-- Boots the real bootstrap and driver with the real group in plan.libs inside the simulated game of
-- _rig_driver_env.lua, plus a stub world: one bot whose PlayerBotInput stand-in turns a wield request into a wielded
-- slot on its next update (as _update_actions does, player_bot_input.lua:202-220), a pickup system whose
-- buff_spawn_pickup returns a unit, and a hero locomotion that records teleport_to. This proves the helpers' control
-- flow, cleanup and evidence lines only, never that the game reacts the same way.
return function(H, repo_root)
    local E = assert(loadfile(repo_root .. "/qa/lua/tests/_rig_driver_env.lua"))()(H, repo_root)
    local tag, first, count = E.tag, E.first, E.count

    local function vec(x, y, z)
        return setmetatable({ x = x, y = y, z = z }, {
            __add = function(a, b) return vec(a.x + b.x, a.y + b.y, a.z + b.z) end,
        })
    end

    local function actor_world(env)
        local w = { in_coroutine = {}, calls = {}, spawned = {}, deleted = {}, teleports = {}, hero_pos = vec(10, 20, 30) }
        local function note_call(name)
            w.calls[#w.calls + 1] = name
            if coroutine.running() then
                w.in_coroutine[#w.in_coroutine + 1] = name
            end
        end
        local hero = env.Managers.player:local_player().player_unit
        local bot_unit = { name = "bot 1" }
        w.hero, w.bot_unit = hero, bot_unit
        env.Unit.alive = function(unit)
            return unit == hero or unit == bot_unit or (w.spawned[unit] and not w.deleted[unit]) or false
        end
        env.Unit.local_position = function(unit)
            note_call("Unit.local_position")
            return unit == hero and w.hero_pos or vec(0, 0, 0)
        end
        env.Vector3 = vec
        env.Managers.player.bots = function()
            return { { player_unit = bot_unit } }
        end
        local bot_input = { wielded = "slot_melee" }
        for _, name in ipairs({ "tap_attack", "hold_attack", "defend", "fire", "fire_hold", "charge_shot", "activate_ability",
            "melee_push", "dodge", "interact", "weapon_reload" }) do
            bot_input[name] = function()
                note_call("bot." .. name)
            end
        end
        bot_input.wield = function(self, slot)
            note_call("bot.wield")
            self.wanted = slot
        end
        local bot_inventory = { get_wielded_slot_name = function() return bot_input.wielded end }
        local locomotion = {
            teleport_to = function(_, position)
                note_call("teleport_to")
                w.teleports[#w.teleports + 1] = position
                if type(position) == "table" and position.x then
                    w.hero_pos = vec(position.x, position.y, position.z)
                end
            end,
        }
        env.ScriptUnit = {
            has_extension = function(unit, system)
                if unit == bot_unit and system == "input_system" then
                    return bot_input
                elseif unit == bot_unit and system == "inventory_system" then
                    return bot_inventory
                elseif unit == hero and system == "locomotion_system" then
                    return locomotion
                elseif unit == hero and system == "health_system" then
                    return w.health
                end
            end,
        }
        w.health = { is_invincible = false }
        env.AllPickups = { healing_draught = {}, unloaded_pickup = {} }
        local pickup_system = {
            buff_spawn_pickup = function(_, name, position, raycast_down)
                note_call("buff_spawn_pickup")
                if name == "unloaded_pickup" then
                    return nil
                end
                local unit = { name = "pickup " .. name, at = position, raycast_down = raycast_down }
                w.spawned[unit] = true
                w.last_pickup = unit
                return unit
            end,
            _delete_pickup = function(_, unit)
                note_call("_delete_pickup")
                w.deleted[unit] = true
            end,
        }
        env.Managers.state.entity = { system = function(_, name) return name == "pickup_system" and pickup_system or nil end }
        -- the bot's next update: a wield request becomes the wielded slot
        w.frame = function()
            if bot_input.wanted then
                bot_input.wielded, bot_input.wanted = bot_input.wanted, nil
            end
        end
        return w
    end

    local function run(cases)
        local plan = E.make_plan(cases, { libs = { E.lib_entry("actor") } })
        local object, env, lines = E.boot(plan)
        local w = actor_world(env)
        H.truthy(E.run_to_end(object, env, nil, w.frame), "run completed")
        return lines, w
    end

    H.test("rig T.first_bot_unit / T.as_bot: bot input methods run in the main update, frames repeat them", function()
        local lines, w = run({ { id = "bot", src = [[
return { run = function(T)
    local unit = T.first_bot_unit(5)
    local bot = T.as_bot(unit)
    bot.wield("slot_ranged")
    T.frames(2)
    T.expect_eq(T.ext(unit, "inventory_system"):get_wielded_slot_name(), "slot_ranged", "the wield request reached the bot")
    bot.hold_attack(3)
    bot.tap_attack()
end }
]] } })
        H.truthy(first(lines, tag .. "CASE END id=bot verdict=PASS asserts=1 failed=0"), "bot passes")
        local holds = 0
        for _, name in ipairs(w.calls) do
            if name == "bot.hold_attack" then
                holds = holds + 1
            end
        end
        H.equal(holds, 3, "hold_attack(3) is three updates of input")
        H.truthy(first(lines, tag .. "BOT INPUT id=bot action=wield slot=slot_ranged"), "wield line")
        H.truthy(first(lines, tag .. "BOT INPUT id=bot action=hold_attack frames=3"), "hold line")
        H.equal(table.concat(w.in_coroutine, ","), "", "no bot input ran inside the case coroutine")
    end)

    H.test("rig T.first_bot_unit / T.as_bot: no bot, or a unit without bot input, is INCONCLUSIVE", function()
        local lines = run({
            { id = "hero-as-bot", src = "return { run = function(T) T.as_bot(T.local_hero()) end }" },
        })
        H.truthy(first(lines, tag .. "CASE END id=hero%-as%-bot verdict=INCONCLUSIVE .*extension input_system"), "the hero has no bot input")
        local plan = E.make_plan({ { id = "no-bot", src = "return { run = function(T) T.first_bot_unit(1) end }" } }, { libs = { E.lib_entry("actor") } })
        local object, env, none = E.boot(plan)
        actor_world(env)
        env.Managers.player.bots = function() return {} end
        H.truthy(E.run_to_end(object, env), "run completed")
        H.truthy(first(none, tag .. "CASE END id=no%-bot verdict=INCONCLUSIVE .*a bot is alive"), "no bot")
    end)

    H.test("rig T.pickup: dropped next to the hero from 1 m up, removed at cleanup; unknown or unspawned is INCONCLUSIVE", function()
        local lines, w = run({
            { id = "drop", src = "return { run = function(T) T.expect(T.pickup('healing_draught', { 2, 0, 0 }) ~= nil, 'unit returned') end }" },
            { id = "unknown", src = "return { run = function(T) T.pickup('no_such_pickup') end }" },
            { id = "unloaded", src = "return { run = function(T) T.pickup('unloaded_pickup') end }" },
        })
        H.truthy(first(lines, tag .. "CASE END id=drop verdict=PASS"), "drop passes")
        local unit = w.last_pickup
        H.equal(unit.at.x .. "," .. unit.at.y .. "," .. unit.at.z, "12,20,31", "hero position + offset + 1 m up")
        H.equal(unit.raycast_down, true, "rays down to the floor")
        H.equal(w.deleted[unit], true, "removed at cleanup")
        H.truthy(first(lines, tag .. "CASE END id=unknown verdict=INCONCLUSIVE .*pickup no_such_pickup exists"), "unknown pickup")
        H.truthy(first(lines, tag .. "CASE END id=unloaded verdict=INCONCLUSIVE .*pickup unloaded_pickup spawned"), "nothing spawned")
        H.equal(table.concat(w.in_coroutine, ","), "", "no engine call inside the case coroutine")
    end)

    H.test("rig T.teleport: { x, y, z } and a box become a value in the main update; another value passes through", function()
        local lines, w = run({ { id = "tp", src = [[
return { run = function(T)
    local hero = T.local_hero()
    T.teleport(hero, { 1, 2, 3 })
    T.teleport(hero, { x = 4, y = 5, z = 6 })
    T.teleport(hero, { unbox = function() return "unboxed value" end })
    T.teleport(hero, "a vector value")
end }
]] } })
        H.truthy(first(lines, tag .. "CASE END id=tp verdict=PASS"), "tp passes: " .. tostring(first(lines, tag .. "CASE END id=tp")))
        H.equal(#w.teleports, 4, "four teleports")
        H.equal(w.teleports[1].x .. "," .. w.teleports[1].y .. "," .. w.teleports[1].z, "1,2,3", "list form")
        H.equal(w.teleports[2].x .. "," .. w.teleports[2].y .. "," .. w.teleports[2].z, "4,5,6", "named form")
        H.equal(w.teleports[3], "unboxed value", "a box is unboxed")
        H.equal(w.teleports[4], "a vector value", "a plain value passes through")
        H.equal(table.concat(w.in_coroutine, ","), "", "teleport_to ran in the main update")
        H.equal(count(lines, tag .. "CASE END"), 1, "one case")
    end)

    -- The selftest's mission case against the stub world: catches a script defect before the plan costs a rig run.
    H.test("rig api-selftest case api_actor: passes in the simulated game", function()
        -- run in the keep here: the stub world has no level loader (test_rig_driver.lua covers mission arenas)
        local src = E.read(repo_root .. "/qa/runtime/_rig/api_actor.lua"):gsub('arena = "mission:military"', 'arena = "keep"')
        local lines, w = run({ { id = "api-actor", src = src } })
        H.truthy(first(lines, tag .. "CASE END id=api%-actor verdict=PASS"), "api-actor passes: " .. tostring(first(lines, tag .. "CASE END id=api%-actor")))
        H.equal(w.health.is_invincible, false, "invincibility restored")
        H.equal(w.deleted[w.last_pickup], true, "the draught removed at cleanup")
    end)
end
