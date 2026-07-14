return function(H, repo_root)
    local root = repo_root .. "/weapon_tweaker/scripts/mods/weapon_tweaker/"
    local unlocks = dofile(root .. "wt_unlock_data.lua").weapon_unlock_map.wh_priest
    local status = dofile(root .. "wt_port_status.lua")
    local expected = {
        es_1h_flail = true,
        wh_1h_hammer = true,
        wh_2h_hammer = true,
        wh_dual_hammer = true,
        wh_flail_shield = true,
        wh_hammer_book = true,
        wh_hammer_shield = true,
    }

    H.test("WT #113 Warrior Priest catalog is exact and melee-only", function()
        local seen = {}
        for _, key in ipairs(unlocks) do
            H.truthy(expected[key], "unexpected Warrior Priest key " .. tostring(key))
            H.equal(seen[key], nil, "duplicate Warrior Priest key " .. tostring(key))
            seen[key] = true
        end
        H.equal(#unlocks, 7)
        for key in pairs(expected) do H.truthy(seen[key], "missing Warrior Priest key " .. key) end
    end)

    H.test("WT #113 Warrior Priest has one complete cross-character port", function()
        local rows, counts = status.audit_cross_character("wh_priest", unlocks)
        H.equal(#rows, 1)
        H.equal(counts.total, 1)
        H.equal(counts.working, 1)
        H.equal(counts.needs_animations, 0)
        H.equal(counts.untested, 0)
        H.equal(counts.needs_offsets, 0)
        H.equal(counts.picker_visible, 0)
        H.equal(counts.hidden_needs_animations, 0)
        H.equal(rows[1].weapon_key, "es_1h_flail")
        H.equal(rows[1].redirect, "[Warrior Priest flail event map]")
        H.equal(rows[1].model_substitute, nil)
        H.equal(rows[1].picker_visible, false)
    end)

    H.test("WT #113 Warrior Priest native rows remain native working entries", function()
        for _, key in ipairs({
            "wh_1h_hammer", "wh_2h_hammer", "wh_dual_hammer",
            "wh_flail_shield", "wh_hammer_book", "wh_hammer_shield",
        }) do
            H.equal(status.tag("wh_priest", key), "[working]")
            H.equal(status.needs_anims("wh_priest", key), false)
            H.equal(status.model_substitute("wh_priest", key), nil)
        end
    end)

    H.test("WT #113 Warrior Priest diagnostics are automatic and bounded", function()
        local file = assert(io.open(root .. "_wt_diagnostics.lua", "rb"))
        local source = file:read("*a")
        file:close()
        H.truthy(source:find("_audit_warrior_priest_3p(false)", 1, true))
        H.truthy(source:find('mod:command("wt_audit_warrior_priest_3p"', 1, true))
        H.truthy(source:find("catalog=%d native=%d cross=%d", 1, true))
    end)
end
