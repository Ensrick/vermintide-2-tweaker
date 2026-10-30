-- #645 detached Mace-on-Sword SOURCE tests; not executed by preparation.
-- No movement-lease, catalogue, entry activation or game/ABI claim.
return function(H, root)
    local F = assert(loadfile(root .. "/qa/lua/fixtures/cwv_mace_sword_construction_harness.lua"))()
    local MACE, SWORD = "one_handed_hammer_template_1", "one_handed_swords_template_1"
    local CAREER = "action_career_qa_mace_sword"
    local function natives(c)
        local profiles = {}
        for _, name in ipairs({ "medium_slashing_tank_1h_finesse", "light_slashing_linesman_finesse",
            "sword_1h_light_smiter_vertical", "medium_slashing_linesman_finesse", "medium_push", "light_push" }) do
            profiles[#profiles + 1] = c.env.DamageProfileTemplates[name]
        end
        return assert(c.graph.capture({ c.env.Weapons[MACE], c.env.Weapons[SWORD],
            c.env.Weapons.one_handed_hammer_template_2, c.env.Weapons.one_handed_hammer_priest_template,
            profiles, c.env.PowerLevelTemplates, c.env.ItemMasterList }, 8192, 131072))
    end
    local function construct(c)
        local before, owner = F.baseline(c), c.create_mace()
        H.truthy(owner.construct(), owner.check()); F.verify(H, c, owner, before)
        return owner, before
    end
    H.test("645 Mace complete geometric Sword projection preserves literal finesse and native graph", function()
        local c = F.new(H, root)
        local native, owner, before = natives(c)
        owner, before = construct(c)
        H.truthy(c.graph.intact(native), "construction never rewrites either donor/profile/physical item")
        local _, value = owner.template("mace_on_empire_sword")
        H.equal(value.weapon_type, "SWORD_1H"); H.equal(value.max_fatigue_points, 8)
        H.equal(value.dodge_count, 6); H.equal(value.block_angle, 90)
        H.equal(value.sound_event_block_within_arc, nil)
        H.equal(value.wwise_dep_right_hand[1], "wwise/one_handed_swords")
        H.equal(value.state_machine, c.oracle.mace.state_machine)
        H.equal(value.wield_anim, c.oracle.mace.wield_anim)
        H.truthy(c.F.same(value.buffs, c.oracle.sword.buffs), "no template.buffs movement shortcut")
        local nodes, chains = 0, 0
        for _, group_name in ipairs({ "action_one", "action_two" }) do
            for _, node in pairs(value.actions[group_name]) do
                nodes = nodes + 1; chains = chains + #node.allowed_chain_actions
            end
        end
        H.equal(nodes, 13); H.equal(chains, 65, "complete ordered local Mace chains")
        H.equal(#value.actions.action_inspect.default.allowed_chain_actions, 2)
        H.equal(#value.actions.action_wield.default.allowed_chain_actions, 0)
        local published, generation = value, c.state._cwv_damage_profile_generation
        H.truthy(owner.construct()); H.truthy(rawequal(select(2, owner.template("mace_on_empire_sword")), published))
        H.equal(c.state._cwv_damage_profile_generation, generation, "no scalar/generation/audit replay")
        F.verify(H, c, owner, before)
    end)
    for _, enabled in ipairs({ false, true }) do
        local flag = enabled
        H.test("645 Mace actual599 timing snapshots enabled=" .. tostring(flag), function()
            local c = F.new(H, root, { mhi = flag })
            local owner = construct(c)
            for _, next_flag in ipairs({ not flag, flag }) do
                c.apply_mhi(next_flag)
                H.equal(owner.check(), nil, "known real599 transition retains authored Current custom")
                local _, template = owner.template("mace_on_empire_sword")
                H.truthy(c.F.same(template, (F.expected(c))), "native Current timings, not a blind1.05 division")
            end
        end)
    end
    for _, stream in ipairs({ "wt", "wt_dev" }) do for _, state in ipairs({ "5_1_1", "5_2_0" }) do
        local id, sid = stream, state
        H.test("645 Mace actual fullWT " .. id .. " " .. sid .. " nine-six closure", function()
            local c = F.new(H, root, { stream = id, history = sid, parity = false })
            local r = c.records[id]; F.history(H, r, sid)
            local before, native = F.baseline(c), natives(c)
            local owner = c.create_mace(); H.truthy(owner.construct(), owner.check())
            F.verify(H, c, owner, before); H.truthy(c.graph.intact(native))
            for _, parity in ipairs({ true, false }) do
                r.set_parity(parity); H.truthy(r.owner:reconcile("qa-real-Mace-parity"))
                F.history(H, r, sid); H.equal(owner.check(), nil)
            end
            H.truthy(r.owner:restore()); H.equal(#r.runtime.ledgers[F.family], 0)
            H.equal(r.runtime.active[F.family], nil); H.equal(owner.check(), nil)
            H.truthy(c.F.same(select(2, owner.template("mace_on_empire_sword")), (F.expected(c))))
        end)
    end end
    H.test("645 Mace late realWT discovery and pending checkbox preserve Current construction", function()
        local c = F.new(H, root)
        local owner = construct(c)
        local r = c.install("wt", "current", false)
        F.history(H, r, "current"); H.equal(owner.check(), nil)
        local native = natives(c)
        r.saved[F.setting] = "5_1_1"; r.mod.on_setting_changed(F.setting)
        H.equal(r.runtime.pending[F.setting], true)
        H.equal(r.runtime.boot_selections[F.setting], "current")
        r.mod.on_settings_batch_changed({ F.setting })
        H.truthy(c.graph.intact(native), "pending settings do not become applied source authority")
        H.equal(owner.check(), nil)
        local late = F.new(H, root)
        local custom = construct(late)
        local actual = late.install("wt_dev", "5_1_1", true)
        F.history(H, actual, "5_1_1"); H.equal(custom.check(), nil)
    end)
    H.test("645 Mace fullWT rejects filtered or tampered nonMace ledger rows", function()
        local mutations = {
            function(c, r) table.remove(r.runtime.ledgers[F.family], 1) end,
            function(c, r) r.runtime.ledgers[F.family][9].owner_object = {} end,
            function(c, r) r.runtime.ledgers[F.family][1].operation.expected_current = 999 end,
            function(c, r) r.runtime.ledgers[F.family][7].original_value = false end,
            function(c, r) r.runtime.boot_selections[F.setting] = "current" end,
            function(c) c.env.Weapons.one_handed_hammer_priest_template.block_angle = 91 end,
        }
        for _, mutate in ipairs(mutations) do
            local c = F.new(H, root, { history = "5_1_1" })
            local r = c.records.wt; F.history(H, r, "5_1_1")
            mutate(c, r)
            local before = c.F.snapshot(c)
            local owner = c.create_mace()
            H.equal(owner.construct(), false); H.truthy(owner.check())
            c.F.unchanged(H, c, before)
        end
    end)
    H.test("645 Mace refuses unknown599 snapshot and method authority without repairing donor", function()
        local mutations = {
            function(c) c.mhi_state.speed_snapshots[c.env.Weapons[MACE].actions.action_one.default].had_value = nil end,
            function(c) c.mhi_state.speed_snapshots[c.env.Weapons[MACE].actions.action_one.light_attack_left].value = .123 end,
            function(c) c.mhi_state.apply = function() end end,
            function(c) c.mhi_policy.MACE_SPEED_MULT = 1.10 end,
            function(c) c.env.Weapons[MACE].actions.action_one.default.anim_time_scale = 1 end,
        }
        for _, mutate in ipairs(mutations) do
            local c = F.new(H, root); mutate(c)
            local before, mhi = c.F.snapshot(c), assert(c.graph.capture(c.mhi_state, 8192, 131072))
            local owner = c.create_mace()
            H.equal(owner.construct(), false); H.truthy(owner.check())
            c.F.unchanged(H, c, before); H.truthy(c.graph.intact(mhi), "no producer-state repair")
        end
        for _, retained in ipairs({ false, true }) do
            for _, key in ipairs({ "apply", "ensure_cwv_dual_mace_template", "_balanced_profile",
                "state_identity", "policy_identity" }) do
                local c = F.new(H, root)
                local owner = retained and construct(c) or c.create_mace()
                if key == "state_identity" or key == "policy_identity" then
                    local field = key == "state_identity" and "mhi_state" or "mhi_policy"
                    local replacement = {}; for k, value in next, c[field] do replacement[k] = value end
                    c[field] = replacement -- Same values/functions are not the trusted private owner.
                else
                    c.mhi_state[key] = function() error("unknown599 method must never execute", 0) end
                end
                local before, mhi = c.F.snapshot(c), assert(c.graph.capture(c.mhi_state, 8192, 131072))
                H.equal(owner.construct(), false, "trusted599 owner/method replacement refuses before/after construction")
                H.equal(owner.template("mace_on_empire_sword"), nil)
                H.truthy(owner.check())
                c.F.unchanged(H, c, before)
                H.truthy(c.graph.intact(mhi), "owner/method refusal never repairs the producer")
            end
        end
    end)
    H.test("645 Mace known career install release remains actual canonical identity", function()
        local c = F.new(H, root)
        local owner = construct(c)
        local _, template = owner.template("mace_on_empire_sword")
        local canonical = { opaque_body_identity_only = true }
        c.env.ActionTemplates[CAREER] = canonical
        local careers = { qa_mace_actor = { activated_ability = { { action_name = CAREER } } } }
        for _, target in ipairs({ c.env.Weapons[MACE], c.env.Weapons[SWORD], template }) do
            local report = c.integration.install(target, { "qa_mace_actor" }, careers,
                c.env.ActionTemplates, "character_weapon_variants")
            H.equal(report.ok, true); H.equal(report.installed, 1)
            H.truthy(rawequal(target.actions[CAREER], canonical))
        end
        H.equal(owner.check(), nil, "existing typed career protocol, not a synthetic no-op")
        for _, target in ipairs({ c.env.Weapons[MACE], c.env.Weapons[SWORD], template }) do
            local report = c.integration.release(target, "character_weapon_variants")
            H.equal(#report.removed_names, 1); H.equal(#report.changed_names, 0)
            H.equal(target.actions[CAREER], nil)
        end
        H.equal(owner.check(), nil)
    end)
    H.test("645 Mace source or retained graph drift refuses without reconstruction", function()
        for _, mutation in ipairs({
            function(c, t) t.actions.action_one.light_attack_last.damage_profile = "light_blunt_smiter" end,
            function(c, t) t.actions.action_one.default.buff_data[1].external_multiplier = .123 end,
            function(c, t) c.env.Weapons[MACE].actions.action_one.default.total_time = .123 end,
            function(c, t) c.env.Weapons[SWORD].weapon_type = "MACE_1H" end,
            function(c, t) c.env.DamageProfileTemplates[F.prefix .. "medium_slashing_tank_1h_finesse"].targets[1].attack_template = "slashing_tank" end,
        }) do
            local c = F.new(H, root); local owner = construct(c)
            local _, template = owner.template("mace_on_empire_sword")
            mutation(c, template)
            local before = c.F.snapshot(c)
            H.equal(owner.template("mace_on_empire_sword"), nil)
            H.truthy(owner.check()); H.equal(owner.construct(), false)
            c.F.unchanged(H, c, before)
        end
    end)
    H.test("645 Mace every actual firstproducer write and readback fault rolls raw state back", function()
        local tags = {}
        local probe = F.new(H, root, { early = function(c)
            H.equal(c.state._cwv_wire_fallback_profile_id, nil, "genuine first-producer ordering")
            local owner = c.create_mace({ write = function(t, key, value, tag)
                tags[#tags + 1] = tag; rawset(t, key, value)
            end })
            H.truthy(owner.construct(), owner.check())
        end })
        H.equal(#tags, 30, "24 profile/index/source + template +3audit +generation +nilfallback")
        local distinct = {}; for _, tag in ipairs(tags) do H.equal(distinct[tag], nil); distinct[tag] = true end
        H.truthy(distinct.fallback)
        H.truthy(probe.state._cwv_wire_fallback_profile_id ~= nil)
        for _, mode in ipairs({ "write", "read" }) do for _, wanted in ipairs(tags) do
            local how, target = mode, wanted
            local result = F.new(H, root, { early = function(c, base)
                local before, reached, wrote = base.snapshot(c), 0, false
                local owner = c.create_mace({
                    write = function(t, key, value, tag)
                        rawset(t, key, value)
                        if tag == target then
                            H.truthy(rawequal(rawget(t, key), value), "actual destination reached after rawset")
                            wrote = true
                            if how == "write" then reached = reached + 1; error("qa-after-real-Mace-write", 0) end
                        end
                    end,
                    read = function(t, key, tag)
                        if how == "read" and wrote and tag == target then
                            reached = reached + 1; return {}
                        end
                        return rawget(t, key)
                    end,
                })
                H.equal(owner.construct(), false); H.truthy(owner.check())
                H.equal(reached, 1, "exact targeted attempted write/readback, not setup failure")
                base.unchanged(H, c, before)
                H.equal(rawget(c.state, "_cwv_wire_fallback_profile_id"), nil, "rollback restores raw absence")
            end })
            H.equal(result.env.Weapons[F.template], nil)
            H.truthy(result.state._cwv_wire_fallback_profile_id ~= nil, "later real Musket producer still publishes")
        end end
    end)
    H.test("645 Mace midcommit donor writer is preserved while owned publication rolls back", function()
        local c = F.new(H, root)
        local node, hit = c.env.Weapons[MACE].actions.action_one.default, 0
        local original, before = node.total_time, c.F.snapshot(c)
        local owner = c.create_mace({ write = function(t, key, value, tag)
            rawset(t, key, value)
            if tag == "template:" .. F.template then
                hit = hit + 1; H.truthy(rawequal(t, c.env.Weapons)); H.truthy(rawequal(rawget(t, key), value))
                node.total_time = .123 -- genuine intervening test-owned source write, not the constructor.
            end
        end })
        H.equal(owner.construct(), false); H.equal(hit, 1)
        H.equal(node.total_time, .123, "constructor must not repair/undo another writer")
        node.total_time = original -- test undoes ONLY its own interposition after proving preservation.
        c.F.unchanged(H, c, before)
    end)
end
