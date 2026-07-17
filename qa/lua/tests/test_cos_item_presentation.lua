return function(H, repo_root)
    local policy = dofile(repo_root
        .. "/cosmetics_tweaker/scripts/mods/cosmetics_tweaker/_cos_item_presentation.lua")

    H.test("shield owns locally resident icon and independent text", function()
        local result = policy.resolve({
            base_icon = "sword_icon",
            primary_name = "Sword",
            secondary_option = {
                name = "Named Shield",
                description = "Shield-authored flavor text.",
                inventory_icon = "shield_icon",
            },
            ownership = "shield",
            local_resource_available = function(icon) return icon == "shield_icon" end,
        })
        H.equal(result.icon, "shield_icon")
        H.equal(result.primary_name, "Sword")
        H.equal(result.secondary_name, "Named Shield")
        H.equal(result.secondary_description, "Shield-authored flavor text.")
        H.truthy(result.changed)
    end)

    H.test("dual offhand name never steals primary icon", function()
        local result = policy.resolve({
            base_icon = "primary_icon",
            primary_name = "Primary Axe",
            secondary_option = { name = "Offhand Axe", inventory_icon = "offhand_icon" },
            ownership = "dual",
            local_resource_available = function() return true end,
        })
        H.equal(result.icon, "primary_icon")
        H.equal(result.secondary_name, "Offhand Axe")
    end)

    H.test("missing local custom asset fails closed to vanilla icon", function()
        local result = policy.resolve({
            base_icon = "vanilla_icon",
            primary_name = "Sword",
            secondary_option = { name = "Mod Shield", inventory_icon = "custom_icon" },
            ownership = "shield",
            local_resource_available = function() return false end,
        })
        H.equal(result.icon, "vanilla_icon")
        H.equal(result.secondary_name, "Mod Shield")
    end)

    H.test("component description never falls back to primary text", function()
        local result = policy.resolve({
            base_icon = "primary_icon",
            primary_name = "Primary Weapon",
            secondary_option = {
                name = "Independent Offhand",
                description = "Offhand source description.",
            },
            ownership = "dual",
        })
        H.equal(result.secondary_description, "Offhand source description.")
        H.equal(result.secondary_description == "Primary weapon description.", false)
    end)

    H.test("Hold-Tab peer identity resolves only from existing local caches", function()
        local la = {
            peer_a = {
                slot_melee = {
                    kind = "offhand",
                    armoury_key = "la_shield",
                    vanilla_key = "shield_skin",
                },
            },
        }
        local mesh = {
            peer_b = {
                slot_melee = { left_hand_unit = "units/cwv/offhand" },
            },
        }
        local record, source = policy.find_peer_record(
            "peer_a", { "slot_melee" }, la, mesh)
        H.equal(record.armoury_key, "la_shield")
        H.equal(source, "la_peer_cache")

        record, source = policy.find_peer_record(
            "peer_b", { "slot_melee" }, la, mesh)
        H.equal(record.unit_path, "units/cwv/offhand")
        H.equal(source, "mesh_peer_cache")

        H.equal(policy.find_peer_record("peer_without_parity",
            { "slot_melee" }, la, mesh), nil)
        H.equal(policy.find_peer_record(nil,
            { "slot_melee" }, la, mesh), nil)
    end)
end
