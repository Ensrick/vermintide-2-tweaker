-- Boundary + behaviour guard for the #1159 LA apply / revert / reconcile owner
-- (_cos_la_apply_runtime.lua).
--
-- Two load-bearing properties this file exists to pin, both of them signals the
-- structural move cannot silently break:
--
--   1. THE ACCESSOR PAIR. `_la_pending_apply` (the LA retry queue) stays an
--      ENTRY local, and BOTH of its drains REBIND it (`_la_pending_apply = kept`)
--      instead of mutating in place - one drain moved into this owner, the other
--      stayed on the entry in mod.update. So the queue crosses the boundary as a
--      GETTER **and** a SETTER, and each half gets a matched pair of tests:
--        * getter: the first test proves the owner appends to the queue at all;
--          the second REBINDS the entry-side local the way mod.update's drain
--          does and proves the append lands in the NEW table. A by-value
--          hand-off passes the first and fails only the second.
--        * setter: the control test asserts the same revert call's effect on the
--          BY-VALUE store, which the setter cannot influence; the treatment test
--          asserts the queue rebind is VISIBLE TO THE ENTRY. Drop the setter and
--          the control still passes - the owner's private copy is purged - while
--          the entry keeps handing the un-purged queue to mod.update, which
--          re-imposes the cosmetic that was just reverted.
--      That second failure is invisible to a compile, to luacheck, and to every
--      other test in this suite.
--
--   2. THE REGISTRATION VOID. The moved block registered NOTHING - no mod:hook,
--      mod:hook_safe, mod:hook_origin, mod:command, mod:network_register or
--      mod:dofile. That is WHY the move could not perturb hook order, so it is
--      asserted here rather than left as a claim in a commit message.
return function(H, repo_root)
    local function read(relative)
        local file = assert(io.open(repo_root .. "/" .. relative, "rb"))
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

    local entry = read("cosmetics_tweaker/scripts/mods/cosmetics_tweaker/cosmetics_tweaker.lua")
    local module_relative =
        "cosmetics_tweaker/scripts/mods/cosmetics_tweaker/_cos_la_apply_runtime.lua"
    local source = read(module_relative)
    local owner_install =
        'mod:dofile("scripts/mods/cosmetics_tweaker/_cos_la_apply_runtime").install(mod, {'

    -- ================================================================
    -- Structure
    -- ================================================================

    H.test("cos la apply runtime installs exactly once, in its former position",
    function()
        H.equal(occurrences(entry, owner_install), 1)
        local at_owner = entry:find(owner_install, 1, true)
        -- The block sat between the husk-init hook_safe above and the bounded
        -- replay coordinator below, and the latter's own comment requires it to
        -- follow the canonical _la_reconcile owner immediately.
        local at_husk_init = entry:find(
            'mod:hook_safe("SimpleHuskInventoryExtension", "init"', 1, true)
        local at_replay = entry:find(
            'mod:dofile("scripts/mods/cosmetics_tweaker/_cos_la_replay_runtime").install',
            1, true)
        -- #1159: the cos_la_* receivers moved into _cos_la_sync_transport, whose
        -- second install phase now occupies the line the first
        -- mod:network_register used to hold. Same anchor, measured at the call
        -- site that replaced the registration.
        local at_first_rpc = entry:find("LA_SYNC.install_receivers()", 1, true)
        H.truthy(at_husk_init and at_replay and at_first_rpc)
        H.truthy(at_husk_init < at_owner)
        H.truthy(at_owner < at_replay)
        H.truthy(at_replay < at_first_rpc)
    end)

    H.test("cos la apply runtime registers nothing at all", function()
        -- Strip comments: the header names these on purpose.
        local exec = source:gsub("%-%-[^\n]*", "")
        H.equal(occurrences(exec, "mod:hook("), 0)
        H.equal(occurrences(exec, "mod:hook_safe("), 0)
        H.equal(occurrences(exec, "mod:hook_origin("), 0)
        H.equal(occurrences(exec, "mod:command("), 0)
        H.equal(occurrences(exec, "mod:network_register("), 0)
        H.equal(occurrences(exec, "mod:dofile("), 0)
        -- A registration-free owner is the whole reason the move is order-safe.
        H.truthy(source:find("RESPONSIBILITY", 1, true))
        H.truthy(source:find("Consumed via:", 1, true))
    end)

    H.test("cos la apply runtime owns the apply core and the revert primitives",
    function()
        for _, needle in ipairs({
            "local function _apply_la_on_unit(",
            "local function _try_apply_by_peer(",
            "local function _ensure_offhand_mesh(",
            "local _offhand_reswap_state = setmetatable(",
            "mod._la_native_pulse = function",
            "mod._la_restore_native_hat = function",
            "mod._la_apply_revert_recv = function",
            "mod._la_reconcile = function",
        }) do
            H.truthy(source:find(needle, 1, true), needle .. " missing from the owner")
            H.equal(entry:find(needle, 1, true), nil, needle .. " must not stay in the entry")
        end
    end)

    H.test("cos la apply runtime leaves the two entry-kept hooks alone", function()
        -- These two deliberately stay on the entry (#1159 scope note). The owner
        -- CALLS the attachment extension's own create_attachment method, which is
        -- a different thing from hooking AttachmentUtils.
        H.truthy(entry:find(
            'mod:hook("SimpleHuskInventoryExtension", "_wield_slot"', 1, true))
        H.truthy(entry:find('mod:hook(AttachmentUtils, "create_attachment"', 1, true))
        H.equal(source:find('mod:hook(AttachmentUtils', 1, true), nil)
        H.truthy(source:find("pcall(ext.create_attachment, ext, slot_name", 1, true))
    end)

    H.test("cos la apply runtime crossing state uses the correct hand-off kind",
    function()
        -- REBOUND by BOTH sides -> getter AND setter; the owner must never
        -- declare a queue of its own at install scope.
        H.truthy(entry:find(
            "get_la_pending_apply = function() return _la_pending_apply end,", 1, true))
        H.truthy(entry:find(
            "set_la_pending_apply = function(t) _la_pending_apply = t end,", 1, true))
        H.equal(source:find("local _la_pending_apply = {}", 1, true), nil)
        H.equal(source:find("local _la_pending_apply\n", 1, true), nil)
        -- Every read resolves through the getter, at the statement that used to
        -- perform the inline read: three sites, one per enclosing scope.
        H.equal(occurrences(source, "local _la_pending_apply = _get_la_pending_apply()"), 3)
        H.equal(occurrences(source, "_set_la_pending_apply(_la_pending_apply)"), 1)
        -- The store, by contrast, is identity-stable and crosses BY VALUE.
        H.truthy(entry:find("la_equips_by_peer = _la_equips_by_peer,", 1, true))
        H.equal(source:find("local _la_equips_by_peer = {}", 1, true), nil)
    end)

    -- ================================================================
    -- Behaviour: a stub install driven through the real module
    -- ================================================================

    -- The entry-side local the accessors front. Rebinding THIS variable is what
    -- mod.update's drain does, and what the owner's setter must be able to do.
    local entry_pending
    local la_equips_by_peer
    local mod
    local paint_mesh_ok
    local rewield_requests

    local function build()
        entry_pending = {}
        la_equips_by_peer = {}
        paint_mesh_ok = false
        rewield_requests = 0
        mod = {
            info = function() end,
            _cos_rewield = {
                pulsing = function() return false end,
                alternate_slot = function() return "slot_ranged" end,
                pulse_now = function() return true, true end,
                request = function()
                    rewield_requests = rewield_requests + 1
                    return false, "deferred"
                end,
            },
            _cos_husk_identity = {
                entry_matches_career = function() return true, "ok" end,
            },
            _la_deus_weapon_yield = function() return false end,
            _la_career_for_unit = function() return "es_knight" end,
            _la_wielded_item_matches = function() return true, { template = "t" } end,
        }
        local Runtime = assert(loadfile(repo_root .. "/" .. module_relative))()
        return Runtime.install(mod, {
            custom_hats = { is_custom_identity = function() return false end },
            gk_set = { resolve_variant = function() return nil end },
            la_bridge = { registered = true, resolve_texture_receiver = function() return nil end },
            la_replay_policy = { wielded_slot = function() return "slot_melee" end },
            probe = nil,
            apply_authored_offhand_to_unit = function() return true end,
            dbg = function() end,
            dbg_alert = function() end,
            la_chars_compatible = function() return true end,
            la_equips_by_peer = la_equips_by_peer,
            level_world = function() return "world" end,
            offhand_paint_mesh_ok = function() return paint_mesh_ok end,
            override_package_ready = function() return true end,
            purge_stale_peer_slot = function() end,
            resolve_authored_offhand_mesh = function()
                return "units/la_shield", nil, true
            end,
            resolve_la_variant = function()
                return { swap_hand = "offhand", kind = "unit",
                         new_units = { "units/la_shield" } }
            end,
            trace_paint = function() end,
            unit_mesh_name = function() return "mesh" end,
            wearer_unit_for_peer = function(peer)
                if peer == "peer_a" then return "unit_a" end
                if peer == "peer_b" then return "unit_b" end
                return nil
            end,
            get_la_pending_apply = function() return entry_pending end,
            set_la_pending_apply = function(t) entry_pending = t end,
        })
    end

    -- Minimal engine surface the moved code touches on the paths driven below.
    local function with_engine(body)
        local saved = {
            Unit = _G.Unit, ScriptUnit = _G.ScriptUnit, get_mod = _G.get_mod,
            printf = _G.printf, Application = _G.Application,
        }
        _G.Unit = { alive = function(u) return u ~= nil end }
        _G.ScriptUnit = {
            has_extension = function()
                return {
                    wield = function() end,
                    _equipment = {
                        slots = { slot_melee = {}, slot_ranged = {} },
                        left_hand_wielded_unit_3p = "left_3p",
                        wielded_slot = "slot_melee",
                    },
                }
            end,
        }
        _G.get_mod = function(name)
            if name ~= "Loremasters-Armoury" then return nil end
            return { SKIN_LIST = { la_key = {
                swap_hand = "offhand", kind = "unit",
                new_units = { "units/la_shield" },
            } } }
        end
        _G.printf = function() end
        _G.Application = { can_get = function() return true end }
        local ok, err = pcall(body)
        for k, v in pairs(saved) do _G[k] = v end
        if not ok then error(err, 0) end
    end

    local function queue(peer, slot)
        return { peer, slot, "offhand", "la_key", "vanilla_key", 0 }
    end

    -- --------- accessor pair 1: the SETTER (revert purge must reach the entry)
    -- CONTROL half. The store is handed over BY VALUE, so this half is blind to
    -- the setter by construction: it passes whether or not the owner's queue
    -- rebind reaches the entry. Verified by mutation - dropping the setter leaves
    -- this test green and reddens only the treatment half below.
    H.test("cos la apply runtime revert deletes the store entry",
    function() with_engine(function()
        build()
        la_equips_by_peer.peer_a = {
            slot_melee = { kind = "armor", armoury_key = "la_key" },
            slot_hat = { kind = "hat", armoury_key = "other_key" },
        }
        entry_pending = { queue("peer_a", "slot_melee") }
        mod._la_apply_revert_recv("peer_a", "slot_melee", "armor", nil, nil)
        H.equal(la_equips_by_peer.peer_a.slot_melee, nil)
        H.truthy(la_equips_by_peer.peer_a.slot_hat,
            "revert must not touch the wearer's other slots")
    end) end)

    -- TREATMENT half. Same call, but the assertion is on the ENTRY's binding.
    H.test("cos la apply runtime revert purge is VISIBLE TO THE ENTRY",
    function() with_engine(function()
        build()
        -- Hold the table the entry started with. The owner rebinds the queue
        -- (`_la_pending_apply = kept`); without the setter the entry would keep
        -- pointing at THIS table, and mod.update would re-impose the cosmetic the
        -- revert just removed. Identity, not contents, is the assertion.
        local before = { queue("peer_a", "slot_melee"), queue("peer_b", "slot_melee") }
        entry_pending = before
        mod._la_apply_revert_recv("peer_a", "slot_melee", "armor", nil, nil)
        H.truthy(entry_pending ~= before,
            "the owner's rebind never reached the entry (setter dropped?)")
        H.equal(#entry_pending, 1)
        H.equal(entry_pending[1][1], "peer_b", "revert purged the wrong wearer")
        H.equal(#before, 2, "the discarded table must be left untouched")
    end) end)

    -- --------- accessor pair 2: the GETTER (appends must follow a rebind)
    H.test("cos la apply runtime defers a coalesced repaint onto the queue",
    function() with_engine(function()
        build()
        la_equips_by_peer.peer_a = {
            slot_melee = { kind = "offhand", armoury_key = "la_key",
                           hand_field = "left_hand_unit", vanilla_key = "vanilla_key" },
        }
        -- paint_mesh_ok=false: the #204 warp guard skips the paint, and the
        -- mesh pulse coalesces (#1145), so the re-paint must be queued.
        local applied = mod._la_reconcile("peer_a", "slot_melee", "test", true)
        H.equal(applied, false)
        H.equal(rewield_requests, 1)
        H.equal(#entry_pending, 1)
        H.equal(entry_pending[1][1], "peer_a")
    end) end)

    H.test("cos la apply runtime appends into a REBOUND queue",
    function() with_engine(function()
        build()
        local eq = { kind = "offhand", armoury_key = "la_key",
                     hand_field = "left_hand_unit", vanilla_key = "vanilla_key" }
        la_equips_by_peer.peer_a = { slot_melee = eq }
        la_equips_by_peer.peer_b = { slot_melee = eq }
        mod._la_reconcile("peer_a", "slot_melee", "test", true)
        -- mod.update's drain rebinds the queue to a fresh filtered table. An
        -- install-time value would leave the owner appending to the discarded
        -- one, and the deferred re-paint would never be drained. A second wearer
        -- is used because the mesh pulse is rate-limited per owner unit.
        local discarded = entry_pending
        entry_pending = {}
        mod._la_reconcile("peer_b", "slot_melee", "test", true)
        H.equal(#entry_pending, 1,
            "append landed in the discarded queue (getter frozen at install?)")
        H.equal(entry_pending[1][1], "peer_b")
        H.equal(#discarded, 1, "the discarded table must not grow")
    end) end)

    -- --------- the reconcile gates still short-circuit as before
    H.test("cos la apply runtime reconcile reports its terminal reasons",
    function() with_engine(function()
        build()
        local ok, why = mod._la_reconcile("peer_a", "slot_melee", "test", true)
        H.equal(ok, false)
        H.equal(why, "no-entry")

        la_equips_by_peer.peer_z = {
            slot_melee = { kind = "offhand", armoury_key = "la_key",
                           hand_field = "left_hand_unit" },
        }
        local ok2, why2 = mod._la_reconcile("peer_z", "slot_melee", "test", true)
        H.equal(ok2, false)
        H.equal(why2, "wearer-not-spawned")

        mod._la_deus_weapon_yield = function() return true end
        local ok3, why3 = mod._la_reconcile("peer_z", "slot_melee", "test", true)
        H.equal(ok3, false)
        H.equal(why3, "deus-yield")
    end) end)

    H.test("cos la apply runtime marks itself installed exactly once",
    function() with_engine(function()
        local marker = build()
        H.truthy(marker and marker.installed)
        H.truthy(mod._cos_la_apply_runtime_owner == marker)
    end) end)
end
