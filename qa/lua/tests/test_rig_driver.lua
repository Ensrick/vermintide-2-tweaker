-- test_rig_driver.lua: offline run of the test rig driver (WP-H-01).
--
-- Loads the real bootstrap (tools/harness/bootstrap/vt2_rig_driver.mod) and lets it compile the real driver
-- (tools/harness/driver/vt2_rig_driver.lua) from a plan that a stub Application.user_setting returns, exactly as
-- the game does. Every engine global the two files read is a stub inside a private environment, so nothing
-- leaks into the shared test process. The driver's callbacks are called the way the game's mod manager calls
-- them (pcall(cb, object, ...), Vermintide-2-Source-Code/scripts/managers/mod/mod_manager.lua:208-216).
--
-- This proves the driver's control flow and evidence lines only. It does not prove that any engine call
-- behaves like the stub: that is what rig runs are for.
return function(H, repo_root)
    local DRIVER = repo_root .. "/tools/harness/driver/vt2_rig_driver.lua"
    local BOOTSTRAP = repo_root .. "/tools/harness/bootstrap/vt2_rig_driver.mod"
    local NONCE = "0123abcd"

    local function read(path)
        local file = assert(io.open(path, "rb"))
        local text = file:read("*a")
        file:close()
        return text
    end

    local function hex(text)
        return (text:gsub(".", function(c)
            return string.format("%02x", c:byte())
        end))
    end

    -- A private global table for one simulated game: the bootstrap, the driver and the cases all run in it.
    local function new_env(plan, opts)
        opts = opts or {}
        local env, lines, settings = {}, {}, { vt2_rig_plan = plan }
        setmetatable(env, { __index = _G })
        env._G = env
        env.print = function(...)
            local parts = {}
            for i = 1, select("#", ...) do
                parts[i] = tostring((select(i, ...)))
            end
            lines[#lines + 1] = table.concat(parts, "\t")
        end
        -- Lua 5.1 gives a loadstring chunk the thread's globals; keep compiled code inside the private table.
        env.loadstring = function(source, name)
            local chunk, err = loadstring(source, name)
            if chunk then
                setfenv(chunk, env)
            end
            return chunk, err
        end
        env.table = setmetatable({
            clear = function(t)
                for key in pairs(t) do
                    t[key] = nil
                end
            end,
        }, { __index = table })
        env.MODDED_REALM = opts.modded_realm ~= false
        env.Development = {
            application_parameter = { ["vt2-test-run"] = opts.command_line_nonce or NONCE },
            _hardcoded_dev_params = {},
        }
        env.GameSettingsDevelopment = {}
        env.Application = {
            user_setting = function(key)
                return settings[key]
            end,
            set_user_setting = function(key, value)
                settings[key] = value
            end,
            save_user_settings = function()
                settings.saves = (settings.saves or 0) + 1
            end,
        }
        local hero = { name = "stub hero unit" }
        env.Unit = {
            alive = function(unit)
                return unit ~= nil and unit == hero
            end,
        }
        env.Boot = { quit_game = false }
        env.Managers = {
            player = {
                local_player = function()
                    return { player_unit = hero }
                end,
                bots = function()
                    return {}
                end,
            },
            state = {
                game_mode = {
                    level_key = function()
                        return "inn_level"
                    end,
                },
            },
            backend = opts.backend,
        }
        env.cjson = opts.cjson
        return env, lines, settings
    end

    local function make_plan(cases, extra)
        local plan = {
            nonce = NONCE,
            name = "offline",
            timeout = 600,
            settle = 1,
            quit = true,
            driver_hex = hex(read(DRIVER)),
            cases = {},
        }
        for i, case in ipairs(cases) do
            plan.cases[i] = { id = case.id, arena = case.arena or "keep", hex = hex(case.src) }
        end
        for key, value in pairs(extra or {}) do
            plan[key] = value
        end
        return plan
    end

    local function boot(plan, opts)
        local env, lines, settings = new_env(plan, opts)
        local chunk = assert(loadfile(BOOTSTRAP))
        setfenv(chunk, env)
        local mod_data = chunk()
        H.equal(type(mod_data.run), "function", "bootstrap returns a table with run()")
        local ok, object = pcall(mod_data.run)
        H.truthy(ok, "bootstrap run() raised: " .. tostring(object))
        return object, env, lines, settings
    end

    local function callback(object, name, ...)
        local cb = object[name]
        if not cb then
            return
        end
        local ok, err = pcall(cb, object, ...)
        if not ok then
            error("driver callback " .. name .. " raised; the game would disable its callbacks: " .. tostring(err), 2)
        end
    end

    local function run_to_end(object, env, max_ticks)
        callback(object, "on_game_state_changed", "enter", "StateTitleScreen")
        callback(object, "update", 0.1)
        callback(object, "on_game_state_changed", "enter", "StateIngame")
        for _ = 1, max_ticks or 20000 do
            callback(object, "update", 0.1)
            if env.Boot.quit_game then
                return true
            end
        end
        return false
    end

    local function count(lines, pattern)
        local n = 0
        for _, line in ipairs(lines) do
            if line:find(pattern) then
                n = n + 1
            end
        end
        return n
    end

    local function first(lines, pattern)
        for _, line in ipairs(lines) do
            if line:find(pattern) then
                return line
            end
        end
    end

    local tag = "^%[vt2t:" .. NONCE .. "%] "

    local PASS_CASE = [[
return {
    issue = 0,
    timeout = 30,
    run = function(T)
        T.step("read the stub world")
        T.expect(T.local_player() ~= nil, "local player exists")
        T.expect_eq(T.level_key(), "inn_level", "level is the keep")
        T.wait(0.5)
        T.expect_near(1.0, 1.0004, 0.001, "near")
    end,
}
]]
    local FAIL_CASE = [[
return {
    issue = 0,
    run = function(T)
        T.expect(true, "this one holds")
        T.expect(false, "planted expect failure")
        T.expect(true, "the case continues after a failure")
    end,
}
]]

    H.test("rig driver: bootstrap compiles the driver from the plan and the run reaches RUN END", function()
        local plan = make_plan({ { id = "pass", src = PASS_CASE }, { id = "fail", src = FAIL_CASE } })
        local object, env, lines, settings = boot(plan)
        H.truthy(type(object.update) == "function" and type(object.on_game_state_changed) == "function",
            "bootstrap returns the driver object")
        H.truthy(first(lines, tag .. "BOOTSTRAP OK"), "BOOTSTRAP OK printed")
        H.truthy(first(lines, tag .. "RUN BEGIN driver=%S+ plan=\"offline\" cases=2"), "RUN BEGIN printed with two cases")
        H.truthy(run_to_end(object, env), "the driver asked the game to quit")
        H.equal(env.Boot.quit_game, true, "Boot.quit_game set")
        H.equal(count(lines, tag .. "KEEP READY level=inn_level"), 1, "KEEP READY once")
        H.equal(count(lines, tag .. "CASE END id=pass verdict=PASS asserts=3 failed=0"), 1, "one PASS case end")
        H.equal(count(lines, tag .. "CASE END id=fail verdict=FAIL asserts=3 failed=1"), 1, "one FAIL case end")
        H.equal(count(lines, tag .. "CASE END id=%S+ verdict=PASS"), 1, "exactly one PASS")
        H.equal(count(lines, tag .. "CASE END id=%S+ verdict=FAIL"), 1, "exactly one FAIL")
        H.truthy(first(lines, tag .. "CASE END id=fail verdict=FAIL .* detail=\"planted expect failure\""),
            "FAIL names the first failed assertion")
        H.truthy(first(lines, tag .. "ASSERT id=fail n=%d+ FAIL label=\"planted expect failure\""), "failed ASSERT line printed")
        H.equal(count(lines, tag .. "RUN END reason=\"plan complete\" cases=2 pass=1 fail=1 error=0 timeout=0 inconclusive=0"), 1,
            "RUN END with the counts")
        for _, line in ipairs(lines) do
            H.truthy(line:find(tag), "every printed line carries the run tag: " .. line)
        end
        local results = settings.vt2_rig_results
        H.truthy(type(results) == "table" and results.nonce == NONCE and #results.cases == 2, "vt2_rig_results saved with both cases")
        H.equal(results.cases[1].verdict, "PASS")
        H.equal(results.cases[2].verdict, "FAIL")
        H.truthy(type(settings.vt2_rig_progress) == "table" and settings.vt2_rig_progress.phase == "QUIT", "progress checkpoint ends in QUIT")
    end)

    H.test("rig driver: a script that throws ends as ERROR and the run continues", function()
        local plan = make_plan({
            { id = "boom", src = "return { run = function(T) T.step('about to throw') error('planted script error') end }" },
            { id = "after", src = PASS_CASE },
        })
        local object, env, lines = boot(plan)
        H.truthy(run_to_end(object, env), "run completed")
        H.truthy(first(lines, tag .. "CASE END id=boom verdict=ERROR .*planted script error"), "ERROR with the message")
        H.equal(count(lines, tag .. "CASE END id=after verdict=PASS"), 1, "next case still runs")
        H.equal(count(lines, tag .. "RUN END .* error=1"), 1, "RUN END counts the error")
    end)

    H.test("rig driver: a script that does not compile ends as ERROR", function()
        local plan = make_plan({ { id = "syntax", src = "return { run = function(T) T.step( end }" } })
        local object, env, lines = boot(plan)
        H.truthy(run_to_end(object, env), "run completed")
        H.truthy(first(lines, tag .. "CASE END id=syntax verdict=ERROR .*compile:"), "compile error reported as ERROR")
    end)

    H.test("rig driver: a script that outlives its timeout ends as TIMEOUT", function()
        local plan = make_plan({ { id = "slow", src = "return { timeout = 1, run = function(T) T.wait(30) end }" } })
        local object, env, lines = boot(plan)
        H.truthy(run_to_end(object, env), "run completed")
        H.truthy(first(lines, tag .. "CASE END id=slow verdict=TIMEOUT .*exceeded 1 s"), "TIMEOUT reported")
        H.equal(count(lines, tag .. "RUN END .* timeout=1"), 1, "RUN END counts the timeout")
    end)

    H.test("rig driver: a failed precondition ends as INCONCLUSIVE, not FAIL", function()
        local plan = make_plan({
            { id = "pre", src = "return { run = function(T) T.require(false, 'precondition absent') T.expect(false, 'never reached') end }" },
        })
        local object, env, lines = boot(plan)
        H.truthy(run_to_end(object, env), "run completed")
        H.truthy(first(lines, tag .. "REQUIRE id=pre FAILED label=\"precondition absent\""), "REQUIRE line printed")
        H.truthy(first(lines, tag .. "CASE END id=pre verdict=INCONCLUSIVE asserts=0 failed=0 .*precondition absent"),
            "INCONCLUSIVE with the label")
        H.equal(count(lines, "never reached"), 0, "nothing after the precondition ran")
        H.equal(count(lines, tag .. "RUN END .* fail=0 .* inconclusive=1"), 1, "RUN END counts it as inconclusive")
    end)

    H.test("rig bootstrap: inert unless the command line nonce matches the plan", function()
        local plan = make_plan({ { id = "pass", src = PASS_CASE } })
        local object, _, lines = boot(plan, { command_line_nonce = "ffffffff" })
        H.equal(next(object), nil, "bootstrap returns an empty object")
        H.equal(#lines, 0, "nothing printed")
        local realm_object, _, realm_lines = boot(plan, { modded_realm = false })
        H.equal(next(realm_object), nil, "bootstrap is inert outside the modded realm")
        H.equal(#realm_lines, 0, "nothing printed outside the modded realm")
    end)
end
