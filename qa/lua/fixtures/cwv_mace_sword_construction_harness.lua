-- Focused #645 SOURCE preparation; actual entry/core and native/WT producers.
-- #599 coverage is its real Mace timing arm over the real native Mace object;
-- unrelated Hammer balance math is not claimed by this fixture.
local M = {}
local CP = "/character_weapon_variants/scripts/mods/character_weapon_variants/"
local MACE, SWORD = "one_handed_hammer_template_1", "one_handed_swords_template_1"
local FAMILY, SETTING = "one_handed_hammer_shared", "wt_history_one_handed_hammer_shared"
local SFAMILY, SSETTING = "one_handed_sword_shared", "wt_history_one_handed_sword_shared"
local TEMPLATE, PREFIX = "cwv_645_mace_sword_style", "cwv_645_mace_sword_"
local TOKEN = TEMPLATE .. "<-" .. MACE
local MARKER, CLAIMS = "__vt2_tweaker_career_action_clone_source", "__vt2_tweaker_career_action_claims"
local MAP = {
    { "default", "default" }, { "default_right", "default_right" },
    { "default_left", "default_left" }, { "default_last", "default_left" },
    { "heavy_attack_left", "heavy_attack_left", "medium_slashing_tank_1h_finesse" },
    { "heavy_attack_right", "heavy_attack_right", "medium_slashing_tank_1h_finesse" },
    { "light_attack_left", "light_attack_left", "light_slashing_linesman_finesse" },
    { "light_attack_right", "light_attack_right", "light_slashing_linesman_finesse" },
    { "light_attack_last", "light_attack_left", "light_slashing_linesman_finesse" },
    { "light_attack_down", "light_attack_last", "sword_1h_light_smiter_vertical" },
    { "light_attack_bopp", "light_attack_bopp", "medium_slashing_linesman_finesse" },
    { "push", "push", "medium_push", "light_push" },
}
local PROFILES = { "medium_slashing_tank_1h_finesse", "light_slashing_linesman_finesse",
    "sword_1h_light_smiter_vertical", "medium_slashing_linesman_finesse", "medium_push", "light_push" }
local FIELDS = { "buff_data", "additional_critical_strike_chance", "hit_mass_count",
    "hit_effect", "impact_sound_event", "no_damage_impact_sound_event", "first_person_hit_anim",
    "hit_stop_anim", "hit_armor_anim", "hit_shield_stop_anim", "armor_impact_sound_event",
    "stagger_impact_sound_event", "no_damage_impact_particle_effect", "armour_impact_particle_effect",
    "impact_particle_effect", "additional_hit_effects" }
local function read(path)
    local f = assert(io.open(path, "rb")); local s = f:read("*a"); f:close()
    if s:sub(1, 3) == string.char(239, 187, 191) then s = s:sub(4) end
    return (s:gsub("\r\n", "\n"))
end
local function section(s, first, ending)
    local a = assert(s:find(first, 1, true)); assert(not s:find(first, a + 1, true))
    local b = assert(s:find(ending, a, true)); assert(not s:find(ending, b + 1, true))
    return s:sub(a, b - 1)
