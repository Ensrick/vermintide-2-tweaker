-- _cwv_shortsword_construction_owner.lua -- Atomic closed Shortsword family.
--
-- Owns five scalar profiles/seven source encounters, prepared dagger template,
-- and private core audit contribution. Graph/lookup/scalar mechanics are injected
-- once; no donor math, registry repair, native fallback or engine hook lives here.
-- Owned by: character_weapon_variants.lua entry point.
-- Consumed via: one manifest load and private by-value core/bootstrap handoff.
local M = {}
local TEMPLATE, DONOR, PREFIX = "shortsword_template", "one_handed_daggers_template_1", "cwv_shortsword_"
local SOURCES = { medium_slashing_linesman = true, medium_slashing_smiter_stab = true,
    light_fencer_stab = true, dagger_1h_light_linesman = true, dagger_1h_light_smiter_stab = true }
local function integer(value)
    return type(value) == "number" and value == value and value >= 0
        and value < 9007199254740991 and value % 1 == 0
end
local function finite(value)
    return type(value) == "number" and value == value and value ~= math.huge and value ~= -math.huge
end
local function profile_shape(profile, levels)
    if type(profile) ~= "table" or type(rawget(profile, "charge_value")) ~= "string" then return false end
    local function field(key)
        local value = rawget(profile, key)
        return type(value) == "string" and rawget(levels, value) or value
    end
    local target, cleave = field("default_target"), field("cleave_distribution")
    if type(target) ~= "table" or type(cleave) ~= "table" or not finite(rawget(cleave, "attack"))
            or not finite(rawget(cleave, "impact")) or type(field("targets")) ~= "table" then return false end
    local power = rawget(target, "power_distribution")
    return type(power) == "table" and finite(rawget(power, "attack")) and finite(rawget(power, "impact"))
