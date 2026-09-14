return function(H, repo_root)
    local root = repo_root
        .. "/chaos_wastes_tweaker_dev/scripts/mods/chaos_wastes_tweaker_dev/"
    local module_path = root .. "_ct_progressive_modifier_runtime.lua"
    local audit_path = root .. "_ct_modifier_stack_audit.lua"
    local policy_path = root .. "_ct_modifier_stack_policy.lua"
    local entry_path = root .. "chaos_wastes_tweaker_dev.lua"
    local data_path = root .. "chaos_wastes_tweaker_dev_data.lua"
    local loc_path = root .. "chaos_wastes_tweaker_dev_localization.lua"
    local Policy = assert(loadfile(policy_path))()
    local HOOK_KEY = "GameModeDeus.mutators"
    local NODE_CURSE = "curse_skulls_of_fury"

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

    local function catalog_templates(extra)
        local templates = {
            curse_empathy = { server = {}, client = {} },
            curse_abundance_of_life = { server = {}, client = {} },
            [NODE_CURSE] = { server = {}, client = {}, packages = { "resource_packages/mutators/x" } },
            deus_more_hordes = { server = {}, client = {} },
        }
        for key, value in pairs(extra or {}) do templates[key] = value end
        return templates
    end

    local function catalog_lookup(templates)
        local lookup, index = {}, 0
        for name in pairs(templates) do
            index = index + 1
            lookup[name] = index
            lookup[index] = name
        end
        return lookup
    end

    local function fixture(opts)
        opts = opts or {}
        local hooks, order, settings, logs, rt, disabled = {}, {}, {}, {}, {}, {}
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
        if opts.templates_nil then
            templates = nil
        elseif opts.templates then
            templates = opts.templates
        else
            templates = catalog_templates()
        end
        local env = {
            server = true,
            depth = 2,
            seed = "SEED_A",
            node_key = "node_3",
            node_curse = NODE_CURSE,
        }
        local installer = assert(loadfile(module_path))()
        local ctx = {
            mod = mod,
            policy = Policy,
            effective_setting = function(id) return settings[id] end,
            is_curse_disabled = function(name)
                if env.disabled_error then error("disable lookup exploded") end
                return disabled[name] == true
            end,
            is_server = function() return env.server end,
            templates = function() return templates end,
            lookup = function() return catalog_lookup(templates or {}) end,
            log = function(fmt, ...) logs[#logs + 1] = string.format(fmt, ...) end,
        }
        local state = installer(ctx)
        return {
            mod = mod, hooks = hooks, order = order, settings = settings, logs = logs,
            rt = rt, env = env, disabled = disabled, templates = templates, state = state,
            ctx = ctx, installer = installer,
        }
    end

    -- A GameModeDeus double: only the run-controller field the hook reads.
    local function game_mode_for(f, overrides)
        overrides = overrides or {}
        local controller = {
            get_current_node = function()
                if f.env.node_error then error("node exploded") end
                if f.env.node_curse == false then return nil end
                return { curse = f.env.node_curse, key = f.env.node_key }
            end,
            get_completed_level_count = function() return f.env.depth end,
            get_run_seed = function() return f.env.seed end,
            get_current_node_key = function() return f.env.node_key end,
        }
        for key, value in pairs(overrides) do controller[key] = value end
        local game_mode = {}
        if not overrides.no_controller then
            game_mode._deus_run_controller = controller
        end
        return game_mode
    end

    -- Drive the captured hook with a vanilla double that returns a fresh list.
    local function run_hook(f, game_mode, vanilla_list, vanilla)
        local hook = assert(f.hooks[HOOK_KEY])
        local calls = {}
        local func = vanilla or function(...)
            calls[#calls + 1] = { n = select("#", ...), ... }
            local copy = {}
            for i = 1, #vanilla_list do copy[i] = vanilla_list[i] end
            return copy, nil, "tail"
        end
        local r = { n = 0 }
        local function capture(...)
            r.n = select("#", ...)
            for i = 1, r.n do r[i] = select(i, ...) end
        end
        capture(hook(func, game_mode, "arg1", nil, "arg3"))
        return calls, r
    end

    local function default_list()
        return { "deus_more_hordes", NODE_CURSE }
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
    H.test("CT #289 runtime installs exactly one hook on GameModeDeus.mutators", function()
        local f = fixture()
        H.deep_equal(f.order, { "hook:" .. HOOK_KEY })
        H.equal(f.state.installed, true)
        H.equal(f.state.hook_pair, HOOK_KEY)
        H.equal(f.state.setting_id, "progressive_modifier_stack")
        H.equal(f.mod._ct_progressive_modifier_runtime_state, f.state)
        H.equal(type(f.rt.issue289_progressive_modifier_stack), "function")
        H.equal(f.state.activation(), "disabled")
        H.equal(f.state.ladder_label(), "1/1/2/2/3")
        H.equal(f.state.extra_label(), "0/0/1/1/1")
        H.equal(f.state.allowlist(), "curse_empathy,curse_abundance_of_life")
        H.equal(#f.logs, 1)
        H.equal(f.logs[1], "[ct:289] runtime installed activation=disabled ladder=1/1/2/2/3 extras=0/0/1/1/1 pair=curse_empathy,curse_abundance_of_life hook=GameModeDeus.mutators")
    end)

    H.test("CT #289 a second install is idempotent and never re-hooks", function()
        local f = fixture()
        local again = f.installer(f.ctx)
        H.equal(again, f.state)
        H.equal(#f.order, 1)
    end)

    H.test("CT #289 ctx contract is load-time asserted", function()
        local f = fixture()
        H.equal(pcall(f.installer, nil), false)
        H.equal(pcall(f.installer, "nope"), false)
        for _, key in ipairs({ "mod", "effective_setting", "is_curse_disabled", "policy" }) do
            local partial = {}
            for k, v in pairs(f.ctx) do partial[k] = v end
            partial.mod = {}  -- fresh mod (no dofile) so the idempotent early-return cannot mask it
            partial[key] = nil
            H.equal(pcall(f.installer, partial), false, "missing " .. key .. " must assert")
        end
    end)

    H.test("CT #289 entry-shaped install (mod, effective_setting, is_curse_disabled) binds the live seams", function()
        local hooks, order, settings = {}, {}, {}
        local mod = {}
        function mod:hook(class_name, method_name, callback)
            hooks[class_name .. "." .. method_name] = callback
            order[#order + 1] = class_name .. "." .. method_name
        end
        function mod:dofile(path)
            H.equal(path, "scripts/mods/chaos_wastes_tweaker_dev/_ct_modifier_stack_policy")
            return Policy
        end
        local rt = {}
        mod._ct_rt_register = function(name, fn) rt[name] = fn end
        local printed = {}
        local templates = catalog_templates()
        local live = { is_server = true }
        with_globals({
            printf = function(fmt, ...) printed[#printed + 1] = string.format(fmt, ...) end,
            MutatorTemplates = templates,
            NetworkLookup = { mutator_templates = catalog_lookup(templates) },
            GameModeDeus = { mutators = function() end },
            Managers = {
                player = setmetatable({}, { __index = function(_, k)
                    if k == "is_server" then return live.is_server end
                end }),
            },
        }, function()
            local state = assert(loadfile(module_path))()({
                mod = mod,
                effective_setting = function(id) return settings[id] end,
                is_curse_disabled = function() return false end,
            })
            H.deep_equal(order, { HOOK_KEY })
            H.equal(#printed, 1)
            settings.progressive_modifier_stack = true
            local f = { hooks = hooks, env = { depth = 2, seed = "S", node_key = "n", node_curse = NODE_CURSE } }
            local _, r = run_hook(f, game_mode_for(f), default_list())
            H.equal(#r[1], 3)
            H.equal(Policy.is_allowlisted(r[1][3]), true)
            H.equal(state.appended, 1)
            -- The live is_server seam gates a client.
            live.is_server = false
            _, r = run_hook(f, game_mode_for(f), default_list())
            H.equal(#r[1], 2)
            H.equal(state.skipped.client, 1)
            H.equal(rt.issue289_progressive_modifier_stack(), nil)
        end)
    end)

    -- ------------------------------------------------------------------
    -- vanilla-first order and preserved returns
    -- ------------------------------------------------------------------
    H.test("CT #289 vanilla runs first with every argument and return preserved", function()
        local f = fixture()
        f.settings.progressive_modifier_stack = true
        local calls, r = run_hook(f, game_mode_for(f), default_list())
        H.equal(#calls, 1)
        H.equal(calls[1].n, 4)
        H.equal(calls[1][2], "arg1")
        H.equal(calls[1][3], nil)
        H.equal(calls[1][4], "arg3")
        H.equal(r.n, 3, "multi-return count with an interior nil hole is preserved")
        H.equal(r[2], nil)
        H.equal(r[3], "tail")
        H.equal(#r[1], 3)
        H.equal(r[1][1], "deus_more_hordes")
        H.equal(r[1][2], NODE_CURSE)
        H.equal(Policy.is_allowlisted(r[1][3]), true)
        H.equal(f.state.appended, 1)
        H.equal(f.state.selections, 1)
        H.equal(f.state.last.extra, r[1][3])
        H.equal(f.state.last.reason, "selected")
        H.equal(f.state.last.completed, 2)
        H.equal(f.state.last.node_curse, NODE_CURSE)
        H.equal(f.state.last.vanilla_count, 2)
    end)

    H.test("CT #289 a non-table vanilla return passes through untouched", function()
        local f = fixture()
        f.settings.progressive_modifier_stack = true
        local _, r = run_hook(f, game_mode_for(f), nil, function() return nil end)
        H.equal(r.n, 1)
        H.equal(r[1], nil)
        H.equal(f.state.selections, 0)
        _, r = run_hook(f, game_mode_for(f), nil, function() return "weird", 2 end)
        H.equal(r.n, 2)
        H.equal(r[1], "weird")
        H.equal(f.state.selections, 0)
    end)

    -- ------------------------------------------------------------------
    -- gating: toggle, role, scope, ladder
    -- ------------------------------------------------------------------
    H.test("CT #289 default-off: nothing is appended and the reason is recorded", function()
        local f = fixture()
        for _ = 1, 3 do
            local _, r = run_hook(f, game_mode_for(f), default_list())
            H.equal(#r[1], 2)
        end
        H.equal(f.state.appended, 0)
        H.equal(f.state.skipped.disabled, 3)
        H.equal(f.state.last.extra, nil)
        H.equal(f.state.last.reason, "disabled")
        H.equal(count_rows(f.logs, "[ct:289] stack"), 0)
        f.settings.progressive_modifier_stack = "true"
        local _, r = run_hook(f, game_mode_for(f), default_list())
        H.equal(#r[1], 2, "only boolean true enables")
    end)

    H.test("CT #289 a client never appends even with the option on", function()
        local f = fixture()
        f.settings.progressive_modifier_stack = true
        f.env.server = false
        local _, r = run_hook(f, game_mode_for(f), default_list())
        H.equal(#r[1], 2)
        H.equal(f.state.skipped.client, 1)
        H.equal(f.state.appended, 0)
    end)

    H.test("CT #289 the ladder gates maps one and two and opens from map three", function()
        local f = fixture()
        f.settings.progressive_modifier_stack = true
        for depth = 0, 1 do
            f.env.depth = depth
            local _, r = run_hook(f, game_mode_for(f), default_list())
            H.equal(#r[1], 2, "depth " .. depth)
        end
        H.equal(f.state.skipped.below_ladder, 2)
        for depth = 2, 8 do
            f.env.depth = depth
            local _, r = run_hook(f, game_mode_for(f), default_list())
            H.equal(#r[1], 3, "depth " .. depth)
            H.equal(Policy.is_allowlisted(r[1][3]), true)
        end
        H.equal(f.state.appended, 7)
        -- A controller without a depth is a skip, never an error.
        local gm = game_mode_for(f, { get_completed_level_count = function() return nil end })
        local _, r = run_hook(f, gm, default_list())
        H.equal(#r[1], 2)
        H.equal(f.state.skipped.no_completed_count, 1)
        H.equal(f.state.errors, 0)
    end)

    H.test("CT #289 only a cursed node whose curse is live in vanilla's list qualifies", function()
        local f = fixture()
        f.settings.progressive_modifier_stack = true
        -- Uncursed node (shrine, finale, travel without a curse).
        f.env.node_curse = nil
        local _, r = run_hook(f, game_mode_for(f), { "deus_more_hordes" })
        H.equal(#r[1], 1)
        H.equal(f.state.skipped.no_node_curse, 1)
        -- No node at all.
        f.env.node_curse = false
        _, r = run_hook(f, game_mode_for(f), { "deus_more_hordes" })
        H.equal(#r[1], 1)
        H.equal(f.state.skipped.no_node_curse, 2)
        -- Node curse present in the graph but stripped by CT's disable path.
        f.env.node_curse = NODE_CURSE
        _, r = run_hook(f, game_mode_for(f), { "deus_more_hordes" })
        H.equal(#r[1], 1)
        H.equal(f.state.skipped.node_curse_inactive, 1)
        -- No run controller on the game mode.
        _, r = run_hook(f, game_mode_for(f, { no_controller = true }), default_list())
        H.equal(#r[1], 2)
        H.equal(f.state.skipped.no_run_controller, 1)
        H.equal(f.state.appended, 0)
        H.equal(f.state.errors, 0)
    end)

    -- ------------------------------------------------------------------
    -- exclusion: disabled curses, missing templates, packages, duplicates
    -- ------------------------------------------------------------------
    H.test("CT #289 a host-disabled curse is never the extra", function()
        local f = fixture()
        f.settings.progressive_modifier_stack = true
        f.disabled.curse_empathy = true
        for seed = 1, 12 do
            f.env.seed = "seed_" .. seed
            local _, r = run_hook(f, game_mode_for(f), default_list())
            H.equal(r[1][3], "curse_abundance_of_life")
        end
        f.disabled.curse_abundance_of_life = true
        local _, r = run_hook(f, game_mode_for(f), default_list())
        H.equal(#r[1], 2)
        H.equal(f.state.skipped.no_candidate, 1)
    end)

    H.test("CT #289 a template that is missing or declares packages is never the extra", function()
        local f = fixture({ templates = catalog_templates({
            curse_empathy = { server = {}, client = {}, packages = { "resource_packages/mutators/late" } },
        }) })
        f.settings.progressive_modifier_stack = true
        for seed = 1, 8 do
            f.env.seed = "seed_" .. seed
            local _, r = run_hook(f, game_mode_for(f), default_list())
            H.equal(r[1][3], "curse_abundance_of_life", "packages exclude empathy")
        end
        f.templates.curse_abundance_of_life = nil
        local _, r = run_hook(f, game_mode_for(f), default_list())
        H.equal(#r[1], 2, "missing template excludes abundance")
        H.equal(f.state.skipped.no_candidate, 1)
        -- A missing catalog excludes everything rather than erroring.
        local g = fixture({ templates_nil = true })
        g.settings.progressive_modifier_stack = true
        _, r = run_hook(g, game_mode_for(g), default_list())
        H.equal(#r[1], 2)
        H.equal(g.state.errors, 0)
    end)

    H.test("CT #289 the extra is never the node curse and never duplicates a list entry", function()
        local f = fixture()
        f.settings.progressive_modifier_stack = true
        f.env.node_curse = "curse_empathy"
        local _, r = run_hook(f, game_mode_for(f), { "deus_more_hordes", "curse_empathy" })
        H.equal(r[1][3], "curse_abundance_of_life")
        f.env.node_curse = "curse_abundance_of_life"
        _, r = run_hook(f, game_mode_for(f), { "curse_abundance_of_life" })
        H.equal(r[1][2], "curse_empathy")
        f.env.node_curse = NODE_CURSE
        _, r = run_hook(f, game_mode_for(f), { NODE_CURSE, "curse_empathy" })
        H.equal(r[1][3], "curse_abundance_of_life")
        _, r = run_hook(f, game_mode_for(f), { NODE_CURSE, "curse_empathy", "curse_abundance_of_life" })
        H.equal(#r[1], 3, "both pair members present: nothing appended")
        H.equal(f.state.skipped.no_candidate, 1)
    end)

    -- ------------------------------------------------------------------
    -- determinism, bounded logs, contained errors
    -- ------------------------------------------------------------------
    H.test("CT #289 repeated calls for one mission always pick the same extra", function()
        local f = fixture()
        f.settings.progressive_modifier_stack = true
        local _, first = run_hook(f, game_mode_for(f), default_list())
        for _ = 1, 15 do
            local _, r = run_hook(f, game_mode_for(f), default_list())
            H.equal(r[1][3], first[1][3])
        end
        local seen = {}
        for seed = 1, 30 do
            f.env.seed = "run_" .. seed
            local _, r = run_hook(f, game_mode_for(f), default_list())
            seen[r[1][3]] = true
        end
        H.equal(seen.curse_empathy and seen.curse_abundance_of_life, true,
            "both pair members are reachable across runs")
    end)

    H.test("CT #289 stack log rows are capped and carry the mission identity", function()
        local f = fixture()
        f.settings.progressive_modifier_stack = true
        for i = 1, f.state.LOG_CAP + 5 do
            f.env.node_key = "node_" .. i
            run_hook(f, game_mode_for(f), default_list())
        end
        H.equal(count_rows(f.logs, "[ct:289] stack "), f.state.LOG_CAP)
        H.equal(f.state.appended, f.state.LOG_CAP + 5)
        local row = f.logs[2]
        H.equal(row:find("[ct:289] stack 1/12 node=node_1 curse=" .. NODE_CURSE .. " extra=curse_", 1, true) ~= nil, true, row)
        H.equal(row:find(" completed=2 ladder=1/1/2/2/3 extras=0/0/1/1/1 list=3", 1, true) ~= nil, true, row)
    end)

    H.test("CT #289 a throwing seam is contained, counted, capped and never breaks vanilla", function()
        local f = fixture()
        f.settings.progressive_modifier_stack = true
        f.env.node_error = true
        for _ = 1, f.state.ERROR_CAP + 3 do
            local _, r = run_hook(f, game_mode_for(f), default_list())
            H.equal(#r[1], 2, "vanilla list returned intact")
            H.equal(r.n, 3)
        end
        H.equal(f.state.errors, f.state.ERROR_CAP + 3)
        H.equal(count_rows(f.logs, "[ct:289] select_error"), f.state.ERROR_CAP)
        H.equal(f.state.last_error:find("node exploded", 1, true) ~= nil, true)
        H.equal(f.state.appended, 0)
        H.equal(type(f.rt.issue289_progressive_modifier_stack()), "string")
        -- A throwing disable predicate is contained the same way.
        local g = fixture()
        g.settings.progressive_modifier_stack = true
        g.env.disabled_error = true
        local _, r = run_hook(g, game_mode_for(g), default_list())
        H.equal(#r[1], 2)
        H.equal(g.state.errors, 1)
        -- A throwing observer never reaches vanilla or the caller.
        local h = fixture()
        h.settings.progressive_modifier_stack = true
        local seen = {}
        h.state.add_observer(function(list, extra, reason)
            seen[#seen + 1] = { n = #list, extra = extra, reason = reason }
            error("observer exploded")
        end)
        h.state.add_observer("not a function")
        local _, rr = run_hook(h, game_mode_for(h), default_list())
        H.equal(#rr[1], 3)
        H.equal(#seen, 1)
        H.equal(seen[1].n, 3)
        H.equal(seen[1].reason, "selected")
        H.equal(#h.state.observers, 1)
    end)

    -- ------------------------------------------------------------------
    -- regression check
    -- ------------------------------------------------------------------
    H.test("CT #289 regression check passes on a healthy install and names each drift", function()
        local templates = catalog_templates()
        local seams = {
            GameModeDeus = { mutators = function() end },
        }
        with_globals(seams, function()
            local f = fixture({ templates = templates })
            H.equal(f.rt.issue289_progressive_modifier_stack(), nil)
            f.state.hook_pair = "Elsewhere.mutators"
            H.equal(f.rt.issue289_progressive_modifier_stack(), "hook pair drift: Elsewhere.mutators")
        end)
        with_globals({ GameModeDeus = {} }, function()
            local f = fixture({ templates = templates })
            H.equal(f.rt.issue289_progressive_modifier_stack(), "GameModeDeus.mutators seam missing")
        end)
        with_globals(seams, function()
            local f = fixture({ templates = catalog_templates({
                curse_empathy = { server = {}, client = {}, packages = { "p" } },
            }) })
            H.equal(f.rt.issue289_progressive_modifier_stack(),
                "allowlist template declares packages: curse_empathy")
            local g = fixture({ templates = catalog_templates({ curse_abundance_of_life = false }) })
            H.equal(g.rt.issue289_progressive_modifier_stack(),
                "allowlist template missing: curse_abundance_of_life")
            local h = fixture({ templates = catalog_templates({ curse_empathy = { client = {} } }) })
            H.equal(h.rt.issue289_progressive_modifier_stack(),
                "allowlist template is not handler-wrapped: curse_empathy")
            -- The lookup seam is captured at install; build a fresh install with
            -- the override on a mod double that has no prior state.
            local i = fixture({ templates = templates })
            local k_mod = {}
            function k_mod:hook() end
            local k_rt = {}
            k_mod._ct_rt_register = function(name, fn) k_rt[name] = fn end
            local k_ctx = {}
            for key, value in pairs(i.ctx) do k_ctx[key] = value end
            k_ctx.mod = k_mod
            k_ctx.lookup = function() return { curse_empathy = 1 } end
            assert(loadfile(module_path))()(k_ctx)
            H.equal(k_rt.issue289_progressive_modifier_stack(),
                "allowlist wire entry missing: curse_abundance_of_life")
            k_ctx.lookup = function() return nil end
            k_mod._ct_progressive_modifier_runtime_state = nil
            assert(loadfile(module_path))()(k_ctx)
            H.equal(k_rt.issue289_progressive_modifier_stack(),
                "NetworkLookup.mutator_templates missing")
        end)
    end)

    -- ------------------------------------------------------------------
    -- audit module reads the runtime and reports parity
    -- ------------------------------------------------------------------
    H.test("CT #289 audit hooks nothing and reports activation, extra and the parity rule", function()
        local f = fixture()
        f.settings.progressive_modifier_stack = true
        local printed, commands = {}, {}
        function f.mod:dofile(path)
            return assert(loadfile(root .. path:match("([^/]+)$") .. ".lua"))()
        end
        function f.mod:command(name, _, fn) commands[name] = fn end
        local game_mode = game_mode_for(f)
        local hook = f.hooks[HOOK_KEY]
        game_mode.mutators = function(self)
            return hook(function() return default_list() end, self)
        end
        local extra = game_mode:mutators()[3]
        local active = { deus_more_hordes = {}, [NODE_CURSE] = {}, [extra] = {} }
        local audit
        with_globals({
            get_mod = function(id) H.equal(id, "ct_dev"); return f.mod end,
            printf = function(fmt, ...) printed[#printed + 1] = string.format(fmt, ...) end,
            MutatorTemplates = f.templates,
            NetworkLookup = { mutator_templates = catalog_lookup(f.templates) },
            LevelSettings = { some_level = { mutators = { "level_only" } } },
            Managers = {
                mechanism = {
                    game_mechanism = function()
                        return {
                            get_deus_run_controller = function()
                                return game_mode._deus_run_controller
                            end,
                        }
                    end,
                },
                state = {
                    game_mode = {
                        is_server = true,
                        _game_mode = game_mode,
                        _mutator_handler = { _active_mutators = active },
                        level_key = function() return "some_level" end,
                    },
                },
            },
        }, function()
            audit = assert(loadfile(audit_path))()
            H.equal(#f.order, 1, "the audit registers no hook of its own")
            commands.ct_modifier_stack_audit()
            H.equal(#printed, 2)
            H.equal(printed[1]:find("[ct:289] audit=1/3 reason=command role=host completed=2 ramp_target=2 proof_target=2 node_curse=" .. NODE_CURSE .. " ", 1, true) ~= nil, true, printed[1])
            H.equal(printed[1]:find(" missing_template=0 missing_wire=0 duplicates=0 transport_ready=true", 1, true) ~= nil, true, printed[1])
            H.equal(printed[2]:find("[ct:289] schema=node.curse:singular ramp_blocked=false activation=enabled extra=" .. extra .. " extra_reason=selected unexpected_active=0 allowlisted=true pair=curse_empathy,curse_abundance_of_life", 1, true) ~= nil, true, printed[2])
            H.equal(type(f.rt.issue289_modifier_stack_feasibility), "function")
            H.equal(f.rt.issue289_modifier_stack_feasibility(), nil)
            -- Client shape: vanilla list is local, the extra arrives only via activation.
            f.env.server = false
            Managers.state.game_mode.is_server = false
            active.level_only = {}
            H.equal(f.rt.issue289_modifier_stack_feasibility(), nil)
            commands.ct_modifier_stack_audit()
            H.equal(printed[4]:find(" unexpected_active=1 allowlisted=true ", 1, true) ~= nil, true, printed[4])
            -- A stray activation outside the pair is the falsifier; the client's
            -- own allowlisted extra is listed beside it because vanilla's local
            -- list cannot explain either.
            active.curse_monophobia = {}
            H.equal(f.rt.issue289_modifier_stack_feasibility(),
                "active modifiers outside vanilla's list and the curated pair: "
                .. extra .. ",curse_monophobia")
            active.curse_monophobia = nil
            H.equal(f.rt.issue289_modifier_stack_feasibility(), nil)
            -- Missing runtime is reported.
            f.mod._ct_progressive_modifier_runtime_state = nil
            H.equal(f.rt.issue289_modifier_stack_feasibility(),
                "progressive modifier runtime is not installed")
        end)
        H.equal(type(audit), "table")
    end)

    -- ------------------------------------------------------------------
    -- source-pattern invariants
    -- ------------------------------------------------------------------
    -- Every ct_dev script as of 0.7.351-dev (92 files). The floor assertion in the
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
        "_ct_progressive_elite_policy", "_ct_progressive_elite_runtime",
        "_ct_progressive_modifier_runtime", "_ct_regression",
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

    H.test("CT #289 entry installs the runtime once, before the audit, and no other hook shares the seam", function()
        local entry = read(entry_path)
        local runtime = read(module_path)
        local audit = read(audit_path)
        H.equal(count_plain(entry,
            'mod:dofile("scripts/mods/chaos_wastes_tweaker_dev/_ct_progressive_modifier_runtime")'), 1)
        H.equal(count_plain(entry,
            'mod:dofile("scripts/mods/chaos_wastes_tweaker_dev/_ct_modifier_stack_audit")'), 1)
        local runtime_at = entry:find("_ct_progressive_modifier_runtime\")", 1, true)
        local audit_at = entry:find("_ct_modifier_stack_audit\")", 1, true)
        H.equal(runtime_at < audit_at, true, "runtime must install before the audit")
        H.equal(entry:find("is_curse_disabled = function(name) return is_curse_disabled(name) end", 1, true) ~= nil, true,
            "the entry passes its disable predicate as a late-binding wrapper")
        H.equal(count_plain(runtime, 'mod:hook("GameModeDeus", "mutators"'), 1)
        H.equal(count_plain(runtime, "_ct_consolidated_game_mode_deus_mutators_hook"), 1)
        H.equal(count_plain(runtime, "-- hook-test: issue289_progressive_modifier_stack"), 1)
        H.equal(count_plain(audit, "mod:hook"), 0, "the audit must not hook anything")
        -- Vanilla must run before the append, and the run state / node are never
        -- write targets (the singular node.curse schema stays vanilla's).
        local vanilla_at = runtime:find("pack(func(self, ...))", 1, true)
        local append_at = runtime:find("list[#list + 1] = extra", 1, true)
        H.equal(vanilla_at ~= nil and append_at ~= nil and vanilla_at < append_at, true,
            "vanilla must precede the CT append")
        H.equal(runtime:find("node%.curse%s*=[^=]"), nil, "the runtime must never assign node.curse")
        H.equal(runtime:find("set_event_mutators"), nil, "the runtime must never write the run state")
        H.equal(runtime:find("network_register"), nil, "no CT RPC")
        H.equal(runtime:find("Managers%.package"), nil, "no CT package load")
        H.equal(#CT_SCRIPT_FILES >= 92, true, "script roster shrank")
        for _, name in ipairs(CT_SCRIPT_FILES) do
            local source = read(root .. name .. ".lua")
            local expected = name == "_ct_progressive_modifier_runtime" and 1 or 0
            H.equal(count_plain(source, '"GameModeDeus", "mutators"'), expected, name .. " GameModeDeus.mutators")
        end
    end)

    H.test("CT #289 data exposes the default-off toggle and localization covers every key", function()
        local data = read(data_path)
        local loc = read(loc_path)
        local at = data:find('setting_id = "progressive_modifier_stack"', 1, true)
        H.equal(at ~= nil, true)
        H.equal(count_plain(data, 'setting_id = "progressive_modifier_stack"'), 1)
        local block = data:sub(at, at + 200)
        H.equal(block:find("default_value = false", 1, true) ~= nil, true, "must default off")
        H.equal(block:find("sub_widgets", 1, true), nil, "no rate or count knob in this slice")
        local elite_at = data:find('setting_id = "progressive_elite_enhancements"', 1, true)
        H.equal(elite_at < at, true, "placed beside the other progressive options")
        for _, key in ipairs({ "progressive_modifier_stack", "progressive_modifier_stack_tooltip" }) do
            local needle = "\n    " .. key .. " = { en = "
            H.equal(count_plain(loc, needle), 1, key)
            local key_at = loc:find(needle, 1, true)
            local line = loc:sub(key_at + 1, (loc:find("\n", key_at + 1, true) or #loc) - 1)
            H.equal(line:find("\226\128\148", 1, true), nil, "no em dash in " .. key)
            H.equal(line:find("%[verify%-fix%]") or line:find("%[Issue") or line:find("#289", 1, true), nil,
                "no lifecycle metadata in " .. key)
            local stripped = line:gsub("%%%%", "")
            H.equal(stripped:find("%", 1, true), nil, "every literal percent is escaped in " .. key)
        end
        local tooltip_at = loc:find("\n    progressive_modifier_stack_tooltip = { en = ", 1, true)
        local tooltip = loc:sub(tooltip_at, (loc:find("\n", tooltip_at + 1, true) or #loc) - 1)
        H.equal(tooltip:find("Empathy", 1, true) ~= nil, true, "names the first pair member")
        H.equal(tooltip:find("Unquenchable Thirst", 1, true) ~= nil, true, "names the second pair member")
        H.equal(tooltip:find("third map", 1, true) ~= nil, true, "states the ladder step")
    end)
end
