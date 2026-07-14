return function(H, repo_root)
    local root = repo_root .. "/weapon_tweaker/scripts/mods/weapon_tweaker/"
    local unlocks = dofile(root .. "wt_unlock_data.lua").weapon_unlock_map
    local status = dofile(root .. "wt_port_status.lua")
    local careers = { "we_waywatcher", "we_maidenguard", "we_shade", "we_thornsister" }

    H.test("WT #111 Kerillian coverage is exact and career-parity safe", function()
        local baseline
        for _, career in ipairs(careers) do
            local rows, counts = status.audit_cross_character(career, unlocks[career])
            local keys = {}
            for i, row in ipairs(rows) do keys[i] = row.weapon_key end
            local signature = table.concat(keys, "\0")
            baseline = baseline or signature
            H.equal(signature, baseline, career .. " cross-character coverage drift")
            H.equal(#rows, 60)
            H.equal(counts.total, 60)
            H.equal(counts.working, 44)
            H.equal(counts.needs_animations, 14)
            H.equal(counts.untested, 2)
            H.equal(counts.needs_offsets, 0)
            H.equal(counts.picker_visible, 0)
            H.equal(counts.hidden_needs_animations, 14)
        end
    end)

    H.test("WT #111 decided ranged targets remain pending and gaps stay untested", function()
        local rows = status.audit_cross_character("we_waywatcher", unlocks.we_waywatcher)
        local by_key = {}
        for _, row in ipairs(rows) do by_key[row.weapon_key] = row end
        for _, key in ipairs({
            "dr_crossbow", "dr_deus_01", "dr_drake_pistol", "dr_drakegun",
            "dr_rakegun", "dr_steam_pistol", "es_blunderbuss", "es_handgun",
            "es_repeating_handgun", "wh_brace_of_pistols", "wh_crossbow",
            "wh_crossbow_repeater", "wh_deus_01", "wh_repeating_pistols",
        }) do
            H.equal(by_key[key].status, "[needs animations]")
            H.equal(by_key[key].redirect, "[Elf Repeater Crossbow]")
            H.equal(by_key[key].picker_visible, false)
        end
        for _, key in ipairs({ "es_1h_mace", "es_longbow" }) do
            H.equal(by_key[key].status, "[untested]")
            H.equal(by_key[key].redirect, nil)
            H.equal(by_key[key].picker_visible, false)
        end
    end)

    H.test("WT #111 Kerillian diagnostics are automatic and bounded", function()
        local file = assert(io.open(root .. "_wt_diagnostics.lua", "rb"))
        local source = file:read("*a")
        file:close()
        H.truthy(source:find("_audit_kerillian_3p(false)", 1, true))
        H.truthy(source:find('mod:command("wt_audit_kerillian_3p"', 1, true))
        H.truthy(source:find("hidden_needs_anims=%d", 1, true))
    end)
end
