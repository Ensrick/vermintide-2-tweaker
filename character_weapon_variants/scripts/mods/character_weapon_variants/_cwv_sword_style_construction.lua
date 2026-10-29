-- _cwv_sword_style_construction.lua -- Closed reciprocal 1h Sword construction.
--
-- Source-preparation ONLY: no manifest/call site or Combat Style is activated.
-- Defines two closed directions; each private instance owns ONE complete donor
-- clone/profile transaction, including ONE private core audit contribution.
-- The existing private core scalar factory owns all damage/stagger/cleave math;
-- the existing graph journal owns attempted-write/readback rollback. No item,
-- native template/profile, resource, hook, persistence or wire schema is changed.
-- Owned by: character_weapon_variants.lua entry point (future reviewed binding).
-- Consumed via: one intended manifest load/private core-return handoff; NOT loaded now.
local M = {}
local function finite(value)
    return type(value) == "number" and value == value and value ~= math.huge and value ~= -math.huge
end
local function integer(value)
    return finite(value) and value >= 0 and value < 9007199254740991 and value % 1 == 0
end
local EMPIRE = {
    id = "empire_on_elf", donor = "one_handed_swords_template_1",
    template = "cwv_645_empire_sword_style", prefix = "cwv_645_empire_sword_",
    speed = 1.10, modifiers = { damage = 1, stagger = 0.90, cleave = 0.90 },
    encounters = 8, profiles = 6,
    nodes = {
        { "default", "melee_start" }, { "default_right", "melee_start" }, { "default_left", "melee_start" },
        { "heavy_attack_left", "sweep", "medium_slashing_tank_1h_finesse" },
        { "heavy_attack_right", "sweep", "medium_slashing_tank_1h_finesse" },
        { "light_attack_left", "sweep", "light_slashing_linesman_finesse" },
        { "light_attack_right", "sweep", "light_slashing_linesman_finesse" },
        { "light_attack_last", "sweep", "sword_1h_light_smiter_vertical" },
        { "light_attack_bopp", "sweep", "medium_slashing_linesman_finesse" },
        { "push", "push_stagger", "medium_push", "light_push" },
    },
}
local ELVEN = {
    id = "elven_on_empire", donor = "we_one_hand_sword_template_1",
    template = "cwv_645_elven_sword_style", prefix = "cwv_645_elven_sword_",
    speed = 0.90, modifiers = { damage = 1, stagger = 1.10, cleave = 1.10 },
    encounters = 9, profiles = 6,
    nodes = {
        { "default", "melee_start" }, { "default_right", "melee_start" }, { "default_left", "melee_start" },
        { "heavy_attack_left", "sweep", "medium_slashing_smiter_1h" },
        { "heavy_attack_right", "sweep", "medium_slashing_smiter_1h" },
        { "heavy_attack_up", "sweep", "medium_slashing_tank_1h_finesse" },
        { "light_attack_left", "sweep", "light_slashing_linesman_elf" },
        { "light_attack_right", "sweep", "light_slashing_linesman_elf" },
        { "light_attack_last", "sweep", "light_slashing_smiter_stab_swords" },
        { "light_attack_bopp", "sweep", "light_slashing_linesman_elf" },
        { "push", "push_stagger", "medium_push", "light_push" },
    },
}
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
    medium_slashing_smiter_1h = 6, light_slashing_linesman_elf = 5,
    light_slashing_smiter_stab_swords = 5,
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
    -- Optional typed integration only; omitted preserves the frozen native-only path.
    local envelope_snapshot
    if donor_envelope ~= nil then
        assert(type(donor_envelope) == "table" and getmetatable(donor_envelope) == nil, "#645 donor envelope invalid")
        for _, key in ipairs({ "capture", "intact", "prepare_clone", "source_axis", "capture_clone", "clone_intact" }) do
            assert(type(rawget(donor_envelope, key)) == "function", "#645 donor envelope method missing")
        end
        envelope_snapshot = assert(capture(donor_envelope, 32, 256), "#645 donor envelope unbounded")
    end
    local function envelope_ok() return donor_envelope == nil or intact(envelope_snapshot) end
    return function(options)
        local spec = options.direction == EMPIRE.id and EMPIRE or options.direction == ELVEN.id and ELVEN
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
                local source = rawget(weapons, spec.donor)
                assert(type(source) == "table" and rawget(weapons, spec.template) == nil, "#645 donor missing/foreign template")
                local source_snapshot = assert(capture(source, 4096, 32768), "#645 donor graph exceeds bound")
                assert(envelope_ok(), "#645 donor envelope changed")
                local source_envelope = donor_envelope and donor_envelope.capture(source, weapons, spec.id)
                assert(donor_envelope == nil or source_envelope, "#645 donor producer authority unproven")
                local template = clone(source)
                assert(disjoint(source_snapshot, capture(template, 4096, 32768)), "#645 donor clone aliases source")
                local template_row = { spec = spec, source = source, source_snapshot = source_snapshot, template = template, envelope = source_envelope }
                proof.templates[#proof.templates + 1] = template_row
                local token = spec.template .. "<-" .. spec.donor
                if source_envelope then
                    assert(donor_envelope.prepare_clone(source_envelope, template, token) == true, "#645 detached Current normalization rejected")
                end
                local function source_axis(node, key, expected)
                    if source_envelope then return donor_envelope.source_axis(source_envelope, node, key, expected) == true end
                    return rawget(node, key) == expected
                end
                local native_group, group = rawget(source, "actions"), rawget(template, "actions")
                native_group = type(native_group) == "table" and rawget(native_group, "action_one")
                group = type(group) == "table" and rawget(group, "action_one")
                assert(type(native_group) == "table" and type(group) == "table", "#645 action_one missing")
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
                -- Native ActionUtils:538-539 uses implicit 1, not 'leave absent'.
                -- Only these closed action_one attack-chain nodes are changed;
                -- block, inspect, wield, buff windows, chains and baked sweeps stay exact.
                local clone_profile = assert(planner.clone_damage_profile)
                for _, row in ipairs(spec.nodes) do
                    local action, original = rawget(group, row[1]), rawget(native_group, row[1])
                    assert(type(action) == "table" and type(original) == "table" and getmetatable(original) == nil
                        and getmetatable(action) == nil and rawget(original, "kind") == row[2]
                        and rawget(action, "kind") == row[2], "#645 exact action node unproven")
                    for _, field in ipairs(HAND_FIELDS) do assert(rawget(original, field) == nil, "#645 unsupported per-hand profile") end
                    if row[2] ~= "sweep" then assert(rawget(original, "damage_profile") == nil, "#645 unexpected main profile") end
                    if row[2] ~= "push_stagger" then
                        assert(rawget(original, "damage_profile_inner") == nil and rawget(original, "damage_profile_outer") == nil, "#645 unexpected push profile")
                    end
                    local speed = rawget(original, "anim_time_scale")
                    assert(speed == nil or finite(speed) and speed > 0, "#645 action speed source unproven")
                    assert(rawget(action, "anim_time_scale") == speed, "#645 detached action speed changed")
                    rawset(action, "anim_time_scale", (speed or 1) * spec.speed)
                    if row[2] == "sweep" then
                        assert(source_axis(original, "damage_profile", row[3]), "#645 sweep donor axis changed")
                        rawset(action, "damage_profile", clone_profile(row[3], spec.prefix, spec.modifiers))
                    elseif row[2] == "push_stagger" then
                        assert(source_axis(original, "damage_profile_inner", row[3]) and source_axis(original, "damage_profile_outer", row[4]), "#645 push donor axis changed")
                        rawset(action, "damage_profile_inner", clone_profile(row[3], spec.prefix, spec.modifiers))
                        rawset(action, "damage_profile_outer", clone_profile(row[4], spec.prefix, spec.modifiers))
                    end
                end
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
                    assert(intact(row.source_snapshot) and intact(row.snapshot), "#645 publication graph changed")
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
