-- _cwv_javelin_construction_owner.lua -- Atomic finite-stack Javelin construction.
--
-- Owns four profiles, seven source encounters, the prepared template, selected
-- donor preview cells and the private core audit contribution in one journal.
-- The original runtime prepares its detached template; this owner never repairs
-- live registries or adopts foreign/hot-reloaded templates. Projectile lifetime,
-- wire capability and retained native action safety remain separate contracts.
--
-- Owned by: character_weapon_variants.lua entry point.
-- Consumed via: one manifest mod:dofile and private by-value factory binding.
local M = {}
local TEMPLATE, DONOR, PREFIX = "tuskgor_javelin_template", "javelin_template", "cwv_tj_"
local SOURCES = { medium_javelin_smiter_stab = true, medium_javelin_smiter_stab_bleed = true,
    heavy_javelin_smiter_stab_bleed = true, thrown_javelin = true }
local ITEMS = { cwv_es_javelin = true, cwv_wh_javelin = true }
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
    local found = false
    for _, key in ipairs({ "power_distribution", "power_distribution_near", "power_distribution_far" }) do
        local row = rawget(target, key)
        if row ~= nil then
            if type(row) ~= "table" or not finite(rawget(row, "attack")) or not finite(rawget(row, "impact")) then return false end
            found = true
        end
    end
    return found
