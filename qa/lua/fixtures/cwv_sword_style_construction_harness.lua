-- #645 PREPARATION ONLY. Exact native sources + actual entry/core scalar handoff.
-- No catalog/admission/receiver activation and no engine/playback/VMF ABI claim.
local M = {}
local PREFIX = "/character_weapon_variants/scripts/mods/character_weapon_variants/"
local FINAL = { "light_push", "light_slashing_linesman_elf", "light_slashing_linesman_finesse",
    "light_slashing_smiter_stab_swords", "medium_push", "medium_slashing_linesman_finesse",
    "medium_slashing_smiter_1h", "medium_slashing_tank_1h_finesse", "sword_1h_light_smiter_vertical" }
M.specs = {
    empire_on_elf = { donor = "one_handed_swords_template_1", template = "cwv_645_empire_sword_style",
        prefix = "cwv_645_empire_sword_", speed = 1.10, factor = 0.90, encounters = 8,
        nodes = { "default", "default_right", "default_left", "heavy_attack_left", "heavy_attack_right",
            "light_attack_left", "light_attack_right", "light_attack_last", "light_attack_bopp", "push" } },
    elven_on_empire = { donor = "we_one_hand_sword_template_1", template = "cwv_645_elven_sword_style",
        prefix = "cwv_645_elven_sword_", speed = 0.90, factor = 1.10, encounters = 9,
        nodes = { "default", "default_right", "default_left", "heavy_attack_left", "heavy_attack_right", "heavy_attack_up",
            "light_attack_left", "light_attack_right", "light_attack_last", "light_attack_bopp", "push" } },
}
local function strip_bom(source)
    if source:sub(1, 3) == string.char(239, 187, 191) then return source:sub(4) end
    return source
end
local function fragment(part, shared)
    if part.source then return part.source end
    local source = assert(shared[part.field], "required sealed shared fragment field missing")
    local at = assert(source:find(part.anchor, 1, true), "required sealed shared fragment anchor missing")
    assert(not source:find(part.anchor, at + 1, true), "shared fragment anchor nonunique")
    return source:sub(at, at + part.bytes - 1)
