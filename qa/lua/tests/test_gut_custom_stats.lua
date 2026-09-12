return function(H, repo_root)
    -- #1570 friendly-fire damage, #1571 melee/ranged damage, #1572 Permanent
    -- Health Restored: pure ledger/credit policy, the real host adapter hooks
    -- driven through a minimal VMF/engine seam, and the shared presenter.
    local mod_root = repo_root .. "/gui_tweaker_dev/"
    local scripts = mod_root .. "scripts/mods/gui_tweaker_dev/"
    local Policy = assert(loadfile(scripts .. "_gut_custom_stats_policy.lua"))()
    local ScorePolicy = assert(loadfile(scripts .. "_gut_scoreboard_policy.lua"))()

    local function native_topics()
        local names = {
            "kills_elites", "kills_specials", "kills_total", "kills_melee",
            "kills_ranged", "damage_taken", "damage_dealt",
            "damage_dealt_bosses", "headshots", "saves", "revives",
        }
        local topics = {}
        for i, name in ipairs(names) do
            topics[i] = { name = name, display_text = "scoreboard_topic_" .. name, stat_type = name }
        end
        return topics
    end

    H.test("GUT #1570-#1572 ledger validates, caps and saturates credits", function()
        local ledger = Policy.new_ledger()
        H.deep_equal({ Policy.credit(ledger, "peer:1", Policy.FRIENDLY_FIRE, 4.5) },
            { true, 4.5 })
        H.deep_equal({ Policy.credit(ledger, "peer:1", Policy.FRIENDLY_FIRE, 2) },
            { true, 6.5 })
        H.deep_equal({ Policy.credit(ledger, "peer:1", "damage_dealt", 1) },
            { false, "topic" }, "native topics are never custom-credited")
        H.deep_equal({ Policy.credit(ledger, "bad id", Policy.MELEE, 1) },
            { false, "stats-id" })
        for _, amount in ipairs({ 0, -1, 0 / 0, math.huge, Policy.MAX_EVENT + 1 }) do
            H.equal(select(2, Policy.credit(ledger, "peer:1", Policy.MELEE, amount)),
                "amount", "invalid amount " .. tostring(amount))
        end
        for i = 2, Policy.MAX_PLAYERS do
            H.truthy(Policy.credit(ledger, "peer:" .. i, Policy.RANGED, 1))
        end
        H.deep_equal({ Policy.credit(ledger, "late:1", Policy.RANGED, 1) },
            { false, "player-cap" }, "a new row beyond the cap is refused, not evicted")
        H.equal(ledger.overflow, 1)
        ledger.rows["peer:1"][Policy.MELEE] = Policy.MAX_VALUE - 1
        H.deep_equal({ Policy.credit(ledger, "peer:1", Policy.MELEE, 50) },
            { true, Policy.MAX_VALUE }, "totals saturate")
        H.truthy(Policy.forget(ledger, "peer:1"))
        H.equal(ledger.rows["peer:1"], nil)
        H.equal(Policy.forget(ledger, "peer:1"), false)
    end)

    H.test("GUT #1570-#1572 scores give known players real zeros and copy boundedly", function()
        local ledger = Policy.new_ledger()
        Policy.credit(ledger, "a:1", Policy.PERMANENT_HEALTH, 12)
        local players = {}
        for i = 1, 6 do players[i] = { stats_id = i == 1 and "a:1" or ("p:" .. i) } end
        local scores = Policy.scores_for_players(ledger, players, 9)
        local count = 0
        for _ in pairs(scores) do count = count + 1 end
        H.equal(count, 4, "at most four presenter rows")
        H.equal(scores["a:1"][Policy.PERMANENT_HEALTH], 12)
        H.equal(scores["a:1"][Policy.FRIENDLY_FIRE], 0)
        H.equal(scores["p:2"][Policy.MELEE], 0)
        local copy = Policy.copy_scores(scores)
        scores["a:1"][Policy.PERMANENT_HEALTH] = 99
        H.equal(copy["a:1"][Policy.PERMANENT_HEALTH], 12, "sidecar copy is detached")
        H.equal(Policy.copy_scores(nil), nil)
    end)

    H.test("GUT #1570/#1571 damage delta attribution accepts exactly one gain", function()
        local ids = { "a:1", "b:1", "c:1" }
        H.deep_equal({ Policy.plan_damage_credit(ids, { 1, 2, 3 }, { 1, 9.25, 3 }) },
            { "b:1", 7.25 })
        H.deep_equal({ Policy.plan_damage_credit(ids, { 1, 2, 3 }, { 1, 2, 3 }) },
            { nil, "no-credit" })
        H.deep_equal({ Policy.plan_damage_credit(ids, { 1, 2, 3 }, { 2, 3, 3 }) },
            { nil, "ambiguous" })
        H.deep_equal({ Policy.plan_damage_credit(ids, { 5, 2, 3 }, { 4, 2, 3 }) },
            { nil, "amount" })
        H.deep_equal({ Policy.plan_damage_credit(ids, { 1, 2, 3 }, { nil, 2, 3 }) },
            { nil, "no-credit" }, "an unreadable after-value is not a credit")
    end)

    H.test("GUT #1570/#1571 victim classification excludes self and allied non-heroes", function()
        local base = { attacker_id = "a:1" }
        local function kind(extra)
            local facts = {}
            for k, v in pairs(base) do facts[k] = v end
            for k, v in pairs(extra) do facts[k] = v end
            return Policy.damage_kind(facts)
        end
        H.equal(kind({ victim_owner_id = "b:1", victim_is_player_unit = true, same_side = true }),
            "friendly_fire")
        H.equal(kind({ victim_owner_id = "a:1", victim_is_player_unit = true, same_side = true }),
            "self")
        H.equal(kind({ victim_owner_id = "a:1", enemy_side = true }), "self",
            "the attacker's own units are self damage even if flagged enemy")
        H.equal(kind({ enemy_side = true }), "enemy")
        H.equal(kind({ victim_owner_id = "b:1", victim_is_player_unit = false, same_side = true }),
            nil, "allied non-hero units are uncredited")
        H.equal(kind({}), nil)
        H.equal(Policy.damage_kind({ attacker_id = "bad id", enemy_side = true }), nil)
    end)

    H.test("GUT #1571 classifier mirrors statistics_util.lua:227-257", function()
        local sword = { slot_type = "melee", template = "one_handed_swords_template_1" }
        local bow = { slot_type = "ranged", template = "longbow_template_1" }
        H.equal(Policy.classify_attack(sword, "light_attack"), "melee")
        H.equal(Policy.classify_attack(sword, "heavy_attack"), "melee")
        H.equal(Policy.classify_attack(sword, "action_push"), "ranged",
            "any non light/heavy attack type is ranged, exactly as vanilla kills")
        H.equal(Policy.classify_attack(bow, "n/a"), "ranged")
        H.equal(Policy.classify_attack(nil, "light_attack"), nil, "non-item sources stay unclassified")
        H.equal(Policy.classify_attack({ slot_type = "grenade" }, nil), nil)
        H.equal(Policy.classify_attack({ template = "t" }, nil, function() return "melee" end), "melee")
        H.equal(Policy.classify_attack({ template = "t" }, nil, function() error("boom") end), nil)
    end)

    H.test("GUT #1572 permanent-health credit goes to the healer or the healed player", function()
        H.deep_equal({ Policy.plan_heal_credit(40, 65, "medic:1", "hurt:1") }, { "medic:1", 25 })
        H.deep_equal({ Policy.plan_heal_credit(40, 50, nil, "hurt:1") }, { "hurt:1", 10 })
        H.deep_equal({ Policy.plan_heal_credit(40, 40, "medic:1", "hurt:1") }, { nil, "no-gain" })
        H.deep_equal({ Policy.plan_heal_credit(40, 30, "medic:1", "hurt:1") }, { nil, "no-gain" })
        H.deep_equal({ Policy.plan_heal_credit(nil, 30, "medic:1", "hurt:1") }, { nil, "health" })
        H.deep_equal({ Policy.plan_heal_credit(1, 2, nil, nil) }, { nil, "stats-id" })
    end)

    H.test("GUT #1570-#1572 registry stays thirteen rows unless custom rows are passed", function()
        H.equal(#ScorePolicy.build_topic_registry(native_topics()), 13)
        local registry = ScorePolicy.build_topic_registry(native_topics(), Policy.TOPICS)
        H.equal(#registry, 17)
        H.equal(registry[14].name, Policy.FRIENDLY_FIRE)
        H.equal(registry[17].name, Policy.PERMANENT_HEALTH)
        H.equal(registry[17].custom, true)
        local players = {
            host = {
                name = "Host", stats_id = "host",
                group_scores = { offense = { { stat_name = "damage_dealt", score = 80 } } },
            },
        }
        local model = ScorePolicy.build_native_model(players, registry, {
            selected_page = 2,
            custom_scores = {
                host = {
                    [Policy.FRIENDLY_FIRE] = 3, [Policy.MELEE] = 50,
                    damage_dealt = 999, [Policy.RANGED] = -1,
                },
            },
        })
        local scores = model.players[1].scores
        H.equal(model.page_count, 2)
        H.equal(#model.pages[2].topics, 6)
        H.equal(scores[Policy.FRIENDLY_FIRE], 3)
        H.equal(scores[Policy.MELEE], 50)
        H.equal(scores.damage_dealt, 80, "a custom overlay can never replace a native row")
        H.equal(scores[Policy.RANGED], nil, "invalid custom values stay unavailable")
        local client = ScorePolicy.build_native_model(players, registry, { selected_page = 2 })
        H.equal(client.players[1].scores[Policy.FRIENDLY_FIRE], nil,
            "a peer without host scores shows the row unavailable")
    end)

    -- Minimal VMF + engine seam executing the production adapter.
    local GLOBAL_NAMES = {
        "get_mod", "Managers", "DamageDataIndex", "ItemMasterList", "WeaponUtils",
        "MeleeBuffTypes", "RangedBuffTypes", "GameSession", "printf",
    }

    local function with_adapter(body)
        local state = { logs = {}, server = true, mechanism = "adventure", sides = {} }
        local fake_mod = { hooks = {}, settings = {} }
        function fake_mod:dofile(path)
            return assert(loadfile(mod_root .. path .. ".lua"))()
        end
        function fake_mod:hook(class_name, method_name, callback)
            assert(self.hooks[class_name .. "." .. method_name] == nil,
                "duplicate hook " .. class_name .. "." .. method_name)
            self.hooks[class_name .. "." .. method_name] = callback
        end
        function fake_mod:hook_safe(class_name, method_name, callback)
            self:hook(class_name, method_name, callback)
        end
        function fake_mod:get(id) return self.settings[id] end
        fake_mod.registered = {}
        fake_mod._gut_rt_register = function(name) fake_mod.registered[#fake_mod.registered + 1] = name end
        fake_mod._gut_scoreboard_retention = {
            add_listener = function(fn) state.listener = fn; return true end,
        }
        state.prior_state_calls = 0
        fake_mod.on_game_state_changed = function()
            state.prior_state_calls = state.prior_state_calls + 1
        end

        local function player(stats_id, unit)
            return {
                player_unit = unit,
                stats_id = function() return stats_id end,
                unique_id = function() return stats_id end,
            }
        end
        local heroes = {
            alpha = player("alpha:1", "alpha_unit"),
            bravo = player("bravo:1", "bravo_unit"),
        }
        local unit_owner = { alpha_unit = heroes.alpha, bravo_unit = heroes.bravo }
        local database = { stats = { ["alpha:1"] = 0, ["bravo:1"] = 0 }, registered = {
            ["alpha:1"] = true, ["bravo:1"] = true,
        } }
        function database:is_registered(id) return self.registered[id] end
        function database:get_stat(id, name)
            assert(name == "damage_dealt")
            if not self.registered[id] then error("unregistered " .. tostring(id)) end
            return self.stats[id]
        end
        local hero_side, enemy_side = { name = "heroes" }, { name = "dark_pact" }
        local side_by_unit = { alpha_unit = hero_side, bravo_unit = hero_side, rat_unit = enemy_side }
        local health_fields = {}
        local values = {
            get_mod = function(name) return name == "gut_dev" and fake_mod or nil end,
            Managers = {
                player = {
                    is_server = true,
                    players = function() return heroes end,
                    player_from_stats_id = function(_, id)
                        for _, p in pairs(heroes) do if p.stats_id() == id then return p end end
                    end,
                    owner = function(_, unit) return unit_owner[unit] end,
                    is_player_unit = function(_, unit)
                        local owner = unit_owner[unit]
                        return owner ~= nil and owner.player_unit == unit
                    end,
                    statistics_db = function() return database end,
                },
                mechanism = {
                    current_mechanism_name = function() return state.mechanism end,
                },
                state = {
                    side = {
                        side_by_unit = side_by_unit,
                        get_side_from_player_unique_id = function() return hero_side end,
                        is_enemy_by_side = function(_, a, b)
                            return a ~= nil and b ~= nil and a ~= b
                        end,
                    },
                },
            },
            DamageDataIndex = { DAMAGE_SOURCE_NAME = 7, ATTACK_TYPE = 14 },
            ItemMasterList = {
                es_1h_sword = { slot_type = "melee", template = "sword" },
                es_longbow = { slot_type = "ranged", template = "bow" },
            },
            WeaponUtils = { get_weapon_template = function() return nil end },
            MeleeBuffTypes = {},
            RangedBuffTypes = {},
            GameSession = {
                game_object_field = function(_, id, field)
                    assert(field == "current_health")
                    return health_fields[id]
                end,
            },
            printf = function(fmt, ...) state.logs[#state.logs + 1] = string.format(fmt, ...) end,
        }
        local previous = {}
        for _, name in ipairs(GLOBAL_NAMES) do
            previous[name] = rawget(_G, name)
            rawset(_G, name, values[name])
        end
        local ok, err = pcall(function()
            local api = assert(loadfile(scripts .. "_gut_custom_stats.lua"))()
            state.player_manager = values.Managers.player
            body({
                api = api,
                mod = fake_mod,
                state = state,
                database = database,
                heroes = heroes,
                health = health_fields,
                register = assert(fake_mod.hooks["StatisticsUtil.register_damage"]),
                add_heal = assert(fake_mod.hooks["PlayerUnitHealthExtension.add_heal"]),
                damage = function(victim, source, attack_type, attacker_id, amount)
                    local data = { [7] = source, [14] = attack_type }
                    return fake_mod.hooks["StatisticsUtil.register_damage"](
                        function(_, _, db)
                            if attacker_id then
                                db.stats[attacker_id] = db.stats[attacker_id] + amount
                            end
                            return "vanilla-result", nil, 3
                        end, victim, data, database)
                end,
            })
        end)
        for _, name in ipairs(GLOBAL_NAMES) do rawset(_G, name, previous[name]) end
        if not ok then error(err, 0) end
    end

    local function score(env, stats_id, topic)
        local scores = env.api.current_scores({ { stats_id = stats_id } })
        return scores and scores[stats_id][topic]
    end

    H.test("GUT #1570/#1571 host adapter credits friendly fire and enemy damage once", function()
        with_adapter(function(env)
            local a, b, c = env.damage("rat_unit", "es_1h_sword", "light_attack", "alpha:1", 10)
            H.deep_equal({ a, b, c }, { "vanilla-result", nil, 3 },
                "every vanilla return value is forwarded")
            H.equal(env.api.current_scores({ { stats_id = "alpha:1" } }), nil,
                "no ledger before the mission enters")

            env.mod.on_game_state_changed("enter", "StateIngame")
            H.equal(env.state.prior_state_calls, 1, "lifecycle chain preserved")
            env.damage("rat_unit", "es_1h_sword", "light_attack", "alpha:1", 10)
            env.damage("rat_unit", "es_longbow", "n/a", "alpha:1", 4)
            env.damage("rat_unit", "dot_debuff", "n/a", "alpha:1", 2)
            env.damage("bravo_unit", "es_longbow", "n/a", "alpha:1", 7.5)
            env.damage("alpha_unit", "es_longbow", "n/a", "alpha:1", 3)
            env.damage("rat_unit", "es_1h_sword", "heavy_attack", nil, 0)

            H.equal(score(env, "alpha:1", Policy.MELEE), 10)
            H.equal(score(env, "alpha:1", Policy.RANGED), 4,
                "unclassified dot, friendly fire and self damage stay out of ranged")
            H.equal(score(env, "alpha:1", Policy.FRIENDLY_FIRE), 7.5)
            H.equal(score(env, "bravo:1", Policy.FRIENDLY_FIRE), 0)

            env.state.player_manager.is_server = false
            env.damage("rat_unit", "es_1h_sword", "light_attack", "alpha:1", 100)
            H.equal(env.api.current_scores({ { stats_id = "alpha:1" } }), nil,
                "a client exposes no custom values")
            env.state.player_manager.is_server = true
            H.equal(score(env, "alpha:1", Policy.MELEE), 10, "client-path hits are never recorded")

            env.mod.on_game_state_changed("exit", "StateIngame")
            H.equal(env.api.current_scores({ { stats_id = "alpha:1" } }), nil)
            env.mod.on_game_state_changed("enter", "StateIngame")
            H.equal(score(env, "alpha:1", Policy.MELEE), 0, "a new mission starts a fresh ledger")
        end)
    end)

    H.test("GUT #1570 vanilla errors propagate and ambiguous deltas are refused", function()
        with_adapter(function(env)
            env.mod.on_game_state_changed("enter", "StateIngame")
            local ok, err = pcall(env.register, function() error("vanilla failure") end,
                "rat_unit", {}, env.database)
            H.equal(ok, false)
            H.truthy(tostring(err):find("vanilla failure", 1, true))
            env.register(function(_, _, db)
                db.stats["alpha:1"] = db.stats["alpha:1"] + 1
                db.stats["bravo:1"] = db.stats["bravo:1"] + 1
            end, "rat_unit", { [7] = "es_1h_sword", [14] = "light_attack" }, env.database)
            H.equal(score(env, "alpha:1", Policy.MELEE), 0)
            local refused = false
            for _, line in ipairs(env.state.logs) do
                if line:find("custom refusal", 1, true) and line:find("ambiguous", 1, true) then
                    refused = true
                end
            end
            H.truthy(refused, "ambiguous attribution leaves a bounded refusal receipt")
        end)
    end)

    H.test("GUT #1572 host add_heal wrapper credits the permanent delta to the healer", function()
        with_adapter(function(env)
            env.mod.on_game_state_changed("enter", "StateIngame")
            local extension = {
                is_server = true, game = "session", health_game_object_id = "hurt",
                player = env.heroes.bravo,
            }
            env.health.hurt = 40
            local function heal_to(target)
                return function() env.health.hurt = target; return "healed" end
            end
            H.equal(env.add_heal(heal_to(65), extension, "alpha_unit", 25, "bandage", "bandage"),
                "healed")
            env.add_heal(heal_to(75), extension, "bravo_unit", 10, "potion", "healing_draught")
            env.add_heal(heal_to(75), extension, "alpha_unit", 30, "proc", "heal_from_proc")
            env.add_heal(heal_to(80), extension, nil, 5, "level", "debug")
            H.equal(score(env, "alpha:1", Policy.PERMANENT_HEALTH), 25)
            H.equal(score(env, "bravo:1", Policy.PERMANENT_HEALTH), 15,
                "self and non-player heals credit the healed player; temporary heals add nothing")

            extension.is_server = false
            env.add_heal(heal_to(99), extension, "alpha_unit", 19, "bandage", "bandage")
            H.equal(score(env, "alpha:1", Policy.PERMANENT_HEALTH), 25,
                "a non-authoritative extension is never observed")
        end)
    end)

    H.test("GUT #1570-#1572 rows mirror #437 retention decisions", function()
        with_adapter(function(env)
            env.mod.on_game_state_changed("enter", "StateIngame")
            env.damage("rat_unit", "es_1h_sword", "light_attack", "alpha:1", 5)
            env.damage("rat_unit", "es_1h_sword", "light_attack", "bravo:1", 6)
            env.api.on_retention_event("unregister", "alpha:1", true)
            H.equal(score(env, "alpha:1", Policy.MELEE), 5, "retained rejoin keeps the row")
            env.api.on_retention_event("unregister", "alpha:1", false)
            H.equal(score(env, "alpha:1", Policy.MELEE), 0, "an unretained departure drops the row")
            env.damage("rat_unit", "es_1h_sword", "light_attack", "alpha:1", 2)
            env.api.on_retention_event("evicted", "alpha:1", false)
            H.equal(score(env, "alpha:1", Policy.MELEE), 0)
            env.database.registered["bravo:1"] = nil
            env.api.on_retention_event("cleared", nil, false)
            H.equal(score(env, "bravo:1", Policy.MELEE), 0,
                "a discarded retention drops departed players only")
        end)
    end)

    H.test("GUT #437 retention notifies keep, evict and discard decisions", function()
        local fake_mod = { hooks = {}, settings = { gut_preserve_disconnected_scoreboard = true } }
        function fake_mod:dofile(path) return assert(loadfile(mod_root .. path .. ".lua"))() end
        function fake_mod:hook(class_name, method_name, callback)
            self.hooks[class_name .. "." .. method_name] = callback
        end
        function fake_mod:hook_safe(class_name, method_name, callback)
            self.hooks[class_name .. "." .. method_name] = callback
        end
        function fake_mod:get(id) return self.settings[id] end
        local events, logs = {}, {}
        local saved = {}
        local globals = {
            get_mod = function(name) return name == "gut_dev" and fake_mod or nil end,
            Managers = {
                player = { is_server = true },
                mechanism = { current_mechanism_name = function() return "adventure" end },
            },
            ScoreboardHelper = { scoreboard_topic_stats = native_topics() },
            printf = function(fmt, ...) logs[#logs + 1] = string.format(fmt, ...) end,
        }
        for name, value in pairs(globals) do saved[name] = rawget(_G, name); rawset(_G, name, value) end
        local ok, err = pcall(function()
            local retention = assert(loadfile(scripts .. "_gut_scoreboard_retention.lua"))()
            H.truthy(retention.add_listener(function(event, stats_id, kept)
                events[#events + 1] = table.concat({ event, tostring(stats_id), tostring(kept) }, "|")
            end))
            H.equal(retention.add_listener("not a function"), false)
            fake_mod.on_game_state_changed("enter", "StateIngame")
            local database = { rows = {} }
            function database:get_stat(stats_id, name)
                local row = self.rows[stats_id]
                return row and row[name] or nil
            end
            local unregister = assert(fake_mod.hooks["StatisticsDatabase.unregister"])
            database.rows.empty = {}
            unregister(function() end, database, "empty")
            for i = 1, 9 do
                local id = "p" .. i
                database.rows[id] = { kills_total = i }
                unregister(function() end, database, id)
            end
            fake_mod.settings.gut_preserve_disconnected_scoreboard = false
            fake_mod.on_setting_changed("gut_preserve_disconnected_scoreboard")
            unregister(function() end, database, "p9")
        end)
        for name in pairs(globals) do rawset(_G, name, saved[name]) end
        if not ok then error(err, 0) end
        H.truthy(type(fake_mod._gut_scoreboard_retention) == "table",
            "retention publishes its listener API for later owners")
        H.equal(events[1], "unregister|empty|false", "nothing captured means nothing kept")
        H.equal(events[2], "unregister|p1|true")
        H.equal(events[10], "evicted|p1|false", "the ninth capture evicts the oldest row first")
        H.equal(events[11], "unregister|p9|true")
        H.equal(events[12], "cleared|nil|false", "disabling retention discards every kept row")
        H.equal(events[13], "unregister|p9|false")
        H.equal(#events, 13)
    end)

    H.test("GUT #1570-#1572 entry point loads custom rows after the scoreboard owners", function()
        local file = assert(io.open(scripts .. "gui_tweaker_dev.lua", "rb"))
        local source = file:read("*a")
        file:close()
        local live = source:find('"scripts/mods/gui_tweaker_dev/_gut_scoreboard_live"', 1, true)
        local retention = source:find('"scripts/mods/gui_tweaker_dev/_gut_scoreboard_retention"', 1, true)
        local boss = source:find('"scripts/mods/gui_tweaker_dev/_gut_boss_damage_sync"', 1, true)
        local custom = source:find('"scripts/mods/gui_tweaker_dev/_gut_custom_stats"', 1, true)
        H.truthy(live and retention and boss and custom, "every scoreboard owner is loaded")
        H.truthy(live < retention and retention < boss and boss < custom,
            "the custom ledger must wrap the lifecycle after the presenter captures")
    end)

    H.test("GUT #1570-#1572 runtime checks execute the real policy and model", function()
        with_adapter(function(env)
            local names = {}
            for _, check in ipairs(env.api.rt_checks) do
                names[#names + 1] = check.name
                H.equal(check.fn(), nil, check.name)
                H.equal(check.fn(), nil, check.name .. " repeat")
            end
            H.deep_equal(names, {
                "issue1570_host_friendly_fire_statistic",
                "issue1571_host_melee_ranged_damage_statistic",
                "issue1572_host_permanent_health_statistic",
            })
            H.deep_equal(env.mod.registered, names, "the module self-registers every check once")
            H.equal(env.mod._gut_custom_stats, env.api, "the presenter API is self-published")
            H.equal(env.state.listener, env.api.on_retention_event,
                "the #437 retention listener is self-wired")
            local receipts = 0
            for _, line in ipairs(env.state.logs) do
                if line:find("runtime verdict=PASS", 1, true) then receipts = receipts + 1 end
            end
            H.equal(receipts, 3, "one bounded receipt per check")
        end)
    end)
end
