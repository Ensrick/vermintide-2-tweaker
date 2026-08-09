return function(H, repo_root)
    local path = repo_root .. "/chaos_wastes_tweaker_dev/scripts/mods/chaos_wastes_tweaker_dev/"
    local Policy = assert(loadfile(path .. "_ct_collectible_policy.lua"))()

    H.test("CT converts every dead Adventure collectible on host", function()
        for _, name in ipairs({ "loot_die", "lorebook_page", "painting_scrap" }) do
            local final, converted = Policy.route_name(name, true, true)
            H.equal(final, "deus_soft_currency", name)
            H.equal(converted, true, name)
        end
    end)

    H.test("CT collectible policy leaves clients and stock Adventure unchanged", function()
        local final, converted = Policy.route_name("painting_scrap", false, true)
        H.equal(final, "painting_scrap")
        H.equal(converted, false)
        final, converted = Policy.route_name("loot_die", true, false)
        H.equal(final, "loot_die")
        H.equal(converted, false)
        final, converted = Policy.route_name("frag_grenade_t1", true, true)
        H.equal(final, "frag_grenade_t1")
        H.equal(converted, false)
    end)

    H.test("CT direct network rewrite is exact immutable and coin-shaped", function()
        local original_pickup = { pickup_name = "loot_die", spawn_type = "rare" }
        local original_init = { pickup_system = original_pickup, other = { keep = true } }
        local coin = { unit_name = "coin_unit", unit_template_name = "coin_template" }
        local unit, template, init, converted, original = Policy.rewrite_network_spawn(
            "die_unit", "pickup_unit", original_init, coin, true, true)
        H.equal(converted, true)
        H.equal(original, "loot_die")
        H.equal(unit, "coin_unit")
        H.equal(template, "coin_template")
        H.equal(init.pickup_system.pickup_name, "deus_soft_currency")
        H.equal(init.pickup_system.spawn_type, "rare")
        H.equal(init.other, original_init.other)
        H.equal(original_init.pickup_system, original_pickup)
        H.equal(original_pickup.pickup_name, "loot_die")
    end)

    H.test("CT direct network rewrite fails closed without coin settings", function()
        local init = { pickup_system = { pickup_name = "loot_die" } }
        local unit, template, unchanged, converted, _, reason = Policy.rewrite_network_spawn(
            "die_unit", "pickup_unit", init, nil, true, true)
        H.equal(unit, "die_unit")
        H.equal(template, "pickup_unit")
        H.equal(unchanged, init)
        H.equal(converted, false)
        H.equal(reason, "coin_settings_missing")
    end)

    H.test("CT production wires host spawn and PickupSystem conversion boundaries", function()
        -- #1159: both conversion seams moved out of the entry into the
        -- pickup-spawn owner. The wiring contract is unchanged; only the file
        -- that carries it moved, so assert against the owner and confirm the
        -- entry no longer holds a second (shadowing) copy.
        local file = assert(io.open(path .. "_ct_pickup_spawn_owner.lua", "rb"))
        local source = file:read("*a"); file:close()
        H.truthy(source:find('mod:hook("UnitSpawner", "spawn_network_unit"', 1, true))
        H.truthy(source:find("_ct_collectible_policy.route_name", 1, true))
        H.truthy(source:find("self.is_server == true", 1, true))
        H.truthy(source:find("mod._ct351_rewrite_network_spawn", 1, true))

        local entry_file = assert(io.open(path .. "chaos_wastes_tweaker_dev.lua", "rb"))
        local entry = entry_file:read("*a"); entry_file:close()
        H.equal(entry:find('mod:hook("UnitSpawner", "spawn_network_unit"', 1, true), nil,
            "a second spawn_network_unit hook would be silently dropped by VMF")
        H.equal(entry:find("mod._ct351_rewrite_network_spawn =", 1, true), nil,
            "the rewrite export must be published only by the owner")
    end)
end
