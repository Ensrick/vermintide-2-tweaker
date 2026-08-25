return function(H, repo_root)
    local registrar_path = repo_root
        .. "/enemy_tweaker/scripts/mods/enemy_tweaker/_et_custom_breed_registrar.lua"
    local lookup_path = repo_root
        .. "/enemy_tweaker/scripts/mods/enemy_tweaker/_lib_network_lookup.lua"
    local Registrar = assert(loadfile(registrar_path))()
    local Lookup = assert(loadfile(lookup_path))()

    local STAT_NAMES = {
        "kills_per_breed", "kills_per_breed_persistent",
        "kill_assists_per_breed", "damage_dealt_per_breed",
        "kills_per_breed_difficulty", "kill_assists_per_breed_difficulty",
    }

    local function clone(value, seen)
        if type(value) ~= "table" then return value end
        seen = seen or {}
        if seen[value] then return seen[value] end
        local out = {}
        seen[value] = out
        for key, child in next, value do out[clone(key, seen)] = clone(child, seen) end
        setmetatable(out, getmetatable(value))
        return out
    end

    local STRICT = {
        __index = function(_, key) error("strict lookup miss: " .. tostring(key)) end,
    }

    local function lookup()
        return setmetatable({ [1] = "vanilla", vanilla = 1 }, STRICT)
    end

    local function statistics_lookup()
        return setmetatable({
            [1] = "kills_per_breed", kills_per_breed = 1,
        }, STRICT)
    end

    local function fixture(name, cap)
        local source_name = "source_skaven"
        local source_hit_zones = { head = 1, torso = 2 }
        local source_dismemberment = { head = { "head" } }
        local source_aliases = { "existing_alias" }
        local source = {
            name = source_name, race = "skaven", elite = false, boss = true,
            threat_value = 32, hit_zones_lookup = source_hit_zones,
            max_health = { 300, 350, 400, 500, 800, 800, 800, 800 },
        }
        local source_actions = { attack = { damage = 10 } }
        local player = {}
        for i = 1, #STAT_NAMES do player[STAT_NAMES[i]] = {} end
        local readiness = { ready = false, breed_name = nil, threat_seeded = false }
        local localization, portraits, grudge_names = {}, {}, {}
        local threat = {}
        local events = {}
        local runtime = {
            breeds = { [source_name] = source },
            actions = { [source_name] = source_actions },
            network_lookup = {
                breeds = lookup(), damage_sources = lookup(),
                statistics_path_names = statistics_lookup(),
            },
            network_constants = { damage_source_id = { max = cap or 2 } },
            network = { type_info = function(kind)
                if kind == "statistics_path_lookup" then return { max = cap or 2 } end
                if kind == "damage_source_id" then return { max = cap or 2 } end
                error("unexpected network type: " .. tostring(kind))
            end },
            clone = clone,
            conflict_director = {
                set_threat_value = function(_, breed_name, value)
                    events[#events + 1] = "threat"
                    threat[breed_name] = value
                end,
            },
            statistics = { player = player },
            difficulties = { recruit = true, veteran = true },
            package_settings = {
                alias_to_breed = { existing_alias = source_name },
                breed_to_aliases = { [source_name] = source_aliases },
            },
            dismemberments = { [source_name] = source_dismemberment },
            race_sets = {
                beastmen = {}, chaos = {}, critter = {}, skaven = {}, undead = {},
            },
            elites = {},
            hit_zones = { [source_name] = source_hit_zones },
            performance = { _activated_per_breed = {} },
            raw_set = function(target, key, value)
                events[#events + 1] = { target = target, key = key }
                rawset(target, key, value)
            end,
            lookup_lib = Lookup,
        }
        local spec = {
            owner = "enemy_tweaker.test", name = name,
            source_breed = source_name, race = "skaven",
            fingerprint = "test-fingerprint-v1",
            configure = function(breed) breed.display_name = "test_name" end,
            validate_breed = function(breed)
                if breed.display_name ~= "test_name" then return nil, "display" end
                if breed.max_health[8] ~= 800 then return nil, "health" end
                return true
            end,
            presentations = {
                { target = localization, key = "test_name", value = "Test",
                    ephemeral = true },
                { target = portraits, key = name, value = "portrait" },
                { target = grudge_names, key = name, value = { "one", "two" } },
            },
            readiness = {
                { target = readiness, key = "threat_seeded", value = true },
                { target = readiness, key = "breed_name", value = name },
                { target = readiness, key = "ready", value = true },
            },
        }
        return {
            name = name, source_name = source_name, runtime = runtime, spec = spec,
            source = source, source_actions = source_actions,
            source_aliases = source_aliases, source_dismemberment = source_dismemberment,
            readiness = readiness, localization = localization,
            portraits = portraits, grudge_names = grudge_names,
            threat = threat, events = events,
        }
    end

    local function assert_unpublished(fx)
        local rt, name = fx.runtime, fx.name
        H.equal(rawget(rt.breeds, name), nil)
        H.equal(rawget(rt.actions, name), nil)
        H.equal(rawget(rt.network_lookup.breeds, name), nil)
        H.equal(rawget(rt.network_lookup.breeds, 2), nil)
        H.equal(rawget(rt.network_lookup.damage_sources, name), nil)
        H.equal(rawget(rt.network_lookup.damage_sources, 2), nil)
        H.equal(rawget(rt.network_lookup.statistics_path_names, name), nil)
        H.equal(rawget(rt.network_lookup.statistics_path_names, 2), nil)
        for i = 1, #STAT_NAMES do
            H.equal(rawget(rt.statistics.player[STAT_NAMES[i]], name), nil)
        end
        H.equal(rawget(rt.package_settings.alias_to_breed, name), nil)
        H.equal(rt.package_settings.breed_to_aliases[fx.source_name], fx.source_aliases)
        H.equal(#fx.source_aliases, 1)
        H.equal(rawget(rt.dismemberments, name), nil)
        H.equal(rawget(rt.race_sets.skaven, name), nil)
        H.equal(rawget(rt.elites, name), nil)
        H.equal(rawget(rt.hit_zones, name), nil)
        H.equal(rawget(rt.performance._activated_per_breed, name), nil)
        H.equal(rawget(fx.localization, "test_name"), nil)
        H.equal(rawget(fx.portraits, name), nil)
        H.equal(rawget(fx.grudge_names, name), nil)
        H.equal(fx.readiness.ready, false)
        H.equal(fx.readiness.breed_name, nil)
        H.equal(fx.readiness.threat_seeded, false)
        H.equal(getmetatable(rt.network_lookup.breeds), STRICT)
        H.equal(getmetatable(rt.network_lookup.damage_sources), STRICT)
        H.equal(getmetatable(rt.network_lookup.statistics_path_names), STRICT)
    end

    local function assert_reload_rejects(fx, mutate, expected_reason)
        local ok, reason, breed = Registrar.register(fx.spec, fx.runtime)
        H.equal(ok, true)
        H.equal(reason, "registered")
        fx.readiness.ready = false
        fx.readiness.breed_name = nil
        fx.readiness.threat_seeded = false
        mutate(fx, breed, rawget(breed, Registrar.marker_key))
        local event_count = #fx.events
        local rejected, rejected_reason = Registrar.register(fx.spec, fx.runtime)
        H.equal(rejected, nil)
        if expected_reason then H.equal(rejected_reason, expected_reason) end
        H.equal(#fx.events, event_count,
            "persistent tamper reached threat or a raw write")
        H.equal(fx.readiness.ready, false)
        H.equal(fx.readiness.breed_name, nil)
        H.equal(fx.readiness.threat_seeded, false)
        return rejected_reason
    end

    local function apply_bot_threat_difficulty(node, difficulty_index, seen)
        if type(node) ~= "table" then return end
        seen = seen or {}
        if seen[node] then return end
        seen[node] = true
        local declaration = rawget(node, "bot_threat_difficulty_data")
        if declaration then
            local difficulty = declaration[difficulty_index]
            local max_delay = difficulty.max_start_delay
            local function apply_target(target)
                if target.duration then
                    target.max_start_delay = math.min(max_delay, target.duration * 0.9)
                elseif target.bot_threat_duration then
                    target.bot_threat_max_start_delay = math.min(
                        max_delay, target.bot_threat_duration * 0.9)
                end
            end
            local threats = rawget(node, "bot_threats")
            if threats then
                if threats[1] then
                    for i = 1, #threats do apply_target(threats[i]) end
                else
                    for _, animation_threats in next, threats do
                        for i = 1, #animation_threats do
                            apply_target(animation_threats[i])
                        end
                    end
                end
            elseif node.bot_threat_duration then
                apply_target(node)
            end
            return
        end
        for _, child in next, node do
            if type(child) == "table" then
                apply_bot_threat_difficulty(child, difficulty_index, seen)
            end
        end
    end

    local function apply_action_difficulty(actions, difficulty_index)
        for _, action in next, actions do
            if action.difficulty_diminishing_damage then
                action.diminishing_damage = clone(
                    action.difficulty_diminishing_damage[difficulty_index])
            end
            if action.difficulty_damage then
                action.damage = action.difficulty_damage[difficulty_index]
            end
            if action.blocked_difficulty_damage then
                action.blocked_damage =
                    action.blocked_difficulty_damage[difficulty_index]
            end
            apply_bot_threat_difficulty(action, difficulty_index)
        end
    end

    local function install_difficulty_shapes(warlord_actions, chosen_actions)
        warlord_actions.attack = {
            duration = 1.25,
            difficulty_damage = { 11, 21 },
            difficulty_diminishing_damage = {
                { amount = 1, cooldown = 0.1 },
                { amount = 2, cooldown = 0.2 },
            },
            bot_threat_difficulty_data = {
                { max_start_delay = 0.2 },
                { max_start_delay = 0.7 },
            },
            bot_threats = {
                { duration = 1 },
                { bot_threat_duration = 0.5 },
            },
            unrelated_threat = { duration = 0.25 },
        }
        chosen_actions.attack = {
            duration = 1.5,
            blocked_difficulty_damage = { 3, 8 },
            difficulty_damage = { 17, 27 },
            nested = {
                bot_threat_duration = 0.4,
                bot_threat_difficulty_data = {
                    { max_start_delay = 0.1 },
                    { max_start_delay = 0.6 },
                },
            },
        }
    end

    local function difficulty_fixture(name)
        local fx = fixture(name)
        local unused = {}
        install_difficulty_shapes(fx.source_actions, unused)
        H.equal(Registrar.register(fx.spec, fx.runtime), true)
        apply_action_difficulty(fx.source_actions, 1)
        apply_action_difficulty(fx.runtime.actions[fx.name], 1)
        fx.readiness.ready = false
        return fx
    end

    local owner_global_keys = {
        "Application", "BreedActions", "BreedBehaviors", "Breeds",
        "GrudgeMarkedNames", "InventoryConfigurations", "NetworkLookup",
        "UISettings", "get_mod", "printf",
    }
    local breeds_module_name =
        "scripts/mods/enemy_tweaker/enemy_tweaker_breeds"

    local function owner_environment_snapshot()
        local globals = {}
        for i = 1, #owner_global_keys do
            local key = owner_global_keys[i]
            globals[key] = { value = rawget(_G, key) }
        end
        return {
            globals = globals,
            breeds_module = rawget(package.loaded, breeds_module_name),
        }
    end

    local function assert_owner_environment_restored(snapshot)
        for i = 1, #owner_global_keys do
            local key = owner_global_keys[i]
            H.equal(rawget(_G, key), snapshot.globals[key].value,
                "owner seam leaked global " .. key)
        end
        H.equal(rawget(package.loaded, breeds_module_name), snapshot.breeds_module,
            "owner seam leaked package.loaded breed constants")
    end

    local function with_raw_bindings(rows, callback)
        local saved, installed = {}, 0
        local ok, result = pcall(function()
            for i = 1, #rows do
                local row = rows[i]
                saved[i] = {
                    target = row.target,
                    key = row.key,
                    value = rawget(row.target, row.key),
                }
                installed = i
                rawset(row.target, row.key, row.value)
            end
            return callback()
        end)
        for i = installed, 1, -1 do
            local row = saved[i]
            rawset(row.target, row.key, row.value)
        end
        if not ok then error(result, 0) end
        return result
    end

    local function capture_actual_owner_specs(fail_get_mod_call, shared_surfaces)
        local breeds_path = repo_root
            .. "/enemy_tweaker/scripts/mods/enemy_tweaker/enemy_tweaker_breeds.lua"
        local core_path = repo_root
            .. "/enemy_tweaker/scripts/mods/enemy_tweaker/_et_boss_ideas_core.lua"
        local warlord_path = repo_root
            .. "/enemy_tweaker/scripts/mods/enemy_tweaker/_et_skaven_warlord_breed.lua"
        local chosen_path = repo_root
            .. "/enemy_tweaker/scripts/mods/enemy_tweaker/_et_boss_ideas.lua"
        local B = assert(loadfile(breeds_path))()
        local Core = assert(loadfile(core_path))()
        local capture = {
            specs = {}, hooks = {}, commands = {}, runtime_checks = {},
            runtime_check_order = {},
        }
        capture.validate_all = function() return true end
        local capture_registrar = {
            register = function(spec)
                capture.specs[#capture.specs + 1] = spec
                return nil, "capture_only"
            end,
            validate_all_registered = function()
                return capture.validate_all()
            end,
        }
        local ET = {
            BossIdeasCore = Core,
            CustomBreedRegistrar = capture_registrar,
        }
        ET.rt_register = function(name, callback)
            capture.runtime_checks[name] = callback
            capture.runtime_check_order[#capture.runtime_check_order + 1] = name
        end
        local mod = { _et = ET }
        mod.hook = function(_, target, name, callback)
            capture.hooks[#capture.hooks + 1] = {
                target = target, name = name, callback = callback,
            }
        end
        mod.command = function(_, name, description, callback)
            capture.commands[#capture.commands + 1] = {
                name = name, description = description, callback = callback,
            }
        end
        mod.echo = function() end

        local ui_settings = shared_surfaces and shared_surfaces.ui_settings
            or { breed_textures = {} }
        local grudge_names = shared_surfaces and shared_surfaces.grudge_names or {}
        local get_mod_calls = 0
        local bindings = {
            { target = _G, key = "get_mod", value = function(name)
                get_mod_calls = get_mod_calls + 1
                if fail_get_mod_call == get_mod_calls then
                    error("injected actual-consumer load failure")
                end
                if name ~= "enemy_tweaker" then error("unexpected mod request") end
                return mod
            end },
            { target = _G, key = "printf", value = function() end },
            { target = _G, key = "UISettings", value = ui_settings },
            { target = _G, key = "GrudgeMarkedNames", value = grudge_names },
            { target = _G, key = "Breeds", value = {} },
            { target = _G, key = "BreedActions", value = {} },
            { target = _G, key = "BreedBehaviors", value = {} },
            { target = _G, key = "InventoryConfigurations", value = {} },
            { target = _G, key = "NetworkLookup", value = { breeds = {} } },
            { target = _G, key = "Application", value = {
                can_get = function() return false end,
            } },
            { target = package.loaded, key = breeds_module_name, value = B },
        }
        capture.mod = mod
        capture.ui_settings = ui_settings
        capture.grudge_names = grudge_names
        return with_raw_bindings(bindings, function()
            assert(loadfile(warlord_path))()
            assert(loadfile(chosen_path))()
            return capture
        end)
    end

    local function actual_consumer_runtime(capture)
        local warlord_spec, chosen_spec = capture.specs[1], capture.specs[2]
        local warlord_health = { 300, 350, 400, 500, 800, 800, 800, 800 }
        local chosen_health = { 55, 65, 75, 85, 95, 105, 115, 125 }
        local warlord_hit_zones = { head = 1, torso = 2 }
        local chosen_hit_zones = { head = 3, torso = 4 }
        local warlord_source = {
            name = warlord_spec.source_breed, race = "skaven", boss = true,
            threat_value = 32, behavior = "storm_vermin_champion",
            hit_zones_lookup = warlord_hit_zones, max_health = warlord_health,
        }
        local chosen_source = {
            name = chosen_spec.source_breed, race = "chaos", elite = true,
            threat_value = 12, behavior = "chaos_warrior",
            default_inventory_template = "warrior_axe",
            hit_zones_lookup = chosen_hit_zones, max_health = chosen_health,
        }
        local warlord_actions = { attack = { damage = 31 } }
        local chosen_actions = { attack = { damage = 17 } }
        local warlord_dismemberment = { head = { "warlord_head" } }
        local chosen_dismemberment = { head = { "chosen_head" } }
        local warlord_aliases = { "warlord_source_alias" }
        local chosen_aliases = { "chosen_source_alias" }
        local player = {}
        for i = 1, #STAT_NAMES do player[STAT_NAMES[i]] = {} end
        local events, threat = {}, {}
        local runtime = {
            breeds = {
                [warlord_spec.source_breed] = warlord_source,
                [chosen_spec.source_breed] = chosen_source,
            },
            actions = {
                [warlord_spec.source_breed] = warlord_actions,
                [chosen_spec.source_breed] = chosen_actions,
            },
            network_lookup = {
                breeds = lookup(), damage_sources = lookup(),
                statistics_path_names = statistics_lookup(),
            },
            network_constants = { damage_source_id = { max = 3 } },
            network = { type_info = function(kind)
                if kind == "statistics_path_lookup" then return { max = 3 } end
                if kind == "damage_source_id" then return { max = 3 } end
                error("unexpected network type: " .. tostring(kind))
            end },
            clone = clone,
            conflict_director = {
                set_threat_value = function(_, name, value)
                    events[#events + 1] = { kind = "threat", name = name }
                    threat[name] = value
                end,
            },
            statistics = { player = player },
            difficulties = { recruit = true, veteran = true },
            package_settings = {
                alias_to_breed = {
                    warlord_source_alias = warlord_spec.source_breed,
                    chosen_source_alias = chosen_spec.source_breed,
                },
                breed_to_aliases = {
                    [warlord_spec.source_breed] = warlord_aliases,
                    [chosen_spec.source_breed] = chosen_aliases,
                },
            },
            dismemberments = {
                [warlord_spec.source_breed] = warlord_dismemberment,
                [chosen_spec.source_breed] = chosen_dismemberment,
            },
            race_sets = {
                beastmen = {}, chaos = {}, critter = {}, skaven = {}, undead = {},
            },
            elites = {},
            hit_zones = {
                [warlord_spec.source_breed] = warlord_hit_zones,
                [chosen_spec.source_breed] = chosen_hit_zones,
            },
            performance = { _activated_per_breed = {} },
            raw_set = function(target, key, value)
                events[#events + 1] = {
                    kind = "raw_set", target = target, key = key,
                }
                rawset(target, key, value)
            end,
            lookup_lib = Lookup,
        }
        return {
            runtime = runtime, events = events, threat = threat,
            warlord_source = warlord_source, chosen_source = chosen_source,
            warlord_health = warlord_health, chosen_health = chosen_health,
            warlord_actions = warlord_actions, chosen_actions = chosen_actions,
            warlord_aliases = warlord_aliases, chosen_aliases = chosen_aliases,
            warlord_dismemberment = warlord_dismemberment,
            chosen_dismemberment = chosen_dismemberment,
            warlord_hit_zones = warlord_hit_zones,
            chosen_hit_zones = chosen_hit_zones,
        }
    end

    H.test("ET #1413 actual Warlord and Chosen consumers register atomically", function()
        local error_snapshot = owner_environment_snapshot()
        local error_ok, error_reason = pcall(capture_actual_owner_specs, 2)
        H.equal(error_ok, false)
        H.truthy(tostring(error_reason):find(
            "injected actual-consumer load failure", 1, true) ~= nil)
        assert_owner_environment_restored(error_snapshot)

        local success_snapshot = owner_environment_snapshot()
        local capture = capture_actual_owner_specs()
        assert_owner_environment_restored(success_snapshot)
        H.equal(#capture.specs, 2)

        local warlord_spec, chosen_spec = capture.specs[1], capture.specs[2]
        H.equal(warlord_spec.owner, "enemy_tweaker.skaven_warlord")
        H.equal(warlord_spec.name, "et_skaven_warlord")
        H.equal(warlord_spec.source_breed, "skaven_storm_vermin_champion")
        H.equal(warlord_spec.race, "skaven")
        H.equal(warlord_spec.fingerprint,
            "et-custom-breed:v3:skaven-warlord:champion-pristine")
        H.equal(#warlord_spec.presentations, 15)
        H.equal(warlord_spec.presentations[1].target,
            capture.mod._et_warlord2_loc_strings)
        H.equal(warlord_spec.presentations[14].target,
            capture.ui_settings.breed_textures)
        H.equal(warlord_spec.presentations[15].target, capture.grudge_names)
        H.equal(#warlord_spec.readiness, 3)
        H.equal(warlord_spec.readiness[1].target, capture.mod)
        H.equal(warlord_spec.readiness[1].key, "_et_warlord2_threat_seeded")
        H.equal(warlord_spec.readiness[2].key, "_et_warlord2_breed_name")
        H.equal(warlord_spec.readiness[3].key, "_et_warlord2_ready")

        H.equal(chosen_spec.owner, "enemy_tweaker.chosen_greataxe")
        H.equal(chosen_spec.name, "et_chosen_greataxe")
        H.equal(chosen_spec.source_breed, "chaos_warrior")
        H.equal(chosen_spec.race, "chaos")
        H.equal(chosen_spec.fingerprint,
            "et-custom-breed:v3:chosen-greataxe:chaos-warrior")
        H.equal(#chosen_spec.presentations, 1)
        H.equal(chosen_spec.presentations[1].target,
            capture.mod._et_warlord2_loc_strings)
        H.equal(#chosen_spec.readiness, 1)
        H.equal(chosen_spec.readiness[1].target, capture.mod)
        H.equal(chosen_spec.readiness[1].key, "_et_chosen_ready")
        H.equal(capture.mod._et_warlord2_ready, false)
        H.equal(capture.mod._et_warlord2_threat_seeded, false)
        H.equal(capture.mod._et_warlord2_breed_name, nil)
        H.equal(capture.mod._et_chosen_ready, false)
        H.equal(#capture.hooks, 1)
        H.equal(capture.hooks[1].target, _G)
        H.equal(capture.hooks[1].name, "Localize")
        H.truthy(type(capture.runtime_checks.issue324_warlord_diag_armed)
            == "function")
        H.truthy(type(capture.runtime_checks
            .issue1413_atomic_custom_breed_registration) == "function")
        H.truthy(type(capture.runtime_checks.issue451_chosen_greataxe_prototype)
            == "function")

        local ActualRegistrar = assert(loadfile(registrar_path))()
        ActualRegistrar.lookup_lib = Lookup
        local fx = actual_consumer_runtime(capture)
        local runtime = fx.runtime
        local warlord_ok, warlord_reason, warlord = ActualRegistrar.register(
            warlord_spec, runtime)
        H.equal(warlord_ok, true)
        H.equal(warlord_reason, "registered")
        local chosen_ok, chosen_reason, chosen = ActualRegistrar.register(
            chosen_spec, runtime)
        H.equal(chosen_ok, true)
        H.equal(chosen_reason, "registered")
        H.equal(runtime.breeds[warlord_spec.name], warlord)
        H.equal(runtime.breeds[chosen_spec.name], chosen)
        H.equal(warlord.display_name, "et_skaven_warlord_name")
        H.equal(chosen.display_name, "et_chosen_greataxe_name")
        H.equal(chosen.default_inventory_template, "warrior_axe")
        H.equal(chosen.max_health[1], 2000)
        H.equal(chosen.max_health[8], 2000)
        H.equal(runtime.network_lookup.breeds[warlord_spec.name], 2)
        H.equal(runtime.network_lookup.breeds[chosen_spec.name], 3)
        H.equal(runtime.network_lookup.damage_sources[warlord_spec.name], 2)
        H.equal(runtime.network_lookup.damage_sources[chosen_spec.name], 3)
        H.equal(runtime.network_lookup.statistics_path_names[warlord_spec.name], 2)
        H.equal(runtime.network_lookup.statistics_path_names[chosen_spec.name], 3)
        H.equal(runtime.network_lookup.statistics_path_names[2], warlord_spec.name)
        H.equal(runtime.network_lookup.statistics_path_names[3], chosen_spec.name)
        local function resolve_hot_join_path(name)
            local names = runtime.network_lookup.statistics_path_names
            local encoded = { names.kills_per_breed, names[name] }
            return { names[encoded[1]], names[encoded[2]] }
        end
        local warlord_path = resolve_hot_join_path(warlord_spec.name)
        local chosen_path = resolve_hot_join_path(chosen_spec.name)
        H.equal(warlord_path[1], "kills_per_breed")
        H.equal(warlord_path[2], warlord_spec.name)
        H.equal(chosen_path[1], "kills_per_breed")
        H.equal(chosen_path[2], chosen_spec.name)
        H.equal(runtime.statistics.player.kills_per_breed[warlord_spec.name]
            .sync_on_hot_join, true)
        H.equal(runtime.statistics.player.kills_per_breed[chosen_spec.name]
            .sync_on_hot_join, true)
        H.equal(capture.mod._et_warlord2_threat_seeded, true)
        H.equal(capture.mod._et_warlord2_breed_name, warlord_spec.name)
        H.equal(capture.mod._et_warlord2_ready, true)
        H.equal(capture.mod._et_chosen_ready, true)
        H.equal(capture.mod._et_warlord2_loc_strings.et_skaven_warlord_name,
            "Skaven Warlord")
        H.equal(capture.mod._et_warlord2_loc_strings.et_chosen_greataxe_name,
            "Chaos Chosen")
        H.equal(capture.ui_settings.breed_textures[warlord_spec.name],
            "unit_frame_portrait_enemy_warlord")
        H.equal(#capture.grudge_names[warlord_spec.name], 12)
        H.truthy(not rawequal(capture.grudge_names[warlord_spec.name],
            warlord_spec.presentations[15].value),
            "table-valued presentation was published by reference")

        H.equal(runtime.breeds[warlord_spec.source_breed], fx.warlord_source)
        H.equal(runtime.breeds[chosen_spec.source_breed], fx.chosen_source)
        H.equal(fx.warlord_source.max_health, fx.warlord_health)
        H.equal(fx.chosen_source.max_health, fx.chosen_health)
        H.equal(fx.warlord_health[8], 800)
        H.equal(fx.chosen_health[1], 55)
        H.equal(runtime.actions[warlord_spec.source_breed], fx.warlord_actions)
        H.equal(runtime.actions[chosen_spec.source_breed], fx.chosen_actions)
        H.equal(fx.warlord_actions.attack.damage, 31)
        H.equal(fx.chosen_actions.attack.damage, 17)
        H.equal(fx.warlord_aliases[2], nil)
        H.equal(fx.chosen_aliases[2], nil)
        H.equal(runtime.dismemberments[warlord_spec.source_breed],
            fx.warlord_dismemberment)
        H.equal(runtime.dismemberments[chosen_spec.source_breed],
            fx.chosen_dismemberment)
        H.equal(fx.warlord_source.hit_zones_lookup, fx.warlord_hit_zones)
        H.equal(fx.chosen_source.hit_zones_lookup, fx.chosen_hit_zones)

        capture.validate_all = function()
            return ActualRegistrar.validate_all_registered(runtime)
        end
        H.equal(capture.runtime_checks
            .issue1413_atomic_custom_breed_registration(), nil)

        capture.mod._et_warlord2_threat_seeded = false
        capture.mod._et_warlord2_breed_name = nil
        capture.mod._et_warlord2_ready = false
        capture.mod._et_chosen_ready = false
        local reload_w_ok, reload_w_reason, reload_w = ActualRegistrar.register(
            warlord_spec, runtime)
        H.equal(reload_w_ok, true)
        H.equal(reload_w_reason, "revalidated")
        H.equal(reload_w, warlord)
        local reload_c_ok, reload_c_reason, reload_c = ActualRegistrar.register(
            chosen_spec, runtime)
        H.equal(reload_c_ok, true)
        H.equal(reload_c_reason, "revalidated")
        H.equal(reload_c, chosen)
        H.equal(capture.mod._et_warlord2_ready, true)
        H.equal(capture.mod._et_chosen_ready, true)

        capture.mod._et_warlord2_threat_seeded = false
        capture.mod._et_warlord2_breed_name = nil
        capture.mod._et_warlord2_ready = false
        local warlord_index = rawget(runtime.network_lookup.breeds,
            warlord_spec.name)
        rawset(runtime.network_lookup.breeds, warlord_spec.name, nil)
        local asymmetric_events = #fx.events
        local asymmetric_ok, asymmetric_reason = ActualRegistrar.register(
            warlord_spec, runtime)
        H.equal(asymmetric_ok, nil)
        H.truthy(tostring(asymmetric_reason):find("lookup_breeds", 1, true)
            ~= nil)
        H.equal(#fx.events, asymmetric_events)
        H.equal(capture.mod._et_warlord2_threat_seeded, false)
        H.equal(capture.mod._et_warlord2_breed_name, nil)
        H.equal(capture.mod._et_warlord2_ready, false)
        rawset(runtime.network_lookup.breeds, warlord_spec.name, warlord_index)
        H.equal(ActualRegistrar.register(warlord_spec, runtime), true)

        capture.mod._et_chosen_ready = false
        local chosen_hit_zones = runtime.hit_zones[chosen_spec.name]
        runtime.hit_zones[chosen_spec.name] = {}
        local tamper_events = #fx.events
        local tamper_ok, tamper_reason = ActualRegistrar.register(
            chosen_spec, runtime)
        H.equal(tamper_ok, nil)
        H.equal(tamper_reason, "hit_zones_mismatch")
        H.equal(#fx.events, tamper_events)
        H.equal(capture.mod._et_chosen_ready, false)
        runtime.hit_zones[chosen_spec.name] = chosen_hit_zones
        H.equal(ActualRegistrar.register(chosen_spec, runtime), true)
        H.equal(capture.mod._et_chosen_ready, true)
        H.equal(capture.runtime_checks
            .issue1413_atomic_custom_breed_registration(), nil)
    end)

    H.test("ET #1413 real-owner fingerprints reject coordinated persistent tamper", function()
        local cases = {
            {
                label = "warlord_behavior", owner = 1,
                mutate = function(_, breed) breed.behavior = "foreign" end,
            },
            {
                label = "warlord_threat", owner = 1,
                mutate = function(_, breed) breed.threat_value = 0 end,
            },
            {
                label = "warlord_actions", owner = 1,
                mutate = function(fx, _, spec)
                    fx.runtime.actions[spec.name].attack.damage = 999
                end,
            },
            {
                label = "warlord_dismemberment", owner = 1,
                mutate = function(fx, _, spec)
                    local replacement = { foreign = true }
                    fx.runtime.dismemberments[spec.source_breed] = replacement
                    fx.runtime.dismemberments[spec.name] = replacement
                end,
            },
            {
                label = "chosen_elite_pair", owner = 2,
                mutate = function(fx, breed, spec)
                    breed.elite = nil
                    fx.runtime.elites[spec.name] = nil
                end,
            },
            {
                label = "chosen_hit_zones", owner = 2,
                mutate = function(_, breed) breed.hit_zones_lookup.foreign = true end,
            },
            {
                label = "chosen_wire_relocation", owner = 2,
                mutate = function(fx, _, spec)
                    for _, axis in ipairs({ "breeds", "damage_sources" }) do
                        local wire = fx.runtime.network_lookup[axis]
                        rawset(wire, 1, spec.name)
                        rawset(wire, spec.name, 1)
                        rawset(wire, 3, "vanilla")
                        rawset(wire, "vanilla", 3)
                    end
                end,
            },
            {
                label = "chosen_marker", owner = 2,
                mutate = function(_, breed)
                    rawget(breed, Registrar.marker_key).foreign = true
                end,
            },
        }
        for i = 1, #cases do
            local case = cases[i]
            local capture = capture_actual_owner_specs()
            local actual = assert(loadfile(registrar_path))()
            actual.lookup_lib = Lookup
            local fx = actual_consumer_runtime(capture)
            for owner = 1, 2 do
                H.equal(actual.register(capture.specs[owner], fx.runtime), true)
            end
            local spec = capture.specs[case.owner]
            local breed = fx.runtime.breeds[spec.name]
            if case.owner == 1 then
                capture.mod._et_warlord2_threat_seeded = false
                capture.mod._et_warlord2_breed_name = nil
                capture.mod._et_warlord2_ready = false
            else
                capture.mod._et_chosen_ready = false
            end
            case.mutate(fx, breed, spec)
            local event_count = #fx.events
            local ok = actual.register(spec, fx.runtime)
            H.equal(ok, nil, case.label .. " was accepted")
            H.equal(#fx.events, event_count,
                case.label .. " reached threat or structural commit")
            if case.owner == 1 then
                H.equal(capture.mod._et_warlord2_ready, false)
                H.equal(capture.mod._et_warlord2_breed_name, nil)
                H.equal(capture.mod._et_warlord2_threat_seeded, false)
            else
                H.equal(capture.mod._et_chosen_ready, false)
            end
        end
    end)

    H.test("ET #1413 fresh registrar hot reload retains first canonical owner state", function()
        local capture = capture_actual_owner_specs()
        local first = assert(loadfile(registrar_path))()
        first.lookup_lib = Lookup
        local fx = actual_consumer_runtime(capture)
        H.equal(first.register(capture.specs[1], fx.runtime), true)
        H.equal(first.register(capture.specs[2], fx.runtime), true)
        local warlord = fx.runtime.breeds[capture.specs[1].name]
        local chosen = fx.runtime.breeds[capture.specs[2].name]

        -- The later Champion owner can retune this global source before a whole
        -- mod reload. A fresh registrar must trust the persisted detached marker,
        -- not redefine the Warlord from this presently live source.
        fx.warlord_source.max_health = { 100, 120, 140, 160, 180, 200, 230, 260 }
        fx.warlord_source.ai_strength = 10
        fx.warlord_source.primary_armor_category = 6

        local environment = owner_environment_snapshot()
        local reload_capture = capture_actual_owner_specs(nil, capture)
        assert_owner_environment_restored(environment)
        local reloaded = assert(loadfile(registrar_path))()
        reloaded.lookup_lib = Lookup
        local warlord_ok, warlord_reason, same_warlord = reloaded.register(
            reload_capture.specs[1], fx.runtime)
        H.equal(warlord_ok, true)
        H.equal(warlord_reason, "revalidated")
        H.equal(same_warlord, warlord)
        local chosen_ok, chosen_reason, same_chosen = reloaded.register(
            reload_capture.specs[2], fx.runtime)
        H.equal(chosen_ok, true)
        H.equal(chosen_reason, "revalidated")
        H.equal(same_chosen, chosen)
        H.equal(fx.warlord_source.max_health[8], 260)
        H.equal(warlord.max_health[8], 800)
        H.equal(reload_capture.mod._et_warlord2_threat_seeded, true)
        H.equal(reload_capture.mod._et_warlord2_breed_name,
            reload_capture.specs[1].name)
        H.equal(reload_capture.mod._et_warlord2_ready, true)
        H.equal(reload_capture.mod._et_chosen_ready, true)
        H.equal(reload_capture.mod._et_warlord2_loc_strings
            .et_skaven_warlord_name, "Skaven Warlord")
        H.equal(reload_capture.mod._et_warlord2_loc_strings
            .et_chosen_greataxe_name, "Chaos Chosen")
        reload_capture.validate_all = function()
            return reloaded.validate_all_registered(fx.runtime)
        end
        H.equal(reload_capture.runtime_checks
            .issue1413_atomic_custom_breed_registration(), nil)
    end)

    H.test("ET #1413 fresh reload accepts only source-baked difficulty overlays", function()
        local capture = capture_actual_owner_specs()
        local first = assert(loadfile(registrar_path))()
        first.lookup_lib = Lookup
        local fx = actual_consumer_runtime(capture)
        install_difficulty_shapes(fx.warlord_actions, fx.chosen_actions)
        H.equal(first.register(capture.specs[1], fx.runtime), true)
        H.equal(first.register(capture.specs[2], fx.runtime), true)

        local warlord_name, chosen_name =
            capture.specs[1].name, capture.specs[2].name
        local warlord_actions = fx.runtime.actions[warlord_name]
        local chosen_actions = fx.runtime.actions[chosen_name]
        local warlord_marker = fx.runtime.breeds[warlord_name][first.marker_key]
        local chosen_marker = fx.runtime.breeds[chosen_name][first.marker_key]
        H.equal(rawget(warlord_marker.actions_snapshot.attack, "damage"), nil)
        H.equal(rawget(warlord_marker.actions_snapshot.attack,
            "diminishing_damage"), nil)
        H.equal(rawget(chosen_marker.actions_snapshot.attack, "blocked_damage"), nil)

        apply_action_difficulty(fx.warlord_actions, 1)
        apply_action_difficulty(fx.chosen_actions, 1)
        apply_action_difficulty(warlord_actions, 1)
        apply_action_difficulty(chosen_actions, 1)
        local reload_capture_a = capture_actual_owner_specs(nil, capture)
        local reload_a = assert(loadfile(registrar_path))()
        reload_a.lookup_lib = Lookup
        H.equal(reload_a.register(reload_capture_a.specs[1], fx.runtime), true)
        H.equal(reload_a.register(reload_capture_a.specs[2], fx.runtime), true)
        H.equal(warlord_actions.attack.damage, 11)
        H.equal(warlord_actions.attack.diminishing_damage.amount, 1)
        H.equal(warlord_actions.attack.bot_threats[1].max_start_delay, 0.2)
        H.equal(warlord_actions.attack.bot_threats[2]
            .bot_threat_max_start_delay, 0.2)
        H.equal(chosen_actions.attack.blocked_damage, 3)
        H.equal(chosen_actions.attack.nested.bot_threat_max_start_delay, 0.1)

        apply_action_difficulty(fx.warlord_actions, 2)
        apply_action_difficulty(fx.chosen_actions, 2)
        apply_action_difficulty(warlord_actions, 2)
        apply_action_difficulty(chosen_actions, 2)
        local reload_capture_b = capture_actual_owner_specs(nil, capture)
        local reload_b = assert(loadfile(registrar_path))()
        reload_b.lookup_lib = Lookup
        H.equal(reload_b.register(reload_capture_b.specs[1], fx.runtime), true)
        H.equal(reload_b.register(reload_capture_b.specs[2], fx.runtime), true)
        H.equal(warlord_actions.attack.damage, 21)
        H.equal(warlord_actions.attack.diminishing_damage.amount, 2)
        H.equal(warlord_actions.attack.bot_threats[1].max_start_delay, 0.7)
        H.equal(chosen_actions.attack.damage, 27)
        H.equal(chosen_actions.attack.blocked_damage, 8)
        H.truthy(math.abs(chosen_actions.attack.nested
            .bot_threat_max_start_delay - 0.36) < 0.000001)

        H.equal(rawget(warlord_marker.actions_snapshot.attack, "damage"), nil,
            "difficulty A/B must not refresh the detached canonical snapshot")
        H.equal(rawget(chosen_marker.actions_snapshot.attack, "blocked_damage"), nil,
            "difficulty A/B must not refresh the detached canonical snapshot")
        H.equal(warlord_marker.actions_snapshot.attack.duration, 1.25)
        H.equal(chosen_marker.actions_snapshot.attack.duration, 1.5)
    end)

    H.test("ET #1413 difficulty overlay drift rejects before any write", function()
        local cases = {
            {
                name = "stable", reason = "existing_actions_fingerprint_mismatch",
                mutate = function(fx, actions) actions.attack.duration = 9 end,
            },
            {
                name = "unauthorized", reason = "existing_actions_fingerprint_mismatch",
                mutate = function(fx, actions) actions.attack.foreign_overlay = 11 end,
            },
            { name = "undeclared_bot_threat",
              reason = "existing_actions_fingerprint_mismatch",
              mutate = function(_, actions)
                  actions.attack.unrelated_threat.max_start_delay = 0.1 end },
            {
                name = "value", reason = "existing_actions_overlay_mismatch",
                mutate = function(fx, actions) actions.attack.damage = 999 end,
            },
            { name = "source_declaration",
              reason = "existing_actions_overlay_source_mismatch",
              mutate = function(fx)
                  fx.source_actions.attack.difficulty_damage[1] = 999 end },
            { name = "source_duration",
              reason = "existing_actions_overlay_source_mismatch",
              mutate = function(fx)
                  fx.source_actions.attack.bot_threats[1].duration = 9 end },
            { name = "source_value", reason = "existing_actions_overlay_mismatch",
              mutate = function(fx) fx.source_actions.attack.damage = 998 end },
        }
        for i = 1, #cases do
            local case = cases[i]
            local fx = difficulty_fixture("et_difficulty_reject_" .. case.name)
            local actions = fx.runtime.actions[fx.name]
            case.mutate(fx, actions)
            local events_before = #fx.events
            local ok, reason = Registrar.register(fx.spec, fx.runtime)
            H.equal(ok, nil, case.name .. " difficulty tamper was accepted")
            H.equal(reason, case.reason)
            H.equal(#fx.events, events_before,
                case.name .. " difficulty tamper reached threat/raw writes")
            H.equal(fx.readiness.ready, false)
        end
    end)

    H.test("ET #1413 registers Warlord and Chosen-shaped immutable-source transactions", function()
        local fx = fixture("et_atomic_success")
        local source_health = fx.source.max_health
        local source_action = fx.source_actions.attack
        local ok, reason, breed = Registrar.register(fx.spec, fx.runtime)
        H.equal(ok, true)
        H.equal(reason, "registered")
        H.equal(rawget(fx.runtime.breeds, fx.name), breed)
        local marker = rawget(breed, Registrar.marker_key)
        H.equal(Registrar.schema, 3)
        H.equal(marker.schema, 3)
        H.equal(rawget(fx.runtime.actions, fx.name),
            marker.actions_ref)
        H.equal(marker.breed_index, 2)
        H.equal(marker.damage_source_index, 2)
        H.equal(marker.statistics_path_index, 2)
        H.truthy(marker.breed_snapshot ~= breed)
        H.truthy(marker.actions_snapshot ~= marker.actions_ref)
        H.truthy(marker.dismemberment_snapshot ~= marker.dismemberment_ref)
        H.equal(marker.threat_value, 32)
        H.equal(marker.elite, false)
        H.equal(marker.breed_index, 2)
        H.equal(marker.damage_source_index, 2)
        H.equal(marker.hit_zones_ref, breed.hit_zones_lookup)
        H.equal(fx.source.max_health, source_health)
        H.equal(fx.source.max_health[8], 800)
        H.equal(fx.source_actions.attack, source_action)
        H.equal(fx.source_actions.attack.damage, 10)
        H.equal(fx.runtime.network_lookup.breeds[fx.name], 2)
        H.equal(fx.runtime.network_lookup.damage_sources[fx.name], 2)
        H.equal(fx.runtime.package_settings.breed_to_aliases[fx.source_name][2], fx.name)
        H.equal(fx.source_aliases[2], nil,
            "reverse aliases must be replaced from an off-table copy")
        H.equal(fx.runtime.dismemberments[fx.name], fx.source_dismemberment)
        H.equal(fx.runtime.race_sets.skaven[fx.name], true)
        H.equal(fx.runtime.hit_zones[fx.name], breed.hit_zones_lookup)
        H.equal(fx.threat[fx.name], 32)
        H.equal(fx.readiness.ready, true)
        H.equal(fx.events[1], "threat", "no real raw write may precede threat seed")
        H.equal(Registrar.validate_registered(fx.spec, fx.runtime), true)
        local breed_write, ready_write
        for i = 2, #fx.events do
            local event = fx.events[i]
            if event.target == fx.runtime.breeds and event.key == fx.name then breed_write = i end
            if event.target == fx.readiness and event.key == "ready" then ready_write = i end
        end
        H.truthy(breed_write ~= nil and ready_write ~= nil and ready_write < breed_write,
            "readiness must remain rollback-covered before final breed publication")
        H.equal(breed_write, #fx.events,
            "Breeds[name] must be the final raw write")

        local chosen = fixture("et_atomic_chosen")
        chosen.source.race = "chaos"
        chosen.source.elite = true
        chosen.spec.race = "chaos"
        chosen.spec.fingerprint = "test-chosen-fingerprint-v1"
        chosen.spec.configure = function(candidate)
            candidate.display_name = "et_chosen_greataxe_name"
            candidate.default_inventory_template = "et_chosen_greataxe_inventory"
            candidate.boss_staggers = true
            candidate.max_health = {}
            for i = 1, 8 do candidate.max_health[i] = 2000 end
        end
        chosen.spec.validate_breed = function(candidate)
            if candidate.display_name ~= "et_chosen_greataxe_name"
                or candidate.default_inventory_template
                    ~= "et_chosen_greataxe_inventory"
                or candidate.boss_staggers ~= true then
                return nil, "chosen_override_mismatch"
            end
            for i = 1, 8 do
                if candidate.max_health[i] ~= 2000 then
                    return nil, "chosen_health_mismatch"
                end
            end
            return true
        end
        local chosen_source_health = chosen.source.max_health
        local chosen_ok, chosen_reason, chosen_breed = Registrar.register(
            chosen.spec, chosen.runtime)
        H.equal(chosen_ok, true)
        H.equal(chosen_reason, "registered")
        H.equal(chosen.runtime.breeds[chosen.name], chosen_breed)
        H.equal(chosen.runtime.race_sets.chaos[chosen.name], true)
        H.equal(chosen.runtime.race_sets.skaven[chosen.name], nil)
        H.equal(chosen.runtime.elites[chosen.name], true)
        H.equal(chosen_breed.max_health[1], 2000)
        H.equal(chosen_breed.max_health[8], 2000)
        H.equal(chosen.source.max_health, chosen_source_health)
        H.equal(chosen.source.max_health[1], 300)
        H.equal(Registrar.validate_registered(chosen.spec, chosen.runtime), true)
    end)

    H.test("ET #1413 exact reload revalidates every surface and republishes only ephemeral state", function()
        local fx = fixture("et_atomic_reload")
        H.equal(Registrar.register(fx.spec, fx.runtime), true)
        local aliases = fx.runtime.package_settings.breed_to_aliases[fx.source_name]
        local breed = fx.runtime.breeds[fx.name]
        fx.localization.test_name = nil
        fx.readiness.ready = false
        fx.readiness.breed_name = nil
        fx.readiness.threat_seeded = false
        fx.threat[fx.name] = 0
        fx.runtime.network_constants = {}
        fx.runtime.network = nil
        local ok, reason, reloaded = Registrar.register(fx.spec, fx.runtime)
        H.equal(ok, true)
        H.equal(reason, "revalidated")
        H.equal(reloaded, breed)
        H.equal(fx.runtime.package_settings.breed_to_aliases[fx.source_name], aliases)
        H.equal(#aliases, 2)
        H.equal(fx.localization.test_name, "Test")
        H.equal(fx.readiness.ready, true)
        H.equal(fx.threat[fx.name], 32,
            "reload must seed the canonical marker threat, not hidden residue")
        H.equal(Registrar.validate_registered(fx.spec, fx.runtime), true)

        fx.localization.test_name = nil
        local loc_valid, loc_reason = Registrar.validate_registered(fx.spec, fx.runtime)
        H.equal(loc_valid, nil)
        H.equal(loc_reason, "registered_state_incomplete:presentation_1")
        H.equal(fx.localization.test_name, nil,
            "validation must never repair ephemeral presentation state")
        H.equal(Registrar.register(fx.spec, fx.runtime), true)

        fx.readiness.ready = false
        local ready_valid, ready_reason = Registrar.validate_registered(
            fx.spec, fx.runtime)
        H.equal(ready_valid, nil)
        H.equal(ready_reason, "registered_state_incomplete:readiness_3")
        H.equal(fx.readiness.ready, false,
            "validation must never republish readiness")
        H.equal(Registrar.register(fx.spec, fx.runtime), true)

        fx.portraits[fx.name] = "foreign"
        local presentation_events = #fx.events
        local presentation_ok, presentation_reason = Registrar.register(
            fx.spec, fx.runtime)
        H.equal(presentation_ok, nil)
        H.equal(presentation_reason, "presentation_2_mismatch")
        H.equal(#fx.events, presentation_events,
            "persistent presentation mismatch must not reach threat or raw writes")
        fx.portraits[fx.name] = "portrait"

        fx.runtime.hit_zones[fx.name] = {}
        fx.readiness.ready = false
        local hit_zone_events = #fx.events
        local rejected, rejected_reason = Registrar.register(fx.spec, fx.runtime)
        H.equal(rejected, nil)
        H.equal(rejected_reason, "hit_zones_mismatch")
        H.equal(fx.readiness.ready, false)
        H.equal(#fx.events, hit_zone_events,
            "persistent side-surface mismatch must reject before commit")
    end)

    H.test("ET #1413 table presentations are detached and reject alias tamper", function()
        local function prepared(name)
            local fx = fixture(name)
            local shared = { color = "red" }
            local canonical = {
                primary = shared, secondary = shared,
                nested = { value = 4 },
            }
            fx.spec.presentations[3].value = canonical
            H.equal(Registrar.register(fx.spec, fx.runtime), true)
            local live = fx.grudge_names[fx.name]
            H.truthy(not rawequal(live, canonical))
            H.truthy(not rawequal(live.primary, canonical.primary))
            H.truthy(rawequal(live.primary, live.secondary),
                "detached presentation lost declared shared topology")
            H.truthy(not rawequal(live.nested, canonical.nested))
            canonical.nested.value = 9
            H.equal(live.nested.value, 4,
                "canonical declaration mutation leaked into live presentation")
            canonical.nested.value = 4
            fx.readiness.ready = false
            return fx, live, canonical
        end

        local in_place, in_place_live = prepared("et_presentation_in_place")
        in_place_live.nested.value = 99
        local in_place_events = #in_place.events
        local in_place_ok, in_place_reason = Registrar.register(
            in_place.spec, in_place.runtime)
        H.equal(in_place_ok, nil)
        H.equal(in_place_reason, "presentation_3_mismatch")
        H.equal(#in_place.events, in_place_events,
            "in-place presentation tamper reached threat/raw writes")
        H.equal(in_place.readiness.ready, false)

        local root_alias, _, root_canonical = prepared(
            "et_presentation_root_alias")
        root_alias.grudge_names[root_alias.name] = root_canonical
        local root_events = #root_alias.events
        local root_ok, root_reason = Registrar.register(
            root_alias.spec, root_alias.runtime)
        H.equal(root_ok, nil)
        H.equal(root_reason, "presentation_3_mismatch")
        H.equal(#root_alias.events, root_events,
            "root presentation alias reached threat/raw writes")

        local nested_alias, nested_live, nested_canonical = prepared(
            "et_presentation_nested_alias")
        nested_live.primary = nested_canonical.primary
        nested_live.secondary = nested_canonical.primary
        local nested_events = #nested_alias.events
        local nested_ok, nested_reason = Registrar.register(
            nested_alias.spec, nested_alias.runtime)
        H.equal(nested_ok, nil)
        H.equal(nested_reason, "presentation_3_mismatch")
        H.equal(#nested_alias.events, nested_events,
            "nested presentation alias reached threat/raw writes")
    end)

    H.test("ET #1413 schema-3 marker rejects coherent persistent tamper before threat", function()
        local cases = {
            {
                name = "breed_scalar", reason = "existing_breed_fingerprint_mismatch",
                mutate = function(_, breed) breed.boss = false end,
            },
            {
                name = "breed_nested", reason = "existing_breed_fingerprint_mismatch",
                mutate = function(_, breed) breed.max_health[1] = 301 end,
            },
            {
                name = "threat", reason = "existing_threat_value_mismatch",
                mutate = function(_, breed) breed.threat_value = 7 end,
            },
            {
                name = "actions", reason = "existing_actions_fingerprint_mismatch",
                mutate = function(fx) fx.runtime.actions[fx.name].attack.damage = 11 end,
            },
            {
                name = "actions_identity", reason = "existing_actions_mismatch",
                mutate = function(fx)
                    fx.runtime.actions[fx.name] = clone(fx.runtime.actions[fx.name])
                end,
            },
            {
                name = "elite_pair", reason = "existing_elite_fingerprint_mismatch",
                mutate = function(fx, breed)
                    breed.elite = true
                    fx.runtime.elites[fx.name] = true
                end,
            },
            {
                name = "hit_zones_content", reason = "hit_zones_fingerprint_mismatch",
                mutate = function(_, breed) breed.hit_zones_lookup.foreign = true end,
            },
            {
                name = "hit_zones_identity", reason = "hit_zones_mismatch",
                mutate = function(fx, breed)
                    local replacement = clone(breed.hit_zones_lookup)
                    breed.hit_zones_lookup = replacement
                    fx.runtime.hit_zones[fx.name] = replacement
                end,
            },
            {
                name = "dismemberment_pair", reason = "dismemberment_mismatch",
                mutate = function(fx)
                    local replacement = { foreign = true }
                    fx.runtime.dismemberments[fx.source_name] = replacement
                    fx.runtime.dismemberments[fx.name] = replacement
                end,
            },
            {
                name = "dismemberment_content", reason = "dismemberment_mismatch",
                mutate = function(fx)
                    fx.runtime.dismemberments[fx.name].foreign = true
                end,
            },
            {
                name = "wire_relocation", reason = "existing_wire_identity_mismatch",
                mutate = function(fx)
                    for _, axis in ipairs({
                        "breeds", "damage_sources", "statistics_path_names",
                    }) do
                        local wire = fx.runtime.network_lookup[axis]
                        local original = rawget(wire, 1)
                        rawset(wire, 1, fx.name)
                        rawset(wire, fx.name, 1)
                        rawset(wire, 2, original)
                        rawset(wire, original, 2)
                    end
                end,
            },
            {
                name = "marker_extra", reason = "existing_breed_fingerprint_mismatch",
                mutate = function(_, _, marker) marker.foreign = true end,
            },
            {
                name = "marker_schema", reason = "existing_breed_fingerprint_mismatch",
                mutate = function(_, _, marker) marker.schema = 2 end,
            },
            {
                name = "marker_metatable", reason = "existing_breed_fingerprint_mismatch",
                mutate = function(_, _, marker) setmetatable(marker, {}) end,
            },
            {
                name = "marker_breed_snapshot",
                reason = "existing_breed_fingerprint_mismatch",
                mutate = function(_, _, marker) marker.breed_snapshot.boss = false end,
            },
            {
                name = "marker_actions_snapshot",
                reason = "existing_actions_fingerprint_mismatch",
                mutate = function(_, _, marker)
                    marker.actions_snapshot.attack.damage = 11
                end,
            },
            {
                name = "marker_actions_not_detached",
                reason = "existing_actions_fingerprint_mismatch",
                mutate = function(_, _, marker)
                    marker.actions_snapshot = marker.actions_ref
                end,
            },
            {
                name = "marker_breed_not_detached",
                reason = "existing_breed_fingerprint_mismatch",
                mutate = function(_, breed, marker)
                    marker.breed_snapshot = breed
                end,
            },
            {
                name = "marker_dismemberment_not_detached",
                reason = "dismemberment_mismatch",
                mutate = function(_, _, marker)
                    marker.dismemberment_snapshot = marker.dismemberment_ref
                end,
            },
            {
                name = "marker_wire", reason = "existing_wire_identity_mismatch",
                mutate = function(_, _, marker) marker.breed_index = 1 end,
            },
            {
                name = "marker_statistics_wire",
                reason = "existing_wire_identity_mismatch",
                mutate = function(_, _, marker) marker.statistics_path_index = 1 end,
            },
            {
                name = "marker_hit_zones", reason = "hit_zones_mismatch",
                mutate = function(_, _, marker) marker.hit_zones_ref = {} end,
            },
        }
        for i = 1, #cases do
            local case = cases[i]
            assert_reload_rejects(
                fixture("et_schema3_" .. case.name), case.mutate, case.reason)
        end
    end)

    H.test("ET #1413 detached fingerprints preserve cycles and shared topology", function()
        local breed_fx = fixture("et_schema3_breed_topology")
        local shared = { value = 1 }
        shared.self = shared
        breed_fx.source.shared_a = shared
        breed_fx.source.shared_b = shared
        assert_reload_rejects(breed_fx, function(_, breed)
            breed.shared_b = clone(breed.shared_b)
        end, "existing_breed_fingerprint_mismatch")

        local action_fx = fixture("et_schema3_action_topology")
        local action_shared = { value = 2 }
        action_shared.self = action_shared
        action_fx.source_actions.shared_a = action_shared
        action_fx.source_actions.shared_b = action_shared
        assert_reload_rejects(action_fx, function(fx)
            fx.runtime.actions[fx.name].shared_b = clone(
                fx.runtime.actions[fx.name].shared_b)
        end, "existing_actions_fingerprint_mismatch")
    end)

    H.test("ET #1413 performance reload accepts only finite nonnegative integers", function()
        local valid = fixture("et_performance_live_count")
        H.equal(Registrar.register(valid.spec, valid.runtime), true)
        valid.runtime.performance._activated_per_breed[valid.name] = 7
        valid.readiness.ready = false
        local valid_ok, valid_reason = Registrar.register(valid.spec, valid.runtime)
        H.equal(valid_ok, true)
        H.equal(valid_reason, "revalidated")

        local invalid = {
            { "nil", function() return nil end },
            { "false", function() return false end },
            { "string", function() return "1" end },
            { "nan", function() return 0 / 0 end },
            { "positive_inf", function() return math.huge end },
            { "negative_inf", function() return -math.huge end },
            { "negative", function() return -1 end },
            { "fraction", function() return 0.5 end },
        }
        for i = 1, #invalid do
            local row = invalid[i]
            local fx = fixture("et_performance_" .. row[1])
            assert_reload_rejects(fx, function(current)
                current.runtime.performance._activated_per_breed[current.name] = row[2]()
            end, "performance_mismatch")
        end
    end)

    H.test("ET #1413 plans all three strict wire axes before touching live lookup", function()
        local fx = fixture("et_second_wire_reject")
        fx.runtime.network_lookup.damage_sources[3] = "sparse"
        local breeds_meta = getmetatable(fx.runtime.network_lookup.breeds)
        local ok, reason = Registrar.register(fx.spec, fx.runtime)
        H.equal(ok, nil)
        H.truthy(reason:find("lookup_damage_sources", 1, true) ~= nil)
        assert_unpublished(fx)
        H.equal(getmetatable(fx.runtime.network_lookup.breeds), breeds_meta)

        local half = fixture("et_half_wire")
        rawset(half.runtime.network_lookup.breeds, 2, half.name)
        rawset(half.runtime.network_lookup.breeds, half.name, 2)
        local half_ok, half_reason = Registrar.register(half.spec, half.runtime)
        H.equal(half_ok, nil)
        H.equal(half_reason, "new_breed_wire_residue")
        H.equal(rawget(half.runtime.network_lookup.damage_sources, half.name), nil)
        H.equal(rawget(half.runtime.network_lookup.statistics_path_names,
            half.name), nil)
    end)

    H.test("ET #1413 statistics path identity rejects malformed and relocated state", function()
        local malformed = {
            {
                label = "sparse",
                mutate = function(fx)
                    rawset(fx.runtime.network_lookup.statistics_path_names, 3, "gap")
                end,
            },
            {
                label = "asymmetric_forward",
                mutate = function(fx)
                    rawset(fx.runtime.network_lookup.statistics_path_names, 2, fx.name)
                end,
            },
            {
                label = "asymmetric_reverse",
                mutate = function(fx)
                    rawset(fx.runtime.network_lookup.statistics_path_names, fx.name, 2)
                end,
            },
            {
                label = "foreign",
                mutate = function(fx)
                    local axis = fx.runtime.network_lookup.statistics_path_names
                    rawset(axis, 2, "foreign_path")
                    rawset(axis, "foreign_path", 2)
                    rawset(axis, fx.name, 2)
                end,
            },
        }
        for i = 1, #malformed do
            local case = malformed[i]
            local fx = fixture("et_statistics_" .. case.label)
            case.mutate(fx)
            local ok, reason = Registrar.register(fx.spec, fx.runtime)
            H.equal(ok, nil, case.label .. " statistics path was accepted")
            H.truthy(tostring(reason):find(
                "lookup_statistics_path_names", 1, true) ~= nil)
            H.equal(#fx.events, 0,
                case.label .. " statistics path reached threat/raw writes")
            H.equal(rawget(fx.runtime.network_lookup.breeds, fx.name), nil)
            H.equal(rawget(fx.runtime.network_lookup.damage_sources, fx.name), nil)
        end

        local relocated = fixture("et_statistics_relocated")
        H.equal(Registrar.register(relocated.spec, relocated.runtime), true)
        local axis = relocated.runtime.network_lookup.statistics_path_names
        rawset(axis, 2, "foreign_path")
        rawset(axis, "foreign_path", 2)
        rawset(axis, relocated.name, 3)
        rawset(axis, 3, relocated.name)
        relocated.readiness.ready = false
        local events_before = #relocated.events
        local relocated_ok, relocated_reason = Registrar.register(
            relocated.spec, relocated.runtime)
        H.equal(relocated_ok, nil)
        H.equal(relocated_reason, "existing_wire_identity_mismatch")
        H.equal(#relocated.events, events_before,
            "relocated statistics path reached threat/raw writes")
        H.equal(relocated.readiness.ready, false)
    end)

    H.test("ET #1413 reads capacity only from guarded runtime authority", function()
        local boundary = fixture("et_cap_boundary", 2)
        H.equal(Registrar.register(boundary.spec, boundary.runtime), true)

        local over = fixture("et_cap_over", 1)
        local ok, reason = Registrar.register(over.spec, over.runtime)
        H.equal(ok, nil)
        H.equal(reason, "damage_source_cap_exceeded")
        assert_unpublished(over)

        local statistics_over = fixture("et_statistics_cap_over")
        statistics_over.runtime.network.type_info = function(kind)
            if kind == "statistics_path_lookup" then return { max = 1 } end
            return { max = 2 }
        end
        local statistics_ok, statistics_reason = Registrar.register(
            statistics_over.spec, statistics_over.runtime)
        H.equal(statistics_ok, nil)
        H.equal(statistics_reason, "statistics_path_cap_exceeded")
        assert_unpublished(statistics_over)

        local statistics_unavailable = fixture("et_statistics_cap_missing")
        statistics_unavailable.runtime.network = {
            type_info = function() error("statistics authority unavailable") end,
        }
        local unavailable_ok, unavailable_reason = Registrar.register(
            statistics_unavailable.spec, statistics_unavailable.runtime)
        H.equal(unavailable_ok, nil)
        H.equal(unavailable_reason, "statistics_path_cap_unavailable")
        assert_unpublished(statistics_unavailable)

        local unavailable = fixture("et_cap_missing")
        unavailable.runtime.network_constants = {}
        unavailable.runtime.network = { type_info = function() error("not ready") end }
        local missing_ok, missing_reason = Registrar.register(
            unavailable.spec, unavailable.runtime)
        H.equal(missing_ok, nil)
        H.equal(missing_reason, "damage_source_cap_unavailable")
        assert_unpublished(unavailable)

        local fallback = fixture("et_cap_fallback")
        fallback.runtime.network_constants = nil
        fallback.runtime.network = {
            type_info = function(kind)
                H.truthy(kind == "damage_source_id"
                    or kind == "statistics_path_lookup")
                return { max = 2 }
            end,
        }
        H.equal(Registrar.register(fallback.spec, fallback.runtime), true)

        local exact = fixture("et_statistics_exact_without_capacity")
        H.equal(Registrar.register(exact.spec, exact.runtime), true)
        exact.runtime.network = nil
        exact.runtime.network_constants = nil
        H.equal(Registrar.register(exact.spec, exact.runtime), true,
            "exact existing rows must not require capacity authority")
    end)

    require("test_et_custom_breed_registrar_adversarial")(H, {
        fixture = fixture, Registrar = Registrar,
        assert_unpublished = assert_unpublished, STAT_NAMES = STAT_NAMES,
        clone = clone, Lookup = Lookup, STRICT = STRICT, repo_root = repo_root,
    })
end
