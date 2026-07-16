return function(H, repo_root)
    local path = repo_root
        .. "/gui_tweaker_dev/scripts/mods/gui_tweaker_dev/_mod_tweaker_disabled_sections.lua"
    local Policy = assert(loadfile(path))()

    H.test("Mod Tweaker recognizes both Tweaker Weapons streams", function()
        H.equal(true, Policy.is_author_mod("wt"))
        H.equal(true, Policy.is_author_mod("wt_dev"))
        H.equal(false, Policy.is_author_mod("HideBuffs"))
        H.equal(false, Policy.is_author_mod("Crosshair Kill Confirmation"))
    end)

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

    H.test("Mod Tweaker Weapons collapsible selects wt_dev and preserves its rows", function()
        local dev_widgets = {
            { mod_name = "wt_dev", readable_mod_name = "Tweaker: Weapons Dev" },
            { setting_id = "weapon_availability", type = "group", depth = 1 },
            { setting_id = "enable_dev_anim_picker", type = "checkbox", depth = 1 },
            { setting_id = "wt_dev_hold_pose", type = "group", depth = 1 },
        }
        local members, count = Policy.select_equipment_members({
            { mod_id = "wt", enabled = false, widgets = {
                { mod_name = "wt" }, { setting_id = "weapon_availability" },
            } },
            { mod_id = "wt_dev", enabled = true, widgets = dev_widgets },
            { mod_id = "character_weapon_variants", enabled = true, widgets = {
                { mod_name = "character_weapon_variants" },
                { setting_id = "cwv_weapon_availability" },
            } },
        })

        H.equal(2, count)
        H.equal("wt_dev", members.weapons.mod_id)
        H.equal(dev_widgets, members.weapons.widgets,
            "policy must preserve the selected VMF widget list")
        H.equal("weapon_availability", members.weapons.widgets[2].setting_id)
        H.equal("enable_dev_anim_picker", members.weapons.widgets[3].setting_id)
        H.equal("wt_dev_hold_pose", members.weapons.widgets[4].setting_id)
    end)

    H.test("both Mod Tweaker presentation paths synthesize the Weapons collapsible", function()
        local root = repo_root .. "/gui_tweaker_dev/scripts/mods/gui_tweaker_dev/"
        for _, filename in ipairs({ "_mod_tweaker_state.lua", "_mod_tweaker_view.lua" }) do
            local file = assert(io.open(root .. filename, "rb"))
            local source = file:read("*a")
            file:close()

            H.truthy(source:find("disabled_sections.is_author_mod(mod_name)", 1, true),
                filename .. " must use shared authored-mod discovery")
            H.truthy(source:find("disabled_sections.select_equipment_members(cats)", 1, true),
                filename .. " must use shared Equipment aliases")
            H.truthy(source:find('"__equip_weapons"', 1, true),
                filename .. " must create the Weapons collapsible")
            H.truthy(source:find("_add_member(members.weapons, 1)", 1, true),
                filename .. " must copy Tweaker: Weapons rows beneath the collapsible")
            H.equal(nil, source:find("local _MY_MODS", 1, true),
                filename .. " must not duplicate authored-mod aliases")
            H.equal(nil, source:find("local _EQUIP_ROLE", 1, true),
                filename .. " must not duplicate Equipment aliases")
        end
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
