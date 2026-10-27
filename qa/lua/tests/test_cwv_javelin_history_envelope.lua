-- Actual producer -> retained owner -> exact private item/acquisition route.
return function(H, root)
    local F = dofile(root .. "/qa/lua/fixtures/cwv_javelin_history_owner.lua")
    local function create(options) return F.new(H, root, options):install() end
    local function history(c, id, parity)
        local row = c.install_history(id or "wt", "5_1_1", parity)
        H.equal(#row.runtime.ledgers.javelin, 7); H.equal(row.verify(), nil)
        return row
    end
    for _, id in ipairs({ "wt", "wt_dev" }) do
        H.test("#428 Javelin actual " .. id .. " history after construction retains both items and seeds", function()
            local c = create(); F.admitted(H, c)
            local row = history(c, id); F.admitted(H, c)
            H.equal(row.owner:reconcile("bounded-javelin-history"), true); F.admitted(H, c)
            H.equal(row.owner:restore(), true); H.truthy(row.verify()); F.admitted(H, c)
            c.history_mods[id] = nil; F.admitted(H, c)
        end)
        H.test("#428 Javelin actual " .. id .. " history before construction normalizes detached only", function()
            local c = create({ before = function(_, install) install(id) end })
            F.admitted(H, c)
            H.equal(c.env.Weapons.javelin_template.actions.action_one.stab_01.damage_profile,
                c.histories[id].runtime.registration.private_by_state_name["5_1_1"].medium_javelin_smiter_stab)
            H.equal(c.template.actions.action_one.stab_01.damage_profile, "cwv_tj_medium_javelin_smiter_stab")
            H.equal(c.histories[id].owner:restore(), true); F.admitted(H, c)
        end)
    end
    H.test("#428 Javelin parityfalse active seven native-valued routes remain authorized", function()
        local c = create(); local row = history(c, "wt", false)
        H.equal(row.runtime.active.javelin.parity, false); F.admitted(H, c)
        row.set_parity(true); H.equal(row.owner:reconcile("parity-on"), true); F.admitted(H, c)
        row.set_parity(false); H.equal(row.owner:reconcile("parity-off"), true); F.admitted(H, c)
    end)
    H.test("#428 Javelin parityfalse before construction preserves healthy admission", function()
        local c = create({ before = function(_, install) install("wt", "5_1_1", false) end }); F.admitted(H, c)
    end)
    H.test("#428 Javelin Current registration before construction preserves native admission", function()
        local c = create({ before = function(_, install) install("wt", "current") end }); F.admitted(H, c)
        H.equal(#(c.histories.wt.runtime.ledgers.javelin or {}), 0)
    end)
    H.test("#428 Javelin no resolver Current remains supported", function()
        F.admitted(H, create({ resolve = function() error("unavailable") end }))
    end)
    H.test("#428 Javelin live historical routes require their actual producer", function()
        local c = create(); history(c); F.admitted(H, c); c.history_mods.wt = nil; F.denied(H, c)
    end)
    local defects = {
        { "runtime replacement", function(c, row) row.mod._wt_history_runtime = {} end },
        { "captured verifier", function(c, row) row.runtime.verify = function() return nil end end },
        { "ledger route path", function(c, row) row.runtime.ledgers.javelin[1].operation.path[3] = "foreign" end },
        { "ledger foreign parent", function(c, row) row.runtime.ledgers.javelin[1].parent = {} end },
        { "ledger wrong original", function(c, row) row.runtime.ledgers.javelin[1].original_value = "foreign" end },
        { "ledger metatable", function(c, row) setmetatable(row.runtime.ledgers.javelin[1], {}) end },
        { "active wrong parity", function(c, row) row.runtime.active.javelin.parity = false end },
        { "missing route", function(c, row) table.remove(row.runtime.ledgers.javelin) end },
        { "profile object", function(c, row)
            local name = row.runtime.registration.names[1]; c.env.DamageProfileTemplates[name] = {} end },
        { "profile lookup reverse", function(c, row)
            local name = row.runtime.registration.names[1]; c.lookup[c.lookup[name]] = "foreign" end },
        { "profile lookup missing forward", function(c, row) c.lookup[row.runtime.registration.names[1]] = nil end },
        { "profile lookup metatable", function(c) setmetatable(c.lookup, {}) end },
        { "profile lookup foreign root", function(c) c.env.NetworkLookup.damage_profiles = {} end },
        { "shared fallback owned row", function(c, row) row.mod._wt431_custom_profile_fallback[row.runtime.registration.names[1]] = "foreign" end },
        { "shared fallback map", function(c, row) row.mod._wt431_custom_profile_fallback = {} end },
        { "source action parent", function(c)
            local one = c.env.Weapons.javelin_template.actions.action_one
            one.stab_01 = c.env.table.clone(one.stab_01, true) end },
        { "source action metatable", function(c) setmetatable(c.env.Weapons.javelin_template.actions.action_one.stab_01, {}) end },
        { "unrelated source cell", function(c) c.env.Weapons.javelin_template.actions.action_one.stab_01.anim_time_scale = 29 end },
        { "owned clone cell", function(c) c.template.actions.action_one.stab_01.damage_profile = "foreign" end },
        { "foreign scalar", function(c) c.env.Weapons.javelin_template.actions.action_one.stab_01.damage_profile = "foreign" end },
        { "partial native restore", function(c) c.env.Weapons.javelin_template.actions.action_one.stab_01.damage_profile = "medium_javelin_smiter_stab" end },
    }
    for _, defect in ipairs(defects) do
        H.test("#428 Javelin finite delegation rejects " .. defect[1], function()
            local c = create(); local row = history(c); F.admitted(H, c); defect[2](c, row); F.denied(H, c)
        end)
    end
    H.test("#428 Javelin equal-comparing foreign parent is not raw authority", function()
        local c = create(); history(c); F.admitted(H, c)
        local one = c.env.Weapons.javelin_template.actions.action_one
        local original, meta = one.stab_01, { __eq = function() return true end }
        setmetatable(original, meta)
        local foreign = setmetatable(c.env.table.clone(original, true), meta)
        H.truthy(original == foreign); H.equal(rawequal(original, foreign), false)
        one.stab_01 = foreign; F.denied(H, c)
    end)
    H.test("#428 Javelin actual AuthenticPistol append does not own history fallback siblings", function()
        local c = create(); local row = history(c); F.admitted(H, c)
        local Owner = c.T.run(c.T.read(root .. "/weapon_tweaker/scripts/mods/weapon_tweaker/_wt_authentic_pistol_owner.lua"), c.env, "actual-AuthenticPistol")
        local owner = Owner.install(row.mod, { lookup = c.capsule.network_lookup, globals = c.env })
        H.equal(owner.validate(), true); H.equal(row.verify(), nil); F.admitted(H, c)
    end)
    H.test("#428 Javelin real history during prepare aborts complete source-before commit", function()
        local install, once
        local c = F.new(H, root, { before = function(_, actual) install = actual end,
            construction_owner = function(owner)
                local construct = owner.construct
                owner.construct = function(prepare, wields)
                    return construct(function(...)
                        local result = prepare(...)
                        if not once then once = true; install("wt") end
                        return result
                    end, wields)
                end
            end }):install()
        H.truthy(once); H.truthy(c.owner.check():find("family_commit_rejected", 1, true)); F.denied(H, c)
        H.equal(c.env.Weapons.tuskgor_javelin_template, nil)
        for _, name in ipairs(c.names) do H.equal(c.env.DamageProfileTemplates["cwv_tj_" .. name], nil) end
    end)
    H.test("#428 Javelin identical profile combat body remains delegated not gameplay-attested", function()
        local c = create(); local row = history(c); F.admitted(H, c)
        c.env.DamageProfileTemplates[row.runtime.registration.names[1]].not_gameplay_attested = true
        F.admitted(H, c)
    end)
    H.test("#428 Javelin Current and historical preserve same registered-profile IDs math and audit", function()
        local a = create({ before = function(_, install) install("wt", "current") end })
        local b = create({ before = function(_, install) install("wt", "5_1_1") end })
        local legacy = create({ prior = true, before = function(_, install) install("wt", "current") end })
        H.truthy(legacy.template, "complete reconstructed original installer executed")
        F.admitted(H, a); F.admitted(H, b)
        for _, name in ipairs(a.names) do
            H.equal(a.lookup["cwv_tj_" .. name], b.lookup["cwv_tj_" .. name])
            H.deep_equal(a.env.DamageProfileTemplates["cwv_tj_" .. name], b.env.DamageProfileTemplates["cwv_tj_" .. name])
        end
        -- Reuse the existing complete callback/shape observer verbatim, not a
        -- function-address comparison across two separately loaded modules.
        local source = a.T.read(root .. "/qa/lua/tests/test_cwv_javelin_construction.lua")
        local ending = assert(source:find('    H.test("#428 Javelin actual complete old new', 1, true))
        local observe = a.T.run(source:sub(1, ending - 1) .. "    return observed\nend\n", a.env, "existing-Javelin-complete-observer")(H, root)
        local left, right = observe(a), observe(b)
        left.donor, right.donor = nil, nil
        H.deep_equal(left, right, "complete callback transcripts and owned shape under identical four-profile history registration")
        local old = observe(legacy); old.donor = nil
        H.deep_equal(left, old, "complete original installer equals current after the same four WT registrations")
        H.deep_equal(a.audit(), b.audit()); H.equal(a.state._cwv_damage_profile_generation, b.state._cwv_damage_profile_generation)
    end)
    H.test("#428 shared history actual manifest preserves once-load order and captured resolver", function()
        local Short = dofile(root .. "/qa/lua/fixtures/cwv_shortsword_history_owner.lua")
        local c = Short.new(H, root)
        local positions = {}
        for index, name in ipairs(c.loads_order) do
            if name == "_cwv_history_producer_binding" or name == "_cwv_core_templates"
                    or name == "_cwv_shortsword_construction_owner" or name == "_cwv_shortsword_history_envelope" then
                H.equal(positions[name], nil, "actual helper/module load once"); positions[name] = index
            end
        end
        H.truthy(positions._cwv_history_producer_binding < positions._cwv_core_templates)
        H.truthy(positions._cwv_core_templates < positions._cwv_shortsword_construction_owner)
        H.truthy(positions._cwv_shortsword_construction_owner < positions._cwv_shortsword_history_envelope)
        H.truthy(c.core.history_producer_binding)
        c.env.get_mod = function() error("late replacement must not be read") end
        c.install_history("wt"); Short.admitted(H, c)
    end)
    H.test("#428 Javelin private factory captures helper across core-field reassignment", function()
        local c = create()
        H.truthy(rawequal(c.core.history_producer_binding, c.history_binding))
        c.core.history_producer_binding = nil
        history(c); F.admitted(H, c)
    end)
    for _, defect in ipairs({ "live-source alias", "wrong detached scalar", "wrong detached parent" }) do
        H.test("#428 Javelin detached finite normalization rejects " .. defect, function()
            local source, before
            local c = F.new(H, root, { before = function(context, install)
                install("wt"); source = context.env.Weapons.javelin_template
                before = source.actions.action_one.stab_01.damage_profile
            end, construction_options = function(options)
                local clone = options.clone
                options.clone = function(value)
                    local result = clone(value)
                    if rawequal(value, source) then
                        if defect == "live-source alias" then return source end
                        if defect == "wrong detached scalar" then result.actions.action_one.stab_01.damage_profile = "foreign"
                        else result.actions.action_one.stab_01 = {} end
                    end
                    return result
                end
            end }):install()
            F.denied(H, c); H.equal(source.actions.action_one.stab_01.damage_profile, before)
            H.equal(c.env.Weapons.tuskgor_javelin_template, nil)
        end)
    end
    H.test("#428 Javelin initial shallow fabricated history runtime cannot authorize private route", function()
        local c = create({ before = function(context, _, mods)
            local mod = {}; mod._wt_history_runtime = { mod = mod, verify = function() return nil end }; mods.wt = mod
            context.env.Weapons.javelin_template.actions.action_one.stab_01.damage_profile = "foreign_private"
        end }); F.denied(H, c)
    end)
end
