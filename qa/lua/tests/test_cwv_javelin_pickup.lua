return function(H, repo_root)
    local gate = dofile(repo_root
        .. "/character_weapon_variants/scripts/mods/character_weapon_variants/_cwv_javelin_gate.lua")

    -- The nil-ambiguous `_cwv_javelin_pickup.wire_fallback` helper this suite
    -- used to exercise was removed by the #423/#424 exact-catalog conversion:
    -- it returned nil for BOTH "keep the custom id" and "no donor declared".
    -- Its successor is the three-valued _cwv_thrown_wire_policy, covered in
    -- qa/lua/tests/test_cwv_thrown_wire_policy.lua. What remains here is the
    -- identity/ref-shadow/fence surface the gate still owns.
    H.test("CWV source routes recovered javelin pickups through the three-valued policy", function()
        local source = require("cwv_source").combined(repo_root)
        H.truthy(source:find("_om._tj_pickup_disposition(pickup_name)", 1, true))
        H.truthy(source:find("thrown_wire_policy.pickup_disposition", 1, true))
        -- The superseded helper must be gone from every cwv module, not merely
        -- unused: a surviving nil-ambiguous entry point is a live wire hazard.
        -- (`_cwv_wire_fallback_profile_id` is the unrelated #423 donor id and
        -- deliberately survives, so match the call shape, not the substring.)
        H.equal(source:find(".wire_fallback(", 1, true), nil)
        H.equal(source:find("_wire_safe_pickup_name", 1, true), nil)
        -- The module itself is gone, so nothing may still dofile it (the policy
        -- module names it in a provenance comment, which is why this asserts on
        -- the load path rather than the bare symbol).
        H.equal(source:find('mod:dofile("scripts/mods/character_weapon_variants/_cwv_javelin_pickup")',
            1, true), nil)
    end)

    H.test("CWV javelin gate recognizes only concrete thrown variants", function()
        H.truthy(gate.is_cwv_javelin("cwv_es_javelin"))
        H.truthy(gate.is_cwv_javelin("cwv_wh_javelin_001"))
        H.truthy(gate.is_cwv_javelin("cwv_es_javelin_skin"))
        H.truthy(gate.is_cwv_javelin("cwv_grenade_tuskgor_javelin"))
        H.truthy(gate.is_cwv_javelin({
            item_data = { mod_data = { backend_id = "cwv_es_javelin_042" } },
        }))
        H.truthy(not gate.is_cwv_javelin("we_javelin"))
        H.truthy(not gate.is_cwv_javelin("cwv_es_javelin_shield_001"))
        H.truthy(not gate.is_cwv_javelin({ data = { name = "we_javelin" } }))
    end)

    H.test("CWV javelin gate hides rows only while capability is unproven", function()
        local vanilla = { backend_id = "vanilla_javelin" }
        local cwv = { data = { mod_data = { backend_id = "cwv_es_javelin_001" } } }
        local rows = { vanilla, cwv }
        local enabled, enabled_removed = gate.filter_unavailable(rows, "enabled")
        H.equal(enabled, rows)
        H.equal(enabled_removed, 0)
        local disabled, disabled_removed = gate.filter_unavailable(rows, "disabled")
        H.equal(disabled_removed, 1)
        H.equal(#disabled, 1)
        H.equal(disabled[1], vanilla)
        H.equal(gate.should_block(cwv, "disabled"), true)
        H.equal(gate.should_block(cwv, "enabled"), false)
        H.equal(gate.should_block(vanilla, "disabled"), false)
    end)

    H.test("CWV transient ref shadow substitutes and restores exact counts", function()
        local refs = { cwv_custom = 2, vanilla_safe = 3, unrelated = 7 }
        local restore, changed = gate.begin_ref_shadow(
            refs, "cwv_custom", "vanilla_safe", true)
        H.equal(changed, true)
        H.equal(refs.cwv_custom, nil)
        H.equal(refs.vanilla_safe, 5)
        H.equal(refs.unrelated, 7)
        restore()
        H.equal(refs.cwv_custom, 2)
        H.equal(refs.vanilla_safe, 3)
        H.equal(refs.unrelated, 7)
        restore()
        H.equal(refs.cwv_custom, 2)
        H.equal(refs.vanilla_safe, 3)
    end)

    H.test("CWV transient ref shadow omits unregistered fallback and restores", function()
        local refs = { cwv_custom = 1 }
        local restore, changed = gate.begin_ref_shadow(
            refs, "cwv_custom", "missing_safe", false)
        H.equal(changed, true)
        H.equal(refs.cwv_custom, nil)
        H.equal(refs.missing_safe, nil)
        restore()
        H.equal(refs.cwv_custom, 1)
        H.equal(refs.missing_safe, nil)

        local untouched = { vanilla_safe = 4 }
        local no_op, no_change = gate.begin_ref_shadow(
            untouched, "not_present", "vanilla_safe", true)
        H.equal(no_change, false)
        no_op()
        H.equal(untouched.vanilla_safe, 4)
    end)

    -- #424 world-resident pickup axis. A cwv pickup lying in the level crashes a
    -- joining non-cwv peer with no cwv RPC involved: PickupSystem._spawn_pickup
    -- goes through spawn_network_unit (pickup_system.lua:1278), the pickup game
    -- object carries the name as a NetworkLookup.pickup_names INDEX
    -- (game_object_initializers_extractors.lua:880) and the joiner decodes it
    -- strictly at game_object_initializers_extractors.lua:3411. The fence registry
    -- is what the hot-join sweep iterates.
    H.test("CWV pickup fence registry appends once and rejects non-strings", function()
        local before = #gate.fenced_pickup_names
        H.equal(gate.fence_pickup("cwv_rt424_probe"), true)
        H.equal(#gate.fenced_pickup_names, before + 1)
        H.equal(gate.fence_pickup("cwv_rt424_probe"), false)
        H.equal(#gate.fenced_pickup_names, before + 1)
        H.equal(gate.fence_pickup(""), false)
        H.equal(gate.fence_pickup(nil), false)
        H.equal(gate.fence_pickup({}), false)
        H.equal(#gate.fenced_pickup_names, before + 1)
        H.equal(gate.fenced_pickup_names[before + 1], "cwv_rt424_probe")
    end)

    H.test("CWV grenade-slot bomb enrols in the sweep and every gate close sweeps the world", function()
        local source = require("cwv_source").combined(repo_root)
        -- The bomb block loads after javelin_gate.install(), so the seeded pair is
        -- not enough; it must enrol itself.
        H.truthy(source:find("_om.javelin_gate.fence_pickup(_TJB_PICKUP_KEY)", 1, true))

        local gate_path = repo_root
            .. "/character_weapon_variants/scripts/mods/character_weapon_variants/_cwv_javelin_gate.lua"
        local file = assert(io.open(gate_path, "rb"))
        local gate_source = file:read("*a")
        file:close()
        -- The sweep iterates the registry, never a hardcoded pair.
        H.truthy(gate_source:find("for _, pickup_name in ipairs(M.fenced_pickup_names) do", 1, true))
        H.equal(gate_source:find("ipairs({ pickup_key, link_pickup_key })", 1, true), nil)
        H.truthy(gate_source:find("fenced=%d", 1, true))
        -- Pool ejection retracts only FUTURE rolls, so the sweep must hang off the
        -- gate's own close transition rather than any single detecting seam.
        local feature = assert(gate_source:find('register_gated_feature("cwv_tuskgor_javelin_throw"', 1, true))
        local on_disable = assert(gate_source:find("on_disable = function()", feature, true))
        local sweep_call = assert(gate_source:find("remove_live_recovery_pickups()", on_disable, true))
        H.truthy(feature < on_disable and on_disable < sweep_call)
        H.truthy(gate_source:find("[cwv:424] gate closed; world sweep", 1, true))
        H.truthy(gate_source:find("_cwv424_gate_close_sweep_installed = true", 1, true))
        -- A parity transition reaches on_disable on EVERY peer, but retracting a
        -- server-owned pickup unit is a host action; a client doing it locally
        -- desyncs instead of protecting anyone.
        local system = assert(gate_source:find('entity:system("pickup_system")', 1, true))
        local server_guard = assert(gate_source:find("if not pickup_system.is_server then return 0 end", system, true))
        local delete = assert(gate_source:find("spawner:mark_for_deletion(unit)", server_guard, true))
        H.truthy(system < server_guard and server_guard < delete)
    end)

    H.test("CWV source fences hot join and blocks every thrown sender before encode", function()
        local source = require("cwv_source").combined(repo_root)
        local transient = assert(source:find('mod:hook("TransientPackageLoader", "hot_join_sync"', 1, true))
        local transient_fence = assert(source:find("parity:require_peer(peer_id)", transient, true))
        local projectile_shadow = assert(source:find("M.begin_ref_shadow(", transient_fence, true))
        local transient_send = assert(source:find("pcall(func, self, peer_id)", projectile_shadow, true))
        H.truthy(transient < transient_fence and transient_fence < projectile_shadow
            and projectile_shadow < transient_send)
        local hot_join = assert(source:find('mod:hook("GameNetworkManager", "set_peer_synchronizing"', 1, true))
        local require_peer = assert(source:find("parity:require_peer(peer_id)", hot_join, true))
        local cleanup = assert(source:find("remove_live_recovery_pickups()", require_peer, true))
        local native_sync = assert(source:find("return func(self, peer_id)", cleanup, true))
        H.truthy(hot_join < require_peer and require_peer < cleanup and cleanup < native_sync)
        local sync_predicate = assert(source:find(
            'mod:hook("NetworkServer", "is_network_state_fully_synced_for_peer"', native_sync, true))
        local failed_join_floor = assert(source:find(
            "if rejected_peers[peer_id] then return false end", sync_predicate, true))
        H.truthy(native_sync < sync_predicate and sync_predicate < failed_join_floor)
        H.truthy(source:find('mod:hook("ActionThrownProjectile", "_fire"', 1, true))
        H.truthy(source:find('mod:hook("ActionThrownProjectile", "_use_ammo"', 1, true))
        H.truthy(source:find('mod:hook("ActionUtils", "spawn_pickup_projectile"', 1, true))
        H.truthy(source:find("_cwv424_actionutils_sender_guard_installed = true", 1, true))
        H.truthy(source:find("_cwv424_transient_sender_guard_installed = true", 1, true))
        H.truthy(source:find("_cwv424_throw_gate_installed = true", 1, true))
        H.truthy(source:find("_cwv424_hot_join_fence_installed = true", 1, true))
    end)

    H.test("CWV tuskgor bomb path stays fail-closed until ActionUtils sender gate exists", function()
        local source = require("cwv_source").combined(repo_root)
        local feature_on = source:find("local _TJB_FEATURE_ON = true", 1, true) ~= nil
        local feature_off = source:find("local _TJB_FEATURE_ON = false", 1, true) ~= nil
        local has_actionutils_sender_gate = source:find('ActionUtils", "spawn_pickup_projectile"', 1, true) ~= nil
            or source:find("ActionUtils.spawn_pickup_projectile", 1, true) ~= nil
            or source:find("cwv_tuskgor_javelin_bomb_actionutils_wire_gate", 1, true) ~= nil

        if feature_on then
            H.truthy(
                has_actionutils_sender_gate,
                "enabling the Tuskgor bomb path requires an ActionUtils.spawn_pickup_projectile sender gate"
            )
        else
            H.truthy(feature_off, "Tuskgor bomb path must be explicitly inert while no ActionUtils sender gate exists")
        end

        H.truthy(
            source:find('mod._cwv_peer_parity:register_gated_feature("cwv_tuskgor_javelin_bomb_pool"', 1, true),
            "Tuskgor bomb world/pool injection must remain behind the peer-parity registry"
        )
        H.truthy(
            source:find("if not _TJB_FEATURE_ON then return end", 1, true),
            "Tuskgor bomb pool injection must self-guard while the feature flag is disabled"
        )
        H.truthy(
            source:find("rawget(ItemMasterList, _TJB_ITEM_KEY)", 1, true),
            "manual grant command must not index an unregistered bomb item directly"
        )
        H.truthy(
            source:find("javelin-bomb item not registered", 1, true),
            "manual grant command must fail closed while the bomb item is not registered"
        )
    end)
end
