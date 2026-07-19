-- Offline pin for the issue #479 ConflictDirector tick-guard contract
-- (enemy_tweaker/_et_protect.lua + _et_pacing.lua):
--   * hooks on non-re-runnable per-tick targets must NEVER re-run vanilla on an
--     inner error (the pre-#479 _hook_wrap fallback re-popped the still-unbooked
--     spawn queue and doubled partial state - the #470 crash session),
--   * engine-global overrides (RecycleSettings.max_grunts) restore on BOTH the
--     success and the error path,
--   * fault episodes log once and report a recovery summary (the 2026-07-13
--     recurrence produced 1,173 identical failures in 17 s),
--   * the terror_event_mixer.lua:1800 malformed-event recovery is EXACT-error
--     scoped: it reproduces vanilla's missed post-return index advance
--     (enemy_recycler.lua:456-463) and quarantines ET pacing overrides; unknown
--     errors fail closed with no guessed state mutation.
-- The suite loads the shipped modules under a stubbed VMF environment and also
-- executes the three shipped in-game `/et_regression_test` #479 check bodies
-- offline, so a drift in either the helpers or the checks fails CI.
return function(H, repo_root)
    local root = repo_root .. "/enemy_tweaker/scripts/mods/enemy_tweaker/"

    -- Load _et_protect.lua then _et_pacing.lua under a stub mod. A fake
    -- ConflictDirector boot global is planted in the REAL _G for the duration
    -- (both files gate hook registration on rawget(_G, "ConflictDirector")),
    -- then restored, so the wrap-registry provenance the in-game #479 check
    -- asserts gets populated here exactly as it does at mod load in retail.
    local checks = {}
    local mod
    local load_err
    do
        local ET = {
            rt_register = function(name, fn) checks[name] = fn end,
            dbg = function() end,
            dbg_alert = function() end,
            et_probe = function() end,
        }
        mod = { _et = ET }
        function mod:hook() end
        function mod:hook_safe() end
        function mod:get() return nil end
        function mod:warning() end

        local env = setmetatable({
            get_mod = function() return mod end,
            printf = function() end,
        }, { __index = _G })

        local prior_cd = rawget(_G, "ConflictDirector")
        _G.ConflictDirector = {} -- boot-global stand-in; gates hook registration
        local ok, err = pcall(function()
            for _, name in ipairs({ "_et_protect.lua", "_et_pacing.lua" }) do
                local chunk = assert(loadfile(root .. name))
                setfenv(chunk, env)
                chunk()
            end
            -- Execute the three shipped #479 regression bodies offline while the
            -- fake boot global is still planted (the wiring half of the first
            -- check reads rawget(_G, "ConflictDirector") at run time). Each body
            -- returns nil on pass, a failure string otherwise.
            for _, name in ipairs({
                "issue479_cd_tick_no_rerun_and_restore",
                "issue479_tick_fault_logging_bounded",
                "issue479_malformed_main_path_event_quarantined",
            }) do
                local body = checks[name]
                if type(body) ~= "function" then
                    error(name .. " was not registered by _et_pacing.lua")
                end
                local fail = body()
                if fail ~= nil then
                    error(name .. " FAILED: " .. tostring(fail))
                end
            end
        end)
        _G.ConflictDirector = prior_cd
        if not ok then load_err = err end
    end

    H.test("ET #479 modules load and the shipped regression bodies pass offline", function()
        H.equal(load_err, nil)
    end)

    H.test("ET #479 CD tick registers via the no-re-run guard; idempotent wraps stay plain", function()
        H.equal(load_err, nil)
        local reg = mod._et and mod._et.wrap_registry
        H.truthy(type(reg) == "table" and type(reg.tick) == "table" and type(reg.plain) == "table",
            "wrap_registry provenance missing")
        H.equal(reg.tick["ConflictDirector.update"], true,
            "ConflictDirector.update must register through _hook_wrap_tick (no vanilla re-run)")
        H.equal(reg.plain["ConflictDirector.update"], nil,
            "ConflictDirector.update must NOT also ride the re-running _hook_wrap")
        H.equal(reg.plain["ConflictDirector.update_horde_pacing"], true,
            "re-runnable pacing wraps keep the vanilla-fallback _hook_wrap")
    end)

    H.test("ET #479 quarantine ignores unknown errors without mutating state", function()
        H.equal(load_err, nil)
        local quarantine = mod._et479_quarantine_main_path_event
        H.equal(type(quarantine), "function", "quarantine helper missing")
        local recycler = {
            current_main_path_event_id = 4,
            current_main_path_event_activation_dist = 33,
            main_path_events = { [4] = { 33, false, "some_event" } },
        }
        local mixer = { active_events = { { name = "some_event", elements = {} } } }
        local prior = mod._et_pacing_quarantined
        local ok = quarantine({ enemy_recycler = recycler },
            "scripts/managers/conflict_director/terror_event_mixer.lua:1755: some other throw",
            mixer)
        H.equal(ok, false, "unknown errors must not be recognized")
        H.equal(mod._et_pacing_quarantined, prior, "unknown errors must not quarantine pacing")
        H.equal(recycler.current_main_path_event_id, 4, "recycler index must be untouched")
        H.equal(recycler.current_main_path_event_activation_dist, 33)
        H.equal(#mixer.active_events, 1, "active_events must be untouched on unknown errors")
        mod._et_pacing_quarantined = prior
    end)

    H.test("ET #479 line-1800 fault with unreadable recycler state fails closed", function()
        H.equal(load_err, nil)
        local quarantine = mod._et479_quarantine_main_path_event
        local prior = mod._et_pacing_quarantined
        mod._et_pacing_quarantined = nil
        -- Matching error but no enemy_recycler on the director: recovery must
        -- bail (false, no guessed mutation) while the session override
        -- quarantine still latches - deliberate fail-closed direction.
        local ok = quarantine({},
            "terror_event_mixer.lua:1800: attempt to index a nil value", nil)
        H.equal(ok, false, "unreadable recycler state must abort the recovery mutation")
        H.equal(mod._et_pacing_quarantined, true,
            "a line-1800 fault must still quarantine pacing overrides for the session")
        mod._et_pacing_quarantined = prior
    end)
end