end
function M.bind(helper, mechanics, envelope)
    local register = assert(helper and helper.register, "Shortsword lookup helper missing")
    local capture, intact, disjoint, commit = assert(mechanics.capture), assert(mechanics.intact),
        assert(mechanics.disjoint), assert(mechanics.commit)
    local career_capture, career_intact = assert(envelope.capture), assert(envelope.intact)
    return function(options)
        local profiles_for, levels_for, lookup_for, weapons_for = options.profiles, options.power_levels, options.lookup, options.weapons
        local state, clone, scalar = assert(options.state), assert(options.clone), assert(options.scalar_factory)
        local read, write = options.read or rawget, options.write or rawset
        local owned, failure = nil, "not_constructed"
        local function pair(lookup, name, id)
            return integer(id) and id > 0 and rawget(lookup, name) == id and rawget(lookup, id) == name
        end
        local function retained(p)
            if not p or profiles_for() ~= p.profiles or levels_for() ~= p.levels or lookup_for() ~= p.lookup or weapons_for() ~= p.weapons
                    or rawget(p.weapons, DONOR) ~= p.source or rawget(p.weapons, TEMPLATE) ~= p.template
                    or not career_intact(p.source_snapshot) or not career_intact(p.template_snapshot)
                    or rawget(state, "_cwv_damage_profile_wire_source") ~= p.map
                    or not integer(rawget(state, "_cwv_damage_profile_generation"))
                    or rawget(state, "_cwv_damage_profile_generation") < p.generation
                    or rawget(state, "_cwv_wire_fallback_profile_id") ~= p.fallback then return false end
            for name, meta in next, p.metas do
                if getmetatable(p[name]) ~= meta.value then return false end
            end
            for name, donor in next, p.donors do
                local selected = p.custom[name]
                if rawget(p.profiles, name) ~= donor.profile or not intact(donor.snapshot) or not pair(p.lookup, name, donor.id)
                        or rawget(p.profiles, PREFIX .. name) ~= selected.profile or not intact(selected.snapshot)
                        or not pair(p.lookup, PREFIX .. name, selected.id) or rawget(p.map, PREFIX .. name) ~= name then return false end
            end
            for _, row in ipairs(p.power) do
                if rawget(p.levels, row.key) ~= row.value or not intact(row.snapshot) then return false end
            end
            return true
        end
        local function construct(prepare)
            local profiles, levels, lookup, weapons = profiles_for(), levels_for(), lookup_for(), weapons_for()
            local map, generation, first = rawget(state, "_cwv_damage_profile_wire_source"),
                rawget(state, "_cwv_damage_profile_generation"), rawget(state, "_cwv_wire_fallback_profile_id")
            if type(profiles) ~= "table" or type(levels) ~= "table" or type(lookup) ~= "table" or type(weapons) ~= "table"
                    or type(map) ~= "table" or not integer(generation) or generation > 9007199254740983
                    or type(prepare) ~= "function" then return false, "source_roots_unproven" end
            local source = rawget(weapons, DONOR)
            if type(source) ~= "table" or rawget(weapons, TEMPLATE) ~= nil then return false, "template_source_or_foreign" end
            local source_before, map_before = capture(source, 4096, 32768), capture(map, 2048, 8192)
            local source_snapshot = career_capture(source, { role = "source" })
            if not source_snapshot or not map_before then return false, "source_graph_unproven" end
            local metas = {}
            for name, value in next, { profiles = profiles, levels = levels, lookup = lookup, weapons = weapons, map = map } do
                metas[name] = { value = getmetatable(value) }
            end
            local detached_profiles, detached_levels, detached_lookup, donors, power, destinations = {}, {}, {}, {}, {}, {}
            for key, value in next, lookup do detached_lookup[key] = value end
            local initial_max = #detached_lookup
            if first ~= nil then
                local name = rawget(lookup, first)
                if type(name) ~= "string" or name:sub(1, 4) == "cwv_" or not pair(lookup, name, first)
                        or type(rawget(profiles, name)) ~= "table" then return false, "first_fallback_unproven" end
            end
            for name in next, SOURCES do
                local profile, id = rawget(profiles, name), rawget(lookup, name)
                local checked, inserted = register(detached_lookup, name)
                if not profile_shape(profile, levels) or not pair(lookup, name, id) or checked ~= id or inserted then return false, "native_profile_or_pair_unproven" end
                local snapshot = capture(profile, 256, 2048)
                if not snapshot then return false, "native_profile_graph_unproven" end
                if rawget(profiles, PREFIX .. name) ~= nil or rawget(lookup, PREFIX .. name) ~= nil
                        or rawget(map, PREFIX .. name) ~= nil then return false, "foreign_custom_state" end
                local detached = clone(profile)
                local prepared = capture(detached, 256, 2048)
                if not prepared or not disjoint(snapshot, prepared) then return false, "detached_donor_alias" end
                donors[name] = { profile = profile, snapshot = snapshot, id = id, prepared_snapshot = prepared }
                detached_profiles[name] = detached
                for _, key in ipairs({ "cleave_distribution", "default_target", "targets", "critical_strike" }) do
                    local reference = rawget(profile, key)
                    if type(reference) == "string" then
                        local value = rawget(levels, reference)
                        if type(value) ~= "table" or rawget(levels, PREFIX .. reference) ~= nil then return false, "power_reference_unproven" end
                        if detached_levels[reference] == nil then
                            local snapshot, copied = capture(value, 256, 2048), clone(value)
                            local copied_snapshot = capture(copied, 256, 2048)
                            if not snapshot or not copied_snapshot or not disjoint(snapshot, copied_snapshot) then return false, "detached_power_alias" end
                            detached_levels[reference] = copied
                            destinations[#destinations + 1] = { key = PREFIX .. reference, before = nil }
                            power[#power + 1] = { key = reference, value = value, snapshot = snapshot, prepared_snapshot = copied_snapshot }
                        end
                    end
                end
            end
            local changes, events, custom, captured_first = {}, {}, {}, first
            -- Every newly owned destination was proved absent BEFORE preparation.
            -- Never adopt a callback's intervening value as a rollback preimage.
            local function stage(t, key, value, tag, before)
                changes[#changes + 1] = { t, key, value, tag, before = before }
            end
            local function record(name, donor)
                assert(SOURCES[donor] and name == PREFIX .. donor, "Shortsword source axis changed")
                events[#events + 1] = { name, donor }
                if first == nil then first = donors[donor].id end
            end
            local function publish(name, profile)
                local donor = name:sub(#PREFIX + 1)
                assert(SOURCES[donor] and not custom[donor], "Shortsword publication axis changed")
                local id, inserted = register(detached_lookup, name)
                assert(integer(id) and inserted and id > initial_max, "Shortsword paired append rejected")
                local snapshot = capture(profile, 256, 2048)
                assert(snapshot and disjoint(donors[donor].snapshot, snapshot), "Shortsword profile aliases source")
                detached_profiles[name] = profile
                custom[donor] = { profile = profile, snapshot = snapshot, id = id }
                stage(map, name, donor, "source:" .. donor)
                stage(profiles, name, profile, "profile:" .. donor)
                stage(lookup, id, name, "numeric:" .. donor)
                stage(lookup, name, id, "reverse:" .. donor)
                return true
            end
            local planner = scalar({ profiles = detached_profiles, power_levels = detached_levels, record_source = record, register = publish })
            local clone_scalar, check_scalar, append_audit = assert(planner.clone_damage_profile), assert(planner.check),
                assert(planner.append_live_audit_changes, "Shortsword private audit handoff missing")
            local template = clone(source)
            assert(disjoint(source_before, capture(template, 4096, 32768)), "template clone aliases source")
            assert(prepare(template, clone_scalar) == true, "template preparation rejected")
            assert(#events == 7 and check_scalar() == nil, "Shortsword encounter or scalar audit rejected")
            local count = 0; for _ in next, custom do count = count + 1 end
            assert(count == 5, "Shortsword unique profile family changed")
            for _, row in next, donors do assert(intact(row.snapshot) and intact(row.prepared_snapshot), "donor changed during preparation") end
            for _, row in ipairs(power) do assert(intact(row.snapshot) and intact(row.prepared_snapshot), "native power changed during preparation") end
            for _, destination in ipairs(destinations) do
                local value = rawget(detached_levels, destination.key)
                if value ~= nil then
                    assert(rawget(levels, destination.key) == destination.before, "prepared power destination changed")
                    local snapshot = type(value) == "table" and capture(value, 256, 2048)
                    assert(snapshot, "prepared power graph unproven")
                    power[#power + 1] = { key = destination.key, value = value, snapshot = snapshot }
                    stage(levels, destination.key, value, "power:" .. destination.key, destination.before)
                end
            end
            local template_snapshot = career_capture(template, { role = "clone", source = source, token = TEMPLATE .. "<-" .. DONOR })
            assert(template_snapshot, "prepared template graph unproven")
            assert(rawget(state, "_cwv_damage_profile_wire_source") == map
                and rawget(state, "_cwv_damage_profile_generation") == generation
                and rawget(state, "_cwv_wire_fallback_profile_id") == captured_first, "source preimage changed during prepare")
            stage(state, "_cwv_damage_profile_generation", generation + #events, "generation", generation)
            if captured_first == nil then stage(state, "_cwv_wire_fallback_profile_id", first, "fallback") end
            stage(weapons, TEMPLATE, template, "template")
            assert(append_audit(changes) == true, "private live audit rejected")
            local proof = { profiles = profiles, levels = levels, lookup = lookup, weapons = weapons, map = map, metas = metas,
                source = source, source_snapshot = source_snapshot, template = template, template_snapshot = template_snapshot,
                donors = donors, custom = custom, power = power, events = events,
                generation = generation + #events, fallback = first }
            local ok = commit(changes, function()
                assert(profiles_for() == profiles and levels_for() == levels and lookup_for() == lookup and weapons_for() == weapons
                    and rawget(weapons, DONOR) == source and intact(source_before) and intact(map_before), "source graph changed before commit")
                for name, row in next, donors do
                    assert(rawget(profiles, name) == row.profile and intact(row.snapshot) and pair(lookup, name, row.id), "donor changed before commit")
                end
            end, function()
                assert(rawget(state, "_cwv_damage_profile_generation") == proof.generation and retained(proof), "family readback rejected")
            end, read, write)
            if not ok then return false, "family_commit_rejected" end
            owned, failure = proof, nil
            return true
        end
        local C = {}
        function C.construct(prepare)
            if owned then local ok, ready = pcall(retained, owned); return ok and ready or false end
            local ok, ready, reason = pcall(construct, prepare)
            if ok and ready then return true end
            failure = ok and reason or tostring(ready)
            return false
        end
        function C.admit(def)
            if type(def) ~= "table" or rawget(def, "item_key") ~= "cwv_es_shortsword" or rawget(def, "template") ~= TEMPLATE then return false end
            local ok, ready = pcall(retained, owned)
            return ok and ready == true
        end
        function C.check()
            local ok, ready = pcall(retained, owned)
            if not ok or not ready then return "#428 Shortsword construction unproven: " .. tostring(failure or "retained_authority_lost") end
        end
        return C
    end
end
return M
