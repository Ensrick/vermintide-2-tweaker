return function(H, repo_root)
    local authority = assert(loadfile(
        repo_root .. "/tools/shared_lib/_lib_modded_realm_authority.lua"))()
    local guard = assert(loadfile(
        repo_root .. "/general_tweaker_dev/scripts/mods/general_tweaker_dev/" ..
        "_gt_level_control_backend_guard.lua"))()

    H.test("GT #1509 restores cached modded state from immutable launch authority", function()
        local state = { _booted_eac_untrusted = false }
        local skip, corrected = guard.reconcile(
            authority, state, { ["eac-untrusted"] = false },
            { application_parameter = { ["eac-untrusted"] = true } })
        H.equal(skip, true)
        H.equal(corrected, true)
        H.equal(state._booted_eac_untrusted, true)
    end)

    H.test("GT #1509 accepts the exact raw modded flag", function()
        local state = {}
        local skip, corrected = guard.reconcile(
            authority, state, { ["eac-untrusted"] = true }, nil)
        H.equal(skip, true)
        H.equal(corrected, true)
        H.equal(state._booted_eac_untrusted, true)
    end)

    H.test("GT #1509 preserves official reward generation", function()
        local state = { _booted_eac_untrusted = false }
        local skip, corrected = guard.reconcile(
            authority, state, { ["eac-untrusted"] = false },
            { application_parameter = {} })
        H.equal(skip, false)
        H.equal(corrected, false)
        H.equal(state._booted_eac_untrusted, false)
    end)

    H.test("GT #1509 fails closed on malformed or throwing authority", function()
        local state = { _booted_eac_untrusted = false }
        H.equal(guard.reconcile(nil, state, {}, {}), false)
        H.equal(guard.reconcile({ is_modded = function() error("boom") end },
            state, {}, {}), false)
        H.equal(state._booted_eac_untrusted, false)
    end)

    H.test("GT #1509 runtime hook reconciles before delegating", function()
        local file = assert(io.open(repo_root ..
            "/general_tweaker_dev/scripts/mods/general_tweaker_dev/_gt_level_control.lua", "rb"))
        local source = file:read("*a")
        file:close()
        local reconcile = assert(source:find("BackendGuard.reconcile", 1, true))
        local delegate = assert(source:find("local ok, err = pcall(func, self", 1, true))
        H.truthy(reconcile < delegate)
        H.truthy(source:find("[gt:1509] corrected stale modded-realm reward state", 1, true) ~= nil)
    end)
end
