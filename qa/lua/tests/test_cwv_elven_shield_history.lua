-- Finite actual WT history production, native donor vs authored CWV Current.
return function(H, root)
    local F = dofile(root .. "/qa/lua/fixtures/cwv_elven_shield_history_owner.lua")
    local TARGET = "elven_sword_shield_template"
    local function authored(c)
        local one = c.env.Weapons[TARGET].actions.action_one
        H.equal(one.heavy_attack_right.damage_profile, "cwv_ess_medium_slashing_tank_1h")
        H.equal(one.light_attack_stab_postpush.damage_window_end, 0.32)
        H.equal(one.light_attack_stab_postpush.damage_window_start, 0.22)
        H.equal(one.light_attack_stab_postpush.dedicated_target_range, 2.8)
        H.equal(one.light_attack_stab_postpush.range_mod, 1.3)
        H.equal(one.light_attack_stab_postpush.range_mod_add, 0.2)
        H.equal(#c.ess_proof().events, 7)
        H.equal(c.state._cwv_profile_multiplier_check(), nil)
    end
    for _, id in ipairs({ "wt", "wt_dev" }) do
        for _, state in ipairs({ "5_1_1", "5_2_0", "5_6_1" }) do
            for _, parity in ipairs({ false, true }) do
                local mod_id, selected, allowed = id, state, parity
                H.test("#428 Elven history real " .. id .. " " .. state .. " parity=" .. tostring(parity) .. " after Current", function()
                    local c = F.new(H, root); F.admitted(H, c)
                    local row = c.install_history(mod_id, selected, allowed)
                    H.equal(row.verify(), nil); H.equal(#row.runtime.ledgers.kruber_sword_and_shield, selected == "5_1_1" and 6 or 5)
                    F.admitted(H, c); authored(c)
                    H.equal(row.owner:restore(), true); H.truthy(row.verify(), "historical boot selection remains after real restore")
                    F.admitted(H, c); authored(c)
                    c.history_mods[mod_id] = nil; F.admitted(H, c)
                end)
            end
        end
    end
    for _, state in ipairs({ "5_1_1", "5_2_0", "5_6_1" }) do
        local selected = state
        H.test("#428 Elven history " .. state .. " before construction stays authored Current", function()
            local c = F.new(H, root, { before = function(_, install) install("wt", selected, false) end })
            F.admitted(H, c); authored(c)
            H.equal(c.histories.wt.owner:restore(), true); F.admitted(H, c)
            H.equal(c.histories.wt.owner:reconcile("actual-retained-history"), true); F.admitted(H, c)
        end)
    end
    H.test("#428 Elven history current selection and both real streams coexist", function()
        local c = F.new(H, root); c.install_history("wt", "current", false); F.admitted(H, c)
        c.install_history("wt_dev", "5_1_1", true); F.admitted(H, c); authored(c)
    end)
    H.test("#428 Elven history once-manifest private by-value capsule", function()
        local c = F.new(H, root); F.admitted(H, c)
        H.equal(c.ess_loads._cwv_history_producer_binding, 1)
        H.equal(c.ess_loads._cwv_elven_shield_history_envelope, 1)
        H.equal(c.ess_loads._cwv_elven_shield_construction_owner, 1)
        c.install_history("wt", "5_1_1", false); F.admitted(H, c)
        c.ess_history.capture = function() error("late capture access") end
        c.ess_history.intact = function() error("late intact access") end
        c.ess_history.prepare_clone = function() error("late normalizer access") end
        F.admitted(H, c)
    end)
    H.test("#428 Elven history real restore before construction permits native Current", function()
        local c = F.new(H, root, { before = function(_, install)
            local row = install("wt", "5_1_1", false)
            H.equal(row.owner:restore(), true); H.truthy(row.verify())
        end })
        F.admitted(H, c); authored(c)
    end)
    for _, defect in ipairs({ "hash-row", "ledger-root", "active-root", "boot-root" }) do
        local selected = defect
        H.test("#428 Elven history restored Current rejects " .. defect, function()
            local c = F.new(H, root); local row = c.install_history("wt", "5_1_1", false)
            F.admitted(H, c); H.equal(row.owner:restore(), true); F.admitted(H, c)
            if selected == "hash-row" then row.runtime.ledgers.kruber_sword_and_shield.foreign = true
            elseif selected == "ledger-root" then row.runtime.ledgers = {}
            elseif selected == "active-root" then row.runtime.active = {}
            else row.runtime.boot_selections = c.env.table.clone(row.runtime.boot_selections, true) end
            F.denied(H, c)
        end)
    end
    local negatives = { "runtime-reference", "ledger-parent", "ledger-operation", "ledger-key", "ledger-value",
        "ledger-presence", "operation-body", "parent-reference", "parent-metatable", "absent-vs-false", "unrelated-donor", "owned-cell" }
    for _, defect in ipairs(negatives) do
        local selected = defect
        H.test("#428 Elven finite history rejects " .. defect, function()
            local c = F.new(H, root); local row = c.install_history("wt", "5_1_1", true)
            F.admitted(H, c)
            local ledger = row.runtime.ledgers.kruber_sword_and_shield
            local one = c.ess_source.actions.action_one
            if selected == "runtime-reference" then row.mod._wt_history_runtime = {}
            elseif selected == "ledger-parent" then ledger[1].parent = {}
            elseif selected == "ledger-operation" then ledger[1].operation = c.env.table.clone(ledger[1].operation, true)
            elseif selected == "ledger-key" then ledger[1].key = "foreign"
            elseif selected == "ledger-value" then ledger[1].applied_snapshot = "foreign"
            elseif selected == "ledger-presence" then ledger[1].original_present = false
            elseif selected == "operation-body" then ledger[1].operation.official_change_id = "foreign"
            elseif selected == "parent-reference" then
                local old = one.light_attack_stab_postpush
                local meta = { __eq = function() return true end }; setmetatable(old, meta)
                one.light_attack_stab_postpush = setmetatable(c.env.table.clone(old, true), meta)
                H.equal(rawequal(one.light_attack_stab_postpush, old), false)
            elseif selected == "parent-metatable" then setmetatable(one.light_attack_stab_postpush, {})
            elseif selected == "absent-vs-false" then one.light_attack_stab_postpush.range_mod_add = false
            elseif selected == "unrelated-donor" then one.heavy_attack_right.anim_time_scale = 0.12345
            else c.ess_template.actions.action_one.light_attack_stab_postpush.range_mod = 9 end
            F.denied(H, c)
        end)
    end
    H.test("#428 Elven historical scalar without real producer is denied", function()
        local c = F.new(H, root); c.ess_source.actions.action_one.heavy_attack_right.damage_profile = "medium_slashing_linesman_1h"
        F.denied(H, c)
    end)
    H.test("#428 Elven history in-prepare producer change aborts complete transaction", function()
        local c = F.new(H, root, { after_prepare = function(context)
            context.ess_source.actions.action_one.light_attack_stab_postpush.range_mod = 99
        end })
        H.equal(c.ess_constructed, false); H.equal(c.env.Weapons[TARGET], nil); F.denied(H, c)
        H.equal(c.ess_source.actions.action_one.light_attack_stab_postpush.range_mod, 99, "external writer not repaired")
        for key, intact in next, c.ess_raw_unchanged do if key ~= "weapons" then H.truthy(intact, "no partial publication " .. key) end end
    end)
    H.test("#428 Elven history real AuthenticPistol append leaves finite authority intact", function()
        local c = F.new(H, root); local row = c.install_history("wt", "5_1_1", false); F.admitted(H, c)
        local Producer = dofile(root .. "/weapon_tweaker/scripts/mods/weapon_tweaker/_wt_authentic_pistol_owner.lua")
        local owner, problem = Producer.install(row.mod, { globals = c.env, lookup = c.helper,
            clone = function(value) return c.env.table.clone(value, true) end })
        H.truthy(owner, problem); H.equal(owner.validate(), true); H.equal(row.verify(), nil)
        H.equal(row.mod._wt431_custom_profile_fallback.wt_authentic_pistol, "shot_sniper")
        F.admitted(H, c); authored(c)
    end)
    H.test("#428 Elven detached normalizer rejects live alias wrong parent and value without writes", function()
        local c = F.new(H, root); F.admitted(H, c)
        local history = c.ess_proof().history
        local normalizer = c.ess_history.prepare_clone
        H.equal(normalizer(history, c.ess_source), false, "never mutate live source alias")
        for _, defect in ipairs({ "parent", "value", "unrelated" }) do
            local clone = c.env.table.clone(c.ess_source, true)
            if defect == "parent" then clone.actions.action_one.heavy_attack_right = nil
            elseif defect == "value" then clone.actions.action_one.heavy_attack_right.damage_profile = "foreign"
            else clone.actions.action_one.heavy_attack_right.anim_time_scale = 17 end
            local before = c.graph.capture(clone, 4096, 32768)
            if defect ~= "unrelated" then H.equal(normalizer(history, clone), false); H.truthy(c.graph.intact(before))
            else H.equal(normalizer(history, clone), true); H.equal(clone.actions.action_one.heavy_attack_right.anim_time_scale, 17) end
        end
    end)
end
