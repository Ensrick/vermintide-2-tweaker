-- Actual entry composition/producer/bootstrap/constructor bodies; no style admission.
-- VMF's finite source callbacks run over ordinary recording hosts, not the game.
return function(H, root)
    local CP = "/character_weapon_variants/scripts/mods/character_weapon_variants/"
    local CHECK = "issue645_tuskgor_retained_construction"
    local function read(path)
        local file = assert(io.open(path, "rb")); local value = file:read("*a"); file:close()
        value = value:gsub("\r\n", "\n")
        if value:sub(1, 3) == string.char(239, 187, 191) then value = value:sub(4) end
        return value
    end
    local function span(source, first, following)
        local at = assert(source:find(first, 1, true), "actual source begin missing")
        assert(not source:find(first, at + 1, true), "actual source begin repeated")
        local stop = assert(source:find(following, at + #first, true), "actual source end missing")
        return source:sub(at, stop - 1)
    end
    local function exists(path)
        local file = io.open(path, "rb"); if not file then return false end
        file:close(); return true
    end
    local quiet = setmetatable({ test = function() end, test_if = function() end }, { __index = H })
    local Leaf = assert(loadfile(root .. "/qa/lua/fixtures/cwv_tuskgor_style_construction_harness.lua"))()
    local Integration = assert(loadfile(root .. "/qa/lua/tests/test_cwv_mace_sword_integration.lua"))()(quiet, root)
    local native_root = os.getenv("VT2_SOURCE_ROOT") or root .. "/../Vermintide-2-Source-Code"
    local vmf_root = os.getenv("VT2_VMF_SOURCE_ROOT") or root .. "/../Vermintide-Mod-Framework"
    local vmf_loader = vmf_root .. "/vmf/scripts/mods/vmf/vmf_loader.lua"
    local vmf_events = vmf_root .. "/vmf/scripts/mods/vmf/modules/core/events.lua"
    local available = Leaf.available(root) and exists(vmf_loader) and exists(vmf_events)
    local function native_test(name, body)
        H.test_if(available, name, body, "optional sibling6.13/VMF source inputs absent")
    end
    local function fixture(config)
        config = config or {}
        config.with_tuskgor = true
        local prepare_core = config.prepare_core
        config.prepare_core = function(c)
            Leaf.prepare_core(c, root)
            local actual_policy = c.state.combat_style_policy
            if prepare_core then prepare_core(c) end
            H.truthy(rawequal(c.state.combat_style_policy, actual_policy), "actual pre-core policy must not be replaced")
            c.retained_combat_style_policy = actual_policy
        end
        local prepare = config.prepare_sources
        config.prepare_sources = function(c)
            Leaf.prepare_native(c, root, native_root)
            if prepare then prepare(c) end
        end
        return Integration.fixture(config)
    end
    local function bootstrap(s, c, previous)
        local source = read(root .. CP .. "_cwv_variant_bootstrap_owner.lua")
        -- Same actual prefix/private-register extraction used by acquisition QA.
        -- Localization/unlocks/UI hooks after this boundary are not modeled.
        local stop = assert(source:find("\n\t-- ============================================================\n\t-- Optional mod detection", 1, true))
        local installer = c.T.run(source:sub(1, stop - 1)
            .. "\nreturn register_checks\nend\nreturn install", c.env, "actual-Tuskgor-bootstrap-prefix")
        local entry = read(root .. CP .. "character_weapon_variants.lua")
        local call = span(entry, "_variant_install =\n\tmod:dofile(\"scripts/mods/character_weapon_variants/_cwv_variant_bootstrap_owner\")",
            "\n-- Skin/illusion registrars stay")
        local bind = c.T.run("return function(mod, _om, _variant_definitions, _javelin_runtime, "
            .. "_core_template_construction, _variant_install, _tuskgor_family)\n" .. call
            .. "\nreturn _variant_install end", c.env, "actual-entry-Tuskgor-bootstrap-consumer")
        local mod = { on_all_mods_loaded = previous, dofile = function(_, path)
            H.equal(path, "scripts/mods/character_weapon_variants/_cwv_variant_bootstrap_owner")
            return installer
        end }
        local register = bind(mod, c.state, {}, nil, c.core, c.capsule, s.tuskgor_family)
        local checks = {}
        register(function(name, callback)
            H.equal(checks[name], nil, "actual bootstrap registers each check once")
            checks[name] = callback
        end)
        return mod, checks[CHECK]
    end
    local function vmf_update(c, mod, wt_mod, trace)
        local vmf = { mods = { cwv = mod, wt = wt_mod }, mods_unloading_order = { "wt", "cwv" } }
        -- Exact source dispatch; only its protected-call/logging host is recorded.
        vmf.safe_call_nr = function(_, _, callback, ...) return callback(...) end
        local env = setmetatable({ get_mod = function(id) H.equal(id, "VMF"); return vmf end,
            VT1 = false, Managers = { mod = { _state = "loading" } }, vmf_mod_object = {} }, { __index = _G })
        local events = read(vmf_events)
        local helper_at = assert(events:find("local function run_event(", 1, true))
        local helper_end = assert(events:find("\nend", helper_at, true)) + 3
        local event_at = assert(events:find("function vmf.all_mods_loaded_event()", 1, true))
        local event_end = assert(events:find("\nend", event_at, true)) + 3
        c.T.run(events:sub(1, helper_end) .. "\n" .. events:sub(event_at, event_end),
            env, "actual-VMF-protected-dispatch-and-all-loaded")
        for _, name in ipairs({ "update_package_manager", "mods_update_event", "check_keybinds",
                "execute_queued_chat_command", "generate_keybinds", "initialize_vmf_options_view",
                "create_network_dictionary", "ping_vmf_users" }) do
            local marker = name
            vmf[name] = function() trace[#trace + 1] = marker end
        end
        env.vmf = vmf
        c.T.run(span(read(vmf_loader), "function vmf_mod_object:update(dt)",
            "\nfunction vmf_mod_object:on_unload"), env, "actual-VMF-done-before-all-loaded")
        return function(done)
            env.Managers.mod._state = done and "done" or "loading"
            return env.vmf_mod_object:update(.01)
        end
    end
    local function named(check)
        H.equal(type(check), "function", "Tuskgor named check must be registered by actual bootstrap")
    end
    local function no_admission(s)
        H.equal(s.policy.member("we_spear"), nil)
        H.equal(s.policy.package("we_spear", "tuskgor"), nil)
        H.equal(s.policy.FAMILIES.elf_tuskgor_spears, nil)
        H.equal(s.policy.DIAGNOSTIC_CANDIDATES.elf_tuskgor_spears.members.we_spear, true)
    end
    local CLAIMS = "__vt2_tweaker_career_action_claims"
    local CLONE = "__vt2_tweaker_career_action_clone_source"
    local CAREER = "action_career_we_3"
    local function native_career(c)
        local source = read(native_root .. "/scripts/settings/action_templates.lua")
        c.T.run(span(source, "ActionTemplates.action_career_we_3 = {",
            "\nActionTemplates.action_career_we_3_piercing"), c.env, "actual-native-Elf-career-action")
        return { we_waywatcher = { activated_ability = { { action_name = CAREER } } } }
    end
    local function shared(c, target, owner, careers)
        local report = c.integration.install(target, { "we_waywatcher" }, careers,
            c.env.ActionTemplates, owner)
        H.equal(report.ok, true, "actual shared career installation must succeed")
        H.equal(target.actions[CAREER], c.env.ActionTemplates[CAREER])
        return report
    end
    local function career_constructor(c, options)
        options = options or {}
        local history = c.T.run(read(root .. CP .. "_cwv_tuskgor_history_envelope.lua"),
            c.env, "actual-Tuskgor-career-test-history").bind(c.graph, c.core.history_producer_binding)
        local module = c.T.run(read(root .. CP .. "_cwv_tuskgor_spear_style_construction.lua"),
            c.env, "actual-Tuskgor-career-test-constructor")
        local factory = module.bind(c.helper, c.graph, history, c.career_envelope,
            c.integration, function() return c.env.ActionTemplates end)
        return factory({ state = c.state, clone = function(value) return c.env.table.clone(value, true) end,
            profiles = function() return c.env.DamageProfileTemplates end,
            power_levels = function() return c.env.PowerLevelTemplates end,
            lookup = function() return c.env.NetworkLookup.damage_profiles end,
            weapons = function() return c.env.Weapons end,
            scalar_factory = options.scalar or c.core.detached_scalar_factory,
            read = options.read, write = options.write })
    end
    H.test("645 private family handoff preserves first-call exception identity", function()
        local module = assert(loadfile(root .. CP .. "_cwv_family_bootstrap.lua"))()
        local sentinel, calls = {}, 0
        local ok, problem = pcall(module.install, {}, {
            sword_install = function() error(sentinel, 0) end,
            prepare_tuskgor = function() calls = calls + 1 end,
        })
        H.equal(ok, false); H.equal(problem, sentinel); H.equal(calls, 0)
    end)
    native_test("645 staged Tuskgor actual entry waits for VMF done in both script orders", function()
        for _, order in ipairs({ "wt_first", "cwv_first" }) do
            local s, c = fixture({ history = order == "wt_first" and "current" or nil })
            local before_sword, before_mace = s.family_check(), s.mace_check()
            if order == "wt_first" then H.equal(before_sword, nil); H.equal(before_mace, nil) end
            local trace = {}
            local mod, check = bootstrap(s, c, function() trace[#trace + 1] = "prior_cwv" end)
            named(check); H.equal(check(), "#645 Tuskgor retained bootstrap pending")
            H.equal(c.env.Weapons[Leaf.key], nil)
            local record = c.records.wt or c.install("wt", "current", false)
            local published_sword, published_mace = s.family_check(), s.mace_check()
            local update = vmf_update(c, mod, record.mod, trace)
            local generation = c.state._cwv_damage_profile_generation
            update(false); H.equal(c.env.Weapons[Leaf.key], nil)
            H.equal(c.state._cwv_damage_profile_generation, generation)
            update(true)
            local after_sword, after_mace = s.family_check(), s.mace_check()
            H.equal(after_sword, published_sword, "Tuskgor preserves the actual post-WT Sword verdict")
            H.equal(after_mace, published_mace, "Tuskgor preserves the actual post-WT Mace verdict")
            H.equal(check(), nil, "actual all-loaded callback must initialize the retained Tuskgor owner")
            H.equal(c.state._cwv_damage_profile_generation, generation + 9)
            H.equal(type(c.env.Weapons[Leaf.key]), "table"); no_admission(s)
            H.equal(s.sword_family:package("we_1h_sword", "elven"), "we_one_hand_sword_template_1",
                "native restoration remains the actual live Elf Sword")
            print("TUSKGOR_ORDER_EVIDENCE", order, "before_sword=" .. tostring(before_sword),
                "after_sword=" .. tostring(after_sword), "before_mace=" .. tostring(before_mace),
                "after_mace=" .. tostring(after_mace))
            if order == "wt_first" then H.equal(s.family_check(), nil); H.equal(s.mace_check(), nil) end
            local prior
            for index, value in ipairs(trace) do if value == "prior_cwv" then prior = index end end
            H.truthy(prior, "actual prior CWV callback must run")
        end
    end)
    native_test("645 staged Tuskgor setup refusal preserves actual WT-first Sword and Mace owners", function()
        local ok, s, c = pcall(fixture, { history = "current", before = function(current)
            current.family_module_fault = function(path)
                if path:match("/_cwv_tuskgor_spear_family$") then error("denied-Tuskgor-loader", 0) end
            end
        end })
        H.truthy(ok, "Tuskgor setup failure must not erase the published Sword result")
        H.equal(s.family_check(), nil); H.equal(s.mace_check(), nil)
        local mod, check = bootstrap(s, c, function() end); named(check)
        H.equal(check(), "#645 Tuskgor setup unavailable: denied-Tuskgor-loader")
        local before = Leaf.snapshot(c)
        mod.on_all_mods_loaded(); H.equal(check(), "#645 Tuskgor setup unavailable: denied-Tuskgor-loader")
        H.truthy(c.graph.intact(before)); H.equal(s.family_check(), nil); H.equal(s.mace_check(), nil)
        no_admission(s)
    end)
    native_test("645 staged Tuskgor bind failure is contained and cannot retry", function()
        local s, c = fixture({ history = "current", before = function(current)
            current.tuskgor_bind_calls = 0
            current.record_tuskgor_bind = function()
                current.tuskgor_bind_calls = current.tuskgor_bind_calls + 1
            end
            current.family_module_fault = function(path)
                if path:match("/_cwv_tuskgor_spear_family$") then
                    -- Replace only the handoff pointer AFTER published families bound it.
                    current.saved_producer = current.core.history_producer_binding
                    current.core.history_producer_binding = nil
                end
            end
        end })
        H.equal(s.family_check(), nil); H.equal(s.mace_check(), nil)
        local mod, check = bootstrap(s, c, function() end); named(check)
        H.equal(c.tuskgor_bind_calls, 0)
        local before = Leaf.snapshot(c)
        mod.on_all_mods_loaded(); H.equal(type(check()), "string")
        H.equal(c.tuskgor_bind_calls, 1)
        local reason = check(); H.truthy(reason:find("initialization refused", 1, true))
        H.truthy(c.graph.intact(before), "bind refusal leaves the observed runtime graph untouched")
        c.core.history_producer_binding = c.saved_producer
        local repaired = Leaf.snapshot(c)
        mod.on_all_mods_loaded(); H.equal(check(), reason)
        H.equal(c.tuskgor_bind_calls, 1, "failed initializer must not bind again")
        H.truthy(c.graph.intact(repaired)); H.equal(c.env.Weapons[Leaf.key], nil)
        H.equal(s.family_check(), nil); H.equal(s.mace_check(), nil)
    end)
    native_test("645 staged Tuskgor prior callback exception leaves capture pending", function()
        local s, c = fixture({ history = "current" })
        local sentinel = {}
        local mod, check = bootstrap(s, c, function() error(sentinel, 0) end); named(check)
        local before = Leaf.snapshot(c)
        local ok, problem = pcall(mod.on_all_mods_loaded)
        H.equal(ok, false); H.equal(problem, sentinel, "prior all-loaded exception identity must be preserved")
        H.equal(check(), "#645 Tuskgor retained bootstrap pending")
        H.equal(c.env.Weapons[Leaf.key], nil); H.truthy(c.graph.intact(before))
    end)
    native_test("645 staged Tuskgor construction refusal stays closed after native repair", function()
        local s, c = fixture({ history = "current" })
        c.env.Weapons[Leaf.donor].block_fatigue_point_multiplier = .125
        local mod, check = bootstrap(s, c, function() end); named(check)
        local before = Leaf.snapshot(c)
        mod.on_all_mods_loaded(); local reason = check()
        H.equal(type(reason), "string"); H.truthy(c.graph.intact(before))
        c.env.Weapons[Leaf.donor].block_fatigue_point_multiplier = .5
        local repaired = Leaf.snapshot(c)
        mod.on_all_mods_loaded(); H.equal(check(), reason)
        H.truthy(c.graph.intact(repaired)); H.equal(c.env.Weapons[Leaf.key], nil)
        H.equal(s.family_check(), nil); H.equal(s.mace_check(), nil); no_admission(s)
    end)
    native_test("645 staged Tuskgor successful callback and named checks are read-only reentry", function()
        local s, c = fixture({ history = "current" })
        local prior_calls = 0
        local mod, check = bootstrap(s, c, function() prior_calls = prior_calls + 1 end); named(check)
        mod.on_all_mods_loaded(); H.equal(check(), nil)
        local value, before = c.env.Weapons[Leaf.key], Leaf.snapshot(c)
        mod.on_all_mods_loaded(); H.equal(check(), nil, "successful retained stage cannot be reconstructed")
        H.equal(check(), nil); H.equal(prior_calls, 2)
        H.truthy(rawequal(c.env.Weapons[Leaf.key], value)); H.truthy(c.graph.intact(before))
    end)
    native_test("645 staged Tuskgor actual WT lifecycle and pending choice never recapture", function()
        local s, c = fixture({ history = "current", stream = "wt_dev", tuskgor_history = "pre_3_1_delta" })
        local mod, check = bootstrap(s, c, function() end); named(check)
        mod.on_all_mods_loaded(); H.equal(check(), nil)
        local r = c.records.wt_dev
        H.equal(c.env.Weapons[Leaf.donor].block_fatigue_point_multiplier, .25)
        H.equal(r.owner:restore(), true); H.equal(check(), nil)
        H.equal(c.env.Weapons[Leaf.donor].block_fatigue_point_multiplier, .5)
        H.equal(r.owner:reconcile("Tuskgor-retained-test"), true); H.equal(check(), nil)
        H.equal(c.env.Weapons[Leaf.donor].block_fatigue_point_multiplier, .25)
        local calls, getter = 0, r.mod.get
        r.mod.get = function(...) calls = calls + 1; return getter(...) end
        r.saved.wt_history_tuskgor_spear = "current"
        H.equal(r.runtime:on_setting_changed("wt_history_tuskgor_spear"), true)
        H.equal(r.runtime.pending.wt_history_tuskgor_spear, true)
        H.equal(c.env.Weapons[Leaf.donor].block_fatigue_point_multiplier, .25)
        calls = 0; local before = Leaf.snapshot(c)
        H.equal(check(), nil); mod.on_all_mods_loaded(); H.equal(check(), nil)
        H.equal(calls, 0); H.truthy(c.graph.intact(before))
        local runtime = r.mod._wt_history_runtime
        r.mod._wt_history_runtime = {}
        H.equal(type(check()), "string"); r.mod._wt_history_runtime = runtime
        H.equal(type(check()), "string", "lost producer authority cannot be recaptured")
    end)
    native_test("645 staged Tuskgor canonicalizes inherited Elf claims and permits legitimate release", function()
        local s, c = fixture({ history = "current", before = function(current)
            local source = read(native_root .. "/scripts/settings/action_templates.lua")
            current.T.run(span(source, "ActionTemplates.action_career_we_3 = {",
                "\nActionTemplates.action_career_we_3_piercing"), current.env, "actual-native-Elf-career-action")
            local careers = { we_waywatcher = { activated_ability = { { action_name = "action_career_we_3" } } } }
            H.equal(current.integration.install(current.env.Weapons[Leaf.receiver], { "we_waywatcher" },
                careers, current.env.ActionTemplates, "character_weapon_variants").ok, true)
        end })
        local receiver = c.env.Weapons[Leaf.receiver]
        local inspect = receiver.actions.action_inspect
        local mod, check = bootstrap(s, c, function() end); named(check)
        mod.on_all_mods_loaded(); H.equal(check(), nil)
        local template = assert(c.env.Weapons[Leaf.key])
        local native = c.env.ActionTemplates.action_career_we_3.default.condition_func
        local retained = template.actions.action_career_we_3.default.condition_func
        H.truthy(rawequal(native, retained), "same actual native career condition body retained")
        H.equal(template.actions[CAREER], c.env.ActionTemplates[CAREER], "clone row is the exact canonical table")
        H.equal(rawget(template, CLAIMS), nil, "copied receiver claims must not become clone ownership")
        H.equal(rawget(template, CLONE), Leaf.key .. "<-" .. Leaf.receiver)
        local expected = Leaf.expected_template(c)
        H.equal(c.integration.prepare_inherited_clone(expected, receiver, c.env.ActionTemplates,
            Leaf.key .. "<-" .. Leaf.receiver).ok, true)
        H.truthy(Leaf.same(template, expected), "complete typed-career clone retains the exact authored graph")
        H.truthy(rawequal(receiver.actions.action_inspect, inspect))
        H.equal(#c.integration.release(receiver, "character_weapon_variants").removed_names, 1)
        H.equal(check(), nil, "legitimate source release must preserve the retained career capability")
        H.equal(template.actions[CAREER], c.env.ActionTemplates[CAREER], "inherited canonical clone baseline remains")
        local careers = { we_waywatcher = { activated_ability = { { action_name = CAREER } } } }
        shared(c, template, "character_weapon_variants", careers)
        H.equal(template[CLAIMS][CAREER].baseline_present, true)
        H.equal(#c.integration.release(template, "character_weapon_variants").removed_names, 0)
        H.equal(check(), nil)
        local after = Leaf.snapshot(c); mod.on_all_mods_loaded(); H.equal(check(), nil)
        H.truthy(c.graph.intact(after), "career lifecycle never reconstructs or recaptures")
        H.truthy(rawequal(receiver.actions.action_inspect, inspect))
        H.equal(receiver.actions.action_career_we_3, nil); no_admission(s)
    end)

    native_test("645 typed Tuskgor actual CWV and each WT stream co-own donor receiver and clone", function()
        for _, id in ipairs({ "wt", "wt_dev" }) do
            for _, surface in ipairs({ "donor", "receiver", "clone" }) do
                local careers
                local s, c = fixture({ history = "current", stream = id, before = function(current)
                    careers = native_career(current)
                end })
                local other = id == "wt" and "wt_dev" or "wt"
                H.equal(c.records[other], nil, "only the selected history producer is installed")
                H.equal(c.env.get_mod(other), nil, "the other stream is absent from actual resolution")
                local mod, check = bootstrap(s, c, function() end); named(check)
                mod.on_all_mods_loaded(); H.equal(check(), nil)
                local target = surface == "clone" and c.env.Weapons[Leaf.key] or c.env.Weapons[Leaf[surface]]
                H.equal(rawget(target.actions, CAREER), nil, "actual native selected row starts absent")
                local generation, identity = c.state._cwv_damage_profile_generation, c.env.Weapons[Leaf.key]
                local owners = { "character_weapon_variants", "weapon_tweaker:" .. tostring(c.records[id].mod) }
                for _, owner in ipairs(owners) do shared(c, target, owner, careers); H.equal(check(), nil) end
                for index, owner in ipairs(owners) do
                    local report = c.integration.release(target, owner)
                    H.equal(#report.removed_names, index == #owners and 1 or 0)
                    if index == #owners then H.equal(rawget(target.actions, CAREER), nil)
                    else H.equal(target.actions[CAREER], c.env.ActionTemplates[CAREER]) end
                    H.equal(check(), nil, "actual co-owner release must retain exact capability")
                end
                H.equal(rawget(target, CLAIMS), nil)
                H.equal(c.state._cwv_damage_profile_generation, generation)
                H.equal(c.env.Weapons[Leaf.key], identity)
                H.equal(s.family_check(), nil); H.equal(s.mace_check(), nil); no_admission(s)
            end
        end
    end)
    native_test("645 typed Tuskgor foreign career and unrelated raw graph drift refuse without repair", function()
        local changes = {
            function(c, target) target.actions[CAREER] = {} end,
            function(_, target) target[CLAIMS][CAREER].owners.foreign = true end,
            function(_, target) target[CLAIMS][CAREER].baseline_present = "false" end,
            function(_, target) setmetatable(target[CLAIMS][CAREER].owners, {}) end,
            function(c) c.env.ActionTemplates[CAREER] = {} end,
            function(_, target) target[CLONE] = "foreign<-source" end,
            function(_, target) target.actions.action_two.default.career_r1_foreign = true end,
        }
        for _, surface in ipairs({ "donor", "receiver", "clone" }) do
            for _, change in ipairs(changes) do
                local careers
                local s, c = fixture({ history = "current", before = function(current)
                    careers = native_career(current)
                end })
                local mod, check = bootstrap(s, c, function() end); named(check)
                mod.on_all_mods_loaded(); H.equal(check(), nil)
                local target = surface == "clone" and c.env.Weapons[Leaf.key] or c.env.Weapons[Leaf[surface]]
                shared(c, target, "character_weapon_variants", careers); H.equal(check(), nil)
                change(c, target)
                local after = Leaf.snapshot(c)
                H.equal(type(check()), "string", "foreign typed career or unrelated raw drift must refuse")
                H.truthy(c.graph.intact(after), "retained refusal is read-only")
                no_admission(s)
            end
        end
    end)
    native_test("645 typed Tuskgor strict prepare and commit readsets reject legitimate career drift", function()
        for _, mode in ipairs({ "prepare", "source_commit", "clone_commit" }) do
            local careers
            local s, c = fixture({ history = "current", before = function(current)
                careers = native_career(current)
            end })
            local before, hit, target = Leaf.snapshot(c), 0
            local options = {}
            if mode == "prepare" then
                options.scalar = function(settings)
                    local planner = c.core.detached_scalar_factory(settings)
                    local actual = planner.clone_damage_profile
                    planner.clone_damage_profile = function(...)
                        local name = actual(...)
                        if hit == 0 then
                            hit, target = 1, c.env.Weapons[Leaf.receiver]
                            shared(c, target, "character_weapon_variants", careers)
                        end
                        return name
                    end
                    return planner
                end
            else
                options.write = function(t, key, value, label)
                    rawset(t, key, value)
                    if label == "template:" .. Leaf.key then
                        hit = hit + 1
                        target = mode == "source_commit" and c.env.Weapons[Leaf.receiver] or value
                        shared(c, target, "character_weapon_variants", careers)
                    end
                end
            end
            local owner = career_constructor(c, options)
            H.equal(owner.construct(), false, "legitimate lifetime transition is not mid-transaction permission")
            H.equal(hit, 1, "actual prepare/commit branch must be reached exactly once")
            H.truthy(owner.check():find("Tuskgor transaction rejected", 1, true),
                "actual journal must fail at its normal constructor refusal boundary")
            H.equal(owner.template(), nil); H.equal(rawget(c.env.Weapons, Leaf.key), nil)
            H.equal(target.actions[CAREER], c.env.ActionTemplates[CAREER], "external shared write remains untouched")
            H.equal(#c.integration.release(target, "character_weapon_variants").removed_names, 1)
            H.truthy(c.graph.intact(before), "all owned journal publications roll back, excluding the disclosed external write")
            H.equal(s.family_check(), nil); H.equal(s.mace_check(), nil); no_admission(s)
        end
    end)
    native_test("645 typed Tuskgor partial career wiring cannot select strict-native fallback", function()
        local s, c = fixture({ history = "current" })
        local history = c.T.run(read(root .. CP .. "_cwv_tuskgor_history_envelope.lua"),
            c.env, "actual-Tuskgor-partial-bind-history").bind(c.graph, c.core.history_producer_binding)
        local module = c.T.run(read(root .. CP .. "_cwv_tuskgor_spear_style_construction.lua"),
            c.env, "actual-Tuskgor-partial-bind-constructor")
        local getter = function() return c.env.ActionTemplates end
        for _, missing in ipairs({ "career", "integration", "getter" }) do
            local career, integration, canonical = c.career_envelope, c.integration, getter
            if missing == "career" then career = nil
            elseif missing == "integration" then integration = nil
            else canonical = nil end
            local ok, problem = pcall(module.bind, c.helper, c.graph, history, career, integration, canonical)
            H.equal(ok, false, "partial installed-mode dependencies must not use native-only mode")
            H.truthy(tostring(problem):find("Tuskgor typed career capability required", 1, true))
        end
        no_admission(s)
    end)
end
