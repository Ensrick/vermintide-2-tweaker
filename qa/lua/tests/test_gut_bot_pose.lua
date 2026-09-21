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

    H.test("GUT #1637 production lookup recovers only after native weapon miss", function()
        local api, env, lookups, mod = load_production()
        local recoveries = {}
        local fallback = { backend_id = "safe_default", data = { name = "bw_1h_sword" } }
        mod._gut_recover_missing_weapon = function(career, slot, resolved, received, depth)
            recoveries[#recoveries + 1] = {
                career = career, slot = slot, resolved = resolved,
                received = received, depth = depth,
            }
            return fallback
        end

        local item = api.hook_callbacks.lookup(function()
            return nil
        end, "bw_unchained", "slot_melee", false)
        H.equal(item, fallback)
        H.deep_equal(recoveries[1], {
            career = "bw_unchained", slot = "slot_melee", resolved = false,
            received = false, depth = 0,
        })

        -- Inside a bot spawn the recovery sees the resolved flag, the value
        -- vanilla passed and the spawn depth (the #1637 miss line records all three).
        api.hook_callbacks.spawn(function()
            api.hook_callbacks.lookup(function() return nil end, "bw_unchained", "slot_pose", nil)
        end, {})
        H.deep_equal(recoveries[2], {
            career = "bw_unchained", slot = "slot_pose", resolved = true,
            received = nil, depth = 1,
        })

        local native = { backend_id = "still_live" }
        item = api.hook_callbacks.lookup(function()
            return native
        end, "bw_unchained", "slot_ranged", false)
        H.equal(item, native)
        H.equal(#recoveries, 2, "valid native item must bypass recovery")

        mod._gut_recover_missing_weapon = function()
            error("guard fault")
        end
        item = api.hook_callbacks.lookup(function() return nil end,
            "bw_unchained", "slot_melee", false)
        H.equal(item, nil, "recovery errors must preserve vanilla's nil result")
    end)

    H.test("GUT #232 strengthened runtime check passes on the captured chain", function()
        local api, env, lookups, mod = load_production()
        mod._gut_recover_missing_weapon = function() return nil end
        H.equal(api.rt_checks[1].name, "issue232_bot_designated_victory_pose")
        H.equal(api.rt_checks[1].fn(), nil)
        H.equal(api.exec_chain_cases(), nil)
    end)

    -- The #1637 runtime checks run the REAL recovery module against the real
    -- policy, exactly as the entry point wires them in-game, plus a live-shaped
    -- census over fake ItemMasterList / CareerSettings / PROFILES_BY_CAREER_NAMES.
    local function wire_1637(mod, env)
        local Policy = assert(loadfile(root .. "_gut_native_loadout_policy.lua"))()
        -- The recovery module reads its globals through rawget(_G, ...); run it
        -- in the same fake environment as the hook owner (env._G = env).
        local chunk = assert(loadfile(root .. "_gut_spawn_weapon_recovery.lua"))
        setfenv(chunk, env)
        local Recovery = chunk()
        env.LoadoutUtils = { sync_loadout_slot = function() end }
        mod._gut_recover_missing_weapon = Recovery.install(mod, Policy,
            function() return Policy.MODE_STORE end, Policy.MODE_STORE)
        env.ItemMasterList = {
            bw_sword = { slot_type = "melee", rarity = "plentiful", template = "t",
                right_hand_unit = "u", can_wield = { "bw_unchained", "bw_adept" } },
            bw_skullstaff_fireball = { slot_type = "ranged", rarity = "plentiful", template = "t",
                right_hand_unit = "u", can_wield = { "bw_unchained", "bw_adept" } },
            vs_bw_sword = { slot_type = "melee", rarity = "plentiful", template = "t",
                right_hand_unit = "u", can_wield = { "vs_only" } },
        }
        env.CareerSettings = {
            bw_unchained = { item_slot_types_by_slot_name = { slot_melee = { "melee" }, slot_ranged = { "ranged" } } },
            bw_adept = { item_slot_types_by_slot_name = { slot_melee = { "melee" }, slot_ranged = { "ranged" } } },
        }
        local heroes = { affiliation = "heroes" }
        env.PROFILES_BY_CAREER_NAMES = {
            bw_unchained = heroes, bw_adept = heroes,
            empire_soldier_tutorial = { affiliation = "tutorial" },
            vs_only = { affiliation = "dark_pact" },
        }
    end

    H.test("GUT #1637 runtime checks prove the seam, the ordering and the live census", function()
        local api, env, lookups, mod = load_production()
        wire_1637(mod, env)
        H.equal(api.rt_checks[2].name, "issue1637_spawn_weapon_consumer_guard")
        H.equal(api.rt_checks[3].name, "issue1637_spawn_weapon_default_fallback")
        H.deep_equal(api.hero_careers(), { "bw_adept", "bw_unchained" })
        H.equal(mod.hooks.sync_loadout_slot ~= nil, true, "sync guard hook registered by install")
        -- The production modules resolve printf through env (setfenv above):
        -- capture their lines HERE, in the harness, and prove the seam never
        -- touches the global printf (deployed-source authority rule).
        local old_printf = rawget(_G, "printf")
        local lines = {}
        env.printf = function(fmt, ...) lines[#lines + 1] = string.format(fmt, ...) end
        local ledger = mod._gut_spawn_weapon_selftest.ledger
        H.equal(type(ledger), "table")
        H.equal(ledger.miss.count, 0)
        H.equal(api.rt_checks[2].fn(), nil)
        H.equal(rawget(_G, "printf"), old_printf, "the seam proof must not touch the global printf")
        -- The live route ran once through the registered hook with a probe
        -- token of its own, then the ordering proof logged its 12 lines.
        H.equal(ledger.miss.count, 1)
        H.equal(ledger.miss.ok, 1)
        H.equal(ledger.miss.last.ok, true)
        H.equal(ledger.miss.last.fields.career, "gut_rt1637_probe_1")
        H.equal(ledger.miss.last.fields.slot, "slot_melee")
        H.equal(ledger.miss.last.fields.spawn_depth, 0)
        H.truthy(lines[1]:find("^%[gut:1637%] miss career=gut_rt1637_probe_1 slot=slot_melee is_bot=false resolved=false spawn_depth=0 "), lines[1])
        H.equal(#lines, 13)
        H.equal(api.rt_checks[3].fn(), nil)
        -- A second run takes a fresh token, so the dedupe never hides the route.
        lines = {}
        H.equal(api.exec_1637_seam(), nil)
        H.equal(ledger.miss.count, 2)
        H.equal(ledger.miss.last.fields.career, "gut_rt1637_probe_2")
        H.equal(#lines, 13)
        H.equal(api.exec_1637_census(), nil)
        H.equal(type(mod._gut_recover_missing_weapon), "function",
            "seam probe must restore the production recovery")

        -- A route whose pcall cannot run fails the check instead of passing.
        -- A throwing stub, not nil: env falls back to _G, and other suites may
        -- leave an ambient global printf behind.
        env.printf = function() error("printf exploded") end
        local route_err = api.rt_checks[2].fn()
        H.equal(type(route_err), "string")
        H.truthy(route_err:find("live miss route pcall failed", 1, true), route_err)
        H.truthy(route_err:find("printf exploded", 1, true), route_err)
        H.equal(ledger.miss.count, 3)
        H.equal(ledger.miss.ok, 2)
        env.printf = function(fmt, ...) lines[#lines + 1] = string.format(fmt, ...) end
        -- A missing ledger is reported, never silently passed.
        mod._gut_spawn_weapon_selftest.ledger = nil
        H.equal(api.rt_checks[2].fn(), "spawn-weapon route ledger missing")
        mod._gut_spawn_weapon_selftest.ledger = ledger
        env.printf = nil

        -- A career without a wieldable weapon fails the census loudly.
        env.PROFILES_BY_CAREER_NAMES.vs_only = { affiliation = "heroes" }
        local err = api.rt_checks[3].fn()
        H.equal(type(err), "string")
        H.truthy(err:find("no default weapon for vs_only", 1, true), err)
        env.PROFILES_BY_CAREER_NAMES.vs_only = nil

        -- A missing selftest surface is reported, never silently passed.
        mod._gut_spawn_weapon_selftest = nil
        H.equal(api.rt_checks[2].fn(), "spawn-weapon selftest surface missing")
        H.equal(api.rt_checks[3].fn(), "spawn-weapon selftest surface missing")
        mod._gut_recover_missing_weapon = nil
        H.equal(api.rt_checks[2].fn(), "native-loadout recovery owner missing")
        H.equal(api.rt_checks[3].fn(), "native-loadout recovery owner missing")
    end)

    H.test("GUT #1637 production lookup ends on the synthetic career default through the real chain", function()
        local api, env, lookups, mod = load_production()
        wire_1637(mod, env)
        env.Managers = { backend = { _interfaces = { items = {
            _backend_mirror = { _career_loadouts = {}, _career_data = {},
                get_default_loadouts = function() return nil end },
            get_item_from_id = function() return nil end,
            get_all_backend_items = function() return {} end,
        } } } }
        env.BackendUtils.get_loadout_item_id = function() return "vanished_id" end
        local lines = {}
        env.printf = function(fmt, ...) lines[#lines + 1] = string.format(fmt, ...) end
        local ok, item = pcall(api.hook_callbacks.lookup, function() return nil end,
            "bw_unchained", "slot_melee", false)
        env.printf = nil
        H.truthy(ok, tostring(item))
        H.equal(item.key, "bw_sword")
        H.equal(item.backend_id, nil)
        H.equal(item.data, env.ItemMasterList.bw_sword)
        H.truthy(lines[1]:find("^%[gut:1637%] miss career=bw_unchained slot=slot_melee is_bot=false resolved=false spawn_depth=0 mode=store loadout_id=vanished_id id_resolves=false tried=retry:vanished_id=nil,default%-owned:bw_sword=none,default%-synthetic:bw_sword=ok source=career%-default%-synthetic key=bw_sword error=nil$"), lines[1])
        H.truthy(lines[2]:find("recovered missing spawn weapon career=bw_unchained slot=slot_melee bot=false source=career-default-synthetic backend_id=nil key=bw_sword", 1, true))

        -- The sync guard shadows the raw master-list row for that key only.
        local sent
        env.LoadoutUtils.sync_loadout_slot = function(player, slot, item) sent = item end
        local guard = mod.hooks.sync_loadout_slot
        guard(env.LoadoutUtils.sync_loadout_slot, "player", "slot_melee",
            { key = "bw_sword", rarity = "plentiful" })
        H.equal(sent.power_level, 300)
        H.equal(sent.key, "bw_sword")
        local real = { key = "bw_sword", power_level = 120 }
        guard(env.LoadoutUtils.sync_loadout_slot, "player", "slot_melee", real)
        H.equal(sent, real)
    end)
end
