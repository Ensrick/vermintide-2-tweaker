return function(H, repo_root)
    local root = repo_root .. "/weapon_tweaker/scripts/mods/weapon_tweaker/"
    local unlocks = dofile(root .. "wt_unlock_data.lua").weapon_unlock_map
    local status = dofile(root .. "wt_port_status.lua")
    local careers = { "wh_captain", "wh_bountyhunter", "wh_zealot" }

    H.test("WT #112 Saltzpyre non-WP coverage is exact and career-parity safe", function()
        local baseline
        for _, career in ipairs(careers) do
            local rows, counts = status.audit_cross_character(career, unlocks[career])
            local keys = {}
            for i, row in ipairs(rows) do keys[i] = row.weapon_key end
            local signature = table.concat(keys, "\0")
            baseline = baseline or signature
            H.equal(signature, baseline, career .. " cross-character coverage drift")
            H.equal(counts.total, 54)
            H.equal(counts.working, 37)
            H.equal(counts.needs_animations, 17)
            H.equal(counts.untested, 0)
            H.equal(counts.needs_offsets, 0)
            H.equal(counts.picker_visible, 2)
            H.equal(counts.hidden_needs_animations, 15)
        end
    end)

    H.test("WT #112 promotes proven 1H rows and removes stale Dual Hammers", function()
        for _, career in ipairs(careers) do
            H.equal(status.tag(career, "es_1h_mace"), "[working]")
            H.equal(status.tag(career, "es_1h_sword"), "[working]")
            H.equal(status.tag(career, "we_1h_axe"), "[working]")
            H.equal(status.redirect_target(career, "we_1h_axe"), "[Saltzpyre 1H Axe]")
            H.equal(status.needs_anims(career, "dr_dual_wield_hammers"), false)
        end
        local present = {}
        for _, key in ipairs(unlocks.wh_captain) do present[key] = true end
        H.equal(present.dr_dual_wield_hammers, nil)
    end)

    H.test("WT #112 pending targets stay diagnostic and picker-bounded", function()
        local rows = status.audit_cross_character("wh_captain", unlocks.wh_captain)
        local targets, no_target = 0, 0
        local by_key = {}
        for _, row in ipairs(rows) do
            by_key[row.weapon_key] = row
            if row.status ~= "[working]" then
                if row.redirect then targets = targets + 1 else no_target = no_target + 1 end
            end
        end
        H.equal(targets, 15)
        H.equal(no_target, 2)
        H.equal(by_key.bw_ghost_scythe.picker_visible, true)
        H.equal(by_key.we_spear.picker_visible, true)
        H.equal(by_key.we_1h_spears_shield.redirect, "[Dual Axe & Falchion]")
        H.equal(by_key.we_deus_01.redirect, "[Saltzpyre Crossbow]")
        H.equal(by_key.we_deus_01.model_substitute, "Crossbow")
        for _, key in ipairs({ "we_shortbow", "we_shortbow_hagbane" }) do
            H.equal(by_key[key].status, "[needs animations]")
            H.equal(by_key[key].redirect, nil)
            H.equal(by_key[key].model_substitute, nil)
            H.equal(by_key[key].picker_visible, false)
        end
    end)

    H.test("WT #112 Saltzpyre diagnostics are automatic and bounded", function()
        local file = assert(io.open(root .. "_wt_diagnostics.lua", "rb"))
        local source = file:read("*a")
        file:close()
        H.truthy(source:find("_audit_saltzpyre_3p(false)", 1, true))
        H.truthy(source:find('mod:command("wt_audit_saltzpyre_3p"', 1, true))
        H.truthy(source:find("careers=3 parity=%s ports=%d", 1, true))
    end)
end
