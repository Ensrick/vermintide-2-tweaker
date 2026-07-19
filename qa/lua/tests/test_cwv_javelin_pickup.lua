return function(H, repo_root)
    local helper = dofile(repo_root
        .. "/character_weapon_variants/scripts/mods/character_weapon_variants/_cwv_javelin_pickup.lua")
    local map = {
        cwv_javelin = "ammo_throwing_axe_01_t1",
        cwv_link_javelin = "link_ammo_throwing_axe_01_t1",
    }

    H.test("CWV javelin keeps functional pickup under confirmed parity", function()
        H.equal(helper.wire_fallback("cwv_javelin", map, true), nil)
        H.equal(helper.wire_fallback("cwv_link_javelin", map, true), nil)
    end)

    H.test("CWV javelin degrades to wire-safe pickup without parity", function()
        H.equal(helper.wire_fallback("cwv_javelin", map, false), "ammo_throwing_axe_01_t1")
        H.equal(helper.wire_fallback("cwv_link_javelin", map, false), "link_ammo_throwing_axe_01_t1")
        H.equal(helper.wire_fallback("vanilla_pickup", map, false), nil)
    end)

    H.test("CWV source gates recovered javelin pickup on peer parity", function()
        local source = require("cwv_source").combined(repo_root)
        H.truthy(source:find("mod._cwv_javelin_pickup.wire_fallback", 1, true))
        H.truthy(source:find("_wire_safe_pickup_name(cwv_key, true)", 1, true))
        H.truthy(source:find("_wire_safe_pickup_name(cwv_key, false)", 1, true))
    end)

    H.test("CWV tuskgor bomb path stays fail-closed until ActionUtils sender gate exists", function()
        local source = require("cwv_source").combined(repo_root)
        local feature_on = source:find("local _TJB_FEATURE_ON = true", 1, true) ~= nil
        local feature_off = source:find("local _TJB_FEATURE_ON = false", 1, true) ~= nil
        local has_actionutils_sender_gate = source:find('ActionUtils", "spawn_pickup_projectile"', 1, true) ~= nil
            or source:find("ActionUtils.spawn_pickup_projectile", 1, true) ~= nil
            or source:find("cwv_tuskgor_javelin_bomb_actionutils_wire_gate", 1, true) ~= nil

        if feature_on then
            H.truthy(
                has_actionutils_sender_gate,
                "enabling the Tuskgor bomb path requires an ActionUtils.spawn_pickup_projectile sender gate"
            )
        else
            H.truthy(feature_off, "Tuskgor bomb path must be explicitly inert while no ActionUtils sender gate exists")
        end

        H.truthy(
            source:find('mod._cwv_peer_parity:register_gated_feature("cwv_tuskgor_javelin_bomb_pool"', 1, true),
            "Tuskgor bomb world/pool injection must remain behind the peer-parity registry"
        )
        H.truthy(
            source:find("if not _TJB_FEATURE_ON then return end", 1, true),
            "Tuskgor bomb pool injection must self-guard while the feature flag is disabled"
        )
        H.truthy(
            source:find("rawget(ItemMasterList, _TJB_ITEM_KEY)", 1, true),
            "manual grant command must not index an unregistered bomb item directly"
        )
        H.truthy(
            source:find("javelin-bomb item not registered", 1, true),
            "manual grant command must fail closed while the bomb item is not registered"
        )
    end)
end
