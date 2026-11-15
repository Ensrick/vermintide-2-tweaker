-- _rig_driver_env.lua: the simulated game that the rig driver tests run in (WP-H-01, moved here for WP-H-06).
--
-- Shared by test_rig_driver.lua and the test_rig_api_*.lua suites; not a suite itself (the gate discovers top-level
-- test_*.lua files only). Load it with
--   local E = assert(loadfile(repo_root .. "/qa/lua/tests/_rig_driver_env.lua"))()(H, repo_root)
-- The bootstrap, the driver and the cases run in a private global table per boot; see new_env.
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

    -- One helper group of tools/harness/driver/lib/ as a plan.libs entry (New-RigProfile.ps1 -LibDir sends them all).
    local function lib_entry(name)
        return { id = name, hex = hex(read(repo_root .. "/tools/harness/driver/lib/" .. name .. ".lua")) }
    end

    return {
        DRIVER = DRIVER,
        BOOTSTRAP = BOOTSTRAP,
        NONCE = NONCE,
        tag = tag,
        read = read,
        hex = hex,
        new_env = new_env,
        make_plan = make_plan,
        boot = boot,
        callback = callback,
        run_to_end = run_to_end,
        count = count,
        first = first,
        lib_entry = lib_entry,
    }
end
