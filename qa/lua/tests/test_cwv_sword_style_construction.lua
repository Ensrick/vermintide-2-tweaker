-- Small first batch only. Not an activation/receiver/compiled-animation test.
return function(H, root)
    local F = assert(loadfile(root .. "/qa/lua/fixtures/cwv_sword_style_construction_harness.lua"))()
    local DIRECTIONS = { "empire_on_elf", "elven_on_empire" }
    local function native_snapshot(c)
        local profiles = {}
        for name, value in next, c.native_selected.DamageProfileTemplates do
            if rawget(c.env.DamageProfileTemplates, name) then profiles[name] = value end
        end
        return assert(c.graph.capture({ c.env.Weapons.one_handed_swords_template_1,
            c.env.Weapons.we_one_hand_sword_template_1, profiles, c.env.PowerLevelTemplates,
            c.env.ItemMasterList.es_1h_sword, c.env.ItemMasterList.we_1h_sword }, 8192, 65536))
    end
    for _, value in ipairs(DIRECTIONS) do
        local direction = value
        H.test("#645 " .. direction .. " complete native graph math speed callbacks physical identity", function()
            -- Native dump does not establish a C-global NONE. Preserve absent
            -- standalone input AND a disclosed nonnative opaque scalar exactly.
            local modes = direction == "elven_on_empire" and { {}, { none_sentinel = "qa-opaque-NONE" } } or { {} }
            for _, mode in ipairs(modes) do
            local c = F.new(H, root, mode); local native = native_snapshot(c)
            if direction == "elven_on_empire" then
                H.equal(rawget(c.env.Weapons.we_one_hand_sword_template_1.actions.action_one.heavy_attack_up,
                    "hit_mass_count"), mode.none_sentinel, "declared standalone/opaque NONE input is preserved")
            end
            local before = F.baseline(c); local owner = c.create(direction)
            H.truthy(owner.construct(), "actual current native constructor should succeed")
            F.verify(H, c, direction, owner, before)
            H.truthy(c.graph.intact(native), "native templates/profiles/power/physical IML remain exact")
            H.equal(c.loads._lib_network_lookup, 1); H.equal(c.loads._cwv_profile_graph_transaction, 1)
            H.equal(c.loads._cwv_core_templates, 1)
            H.equal(rawget(c.env.ItemMasterList, "cwv_645_empire_sword_style"), nil)
            H.equal(rawget(c.env.ItemMasterList, "cwv_645_elven_sword_style"), nil)
            end
        end)
    end
    H.test("#645 sequential directions retain actual core audit IDs fallback and no double modification", function()
        local c = F.new(H, root); local native = native_snapshot(c)
        local first = c.state._cwv_wire_fallback_profile_id
        for _, direction in ipairs(DIRECTIONS) do
            local before = F.baseline(c); local owner = c.create(direction)
            H.truthy(owner.construct()); F.verify(H, c, direction, owner, before)
            H.equal(c.state._cwv_wire_fallback_profile_id, first)
            local full, events = F.snapshot(c), #c.events
            H.truthy(owner.construct()); H.equal(#c.events, events); F.unchanged(H, c, full)
        end
        H.truthy(c.graph.intact(native))
        H.equal(c.owners.empire_on_elf.check(), nil); H.equal(c.owners.elven_on_empire.check(), nil)
    end)
    H.test("#645 genuine first producer fallback survives later actual Musket publishers", function()
        local c = F.new(H, root, { early_direction = "empire_on_elf" })
        local fallback = c.early_fallback
        H.equal(rawget(c.lookup, fallback), "medium_slashing_tank_1h_finesse")
        H.equal(c.state._cwv_wire_fallback_profile_id, fallback)
        H.equal(c.early_owner.check(), nil)
        H.truthy(c.action, "actual later Old Musket constructor still publishes its proven native/custom mode")
        H.truthy(c.state._cwv_damage_profile_generation > 8)
        H.equal(c.state._cwv_profile_multiplier_check(), nil)
    end)
    H.test("#645 real critical armor five six arrays reject target mixed sparse and push critical shapes", function()
        local mutations = {
            function(c) c.env.DamageProfileTemplates.medium_slashing_smiter_1h.critical_strike = {
                power_distribution = { attack = 1, impact = 1 } } end,
            function(c) c.env.DamageProfileTemplates.medium_slashing_smiter_1h.critical_strike.power_distribution = { attack = 1, impact = 1 } end,
            function(c) c.env.DamageProfileTemplates.medium_slashing_smiter_1h.critical_strike.impact_armor_power_modifer[6] = nil end,
            function(c) c.env.DamageProfileTemplates.medium_slashing_smiter_1h.critical_strike.attack_armor_power_modifer[2] = nil end,
            function(c) c.env.DamageProfileTemplates.medium_push.critical_strike = c.env.DamageProfileTemplates.medium_slashing_smiter_1h.critical_strike end,
        }
        for index, mutate in ipairs(mutations) do
            local c = F.new(H, root); mutate(c); local before = F.snapshot(c)
            local owner = c.create("elven_on_empire")
            H.equal(owner.construct(), false, "critical-shape denial " .. index)
            H.truthy(owner.check()); H.equal(owner.template("elven_on_empire"), nil); F.unchanged(H, c, before)
        end
    end)
    H.test("#645 foreign template profile lookup and source destinations are never adopted or overwritten", function()
        local mutations = {
            function(c, spec, foreign) c.env.Weapons[spec.template] = foreign end,
            function(c, spec, foreign) c.env.DamageProfileTemplates[spec.prefix .. "medium_slashing_tank_1h_finesse"] = foreign end,
            function(c, spec) c.lookup[spec.prefix .. "medium_slashing_tank_1h_finesse"] = 999 end,
            function(c, spec) c.state._cwv_damage_profile_wire_source[spec.prefix .. "medium_slashing_tank_1h_finesse"] = "foreign" end,
        }
        for index, mutate in ipairs(mutations) do
            local c = F.new(H, root); local spec, foreign = F.specs.empire_on_elf, {}
            mutate(c, spec, foreign); local before = F.snapshot(c)
            local owner = c.create("empire_on_elf")
            H.equal(owner.construct(), false, "foreign destination " .. index); F.unchanged(H, c, before)
            H.equal(owner.template("empire_on_elf"), nil); H.truthy(owner.check())
        end
    end)
    H.test("#645 attempted publication and bad readback rollback every reached journal class", function()
        local tags = { "profile:", "numeric:", "reverse:", "source:", "template:",
            "audit:profiles", "audit:comparisons", "audit:failure", "generation" }
        for _, tag in ipairs(tags) do
            for _, mode in ipairs({ "write", "readback" }) do
                local c = F.new(H, root); local before, hit = F.snapshot(c), 0
                local function matches(current) return current:sub(1, #tag) == tag end
                local options = {}
                if mode == "write" then options.write = function(t, key, value, current)
                    rawset(t, key, value)
                    if matches(current) then hit = hit + 1; error("injected attempted write " .. tag) end
                end else options.read = function(t, key, current)
                    if matches(current) then hit = hit + 1; return {} end
                    return rawget(t, key)
                end end
                local owner = c.create("empire_on_elf", options)
                H.equal(owner.construct(), false, tag .. " " .. mode); H.equal(hit, 1, "fault must reach exact real journal class")
                H.truthy(owner.check()); H.equal(owner.template("empire_on_elf"), nil); F.unchanged(H, c, before)
            end
        end
    end)
    H.test("#645 actual detached prepare detects intervening source mutation or raw root replacement", function()
        for _, mode in ipairs({ "source", "lookup" }) do
            local c = F.new(H, root); local before = F.snapshot(c)
            local action = c.env.Weapons.one_handed_swords_template_1.actions.action_one.heavy_attack_left
            local old_time, old_lookup, foreign = action.total_time, c.lookup, {}
            local hit = 0
            local actual_factory = c.core.detached_scalar_factory
            local owner = c.create("empire_on_elf", { scalar = function(settings)
                local planner = actual_factory(settings); local clone = planner.clone_damage_profile
                planner.clone_damage_profile = function(...)
                    local result = clone(...)
                    if hit == 0 then
                        hit = 1
                        if mode == "source" then action.total_time = old_time + 0.001
                        else c.env.NetworkLookup.damage_profiles = foreign end
                    end
                    return result
                end
                return planner
            end })
            H.equal(owner.construct(), false); H.equal(hit, 1); H.truthy(owner.check())
            H.equal(owner.template("empire_on_elf"), nil)
            if mode == "source" then
                H.equal(action.total_time, old_time + 0.001, "external writer must not be undone")
                action.total_time = old_time -- QA-only restore after preserving the external-write observation.
            else
                H.truthy(rawequal(c.env.NetworkLookup.damage_profiles, foreign), "foreign root must not be repaired")
                c.env.NetworkLookup.damage_profiles = old_lookup
            end
            F.unchanged(H, c, before)
        end
    end)
    for _, value in ipairs(DIRECTIONS) do
        local direction = value
        H.test("#645 named PowerLevel " .. direction .. " complete destinations native identities and no replay", function()
            local c = F.new(H, root, { named_profiles = true })
            local before = F.named_baseline(H, c, direction)
            local owner = c.create(direction)
            H.truthy(owner.construct(), "actual mixed native named constructor should succeed")
            F.verify_named(H, c, direction, owner, before)
            local complete, events = F.snapshot(c), #c.events
            H.truthy(owner.construct()); H.equal(#c.events, events)
            F.unchanged(H, c, complete)
        end)
        H.test("#645 named PowerLevel " .. direction .. " every real destination reached write and readback rollback", function()
            local reference = F.new(H, root, { named_profiles = true })
            local keys = F.named_plan(H, reference, direction).power_keys
            for _, key in ipairs(keys) do
                local destination = key
                for _, mode in ipairs({ "write", "readback" }) do
                    local c = F.new(H, root, { named_profiles = true })
                    local plan = F.named_plan(H, c, direction)
                    H.truthy(F.same(plan.power_keys, keys), "same sealed native destination set")
                    local expected = assert(plan.powers[destination])
                    local before, hit, tag = F.snapshot(c), 0, "power:" .. destination
                    local function reached(t, actual_key, value, current)
                        H.truthy(rawequal(t, c.env.PowerLevelTemplates), "fault reaches actual Power registry")
                        H.equal(actual_key, destination); H.equal(current, tag)
                        H.truthy(F.same(value, expected), "fault reaches complete real prepared Power row")
                        hit = hit + 1
                    end
                    local options = {}
                    if mode == "write" then options.write = function(t, actual_key, value, current)
                        if current == tag then
                            H.equal(rawget(t, actual_key), nil, "actual destination preimage nil")
                            rawset(t, actual_key, value)
                            H.truthy(rawequal(rawget(t, actual_key), value), "actual Power cell written before throw")
                            reached(t, actual_key, value, current)
                            error("injected reached Power write " .. destination)
                        end
                        rawset(t, actual_key, value)
                    end else options.read = function(t, actual_key, current)
                        if current == tag then
                            reached(t, actual_key, rawget(t, actual_key), current)
                            return {} -- corrupt only the readback, after proving the real publication.
                        end
                        return rawget(t, actual_key)
                    end end
                    local owner = c.create(direction, options)
                    H.equal(owner.construct(), false, "reached Power " .. mode)
                    H.equal(hit, 1, "each exact real Power destination fault reached once")
                    H.truthy(owner.check()); H.equal(owner.template(direction), nil)
                    F.unchanged(H, c, before) -- FULL roots: all new Power keys must be removed.
                end
            end
        end)
        H.test("#645 initial-nil fallback " .. direction .. " reached faults preserve later actual Musket publication", function()
            for _, mode in ipairs({ "write", "readback" }) do
                local c = F.new(H, root, { early_attempt = function(early)
                    H.equal(rawget(early.state, "_cwv_wire_fallback_profile_id"), nil, "genuine pre-Musket nil fallback")
                    local before, hit = F.snapshot(early), 0
                    local _, events = F.expected_template(early, direction)
                    local donor = assert(events[1][2])
                    local expected = assert(rawget(early.lookup, donor))
                    H.equal(rawget(early.lookup, expected), donor, "actual first native source pair")
                    local function reached(t, key, value, tag)
                        H.truthy(rawequal(t, early.state), "fault reaches actual fallback state")
                        H.equal(key, "_cwv_wire_fallback_profile_id"); H.equal(tag, "fallback")
                        H.equal(value, expected); H.equal(rawget(t, key), expected)
                        hit = hit + 1
                    end
                    local options = {}
                    if mode == "write" then options.write = function(t, key, value, tag)
                        if tag == "fallback" then
                            H.equal(rawget(t, key), nil, "fallback is still genuinely absent before write")
                            rawset(t, key, value); reached(t, key, value, tag)
                            error("injected reached nil-fallback write")
                        end
                        rawset(t, key, value)
                    end else options.read = function(t, key, tag)
                        if tag == "fallback" then reached(t, key, rawget(t, key), tag); return {} end
                        return rawget(t, key)
                    end end
                    local owner = early.create(direction, options)
                    H.equal(owner.construct(), false); H.equal(hit, 1, "exact nil-fallback fault reached once")
                    H.equal(rawget(early.state, "_cwv_wire_fallback_profile_id"), nil, "rollback restores raw absence")
                    H.truthy(owner.check()); H.equal(owner.template(direction), nil)
                    F.unchanged(H, early, before)
                    early.failed_sword_owner, early.failed_sword_generation = owner, early.state._cwv_damage_profile_generation
                end })
                -- The unchanged T.installed path now runs its REAL later Musket publisher.
                H.truthy(c.action); H.equal(c.action.damage_profile, "cwv_old_musket_shot")
                H.equal(c.capsule.check_old_musket(), nil)
                local native_id = assert(rawget(c.lookup, "shot_sniper"))
                H.equal(rawget(c.lookup, native_id), "shot_sniper")
                H.equal(rawget(c.state, "_cwv_wire_fallback_profile_id"), native_id)
                H.equal(rawget(c.state._cwv_damage_profile_wire_source, "cwv_old_musket_shot"), "shot_sniper")
                H.truthy(c.state._cwv_damage_profile_generation > c.failed_sword_generation)
                local after = F.snapshot(c)
                H.truthy(c.failed_sword_owner.check()); H.equal(c.failed_sword_owner.template(direction), nil)
                F.unchanged(H, c, after) -- observation must not erase/retry over later publication.
            end
        end)
    end
    require("test_cwv_sword_donor_envelope")(H, root, F)
end
