-- Offline pin for the issue #512 / #566 context-precondition harness contract
-- (enemy_tweaker/_et_regression.lua runner; cosmetics_tweaker carries the same
-- scaffold, pinned textually below):
--   * a check may declare opts.precondition; when it reports (false, reason)
--     the runner emits an explicit "SKIP: <name> -- context absent: <reason>"
--     result (chat echo + printf) that is NEITHER a PASS nor a FAIL, and the
--     check body never runs,
--   * a truthy precondition runs the body normally (PASS/FAIL as before),
--   * a THROWING precondition reports as FAIL ("precondition error: ..."),
--     never as a skip, so a broken gate cannot mask its check,
--   * two-argument registrations keep their exact pre-#512 behavior,
--   * the #512 pacing application: spawn_pacing_mini_patrol_runtime_path
--     SKIPs under the keep's disabled pacing preset (no mini_patrol block,
--     conflict_settings.lua:3603), PASSes under a mission-shaped enabled
--     clone (conflict_director.lua:878), and still true-positive-FAILs when
--     the mini_patrol path is renamed/removed in an enabled clone.
-- The suite loads the REAL shipped modules under a stubbed VMF environment
-- (same pattern as test_et_pacing_tick_guard.lua) and drives the captured
-- /et_regression_test command.
return function(H, repo_root)
    local root = repo_root .. "/enemy_tweaker/scripts/mods/enemy_tweaker/"
    local cos_root = repo_root .. "/cosmetics_tweaker/scripts/mods/cosmetics_tweaker/"

    local function read_all(path)
        local file = assert(io.open(path, "rb"))
        local text = file:read("*a")
        file:close()
        return text
    end

    -- ------------------------------------------------------------------
    -- Load _et_regression.lua (the real registrar + runner), then
    -- _et_protect.lua and _et_pacing.lua so the real #512 checks register.
    -- ------------------------------------------------------------------
    local lines = {}
    local printf_lines = {}
    local commands = {}
    local mod, ET
    local load_err
    do
        ET = {
            version = "0.0.0-test",
            dbg = function() end,
            dbg_alert = function() end,
            et_probe = function() end,
        }
        mod = { _et = ET }
        function mod:hook() end
        function mod:hook_safe() end
        function mod:get() return nil end
        function mod:info() end
        function mod:warning() end
        function mod:echo(fmt, ...)
            local line = fmt
            if select("#", ...) > 0 then
                local ok, formatted = pcall(string.format, fmt, ...)
                line = ok and formatted or (tostring(fmt) .. " <format error>")
            end
            lines[#lines + 1] = line
        end
        function mod:command(name, _, fn) commands[name] = fn end

        local env = setmetatable({
            get_mod = function() return mod end,
            printf = function(fmt, ...)
                local line = fmt
                if select("#", ...) > 0 then
                    local ok, formatted = pcall(string.format, fmt, ...)
                    line = ok and formatted or tostring(fmt)
                end
                printf_lines[#printf_lines + 1] = line
            end,
        }, { __index = _G })

        local prior_cd = rawget(_G, "ConflictDirector")
        _G.ConflictDirector = {} -- boot-global stand-in; gates hook registration
        local ok, err = pcall(function()
            for _, name in ipairs({ "_et_regression.lua", "_et_protect.lua", "_et_pacing.lua" }) do
                local chunk = assert(loadfile(root .. name))
                setfenv(chunk, env)
                chunk()
            end
        end)
        _G.ConflictDirector = prior_cd
        if not ok then load_err = err end
    end

    -- Synthetic checks appended AFTER the real ones, covering every runner
    -- outcome the contract defines.
    local synth = { met_runs = 0, absent_body_runs = 0 }
    if load_err == nil and type(ET.rt_register) == "function" then
        ET.rt_register("synth_back_compat_pass", function() end)
        ET.rt_register("synth_plain_fail", function() return "planted failure" end)
        ET.rt_register("synth_ctx_absent", function()
            synth.absent_body_runs = synth.absent_body_runs + 1
        end, { precondition = function() return false, "planted absent context" end })
        ET.rt_register("synth_ctx_met", function()
            synth.met_runs = synth.met_runs + 1
        end, { precondition = function() return true end })
        ET.rt_register("synth_ctx_broken", function() end,
            { precondition = function() error("planted precondition error") end })
    end

    -- Drive the captured command with a full fake spawn-pacing engine surface
    -- planted in the real _G (the checks read via rawget(_G, ...)), restoring
    -- every prior value afterwards.
    local function run_suite(current_pacing)
        local fn = commands["et_regression_test"]
        if type(fn) ~= "function" then
            error("/et_regression_test command was not captured")
        end
        local planted = {
            ConflictDirector = {
                update = function() end,
                update_horde_pacing = function() end,
                horde_killed = function() end,
                update_mini_patrol = function() end,
                calculate_threat_value = function() end,
            },
            Pacing = { update = function() end },
            RecycleSettings = { max_grunts = 60, push_horde_if_num_alive_grunts_above = 15 },
            PacingSettings = {
                default = {
                    horde_frequency = { 50, 100 },
                    mini_patrol = { only_spawn_below_intensity = 15 },
                },
            },
            CurrentPacing = current_pacing,
        }
        local saved = {}
        for key, value in pairs(planted) do
            saved[key] = rawget(_G, key)
            _G[key] = value
        end
        for i = #lines, 1, -1 do lines[i] = nil end
        for i = #printf_lines, 1, -1 do printf_lines[i] = nil end
        local ok, err = pcall(fn)
        for key in pairs(planted) do
            _G[key] = saved[key]
        end
        if not ok then
            error("suite invocation errored: " .. tostring(err))
        end
        local echo_snapshot = {}
        for i, line in ipairs(lines) do echo_snapshot[i] = line end
        local printf_snapshot = {}
        for i, line in ipairs(printf_lines) do printf_snapshot[i] = line end
        return echo_snapshot, printf_snapshot
    end

    local function find_line(snapshot, needle)
        for _, line in ipairs(snapshot) do
            if line:find(needle, 1, true) then return line end
        end
        return nil
    end

    H.test("ET harness modules load with the real precondition-aware registrar", function()
        H.equal(load_err, nil)
    end)

    H.test("keep-shaped run: mini_patrol check SKIPs as context absent, never FAILs", function()
        H.equal(load_err, nil)
        -- The keep's clone is PacingSettings.disabled: no mini_patrol block.
        local echo, plog = run_suite({ disabled = true, horde_frequency = { 0, 0 } })
        H.truthy(find_line(echo, "PASS: spawn_pacing_hook_targets_present"),
            "static pacing surface check must PASS at the keep")
        local skip_line = find_line(echo, "SKIP: spawn_pacing_mini_patrol_runtime_path")
        H.truthy(skip_line, "mini_patrol runtime check must SKIP at the keep")
        H.truthy(skip_line:find("context absent: no live mission conflict director pacing", 1, true),
            "skip line must carry the context-absent reason")
        H.equal(find_line(echo, "FAIL: spawn_pacing_mini_patrol_runtime_path"), nil,
            "the pre-0.7.36 keep false-FAIL must not come back")
        H.truthy(find_line(echo, "passed,"), "pass/fail summary line must survive")
        H.truthy(find_line(echo, "skipped (context absent)"),
            "skip summary line must be reported when skips occurred")
        H.truthy(find_line(plog, "SKIP (context absent) spawn_pacing_mini_patrol_runtime_path"),
            "printf skip line missing (must be visible with mod logging off)")
    end)

    H.test("runner contract: back-compat, fail, absent, met, and broken preconditions", function()
        H.equal(load_err, nil)
        local echo = run_suite({ disabled = true, horde_frequency = { 0, 0 } })
        H.truthy(find_line(echo, "PASS: synth_back_compat_pass"),
            "2-arg registration must keep pre-#512 behavior")
        H.truthy(find_line(echo, "FAIL: synth_plain_fail -- planted failure"),
            "plain FAIL reporting must survive")
        local absent_line = find_line(echo, "SKIP: synth_ctx_absent")
        H.truthy(absent_line, "false precondition must SKIP")
        H.truthy(absent_line:find("context absent: planted absent context", 1, true),
            "skip line must carry the precondition's reason")
        H.equal(synth.absent_body_runs, 0, "a skipped check's body must never run")
        H.truthy(find_line(echo, "PASS: synth_ctx_met"),
            "true precondition must run the body")
        H.truthy(synth.met_runs >= 1, "met-precondition body did not run")
        local broken_line = find_line(echo, "FAIL: synth_ctx_broken")
        H.truthy(broken_line, "a THROWING precondition must report as FAIL, not skip")
        H.truthy(broken_line:find("precondition error:", 1, true),
            "broken-precondition FAIL must name the precondition error")
        H.truthy(broken_line:find("planted precondition error", 1, true),
            "broken-precondition FAIL must carry the thrown message")
    end)

    H.test("mission-shaped run: mini_patrol check runs and PASSes", function()
        H.equal(load_err, nil)
        local before = synth.met_runs
        local echo = run_suite({
            horde_frequency = { 50, 100 },
            mini_patrol = { only_spawn_below_intensity = 15 },
        })
        H.truthy(find_line(echo, "PASS: spawn_pacing_mini_patrol_runtime_path"),
            "enabled pacing clone must run and pass the mini_patrol check")
        H.equal(find_line(echo, "SKIP: spawn_pacing_mini_patrol_runtime_path"), nil,
            "no skip when the mission context is live")
        H.truthy(find_line(echo, "PASS: spawn_pacing_hook_targets_present"),
            "static pacing surface check must PASS in-mission")
        H.equal(synth.met_runs, before + 1,
            "preconditions must be re-evaluated on every run")
    end)

    H.test("mission-shaped run with a renamed path stays a true-positive FAIL", function()
        H.equal(load_err, nil)
        local echo = run_suite({
            horde_frequency = { 50, 100 },
            mini_patrol = {}, -- only_spawn_below_intensity renamed/removed
        })
        local fail_line = find_line(echo, "FAIL: spawn_pacing_mini_patrol_runtime_path")
        H.truthy(fail_line, "renamed mini_patrol path must FAIL when the context is live")
        H.truthy(fail_line:find("only_spawn_below_intensity (path changed)", 1, true),
            "FAIL must name the mutated pacing path")
    end)

    H.test("both mods' scaffolds carry the precondition contract (source pins)", function()
        local et_reg = read_all(root .. "_et_regression.lua")
        H.truthy(et_reg:find("opts and opts.precondition", 1, true) ~= nil,
            "et registrar lost opts.precondition")
        H.truthy(et_reg:find("SKIP: %s -- context absent: %s", 1, true) ~= nil,
            "et runner lost the context-absent SKIP line")
        H.truthy(et_reg:find("skipped (context absent)", 1, true) ~= nil,
            "et runner lost the skip summary")

        local et_pacing = read_all(root .. "_et_pacing.lua")
        H.truthy(et_pacing:find("spawn_pacing_mini_patrol_runtime_path", 1, true) ~= nil,
            "the #512 precondition-gated pacing check is gone")
        H.equal(et_pacing:find("not CP.disabled and (type(CP.mini_patrol)", 1, true), nil,
            "the old inline CP.disabled gate must stay retired (single ownership)")

        local cos_entry = read_all(cos_root .. "cosmetics_tweaker.lua")
        H.truthy(cos_entry:find("opts and opts.precondition", 1, true) ~= nil,
            "cosmetics registrar lost opts.precondition")
        H.truthy(cos_entry:find("SKIP: %s -- context absent: %s", 1, true) ~= nil,
            "cosmetics runner lost the context-absent SKIP line")
        H.truthy(cos_entry:find("skipped (context absent)", 1, true) ~= nil,
            "cosmetics runner lost the skip summary")

        local cos_checks = read_all(cos_root .. "_cos_runtime_checks.lua")
        H.truthy(cos_checks:find("MaterialSettingsTemplates not populated (engine boot state)", 1, true) ~= nil,
            "#566 check lost its engine-catalog precondition")
        H.equal(cos_checks:find("MaterialSettingsTemplates global not loaded", 1, true), nil,
            "#566 check must not FAIL on unpopulated engine catalogs (context absent, not a failure)")
        H.truthy(cos_checks:find("white_glow fallback skin mapping missing or changed", 1, true) ~= nil,
            "#566 inversion lost: the Nornaz white_glow FALLBACK contract must stay asserted")
        H.truthy(cos_checks:find('"blue_glow", "purple_glow", "golden_glow", "deep_crimson",', 1, true) ~= nil,
            "#566 registered-family coverage lost (the eight vanilla-registered templates)")
        H.equal(cos_checks:find('"white_glow",', 1, true), nil,
            "the suite must never demand a white_glow registration vanilla does not perform")
    end)
end
