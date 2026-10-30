-- _cwv_mace_sword_construction.lua -- closed Mace graph on Kruber's Sword.
-- Literal Sword profiles/armor/target IDs at UNITY; no native finesse rewrite.
-- Actual typed #599/WT9/6/Sword/career source envelopes normalize only clones.
-- Uses existing private scalar audit and atomic journal. No movement lease,
-- activation, hook, resource load, item/persistence mutation or new wire schema.
-- Owned by: character_weapon_variants.lua. Consumed via the Mace family factory.
local M = {}
local function finite(value)
    return type(value) == "number" and value == value and value ~= math.huge and value ~= -math.huge
end
local function integer(value)
    return finite(value) and value >= 0 and value < 9007199254740991 and value % 1 == 0
end
local SPEC = {
    id = "mace_on_empire_sword", donor = "one_handed_hammer_template_1",
    template = "cwv_645_mace_sword_style", prefix = "cwv_645_mace_sword_",
    modifiers = { damage = 1, stagger = 1, cleave = 1 }, encounters = 9, profiles = 6,
    -- id, kind, Sword main/inner profile, Sword outer profile, Sword proxy,
    -- native Mace main/inner profile, native Mace outer profile.
    nodes = {
        { "default", "melee_start", nil, nil, "default" },
        { "default_right", "melee_start", nil, nil, "default_right" },
        { "default_left", "melee_start", nil, nil, "default_left" },
        { "default_last", "melee_start", nil, nil, "default_left" },
        { "heavy_attack_left", "sweep", "medium_slashing_tank_1h_finesse", nil, "heavy_attack_left", "medium_blunt_smiter_1h" },
        { "heavy_attack_right", "sweep", "medium_slashing_tank_1h_finesse", nil, "heavy_attack_right", "medium_blunt_smiter_1h" },
        { "light_attack_left", "sweep", "light_slashing_linesman_finesse", nil, "light_attack_left", "light_blunt_tank_diag" },
        { "light_attack_right", "sweep", "light_slashing_linesman_finesse", nil, "light_attack_right", "light_blunt_tank_diag" },
        { "light_attack_last", "sweep", "light_slashing_linesman_finesse", nil, "light_attack_left", "light_blunt_smiter" },
        { "light_attack_down", "sweep", "sword_1h_light_smiter_vertical", nil, "light_attack_last", "light_blunt_smiter" },
        { "light_attack_bopp", "sweep", "medium_slashing_linesman_finesse", nil, "light_attack_bopp", "light_blunt_tank" },
        { "push", "push_stagger", "medium_push", "light_push", "push", "medium_push", "light_push" },
    },
}
local SWORD = "one_handed_swords_template_1"
local CLAIMS, CLONE = "__vt2_tweaker_career_action_claims", "__vt2_tweaker_career_action_clone_source"
-- Exact accepted Sword fields only. Never replace Mace chains, callback
-- identities/absences, baked sweeps, events, timing or damage-window structure.
local PROJECTION = { "buff_data", "additional_critical_strike_chance", "hit_mass_count",
    "hit_effect", "impact_sound_event", "no_damage_impact_sound_event", "first_person_hit_anim",
    "hit_stop_anim", "hit_armor_anim", "hit_shield_stop_anim", "armor_impact_sound_event",
    "stagger_impact_sound_event", "no_damage_impact_particle_effect", "armour_impact_particle_effect",
    "impact_particle_effect", "additional_hit_effects" }
local PROFILE_FIELDS = { "cleave_distribution", "default_target", "targets", "critical_strike", "armor_modifier" }
local SCALED_FIELDS = { cleave_distribution = true, default_target = true, targets = true, critical_strike = true }
local HAND_FIELDS = { "damage_profile_left", "damage_profile_right", "damage_profile_inner_left",
    "damage_profile_inner_right", "damage_profile_outer_left", "damage_profile_outer_right" }

local function sources_for(spec)
    local result = {}
    for _, node in ipairs(spec.nodes) do
        if node[3] then result[node[3]] = node[2] end
        if node[4] then result[node[4]] = node[2] end
    end
    return result
end
local function resolved(profile, levels, key)
    local value = rawget(profile, key)
    return type(value) == "string" and rawget(levels, value) or value
