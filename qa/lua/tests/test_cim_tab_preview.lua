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
        H.equal(core.resolve_rarity("modded", true, false), "unique")
        H.equal(core.resolve_rarity("modded", false, false), "modded")

        local ok, skin, icon, reason = core.resolve({},
            { slots = { slot_melee = { skin = "custom_skin" } } }, "slot_melee",
            { custom_skin = { inventory_icon = "package_local_icon" } },
            function() return false end)
        H.equal(ok, false)
        H.equal(skin, "custom_skin")
        H.equal(icon, nil)
        H.equal(reason, "skin_icon_resource_unavailable")
    end)

    H.test("CIM #598 mirrors owner state and repairs the rendered rarity frame", function()
        local main_path = repo_root
            .. "/crafting_in_modded_dev/scripts/mods/crafting_in_modded_dev/crafting_in_modded_dev.lua"
        local main_file = assert(io.open(main_path, "rb"))
        local main_source = main_file:read("*a")
        main_file:close()
        H.truthy(main_source:find("_cim_record_modded_slot(peer_id, local_player_id, slot_name, is_modded)",
            1, true) ~= nil)
        H.truthy(main_source:find("slots[slot_name] = is_modded", 1, true) ~= nil)

        local preview_path = repo_root
            .. "/crafting_in_modded_dev/scripts/mods/crafting_in_modded_dev/_cim_tab_preview.lua"
        local preview_file = assert(io.open(preview_path, "rb"))
        local preview_source = preview_file:read("*a")
        preview_file:close()
        H.truthy(preview_source:find('content[slot_name .. "_rarity_texture"]',
            1, true) ~= nil)
        H.truthy(preview_source:find("Core.resolve_rarity(item.rarity, true, is_modded)",
            1, true) ~= nil)
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
