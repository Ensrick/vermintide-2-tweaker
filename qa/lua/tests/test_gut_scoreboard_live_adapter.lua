return function(H, repo_root)
    local live_path = repo_root
        .. "/gui_tweaker_dev/scripts/mods/gui_tweaker_dev/_gut_scoreboard_live.lua"
    local retention_path = repo_root
        .. "/gui_tweaker_dev/scripts/mods/gui_tweaker_dev/_gut_scoreboard_retention.lua"
    local mod_root = repo_root .. "/gui_tweaker_dev/"

    local GLOBAL_NAMES = {
        "get_mod", "Managers", "ScoreboardHelper", "UIRenderer",
        "UISceneGraph", "UIWidget", "UILayer", "UTF8Utils", "Localize",
        "printf",
    }

    local function with_globals(values, fn)
        local previous = {}
        for _, name in ipairs(GLOBAL_NAMES) do
            previous[name] = rawget(_G, name)
            rawset(_G, name, values[name])
        end
        local ok, err = pcall(fn)
        for _, name in ipairs(GLOBAL_NAMES) do
            rawset(_G, name, previous[name])
        end
        if not ok then error(err, 0) end
    end

    local function native_topics()
        local names = {
            "kills_elites", "kills_specials", "kills_total", "kills_melee",
            "kills_ranged", "damage_taken", "damage_dealt",
            "damage_dealt_bosses", "headshots", "saves", "revives",
        }
        local topics = {}
        for i, name in ipairs(names) do
            topics[i] = {
                name = name,
                display_text = "scoreboard_topic_" .. name,
                stat_type = name,
            }
        end
        return topics
    end

    local function player(stats_id, name, score, boss)
        return {
            stats_id = stats_id,
            name = name,
            group_scores = {
                offense = {
                    { stat_name = "kills_total", score = score or 0 },
                    { stat_name = "damage_dealt_bosses", score = boss or score or 0 },
                },
            },
        }
    end

    local function live_harness(body)
        local state = {
            now = 0,
            mechanism = "adventure",
            grouped_calls = 0,
            logs = {},
            prior_state_calls = 0,
            settings = {
                gut_scoreboard_live_native = true,
                gut_scoreboard_live_page = 2,
                gut_scoreboard_live_sort = "player_name",
            },
            grouped = {
                host = player("host", "Alpha", 4),
                remote = player("remote", "Bravo", 2),
            },
        }
        local database = {
            reads = 0,
            rows = {
                host = { aidings = 3, times_revived = 1 },
                remote = { aidings = 8, times_revived = 2 },
            },
        }
        function database:get_stat(stats_id, stat_type)
            self.reads = self.reads + 1
            if self.poisoned then error("statistics row accessed after exit") end
            local row = self.rows[stats_id]
            if not row then error("statistics row removed: " .. tostring(stats_id)) end
            return row[stat_type]
        end

        local fake_mod = { hooks = {}, settings = state.settings }
        fake_mod._gut_boss_damage_sync = {
            current_scores = function() return state.boss_scores end,
        }
        function fake_mod:dofile(path)
            return assert(loadfile(mod_root .. path .. ".lua"))()
        end
        function fake_mod:hook_safe(class_name, method_name, callback)
            self.hooks[class_name .. "." .. method_name] = callback
        end
        function fake_mod:get(setting_id) return self.settings[setting_id] end
        function fake_mod:set(setting_id, value) self.settings[setting_id] = value end
        function fake_mod:localize(key) return key end
        fake_mod.on_game_state_changed = function(status, state_name)
            state.prior_state_calls = state.prior_state_calls + 1
            if state.poison_on_prior_exit and status == "exit"
                    and state_name == "StateIngame" then
                database.poisoned = true
            end
        end

        local helper = {
            scoreboard_topic_stats = native_topics(),
            get_grouped_topic_statistics = function()
                state.grouped_calls = state.grouped_calls + 1
                if database.poisoned then error("grouped read after exit") end
                return state.grouped
            end,
        }
        local renderer = {
            begin_pass = function() end,
            draw_widget = function(_, widget) state.last_widget = widget end,
            end_pass = function() end,
        }
        local values = {
            get_mod = function(name)
                if name == "gut_dev" then return fake_mod end
                return nil
            end,
            Managers = {
                player = {
                    statistics_db = function()
                        state.manager_database_calls =
                            (state.manager_database_calls or 0) + 1
                        if state.manager_database_throws then
                            error("manager database unavailable")
                        end
                        return database
                    end,
                },
                state = {
                    network = { profile_synchronizer = {} },
                },
                time = {
                    time = function() return state.now end,
                },
                mechanism = {
                    current_mechanism_name = function()
                        if state.mechanism_throws then error("mechanism unavailable") end
                        return state.mechanism
                    end,
                },
            },
            ScoreboardHelper = helper,
            UIRenderer = renderer,
            UISceneGraph = { init_scenegraph = function() return {} end },
            UIWidget = {
                init = function(definition)
                    return { content = definition.content, style = definition.style }
                end,
            },
            UILayer = { hud = 100 },
            Localize = function(key) return key end,
            printf = function(fmt, ...)
                state.logs[#state.logs + 1] = string.format(fmt, ...)
            end,
        }

        with_globals(values, function()
            local api = assert(loadfile(live_path))()
            body({
                api = api,
                mod = fake_mod,
                state = state,
                database = database,
                helper = helper,
                tab_draw = assert(fake_mod.hooks["IngamePlayerListUI._draw"]),
                end_draw = assert(fake_mod.hooks["EndViewStateScore.draw"]),
            })
        end)
    end

    H.test("GUT #1414 exit sidecar survives absent end database and deleted remote rows", function()
        live_harness(function(env)
            env.state.manager_database_throws = true
            env.mod.on_game_state_changed("exit", "StateIngame", {
                statistics_db = env.database,
                profile_synchronizer = {},
            })
            H.equal(env.database.reads, 4,
                "two scalar reads per player must complete before the prior exit chain")
            H.equal(env.state.manager_database_calls, nil,
                "the source-provided old StateIngame database must outrank Managers")
            H.equal(env.state.prior_state_calls, 1)

            env.mod.on_game_state_changed("enter", "StateLoading", {})
            env.mod.on_game_state_changed("enter", "StateInGameRunning", {})
            env.mod.on_game_state_changed("enter", "StateIngame", {
                parent = {
                    loading_context = {
                        level_end_view_wrappers = { {} },
                    },
                },
            })
            H.equal(env.state.prior_state_calls, 4,
                "the loading, nested, and carried-wrapper enter chain must remain intact")

            env.database.poisoned = true
            env.database.rows.remote = nil
            local end_state = {
                _context = { players_session_score = env.state.grouped },
                game_mode_key = "adventure",
                ui_renderer = {},
                statistics_db = nil,
            }
            env.end_draw(end_state, {}, 0.016)
            H.equal(env.state.last_widget.content.player_1_row_1, "3")
            H.equal(env.state.last_widget.content.player_1_row_2, "1")
            H.equal(env.state.last_widget.content.player_2_row_1, "8")
            H.equal(env.state.last_widget.content.player_2_row_2, "2")
            H.equal(env.database.reads, 4,
                "end presenter must consume the sidecar without a database reread")

            env.end_draw(end_state, {}, 0.016)
            H.equal(env.database.reads, 4,
                "repeated end draws must not reread the database")
            local sidecar_lines = 0
            for _, line in ipairs(env.state.logs) do
                if line:find("[gut:1414] sidecar evidence=", 1, true) then
                    sidecar_lines = sidecar_lines + 1
                end
            end
            H.equal(sidecar_lines, 1, "one mission generation captures at most once")
        end)
    end)

    H.test("GUT #1414 ordinary StateIngame enter clears a stale end sidecar", function()
        live_harness(function(env)
            env.mod.on_game_state_changed("exit", "StateIngame", {
                statistics_db = env.database,
                profile_synchronizer = {},
            })
            H.equal(env.database.reads, 4)
            env.mod.on_game_state_changed("enter", "StateIngame", {
                parent = { loading_context = {} },
            })
            env.database.poisoned = true
            local end_state = {
                _context = { players_session_score = env.state.grouped },
                game_mode_key = "adventure",
                ui_renderer = {},
            }
            env.end_draw(end_state, {}, 0.016)
            H.equal(env.state.last_widget.content.player_1_row_1, "—")
            H.equal(env.state.last_widget.content.player_2_row_2, "—")
            H.equal(env.database.reads, 4,
                "a cleared sidecar must not fall back to the dead database")
        end)
    end)

    H.test("GUT #1414 Tab cache cannot survive a backwards mission clock", function()
        live_harness(function(env)
            local list_ui = { _ui_top_renderer = {} }
            env.state.now = 900
            env.state.grouped = { old = player("old", "OLD_SENTINEL", 1) }
            env.database.rows.old = { aidings = 1, times_revived = 1 }
            env.tab_draw(list_ui, 0.016)
            H.equal(env.state.last_widget.content.player_header_1, "OLD_SENTINEL")
            H.equal(env.state.grouped_calls, 1)

            env.state.now = 0
            env.state.grouped = { fresh = player("fresh", "NEW_MISSION", 2) }
            env.database.rows.fresh = { aidings = 2, times_revived = 2 }
            env.tab_draw(list_ui, 0.016)
            H.equal(env.state.last_widget.content.player_header_1, "NEW_MISSION")
            H.equal(env.state.grouped_calls, 2,
                "now < cached_at must force an immediate fresh snapshot")

            env.state.grouped = { entered = player("entered", "ENTER_RESET", 3) }
            env.database.rows.entered = { aidings = 3, times_revived = 3 }
            env.mod.on_game_state_changed("enter", "StateIngame")
            env.tab_draw(list_ui, 0.016)
            H.equal(env.state.last_widget.content.player_header_1, "ENTER_RESET")
            H.equal(env.state.grouped_calls, 3,
                "StateIngame enter must clear cached_model and cached_at")
        end)
    end)

    H.test("GUT #1414 sidecar failure cannot orphan the prior lifecycle chain", function()
        live_harness(function(env)
            env.state.mechanism_throws = true
            env.mod.on_game_state_changed("exit", "StateIngame")
            env.mod.on_game_state_changed("exit", "StateIngame")
            H.equal(env.state.prior_state_calls, 2)
            H.equal(env.database.reads, 0)
            local errors = 0
            for _, line in ipairs(env.state.logs) do
                if line:find("[gut:1414] sidecar evidence=", 1, true)
                        and line:find("error=", 1, true) then
                    errors = errors + 1
                end
            end
            H.equal(errors, 1,
                "a failed mission generation must remain contained and at-most-once")
        end)
    end)

    H.test("GUT #1448 Tab and end consume one boss override fingerprint", function()
        live_harness(function(env)
            env.mod.settings.gut_scoreboard_live_page = 1
            env.state.grouped = {
                host = player("host", "Alpha", 4, 6),
                remote = player("remote", "Bravo", 2, 5),
            }
            env.state.boss_scores = { host = 91 }
            local list_ui = { _ui_top_renderer = {} }
            env.tab_draw(list_ui, 0.016)
            H.equal(env.state.last_widget.content.player_1_row_8, "91")
            H.equal(env.state.last_widget.content.player_2_row_8, "5",
                "missing compatible row must retain the native subtotal")

            env.mod.on_game_state_changed("exit", "StateIngame", {
                statistics_db = env.database,
                profile_synchronizer = {},
            })
            env.state.boss_scores = nil
            env.mod.on_game_state_changed("enter", "StateIngame", {
                parent = {
                    loading_context = { level_end_view_wrappers = { {} } },
                },
            })
            env.end_draw({
                _context = { players_session_score = env.state.grouped },
                game_mode_key = "adventure",
                ui_renderer = {},
            }, {}, 0.016)
            H.equal(env.state.last_widget.content.player_1_row_8, "91")
            H.equal(env.state.last_widget.content.player_2_row_8, "5")

            local tab_fp, end_fp
            for _, line in ipairs(env.state.logs) do
                local surface, fp = line:match("surface=(%a+).+fp=([0-9a-f]+)")
                if surface == "tab" then tab_fp = fp end
                if surface == "end" then end_fp = fp end
            end
            H.truthy(tab_fp ~= nil)
            H.equal(end_fp, tab_fp)
        end)
    end)

    H.test("GUT #1414 live adapter bounds four-player sidecars and evidence", function()
        live_harness(function(env)
            env.state.grouped = {}
            env.database.rows = {}
            for i = 1, 6 do
                local id = "p" .. tostring(i)
                env.state.grouped[id] = player(id, "Player " .. tostring(i), i)
                env.database.rows[id] = { aidings = i, times_revived = i }
            end
            env.mod.on_game_state_changed("exit", "StateIngame")
            H.equal(env.database.reads, 8,
                "sidecar must read at most four players times two scalar leaves")

            env.database.poisoned = false
            local list_ui = { _ui_top_renderer = {} }
            for i = 1, 20 do
                local id = "visible" .. tostring(i)
                env.state.now = 1000 + i
                env.state.grouped = {
                    [id] = player(id, "Fingerprint " .. tostring(i), i),
                }
                env.database.rows[id] = { aidings = i, times_revived = i }
                env.tab_draw(list_ui, 0.016)
            end
            local page_lines, sidecar_lines = 0, 0
            for _, line in ipairs(env.state.logs) do
                if line:find("[gut:1414] page evidence=", 1, true) then
                    page_lines = page_lines + 1
                elseif line:find("[gut:1414] sidecar evidence=", 1, true) then
                    sidecar_lines = sidecar_lines + 1
                end
            end
            H.equal(page_lines, 8)
            H.truthy(sidecar_lines <= 8)
        end)
    end)

    H.test("GUT #1414 real retention adapter restores each captured row once", function()
        local state = {
            logs = {},
            previous_calls = 0,
            manager_database_calls = 0,
            settings = {
                gut_scoreboard_live_native = true,
                gut_scoreboard_live_page = 2,
                gut_scoreboard_live_sort = "player_name",
            },
        }
        local fake_mod = { hooks = {}, settings = state.settings }
        function fake_mod:dofile(path)
            return assert(loadfile(mod_root .. path .. ".lua"))()
        end
        function fake_mod:get(setting_id)
            local value = self.settings[setting_id]
            return value == nil and true or value
        end
        function fake_mod:set(setting_id, value) self.settings[setting_id] = value end
        function fake_mod:localize(key) return key end
        function fake_mod:hook(class_name, method_name, callback)
            self.hooks[class_name .. "." .. method_name] = callback
        end
        function fake_mod:hook_safe(class_name, method_name, callback)
            self.hooks[class_name .. "." .. method_name] = callback
        end
        fake_mod.on_game_state_changed = function()
            state.previous_calls = state.previous_calls + 1
        end
        local values = {
            get_mod = function(name) return name == "gut_dev" and fake_mod or nil end,
            Managers = {
                player = {
                    is_server = true,
                    statistics_db = function()
                        state.manager_database_calls =
                            state.manager_database_calls + 1
                        error("source StateIngame database should win")
                    end,
                },
                state = { network = { profile_synchronizer = {} } },
                mechanism = {
                    current_mechanism_name = function() return "adventure" end,
                },
                time = { time = function() return 0 end },
            },
            ScoreboardHelper = {
                scoreboard_topic_stats = native_topics(),
                get_grouped_topic_statistics = function()
                    return { remote = player("remote", "Remote", 2) }
                end,
            },
            printf = function(fmt, ...)
                state.logs[#state.logs + 1] = string.format(fmt, ...)
            end,
        }
        with_globals(values, function()
            assert(loadfile(live_path))()
            assert(loadfile(retention_path))()
            fake_mod.on_game_state_changed("enter", "StateIngame")
            H.equal(state.previous_calls, 1, "retention must preserve the prior chain")

            local database = {
                rows = { remote = { aidings = 9, times_revived = 4 } },
                reads = 0,
                writes = 0,
            }
            function database:get_stat(stats_id, stat_name)
                self.reads = self.reads + 1
                return self.rows[stats_id][stat_name]
            end
            function database:set_non_persistent_stat(stats_id, stat_name, value)
                self.writes = self.writes + 1
                self.rows[stats_id][stat_name] = value
            end
            local unregister = assert(fake_mod.hooks["StatisticsDatabase.unregister"])
            local register = assert(fake_mod.hooks["StatisticsDatabase.register"])
            unregister(function(self, stats_id) self.rows[stats_id] = nil end,
                database, "remote")
            database.rows.remote = { aidings = 0, times_revived = 0 }
            register(database, "remote")
            H.equal(database.rows.remote.aidings, 9)
            H.equal(database.rows.remote.times_revived, 4)
            H.equal(database.writes, 2)
            register(database, "remote")
            H.equal(database.writes, 2,
                "a second native register callback must not replay consumed retention")

            local reads_before_exit = database.reads
            fake_mod.on_game_state_changed("exit", "StateIngame", {
                statistics_db = database,
                profile_synchronizer = {},
            })
            H.equal(database.reads, reads_before_exit + 2,
                "the chained live adapter must capture both scalar leaves from the old state")
            H.equal(state.manager_database_calls, 0,
                "the retention wrapper must forward the old StateIngame object")
            fake_mod.on_game_state_changed("exit", "StateIngame", {
                statistics_db = database,
                profile_synchronizer = {},
            })
            H.equal(database.reads, reads_before_exit + 2,
                "a repeated real lifecycle exit must not capture the mission twice")
            H.equal(state.previous_calls, 3,
                "both real lifecycle exits must continue through the prior owner")
        end)
    end)
end
