return function(H, repo_root)
    local diagnostic_path = repo_root .. "/event_tweaker/scripts/mods/event_tweaker/_evt_diag_high_intensity.lua"
    local old_path = repo_root .. "/event_tweaker/scripts/mods/event_tweaker/_evt_issue393_probe.lua"
    local owner_path = repo_root .. "/event_tweaker/scripts/mods/event_tweaker/_evt_diagnostics.lua"
    local Diagnostic = dofile(diagnostic_path)

    local function read(path)
        local file = assert(io.open(path, "rb"))
        local text = file:read("*a")
        file:close()
        return text
    end

    local function count_literal(text, needle)
        local count = 0
        local cursor = 1
        while true do
            local found = text:find(needle, cursor, true)
            if not found then return count end
            count = count + 1
            cursor = found + #needle
        end
    end

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

    H.test("Event high-intensity diagnostic accepts canonical settled settings", function()
        local injected, intensity, pacing, cached = canonical()
        local verdict = Diagnostic.classify(injected, intensity, pacing, cached)
        H.equal(verdict, "intact")
    end)

    H.test("Event high-intensity diagnostic detects global setting stomps", function()
        local injected, intensity, pacing, cached = canonical()
        intensity.decay_per_second = 5
        local verdict, evidence = Diagnostic.classify(injected, intensity, pacing, cached)
        H.equal(verdict, "settings_stomp")
        H.truthy(evidence:find("decay_per_second=5", 1, true))
    end)

    H.test("Event high-intensity diagnostic detects stale director caches", function()
        local injected, intensity, pacing, cached = canonical()
        cached.delay_specials_threat_value = 75
        local verdict, evidence = Diagnostic.classify(injected, intensity, pacing, cached)
        H.equal(verdict, "settings_stomp")
        H.truthy(evidence:find("cached.delay_specials_threat_value=75", 1, true))
    end)

    H.test("Event high-intensity diagnostic has one role-owned runtime consumer", function()
        local old = io.open(old_path, "rb")
        if old then old:close() end
        H.equal(old, nil, "legacy probe path must stay absent")

        local owner = read(owner_path)
        H.equal(count_literal(owner,
            'require("scripts/mods/event_tweaker/_evt_diag_high_intensity")'), 1)
        H.equal(count_literal(owner, 'mod:hook_safe("Pacing", "update"'), 1)
        H.equal(count_literal(owner,
            'local _issue393_seen = setmetatable({}, { __mode = "k" })'), 1)
        H.equal(count_literal(owner, "[event-inject:393] settled verdict=%s"), 1)
        H.equal(count_literal(owner,
            'ET.rt_register("issue393_high_intensity_settled_classifier"'), 1)
    end)
end
