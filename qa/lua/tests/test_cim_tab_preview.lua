return function(H, repo_root)
    local core = dofile(repo_root
        .. "/crafting_in_modded_dev/scripts/mods/crafting_in_modded_dev/_cim_tab_preview_core.lua")

    H.test("CIM Tab preview prefers exact live equipment skin icon", function()
        local equipment = { slots = { slot_melee = { skin = "skin_gold" } } }
        local skins = { skin_gold = { inventory_icon = "gold_icon" } }
        local authoritative, skin, icon, reason = core.resolve(
            {}, equipment, "slot_melee", skins)
        H.truthy(authoritative)
        H.equal(skin, "skin_gold")
        H.equal(icon, "gold_icon")
        H.equal(reason, "exact_skin")
    end)

    H.test("CIM Tab preview recognizes authoritative default skin", function()
        local authoritative, skin, icon, reason = core.resolve(
            {}, { slots = { slot_ranged = { skin = "n/a" } } }, "slot_ranged", {})
        H.truthy(authoritative)
        H.equal(skin, nil)
        H.equal(icon, nil)
        H.equal(reason, "default_skin")
    end)

    H.test("CIM Tab preview fails closed without exact icon identity", function()
        local authoritative, skin, icon, reason = core.resolve(
            {}, { slots = { slot_melee = { skin = "missing_skin" } } }, "slot_melee", {})
        H.equal(authoritative, false)
        H.equal(skin, "missing_skin")
        H.equal(icon, nil)
        H.equal(reason, "skin_icon_unavailable")
    end)

    H.test("CIM #598 keeps safe rarity metadata separate from custom resources", function()
        H.equal(core.resolve_rarity("unique", false, true), "unique")
        H.equal(core.resolve_rarity("unique", true, true), "modded")
        H.equal(core.resolve_rarity("unique", true, false), "unique")

        local ok, skin, icon, reason = core.resolve({},
            { slots = { slot_melee = { skin = "custom_skin" } } }, "slot_melee",
            { custom_skin = { inventory_icon = "package_local_icon" } },
            function() return false end)
        H.equal(ok, false)
        H.equal(skin, "custom_skin")
        H.equal(icon, nil)
        H.equal(reason, "skin_icon_resource_unavailable")
    end)

    H.test("CIM Tab does not clobber Cosmetics component presentation", function()
        local icon, name, source = core.choose_presentation("primary_icon", {
            icon = "shield_icon",
            display_name = "combined_name_key",
        })
        H.equal(icon, "shield_icon")
        H.equal(name, "combined_name_key")
        H.equal(source, "cosmetics_components")

        icon, name, source = core.choose_presentation("primary_icon", nil)
        H.equal(icon, "primary_icon")
        H.equal(name, nil)
        H.equal(source, "primary_skin")
    end)
end
