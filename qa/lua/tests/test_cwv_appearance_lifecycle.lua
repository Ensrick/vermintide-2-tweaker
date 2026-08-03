return function(H, repo_root)
    local policy_path = repo_root
        .. "/character_weapon_variants/scripts/mods/character_weapon_variants/_cwv_appearance_lifecycle.lua"
    local exact_path = repo_root
        .. "/character_weapon_variants/scripts/mods/character_weapon_variants/_cwv_exact_appearance.lua"
    local family_path = repo_root
        .. "/character_weapon_variants/scripts/mods/character_weapon_variants/_cwv_crowbill_family.lua"
    local main_path = repo_root
        .. "/character_weapon_variants/scripts/mods/character_weapon_variants/character_weapon_variants.lua"
    local Policy = assert(loadfile(policy_path))()
    local Exact = assert(loadfile(exact_path))()
    local CrowbillFamily = assert(loadfile(family_path))()

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

    H.test("CWV #476 partial publish never emits native records for absent slots", function()
        local sent = {}
        local lifecycle = Policy.new({
            resolve_local = function(slot)
                return slot and slot.exact or nil, slot and slot.base or nil
            end,
            resolve_remote = function() return nil, "unused" end,
            send = function(_, _, payload, edge)
                sent[#sent + 1] = { slot = payload.slot,
                    item_key = payload.item_key, edge = edge }
                return true
            end,
        })
        local plain = descriptor(nil)
        local reskinned = descriptor("selected_skin", "skin_right", "skin_left")
        local full = {
            slot_melee = { exact = plain, base = "vanilla_base" },
            slot_ranged = { exact = plain, base = "vanilla_ranged" },
        }
        H.equal(lifecycle:publish(full, "equip", "others", false), 2)

        -- Vanilla _spawn_resynced_loadout resyncs ONE slot. A partial publish
        -- of the changed melee slot must emit exactly that slot and NO
        -- explicit native (item_key == "") record for the untouched ranged
        -- slot - the pre-fix complete-snapshot iteration reverted the other
        -- slot to base on every remote for the session (#476 Defect B).
        sent = {}
        local single = { slot_melee = { exact = reskinned, base = "vanilla_base" } }
        H.equal(lifecycle:publish(
            single, "spawn_resynced_loadout", "others", false, true), 1)
        H.equal(#sent, 1)
        H.equal(sent[1].slot, "slot_melee")
        H.truthy(sent[1].item_key ~= "",
            "partial publish emitted an empty (native) record")

        -- The untouched slot's dedupe signature must survive the partial
        -- publish: a follow-up COMPLETE snapshot with the same ranged
        -- identity re-sends nothing. Pre-fix, the partial publish pinned a
        -- false native signature for slot_ranged, so this complete publish
        -- would have had to re-send it after remotes already reverted.
        full.slot_melee = { exact = reskinned, base = "vanilla_base" }
        H.equal(lifecycle:publish(full, "equip", "others", false), 0)

        -- Complete snapshots keep clear-to-native semantics: an absent slot
        -- in a COMPLETE publish still emits the explicit native record.
        full.slot_melee = nil
        sent = {}
        H.equal(lifecycle:publish(full, "unequip", "others", false), 1)
        H.equal(sent[1].slot, "slot_melee")
        H.equal(sent[1].item_key, "")
    end)

    H.test("CWV #660 hot-join identity retry is acknowledged and bounded", function()
        local sent = {}
        local d = descriptor(nil)
        local lifecycle = Policy.new({
            resolve_local = function(slot)
                return slot and slot.exact or nil, slot and slot.base or nil
            end,
            resolve_remote = function() return descriptor(nil) end,
            send = function(recipient, schema, payload, edge)
                sent[#sent + 1] = { recipient, schema, payload.slot, edge }
                return true
            end,
        })
        local slots = {
            slot_melee = { exact = d, base = "vanilla_base" },
            slot_ranged = { base = "vanilla_ranged" },
        }

        H.equal(lifecycle:track_delivery("peer-join", slots, "hot_join_retry"), 1)
        H.equal(lifecycle:pending_delivery_count(), 1)
        H.equal(lifecycle:step_deliveries(Policy.RETRY_INTERVAL - 0.01), 0)
        H.equal(lifecycle:step_deliveries(0.01), 1)
        H.equal(#sent, 1)
        H.equal(sent[1][1], "peer-join")
        H.equal(sent[1][3], "slot_melee")

        local payload = assert(lifecycle:payload_for("slot_melee", slots.slot_melee))
        local ack = assert(lifecycle:ack_payload(payload))
        H.equal(ack.slot, Policy.ACK_SLOT)
        H.equal(lifecycle:accept_ack("wrong-peer", Policy.SCHEMA, ack), false)
        H.equal(lifecycle:accept_ack("peer-join", Policy.SCHEMA, ack), true)
        H.equal(lifecycle:accept_ack("peer-join", Policy.SCHEMA, ack), false)
        H.equal(lifecycle:pending_delivery_count(), 0)
        H.equal(lifecycle:step_deliveries(Policy.RETRY_INTERVAL), 0)
        H.equal(#sent, 1, "an acknowledged descriptor must not be retried")

        H.equal(lifecycle:track_delivery("peer-no-mod", slots, "hot_join_retry"), 1)
        for _ = 1, Policy.MAX_RETRY_ATTEMPTS do
            H.equal(lifecycle:step_deliveries(Policy.RETRY_INTERVAL), 1)
        end
        local final_sent, expired = lifecycle:step_deliveries(Policy.RETRY_INTERVAL)
        H.equal(final_sent, 0)
        H.equal(expired, 1)
        H.equal(lifecycle:pending_delivery_count(), 0)
        H.equal(#sent, 1 + Policy.MAX_RETRY_ATTEMPTS,
            "a peer without CWV must receive only the strict retry cap")
    end)

    H.test("CWV #660 delayed receiver readiness converges exactly once", function()
        local owner = descriptor("selected_skin", "skin_right", "skin_left")
        local sender, receiver
        local ready = false
        local attempts = 0
        local accepts = 0

        receiver = Policy.new({
            resolve_local = function() return nil, nil end,
            resolve_remote = function()
                return descriptor("selected_skin", "skin_right", "skin_left")
            end,
            send = function() return true end,
        })
        sender = Policy.new({
            resolve_local = function(slot)
                return slot and slot.exact or nil, slot and slot.base or nil
            end,
            resolve_remote = function() return nil, "unused" end,
            send = function(recipient, schema, payload)
                attempts = attempts + 1
                if ready then
                    local changed, exact = receiver:accept("owner-peer", schema, payload)
                    if changed and exact then accepts = accepts + 1 end
                    local ack = receiver:ack_payload(payload)
                    if ack then sender:accept_ack(recipient, schema, ack) end
                end
                -- This mirrors VMF accepting the sender call even when the
                -- joining peer's handler is not ready and delivery is lost.
                return true
            end,
        })
        local slots = {
            slot_melee = { exact = owner, base = "vanilla_base" },
        }

        H.equal(sender:track_delivery("joining-peer", slots, "hot_join_retry"), 1)
        for _ = 1, 49 do
            H.equal(sender:step_deliveries(0.01), 0,
                "per-frame stepping must not create per-frame traffic")
        end
        H.equal(attempts, 0)
        H.equal(sender:step_deliveries(0.01), 1)
        H.equal(attempts, 1, "first locally accepted send is dropped")
        H.equal(sender:pending_delivery_count(), 1)

        ready = true
        H.equal(sender:step_deliveries(Policy.RETRY_INTERVAL), 1)
        H.equal(attempts, 2)
        H.equal(accepts, 1)
        H.equal(sender:pending_delivery_count(), 0)
        local exact, state = receiver:descriptor(
            "owner-peer", "slot_melee", "vanilla_base")
        H.equal(state, "exact")
        H.equal(exact.fingerprint, owner.fingerprint)

        local payload = assert(sender:payload_for("slot_melee", slots.slot_melee))
        H.equal(receiver:accept("owner-peer", Policy.SCHEMA, payload), false,
            "duplicate delivery must be idempotent")
        H.equal(sender:step_deliveries(Policy.RETRY_INTERVAL), 0)
        H.equal(attempts, 2, "ACK must stop every later retry")
    end)

    H.test("CWV #401 #914 mission peer-ready pull is bounded and exact", function()
        local owner_descriptor = descriptor("selected_skin", "skin_right", "skin_left")
        local slots = {
            slot_melee = { exact = owner_descriptor, base = "vanilla_base" },
        }
        local requester, owner
        local owner_ready = false
        local request_attempts = 0
        local exact_replies = 0

        owner = Policy.new({
            resolve_local = function(slot)
                return slot and slot.exact or nil, slot and slot.base or nil
            end,
            resolve_remote = function() return nil, "unused" end,
            send = function(recipient, schema, payload)
                local changed, exact = requester:accept("owner-peer", schema, payload)
                H.truthy(changed, "peer-ready reply must update its exact slot state")
                if payload.item_key ~= "" then
                    exact_replies = exact_replies + 1
                    H.truthy(exact, "peer-ready exact slot must reconstruct exactly")
                    local ack = requester:ack_payload(payload)
                    H.truthy(ack and owner:accept_ack(recipient, schema, ack),
                        "peer-ready exact reply must use the existing ACK ledger")
                end
                return true
            end,
        })
        requester = Policy.new({
            resolve_local = function() return nil, nil end,
            resolve_remote = function()
                return descriptor("selected_skin", "skin_right", "skin_left")
            end,
            send = function(_, schema, payload)
                request_attempts = request_attempts + 1
                if owner_ready and owner:accept_request("joining-peer", schema, payload) then
                    H.equal(owner:track_delivery(
                        "joining-peer", slots, "peer_ready_reply"), 1)
                    H.equal(owner:publish(
                        slots, "peer_ready_reply", "joining-peer", true), 2)
                end
                return true
            end,
        })

        H.equal(requester:begin_request(1, "mission_transition_ready"), true)
        H.equal(request_attempts, 1, "first request is intentionally lost pre-ready")
        owner_ready = true
        H.equal(requester:step_request(Policy.RETRY_INTERVAL), 1)
        H.equal(exact_replies, 1)
        H.equal(owner:pending_delivery_count(), 0,
            "ACK must retire the direct peer-ready reply immediately")
        local exact, state = requester:descriptor(
            "owner-peer", "slot_melee", "vanilla_base")
        H.equal(state, "exact")
        H.equal(exact.fingerprint, owner_descriptor.fingerprint)

        -- The request itself remains capped because the requester does not know
        -- how many same-mod peers exist. Receiver generation dedupe prevents the
        -- later retries from multiplying direct replies.
        for _ = 3, Policy.MAX_RETRY_ATTEMPTS do
            requester:step_request(Policy.RETRY_INTERVAL)
        end
        local sent, expired = requester:step_request(Policy.RETRY_INTERVAL)
        H.equal(sent, 0)
        H.equal(expired, 1)
        H.equal(request_attempts, Policy.MAX_RETRY_ATTEMPTS)
        H.equal(exact_replies, 1)
        H.equal(owner:accept_request("joining-peer", Policy.SCHEMA, {
            slot = Policy.REQUEST_SLOT, generation = 1,
        }), false, "same request generation must remain coalesced")
        owner:clear_peer("joining-peer")
        H.equal(owner:accept_request("joining-peer", Policy.SCHEMA, {
            slot = Policy.REQUEST_SLOT, generation = 1,
        }), true, "peer teardown must clear request-generation ownership")
        H.equal(owner:accept_request("joining-peer", Policy.SCHEMA, {
            slot = Policy.REQUEST_SLOT,
            generation = Policy.MAX_REQUEST_GENERATION + 1,
        }), false, "request generations must stay wire-bounded")
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

    H.test("CWV #604 skinless Dawi model survives exact remote reconstruction", function()
        local model = assert(CrowbillFamily.model_for_variant("cwv_dr_dawi_crowbill"))
        local function dawi_descriptor()
            return assert(Exact.resolve_spawn_descriptor({
                provider = "cwv",
                variant = {
                    item_key = "cwv_dr_dawi_crowbill",
                    base_weapon = CrowbillFamily.SOURCE_ITEM,
                    right_hand_unit = model.right_hand_unit,
                },
                base = { right_hand_unit = CrowbillFamily.PLACEHOLDER_UNIT },
            }))
        end
        local owner = dawi_descriptor()
        H.equal(owner.skin, nil)
        H.equal(owner.right_hand_unit, model.right_hand_unit)

        local lifecycle = Policy.new({
            resolve_local = function() return owner, CrowbillFamily.SOURCE_ITEM end,
            resolve_remote = function() return dawi_descriptor() end,
            send = function() return true end,
        })
        local payload = assert(lifecycle:payload_for("slot_melee", {}))
        H.equal(payload.item_key, "cwv_dr_dawi_crowbill")
        H.equal(payload.base_item_key, CrowbillFamily.SOURCE_ITEM)
        H.equal(payload.skin_key, "")
        H.equal(payload.right_hand_unit, nil,
            "custom unit path must be reconstructed locally, never transported")

        local changed, remote, reason = lifecycle:accept(
            "peer-dawi", Policy.SCHEMA, payload)
        H.equal(changed, true)
        H.equal(reason, "exact")
        H.equal(remote.right_hand_unit, model.right_hand_unit)
        H.equal(remote.fingerprint, owner.fingerprint)
    end)

    H.test("CWV #719 skinless Imperial Crowbill survives exact remote reconstruction", function()
        local model = assert(CrowbillFamily.model_for_variant("cwv_es_imperial_crowbill"))
        local cim_item = {
            name = CrowbillFamily.SOURCE_ITEM,
            mod_data = {
                backend_id = "rt719-guid-shaped-backend",
                cwv_key = "cwv_es_imperial_crowbill",
            },
        }
        H.equal(cim_item.name, CrowbillFamily.SOURCE_ITEM)
        H.equal(cim_item.mod_data.cwv_key, "cwv_es_imperial_crowbill")
        local function imperial_descriptor()
            return assert(Exact.resolve_spawn_descriptor({
                provider = "cwv",
                variant = {
                    item_key = "cwv_es_imperial_crowbill",
                    base_weapon = CrowbillFamily.SOURCE_ITEM,
                    right_hand_unit = model.right_hand_unit,
                },
                base = { right_hand_unit = CrowbillFamily.PLACEHOLDER_UNIT },
            }))
        end
        local owner = imperial_descriptor()
        H.equal(owner.skin, nil)
        H.equal(owner.right_hand_unit, model.right_hand_unit)
        H.truthy(owner.right_hand_unit ~= CrowbillFamily.PLACEHOLDER_UNIT,
            "Imperial descriptor must not collapse to Sienna's donor Crowbill")

        local lifecycle = Policy.new({
            resolve_local = function(slot)
                local item = slot and slot.item_data
                if not (item and item.mod_data
                        and item.mod_data.cwv_key == "cwv_es_imperial_crowbill") then
                    return nil, item and item.name
                end
                return owner, item.name
            end,
            resolve_remote = function() return imperial_descriptor() end,
            send = function() return true end,
        })
        local payload = assert(lifecycle:payload_for("slot_melee", { item_data = cim_item }))
        H.equal(payload.item_key, "cwv_es_imperial_crowbill")
        H.equal(payload.base_item_key, CrowbillFamily.SOURCE_ITEM)
        H.equal(payload.skin_key, "")
        H.equal(payload.right_hand_unit, nil,
            "custom unit path must be reconstructed locally, never transported")

        local changed, remote, reason = lifecycle:accept(
            "peer-imperial", Policy.SCHEMA, payload)
        H.equal(changed, true)
        H.equal(reason, "exact")
        H.equal(remote.right_hand_unit, model.right_hand_unit)
        H.equal(remote.fingerprint, owner.fingerprint)

        local duplicate = lifecycle:accept("peer-imperial", Policy.SCHEMA, payload)
        H.equal(duplicate, false,
            "duplicate Imperial identity must not schedule another husk rebuild")
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
            '"spawn_resynced_loadout", false, nil, true)',
            'lifecycle:track_delivery(peer_id, slots, "hot_join_retry")',
            'lifecycle:begin_request(generation',
            'lifecycle:accept_request(sender_peer_id, schema, payload)',
            'lifecycle:track_delivery(sender_peer_id,',
            '"peer_ready_reply", true, sender_peer_id)',
            'lifecycle:step_request(dt)',
            'lifecycle:step_deliveries(dt)',
            'payload.slot == _om.appearance_lifecycle_policy.ACK_SLOT',
            '_om.cosmetic_skin_wire.with_safe_slots',
            'mod._cwv_skin_wire_surfaces.vanilla_skin_replay_retired = true',
            'lifecycle=world_spawn adapter=%s',
            'issue660_world_identity_lifecycle_replay',
        }) do
            H.truthy(source:find(marker, 1, true), "missing #660 lifecycle route: " .. marker)
        end
        H.equal(source:find('NetworkLookup.item_names[payload.item_key]', 1, true), nil,
            "modded identity leaked into vanilla item lookup")
        H.equal(source:find('NetworkLookup.weapon_skins[payload.skin_key]', 1, true), nil,
            "modded skin identity leaked into vanilla skin lookup")
        H.equal(source:find('_replay_cwv_skins_after_parity', 1, true), nil,
            "numeric CWV skin replay re-entered the vanilla equipment channel")
    end)
end
