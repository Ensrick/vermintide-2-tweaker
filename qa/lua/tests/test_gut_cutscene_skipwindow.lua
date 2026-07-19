return function(H, repo_root)
    local path = repo_root
        .. "/gui_tweaker_dev/scripts/mods/gui_tweaker_dev/_gut_cutscene_skipwindow.lua"
    local W = assert(loadfile(path))()

    -- Convenience: a fresh state + one system table per test.
    local function fresh()
        return W.new(), {}
    end

    H.test("skip window arms on a proven skip and classifies both straggler kinds", function()
        local state, sys = fresh()
        W.note_logic_activate(state, sys, "cs_01_skip", 0)
        W.note_skip_executed(state, sys, "cs_01_skip", 1)
        H.truthy(W.window_active(state, sys, 2))
        -- issue 140 proven ordering: fade BEFORE its camera node - both classified
        H.equal(W.classify_fade(state, sys, false, false, 2), "swallow_window")
        H.equal(W.classify_camera(state, sys, nil, 2.1), "suppress")
        -- and the reverse order on a later group: camera before fade
        H.equal(W.classify_camera(state, sys, nil, 5), "suppress")
        H.equal(W.classify_fade(state, sys, false, false, 5.1), "swallow_window")
    end)

    H.test("straggler activity refreshes the rolling grace under the hard cap", function()
        local state, sys = fresh()
        W.note_skip_executed(state, sys, "cs_01_skip", 0)
        -- Without refresh the window would die at GRACE_SECONDS; classified
        -- stragglers keep re-granting grace...
        local t = 0
        while t + W.GRACE_SECONDS - 1 < W.MAX_WINDOW_SECONDS - 2 do
            t = t + W.GRACE_SECONDS - 1
            H.equal(W.classify_fade(state, sys, false, false, t), "swallow_window",
                "straggler at t=" .. t)
        end
        -- ...but never past the hard cap from the skip moment.
        H.equal(W.window_active(state, sys, W.MAX_WINDOW_SECONDS + 0.1), false)
        H.equal(W.classify_camera(state, sys, nil, W.MAX_WINDOW_SECONDS + 0.1), "pass")
    end)

    H.test("a silent gap longer than the grace closes the window early", function()
        local state, sys = fresh()
        W.note_skip_executed(state, sys, "cs_01_skip", 0)
        H.truthy(W.window_active(state, sys, W.GRACE_SECONDS - 0.5))
        H.equal(W.window_active(state, sys, W.GRACE_SECONDS + 0.5), false)
        H.equal(W.classify_fade(state, sys, false, false, W.GRACE_SECONDS + 0.5), "pass")
    end)

    H.test("issue 274: a logic activation is the release condition and passes the new cutscene", function()
        local state, sys = fresh()
        W.note_skip_executed(state, sys, "cs_01_skip", 0)
        H.truthy(W.window_active(state, sys, 1))
        local release, gen = W.note_logic_activate(state, sys, "outro_event", 2)
        H.equal(release, "released")
        H.truthy(gen >= 1)
        H.equal(W.window_active(state, sys, 2), false)
        -- the new cutscene's camera and fade pass untouched
        H.equal(W.classify_camera(state, sys, "outro_event", 2.1), "pass")
        H.equal(W.classify_fade(state, sys, false, false, 2.2), "pass")
    end)

    H.test("issue 274: a NEW identity visible at the camera node releases the window", function()
        local state, sys = fresh()
        W.note_logic_activate(state, sys, "cs_01_skip", 0)
        W.note_skip_executed(state, sys, "cs_01_skip", 1)
        H.truthy(W.window_active(state, sys, 2))
        -- camera-before-logic ordering on the NEXT cutscene: its stored identity
        -- differs from the skipped episode's, so it must release + pass
        H.equal(W.classify_camera(state, sys, "outro_event", 3), "released_pass")
        H.equal(W.window_active(state, sys, 3), false)
        H.equal(W.classify_fade(state, sys, false, false, 3.1), "pass")
    end)

    H.test("issue 274: a legitimate cutscene long after the skip always passes (hard bound)", function()
        local state, sys = fresh()
        W.note_logic_activate(state, sys, "cs_01_skip", 0)
        W.note_skip_executed(state, sys, "cs_01_skip", 1)
        -- the Parting of the Waves ENDING, minutes later, with NO identity visible
        -- at its camera node (worst case): the window is long dead
        H.equal(W.classify_camera(state, sys, nil, 300), "pass")
        H.equal(W.classify_fade(state, sys, false, false, 300.5), "pass")
    end)

    H.test("issue 257: pending deferred skip swallows every fade in the gap", function()
        local state, sys = fresh()
        W.note_logic_activate(state, sys, "cs_01_skip", 0)
        -- deferred skip queued; two fades arrive before the deferred tick fires
        H.equal(W.classify_fade(state, sys, true, true, 0.1), "swallow_pending")
        H.equal(W.classify_fade(state, sys, true, true, 0.2), "swallow_pending")
    end)

    H.test("issue 257: pre-identity intro watch swallows only early unidentified fades under auto-skip", function()
        local state, sys = fresh()
        -- fade arrives BEFORE any activation callback (fade-first map shape)
        H.equal(W.classify_fade(state, sys, false, true, 0), "swallow_intro_watch")
        -- without auto-skip intent it passes
        local state2, sys2 = fresh()
        H.equal(W.classify_fade(state2, sys2, false, false, 0), "pass")
        -- once the first identity resolves, the watch is closed forever
        W.note_logic_activate(state, sys, "locked_boss_event", 1)
        H.equal(W.classify_fade(state, sys, false, true, 2), "pass")
        -- and the watch itself is time-bounded from first contact
        local state3, sys3 = fresh()
        W.note_contact(state3, sys3, 0)
        H.equal(W.classify_fade(state3, sys3, false, true, W.INTRO_WATCH_SECONDS + 1), "pass")
    end)

    H.test("windows are per system instance: a fresh level's system is unaffected", function()
        local state = W.new()
        local sys_a, sys_b = {}, {}
        W.note_skip_executed(state, sys_a, "cs_01_skip", 0)
        H.truthy(W.window_active(state, sys_a, 1))
        H.equal(W.window_active(state, sys_b, 1), false)
        H.equal(W.classify_camera(state, sys_b, nil, 1), "pass")
        H.equal(W.classify_fade(state, sys_b, false, false, 1), "pass")
    end)

    H.test("bounds hold: grace positive, cap covers grace, watch bounded", function()
        H.truthy(W.GRACE_SECONDS > 0)
        H.truthy(W.MAX_WINDOW_SECONDS >= W.GRACE_SECONDS)
        H.truthy(W.MAX_WINDOW_SECONDS <= 60)
        H.truthy(W.INTRO_WATCH_SECONDS > 0)
        H.truthy(W.INTRO_WATCH_SECONDS <= 60)
    end)

    H.test("nil system never activates a window", function()
        local state = W.new()
        H.equal(W.window_active(state, nil, 0), false)
    end)

    H.test("production wiring: _gut_cutscenes classifies through the skip window", function()
        local runtime_path = repo_root
            .. "/gui_tweaker_dev/scripts/mods/gui_tweaker_dev/_gut_cutscenes.lua"
        local file = assert(io.open(runtime_path, "rb"))
        local source = file:read("*a")
        file:close()
        H.truthy(source:find("_gut_cutscene_fade_swallow_site", 1, true) ~= nil)
        H.truthy(source:find("_skipwindow.classify_fade(_sw_state, self, pending, auto, _sw_now)", 1, true) ~= nil)
        H.truthy(source:find("_skipwindow.classify_camera(_sw_state, self, self.event_on_skip, _sw_now)", 1, true) ~= nil)
        H.truthy(source:find("_skipwindow.note_logic_activate(", 1, true) ~= nil)
        H.truthy(source:find("_skipwindow.note_skip_executed(_sw_state, self, pre_skip_identity, _sw_now)", 1, true) ~= nil)
        -- the issue-275/274 intro-only SKIP policy must survive the rework
        H.truthy(source:find("_policy274.is_intro(event_on_skip)", 1, true) ~= nil)
        H.truthy(source:find("_gut_cutscene_is_intro(sys)", 1, true) ~= nil)
    end)
end
