return function(H, repo_root)
    local root = repo_root
        .. "/chaos_wastes_tweaker_dev/scripts/mods/chaos_wastes_tweaker_dev/"
    local module_path = root .. "_ct_progressive_elite_runtime.lua"
    local audit_path = root .. "_ct_progressive_elite_audit.lua"
    local entry_path = root .. "chaos_wastes_tweaker_dev.lua"
    local data_path = root .. "chaos_wastes_tweaker_dev_data.lua"
    local loc_path = root .. "chaos_wastes_tweaker_dev_localization.lua"
    local Policy = assert(loadfile(root .. "_ct_progressive_elite_policy.lua"))()
    local HOOK_KEY = "ConflictDirector._post_spawn_unit"

    local function read(path)
        local file = assert(io.open(path, "rb"))
        local source = file:read("*a")
        file:close()
        return source
    end

    local function count_plain(source, needle)
        local count, cursor = 0, 1
        while true do
            local at = source:find(needle, cursor, true)
            if not at then return count end
            count = count + 1
            cursor = at + #needle
        end
    end

    local function with_globals(values, body)
        local saved = {}
        for key, value in pairs(values) do
            saved[key] = rawget(_G, key)
            _G[key] = value
        end
        local ok, err = pcall(body)
        for key in pairs(values) do
            _G[key] = saved[key]
        end
        if not ok then error(err, 0) end
    end

    local function catalog_templates()
        local templates = { elite_base = { name = "elite_base" } }
        for _, row in ipairs(Policy.CATALOG) do
            templates[row.name] = { name = row.name }
        end
        return templates
    end

    local function engine_seams(extra)
        local seams = {
            ConflictDirector = { _post_spawn_unit = function() end },
            TerrorEventUtils = { apply_breed_enhancements = function() end },
            AISystem = { get_attributes = function() end },
        }
        for key, value in pairs(extra or {}) do seams[key] = value end
        return seams
    end

    local ELITE = { elite = true, name = "chaos_warrior" }
    local SPECIAL = { special = true, name = "skaven_gutter_runner" }
    local MONSTER = { boss = true, elite = true, name = "chaos_troll" }
    local TRASH = { name = "skaven_slave" }

    local function fixture(opts)
        opts = opts or {}
        local hooks, order, settings, logs, rt = {}, {}, {}, {}, {}
        local mod = {}
        function mod:hook(class_name, method_name, callback)
            H.equal(hooks[class_name .. "." .. method_name], nil,
                "duplicate hook " .. class_name .. "." .. method_name)
            hooks[class_name .. "." .. method_name] = callback
            order[#order + 1] = "hook:" .. class_name .. "." .. method_name
        end
        function mod:hook_safe(class_name, method_name, callback)
            H.equal(hooks[class_name .. "." .. method_name], nil,
                "duplicate safe hook " .. class_name .. "." .. method_name)
            hooks[class_name .. "." .. method_name] = callback
            order[#order + 1] = "safe:" .. class_name .. "." .. method_name
        end
        mod._ct_rt_register = function(name, fn)
            rt[name] = fn
        end
        local templates
        if opts.templates == false then
            templates = nil
        elseif opts.templates then
            templates = opts.templates
        else
            templates = catalog_templates()
        end
        -- `marked[unit]` models AISystem attributes.grudge_marked.name_index.
        local env = { server = true, depth = 4, marked = {}, applied = {} }
        local installer = assert(loadfile(module_path))()
        local ctx = {
            mod = mod,
            policy = Policy,
            effective_setting = function(id) return settings[id] end,
            is_server = function() return env.server end,
            completed_level_count = function()
                if env.depth_error then error("controller exploded") end
                return env.depth
            end,
            already_marked = function(ai_unit)
                if env.marked_error then error("attributes exploded") end
                return env.marked[ai_unit] ~= nil
            end,
            apply_enhancements = function(ai_unit, breed, data)
                if env.apply_error then error("apply exploded") end
                env.applied[#env.applied + 1] = { unit = ai_unit, breed = breed, data = data }
                env.marked[ai_unit] = data.name_index
            end,
            templates = function() return templates end,
            log = function(fmt, ...) logs[#logs + 1] = string.format(fmt, ...) end,
        }
        local state = installer(ctx)
        return {
            mod = mod, hooks = hooks, order = order, settings = settings, logs = logs,
            rt = rt, env = env, templates = templates, state = state, ctx = ctx,
            installer = installer,
        }
    end

    local function unit_for(spawn_queue_id)
        return "unit_" .. tostring(spawn_queue_id)
    end

    -- Drive the captured hook with vanilla's exact _post_spawn_unit argument list.
    local function run_hook(f, breed, optional_data, spawn_queue_id, vanilla)
        local hook = assert(f.hooks[HOOK_KEY])
        local calls = {}
        local func = vanilla or function(...)
            calls[#calls + 1] = { n = select("#", ...), ... }
            return "ret_" .. tostring(spawn_queue_id), 77, nil, "tail"
        end
        local r = { n = 0 }
        local function capture(...)
            r.n = select("#", ...)
            for i = 1, r.n do r[i] = select(i, ...) end
        end
        capture(hook(func, "director", unit_for(spawn_queue_id), 12, breed, "pos", "cat",
            "anim", optional_data, "type", spawn_queue_id))
        return calls, r
    end

    local function applied_to(f, spawn_queue_id)
        local unit = unit_for(spawn_queue_id)
        for _, row in ipairs(f.env.applied) do
            if row.unit == unit then return row end
        end
    end

    local function count_expected(depth, step, templates)
        local n = 0
        for index = 1, 400 do
            if Policy.enhancements_for_spawn(index, ELITE, depth, templates, step) then
                n = n + 1
            end
        end
        return n
    end

    local function count_rows(logs, needle)
        local rows = 0
        for _, row in ipairs(logs) do
            if row:find(needle, 1, true) then rows = rows + 1 end
        end
        return rows
    end

    -- ------------------------------------------------------------------
    -- registration boundary
    -- ------------------------------------------------------------------
    H.test("CT #323 runtime installs exactly one hook on ConflictDirector._post_spawn_unit", function()
        local f = fixture()
        H.deep_equal(f.order, { "hook:" .. HOOK_KEY })
        H.equal(f.state.installed, true)
        H.equal(f.state.hook_pair, HOOK_KEY)
        H.equal(f.state.setting_id, "progressive_elite_enhancements")
        H.equal(f.state.step_setting_id, "progressive_elite_step_percent")
        H.equal(f.mod._ct_progressive_elite_runtime_state, f.state)
        H.equal(type(f.rt.issue323_progressive_elite_runtime), "function")
        H.equal(f.state.activation(), "disabled")
        H.equal(f.state.rate_label(), "0/5/10/15/20")
        H.equal(#f.logs, 1)
        H.equal(f.logs[1]:find("[ct:323] runtime installed activation=disabled rates=0/5/10/15/20 hook=ConflictDirector._post_spawn_unit", 1, true) ~= nil, true)
    end)

    H.test("CT #323 a second install is idempotent and never re-hooks", function()
        local f = fixture()
        local again = f.installer(f.ctx)
        H.equal(again, f.state)
        H.equal(#f.order, 1)
    end)

    H.test("CT #323 ctx contract is load-time asserted", function()
        local f = fixture()
        H.equal(pcall(f.installer, nil), false)
        H.equal(pcall(f.installer, "nope"), false)
        for _, key in ipairs({ "mod", "effective_setting", "policy" }) do
            local partial = {}
            for k, v in pairs(f.ctx) do partial[k] = v end
            partial.mod = {}  -- fresh mod (no dofile) so the idempotent early-return cannot mask it
            partial[key] = nil
            H.equal(pcall(f.installer, partial), false, "missing " .. key .. " must assert")
        end
    end)

    H.test("CT #323 entry-shaped install (mod + effective_setting only) binds the live engine seams", function()
        local hooks, order, settings = {}, {}, {}
        local mod = {}
        function mod:hook(class_name, method_name, callback)
            hooks[class_name .. "." .. method_name] = callback
            order[#order + 1] = class_name .. "." .. method_name
        end
        function mod:dofile(path)
            H.equal(path, "scripts/mods/chaos_wastes_tweaker_dev/_ct_progressive_elite_policy")
            return Policy
        end
        local rt = {}
        mod._ct_rt_register = function(name, fn) rt[name] = fn end
        local printed, applied = {}, {}
        local catalog = catalog_templates()
        local live = { is_server = true, depth = 4, attributes = {} }
        local ai_system = {}
        function ai_system:get_attributes(unit)
            H.equal(self, ai_system, "attributes must be read through the live AI system")
            return live.attributes[unit] or {}
        end
        local seams = engine_seams({
            printf = function(fmt, ...) printed[#printed + 1] = string.format(fmt, ...) end,
            BreedEnhancements = catalog,
            TerrorEventUtils = {
                apply_breed_enhancements = function(unit, breed, data)
                    applied[#applied + 1] = { unit = unit, breed = breed, data = data }
                end,
            },
            AISystem = { get_attributes = ai_system.get_attributes },
            Managers = {
                player = setmetatable({}, { __index = function(_, k)
                    if k == "is_server" then return live.is_server end
                end }),
                state = {
                    entity = {
                        system = function(_, name)
                            H.equal(name, "ai_system")
                            return ai_system
                        end,
                    },
                },
                mechanism = {
                    game_mechanism = function()
                        if live.no_run then return nil end
                        return {
                            get_deus_run_controller = function()
                                return { get_completed_level_count = function() return live.depth end }
                            end,
                        }
                    end,
                },
            },
        })
        with_globals(seams, function()
            local state = assert(loadfile(module_path))()({
                mod = mod,
                effective_setting = function(id) return settings[id] end,
            })
            H.deep_equal(order, { HOOK_KEY })
            H.equal(#printed, 1)
            H.equal(printed[1]:find("[ct:323] runtime installed", 1, true) ~= nil, true)
            settings.progressive_elite_enhancements = true
            settings.progressive_elite_step_percent = 25
            local hook = hooks[HOOK_KEY]
            local function drive(data, unit, id)
                local called = 0
                hook(function() called = called + 1 end, "director", unit, 1, ELITE, "p", "c",
                    "a", data, "t", id)
                H.equal(called, 1)
            end
            local data = { side_id = 2 }
            drive(data, "u1", 1)
            H.equal(#applied, 1)
            H.equal(applied[1].unit, "u1")
            H.equal(applied[1].breed, ELITE)
            H.equal(applied[1].data ~= data, true, "marks travel in a private table")
            H.equal(applied[1].data.enhancements[1], catalog.elite_base)
            H.equal(applied[1].data.enhancements[2] == catalog.shockwave
                or applied[1].data.enhancements[2] == catalog.ignore_death_aura, true)
            H.equal(applied[1].data.name_index, Policy.name_index(1, "chaos_warrior"))
            H.equal(data.enhancements, nil, "the spawn payload is never written")
            H.equal(data.name_index, nil)
            -- A unit vanilla already marked keeps its own marks.
            live.attributes.u2 = { grudge_marked = { name_index = 99 } }
            drive({}, "u2", 2)
            H.equal(#applied, 1)
            H.equal(state.preserved, 1)
            -- A freezer-reused unit keeps an emptied category table; it still rolls.
            live.attributes.u3 = { grudge_marked = {} }
            drive({}, "u3", 3)
            H.equal(#applied, 2)
            live.is_server = false
            drive({}, "u4", 4)
            H.equal(#applied, 2, "client side never applies")
            live.is_server = true
            live.no_run = true
            drive({}, "u5", 5)
            H.equal(#applied, 2, "no Deus run means no depth means no selection")
            live.no_run = false
            live.depth = 0
            drive({}, "u6", 6)
            H.equal(#applied, 2, "first map stays at zero percent")
            H.equal(state.applied, 2)
            H.equal(state.errors, 0)
            H.equal(state.no_identity, 0)
            H.equal(rt.issue323_progressive_elite_runtime(), nil)
            -- No spawn queue id: nothing applies and the runtime check reports it.
            live.depth = 4
            drive({}, "u7", nil)
            H.equal(#applied, 2)
            H.equal(state.no_identity, 1)
            H.equal(type(rt.issue323_progressive_elite_runtime()), "string")
        end)
    end)

    H.test("CT #323 runtime check fails closed when an engine seam is missing", function()
        local f = fixture()
        with_globals(engine_seams(), function()
            H.equal(f.rt.issue323_progressive_elite_runtime(), nil)
        end)
        with_globals(engine_seams({ ConflictDirector = {} }), function()
            H.equal(f.rt.issue323_progressive_elite_runtime(),
                "ConflictDirector._post_spawn_unit seam missing")
        end)
        with_globals(engine_seams({ TerrorEventUtils = {} }), function()
            H.equal(f.rt.issue323_progressive_elite_runtime(),
                "TerrorEventUtils.apply_breed_enhancements seam missing")
        end)
        with_globals(engine_seams({ AISystem = {} }), function()
            H.equal(f.rt.issue323_progressive_elite_runtime(),
                "AISystem.get_attributes seam missing")
        end)
    end)

    -- ------------------------------------------------------------------
    -- default-off / host-only gates
    -- ------------------------------------------------------------------
    H.test("CT #323 default-off: vanilla runs untouched with every argument and return", function()
        local f = fixture()
        local data = { side_id = 2 }
        local calls, r = run_hook(f, ELITE, data, 5)
        H.equal(#calls, 1)
        H.equal(calls[1].n, 10)
        H.equal(calls[1][1], "director")
        H.equal(calls[1][2], "unit_5")
        H.equal(calls[1][4], ELITE)
        H.equal(calls[1][8], data)
        H.equal(calls[1][10], 5)
        H.equal(data.enhancements, nil)
        H.equal(r.n, 4)
        H.equal(r[1], "ret_5")
        H.equal(r[2], 77)
        H.equal(r[3], nil)
        H.equal(r[4], "tail")
        H.equal(#f.env.applied, 0)
        H.equal(f.state.applied, 0)
    end)

    H.test("CT #323 trailing vanilla arguments pass through unchanged", function()
        local f = fixture()
        local hook = f.hooks[HOOK_KEY]
        local seen
        hook(function(...) seen = { n = select("#", ...), ... } end, "director", "u", 1, ELITE,
            "p", "c", "a", {}, "t", 1, "extra", nil)
        H.equal(seen.n, 12)
        H.equal(seen[11], "extra")
    end)

    H.test("CT #323 a client never marks an elite even when enabled", function()
        local f = fixture()
        f.settings.progressive_elite_enhancements = true
        f.env.server = false
        for index = 1, 200 do
            local calls = run_hook(f, ELITE, {}, index)
            H.equal(#calls, 1)
        end
        H.equal(#f.env.applied, 0)
        H.equal(f.state.applied, 0)
    end)

    H.test("CT #323 setting must be exactly true", function()
        local f = fixture()
        for _, value in ipairs({ "true", 1, {} }) do
            f.settings.progressive_elite_enhancements = value
            run_hook(f, ELITE, {}, 1)
        end
        H.equal(#f.env.applied, 0)
        H.equal(f.state.applied, 0)
    end)

    -- ------------------------------------------------------------------
    -- enabled host behaviour
    -- ------------------------------------------------------------------
    H.test("CT #323 enabled host marks only allowlisted recipes on ordinary elites under the rate", function()
        local f = fixture()
        f.settings.progressive_elite_enhancements = true
        f.env.depth = 4
        local boss = {}
        for _, row in ipairs(Policy.CATALOG) do
            if row.tier == "boss_unproven" then boss[row.name] = true end
        end
        local applied, seen = 0, {}
        for index = 1, 400 do
            local data = {}
            local calls, r = run_hook(f, ELITE, data, index)
            H.equal(#calls, 1)
            H.equal(calls[1][8], data, "vanilla must receive the same table")
            H.equal(r[1], "ret_" .. index)
            H.equal(data.enhancements, nil, "spawn payload untouched " .. index)
            local expected = Policy.enhancements_for_spawn(index, ELITE, 4, f.templates, 5)
            local row = applied_to(f, index)
            if expected then
                applied = applied + 1
                H.equal(row ~= nil, true, "spawn " .. index)
                H.equal(#row.data.enhancements, 2)
                H.equal(row.data.enhancements[1], f.templates.elite_base)
                H.equal(row.data.enhancements[2], expected[2])
                H.equal(boss[row.data.enhancements[2].name], nil)
                H.equal(Policy.is_elite_recipe(row.data.enhancements[2].name), true)
                H.equal(row.data.name_index, Policy.name_index(index, ELITE.name))
                seen[row.data.enhancements[2].name] = true
            else
                H.equal(row, nil, "spawn " .. index)
            end
        end
        H.equal(applied, count_expected(4, 5, f.templates))
        H.equal(applied > 0, true)
        H.equal(applied < 400, true)
        H.equal(f.state.applied, applied)
        H.equal(seen.shockwave, true)
        H.equal(seen.ignore_death_aura, true)
    end)

    H.test("CT #323 marks are applied after vanilla and never stack onto a vanilla-marked unit", function()
        local f = fixture()
        f.settings.progressive_elite_enhancements = true
        f.settings.progressive_elite_step_percent = 25  -- 100 percent for elites
        f.env.depth = 4
        local trace = {}
        -- Geheimnisnacht Hard Mode shape: vanilla appends and applies inside
        -- _post_spawn_unit (mutator_geheimnisnacht_2021_hard_mode.lua:144-152;
        -- conflict_director.lua:2034-2041).
        run_hook(f, ELITE, {}, 1, function(_, ai_unit, _, _, _, _, _, optional_data)
            trace[#trace + 1] = "vanilla"
            H.equal(#f.env.applied, 0, "CT must not apply before vanilla returns")
            optional_data.enhancements = { f.templates.elite_base, f.templates.ignore_death_aura }
            f.env.marked[ai_unit] = 1234
        end)
        H.deep_equal(trace, { "vanilla" })
        H.equal(#f.env.applied, 0, "no second elite_base")
        H.equal(f.state.preserved, 1)
        -- The same unit marked only through attributes (payload already cleaned).
        run_hook(f, ELITE, {}, 2, function(_, ai_unit)
            f.env.marked[ai_unit] = 7
        end)
        H.equal(#f.env.applied, 0)
        H.equal(f.state.preserved, 2)
        -- An untouched spawn is marked right after vanilla.
        run_hook(f, ELITE, {}, 3, function() trace[#trace + 1] = "vanilla" end)
        H.equal(#f.env.applied, 1)
        H.equal(f.state.applied, 1)
    end)

    H.test("CT #323 a shared horde or recycler payload never carries marks to another unit", function()
        local f = fixture()
        f.settings.progressive_elite_enhancements = true
        f.settings.progressive_elite_step_percent = 25
        f.env.depth = 4
        -- One horde table for every unit (horde_spawner.lua:1236-1242).
        local shared = { side_id = 2 }
        run_hook(f, ELITE, shared, 10)
        run_hook(f, TRASH, shared, 11)
        run_hook(f, SPECIAL, shared, 12)
        run_hook(f, ELITE, shared, 13)
        H.equal(shared.enhancements, nil)
        H.equal(shared.name_index, nil)
        local keys = 0
        for _ in pairs(shared) do keys = keys + 1 end
        H.equal(keys, 1, "only vanilla's own side_id remains")
        H.equal(#f.env.applied, 2)
        H.equal(f.env.applied[1].unit, unit_for(10))
        H.equal(f.env.applied[2].unit, unit_for(13))
        H.equal(f.env.applied[1].data ~= f.env.applied[2].data, true, "one private table per unit")
    end)

    H.test("CT #323 specials, monsters and trash are never marked", function()
        local f = fixture()
        f.settings.progressive_elite_enhancements = true
        f.settings.progressive_elite_step_percent = 25  -- 100 percent for elites
        f.env.depth = 4
        for index = 1, 200 do
            for _, breed in ipairs({ SPECIAL, MONSTER, TRASH }) do
                local calls = run_hook(f, breed, {}, index)
                H.equal(#calls, 1)
            end
            H.equal(run_hook(f, nil, {}, index) ~= nil, true)
        end
        H.equal(#f.env.applied, 0)
        H.equal(f.state.applied, 0)
        H.equal(f.state.preserved, 0)
        run_hook(f, ELITE, {}, 1)
        H.equal(#f.env.applied, 1, "elite at 100 percent applies")
        H.equal(f.state.applied, 1)
    end)

    H.test("CT #323 an existing enhancement list in the payload is respected", function()
        local f = fixture()
        f.settings.progressive_elite_enhancements = true
        f.settings.progressive_elite_step_percent = 25
        f.env.depth = 4
        local preset = { { name = "base" }, { name = "crushing" } }
        local data = { enhancements = preset }
        run_hook(f, ELITE, data, 1)
        H.equal(data.enhancements, preset)
        run_hook(f, ELITE, { enhancements = {} }, 2)
        H.equal(#f.env.applied, 0, "an empty vanilla list is also respected")
        H.equal(f.state.preserved, 2)
    end)

    H.test("CT #323 nil optional_data passes through untouched and still rolls", function()
        local f = fixture()
        f.settings.progressive_elite_enhancements = true
        f.settings.progressive_elite_step_percent = 25
        f.env.depth = 4
        local calls, r = run_hook(f, ELITE, nil, 3)
        H.equal(#calls, 1)
        H.equal(calls[1].n, 10)
        H.equal(calls[1][8], nil)
        H.equal(r[1], "ret_3")
        H.equal(#f.env.applied, 1)
        H.equal(f.state.errors, 0)
    end)

    H.test("CT #323 first map and non-Deus contexts apply nothing", function()
        local f = fixture()
        f.settings.progressive_elite_enhancements = true
        for _, depth in ipairs({ 0, nil, "4", false }) do
            f.env.depth = depth
            for index = 1, 100 do
                run_hook(f, ELITE, {}, index)
            end
        end
        H.equal(#f.env.applied, 0)
        H.equal(f.state.applied, 0)
        H.equal(f.state.no_identity, 0)
    end)

    H.test("CT #323 step override rescales the rate; step 0 never applies", function()
        local f = fixture()
        f.settings.progressive_elite_enhancements = true
        f.env.depth = 4
        f.settings.progressive_elite_step_percent = 0
        H.equal(f.state.rate_label(), "0/0/0/0/0")
        for index = 1, 200 do run_hook(f, ELITE, {}, index) end
        H.equal(f.state.applied, 0)
        f.settings.progressive_elite_step_percent = 25
        H.equal(f.state.rate_label(), "0/25/50/75/100")
        for index = 201, 400 do run_hook(f, ELITE, {}, index) end
        H.equal(f.state.applied, 200)
        f.settings.progressive_elite_step_percent = 10
        H.equal(f.state.rate_label(), "0/10/20/30/40")
        f.settings.progressive_elite_step_percent = 999
        H.equal(f.state.step(), 25, "step clamps to 25")
        f.settings.progressive_elite_step_percent = "junk"
        H.equal(f.state.step(), 5, "junk falls back to the default step")
    end)

    -- ------------------------------------------------------------------
    -- containment
    -- ------------------------------------------------------------------
    H.test("CT #323 a throwing selection dependency never blocks vanilla and is bounded", function()
        local f = fixture()
        f.settings.progressive_elite_enhancements = true
        f.env.depth_error = true
        for index = 1, 10 do
            local calls, r = run_hook(f, ELITE, {}, index)
            H.equal(#calls, 1)
            H.equal(calls[1].n, 10)
            H.equal(r[1], "ret_" .. index)
        end
        H.equal(#f.env.applied, 0)
        H.equal(f.state.errors, 10)
        H.equal(f.state.last_error:find("controller exploded", 1, true) ~= nil, true)
        H.equal(count_rows(f.logs, "[ct:323] select_error"), f.state.ERROR_CAP)
        H.equal(f.rt.issue323_progressive_elite_runtime() ~= nil, true,
            "the runtime check reports selection errors")
    end)

    H.test("CT #323 a throwing attribute read is contained as a selection error", function()
        local f = fixture()
        f.settings.progressive_elite_enhancements = true
        f.settings.progressive_elite_step_percent = 25
        f.env.marked_error = true
        local calls = run_hook(f, ELITE, {}, 1)
        H.equal(#calls, 1)
        H.equal(#f.env.applied, 0)
        H.equal(f.state.errors, 1)
    end)

    H.test("CT #323 a throwing vanilla apply is contained, counted and bounded", function()
        local f = fixture()
        f.settings.progressive_elite_enhancements = true
        f.settings.progressive_elite_step_percent = 25
        f.env.apply_error = true
        for index = 1, 6 do
            local calls, r = run_hook(f, ELITE, {}, index)
            H.equal(#calls, 1)
            H.equal(r[1], "ret_" .. index)
        end
        H.equal(f.state.applied, 0)
        H.equal(f.state.errors, 6)
        H.equal(count_rows(f.logs, "[ct:323] apply_error"), f.state.ERROR_CAP)
        H.equal(f.rt.issue323_progressive_elite_runtime() ~= nil, true)
    end)

    H.test("CT #323 a missing templates catalog applies nothing and never throws", function()
        local g = fixture({ templates = false })
        g.settings.progressive_elite_enhancements = true
        g.settings.progressive_elite_step_percent = 25
        g.env.depth = 4
        local calls = run_hook(g, ELITE, {}, 1)
        H.equal(#calls, 1)
        H.equal(#g.env.applied, 0)
        H.equal(g.state.errors, 0)
        H.equal(g.state.applied, 0)
    end)

    H.test("CT #323 observers run after vanilla and the apply, and are contained", function()
        local f = fixture()
        f.settings.progressive_elite_enhancements = true
        f.settings.progressive_elite_step_percent = 25
        f.env.depth = 4
        local trace = {}
        f.state.add_observer(function(breed, spawn_queue_id, applied_recipe, optional_data)
            trace[#trace + 1] = { "observe", breed, spawn_queue_id, applied_recipe,
                optional_data, #f.env.applied }
        end)
        f.state.add_observer(function() error("observer exploded") end)
        f.state.add_observer("not a function")
        H.equal(#f.state.observers, 2)
        local data = {}
        local _, r = run_hook(f, ELITE, data, 9, function()
            trace[#trace + 1] = { "vanilla" }
            return "ret_9"
        end)
        H.equal(r[1], "ret_9")
        H.equal(#trace, 2)
        H.equal(trace[1][1], "vanilla")
        H.equal(trace[2][1], "observe")
        H.equal(trace[2][2], ELITE)
        H.equal(trace[2][3], 9)
        H.equal(Policy.is_elite_recipe(trace[2][4]), true)
        H.equal(trace[2][5], data)
        H.equal(trace[2][6], 1, "observers run after the apply")
        trace = {}
        run_hook(f, SPECIAL, {}, 10, function() trace[#trace + 1] = { "vanilla" } end)
        H.equal(trace[2][4], nil, "no recipe reported for a special")
        H.equal(trace[2][3], 10, "observers still receive the spawn id")
    end)

    H.test("CT #323 apply log rows are capped per session", function()
        local f = fixture()
        f.settings.progressive_elite_enhancements = true
        f.settings.progressive_elite_step_percent = 25
        f.env.depth = 4
        for index = 1, 40 do run_hook(f, ELITE, {}, index) end
        H.equal(count_rows(f.logs, "[ct:323] apply "), f.state.LOG_CAP)
        H.equal(f.state.applied, 40)
        H.equal(f.logs[2]:find("recipe=", 1, true) ~= nil, true)
        H.equal(f.logs[2]:find("spawn=1 completed=4 rate=100", 1, true) ~= nil, true)
    end)

    -- ------------------------------------------------------------------
    -- runtime regression check
    -- ------------------------------------------------------------------
    H.test("CT #323 runtime check passes on the vanilla catalog shape and fails on drift", function()
        local boss = {}
        for _, row in ipairs(Policy.CATALOG) do
            if row.tier == "boss_unproven" then boss[row.name] = true end
        end
        with_globals(engine_seams({ BossGrudgeMarks = boss }), function()
            local f = fixture()
            H.equal(f.rt.issue323_progressive_elite_runtime(), nil)
            local missing = catalog_templates()
            missing.shockwave = nil
            local g = fixture({ templates = missing })
            H.equal(type(g.rt.issue323_progressive_elite_runtime()), "string")
            local no_base = catalog_templates()
            no_base.elite_base = nil
            local h = fixture({ templates = no_base })
            H.equal(type(h.rt.issue323_progressive_elite_runtime()), "string")
        end)
        -- If a boss mark ever entered the allowlist the check must refuse it.
        with_globals(engine_seams({ BossGrudgeMarks = { shockwave = true } }), function()
            local f = fixture()
            H.equal(f.rt.issue323_progressive_elite_runtime(),
                "allowlist entry is a boss grudge mark: shockwave")
        end)
    end)

    -- ------------------------------------------------------------------
    -- audit module attaches as an observer and reports runtime state
    -- ------------------------------------------------------------------
    H.test("CT #323 audit observes the runtime hook and reports activation and rates", function()
        local f = fixture()
        f.settings.progressive_elite_enhancements = true
        f.settings.progressive_elite_step_percent = 25
        f.env.depth = 4
        local printed, commands = {}, {}
        function f.mod:dofile(path)
            return assert(loadfile(root .. path:match("([^/]+)$") .. ".lua"))()
        end
        function f.mod:command(name, _, fn) commands[name] = fn end
        local audit
        with_globals({
            get_mod = function(id) H.equal(id, "ct_dev"); return f.mod end,
            printf = function(fmt, ...) printed[#printed + 1] = string.format(fmt, ...) end,
            Managers = {
                mechanism = {
                    game_mechanism = function()
                        return {
                            get_deus_run_controller = function()
                                return { get_completed_level_count = function() return 4 end }
                            end,
                        }
                    end,
                },
            },
        }, function()
            audit = assert(loadfile(audit_path))()
            H.equal(#f.state.observers, 1, "the audit attaches exactly one observer")
            H.equal(#f.order, 1, "the audit registers no hook of its own")
            f.mod.on_game_state_changed("enter", "StateIngame")
            for index = 1, 20 do run_hook(f, ELITE, {}, index) end
            for index = 21, 30 do run_hook(f, SPECIAL, {}, index) end
            run_hook(f, MONSTER, {}, 31)
            commands.ct_progressive_elite_audit()
        end)
        H.equal(type(audit), "table")
        H.equal(#printed, 1)
        local line = printed[1]
        H.equal(line:find("[ct:323] audit=1/7 reason=command completed=4 rate=100 rates=0/25/50/75/100 step=25 ", 1, true) ~= nil, true, line)
        H.equal(line:find(" elite=20 selected=20 applied=20 special=10 selected_special=10 applied_special=0 ", 1, true) ~= nil, true, line)
        H.equal(line:find(" activation=enabled", 1, true) ~= nil, true, line)
        H.equal(type(f.rt.issue323_progressive_elite_feasibility), "function")
    end)

    -- ------------------------------------------------------------------
    -- source-pattern invariants
    -- ------------------------------------------------------------------
    -- Every ct_dev script as of 0.7.350-dev (91 files). The floor assertion in the
    -- test below makes a silently shrinking roster fail instead of passing.
    local CT_SCRIPT_FILES = {
        "_adventure_pool", "_ct_adventure_illusions", "_ct_adventure_runtime_owner",
        "_ct_altar_reuse_owner", "_ct_ammo_guard_core", "_ct_blessed_bots",
        "_ct_bomb_cooldown_display", "_ct_boon_balance", "_ct_boon_grant_owner",
        "_ct_boon_offer_view_owner", "_ct_boon_preview_helpers", "_ct_boon_preview_runtime",
        "_ct_boon_preview_tooltip", "_ct_boon_pricing_audit", "_ct_boon_pricing_policy",
        "_ct_boon_pricing_runtime", "_ct_boon_registry", "_ct_boon_runtime_owner",
        "_ct_boss_grudge_marks", "_ct_bot_coin_pickup", "_ct_bot_economy",
        "_ct_bot_weapon_chest_owner", "_ct_campaign_graph_owner", "_ct_chest_count_audit_core",
        "_ct_chest_revive_owner", "_ct_chest_revive_policy", "_ct_collectible_policy",
        "_ct_combat_hooks", "_ct_command_owner", "_ct_cot_cost", "_ct_cot_cost_policy",
        "_ct_cot_early_reward", "_ct_cot_early_reward_core", "_ct_cot_placement_policy",
        "_ct_curse_lighting_owner", "_ct_dev_mission", "_ct_dev_mission_catalog",
        "_ct_diag_cursed_chest132", "_ct_diag_gargoyle1124", "_ct_diag_skull52",
        "_ct_diag_tab_native533", "_ct_dup_vote_chips", "_ct_host_state_transport_owner",
        "_ct_journey_difficulty_guard", "_ct_level_load_owner", "_ct_mechanic_tweaks",
        "_ct_meta_boon_owner", "_ct_meta_trait_boons", "_ct_miasma", "_ct_miasma_policy",
        "_ct_modifier_stack_audit", "_ct_modifier_stack_policy", "_ct_node_entry_owner",
        "_ct_parry_cooldown_policy", "_ct_peer_manifest_owner", "_ct_peer_parity_owner",
        "_ct_pickup_population_owner", "_ct_pickup_spawn_owner", "_ct_pilgrimage_context",
        "_ct_profile_snapshot", "_ct_progressive_difficulty", "_ct_progressive_elite_audit",
        "_ct_progressive_elite_policy", "_ct_progressive_elite_runtime", "_ct_regression",
        "_ct_regression_resource_safety", "_ct_replacement_compensation",
        "_ct_replacement_runtime", "_ct_resume_audit", "_ct_resume_policy",
        "_ct_run_creation_owner", "_ct_run_runtime_owner", "_ct_settings_lifecycle_owner",
        "_ct_spawn_eligibility_owner", "_ct_stack_rebroadcast_owner", "_ct_start_shrine_policy",
        "_ct_start_shrine_runtime", "_ct_starting_coins_policy", "_ct_tab_collectibles_layout",
        "_ct_tab_panel_owner", "_ct_umbrella_policy", "_ct_weapon_trait_generation",
        "_ct_weave_curse_audit", "_ct_weave_curse_policy", "_ct_wire_policy", "_lib_peer_parity",
        "_lib_wire_catalog", "chaos_wastes_tweaker_dev", "chaos_wastes_tweaker_dev_data",
        "chaos_wastes_tweaker_dev_localization", "chaos_wastes_tweaker_mutex",
    }

    H.test("CT #323 entry installs the runtime once, before the audit, and no other hook shares the seam", function()
        local entry = read(entry_path)
        local runtime = read(module_path)
        local audit = read(audit_path)
        H.equal(count_plain(entry,
            'mod:dofile("scripts/mods/chaos_wastes_tweaker_dev/_ct_progressive_elite_runtime")'), 1)
        H.equal(count_plain(entry,
            'mod:dofile("scripts/mods/chaos_wastes_tweaker_dev/_ct_progressive_elite_audit")'), 1)
        local runtime_at = entry:find("_ct_progressive_elite_runtime\")", 1, true)
        local audit_at = entry:find("_ct_progressive_elite_audit\")", 1, true)
        H.equal(runtime_at < audit_at, true, "runtime must install before the audit")
        H.equal(count_plain(runtime, 'mod:hook("ConflictDirector", "_post_spawn_unit"'), 1)
        H.equal(count_plain(runtime, "_ct_consolidated_post_spawn_unit_hook"), 1)
        H.equal(count_plain(runtime, "-- hook-test: issue323_progressive_elite_runtime"), 1)
        H.equal(count_plain(audit, "mod:hook"), 0, "the audit must not hook anything")
        H.equal(count_plain(audit, "add_observer(_observe)"), 1)
        -- Vanilla must run before the CT apply, and the spawn payload is never a
        -- write target (shared by horde units and recycled respawns).
        local vanilla_at = runtime:find("pack(func(self, ai_unit, go_id, breed, spawn_pos,", 1, true)
        local apply_at = runtime:find("pcall(apply_enhancements, ai_unit, breed, private_data)", 1, true)
        H.equal(vanilla_at ~= nil and apply_at ~= nil and vanilla_at < apply_at, true,
            "vanilla must precede the CT apply")
        H.equal(runtime:find("optional_data%.[%w_]+%s*=[^=]"), nil,
            "the runtime must never assign into optional_data")
        H.equal(#CT_SCRIPT_FILES >= 91, true, "script roster shrank")
        for _, name in ipairs(CT_SCRIPT_FILES) do
            local source = read(root .. name .. ".lua")
            local expected = name == "_ct_progressive_elite_runtime" and 1 or 0
            H.equal(count_plain(source, '"_post_spawn_unit"'), expected, name .. " _post_spawn_unit")
        end
    end)

    H.test("CT #323 data exposes the default-off toggle and localization covers every key", function()
        local data = read(data_path)
        local loc = read(loc_path)
        local at = data:find('setting_id = "progressive_elite_enhancements"', 1, true)
        H.equal(at ~= nil, true)
        H.equal(count_plain(data, 'setting_id = "progressive_elite_enhancements"'), 1)
        H.equal(count_plain(data, 'setting_id = "progressive_elite_step_percent"'), 1)
        local block = data:sub(at, at + 700)
        H.equal(block:find("default_value = false", 1, true) ~= nil, true, "must default off")
        H.equal(block:find("default_value = 5,", 1, true) ~= nil, true, "step defaults to 5")
        H.equal(block:find("range = { 0, 25 }", 1, true) ~= nil, true)
        for _, key in ipairs({ "progressive_elite_enhancements", "progressive_elite_enhancements_tooltip",
                "progressive_elite_step_percent", "progressive_elite_step_percent_tooltip" }) do
            local needle = "\n    " .. key .. " = { en = "
            H.equal(count_plain(loc, needle), 1, key)
            local key_at = loc:find(needle, 1, true)
            local line = loc:sub(key_at + 1, (loc:find("\n", key_at + 1, true) or #loc) - 1)
            H.equal(line:find("\226\128\148", 1, true), nil, "no em dash in " .. key)
            H.equal(line:find("%[verify%-fix%]") or line:find("%[Issue"), nil,
                "no lifecycle metadata in " .. key)
            local stripped = line:gsub("%%%%", "")
            H.equal(stripped:find("%", 1, true), nil, "every literal percent is escaped in " .. key)
        end
    end)
end
