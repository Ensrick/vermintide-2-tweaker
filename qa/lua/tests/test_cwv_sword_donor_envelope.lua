-- #645 SOURCE-ONLY focused donor-envelope tests. No family/game activation.
-- Real selected WT Owner/runtime/catalog/transaction and complete #348 producer.
-- Opaque career DATA tests shared identity protocol, not a native gameplay body.
return function(H, root, F)
    F = F or assert(loadfile(root .. "/qa/lua/fixtures/cwv_sword_style_construction_harness.lua"))()
    local CP = root .. "/character_weapon_variants/scripts/mods/character_weapon_variants/"
    local FAMILY, SETTING = "one_handed_sword_shared", "wt_history_one_handed_sword_shared"
    local COMBO = "wt_revert_1h_sword_push_combo"
    local DIRECTIONS = { "empire_on_elf", "elven_on_empire" }
    local EMPIRE, ELVEN = "one_handed_swords_template_1", "we_one_hand_sword_template_1"
    local MARKER, CLAIMS = "__vt2_tweaker_career_action_clone_source", "__vt2_tweaker_career_action_claims"
    local CAREER = "action_career_qa_sword_envelope"
    local OLD_CHAIN = {
        { action = "action_one", end_time = 1.2, input = "action_one", release_required = "action_two_hold", start_time = .55, sub_action = "default" },
        { action = "action_one", end_time = 1.2, input = "action_one_hold", release_required = "action_two_hold", start_time = .55, sub_action = "default" },
        { action = "action_one", input = "action_one", start_time = .85, sub_action = "default" },
        { action = "action_two", input = "action_two_hold", start_time = .55, sub_action = "default" },
        { action = "action_wield", input = "action_wield", start_time = .5, sub_action = "default" },
    } -- exact frozen WT #348 producer tuple, not invented native data.
    local function read(path)
        local f = assert(io.open(path, "rb")); local value = f:read("*a"); f:close()
        if value:sub(1, 3) == string.char(239, 187, 191) then value = value:sub(4) end
        return (value:gsub("\r\n", "\n"))
    end
    local function section(source, first, ending, label)
        local a = assert(source:find(first, 1, true), label .. " first anchor")
        assert(not source:find(first, a + 1, true), label .. " first anchor nonunique")
        local b = assert(source:find(ending, a, true), label .. " last anchor")
        assert(not source:find(ending, b + 1, true), label .. " last anchor nonunique")
        return source:sub(a, b - 1)
    end
    local function freeze_oracle(c)
        c.current, c.native_refs = {}, {}
        for _, direction in ipairs(DIRECTIONS) do
            local spec = F.specs[direction]
            local expected, events, ordered = F.expected_template(c, direction)
            expected[MARKER] = spec.template .. "<-" .. spec.donor
            local profiles = {}
            for _, name in ipairs(ordered) do profiles[name] = F.expected_profile(c, name, spec.factor) end
            c.current[direction] = { template = expected, events = events, ordered = ordered, profiles = profiles }
            c.native_refs[direction] = c.env.Weapons[spec.donor]
        end
        c.current_chain = c.env.Weapons[EMPIRE].actions.action_one.light_attack_bopp.allowed_chain_actions
        c.current_chain_graph = assert(c.graph.capture(c.current_chain, 32, 256))
        local profiles = {}; for _, data in pairs(c.current) do
            for name in pairs(data.profiles) do profiles[name] = c.env.DamageProfileTemplates[name] end
        end
        local powers = {}; for name, value in next, c.env.PowerLevelTemplates do powers[name] = value end
        c.current_inputs = { profiles = profiles, powers = powers,
            profile_root = c.env.DamageProfileTemplates, power_root = c.env.PowerLevelTemplates }
        c.current_profile_graph = assert(c.graph.capture({ profiles, powers,
            c.env.ItemMasterList.es_1h_sword, c.env.ItemMasterList.we_1h_sword }, 4096, 65536))
    end
    local function native_inputs(c)
        H.truthy(rawequal(c.env.DamageProfileTemplates, c.current_inputs.profile_root))
        H.truthy(rawequal(c.env.PowerLevelTemplates, c.current_inputs.power_root))
        for name, value in next, c.current_inputs.profiles do
            H.truthy(rawequal(rawget(c.env.DamageProfileTemplates, name), value), "Current native profile root cell")
        end
        for name, value in next, c.current_inputs.powers do
            H.truthy(rawequal(rawget(c.env.PowerLevelTemplates, name), value), "Current native power root cell")
        end
        H.truthy(c.graph.intact(c.current_profile_graph), "Current native member graphs/physical data untouched")
    end
    local function bind_optional(c)
        c.integration = c.T.run(read(CP .. "_lib_career_weapon_actions.lua"), c.env, "actual-career-shared-library")
        c.leaf = c.T.run(read(CP .. "_cwv_sword_donor_envelope.lua"), c.env, "actual-Sword-donor-envelope")
        c.donor_api = c.leaf.bind(c.graph, c.career_envelope, c.core.history_producer_binding,
            c.integration, function() return c.env.ActionTemplates end)
        return c.donor_api
    end
    local setup
    local function install_factory(c, mods, records, id, state, parity, combo, emit)
        H.truthy(id == "wt" or id == "wt_dev")
        local dir = id == "wt" and "weapon_tweaker" or "weapon_tweaker_dev"
        local module_root = "scripts/mods/" .. dir .. "/"
        local enabled, calls = parity == true, { catalog = 0, combo_get = 0, producer = 0, sync = 0 }
        local saved = { [SETTING] = state or "current", [COMBO] = combo == true }
        local mod = { _wt = { dbg = function() end }, get = function(_, key)
            if key == COMBO then calls.combo_get = calls.combo_get + 1 end
            if saved[key] ~= nil then return saved[key] end
            return "current"
        end, _wt431_profiles_allowed = function() return enabled end }
        local loads, canonical = {}, nil
        mod.dofile = function(_, path)
            loads[path] = (loads[path] or 0) + 1
            local value = c.T.run(read(root .. "/" .. dir .. "/" .. path .. ".lua"), c.env, path)
            if path ~= module_root .. "_wt_history_catalog" then return value end
            canonical = value
            return { load = function(actual_mod)
                H.truthy(rawequal(actual_mod, mod)); calls.catalog = calls.catalog + 1
                local original, problem = canonical.load(actual_mod, { module_root .. "_wt_history_5_2_catalog" })
                H.truthy(original, problem)
                local family
                for _, row in ipairs(original.families) do if row.id == FAMILY then
                    H.equal(family, nil, "one actual source Sword family"); family = row
                end end
                H.truthy(family)
                local selected = {}; for key, field in next, original do selected[key] = field end
                selected.families, selected.states, selected.profile_specs, selected.derived_profiles = { family }, {}, {}, {}
                for _, sid in ipairs(family.state_order) do
                    selected.states[sid], selected.profile_specs[sid] = original.states[sid], {}
                    for _, name in ipairs(family.states[sid].profile_names) do
                        selected.profile_specs[sid][name] = assert(original.profile_specs[sid][name])
                    end
                end
                -- Actual composer copies all retained original rows and provenance.
                return canonical.merge({ selected })
            end }
        end
        mods[id] = mod
        local source = read(root .. "/" .. dir .. "/" .. module_root .. dir .. ".lua")
        local boot = section(source, "local _wt348_source_owner =",
            "\n-- #348 retained producer end", "actual retained348 entry capability")
        c.T.run("return function(mod)\n" .. boot .. "\nend", c.env, "actual-retained348-entry")(mod)
        local expression = section(source, "local _wt_history_owner, _wt_history_verify = mod:dofile(",
            "\n-- Bret Sword & Shield damage buff", "actual history entry expression")
        local invoke = c.T.run("return function(mod)\n" .. expression
            .. "\nreturn _wt_history_owner, _wt_history_verify, _wt_history_runtime end", c.env, "actual-WT-history-owner-entry")
        local owner, verify, runtime = invoke(mod)
        H.truthy(rawequal(owner.runtime, runtime)); H.truthy(rawequal(rawget(mod, "_wt_history_runtime"), runtime))
        H.equal(runtime.fatal_error, nil); H.equal(runtime.last_error, nil); H.equal(verify(), nil)
        H.equal(runtime.registration.count, 3); H.equal(calls.catalog, 1)
        local r = { mod = mod, owner = owner, verify = verify, runtime = runtime, saved = saved,
            loads = loads, calls = calls, id = id, state = state or "current", dir = dir,
            set_parity = function(value) enabled = value end }
        function r.produce_combo()
            local balance = read(root .. "/" .. dir .. "/" .. module_root .. "_wt_weapon_balance_patches.lua")
            local complete = section(balance, "local function _patch_kruber_1h_sword_push_combo_revert()",
                "\n-- ============================================================\n-- Warrior Priest punch buff", "complete actual348 producer")
            local actual = c.T.run("return function(mod, _dbg)\n" .. complete
                .. "\nreturn mod._wt348_sword_push_combo end", c.env, "complete-actual-WT348-producer-and-record")
            calls.producer = calls.producer + 1
            local prior, reads = rawget(mod, "_wt348_sword_push_combo"), calls.combo_get
            local row = actual(mod, mod._wt.dbg)
            H.equal(type(row), "table", "actual producer emits applied record")
            H.equal(calls.combo_get, reads + (prior == nil and 1 or 0), "boot checkbox is read only by the retained first producer")
            if prior ~= nil then H.truthy(rawequal(row, prior), "actual producer reentry retains record identity") end
            return row
        end
        if emit then r.produce_combo() end
        local settings = c.T.run(read(root .. "/" .. dir .. "/" .. module_root .. "_wt_settings_runtime.lua"),
            c.env, "actual-WT-setting-callback-owner")
        local nop = function() end
        settings.install({ mod = mod, history_runtime = runtime,
            rework_runtime = { is_batching = function() return false end, on_master_changed = function() return false end,
                sync_for_leaf = function() calls.sync = calls.sync + 1 end, prepare_batch = function() return true end },
            balance_policy = {}, bolt_policy = { SETTING_ID = "qa_unused_bolt" }, bolt_runtime = { apply = nop },
            master_toggles = { reconcile_batch = nop }, backend = { refresh_on_setting_change = nop },
            apply_weapon_unlocks = nop, patch_career_actions = nop, apply_trait_filters = nop })
        records[id] = r
        return r
    end
    -- Case-local optional wiring only; no production routine is substituted.
    setup = function(options)
        options = options or {}
        local mods, records = {}, {}
        local function resolver(id) return rawget(mods, id) end
        local c = F.new(H, root, {
            get_mod = resolver, donor_envelope = bind_optional,
            after_native = function(current)
                freeze_oracle(current); current.records = records
                if options.before then options.before(current) end
                current.install = function(id, state, parity, combo, emit)
                    return install_factory(current, mods, records, id, state, parity, combo, emit)
                end
                if options.early then current.install(options.stream or "wt", options.state or "current",
                    options.parity == true, options.combo == true, options.emit ~= false) end
            end,
        })
        return c
    end
    local function verify_current(c, direction, owner, baseline)
        local spec, oracle = F.specs[direction], c.current[direction]
        local name, template = owner.template(direction)
        H.equal(name, spec.template); H.truthy(rawequal(template, c.env.Weapons[name]))
        H.truthy(F.same(template, oracle.template), "independent complete authored-Current template oracle")
        H.equal(#oracle.events, spec.encounters); H.equal(#oracle.ordered, 6)
        for index, native in ipairs(oracle.ordered) do
            local custom = spec.prefix .. native
            H.equal(c.lookup[custom], baseline.max_id + index)
            H.equal(c.lookup[baseline.max_id + index], custom)
            H.equal(c.state._cwv_damage_profile_wire_source[custom], native)
            H.truthy(F.same(c.env.DamageProfileTemplates[custom], oracle.profiles[native]), "independent complete Current profile oracle")
        end
        for index, event in ipairs(oracle.events) do
            H.equal(c.events[baseline.events + index][1], event[1]); H.equal(c.events[baseline.events + index][2], event[2])
        end
        H.equal(c.state._cwv_damage_profile_generation, baseline.generation + spec.encounters)
        H.equal(c.audit().profiles, baseline.audit_profiles + spec.encounters)
        H.equal(c.state._cwv_profile_multiplier_check(), nil); H.equal(owner.check(), nil)
        native_inputs(c)
        return template
    end
    local function construct(c)
        c.built = {}
        for _, direction in ipairs(DIRECTIONS) do
            local before, owner = F.baseline(c), c.create(direction)
            H.truthy(owner.construct(), "real constructor reaches successful publication")
            local template = verify_current(c, direction, owner, before)
            c.built[direction] = { owner = owner, before = before, template = template }
        end
        c.stable = { generation = c.state._cwv_damage_profile_generation, profiles = c.audit().profiles,
            comparisons = c.audit().comparisons, events = #c.events, fallback = c.state._cwv_wire_fallback_profile_id }
    end
    local function retained(c)
        for _, direction in ipairs(DIRECTIONS) do
            local data, spec, oracle = c.built[direction], F.specs[direction], c.current[direction]
            H.equal(data.owner.check(), nil)
            local _, actual = data.owner.template(direction)
            H.truthy(rawequal(actual, data.template))
            H.truthy(F.same(actual, oracle.template), "retained custom Current graph")
            for index, name in ipairs(oracle.ordered) do
                H.equal(c.lookup[spec.prefix .. name], data.before.max_id + index)
                H.truthy(F.same(c.env.DamageProfileTemplates[spec.prefix .. name], oracle.profiles[name]))
            end
            H.truthy(data.owner.construct(), "owned path is read-only/idempotent")
        end
        H.equal(c.state._cwv_damage_profile_generation, c.stable.generation)
        H.equal(c.audit().profiles, c.stable.profiles); H.equal(c.audit().comparisons, c.stable.comparisons)
        H.equal(#c.events, c.stable.events); H.equal(c.state._cwv_wire_fallback_profile_id, c.stable.fallback)
        native_inputs(c)
    end
    local function actual_history(c, r, state, parity)
        local runtime, ledger = r.runtime, r.runtime.ledgers[FAMILY] or {}
        H.equal(runtime.boot_selections[SETTING], state); H.equal(r.verify(), nil)
        if state == "current" then H.equal(#ledger, 0); H.equal(runtime.active[FAMILY], nil); return end
        local base, extra = state == "5_1_1" and 9 or 7, state == "5_1_1" and 4 or 2
        H.equal(#ledger, base + extra, "complete actual base PLUS synthetic ledger")
        local family = runtime.family_by_id[FAMILY]
        for index = 1, base do H.truthy(rawequal(ledger[index].operation, family.states[state].operations[index])) end
        local seen = 0
        for index = base + 1, #ledger do
            local row = ledger[index]; H.equal(row.operation.synthetic_profile_route, true)
            local native = row.operation.expected_current
            local expected = parity and runtime.registration.private_by_state_name[state][native] or native
            H.equal(row.applied_value, expected); H.equal(rawget(row.parent, row.key), expected); seen = seen + 1
        end
        H.equal(seen, extra); H.equal(runtime.active[FAMILY].parity, parity)
        H.truthy(rawequal(c.env.Weapons[EMPIRE], c.native_refs.empire_on_elf), "actual native donor identity retained")
    end
    local function actual_combo(c, r, enabled)
        local record = r.mod._wt348_sword_push_combo
        H.equal(record.schema, 1); H.equal(record.setting_id, COMBO); H.equal(record.boot_enabled, enabled)
        H.truthy(rawequal(record.weapons, c.env.Weapons)); H.truthy(rawequal(record.source, c.native_refs.empire_on_elf))
        H.truthy(rawequal(record.before, c.current_chain)); H.truthy(c.graph.intact(c.current_chain_graph))
        local chain = c.env.Weapons[EMPIRE].actions.action_one.light_attack_bopp.allowed_chain_actions
        H.truthy(rawequal(record.applied, chain)); H.truthy(F.same(chain, enabled and OLD_CHAIN
            or c.current.empire_on_elf.template.actions.action_one.light_attack_bopp.allowed_chain_actions), "complete actual348/Current five rows")
    end
    local function owned_snapshot(c)
        -- Exclude ONLY the real external producer's donor graph, not owned rows.
        local donor = c.env.Weapons[EMPIRE]
        return assert(c.graph.capture({ c.env.Weapons, c.env.DamageProfileTemplates, c.env.PowerLevelTemplates,
            c.lookup, c.state, c.audit(), c.env.ItemMasterList }, 8192, 131072, function(t, key)
                return not (rawequal(t, c.env.Weapons) and key == EMPIRE)
            end)), donor
    end
    H.test("#645 donor envelope Current both directions no WT", function()
        local c = setup(); local native = assert(c.graph.capture({ c.env.Weapons[EMPIRE], c.env.Weapons[ELVEN] }, 8192, 65536))
        construct(c); retained(c); H.truthy(c.graph.intact(native))
    end)
    H.test("#645 donor envelope Current real WT catalog both directions", function()
        local c = setup({ early = true }); local r = c.records.wt
        actual_history(c, r, "current", false); actual_combo(c, r, false)
        local native = assert(c.graph.capture({ c.env.Weapons[EMPIRE], c.env.Weapons[ELVEN] }, 8192, 65536))
        construct(c); retained(c); H.truthy(c.graph.intact(native))
    end)
    for _, sid in ipairs({ "5_1_1", "5_2_0" }) do for _, enabled in ipairs({ false, true }) do
        local state, parity = sid, enabled
        H.test("#645 donor envelope early " .. state .. " parity=" .. tostring(parity) .. " Current oracle", function()
            local c = setup({ early = true, state = state, parity = parity })
            local r = c.records.wt; actual_history(c, r, state, parity)
            local native = assert(c.graph.capture({ c.env.Weapons[EMPIRE], c.env.Weapons[ELVEN] }, 8192, 65536))
            construct(c); retained(c); H.truthy(c.graph.intact(native), "constructor never rewrites actual WT native state")
        end)
    end end
    for _, sid in ipairs({ "5_1_1", "5_2_0" }) do
        local state = sid
        H.test("#645 donor envelope late " .. state .. " parity restore and no replay", function()
            local c = setup(); construct(c)
            local r = c.install("wt", state, false, false, true)
            actual_history(c, r, state, false); retained(c)
            for _, value in ipairs({ true, false }) do
                r.set_parity(value); H.truthy(r.owner:reconcile("qa-real-parity-edge"))
                actual_history(c, r, state, value); retained(c)
                H.truthy(r.owner:reconcile("qa-repeat")); retained(c)
            end
            H.truthy(r.owner:restore()); H.equal(#r.runtime.ledgers[FAMILY], 0); H.equal(r.runtime.active[FAMILY], nil)
            retained(c)
        end)
    end
    for _, modid in ipairs({ "wt", "wt_dev" }) do for _, flag in ipairs({ false, true }) do for _, timing in ipairs({ "early", "late" }) do
        local id, combo, phase = modid, flag, timing
        H.test("#645 donor envelope348 " .. id .. " boot=" .. tostring(combo) .. " " .. phase, function()
            local c = setup({ early = phase == "early", stream = id, combo = combo })
            if phase == "late" then construct(c) end
            local r = phase == "early" and c.records[id] or c.install(id, "current", false, combo, true)
            actual_combo(c, r, combo)
            if phase == "early" then construct(c) end
            retained(c)
            local record, native = r.mod._wt348_sword_push_combo, assert(c.graph.capture(c.env.Weapons[EMPIRE], 4096, 32768))
            local current_ledger = rawget(r.runtime.ledgers, FAMILY)
            r.saved[COMBO] = not combo; r.mod.on_setting_changed(COMBO)
            H.truthy(rawequal(r.mod._wt348_sword_push_combo, record)); actual_combo(c, r, combo)
            H.equal(r.calls.producer, 1); H.equal(r.calls.combo_get, 1)
            H.truthy(rawequal(rawget(r.runtime.ledgers, FAMILY), current_ledger), "actual Current ledger raw identity after combo callback")
            H.equal(rawget(r.runtime.active, FAMILY), nil, "Current remains inactive after combo callback")
            r.saved[SETTING] = "5_1_1"; r.mod.on_setting_changed(SETTING)
            H.equal(r.runtime.pending[SETTING], true); H.equal(r.runtime.boot_selections[SETTING], "current")
            H.truthy(rawequal(rawget(r.runtime.ledgers, FAMILY), current_ledger), "actual Current ledger raw identity after history callback")
            H.equal(rawget(r.runtime.active, FAMILY), nil, "Current remains inactive after history callback")
            r.mod.on_settings_batch_changed({ SETTING, COMBO })
            H.equal(r.calls.producer, 1); H.equal(r.runtime.boot_selections[SETTING], "current")
            H.equal(r.calls.combo_get, 1); H.equal(r.runtime.pending[SETTING], true)
            H.truthy(rawequal(rawget(r.runtime.ledgers, FAMILY), current_ledger), "actual Current ledger raw identity after batch callback")
            H.equal(rawget(r.runtime.active, FAMILY), nil, "Current remains inactive after batch callback")
            H.truthy(c.graph.intact(native), "saved settings do not reproject restart-bound native state")
            retained(c)
        end)
    end end end
    H.test("#645 donor envelope legacy348 requires actual applied record", function()
        local c = setup({ early = true, combo = true })
        c.records.wt.mod._wt348_sword_push_combo = nil -- legacy: real producer ran, record absent.
        local before = F.snapshot(c); local owner = c.create("empire_on_elf")
        H.equal(owner.construct(), false); H.truthy(owner.check()); F.unchanged(H, c, before)
        local current = setup({ early = true, emit = false })
        construct(current); retained(current) -- old WT with exact Current remains admitted.
    end)
    H.test("#645 donor envelope actual shared career claims and unrelated drift", function()
        local inherited = setup({ before = function(c)
            -- Exercise real inherited-clone restoration, not only an empty prepare.
            local canonical = { opaque_identity_only = true }
            c.env.ActionTemplates[CAREER] = canonical
            local data = { qa_sword_actor = { activated_ability = { { action_name = CAREER } } } }
            local shared = c.T.run(read(CP .. "_lib_career_weapon_actions.lua"), c.env, "actual-early-career-producer")
            c.early_canonical = canonical
            for _, direction in ipairs(DIRECTIONS) do
                local report = shared.install(c.native_refs[direction], { "qa_sword_actor" }, data,
                    c.env.ActionTemplates, "character_weapon_variants")
                H.equal(report.ok, true); H.equal(report.installed, 1)
                -- Declared opaque identity only; gameplay Current oracle stays frozen.
                c.current[direction].template.actions[CAREER] = canonical
            end
        end })
        construct(inherited); retained(inherited)
        for _, direction in ipairs(DIRECTIONS) do
            local data = inherited.built[direction]
            H.truthy(rawequal(data.template.actions[CAREER], inherited.early_canonical))
            H.equal(rawget(data.template, CLAIMS), nil, "copied donor claims discarded by actual prepare")
            local report = inherited.integration.release(inherited.native_refs[direction], "character_weapon_variants")
            H.equal(#report.removed_names, 1); H.equal(data.owner.check(), nil)
        end
        local c = setup(); construct(c)
        -- Explicit opaque identity DATA, not a native career/moveset claim.
        local canonical = { opaque_identity_only = true }
        c.env.ActionTemplates[CAREER] = canonical
        local careers = { qa_sword_actor = { activated_ability = { { action_name = CAREER } } } }
        for _, direction in ipairs(DIRECTIONS) do
            local source, clone = c.native_refs[direction], c.built[direction].template
            for _, template in ipairs({ source, clone }) do
                local report = c.integration.install(template, { "qa_sword_actor" }, careers, c.env.ActionTemplates, "character_weapon_variants")
                H.equal(report.ok, true); H.truthy(rawequal(template.actions[CAREER], canonical))
                H.equal(c.built[direction].owner.check(), nil)
                local released = c.integration.release(template, "character_weapon_variants")
                H.equal(#released.removed_names, 1); H.equal(#released.changed_names, 0)
                H.equal(#released.retained_names, 0); H.equal(rawget(template.actions, CAREER), nil)
                H.equal(c.built[direction].owner.check(), nil)
            end
        end
        -- Protocol may retain empty claim registries, so compare gameplay graph
        -- after removing ONLY that declared shared metadata from private copies.
        for _, direction in ipairs(DIRECTIONS) do
            local actual = c.env.table.clone(c.built[direction].template, true); actual[CLAIMS] = nil
            H.truthy(F.same(actual, c.current[direction].template))
        end
        c.env.Weapons[EMPIRE].unrelated_unknown = true
        H.truthy(c.built.empire_on_elf.owner.check(), "unrelated donor drift is denied")
    end)
    H.test("#645 donor envelope real producer corruption denies retained authority", function()
        local mutations = {
            function(c, r) r.runtime.policy.commit = function() return {} end end,
            function(c, r) r.runtime.roots.Weapons = setmetatable({}, { __eq = function() return true end }) end,
            function(c, r) local row = r.runtime.ledgers[FAMILY][1]; row.parent = {} end,
            function(c, r) r.runtime.ledgers[FAMILY][1].original_value = {} end,
            function(c, r) local row = r.runtime.ledgers[FAMILY][#r.runtime.ledgers[FAMILY]]; rawset(row.parent, row.key, "wt_hist_forged") end,
            function(c, r) r.mod._wt348_sword_push_combo.boot_enabled = false end,
            function(c, r) r.mod._wt348_sword_push_combo.before[1].start_time = .123 end,
            function(c, r) r.mod._wt348_sword_push_combo = nil end,
            function(c, r) c.integration.prepare_inherited_clone = function() return { ok = true } end end,
            function(c, r)
                local row = r.runtime.ledgers[FAMILY][1]
                row.applied_value[1] = c.env.table.clone(row.applied_value[1], true)
                H.equal(r.verify(), nil, "WT semantic equality alone does not prove child identity")
            end,
            function(c, r)
                local row = r.runtime.ledgers[FAMILY][1]
                row.original_value[1] = c.env.table.clone(row.original_value[1], true)
            end,
            function(c, r)
                local canonical = { opaque_identity_only = true }; c.env.ActionTemplates[CAREER] = canonical
                local careers = { qa_sword_actor = { activated_ability = { { action_name = CAREER } } } }
                local source = c.native_refs.empire_on_elf
                H.equal(c.integration.install(source, { "qa_sword_actor" }, careers,
                    c.env.ActionTemplates, "character_weapon_variants").ok, true)
                H.equal(c.built.empire_on_elf.owner.check(), nil, "actual known claim first admitted")
                source[CLAIMS][CAREER].owners.unknown_owner = true
            end,
            function(c, r)
                c.built.empire_on_elf.template.actions.action_one.light_attack_last.buff_data[1].external_multiplier = .123
            end,
        }
        for index, mutate in ipairs(mutations) do
            local c = setup({ early = true, state = "5_1_1", parity = true, combo = true }); construct(c)
            local r = c.records.wt; actual_history(c, r, "5_1_1", true); actual_combo(c, r, true)
            mutate(c, r)
            H.truthy(c.built.empire_on_elf.owner.check(), "actual retained denial " .. index)
        end
    end)
    H.test("#645 donor envelope actual synthetic omission denied", function()
        local c = setup({ early = true, state = "5_1_1", parity = true }); construct(c)
        local r = c.records.wt; actual_history(c, r, "5_1_1", true)
        local ledger = r.runtime.ledgers[FAMILY]
        H.equal(#ledger, 13); H.equal(ledger[#ledger].operation.synthetic_profile_route, true)
        local row = table.remove(ledger)
        H.equal(#ledger, 12); H.equal(rawget(row.parent, row.key), row.applied_value)
        H.equal(r.verify(), nil, "actual WT verifier checks remaining ownership, not required full route cardinality")
        H.truthy(c.built.empire_on_elf.owner.check(), "same actual synthetic-omission authority assertion")
    end)
    for _, subject in ipairs({ "source", "clone" }) do for _, method in ipairs({ "write", "readback" }) do
        local target, mode = subject, method
        H.test("#645 donor envelope exact publication guard " .. target .. " " .. mode, function()
            local c = setup({ early = true, state = "5_1_1", parity = false })
            local r = c.records.wt; actual_history(c, r, "5_1_1", false)
            local canonical = { opaque_identity_only = true }
            c.env.ActionTemplates[CAREER] = canonical
            local careers = { qa_sword_actor = { activated_ability = { { action_name = CAREER } } } }
            local before, donor = owned_snapshot(c); local hit = 0
            local function intervene(t, key, value, tag)
                if tag == "template:cwv_645_empire_sword_style" then
                    hit = hit + 1; H.truthy(rawequal(t, c.env.Weapons)); H.truthy(rawequal(rawget(t, key), value))
                    if target == "source" then
                        r.set_parity(true); H.truthy(r.owner:reconcile("qa-actual-mid-publication-producer"))
                        actual_history(c, r, "5_1_1", true)
                    else
                        local report = c.integration.install(value, { "qa_sword_actor" }, careers,
                            c.env.ActionTemplates, "character_weapon_variants")
                        H.equal(report.ok, true); H.truthy(rawequal(value.actions[CAREER], canonical))
                    end
                end
            end
            local options = {}
            if mode == "write" then options.write = function(t, key, value, tag)
                rawset(t, key, value); intervene(t, key, value, tag)
            end else options.read = function(t, key, tag)
                local value = rawget(t, key); intervene(t, key, value, tag); return value
            end end
            local owner = c.create("empire_on_elf", options)
            H.equal(owner.construct(), false, "exact postpublication graph guard rejects even known lifetime transitions")
            H.equal(hit, 1); H.truthy(owner.check()); H.equal(owner.template("empire_on_elf"), nil)
            H.truthy(rawequal(c.env.Weapons[EMPIRE], donor)); H.truthy(c.graph.intact(before), "all attempted owned rows/audit rolled back")
            if target == "source" then actual_history(c, r, "5_1_1", true) end
        end)
    end end
    return { setup = setup, native_inputs = native_inputs, actual_combo = actual_combo,
        actual_history = actual_history }
end
