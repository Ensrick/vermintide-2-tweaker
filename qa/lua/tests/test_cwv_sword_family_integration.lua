-- Complete Sword-family consumer integration. No live game objects are created.
-- Reuses actual frozen native/core/WT producers and the real actor/world/UI/queue
-- fixtures. The small selector below is the complete native WUE315-334 function;
-- this is selector/caller proof, not whole WUE playback or graphics acceptance.
return function(H, root)
    local F = assert(loadfile(root .. "/qa/lua/fixtures/cwv_sword_style_construction_harness.lua"))()
    local quiet = setmetatable({ test = function() end, test_if = function() end }, { __index = H })
    local Actors = assert(loadfile(root .. "/qa/lua/tests/test_cwv_sword_actor_admission.lua"))()(quiet, root)
    local Donors = assert(loadfile(root .. "/qa/lua/tests/test_cwv_sword_donor_envelope.lua"))()(quiet, root, F)
    local EMPIRE, ELVEN = "one_handed_swords_template_1", "we_one_hand_sword_template_1"
    local SPECS = {
        { direction = "empire_on_elf", key = "we_1h_sword", style = "empire", default = "elven", profile = 12,
            donor = EMPIRE, native = ELVEN, template = "cwv_645_empire_sword_style", prefix = "cwv_645_empire_sword_" },
        { direction = "elven_on_empire", key = "es_1h_sword", style = "elven", default = "empire", profile = 7,
            donor = ELVEN, native = EMPIRE, template = "cwv_645_elven_sword_style", prefix = "cwv_645_elven_sword_" },
    }
    local TARGETS = {
        empire_on_elf = {
            default = "attack_swing_charge_down", default_right = "attack_swing_charge_right_diagonal_pose",
            default_left = "attack_swing_charge_left", heavy_attack_left = "attack_swing_heavy_down",
            heavy_attack_right = "attack_swing_heavy_down_right", light_attack_left = "attack_swing_left_diagonal",
            light_attack_right = "attack_swing_right_diagonal", light_attack_last = "attack_swing_stab",
            light_attack_bopp = "attack_swing_left", push = "attack_push",
        },
        elven_on_empire = {
            default = "attack_swing_charge_left_diagonal", default_right = "attack_swing_charge_left_diagonal",
            default_left = "attack_swing_charge_right_pose", heavy_attack_left = "attack_swing_heavy_down",
            heavy_attack_right = "attack_swing_heavy_down", heavy_attack_up = "attack_swing_heavy_right",
            light_attack_left = "attack_swing_left_diagonal", light_attack_right = "attack_swing_right_diagonal",
            light_attack_last = "attack_swing_down", light_attack_bopp = "attack_swing_left", push = "attack_push",
        },
    } -- Independent literal expectations from approved MATRIX, not production ROUTES.
    local function target(spec, action, name, previous_action, previous_name)
        if action == "action_two" then H.equal(name, "default"); return "parry_pose" end
        if spec.direction == "empire_on_elf" and name == "heavy_attack_left"
            and previous_action == "action_one" and previous_name == "default_left" then
            return "attack_swing_heavy_left_up"
        end
        return assert(TARGETS[spec.direction][name])
    end
    local function get_action_anim_event(previous_action_settings, current_action_settings, skin_data, anim_key)
        if previous_action_settings then
            local anim_event_from_chain = current_action_settings.anim_event_from_chain
            if anim_event_from_chain then
                local lookup_data = previous_action_settings.lookup_data
                local action_anim_data = anim_event_from_chain[lookup_data.action_name]
                if action_anim_data then
                    local sub_action_anim_data = action_anim_data[lookup_data.sub_action_name]
                    if sub_action_anim_data and sub_action_anim_data[anim_key] then
                        return sub_action_anim_data[anim_key]
                    end
                end
            end
        end
        return skin_data and skin_data[anim_key] or current_action_settings[anim_key]
    end
    local function make(options)
        local c = Donors.setup(options or {})
        local baseline = F.baseline(c)
        baseline.fallback = rawget(c.state, "_cwv_wire_fallback_profile_id")
        local native = assert(c.graph.capture({ c.env.Weapons[EMPIRE], c.env.Weapons[ELVEN] }, 8192, 65536))
        local s = Actors.fixture(nil, c)
        H.truthy(c.graph.intact(native), "constructor never decorates native donor tables")
        return s, c, baseline
    end
    local function for_member(s, spec)
        s.item.name, s.remote_item.name = spec.key, spec.key
        s.local_pi, s.remote_pi = spec.profile, spec.profile
        s.inventory._career_name = spec.profile == 7 and "es_native" or "we_native"
        s.runtime.store.items.sword_id = spec.style
    end
    local function corrupt(s, spec)
        local node = s.weapons[spec.template].actions.action_one.default
        local before = node.anim_event_3p
        node.anim_event_3p = "foreign_constructor_cell"
        return function() node.anim_event_3p = before end
    end
    H.test("645 composed real serial constructors preserve full Current graph and all23 nodes110 chains", function()
        local s, c, baseline = make()
        H.equal(c.state._cwv_damage_profile_generation, baseline.generation + 17)
        H.equal(c.audit().profiles, baseline.audit_profiles + 17)
        H.equal(#c.lookup, baseline.max_id + 12)
        H.equal(c.state._cwv_wire_fallback_profile_id, baseline.fallback)
        local nodes, chains, blockers, wield = 0, 0, 0, 0
        for _, spec in ipairs(SPECS) do
            local oracle = c.current[spec.direction]
            local expected = c.env.table.clone(oracle.template, true)
            for group, rows in pairs(expected.actions) do
                if group == "action_one" or group == "action_two" then
                    for name, node in pairs(rows) do
                        nodes = nodes + 1
                        node.anim_event_3p = target(spec, group, name)
                        node.anim_event_from_chain = {}
                    end
                end
            end
            for group, rows in pairs(oracle.template.actions) do
                if group == "action_one" or group == "action_two" then
                    for name, previous in pairs(rows) do
                        for _, row in ipairs(previous.allowed_chain_actions) do
                            chains = chains + 1
                            if row.action == "action_wield" then
                                wield = wield + 1
                            elseif row.action == nil then
                                blockers = blockers + 1
                            else
                                local node = expected.actions[row.action][row.sub_action]
                                local from = node.anim_event_from_chain[group] or {}
                                node.anim_event_from_chain[group] = from
                                from[name] = { anim_event_3p = target(spec, row.action, row.sub_action, group, name) }
                                local actual = s.weapons[spec.template].actions[row.action][row.sub_action]
                                -- Native-created lookup metadata, not fabricated action behavior.
                                local predecessor = { lookup_data = { action_name = group, sub_action_name = name } }
                                H.equal(get_action_anim_event(predecessor, actual,
                                    { anim_event_3p = "unrelated_skin_override" }, "anim_event_3p"),
                                    target(spec, row.action, row.sub_action, group, name), "every actual native chain edge")
                                H.equal(get_action_anim_event(predecessor, actual, nil, "anim_event"),
                                    oracle.template.actions[row.action][row.sub_action].anim_event, "native1P selector is unchanged")
                            end
                        end
                    end
                end
            end
            H.truthy(F.same(s.weapons[spec.template], expected), "independent complete Current plus ONLY authored3P selectors")
            H.equal(s.weapons[spec.template].wield_anim, "to_1h_sword")
            for native, profile in pairs(oracle.profiles) do
                H.truthy(F.same(c.env.DamageProfileTemplates[spec.prefix .. native], profile), "one private scalar, no double WT math")
                H.equal(c.state._cwv_damage_profile_wire_source[spec.prefix .. native], native)
            end
            local name, value = s.sword_family:package(spec.key, spec.style)
            H.equal(name, spec.template); H.equal(value, s.weapons[name])
            H.equal(s.policy.package(spec.key, spec.style).presentation, nil, "no physical1.15 scale or grip transform")
        end
        H.equal(nodes, 23); H.equal(chains, 110); H.equal(blockers, 6); H.equal(wield, 23)
        Donors.native_inputs(c); H.equal(s.family_check(), nil)
    end)
    for _, member in ipairs(SPECS) do
        local spec = member
        H.test("645 composed " .. spec.direction .. " retained loss gates local UI template rider and dormant preference", function()
            local s = make(); for_member(s, spec)
            H.truthy(s.runtime:describe(s.item))
            local restore = corrupt(s, spec)
            H.equal(s.runtime:describe(s.item), nil, "retained construction loss must hide actual local selector")
            H.truthy(s.family_check())
            H.equal(s.runtime:resolve_template(s.item), nil, "nil delegates the actual native backend")
            H.equal(s.runtime:effective_template_name(s.item, nil, s.unit, "slot_melee"), nil)
            H.equal(s.runtime:local_style_rider("slot_melee", spec.key), nil)
            H.equal(s.runtime:set_item_style(s.item, nil, spec.default, "lost", false), false)
            H.equal(s.runtime:request_item_style(s.item, nil, spec.default, "lost", true), false)
            H.equal(s.runtime.store.items.sword_id, spec.style); H.equal(s.writes, 0)
            restore()
            H.equal(s.runtime:resolve_template(s.item), s.weapons[spec.template])
            H.equal(s.runtime.store.items.sword_id, spec.style)
        end)
        H.test("645 composed " .. spec.direction .. " unknown construction does not burn remote edge and rechecks actual deferred queue", function()
            local s = make(); for_member(s, spec)
            local restore = corrupt(s, spec)
            H.equal(s.runtime:accept_style_edge("remote", "slot_melee", s.family, spec.style, "style_channel"), false)
            H.equal(s.runtime.remote.remote, nil); H.equal(next(s.runtime.pending_remote), nil)
            H.equal(next(s.runtime.fallback_remote), nil); H.equal(s.coalescer.depth(), 0)
            restore()
            H.equal(s.runtime:accept_style_edge("remote", "slot_melee", s.family, spec.style, "identity"), true)
            H.equal(s.coalescer.depth(), 1)
            local token = s.runtime.remote.remote.slot_melee.token
            local again = corrupt(s, spec)
            H.equal(s.runtime:effective_template_name(s.remote_item, nil, s.remote_unit, "slot_melee"), nil)
            H.equal(s.runtime:begin_husk_wield({ _unit = s.remote_unit }, "slot_melee"), false)
            H.equal(s.runtime:resolve_template(s.remote_item), nil); s.runtime:end_husk_wield()
            s.coalescer.drain({ unit_api = s.units, script_unit = s.script, silent = true })
            H.equal(s.wields, 0); H.equal(s.coalescer.depth(), 0)
            H.equal(s.runtime.remote.remote.slot_melee.token, token)
            H.equal(s.runtime.store.items.sword_id, spec.style)
            again()
            H.equal(s.runtime:effective_template_name(s.remote_item, nil, s.remote_unit, "slot_melee"), spec.template)
        end)
        H.test("645 composed " .. spec.direction .. " async completion cannot persist a lost target constructor", function()
            local s = make(); for_member(s, spec)
            s.runtime.store.items.sword_id = spec.default
            local window = { hero_name = spec.profile == 7 and "empire_soldier" or "wood_elf", career_index = 1 }
            local done
            H.equal(s.runtime:request_item_style(s.item, nil, spec.style, "real-C-async", true,
                function(value) done = value end, s.runtime:loadout_actor(window)), true)
            H.equal(type(s.complete), "function")
            local restore = corrupt(s, spec); s.complete(true)
            H.equal(done, false); H.equal(s.runtime.pending.sword_id, nil)
            H.equal(s.runtime.store.items.sword_id, spec.default); H.equal(s.writes, 0); H.equal(s.wields, 0)
            H.equal(s.runtime:resolve_template(s.item), s.weapons[spec.native], "native default does not depend on failed custom proof")
            restore()
        end)
    end
    for _, timing in ipairs({ "early", "late" }) do
        for _, selected in ipairs({ "5_1_1", "5_2_0" }) do
            local phase, state = timing, selected
            H.test("645 composed actual WT " .. state .. " " .. phase .. " custom stays Current native restoration keeps live history348", function()
                local s, c = make({ early = phase == "early", state = state, parity = true, combo = true })
                local record = phase == "early" and c.records.wt or c.install("wt", state, true, true, true)
                Donors.actual_history(c, record, state, true); Donors.actual_combo(c, record, true)
                H.equal(s.family_check(), nil)
                for _, spec in ipairs(SPECS) do
                    for_member(s, spec)
                    local live = c.env.Weapons[spec.native]
                    local before = assert(c.graph.capture(live, 4096, 32768))
                    s.runtime.store.items.sword_id = spec.default
                    H.equal(s.runtime:resolve_template(s.item), live, "actual live native donor, never captured Current writeback")
                    H.equal(s.runtime:set_item_style(s.item, nil, spec.style, "real-C-custom", false), true)
                    H.equal(s.runtime:resolve_template(s.item), c.env.Weapons[spec.template])
                    local custom = c.env.Weapons[spec.template]
                    local current = c.current[spec.direction].template.actions.action_one.light_attack_bopp.allowed_chain_actions
                    H.truthy(F.same(custom.actions.action_one.light_attack_bopp.allowed_chain_actions, current),
                        "actual348 normalizes custom chain to Current before retained snapshot")
                    for _, edge in ipairs(current) do
                        if edge.action == "action_one" or edge.action == "action_two" then
                            local previous = { lookup_data = { action_name = "action_one", sub_action_name = "light_attack_bopp" } }
                            H.equal(get_action_anim_event(previous, custom.actions[edge.action][edge.sub_action], nil, "anim_event_3p"),
                                target(spec, edge.action, edge.sub_action, "action_one", "light_attack_bopp"))
                        end
                    end
                    H.equal(s.runtime:set_item_style(s.item, nil, spec.default, "native-restore", false), true)
                    H.equal(s.runtime:resolve_template(s.item), live)
                    H.truthy(c.graph.intact(before), "native restoration wrote no Current values over WT")
                end
                H.equal(s.family_check(), nil); Donors.native_inputs(c)
            end)
        end
    end
    H.test("645 composed lost target constructor hides both actual installed native-default UI controls", function()
        local desktop = { scenegraph_definition = {}, widgets = {} }
        local console = { generic_input_actions = { default = {}, default_no_customization = {} } }
        console.create_loadout_grid_func = function()
            return { element = { passes = {} }, content = { rows = 1, columns = 1,
                hotspot_1_1 = { is_selected = true } }, style = {
                customize_hotspot_1_1 = { offset = { 20, 3, 2 } },
                customize_item_hover_1_1 = { offset = { 20, 3, 2 } } } }
        end
        local env = setmetatable({ printf = function() end, local_require = function(name)
            if name:find("hero_window_loadout_console_definitions", 1, true) then return console end
            if name:find("hero_window_loadout_definitions", 1, true) then return desktop end
            error("unexpected native definitions")
        end }, { __index = _G })
        local s, hooks = Actors.fixture(env, Donors.setup({})), {}
        s.runtime.store.items.sword_id = "empire"
        s.mod.hook = function(_, class, name, fn) hooks[class .. "." .. name] = fn end
        H.equal(s.policy.install_loadout_ui(s.mod, s.runtime, s.ui_installer), true)
        local grid = console.create_loadout_grid_func()
        grid.content.item_1_1 = { data = s.item, backend_id = "sword_id" }
        local dw = { hero_name = "empire_soldier", career_index = 1,
            parent = { get_selected_loadout_slot_index = function() return 1 end },
            _equipment_items = { { data = s.item, backend_id = "sword_id" } },
            _widgets_by_name = { cwv_combat_style_button = { content = { button_hotspot = {} } },
                cwv_combat_style_status = { content = {} } } }
        local cw = { hero_name = "empire_soldier", career_index = 1, _widgets_by_name = { loadout_grid = grid } }
        local dp, cp = hooks["HeroWindowLoadout._populate_loadout"], hooks["HeroWindowLoadoutConsole._populate_loadout"]
        H.equal(dp(function() return 41 end, dw), 41); H.equal(cp(function() return 43 end, cw), 43)
        H.equal(dw._widgets_by_name.cwv_combat_style_button.content.visible, true)
        H.equal(grid.content.cwv_style_hotspot_1_1.cwv_visible, true)
        dw._widgets_by_name.cwv_combat_style_button.content.button_hotspot.on_release = true
        local restore = corrupt(s, SPECS[2])
        H.truthy(s.runtime:describe(s.item), "live native package remains authoritative")
        dp(function() end, dw); cp(function() end, cw)
        H.equal(dw._widgets_by_name.cwv_combat_style_button.content.visible, false)
        H.equal(dw._widgets_by_name.cwv_combat_style_button.content.button_hotspot.on_release, false)
        H.equal(grid.content.cwv_style_hotspot_1_1.cwv_visible, false)
        H.equal(s.runtime:request_item_style(s.item, nil, "elven", "unavailable UI target", true), false)
        H.equal(s.complete, nil, "no resource acquisition before target authority")
        H.equal(s.runtime.store.items.sword_id, "empire"); H.equal(s.writes, 0)
        restore()
    end)
    H.test("645 composed actual consumers retain the shared career install release protocol", function()
        local s, c = make()
        -- Opaque identity DATA only, not a native career-action gameplay claim.
        local career, canonical = "action_career_qa_sword_envelope", { opaque_identity_only = true }
        c.env.ActionTemplates[career] = canonical
        local careers = { qa_sword_actor = { activated_ability = { { action_name = career } } } }
        for _, spec in ipairs(SPECS) do
            for_member(s, spec)
            for _, template in ipairs({ c.env.Weapons[spec.donor], c.env.Weapons[spec.template] }) do
                local report = c.integration.install(template, { "qa_sword_actor" }, careers,
                    c.env.ActionTemplates, "character_weapon_variants")
                H.equal(report.ok, true); H.equal(template.actions[career], canonical)
                H.equal(s.runtime:resolve_template(s.item), c.env.Weapons[spec.template])
                H.equal(s.family_check(), nil)
                local released = c.integration.release(template, "character_weapon_variants")
                H.equal(#released.removed_names, 1); H.equal(#released.changed_names, 0)
                H.equal(rawget(template.actions, career), nil)
                H.equal(s.runtime:resolve_template(s.item), c.env.Weapons[spec.template])
                H.equal(s.family_check(), nil)
            end
        end
    end)
    H.test("645 composed actual entry registry readers fail unknown safely while live native restoration stays distinct", function()
        local s, c = make()
        local registry, prior_meta = c.env.Weapons, getmetatable(c.env)
        for _, fault in ipairs({ "non-table", "throwing-reader" }) do
            if fault == "non-table" then
                rawset(c.env, "Weapons", false)
            else
                rawset(c.env, "Weapons", nil)
                local previous = prior_meta and prior_meta.__index
                setmetatable(c.env, { __index = function(env, key)
                    if key == "Weapons" then error("destroyed registry reader", 0) end
                    if type(previous) == "function" then return previous(env, key) end
                    if type(previous) == "table" then return previous[key] end
                end })
            end
            local ok, name = pcall(s.sword_family.package, s.sword_family, "es_1h_sword", "elven")
            H.equal(ok, true); H.equal(name, nil)
            ok, name = pcall(s.sword_family.package, s.sword_family, "es_1h_sword", "empire")
            H.equal(ok, true); H.equal(name, nil, "unreadable registry is not captured native authority")
            ok, name = pcall(s.runtime.resolve_template, s.runtime, s.item)
            H.equal(ok, true); H.equal(name, nil)
            local checked, reason = pcall(s.family_check)
            H.equal(checked, true); H.truthy(reason)
            H.equal(s.runtime.store.items.sword_id, "elven"); H.equal(s.writes, 0)
            setmetatable(c.env, prior_meta); rawset(c.env, "Weapons", registry)
            H.equal(s.runtime:resolve_template(s.item), registry.cwv_645_elven_sword_style)
            H.equal(s.family_check(), nil)
        end
        local restore = corrupt(s, SPECS[2])
        local native = s.runtime:package("es_1h_sword", "empire")
        H.truthy(native); H.equal(native.template, EMPIRE, "readable live native remains independent of failed custom authority")
        restore()
    end)
    H.test("645 composed catalogue drift refuses real selectors without erasing saved style", function()
        local s = make()
        local family = s.policy.FAMILIES.one_handed_swords
        local prior = family.styles.elven.receivers.es_1h_sword.template
        family.styles.elven.receivers.es_1h_sword.template = "foreign"
        H.equal(s.runtime:describe(s.item), nil); H.truthy(s.family_check())
        H.equal(s.runtime:accept_style_edge("remote", "slot_melee", s.family, "elven", "identity"), false)
        H.equal(s.runtime.remote.remote, nil); H.equal(s.runtime.store.items.sword_id, "elven"); H.equal(s.writes, 0)
        family.styles.elven.receivers.es_1h_sword.template = prior
        H.truthy(s.runtime:describe(s.item)); H.equal(s.family_check(), nil)
    end)
end