end
function M.bind(helper, mechanics, scalar_factory, envelope)
    local register = assert(helper and helper.register, "Javelin lookup helper missing")
    local capture, intact, disjoint, commit = assert(mechanics.capture), assert(mechanics.intact),
        assert(mechanics.disjoint), assert(mechanics.commit)
    local scalar = assert(scalar_factory, "Javelin detached scalar factory missing")
    local career_capture, career_intact = assert(envelope.capture), assert(envelope.intact)
    return function(options)
        local profiles_for, levels_for, lookup_for, weapons_for = options.profiles, options.power_levels, options.lookup, options.weapons
        local state, clone = assert(options.state), assert(options.clone)
        local read, write = options.read or rawget, options.write or rawset
        local owned, failure = nil, "not_constructed"
        local function pair(lookup, key, id)
            return integer(id) and id > 0 and rawget(lookup, key) == id and rawget(lookup, id) == key
        end
        local function retained(p)
            if profiles_for() ~= p.profiles or levels_for() ~= p.levels or lookup_for() ~= p.lookup
                    or weapons_for() ~= p.weapons or rawget(p.weapons, DONOR) ~= p.source
                    or rawget(p.weapons, TEMPLATE) ~= p.template or not career_intact(p.template_snapshot)
                    or not career_intact(p.source_snapshot)
                    or rawget(state, "_cwv_damage_profile_wire_source") ~= p.map
                    or not integer(rawget(state, "_cwv_damage_profile_generation"))
                    or rawget(state, "_cwv_damage_profile_generation") < p.generation
                    or rawget(state, "_cwv_wire_fallback_profile_id") ~= p.fallback then return false end
            for name, row in next, p.donors do
                if rawget(p.profiles, name) ~= row.profile or not intact(row.snapshot) or not pair(p.lookup, name, row.id) then return false end
                local selected = p.custom[name]
                if rawget(p.profiles, PREFIX .. name) ~= selected.profile or not intact(selected.snapshot)
                        or not pair(p.lookup, PREFIX .. name, selected.id) or rawget(p.map, PREFIX .. name) ~= name then return false end
            end
            for _, row in ipairs(p.power) do
                if rawget(p.levels, row.key) ~= row.value or not intact(row.snapshot) then return false end
            end
            if rawget(p.source, "wield_anim_career_3p") ~= p.preview or getmetatable(p.preview) ~= p.preview_meta then return false end
            for career, value in next, p.wields do if rawget(p.preview, career) ~= value then return false end end
            return true
        end
        local function construct(prepare, wields)
            local profiles, levels, lookup, weapons = profiles_for(), levels_for(), lookup_for(), weapons_for()
            local map, generation, first = rawget(state, "_cwv_damage_profile_wire_source"),
                rawget(state, "_cwv_damage_profile_generation"), rawget(state, "_cwv_wire_fallback_profile_id")
            if type(profiles) ~= "table" or type(levels) ~= "table" or type(lookup) ~= "table" or type(weapons) ~= "table"
                    or type(map) ~= "table" or not integer(generation) or generation > 9007199254740983
                    or type(prepare) ~= "function" or type(wields) ~= "table" then return false, "source_roots_unproven" end
            local wields_snapshot, stable_wields = capture(wields, 4, 32), {}
            if not wields_snapshot then return false, "preview_policy_unproven" end
            for career, value in next, wields do
                if type(career) ~= "string" or type(value) ~= "string" then return false, "preview_policy_unproven" end
                stable_wields[career] = value
            end
            wields = stable_wields
            local source = rawget(weapons, DONOR)
            if type(source) ~= "table" or rawget(weapons, TEMPLATE) ~= nil then return false, "template_source_or_foreign" end
            local source_before, map_before = capture(source, 4096, 32768), capture(map, 2048, 8192)
            if not source_before or not map_before then return false, "source_graph_unproven" end
            local preview_before = rawget(source, "wield_anim_career_3p")
            if preview_before ~= nil and type(preview_before) ~= "table" then return false, "preview_shape_unproven" end
            local source_snapshot = career_capture(source, { role = "source", include = function(t, key)
                return not ((t == source and key == "wield_anim_career_3p") or (t == preview_before and wields[key] ~= nil))
            end })
            local detached_profiles, detached_levels, detached_lookup, donors, power, destinations = {}, {}, {}, {}, {}, {}
            for key, value in next, lookup do detached_lookup[key] = value end
            local initial_max = #detached_lookup
            if first ~= nil then
                local key = rawget(lookup, first)
                if type(key) ~= "string" or key:sub(1, 4) == "cwv_" or not pair(lookup, key, first) or type(rawget(profiles, key)) ~= "table" then
                    return false, "first_fallback_unproven"
                end
            end
            for name in next, SOURCES do
                local profile, id = rawget(profiles, name), rawget(lookup, name)
                local checked, inserted = register(detached_lookup, name)
                if not profile_shape(profile, levels) or not pair(lookup, name, id) or checked ~= id or inserted then return false, "native_profile_or_pair_unproven" end
                local snapshot = capture(profile, 256, 2048)
                if not snapshot then return false, "native_profile_graph_unproven" end
                if rawget(profiles, PREFIX .. name) ~= nil or rawget(lookup, PREFIX .. name) ~= nil
                        or rawget(map, PREFIX .. name) ~= nil then return false, "foreign_custom_state" end
                donors[name] = { profile = profile, snapshot = snapshot, id = id }
                local detached = clone(profile)
                local prepared = capture(detached, 256, 2048)
                if not prepared or not disjoint(snapshot, prepared) then return false, "detached_donor_alias" end
                detached_profiles[name], donors[name].prepared_snapshot = detached, prepared
                for _, key in ipairs({ "cleave_distribution", "default_target", "targets", "critical_strike" }) do
                    local reference = rawget(profile, key)
                    if type(reference) == "string" then
                        local value = rawget(levels, reference)
                        if type(value) ~= "table" or rawget(levels, PREFIX .. reference) ~= nil then return false, "power_reference_unproven" end
                        if detached_levels[reference] == nil then
                            local snapshot, copied = capture(value, 256, 2048), clone(value)
                            local prepared_power = capture(copied, 256, 2048)
                            if not snapshot or not prepared_power or not disjoint(snapshot, prepared_power) then return false, "detached_power_alias" end
                            detached_levels[reference] = copied
                            -- Preserve the proven nil destination BEFORE prepare can run callbacks.
                            destinations[#destinations + 1] = { key = PREFIX .. reference, before = nil }
                            power[#power + 1] = { key = reference, value = value, snapshot = snapshot, prepared_snapshot = prepared_power }
                        end
                    end
                end
            end
            local changes, events, custom, created, captured_first = {}, {}, {}, {}, first
            local function stage(t, key, value, tag)
                changes[#changes + 1] = { t, key, value, tag, before = rawget(t, key) }
            end
            local function record(name, donor)
                assert(SOURCES[donor] and name == PREFIX .. donor, "Javelin source axis changed")
                events[#events + 1] = { name, donor }
                if first == nil then first = donors[donor].id end
            end
            local function publish(name, profile)
                assert(SOURCES[name:sub(#PREFIX + 1)] and not created[name], "Javelin publication axis changed")
                local id, inserted = register(detached_lookup, name)
                assert(integer(id) and inserted and id > initial_max, "Javelin paired append rejected")
                detached_profiles[name], created[name] = profile, true
                local donor = name:sub(#PREFIX + 1)
                local snapshot = capture(profile, 256, 2048)
                assert(snapshot and disjoint(donors[donor].snapshot, snapshot), "Javelin profile clone aliases source")
                custom[donor] = { profile = profile, snapshot = snapshot, id = id }
                stage(map, name, donor, "source:" .. donor)
                stage(profiles, name, profile, "profile:" .. donor)
                stage(lookup, id, name, "numeric:" .. donor)
                stage(lookup, name, id, "reverse:" .. donor)
                return true
            end
            local planner = scalar({ profiles = detached_profiles, power_levels = detached_levels, record_source = record, register = publish })
            local clone_scalar, check_scalar, append_audit = assert(planner.clone_damage_profile), assert(planner.check),
                assert(planner.append_live_audit_changes, "Javelin private audit handoff missing")
            local function inline(name, prefix, damage_mult)
                assert(name == "thrown_javelin" and prefix == PREFIX and damage_mult == 2, "Javelin inline axis changed")
                local new_name = prefix .. name; record(new_name, name)
                if detached_profiles[new_name] then return new_name end
                local result = clone(detached_profiles[name])
                assert(disjoint(donors[name].prepared_snapshot, capture(result, 256, 2048)), "inline clone aliases source")
                local function scale(target)
                    if type(target) ~= "table" then return end
                    for _, key in ipairs({ "power_distribution_near", "power_distribution_far", "power_distribution" }) do
                        if target[key] and target[key].attack then target[key].attack = target[key].attack * damage_mult end
                    end
                end
                scale(result.default_target)
                if type(result.targets) == "table" then for _, target in ipairs(result.targets) do scale(target) end end
                local function checked(a, b)
                    if type(a) ~= "table" then return true end
                    for _, key in ipairs({ "power_distribution_near", "power_distribution_far", "power_distribution" }) do
                        if a[key] and a[key].attack and (not b or not b[key] or b[key].attack ~= a[key].attack * damage_mult
                                or b[key].impact ~= a[key].impact) then return false end
                    end
                    return true
                end
                assert(checked(donors[name].profile.default_target, result.default_target), "inline default multiplier unproven")
                if type(donors[name].profile.targets) == "table" then
                    for index, target in ipairs(donors[name].profile.targets) do
                        assert(checked(target, result.targets and result.targets[index]), "inline target multiplier unproven")
                    end
                end
                publish(new_name, result); return new_name
            end
            local template = clone(source)
            assert(disjoint(source_before, capture(template, 4096, 32768)), "template clone aliases source")
            assert(prepare(template, clone_scalar, inline) == true, "template preparation rejected")
            assert(#events == 7 and check_scalar() == nil, "Javelin encounter or scalar audit rejected")
            assert(intact(wields_snapshot), "preview policy changed during preparation")
            local count = 0; for _ in next, custom do count = count + 1 end
            assert(count == 4, "Javelin unique profile family changed")
            for _, row in next, donors do
                assert(intact(row.snapshot) and intact(row.prepared_snapshot), "donor changed during preparation")
            end
            for _, row in ipairs(power) do
                if not intact(row.snapshot) or not intact(row.prepared_snapshot) then error("native power source changed") end
            end
            for _, destination in ipairs(destinations) do
                local key, before = destination.key, destination.before
                local value = rawget(detached_levels, key)
                if value ~= nil then
                    assert(rawget(levels, key) == before, "prepared power destination changed")
                    local snapshot = type(value) == "table" and capture(value, 256, 2048)
                    assert(snapshot, "prepared power graph unproven")
                    power[#power + 1] = { key = key, value = value, snapshot = snapshot }
                    -- Always journal the prepared cell against its original nil preimage.
                    changes[#changes + 1] = { levels, key, value, "power:" .. key, before = before }
                end
            end
            local template_snapshot = career_capture(template, { role = "clone", source = source, token = TEMPLATE .. "<-" .. DONOR })
            assert(template_snapshot and source_snapshot, "prepared template graph unproven")
            assert(rawget(state, "_cwv_damage_profile_wire_source") == map
                and rawget(state, "_cwv_damage_profile_generation") == generation
                and rawget(state, "_cwv_wire_fallback_profile_id") == captured_first, "source preimage changed during prepare")
            stage(state, "_cwv_damage_profile_generation", generation + #events, "generation")
            if captured_first == nil then stage(state, "_cwv_wire_fallback_profile_id", first, "fallback") end
            stage(weapons, TEMPLATE, template, "template")
            local preview = preview_before or {}
            if preview_before == nil then stage(source, "wield_anim_career_3p", preview, "preview_root") end
            for career, value in pairs(stable_wields) do stage(preview, career, value, "preview:" .. career) end
            assert(append_audit(changes) == true, "private live audit rejected")
            local proof = { profiles = profiles, levels = levels, lookup = lookup, weapons = weapons,
                source = source, source_snapshot = source_snapshot, template = template, template_snapshot = template_snapshot,
                donors = donors, custom = custom, power = power, map = map,
                generation = generation + #events, fallback = first, preview = preview, preview_meta = getmetatable(preview), wields = stable_wields }
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
        function C.construct(prepare, wields)
            if owned then local ok, result = pcall(retained, owned); return ok and result or false end
            local ok, result, reason = pcall(construct, prepare, wields)
            if ok and result then return true end
            failure = ok and reason or tostring(result)
            return false
        end
        function C.admit(def)
            if type(def) ~= "table" or not ITEMS[rawget(def, "item_key")] or rawget(def, "template") ~= TEMPLATE then return false end
            local ok, ready = pcall(retained, owned)
            return ok and ready == true
        end
        function C.check()
            local ok, ready = pcall(retained, owned)
            if not ok or not ready then return "#428 Tuskgor Javelin construction unproven: " .. tostring(failure or "retained_authority_lost") end
        end
        return C
    end
end
return M
