return function(H, repo_root)
    local root = repo_root .. "/weapon_tweaker/scripts/mods/weapon_tweaker/"
    local unlocks = dofile(root .. "wt_unlock_data.lua").weapon_unlock_map
    local status = dofile(repo_root .. "/weapon_tweaker_dev/scripts/mods/weapon_tweaker_dev/wt_port_status.lua")

    local careers = { "es_mercenary", "es_huntsman", "es_knight", "es_questingknight" }

    H.test("WT #109 Kruber cross-character inventory is bounded and career-parity safe", function()
        local baseline
        for _, career in ipairs(careers) do
            local rows, counts = status.audit_cross_character(career, unlocks[career])
            local keys = {}
            for i, row in ipairs(rows) do keys[i] = row.weapon_key end
            local signature = table.concat(keys, "\0")
            baseline = baseline or signature
            H.equal(signature, baseline, career .. " cross-character coverage drift")
            H.equal(#rows, 52)
            H.equal(counts.total, 52)
            H.equal(counts.working, 37)
            H.equal(counts.needs_animations, 13)
            H.equal(counts.untested, 2)
            H.equal(counts.needs_offsets, 0)
            H.equal(counts.picker_visible, 0)
            H.equal(counts.hidden_needs_animations, 13)
        end
    end)

    H.test("WT #109 diagnostics expose source-backed targets without claiming a bake", function()
        local rows = status.audit_cross_character("es_mercenary", unlocks.es_mercenary)
        local by_key = {}
        for _, row in ipairs(rows) do by_key[row.weapon_key] = row end

        H.equal(by_key.we_deus_01.state, "needs_animations")
        H.equal(by_key.we_deus_01.redirect, "Empire Longbow")
        H.equal(by_key.we_deus_01.picker_visible, false)
        H.equal(by_key.wh_crossbow.state, "needs_animations")
        H.equal(by_key.wh_crossbow.redirect, nil)
        H.equal(by_key.wh_dual_wield_axe_falchion.state, "needs_animations")
        H.equal(by_key.wh_dual_wield_axe_falchion.redirect, nil)
        H.equal(by_key.we_javelin.state, "untested")
        H.equal(by_key.we_life_staff.state, "untested")
    end)

    H.test("WT #109 automatic and on-demand diagnostics are wired", function()
        local file = assert(io.open(repo_root .. "/weapon_tweaker_dev/scripts/mods/weapon_tweaker_dev/_wt_diagnostics.lua", "rb"))
        local source = file:read("*a")
        file:close()
        H.truthy(source:find("_audit_kruber_3p(false)", 1, true))
        H.truthy(source:find('mod:command("wt_audit_kruber_3p"', 1, true))
        H.truthy(source:find("hidden_needs_anims=%d", 1, true))
    end)
end
