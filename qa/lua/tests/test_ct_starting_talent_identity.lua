return function(H, repo_root)
    local path = repo_root
        .. "/chaos_wastes_tweaker_dev/scripts/mods/chaos_wastes_tweaker_dev/chaos_wastes_tweaker_dev.lua"
    local file = assert(io.open(path, "rb"))
    local source = file:read("*a")
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
        H.truthy(source:find('function mod._ct_start_boon_identity(', 1, true))
        H.truthy(source:find('utils.get_power_up_name_text', 1, true))
        H.truthy(source:find('utils.get_power_up_icon', 1, true))
        H.truthy(source:find('player:profile_index(), player:career_index()', 1, true))
        H.truthy(source:find('issue556_starting_talent_identity', 1, true))
    end)
end
