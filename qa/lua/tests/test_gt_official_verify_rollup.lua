return function(H, root)
    local function read(path)
        local f = assert(io.open(root .. "/" .. path, "rb"))
        local s = f:read("*a"); f:close()
        return s:gsub("\r\n", "\n")
    end
    local function clone(t)
        local result = {}
        for k, v in pairs(t) do result[k] = v end
        return result
    end
    local function context(stream)
        local directory = stream == "public" and "general_tweaker" or "general_tweaker_dev"
        local id = stream == "public" and "gt" or "gt_dev"
        local folder = directory .. "/scripts/mods/" .. directory .. "/"
        local hooks, checks = {}, {}
        local settings = {
            gt_offline_twitch_enabled = true,
            gt_offline_twitch_allow_buffs = true,
            gt_offline_twitch_allow_items = false,
            gt_offline_twitch_allow_mutators = true,
            gt_offline_twitch_allow_spawns = true,
        }
        local templates = {
            a = { name = "a", cost = 10 },
            twitch_give_bomb = { name = "twitch_give_bomb", cost = 10 },
            c = { name = "c", cost = 12 },
        }
        local env = setmetatable({
            TwitchVoteTemplates = templates,
            TwitchStandardVoteTemplatesLookup = { "a", "twitch_give_bomb", "c" },
            TwitchVoteTemplatesLookup = { "a", "twitch_give_bomb", "c" },
            TwitchSettings = { max_a_b_vote_cost_diff = 5 },
            TwitchVoteWhitelists = {},
            Managers = { state = { game_mode = { game_mode_key = function() return "adventure" end } } },
            table = clone(table),
            print = function() end,
        }, { __index = _G })
        env._G = env
        env.table.clone = clone
        env.table.shuffle = function() end
        env.table.contains = function(t, value)
            for _, v in pairs(t) do if v == value then return true end end
            return false
        end
        env.table.clear = function(t) for k in pairs(t) do t[k] = nil end end
        env.table.size = function(t) local n = 0; for _ in pairs(t) do n = n + 1 end; return n end
        local mod = {}
        function mod:get(key) return settings[key] end
        function mod:dofile(path)
            local fn = assert(loadfile(root .. "/" .. directory .. "/" .. path .. ".lua"))
            return setfenv(fn, env)()
        end
        function mod:hook(class, method, callback)
            local key = class .. "." .. method
            assert(not hooks[key], "duplicate hook " .. key)
            hooks[key] = callback
        end
        function mod._gt_rt_register(name, callback) checks[name] = callback end
        env.get_mod = function(name) if name == id then return mod end end
        local oracle = assert(loadfile(root .. "/qa/lua/tests/fixtures/gt_native_standard_vote.lua"))
        local Native = setfenv(oracle, env)()
        setfenv(assert(loadfile(root .. "/" .. folder .. "_gt_offline_twitch.lua")), env)()
        local clear_count, package_calls = 0, {}
        local self = {
            _used_vote_templates = {},
            _funds = 37,
            _parent = { locked_breed_packages = {} },
            _get_game_mode_whitelist = Native._get_game_mode_whitelist,
            _clear_used_votes = function(owner, force)
                clear_count = clear_count + 1
                return Native._clear_used_votes(owner, force)
            end,
            _check_breed_package_loading = function(_, template, previous)
                package_calls[#package_calls + 1] = { template, previous }
                return template
            end,
        }
        self._in_whitelist = function(owner, name)
            return hooks["TwitchGameMode._in_whitelist"](Native._in_whitelist, owner, name)
        end
        self._next_standard_vote = function(owner, a)
            return hooks["TwitchGameMode._next_standard_vote"](Native._next_standard_vote, owner, a)
        end
        return {
            env = env, mod = mod, hooks = hooks, checks = checks,
            settings = settings, templates = templates, Native = Native, self = self,
            clear_count = function() return clear_count end,
            package_calls = package_calls,
        }
    end

    for _, stream in ipairs({ "dev", "public" }) do
        H.test("GT #333 " .. stream .. " actual hook rejects native candidate-B bypass", function()
            local c = context(stream)
            c.settings.gt_offline_twitch_enabled = false
            local kind, values = c.self:_next_standard_vote(c.templates.a)
            H.equal(kind, "standard_vote")
            H.equal(values[2], "twitch_give_bomb") -- native reproduced defect
            c.settings.gt_offline_twitch_enabled = true
            kind, values = c.self:_next_standard_vote(c.templates.a)
            H.equal(kind, "standard_vote")
            H.equal(values[1], "a"); H.equal(values[2], "c")
            H.equal(c.self._funds, 37)
        end)
        H.test("GT #333 " .. stream .. " preserves whitelist conditions used votes costs and boss pairing", function()
            local c = context(stream)
            c.env.TwitchVoteWhitelists.adventure = { "a", "c", "blocked", "costly", "equivalent" }
            c.templates.blocked = { name = "blocked", cost = 10, condition_func = function() return false end }
            c.templates.costly = { name = "costly", cost = 99 }
            c.templates.equivalent = { name = "equivalent", cost = 13, boss_equivalent = true }
            c.env.TwitchStandardVoteTemplatesLookup = { "twitch_give_bomb", "blocked", "costly", "c", "equivalent" }
            c.self._used_vote_templates.c = 2
            c.templates.a.boss = true
            local kind, values, validation = c.self:_next_standard_vote(c.templates.a)
            H.equal(kind, "standard_vote"); H.equal(values[2], "equivalent")
            H.equal(validation, nil); H.equal(c.self._used_vote_templates.c, 2)
            H.equal(c.clear_count(), 0)
        end)
        H.test("GT #333 " .. stream .. " retries used rotation once and defers impossible ballots", function()
            local c = context(stream)
            c.self._used_vote_templates.c = 3
            local kind, values = c.self:_next_standard_vote(c.templates.a)
            H.equal(kind, "standard_vote"); H.equal(values[2], "c")
            H.equal(c.clear_count(), 1)
            c.templates.c.condition_func = function() return false end
            H.equal(c.self:_next_standard_vote(c.templates.a), nil)
            H.equal(c.clear_count(), 2)
        end)
        H.test("GT #333 " .. stream .. " filters package replacements without rewriting shared lookups", function()
            local c = context(stream)
            local original = c.env.TwitchStandardVoteTemplatesLookup
            c.settings.gt_offline_twitch_allow_spawns = false
            c.templates.spawn_replacement = { name = "spawn_replacement", cost = 12, breed_name = "rat" }
            c.templates.d = { name = "d", cost = 14 }
            original[#original + 1] = "d"
            c.self._check_breed_package_loading = function(_, template)
                if template.name == "c" then return c.templates.spawn_replacement end
                return template
            end
            local kind, values = c.self:_next_standard_vote(c.templates.a)
            H.equal(kind, "standard_vote"); H.equal(values[2], "d")
            H.equal(c.env.TwitchStandardVoteTemplatesLookup, original)
            H.equal(#original, 4); H.equal(next(c.self._used_vote_templates), nil)
        end)
        H.test("GT #333 " .. stream .. " alias and lookup-mutating condition remain finitely bounded", function()
            local c = context(stream)
            local calls = 0
            c.env.TwitchStandardVoteTemplatesLookup = { "alias" }
            c.templates.alias = {
                name = "different_template_name", cost = 10,
                condition_func = function()
                    calls = calls + 1
                    local name = "appended_" .. calls
                    c.templates[name] = { name = name, cost = 10 }
                    local lookup = c.env.TwitchStandardVoteTemplatesLookup
                    lookup[#lookup + 1] = name
                    return true
                end,
            }
            c.self._check_breed_package_loading = function(_, template)
                if template.name == "a" then return template end
                return c.templates.twitch_give_bomb
            end
            H.equal(c.self:_next_standard_vote(c.templates.a), nil)
            H.equal(calls, 1); H.equal(c.clear_count(), 1)
            H.equal(#c.env.TwitchStandardVoteTemplatesLookup, 2)
        end)
        H.test("GT #333 " .. stream .. " callback errors and reentrancy leak no temporary state", function()
            local c = context(stream)
            local sentinel, used, lookup = {}, c.self._used_vote_templates, c.env.TwitchStandardVoteTemplatesLookup
            c.templates.c.condition_func = function() error(sentinel, 0) end
            local ok, err = pcall(c.self._next_standard_vote, c.self, c.templates.a)
            H.equal(ok, false); H.equal(err, sentinel)
            H.equal(c.self._used_vote_templates, used)
            H.equal(c.env.TwitchStandardVoteTemplatesLookup, lookup)
            local entered = false
            c.templates.c.condition_func = function()
                if not entered then
                    entered = true
                    local kind, values = c.self:_next_standard_vote(c.templates.a)
                    H.equal(kind, "standard_vote"); H.equal(values[2], "c")
                end
                return true
            end
            local kind, values = c.self:_next_standard_vote(c.templates.a)
            H.equal(kind, "standard_vote"); H.equal(values[2], "c")
            H.equal(c.env.TwitchStandardVoteTemplatesLookup, lookup)
            H.equal(c.self._used_vote_templates, used)
        end)
        H.test("GT #333 " .. stream .. " disabled live-connected hook preserves exact arguments and nil returns", function()
            local c = context(stream)
            c.settings.gt_offline_twitch_enabled = false
            local token = {}
            local count
            local function original(owner, a, ...)
                H.equal(owner, c.self); H.equal(a, c.templates.a)
                count = select("#", ...); H.equal(select(2, ...), token)
                return "native", nil, token
            end
            local a, b, z = c.hooks["TwitchGameMode._next_standard_vote"](original, c.self, c.templates.a, nil, token)
            H.equal(count, 2); H.equal(a, "native"); H.equal(b, nil); H.equal(z, token)
        end)
        H.test("GT #333 " .. stream .. " native package loader keeps lock and error ownership", function()
            local c = context(stream)
            local locked, requested = {}, {}
            c.env.Managers.level_transition_handler = { enemy_package_loader = {
                is_breed_processed = function() return false end,
                request_breed = function(_, name) requested[#requested + 1] = name; return true end,
                lock_breed_package = function(_, name) locked[#locked + 1] = name end,
            } }
            c.templates.c.breed_name, c.templates.c.special = "native_breed", true
            c.self._check_breed_package_loading = c.Native._check_breed_package_loading
            local kind, values = c.self:_next_standard_vote(c.templates.a)
            H.equal(kind, "standard_vote"); H.equal(values[2], "c")
            H.equal(requested[1], "native_breed"); H.equal(locked[1], "native_breed")
            H.equal(c.self._parent.locked_breed_packages.native_breed, true)
            local sentinel = {}
            c.env.Managers.level_transition_handler.enemy_package_loader.request_breed = function() error(sentinel, 0) end
            local ok, err = pcall(c.self._next_standard_vote, c.self, c.templates.a)
            H.equal(ok, false); H.equal(err, sentinel)
        end)
    end

    H.test("GT #364 official production mule and greedy consumers reserve only Survival Ale", function()
        local hooks, checks = {}, {}
        local settings = { gt_bot_behavior_improvements = true, gt_bot_greedy_pickup = true }
        local ale = { alive = true, pickup = { pickup_name = "bardin_survival_ale" } }
        local potion = { alive = true, pickup = { pickup_name = "damage_boost_potion" } }
        local bot = { alive = true }
        local positions = { [ale] = 1, [potion] = 2, [bot] = 0 }
        local mod = {}
        function mod:get(key) return settings[key] end
        function mod:debug() end
        function mod._gt_rt_register(name, fn) checks[name] = fn end
        function mod:hook_safe(class, method, fn) hooks[class .. "." .. method] = fn end
        local env = setmetatable({
            get_mod = function() return mod end,
            Unit = { alive = function(unit) return unit and unit.alive == true end },
            ScriptUnit = { has_extension = function(unit, name)
                if name == "pickup_system" then return unit.pickup end
            end },
            POSITION_LOOKUP = positions,
            Vector3 = { distance_squared = function(a, b) return (a - b) ^ 2 end },
        }, { __index = _G })
        function mod:dofile(path)
            return setfenv(assert(loadfile(root .. "/general_tweaker/" .. path .. ".lua")), env)()
        end
        setfenv(assert(loadfile(root .. "/general_tweaker/scripts/mods/general_tweaker/_gt_bot_pickups.lua")), env)()
        local bb = {
            mule_pickup = ale, interaction_unit = ale, forced_pickup_unit = ale,
            inventory_extension = {
                get_slot_data = function() return nil end,
                can_store_additional_item = function() return false end,
            },
        }
        local self = {
            _bot_ai_data = { { [bot] = { blackboard = bb, follow_position = 0 } } },
            _available_mule_pickups = { { slot_potion = { [ale] = true, [potion] = true } } },
        }
        hooks["AIBotGroupSystem._update_mule_pickups"](self, 0.1, 1)
        H.equal(bb.mule_pickup, potion) -- closer ale refused, ordinary candidate retained
        H.equal(bb.interaction_unit, nil); H.equal(bb.forced_pickup_unit, nil)
        settings.gt_bot_greedy_pickup = false
        bb.mule_pickup = ale
        hooks["AIBotGroupSystem._update_mule_pickups"](self, 0.1, 2)
        H.equal(bb.mule_pickup, nil) -- native claim cleanup is not gated by greedy
        bb.mule_pickup = potion
        hooks["AIBotGroupSystem._update_mule_pickups"](self, 0.1, 3)
        H.equal(bb.mule_pickup, potion)
        H.equal(checks.gt364_survival_ale_reserved_for_humans(), nil)
    end)

    H.test("GT #364 official actual instant consumer sanitizes reserved mule target", function()
        local source = read("general_tweaker/scripts/mods/general_tweaker/_gt_bot_fixes.lua")
        local body = assert(source:match("(local function _gt_instant_pickup_tick.-\nend)\n"))
        local ale, potion = {}, {}
        local mod = { _gt_bot_pickup_is_reserved = function(unit) return unit == ale end }
        local factory = assert(loadstring("return function(mod)\n" .. body .. "\nreturn _gt_instant_pickup_tick\nend"))
        setfenv(factory, setmetatable({ Unit = { alive = function(unit) return unit ~= nil end } }, { __index = _G }))
        local tick = factory()(mod)
        local bb = { mule_pickup = ale, health_pickup = potion, interaction_unit = ale, forced_pickup_unit = ale }
        tick(nil, nil, bb, 0)
        H.equal(bb.interaction_unit, potion); H.equal(bb.forced_pickup_unit, potion)
        bb = { mule_pickup = ale, interaction_unit = ale, forced_pickup_unit = ale }
        tick(nil, nil, bb, 0)
        H.equal(bb.interaction_unit, nil); H.equal(bb.forced_pickup_unit, nil)
    end)

    H.test("GT official statistics group exposes only the promoted HUD with matching localization", function()
        local mod, cache = {}, {}
        function mod:localize(key) return key end
        local env = setmetatable({}, { __index = _G })
        env.get_mod = function(name) if name == "gt" then return mod end end
        env.require = function(name)
            if cache[name] then return cache[name] end
            local path = root .. "/general_tweaker/" .. name .. ".lua"
            cache[name] = setfenv(assert(loadfile(path)), env)()
            return cache[name]
        end
        local data = setfenv(assert(loadfile(root .. "/general_tweaker/scripts/mods/general_tweaker/general_tweaker_data.lua")), env)()
        local loc = assert(loadfile(root .. "/general_tweaker/scripts/mods/general_tweaker/general_tweaker_localization.lua"))()
        local groups, seen = {}, {}
        local function walk(node)
            if type(node) ~= "table" then return end
            if node.setting_id then
                H.equal(seen[node.setting_id], nil, "duplicate widget " .. node.setting_id)
                seen[node.setting_id] = true
                H.truthy(loc[node.setting_id], "missing localization " .. node.setting_id)
            end
            for _, value in pairs(node) do if type(value) == "table" then walk(value) end end
        end
        for _, group in ipairs(data.options.widgets) do groups[group.setting_id] = group end
        local group = assert(groups.gt_player_statistics_group)
        H.equal(#group.sub_widgets, 1)
        H.equal(group.sub_widgets[1].setting_id, "gt_devtools_player_stat_hud")
        H.equal(groups.gt_devtools_group, nil); H.equal(groups.gttools_group, nil)
        H.equal(loc.gt_player_statistics_group.en, "Player Statistics")
        walk(data)
    end)

    H.test("GT official rollup keeps one freeze queue owner and excludes unrelated probes", function()
        local entry = read("general_tweaker/scripts/mods/general_tweaker/general_tweaker.lua")
        local time = read("general_tweaker/scripts/mods/general_tweaker/_gt_time_hooks.lua")
        local pickups = read("general_tweaker/scripts/mods/general_tweaker/_gt_bot_pickups.lua")
        H.equal(entry:find('"ConflictDirector", "update_spawn_queue"', 1, true), nil)
        H.truthy(time:find('mod:get("disable_enemy_spawns")', 1, true))
        H.truthy(time:find("mod._gt_time_world_frozen", 1, true))
        H.equal(pickups:find("_gt347", 1, true), nil)
        H.equal(entry:find('_gt_agent_bridge"', 1, true), nil)
        H.equal(entry:find('_gt_freeze_ai"', 1, true), nil)
        H.equal(entry:find('_gt_bot_hazard_resistance"', 1, true), nil)
    end)

    H.test("GT official complete literal dofile graph resolves without missing feature dependencies", function()
        local visited = {}
        local function visit(path)
            if visited[path] then return end
            visited[path] = true
            local source = read(path)
            for child in source:gmatch('mod:dofile%s*%(%s*"([^"]+)"') do
                visit("general_tweaker/" .. child .. ".lua")
            end
        end
        visit("general_tweaker/scripts/mods/general_tweaker/general_tweaker.lua")
    end)

    local function btlab_context(application)
        local mod, registered, world, gui = {}, nil, {}, {}
        local counters = { creates = 0, probes = 0 }
        function mod:get() return true end -- even saved tools-on settings must stay inert publicly
        function mod:command() end
        function mod:info() end
        function mod._gt_register_update(name, fn)
            if name == "btlab_draw" then registered = fn end
        end
        local env = setmetatable({
            get_mod = function(name) if name == "gt" then return mod end end,
            Managers = {
                world = { has_world = function() return true end, world = function() return world end },
                player = { is_server = true, local_player = function() return nil end },
            },
            POSITION_LOOKUP = {}, ALIVE = {}, HEALTH_ALIVE = {},
            Vector3 = function() return {} end,
            Color = function() return {} end,
            World = {
                create_screen_gui = function(actual_world, kind, material, mode)
                    H.equal(actual_world, world); H.equal(kind, "material")
                    H.equal(material, "materials/fonts/gw_fonts"); H.equal(mode, "immediate")
                    counters.creates = counters.creates + 1
                    return gui
                end,
                create_line_object = function() error("unexpected line-object creation") end,
            },
        }, { __index = _G })
        env._G = env
        if application then
            env.Application = {}
            if application.can_get then
                env.Application.can_get = function(kind, path)
                    counters.probes = counters.probes + 1
                    H.equal(kind, "material"); H.equal(path, "materials/fonts/gw_fonts")
                    return application.can_get(kind, path)
                end
            end
        end
        function mod:dofile(path)
            return setfenv(assert(loadfile(root .. "/general_tweaker/" .. path .. ".lua")), env)()
        end
        setfenv(assert(loadfile(root .. "/general_tweaker/scripts/mods/general_tweaker/_gt_bot_teleport_lab.lua")), env)()
        H.equal(type(registered), "function")
        -- Inspect the real registered callback's draw dependency without changing
        -- IS_DEV_STREAM, source text, hooks, or any production setting/gate.
        local draw
        for i = 1, 100 do
            local name, value = debug.getupvalue(registered, i)
            if not name then break end
            if name == "_do_draw" then draw = value break end
        end
        H.equal(type(draw), "function")
        return draw, registered, counters, mod, gui
    end

    H.test("gt_public_btlab_material_residency blocks absent unknown and throwing material proof", function()
        local cases = {
            false, {},
            { can_get = function() return false end },
            { can_get = function() return nil end },
            { can_get = function() return "resident" end },
            { can_get = function() error("native proof unavailable") end },
        }
        for _, application in ipairs(cases) do
            local draw, _, counters, mod = btlab_context(application)
            draw(true, false)
            H.equal(counters.creates, 0)
            H.equal(mod._gt_btlab_gui, nil)
        end
    end)

    H.test("gt_public_btlab_material_residency permits the actual native GUI call only after true proof", function()
        local draw, _, counters, mod, gui = btlab_context({ can_get = function() return true end })
        draw(true, false)
        H.equal(counters.probes, 1); H.equal(counters.creates, 1)
        H.equal(mod._gt_btlab_gui, gui)
        draw(true, false)
        H.equal(counters.creates, 1) -- existing GUI is reused, not recreated
    end)

    H.test("gt_public_btlab_material_residency preserves the public Dev-only runtime gate", function()
        local _, registered, counters = btlab_context({ can_get = function() return true end })
        registered(0.016)
        H.equal(counters.probes, 0); H.equal(counters.creates, 0)
    end)

    for _, stream in ipairs({ "dev", "public" }) do
        H.test("GT #797 " .. stream .. " idle mode and scale changes invalidate actual HUD cache", function()
            local directory = stream == "public" and "general_tweaker" or "general_tweaker_dev"
            local id = stream == "public" and "gt" or "gt_dev"
            local settings = {
                gt_devtools_player_stat_hud = true,
                gt_player_stat_hud_mode = "compact",
                gt_player_stat_hud_scale = 100,
                gt_player_stat_hud_position = "bottom_left",
            }
            local unit, update, formats = {}, nil, {}
            local health = {
                is_alive = function() return true end,
                current_health = function() return 100 end,
                get_max_health = function() return 100 end,
                get_base_max_health = function() return 100 end,
            }
            local extensions = {
                health_system = health,
                status_system = {},
                buff_system = { _stat_buffs = {}, _buffs = {}, _num_buffs = 0 },
            }
            local mod = {}
            function mod:get(key) return settings[key] end
            function mod:localize(key) return key end
            function mod:command() end
            function mod._gt_register_update(_, fn) update = fn end
            function mod._gt_rt_register() end
            local env = setmetatable({
                get_mod = function(name) if name == id then return mod end end,
                Managers = { player = { local_player = function() return { player_unit = unit } end } },
                Unit = { alive = function(candidate) return candidate == unit end },
                ScriptUnit = { has_extension = function(_, name) return extensions[name] end },
                printf = function() end,
                _dbg = function() end,
            }, { __index = _G })
            env._G = env
            function mod:dofile(path)
                local value = setfenv(assert(loadfile(root .. "/" .. directory .. "/" .. path .. ".lua")), env)()
                if path:match("_gt_player_stat_hud_policy$") then
                    local all_lines, wrap_lines, max_chars = value.all_lines, value.wrap_lines, value.max_chars
                    value.all_lines = function(snapshot, expanded, text)
                        formats[#formats + 1] = { expanded = expanded }
                        return all_lines(snapshot, expanded, text)
                    end
                    value.wrap_lines = function(lines, maximum)
                        formats[#formats].maximum = maximum
                        return wrap_lines(lines, maximum)
                    end
                    value.max_chars = function(scale)
                        formats[#formats].scale = scale
                        return max_chars(scale)
                    end
                end
                return value
            end
            setfenv(assert(loadfile(root .. "/" .. directory .. "/scripts/mods/" .. directory .. "/_gt_diag_player_stats.lua")), env)()
            local entry = read(directory .. "/scripts/mods/" .. directory .. "/" .. directory .. ".lua")
            local handler = assert(entry:match("(mod.on_setting_changed = function%(setting_id%).-\nend)\n\nmod.on_disabled"))
            local factory = assert(loadstring("return function(mod)\n" .. handler .. "\nreturn mod.on_setting_changed\nend"))
            local setting_changed = setfenv(factory, env)()(mod)
            update(0.3); H.equal(#formats, 1); H.equal(formats[1].expanded, false)
            update(0.3); H.equal(#formats, 1) -- no stat/action change
            settings.gt_player_stat_hud_mode = "expanded"
            setting_changed("gt_player_stat_hud_mode")
            update(0.3); H.equal(#formats, 2); H.equal(formats[2].expanded, true)
            settings.gt_player_stat_hud_scale = 125
            setting_changed("gt_player_stat_hud_scale")
            update(0.3); H.equal(#formats, 3)
            H.equal(formats[3].scale, 125)
            H.equal(formats[2].scale, 100)
            update(0.3); H.equal(#formats, 3)
        end)
    end
end
