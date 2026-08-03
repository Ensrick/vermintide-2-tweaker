-- Cosmetics command-lifecycle owner.
-- Owns the regression registry/runner and persistence maintenance commands;
-- runtime checks remain lazy and register through the returned function.
local M = {}

function M.install(mod, deps)
    if mod._cos_command_owner then
        return mod._cos_command_owner.register, mod._cos_command_owner
    end

    local checks = {}
    local version = deps.version
    local local_player_safe = deps.local_player_safe
    local la_persist = deps.la_persist
    local printf = deps.printf

    local function register(name, fn, opts)
        checks[#checks + 1] = {
            name = name,
            fn = fn,
            precondition = opts and opts.precondition or nil,
        }
    end

    register("local_player_safe_network_lifecycle_609", function()
        local current_player
        local safe_calls = 0
        local fake_pm = {
            local_player = function() error("unsafe local_player called") end,
            local_player_safe = function()
                safe_calls = safe_calls + 1
                return current_player
            end,
        }
        if local_player_safe(fake_pm) ~= nil then return "title state must yield nil" end
        local live_player = {}
        current_player = live_player
        if local_player_safe(fake_pm) ~= live_player then return "ingame state lost player" end
        if safe_calls ~= 2 then return "safe accessor was not used for both transitions" end
    end)

    mod:command("cos_regression_test", "Run regression smoke checks for past bugs", function()
        local pass, fail, skip = 0, 0, 0
        mod:echo("=== cosmetics_tweaker regression_test (v%s) ===", version)
        for _, check in ipairs(checks) do
            local ok, err
            local skip_reason
            if check.precondition then
                local pc_ok, present, reason = pcall(check.precondition)
                if not pc_ok then
                    ok, err = false, "precondition error: " .. tostring(present)
                elseif not present then
                    skip_reason = tostring(reason or "precondition not met")
                end
            end
            if skip_reason then
                skip = skip + 1
                mod:echo("  SKIP: %s -- context absent: %s", check.name, skip_reason)
                mod:info("[regression] SKIP (context absent) %s: %s", check.name, skip_reason)
                if type(printf) == "function" then
                    printf("[cos-regression] SKIP (context absent) %s: %s", check.name, skip_reason)
                end
            else
                if ok == nil then ok, err = pcall(check.fn) end
                if ok and err == nil then
                    mod:echo("  PASS: %s", check.name)
                    pass = pass + 1
                    mod:info("[regression] PASS %s", check.name)
                else
                    local message = (not ok and tostring(err)) or tostring(err)
                    mod:echo("  FAIL: %s -- %s", check.name, message)
                    fail = fail + 1
                    mod:warning("[regression] FAIL %s: %s", check.name, message)
                end
            end
        end
        mod:echo("=== %d passed, %d failed ===", pass, fail)
        if skip > 0 then mod:echo("=== %d skipped (context absent) ===", skip) end
    end)
    mod:info("[regression-test-command] registered as /cos_regression_test")

    mod:command("cos_persist_dump", "Dump saved LA cosmetic + illusion entries", function()
        local player_manager = Managers and Managers.player
        local player = local_player_safe(player_manager)
        local career = player and la_persist and la_persist._career_name_for_player(player)
        mod:echo("=== la_persistence (current career: %s) ===", tostring(career))
        local persisted = mod:get("la_persisted_equips") or {}
        local careers = persisted.careers or {}
        local illusions = persisted.illusions or {}
        local career_count = 0
        for key, value in pairs(careers) do
            career_count = career_count + 1
            mod:echo("  career[%s] = { hat=%s, skin=%s }", tostring(key),
                tostring(value.slot_hat or "-"), tostring(value.slot_skin or "-"))
        end
        local illusion_count = 0
        for _ in pairs(illusions) do illusion_count = illusion_count + 1 end
        mod:echo("  %d career entries, %d illusion entries", career_count, illusion_count)
        if illusion_count > 0 and illusion_count <= 20 then
            for backend_id, skin in pairs(illusions) do
                mod:echo("    illusion[%s] = %s", tostring(backend_id), tostring(skin))
            end
        end
    end)

    mod:command("cos_persist_replay",
        "Re-apply saved LA hat + armor for local player's current career", function()
            local player_manager = Managers and Managers.player
            local player = local_player_safe(player_manager)
            if not player then mod:echo("no local player"); return end
            local count = la_persist and la_persist.restore_for_player(player) or 0
            mod:echo("replayed %d saved LA cosmetic(s) for current career", count)
        end)

    mod:command("cos_persist_clear", "Wipe all saved LA persistence entries", function()
        -- #25: route through the module so the process mirror resets with the
        -- setting. The old direct mod:set left the mirror stale and the next
        -- save_* call wrote every "cleared" record straight back.
        if la_persist and la_persist.reset_all then
            la_persist.reset_all()
        else
            mod:set("la_persisted_equips",
                { schema = 1, careers = {}, illusions = {}, offhands = {} })
        end
        mod:echo("[la-persist] cleared all saved entries")
    end)

    local owner = {
        register = register,
        command_count = 4,
        check_count = function() return #checks end,
    }
    mod._cos_command_owner = owner
    return register, owner
end

return M