end
local function target_shape(value)
    local power = type(value) == "table" and rawget(value, "power_distribution")
    return type(power) == "table" and finite(rawget(power, "attack")) and finite(rawget(power, "impact"))
end
local CRITICAL_IMPACT_COUNTS = {
    medium_slashing_tank_1h_finesse = 5, light_slashing_linesman_finesse = 5,
    sword_1h_light_smiter_vertical = 5, medium_slashing_linesman_finesse = 5,
}
local function armor_array(value, size)
    if type(value) ~= "table" or getmetatable(value) ~= nil then return false end
    local count = 0
    for key, number in next, value do
        if not integer(key) or key < 1 or key > size or not finite(number) then return false end
        count = count + 1
    end
    return count == size
end
local function critical_shape(value, impact_count)
    if type(value) ~= "table" or getmetatable(value) ~= nil or not impact_count then return false end
    local count = 0
    for key in next, value do
        if key ~= "attack_armor_power_modifer" and key ~= "impact_armor_power_modifer" then return false end
        count = count + 1
    end
    -- Native critical rows are armor multipliers, NOT target power rows.
    -- PL:441/872/1963/2331/3105/3581; smiter_M impact alone has SIX entries.
    return count == 2 and armor_array(rawget(value, "attack_armor_power_modifer"), 5)
        and armor_array(rawget(value, "impact_armor_power_modifer"), impact_count)
end
local function profile_shape(profile, levels, kind, name)
    if type(profile) ~= "table" or type(rawget(profile, "charge_value")) ~= "string" then return false end
    local cleave, target = resolved(profile, levels, "cleave_distribution"), resolved(profile, levels, "default_target")
    if type(cleave) ~= "table" or not finite(rawget(cleave, "attack")) or not finite(rawget(cleave, "impact"))
            or not target_shape(target) then return false end
    local critical, targets = resolved(profile, levels, "critical_strike"), resolved(profile, levels, "targets")
    if kind == "sweep" then
        if not critical_shape(critical, CRITICAL_IMPACT_COUNTS[name]) or type(targets) ~= "table" then return false end
    elseif critical ~= nil then return false end
    if targets ~= nil then
        if type(targets) ~= "table" then return false end
        for key, row in next, targets do
            if type(key) == "number" and not target_shape(row) then return false end
        end
    end
    return true
end