end
local function source_closure(c, root, config)
    local native = assert(loadfile(root .. "/qa/lua/fixtures/cwv_sword_style_native_6_13.lua"))()
    local shared = assert(loadfile(root .. "/qa/lua/fixtures/cwv_elven_shield_construction_source.lua"))()
    local env, T = c.env, c.T
    local selected = setmetatable({ table = env.table, fassert = function(ok, message, ...)
        assert(ok, string.format(message, ...))
    end }, { __index = env })
    selected._G = selected
    local powers, profiles = {}, {}
    for _, part in ipairs(native.power_parts) do powers[#powers + 1] = fragment(part, shared) end
    for _, part in ipairs(native.profile_parts) do profiles[#profiles + 1] = fragment(part, shared) end
    -- Local new_template and every selected invocation stay in ONE lexical chunk.
    T.run("PowerLevelTemplates = {\n" .. table.concat(powers) .. "}\n", selected, "exact43-native-power-members")
    -- Named mode is the actual sealed earlier producer phase, not fabricated
    -- reverse-conversion of resolved tables. Normal8 keeps its full native chunk.
    local profile_chunk = table.concat(profiles)
    if not config.named_profiles then profile_chunk = profile_chunk .. shared.resolve .. native.name_loop end
    T.run(profile_chunk, selected, config.named_profiles and "exact-native-pre-resolution-profile-producer"
        or "exact-native-profile-helper-calls-resolver-name")
    if config.named_profiles then c.native_named = selected.DamageProfileTemplates end
    for key, value in next, selected.PowerLevelTemplates do
        assert(rawget(env.PowerLevelTemplates, key) == nil, "native power closure collides with core input")
        rawset(env.PowerLevelTemplates, key, value)
    end
    for _, key in ipairs(FINAL) do
        assert(rawget(env.DamageProfileTemplates, key) == nil, "native selected profile collision")
        rawset(env.DamageProfileTemplates, key, assert(rawget(selected.DamageProfileTemplates, key)))
        local id, inserted = c.helper.register(c.lookup, key)
        assert(inserted and rawget(c.lookup, id) == key, "native canonical pair initialization failed")
    end
    -- Exact module sources retain callbacks; only their leading UTF-8 BOM is decoded.
    local globals = assert(loadfile(root .. "/qa/lua/fixtures/cwv_sword_style_native_globals.lua"))()
    local tracked_mass = assert(loadfile(root .. "/qa/lua/fixtures/cwv_greataxe_construction_source.lua"))()
    T.run(tracked_mass.mass, env, "exact-native-linesman-hit-mass-by-reference")
    T.run(globals.tank, env, "exact-native-tank-hit-mass-supplement")
    assert(type(rawget(env, "LINESMAN_HIT_MASS_COUNT")) == "table"
        and type(rawget(env, "TANK_HIT_MASS_COUNT")) == "table", "required native hit-mass globals missing")
    assert(rawget(_G, "NONE") == nil, "standalone NONE-absent precondition changed")
    rawset(env, "NONE", config.none_sentinel)
    env.AttachmentNodeLinking.one_handed_melee_weapon = { right = {} }
    local empire = T.run(strip_bom(native.empire), env, "complete-native6.13-Empire-1hSword")
    local elven = T.run(strip_bom(native.elven), env, "complete-native6.13-Elven-1hSword")
    for key, value in next, empire do assert(rawget(env.Weapons, key) == nil); env.Weapons[key] = value end
    for key, value in next, elven do assert(rawget(env.Weapons, key) == nil); env.Weapons[key] = value end
    for _, statement in ipairs(native.items) do T.run(statement, env, "exact-native-IML-sword-record") end
    c.native_selected, c.native_payload = selected, native
end
-- Raw bijective graph equality: scalar/functions exact, table aliases and metas exact.
-- This deliberately does not use the legacy harness' metamethod-aware == shortcut.
function M.same(actual, expected, forward, reverse)
    if type(actual) ~= type(expected) then return false end
    if type(actual) ~= "table" then return rawequal(actual, expected) end
    forward, reverse = forward or {}, reverse or {}
    if forward[actual] then return rawequal(forward[actual], expected) end
    if reverse[expected] then return false end
    if not rawequal(getmetatable(actual), getmetatable(expected)) then return false end
    forward[actual], reverse[expected] = expected, actual
    local count, other = 0, 0
    for key, value in next, actual do
        if type(key) == "table" or not M.same(value, rawget(expected, key), forward, reverse) then return false end
        count = count + 1
    end
    for _ in next, expected do other = other + 1 end
    return count == other
end
function M.snapshot(c)
    return assert(c.graph.capture({ c.env.DamageProfileTemplates, c.env.PowerLevelTemplates, c.lookup,
        c.env.Weapons, c.env.ItemMasterList, c.state, c.audit() }, 8192, 131072), "bounded context snapshot failed")
end
function M.unchanged(H, c, before) H.truthy(c.graph.intact(before), "all raw context cells/metas/audit must be unchanged") end
function M.new(H, root, config)
    config = config or {}
    local quiet = setmetatable({ test = function() end, test_if = function() end }, { __index = H })
    local T = assert(loadfile(root .. "/qa/lua/tests/test_cwv_old_musket_shot_owner.lua"))()(quiet, root)
    local c = T.installed(function(current)
        current.T = T
        if config.get_mod then current.env.get_mod = config.get_mod end
        current.before_musket = function(helper, graph, envelope)
            current.helper, current.graph, current.career_envelope = helper, graph, envelope
            current.env.PowerLevelTemplates = {}
            if config.prepare_core then
                config.prepare_core(current)
            else
                current.state.combat_style_policy = {}
            end
            local entry = T.read(root .. PREFIX .. "character_weapon_variants.lua")
            local a = assert(entry:find("local _core_template_construction = mod:dofile(", 1, true))
            local b = assert(entry:find("\nlocal _clone_damage_profile = _core_template_construction.clone_damage_profile", a, true))
            local bind = T.run("return function(mod, _om, _cwv_network_lookup, _cwv_profile_graph, _cwv_career_envelope)\n"
                .. entry:sub(a, b - 1) .. "\nreturn _core_template_construction end", current.env, "exact-actual-entry-core-factory-return")
            current.core = bind(current.mod, current.state, helper, graph, envelope)
            H.equal(type(current.core.detached_scalar_factory), "function", "actual private scalar factory missing")
            source_closure(current, root, config)
            if config.after_native then config.after_native(current) end
            local donor_envelope = config.donor_envelope and config.donor_envelope(current) or nil
            local factory = assert(loadfile(root .. PREFIX .. "_cwv_sword_style_construction.lua"))().bind(helper, graph, donor_envelope)
            current.factory, current.owners, current.events = factory, {}, {}
            function current.audit()
                for index = 1, 20 do
                    local name, value = debug.getupvalue(current.state._cwv_profile_multiplier_check, index)
                    if name == "multiplier_audit" then return value end
                    if not name then break end
                end
                error("actual private live audit ledger unavailable")
            end
            function current.create(direction, options)
                options = options or {}
                local scalar = options.scalar or current.core.detached_scalar_factory
                local input = { direction = direction, state = current.state,
                    clone = function(value) return current.env.table.clone(value, true) end,
                    profiles = function() return current.env.DamageProfileTemplates end,
                    power_levels = function() return current.env.PowerLevelTemplates end,
                    lookup = function() return current.env.NetworkLookup.damage_profiles end,
                    weapons = function() return current.env.Weapons end,
                    scalar_factory = function(settings)
                        local record = settings.record_source
                        settings.record_source = function(name, donor)
                            current.events[#current.events + 1] = { name, donor }
                            return record(name, donor)
                        end
                        return scalar(settings)
                    end,
                    read = options.read, write = options.write }
                if options.adjust then options.adjust(input, current) end
                local owner = factory(input)
                current.owners[direction] = owner
                return owner
            end
            if config.early_attempt then
                assert(type(config.early_attempt) == "function" and config.early_direction == nil,
                    "one explicit pre-Musket attempt only")
                config.early_attempt(current)
            end
            if config.early_direction then
                H.equal(rawget(current.state, "_cwv_wire_fallback_profile_id"), nil, "real first-producer ordering changed")
                current.early_before = M.snapshot(current)
                current.early_owner = current.create(config.early_direction)
                H.truthy(current.early_owner.construct(), "pre-Musket first native sword construction")
                current.early_fallback = current.state._cwv_wire_fallback_profile_id
            end
        end
    end)
    c.T = T
    return c
end
function M.expected_template(c, direction)
    local spec = assert(M.specs[direction])
    local expected = c.env.table.clone(assert(c.env.Weapons[spec.donor]), true)
    local events, unique, ordered = {}, {}, {}
    for _, name in ipairs(spec.nodes) do
        local action = expected.actions.action_one[name]
        action.anim_time_scale = (rawget(action, "anim_time_scale") or 1) * spec.speed
        local fields = action.kind == "sweep" and { "damage_profile" }
            or action.kind == "push_stagger" and { "damage_profile_inner", "damage_profile_outer" } or {}
        for _, field in ipairs(fields) do
            local donor = assert(rawget(action, field)); events[#events + 1] = { spec.prefix .. donor, donor }
            if not unique[donor] then unique[donor] = true; ordered[#ordered + 1] = donor end
            action[field] = spec.prefix .. donor
        end
    end
    return expected, events, ordered
end
function M.expected_profile(c, name, factor)
    local expected = c.env.table.clone(assert(c.env.DamageProfileTemplates[name]), true)
    local function target(row)
        if type(row) == "table" and type(rawget(row, "power_distribution")) == "table" then
            local power = row.power_distribution
            if type(rawget(power, "impact")) == "number" then power.impact = power.impact * factor end
        end
    end
    local cleave = assert(expected.cleave_distribution)
    cleave.attack, cleave.impact = cleave.attack * factor, cleave.impact * factor
    target(expected.default_target); target(expected.critical_strike)
    for key, row in next, expected.targets or {} do if type(key) == "number" then target(row) end end
    return expected
end
function M.verify(H, c, direction, owner, baseline, profile_expectations)
    local spec = assert(M.specs[direction])
    local name, actual = owner.template(direction)
    H.equal(name, spec.template); H.truthy(rawequal(actual, rawget(c.env.Weapons, name)))
    local expected, events, ordered = M.expected_template(c, direction)
    H.truthy(M.same(actual, expected), "complete native graph plus ONLY closed attack-speed/profile changes")
    H.truthy(not rawequal(actual, c.env.Weapons[spec.donor]), "template must be a detached clone")
    H.equal(#events, spec.encounters); H.equal(#ordered, 6)
    for index, event in ipairs(events) do
        local seen = c.events[baseline.events + index]
        H.equal(seen[1], event[1]); H.equal(seen[2], event[2])
    end
    for index, donor in ipairs(ordered) do
        local custom = spec.prefix .. donor
        H.equal(rawget(c.lookup, custom), baseline.max_id + index)
        H.equal(rawget(c.lookup, baseline.max_id + index), custom)
        H.equal(rawget(c.state._cwv_damage_profile_wire_source, custom), donor)
        local expected_profile = profile_expectations and assert(profile_expectations[donor])
            or M.expected_profile(c, donor, spec.factor)
        H.truthy(M.same(c.env.DamageProfileTemplates[custom], expected_profile), "whole profile math/critical/sparse target graph")
        H.truthy(c.graph.disjoint(c.graph.capture(c.env.DamageProfileTemplates[donor], 256, 2048),
            c.graph.capture(c.env.DamageProfileTemplates[custom], 256, 2048)), "owned profiles must not alias native tables")
    end
    H.equal(c.state._cwv_damage_profile_generation, baseline.generation + spec.encounters)
    H.equal(c.audit().profiles, baseline.audit_profiles + spec.encounters)
    H.truthy(c.audit().comparisons > baseline.comparisons)
    H.equal(c.state._cwv_profile_multiplier_check(), nil)
    H.equal(owner.check(), nil)
    for _, node in ipairs(spec.nodes) do
        local source = c.env.Weapons[spec.donor].actions.action_one[node]
        local cloned = actual.actions.action_one[node]
        local native_callback = rawget(source, "anim_end_event_condition_func")
        local cloned_callback = rawget(cloned, "anim_end_event_condition_func")
        H.truthy(rawequal(native_callback, cloned_callback), "exact raw optional callback identity")
        if native_callback == nil then
            H.equal(cloned_callback, nil, "native absence must not synthesize a callback")
        else
            H.equal(type(native_callback), "function", "present native callback must be callable")
            for _, reason in ipairs({ "action_complete", "new_interupting_action", "interrupted" }) do
                H.equal(cloned_callback(nil, reason), native_callback(nil, reason))
            end
        end
    end
end
function M.baseline(c)
    return { events = #c.events, max_id = #c.lookup, generation = c.state._cwv_damage_profile_generation,
        audit_profiles = c.audit().profiles, comparisons = c.audit().comparisons }
end
-- Independent oracle for the exact pre-resolution named/TABLE mixture.
local NAMED_FIELDS = { "cleave_distribution", "default_target", "targets", "critical_strike" }
local function shallow(source)
    local result = {}; for key, value in next, source do result[key] = value end
    return result
end
local function scale_named(row, field, factor)
    local function target(value)
        local power = type(value) == "table" and rawget(value, "power_distribution")
        if type(power) == "table" and type(rawget(power, "impact")) == "number" then
            power.impact = power.impact * factor
        end
    end
    if field == "cleave_distribution" then
        row.attack, row.impact = row.attack * factor, row.impact * factor
    elseif field == "targets" then
        for key, value in next, row do if type(key) == "number" then target(value) end end
    else target(row) end -- critical armor arrays have no target power to scale.
end
function M.named_plan(H, c, direction)
    H.equal(type(c.native_named), "table", "declared native pre-resolution mode")
    local spec = assert(M.specs[direction])
    local _, _, ordered = M.expected_template(c, direction)
    local plan = { profiles = {}, powers = {}, power_keys = {}, named_fields = 0, table_fields = 0 }
    for _, donor in ipairs(ordered) do
        local source = assert(rawget(c.env.DamageProfileTemplates, donor))
        H.truthy(M.same(source, assert(rawget(c.native_named, donor))), "exact native pre-resolution profile")
        local expected = c.env.table.clone(source, true)
        for _, field in ipairs(NAMED_FIELDS) do
            local value = rawget(source, field)
            if type(value) == "string" then
                plan.named_fields = plan.named_fields + 1
                local key = spec.prefix .. value
                H.equal(rawget(c.env.PowerLevelTemplates, key), nil, "native Power destination starts absent")
                local native = assert(rawget(c.env.PowerLevelTemplates, value), "actual named native Power source")
                H.equal(type(native), "table")
                local owned = c.env.table.clone(native, true); scale_named(owned, field, spec.factor)
                if plan.powers[key] then H.truthy(M.same(plan.powers[key], owned), "one consistent shared Power destination")
                else plan.powers[key] = owned; plan.power_keys[#plan.power_keys + 1] = key end
                expected[field] = key
            elseif type(value) == "table" then
                plan.table_fields = plan.table_fields + 1
                scale_named(expected[field], field, spec.factor)
            else H.equal(value, nil, "native scaled field is absent/string/table") end
        end
        -- armor_modifier deliberately remains the exact unscaled native reference.
        H.truthy(M.same(expected.armor_modifier, source.armor_modifier), "unscaled native armor reference/graph")
        plan.profiles[donor] = expected
    end
    table.sort(plan.power_keys)
    H.truthy(plan.named_fields > 0 and plan.table_fields > 0, "actual native producer remains mixed")
    H.truthy(#plan.power_keys > 0 and #plan.power_keys <= 24, "finite real six-profile/four-field destinations")
    return plan
end
function M.named_baseline(H, c, direction)
    local before = M.baseline(c)
    before.named = M.named_plan(H, c, direction)
    before.registries = {
        profiles = c.env.DamageProfileTemplates, powers = c.env.PowerLevelTemplates,
        weapons = c.env.Weapons, items = c.env.ItemMasterList,
        lookup = c.lookup, map = c.state._cwv_damage_profile_wire_source,
    }
    before.members, before.metas = {}, {}
    for key, value in pairs(before.registries) do
        before.members[key], before.metas[key] = shallow(value), getmetatable(value)
    end
    -- Snapshot member graphs, NOT roots whose exact allowed append set is checked below.
    before.native = assert(c.graph.capture({ before.members.profiles, before.members.powers,
        before.members.weapons, before.members.items }, 8192, 131072))
    before.fallback = rawget(c.state, "_cwv_wire_fallback_profile_id")
    return before
end
function M.verify_named(H, c, direction, owner, before)
    M.verify(H, c, direction, owner, before, before.named.profiles)
    H.truthy(c.graph.intact(before.native), "all original native member graphs stay exact")
    local spec, plan = M.specs[direction], before.named
    local actual_profiles, actual_powers, added_profiles, added_lookup, added_map = {}, {}, {}, {}, {}
    local _, _, ordered = M.expected_template(c, direction)
    for _, donor in ipairs(ordered) do
        local key, id = spec.prefix .. donor, rawget(c.lookup, spec.prefix .. donor)
        actual_profiles[donor] = rawget(c.env.DamageProfileTemplates, key)
        added_profiles[key], added_lookup[key], added_lookup[id], added_map[key] = true, true, true, true
    end
    H.truthy(M.same(actual_profiles, plan.profiles), "complete named profile graph/reference mixture")
    for _, key in ipairs(plan.power_keys) do
        actual_powers[key] = rawget(c.env.PowerLevelTemplates, key)
        H.equal(type(actual_powers[key]), "table", "actual owned Power destination exists")
        H.truthy(c.graph.disjoint(before.native, c.graph.capture(actual_powers[key], 256, 2048)),
            "owned Power rows do not alias any original native member")
    end
    H.truthy(M.same(actual_powers, plan.powers), "whole named Power math critical arrays and aliases")
    local actual_roots = { profiles = c.env.DamageProfileTemplates, powers = c.env.PowerLevelTemplates,
        weapons = c.env.Weapons, items = c.env.ItemMasterList, lookup = c.env.NetworkLookup.damage_profiles,
        map = c.state._cwv_damage_profile_wire_source }
    local allowed = { profiles = added_profiles, powers = plan.powers,
        weapons = { [spec.template] = true }, items = {}, lookup = added_lookup, map = added_map }
    for label, original in pairs(before.registries) do
        local actual, old, additions = actual_roots[label], before.members[label], allowed[label]
        H.truthy(rawequal(actual, original), "registry root identity " .. label)
        H.truthy(rawequal(getmetatable(actual), before.metas[label]), "registry metatable " .. label)
        local count, expected_count = 0, 0
        for key, value in next, old do
            expected_count = expected_count + 1
            H.truthy(rawequal(rawget(actual, key), value), "original registry member identity " .. label)
        end
        for key in next, additions do
            H.equal(rawget(old, key), nil, "only new destinations permitted " .. label)
            expected_count = expected_count + 1
        end
        for key in next, actual do
            count = count + 1
            H.truthy(rawget(old, key) ~= nil or rawget(additions, key) ~= nil, "exact destination census " .. label)
        end
        H.equal(count, expected_count, "exact registry size " .. label)
    end
    H.equal(rawget(c.state, "_cwv_wire_fallback_profile_id"), before.fallback, "named branch preserves prior fallback")
end
return M
