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
end
