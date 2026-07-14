return function(H, repo_root)
    local path = repo_root .. "/modded_progression/scripts/mods/modded_progression/_mp_shilling_ui_policy.lua"
    local Policy = assert(loadfile(path))()

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
end
