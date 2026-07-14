return function(H, repo_root)
    local root = repo_root .. "/general_tweaker_dev/scripts/mods/general_tweaker_dev/"
    local policy = dofile(root .. "_gt_ai_takeover_policy.lua")

    local function read(name)
        local f = assert(io.open(root .. name, "rb"))
        local value = f:read("*a")
        f:close()
        return value
    end

    H.test("GT #247 supports exactly the three hero mission families", function()
        H.truthy(policy.mode_supported("adventure"))
        H.truthy(policy.mode_supported("deus"))
        H.truthy(policy.mode_supported("weave"))
        H.equal(policy.mode_supported("inn"), false)
        H.equal(policy.mode_supported("inn_deus"), false)
        H.equal(policy.mode_supported("versus"), false)
        H.equal(policy.mode_supported("tutorial"), false)
    end)

    H.test("GT #247 requires a live human and a free or native-bot slot", function()
        local base = {
            is_server = true,
            mode_key = "adventure",
            player_exists = true,
            is_bot = false,
            unit_alive = true,
            has_party_slot = true,
            num_used_slots = 3,
            num_slots = 4,
            has_profile = true,
            has_game_mode_api = true,
        }
        H.truthy(policy.validate_begin(base))

        local full = {}
        for k, v in pairs(base) do full[k] = v end
        full.num_used_slots = 4
        local ok, reason = policy.validate_begin(full)
        H.equal(ok, false)
        H.equal(reason, "party has no free or replaceable bot slot")

        full.has_displaceable_bot = true
        H.truthy(policy.validate_begin(full))

        local dead = {}
        for k, v in pairs(base) do dead[k] = v end
        dead.unit_alive = false
        H.equal(policy.validate_begin(dead), false)
    end)

    H.test("GT #247 authenticates requests to the VMF sender only", function()
        local ok, peer, local_id = policy.authenticate_request("peer-a", "peer-a", 1)
        H.truthy(ok)
        H.equal(peer, "peer-a")
        H.equal(local_id, 1)

        ok = policy.authenticate_request("peer-a", "peer-b", 1)
        H.equal(ok, false)
        ok = policy.authenticate_request("peer-a", "peer-a", 2)
        H.equal(ok, false)
        ok = policy.authenticate_request(nil, nil, 1)
        H.equal(ok, false)
    end)

    H.test("GT #247 accepts only an explicit boolean takeover intent", function()
        H.truthy(policy.validate_intent(true))
        H.truthy(policy.validate_intent(false))
        H.equal(policy.validate_intent(nil), false)
        H.equal(policy.validate_intent("false"), false)
        H.equal(policy.validate_intent(0), false)
    end)

    H.test("GT #247 production keeps the human identity and bounds transport", function()
        local runtime = read("_gt_ai_takeover.lua")
        local main = read("general_tweaker_dev.lua")

        H.truthy(runtime:find("gt-247-keep-slot-v1", 1, true))
        H.truthy(runtime:find("rpc_set_observer_camera", 1, true))
        H.truthy(runtime:find("game_mode.force_respawn", 1, true))
        H.truthy(runtime:find("_ai_restore_displaced_bot", 1, true))
        H.truthy(runtime:find("peer claim does not match sender", 1, true) == nil)
        H.truthy(runtime:find("gt_ai_toggle_result", 1, true))
        H.truthy(runtime:find("#reason > 120", 1, true))
        H.truthy(runtime:find("type(active) ~= \"boolean\"", 1, true))
        H.truthy(runtime:find("Despawn before changing cameras", 1, true))
        local reclaim_gate = assert(runtime:find("reclaim API unavailable", 1, true))
        local reclaim_remove = assert(runtime:find("pcall(_ai_remove_takeover_bot, saved)",
            reclaim_gate, true))
        H.truthy(reclaim_gate < reclaim_remove)
        H.equal(runtime:find("remove_peer_from_party", 1, true), nil)
        H.equal(runtime:find("remove_player", 1, true), nil)
        H.equal(runtime:find("unassign_profiles_of_peer", 1, true), nil)
        H.equal(runtime:find("set_override_player", 1, true), nil)
        H.truthy(main:find("mod.GT_AI_RPC_SCHEMA = 2", 1, true))
        H.truthy(main:find("mod._gt_ai_takeover_disabled         = false", 1, true))
    end)
end
