-- Extended fail-closed planner/commit adversaries for issue #1413.
return function(H, C)
    local fixture, Registrar = assert(C.fixture), assert(C.Registrar)
    local assert_unpublished = assert(C.assert_unpublished)
    local STAT_NAMES, clone = assert(C.STAT_NAMES), assert(C.clone)
    local Lookup, STRICT = assert(C.Lookup), assert(C.STRICT)
    local repo_root = assert(C.repo_root)

    -- Faithful to Foundation table.clone for ordinary nil-metatable tables:
    -- every occurrence is recursively cloned without a global seen map.
    local function foundation_clone(value)
        if type(value) ~= "table" then return value end
        local copied = {}
        for key, child in next, value do
            copied[key] = type(child) == "table"
                and foundation_clone(child) or child
        end
        return copied
    end

    H.test("ET #1413 reuses a preseeded statistics path without capacity", function()
        local fx = fixture("et_preseeded_statistics_path")
        local axis = fx.runtime.network_lookup.statistics_path_names
        rawset(axis, 2, fx.name)
        rawset(axis, fx.name, 2)
        fx.runtime.network.type_info = function(kind)
            if kind == "statistics_path_lookup" then
                error("exact statistics path must not read capacity")
            end
            return { max = 2 }
        end
        H.equal(Registrar.register(fx.spec, fx.runtime), true)
        local marker = fx.runtime.breeds[fx.name][Registrar.marker_key]
        H.equal(marker.statistics_path_index, 2)
        fx.runtime.network = nil
        fx.runtime.network_constants = nil
        H.equal(Registrar.register(fx.spec, fx.runtime), true,
            "preseeded path identity must survive exact reload without capacity")
    end)

    H.test("ET #1413 difficulty output graph topology is source-authoritative", function()
        local function prepared(suffix)
            local fx = fixture("et_overlay_graph_" .. suffix)
            fx.source_actions.attack = nil
            fx.source_actions.left = {
                difficulty_diminishing_damage = { { token = 1 } },
            }
            fx.source_actions.right = {
                difficulty_diminishing_damage = { { token = 1 } },
            }
            H.equal(Registrar.register(fx.spec, fx.runtime), true)
            local live = fx.runtime.actions[fx.name]
            fx.source_actions.left.diminishing_damage = { token = 1 }
            fx.source_actions.right.diminishing_damage = { token = 1 }
            live.left.diminishing_damage = { token = 1 }
            live.right.diminishing_damage = { token = 1 }
            fx.readiness.ready = false
            return fx, fx.source_actions, live
        end

        local cases = {
            { "equal_distinct_became_aliased", function(_, _, live)
                live.right.diminishing_damage = live.left.diminishing_damage
            end },
            { "source_shared_became_split", function(_, source)
                source.right.diminishing_damage = source.left.diminishing_damage
            end },
            { "live_source_alias", function(_, source, live)
                live.left.diminishing_damage = source.left.diminishing_damage
            end },
            { "live_declaration_alias", function(_, _, live)
                live.left.diminishing_damage =
                    live.left.difficulty_diminishing_damage[1]
            end },
        }
        for i = 1, #cases do
            local case = cases[i]
            local fx, source, live = prepared(case[1])
            case[2](fx, source, live)
            local events_before = #fx.events
            local ok, reason = Registrar.register(fx.spec, fx.runtime)
            H.equal(ok, nil, case[1] .. " overlay graph drift was accepted")
            H.equal(reason, "existing_actions_overlay_mismatch")
            H.equal(#fx.events, events_before,
                case[1] .. " overlay graph drift reached a write")
            H.equal(fx.readiness.ready, false)
        end

        local cyclic, source, live = prepared("cyclic_shared_control")
        local source_shared = { leaf = { value = 4 } }
        source_shared.alias = source_shared.leaf
        source_shared.self = source_shared
        source.left.diminishing_damage = source_shared
        source.right.diminishing_damage = source_shared
        local live_shared = { leaf = { value = 4 } }
        live_shared.alias = live_shared.leaf
        live_shared.self = live_shared
        live.left.diminishing_damage = live_shared
        live.right.diminishing_damage = live_shared
        cyclic.readiness.ready = true
        H.equal(Registrar.validate_registered(cyclic.spec, cyclic.runtime), true,
            "matching disjoint cyclic/shared output topology was rejected")
    end)

    H.test("ET #1413 accepts real Chosen declaration topology after Foundation clone", function()
        -- Vanilla chaos_warrior actions special_attack_sweep,
        -- running_attack_right, and special_attack_launch share
        -- BreedTweaks.difficulty_damage.elite_attack. Foundation table.clone
        -- recursively clones each occurrence without a seen map, so the ET
        -- clone legitimately splits that one donor declaration three ways.
        local fx = fixture("et_chosen_foundation_clone_topology")
        local shared_declaration = { 11, 21 }
        fx.source_actions.attack = nil
        fx.source_actions.special_attack_sweep = {
            difficulty_damage = shared_declaration,
        }
        fx.source_actions.running_attack_right = {
            difficulty_damage = shared_declaration,
        }
        fx.source_actions.special_attack_launch = {
            difficulty_damage = shared_declaration,
        }
        fx.runtime.clone = foundation_clone
        H.equal(Registrar.register(fx.spec, fx.runtime), true)

        local live = fx.runtime.actions[fx.name]
        local marker = fx.runtime.breeds[fx.name][Registrar.marker_key]
        local canonical = marker.actions_snapshot
        H.truthy(rawequal(
            fx.source_actions.special_attack_sweep.difficulty_damage,
            fx.source_actions.running_attack_right.difficulty_damage))
        H.truthy(not rawequal(live.special_attack_sweep.difficulty_damage,
            live.running_attack_right.difficulty_damage))
        H.truthy(not rawequal(live.running_attack_right.difficulty_damage,
            live.special_attack_launch.difficulty_damage))
        H.truthy(not rawequal(
            canonical.special_attack_sweep.difficulty_damage,
            canonical.running_attack_right.difficulty_damage))
        H.truthy(not rawequal(
            canonical.running_attack_right.difficulty_damage,
            canonical.special_attack_launch.difficulty_damage))

        for _, actions in ipairs({ fx.source_actions, live }) do
            for _, action in next, actions do
                action.damage = action.difficulty_damage[2]
            end
        end
        local events_before = #fx.events
        local fresh = assert(loadfile(repo_root
            .. "/enemy_tweaker/scripts/mods/enemy_tweaker/"
            .. "_et_custom_breed_registrar.lua"))()
        fresh.lookup_lib = Lookup
        H.equal(fresh.validate_registered(fx.spec, fx.runtime), true)
        H.equal(#fx.events, events_before,
            "valid Chosen clone topology caused a validation write")
        local ok, reason, same = fresh.register(fx.spec, fx.runtime)
        H.equal(ok, true)
        H.equal(reason, "revalidated")
        H.equal(same, fx.runtime.breeds[fx.name])
        H.equal(#fx.events, events_before + 1)
        H.equal(fx.events[#fx.events], "threat",
            "exact reload performed a structural raw write")
        local after_reload = #fx.events
        H.equal(fresh.validate_registered(fx.spec, fx.runtime), true)
        H.equal(#fx.events, after_reload,
            "post-reload Chosen validation caused a write")
    end)

    H.test("ET #1413 pins donor declaration topology independently", function()
        local action_names = {
            "special_attack_sweep", "running_attack_right",
            "special_attack_launch",
        }
        local function prepared(suffix, shared)
            local fx = fixture("et_donor_declaration_topology_" .. suffix)
            fx.source_actions.attack = nil
            local common = { 11, 21 }
            for i = 1, #action_names do
                fx.source_actions[action_names[i]] = {
                    difficulty_damage = shared and common or { 11, 21 },
                }
            end
            fx.runtime.clone = foundation_clone
            H.equal(Registrar.register(fx.spec, fx.runtime), true)
            return fx
        end

        local distinct = prepared("distinct_to_shared", false)
        distinct.source_actions.running_attack_right.difficulty_damage =
            distinct.source_actions.special_attack_sweep.difficulty_damage
        local distinct_events = #distinct.events
        local distinct_ok, distinct_reason = Registrar.register(
            distinct.spec, distinct.runtime)
        H.equal(distinct_ok, nil)
        H.equal(distinct_reason, "existing_actions_overlay_source_mismatch")
        H.equal(#distinct.events, distinct_events,
            "distinct-to-shared donor drift reached a write")

        local shared = prepared("shared_to_distinct", true)
        shared.source_actions.running_attack_right.difficulty_damage = { 11, 21 }
        local shared_events = #shared.events
        local shared_ok, shared_reason = Registrar.register(
            shared.spec, shared.runtime)
        H.equal(shared_ok, nil)
        H.equal(shared_reason, "existing_actions_overlay_source_mismatch")
        H.equal(#shared.events, shared_events,
            "shared-to-distinct donor drift reached a write")

        local marker_tamper = prepared("marker_authority_tamper", true)
        local marker = marker_tamper.runtime.breeds[marker_tamper.name]
            [Registrar.marker_key]
        marker.source_overlay_snapshot[1].declaration[1] = 999
        marker_tamper.readiness.ready = false
        local marker_events = #marker_tamper.events
        local marker_ok, marker_reason = Registrar.register(
            marker_tamper.spec, marker_tamper.runtime)
        H.equal(marker_ok, nil)
        H.equal(marker_reason, "existing_actions_overlay_source_mismatch")
        H.equal(#marker_tamper.events, marker_events,
            "donor marker tamper reached a write")
        H.equal(marker_tamper.readiness.ready, false)

        local marker_missing = prepared("marker_authority_missing", true)
        local missing_marker = marker_missing.runtime.breeds[marker_missing.name]
            [Registrar.marker_key]
        missing_marker.source_overlay_snapshot = nil
        marker_missing.readiness.ready = false
        local missing_events = #marker_missing.events
        local missing_ok, missing_reason = Registrar.register(
            marker_missing.spec, marker_missing.runtime)
        H.equal(missing_ok, nil)
        H.equal(missing_reason, "existing_breed_fingerprint_mismatch")
        H.equal(#marker_missing.events, missing_events)
        H.equal(marker_missing.readiness.ready, false)

        local donor_alias = prepared("marker_authority_donor_alias", true)
        local donor_marker = donor_alias.runtime.breeds[donor_alias.name]
            [Registrar.marker_key]
        donor_marker.source_overlay_snapshot = donor_alias.source_actions
        donor_alias.readiness.ready = false
        local donor_events = #donor_alias.events
        local donor_ok, donor_reason = Registrar.register(
            donor_alias.spec, donor_alias.runtime)
        H.equal(donor_ok, nil)
        H.equal(donor_reason, "existing_actions_overlay_source_mismatch")
        H.equal(#donor_alias.events, donor_events)
        H.equal(donor_alias.readiness.ready, false)

        local canonical_alias = prepared(
            "marker_authority_canonical_alias", true)
        local canonical_marker = canonical_alias.runtime.breeds[
            canonical_alias.name][Registrar.marker_key]
        canonical_marker.source_overlay_snapshot =
            canonical_marker.actions_snapshot
        canonical_alias.readiness.ready = false
        local canonical_events = #canonical_alias.events
        local canonical_ok, canonical_reason = Registrar.register(
            canonical_alias.spec, canonical_alias.runtime)
        H.equal(canonical_ok, nil)
        H.equal(canonical_reason, "existing_actions_overlay_source_mismatch")
        H.equal(#canonical_alias.events, canonical_events)
        H.equal(canonical_alias.readiness.ready, false)

        local live_alias = prepared("marker_authority_live_alias", true)
        local live_marker = live_alias.runtime.breeds[live_alias.name]
            [Registrar.marker_key]
        live_marker.source_overlay_snapshot = live_marker.actions_ref
        live_alias.readiness.ready = false
        local live_events = #live_alias.events
        local live_ok, live_reason = Registrar.register(
            live_alias.spec, live_alias.runtime)
        H.equal(live_ok, nil)
        H.equal(live_reason, "existing_actions_overlay_source_mismatch")
        H.equal(#live_alias.events, live_events)
        H.equal(live_alias.readiness.ready, false)
    end)

    H.test("ET #1413 rejects mutable table keys and metatables before writes", function()
        local presentation_key = fixture("et_presentation_table_key")
        presentation_key.spec.presentations[3].value = {
            [{ identity = "mutable" }] = { value = 4 },
        }
        local key_ok, key_reason = Registrar.register(
            presentation_key.spec, presentation_key.runtime)
        H.equal(key_ok, nil)
        H.equal(key_reason, "presentation_3_copy_failed")
        H.equal(#presentation_key.events, 0)
        assert_unpublished(presentation_key)

        local presentation_meta = fixture("et_presentation_metatable")
        presentation_meta.spec.presentations[3].value = setmetatable(
            { nested = { value = 4 } }, { mutable = true })
        local meta_ok, meta_reason = Registrar.register(
            presentation_meta.spec, presentation_meta.runtime)
        H.equal(meta_ok, nil)
        H.equal(meta_reason, "presentation_3_copy_failed")
        H.equal(#presentation_meta.events, 0)
        assert_unpublished(presentation_meta)

        local snapshot_key = fixture("et_snapshot_table_key")
        snapshot_key.source_actions.attack[{ identity = "mutable" }] = {
            value = 4,
        }
        local snapshot_key_ok, snapshot_key_reason = Registrar.register(
            snapshot_key.spec, snapshot_key.runtime)
        H.equal(snapshot_key_ok, nil)
        H.equal(snapshot_key_reason, "actions_snapshot_failed")
        H.equal(#snapshot_key.events, 0)
        assert_unpublished(snapshot_key)

        local snapshot_meta = fixture("et_snapshot_metatable")
        snapshot_meta.source_actions.attack.nested = setmetatable(
            { value = 4 }, { mutable = true })
        local snapshot_meta_ok, snapshot_meta_reason = Registrar.register(
            snapshot_meta.spec, snapshot_meta.runtime)
        H.equal(snapshot_meta_ok, nil)
        H.equal(snapshot_meta_reason, "actions_snapshot_failed")
        H.equal(#snapshot_meta.events, 0)
        assert_unpublished(snapshot_meta)
    end)

    H.test("ET #1413 donor declarations cannot alias detached authority", function()
        local fx = fixture("et_overlay_donor_authority_alias")
        fx.source_actions.attack.difficulty_diminishing_damage = {
            { amount = 1 }, { amount = 2 },
        }
        H.equal(Registrar.register(fx.spec, fx.runtime), true)
        local marker = fx.runtime.breeds[fx.name][Registrar.marker_key]
        fx.source_actions.attack.difficulty_diminishing_damage =
            marker.actions_snapshot.attack.difficulty_diminishing_damage
        fx.readiness.ready = false
        local events_before = #fx.events
        local ok, reason = Registrar.register(fx.spec, fx.runtime)
        H.equal(ok, nil, "donor declaration aliased marker authority")
        H.equal(reason, "existing_actions_overlay_source_mismatch")
        H.equal(#fx.events, events_before,
            "donor/authority alias reached a write")
        H.equal(fx.readiness.ready, false)
    end)

    H.test("ET #1413 fresh action clones must detach every nested table", function()
        local fx = fixture("et_nested_action_clone_alias")
        local ordinary_clone = fx.runtime.clone
        fx.source_actions.attack.nested = { value = 4 }
        fx.runtime.clone = function(value)
            local copied = ordinary_clone(value)
            if value == fx.source_actions then
                copied.attack.nested = value.attack.nested
            end
            return copied
        end
        local ok, reason = Registrar.register(fx.spec, fx.runtime)
        H.equal(ok, nil, "nested donor alias escaped clone validation")
        H.equal(reason, "actions_clone_failed")
        H.equal(#fx.events, 0, "nested donor alias reached commit")
        assert_unpublished(fx)
    end)

    H.test("ET #1413 ephemeral table presentations repair with detached graphs", function()
        local fx = fixture("et_ephemeral_table_presentation")
        local declaration = { nested = { value = 4 } }
        fx.spec.presentations[3].value = declaration
        fx.spec.presentations[3].ephemeral = true
        H.equal(Registrar.register(fx.spec, fx.runtime), true)
        local first = fx.grudge_names[fx.name]
        H.truthy(not rawequal(first, declaration))
        first.nested.value = 99
        fx.readiness.ready = false
        H.equal(Registrar.register(fx.spec, fx.runtime), true)
        local repaired = fx.grudge_names[fx.name]
        H.equal(repaired.nested.value, 4)
        H.truthy(not rawequal(repaired, first))
        H.truthy(not rawequal(repaired, declaration))
        H.truthy(not rawequal(repaired.nested, declaration.nested))
    end)

    H.test("ET #1413 presentation graphs stay globally detached", function()
        local function prepared(suffix)
            local fx = fixture("et_presentation_global_" .. suffix)
            local first = { nested = { value = 4 } }
            local second = { nested = { value = 4 } }
            fx.spec.presentations[3].value = first
            fx.spec.presentations[4] = {
                target = fx.portraits, key = fx.name .. "_second", value = second,
            }
            H.equal(Registrar.register(fx.spec, fx.runtime), true)
            local live_first = fx.grudge_names[fx.name]
            local live_second = fx.portraits[fx.name .. "_second"]
            H.truthy(not rawequal(live_first, first))
            H.truthy(not rawequal(live_second, second))
            H.truthy(not rawequal(live_first, live_second))
            H.truthy(not rawequal(live_first.nested, live_second.nested))
            fx.readiness.ready = false
            return fx, first, live_first, live_second
        end

        local cross_live, _, live_first = prepared("cross_live_alias")
        cross_live.portraits[cross_live.name .. "_second"] = live_first
        local cross_events = #cross_live.events
        local cross_ok, cross_reason = Registrar.register(
            cross_live.spec, cross_live.runtime)
        H.equal(cross_ok, nil)
        H.equal(cross_reason, "presentation_4_mismatch")
        H.equal(#cross_live.events, cross_events)

        local declaration_alias, first_declaration = prepared("declaration_alias")
        declaration_alias.portraits[declaration_alias.name .. "_second"] =
            first_declaration
        local declaration_events = #declaration_alias.events
        local declaration_ok, declaration_reason = Registrar.register(
            declaration_alias.spec, declaration_alias.runtime)
        H.equal(declaration_ok, nil)
        H.equal(declaration_reason, "presentation_4_mismatch")
        H.equal(#declaration_alias.events, declaration_events)
    end)

    H.test("ET #1413 rejects every mandatory surface and fallible planner without mutation", function()
        local mutations = {
            function(rt) rt.breeds = nil end,
            function(rt, fx) rt.breeds[fx.source_name] = nil end,
            function(rt) rt.actions = nil end,
            function(rt, fx) rt.actions[fx.source_name] = nil end,
            function(rt) rt.network_lookup = nil end,
            function(rt) rt.network_lookup.breeds = nil end,
            function(rt) rt.network_lookup.damage_sources = nil end,
            function(rt) rt.network_lookup.statistics_path_names = nil end,
            function(rt) rt.lookup_lib = nil end,
            function(rt) rt.lookup_lib = {} end,
            function(rt) rt.statistics = nil end,
            function(rt) rt.statistics.player.kills_per_breed = nil end,
            function(rt) rt.difficulties = nil end,
            function(rt) rt.package_settings = nil end,
            function(rt) rt.package_settings.alias_to_breed = nil end,
            function(rt) rt.package_settings.breed_to_aliases = nil end,
            function(rt) rt.dismemberments = nil end,
            function(rt, fx) rt.dismemberments[fx.source_name] = nil end,
            function(rt) rt.race_sets.chaos = nil end,
            function(rt) rt.race_sets.skaven = nil end,
            function(rt) rt.elites = nil end,
            function(rt) rt.hit_zones = nil end,
            function(rt) rt.clone = nil end,
            function(rt) rt.conflict_director = nil end,
            function(rt) rt.conflict_director.set_threat_value = nil end,
            function(rt) rt.raw_set = nil end,
            function(rt) rt.performance._activated_per_breed = nil end,
        }
        for i = 1, #mutations do
            local fx = fixture("et_missing_" .. i)
            mutations[i](fx.runtime, fx)
            local ok = Registrar.register(fx.spec, fx.runtime)
            H.equal(ok, nil, "missing mandatory surface " .. i .. " was accepted")
            H.equal(#fx.events, 0,
                "missing mandatory surface " .. i .. " reached commit")
        end

        for i = 1, #STAT_NAMES do
            local fx = fixture("et_missing_stat_" .. i)
            fx.runtime.statistics.player[STAT_NAMES[i]] = nil
            H.equal(Registrar.register(fx.spec, fx.runtime), nil)
            H.equal(#fx.events, 0)
        end

        local clone_throw = fixture("et_clone_throw")
        clone_throw.runtime.clone = function() error("clone") end
        H.equal(Registrar.register(clone_throw.spec, clone_throw.runtime), nil)
        assert_unpublished(clone_throw)

        local helper_throw = fixture("et_helper_throw")
        helper_throw.runtime.lookup_lib = { register_named = function() error("wire") end }
        H.equal(Registrar.register(helper_throw.spec, helper_throw.runtime), nil)
        assert_unpublished(helper_throw)

        local configure_throw = fixture("et_configure_throw")
        configure_throw.spec.configure = function() error("configure") end
        H.equal(Registrar.register(configure_throw.spec, configure_throw.runtime), nil)
        assert_unpublished(configure_throw)

        local sparse_alias = fixture("et_sparse_alias")
        sparse_alias.source_aliases[3] = "gap"
        local alias_ok, alias_reason = Registrar.register(
            sparse_alias.spec, sparse_alias.runtime)
        H.equal(alias_ok, nil)
        H.equal(alias_reason, "source_aliases_sparse")

        local invalid_threat = fixture("et_invalid_threat")
        invalid_threat.source.threat_value = nil
        local threat_ok, threat_reason = Registrar.register(
            invalid_threat.spec, invalid_threat.runtime)
        H.equal(threat_ok, nil)
        H.equal(threat_reason, "threat_value_invalid")
        assert_unpublished(invalid_threat)

        local invalid_difficulty = fixture("et_invalid_difficulty")
        invalid_difficulty.runtime.difficulties[1] = true
        local difficulty_ok, difficulty_reason = Registrar.register(
            invalid_difficulty.spec, invalid_difficulty.runtime)
        H.equal(difficulty_ok, nil)
        H.equal(difficulty_reason, "difficulty_name_invalid")
        assert_unpublished(invalid_difficulty)

        local aliased_stats = fixture("et_aliased_stats")
        aliased_stats.runtime.statistics.player.kill_assists_per_breed =
            aliased_stats.runtime.statistics.player.kills_per_breed
        local aliased_ok, aliased_reason = Registrar.register(
            aliased_stats.spec, aliased_stats.runtime)
        H.equal(aliased_ok, nil)
        H.equal(aliased_reason,
            "duplicate_write:statistics_kill_assists_per_breed")
        assert_unpublished(aliased_stats)

        local sparse_readiness = fixture("et_sparse_readiness")
        sparse_readiness.spec.readiness[2] = nil
        local readiness_ok, readiness_reason = Registrar.register(
            sparse_readiness.spec, sparse_readiness.runtime)
        H.equal(readiness_ok, nil)
        H.equal(readiness_reason, "readiness_sparse")
        assert_unpublished(sparse_readiness)

        local protected_lookup = fixture("et_protected_lookup")
        setmetatable(protected_lookup.runtime.network_lookup.breeds, {
            __metatable = "locked",
        })
        local lookup_ok, lookup_reason = Registrar.register(
            protected_lookup.spec, protected_lookup.runtime)
        H.equal(lookup_ok, nil)
        H.equal(lookup_reason, "lookup_breeds_copy_failed")
        H.equal(rawget(protected_lookup.runtime.breeds, protected_lookup.name), nil)
        H.equal(rawget(protected_lookup.runtime.network_lookup.breeds,
            protected_lookup.name), nil)
        H.equal(rawget(protected_lookup.runtime.network_lookup.damage_sources,
            protected_lookup.name), nil)
        H.equal(getmetatable(protected_lookup.runtime.network_lookup.breeds), "locked")

        local protected_alias = fixture("et_protected_alias")
        setmetatable(protected_alias.source_aliases, { __metatable = "locked" })
        local protected_ok, protected_reason = Registrar.register(
            protected_alias.spec, protected_alias.runtime)
        H.equal(protected_ok, nil)
        H.equal(protected_reason, "source_aliases_copy_failed")
        assert_unpublished(protected_alias)

        local strict_alias = fixture("et_strict_alias")
        setmetatable(strict_alias.source_aliases, {
            __newindex = function() error("immutable source aliases") end,
        })
        H.equal(Registrar.register(strict_alias.spec, strict_alias.runtime), true)
        H.equal(strict_alias.source_aliases[2], nil)
    end)

    H.test("ET #1413 isolates callbacks and both second-stage planners", function()
        local breed_alias = fixture("et_breed_clone_alias")
        breed_alias.runtime.clone = function(value) return value end
        local breed_alias_ok, breed_alias_reason = Registrar.register(
            breed_alias.spec, breed_alias.runtime)
        H.equal(breed_alias_ok, nil)
        H.equal(breed_alias_reason, "breed_clone_failed")
        assert_unpublished(breed_alias)

        local actions_alias = fixture("et_actions_clone_alias")
        local alias_calls = 0
        actions_alias.runtime.clone = function(value)
            alias_calls = alias_calls + 1
            if alias_calls == 2 then return value end
            return clone(value)
        end
        local actions_alias_ok, actions_alias_reason = Registrar.register(
            actions_alias.spec, actions_alias.runtime)
        H.equal(actions_alias_ok, nil)
        H.equal(actions_alias_reason, "actions_clone_failed")
        assert_unpublished(actions_alias)

        local actions_clone = fixture("et_actions_clone_throw")
        local clone_calls = 0
        actions_clone.runtime.clone = function(value)
            clone_calls = clone_calls + 1
            if clone_calls == 2 then error("actions clone") end
            return clone(value)
        end
        local actions_ok, actions_reason = Registrar.register(
            actions_clone.spec, actions_clone.runtime)
        H.equal(actions_ok, nil)
        H.equal(actions_reason, "actions_clone_failed")
        assert_unpublished(actions_clone)

        local second_helper = fixture("et_second_helper_throw")
        second_helper.runtime.lookup_lib = {
            register_named = function(outer, axis, name)
                if axis == "damage_sources" then error("second helper") end
                return Lookup.register_named(outer, axis, name)
            end,
        }
        local helper_ok, helper_reason = Registrar.register(
            second_helper.spec, second_helper.runtime)
        H.equal(helper_ok, nil)
        H.equal(helper_reason, "lookup_damage_sources_threw")
        assert_unpublished(second_helper)

        local third_helper = fixture("et_third_helper_throw")
        third_helper.runtime.lookup_lib = {
            register_named = function(outer, axis, name)
                if axis == "statistics_path_names" then error("third helper") end
                return Lookup.register_named(outer, axis, name)
            end,
        }
        local third_ok, third_reason = Registrar.register(
            third_helper.spec, third_helper.runtime)
        H.equal(third_ok, nil)
        H.equal(third_reason, "lookup_statistics_path_names_threw")
        assert_unpublished(third_helper)

        local second_copy = fixture("et_second_lookup_copy")
        setmetatable(second_copy.runtime.network_lookup.damage_sources, {
            __metatable = "locked-second",
        })
        local copy_ok, copy_reason = Registrar.register(
            second_copy.spec, second_copy.runtime)
        H.equal(copy_ok, nil)
        H.equal(copy_reason, "lookup_damage_sources_copy_failed")
        H.equal(rawget(second_copy.runtime.network_lookup.breeds,
            second_copy.name), nil)
        H.equal(rawget(second_copy.runtime.network_lookup.breeds, 2), nil)
        H.equal(getmetatable(second_copy.runtime.network_lookup.breeds), STRICT)
        H.equal(getmetatable(second_copy.runtime.network_lookup.damage_sources),
            "locked-second")

        local third_copy = fixture("et_third_lookup_copy")
        setmetatable(third_copy.runtime.network_lookup.statistics_path_names, {
            __metatable = "locked-third",
        })
        local third_copy_ok, third_copy_reason = Registrar.register(
            third_copy.spec, third_copy.runtime)
        H.equal(third_copy_ok, nil)
        H.equal(third_copy_reason, "lookup_statistics_path_names_copy_failed")
        H.equal(rawget(third_copy.runtime.network_lookup.breeds,
            third_copy.name), nil)
        H.equal(rawget(third_copy.runtime.network_lookup.damage_sources,
            third_copy.name), nil)
        H.equal(getmetatable(
            third_copy.runtime.network_lookup.statistics_path_names), "locked-third")

        local configure_throw = fixture("et_detached_configure_throw")
        local configure_health = configure_throw.source.max_health
        configure_throw.spec.configure = function(candidate, source_view)
            candidate.display_name = "test_name"
            source_view.max_health[8] = 1
            source_view.foreign = true
            error("configure after detached source mutation")
        end
        local configure_ok = Registrar.register(
            configure_throw.spec, configure_throw.runtime)
        H.equal(configure_ok, nil)
        H.equal(configure_throw.source.max_health, configure_health)
        H.equal(configure_throw.source.max_health[8], 800)
        H.equal(configure_throw.source.foreign, nil)
        assert_unpublished(configure_throw)

        local validate_throw = fixture("et_detached_validate_throw")
        local validate_health = validate_throw.source.max_health
        validate_throw.spec.validate_breed = function(candidate_view, source_view)
            candidate_view.max_health[8] = 1
            source_view.max_health[8] = 2
            error("validate after detached view mutation")
        end
        local validate_ok, validate_reason = Registrar.register(
            validate_throw.spec, validate_throw.runtime)
        H.equal(validate_ok, nil)
        H.equal(validate_reason, "validate_breed_threw")
        H.equal(validate_throw.source.max_health, validate_health)
        H.equal(validate_throw.source.max_health[8], 800)
        assert_unpublished(validate_throw)

        local isolated = fixture("et_detached_callback_success")
        isolated.spec.configure = function(candidate, source_view)
            candidate.display_name = "test_name"
            source_view.max_health[8] = 1
        end
        isolated.spec.validate_breed = function(candidate_view, source_view)
            H.equal(source_view.max_health[8], 800,
                "validator received configure's mutated source view")
            candidate_view.max_health[8] = 1
            return true
        end
        local isolated_ok, _, isolated_breed = Registrar.register(
            isolated.spec, isolated.runtime)
        H.equal(isolated_ok, true)
        H.equal(isolated.source.max_health[8], 800)
        H.equal(isolated_breed.max_health[8], 800,
            "validator mutated the live off-table candidate")

        local existing = fixture("et_detached_existing_validate")
        local existing_ok, _, existing_breed = Registrar.register(
            existing.spec, existing.runtime)
        H.equal(existing_ok, true)
        existing.spec.validate_breed = function(candidate_view, source_view)
            candidate_view.max_health[8] = 1
            source_view.max_health[8] = 2
            error("existing validator")
        end
        existing.readiness.ready = false
        local existing_events = #existing.events
        local reload_ok, reload_reason = Registrar.register(
            existing.spec, existing.runtime)
        H.equal(reload_ok, nil)
        H.equal(reload_reason, "validate_breed_threw")
        H.equal(existing_breed.max_health[8], 800)
        H.equal(existing.source.max_health[8], 800)
        H.equal(#existing.events, existing_events)
        H.equal(existing.readiness.ready, false)
    end)

    H.test("ET #1413 rolls every injected structural commit failure back exactly", function()
        local count_fx = fixture("et_commit_count")
        local write_count = 0
        count_fx.runtime.raw_set = function(target, key, value)
            write_count = write_count + 1
            rawset(target, key, value)
        end
        H.equal(Registrar.register(count_fx.spec, count_fx.runtime), true)
        H.truthy(write_count > 15)

        for fail_at = 1, write_count do
            local fx = fixture("et_commit_fail_" .. fail_at)
            local calls = 0
            fx.runtime.raw_set = function(target, key, value)
                calls = calls + 1
                rawset(target, key, value)
                if calls == fail_at then error("injected after write") end
            end
            local ok, reason = Registrar.register(fx.spec, fx.runtime)
            H.equal(ok, nil)
            H.truthy(reason:find("commit_failed_after_threat", 1, true) ~= nil)
            assert_unpublished(fx)
            H.equal(fx.threat[fx.name], 32,
                "hidden threat seed is intentionally not claimed as reversible")
            local retry, retry_reason = Registrar.register(fx.spec, fx.runtime)
            H.equal(retry, nil)
            H.truthy(retry_reason:find("terminal:commit_failed_after_threat", 1, true) ~= nil)
        end

        local silent = fixture("et_commit_silent_noop")
        silent.runtime.raw_set = function() return false end
        local silent_ok, silent_reason = Registrar.register(silent.spec, silent.runtime)
        H.equal(silent_ok, nil)
        H.truthy(silent_reason:find("commit_failed_after_threat", 1, true) ~= nil)
        assert_unpublished(silent)

        local substituted = fixture("et_commit_substituted_identity")
        substituted.runtime.raw_set = function(target, key, value)
            rawset(target, key, type(value) == "table" and clone(value) or value)
        end
        local substituted_ok, substituted_reason = Registrar.register(
            substituted.spec, substituted.runtime)
        H.equal(substituted_ok, nil)
        H.truthy(substituted_reason:find(
            "commit_failed_after_threat:actions", 1, true) ~= nil)
        assert_unpublished(substituted)

        local shaped = fixture("et_commit_false_shape")
        rawset(shaped.localization, "test_name", false)
        rawset(shaped.readiness, "breed_name", false)
        local breed_meta = getmetatable(shaped.runtime.network_lookup.breeds)
        local damage_meta = getmetatable(
            shaped.runtime.network_lookup.damage_sources)
        local statistics_meta = getmetatable(
            shaped.runtime.network_lookup.statistics_path_names)
        local aliases = shaped.runtime.package_settings
            .breed_to_aliases[shaped.source_name]
        local shaped_calls = 0
        shaped.runtime.raw_set = function(target, key, value)
            shaped_calls = shaped_calls + 1
            rawset(target, key, value)
            if shaped_calls == write_count then error("final write") end
        end
        local shaped_ok, shaped_reason = Registrar.register(
            shaped.spec, shaped.runtime)
        H.equal(shaped_ok, nil)
        H.truthy(shaped_reason:find(
            "commit_failed_after_threat:breed_publish", 1, true) ~= nil)
        H.equal(rawget(shaped.localization, "test_name"), false)
        H.equal(rawget(shaped.readiness, "breed_name"), false)
        H.equal(rawget(shaped.readiness, "ready"), false)
        H.equal(rawget(shaped.readiness, "threat_seeded"), false)
        H.equal(rawget(shaped.runtime.breeds, shaped.name), nil)
        H.equal(rawget(shaped.runtime.actions, shaped.name), nil)
        H.equal(rawget(shaped.runtime.network_lookup.breeds, shaped.name), nil)
        H.equal(rawget(shaped.runtime.network_lookup.breeds, 2), nil)
        H.equal(rawget(shaped.runtime.network_lookup.damage_sources,
            shaped.name), nil)
        H.equal(rawget(shaped.runtime.network_lookup.damage_sources, 2), nil)
        H.equal(rawget(shaped.runtime.network_lookup.statistics_path_names,
            shaped.name), nil)
        H.equal(rawget(shaped.runtime.network_lookup.statistics_path_names, 2), nil)
        H.equal(shaped.runtime.package_settings
            .breed_to_aliases[shaped.source_name], aliases)
        H.equal(getmetatable(shaped.runtime.network_lookup.breeds), breed_meta)
        H.equal(getmetatable(shaped.runtime.network_lookup.damage_sources),
            damage_meta)
        H.equal(getmetatable(shaped.runtime.network_lookup.statistics_path_names),
            statistics_meta)
    end)

    H.test("ET #1413 treats a throwing opaque threat setter as indeterminate and terminal", function()
        local fx = fixture("et_threat_throw")
        fx.runtime.conflict_director.set_threat_value = function(_, name, value)
            fx.threat[name] = value
            error("throws after hidden write")
        end
        local ok, reason = Registrar.register(fx.spec, fx.runtime)
        H.equal(ok, nil)
        H.equal(reason, "threat_state_indeterminate")
        H.equal(fx.threat[fx.name], 32)
        assert_unpublished(fx)
        local retry, retry_reason = Registrar.register(fx.spec, fx.runtime)
        H.equal(retry, nil)
        H.equal(retry_reason, "terminal:threat_state_indeterminate")

        local before = fixture("et_threat_throw_before_write")
        before.runtime.conflict_director.set_threat_value = function()
            error("throws before hidden write")
        end
        local before_ok, before_reason = Registrar.register(
            before.spec, before.runtime)
        H.equal(before_ok, nil)
        H.equal(before_reason, "threat_state_indeterminate")
        H.equal(before.threat[before.name], nil)
        assert_unpublished(before)
        local before_retry, before_retry_reason = Registrar.register(
            before.spec, before.runtime)
        H.equal(before_retry, nil)
        H.equal(before_retry_reason, "terminal:threat_state_indeterminate")
    end)

    H.test("ET #1413 rejects partial, duplicate, and foreign existing state", function()
        local false_residue = fixture("et_false_breed_residue")
        false_residue.runtime.breeds[false_residue.name] = false
        local false_ok, false_reason = Registrar.register(
            false_residue.spec, false_residue.runtime)
        H.equal(false_ok, nil)
        H.equal(false_reason, "existing_breed_foreign")
        H.equal(rawget(false_residue.runtime.breeds, false_residue.name), false)
        H.equal(#false_residue.events, 0)
        H.equal(rawget(false_residue.runtime.network_lookup.breeds,
            false_residue.name), nil)
        H.equal(rawget(false_residue.runtime.network_lookup.damage_sources,
            false_residue.name), nil)

        local foreign = fixture("et_foreign_breed")
        foreign.runtime.breeds[foreign.name] = { name = foreign.name, race = "skaven" }
        rawset(foreign.runtime.network_lookup.breeds, 2, foreign.name)
        rawset(foreign.runtime.network_lookup.breeds, foreign.name, 2)
        rawset(foreign.runtime.network_lookup.damage_sources, 2, foreign.name)
        rawset(foreign.runtime.network_lookup.damage_sources, foreign.name, 2)
        rawset(foreign.runtime.network_lookup.statistics_path_names, 2, foreign.name)
        rawset(foreign.runtime.network_lookup.statistics_path_names, foreign.name, 2)
        local foreign_ok, foreign_reason = Registrar.register(foreign.spec, foreign.runtime)
        H.equal(foreign_ok, nil)
        H.equal(foreign_reason, "existing_breed_fingerprint_mismatch")
        H.equal(foreign.readiness.ready, false)

        local duplicate = fixture("et_duplicate_alias")
        H.equal(Registrar.register(duplicate.spec, duplicate.runtime), true)
        local aliases = duplicate.runtime.package_settings
            .breed_to_aliases[duplicate.source_name]
        aliases[#aliases + 1] = duplicate.name
        duplicate.readiness.ready = false
        local duplicate_ok, duplicate_reason = Registrar.register(
            duplicate.spec, duplicate.runtime)
        H.equal(duplicate_ok, nil)
        H.equal(duplicate_reason, "package_alias_mismatch")
        H.equal(duplicate.readiness.ready, false)

        local fingerprint = fixture("et_fingerprint_drift")
        H.equal(Registrar.register(fingerprint.spec, fingerprint.runtime), true)
        fingerprint.spec.fingerprint = "foreign"
        fingerprint.readiness.ready = false
        local fp_ok, fp_reason = Registrar.register(fingerprint.spec, fingerprint.runtime)
        H.equal(fp_ok, nil)
        H.equal(fp_reason, "existing_breed_fingerprint_mismatch")
        H.equal(fingerprint.readiness.ready, false)
    end)

    H.test("ET #1413 rejects false and non-table residue on every persistent family", function()
        local rows = {
            {
                label = "breed", mutate = function(fx)
                    rawset(fx.runtime.breeds, fx.name, false)
                    return fx.runtime.breeds, fx.name, false
                end,
            },
            {
                label = "actions", mutate = function(fx)
                    rawset(fx.runtime.actions, fx.name, "foreign")
                    return fx.runtime.actions, fx.name, "foreign"
                end,
            },
            {
                label = "statistics", mutate = function(fx)
                    local target = fx.runtime.statistics.player[STAT_NAMES[1]]
                    rawset(target, fx.name, false)
                    return target, fx.name, false
                end,
            },
            {
                label = "alias_forward", mutate = function(fx)
                    local target = fx.runtime.package_settings.alias_to_breed
                    rawset(target, fx.name, "foreign")
                    return target, fx.name, "foreign"
                end,
            },
            {
                label = "alias_reverse", mutate = function(fx)
                    rawset(fx.source_aliases, 2, false)
                    return fx.source_aliases, 2, false
                end,
            },
            {
                label = "dismemberment", mutate = function(fx)
                    rawset(fx.runtime.dismemberments, fx.name, false)
                    return fx.runtime.dismemberments, fx.name, false
                end,
            },
            {
                label = "race", mutate = function(fx)
                    rawset(fx.runtime.race_sets.skaven, fx.name, false)
                    return fx.runtime.race_sets.skaven, fx.name, false
                end,
            },
            {
                label = "elite", mutate = function(fx)
                    rawset(fx.runtime.elites, fx.name, "foreign")
                    return fx.runtime.elites, fx.name, "foreign"
                end,
            },
            {
                label = "hit_zones", mutate = function(fx)
                    rawset(fx.runtime.hit_zones, fx.name, false)
                    return fx.runtime.hit_zones, fx.name, false
                end,
            },
            {
                label = "performance", mutate = function(fx)
                    local target = fx.runtime.performance._activated_per_breed
                    rawset(target, fx.name, "foreign")
                    return target, fx.name, "foreign"
                end,
            },
            {
                label = "presentation", mutate = function(fx)
                    rawset(fx.portraits, fx.name, false)
                    return fx.portraits, fx.name, false
                end,
            },
            {
                label = "breed_wire", mutate = function(fx)
                    rawset(fx.runtime.network_lookup.breeds, fx.name, false)
                    return fx.runtime.network_lookup.breeds, fx.name, false
                end,
            },
            {
                label = "damage_wire", mutate = function(fx)
                    rawset(fx.runtime.network_lookup.damage_sources,
                        fx.name, "foreign")
                    return fx.runtime.network_lookup.damage_sources,
                        fx.name, "foreign"
                end,
            },
            {
                label = "statistics_wire", mutate = function(fx)
                    rawset(fx.runtime.network_lookup.statistics_path_names,
                        fx.name, "foreign")
                    return fx.runtime.network_lookup.statistics_path_names,
                        fx.name, "foreign"
                end,
            },
        }
        for i = 1, #rows do
            local row = rows[i]
            local fx = fixture("et_residue_" .. row.label)
            local target, key, value = row.mutate(fx)
            local ok = Registrar.register(fx.spec, fx.runtime)
            H.equal(ok, nil, row.label .. " residue was accepted")
            H.equal(rawget(target, key), value,
                row.label .. " residue was rewritten")
            H.equal(#fx.events, 0,
                row.label .. " residue reached threat or structural commit")
            H.equal(fx.readiness.ready, false)
            H.equal(getmetatable(fx.runtime.network_lookup.breeds), STRICT)
            H.equal(getmetatable(fx.runtime.network_lookup.damage_sources), STRICT)
            H.equal(getmetatable(
                fx.runtime.network_lookup.statistics_path_names), STRICT)
        end
    end)

    H.test("ET #1413 owners are declarative and preserve unrelated combat scopes", function()
        local function read(path)
            local handle = assert(io.open(path, "rb"))
            local source = handle:read("*a")
            handle:close()
            return source
        end
        local warlord = read(repo_root
            .. "/enemy_tweaker/scripts/mods/enemy_tweaker/_et_skaven_warlord_breed.lua")
        local chosen = read(repo_root
            .. "/enemy_tweaker/scripts/mods/enemy_tweaker/_et_boss_ideas.lua")
        H.equal(warlord:find("NLLib.register_named", 1, true), nil)
        H.equal(chosen:find("NLLib.register_named", 1, true), nil)
        H.truthy(warlord:find("Registrar.register({", 1, true) ~= nil)
        H.truthy(chosen:find("Registrar.register({", 1, true) ~= nil)
        H.truthy(chosen:find("issue1413_atomic_custom_breed_registration", 1, true) ~= nil)
        H.truthy(warlord:find("issue324_warlord_diag_armed", 1, true) ~= nil,
            "#324 combat diagnostics must remain out of the registrar migration")
        H.truthy(chosen:find("issue451_chosen_greataxe_prototype", 1, true) ~= nil,
            "#451 prototype diagnostics must remain intact")
    end)
end
