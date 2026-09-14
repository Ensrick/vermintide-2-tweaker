-- #451 registrar contract additions: the DLC weapon-kill statistics families,
-- the hot-join health capacity preflight, the declared-spec accessor, and the
-- readiness-coherence runtime check driven through the real Warlord/Chosen
-- owners. Loaded from test_et_custom_breed_registrar with its shared fixtures.
return function(H, C)
    local fixture, Registrar = assert(C.fixture), assert(C.Registrar)
    local assert_unpublished = assert(C.assert_unpublished)
    local Lookup, repo_root = assert(C.Lookup), assert(C.repo_root)
    local capture_actual_owner_specs = assert(C.capture_actual_owner_specs)
    local actual_consumer_runtime = assert(C.actual_consumer_runtime)
    local with_raw_bindings = assert(C.with_raw_bindings)
    local registrar_path = repo_root
        .. "/enemy_tweaker/scripts/mods/enemy_tweaker/_et_custom_breed_registrar.lua"

    local function family(fx)
        return fx.runtime.statistics.player.weapon_kills_per_breed
    end

    H.test("ET #451 registrar seeds every DLC weapon-kill row from the source row", function()
        local fx = fixture("et_dlc_rows")
        local source_hammer = family(fx).test_hammer[fx.source_name]
        local source_blade = family(fx).test_blade[fx.source_name]
        H.equal(Registrar.register(fx.spec, fx.runtime), true)
        local hammer = family(fx).test_hammer[fx.name]
        local blade = family(fx).test_blade[fx.name]
        H.equal(type(hammer), "table")
        H.equal(type(blade), "table")
        H.equal(hammer.database_name, "test_hammer_" .. fx.name)
        H.equal(blade.database_name, fx.name)
        H.equal(hammer.name, fx.name)
        H.equal(blade.name, fx.name)
        H.equal(hammer.source, "player_data")
        H.equal(hammer.value, 0)
        H.truthy(not rawequal(hammer, source_hammer), "custom row aliases the source row")
        H.equal(source_hammer.database_name, "test_hammer_" .. fx.source_name)
        H.equal(source_hammer.name, fx.source_name)
        H.equal(source_blade.database_name, fx.source_name)
        H.equal(source_blade.name, fx.source_name)
        H.equal(Registrar.validate_registered(fx.spec, fx.runtime), true)
        fx.readiness.ready = false
        local ok, reason = Registrar.register(fx.spec, fx.runtime)
        H.equal(ok, true)
        H.equal(reason, "revalidated")
        H.truthy(rawequal(family(fx).test_hammer[fx.name], hammer),
            "exact reload replaced a persistent weapon row")
    end)

    H.test("ET #451 registrar fails closed on missing, malformed, residual, and drifted weapon rows", function()
        local function rejects(label, mutate, expected_reason, after_register, keep_residue)
            local fx = fixture("et_dlc_" .. label)
            if after_register then
                H.equal(Registrar.register(fx.spec, fx.runtime), true)
                fx.readiness.ready = false
                fx.readiness.breed_name = nil
                fx.readiness.threat_seeded = false
            end
            local events = #fx.events
            mutate(fx)
            local ok, reason = Registrar.register(fx.spec, fx.runtime)
            H.equal(ok, nil, label .. " was accepted")
            H.equal(reason, expected_reason)
            H.equal(#fx.events, events, label .. " reached threat or a raw write")
            H.equal(fx.readiness.ready, false)
            if not after_register and not keep_residue then assert_unpublished(fx) end
            return fx
        end
        rejects("missing_family", function(fx)
            fx.runtime.statistics.player.weapon_kills_per_breed = nil
        end, "statistics_weapon_kills_per_breed_missing")
        rejects("foreign_family", function(fx)
            fx.runtime.statistics.player.weapon_kills_per_breed = "foreign"
        end, "statistics_weapon_kills_per_breed_missing")
        rejects("invalid_weapon", function(fx)
            family(fx).test_hammer = "foreign"
        end, "statistics_weapon_kills_per_breed_invalid")
        rejects("source_row_missing", function(fx)
            family(fx).test_hammer[fx.source_name] = nil
        end, "statistics_weapon_kills_per_breed_shape:test_hammer")
        rejects("source_row_unnamed", function(fx)
            family(fx).test_blade[fx.source_name].database_name = "other_breed"
        end, "statistics_weapon_kills_per_breed_shape:test_blade")
        rejects("source_row_ambiguous", function(fx)
            family(fx).test_blade[fx.source_name].database_name =
                fx.source_name .. "_" .. fx.source_name
        end, "statistics_weapon_kills_per_breed_shape:test_blade")
        rejects("source_row_counted", function(fx)
            family(fx).test_hammer[fx.source_name].value = 3
        end, "statistics_weapon_kills_per_breed_shape:test_hammer")
        rejects("source_row_metatable", function(fx)
            setmetatable(family(fx).test_hammer[fx.source_name], {})
        end, "statistics_weapon_kills_per_breed_shape:test_hammer")
        local residue = rejects("residue", function(fx)
            family(fx).test_blade[fx.name] = { source = "player_data", value = 0 }
        end, "statistics_weapon_kills_per_breed_residue:test_blade", false, true)
        H.equal(rawget(residue.runtime.breeds, residue.name), nil)
        H.equal(rawget(family(residue).test_hammer, residue.name), nil)
        H.equal(family(residue).test_blade[residue.name].value, 0,
            "residue must be left exactly as found")
        rejects("aliased_weapons", function(fx)
            family(fx).test_blade = family(fx).test_hammer
        end, "duplicate_write:statistics_weapon_kills_per_breed:test_hammer")
        rejects("reload_drift", function(fx)
            family(fx).test_hammer[fx.name].database_name = "foreign"
        end, "statistics_weapon_kills_per_breed_mismatch:test_hammer", true)
        rejects("reload_removed", function(fx)
            family(fx).test_blade[fx.name] = nil
        end, "statistics_weapon_kills_per_breed_mismatch:test_blade", true)
        local aliased = rejects("reload_aliased", function(fx)
            family(fx).test_blade[fx.name] = family(fx).test_blade[fx.source_name]
        end, "statistics_weapon_kills_per_breed_mismatch:test_blade", true)
        H.equal(family(aliased).test_blade[aliased.source_name].database_name,
            aliased.source_name, "reload rejection mutated the source row")
    end)

    H.test("ET #451 registrar proves candidate health below the hot-join sync capacity", function()
        local function health_fixture(label, health, cap)
            local fx = fixture("et_health_" .. label)
            fx.source.max_health = health
            fx.spec.validate_breed = function(breed)
                if breed.display_name ~= "test_name" then return nil, "display" end
                return true
            end
            if cap ~= nil then
                fx.runtime.network_constants.damage_hotjoin_sync = { max = cap }
            end
            return fx
        end
        local function rejected(fx, expected_reason)
            local ok, reason = Registrar.register(fx.spec, fx.runtime)
            H.equal(ok, nil, expected_reason .. " was accepted")
            H.equal(reason, expected_reason)
            H.equal(#fx.events, 0, expected_reason .. " reached threat or a raw write")
            assert_unpublished(fx)
        end

        local below = health_fixture("below", { 300, 800, 4095.75 }, 4096)
        H.equal(Registrar.register(below.spec, below.runtime), true)
        H.equal(below.runtime.breeds[below.name].max_health[3], 4095.75)

        rejected(health_fixture("at_cap", { 300, 800 }, 800), "health_sync_cap_exceeded")
        rejected(health_fixture("over", { 300, 2000 }, 1000), "health_sync_cap_exceeded")
        rejected(health_fixture("off_grid", { 300, 800.1 }, 4096),
            "health_not_network_representable")
        rejected(health_fixture("sparse", { 300, nil, 800 }, 4096), "max_health_invalid")
        rejected(health_fixture("foreign", "lots", 4096), "max_health_invalid")
        rejected(health_fixture("negative", { -1, 300 }, 4096), "max_health_invalid")
        rejected(health_fixture("empty", {}, 4096), "max_health_invalid")
        rejected(health_fixture("keyed", { a = 300 }, 4096), "max_health_invalid")

        -- The boot loop skips breeds without max_health; so does the registrar.
        local absent = health_fixture("absent", nil, 4096)
        H.equal(Registrar.register(absent.spec, absent.runtime), true)
        H.equal(absent.runtime.breeds[absent.name].max_health, nil)

        -- Guarded fallback to Network.type_info when NetworkConstants lacks
        -- or malforms the row; both authorities absent fails closed.
        local fallback = health_fixture("fallback", { 300, 800 }, nil)
        fallback.runtime.network_constants = { damage_source_id = { max = 2 } }
        H.equal(Registrar.register(fallback.spec, fallback.runtime), true)
        local malformed = health_fixture("malformed_cap", { 300, 800 }, 0)
        H.equal(Registrar.register(malformed.spec, malformed.runtime), true)
        local unavailable = health_fixture("unavailable", { 300, 800 }, nil)
        unavailable.runtime.network_constants = { damage_source_id = { max = 2 } }
        unavailable.runtime.network.type_info = function(kind)
            if kind == "damage_hotjoin_sync" then error("no float authority") end
            return { max = 2 }
        end
        rejected(unavailable, "health_sync_cap_unavailable")
        local absent_network = health_fixture("no_network", { 300, 800 }, nil)
        absent_network.runtime.network_constants = { damage_source_id = { max = 2 } }
        absent_network.runtime.network = nil
        local no_network_ok, no_network_reason = Registrar.register(
            absent_network.spec, absent_network.runtime)
        H.equal(no_network_ok, nil)
        H.equal(no_network_reason, "statistics_path_cap_unavailable",
            "wire capacity authority still precedes the health authority")

        -- Exact reload pins health through the detached snapshot and never
        -- re-reads capacity authority.
        local reload = health_fixture("reload", { 300, 800 }, 4096)
        H.equal(Registrar.register(reload.spec, reload.runtime), true)
        reload.readiness.ready = false
        reload.runtime.network_constants = nil
        reload.runtime.network = nil
        local reload_ok, reload_reason = Registrar.register(reload.spec, reload.runtime)
        H.equal(reload_ok, true)
        H.equal(reload_reason, "revalidated")
        reload.readiness.ready = false
        reload.runtime.breeds[reload.name].max_health[2] = 9000
        local events = #reload.events
        local drift_ok, drift_reason = Registrar.register(reload.spec, reload.runtime)
        H.equal(drift_ok, nil)
        H.equal(drift_reason, "existing_breed_fingerprint_mismatch")
        H.equal(#reload.events, events)
        H.equal(reload.readiness.ready, false)

        -- A Chosen-shaped nine-slot override is proven against the same cap
        -- while the donor's own array stays untouched.
        local function chosen_like(label, cap)
            local fx = health_fixture(label, { 55, 65 }, cap)
            fx.spec.configure = function(breed)
                breed.display_name = "test_name"
                local health = {}
                for i = 1, 9 do health[i] = 2000 end
                breed.max_health = health
            end
            return fx
        end
        rejected(chosen_like("chosen_at_cap", 2000), "health_sync_cap_exceeded")
        local chosen_ok = chosen_like("chosen_below_cap", 8191.75)
        H.equal(Registrar.register(chosen_ok.spec, chosen_ok.runtime), true)
        H.equal(#chosen_ok.runtime.breeds[chosen_ok.name].max_health, 9)
        H.equal(chosen_ok.runtime.breeds[chosen_ok.name].max_health[9], 2000)
        H.equal(#chosen_ok.source.max_health, 2)
        H.equal(chosen_ok.source.max_health[2], 65)
    end)

    H.test("ET #451 declared_specs returns declaration-order copies including rejected specs", function()
        local Fresh = assert(loadfile(registrar_path))()
        Fresh.lookup_lib = Lookup
        H.equal(#Fresh.declared_specs(), 0)
        local first = fixture("et_declared_first")
        H.equal(Fresh.register(first.spec, first.runtime), true)
        local second = fixture("et_declared_second")
        second.runtime.statistics.player.weapon_kills_per_breed = nil
        H.equal(Fresh.register(second.spec, second.runtime), nil)
        local specs = Fresh.declared_specs()
        H.equal(#specs, 2)
        H.truthy(rawequal(specs[1], first.spec))
        H.truthy(rawequal(specs[2], second.spec))
        specs[1] = nil
        H.equal(#Fresh.declared_specs(), 2, "accessor must return a copy")
        first.readiness.ready = false
        local again_ok, again_reason = Fresh.register(first.spec, first.runtime)
        H.equal(again_ok, true)
        H.equal(again_reason, "revalidated")
        H.equal(#Fresh.declared_specs(), 2, "re-registration must not duplicate a declaration")
        local clash = fixture("et_declared_first")
        local clash_ok, clash_reason = Fresh.register(clash.spec, clash.runtime)
        H.equal(clash_ok, nil)
        H.equal(clash_reason, "duplicate_declaration")
        H.equal(#Fresh.declared_specs(), 2)
        local all_ok, all_reason = Fresh.validate_all_registered(first.runtime)
        H.equal(all_ok, nil)
        H.equal(all_reason, "et_declared_second:breed_unpublished")
    end)

    H.test("ET #451 actual owners seed DLC rows, prove health, and satisfy the registrar contract check", function()
        local capture = capture_actual_owner_specs()
        local warlord_spec, chosen_spec = capture.specs[1], capture.specs[2]
        local ActualRegistrar = assert(loadfile(registrar_path))()
        ActualRegistrar.lookup_lib = Lookup
        local fx = actual_consumer_runtime(capture)
        local runtime = fx.runtime
        capture.validate_all = function()
            return ActualRegistrar.validate_all_registered(runtime)
        end
        capture.validate_one = function(spec)
            return ActualRegistrar.validate_registered(spec, runtime)
        end
        local check = assert(capture.runtime_checks.issue451_custom_breed_registrar)
        local function run_check()
            return with_raw_bindings({
                { target = _G, key = "Breeds", value = runtime.breeds },
            }, check)
        end

        local before = run_check()
        H.equal(type(before), "string")
        H.truthy(before:find("et_skaven_warlord: breed_unpublished", 1, true) ~= nil, before)

        H.equal(ActualRegistrar.register(warlord_spec, runtime), true)
        H.equal(ActualRegistrar.register(chosen_spec, runtime), true)
        local weapons = runtime.statistics.player.weapon_kills_per_breed
        H.equal(weapons.dr_2h_cog_hammer[warlord_spec.name].database_name,
            "dr_2h_cog_hammer_et_skaven_warlord")
        H.equal(weapons.dr_2h_cog_hammer[chosen_spec.name].database_name,
            "dr_2h_cog_hammer_et_chosen_greataxe")
        H.equal(weapons.markus_questingknight_career_skill_weapon[warlord_spec.name]
            .database_name, "et_skaven_warlord")
        H.equal(weapons.markus_questingknight_career_skill_weapon[chosen_spec.name]
            .database_name, "et_chosen_greataxe")
        H.equal(weapons.dr_2h_cog_hammer[chosen_spec.name].name, "et_chosen_greataxe")
        H.equal(weapons.dr_2h_cog_hammer[chosen_spec.name].source, "player_data")
        H.equal(weapons.dr_2h_cog_hammer[chosen_spec.name].value, 0)
        H.equal(weapons.dr_2h_cog_hammer[chosen_spec.source_breed].database_name,
            "dr_2h_cog_hammer_chaos_warrior")
        local chosen = runtime.breeds[chosen_spec.name]
        H.equal(#chosen.max_health, 9)
        for i = 1, 9 do H.equal(chosen.max_health[i], 2000) end
        H.equal(#fx.chosen_source.max_health, 8)
        H.equal(fx.chosen_source.max_health[8], 125)
        H.equal(run_check(), nil)

        -- Readiness published while the contract is broken is the failure
        -- class this check exists for.
        local removed = weapons.markus_questingknight_career_skill_weapon[chosen_spec.name]
        weapons.markus_questingknight_career_skill_weapon[chosen_spec.name] = nil
        local broken = run_check()
        H.equal(type(broken), "string")
        H.truthy(broken:find(
            "et_chosen_greataxe readiness _et_chosen_ready published without a validated contract",
            1, true) ~= nil, broken)
        H.truthy(broken:find(
            "statistics_weapon_kills_per_breed_mismatch:markus_questingknight_career_skill_weapon",
            1, true) ~= nil, broken)
        H.equal(capture.mod._et_chosen_ready, true, "the check must never repair readiness")
        weapons.markus_questingknight_career_skill_weapon[chosen_spec.name] = removed
        H.equal(run_check(), nil)

        capture.mod._et_chosen_ready = false
        local unready = run_check()
        H.truthy(unready:find(
            "et_chosen_greataxe: registered_state_incomplete:readiness_1", 1, true) ~= nil,
            unready)
        H.equal(capture.mod._et_chosen_ready, false)
        capture.mod._et_chosen_ready = true
        H.equal(run_check(), nil)

        rawset(fx.warlord_source, ActualRegistrar.marker_key, {})
        local marked = run_check()
        H.truthy(marked:find(
            "vanilla donor skaven_storm_vermin_champion carries registrar state", 1, true)
            ~= nil, marked)
        rawset(fx.warlord_source, ActualRegistrar.marker_key, nil)
        H.equal(run_check(), nil)

        capture.specs[3] = { name = "et_third" }
        local extra = run_check()
        H.truthy(extra:find("expected 2 declared custom breeds, got 3", 1, true) ~= nil, extra)
        capture.specs[3] = nil
        capture.specs[1], capture.specs[2] = capture.specs[2], capture.specs[1]
        local order = run_check()
        H.truthy(order:find(
            "declaration 1 drifted: expected et_skaven_warlord, got et_chosen_greataxe",
            1, true) ~= nil, order)
        capture.specs[1], capture.specs[2] = capture.specs[2], capture.specs[1]
        H.equal(run_check(), nil)
        H.equal(capture.runtime_checks.issue1413_atomic_custom_breed_registration(), nil)
        H.equal(capture.runtime_checks.issue451_chosen_greataxe_prototype ~= nil, true)
    end)
end
