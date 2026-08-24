return function(H, repo_root)
    local policy = dofile(repo_root
        .. "/cosmetics_tweaker/scripts/mods/cosmetics_tweaker/_cos_la_instance_policy.lua")
    local icon_provider = dofile(repo_root
        .. "/cosmetics_tweaker/scripts/mods/cosmetics_tweaker/_cos_la_inventory_icon.lua")

    local bridge_to_armoury = { clone_a = "la_red", clone_b = "la_blue" }
    local bridge_to_vanilla = { clone_a = "skin_a", clone_b = "skin_b" }
    local skin_list = {
        la_red = { icons = { skin_a = "icon_red", skin_runed = "icon_red_glow" } },
        la_blue = { icons = { skin_b = "icon_blue" } },
    }

    H.test("Athanor preview fallback requires exact normalized weapon family", function()
        H.equal(policy.resolve_preview_backend_id("la_item", "es_sword_shield",
            "purpure_item", "es_sword_shield_breton"), "la_item")
        H.equal(policy.resolve_preview_backend_id(nil, "es_sword_shield",
            "la_item", "es_sword_shield"), "la_item")
        H.equal(policy.resolve_preview_backend_id(nil, "es_sword_shield_breton",
            "la_item", "es_sword_shield"), nil)
        H.equal(policy.resolve_preview_backend_id(nil, nil,
            "la_item", "es_sword_shield"), nil)
    end)

    H.test("LA and Purpure offhands remain owned by their exact item and pool", function()
        local la = { la_armoury_key = "Kruber_empire_shield_basic1" }
        local purpure = { la_armoury_key = "cos_gk_purpure_azure_shield_variant" }
        local selections = {
            la_item = { left_hand_unit = la },
            purpure_item = { left_hand_unit = purpure },
        }
        local la_pool = { { la_armoury_key = "Kruber_empire_shield_basic1" } }
        local purpure_pool = {
            { la_armoury_key = "cos_gk_purpure_azure_shield_variant" },
        }
        H.equal(policy.resolve_preview_selection(selections, "la_item",
            "left_hand_unit", la_pool), la)
        H.equal(policy.resolve_preview_selection(selections, "purpure_item",
            "left_hand_unit", purpure_pool), purpure)
        H.equal(policy.resolve_preview_selection(selections, "la_item",
            "left_hand_unit", purpure_pool), nil)
        H.equal(policy.resolve_preview_selection(selections, "purpure_item",
            "left_hand_unit", la_pool), nil)
        H.equal(policy.resolve_preview_selection(selections, "missing_item",
            "left_hand_unit", la_pool), nil)
    end)

    H.test("Athanor authored paint requires exact spawn-data target", function()
        local la = { new_units = { "units/la_shield", "units/la_shield_3p" } }
        local purpure = {
            new_units = { "units/purpure_shield", "units/purpure_shield_3p" },
        }
        H.truthy(policy.preview_target_matches("units/la_shield_3p", la))
        H.truthy(policy.preview_target_matches("units/purpure_shield_3p", purpure))
        H.equal(policy.preview_target_matches("units/purpure_shield_3p", la), false)
        H.equal(policy.preview_target_matches("units/la_shield_3p", purpure), false)
        H.equal(policy.preview_target_matches(nil, la), false)
        H.equal(policy.preview_target_matches("<no-unit_name>", la), false)
        H.equal(policy.preview_target_matches("units/la_shield", {}), false)
    end)

    H.test("persisted row-one LA icon is exact-backend-instance only", function()
        local item = { backend_id = "item_one", skin = "skin_a" }
        H.equal(policy.resolve_inventory_icon(item, "clone_a", nil,
            bridge_to_armoury, bridge_to_vanilla, skin_list), "icon_red")
        H.equal(policy.resolve_inventory_icon({ skin = "skin_a" }, "clone_a", nil,
            bridge_to_armoury, bridge_to_vanilla, skin_list), nil)
        H.equal(policy.resolve_inventory_icon({ backend_id = "item_two", skin = "skin_a" },
            nil, nil, bridge_to_armoury, bridge_to_vanilla, skin_list), nil)
    end)

    H.test("direct LA Armoury identities resolve without hat-outfit clone maps (#883)", function()
        local direct_key = "Kruber_KOTBS_empire_sword_01"
        local realistic = {
            [direct_key] = {
                swap_hand = "right_hand_unit",
                icons = {
                    es_1h_sword_skin_02 = "la_kruber_kotbs_shortsword_icon",
                },
            },
        }
        local icon, reason, armoury_key, skin = policy.resolve_inventory_icon_detailed(
            { backend_id = "exact_sword", skin = "es_1h_sword_skin_02" },
            direct_key, nil, {}, {}, realistic)
        H.equal(icon, "la_kruber_kotbs_shortsword_icon")
        H.equal(reason, "exact-skin")
        H.equal(armoury_key, direct_key)
        H.equal(skin, "es_1h_sword_skin_02")
        H.equal(policy.resolve_inventory_icon(
            { backend_id = "other_sword", skin = "es_1h_sword_skin_02" },
            "not_an_la_key", nil, {}, {}, realistic), nil)
    end)

    H.test("inventory icon provider bounds and deduplicates automatic diagnostics (#883)", function()
        local lines = {}
        local provider = icon_provider.new(policy, function(fmt, ...)
            lines[#lines + 1] = string.format(fmt, ...)
        end, 2)
        local direct = { icons = { skin_a = "icon_a" } }
        local list = { la_direct = direct }
        local function resolve(backend_id)
            return provider.resolve({ backend_id = backend_id, skin = "skin_a" },
                "la_direct", nil, {}, {}, list, "dual")
        end
        H.equal(resolve("one"), "icon_a")
        H.equal(resolve("one"), "icon_a")
        H.equal(resolve("two"), "icon_a")
        H.equal(resolve("three"), "icon_a")
        H.equal(#lines, 2)
        H.truthy(string.find(lines[1], "[cos:883] inventory-icon", 1, true) ~= nil)
        H.truthy(string.find(lines[1], "bid=one", 1, true) ~= nil)
    end)

    H.test("offhand icon uses LA authored variant and base-skin pair", function()
        local hands = {
            left_hand_unit = { armoury_key = "la_red", vanilla_key = "skin_runed" },
        }
        H.equal(policy.resolve_inventory_icon({ backend_id = "shield", skin = "skin_a" },
            nil, hands, bridge_to_armoury, bridge_to_vanilla, skin_list), "icon_red")
    end)

    H.test("offhand icon prefers exact item skin before bridge paint fallback (#883)", function()
        local hands = {
            left_hand_unit = {
                armoury_key = "la_red",
                -- This is a representative paint key, not exact item state.
                vanilla_key = "skin_a",
            },
        }
        local icon, reason, _, skin = policy.resolve_inventory_icon_detailed(
            { backend_id = "shield_runed", skin = "skin_runed" },
            nil, hands, bridge_to_armoury, bridge_to_vanilla, skin_list, "shield")
        H.equal(icon, "icon_red_glow")
        H.equal(reason, "exact-skin")
        H.equal(skin, "skin_runed")

        -- Cross-family options may have no exact authored row; retain the
        -- representative key as a deliberate fallback instead of going blank.
        icon, reason, _, skin = policy.resolve_inventory_icon_detailed(
            { backend_id = "cross_family", skin = "foreign_skin" },
            nil, hands, bridge_to_armoury, bridge_to_vanilla, skin_list, "shield")
        H.equal(icon, "icon_red")
        H.equal(reason, "fallback-skin")
        H.equal(skin, "skin_a")
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
            "shield"), "icon_red")

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

    H.test("Apply commits dual components without a live render owner", function()
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

        local ok_a, action_a = persist.commit_offhand_entry({
            backend_id = "dual_instance_a",
            hand_field = "left_hand_unit",
            offhand_unit = "units/axe_blue",
            skin_key = "axe_blue_skin",
            player_unit = nil,
        })
        local ok_b = persist.commit_offhand_entry({
            backend_id = "dual_instance_b",
            hand_field = "left_hand_unit",
            offhand_unit = "units/axe_red",
            skin_key = "axe_red_skin",
            player_unit = false,
        })
        H.equal(ok_a, true)
        H.equal(action_a, "save-mesh")
        H.equal(ok_b, true)
        H.equal(persist.get_saved_offhands_for("dual_instance_a").left_hand_unit.unit_path,
            "units/axe_blue")
        H.equal(persist.get_saved_offhands_for("dual_instance_a").left_hand_unit.vanilla_key,
            "axe_blue_skin")
        H.equal(persist.get_saved_offhands_for("dual_instance_b").left_hand_unit.unit_path,
            "units/axe_red")

        -- Simulate a full process restart by loading a fresh module instance
        -- from the serialized setting captured by mod:set. The exact item
        -- identities and component skin keys must remain distinct.
        local reloaded = dofile(repo_root
            .. "/cosmetics_tweaker/scripts/mods/cosmetics_tweaker/_la_persistence.lua")
        H.equal(reloaded.get_saved_offhands_for("dual_instance_a").left_hand_unit.unit_path,
            "units/axe_blue")
        H.equal(reloaded.get_saved_offhands_for("dual_instance_a").left_hand_unit.vanilla_key,
            "axe_blue_skin")
        H.equal(reloaded.get_saved_offhands_for("dual_instance_b").left_hand_unit.unit_path,
            "units/axe_red")
        H.equal(reloaded.get_saved_offhands_for("dual_instance_b").left_hand_unit.vanilla_key,
            "axe_red_skin")

        H.equal(persist.commit_offhand_entry({
            hand_field = "left_hand_unit", offhand_unit = "units/wrong",
        }), false)
        H.equal(persist.commit_offhand_entry({
            backend_id = "dual_instance_a", hand_field = "body", offhand_unit = "units/wrong",
        }), false)

        local cleared, clear_action = persist.commit_offhand_entry({
            backend_id = "dual_instance_a",
            hand_field = "left_hand_unit",
            offhand_unit = "",
        })
        H.equal(cleared, true)
        H.equal(clear_action, "clear-follow-main")
        H.equal(persist.get_saved_offhands_for("dual_instance_a"), nil)
        H.equal(persist.get_saved_offhands_for("dual_instance_b").left_hand_unit.unit_path,
            "units/axe_red")
        _G.get_mod = old_get_mod
    end)

    H.test("source keeps icon override local and prunes missing item records", function()
        local main_path = repo_root
            .. "/cosmetics_tweaker/scripts/mods/cosmetics_tweaker/cosmetics_tweaker.lua"
        local persist_path = repo_root
            .. "/cosmetics_tweaker/scripts/mods/cosmetics_tweaker/_la_persistence.lua"
        local commit_path = repo_root
            .. "/cosmetics_tweaker/scripts/mods/cosmetics_tweaker/_cos_offhand_commit_policy.lua"
        local f = assert(io.open(main_path, "rb")); local main = f:read("*a"); f:close()
        local entry_only = main
        f = assert(io.open(repo_root
            .. "/cosmetics_tweaker/scripts/mods/cosmetics_tweaker/_cos_offhand_picker.lua", "rb"))
        main = main .. f:read("*a"); f:close()
        -- #1159: the exit-time OFFHAND_COMMIT.drain moved out of the entry into
        -- the HeroWindowItemCustomization view lifecycle owner.
        f = assert(io.open(repo_root
            .. "/cosmetics_tweaker/scripts/mods/cosmetics_tweaker/_cos_customization_view_lifecycle.lua", "rb"))
        local view_lifecycle = f:read("*a"); f:close()
        main = main .. view_lifecycle
        f = assert(io.open(repo_root
            .. "/cosmetics_tweaker/scripts/mods/cosmetics_tweaker/_cos_update_scheduler.lua", "rb"))
        main = main .. f:read("*a"); f:close()
        f = assert(io.open(repo_root
            .. "/cosmetics_tweaker/scripts/mods/cosmetics_tweaker/_cos_item_presentation_runtime.lua", "rb"))
        main = main .. f:read("*a"); f:close()
        f = assert(io.open(repo_root
            .. "/cosmetics_tweaker/scripts/mods/cosmetics_tweaker/_cos_offhand_state_runtime.lua", "rb"))
        main = main .. f:read("*a"); f:close()
        f = assert(io.open(persist_path, "rb")); local persist = f:read("*a"); f:close()
        f = assert(io.open(commit_path, "rb")); local commit = f:read("*a"); f:close()
        f = assert(io.open(repo_root
            .. "/cosmetics_tweaker/scripts/mods/cosmetics_tweaker/_cos_modded_illusion_swap.lua", "rb"))
        local illusion_swap = f:read("*a"); f:close()
        H.truthy(main:find('mod:hook(UIUtils, "get_ui_information_from_item"', 1, true))
        H.truthy(main:find('shield_icon_owner_item_types[item_type]', 1, true))
        H.truthy(main:find('inventory_icon = selected_inventory_icon', 1, true))
        H.truthy(main:find("return inventory_icon, display_name, description, store_icon", 1, true))
        H.equal(main:find("WeaponSkins.skins[skin]['inventory_icon'] =", 1, true), nil)
        H.truthy(persist:find("M.prune_missing_items", 1, true))
        H.truthy(main:find("INSTANCE-PRUNE", 1, true))
        H.truthy(persist:find("M.commit_offhand_entry = function(entry)", 1, true))
        H.truthy(commit:find("persistence.commit_offhand_entry(entry)", 1, true))
        H.truthy(commit:find("function M.commit_for_backend", 1, true))
        H.truthy(illusion_swap:find("OFFHAND_COMMIT.commit_for_backend", 1, true))
        H.truthy(view_lifecycle:find("OFFHAND_COMMIT.drain", 1, true))
        H.equal(entry_only:find("OFFHAND_COMMIT.drain", 1, true), nil)
        H.equal(main:find("if entry and entry.player_unit and Unit.alive(entry.player_unit) then", 1, true), nil)
        H.truthy(commit:find("mod._la_self_rebroadcast_pending = true", 1, true))
        H.truthy(main:find('local cim = get_mod("cim_dev") or get_mod("cim")', 1, true))
        H.truthy(main:find("mod._la_offhand_restore_done = deferred == 0", 1, true))
    end)
end
