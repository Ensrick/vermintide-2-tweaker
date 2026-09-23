-- Offline proof for #1652: the Mod Tweaker keep route and the check that reads it.
-- RainReligion's 0.2.354-dev log failed `mod_tweaker_transition_registered` with
-- `keep branch did not call transition_with_fade`. That is the closure working as
-- designed: the HeroView sub-state route has been gated off by
-- `_USE_KEEP_SUBSTATE = false` since the 0.2.62-dev bounce revert, so the keep
-- ESC entry opens the standalone ModTweakerView. The check asserted the dormant
-- route whenever the state class existed. These cases lift the SHIPPED transition
-- closure and the SHIPPED runner out of the entry file (column-anchored, so a
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
    local LIVE_ALERT = "[mt] transition: view not attached; ESC entry is a no-op"

    local function extract_closure(source)
        local start_needle = "    settings.transitions.mod_tweaker_view = function(self)"
        local from = source:find(start_needle, 1, true)
        H.truthy(from, "transition closure not found in the entry file")
        local stop_needle = '\n    end\n    _dbg("[mt] transition registered: mod_tweaker_view")'
        local stop = source:find(stop_needle, from, true)
        H.truthy(stop, "transition closure has no column-anchored end")
        return source:sub(from, stop + #"\n    end")
    end

    -- Compiles the lifted closure with its upvalues supplied here. `_attach_view`
    -- keeps the production early-return: a pre-seeded views.mod_tweaker_view is
    -- already attached (true); no views, or no renderer, cannot attach (false).
    local function build_transition(opts)
        local block = extract_closure(main_source)
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
        H.truthy(main_source:find("\nlocal _USE_KEEP_SUBSTATE = false\n", 1, true),
            "the keep sub-state policy must stay a module-level constant")
        H.truthy(main_source:find("\nmod._gut_mt_keep_substate_routing = _USE_KEEP_SUBSTATE\n", 1, true),
            "the policy must be published for the contracts")
        H.equal(select(2, main_source:gsub("_USE_KEEP_SUBSTATE = ", "")), 1, "exactly one policy assignment")
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
end
