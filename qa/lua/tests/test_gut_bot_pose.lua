-- Behavioral coverage for GUT #232: the bot-designated victory pose repair.
-- Loads the real production module (_gut_bot_pose.lua) under a fake VMF
-- environment, captures the registered hook callbacks, composes them exactly
-- as the mod framework does (callback(next_fn, <original call args>),
-- mod_shim.lua:108-109), and drives a fake PlayerBot.spawn modeled on
-- player_bot.lua:109/:134-:142 through a fake backend pose lookup
-- (BackendUtils.get_loadout_item, backend_utils.lua:30).
return function(H, repo_root)
    local root = repo_root .. "/gui_tweaker_dev/scripts/mods/gui_tweaker_dev/"
    local Policy = assert(loadfile(root .. "_gut_bot_pose_policy.lua"))()

    H.test("GUT #232 restores is_bot only for pose lookup inside bot spawn", function()
        local value, repaired = Policy.resolve_is_bot(1, "slot_pose", nil)
        H.equal(value, true)
        H.equal(repaired, true)

        value, repaired = Policy.resolve_is_bot(2, "slot_pose", nil)
        H.equal(value, true)
        H.equal(repaired, true)
    end)

    H.test("GUT #232 preserves explicit and non-pose lookups", function()
        local value, repaired = Policy.resolve_is_bot(1, "slot_pose", false)
        H.equal(value, false)
        H.equal(repaired, false)

        value, repaired = Policy.resolve_is_bot(1, "slot_skin", nil)
        H.equal(value, nil)
        H.equal(repaired, false)

        value, repaired = Policy.resolve_is_bot(0, "slot_pose", nil)
        H.equal(value, nil)
        H.equal(repaired, false)
    end)

    -- Build the production environment once per test: fake PlayerBot /
    -- BackendUtils classes, fake VMF mod capturing hooks, then install the
    -- captured callbacks with the framework's composition so calling
    -- PlayerBot.spawn / BackendUtils.get_loadout_item runs the real chain.
    local function load_production()
        local lookups = {}
        local pose_items = {
            [true] = { data = { name = "bot_designated_pose" } },
            ["nil"] = { data = { name = "human_pose" } },
            [false] = { data = { name = "human_pose" } },
        }
        local env
        local BackendUtils = {
            get_loadout_item = function(career_name, slot, is_bot)
                lookups[#lookups + 1] = {
                    career = career_name, slot = slot, is_bot = is_bot,
                }
                if slot == "slot_pose" then
                    return pose_items[is_bot == nil and "nil" or is_bot]
                end
                return { data = { name = slot .. "_item_" .. tostring(is_bot) } }
            end,
        }
        local PlayerBot = {}
        -- Vanilla PlayerBot.spawn model (player_bot.lua:134-142): skin/frame
        -- lookups pass is_bot explicitly; the pose lookup OMITS the argument.
        PlayerBot.spawn = function(self, position, rotation)
            local career_name = self._career_name
            local skin_item = env.BackendUtils.get_loadout_item(career_name, "slot_skin", true)
            local pose_item = env.BackendUtils.get_loadout_item(career_name, "slot_pose")
            self._spawned_pose = pose_item and pose_item.data.name
            self._spawned_skin = skin_item and skin_item.data.name
            return "bot_unit", position
        end

        local infos = {}
        local mod = { hooks = {} }
        function mod:dofile(path)
            return assert(loadfile(repo_root .. "/gui_tweaker_dev/" .. path .. ".lua"))()
        end
        function mod:info(fmt, ...)
            infos[#infos + 1] = string.format(fmt, ...)
        end
        function mod:hook(obj, method, fn)
            -- Framework composition (mod_shim.lua:108-109): the stored method
            -- becomes a wrapper handing the callback the next function in the
            -- chain plus the original call arguments.
            local orig = obj[method]
            self.hooks[method] = fn
            obj[method] = function(...)
                return fn(orig, ...)
            end
        end

        env = setmetatable({
            get_mod = function() return mod end,
            PlayerBot = PlayerBot,
            BackendUtils = BackendUtils,
        }, { __index = _G })
        env._G = env

        local chunk = assert(loadfile(root .. "_gut_bot_pose.lua"))
        setfenv(chunk, env)
        local api = chunk()
        return api, env, lookups, mod, infos
    end

    H.test("GUT #232 production chain repairs the pose lookup inside a bot spawn", function()
        local api, env, lookups = load_production()
        H.equal(type(api.hook_callbacks.spawn), "function")
        H.equal(type(api.hook_callbacks.lookup), "function")

        local bot = { _career_name = "we_waywatcher" }
        local unit, pos = env.PlayerBot.spawn(bot, "pos", "rot")
        H.equal(unit, "bot_unit")
        H.equal(pos, "pos")

        -- The skin lookup kept its explicit flag; the pose lookup arrived at
        -- the backend with is_bot repaired to true.
        H.equal(#lookups, 2)
        H.deep_equal(lookups[1],
            { career = "we_waywatcher", slot = "slot_skin", is_bot = true })
        H.deep_equal(lookups[2],
            { career = "we_waywatcher", slot = "slot_pose", is_bot = true })
        H.equal(bot._spawned_pose, "bot_designated_pose")
        H.equal(bot._spawned_skin, "slot_skin_item_true")
    end)

    H.test("GUT #232 production chain leaves human and explicit lookups alone", function()
        local api, env, lookups = load_production()

        -- Hub/human path: the same 2-arg call OUTSIDE any spawn stays nil.
        local item = env.BackendUtils.get_loadout_item("es_mercenary", "slot_pose")
        H.deep_equal(lookups[1],
            { career = "es_mercenary", slot = "slot_pose", is_bot = nil })
        H.equal(item.data.name, "human_pose")

        -- Explicit false inside a spawn context is preserved.
        api.hook_callbacks.spawn(function()
            env.BackendUtils.get_loadout_item("es_mercenary", "slot_pose", false)
        end, {})
        H.deep_equal(lookups[2],
            { career = "es_mercenary", slot = "slot_pose", is_bot = false })

        -- Non-pose nil lookups inside a spawn context are preserved.
        api.hook_callbacks.spawn(function()
            env.BackendUtils.get_loadout_item("es_mercenary", "slot_frame", nil)
        end, {})
        H.deep_equal(lookups[3],
            { career = "es_mercenary", slot = "slot_frame", is_bot = nil })
    end)

    H.test("GUT #232 production chain survives nesting and error unwind", function()
        local api, env, lookups = load_production()

        -- Nested spawn: repair still active at depth 2.
        api.hook_callbacks.spawn(function()
            api.hook_callbacks.spawn(function()
                env.BackendUtils.get_loadout_item("dr_ranger", "slot_pose")
            end, {})
        end, {})
        H.deep_equal(lookups[1],
            { career = "dr_ranger", slot = "slot_pose", is_bot = true })

        -- After full unwind the human path is untouched.
        env.BackendUtils.get_loadout_item("dr_ranger", "slot_pose")
        H.deep_equal(lookups[2],
            { career = "dr_ranger", slot = "slot_pose", is_bot = nil })

        -- A throwing spawn body propagates its error and restores the depth.
        local ok, err = pcall(function()
            api.hook_callbacks.spawn(function()
                error("spawn exploded")
            end, {})
        end)
        H.equal(ok, false)
        H.truthy(tostring(err):find("spawn exploded", 1, true))
        env.BackendUtils.get_loadout_item("dr_ranger", "slot_pose")
        H.deep_equal(lookups[3],
            { career = "dr_ranger", slot = "slot_pose", is_bot = nil })

        -- A later bot spawn still repairs (depth not corrupted by the throw).
        local bot = { _career_name = "dr_ranger" }
        env.PlayerBot.spawn(bot, "p", "r")
        H.equal(bot._spawned_pose, "bot_designated_pose")
    end)

    H.test("GUT #232 strengthened runtime check passes on the captured chain", function()
        local api = load_production()
        H.equal(api.rt_checks[1].name, "issue232_bot_designated_victory_pose")
        H.equal(api.rt_checks[1].fn(), nil)
        H.equal(api.exec_chain_cases(), nil)
    end)
end
