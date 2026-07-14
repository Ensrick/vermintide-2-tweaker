return function(H, repo_root)
    local path = repo_root
        .. "/gui_tweaker_dev/scripts/mods/gui_tweaker_dev/_gut_native_loadout_policy.lua"
    local Policy = assert(loadfile(path))()

    H.test("native-loadout readonly preserves exact CWV instances", function()
        H.equal(Policy.readonly_action("slot_melee", "cwv_es_dual_axes_001"), "preserve")
        H.equal(Policy.readonly_action("slot_melee", "cwv_es_dual_maces_001"), "preserve")
        H.equal(Policy.readonly_action("slot_ranged", "cwv_es_crossbow_100"), "preserve")
        H.equal(Policy.is_cwv_backend_id("cwv_es_dual_axes"), false)
        H.equal(Policy.is_cwv_backend_id("D12DB867521442B3"), false)
    end)

    H.test("native-loadout readonly keeps official realm isolation policy", function()
        H.equal(Policy.mode(false, false), Policy.MODE_OFF)
        H.equal(Policy.mode(false, true), Policy.MODE_OFF)
        H.equal(Policy.mode(true, false), Policy.MODE_STORE)
        H.equal(Policy.mode(true, true), Policy.MODE_READONLY)
        H.equal(Policy.readonly_action("slot_hat", "mod_hat_instance"), "preserve")
        H.equal(Policy.readonly_action("slot_melee", "D12DB867521442B3"), "clear")
        H.equal(Policy.readonly_action("slot_necklace", "cwv_fake_001"), "block")
        H.equal(Policy.readonly_action("talents", "1,2,3,4,5,6"), "block")
    end)

    H.test("native-loadout LA outer capture canonicalizes cosmetic identity", function()
        local value, source = Policy.canonical_equip_value("slot_hat", "la_inventory_uuid", {
            ItemId = "la_hat_masterlist",
        })
        H.equal(value, "la_hat_masterlist")
        H.equal(source, "ItemId")

        value, source = Policy.canonical_equip_value("slot_skin", "la_skin_uuid", {
            override_id = "la_skin_override",
            ItemId = "la_skin_masterlist",
        })
        H.equal(value, "la_skin_override")
        H.equal(source, "override_id")

        value, source = Policy.canonical_equip_value("slot_pose", "la_pose_uuid", nil)
        H.equal(value, nil)
        H.equal(source, "unresolved_item")

        value, source = Policy.canonical_equip_value("slot_melee", "la_weapon_uuid", nil)
        H.equal(value, "la_weapon_uuid")
        H.equal(source, "backend_id")
    end)

    H.test("native-loadout LA outer hook wires canonical cosmetics into owned storage", function()
        local runtime_path = repo_root
            .. "/gui_tweaker_dev/scripts/mods/gui_tweaker_dev/_gut_native_loadouts.lua"
        local file = assert(io.open(runtime_path, "rb"))
        local source = file:read("*a")
        file:close()
        H.truthy(source:find("local value, source = _bu_canonical_value(backend_id, slot_name)", 1, true),
            "BackendUtils hook does not invoke canonical resolver")
        H.truthy(source:find("_capture_bu_equip(mode, mirror, career_name, slot_name, value, source)", 1, true),
            "resolved equip does not enter store/overlay capture")
        H.truthy(source:find("local is_loadout_slot = GEAR_SLOT_SET[slot_name] or COSMETIC_SLOT_SET[slot_name]", 1, true),
            "outer hook is not gated to the complete loadout-slot partition")
    end)
end
