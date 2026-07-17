return function(H, repo_root)
    local policy_path = repo_root
        .. "/character_weapon_variants/scripts/mods/character_weapon_variants/_cwv_appearance_lifecycle.lua"
    local exact_path = repo_root
        .. "/character_weapon_variants/scripts/mods/character_weapon_variants/_cwv_exact_appearance.lua"
    local main_path = repo_root
        .. "/character_weapon_variants/scripts/mods/character_weapon_variants/character_weapon_variants.lua"
    local Policy = assert(loadfile(policy_path))()
    local Exact = assert(loadfile(exact_path))()

    local function read(path)
        local file = assert(io.open(path, "rb"))
        local source = file:read("*a")
        file:close()
        return source
    end

    local function descriptor(skin, right, left)
        return assert(Exact.resolve_spawn_descriptor({
            provider = "cwv",
            instance_id = "owner-instance-1",
            variant = {
                item_key = "cwv_exact",
                base_weapon = "vanilla_base",
                right_hand_unit = "variant_right",
                left_hand_unit = "variant_left",
            },
            base = {
                right_hand_unit = "base_right",
                left_hand_unit = "base_left",
            },
            explicit_skin = skin,
            weapon_skins = skin and {
                [skin] = {
                    right_hand_unit = right,
                    left_hand_unit = left,
                },
            } or {},
        }))
    end

    H.test("CWV #660 exact descriptor owns provider item base skin and models", function()
        local d = descriptor("selected_skin", "skin_right", "skin_left")
        H.equal(d.provider, "cwv")
        H.equal(d.instance_id, "owner-instance-1")
        H.equal(d.variant_key, "cwv_exact")
        H.equal(d.base_item_key, "vanilla_base")
        H.equal(d.skin, "selected_skin")
        H.equal(d.right_hand_unit, "skin_right")
        H.equal(d.left_hand_unit, "skin_left")
        H.equal(d.fingerprint:sub(1, 3), "a1:")
        H.equal(#d.fingerprint, 19)
    end)

    H.test("CWV #660 lifecycle publishes two bounded slots and coalesces duplicates", function()
        local sent = {}
        local d = descriptor(nil)
        local lifecycle = Policy.new({
            resolve_local = function(slot)
                return slot and slot.exact or nil, slot and slot.base or nil
            end,
            resolve_remote = function() return d end,
            send = function(recipient, schema, payload, edge)
                sent[#sent + 1] = { recipient, schema, payload.slot, edge }
                return true
            end,
        })
        local slots = {
            slot_melee = { exact = d, base = "vanilla_base" },
            slot_ranged = { base = "vanilla_ranged" },
            slot_hat = { exact = d, base = "ignored" },
        }
        H.equal(lifecycle:publish(slots, "equip", "others", false), 2)
        H.equal(lifecycle:publish(slots, "equip", "others", false), 0)
        H.equal(lifecycle:publish(slots, "mission_transition", "others", true), 2)
        H.equal(lifecycle:publish(slots, "hot_join", "peer-b", true), 2)
        H.equal(#sent, 6)
        H.equal(sent[5][1], "peer-b")
        H.equal(sent[5][4], "hot_join")
    end)

    H.test("CWV #660 receiver reconstructs locally and replays once per fingerprint", function()
        local d = descriptor("selected_skin", "skin_right", "skin_left")
        local lifecycle = Policy.new({
            resolve_local = function() return d, "vanilla_base" end,
            resolve_remote = function() return descriptor("selected_skin", "skin_right", "skin_left") end,
            send = function() return true end,
        })
        local payload = assert(lifecycle:payload_for("slot_melee", { exact = d }))
        local changed, received, reason = lifecycle:accept("peer-a", Policy.SCHEMA, payload)
        H.equal(changed, true)
        H.equal(reason, "exact")
        H.equal(received.fingerprint, d.fingerprint)
        H.equal(lifecycle:accept("peer-a", Policy.SCHEMA, payload), false)
        local stored, state = lifecycle:descriptor("peer-a", "slot_melee", "vanilla_base")
        H.equal(state, "exact")
        H.equal(stored.fingerprint, d.fingerprint)
    end)

    H.test("CWV #660 explicit native identity suppresses stale base-career guesses", function()
        local lifecycle = Policy.new({
            resolve_local = function(slot) return nil, slot.base end,
            resolve_remote = function() error("native payload must not resolve a mod descriptor") end,
            send = function() return true end,
        })
        local payload = lifecycle:payload_for("slot_melee", { base = "shared_base" })
        H.equal(payload.item_key, "")
        H.equal(payload.base_item_key, "shared_base")
        H.equal(lifecycle:accept("peer-native", Policy.SCHEMA, payload), true)
        local got, state = lifecycle:descriptor("peer-native", "slot_melee", "shared_base")
        H.equal(got, nil)
        H.equal(state, "native")
    end)

    H.test("CWV #660 provider drift clears stale exact identity and fails closed", function()
        local d = descriptor(nil)
        local lifecycle = Policy.new({
            resolve_local = function() return d, "vanilla_base" end,
            resolve_remote = function(payload)
                if payload.fingerprint == d.fingerprint then return descriptor(nil) end
                return nil, "provider_missing"
            end,
            send = function() return true end,
        })
        local payload = lifecycle:payload_for("slot_melee", {})
        H.equal(lifecycle:accept("peer-a", Policy.SCHEMA, payload), true)
        payload.fingerprint = payload.fingerprint .. "-drift"
        H.equal(lifecycle:accept("peer-a", Policy.SCHEMA, payload), true)
        local got, state = lifecycle:descriptor("peer-a", "slot_melee", "vanilla_base")
        H.equal(got, nil)
        H.equal(state, "unavailable")
    end)

    H.test("CWV #660 schema and base mismatches cannot reuse prior appearance", function()
        local d = descriptor(nil)
        local lifecycle = Policy.new({
            resolve_local = function() return d, "vanilla_base" end,
            resolve_remote = function() return descriptor(nil) end,
            send = function() return true end,
        })
        local payload = lifecycle:payload_for("slot_melee", {})
        lifecycle:accept("peer-a", Policy.SCHEMA, payload)
        local _, stale = lifecycle:descriptor("peer-a", "slot_melee", "other_base")
        H.equal(stale, "stale_base")
        lifecycle:accept("peer-a", Policy.SCHEMA - 1, payload)
        local got, state = lifecycle:descriptor("peer-a", "slot_melee", "vanilla_base")
        H.equal(got, nil)
        H.equal(state, "unavailable")
    end)

    H.test("CWV #660 world lifecycle adapters are bounded and vanilla-wire safe", function()
        local source = require("cwv_source").combined(repo_root)
        for _, marker in ipairs({
            '_om.appearance_lifecycle_policy = mod:dofile',
            '_om._cwv_resolve_world_descriptor = function',
            '_om._appearance_husk_wield_context = {',
            '_om._husk_identity_descriptor',
            '_send_identity_slots(slots, "hot_join_sync", true, peer_id)',
            'lifecycle=world_spawn adapter=%s',
            'issue660_world_identity_lifecycle_replay',
        }) do
            H.truthy(source:find(marker, 1, true), "missing #660 lifecycle route: " .. marker)
        end
        H.equal(source:find('NetworkLookup.item_names[payload.item_key]', 1, true), nil,
            "modded identity leaked into vanilla item lookup")
        H.equal(source:find('NetworkLookup.weapon_skins[payload.skin_key]', 1, true), nil,
            "modded skin identity leaked into vanilla skin lookup")
    end)
end
