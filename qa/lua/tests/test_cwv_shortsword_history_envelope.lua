-- #428 finite native dagger history delegation; no generic WT-write exception.
return function(H, root)
    local F = dofile(root .. "/qa/lua/fixtures/cwv_shortsword_history_owner.lua")
    local function action(c) return c.env.Weapons.one_handed_daggers_template_1.actions.action_one.heavy_attack_right end
    local function new(options) return F.new(H, root, options) end
    local function historical(c, id) local row = c.install_history(id or "wt"); F.admitted(H, c); return row end
    local function ledger(row) return row.runtime.ledgers.sienna_dagger[1] end
    for _, id in ipairs({ "wt", "wt_dev" }) do
        H.test("#428 actual " .. id .. " Owner history AFTER construction retains item and seed", function()
            local c = new(); F.admitted(H, c)
            local row = historical(c, id)
            H.equal(row.verify(), nil); H.equal(#row.runtime.ledgers.sienna_dagger, 1)
            H.equal(action(c).damage_profile, "dagger_h1_medium_smiter_diag")
            H.equal(c.template.actions.action_one.heavy_attack_right.damage_profile, "cwv_shortsword_medium_slashing_smiter_stab")
            H.equal(row.owner:reconcile("bounded-history-test"), true); F.admitted(H, c)
        end)
        H.test("#428 actual " .. id .. " Owner history BEFORE construction restores then removes", function()
            local c = new({ before = function(_, install) install(id) end })
            F.admitted(H, c)
            local row = c.histories[id]
            H.equal(row.owner:restore(), true)
            H.truthy(row.verify(), "real normal verifier reports historical selection missing ledger after restore")
            H.equal(action(c).damage_profile, "medium_burning_smiter_stab_H")
            F.admitted(H, c)
            c.history_mods[id] = nil; F.admitted(H, c)
        end)
    end
    H.test("#428 actual public historical plus Dev Current coexistence retains exact native state", function()
        local c = new(); historical(c, "wt")
        local row = c.install_history("wt_dev", "current")
        H.equal(row.verify(), nil); F.admitted(H, c)
        c.history_mods.wt_dev = nil; F.admitted(H, c)
        H.equal(c.histories.wt.owner:restore(), true); F.admitted(H, c)
    end)
    H.test("#428 unchanged native Current remains valid without history discovery", function()
        local c = new({ resolve = function() error("resolver unavailable") end })
        F.admitted(H, c)
    end)
    H.test("#428 unowned historical value without actual producer remains denied", function()
        local c = new(); action(c).damage_profile = "dagger_h1_medium_smiter_diag"; F.denied(H, c)
    end)
    H.test("#428 live historical value loses authority when its real producer disappears", function()
        local c = new(); historical(c); c.history_mods.wt = nil; F.denied(H, c)
    end)
    H.test("#428 initial shallow fake runtime true callback does not authorize construction", function()
        local c = new({ before = function(context, _, mods)
            local mod = {}; mod._wt_history_runtime = { mod = mod, verify = function() return nil end }
            mods.wt = mod
            action(context).damage_profile = "dagger_h1_medium_smiter_diag"
        end })
        F.denied(H, c)
    end)
    local defects = {
        { "runtime object", function(c, row) row.mod._wt_history_runtime = {} end },
        { "captured verifier", function(c, row) row.runtime.verify = function() return nil end end },
        { "policy object", function(c, row) row.runtime.policy = {} end },
        { "policy callback", function(c, row) row.runtime.policy.ledger_status = function() return "same" end end },
        { "registration object", function(c, row) row.runtime.registration = {} end },
        { "operation path", function(c, row) ledger(row).operation.path[3] = "heavy_attack_left" end },
        { "ledger raw parent", function(c, row) ledger(row).parent = {} end },
        { "ledger presence", function(c, row) ledger(row).original_present = false end },
        { "ledger original", function(c, row) ledger(row).original_value = "foreign" end },
        { "ledger applied", function(c, row) ledger(row).applied_value = "foreign" end },
        { "runtime metatable", function(c, row) setmetatable(row.runtime, {}) end },
        { "ledger metatable", function(c, row) setmetatable(ledger(row), {}) end },
        { "unrelated donor cell", function(c) action(c).anim_time_scale = 27 end },
        { "owned clone cell", function(c) c.template.actions.action_one.heavy_attack_right.damage_profile = "foreign" end },
        { "owned profile", function(c) c.env.DamageProfileTemplates.cwv_shortsword_medium_slashing_smiter_stab.foreign = true end },
        { "unknown profile value", function(c) action(c).damage_profile = "foreign" end },
        { "native action metatable", function(c) setmetatable(action(c), {}) end },
        { "wrong cell plus permitted value", function(c) c.env.Weapons.one_handed_daggers_template_1.actions.action_one.heavy_attack_left.damage_profile = "dagger_h1_medium_smiter_diag" end },
    }
    for _, defect in ipairs(defects) do
        H.test("#428 history delegation rejects " .. defect[1], function()
            local c = new(); local row = historical(c); defect[2](c, row); F.denied(H, c)
        end)
    end
    H.test("#428 equal-comparing foreign discovered mod is not a raw identity", function()
        local meta = { __eq = function() return true end }
        local c = new({ before = function(_, install)
            local row = install("wt"); setmetatable(row.mod, meta)
        end })
        F.admitted(H, c)
        local mod = c.histories.wt.mod
        local foreign = setmetatable({ _wt_history_runtime = mod._wt_history_runtime }, meta)
        H.truthy(mod == foreign); H.equal(rawequal(mod, foreign), false)
        c.history_mods.wt = foreign; F.denied(H, c)
    end)
    H.test("#428 complete source-before commit still rejects history-time mutation inside prepare", function()
        local install, once
        local c = new({ before = function(_, actual_install) install = actual_install end,
            construction_options = function(options, context)
            local real = options.scalar_factory
            options.scalar_factory = function(input)
                local planner = real(input)
                local clone = planner.clone_damage_profile
                planner.clone_damage_profile = function(...)
                    local result = clone(...)
                    if not once then once = true; install("wt") end
                    return result
                end
                return planner
            end
        end })
        H.truthy(once); H.truthy(c.histories.wt)
        H.truthy(c.owner.check():find("family_commit_rejected", 1, true))
        F.denied(H, c)
    end)
    H.test("#428 semantic LIMIT identical native original has no observable writer provenance", function()
        local c = new(); F.admitted(H, c)
        action(c).damage_profile = "medium_burning_smiter_stab_H"
        F.admitted(H, c)
    end)
    local bad_clones = {
        { "live-source alias", function(source) return source end },
        { "wrong clone H2 value", function(_, copy) copy.actions.action_one.heavy_attack_right.damage_profile = "foreign"; return copy end },
        { "wrong clone parent", function(_, copy) copy.actions.action_one.heavy_attack_right = {}; return copy end },
    }
    for _, bad in ipairs(bad_clones) do
        H.test("#428 detached history normalization rejects " .. bad[1], function()
            local source, original
            local c = new({ before = function(context, install)
                install("wt"); source = context.env.Weapons.one_handed_daggers_template_1
                original = source.actions.action_one.heavy_attack_right.damage_profile
            end, construction_options = function(options)
                local real = options.clone
                options.clone = function(value)
                    local result = real(value)
                    if rawequal(value, source) then return bad[2](source, result) end
                    return result
                end
            end })
            H.equal(source.actions.action_one.heavy_attack_right.damage_profile, original)
            H.equal(original, "dagger_h1_medium_smiter_diag"); F.denied(H, c)
        end)
    end
    H.test("#428 history-before construction preserves complete cloned math IDs audit and native callbacks", function()
        local quiet = setmetatable({ test = function() end }, { __index = H })
        local existing = dofile(root .. "/qa/lua/tests/test_cwv_shortsword_construction.lua")(quiet, root)
        local baseline = new()
        local history = new({ before = function(_, install) install("wt") end })
        F.admitted(H, baseline); F.admitted(H, history)
        local before, after = existing.observed(baseline), existing.observed(history)
        before.donor, after.donor = nil, nil
        H.deep_equal(after, before, "all owned template/profile/math/ID/audit/callback outputs unchanged")
        H.equal(#history.proof().events, 7)
    end)
end
