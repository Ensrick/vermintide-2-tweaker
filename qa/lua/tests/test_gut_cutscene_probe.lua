return function(H, repo_root)
    local path = repo_root
        .. "/gui_tweaker_dev/scripts/mods/gui_tweaker_dev/_gut_cutscene_probe257.lua"
    local Probe = assert(loadfile(path))()

    H.test("Well of Dreams probe classifies production fade precedence", function()
        H.equal(Probe.fade_disposition("fx_fade", true, true), "swallow_one_shot")
        H.equal(Probe.fade_disposition("fx_fade", false, true), "swallow_post_skip")
        H.equal(Probe.fade_disposition("fx_fade", false, false), "pass_fade")
        H.equal(Probe.fade_disposition("subtitle", true, true), "pass_nonfade")
    end)

    H.test("Well of Dreams probe is target-only and bounded", function()
        local state, system = Probe.new(), {}
        H.equal(Probe.record(state, "inn_level", system, "effect"), nil)
        for i = 1, Probe.max_events do
            local e = Probe.record(state, Probe.target_level, system, "effect", { marker = i })
            H.equal(e.seq, i)
            H.equal(e.marker, i)
            H.equal(e.capped, false)
        end
        local cap = Probe.record(state, Probe.target_level, system, "effect")
        H.equal(cap.phase, "cap")
        H.truthy(cap.capped)
        H.equal(Probe.record(state, Probe.target_level, system, "effect"), nil)
    end)

    H.test("Well of Dreams probe resets for a new CutsceneSystem", function()
        local state = Probe.new()
        H.equal(Probe.record(state, Probe.target_level, {}, "effect").seq, 1)
        H.equal(Probe.record(state, Probe.target_level, {}, "logic_activate").seq, 1)
        H.equal(Probe.rt_checks[1].fn(), nil)
    end)
end
