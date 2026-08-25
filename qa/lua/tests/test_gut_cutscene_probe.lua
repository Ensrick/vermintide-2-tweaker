return function(H, repo_root)
    local path = repo_root
        .. "/gui_tweaker_dev/scripts/mods/gui_tweaker_dev/_gut_diag_cutscene257.lua"
    local Probe = assert(loadfile(path))()

    local function read(source_path)
        local file = assert(io.open(source_path, "rb"))
        local source = file:read("*a")
        file:close()
        return source
    end

    local function count_literal(source, needle)
        local count, cursor = 0, 1
        while true do
            local found = source:find(needle, cursor, true)
            if not found then return count end
            count = count + 1
            cursor = found + #needle
        end
    end

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

        local old_path = repo_root
            .. "/gui_tweaker_dev/scripts/mods/gui_tweaker_dev/_gut_cutscene_probe257.lua"
        local old = io.open(old_path, "rb")
        if old then old:close() end
        H.equal(old, nil, "legacy probe path must stay absent")

        local owner_path = repo_root
            .. "/gui_tweaker_dev/scripts/mods/gui_tweaker_dev/_gut_cutscenes.lua"
        local owner = read(owner_path)
        local diagnostic_load =
            'mod:dofile("scripts/mods/gui_tweaker_dev/_gut_diag_cutscene257")'
        H.equal(count_literal(owner, diagnostic_load), 1)
        H.equal(count_literal(owner, "local _probe257_state = _probe257.new()"), 1)
        H.equal(count_literal(owner, "local function _trace257"), 1)
        H.equal(count_literal(owner, "[gut:257] seq=%s phase=%s level=%s"), 1)

        local diagnostic_at = assert(owner:find(diagnostic_load, 1, true))
        local policy_at = assert(owner:find(
            'mod:dofile("scripts/mods/gui_tweaker_dev/_gut_cutscene_policy274")',
            diagnostic_at, true))
        local skipwindow_at = assert(owner:find(
            'mod:dofile("scripts/mods/gui_tweaker_dev/_gut_cutscene_skipwindow")',
            policy_at, true))
        H.truthy(diagnostic_at < policy_at and policy_at < skipwindow_at)
    end)
end
