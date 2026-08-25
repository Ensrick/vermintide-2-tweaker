-- Issue #1156 / PROJECT_STANDARDS 5.1d rule 3: the runner passes ONLY on a `nil` return, so a
-- check that reports success as `true` is a permanent FAIL against healthy wiring (#1153, and
-- BUG_CLASSES 85 sub-pattern (c)). Five gt diagnostic checks were repaired for #1153 but never
-- locked offline, so nothing stops the boolean shape from coming back.
--
-- Each case below loads the PRODUCTION module (never a copied fixture, per 5.4), proves the
-- registration RESOLVED under its exact name, asserts nil-on-success, and then plants a
-- regression that the check must catch. The planted half is what makes the nil half meaningful:
-- without it, a check that returned nil unconditionally would pass this test just as happily.
return function(H, repo_root)
    local base = repo_root
        .. "/general_tweaker_dev/scripts/mods/general_tweaker_dev/"

    -- Engine surfaces these modules only touch at hook-install time. A stub that answers any
    -- index with another stub keeps the load from erroring without teaching the test anything
    -- about behavior -- the assertions all run against the mod table, not these.
    local function stub()
        return setmetatable({}, {
            __index = function() return stub() end,
            __call = function() return stub() end,
        })
    end

    local GLOBALS = {
        "Managers", "Unit", "Actor", "ScriptUnit", "NetworkUnit", "InteractionDefinitions",
        "InteractionResult", "World", "Vector3", "Quaternion", "BotConstants", "AiUtils",
        "LevelHelper", "PLAYER_UNITS", "Breeds", "DamageUtils", "ConflictDirector",
        "POSITION_LOOKUP", "HEALTH_ALIVE", "ALIVE",
    }

    local function load_gt_module(file)
        local registrations, loaded = {}, {}
        local mod
        mod = {
            get = function() return true end,
            hook = function() end,
            hook_safe = function() end,
            command = function() end,
            echo = function() end,
            info = function() end,
            debug = function() end,
            warning = function() end,
            localize = function(_, key) return key end,
            -- Cached so a test can reach the very table the check closed over.
            dofile = function(_, path)
                local name = path:match("([^/]+)$")
                if loaded[name] == nil then
                    loaded[name] = assert(loadfile(base .. name .. ".lua"))()
                end
                return loaded[name]
            end,
        }
        mod._gt_rt_register = function(name, fn) registrations[name] = fn end
        mod._gt_register_update = function() end

        local saved = { get_mod = _G.get_mod, printf = _G.printf, PeerStates = _G.PeerStates }
        for _, name in ipairs(GLOBALS) do saved[name] = _G[name] end

        _G.get_mod = function() return mod end
        _G.printf = function() end
        -- Real function: the #309 probe only records itself installed when the vanilla method
        -- it wraps is actually present, and a stub table would silently skip that branch.
        _G.PeerStates = { Disconnecting = { on_enter = function() end } }
        for _, name in ipairs(GLOBALS) do _G[name] = stub() end

        local ok, err = pcall(function() return assert(loadfile(base .. file))() end)

        for name, value in pairs(saved) do _G[name] = value end

        H.truthy(ok, file .. " failed to load: " .. tostring(err))
        return mod, registrations, loaded
    end

    -- name -> the exact registration the gt runner will invoke. A rename or a relocation out of
    -- this module makes the lookup nil, and the assert below says so instead of scoring green.
    local function resolve(registrations, name)
        local check = registrations[name]
        H.equal(type(check), "function",
            name .. " is not registered by its owning module (renamed, relocated, or dropped)")
        return check
    end

    H.test("GT #309 disconnect-grace check returns nil when armed and a reason when not", function()
        local mod, registrations = load_gt_module("_gt_disconnect_grace_diag.lua")
        local check = resolve(registrations, "issue309_disconnect_grace_diagnostics_armed")
        H.equal(check(), nil)

        mod._gt_disconnect_grace_hook_installed = false
        H.equal(type(check()), "string")
        mod._gt_disconnect_grace_hook_installed = true
        H.equal(check(), nil)

        mod._gt_disconnect_grace_on_remote_join = nil
        H.equal(type(check()), "string")
    end)

    H.test("GT #347 closed-chest check returns nil when armed and a reason when not", function()
        local _, registrations, loaded = load_gt_module("_gt_bot_pickups.lua")
        local check = resolve(registrations, "issue347_closed_chest_pickup_diagnostics")
        H.equal(check(), nil)

        local core = loaded["_gt_diag_chest_pickup_state"]
        H.equal(type(core), "table")
        local original = core.MAX_RECORDS
        core.MAX_RECORDS = original + 1
        H.equal(type(check()), "string")
        core.MAX_RECORDS = original
        H.equal(check(), nil)
    end)

    H.test("GT #753 disconnect-failure check returns nil when armed and a reason when not", function()
        local mod, registrations = load_gt_module("_gt_diag_disconnect_failure.lua")
        local check = resolve(registrations, "issue753_disconnect_failure_diagnostics_armed")
        H.equal(check(), nil)

        local state = mod._gt753_disconnect_diagnostics
        state.steam_hook = false
        H.equal(type(check()), "string")
        state.steam_hook = true
        H.equal(check(), nil)

        local policy = state.policy
        state.policy = nil
        H.equal(type(check()), "string")
        state.policy = policy
        H.equal(check(), nil)
    end)

    H.test("GT #659 necromancer keep-trace check returns nil when armed and a reason when not", function()
        local saved_marker = _G.GT_NECRO_KEEP_TRACE_MARKER_659
        local mod, registrations, loaded = load_gt_module("_gt_necro_keep_trace.lua")
        local check = resolve(registrations, "issue659_necromancer_keep_trace_armed")
        H.equal(check(), nil)

        _G.GT_NECRO_KEEP_TRACE_MARKER_659 = "reverted"
        H.equal(type(check()), "string")
        _G.GT_NECRO_KEEP_TRACE_MARKER_659 = "gt-necro-activation-target-passive-server-trace"
        H.equal(check(), nil)

        -- The per-phase caps are the point of a BOUNDED trace; drifting one must fail the check.
        local core = loaded["_gt_necro_keep_trace_core"]
        H.equal(type(core), "table")
        local original = core.LIMITS.spawn_pet
        core.LIMITS.spawn_pet = original + 1
        H.equal(type(check()), "string")
        core.LIMITS.spawn_pet = original

        local state = mod._gt_necro_keep_trace_state
        mod._gt_necro_keep_trace_state = nil
        H.equal(type(check()), "string")
        mod._gt_necro_keep_trace_state = state
        H.equal(check(), nil)

        _G.GT_NECRO_KEEP_TRACE_MARKER_659 = saved_marker
    end)

    H.test("GT bot-utility nil guard check returns nil when armed and a reason when not", function()
        local mod, registrations = load_gt_module("_gt_bot_fixes.lua")
        local check = resolve(registrations, "gt_bot_utility_nil_guard")
        H.equal(check(), nil)

        -- The guard exists to keep a nil blackboard input from reaching a numeric comparison.
        -- A policy that stops substituting the sentinel is exactly the regression it locks.
        local policy = mod._gt_bot_utility_policy
        local original = policy.prepare_utility_inputs
        policy.prepare_utility_inputs = function(_, _, blackboard)
            blackboard.ally_distance = nil
            return true
        end
        H.equal(type(check()), "string")
        policy.prepare_utility_inputs = original
        H.equal(check(), nil)
    end)

    H.test("GT diagnostic checks never report success as a boolean", function()
        local cases = {
            { "_gt_disconnect_grace_diag.lua", "issue309_disconnect_grace_diagnostics_armed" },
            { "_gt_bot_pickups.lua", "issue347_closed_chest_pickup_diagnostics" },
            { "_gt_diag_disconnect_failure.lua", "issue753_disconnect_failure_diagnostics_armed" },
            { "_gt_necro_keep_trace.lua", "issue659_necromancer_keep_trace_armed" },
            { "_gt_bot_fixes.lua", "gt_bot_utility_nil_guard" },
        }
        for _, case in ipairs(cases) do
            local _, registrations = load_gt_module(case[1])
            local verdict = resolve(registrations, case[2])()
            H.equal(type(verdict) == "boolean", false,
                case[2] .. " returned a boolean; the gt runner scores that BAD-SHAPE, not PASS")
            H.equal(verdict, nil)
        end
    end)
end
