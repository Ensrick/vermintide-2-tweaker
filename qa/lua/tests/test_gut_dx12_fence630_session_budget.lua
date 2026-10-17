-- Offline proof for #630 (diagnostics-armed): through 0.2.361-dev the DX12
-- fence probe (_gut_dx12_fence630.lua) had ONE 48-line budget for the whole game
-- run, created once in gui_tweaker_dev.lua. In the tester's 2026-09-23 log
-- earlier Mod Tweaker opens spent it, so the decisive session's lines and its
-- exit summary never printed. The budget is now per session (enter() resets it)
-- and the session-closing line is reserved. The real module runs here; emit is a
-- test-local ledger, nothing touches printf.
return function(H, root)
    local base = root .. "/gui_tweaker_dev/scripts/mods/gui_tweaker_dev/"
    local function load_probe()
        return assert(loadfile(base .. "_gut_dx12_fence630.lua"))()
    end

    local function find_line(lines, needle, from)
        for i = from or 1, #lines do
            if lines[i]:find(needle, 1, true) then return i, lines[i] end
        end
    end

    -- One healthy keep visit as the live card drives it: open, first draw,
    -- alt-tab out and back, switch tab and back, close.
    local function healthy_session(probe)
        probe:enter({ presentation = "standalone" })
        local steps = {
            { focus = true, tab = "gut_equipment" },
            { focus = false, tab = "gut_equipment" },
            { focus = true, tab = "gut_equipment" },
            { focus = true, tab = "gut_dev" },
            { focus = true, tab = "gut_equipment" },
        }
        for _, info in ipairs(steps) do
            probe:before_draw(info)
            probe:after_draw()
        end
        probe:leave("on_exit")
    end

    H.test("#630 the decisive later session keeps its lines and exit summary after earlier opens", function()
        local Probe = load_probe()
        local wanted = 0
        local unbounded = Probe.new({ line_cap = 100000, emit = function() wanted = wanted + 1 end })
        for _ = 1, 8 do healthy_session(unbounded) end
        H.truthy(wanted > Probe.DEFAULT_LINE_CAP, "eight healthy opens want more than one 48-line budget")

        local lines = {}
        local probe = Probe.new({ emit = function(line) lines[#lines + 1] = line end })
        for _ = 1, 8 do healthy_session(probe) end
        local decisive_from = #lines + 1
        healthy_session(probe)
        local enter_at = find_line(lines, "enter session=9 ", decisive_from)
        H.truthy(enter_at, "the ninth session must log its enter edge")
        H.truthy(find_line(lines, "frame_evidence", decisive_from), "the ninth session must log its frame evidence")
        local last = lines[#lines]
        H.truthy(last:find("exit session=9 ", 1, true), "last line must be the ninth exit summary: " .. last)
        H.truthy(last:find("balance=0 in_draw=false anomalies=0", 1, true), last)
    end)

    H.test("#630 a freeze in a later session still leaves that session's last frame evidence", function()
        local Probe = load_probe()
        local lines = {}
        local probe = Probe.new({ emit = function(line) lines[#lines + 1] = line end })
        for _ = 1, 8 do healthy_session(probe) end
        local decisive_from = #lines + 1
        -- The native fence wait never returns: no leave() runs.
        probe:enter({ presentation = "standalone" })
        probe:before_draw({ focus = true, tab = "gut_equipment" })
        probe:after_draw()
        probe:before_draw({ focus = false, tab = "gut_equipment" })
        probe:after_draw()
        local _, final = find_line(lines, "frame_evidence draw=2 ", decisive_from)
        H.truthy(final, "the alt-tab edge of the frozen session must reach the log")
        H.truthy(lines[#lines]:find("frame_evidence draw=2 ", 1, true), lines[#lines])
    end)

    H.test("#630 a session that spends its own budget prints a reserved exit naming the suppressed count", function()
        local Probe = load_probe()
        local lines = {}
        local probe = Probe.new({ line_cap = 4, emit = function(line) lines[#lines + 1] = line end })
        probe:enter({ presentation = "hero_substate" })
        for i = 1, 30 do
            probe:before_draw({ focus = i % 2 == 0, tab = "gut_equipment" })
            probe:after_draw()
        end
        local before_exit = probe:snapshot()
        H.equal(before_exit.lines, 4)
        H.equal(before_exit.capped, true)
        probe:leave("on_exit")
        H.equal(#lines, 5, "4 budgeted lines plus the reserved exit")
        H.truthy((before_exit.suppressed or 0) > 0, "snapshot must count suppressed detail lines")
        local exit = lines[5]
        H.truthy(exit:find("exit session=1 presentation=hero_substate ", 1, true), exit)
        H.truthy(exit:find("balance=0", 1, true), exit)
        H.truthy(exit:find("lines=4 suppressed=" .. before_exit.suppressed, 1, true), exit)
    end)

    H.test("#630 an abandoned session's reenter anomaly is reserved and carries its draw balance", function()
        local Probe = load_probe()
        local lines = {}
        local probe = Probe.new({ line_cap = 3, emit = function(line) lines[#lines + 1] = line end })
        probe:enter({ presentation = "standalone" })
        for i = 1, 5 do
            probe:before_draw({ focus = i % 2 == 0, tab = "gut_equipment" })
            probe:after_draw()
        end
        probe:before_draw({ focus = true, tab = "gut_equipment" }) -- unmatched begin
        H.equal(probe:snapshot().capped, true)
        probe:enter({ presentation = "hero_substate" })
        local _, anomaly = find_line(lines, "anomaly=reenter ")
        H.truthy(anomaly, "the reenter anomaly must print after the budget was spent")
        H.truthy(anomaly:find("previous=standalone session=1 begins=6 ends=5 in_draw=true", 1, true), anomaly)
        H.truthy(lines[#lines]:find("enter session=2 presentation=hero_substate", 1, true), lines[#lines])
        H.equal(probe:snapshot().lines, 1, "the new session starts a fresh budget")
    end)

    H.test("#630 output stays bounded: line_cap + 1 per session, nothing on steady frames", function()
        local Probe = load_probe()
        local lines = {}
        local probe = Probe.new({ emit = function(line) lines[#lines + 1] = line end })
        for _ = 1, 5 do
            local before = #lines
            probe:enter({ presentation = "standalone" })
            for i = 1, 200 do -- 200 alt-tab edges, each wanting two lines
                probe:before_draw({ focus = i % 2 == 0, tab = "gut_equipment" })
                probe:after_draw()
            end
            local after_edges = #lines
            for _ = 1, 1000 do
                probe:before_draw({ focus = true, tab = "gut_equipment" })
                probe:after_draw()
            end
            H.equal(#lines, after_edges, "steady frames must not emit")
            probe:leave("on_exit")
            H.truthy(#lines - before <= Probe.DEFAULT_LINE_CAP + 1,
                "session emitted " .. tostring(#lines - before))
        end
        -- Exits with no open session do not escape the budget.
        local before = #lines
        for _ = 1, 200 do probe:leave("on_exit") end
        H.truthy(#lines - before <= Probe.DEFAULT_LINE_CAP, "inactive exits emitted " .. tostring(#lines - before))
    end)

    H.test("#630 an enter/leave loop stops at the run backstop with one run_cap line", function()
        local Probe = load_probe()
        H.truthy(Probe.DEFAULT_RUN_LINE_CAP >= 20 * (Probe.DEFAULT_LINE_CAP + 1),
            "the default backstop must leave room for twenty fully spent sessions")
        local lines = {}
        local probe = Probe.new({ line_cap = 3, run_line_cap = 10,
            emit = function(line) lines[#lines + 1] = line end })
        for _ = 1, 50 do -- a lifecycle bounce: reenter without leave, then a leave
            probe:enter({ presentation = "hero_substate" })
            probe:enter({ presentation = "hero_substate" })
            probe:before_draw({ focus = true, tab = "gut_equipment" })
            probe:after_draw()
            probe:leave("on_exit")
        end
        H.equal(#lines, 11, "10 budgeted run lines plus the terminal run_cap line")
        H.truthy(lines[11]:find("[gut:630] run_cap=10 reached session=", 1, true), lines[11])
        local snap = probe:snapshot()
        H.equal(snap.run_capped, true)
        H.equal(snap.run_lines, 10)
        local before = #lines
        healthy_session(probe)
        H.equal(#lines, before, "nothing prints after the run backstop")
    end)

    H.test("#630 issue630_dx12_fence_session_budget is registered and PASSes on the shipped module", function()
        local Probe = load_probe()
        H.equal(type(Probe.session_budget_contract), "function")
        H.equal(Probe.session_budget_contract(), nil)

        local mod = {}
        local env = setmetatable({ get_mod = function() return mod end }, { __index = _G })
        function mod:dofile(path)
            if path:find("_gut_dialogue_contract", 1, true) then return { install = function() end } end
            if path:find("_mod_tweaker_tab_labels", 1, true) then return { rt_checks = {} } end
            local chunk = assert(loadfile(base .. path:match("([^/]+)$") .. ".lua"))
            setfenv(chunk, env)
            return chunk()
        end
        local registered = {}
        local chunk = assert(loadfile(base .. "_gut_mod_tweaker_contracts.lua"))
        setfenv(chunk, env)
        chunk().install({
            register = function(name, fn) registered[name] = fn end,
            src_read = function() return nil end,
        })
        local check = registered.issue630_dx12_fence_session_budget
        H.equal(type(check), "function", "contracts must register issue630_dx12_fence_session_budget")
        H.equal(check(), nil)
    end)

    H.test("#630 the session budget contract FAILs on a whole-run budget (the 0.2.361-dev shape)", function()
        local Probe = load_probe()
        H.equal(type(Probe.session_budget_contract), "function", "module must export the contract")
        local real_new = Probe.new
        -- Same probe, but one run-wide budget filters every line it emits,
        -- including the summary: what the tester's 2026-09-23 log shows.
        Probe.new = function(options)
            local total = 0
            return real_new({
                line_cap = options.line_cap,
                emit = function(line)
                    total = total + 1
                    if total <= options.line_cap then options.emit(line) end
                end,
            })
        end
        local verdict = Probe.session_budget_contract()
        Probe.new = real_new
        H.equal(verdict, "#630 exit summary was dropped once the session budget was spent")
    end)
end
