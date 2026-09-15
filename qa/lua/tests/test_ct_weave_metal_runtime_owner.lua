return function(H, repo_root)
    local root = repo_root
        .. "/chaos_wastes_tweaker_dev/scripts/mods/chaos_wastes_tweaker_dev/"
    local module_path = root .. "_ct_weave_metal_runtime.lua"
    local policy_path = root .. "_ct_weave_metal_policy.lua"
    local entry_path = root .. "chaos_wastes_tweaker_dev.lua"
    local data_path = root .. "chaos_wastes_tweaker_dev_data.lua"
    local audit_path = root .. "_ct_weave_curse_audit.lua"
    local Policy = assert(loadfile(policy_path))()
    local INIT_KEY = "hook:MutatorHandler.init"
    local DESTROY_KEY = "safe:MutatorHandler.destroy"
    local START_KEY = "hook:metal.server.start_function"
    local ARMOR_BREEDS = {
        "skaven_storm_vermin", "skaven_storm_vermin_champion", "skaven_storm_vermin_commander",
        "skaven_storm_vermin_with_shield", "skaven_stormfiend", "skaven_ratling_gunner",
        "skaven_warpfire_thrower", "chaos_warrior", "chaos_bulwark", "beastmen_bestigor",
        "beastmen_standard_bearer",
    }

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

    -- A vanilla-shaped Metal template: the handler-wrapped server/client tables
    -- plus the armor override fields (mutator_metal.lua:21-34).
    local function metal_template(vanilla_start)
        local names = {}
        for i, name in ipairs(ARMOR_BREEDS) do names[i] = name end
        return {
            name = "metal",
            primary_armor_category = 6,
            modify_primary_armor_category_breeds = names,
            server = { start_function = vanilla_start or function() end, stop_function = function() end },
            client = { start_function = function() end, stop_function = function() end },
        }
    end

    local function breeds_catalog()
        local catalog = {}
        for i, name in ipairs(ARMOR_BREEDS) do
            catalog[name] = { primary_armor_category = (i % 2 == 0) and 3 or nil }
        end
        return catalog
    end

    local function fixture(opts)
        opts = opts or {}
        local hooks, order, logs, rt, commands, echoes, settings, sets = {}, {}, {}, {}, {}, {}, {}, {}
        local templates
        if not opts.templates_nil then templates = { metal = metal_template(opts.vanilla_start) } end
        local lookup
        if not opts.lookup_nil then lookup = { metal = 7, [7] = "metal" } end
        local breeds = opts.breeds or breeds_catalog()
        local env = { server = true, mechanism = "deus", buff_system = { name = "buff_system" } }
        local mod = {}
        local function key_for(target, method_name)
            if type(target) == "table" then
                if templates and templates.metal and target == templates.metal.server then
                    return "metal.server." .. method_name
                end
                return "table." .. method_name
            end
            return target .. "." .. method_name
        end
        function mod:hook(target, method_name, callback)
            local key = "hook:" .. key_for(target, method_name)
            H.equal(hooks[key], nil, "duplicate hook " .. key)
            hooks[key] = callback
            order[#order + 1] = key
        end
        function mod:hook_safe(target, method_name, callback)
            local key = "safe:" .. key_for(target, method_name)
            H.equal(hooks[key], nil, "duplicate safe hook " .. key)
            hooks[key] = callback
            order[#order + 1] = key
        end
        function mod:command(name, description, callback)
            H.equal(commands[name], nil, "duplicate command " .. name)
            commands[name] = { description = description, callback = callback }
            order[#order + 1] = "command:" .. name
        end
        function mod:echo(text)
            echoes[#echoes + 1] = text
        end
        mod._ct_rt_register = function(name, fn)
            rt[name] = fn
        end
        local installer = assert(loadfile(module_path))()
        local ctx = {
            mod = mod,
            policy = Policy,
            templates = function() return templates end,
            breeds = function() return breeds end,
            lookup = function() return lookup end,
            mechanism_name = function() return env.mechanism end,
            is_server = function() return env.server end,
            buff_system = function() return env.buff_system end,
            get_setting = function(id) return settings[id] end,
            set_setting = function(id, value)
                settings[id] = value
                sets[#sets + 1] = { id = id, value = value }
            end,
            log = function(fmt, ...) logs[#logs + 1] = string.format(fmt, ...) end,
        }
        if opts.strength_setting ~= nil then settings[Policy.STRENGTH_SETTING] = opts.strength_setting end
        local state = installer(ctx)
        return {
            mod = mod, hooks = hooks, order = order, logs = logs, rt = rt, commands = commands,
            echoes = echoes, settings = settings, sets = sets, env = env, templates = templates,
            breeds = breeds, state = state, ctx = ctx, installer = installer,
            set_templates = function(value) templates = value end,
        }
    end

    -- Drive the captured init hook with a vanilla double recording its arguments.
    local function run_init(f, list)
        local hook = assert(f.hooks[INIT_KEY])
        local calls = {}
        local func = function(...)
            calls[#calls + 1] = { n = select("#", ...), ... }
            return "handler"
        end
        local handler = { tag = "self" }
        local r = { hook(func, handler, list, f.env.server, "network_handler", true, "world", "delegate", "transmit") }
        return calls, r, handler
    end

    local function run_start(f, data)
        local hook = assert(f.hooks[START_KEY])
        local calls = {}
        local func = function(...)
            calls[#calls + 1] = { n = select("#", ...), ... }
            return "vanilla"
        end
        local r = { hook(func, "context", data, "extra") }
        return calls, r
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
    H.test("CT #253 runtime installs exactly its three hooks, one command, one check", function()
        local f = fixture()
        H.deep_equal(f.order, { INIT_KEY, DESTROY_KEY, "command:ct_weave_metal", START_KEY })
        H.equal(f.state.installed, true)
        H.equal(f.state.command, "ct_weave_metal")
        H.deep_equal(f.state.hook_pairs, {
            "MutatorHandler.init", "MutatorHandler.destroy", "MutatorTemplates.metal.server.start_function",
        })
        H.equal(f.mod._ct_weave_metal_state, f.state)
        H.equal(type(f.rt.issue253_metal_wind_adapter), "function")
        H.equal(f.state.enabled, false)
        H.equal(f.state.enabled_at_boot, false)
        H.equal(f.state.exposed_in_menu, false)
        H.equal(f.state.strength, 1)
        H.equal(f.state.bridged, true)
        H.equal(f.state.level, nil)
        H.equal(#f.logs, 1)
        H.equal(f.logs[1], "[ct:253:metal] runtime installed enabled=false strength=1 command=/ct_weave_metal bridged=true hooks=MutatorHandler.init,MutatorHandler.destroy,MutatorTemplates.metal.server.start_function")
        H.truthy(f.commands.ct_weave_metal.description:find("hidden from the curse menu", 1, true))
        H.equal(f.commands.ct_weave_metal.description:find("\226\128\148", 1, true), nil, "no em dash in command text")
    end)

    H.test("CT #253 a second install is idempotent and never re-hooks", function()
        local f = fixture()
        local again = f.installer(f.ctx)
        H.equal(again, f.state)
        H.equal(#f.order, 4)
    end)

    H.test("CT #253 ctx contract is load-time asserted", function()
        local f = fixture()
        H.equal(pcall(f.installer, nil), false)
        H.equal(pcall(f.installer, "nope"), false)
        H.equal(pcall(f.installer, {}), false)
        H.equal(pcall(f.installer, { mod = {}, policy = "bad" }), false)
    end)

    H.test("CT #253 the persisted strength setting seeds the runtime, invalid values fall back", function()
        H.equal(fixture({ strength_setting = 4 }).state.strength, 4)
        H.equal(fixture({ strength_setting = "3" }).state.strength, 3)
        H.equal(fixture({ strength_setting = 9 }).state.strength, 1)
        H.equal(fixture({ strength_setting = "junk" }).state.strength, 1)
    end)

    H.test("CT #253 bridge defers when the template catalog is not loaded yet", function()
        local f = fixture({ templates_nil = true })
        H.equal(f.state.bridged, false)
        H.deep_equal(f.order, { INIT_KEY, DESTROY_KEY, "command:ct_weave_metal" })
        H.truthy(f.logs[1]:find("bridged=false", 1, true))
        -- Enabled on a host Deus level without a bridge: nothing is appended.
        f.state.enabled = true
        local calls, r = run_init(f, { "deus_more_hordes" })
        H.deep_equal(calls[1][2], { "deus_more_hordes" })
        H.equal(f.state.skipped.bridge_missing, 1)
        H.equal(f.state.level, nil)
        H.equal(r[1], "handler")
        -- Once the catalog exists the next level bridges lazily, exactly once.
        f.set_templates({ metal = metal_template() })
        calls = run_init(f, { "deus_more_hordes" })
        H.equal(f.state.bridged, true)
        H.deep_equal(calls[1][2], { "deus_more_hordes", "metal" })
        H.equal(f.order[#f.order], START_KEY)
        run_init(f, { "deus_more_hordes" })
        H.equal(#f.order, 4)
    end)

    -- ------------------------------------------------------------------
    -- per-level activation through MutatorHandler.init
    -- ------------------------------------------------------------------
    H.test("CT #253 default-off: the host list passes through untouched", function()
        local f = fixture()
        local input = { "deus_more_hordes", "curse_empathy" }
        local calls, r, handler = run_init(f, input)
        H.equal(#calls, 1)
        H.equal(calls[1].n, 8)
        H.equal(calls[1][1], handler)
        H.equal(calls[1][2], input, "the very same list object reaches vanilla")
        H.equal(calls[1][3], true)
        H.equal(calls[1][4], "network_handler")
        H.equal(calls[1][5], true)
        H.equal(calls[1][6], "world")
        H.equal(calls[1][7], "delegate")
        H.equal(calls[1][8], "transmit")
        H.equal(r[1], "handler")
        H.equal(f.state.skipped.disabled, 1)
        H.equal(f.state.level, nil)
        H.equal(f.state.activations, 0)
        H.equal(count_rows(f.logs, "[ct:253:metal] armed"), 0)
    end)

    H.test("CT #253 enabled host Deus level: metal is appended to a copy and the context is armed", function()
        local f = fixture({ strength_setting = 3 })
        f.state.enabled = true
        local input = { "deus_more_hordes", "curse_empathy" }
        local calls, r = run_init(f, input)
        H.deep_equal(calls[1][2], { "deus_more_hordes", "curse_empathy", "metal" })
        H.truthy(calls[1][2] ~= input)
        H.deep_equal(input, { "deus_more_hordes", "curse_empathy" }, "input list never mutated")
        H.equal(r[1], "handler")
        H.equal(f.state.activations, 1)
        H.deep_equal(f.state.level.context, { wind = "metal", wind_strength = 3 })
        H.equal(Policy.context_matches(f.state.level.context), true)
        H.equal(f.state.level.breeds, 11)
        H.equal(f.state.level.started, false)
        H.equal(f.state.level.mechanism, "deus")
        H.equal(f.state.level.armor.chaos_warrior, 3)
        H.equal(f.state.level.armor.skaven_storm_vermin, false)
        H.deep_equal(f.state.last, { reason = "appended", list = 3, strength = 3 })
        H.equal(f.logs[#f.logs], "[ct:253:metal] armed strength=3 list=3 breeds=11 mechanism=deus")
    end)

    H.test("CT #253 client, non-Deus, and already-listed levels never append", function()
        local f = fixture()
        f.state.enabled = true
        f.env.server = false
        local calls = run_init(f, { "a" })
        H.deep_equal(calls[1][2], { "a" })
        H.equal(f.state.skipped.client, 1)
        f.env.server = true
        f.env.mechanism = "adventure"
        calls = run_init(f, { "a" })
        H.deep_equal(calls[1][2], { "a" })
        H.equal(f.state.skipped["mechanism:adventure"], 1)
        f.env.mechanism = nil
        calls = run_init(f, { "a" })
        H.equal(f.state.skipped["mechanism:nil"], 1)
        f.env.mechanism = "deus"
        calls = run_init(f, { "metal" })
        H.deep_equal(calls[1][2], { "metal" })
        H.equal(f.state.skipped.already_listed, 1)
        calls = run_init(f, nil)
        H.equal(calls[1][2], nil)
        H.equal(f.state.skipped.no_list, 1)
        H.equal(f.state.activations, 0)
        H.equal(f.state.level, nil)
    end)

    H.test("CT #253 a new level resets the previous armed context first", function()
        local f = fixture()
        f.state.enabled = true
        run_init(f, { "a" })
        H.truthy(f.state.level)
        f.state.enabled = false
        run_init(f, { "a" })
        H.equal(f.state.level, nil)
    end)

    H.test("CT #253 a seam error is recorded and vanilla still runs with the original list", function()
        local mod = {}
        local hooks = {}
        function mod:hook(target, method_name, callback) hooks[method_name] = callback end
        function mod:hook_safe(target, method_name, callback) hooks["safe_" .. method_name] = callback end
        function mod:command() end
        mod._ct_rt_register = function() end
        local logs = {}
        local state = assert(loadfile(module_path))()({
            mod = mod, policy = Policy,
            templates = function() return { metal = metal_template() } end,
            breeds = function() return breeds_catalog() end,
            lookup = function() return { metal = 1 } end,
            mechanism_name = function() error("mechanism exploded") end,
            is_server = function() return true end,
            buff_system = function() return nil end,
            get_setting = function() return nil end,
            set_setting = function() end,
            log = function(fmt, ...) logs[#logs + 1] = string.format(fmt, ...) end,
        })
        state.enabled = true
        local input = { "a" }
        local seen
        local r = hooks.init(function(_, list) seen = list; return "ok" end, {}, input, true)
        H.equal(r, "ok")
        H.equal(seen, input)
        H.equal(state.errors, 1)
        H.truthy(state.last_error:find("mechanism exploded", 1, true))
        H.equal(state.level, nil)
        H.truthy(logs[#logs]:find("[ct:253:metal] prepare_error 1/4", 1, true))
        H.truthy(state.regression():find("runtime errors this session", 1, true))
    end)

    -- ------------------------------------------------------------------
    -- the server start bridge
    -- ------------------------------------------------------------------
    H.test("CT #253 armed level: the CT context replaces the vanilla start body", function()
        local f = fixture({ strength_setting = 2 })
        f.state.enabled = true
        run_init(f, { "a" })
        local data = { template = f.templates.metal }
        local calls, r = run_start(f, data)
        H.equal(#calls, 0, "vanilla server_start body (the Managers.weave read) never runs")
        H.equal(#r, 0)
        H.equal(data.wind_strength, 2)
        H.equal(data.buff_system, f.env.buff_system)
        H.equal(f.state.level.started, true)
        H.equal(f.state.starts, 1)
        H.equal(f.logs[#f.logs], "[ct:253:metal] start wind=metal strength=2 buff_system=true")
    end)

    H.test("CT #253 idle adapter: vanilla start runs untouched with every argument and return", function()
        local f = fixture()
        local data = { template = f.templates.metal }
        local calls, r = run_start(f, data)
        H.equal(#calls, 1)
        H.equal(calls[1].n, 3)
        H.equal(calls[1][1], "context")
        H.equal(calls[1][2], data)
        H.equal(calls[1][3], "extra")
        H.deep_equal(r, { "vanilla" })
        H.equal(data.wind_strength, nil)
        H.equal(f.state.starts, 0)
        -- A non-table data payload also falls through to vanilla.
        f.state.enabled = true
        run_init(f, { "a" })
        calls = run_start(f, nil)
        H.equal(#calls, 1)
    end)

    -- ------------------------------------------------------------------
    -- teardown proof
    -- ------------------------------------------------------------------
    H.test("CT #253 destroy proves exact armor restoration and drops the level context", function()
        local f = fixture()
        f.state.enabled = true
        run_init(f, { "a" })
        run_start(f, { template = f.templates.metal })
        -- vanilla applies category 6 during the level and restores it on stop
        for _, name in ipairs(ARMOR_BREEDS) do f.breeds[name].primary_armor_category = 6 end
        for i, name in ipairs(ARMOR_BREEDS) do
            f.breeds[name].primary_armor_category = (i % 2 == 0) and 3 or nil
        end
        f.hooks[DESTROY_KEY]({})
        H.equal(f.state.level, nil)
        H.equal(f.state.teardowns, 1)
        H.equal(f.state.restored_ok, 1)
        H.equal(f.state.restored_bad, 0)
        H.equal(f.logs[#f.logs], "[ct:253:metal] teardown started=true restored=11/11")
        H.equal(f.rt.issue253_metal_wind_adapter(), nil)
        -- An idle destroy (client, or adapter off) is a no-op.
        f.hooks[DESTROY_KEY]({})
        H.equal(f.state.teardowns, 1)
    end)

    H.test("CT #253 a breed left modified at teardown fails the regression check", function()
        local f = fixture()
        f.state.enabled = true
        run_init(f, { "a" })
        f.breeds.chaos_warrior.primary_armor_category = 6
        f.hooks[DESTROY_KEY]({})
        H.equal(f.state.restored_bad, 1)
        H.equal(f.logs[#f.logs], "[ct:253:metal] teardown started=false restored=10/11")
        H.truthy(f.rt.issue253_metal_wind_adapter():find("armor restoration faults", 1, true))
    end)

    -- ------------------------------------------------------------------
    -- command surface
    -- ------------------------------------------------------------------
    H.test("CT #253 command: status, on, off, strength drive the state and persist strength", function()
        local f = fixture()
        local handle = f.state.handle_command
        local report = handle()
        H.equal(report.action, "status")
        H.equal(report.result, "unchanged")
        H.equal(report.enabled, "false")
        H.equal(report.strength, 1)
        H.equal(report.server, "true")
        H.equal(report.mechanism, "deus")
        H.equal(report.bridged, "true")
        H.equal(report.level, "idle")
        H.truthy(report.text:find("Metal wind adapter: off (hidden from the curse menu)", 1, true))

        report = handle("on")
        H.equal(report.result, "changed")
        H.equal(f.state.enabled, true)
        H.equal(report.enabled, "true")
        H.truthy(report.text:find("Metal wind adapter: ON", 1, true))
        H.equal(report.text:find("Host-owned", 1, true), nil)
        report = handle("on")
        H.equal(report.result, "unchanged")

        report = handle("strength", "4")
        H.equal(report.result, "changed")
        H.equal(f.state.strength, 4)
        H.equal(report.strength, 4)
        H.deep_equal(f.sets, { { id = "weave_metal_strength", value = 4 } })
        report = handle("strength", "4")
        H.equal(report.result, "unchanged")
        H.equal(#f.sets, 1)

        report = handle("off")
        H.equal(report.result, "changed")
        H.equal(f.state.enabled, false)
        H.equal(f.state.strength, 4, "strength survives off")

        report = handle("strength", "9")
        H.equal(report.action, "invalid")
        H.equal(report.result, "rejected")
        H.equal(report.text, "strength must be a whole number from 1 to 5. Usage: /ct_weave_metal on | off | status | strength <1-5>")
        H.equal(f.state.strength, 4)
        report = handle("bogus")
        H.equal(report.result, "rejected")
        H.truthy(report.text:find("unknown action 'bogus'", 1, true))
    end)

    H.test("CT #253 command notes host ownership on a client and mid-level changes", function()
        local f = fixture()
        f.env.server = false
        local report = f.state.handle_command("on")
        H.truthy(report.text:find("Host-owned: takes effect only on missions you host.", 1, true))
        H.equal(report.server, "false")
        f.env.server = true
        run_init(f, { "a" })
        H.truthy(f.state.level)
        report = f.state.handle_command("strength", "5")
        H.equal(report.level, "armed")
        H.truthy(report.text:find("applies from the next mission", 1, true))
        H.equal(f.state.level.context.wind_strength, 1, "the armed level keeps its context")
        report = f.state.handle_command("status")
        H.equal(report.text:find("applies from the next mission", 1, true), nil)
    end)

    H.test("CT #253 the registered command emits the literal [ct:253:diag] receipt and one chat reply", function()
        local f = fixture()
        local printed = {}
        with_globals({
            printf = function(fmt, ...) printed[#printed + 1] = string.format(fmt, ...) end,
        }, function()
            f.commands.ct_weave_metal.callback("on")
            f.commands.ct_weave_metal.callback("strength", "2")
            f.commands.ct_weave_metal.callback()
            f.commands.ct_weave_metal.callback("nope")
        end)
        H.equal(#printed, 4)
        H.equal(printed[1], "[ct:253:diag] action=on result=changed enabled=true strength=1 server=true mechanism=deus bridged=true level=idle")
        H.equal(printed[2], "[ct:253:diag] action=strength result=changed enabled=true strength=2 server=true mechanism=deus bridged=true level=idle")
        H.equal(printed[3], "[ct:253:diag] action=status result=unchanged enabled=true strength=2 server=true mechanism=deus bridged=true level=idle")
        H.equal(printed[4], "[ct:253:diag] action=invalid result=rejected enabled=true strength=2 server=true mechanism=deus bridged=true level=idle")
        H.equal(#f.echoes, 4)
        H.truthy(f.echoes[1]:find("Metal wind adapter: ON", 1, true))
        H.truthy(f.echoes[4]:find("unknown action 'nope'", 1, true))
    end)

    H.test("CT #253 the command callback stays a straight line: helper, receipt, echo", function()
        local source = read(module_path)
        local start = assert(source:find('mod:command("ct_weave_metal"', 1, true))
        local stop = assert(source:find("\n    end)\n", start, true))
        local body = source:sub(start, stop)
        H.equal(count_plain(body, "pcall(printf, \"[ct:253:diag] action=%s result=%s"), 1)
        H.equal(body:find("for ", 1, true), nil, "no loop inside the command callback")
        H.equal(body:find("while ", 1, true), nil)
        H.equal(body:find("repeat", 1, true), nil)
        H.equal(body:find("goto", 1, true), nil)
        H.equal(body:find("function(...)", 1, true) ~= nil, true)
        H.equal(count_plain(body, "function("), 1, "no nested function inside the callback")
        H.equal(count_plain(source, "[ct:253:diag]"), 1, "the diag marker has exactly one emitter")
        H.equal(count_plain(source, "Managers.weave"), 0)
    end)

    -- ------------------------------------------------------------------
    -- regression check
    -- ------------------------------------------------------------------
    H.test("CT #253 regression check passes on a vanilla-shaped catalog and names each drift", function()
        local f = fixture()
        local check = f.rt.issue253_metal_wind_adapter
        H.equal(check(), nil)
        f.state.enabled = true
        run_init(f, { "a" })
        H.equal(check(), nil, "an armed level with a conforming context passes")
        f.state.level.context.weave_manager = {}
        H.truthy(check():find("live context keys drifted", 1, true))
        f.state.level = nil

        local template = f.templates.metal
        template.packages = { "resource_packages/mutators/metal" }
        H.truthy(check():find("declares packages", 1, true))
        template.packages = nil
        template.remove_pickups = { "all" }
        H.truthy(check():find("declares remove_pickups", 1, true))
        template.remove_pickups = nil
        template.primary_armor_category = 5
        H.truthy(check():find("primary_armor_category drift", 1, true))
        template.primary_armor_category = 6
        table.remove(template.modify_primary_armor_category_breeds)
        H.truthy(check():find("armor breed list drift", 1, true))
        template.modify_primary_armor_category_breeds[#template.modify_primary_armor_category_breeds + 1] = "beastmen_standard_bearer"
        H.equal(check(), nil)

        f.state.enabled_at_boot = true
        H.equal(check(), "adapter is not off by default")
        f.state.enabled_at_boot = false
        f.state.exposed_in_menu = true
        H.equal(check(), "adapter claims curse-menu exposure")
        f.state.exposed_in_menu = false
        f.state.command = "ct_weave"
        H.truthy(check():find("command drift", 1, true))
        f.state.command = "ct_weave_metal"
        f.mod._ct_weave_metal_state = {}
        H.equal(check(), "adapter state is not the registered owner")
        f.mod._ct_weave_metal_state = f.state
        H.equal(check(), nil)
    end)

    H.test("CT #253 regression check fails without the wire entry or the template", function()
        local f = fixture({ lookup_nil = true })
        H.truthy(f.rt.issue253_metal_wind_adapter():find("NetworkLookup.mutator_templates.metal missing", 1, true))
        local g = fixture({ templates_nil = true })
        H.equal(g.rt.issue253_metal_wind_adapter(), "MutatorTemplates.metal missing")
    end)

    -- ------------------------------------------------------------------
    -- entry-shaped install against live-shaped globals
    -- ------------------------------------------------------------------
    H.test("CT #253 entry-shaped install ({ mod = mod }) binds the live seams", function()
        local hooks, order = {}, {}
        local templates = { metal = metal_template(function() error("vanilla start ran") end) }
        local breeds = breeds_catalog()
        local mod = {}
        function mod:hook(target, method_name, callback)
            local key = (type(target) == "table" and "server" or target) .. "." .. method_name
            hooks[key] = callback
            order[#order + 1] = key
        end
        function mod:hook_safe(target, method_name, callback)
            hooks["safe." .. target .. "." .. method_name] = callback
            order[#order + 1] = "safe." .. target .. "." .. method_name
        end
        function mod:command(name, _, callback) hooks["command." .. name] = callback end
        function mod:echo() end
        function mod:dofile(path)
            H.equal(path, "scripts/mods/chaos_wastes_tweaker_dev/_ct_weave_metal_policy")
            return Policy
        end
        local stored = {}
        function mod:get(id) return stored[id] end
        function mod:set(id, value) stored[id] = value end
        local rt = {}
        mod._ct_rt_register = function(name, fn) rt[name] = fn end
        local printed = {}
        local live = { is_server = true }
        local buff_system = { name = "buff_system" }
        with_globals({
            printf = function(fmt, ...) printed[#printed + 1] = string.format(fmt, ...) end,
            MutatorTemplates = templates,
            Breeds = breeds,
            NetworkLookup = { mutator_templates = { metal = 3, [3] = "metal" } },
            Managers = {
                player = setmetatable({}, { __index = function(_, k)
                    if k == "is_server" then return live.is_server end
                end }),
                mechanism = { current_mechanism_name = function() return "deus" end },
                state = { entity = { system = function(_, name)
                    H.equal(name, "buff_system")
                    return buff_system
                end } },
            },
        }, function()
            local state = assert(loadfile(module_path))()({ mod = mod })
            H.deep_equal(order, { "MutatorHandler.init", "safe.MutatorHandler.destroy", "server.start_function" })
            H.equal(#printed, 1)
            H.equal(rt.issue253_metal_wind_adapter(), nil)
            hooks["command.ct_weave_metal"]("on")
            H.equal(stored.weave_metal_strength, nil, "no strength write on a plain toggle")
            hooks["command.ct_weave_metal"]("strength", "5")
            H.equal(stored.weave_metal_strength, 5)
            H.truthy(printed[#printed]:find("[ct:253:diag] action=strength result=changed enabled=true strength=5 server=true mechanism=deus bridged=true level=idle", 1, true))
            local seen
            hooks["MutatorHandler.init"](function(_, list) seen = list end, {}, { "a" }, true)
            H.deep_equal(seen, { "a", "metal" })
            local data = { template = templates.metal }
            hooks["server.start_function"](templates.metal.server.start_function, "context", data)
            H.equal(data.wind_strength, 5)
            H.equal(data.buff_system, buff_system)
            hooks["safe.MutatorHandler.destroy"]({})
            H.equal(state.restored_ok, 1)
            H.equal(state.level, nil)
            -- The live is_server seam gates a client.
            live.is_server = false
            hooks["MutatorHandler.init"](function(_, list) seen = list end, {}, { "a" }, false)
            H.deep_equal(seen, { "a" })
            H.equal(state.skipped.client, 1)
            H.equal(rt.issue253_metal_wind_adapter(), nil)
        end)
    end)

    -- ------------------------------------------------------------------
    -- repository wiring
    -- ------------------------------------------------------------------
    H.test("CT #253 the entry installs the adapter once, after the audit, with no hook of its own", function()
        local entry = read(entry_path)
        H.equal(count_plain(entry, 'mod:dofile("scripts/mods/chaos_wastes_tweaker_dev/_ct_weave_metal_runtime")({ mod = mod })'), 1)
        H.equal(count_plain(entry, '"MutatorHandler", "init"'), 0)
        H.equal(count_plain(entry, '"MutatorHandler", "destroy"'), 0)
        local audit_at = entry:find('_ct_weave_curse_audit")', 1, true)
        local runtime_at = entry:find('_ct_weave_metal_runtime")', 1, true)
        H.truthy(audit_at and runtime_at and audit_at < runtime_at)
        local audit = read(audit_path)
        H.equal(count_plain(audit, "mod:hook"), 0, "the feasibility audit stays observation-only")
    end)

    H.test("CT #253 the Metal wind adapter is absent from the widget tree", function()
        local data = read(data_path)
        H.equal(count_plain(data, "weave_metal"), 0)
        H.equal(count_plain(data, "ct_weave_metal"), 0)
    end)
end
