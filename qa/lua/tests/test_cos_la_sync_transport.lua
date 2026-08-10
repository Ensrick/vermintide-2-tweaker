-- Boundary + behaviour guard for the #1159 cos_la_* peer-sync transport owner
-- (_cos_la_sync_transport.lua).
--
-- Two load-bearing properties this file exists to pin.
--
-- 1. TWO-PHASE INSTALL, ONE OWNER. Phase 1 (identity + send + queue) registers
--    nothing; phase 2 runs the six registrations at the exact entry line the
--    first mod:network_register used to occupy, which is AFTER the apply/revert
--    owner and the replay coordinator have published the callbacks the handlers
--    invoke. Folding phase 2 into phase 1 still loads, still passes a naive
--    "the owner registers four channels" check, and silently moves six
--    registrations ~800 lines earlier - so the ordering is asserted at both call
--    sites, and the owner itself asserts phase 2 runs exactly once.
--
-- 2. THE RETRY-QUEUE GETTER. `_la_pending_apply` is an entry local that its
--    drains REBIND (`_la_pending_apply = kept`). The cos_la_apply receiver only
--    appends to it, so a by-value hand-off would load, would pass a plain
--    "a failed apply is deferred" test, and would silently park every deferral
--    in a table nobody drains. The matched pair below is the signal that cannot
--    move: the first test proves a deferral reaches the queue, the second
--    REBINDS the entry-side local the way mod.update's drain does and proves the
--    NEXT deferral reaches the new table. Converting the getter back into an
--    install-time value leaves the first green and reddens only the second.
return function(H, repo_root)
    local base = "cosmetics_tweaker/scripts/mods/cosmetics_tweaker/"
    local module_relative = base .. "_cos_la_sync_transport.lua"

    local function read(relative_path)
        local file = assert(io.open(repo_root .. "/" .. relative_path, "rb"))
        local source = file:read("*a")
        file:close()
        return source
    end

    local function occurrences(haystack, needle)
        local count, offset = 0, 1
        while true do
            local at = haystack:find(needle, offset, true)
            if not at then return count end
            count, offset = count + 1, at + #needle
        end
    end

    local entry = read(base .. "cosmetics_tweaker.lua")
    local source = read(module_relative)
    local owner_install =
        'mod:dofile("scripts/mods/cosmetics_tweaker/_cos_la_sync_transport").install(mod, {'

    -- ================================================================
    -- Boundary
    -- ================================================================

    H.test("cos la sync transport installs in two ordered phases", function()
        H.equal(occurrences(entry, owner_install), 1)
        H.equal(occurrences(entry, "LA_SYNC.install_receivers()"), 1)

        local at_phase1 = assert(entry:find(owner_install, 1, true))
        local at_apply = assert(entry:find(
            'mod:dofile("scripts/mods/cosmetics_tweaker/_cos_la_apply_runtime").install',
            1, true))
        local at_replay = assert(entry:find(
            'mod:dofile("scripts/mods/cosmetics_tweaker/_cos_la_replay_runtime").install',
            1, true))
        local at_phase2 = assert(entry:find("LA_SYNC.install_receivers()", 1, true))
        local at_glow = assert(entry:find(
            '"scripts/mods/cosmetics_tweaker/_cos_glow_transport").install',
            at_phase2, true))

        -- Phase 1 publishes the peer-identity helpers the three installs below
        -- consume, so it must precede all of them.
        H.truthy(at_phase1 < at_apply)
        -- Phase 2's handlers call mod._la_reconcile / mod._la_apply_revert_recv
        -- (apply owner) and mod._cos_replay (replay coordinator), so it must
        -- follow both, and the glow transport keeps its post-LA-RPC position.
        H.truthy(at_apply < at_replay)
        H.truthy(at_replay < at_phase2)
        H.truthy(at_phase2 < at_glow)
    end)

    H.test("cos la sync transport owns the whole cos_la_* channel", function()
        for _, channel in ipairs({
            "cos_la_apply_req", "cos_la_apply", "cos_la_state_req", "cos_la_state_ack",
        }) do
            local needle = 'mod:network_register("' .. channel .. '", function('
            H.equal(occurrences(source, needle), 1,
                channel .. " must be registered exactly once by the owner")
        end
        H.equal(entry:find('mod:network_register("cos_la_', 1, true), nil,
            "the entry must not re-register any cos_la_* channel")
        -- The peer lifecycle pair is hook_safe: VMF silently DROPS a second
        -- registration on the same (Class, method), so a resurrected entry copy
        -- would not error, it would just stop working.
        H.equal(occurrences(source, 'mod:hook_safe(PlayerManager, "remove_player"'), 1)
        H.equal(occurrences(source, 'mod:hook_safe(PlayerManager, "add_remote_player"'), 1)
        H.equal(entry:find("mod:hook_safe(PlayerManager,", 1, true), nil)
        -- Phase 1 is registration-free, which is what makes it order-safe.
        local phase1 = source:sub(1, assert(source:find("function owner.install_receivers()", 1, true)))
        H.equal(phase1:gsub("%-%-[^\n]*", ""):find("mod:network_register(", 1, true), nil)
        H.equal(phase1:gsub("%-%-[^\n]*", ""):find("mod:hook", 1, true), nil)
        H.equal(source:gsub("%-%-[^\n]*", ""):find("mod:command(", 1, true), nil)
        H.equal(source:gsub("%-%-[^\n]*", ""):find("mod:dofile(", 1, true), nil)
        H.truthy(source:find("RESPONSIBILITY", 1, true))
        H.truthy(source:find("Consumed via:", 1, true))
    end)

    H.test("cos la sync transport owns every moved definition exclusively", function()
        for _, needle in ipairs({
            "local function _host_peer_id()",
            "local function _local_peer_id_quick()",
            "local function _is_local_server()",
            "local function _wearer_unit_for_peer(",
            "local function _local_player_peer_id()",
            "local function _drain_deferred_la_emits()",
            "local _last_emit_at = {}",
            "local _EMIT_DEDUP_WINDOW = 0.5",
            "_send_la_apply = function(unit, slot_name, kind,",
            "mod._send_la_revert = function",
            "mod._send_offhand_mesh = function",
            "mod._store_offhand_mesh_recv = function",
            "mod._la_career_for_unit = function",
            "mod._la_tick_peer_purges = function",
        }) do
            H.truthy(source:find(needle, 1, true), needle .. " missing from the owner")
            H.equal(entry:find(needle, 1, true), nil, needle .. " must not stay in the entry")
        end
        -- The entry keeps the net-safe hook-status table and its substitute-name
        -- helper: those are vanilla-RPC broker state, not this mod's own channel.
        -- The two vanilla-RPC substitution hooks themselves moved on to
        -- _cos_la_loadout_safety (#1159 wave 14); their singleton-ness is pinned
        -- by test_cos_la_loadout_safety, so assert only that they left the entry.
        H.truthy(entry:find("local _net_safe_hook_status = {", 1, true))
        H.truthy(entry:find("local function _la_substitute_name(", 1, true))
        H.equal(entry:find('mod:hook(CosmeticUtils, "update_cosmetic_slot"', 1, true), nil)
        H.equal(entry:find('mod:hook(LoadoutUtils, "sync_loadout_slot"', 1, true), nil)
        -- Strip comments: the owner's NOT-OWNED-HERE header names them on purpose.
        H.equal(source:gsub("%-%-[^\n]*", ""):find("_net_safe_hook_status", 1, true), nil)
    end)

    H.test("cos la sync transport crossing state uses the correct hand-off kind",
    function()
        -- REBOUND by the entry's drain -> getter, resolved at the append site.
        H.truthy(entry:find(
            "get_la_pending_apply = function() return _la_pending_apply end,", 1, true))
        H.equal(occurrences(source, "local _la_pending_apply = _get_la_pending_apply()"), 1)
        H.equal(source:find("local _la_pending_apply = {}", 1, true), nil)
        -- The receiver only APPENDS, so unlike _cos_la_apply_runtime it needs no
        -- setter; taking one would be a silent claim it rebinds the queue.
        H.equal(source:find("_set_la_pending_apply", 1, true), nil)
        -- Identity-stable stores cross BY VALUE.
        H.truthy(entry:find("la_equips_by_peer = _la_equips_by_peer,", 1, true))
        H.truthy(entry:find("glow_by_peer = _glow_by_peer,", 1, true))
        H.equal(source:find("local _la_equips_by_peer = {}", 1, true), nil)
        -- The sender's forward declaration is the ONLY way its original plain
        -- assignment stays byte-identical instead of becoming a global write.
        H.equal(occurrences(source, "local _send_la_apply"), 1)
        H.truthy(entry:find("_send_la_apply              = LA_SYNC.send_la_apply", 1, true))
    end)

    -- ================================================================
    -- Behaviour: the real module driven through a stub install
    -- ================================================================

    local saved = {}
    local function set_globals(fixture)
        saved = {
            Unit = _G.Unit, Managers = _G.Managers, ScriptUnit = _G.ScriptUnit,
            PlayerManager = _G.PlayerManager, printf = _G.printf, get_mod = _G.get_mod,
        }
        _G.Unit = { alive = function(u) return u ~= nil end }
        _G.ScriptUnit = { has_extension = function() return nil end }
        _G.PlayerManager = {}
        _G.printf = function() end
        _G.get_mod = function() return nil end
        _G.Managers = fixture
    end
    local function restore_globals()
        _G.Unit, _G.Managers, _G.ScriptUnit = saved.Unit, saved.Managers, saved.ScriptUnit
        _G.PlayerManager, _G.printf, _G.get_mod = saved.PlayerManager, saved.printf, saved.get_mod
    end

    -- The entry-side local the getter fronts. Rebinding THIS is what mod.update's
    -- drain does, and what the receiver must be able to see.
    local entry_pending
    local la_equips_by_peer, glow_by_peer
    local mod, sends, handlers, hooks, reconcile_result

    local function build(options)
        options = options or {}
        entry_pending = {}
        la_equips_by_peer = {}
        glow_by_peer = {}
        sends, handlers, hooks = {}, {}, {}
        reconcile_result = options.reconcile ~= false

        mod = {
            _offhand_mesh_by_peer = {},
            _cos_husk_identity = {
                career_for_unit = function() return "es_knight" end,
                transport_career_valid = function() return true, "ok" end,
                new_entry = function(kind, armoury_key, vanilla_key, hand_field, career)
                    return {
                        kind = kind, armoury_key = armoury_key,
                        vanilla_key = vanilla_key, hand_field = hand_field,
                        wearer_career = career,
                    }
                end,
            },
            _la_reconcile = function() return reconcile_result end,
        }
        function mod:info() end
        function mod:network_send(name, target, schema, payload)
            sends[#sends + 1] =
                { name = name, target = target, schema = schema, payload = payload }
        end
        function mod:network_register(name, fn) handlers[name] = fn end
        function mod:hook_safe(class_ref, method, fn)
            hooks[method] = fn
            hooks[#hooks + 1] = class_ref
        end

        set_globals({
            state = { network = { server_peer_id = options.host_peer } },
            chat = {},
            player = {
                is_server = options.is_server or nil,
                local_player = function() return { peer_id = "local-peer" } end,
                owner = function(_, unit) return { peer_id = unit and unit.peer or "wearer" } end,
                player_from_peer_id = function(_, peer)
                    return { player_unit = { peer = peer } }
                end,
            },
        })

        local Transport = assert(loadfile(repo_root .. "/" .. module_relative))()
        local owner = Transport.install(mod, {
            rpc_schema = 2,
            la_bridge = { registered = true, armoury_to_backend = { KruberPure = "bid" } },
            la_persistence = {},
            la_replay_policy = {
                should_publish_local_on_peer_ready = function() return true end,
            },
            probe = nil,
            glow_log = function() end,
            dbg = function() end,
            dbg_alert = function() end,
            glow_by_peer = glow_by_peer,
            la_equips_by_peer = la_equips_by_peer,
            local_player_safe = function() return { peer_id = "local-peer" } end,
            trace = function() end,
            get_la_pending_apply = function() return entry_pending end,
        })
        owner.install_receivers()
        return owner
    end

    H.test("host emit records authoritative state and broadcasts to all", function()
        build({ is_server = true, host_peer = "local-peer" })
        local ok, how = mod._cos_la_sync_transport_owner.send_la_apply(
            { peer = "wearer" }, "slot_hat", "hat", "KruberPure", "es_hat_01")
        restore_globals()
        H.truthy(ok)
        H.equal(how, "emitted")
        H.equal(la_equips_by_peer["wearer"]["slot_hat"].armoury_key, "KruberPure")
        H.equal(#sends, 1)
        H.equal(sends[1].name, "cos_la_apply")
        H.equal(sends[1].target, "all")
        H.equal(sends[1].schema, 2)
        H.equal(sends[1].payload.wearer_peer_id, "wearer")
    end)

    H.test("client emit requests the host and coalesces a repeat", function()
        local owner = build({ host_peer = "remote-host" })
        local send = owner.send_la_apply
        local ok1 = send({ peer = "wearer" }, "slot_hat", "hat", "KruberPure", "es_hat_01")
        local ok2, how2 = send({ peer = "wearer" }, "slot_hat", "hat", "KruberPure", "es_hat_01")
        local _, how3 = send({ peer = "wearer" }, "slot_skin", "armor", "KruberPure", "es_skin_01")
        restore_globals()
        H.truthy(ok1)
        H.truthy(ok2)
        H.equal(how2, "coalesced", "a repeat inside the 0.5s window must not hit the wire")
        H.equal(how3, "emitted", "a different slot is a different dedup key")
        H.equal(#sends, 2)
        H.equal(sends[1].name, "cos_la_apply_req")
        H.equal(sends[1].target, "remote-host")
        -- The client never writes the authoritative store; only the host does.
        H.equal(next(la_equips_by_peer), nil)
    end)

    H.test("an emit with no host yet queues and drains once a host appears", function()
        local owner = build({})
        local ok, how = owner.send_la_apply(
            { peer = "wearer" }, "slot_hat", "hat", "KruberPure", "es_hat_01")
        H.truthy(ok)
        H.equal(how, "queued")
        H.equal(#sends, 0)
        H.equal(#mod._la_deferred_emits, 1)
        -- Host resolves (mission load wires state.network) -> the drain re-emits.
        _G.Managers.state.network.server_peer_id = "remote-host"
        mod._drain_deferred_la_emits()
        restore_globals()
        H.equal(#sends, 1)
        H.equal(sends[1].name, "cos_la_apply_req")
        H.equal(#mod._la_deferred_emits, 0)
    end)

    H.test("a host revert clears the entry and broadcasts with no armoury key", function()
        build({ is_server = true, host_peer = "local-peer" })
        la_equips_by_peer["wearer"] = { slot_hat = { kind = "hat", armoury_key = "KruberPure" } }
        mod._send_la_revert({ peer = "wearer" }, "slot_hat", "hat", "es_hat_01")
        restore_globals()
        H.equal(la_equips_by_peer["wearer"].slot_hat, nil)
        H.equal(#sends, 1)
        H.equal(sends[1].payload.revert, true)
        H.equal(sends[1].payload.armoury_key, nil)
    end)

    H.test("a vanilla offhand mesh supersedes an LA pick on the same hand", function()
        build({ is_server = true, host_peer = "local-peer" })
        la_equips_by_peer["wearer"] = {
            slot_melee = { kind = "unit", armoury_key = "Bastonne", hand_field = "left_hand_unit" },
        }
        mod._store_offhand_mesh_recv("wearer", "slot_melee", "left_hand_unit", "units/vanilla")
        H.equal(mod._offhand_mesh_by_peer["wearer"].slot_melee.left_hand_unit, "units/vanilla")
        H.equal(la_equips_by_peer["wearer"].slot_melee, nil,
            "per-(wearer, slot, hand) mutual exclusion must drop the LA entry")
        -- The empty-string sentinel CLEARS the hand back to the base offhand.
        mod._store_offhand_mesh_recv("wearer", "slot_melee", "left_hand_unit", "")
        restore_globals()
        H.equal(mod._offhand_mesh_by_peer["wearer"].slot_melee.left_hand_unit, nil)
    end)

    H.test("the apply broadcast is rejected from a non-host sender", function()
        build({ host_peer = "remote-host" })
        handlers["cos_la_apply"]("impostor-peer", 2, {
            wearer_peer_id = "wearer", slot = "slot_hat",
            kind = "hat", armoury_key = "KruberPure",
        })
        -- A cross-version payload is dropped on the same path.
        handlers["cos_la_apply"]("remote-host", 1, {
            wearer_peer_id = "wearer", slot = "slot_hat",
            kind = "hat", armoury_key = "KruberPure",
        })
        restore_globals()
        H.equal(next(la_equips_by_peer), nil)
    end)

    -- ---- the matched pair: getter vs by-value -------------------------------

    H.test("a failed apply defers into the entry-owned retry queue", function()
        build({ host_peer = "remote-host", reconcile = false })
        handlers["cos_la_apply"]("remote-host", 2, {
            wearer_peer_id = "wearer", slot = "slot_hat",
            kind = "hat", armoury_key = "KruberPure", vanilla_key = "es_hat_01",
        })
        restore_globals()
        H.equal(#entry_pending, 1)
        H.equal(entry_pending[1][1], "wearer")
        H.equal(entry_pending[1][4], "KruberPure")
    end)

    H.test("a deferral after the entry REBINDS the queue reaches the new table",
    function()
        build({ host_peer = "remote-host", reconcile = false })
        handlers["cos_la_apply"]("remote-host", 2, {
            wearer_peer_id = "wearer", slot = "slot_hat",
            kind = "hat", armoury_key = "KruberPure", vanilla_key = "es_hat_01",
        })
        local discarded = entry_pending
        H.equal(#discarded, 1)
        -- Exactly what mod.update's drain does: keep the survivors in a FRESH
        -- table and rebind the entry local to it.
        entry_pending = {}
        handlers["cos_la_apply"]("remote-host", 2, {
            wearer_peer_id = "wearer-2", slot = "slot_skin",
            kind = "armor", armoury_key = "KruberPure", vanilla_key = "es_skin_01",
        })
        restore_globals()
        H.equal(#discarded, 1, "the discarded table must not have grown")
        H.equal(#entry_pending, 1,
            "a by-value hand-off parks this deferral in the table nobody drains")
        H.equal(entry_pending[1][1], "wearer-2")
    end)

    -- ---- peer lifecycle ------------------------------------------------------

    H.test("a peer purge is deferred, cancelled by a re-add, and sweeps dedup keys",
    function()
        build({ is_server = true, host_peer = "local-peer" })
        la_equips_by_peer["gone-peer"] = { slot_hat = { kind = "hat" } }
        la_equips_by_peer["back-peer"] = { slot_hat = { kind = "hat" } }

        hooks["remove_player"](nil, "gone-peer")
        hooks["remove_player"](nil, "back-peer")
        H.truthy(mod._la_peer_purge_at["gone-peer"])
        -- A level transition re-adds within seconds; that is NOT a disconnect.
        hooks["add_remote_player"](nil, "back-peer")
        H.equal(mod._la_peer_purge_at["back-peer"], nil)

        -- Not yet due: the store must still be intact.
        mod._la_tick_peer_purges()
        H.truthy(la_equips_by_peer["gone-peer"])
        -- Force the deadline past and tick again.
        mod._la_peer_purge_at["gone-peer"] = os.clock() - 1
        mod._la_tick_peer_purges()
        restore_globals()
        H.equal(la_equips_by_peer["gone-peer"], nil)
        H.truthy(la_equips_by_peer["back-peer"])
    end)

    H.test("the local peer is never purged and receivers install exactly once",
    function()
        local owner = build({ is_server = true, host_peer = "local-peer" })
        la_equips_by_peer["local-peer"] = { slot_hat = { kind = "hat" } }
        mod._la_peer_purge_at = { ["local-peer"] = os.clock() - 1 }
        mod._la_tick_peer_purges()
        H.truthy(la_equips_by_peer["local-peer"],
            "remove_player fires for our OWN peer on every transition")

        local ok = pcall(owner.install_receivers)
        restore_globals()
        H.equal(ok, false,
            "a second phase-2 call would duplicate all six registrations")
    end)
end
