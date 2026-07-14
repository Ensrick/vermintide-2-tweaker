return function(H, repo_root)
    local path = repo_root .. "/modded_progression/scripts/mods/modded_progression/_mp_shilling_ui_policy.lua"
    local Policy = assert(loadfile(path))()
    local main_file = assert(io.open(repo_root .. "/modded_progression/scripts/mods/modded_progression/modded_progression.lua", "rb"))
    local main_source = main_file:read("*a")
    main_file:close()

    H.test("MP shilling UI invalidates on transaction and realm edges", function()
        local refresh, visible = Policy.needs_refresh(nil, nil, true, 4)
        H.truthy(refresh)
        H.equal(4, visible)

        refresh = Policy.needs_refresh(true, visible, true, 4)
        H.equal(false, refresh)

        refresh, visible = Policy.needs_refresh(true, visible, true, 5)
        H.truthy(refresh)
        H.equal(5, visible)

        refresh, visible = Policy.needs_refresh(true, visible, false, 5)
        H.truthy(refresh)
        H.equal(Policy.OFFICIAL_REVISION, visible)
    end)

    H.test("MP shilling labels are scoped and idempotent", function()
        H.equal("[Local] 15", Policy.wallet_text("15", "[Local]"))
        H.equal("[Local] 15", Policy.wallet_text("[Local] 15", "[Local]"))
        H.truthy(Policy.is_local_shilling(true, "SM"))
        H.equal(false, Policy.is_local_shilling(false, "SM"))
        H.equal(false, Policy.is_local_shilling(true, "VS"))
    end)

    H.test("MP shilling verification evidence is revision-bounded", function()
        H.truthy(main_source:find('if refresh then\n        mod:info("[mp:578] wallet_refresh', 1, true))
        H.truthy(main_source:find('if refresh then\n        mod:info("[mp:578] affordability_refresh', 1, true))
        local _, wallet_count = main_source:gsub("%[mp:578%] wallet_refresh", "")
        local _, preview_count = main_source:gsub("%[mp:578%] affordability_refresh", "")
        H.equal(wallet_count, 1)
        H.equal(preview_count, 1)
    end)
end
