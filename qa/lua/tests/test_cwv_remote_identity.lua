return function(H, repo_root)
    local path = repo_root
        .. "/character_weapon_variants/scripts/mods/character_weapon_variants/character_weapon_variants.lua"
    local file = assert(io.open(path, "rb"))
    local source = file:read("*a")
    file:close()

    H.test("CWV remote identity is carried on bounded lifecycle edges", function()
        H.truthy(source:find('mod:network_register("cwv_item_identity"', 1, true))
        H.truthy(source:find('_send_identity_slots(slots, "game_object_initialized", true)', 1, true))
        H.truthy(source:find('"spawn_resynced_loadout", false)', 1, true))
        H.truthy(source:find('_send_identity_slots(equipment and equipment.slots, "parity_replay", true)', 1, true))
        H.equal(source:find('_send_identity_slots(', source:find('mod.update = function', 1, true) or 1, true), nil)
    end)

    H.test("CWV remote identity remains base-bound and skin-authoritative", function()
        H.truthy(source:find("def.base_weapon ~= base_name", 1, true))
        H.truthy(source:find('(reason == "skin" or reason == "identity")', 1, true))
        H.truthy(source:find("local skin_unit = skin_tmpl and skin_tmpl[field]", 1, true))
        H.truthy(source:find('item_key = (def and not def.skin_only) and key or ""', 1, true))
    end)

    H.test("Imperial Longsword owner and Helmgart illusion names stay distinct", function()
        H.truthy(source:find('display_name    = "Imperial Longsword"', 1, true))
        H.truthy(source:find('display_name    = "Helmgart Watchsword"', 1, true))
        H.truthy(source:find('if _display_names[effective_item_type] == nil then', 1, true))
        H.truthy(source:find('issue396_imperial_longsword_identity_and_remote_husk', 1, true))
    end)
end
