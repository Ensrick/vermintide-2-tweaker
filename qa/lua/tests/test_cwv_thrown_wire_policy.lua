-- Issue #423/#424 exact-catalog conversion for CWV.
--
-- Every check here is behavioural where it can be: the gate's hooks are
-- captured from a fake `mod` and invoked, so a planted regression fails on what
-- the code DOES, not on whether a string still appears in it.
return function(H, repo_root)
    local module_root = repo_root
        .. "/character_weapon_variants/scripts/mods/character_weapon_variants/"
    local function load_module(name) return dofile(module_root .. name) end
    local function read(path)
        local file = assert(io.open(path, "rb"))
        local source = file:read("*a")
        file:close()
        return source
    end

    local policy = load_module("_cwv_thrown_wire_policy.lua")
    local catalog = load_module("_lib_wire_catalog.lua")

    local SPEC = {
        projectile_key       = "cwv_tuskgor_javelin",
        safe_projectile_key  = "javelin",
        inflight_unit        = "units/wpn_emp_boar_spear_01_3p",
        safe_projectile_unit = "units/prj_we_javelin_01_3ps",
        carrier_unit         = "units/pup_dw_thrown_axe_01_t1",
        pickup_key           = "cwv_tuskgor_javelin_pickup",
        link_pickup_key      = "cwv_tuskgor_javelin_link_pickup",
        safe_pickup_key      = "ammo_throwing_axe_01_t1",
        safe_link_pickup_key = "link_ammo_throwing_axe_01_t1",
        pickup_fallbacks = {
            cwv_tuskgor_javelin_pickup      = "ammo_throwing_axe_01_t1",
            cwv_tuskgor_javelin_link_pickup = "link_ammo_throwing_axe_01_t1",
        },
    }

    -- A minimal but COMPLETE stand-in for every table the native pickup and
    -- projectile senders dereference. Built fresh per test so one planted
    -- breakage cannot leak into the next.
    local function build_globals()
        local pickup_names, husks, go_types, projectile_units = {}, {}, {}, {}
        local function row(t, name)
            local id = #t + 1
            t[id] = name
            t[name] = id
        end
        row(pickup_names, "ammo_throwing_axe_01_t1")
        row(pickup_names, "link_ammo_throwing_axe_01_t1")
        row(pickup_names, SPEC.pickup_key)
        row(pickup_names, SPEC.link_pickup_key)
        row(husks, SPEC.safe_projectile_unit)
        row(husks, SPEC.inflight_unit)
        row(husks, SPEC.carrier_unit)
        row(husks, "units/pup_throwing_axe")
        row(go_types, "limited_owned_pickup_unit")
        row(projectile_units, SPEC.safe_projectile_key)
        row(projectile_units, SPEC.projectile_key)

        local ammo = {}
        for _, key in ipairs({ SPEC.pickup_key, SPEC.link_pickup_key }) do
            ammo[key] = {
                unit_name = SPEC.carrier_unit,
                unit_template_name = "limited_owned_pickup_unit",
                pickup_name = key,
            }
        end
        local all_pickups = { [SPEC.pickup_key] = ammo[SPEC.pickup_key],
            [SPEC.link_pickup_key] = ammo[SPEC.link_pickup_key] }
        for _, key in ipairs({ "ammo_throwing_axe_01_t1", "link_ammo_throwing_axe_01_t1" }) do
            all_pickups[key] = {
                unit_name = "units/pup_throwing_axe",
                unit_template_name = "limited_owned_pickup_unit",
                pickup_name = key,
            }
        end
        local units = {
            [SPEC.safe_projectile_key] = { projectile_unit_name = SPEC.safe_projectile_unit },
            [SPEC.projectile_key] = { projectile_unit_name = SPEC.inflight_unit },
        }
        return {
            NetworkLookup = {
                pickup_names = pickup_names, husks = husks,
                go_types = go_types, projectile_units = projectile_units,
            },
            ProjectileUnits = units,
            -- Vanilla builds this inverse for every ProjectileUnits entry at
            -- boot (projectile_units.lua:59-63); the cwv row is the one the
            -- exact runtime appends afterwards.
            ProjectileUnitsFromUnitName = {
                [SPEC.safe_projectile_unit] = SPEC.safe_projectile_key,
                [SPEC.inflight_unit] = SPEC.projectile_key,
            },
            Pickups = { ammo = ammo },
            AllPickups = all_pickups,
        }
    end

    -- ---------------------------------------------------------------------
    -- Deliverable 2: three-valued disposition, never nil-ambiguous
    -- ---------------------------------------------------------------------
    H.test("CWV thrown disposition is three-valued and never returns a nil verdict", function()
        local globals = build_globals()
        local names = {
            SPEC.pickup_key, SPEC.link_pickup_key, "cwv_tuskgor_javelin_bomb",
            "ammo_throwing_axe_01_t1", "", "cwv_未_declared",
        }
        local allowed = {
            [policy.RIDE_CUSTOM] = true, [policy.SUBSTITUTE] = true, [policy.DROP] = true,
        }
        for _, exact in ipairs({ true, false }) do
            for i = 1, #names do
                local disposition = policy.pickup_disposition(names[i], exact, SPEC, globals)
                H.truthy(allowed[disposition],
                    "non-verdict for " .. tostring(names[i]) .. ": " .. tostring(disposition))
            end
        end
        -- A nil name is a verdict too, not a crash and not a pass-through.
        H.equal(policy.pickup_disposition(nil, false, SPEC, globals), policy.DROP)
    end)

    -- This is the exact live defect the conversion closes: the predecessor
    -- helper returned nil for BOTH "parity confirmed" and "no donor declared",
    -- and cwv_tuskgor_javelin_bomb was never in the donor map -- so the
    -- ambiguity resolved to sending the custom appended index.
    H.test("CWV undeclared cwv pickup fails closed to DROP, never to the custom id", function()
        local globals = build_globals()
        local disposition, name = policy.pickup_disposition(
            "cwv_tuskgor_javelin_bomb", false, SPEC, globals)
        H.equal(disposition, policy.DROP)
        H.equal(name, nil)
        -- Ownership is what makes it fail closed: the cwv_ prefix alone is
        -- enough, no donor-map membership required.
        H.equal(policy.is_owned_pickup("cwv_tuskgor_javelin_bomb", SPEC), true)
        H.equal(policy.is_owned_pickup("ammo_throwing_axe_01_t1", SPEC), false)
    end)

    H.test("CWV declared pickups substitute unproven and ride proven", function()
        local globals = build_globals()
        local sub, donor = policy.pickup_disposition(SPEC.pickup_key, false, SPEC, globals)
        H.equal(sub, policy.SUBSTITUTE)
        H.equal(donor, "ammo_throwing_axe_01_t1")
        local ride, kept = policy.pickup_disposition(SPEC.pickup_key, true, SPEC, globals)
        H.equal(ride, policy.RIDE_CUSTOM)
        H.equal(kept, SPEC.pickup_key)
        -- A name cwv does not own always rides unchanged, in both states.
        local pass, pass_name = policy.pickup_disposition(
            "ammo_throwing_axe_01_t1", false, SPEC, globals)
        H.equal(pass, policy.RIDE_CUSTOM)
        H.equal(pass_name, "ammo_throwing_axe_01_t1")
    end)

    -- ---------------------------------------------------------------------
    -- Deliverable 2: donor revalidation (planted broken donor -> DROP)
    -- ---------------------------------------------------------------------
    H.test("CWV pickup donor must prove every table the native sender dereferences", function()
        local breakages = {
            ["reverse pickup_names row"] = function(g)
                g.NetworkLookup.pickup_names[g.NetworkLookup.pickup_names.ammo_throwing_axe_01_t1] = nil
            end,
            ["forward pickup_names row"] = function(g)
                g.NetworkLookup.pickup_names.ammo_throwing_axe_01_t1 = nil
            end,
            ["AllPickups settings row"] = function(g)
                g.AllPickups.ammo_throwing_axe_01_t1 = nil
            end,
            ["husk row for the donor unit"] = function(g)
                g.NetworkLookup.husks["units/pup_throwing_axe"] = nil
            end,
            ["go_type row for the donor template"] = function(g)
                g.NetworkLookup.go_types.limited_owned_pickup_unit = nil
            end,
        }
        for label, break_it in pairs(breakages) do
            local globals = build_globals()
            H.equal(policy.pickup_donor_intact(globals, "ammo_throwing_axe_01_t1"), true,
                "baseline donor should be intact before planting " .. label)
            break_it(globals)
            H.equal(policy.pickup_donor_intact(globals, "ammo_throwing_axe_01_t1"), false,
                "broken " .. label .. " still read as an intact donor")
            local disposition = policy.pickup_disposition(SPEC.pickup_key, false, SPEC, globals)
            H.equal(disposition, policy.DROP,
                "broken " .. label .. " did not degrade the pickup to DROP")
        end
    end)

    H.test("CWV projectile donor proof covers both lookup axes and the loader inverse", function()
        local globals = build_globals()
        H.equal(policy.projectile_donor_intact(globals, SPEC.safe_projectile_key), true)
        local breakages = {
            ["projectile_units row"] = function(g) g.NetworkLookup.projectile_units.javelin = nil end,
            ["donor husk row"] = function(g)
                g.NetworkLookup.husks[SPEC.safe_projectile_unit] = nil
            end,
            ["ProjectileUnits template"] = function(g) g.ProjectileUnits.javelin = nil end,
            ["unit->template inverse"] = function(g) g.ProjectileUnitsFromUnitName = {} end,
        }
        for label, break_it in pairs(breakages) do
            local g = build_globals()
            break_it(g)
            H.equal(policy.projectile_donor_intact(g, SPEC.safe_projectile_key), false,
                "broken " .. label .. " still read as an intact projectile donor")
            -- The in-flight floor is UNCONDITIONAL: it never returns the custom
            -- table, so an unprovable donor is a DROP, not a pass-through.
            local disposition, resolved = policy.projectile_disposition(
                { projectile_unit_name = SPEC.inflight_unit }, SPEC, g)
            H.equal(disposition, policy.DROP, "broken " .. label .. " let the custom husk survive")
            H.equal(resolved, nil)
        end
    end)

    H.test("CWV in-flight floor substitutes unconditionally and passes vanilla through", function()
        local globals = build_globals()
        local disposition, resolved = policy.projectile_disposition(
            { projectile_unit_name = SPEC.inflight_unit }, SPEC, globals)
        H.equal(disposition, policy.SUBSTITUTE)
        H.equal(resolved.projectile_unit_name, SPEC.safe_projectile_unit)
        local vanilla = { projectile_unit_name = "units/prj_something_else" }
        local pass, kept = policy.projectile_disposition(vanilla, SPEC, globals)
        H.equal(pass, policy.RIDE_CUSTOM)
        H.equal(kept, vanilla)
    end)

    -- ---------------------------------------------------------------------
    -- Deliverable 1: exact catalog capture + drift detection
    -- ---------------------------------------------------------------------
    H.test("CWV thrown catalog captures the five appended rows and detects drift", function()
        local globals = build_globals()
        local snapshot, err = policy.capture(catalog, globals, SPEC)
        H.truthy(snapshot, "capture failed: " .. tostring(err))
        H.equal(#snapshot.rows, 5)
        H.truthy(snapshot.identity:find("cwv%-thrown%-v1:"))
        H.equal(policy.integrity(snapshot), true)

        -- A second lookup-appending mod renumbering our pickup row is exactly
        -- the shape presence parity cannot see.
        local drifted = build_globals()
        local drifted_snapshot = assert(policy.capture(catalog, drifted, SPEC))
        local names = drifted.NetworkLookup.pickup_names
        local id = names[SPEC.pickup_key]
        names[id], names[SPEC.pickup_key] = nil, 99
        names[99] = SPEC.pickup_key
        local intact, reason = policy.integrity(drifted_snapshot)
        H.equal(intact, false)
        H.truthy(tostring(reason):find("lookup%-drift"))
    end)

    H.test("CWV thrown catalog refuses capture when the loader inverse is missing", function()
        local globals = build_globals()
        globals.ProjectileUnitsFromUnitName = {}
        local snapshot, err = policy.capture(catalog, globals, SPEC)
        H.equal(snapshot, nil)
        H.truthy(tostring(err):find("projectile%-inverse%-mismatch"))
    end)

    H.test("CWV exact_safe requires install, committed state and an undrifted catalog", function()
        local globals = build_globals()
        local snapshot = assert(policy.capture(catalog, globals, SPEC))
        local function parity(installed, state)
            return {
                is_installed = function() return installed end,
                applied_state = function() return state end,
            }
        end
        H.equal(policy.exact_safe(parity(true, "enabled"), snapshot), true)
        H.equal(policy.exact_safe(parity(false, "enabled"), snapshot), false)
        H.equal(policy.exact_safe(parity(true, "disabled"), snapshot), false)
        H.equal(policy.exact_safe(nil, snapshot), false)
        H.equal(policy.exact_safe(parity(true, "enabled"), nil), false)
        -- An erroring accessor must read false, never propagate.
        H.equal(policy.exact_safe({
            is_installed = function() error("boom") end,
            applied_state = function() return "enabled" end,
        }, snapshot), false)
        H.equal(policy.feature_disposition(true), policy.RIDE_CUSTOM)
        H.equal(policy.feature_disposition(false), policy.BLOCK)
    end)

    -- ---------------------------------------------------------------------
    -- Deliverables 3 + 4 + 5: the gate's live hook bodies
    -- ---------------------------------------------------------------------
    -- Capture the hooks the gate installs against a fake mod, then drive them.
    local function install_gate(opts)
        opts = opts or {}
        local hooks, safe_hooks, echoes = {}, {}, {}
        local om = {}
        local mod = {
            hook = function(_, class, method, fn) hooks[class .. "." .. method] = fn end,
            hook_safe = function(_, class, method, fn) safe_hooks[class .. "." .. method] = fn end,
            echo = function(_, text) echoes[#echoes + 1] = text end,
        }
        mod._cwv_peer_parity = opts.parity or {
            applied_state = function() return opts.applied or "enabled" end,
            is_installed = function() return true end,
            peer_has = function() return opts.peer_has ~= false end,
            require_peer = function() end,
            forget_peer = function() end,
            register_gated_feature = function() end,
        }
        mod._cwv_thrown_peer_parity = mod._cwv_peer_parity
        local gate = load_module("_cwv_javelin_gate.lua")
        gate.install({
            mod = mod, om = om,
            pickup_key = SPEC.pickup_key,
            link_pickup_key = SPEC.link_pickup_key,
            projectile_key = SPEC.projectile_key,
            inflight_unit = SPEC.inflight_unit,
            safe_template_key = SPEC.safe_projectile_key,
            wire_safe = function() return opts.wire_safe ~= false end,
            catalog_intact = function() return opts.catalog_intact ~= false end,
            donor_policy = policy,
            globals = opts.globals or build_globals(),
        })
        return { gate = gate, mod = mod, om = om, hooks = hooks,
            safe_hooks = safe_hooks, echoes = echoes }
    end

    -- Engine globals the gate reads directly. Saved and restored so the shared
    -- harness process is not polluted for the suites that run after this one.
    local function with_engine_globals(overrides, body)
        local names = { "Unit", "ScriptUnit", "Managers", "printf", "WeaponUtils",
            "ProjectileUnits", "NetworkLookup" }
        local saved = {}
        for i = 1, #names do saved[names[i]] = rawget(_G, names[i]) end
        rawset(_G, "Unit", { alive = function(u) return u ~= nil and u ~= false end })
        rawset(_G, "ScriptUnit", { has_extension = function() return nil end })
        rawset(_G, "printf", function() end)
        rawset(_G, "Managers", {})
        rawset(_G, "WeaponUtils", { get_weapon_template = function() return nil end })
        for key, value in pairs(overrides or {}) do rawset(_G, key, value) end
        local ok, err = pcall(body)
        for i = 1, #names do rawset(_G, names[i], saved[names[i]]) end
        if not ok then error(err, 0) end
    end

    H.test("CWV throw block matches the action's own item_name, not just the wielded slot", function()
        with_engine_globals({}, function()
            -- The wielded slot is deliberately unreadable (no inventory
            -- extension), which is the frame shape a grenade-slot throw has.
            local ctx = install_gate({ wire_safe = false })
            local fire = assert(ctx.hooks["ActionThrownProjectile._fire"])
            local called = false
            local action = { item_name = "cwv_grenade_tuskgor_javelin", owner_unit = nil }
            fire(function() called = true end, action)
            H.equal(called, false, "a cwv javelin action threw while the gate was closed")
            H.equal(action._cwv424_throw_blocked, true)

            -- ...and the ammo is preserved rather than silently consumed.
            local use_ammo = assert(ctx.hooks["ActionThrownProjectile._use_ammo"])
            local ammo_spent = false
            use_ammo(function() ammo_spent = true end, action)
            H.equal(ammo_spent, false)

            -- A native javelin action is untouched by the gate.
            local native, native_fired = { item_name = "we_javelin" }, false
            fire(function() native_fired = true end, native)
            H.equal(native_fired, true)
        end)
    end)

    H.test("CWV throw gate closes when the exact catalog is unproven even with presence parity", function()
        with_engine_globals({}, function()
            local open = install_gate({ applied = "enabled", wire_safe = true })
            local fired = false
            open.hooks["ActionThrownProjectile._fire"](
                function() fired = true end, { item_name = "cwv_es_javelin" })
            H.equal(fired, true, "a fully proven lobby must still be able to throw")

            -- Same presence verdict, unproven catalog -> blocked.
            local closed = install_gate({ applied = "enabled", wire_safe = false })
            local closed_fired = false
            closed.hooks["ActionThrownProjectile._fire"](
                function() closed_fired = true end, { item_name = "cwv_es_javelin" })
            H.equal(closed_fired, false,
                "presence parity alone opened the gate (BUG_CLASSES 64: same mod, different integers)")

            -- A missing wire_safe function must fail closed, never open.
            local absent = install_gate({ wire_safe = false })
            absent.hooks["ActionThrownProjectile._fire"](
                function() closed_fired = true end, { item_name = "cwv_es_javelin" })
            H.equal(closed_fired, false)
        end)
    end)

    -- Deliverable 3: vanilla dereferences .projectile_unit_name on the line
    -- after _get_projectile_units_names returns (projectile_system.lua:247-249),
    -- so a DROP from the in-flight floor is only survivable if the spawn is
    -- refused first.
    H.test("CWV ProjectileSystem preflight blocks a malformed projectile resolution", function()
        with_engine_globals({
            WeaponUtils = { get_weapon_template = function()
                return { actions = { throw = { default = { projectile_info = {} } } } }
            end },
        }, function()
            local ctx = install_gate({})
            local preflight = assert(ctx.hooks["ProjectileSystem.spawn_player_projectile"],
                "no preflight registered on ProjectileSystem.spawn_player_projectile")

            local resolved_nil = {
                _get_projectile_units_names = function() return nil end,
            }
            local spawned = false
            preflight(function() spawned = true end, resolved_nil, nil, nil, nil, 0, 0,
                nil, 0, "cwv_es_javelin", "cwv_tuskgor_javelin_template", "throw", "default")
            H.equal(spawned, false, "spawn proceeded into an unconditional nil dereference")

            -- A table without the field is equally fatal to vanilla.
            local resolved_fieldless = {
                _get_projectile_units_names = function() return {} end,
            }
            spawned = false
            preflight(function() spawned = true end, resolved_fieldless, nil, nil, nil, 0, 0,
                nil, 0, "cwv_es_javelin", "cwv_tuskgor_javelin_template", "throw", "default")
            H.equal(spawned, false)

            -- A well-formed resolution spawns, and a non-cwv item is never probed.
            local resolved_ok = {
                _get_projectile_units_names = function()
                    return { projectile_unit_name = SPEC.safe_projectile_unit }
                end,
            }
            spawned = false
            preflight(function() spawned = true end, resolved_ok, nil, nil, nil, 0, 0,
                nil, 0, "cwv_es_javelin", "cwv_tuskgor_javelin_template", "throw", "default")
            H.equal(spawned, true)
            spawned = false
            preflight(function() spawned = true end, resolved_nil, nil, nil, nil, 0, 0,
                nil, 0, "we_javelin", "javelin_template", "throw", "default")
            H.equal(spawned, true, "the preflight probed a weapon cwv does not own")
        end)
    end)

    -- Deliverable 4: the sweep must cover in-flight projectiles as well as world
    -- pickups, and a deletion that did not take must NOT report success -- the
    -- joiner is held out instead.
    local function build_world(opts)
        local live_pickups = opts.pickups or {}
        local tracked = opts.tracked or {}
        local deleted = {}
        local spawner = {
            is_marked_for_deletion = function(_, unit) return deleted[unit] == true end,
            mark_for_deletion = function(_, unit) deleted[unit] = true end,
            commit_and_remove_pending_units = function()
                if opts.commit_fails then return end
                for unit in pairs(deleted) do
                    for name, units in pairs(live_pickups) do
                        for i = #units, 1, -1 do
                            if units[i] == unit then table.remove(units, i) end
                        end
                        live_pickups[name] = units
                    end
                    tracked[unit] = nil
                end
            end,
        }
        return {
            Managers = {
                state = {
                    unit_spawner = spawner,
                    entity = { system = function() return {
                        is_server = true,
                        get_pickups_by_type = function(_, name) return live_pickups[name] or {} end,
                    } end },
                },
                level_transition_handler = {
                    transient_package_loader = { _tracked_projectiles = { units = tracked } },
                },
            },
            tracked = tracked,
            live_pickups = live_pickups,
            deleted = deleted,
        }
    end

    H.test("CWV join-fence sweep removes in-flight projectiles as well as world pickups", function()
        local world = build_world({
            pickups = { [SPEC.pickup_key] = { "pickup_a" }, [SPEC.link_pickup_key] = { "pickup_b" } },
            tracked = { projectile_a = SPEC.projectile_key, foreign = "javelin" },
        })
        with_engine_globals({ Managers = world.Managers }, function()
            local ctx = install_gate({})
            local sweep = assert(ctx.om._cwv424_remove_live_recovery_pickups)
            local ok, removed, counts = sweep()
            H.equal(ok, true)
            H.equal(removed, 3)
            H.equal(counts.projectiles, 1)
            H.equal(counts.pickups, 2)
            H.equal(world.deleted.projectile_a, true)
            H.equal(world.deleted.foreign, nil, "the sweep deleted a projectile cwv does not own")
        end)
    end)

    H.test("CWV join-fence sweep reports failure when a deletion did not take", function()
        local world = build_world({
            pickups = { [SPEC.pickup_key] = { "stuck_pickup" } },
            tracked = {},
            commit_fails = true,
        })
        with_engine_globals({ Managers = world.Managers }, function()
            local ctx = install_gate({})
            local ok, detail = ctx.om._cwv424_remove_live_recovery_pickups()
            H.equal(ok, false,
                "a retained world pickup was reported as a successful sweep (the joiner would be let in)")
            H.truthy(tostring(detail):find("retained after cleanup", 1, true))
        end)
    end)

    H.test("CWV join-fence sweep reports failure when an in-flight projectile survives", function()
        local world = build_world({
            pickups = {},
            tracked = { stuck_projectile = SPEC.projectile_key },
            commit_fails = true,
        })
        with_engine_globals({ Managers = world.Managers }, function()
            local ctx = install_gate({})
            local ok, detail = ctx.om._cwv424_remove_live_recovery_pickups()
            H.equal(ok, false,
                "a retained custom projectile was reported as a successful sweep")
            H.truthy(tostring(detail):find("custom projectile retained", 1, true))
        end)
    end)

    H.test("CWV hot-join sync holds the peer and never runs native sync on a failed sweep", function()
        local world = build_world({
            pickups = { [SPEC.pickup_key] = { "stuck_pickup" } },
            tracked = {},
            commit_fails = true,
        })
        with_engine_globals({ Managers = world.Managers }, function()
            local ctx = install_gate({ peer_has = false })
            local sync = assert(ctx.hooks["GameNetworkManager.set_peer_synchronizing"])
            local native_ran, kicked = false, nil
            sync(function() native_ran = true end,
                { network_server = { kick_peer = function(_, peer) kicked = peer end } },
                "peer-1")
            H.equal(native_ran, false, "native set_peer_synchronizing ran after a failed cleanup")
            H.equal(kicked, "peer-1")
            local synced = assert(ctx.hooks["NetworkServer.is_network_state_fully_synced_for_peer"])
            H.equal(synced(function() return true end, {}, "peer-1"), false)
        end)
    end)

    -- A disconnect must retire the peer's proof on EVERY channel. The parity
    -- library expires an ack on its own only after a bounded ABSENCE window
    -- (_lib_peer_parity.lua:576-583), and a fast rejoin under the same peer id
    -- lands inside it -- so an unretired exact channel would still read the
    -- departed peer as having proven our catalog.
    local function ack_tracking_parity(acks)
        return {
            is_installed = function() return true end,
            applied_state = function() return "enabled" end,
            peer_has = function(_, peer_id) return acks[peer_id] == true end,
            forget_peer = function(_, peer_id) acks[peer_id] = nil end,
            require_peer = function() end,
            register_gated_feature = function() end,
        }
    end

    H.test("CWV disconnect retires the exact proof on both new channels", function()
        with_engine_globals({}, function()
            local presence_acks = { ["peer-1"] = true }
            local thrown_acks   = { ["peer-1"] = true }
            local damage_acks   = { ["peer-1"] = true }
            local ctx = install_gate({ parity = ack_tracking_parity(presence_acks) })
            ctx.mod._cwv_thrown_peer_parity = ack_tracking_parity(thrown_acks)
            ctx.mod._cwv_damage_peer_parity = ack_tracking_parity(damage_acks)
            H.equal(ctx.om._cwv424_exact_epoch_retirement_installed, true)

            local teardown = assert(ctx.safe_hooks["GameNetworkManager.remove_peer"],
                "no consolidated hook_safe on (GameNetworkManager, remove_peer)")
            teardown({}, "peer-1")

            H.equal(ctx.mod._cwv_peer_parity:peer_has("peer-1"), false,
                "presence beacon kept a departed peer's ack")
            H.equal(ctx.mod._cwv_thrown_peer_parity:peer_has("peer-1"), false,
                "thrown exact channel kept a departed peer's ack -- a same-id rejoin reuses stale exact proof")
            H.equal(ctx.mod._cwv_damage_peer_parity:peer_has("peer-1"), false,
                "damage exact channel kept a departed peer's ack -- a same-id rejoin reuses stale exact proof")

            -- Untouched peers keep their proof: retirement is per-peer, not a wipe.
            local other_presence = { ["peer-1"] = true, ["peer-2"] = true }
            local other_thrown   = { ["peer-1"] = true, ["peer-2"] = true }
            local scoped = install_gate({ parity = ack_tracking_parity(other_presence) })
            scoped.mod._cwv_thrown_peer_parity = ack_tracking_parity(other_thrown)
            scoped.safe_hooks["GameNetworkManager.remove_peer"]({}, "peer-1")
            H.equal(scoped.mod._cwv_thrown_peer_parity:peer_has("peer-2"), true)
        end)
    end)

    H.test("CWV disconnect forgets each parity instance once even when they alias", function()
        with_engine_globals({}, function()
            -- A build where two handles resolve to the same table must not
            -- double-forget, and a nil handle must not abort the teardown.
            local calls = {}
            local shared = {
                forget_peer = function(_, peer_id) calls[#calls + 1] = peer_id end,
                register_gated_feature = function() end,
                applied_state = function() return "enabled" end,
                is_installed = function() return true end,
                peer_has = function() return true end,
                require_peer = function() end,
            }
            local ctx = install_gate({ parity = shared })
            ctx.mod._cwv_thrown_peer_parity = shared
            ctx.mod._cwv_damage_peer_parity = nil
            ctx.safe_hooks["GameNetworkManager.remove_peer"]({}, "peer-1")
            H.equal(#calls, 1)
            H.equal(calls[1], "peer-1")
        end)
    end)

    H.test("CWV rejoin after disconnect is treated as unproven at the join fence", function()
        local world = build_world({
            pickups = { [SPEC.pickup_key] = { "live_pickup" } },
            tracked = {},
        })
        with_engine_globals({ Managers = world.Managers }, function()
            local presence_acks = { ["peer-1"] = true }
            local thrown_acks   = { ["peer-1"] = true }
            local ctx = install_gate({ parity = ack_tracking_parity(presence_acks) })
            ctx.mod._cwv_thrown_peer_parity = ack_tracking_parity(thrown_acks)
            local sync = assert(ctx.hooks["GameNetworkManager.set_peer_synchronizing"])

            -- Proven peer: the fence leaves the live cwv pickup alone.
            sync(function() end, {}, "peer-1")
            H.equal(#world.live_pickups[SPEC.pickup_key], 1,
                "a proven peer should not trigger the world sweep")

            -- Same peer id disconnects and immediately rejoins.
            ctx.safe_hooks["GameNetworkManager.remove_peer"]({}, "peer-1")
            sync(function() end, {}, "peer-1")
            H.equal(#world.live_pickups[SPEC.pickup_key], 0,
                "a rejoining peer reused its pre-disconnect proof and skipped the sweep")
        end)
    end)

    -- ---------------------------------------------------------------------
    -- Deliverable 1: the exact identity actually reaches a parity instance
    -- ---------------------------------------------------------------------
    H.test("CWV exact runtime opts both channels into shared exact mode", function()
        local runtime = read(module_root .. "_cwv_exact_wire_runtime.lua")
        -- new_exact_parity is the single construction site; it must pass
        -- wire_identity (the opt-in that flips EXACT_MODE at
        -- _lib_peer_parity.lua:105) and refuse to build without one.
        H.truthy(runtime:find("wire_identity = identity", 1, true))
        H.truthy(runtime:find('return nil, "identity-missing"', 1, true))
        H.truthy(runtime:find('"cwv_damage_profiles_exact_v1"', 1, true))
        H.truthy(runtime:find('"cwv_thrown_resources_exact_v1"', 1, true))
        -- Both snapshots feed their own identity, never a shared constant.
        H.truthy(runtime:find("snapshot.identity", 1, true))
        -- The presence beacon stays presence-only: upgrading it in place would
        -- silently redefine a protocol deployed CWV builds already speak.
        local entry = read(module_root .. "character_weapon_variants.lua")
        H.equal(entry:find("[^_%w]wire_identity%s*="), nil)
        H.truthy(entry:find('channel        = "cwv_peer_parity_present"', 1, true))
    end)

    H.test("CWV damage send gate lives in its owner module with one hook and two markers", function()
        local runtime = read(module_root .. "_cwv_exact_wire_runtime.lua")
        local entry = read(module_root .. "character_weapon_variants.lua")
        -- Exactly one registration on the (Class, method) pair, in the owner.
        local _, entry_hooks = entry:gsub('mod:hook%("WeaponSystem"', "")
        H.equal(entry_hooks, 0, "the entry file still registers a WeaponSystem hook")
        local _, runtime_hooks = runtime:gsub('mod:hook%("WeaponSystem"', "")
        H.equal(runtime_hooks, 1)
        -- The [cwv:423] marker stays reserved for the two send outcomes.
        local send = assert(runtime:find('mod:hook("WeaponSystem", "send_rpc_attack_hit"', 1, true))
        local _, send_markers = runtime:sub(send):gsub("%[cwv:423%]", "")
        H.equal(send_markers, 2)
        H.truthy(runtime:find("[cwv:423] wire dmg-profile sub:", 1, true))
        H.truthy(runtime:find("[cwv:423] blocked unsafe hit:", 1, true))
        -- Cosmetic skin nulling is a separate axis and must not borrow it.
        H.truthy(entry:find("[cwv:skin-wire] wire skin null", 1, true))
        H.equal(entry:find("[cwv:423] wire skin null", 1, true), nil)
    end)

    H.test("CWV wire-catalog copy is byte-identical to the shared-lib master", function()
        H.equal(read(module_root .. "_lib_wire_catalog.lua"),
            read(repo_root .. "/tools/shared_lib/_lib_wire_catalog.lua"))
        local manifest = read(repo_root .. "/tools/shared_lib/manifest.psd1")
        H.truthy(manifest:find(
            "character_weapon_variants/scripts/mods/character_weapon_variants/_lib_wire_catalog.lua",
            1, true), "cwv is not registered as a _lib_wire_catalog consumer")
    end)
end
