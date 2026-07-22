return function(H, repo_root)
    local public_root = repo_root .. "/weapon_tweaker/scripts/mods/weapon_tweaker/"
    local dev_root = repo_root .. "/weapon_tweaker_dev/scripts/mods/weapon_tweaker_dev/"
    local public_unlocks = dofile(public_root .. "wt_unlock_data.lua").weapon_unlock_map.wh_priest
    local policy = dofile(dev_root .. "wt_universal_availability.lua")
    local status = dofile(dev_root .. "wt_port_status.lua")

    H.test("WT #113 seven-row public roster is historical not a dev invariant", function()
        H.equal(#public_unlocks, 7)
        local dev_map = {}
        policy.expand_unlock_map(dev_map)
        H.equal(#dev_map.wh_priest, 83)
        local ranged_keys = {}
        for _, key in ipairs(policy.ranged_weapons) do ranged_keys[key] = true end
        local ranged = 0
        for _, key in ipairs(dev_map.wh_priest) do
            if ranged_keys[key] then ranged = ranged + 1 end
        end
        H.equal(ranged, 31)
    end)

    H.test("WT #113 historical Empire Flail route is explicitly untested", function()
        local rows, counts = status.audit_cross_character("wh_priest", public_unlocks)
        H.equal(#rows, 1)
        H.equal(counts.total, 1)
        H.equal(counts.untested, 1)
        H.equal(counts.routing_wired, 1)
        H.equal(rows[1].weapon_key, "es_1h_flail")
        H.equal(rows[1].state, "untested")
        H.equal(rows[1].routing_state, "wired")
        H.equal(rows[1].redirect, "Warrior Priest flail event map")
    end)

    H.test("WT #113 native routing is not verification", function()
        for _, key in ipairs({
            "wh_1h_hammer", "wh_2h_hammer", "wh_dual_hammer",
            "wh_flail_shield", "wh_hammer_book", "wh_hammer_shield",
        }) do
            H.equal(status.routing_state("wh_priest", key), "native")
            H.equal(status.state("wh_priest", key), "untested")
        end
    end)
end
