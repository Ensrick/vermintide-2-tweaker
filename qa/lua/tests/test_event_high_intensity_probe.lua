return function(H, repo_root)
    local Probe = dofile(repo_root .. "/event_tweaker/scripts/mods/event_tweaker/_evt_issue393_probe.lua")

    local function canonical()
        return { "high_intensity" }, {
            max_intensity = 200,
            decay_per_second = 10,
            decay_delay = 0.5,
            intensity_add_per_percent_dmg_taken = 0.1,
        }, {
            delay_horde_threat_value = { normal = 200 },
            delay_specials_threat_value = { normal = 200 },
            delay_mini_patrol_threat_value = { normal = 200 },
        }, {
            delay_horde_threat_value = 200,
            delay_specials_threat_value = 200,
            delay_mini_patrol_threat_value = 200,
        }
    end

    H.test("Event high-intensity probe accepts canonical settled settings", function()
        local injected, intensity, pacing, cached = canonical()
        local verdict = Probe.classify(injected, intensity, pacing, cached)
        H.equal(verdict, "intact")
    end)

    H.test("Event high-intensity probe detects global setting stomps", function()
        local injected, intensity, pacing, cached = canonical()
        intensity.decay_per_second = 5
        local verdict, evidence = Probe.classify(injected, intensity, pacing, cached)
        H.equal(verdict, "settings_stomp")
        H.truthy(evidence:find("decay_per_second=5", 1, true))
    end)

    H.test("Event high-intensity probe detects stale director caches", function()
        local injected, intensity, pacing, cached = canonical()
        cached.delay_specials_threat_value = 75
        local verdict, evidence = Probe.classify(injected, intensity, pacing, cached)
        H.equal(verdict, "settings_stomp")
        H.truthy(evidence:find("cached.delay_specials_threat_value=75", 1, true))
    end)
end
