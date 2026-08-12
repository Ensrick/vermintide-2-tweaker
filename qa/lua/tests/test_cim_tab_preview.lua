return function(H, repo_root)
    local core = dofile(repo_root
        .. "/crafting_in_modded_dev/scripts/mods/crafting_in_modded_dev/_cim_tab_preview_core.lua")

    local function read_all(path)
        local file = assert(io.open(path, "rb"))
        local source = file:read("*a")
        file:close()
        return source
    end

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
        H.equal(core.resolve_rarity("modded", true, nil), "modded")

        local ok, skin, icon, reason = core.resolve({},
            { slots = { slot_melee = { skin = "custom_skin" } } }, "slot_melee",
            { custom_skin = { inventory_icon = "package_local_icon" } },
            function() return false end)
        H.equal(ok, false)
        H.equal(skin, "custom_skin")
        H.equal(icon, nil)
        H.equal(reason, "skin_icon_resource_unavailable")
    end)

    H.test("CIM #598/#921 converges owner and peer rarity state", function()
        local source = read_all(repo_root
            .. "/crafting_in_modded_dev/scripts/mods/crafting_in_modded_dev/_cim_loadout_wire_owner.lua")
        H.truthy(source:find("slot_state[slot_name] = is_modded", 1, true),
            "slot state no longer retains explicit false")
        H.truthy(source:find("slot_state[slot_name] == nil", 1, true),
            "loadout consumer no longer distinguishes false from absence")
        H.truthy(source:find('is_modded, "sender")', 1, true),
            "sender-local rarity metadata priming is missing")
        H.equal(source:find('network_send, mod, "cim_modded_slot",\n                "everyone"', 1, true), nil,
            "custom side-channel must not be broadened to an unsupported recipient")

        local preview_source = read_all(repo_root
            .. "/crafting_in_modded_dev/scripts/mods/crafting_in_modded_dev/_cim_tab_preview.lua")
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
