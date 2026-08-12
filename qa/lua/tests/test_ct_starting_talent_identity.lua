return function(H, repo_root)
    local CTSource = dofile(repo_root .. "/qa/lua/ct_source.lua")
    local source = CTSource.expanded(repo_root)
    local file
    local helper_path = repo_root
        .. "/chaos_wastes_tweaker_dev/scripts/mods/chaos_wastes_tweaker_dev/_ct_boon_preview_helpers.lua"
    file = assert(io.open(helper_path, "rb"))
    local helpers = file:read("*a")
    file:close()

    H.test("CT #556 excludes a selected talent from configured starting boons", function()
        H.truthy(source:find(
            'career_index, initial_talents_for_career)', 1, true),
            "hook must retain vanilla's fifth argument")
        H.truthy(source:find(
            'mod._ct_starting_talent_is_duplicate(template, name, existing_names)', 1, true))
        H.truthy(source:find(
            'template.talent == true and existing_names[name] == true', 1, true))
        H.truthy(source:find(
            '[ct:556] starting talents: skipped=', 1, true))
    end)

    H.test("CT #556 preview delegates talent identity to vanilla career helpers", function()
        H.truthy(helpers:find('function mod._ct_start_boon_identity(', 1, true))
        H.truthy(helpers:find('utils.get_power_up_name_text', 1, true))
        H.truthy(helpers:find('utils.get_power_up_icon', 1, true))
        H.truthy(helpers:find('player:profile_index(), player:career_index()', 1, true))
        -- #1159: the #556 check registers next to the preview it locks, which now
        -- lives in the tab-panel owner. Its duplicate-policy half still guards the
        -- entry's grant hook (asserted above) -- the check just moved file, and
        -- must exist in exactly one of them.
        local panel_path = repo_root
            .. "/chaos_wastes_tweaker_dev/scripts/mods/chaos_wastes_tweaker_dev/_ct_tab_panel_owner.lua"
        local pf = assert(io.open(panel_path, "rb"))
        local panel = pf:read("*a"); pf:close()
        H.truthy(panel:find('issue556_starting_talent_identity', 1, true))
        H.equal(source:find('issue556_starting_talent_identity', 1, true), nil,
            "the #556 check must not be registered twice")
        -- The duplicate policy it calls stays published by the entry, ahead of the
        -- owner's dofile, so the check resolves it through `mod` at run time.
        local policy_at = assert(source:find(
            "function mod._ct_starting_talent_is_duplicate", 1, true))
        local owner_at = assert(source:find(
            'mod:dofile("scripts/mods/chaos_wastes_tweaker_dev/_ct_tab_panel_owner")', 1, true))
        H.truthy(policy_at < owner_at,
            "the duplicate policy must be published before the tab-panel owner loads")
    end)
end
