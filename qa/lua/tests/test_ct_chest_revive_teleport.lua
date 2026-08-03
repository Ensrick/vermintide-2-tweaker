-- Issue #299: Chest-of-Trials rescue must move the disabled player to the team
-- before assisted-respawn recovery can make bots follow the temporary beacon.
return function(H, repo_root)
    local root = repo_root
        .. "/chaos_wastes_tweaker_dev/scripts/mods/chaos_wastes_tweaker_dev/"
    local Policy = assert(loadfile(root .. "_ct_chest_revive_policy.lua"))()

    local function read(path)
        local file = assert(io.open(path, "rb"))
        local content = file:read("*a")
        file:close()
        return content
    end

    H.test("CT #299 policy keys sibling bots by peer and local player", function()
        H.equal(Policy.key("host", 1), "host/1")
        H.equal(Policy.key("host", 2), "host/2")
        H.equal(Policy.key(nil, 1), nil)
        H.equal(Policy.key("host", nil), nil)
    end)

    H.test("CT #299 dead player waits for assisted-respawn spawn", function()
        local entry = assert(Policy.new_entry("peer", 1, {}, { x = 1, y = 2, z = 3 }, 10))
        H.equal(Policy.next_action(entry, { alive = false }), "wait_unit")
        H.equal(Policy.next_action(entry, { alive = true, awaiting = false }), "wait_awaiting")
        H.equal(Policy.next_action(entry, { alive = true, awaiting = true }), "move_then_free")
    end)

    H.test("CT #299 has no policy path that frees before a successful move", function()
        local entry = assert(Policy.new_entry("peer", 1, {}, { x = 1, y = 2, z = 3 }, 10))
        H.equal(Policy.next_action(entry, { alive = true, awaiting = true }), "move_then_free")
        entry.moved = true
        H.equal(Policy.next_action(entry, { alive = true, awaiting = true }), "free")
        entry.freed = true
        H.equal(Policy.next_action(entry, { alive = true, health_alive = false }), "wait_recovery")
    end)

    H.test("CT #299 recovery retention correction is single and bounded", function()
        local entry = assert(Policy.new_entry("peer", 1, {}, { x = 1, y = 2, z = 3 }, 10))
        entry.moved, entry.freed = true, true
        H.equal(Policy.next_action(entry,
            { alive = true, health_alive = true, retained = false }), "correct_once")
        entry.corrections = 1
        H.equal(Policy.next_action(entry,
            { alive = true, health_alive = true, retained = false }), "complete")
        H.equal(Policy.next_action(entry,
            { alive = true, health_alive = true, retained = true }), "complete")
    end)

    H.test("CT #299 timeout and repeated exceptions are bounded", function()
        local entry = assert(Policy.new_entry("peer", 1, {}, { x = 1, y = 2, z = 3 }, 10))
        H.equal(entry.deadline, 10 + Policy.TIMEOUT_SECONDS)
        H.equal(Policy.next_action(entry, { timed_out = true }), "drop")
        entry.errors = Policy.MAX_ERRORS
        H.equal(Policy.next_action(entry, { timed_out = false }), "drop")
    end)

    H.test("CT #299 policy stores only scalar anchor components", function()
        local anchor = { x = 4, y = 5, z = 6 }
        local entry = assert(Policy.new_entry("peer", 1, {}, anchor, 0))
        anchor.x = 99
        H.deep_equal(entry.anchor, { x = 4, y = 5, z = 6 })
    end)

    H.test("CT #299 policy module stays engine-free", function()
        local source = read(root .. "_ct_chest_revive_policy.lua")
        H.equal(source:find("Managers", 1, true), nil)
        H.equal(source:find("POSITION_LOOKUP", 1, true), nil)
        H.equal(source:find("Vector3", 1, true), nil)
        H.equal(source:find("Unit.", 1, true), nil)
        H.equal(source:find("mod:", 1, true), nil)
    end)

    H.test("CT #299 runtime wires move-before-free and visible bounded errors", function()
        local source = read(root .. "chaos_wastes_tweaker_dev.lua")
        H.truthy(source:find("_ct_chest_revive_policy", 1, true))
        H.truthy(source:find("ct299:move_before_free_v1", 1, true))
        H.truthy(source:find("Unit.world_position", 1, true))
        H.truthy(source:find("LocomotionUtils.disable_linked_movement", 1, true))
        H.truthy(source:find("entry.moved = true", 1, true))
        H.truthy(source:find("StatusUtils.set_respawned_network", 1, true))
        H.truthy(source:find("FAILED key=%s error=%s", 1, true))
        H.equal(source:find("local pos = POSITION_LOOKUP[u]", 1, true), nil)

        local move_at = assert(source:find("entry.moved = true", 1, true))
        local free_at = assert(source:find("StatusUtils.set_respawned_network(unit, true, unit)",
            move_at, true))
        H.truthy(move_at < free_at)
        H.truthy(source:find('retained == false and "DEGRADED" or "PASS"', 1, true))
    end)

    H.test("CT #299 POSITION_LOOKUP write is a guarded in-place refresh, kept for teleport_to", function()
        local source = read(root .. "chaos_wastes_tweaker_dev.lua")
        -- KEPT: teleport_to's last line (set_falling_height,
        -- player_unit_locomotion_extension.lua:1022) reads POSITION_LOOKUP[unit].z
        -- (generic_status_extension.lua:2590), a dead frame-pool handle in the
        -- mod.update phase (BUG_CLASSES section 21) - without the refresh the
        -- move-then-free transaction aborts after the player already moved.
        H.truthy(source:find(
            "if lookup and lookup[unit] then lookup[unit] = Vector3(x, y, z) end", 1, true),
            "#299 must refresh an EXISTING POSITION_LOOKUP entry before teleport_to")
        -- NEVER seed: an unguarded write can create an entry the engine is not
        -- maintaining, flipping ALIVE[unit] truthy (ALIVE = POSITION_LOOKUP,
        -- global_utils.lua:15) and leaving dangling frame-pool userdata behind.
        H.equal(source:find("if lookup then lookup[unit] =", 1, true), nil,
            "#299 must not seed POSITION_LOOKUP entries the engine does not maintain")
        -- The mod's own readback never consumes the lookup - it re-derives live
        -- positions through _world_xyz (Unit.world_position).
        H.truthy(source:find("local ux, uy, uz = _world_xyz(unit)", 1, true))
    end)
end