end
function M.new(H, root, config)
    config = config or {}
    local F = assert(loadfile(root .. "/qa/lua/fixtures/cwv_sword_style_construction_harness.lua"))()
    local mods, records = {}, {}
    local function resolver(id) return rawget(mods, id) end
    local function install(c, id, state, parity)
        local dir = id == "wt" and "weapon_tweaker" or "weapon_tweaker_dev"
        assert(id == "wt" or id == "wt_dev")
        local module_root = "scripts/mods/" .. dir .. "/"
        local enabled = parity == true
        local saved = { [SETTING] = state or "current", [SSETTING] = "current",
            wt_history_tuskgor_spear = config.tuskgor_history or "current",
            wt_revert_1h_sword_push_combo = false }
        local mod = { _wt = { dbg = function() end }, get = function(_, key)
            if saved[key] ~= nil then return saved[key] end
            return "current"
        end, _wt431_profiles_allowed = function() return enabled end }
        mod.dofile = function(_, path)
            local actual = c.T.run(read(root .. "/" .. dir .. "/" .. path .. ".lua"), c.env, path)
            if path ~= module_root .. "_wt_history_catalog" then return actual end
            return { load = function(actual_mod)
                H.truthy(rawequal(actual_mod, mod))
                local modules = { module_root .. "_wt_history_5_2_catalog" }
                if config.with_tuskgor then modules[#modules + 1] = module_root .. "_wt_history_3_1_catalog" end
                local original, problem = actual.load(mod, modules)
                H.truthy(original, problem)
                local picked, seen = {}, {}
                for _, family in ipairs(original.families) do
                    if family.id == FAMILY or family.id == SFAMILY
                            or (config.with_tuskgor and family.id == "tuskgor_spear") then
                        H.equal(seen[family.id], nil); seen[family.id] = true; picked[#picked + 1] = family
                    end
                end
                H.truthy(seen[FAMILY] and seen[SFAMILY], "both actual catalog families")
                H.truthy(not config.with_tuskgor or seen.tuskgor_spear, "actual Tuskgor catalog family")
                local selected = {}; for key, value in next, original do selected[key] = value end
                selected.families, selected.states, selected.profile_specs, selected.derived_profiles = picked, {}, {}, {}
                for _, family in ipairs(picked) do for _, sid in ipairs(family.state_order) do
                    selected.states[sid], selected.profile_specs[sid] = original.states[sid], selected.profile_specs[sid] or {}
                    for _, name in ipairs(family.states[sid].profile_names) do
                        selected.profile_specs[sid][name] = assert(original.profile_specs[sid][name])
                    end
                end end
                return actual.merge({ selected })
            end }
        end
        mods[id] = mod
        local entry = read(root .. "/" .. dir .. "/" .. module_root .. dir .. ".lua")
        local body = section(entry, "local _wt_history_owner, _wt_history_verify = mod:dofile(",
            "\n-- Bret Sword & Shield damage buff")
        local invoke = c.T.run("return function(mod)\n" .. body
            .. "\nreturn _wt_history_owner, _wt_history_verify, _wt_history_runtime end", c.env, "actual-WT9/6-entry")
        local owner, verify, runtime = invoke(mod)
        H.truthy(rawequal(owner.runtime, runtime)); H.truthy(rawequal(mod._wt_history_runtime, runtime))
        H.equal(runtime.fatal_error, nil); H.equal(runtime.last_error, nil); H.equal(verify(), nil)
        local r = { mod = mod, owner = owner, verify = verify, runtime = runtime, saved = saved,
            set_parity = function(value) enabled = value end }
        local settings = c.T.run(read(root .. "/" .. dir .. "/" .. module_root .. "_wt_settings_runtime.lua"),
            c.env, "actual-WT-settings-owner")
        local nop = function() end
        settings.install({ mod = mod, history_runtime = runtime,
            rework_runtime = { is_batching = function() return false end, on_master_changed = function() return false end,
                sync_for_leaf = nop, prepare_batch = function() return true end },
            balance_policy = {}, bolt_policy = { SETTING_ID = "qa_unused_bolt" }, bolt_runtime = { apply = nop },
            master_toggles = { reconcile_batch = nop }, backend = { refresh_on_setting_change = nop },
            apply_weapon_unlocks = nop, patch_career_actions = nop, apply_trait_filters = nop })
        records[id] = r
        return r
    end
    local c = F.new(H, root, {
        get_mod = resolver,
        prepare_core = config.prepare_core,
        after_native = function(current)
            -- Fill canonical empty seeds before any retained Sword/Mace proof.
            -- Existing native aliases keep their root identity; no source recapture.
            local canonical = rawget(current.env, "ActionTemplates")
            assert(type(canonical) == "table" and getmetatable(canonical) == nil,
                "native shared-action namespace is not plain")
            local names, targets = { "wield", "action_inspect" }, {}
            for _, name in ipairs(names) do
                local target = rawget(canonical, name)
                assert(type(target) == "table" and getmetatable(target) == nil and next(target) == nil,
                    "native shared-action root is not the empty base-fixture seed: " .. name)
                targets[name] = target
            end
            assert(not rawequal(targets.wield, targets.action_inspect), "native shared-action roots alias")
            local source = assert(loadfile(root .. "/qa/lua/fixtures/cwv_mace_sword_native_actions.lua"))()
            local native = current.T.run("local ActionTemplates = {}\n" .. source .. "\nreturn ActionTemplates",
                current.env, "exact93dea-native-shared-action-prerequisites")
            for _, name in ipairs(names) do
                for key, value in next, assert(rawget(native, name)) do
                    rawset(targets[name], key, value)
                end
                assert(rawequal(rawget(canonical, name), targets[name]), "native shared-action root replaced")
            end
            local mace = assert(loadfile(root .. "/qa/lua/fixtures/cwv_mace_sword_native_mace.lua"))()
            local priest = assert(loadfile(root .. "/qa/lua/fixtures/cwv_mace_sword_native_priest.lua"))()
            for _, chunk in ipairs({ mace, priest }) do
                if chunk:sub(1, 3) == string.char(239, 187, 191) then chunk = chunk:sub(4) end
                local exports = current.T.run(chunk, current.env, "complete-native93dea-Mace-family-member")
                for name, value in next, exports do
                    H.equal(rawget(current.env.Weapons, name), nil)
                    current.env.Weapons[name] = value
                end
            end
            H.truthy(not rawequal(current.env.Weapons[MACE].actions,
                current.env.Weapons.one_handed_hammer_template_2.actions), "native table.clone is recursive")
            -- Additional actual sources must precede every retained proof and WT boot.
            if config.prepare_sources then config.prepare_sources(current) end
            current.oracle = { mace = current.env.table.clone(current.env.Weapons[MACE], true),
                sword = current.env.table.clone(current.env.Weapons[SWORD], true), profiles = {} }
            for _, name in ipairs(PROFILES) do
                current.oracle.profiles[name] = current.env.table.clone(assert(current.env.DamageProfileTemplates[name]), true)
            end
            current.integration = current.T.run(read(root .. CP .. "_lib_career_weapon_actions.lua"), current.env, "actual-career-owner")
            local policy = current.T.run(read(root .. CP .. "_cwv_mace_hammer_identity.lua"), current.env, "actual599-policy")
            current.mhi_policy, current.mhi_state = policy, policy.new()
            function current.apply_mhi(enabled)
                local forbidden = 0
                current.mhi_state:apply(enabled, { [MACE] = current.env.Weapons[MACE] },
                    current.env.DamageProfileTemplates, current.env.PowerLevelTemplates,
                    function(value) return current.env.table.clone(value, true) end,
                    function() forbidden = forbidden + 1 end, function() forbidden = forbidden + 1 end)
                H.equal(forbidden, 0, "only actual Mace timing arm; no invented Hammer profile fixture")
            end
            current.apply_mhi(config.mhi ~= false)
            local sword_api = current.T.run(read(root .. CP .. "_cwv_sword_donor_envelope.lua"), current.env, "actual-Sword-envelope")
                .bind(current.graph, current.career_envelope, current.core.history_producer_binding,
                    current.integration, function() return current.env.ActionTemplates end)
            local source_api = current.T.run(read(root .. CP .. "_cwv_mace_sword_donor_envelope.lua"), current.env, "actual-Mace-envelope")
                .bind(current.graph, current.career_envelope, current.core.history_producer_binding,
                    current.integration, function() return current.env.ActionTemplates end,
                    function() return current.mhi_state, current.mhi_policy end, sword_api)
            current.mace_api = source_api
            local factory = current.T.run(read(root .. CP .. "_cwv_mace_sword_construction.lua"), current.env, "actual-Mace-constructor")
                .bind(current.helper, current.graph, source_api)
            current.mace_events = {}
            function current.create_mace(options)
                options = options or {}
                local input = { direction = "mace_on_empire_sword", state = current.state,
                    clone = function(value) return current.env.table.clone(value, true) end,
                    profiles = function() return current.env.DamageProfileTemplates end,
                    power_levels = function() return current.env.PowerLevelTemplates end,
                    lookup = function() return current.env.NetworkLookup.damage_profiles end,
                    weapons = function() return current.env.Weapons end,
                    scalar_factory = function(settings)
                        local record = settings.record_source
                        settings.record_source = function(name, donor)
                            current.mace_events[#current.mace_events + 1] = { name, donor }
                            return record(name, donor)
                        end
                        return current.core.detached_scalar_factory(settings)
                    end, read = options.read, write = options.write }
                if options.adjust then options.adjust(input, current) end
                return factory(input)
            end
            current.records = records
            current.install = function(id, state, parity) return install(current, id, state, parity) end
            if config.history then current.install(config.stream or "wt", config.history, config.parity) end
            if config.before then config.before(current) end
        end,
        early_attempt = config.early and function(current) config.early(current, F) end or nil,
    })
    c.F = F
    return c
end
function M.expected(c)
    local clone = function(value) return c.env.table.clone(value, true) end
    local result, mace = clone(c.oracle.sword), clone(c.oracle.mace)
    local expected_events, seen, ordered = {}, {}, {}
    local function project(action, source)
        for _, field in ipairs(FIELDS) do
            local value = rawget(source, field)
            if type(value) == "table" then value = clone(value) end
            rawset(action, field, value)
        end
    end
    for _, row in ipairs(MAP) do
        local action, source = mace.actions.action_one[row[1]], result.actions.action_one[row[2]]
        project(action, source)
        for index = 3, #row do
            local name = row[index]
            local field = action.kind == "push_stagger" and (index == 3 and "damage_profile_inner" or "damage_profile_outer")
                or "damage_profile"
            action[field] = PREFIX .. name
            expected_events[#expected_events + 1] = { PREFIX .. name, name }
            if not seen[name] then seen[name] = true; ordered[#ordered + 1] = name end
        end
        if action.kind == "push_stagger" then action.attack_template = rawget(source, "attack_template") end
    end
    project(mace.actions.action_two.default, result.actions.action_two.default)
    result.actions, result.state_machine, result.wield_anim = mace.actions, mace.state_machine, mace.wield_anim
    result[CLAIMS], result[MARKER] = nil, TOKEN
    return result, expected_events, ordered
end
function M.baseline(c)
    local b = c.F.baseline(c); b.events = #c.mace_events; return b
end
function M.verify(H, c, owner, before, expected)
    local name, value = owner.template("mace_on_empire_sword")
    H.equal(name, TEMPLATE); H.truthy(rawequal(value, c.env.Weapons[name]))
    local graph, events, ordered = M.expected(c)
    H.truthy(c.F.same(value, expected or graph), "complete Mace graph plus ONLY approved Sword projection")
    H.equal(#events, 9); H.equal(#ordered, 6)
    for index, event in ipairs(events) do
        local actual = c.mace_events[before.events + index]
        H.equal(actual[1], event[1]); H.equal(actual[2], event[2])
    end
    for index, source in ipairs(ordered) do
        local custom = PREFIX .. source
        H.equal(c.lookup[custom], before.max_id + index); H.equal(c.lookup[before.max_id + index], custom)
        H.equal(c.state._cwv_damage_profile_wire_source[custom], source)
        H.truthy(c.F.same(c.env.DamageProfileTemplates[custom], c.oracle.profiles[source]),
            "literal complete Sword profile, including native armor/critical/target attack IDs")
    end
    H.equal(c.state._cwv_damage_profile_generation, before.generation + 9)
    H.equal(c.audit().profiles, before.audit_profiles + 9)
    H.truthy(c.audit().comparisons > before.comparisons); H.equal(owner.check(), nil)
    local heavy = c.env.DamageProfileTemplates[PREFIX .. PROFILES[1]]
    H.equal(heavy.targets[1].attack_template, "blunt_tank")
    H.equal(heavy.targets[2].attack_template, "blunt_tank")
    H.equal(heavy.targets[3].attack_template, "light_blunt_tank")
    for _, key in ipairs({ "default", "default_right", "default_left", "default_last" }) do
        H.equal(rawget(value.actions.action_one[key], "anim_time_scale"), nil,
            "actual599 implicit charge scale restores raw absence")
    end
end
function M.history(H, record, id)
    local ledger, family = record.runtime.ledgers[FAMILY] or {}, record.runtime.family_by_id[FAMILY]
    H.equal(record.runtime.boot_selections[SETTING], id); H.equal(record.verify(), nil)
    if id == "current" then H.equal(#ledger, 0); H.equal(record.runtime.active[FAMILY], nil); return end
    H.equal(#ledger, id == "5_1_1" and 9 or 6, "full actual9/6 ledger, not filtered3/2")
    for index, row in ipairs(ledger) do
        H.truthy(rawequal(row.operation, family.states[id].operations[index]))
        H.truthy(rawequal(row.owner_object, record.runtime.roots.Weapons[row.template_name]))
    end
end
M.template, M.prefix, M.family, M.setting = TEMPLATE, PREFIX, FAMILY, SETTING
return M
