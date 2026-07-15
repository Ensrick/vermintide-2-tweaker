return function(H, repo_root)
    local policy = dofile(repo_root
        .. "/cosmetics_tweaker/scripts/mods/cosmetics_tweaker/_cos_la_instance_policy.lua")

    local bridge_to_armoury = { clone_a = "la_red", clone_b = "la_blue" }
    local bridge_to_vanilla = { clone_a = "skin_a", clone_b = "skin_b" }
    local skin_list = {
        la_red = { icons = { skin_a = "icon_red", skin_runed = "icon_red_glow" } },
        la_blue = { icons = { skin_b = "icon_blue" } },
    }

    H.test("persisted row-one LA icon is exact-backend-instance only", function()
        local item = { backend_id = "item_one", skin = "skin_a" }
        H.equal(policy.resolve_inventory_icon(item, "clone_a", nil,
            bridge_to_armoury, bridge_to_vanilla, skin_list), "icon_red")
        H.equal(policy.resolve_inventory_icon({ skin = "skin_a" }, "clone_a", nil,
            bridge_to_armoury, bridge_to_vanilla, skin_list), nil)
        H.equal(policy.resolve_inventory_icon({ backend_id = "item_two", skin = "skin_a" },
            nil, nil, bridge_to_armoury, bridge_to_vanilla, skin_list), nil)
    end)

    H.test("offhand icon uses LA authored variant and base-skin pair", function()
        local hands = {
            left_hand_unit = { armoury_key = "la_red", vanilla_key = "skin_runed" },
        }
        H.equal(policy.resolve_inventory_icon({ backend_id = "shield", skin = "skin_a" },
            nil, hands, bridge_to_armoury, bridge_to_vanilla, skin_list), "icon_red_glow")
    end)

    H.test("dual icon remains owned by the main right-hand illusion", function()
        local hands = {
            left_hand_unit = {
                armoury_key = "la_red",
                vanilla_key = "skin_runed",
                inventory_icon = "wrong_cached_offhand_icon",
            },
        }
        H.equal(policy.resolve_inventory_icon({ backend_id = "dual", skin = "skin_a" },
            "clone_a", hands, bridge_to_armoury, bridge_to_vanilla, skin_list,
            "dual"), "icon_red")
        H.equal(policy.resolve_inventory_icon({ backend_id = "dual", skin = "skin_a" },
            nil, hands, bridge_to_armoury, bridge_to_vanilla, skin_list,
            "dual"), nil)
    end)

    H.test("shield icon follows its exact saved offhand", function()
        local vanilla = {
            left_hand_unit = { inventory_icon = "selected_shield_icon" },
        }
        H.equal(policy.resolve_inventory_icon({ backend_id = "shield", skin = "skin_a" },
            "clone_a", vanilla, bridge_to_armoury, bridge_to_vanilla, skin_list,
            "shield"), "selected_shield_icon")

        local la = {
            left_hand_unit = {
                armoury_key = "la_red",
                vanilla_key = "skin_runed",
                inventory_icon = "stale_vanilla_icon",
            },
        }
        H.equal(policy.resolve_inventory_icon({ backend_id = "shield", skin = "skin_a" },
            "clone_a", la, bridge_to_armoury, bridge_to_vanilla, skin_list,
            "shield"), "icon_red_glow")

        la.left_hand_unit.armoury_key = "missing_la_variant"
        H.equal(policy.resolve_inventory_icon({ backend_id = "shield", skin = "skin_a" },
            "clone_a", la, bridge_to_armoury, bridge_to_vanilla, skin_list,
            "shield"), "icon_red")
    end)

    H.test("Cosmetics-authored offhand keeps its custom icon without LA", function()
        local authored = {
            left_hand_unit = {
                armoury_key = "cos_gk_purpure_azure_shield_variant",
                vanilla_key = "es_sword_shield_breton_skin_03",
                inventory_icon = "icon_cos_gk_purpure_azure_shield",
                cos_authored = true,
            },
        }
        H.equal(policy.resolve_inventory_icon({ backend_id = "shield" },
            nil, authored, bridge_to_armoury, bridge_to_vanilla, skin_list,
            "shield"), "icon_cos_gk_purpure_azure_shield")
    end)

    H.test("unknown LA metadata fails closed to vanilla icon", function()
        H.equal(policy.resolve_inventory_icon({ backend_id = "item", skin = "skin_a" },
            "missing_clone", nil, bridge_to_armoury, bridge_to_vanilla, skin_list), nil)
        H.equal(policy.resolve_inventory_icon({ backend_id = "item", skin = "skin_x" },
            "clone_a", nil, bridge_to_armoury, bridge_to_vanilla, skin_list), nil)
    end)

    H.test("missing exact items prune illusion and offhand records together", function()
        local old_get_mod = _G.get_mod
        local setting = {
            schema = 1,
            careers = { es_knight = { slot_hat = "keep_hat" } },
            illusions = { live = "clone_a", gone = "clone_b" },
            offhands = {
                live = { left_hand_unit = { armoury_key = "la_red" } },
                gone = { left_hand_unit = { armoury_key = "la_blue" } },
            },
        }
        local fake_mod = {
            get = function(_, key) return key == "la_persisted_equips" and setting or nil end,
            set = function(_, key, value) if key == "la_persisted_equips" then setting = value end end,
            info = function() end,
            hook_safe = function() end,
        }
        _G.get_mod = function() return fake_mod end
        local persist = dofile(repo_root
            .. "/cosmetics_tweaker/scripts/mods/cosmetics_tweaker/_la_persistence.lua")
        H.equal(persist.prune_missing_items(function(id) return id == "live" end), 1)
        H.equal(persist.get_saved_illusion("gone"), nil)
        H.equal(persist.get_saved_offhands_for("gone"), nil)
        H.equal(persist.get_saved_illusion("live"), "clone_a")
        H.equal(persist.get_saved_cosmetic("es_knight", "slot_hat"), "keep_hat")
        _G.get_mod = old_get_mod
    end)

    H.test("vanilla shield icon metadata persists per exact hand", function()
        local old_get_mod = _G.get_mod
        local setting = { schema = 1, careers = {}, illusions = {}, offhands = {} }
        local fake_mod = {
            get = function(_, key) return key == "la_persisted_equips" and setting or nil end,
            set = function(_, key, value) if key == "la_persisted_equips" then setting = value end end,
            info = function() end,
            hook_safe = function() end,
        }
        _G.get_mod = function() return fake_mod end
        local persist = dofile(repo_root
            .. "/cosmetics_tweaker/scripts/mods/cosmetics_tweaker/_la_persistence.lua")
        persist.save_offhand("shield_item", "left_hand_unit", nil,
            "shield_skin", "units/shield", "selected_shield_icon")
        local record = persist.get_saved_offhands_for("shield_item").left_hand_unit
        H.equal(record.vanilla_key, "shield_skin")
        H.equal(record.unit_path, "units/shield")
        H.equal(record.inventory_icon, "selected_shield_icon")
        persist.save_offhand("authored_shield", "left_hand_unit", "gk_variant",
            "shield_skin", nil, "gk_icon", true)
        local authored = persist.get_saved_offhands_for("authored_shield").left_hand_unit
        H.equal(authored.inventory_icon, "gk_icon")
        H.equal(authored.cos_authored, true)
        _G.get_mod = old_get_mod
    end)

    H.test("source keeps icon override local and prunes missing item records", function()
        local main_path = repo_root
            .. "/cosmetics_tweaker/scripts/mods/cosmetics_tweaker/cosmetics_tweaker.lua"
        local persist_path = repo_root
            .. "/cosmetics_tweaker/scripts/mods/cosmetics_tweaker/_la_persistence.lua"
        local f = assert(io.open(main_path, "rb")); local main = f:read("*a"); f:close()
        f = assert(io.open(persist_path, "rb")); local persist = f:read("*a"); f:close()
        H.truthy(main:find('mod:hook(UIUtils, "get_ui_information_from_item"', 1, true))
        H.truthy(main:find('_SHIELD_ICON_OWNER_ITEM_TYPES[item_type]', 1, true))
        H.truthy(main:find('inventory_icon = selected_inventory_icon', 1, true))
        H.truthy(main:find("return inventory_icon, display_name, description, store_icon", 1, true))
        H.equal(main:find("WeaponSkins.skins[skin]['inventory_icon'] =", 1, true), nil)
        H.truthy(persist:find("M.prune_missing_items", 1, true))
        H.truthy(main:find("INSTANCE-PRUNE", 1, true))
    end)
end
