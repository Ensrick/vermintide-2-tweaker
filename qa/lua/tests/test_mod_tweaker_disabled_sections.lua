return function(H, repo_root)
    local path = repo_root
        .. "/gui_tweaker_dev/scripts/mods/gui_tweaker_dev/_mod_tweaker_disabled_sections.lua"
    local Policy = assert(loadfile(path))()

    H.test("Mod Tweaker equipment layout counts disabled installed members", function()
        local roles = { wt = "weapons", character_weapon_variants = "cwv" }
        local members, count = Policy.select_members({
            { mod_id = "wt", enabled = true },
            { mod_id = "character_weapon_variants", enabled = false },
        }, roles)
        H.equal(2, count)
        H.equal(false, members.cwv.enabled)
    end)

    H.test("Mod Tweaker alias selection prefers the enabled crafting stream", function()
        local roles = { cim = "crafting", cim_dev = "crafting" }
        local members, count = Policy.select_members({
            { mod_id = "cim", enabled = false },
            { mod_id = "cim_dev", enabled = true },
        }, roles)
        H.equal(1, count)
        H.equal("cim_dev", members.crafting.mod_id)
    end)

    H.test("Mod Tweaker disabled integration keeps only its explained header", function()
        local widgets = {
            { setting_id = "before", depth = 0 },
            { setting_id = "ui_tweaks", type = "group", depth = 1 },
            { setting_id = "child_a", depth = 2 },
            { setting_id = "child_group", type = "group", depth = 2 },
            { setting_id = "grandchild", depth = 3 },
            { setting_id = "after", depth = 1 },
        }
        local filtered, found = Policy.disable_group_subtree(widgets, "ui_tweaks")
        H.truthy(found)
        H.equal(3, #filtered)
        H.equal("ui_tweaks", filtered[2].setting_id)
        H.equal(true, filtered[2].disabled)
        H.equal("Disabled in VMF", filtered[2].tooltip)
        H.equal("after", filtered[3].setting_id)
        H.equal(nil, widgets[2].disabled, "VMF source widgets must not be mutated")
    end)
end
