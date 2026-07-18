return function(H, repo_root)
    local source = require("cwv_source").combined(repo_root)

    H.test("CWV remote identity is carried on bounded lifecycle edges", function()
        H.truthy(source:find('mod:network_register("cwv_item_identity"', 1, true))
        H.truthy(source:find('_send_identity_slots(slots, "game_object_initialized", true)', 1, true))
        H.truthy(source:find('"spawn_resynced_loadout", false)', 1, true))
        -- #474 (2026-07-18): the parity replay forces identity only on the
        -- parity-enable edge; the bounded transition poll dedupes instead of
        -- force-resending every 0.5s.
        H.truthy(source:find('_send_identity_slots(equipment and equipment.slots, "parity_replay",', 1, true))
        H.truthy(source:find('identity_force == true)', 1, true))
        H.equal(source:find('_send_identity_slots(equipment and equipment.slots, "parity_replay", true)', 1, true), nil)
        H.equal(source:find('_send_identity_slots(', source:find('mod.update = function', 1, true) or 1, true), nil)
    end)

    H.test("CWV remote identity remains base-bound and skin-authoritative", function()
        H.truthy(source:find("def.base_weapon ~= payload.base_item_key", 1, true))
        H.truthy(source:find('if reason == "identity" and exact then', 1, true))
        H.truthy(source:find("local skin_unit = skin_tmpl and skin_tmpl[field]", 1, true))
        H.truthy(source:find('_om._cwv_resolve_world_descriptor(item_data, skin', 1, true))
        H.truthy(source:find('_send_identity_slots(slots, "hot_join_sync", true, peer_id)', 1, true))
    end)

    H.test("Imperial Longsword owner and Helmgart illusion names stay distinct", function()
        H.truthy(source:find('display_name    = "Imperial Longsword"', 1, true))
        H.truthy(source:find('display_name    = "Helmgart Watchsword"', 1, true))
        H.truthy(source:find('if _display_names[effective_item_type] == nil then', 1, true))
        H.truthy(source:find('issue396_imperial_longsword_identity_and_remote_husk', 1, true))
    end)

    H.test("CWV #482 preserves legacy UUID identity without recrafting", function()
        H.truthy(source:find("_registered_cwv_key(item_data.key)", 1, true))
        H.truthy(source:find("_registered_cwv_key(item.key)", 1, true))
        H.truthy(source:find("_cwv_identity_by_backend_id[backend_id] = key", 1, true))
        H.truthy(source:find("return _cwv_identity_by_backend_id[backend_id]", 1, true))
        H.truthy(source:find("legacy exact CWV key did not recover persisted Imperial Longsword identity", 1, true))
        H.truthy(source:find("proven UUID identity did not survive a backend-unavailable preview transition", 1, true))
        H.equal(source:find("_registered_cwv_key(item_data.name)", 1, true), nil,
            "inherited vanilla name must never infer a CWV variant")
    end)
end