function M.bind(helper, graph, donor_envelope)
    local register = assert(helper and helper.register, "#645 canonical lookup helper missing")
    local capture, intact, disjoint, commit = assert(graph.capture), assert(graph.intact), assert(graph.disjoint), assert(graph.commit)
    -- This family has no native-only bypass for its actual #599/history owners.
    assert(type(donor_envelope) == "table", "#645 Mace donor envelope required")
    local envelope_snapshot
    if donor_envelope ~= nil then
        assert(type(donor_envelope) == "table" and getmetatable(donor_envelope) == nil, "#645 donor envelope invalid")
        for _, key in ipairs({ "capture", "intact", "prepare_clone", "capture_clone", "clone_intact" }) do
            assert(type(rawget(donor_envelope, key)) == "function", "#645 donor envelope method missing")
        end
        envelope_snapshot = assert(capture(donor_envelope, 32, 256), "#645 donor envelope unbounded")
    end
    local function envelope_ok() return donor_envelope ~= nil and intact(envelope_snapshot) end
    return function(options)
        local spec = options.direction == SPEC.id and SPEC
        assert(spec, "#645 construction direction unsupported")
        local profiles_for, levels_for, lookup_for, weapons_for = options.profiles, options.power_levels, options.lookup, options.weapons
        local state, clone, scalar = assert(options.state), assert(options.clone), assert(options.scalar_factory)
        local read, write = options.read or rawget, options.write or rawset
        local owned, failure
        local function pair(lookup, name, id)
            return integer(id) and id > 0 and rawget(lookup, name) == id and rawget(lookup, id) == name
        end
        local function roots(p)
            return rawequal(profiles_for(), p.profiles) and rawequal(levels_for(), p.levels)
                and rawequal(lookup_for(), p.lookup) and rawequal(weapons_for(), p.weapons)
                and rawequal(rawget(state, "_cwv_damage_profile_wire_source"), p.map)
                and rawequal(getmetatable(p.profiles), p.metas[1]) and rawequal(getmetatable(p.levels), p.metas[2])
                and rawequal(getmetatable(p.lookup), p.metas[3]) and rawequal(getmetatable(p.weapons), p.metas[4])
                and rawequal(getmetatable(p.map), p.metas[5])
        end
        local function retained(p)
            if not p or not roots(p) or not integer(rawget(state, "_cwv_damage_profile_generation"))
                    or rawget(state, "_cwv_damage_profile_generation") < p.generation
                    or rawget(state, "_cwv_wire_fallback_profile_id") ~= p.fallback then return false end
            for _, row in ipairs(p.templates) do
                if not rawequal(rawget(p.weapons, row.spec.donor), row.source)
                        or not rawequal(rawget(p.weapons, SWORD), row.sword_source)
                        or not rawequal(rawget(p.weapons, row.spec.template), row.template) or not envelope_ok() then return false end
                if row.envelope then
                    if not donor_envelope.intact(row.envelope) or not donor_envelope.clone_intact(row.clone_envelope) then return false end
                elseif not intact(row.source_snapshot) or not intact(row.snapshot) then return false end
            end
            for _, row in ipairs(p.donors) do
                if not rawequal(rawget(p.profiles, row.name), row.value) or not intact(row.snapshot)
                        or not pair(p.lookup, row.name, row.id) then return false end
            end
            for _, row in ipairs(p.custom) do
                if not rawequal(rawget(p.profiles, row.name), row.value) or not intact(row.snapshot)
                        or not pair(p.lookup, row.name, row.id) or rawget(p.map, row.name) ~= row.source then return false end
            end
            for _, row in ipairs(p.power) do
                if not rawequal(rawget(p.levels, row.name), row.value) or not intact(row.snapshot) then return false end
            end
            return true
        end
        local function construct()
            local profiles, levels, lookup, weapons = profiles_for(), levels_for(), lookup_for(), weapons_for()
            local map, generation, first = rawget(state, "_cwv_damage_profile_wire_source"),
                rawget(state, "_cwv_damage_profile_generation"), rawget(state, "_cwv_wire_fallback_profile_id")
            assert(type(profiles) == "table" and type(levels) == "table" and type(lookup) == "table"
                and type(weapons) == "table" and type(map) == "table" and integer(generation)
                and generation <= 9007199254740973, "#645 source roots/generation unproven")
            local proof = { profiles = profiles, levels = levels, lookup = lookup, weapons = weapons, map = map,
                metas = { getmetatable(profiles), getmetatable(levels), getmetatable(lookup), getmetatable(weapons), getmetatable(map) },
                templates = {}, donors = {}, custom = {}, power = {}, detached = {}, generation = generation + spec.encounters, fallback = first }
            local map_before = assert(capture(map, 2048, 8192), "#645 source-map graph unproven")
            if first ~= nil then
                local name = rawget(lookup, first)
                assert(type(name) == "string" and name:sub(1, 4) ~= "cwv_" and pair(lookup, name, first)
                    and type(rawget(profiles, name)) == "table", "#645 existing fallback unproven")
            end
            local changes, all_events = {}, 0
            local function stage(t, key, value, tag, before)
                changes[#changes + 1] = { t, key, value, tag, before = before }
            end
            local function native_unchanged()
                assert(roots(proof) and intact(map_before), "#645 root/source-map preimage changed")
                assert(rawget(state, "_cwv_damage_profile_generation") == generation
                    and rawget(state, "_cwv_wire_fallback_profile_id") == first, "#645 source scalar preimage changed")
                for _, row in ipairs(proof.templates) do
                    -- Exact full source preimage is STILL required through commit.
                    assert(rawequal(rawget(weapons, row.spec.donor), row.source) and intact(row.source_snapshot)
                        and rawequal(rawget(weapons, SWORD), row.sword_source) and intact(row.sword_snapshot)
                        and envelope_ok() and (not row.envelope or donor_envelope.intact(row.envelope)), "#645 native template changed")
                end
                for _, row in ipairs(proof.donors) do
                    assert(rawequal(rawget(profiles, row.name), row.value) and intact(row.snapshot)
                        and pair(lookup, row.name, row.id), "#645 native profile/pair changed")
                end
                for _, row in ipairs(proof.power) do
                    if row.native then assert(rawequal(rawget(levels, row.name), row.value) and intact(row.snapshot), "#645 native power changed") end
                end
                for _, snapshot in ipairs(proof.detached) do assert(intact(snapshot), "#645 detached source changed during prepare") end
            end
            local detached_lookup = {}; for key, value in next, lookup do detached_lookup[key] = value end
            local initial_max = #lookup
            do
                local source, sword_source = rawget(weapons, spec.donor), rawget(weapons, SWORD)
                assert(type(source) == "table" and type(sword_source) == "table"
                    and rawget(weapons, spec.template) == nil, "#645 donor missing/foreign template")
                local source_snapshot = assert(capture(source, 4096, 32768), "#645 Mace graph exceeds bound")
                local sword_snapshot = assert(capture(sword_source, 4096, 32768), "#645 Sword graph exceeds bound")
                assert(envelope_ok(), "#645 donor envelope changed")
                local source_envelope = assert(donor_envelope.capture(weapons), "#645 actual producer authority unproven")
                local mace_clone, template = clone(source), clone(sword_source)
                assert(disjoint(source_snapshot, capture(mace_clone, 4096, 32768))
                    and disjoint(sword_snapshot, capture(template, 4096, 32768)), "#645 source clone aliases native")
                local template_row = { spec = spec, source = source, source_snapshot = source_snapshot,
                    sword_source = sword_source, sword_snapshot = sword_snapshot,
                    template = template, envelope = source_envelope }
                proof.templates[#proof.templates + 1] = template_row
                local token = spec.template .. "<-" .. spec.donor
                assert(donor_envelope.prepare_clone(source_envelope, mace_clone, template, token) == true,
                    "#645 detached Current normalization rejected")
                local native_actions, mace_actions, sword_actions =
                    rawget(source, "actions"), rawget(mace_clone, "actions"), rawget(template, "actions")
                local native_group = type(native_actions) == "table" and rawget(native_actions, "action_one")
                local group = type(mace_actions) == "table" and rawget(mace_actions, "action_one")
                local proxies = type(sword_actions) == "table" and rawget(sword_actions, "action_one")
                assert(type(native_group) == "table" and type(group) == "table"
                    and type(proxies) == "table", "#645 complete source action groups missing")
                local function project(action, proxy)
                    for _, field in ipairs(PROJECTION) do
                        local value = rawget(proxy, field)
                        if type(value) == "table" then value = clone(value) end
                        rawset(action, field, value)
                    end
                end
                local source_names, detached_profiles, detached_levels, native_power, destinations = sources_for(spec), {}, {}, {}, {}
                local donor_by_name, custom_by_name = {}, {}
                local expected_nodes = {}; for _, row in ipairs(spec.nodes) do expected_nodes[row[1]] = true end
                local node_count = 0
                for name, node in next, native_group do
                    assert(expected_nodes[name] and type(node) == "table", "#645 unexpected action_one node")
                    node_count = node_count + 1
                end
                assert(node_count == #spec.nodes, "#645 incomplete action_one graph")
                for name, kind in next, source_names do
                    local profile, id = rawget(profiles, name), rawget(lookup, name)
                    local existing, inserted = register(detached_lookup, name)
                    assert(profile_shape(profile, levels, kind, name) and pair(lookup, name, id) and existing == id and not inserted,
                        "#645 native profile shape/pair unproven: " .. name)
                    assert(rawget(profiles, spec.prefix .. name) == nil and rawget(lookup, spec.prefix .. name) == nil
                        and rawget(map, spec.prefix .. name) == nil, "#645 foreign profile destination")
                    local snapshot = assert(capture(profile, 256, 2048), "#645 native profile graph unproven")
                    local copied = clone(profile)
                    local copied_snapshot = capture(copied, 256, 2048)
                    assert(copied_snapshot and disjoint(snapshot, copied_snapshot), "#645 detached profile aliases native")
                    proof.detached[#proof.detached + 1] = copied_snapshot
                    detached_profiles[name] = copied
                    local row = { name = name, value = profile, snapshot = snapshot, id = id }
                    proof.donors[#proof.donors + 1], donor_by_name[name] = row, row
                    for _, field in ipairs(PROFILE_FIELDS) do
                        local reference = rawget(profile, field)
                        if type(reference) == "string" and not native_power[reference] then
                            local value = rawget(levels, reference)
                            local power_snapshot = type(value) == "table" and capture(value, 256, 2048)
                            assert(power_snapshot, "#645 named power source missing")
                            native_power[reference] = true
                            proof.power[#proof.power + 1] = { name = reference, value = value, snapshot = power_snapshot, native = true }
                            detached_levels[reference] = clone(value)
                            local copied_snapshot = capture(detached_levels[reference], 256, 2048)
                            assert(copied_snapshot and disjoint(power_snapshot, copied_snapshot), "#645 detached power aliases native")
                            proof.detached[#proof.detached + 1] = copied_snapshot
                        end
                        if type(reference) == "string" and SCALED_FIELDS[field] then
                            local key = spec.prefix .. reference
                            assert(rawget(levels, key) == nil, "#645 foreign power destination")
                            destinations[key] = true
                        end
                    end
                end
                local events = 0
                local planner = scalar({ profiles = detached_profiles, power_levels = detached_levels,
                    record_source = function(name, donor)
                        assert(source_names[donor] and name == spec.prefix .. donor, "#645 source axis changed")
                        events, all_events = events + 1, all_events + 1
                        if proof.fallback == nil then proof.fallback = donor_by_name[donor].id end
                    end,
                    register = function(name, value)
                        local donor = name:sub(#spec.prefix + 1)
                        assert(source_names[donor] and name == spec.prefix .. donor and not custom_by_name[donor], "#645 publication axis changed")
                        local id, inserted = register(detached_lookup, name)
                        local snapshot = capture(value, 256, 2048)
                        assert(inserted and integer(id) and id > initial_max and snapshot
                            and disjoint(donor_by_name[donor].snapshot, snapshot), "#645 custom profile append unproven")
                        detached_profiles[name], custom_by_name[donor] = value, true
                        proof.custom[#proof.custom + 1] = { name = name, source = donor, id = id, value = value, snapshot = snapshot }
                        stage(profiles, name, value, "profile:" .. name)
                        stage(lookup, id, name, "numeric:" .. name)
                        stage(lookup, name, id, "reverse:" .. name)
                        stage(map, name, donor, "source:" .. name)
                        return true
                    end })
                -- Keep exact native Mace cadence, including absent charge scales.
                -- #599 normalization was SOURCE-qualified, never a blind division.
                local clone_profile = assert(planner.clone_damage_profile)
                for _, row in ipairs(spec.nodes) do
                    local action, original, proxy = rawget(group, row[1]),
                        rawget(native_group, row[1]), rawget(proxies, row[5])
                    assert(type(action) == "table" and type(original) == "table" and type(proxy) == "table"
                        and getmetatable(original) == nil and getmetatable(action) == nil
                        and rawget(original, "kind") == row[2] and rawget(action, "kind") == row[2]
                        and rawget(proxy, "kind") == row[2], "#645 exact source/proxy node unproven")
                    for _, field in ipairs(HAND_FIELDS) do assert(rawget(original, field) == nil, "#645 unsupported hand profile") end
                    local speed = rawget(action, "anim_time_scale")
                    assert(speed == nil or finite(speed) and speed > 0, "#645 normalized native timing unproven")
                    project(action, proxy)
                    if row[2] == "sweep" then
                        assert(rawget(original, "damage_profile") == row[6]
                            and rawget(action, "damage_profile") == row[6]
                            and rawget(proxy, "damage_profile") == row[3], "#645 exact profile projection changed")
                        rawset(action, "damage_profile", clone_profile(row[3], spec.prefix, spec.modifiers))
                        assert(rawget(original, "damage_profile_inner") == nil
                            and rawget(original, "damage_profile_outer") == nil, "#645 foreign sweep axis")
                    elseif row[2] == "push_stagger" then
                        assert(rawget(original, "damage_profile_inner") == row[6]
                            and rawget(original, "damage_profile_outer") == row[7]
                            and rawget(proxy, "damage_profile_inner") == row[3]
                            and rawget(proxy, "damage_profile_outer") == row[4], "#645 exact push axes changed")
                        rawset(action, "damage_profile_inner", clone_profile(row[3], spec.prefix, spec.modifiers))
                        rawset(action, "damage_profile_outer", clone_profile(row[4], spec.prefix, spec.modifiers))
                        rawset(action, "attack_template", rawget(proxy, "attack_template"))
                        assert(rawget(original, "damage_profile") == nil, "#645 foreign push main profile")
                    else
                        assert(rawget(original, "damage_profile") == nil
                            and rawget(original, "damage_profile_inner") == nil
                            and rawget(original, "damage_profile_outer") == nil, "#645 foreign charge profile")
                    end
                end
                local block = type(rawget(mace_actions, "action_two")) == "table" and rawget(mace_actions.action_two, "default")
                local block_proxy = type(rawget(sword_actions, "action_two")) == "table" and rawget(sword_actions.action_two, "default")
                assert(type(block) == "table" and type(block_proxy) == "table"
                    and rawget(block, "kind") == "block" and rawget(block_proxy, "kind") == "block", "#645 block source/proxy missing")
                project(block, block_proxy)
                rawset(template, "actions", mace_actions)
                rawset(template, "state_machine", rawget(mace_clone, "state_machine"))
                rawset(template, "wield_anim", rawget(mace_clone, "wield_anim"))
                rawset(template, CLAIMS, rawget(mace_clone, CLAIMS))
                rawset(template, CLONE, rawget(mace_clone, CLONE))
                local count = 0; for _ in next, custom_by_name do count = count + 1 end
                assert(events == spec.encounters and count == spec.profiles and planner.check() == nil, "#645 scalar count/audit rejected")
                for key in next, destinations do
                    local value = rawget(detached_levels, key)
                    assert(type(value) == "table" and rawget(levels, key) == nil, "#645 prepared power collision/missing row")
                    local snapshot = assert(capture(value, 256, 2048), "#645 prepared power graph unproven")
                    proof.power[#proof.power + 1] = { name = key, value = value, snapshot = snapshot }
                    stage(levels, key, value, "power:" .. key)
                end
                template_row.snapshot = assert(capture(template, 4096, 32768), "#645 prepared template graph unproven")
                if source_envelope then
                    template_row.clone_envelope = assert(donor_envelope.capture_clone(source_envelope, template, token), "#645 clone producer envelope unproven")
                end
                stage(weapons, spec.template, template, "template:" .. spec.template)
                assert(planner.append_live_audit_changes(changes) == true, "#645 private audit handoff rejected")
            end
            assert(all_events == spec.encounters, "#645 complete encounter count changed")
            stage(state, "_cwv_damage_profile_generation", proof.generation, "generation", generation)
            if first == nil then stage(state, "_cwv_wire_fallback_profile_id", proof.fallback, "fallback") end
            assert(commit(changes, native_unchanged, function()
                -- Typed lifetime transitions are not permission for mid-commit drift.
                for _, row in ipairs(proof.templates) do
                    assert(intact(row.source_snapshot) and intact(row.sword_snapshot) and intact(row.snapshot), "#645 publication graph changed")
                end
                assert(rawget(state, "_cwv_damage_profile_generation") == proof.generation and retained(proof), "#645 family readback rejected")
            end, read, write), "#645 construction transaction rejected")
            owned, failure = proof, nil
            return true
        end
        local C = {}
        function C.construct()
            if owned then local ok, result = pcall(retained, owned); return ok and result == true end
            local ok, result = pcall(construct)
            if ok and result == true then return true end
            failure = tostring(result)
            return false
        end
        function C.template(direction)
            local ok, ready = pcall(retained, owned)
            if not ok or not ready then return nil end
            for _, row in ipairs(owned.templates) do if row.spec.id == direction then return row.spec.template, row.template end end
        end
        function C.check()
            local ok, ready = pcall(retained, owned)
            if not ok or not ready then return failure or "#645 constructed donor proof missing/drifted" end
        end
        return C
    end
end
return M
