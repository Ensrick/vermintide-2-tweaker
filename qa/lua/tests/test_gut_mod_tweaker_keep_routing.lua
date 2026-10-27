-- Offline proof for #1652: the Mod Tweaker keep route and the check that reads it.
-- RainReligion's 0.2.354-dev log failed `mod_tweaker_transition_registered` with
-- `keep branch did not call transition_with_fade`. That is the closure working as
-- designed: the HeroView sub-state route has been gated off by
-- `_USE_KEEP_SUBSTATE = false` since the 0.2.62-dev bounce revert, so the keep
-- ESC entry opens the standalone ModTweakerView. The check asserted the dormant
-- route whenever the state class existed. These cases lift the SHIPPED transition
-- closure out of its actual shell owner and the SHIPPED runner out of the entry (column-anchored, so a
-- reshaped block fails loudly) and drive the real contracts module against them.
-- printf resolves through a test-local environment; the global is never swapped.
return function(H, repo_root)
    local base = repo_root .. "/gui_tweaker_dev/scripts/mods/gui_tweaker_dev/"

    local function read(path)
        local file = assert(io.open(path, "rb"))
        local source = file:read("*a")
        file:close()
        return source
    end

    local main_source = read(base .. "gui_tweaker_dev.lua")
    local routing_source = read(base .. "_gut_mod_tweaker_shell.lua"):gsub("\n        ", "\n")
    local LIVE_ALERT = "[mt] transition: view not attached; ESC entry is a no-op"

    local function extract_closure(source)
        local start_needle = "    settings.transitions.mod_tweaker_view = function(self)"
        local from = source:find(start_needle, 1, true)
        H.truthy(from, "transition closure not found in its actual owner")
        local stop_needle = '\n    end\n    _dbg("[mt] transition registered: mod_tweaker_view")'
        local stop = source:find(stop_needle, from, true)
        H.truthy(stop, "transition closure has no column-anchored end")
        return source:sub(from, stop + #"\n    end")
    end

    -- Compiles the lifted closure with its upvalues supplied here. `_attach_view`
    -- keeps the production early-return: a pre-seeded views.mod_tweaker_view is
    -- already attached (true); no views, or no renderer, cannot attach (false).
    local function build_transition(opts)
        local block = extract_closure(routing_source)
        local log = { alerts = {}, debugs = {}, repins = 0, attaches = 0 }
        local function attach_view(self)
            log.attaches = log.attaches + 1
            if not self or type(self.views) ~= "table" then return false end
            if self.views.mod_tweaker_view then return true end
            return false
        end
        local settings = { transitions = {} }
        local chunk = assert(loadstring(
            "local settings, _attach_view, _gut_mt_repin_la, _dbg, _dbg_alert, _USE_KEEP_SUBSTATE = ...\n"
                .. block, "@gut_transition_closure"))
        local env = setmetatable({}, { __index = _G })
        env._G = env
        env.HeroViewStateModTweaker = opts.substate_class
        setfenv(chunk, env)
        chunk(settings, attach_view,
            function() log.repins = log.repins + 1 end,
            function(fmt) log.debugs[#log.debugs + 1] = fmt end,
            function(fmt) log.alerts[#log.alerts + 1] = fmt end,
            opts.use_keep_substate)
        H.equal(type(settings.transitions.mod_tweaker_view), "function", "closure did not register")
        return settings, log
    end

    local function keep_fake(with_view, is_in_inn)
        local calls = {}
        local fake = {
            current_view = "hero_view",
            ingame_ui_context = { is_in_inn = is_in_inn ~= false },
            transition_with_fade = function(_self, transition, params)
                calls[#calls + 1] = { transition = transition, params = params }
            end,
        }
        if with_view then fake.views = { mod_tweaker_view = { _exit_transition = nil } } end
        return fake, calls
    end

    local function has_line(lines, needle)
        for _, line in ipairs(lines) do
            if line:find(needle, 1, true) then return true end
        end
        return false
    end

    -- Loads the real contracts module against a fake mod, a fake ingame_ui_settings
    -- and a fake HeroViewStateModTweaker global, returning the registered checks.
    local function load_contracts(opts)
        local registered = {}
        local mod = {
            _gut_mt_keep_substate_routing = opts.policy,
            dofile = function(_, path)
                if path:find("_gut_dialogue_contract", 1, true) then return { install = function() end } end
                if path:find("_mod_tweaker_tab_labels", 1, true) then return { rt_checks = {} } end
                error("unexpected install-time dofile: " .. tostring(path))
            end,
        }
        local chunk = assert(loadfile(base .. "_gut_mod_tweaker_contracts.lua"))
        local env = setmetatable({
            get_mod = function() return mod end,
            package = { loaded = { ["scripts/ui/views/ingame_ui_settings"] = opts.settings } },
            printf = function() end,
        }, { __index = _G })
        env._G = env
        env.HeroViewStateModTweaker = opts.substate_class
        setfenv(chunk, env)
        local M = chunk()
        M.install({
            register = function(name, fn) registered[name] = fn end,
            src_read = function() return nil end,
        })
        H.equal(type(registered.mod_tweaker_transition_registered), "function")
        H.equal(type(registered.mod_tweaker_keep_substate_routing), "function")
        return registered
    end

    H.test("GUT #1652 the shipped keep policy is off and published beside the closure", function()
        H.truthy(routing_source:find("\nlocal _USE_KEEP_SUBSTATE = false\n", 1, true),
            "the keep sub-state policy must stay a module-level constant")
        H.truthy(routing_source:find("\nmod._gut_mt_keep_substate_routing = _USE_KEEP_SUBSTATE\n", 1, true),
            "the policy must be published for the contracts")
        H.equal(select(2, routing_source:gsub("_USE_KEEP_SUBSTATE = ", "")), 1, "exactly one policy assignment")
    end)

    H.test("GUT #1652 policy off: the keep ESC entry opens the standalone view and never fades", function()
        local settings, log = build_transition({ use_keep_substate = false, substate_class = {} })
        local fake, calls = keep_fake(true)
        settings.transitions.mod_tweaker_view(fake)
        H.equal(#calls, 0, "the keep route must not call transition_with_fade")
        H.equal(fake.current_view, "mod_tweaker_view")
        H.equal(fake.views.mod_tweaker_view._exit_transition, "hero_view", "exit returns to the keep hero view")
        H.equal(log.repins, 1, "LA atlas re-pin runs once per open")
        H.equal(log.attaches, 1)
        H.equal(#log.alerts, 0)
    end)

    H.test("GUT #1652 the 0.2.356-dev probe shape reproduces the live FAIL against the shipped closure", function()
        local settings, log = build_transition({ use_keep_substate = false, substate_class = {} })
        local fake, calls = keep_fake(false)   -- no views, as the old keep probe was built
        settings.transitions.mod_tweaker_view(fake)
        H.equal(#calls, 0, "old probe: captured == nil, hence 'keep branch did not call transition_with_fade'")
        H.truthy(has_line(log.alerts, LIVE_ALERT), "the exact alert line above the live FAIL")
        H.equal(fake.current_view, "hero_view", "nothing attached, nothing switched")
    end)

    H.test("GUT #1652 policy on: the dormant sub-state route still carries force_open", function()
        local settings, log = build_transition({ use_keep_substate = true, substate_class = {} })
        local fake, calls = keep_fake(false)
        settings.transitions.mod_tweaker_view(fake)
        H.equal(#calls, 1)
        H.equal(calls[1].transition, "hero_view")
        H.equal(calls[1].params.menu_state_name, "gut_mod_tweaker")
        H.equal(calls[1].params.force_open, true, "the 0.2.60-dev darken-then-nothing fix")
        H.equal(fake.current_view, "hero_view", "the sub-state route leaves current_view to the engine")
        H.equal(log.attaches, 0, "the sub-state route never attaches the standalone view")
    end)

    H.test("GUT #1652 policy on without the state class falls back to the standalone view", function()
        local settings = build_transition({ use_keep_substate = true, substate_class = nil })
        local fake, calls = keep_fake(true)
        settings.transitions.mod_tweaker_view(fake)
        H.equal(#calls, 0)
        H.equal(fake.current_view, "mod_tweaker_view")
    end)

    H.test("GUT #1652 the in-mission route ignores the keep policy and captures its origin", function()
        local settings = build_transition({ use_keep_substate = true, substate_class = {} })
        local fake, calls = keep_fake(true, false)
        fake.current_view = "ingame_menu"
        settings.transitions.mod_tweaker_view(fake)
        H.equal(#calls, 0)
        H.equal(fake.current_view, "mod_tweaker_view")
        H.equal(fake.views.mod_tweaker_view._exit_transition, "ingame_menu")
        local raw, raw_calls = keep_fake(true, false)
        raw.current_view = nil
        settings.transitions.mod_tweaker_view(raw)
        H.equal(#raw_calls, 0)
        H.equal(raw.views.mod_tweaker_view._exit_transition, "ingame_menu", "hotkey open with no origin menu")
    end)

    H.test("GUT #1652 contracts pass and SKIP against the shipped (off) policy", function()
        local settings = build_transition({ use_keep_substate = false, substate_class = {} })
        local checks = load_contracts({ policy = false, settings = settings, substate_class = {} })
        H.equal(checks.mod_tweaker_transition_registered(), nil)
        local verdict = checks.mod_tweaker_keep_substate_routing()
        H.equal(type(verdict), "string")
        H.equal(verdict:sub(1, 5), "skip:", verdict)
        H.truthy(verdict:find("_USE_KEEP_SUBSTATE = false", 1, true), verdict)
        H.truthy(verdict:find("v0.2.62-dev", 1, true), verdict)
    end)

    H.test("GUT #1652 contracts pass against an enabled sub-state route", function()
        local settings = build_transition({ use_keep_substate = true, substate_class = {} })
        local checks = load_contracts({ policy = true, settings = settings, substate_class = {} })
        H.equal(checks.mod_tweaker_transition_registered(), nil)
        H.equal(checks.mod_tweaker_keep_substate_routing(), nil)
    end)

    H.test("GUT #1652 contracts fail loudly when the closure and the published policy disagree", function()
        local on = build_transition({ use_keep_substate = true, substate_class = {} })
        local checks = load_contracts({ policy = false, settings = on, substate_class = {} })
        local verdict = checks.mod_tweaker_transition_registered()
        H.truthy(verdict and verdict:find("called transition_with_fade while the sub-state policy is off", 1, true),
            tostring(verdict))

        local off = build_transition({ use_keep_substate = false, substate_class = {} })
        checks = load_contracts({ policy = true, settings = off, substate_class = {} })
        verdict = checks.mod_tweaker_transition_registered()
        H.truthy(verdict and verdict:find("did not route through transition_with_fade", 1, true), tostring(verdict))
        H.equal(checks.mod_tweaker_keep_substate_routing(), "keep branch did not call transition_with_fade")

        checks = load_contracts({ policy = true, settings = on, substate_class = nil })
        H.equal(checks.mod_tweaker_keep_substate_routing(),
            "sub-state policy is on but HeroViewStateModTweaker is not defined")
    end)

    H.test("GUT #1652 an unpublished policy is a loud failure, never a verdict on nothing", function()
        local settings = build_transition({ use_keep_substate = false, substate_class = {} })
        local checks = load_contracts({ policy = nil, settings = settings, substate_class = {} })
        for _, name in ipairs({ "mod_tweaker_transition_registered", "mod_tweaker_keep_substate_routing" }) do
            local verdict = checks[name]()
            H.truthy(verdict and verdict:find("keep routing policy not published", 1, true), name .. ": " .. tostring(verdict))
        end
    end)

    -- Lifts the shipped /gut_regression_test runner and drives it over synthetic checks.
    local function run_runner(checks)
        local start = main_source:find('mod:command("gut_regression_test"', 1, true)
        H.truthy(start, "gut_regression_test command block not found")
        local stop = main_source:find("\nend)\n", start, true)
        H.truthy(stop, "gut_regression_test block has no column-anchored end)")
        local block = main_source:sub(start, stop + 5)
        local echoes, infos, warnings, printfs = {}, {}, {}, {}
        local function fmt(f, ...)
            if select("#", ...) == 0 then return tostring(f) end
            return string.format(tostring(f), ...)
        end
        local command_fn
        local mod = {
            command = function(_, _, _, fn) command_fn = fn end,
            echo = function(_, f, ...) echoes[#echoes + 1] = fmt(f, ...) end,
            info = function(_, f, ...) infos[#infos + 1] = fmt(f, ...) end,
            warning = function(_, f, ...) warnings[#warnings + 1] = fmt(f, ...) end,
        }
        local chunk = assert(loadstring("local mod, _RT_CHECKS, MOD_VERSION = ...\n" .. block, "@gut_runner"))
        setfenv(chunk, setmetatable({
            printf = function(f, ...) printfs[#printfs + 1] = fmt(f, ...) end,
        }, { __index = _G }))
        chunk(mod, checks, "0.0.0-test")
        H.equal(type(command_fn), "function", "runner command body was never registered")
        command_fn()
        return echoes, infos, warnings, printfs
    end

    H.test("GUT #1652 runner renders a skip: sentinel as SKIP with its reason and its own count", function()
        local echoes, _, warnings, printfs = run_runner({
            { name = "healthy", fn = function() return nil end },
            { name = "wrong_context", fn = function() return "skip: keep sub-state routing is gated off" end },
            { name = "broken", fn = function() return "marker reverted" end },
            { name = "raised", fn = function() error("boom") end },
            { name = "mentions_skip", fn = function() return "we had to skip: nothing" end },
        })
        H.truthy(has_line(echoes, "PASS: healthy"))
        H.truthy(has_line(echoes, "SKIP: wrong_context -- keep sub-state routing is gated off"))
        H.equal(has_line(echoes, "SKIP: wrong_context -- skip:"), false, "the sentinel is stripped from the render")
        H.equal(has_line(echoes, "FAIL: wrong_context"), false, "a skip is not a failure")
        H.truthy(has_line(echoes, "FAIL: broken"))
        H.truthy(has_line(echoes, "FAIL: raised"))
        H.truthy(has_line(echoes, "FAIL: mentions_skip"), "only the prefix is the sentinel")
        H.truthy(has_line(echoes, "=== 1 passed, 3 failed, 1 skipped ==="))
        H.truthy(has_line(printfs, "[regression] SKIP wrong_context: keep sub-state routing is gated off"),
            "skips land in the engine log with mod logging off")
        H.equal(has_line(warnings, "wrong_context"), false, "a skip never reaches the warning channel")
        H.truthy(has_line(warnings, "FAIL broken"))
    end)

    H.test("GUT #1652 runner cannot be made green by an all-skip run", function()
        local echoes = run_runner({
            { name = "a", fn = function() return "skip: not in keep" end },
            { name = "b", fn = function() return "skip: not in keep" end },
        })
        H.truthy(has_line(echoes, "=== 0 passed, 0 failed, 2 skipped ==="))
        H.equal(has_line(echoes, "PASS:"), false)
    end)

    -- #2: actual ordered entry span + complete child, not the lifted probe above.
    local Shell = assert(loadfile(repo_root .. "/qa/lua/fixtures/gut_mod_tweaker_shell_harness.lua"))()(repo_root)
    local function pair(opts)
        opts = opts or {}
        local old = {}; for k, v in pairs(opts) do old[k] = v end
        old.old = true
        return Shell.build(old), Shell.build(opts)
    end
    local function exercise(f)
        local entries = { active_button_data = { { transition = "options_menu" } } }
        H.equal(f.hooks["IngameViewLayoutLogic.setup_button_layout"](entries), nil)
        f.hooks["IngameViewLayoutLogic.setup_button_layout"](entries)
        local ui = Shell.ui("hero_view")
        local ctx = { ui_top_renderer = "argument-renderer" }
        H.equal(f.hooks["IngameUI.setup_views"](ui, ctx), nil)
        H.equal(f.view_context, ctx, "setup_views must use its actual context argument")
        H.equal(f.settings.transitions.mod_tweaker_view(ui), nil)
        f.env.Managers.ui = { handle_transition = function(_, key, params)
            f.open = { key, params }; return false, "native-return" end }
        H.equal(f.mod.gut_open_mod_tweaker(), nil)
        H.equal(f.commands.mod_tweaker(), nil)
        f.hooks["LocalizationManager.init"]()
        f.hooks["IngameView.on_enter"]()
        local menu = { _title_button_widgets = {}, layout_logic = { layout_data = function() return {1,2,3,4,5,6,7,8,9,10} end },
            _widgets_by_name = { logo = { style = { texture_id = { color = {255,2,3,4} } } }, divider = { offset = {9,0,8} } } }
        for i = 1, 10 do menu._title_button_widgets[i] = { offset = {1,2,3} } end
        H.equal(f.hooks["HeroWindowIngameView._update_presentation"](menu), nil)
        f.hooks["HeroWindowIngameView._update_presentation"](menu)
        return { entries = entries, ui = { current_view = ui.current_view, exit = ui.views.mod_tweaker_view._exit_transition },
            open = f.open, menu = { buttons = menu._title_button_widgets, widgets = menu._widgets_by_name },
            logs = f.logs, lookup = f.lookup, ledger = Shell.ledger(f) }
    end

    H.test("GUT menu shell actual entry retains all three phase and existing load/check boundaries", function()
        local old, f = pair()
        H.deep_equal(Shell.ledger(f), Shell.ledger(old), "original install/registration order changed")
        local selected = {}
        for _, value in ipairs(f.ledger) do
            if value:find("phase:", 1, true) or value == "load:_mod_tweaker" or value == "load:_gut_dx12_fence630"
                or value == "check:issue153_292_engine_ui_loc_supplied"
                or value == "load:_gut_mod_tweaker_contracts" or value == "ui:install"
                or value == "load:_la_atlas_keepalive" then selected[#selected + 1] = value end
        end
        H.deep_equal(selected, { "load:_mod_tweaker", "phase:install_api", "load:_gut_dx12_fence630",
            "phase:install_routing", "check:issue153_292_engine_ui_loc_supplied", "phase:install_compaction",
            "load:_gut_mod_tweaker_contracts", "ui:install", "load:_la_atlas_keepalive" })
        H.equal(f.mod.mod_tweaker, f.api)
        H.equal(f.category.widgets[1].range[2], 20)
        H.equal(f.help.mod_tweaker, old.help.mod_tweaker)
    end)

    H.test("GUT menu shell complete callbacks match portable published healthy body", function()
        local old, f = pair()
        H.deep_equal(exercise(f), exercise(old))
        H.equal(f.checks.issue153_292_engine_ui_loc_supplied(), nil)
    end)

    H.test("GUT menu shell actual attach keeps failures, error text and origin behavior", function()
        for _, opts in ipairs({ {}, {view_false=true}, {view_nil=true}, {view_non_table=true}, {view_load_error="view-error"},
            {view_new_error="new-error"} }) do
            local old, f = pair(opts)
            local summaries = {}
            for _, row in ipairs({old, f}) do
                local results = {}
                for _, origin in ipairs({"hero_view", "ingame_menu", "unknown"}) do
                    local ui = Shell.ui(origin)
                    row.settings.transitions.mod_tweaker_view(ui)
                    results[#results + 1] = {ui.current_view, ui.views.mod_tweaker_view}
                end
                local empty = { current_view = "hero_view" }
                row.settings.transitions.mod_tweaker_view(empty)
                local no_renderer = Shell.ui("hero_view", {})
                row.settings.transitions.mod_tweaker_view(no_renderer)
                results[#results + 1] = { empty.current_view, no_renderer.current_view }
                summaries[#summaries + 1] = { results, row.logs, Shell.ledger(row) }
            end
            H.deep_equal(summaries[2], summaries[1])
        end
    end)

    H.test("GUT menu shell API pcall success quirks and load/install errors are unchanged", function()
        for _, opts in ipairs({ {install_result=false}, {api_non_table=true}, {api_error="api-error"},
            {install_error="install-error"}, {registered=true} }) do
            local old, f = pair(opts)
            H.deep_equal(Shell.ledger(f), Shell.ledger(old))
            H.deep_equal(f.logs, old.logs)
            H.equal(f.mod.mod_tweaker == f.api, old.mod.mod_tweaker == old.api)
        end
    end)

    H.test("GUT menu shell existing transition and missing settings retain original refusal", function()
        local existing = function() return "existing", false end
        for _, old in ipairs({true, false}) do
            local f = Shell.build({old=old, transitions={mod_tweaker_view=existing}})
            H.equal(f.settings.transitions.mod_tweaker_view, existing)
            H.equal(select(2, existing()), false)
        end
        local old, f = pair({no_settings=true})
        local reason = "ingame_ui_settings not in package.loaded; mod likely loaded too early"
        for _, row in ipairs({old, f}) do
            H.equal(row.logs[2][1], "alert")
            H.equal(row.logs[2][2], row.settings_error_prefix .. reason,
                "exact genuine Lua source prefix and unchanged reason")
        end
        H.truthy(old.logs[2][2]:find("gut_mod_tweaker_shell_gui365.lua:", 1, true))
        H.truthy(f.logs[2][2]:find("_gut_mod_tweaker_shell.lua:", 1, true))
        -- Lua itself adds the moved chunk's genuine file:line prefix; only that
        -- provenance changes, not the channel, failure reason or surrounding logs.
        old.logs[2][2] = reason
        f.logs[2][2] = reason
        H.deep_equal(f.logs, old.logs)
        H.equal(f.settings.transitions.mod_tweaker_view, nil)
    end)

    H.test("GUT menu shell LA stays uninitialized until actual late entry assignment and methods stay late", function()
        for _, old in ipairs({true, false}) do
            local f = Shell.build({old=old, before_la=function(row)
                row.mod._gut_mt_repin_la({}, "before-late-assignment")
                H.equal(row.pin_calls, 0)
            end})
            f.mod._gut_mt_repin_la({}, "after-late-assignment")
            H.equal(f.pin_calls, 1)
            f.keepalive.pin = function() f.pin_calls = f.pin_calls + 7 end
            f.keepalive.is_pinned = function() return "replacement" end
            f.env.Managers.package = {has_loaded=function() return "replacement-residency" end}
            f.mod._gut_mt_repin_la({}, "replacement-method")
            H.equal(f.pin_calls, 8)
            H.truthy(f.logs[#f.logs][2]:find("gut_pinned=replacement", 1, true))
            H.truthy(f.logs[#f.logs][2]:find("LA_resident=replacement-residency", 1, true))
        end
    end)

    H.test("GUT menu shell unprotected registry and root registrar errors preserve original objects", function()
        local token = setmetatable({}, {__tostring=function()return "sentinel-object" end})
        for _, key in ipairs({"registry_error", "register_error"}) do
            for _, old in ipairs({true, false}) do
                local opts = {old=old}; opts[key]=token
                local ok, err = pcall(Shell.build, opts)
                H.equal(ok, false)
                H.equal(err, token, "unprotected error object was masked or wrapped")
            end
        end
        local old, f = pair({install_error=token})
        H.deep_equal(f.logs, old.logs, "caught install error keeps the original tostring result/channel")
    end)

    H.test("GUT menu shell actual entry view supplier observes replacement dofile and failed localization retries", function()
        for _, old in ipairs({true, false}) do
            local opts = {old=old, loc_error="early-loc-error"}
            local f = Shell.build(opts)
            local before = f.loc_calls
            opts.loc_error = nil
            H.equal(f.private.harvest().gut_video_profile_action_tooltip, "gut_video_profile_action_tooltip 25%")
            H.equal(f.loc_calls, before+1)
            local dofile = f.mod.dofile
            local view = {late="replacement-view"}
            f.mod.dofile = function(self, path)
                if path:find("_mod_tweaker_view",1,true) then return {new=function()return view end}, "extra-load-result" end
                return dofile(self,path)
            end
            local ui = Shell.ui("hero_view")
            f.settings.transitions.mod_tweaker_view(ui)
            H.equal(ui.views.mod_tweaker_view, view)
            H.equal(ui.current_view, "mod_tweaker_view")
        end
    end)

    H.test("GUT menu shell opener and command read current UI and public method at call time", function()
        local old, f = pair()
        for _, row in ipairs({old, f}) do
            row.env.Managers.ui = nil
            row.mod.gut_open_mod_tweaker()
            row.env.Managers.ui = {handle_transition=function() error("current-ui-error", 0) end}
            row.mod.gut_open_mod_tweaker()
            H.truthy(row.logs[#row.logs][2]:find("current-ui-error", 1, true))
            local calls = 0
            row.mod.gut_open_mod_tweaker = function() calls = calls + 1; return "replacement", false end
            H.equal(row.commands.mod_tweaker(), nil, "command keeps its original no-return body")
            H.equal(calls, 1)
        end
        H.deep_equal(f.logs, old.logs)
    end)

    H.test("GUT menu shell localization retries incomplete loads, caches only complete and reads late collaborators", function()
        for _, old in ipairs({true, false}) do
            local f = Shell.build({old=old, incomplete=true, no_localizer=true})
            H.equal(f.loc_calls, 0)
            H.equal(f.private.harvest().gut_video_profile_action_tooltip, nil)
            local dofile = f.mod.dofile
            f.mod.dofile = function(self, path)
                if path:find("gui_tweaker_dev_localization", 1, true) then
                    f.localization.gut_video_profile_action_tooltip = {en="new 50%%"}
                end
                return dofile(self, path)
            end
            H.equal(f.private.harvest().gut_video_profile_action_tooltip, "new 50%")
            H.equal(f.loc_calls, 2)
            f.private.harvest(); H.equal(f.loc_calls, 2)
            local thp, appends = 0, {}
            f.mod._gut_original_thp_names = {register_backend_localizations=function() thp=thp+1 end}
            f.env.Managers.localizer = {append_backend_localizations=function(_, t) appends[#appends+1]=t end}
            f.env.Localize = function() return "replacement-localize" end
            f.hooks["LocalizationManager.init"]()
            H.equal(#appends, 2); H.equal(thp, 1)
            H.truthy(f.logs[#f.logs][2]:find("replacement-localize", 1, true))
        end
    end)

    H.test("GUT menu shell private config captures references by value without freezing live dependencies", function()
        local f = Shell.build({after_bind=function(row, config)
            config.mod = {}; config.dbg = function() error("uncaptured dbg") end
            config.dbg_alert = function() error("uncaptured alert") end
            config.load_view = function() error("uncaptured view loader") end
            config.load_localization = function() error("uncaptured localization loader") end
            config.get_la_keepalive = function() return nil end
        end})
        local ui = Shell.ui("hero_view")
        f.settings.transitions.mod_tweaker_view(ui)
        H.equal(ui.current_view, "mod_tweaker_view")
        H.equal(f.pin_calls, 1)
        H.equal(f.checks.issue153_292_engine_ui_loc_supplied(), nil)
    end)

    H.test("GUT menu shell compaction threshold, idempotence and raw unrelated fields match old", function()
        for _, n in ipairs({7,8,10}) do
            local old, f = pair()
            local results = {}
            for _, row in ipairs({old, f}) do
                local layout, buttons = {}, {}
                for i=1,n do layout[i]=i; buttons[i]={offset={11,12,13}, extra="untouched"} end
                local menu={_title_button_widgets=buttons, layout_logic={layout_data=function()return layout end},
                    _widgets_by_name={logo={style={texture_id={color={255,2,3,4}}}},divider={offset={21,22,23}}}, extra=true}
                row.hooks["HeroWindowIngameView._update_presentation"](menu)
                local first=buttons[1].offset[2]
                row.hooks["HeroWindowIngameView._update_presentation"](menu)
                H.equal(buttons[1].offset[2], first)
                H.equal(buttons[1].offset[1],11); H.equal(buttons[1].offset[3],13)
                H.equal(buttons[1].extra,"untouched"); H.equal(menu.extra,true)
                if n < 8 then H.equal(first,12) else H.equal(first,-47+math.floor(12*n/2)) end
                results[#results+1]={buttons,menu._widgets_by_name}
            end
            H.deep_equal(results[2],results[1])
        end
    end)

    H.test("GUT menu shell same #93 oracle follows actual owner and rejects forbidden toggle while CIM stays entry", function()
        local f = Shell.build()
        H.equal(f.checks.mod_tweaker_compact_esc_implicit(), nil)
        H.equal(f.source_reads[#f.source_reads], Shell.owner_path)
        f.checks.cim_bench_write_through_present()
        H.equal(f.source_reads[#f.source_reads - 1], base .. "gui_tweaker_dev.lua")
        local broken = Shell.build({owner_source=function(source)
            local needle = "local buttons = self._title_button_widgets"
            return (source:gsub(needle, 'if false then mod:get("gut_compact_esc_menu") end\n                '..needle, 1))
        end})
        local verdict = broken.checks.mod_tweaker_compact_esc_implicit()
        H.truthy(verdict and verdict:find("#93 regression:",1,true), tostring(verdict))
        H.equal(broken.source_reads[#broken.source_reads], Shell.owner_path)
    end)

    H.test("GUT menu shell actual root localization check retains missing-source and current Localize failures", function()
        for _, old in ipairs({true,false}) do
            local f=Shell.build({old=old, incomplete=true})
            H.equal(f.checks.issue153_292_engine_ui_loc_supplied(),
                "engine-UI localization source missing key: gut_video_profile_action_tooltip")
            f.localization.gut_video_profile_action_tooltip={en="fixed"}
            f.hooks["IngameView.on_enter"]()
            H.equal(f.checks.issue153_292_engine_ui_loc_supplied(),nil)
            f.env.Localize=false
            H.equal(f.checks.issue153_292_engine_ui_loc_supplied(),
                "global Localize unavailable (engine-UI keys cannot resolve)")
        end
    end)

    H.test("GUT menu shell bounded inventory and whole host raw shapes are unchanged", function()
        local globals, loaded = Shell.snapshot(_G), Shell.snapshot(package.loaded)
        local f=Shell.build(); exercise(f)
        H.truthy(Shell.unchanged(_G,globals)); H.truthy(Shell.unchanged(package.loaded,loaded))
        local child=read(base .. "_gut_mod_tweaker_shell.lua")
        H.equal(child:find("mod:dofile",1,true),nil)
        local code=child:gsub("%-%-[^\n]*", "")
        H.equal(code:find("get_mod(",1,true),nil)
        H.equal(select(2, main_source:gsub("scripts/mods/gui_tweaker_dev/_gut_mod_tweaker_shell", "")),1)
        for _, field in ipairs({"mod_tweaker","gut_open_mod_tweaker","_gut_mt_repin_la","_gut_mt_keep_substate_routing","_gut_dx12_fence630"}) do
            H.truthy(f.mod[field] ~= nil, field)
        end
    end)


    H.test("GUT menu shell raw-shape oracle rejects removed false field hidden by unchanged index fallback", function()
        local meta={__index=function(_, key) if key=="owned" then return false end end}
        local value=setmetatable({owned=false,other="unchanged"},meta)
        local before=Shell.snapshot(value)
        H.equal(Shell.unchanged(value,before),true,"intact raw false remains healthy")
        rawset(value,"owned",nil)
        H.equal(value.owned,false,"adversary retains the same ordinary lookup result")
        H.equal(Shell.unchanged(value,before),false,"removed raw field must not hide behind __index")
        rawset(value,"owned",false)
        H.equal(Shell.unchanged(value,before),true,"exact raw restoration remains healthy")
        H.equal(getmetatable(value),meta)
    end)

end
