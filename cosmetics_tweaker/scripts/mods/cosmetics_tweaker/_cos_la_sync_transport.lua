-- _cos_la_sync_transport.lua - the cos_la_* peer-sync transport.
--
-- RESPONSIBILITY
-- Owns the wire for LA (Loremaster's Armoury) appearance state: getting a local
-- appearance change onto every other machine, and turning an inbound message
-- back into an authoritative entry in the synced store. One responsibility, one
-- RPC family (`cos_la_apply`, `cos_la_apply_req`, `cos_la_state_req`,
-- `cos_la_state_ack`), four concerns that cannot be separated:
--
--   * WHO - the peer-identity layer (`_host_peer_id`, `_local_peer_id_quick`,
--     `_is_local_server`, `_wearer_unit_for_peer`, `_local_player_peer_id`,
--     `mod._la_career_for_unit`). Every routing decision this file makes is a
--     question about identity: am I the host, who is the wearer, which career
--     is the wearer actually playing. The host/local resolution deliberately
--     has multiple sources because `Managers.state.network` is nil in the keep
--     (v0.9.2 / v0.9.3 hotfixes), and both the send and the receive halves
--     depend on getting the SAME answer.
--
--   * SEND - `_send_la_apply`, `mod._send_la_revert` and
--     `mod._send_offhand_mesh`. Three payload shapes (apply carries an
--     `armoury_key`, revert carries `revert = true` and none, the vanilla
--     offhand mesh carries `offhand_unit`), one routing rule: host
--     short-circuits and broadcasts, client requests the host, and an emit with
--     no resolvable host is queued.
--
--   * QUEUE - `_last_emit_at` / `_EMIT_DEDUP_WINDOW` (the 0.5s coalescing
--     window that stops four call sites emitting the same equip four times) and
--     `_drain_deferred_la_emits` (the 300s-TTL retry the entry's mod.update
--     ticks). Both are shared by all three senders.
--
--   * RECEIVE - the four `mod:network_register` handlers, the host-authoritative
--     validate + record + rebroadcast, the hot-join state pull, and the deferred
--     peer purge (`PlayerManager.remove_player` / `add_remote_player` +
--     `mod._la_tick_peer_purges`).
--
-- These travel together because they share mutable private state that exists
-- for no other reason. `_last_emit_at` is written by all three senders AND
-- swept per-peer by the purge tick. The deferred-emit queue is appended by all
-- three senders and drained by one function that must re-derive host identity.
-- The receivers reuse the senders' own routing (`mod._store_offhand_mesh_recv`
-- is called both by the local host short-circuit and by the broadcast handler)
-- and every one of them re-asks the identity layer the same questions. Split at
-- any of the four seams and a mutable dedup table, a queue, or the host
-- predicate becomes shared entry state with two owners.
--
-- Extracted VERBATIM from cosmetics_tweaker.lua (entry lines 2378-2881 and
-- 3192-3697 at b320920d) with no behaviour change. NO original statement was
-- modified: the move adds THREE lines and changes none, each marked DEVIATION
-- inline and described under ENTRY-OWNED STATE below. mod:dofile is not a
-- singleton, so the entry calls `install` EXACTLY once and `install_receivers`
-- EXACTLY once (the latter is asserted, because that phase registers).
--
-- INSTALL POSITION (two phases, one owner)
-- The entry's historical order interleaves this transport with code that is not
-- part of it: the LA spawn monitor, `_resolve_la_variant`,
-- `_la_chars_compatible`, `_purge_stale_peer_slot`, the
-- SimpleHuskInventoryExtension.init hook_safe and the two apply/replay runtime
-- installs all sit BETWEEN the send half and the receive half. Rather than
-- reorder the entry, the owner installs in two phases at the two exact line
-- positions the moved blocks used to start:
--
--   `install(mod, deps)`      at former entry line 2378. Defines the identity,
--                             send and queue layers. Registers NOTHING - no
--                             mod:hook, mod:hook_safe, mod:hook_origin,
--                             mod:command, mod:network_register or mod:dofile -
--                             so this phase cannot move a registration even in
--                             principle.
--   `owner.install_receivers()` at former entry line 3192. Runs the six
--                             registrations (4 network_register + the
--                             PlayerManager remove_player / add_remote_player
--                             hook_safe pair) in their original order, at the
--                             original point, after `_cos_la_apply_runtime` has
--                             published `mod._la_reconcile` /
--                             `mod._la_apply_revert_recv` and after
--                             `_cos_la_replay_runtime` has published
--                             `mod._cos_replay`, exactly as before.
--
-- Mod-wide registration cardinality AND order are therefore unchanged, and the
-- receive half still closes over the send half's locals (`_last_emit_at`,
-- `_wearer_unit_for_peer`, `_host_peer_id`, ...) through the same lexical
-- nesting it had in the entry - which is why `install_receivers` is a closure
-- built inside `install` and not a second top-level function.
--
-- ENTRY-OWNED STATE
--   deps.get_la_pending_apply
--     A late-binding accessor, not a value. `_la_pending_apply` is the LA retry
--     queue and its drain sites REBIND it (`_la_pending_apply = kept`) rather
--     than mutating in place: one drain is in the entry's mod.update, another is
--     inside `_cos_la_apply_runtime`, which already takes the same getter plus a
--     setter for that reason. The `cos_la_apply` receiver only APPENDS, so it
--     needs the getter alone; it is resolved at the exact statement that used to
--     perform the inline read.
--   deps.la_equips_by_peer
--     By value, and provably safe. The synced store is declared `= {}` at entry
--     line 1376 and reassigned exactly once, at FILE SCOPE (entry line 2365,
--     `_la_equips_by_peer = _la_equips_by_peer or {}`), which cannot change the
--     identity because the left side is already a truthy table. That statement
--     executes ABOVE this install call, so the table captured here is the final
--     one - the same single-assignment proof `_cos_la_apply_runtime`,
--     `_cos_la_replay_runtime` and `_cos_attachment_spawn_sync` already use.
--   deps.glow_by_peer
--     By value. The entry binds `local _glow_by_peer = mod._glow_by_peer` once
--     (entry line 400) after `_cos_glow` has initialised it, and never rebinds.
--     The hot-join state-pull reply reads it; the purge tick writes through
--     `mod._glow_by_peer` exactly as it did before.
--   Everything else in deps
--     By value. Each is a `local function` or a module handle bound above the
--     install call and never reassigned anywhere in the entry (verified by a
--     file-scope assignment scan, not by eye).
--
-- NOT OWNED HERE (deliberate)
--   The three OTHER net-safe substitution surfaces stay in the entry, because
--   they are vanilla-RPC substitution, not this mod's own channel:
--   `_net_safe_hook_status`, `_la_substitute_name`, the CosmeticUtils
--   `update_cosmetic_slot` hook and the LoadoutUtils `sync_loadout_slot` hook.
--   `_la_equips_by_peer` itself, `_la_pending_apply`, and the
--   `CUSTOM_ILLUSION_SYNC` install (which consumes `mod._send_offhand_mesh`
--   published here) also stay outside this transport owner. The LA spawn
--   monitor, remote wield transaction, and attachment residency seam belong to
--   `_cos_la_husk_identity_runtime`, `_cos_husk_wield_runtime`, and
--   `_cos_spawn_boundary`, respectively.
--
-- Consumed via: two ordered calls at the two former block positions. Exports
-- stay on `mod` (`_la_career_for_unit`, `_drain_deferred_la_emits`,
-- `_send_la_revert`, `_store_offhand_mesh_recv`, `_send_offhand_mesh`,
-- `_la_tick_peer_purges`) plus a returned table the entry re-localizes the five
-- peer-identity helpers and `_send_la_apply` from, so every existing consumer -
-- `_cos_offhand_commit_policy`, `_cos_attachment_spawn_sync`,
-- `_cos_la_apply_runtime`, `_cos_la_replay_runtime`, `_cos_glow_transport`,
-- `_cos_runtime_checks` and the entry's own mod.update - resolves them exactly
-- as before.

local LaSyncTransport = {}

function LaSyncTransport.install(mod, deps)
    deps = deps or {}

    local COS_RPC_SCHEMA     = assert(deps.rpc_schema, "rpc_schema is required")
    local LA_BRIDGE          = assert(deps.la_bridge, "la_bridge is required")
    local LA_PERSIST         = assert(deps.la_persistence, "la_persistence is required")
    local LA_REPLAY_POLICY   = assert(deps.la_replay_policy, "la_replay_policy is required")
    local PROBE              = deps.probe
    local _cos574_log        = assert(deps.glow_log, "glow_log is required")
    local _dbg               = assert(deps.dbg, "dbg is required")
    local _dbg_alert         = assert(deps.dbg_alert, "dbg_alert is required")
    local _glow_by_peer      = assert(deps.glow_by_peer, "glow_by_peer is required")
    local _la_equips_by_peer = assert(deps.la_equips_by_peer, "la_equips_by_peer is required")
    local _local_player_safe = assert(deps.local_player_safe, "local_player_safe is required")
    local _trace             = assert(deps.trace, "trace is required")

    -- The rebound LA retry queue crosses the chunk boundary as a late-binding
    -- accessor, never as an install-time value. See ENTRY-OWNED STATE above.
    local _get_la_pending_apply = assert(deps.get_la_pending_apply, "get_la_pending_apply is required")

    -- DEVIATION (#1159): forward declaration. In the entry `_send_la_apply` was
    -- declared `local` ~1700 lines above its assignment, so the lexically
    -- earlier CosmeticUtils hook could reach it, and the statement below is the
    -- plain assignment that filled it in. Re-declaring it here keeps that
    -- statement byte-identical instead of turning it into a global write; the
    -- entry fills its own forward-declared local from `owner.send_la_apply`.
    local _send_la_apply

    -- v0.9.3: multi-source host_peer_id resolution.
    -- `Managers.state.network.server_peer_id` is the most authoritative source,
    -- but it's only wired up after mission load — in keep / lobby / pre-mission
    -- it's nil. Symptom from PC-A→PC-B test 2026-05-21 17:21: user joined PC-B's
    -- lobby as client, equipped 17 cosmetics in keep, every emit hit
    -- `(no host peer_id yet)` and deferred. Drain only fired 102s later when
    -- mission load finally populated state.network; 11/17 entries had timed out
    -- by then.
    -- The chat manager stores host_peer_id much earlier (foundation/scripts/
    -- managers/chat/chat_manager.lua:412-417 `ChatManager.setup_network_context`).
    -- Fall back to it so emits during keep / lobby see the host immediately.
    local function _host_peer_id()
        local nm = Managers and Managers.state and Managers.state.network
        if nm and nm.server_peer_id then return nm.server_peer_id end
        local cm = Managers and Managers.chat
        if cm and cm.host_peer_id then return cm.host_peer_id end
        return nil
    end

    local function _local_peer_id_quick()
        local pm = Managers and Managers.player
        local lp = _local_player_safe(pm)
        return lp and lp.peer_id or nil
    end

    -- v0.9.2-hotfix: robust host detection. Previously checked only
    -- `Managers.player.is_server == true`, which is transiently nil during state
    -- transitions AND is unreliable in some keep contexts where the user IS
    -- hosting a lobby but the field isn't set yet. Symptom in user's log
    -- (console-2026-05-21-03.33.15): user was server (`I am server` at line 3198)
    -- but ALL cos_la_apply emits hit the client branch and got DEFERRED because
    -- both this check AND the host_peer_id lookup returned falsy at emit time.
    -- New check: ALSO compare the local peer_id to the network's server_peer_id.
    -- If they match, we're hosting regardless of the player_manager flag.
    local function _is_local_server()
        -- Primary signal: vanilla's own flag (works in mission + most keep paths).
        if Managers and Managers.player and Managers.player.is_server == true then
            return true
        end
        -- Fallback signal: server_peer_id matches our peer_id. Catches the keep
        -- pre-mission window where Managers.player.is_server is nil but the
        -- network manager has already elected us host.
        local host = _host_peer_id()
        local local_peer = _local_peer_id_quick()
        return host ~= nil and local_peer ~= nil and host == local_peer
    end

    local function _wearer_unit_for_peer(wearer_peer_id)
        if not wearer_peer_id then return nil end
        local pm = Managers and Managers.player
        if not pm then return nil end
        -- v0.9.69-dev (#268, I4 targeting): resolve the HUMAN player at the peer.
        -- The old first-alive sweep over players_at_peer could return a BOT's
        -- unit on a host peer (bots share the host's peer_id at local_player_id
        -- 2..4; pairs order is arbitrary), sending a wearer's cosmetic onto a
        -- bot. player_from_peer_id defaults local_player_id=1 = the human
        -- (player_manager.lua:463-470) and is nil-safe.
        if pm.player_from_peer_id then
            local p = pm:player_from_peer_id(wearer_peer_id)
            if p and p.player_unit and Unit.alive(p.player_unit) then
                return p.player_unit
            end
        end
        -- Fallback sweep (older API shape / early-spawn window): humans only.
        local players = pm.players_at_peer and pm:players_at_peer(wearer_peer_id)
        if not players then return nil end
        for _, p in pairs(players) do
            if p.player_unit and Unit.alive(p.player_unit)
                and (not p.is_player_controlled or p:is_player_controlled()) then
                return p.player_unit
            end
        end
        return nil
    end

    local function _local_player_peer_id()
        local pm = Managers and Managers.player
        local lp = _local_player_safe(pm)
        return lp and lp.peer_id
    end

    mod._la_career_for_unit = function(unit)
        return mod._cos_husk_identity.career_for_unit(
            unit, ScriptUnit, Managers, LA_PERSIST)
    end

    -- v0.9.0-dev: emit dedup. CosmeticUtils.update_cosmetic_slot, PUAE
    -- .game_object_initialized, PUAE.spawn_resynced_loadout, and
    -- AttachmentUtils.hot_join_sync all call _send_la_apply for the same
    -- equip event; receivers got 3-4 cos_la_apply messages per change, which
    -- caused "Slot is not empty" errors in the create_attachment receiver and
    -- visible flicker on peers. Suppress duplicates of the same
    -- (wearer_peer, slot, kind, armoury_key) within a short window.
    local _last_emit_at = {}
    local _EMIT_DEDUP_WINDOW = 0.5

    -- Client-facing emit function (used by every equip call site). Routes via
    -- the host so the resulting apply is server-broadcast and consistent across
    -- peers. If we ARE the host, short-circuits the round-trip.
    _send_la_apply = function(unit, slot_name, kind, armoury_key, vanilla_key, hand_field)
        if not (unit and Unit.alive(unit)) then return false end
        if not (slot_name and kind and armoury_key) then return false end
        -- v0.9.9.4-dev: hand_field is optional, defaults to "left_hand_unit"
        -- (legacy behavior — only relevant to kind="offhand"/"illusion"). hat
        -- and armor paths ignore it.
        if (kind == "offhand" or kind == "illusion") and not hand_field then
            hand_field = "left_hand_unit"
        end

        local wearer_peer = nil
        local pm = Managers and Managers.player
        if pm and pm.owner then
            local owner = pm:owner(unit)
            wearer_peer = owner and owner.peer_id or nil
        end
        wearer_peer = wearer_peer or _local_player_peer_id()
        if not wearer_peer then return false end
        local wearer_career = mod._la_career_for_unit(unit)
        if not wearer_career then
            if printf then printf("[cos:698] EMIT SKIP wearer=%s slot=%s kind=%s reason=career-unproven",
                tostring(wearer_peer), tostring(slot_name), tostring(kind)) end
            return false
        end

        -- v0.9.9.4-dev: dedup key includes hand_field so the same shield/weapon
        -- equipped under different hand picks doesn't suppress legitimate
        -- second-hand emits within the 0.5s window.
        local dedup_key = wearer_peer .. "|" .. tostring(wearer_career) .. "|"
            .. tostring(slot_name) .. "|" .. tostring(kind) .. "|"
            .. tostring(armoury_key) .. "|" .. tostring(hand_field)
        local now = os.clock()
        local prev = _last_emit_at[dedup_key]
        if prev and (now - prev) < _EMIT_DEDUP_WINDOW then
            return true, "coalesced"  -- a matching emit was already accepted
        end
        _last_emit_at[dedup_key] = now

        if _is_local_server() then
            -- Record + broadcast directly. Host's own broadcast loops back to
            -- itself via "all"; the cos_la_apply receiver applies locally.
            _la_equips_by_peer[wearer_peer] = _la_equips_by_peer[wearer_peer] or {}
            _la_equips_by_peer[wearer_peer][slot_name] = mod._cos_husk_identity.new_entry(
                kind, armoury_key, vanilla_key, hand_field, wearer_career)
            _dbg("[cos_la_apply emit] HOST wearer=%s slot=%s kind=%s key=%s hand=%s",
                tostring(wearer_peer), tostring(slot_name), tostring(kind), tostring(armoury_key), tostring(hand_field))
            _trace("SYNC emit HOST->all wearer=%s slot=%s kind=%s armoury=%s hand=%s",
                tostring(wearer_peer), tostring(slot_name), tostring(kind), tostring(armoury_key), tostring(hand_field))
            -- v0.9.69-dev (Slice 0, I6): emit routing must be visible with mod
            -- logging OFF -- the #264-comment transport loss could not be pinned
            -- because this branch only logged via _dbg/_trace.
            if printf then printf("[la-state] EMIT host->all wearer=%s slot=%s kind=%s key=%s hand=%s",
                tostring(wearer_peer), tostring(slot_name), tostring(kind), tostring(armoury_key), tostring(hand_field)) end
            mod:network_send("cos_la_apply", "all", COS_RPC_SCHEMA, {
                wearer_peer_id = wearer_peer,
                slot           = slot_name,
                kind           = kind,
                armoury_key    = armoury_key,
                vanilla_key    = vanilla_key,
                hand_field     = hand_field,
                wearer_career  = wearer_career,
            })
            return true, "emitted"
        end

        -- Client: ask the host to fan out.
        -- v0.9.0.15-hotfix: VMF's `mod:network_send` does NOT accept the literal
        -- string "server" as a recipient — only "all"/"others"/"local" or a
        -- literal peer_id. The "server" string falls through to the else branch
        -- in VMF's convert_names_to_numbers, fails the _vmf_users lookup, and
        -- the packet is SILENTLY DROPPED. No error, no log, no wire activity.
        -- This bug had been live since v0.8.67-dev and only surfaced now because
        -- prior multiplayer tests had PC-A as HOST (which hits the `"all"`
        -- short-circuit above). When PC-A is a CLIENT (this session), the broken
        -- line fired every emit → host never received any cos_la_apply_req →
        -- entire LA sync chain dead. Fix: target the host's peer_id directly.
        -- Nil-guard for the level-transition window when server_peer_id may
        -- transiently be nil; pending queue retries pick it up.
        local host = _host_peer_id()
        if not host then
            -- v0.9.2-hotfix: ENQUEUE the deferred emit so it actually drains
            -- when the network state settles. Previously the request was logged
            -- and discarded — meaning a cosmetic equipped in keep before the
            -- network manager was fully wired never broadcast. User's log
            -- (console-2026-05-21-03.33.15) showed every emit DEFERRED, no
            -- broadcast, hat/shield invisible to other peers.
            mod._la_deferred_emits = mod._la_deferred_emits or {}
            mod._la_deferred_emits[#mod._la_deferred_emits + 1] = {
                wearer_peer  = wearer_peer,
                slot_name    = slot_name,
                kind         = kind,
                armoury_key  = armoury_key,
                vanilla_key  = vanilla_key,
                hand_field   = hand_field,
                wearer_career = wearer_career,
                queued_at    = os.clock(),
            }
            _dbg("[cos_la_apply emit] CLIENT->req DEFERRED+queued (no host peer_id yet) wearer=%s slot=%s key=%s queue_size=%d",
                tostring(wearer_peer), tostring(slot_name), tostring(armoury_key),
                #mod._la_deferred_emits)
            -- v0.9.69-dev (Slice 0, I6): the deferred branch is the prime suspect
            -- for the 79s-late mid-mission emits (#264 comment). printf so the
            -- user's log shows exactly when an emit queued instead of sending.
            if printf then printf("[la-state] EMIT client DEFERRED (no host yet) slot=%s kind=%s key=%s queue=%d",
                tostring(slot_name), tostring(kind), tostring(armoury_key), #mod._la_deferred_emits) end
            return true, "queued"
        end
        _dbg("[cos_la_apply emit] CLIENT->req wearer=%s slot=%s kind=%s key=%s hand=%s host=%s",
            tostring(wearer_peer), tostring(slot_name), tostring(kind), tostring(armoury_key), tostring(hand_field), tostring(host))
        _trace("SYNC emit CLIENT->req wearer=%s slot=%s kind=%s armoury=%s hand=%s host=%s",
            tostring(wearer_peer), tostring(slot_name), tostring(kind), tostring(armoury_key), tostring(hand_field), tostring(host))
        -- v0.9.69-dev (Slice 0, I6): pair this line with the host's [la-state]
        -- REQ-RECV line to pin a lost request to the wire (mid-mission transport
        -- loss, #264 comment).
        if printf then printf("[la-state] EMIT client->req host=%s slot=%s kind=%s key=%s hand=%s",
            tostring(host), tostring(slot_name), tostring(kind), tostring(armoury_key), tostring(hand_field)) end
        mod:network_send("cos_la_apply_req", host, COS_RPC_SCHEMA, {
            slot         = slot_name,
            kind         = kind,
            armoury_key  = armoury_key,
            vanilla_key  = vanilla_key,
            hand_field   = hand_field,
            wearer_career = wearer_career,
        })
        return true, "emitted"
    end

    -- v0.9.2-hotfix: deferred-emit drain. Called from mod.update every frame.
    -- Walks the queue, retries each entry. Entries older than 30s get dropped
    -- (assume the user changed their mind and re-equipped something else).
    local function _drain_deferred_la_emits()
        local q = mod._la_deferred_emits
        if not q or #q == 0 then return end
        -- Only attempt drain if we now have a host AND/OR are the host ourselves.
        local host = _host_peer_id()
        local am_host = _is_local_server()
        if not host and not am_host then return end

        local now = os.clock()
        local survivors = {}
        -- v0.9.3: bumped from 30s to 300s. PC-A→PC-B test 2026-05-21 17:21 showed
        -- emits queued at lobby-join sat for 102s before the drain finally fired,
        -- by which time the original 30s timeout had purged them. Lobby load can
        -- legitimately be that slow; 5min is a safer ceiling for "user changed
        -- their mind" purging without dropping live equips.
        for _, entry in ipairs(q) do
            if (now - entry.queued_at) > 300 then
                _dbg("[cos_la_apply drain] dropping stale entry wearer=%s slot=%s key=%s age=%.1fs",
                    tostring(entry.wearer_peer), tostring(entry.slot_name),
                    tostring(entry.armoury_key), now - entry.queued_at)
            else
                -- Re-emit. If we're now host, the broadcast fires directly. If
                -- we're now client with a known host, the request lands.
                -- v0.9.69-dev (#265 Slice 1): revert entries drain too -- delete
                -- instead of write, payload carries revert=true and no armoury_key.
                if entry.offhand_unit ~= nil then
                    -- v0.9.82-dev (#416): vanilla offhand mesh entry (its own payload
                    -- field; no armoury_key). Host stores + broadcasts; client requests.
                    if am_host then
                        mod._store_offhand_mesh_recv(entry.wearer_peer, entry.slot_name,
                            entry.hand_field, entry.offhand_unit)
                        mod:network_send("cos_la_apply", "all", COS_RPC_SCHEMA, {
                            wearer_peer_id = entry.wearer_peer, slot = entry.slot_name,
                            kind = "offhand", offhand_unit = entry.offhand_unit,
                            hand_field = entry.hand_field,
                        })
                    else
                        mod:network_send("cos_la_apply_req", host, COS_RPC_SCHEMA, {
                            slot = entry.slot_name, kind = "offhand",
                            offhand_unit = entry.offhand_unit, hand_field = entry.hand_field,
                        })
                    end
                    if printf then printf("[la-state] OFFHAND-MESH drain %s slot=%s hand=%s unit=%s (queued %.1fs)",
                        am_host and "host->all" or "client->req", tostring(entry.slot_name),
                        tostring(entry.hand_field), tostring(entry.offhand_unit), now - entry.queued_at) end
                elseif am_host then
                    if entry.revert then
                        if _la_equips_by_peer[entry.wearer_peer] then
                            _la_equips_by_peer[entry.wearer_peer][entry.slot_name] = nil
                        end
                    else
                        _la_equips_by_peer[entry.wearer_peer] = _la_equips_by_peer[entry.wearer_peer] or {}
                        _la_equips_by_peer[entry.wearer_peer][entry.slot_name] =
                            mod._cos_husk_identity.new_entry(entry.kind, entry.armoury_key,
                                entry.vanilla_key, entry.hand_field, entry.wearer_career)
                    end
                    mod:network_send("cos_la_apply", "all", COS_RPC_SCHEMA, {
                        wearer_peer_id = entry.wearer_peer,
                        slot           = entry.slot_name,
                        kind           = entry.kind,
                        revert         = entry.revert or nil,
                        armoury_key    = entry.armoury_key,
                        vanilla_key    = entry.vanilla_key,
                        hand_field     = entry.hand_field,
                        wearer_career  = entry.wearer_career,
                    })
                    _dbg("[cos_la_apply drain] HOST broadcast wearer=%s slot=%s key=%s (was queued %.1fs)",
                        tostring(entry.wearer_peer), tostring(entry.slot_name),
                        tostring(entry.armoury_key), now - entry.queued_at)
                    if printf then printf("[la-state] EMIT drain host->all wearer=%s slot=%s kind=%s key=%s revert=%s (queued %.1fs)",
                        tostring(entry.wearer_peer), tostring(entry.slot_name), tostring(entry.kind),
                        tostring(entry.armoury_key), tostring(entry.revert or false), now - entry.queued_at) end
                else
                    mod:network_send("cos_la_apply_req", host, COS_RPC_SCHEMA, {
                        slot         = entry.slot_name,
                        kind         = entry.kind,
                        revert       = entry.revert or nil,
                        armoury_key  = entry.armoury_key,
                        vanilla_key  = entry.vanilla_key,
                        hand_field   = entry.hand_field,
                        wearer_career = entry.wearer_career,
                    })
                    _dbg("[cos_la_apply drain] CLIENT->req sent wearer=%s slot=%s key=%s host=%s (was queued %.1fs)",
                        tostring(entry.wearer_peer), tostring(entry.slot_name),
                        tostring(entry.armoury_key), tostring(host), now - entry.queued_at)
                    if printf then printf("[la-state] EMIT drain client->req host=%s slot=%s kind=%s key=%s revert=%s (queued %.1fs)",
                        tostring(host), tostring(entry.slot_name), tostring(entry.kind),
                        tostring(entry.armoury_key), tostring(entry.revert or false), now - entry.queued_at) end
                end
                -- Drop entry from queue after successful re-emit.
            end
        end
        mod._la_deferred_emits = survivors
    end
    mod._drain_deferred_la_emits = _drain_deferred_la_emits

    -- v0.9.69-dev (#265, LA_SYNC_CORE_AUDIT Slice 1 / invariant I2): REVERT
    -- broadcast. Every prior emit path covered APPLY only; reverting to vanilla
    -- cleared local stores and sent NOTHING, so remote peers kept the stale LA
    -- cosmetic until disconnect (D2/D3 in the audit). A revert is a state change
    -- like any other: same routing as _send_la_apply (host short-circuit /
    -- client req / deferred queue), payload carries `revert = true` with NO
    -- armoury_key. Old-version peers drop the payload harmlessly at their
    -- `armoury_key` guard (schema unchanged). Attached to `mod` (not a local)
    -- so call sites lexically before this point can reach it at runtime and no
    -- top-level local is spent (200-local ceiling).
    mod._send_la_revert = function(unit, slot_name, kind, vanilla_key, hand_field)
        if not (unit and Unit.alive(unit)) then return end
        if not (slot_name and kind) then return end
        if (kind == "offhand" or kind == "illusion") and not hand_field then
            hand_field = "left_hand_unit"
        end
        local wearer_peer = nil
        local pm = Managers and Managers.player
        if pm and pm.owner then
            local owner = pm:owner(unit)
            wearer_peer = owner and owner.peer_id or nil
        end
        wearer_peer = wearer_peer or _local_player_peer_id()
        if not wearer_peer then return end
        local dedup_key = wearer_peer .. "|" .. tostring(slot_name) .. "|" .. tostring(kind) .. "|REVERT|" .. tostring(hand_field)
        local now = os.clock()
        local prev = _last_emit_at[dedup_key]
        if prev and (now - prev) < _EMIT_DEDUP_WINDOW then
            return
        end
        _last_emit_at[dedup_key] = now

        if _is_local_server() then
            if _la_equips_by_peer[wearer_peer] then
                _la_equips_by_peer[wearer_peer][slot_name] = nil
            end
            if printf then printf("[la-state] REVERT host->all wearer=%s slot=%s kind=%s (store entry cleared)",
                tostring(wearer_peer), tostring(slot_name), tostring(kind)) end
            mod:network_send("cos_la_apply", "all", COS_RPC_SCHEMA, {
                wearer_peer_id = wearer_peer,
                slot           = slot_name,
                kind           = kind,
                revert         = true,
                vanilla_key    = vanilla_key,
                hand_field     = hand_field,
            })
            return
        end

        local host = _host_peer_id()
        if not host then
            mod._la_deferred_emits = mod._la_deferred_emits or {}
            mod._la_deferred_emits[#mod._la_deferred_emits + 1] = {
                wearer_peer  = wearer_peer,
                slot_name    = slot_name,
                kind         = kind,
                revert       = true,
                vanilla_key  = vanilla_key,
                hand_field   = hand_field,
                queued_at    = os.clock(),
            }
            if printf then printf("[la-state] REVERT client DEFERRED (no host yet) slot=%s kind=%s queue=%d",
                tostring(slot_name), tostring(kind), #mod._la_deferred_emits) end
            return
        end
        if printf then printf("[la-state] REVERT client->req host=%s slot=%s kind=%s",
            tostring(host), tostring(slot_name), tostring(kind)) end
        mod:network_send("cos_la_apply_req", host, COS_RPC_SCHEMA, {
            slot         = slot_name,
            kind         = kind,
            revert       = true,
            vanilla_key  = vanilla_key,
            hand_field   = hand_field,
        })
    end

    -- v0.9.82-dev (#416): receiver-side store for a VANILLA offhand mesh sync. Writes
    -- the parallel _offhand_mesh_by_peer store, enforces mutual exclusion with the LA
    -- store for the SAME (wearer, slot, hand), and forces a re-render on the wearer's
    -- unit so the swap shows without the wearer manually re-wielding. `unit_path` = a
    -- concrete unit path (STORE) or "" (CLEAR = revert that hand to the base offhand).
    -- Called on every peer (host stores directly + via its own "all" loopback; clients
    -- via the broadcast). Idempotent. Attached to `mod` (200-local ceiling).
    mod._store_offhand_mesh_recv = function(wearer, slot_name, hand_field, unit_path)
        if not (wearer and slot_name) then return end
        hand_field = hand_field or "left_hand_unit"
        mod._offhand_mesh_by_peer[wearer] = mod._offhand_mesh_by_peer[wearer] or {}
        local by_slot = mod._offhand_mesh_by_peer[wearer]
        local is_set = type(unit_path) == "string" and unit_path ~= ""
        if is_set then
            by_slot[slot_name] = by_slot[slot_name] or {}
            by_slot[slot_name][hand_field] = unit_path
            -- A vanilla mesh supersedes any LA armoury entry on the SAME hand so the
            -- husk LA branch can't shadow it (per-(wearer,slot,hand) mutual exclusion).
            local la_entry = _la_equips_by_peer[wearer] and _la_equips_by_peer[wearer][slot_name]
            if la_entry and (la_entry.hand_field or "left_hand_unit") == hand_field then
                _la_equips_by_peer[wearer][slot_name] = nil
            end
        else
            -- CLEAR: drop this hand's vanilla mesh AND any LA entry on the same hand, so
            -- the wearer's husk re-resolves to the native base offhand.
            if by_slot[slot_name] then by_slot[slot_name][hand_field] = nil end
            local la_entry = _la_equips_by_peer[wearer] and _la_equips_by_peer[wearer][slot_name]
            if la_entry and (la_entry.hand_field or "left_hand_unit") == hand_field then
                _la_equips_by_peer[wearer][slot_name] = nil
            end
        end
        if printf then printf("[la-state] OFFHAND-MESH-STORE wearer=%s slot=%s hand=%s unit=%s decision=%s",
            tostring(wearer), tostring(slot_name), tostring(hand_field),
            tostring(unit_path), is_set and "STORE" or "CLEAR") end
        if PROBE then
            PROBE.emit("cos:sync",
                "offhand_mesh_store/" .. tostring(wearer) .. "/" .. tostring(slot_name) .. "/" .. tostring(hand_field),
                string.format("peer=recv wearer=%s slot=%s hand=%s unit=%s decision=%s",
                    tostring(wearer), tostring(slot_name), tostring(hand_field),
                    tostring(unit_path), is_set and "STORE" or "CLEAR"))
        end
        -- Re-render now if the wearer is spawned locally (no-op / cooldown-guarded
        -- otherwise); the store is also read on the wearer's next natural husk wield.
        local wu = _wearer_unit_for_peer(wearer)
        if wu and mod._la_native_pulse then mod._la_native_pulse(wu, "offhand-mesh") end
    end

    -- v0.9.82-dev (#416): client-facing emit for a VANILLA offhand mesh pick. Same
    -- host-short-circuit / client-request / deferred-queue routing as _send_la_revert,
    -- but carries the additive `offhand_unit` payload field (STORE path or "" CLEAR).
    -- Rides the existing cos_la_apply / cos_la_apply_req VMF mod channel -- a non-mod
    -- peer never receives it, so no modded key can ride a vanilla RPC into its
    -- NetworkLookup (#421 floor intact). Attached to `mod` (200-local ceiling).
    mod._send_offhand_mesh = function(unit, slot_name, hand_field, unit_path)
        if not (unit and Unit.alive(unit)) then return false end
        if not slot_name or unit_path == nil then return false end
        hand_field = hand_field or "left_hand_unit"
        local wearer_peer = nil
        local pm = Managers and Managers.player
        if pm and pm.owner then
            local owner = pm:owner(unit)
            wearer_peer = owner and owner.peer_id or nil
        end
        wearer_peer = wearer_peer or _local_player_peer_id()
        if not wearer_peer then return false end
        local dedup_key = wearer_peer .. "|" .. tostring(slot_name) .. "|OFFHANDMESH|"
            .. tostring(hand_field) .. "|" .. tostring(unit_path)
        local now = os.clock()
        local prev = _last_emit_at[dedup_key]
        if prev and (now - prev) < _EMIT_DEDUP_WINDOW then
            return true, "coalesced"
        end
        _last_emit_at[dedup_key] = now

        if _is_local_server() then
            mod._store_offhand_mesh_recv(wearer_peer, slot_name, hand_field, unit_path)
            if printf then printf("[la-state] OFFHAND-MESH host->all wearer=%s slot=%s hand=%s unit=%s",
                tostring(wearer_peer), tostring(slot_name), tostring(hand_field), tostring(unit_path)) end
            mod:network_send("cos_la_apply", "all", COS_RPC_SCHEMA, {
                wearer_peer_id = wearer_peer, slot = slot_name, kind = "offhand",
                offhand_unit = unit_path, hand_field = hand_field,
            })
            return true, "emitted"
        end

        local host = _host_peer_id()
        if not host then
            mod._la_deferred_emits = mod._la_deferred_emits or {}
            mod._la_deferred_emits[#mod._la_deferred_emits + 1] = {
                wearer_peer = wearer_peer, slot_name = slot_name, kind = "offhand",
                offhand_unit = unit_path, hand_field = hand_field, queued_at = os.clock(),
            }
            if printf then printf("[la-state] OFFHAND-MESH client DEFERRED (no host yet) slot=%s hand=%s unit=%s queue=%d",
                tostring(slot_name), tostring(hand_field), tostring(unit_path), #mod._la_deferred_emits) end
            return true, "queued"
        end
        if printf then printf("[la-state] OFFHAND-MESH client->req host=%s slot=%s hand=%s unit=%s",
            tostring(host), tostring(slot_name), tostring(hand_field), tostring(unit_path)) end
        mod:network_send("cos_la_apply_req", host, COS_RPC_SCHEMA, {
            slot = slot_name, kind = "offhand", offhand_unit = unit_path, hand_field = hand_field,
        })
        return true, "emitted"
    end

    -- Phase-1 exports. The entry re-localizes the five peer-identity helpers
    -- (its own later module installs and mod.update consume them) and fills its
    -- forward-declared `_send_la_apply` local, so every existing call site
    -- resolves the same function object it did before the move.
    local owner = {
        host_peer_id         = _host_peer_id,
        local_peer_id_quick  = _local_peer_id_quick,
        is_local_server      = _is_local_server,
        wearer_unit_for_peer = _wearer_unit_for_peer,
        local_player_peer_id = _local_player_peer_id,
        send_la_apply        = _send_la_apply,
        installed            = true,
        receivers_installed  = false,
    }

    -- Phase 2. Unlike phase 1 this DOES register (4 mod:network_register + the
    -- PlayerManager hook_safe pair), so a second call would duplicate the
    -- mod-wide registration set. The assert makes that invariant machine-checked
    -- rather than a comment: the entry must call this exactly once, at the line
    -- the receive block used to start.
    function owner.install_receivers()
        assert(owner.receivers_installed == false,
            "_cos_la_sync_transport.install_receivers must be called exactly once")
        owner.receivers_installed = true

        -- HOST: receives equip requests from clients, validates, records into
        -- `_la_equips_by_peer`, broadcasts the authoritative cos_la_apply to ALL.
        mod:network_register("cos_la_apply_req", function(sender_peer_id, schema_version, payload)
            if schema_version ~= COS_RPC_SCHEMA then  -- #45: drop cross-version payloads
                _dbg_alert("[rpc:schema] cos_la_apply_req mismatch from peer=%s: peer sent v%s, we expect v%d. Dropping.",
                    tostring(sender_peer_id), tostring(schema_version), COS_RPC_SCHEMA)
                -- Task-3 visibility: _dbg_alert routes through mod:warning (VMF-gated,
                -- invisible with mod logging OFF). Mirror to engine printf so a dropped
                -- cross-version RPC is never a silent failure in the user's log.
                if printf then printf("[rpc:schema] cos_la_apply_req DROP peer=%s sent=v%s expect=v%d",
                    tostring(sender_peer_id), tostring(schema_version), COS_RPC_SCHEMA) end
                return
            end
            if not _is_local_server() then return end  -- defense in depth
            if type(payload) ~= "table" or not sender_peer_id then return end
            local slot_name   = payload.slot
            local kind        = payload.kind
            local armoury_key = payload.armoury_key
            local vanilla_key = payload.vanilla_key
            local wearer_career = payload.wearer_career
            -- v0.9.9.4-dev: hand_field is new; older clients omit it. Default to
            -- "left_hand_unit" for offhand/illusion (legacy behavior) so peers on
            -- pre-v0.9.9.4 versions still sync correctly.
            local hand_field  = payload.hand_field
            if (kind == "offhand" or kind == "illusion") and not hand_field then
                hand_field = "left_hand_unit"
            end
            -- v0.9.69-dev (Slice 0, I6): host-side receipt line BEFORE any validation,
            -- so a client req that reaches the host but is then rejected/deduped is
            -- distinguishable from one lost on the wire (#264-comment transport loss).
            if printf then printf("[la-state] REQ-RECV from=%s slot=%s kind=%s key=%s revert=%s",
                tostring(sender_peer_id), tostring(slot_name), tostring(kind),
                tostring(armoury_key), tostring(payload.revert or false)) end
            -- v0.9.69-dev (#265 Slice 1): client-originated REVERT. No armoury_key to
            -- validate -- delete the sender's store entry and rebroadcast the revert
            -- authoritatively to all peers (the sender included, for lockstep).
            if payload.revert then
                if slot_name and kind then
                    if _la_equips_by_peer[sender_peer_id] then
                        _la_equips_by_peer[sender_peer_id][slot_name] = nil
                    end
                    mod:network_send("cos_la_apply", "all", COS_RPC_SCHEMA, {
                        wearer_peer_id = sender_peer_id,
                        slot           = slot_name,
                        kind           = kind,
                        revert         = true,
                        vanilla_key    = payload.vanilla_key,
                        hand_field     = hand_field,
                    })
                end
                return
            end
            -- v0.9.82-dev (#416): client-originated VANILLA offhand mesh. No armoury_key to
            -- validate; store on the host + rebroadcast authoritatively to all (sender
            -- included, for lockstep). Placed before the armoury_key gate, like the revert.
            if payload.offhand_unit ~= nil then
                if slot_name and mod._store_offhand_mesh_recv then
                    mod._store_offhand_mesh_recv(sender_peer_id, slot_name, hand_field, payload.offhand_unit)
                    mod:network_send("cos_la_apply", "all", COS_RPC_SCHEMA, {
                        wearer_peer_id = sender_peer_id, slot = slot_name, kind = "offhand",
                        offhand_unit = payload.offhand_unit, hand_field = hand_field,
                    })
                end
                return
            end
            if not (slot_name and kind and armoury_key) then return end
            local sender_unit = _wearer_unit_for_peer(sender_peer_id)
            local sender_live_career = sender_unit and mod._la_career_for_unit(sender_unit)
            local career_ok, career_reason = mod._cos_husk_identity.transport_career_valid(
                wearer_career, sender_live_career)
            if not career_ok then
                if printf then printf("[cos:698] REQ SKIP wearer=%s slot=%s reason=%s",
                    tostring(sender_peer_id), tostring(slot_name), tostring(career_reason)) end
                return
            end
            -- v0.9.3.2-hotfix: accept armoury_keys present in EITHER our bridge index
            -- OR LA's own SKIN_LIST directly. The bridge's register_all only registers
            -- swap_hand == "hat" or "armor" variants — shields and weapons (swap_hand
            -- == "left_hand_unit" / "right_hand_unit") are NOT in armoury_to_backend.
            -- That left shield repaints silently rejected on the host side even though
            -- the client paints them locally just fine (its paint code reads LA's
            -- SKIN_LIST directly). Now: accept any armoury_key LA knows about.
            -- Burned PC-A→PC-B test 2026-05-21 17:53.
            local bridge_known = LA_BRIDGE and LA_BRIDGE.registered and LA_BRIDGE.armoury_to_backend[armoury_key]
            local la_known = false
            do
                local la = get_mod("Loremasters-Armoury")
                if la and type(la.SKIN_LIST) == "table" and la.SKIN_LIST[armoury_key] then
                    la_known = true
                end
            end
            if not (bridge_known or la_known) then
                _dbg_alert("[cos_la_apply_req] reject from %s: unknown armoury_key %s",
                    tostring(sender_peer_id), tostring(armoury_key))
                return
            end
            _la_equips_by_peer[sender_peer_id] = _la_equips_by_peer[sender_peer_id] or {}
            _la_equips_by_peer[sender_peer_id][slot_name] = mod._cos_husk_identity.new_entry(
                kind, armoury_key, vanilla_key, hand_field, wearer_career)
            mod:network_send("cos_la_apply", "all", COS_RPC_SCHEMA, {
                wearer_peer_id = sender_peer_id,
                slot           = slot_name,
                kind           = kind,
                armoury_key    = armoury_key,
                vanilla_key    = vanilla_key,
                hand_field     = hand_field,
                wearer_career  = wearer_career,
            })
        end)

        -- v0.9.70-dev (#267, LA_SYNC_CORE_AUDIT Slice 2b / invariant I9): HOST side
        -- of the pull-on-ready flow. A peer that just reached StateIngame requests
        -- the full LA store; we reply with one targeted cos_la_apply per recorded
        -- (wearer, slot). Reuses the existing broadcast payload shape, so the
        -- joiner's recv path (mirror + reconcile) needs nothing new. The requester's
        -- own entries are included deliberately -- after a transition they re-drive
        -- the client's local reconcile, hardening #233. Old-version peers never send
        -- this RPC and ignore it if received (unknown name), so it is
        -- backward-compatible without a schema bump.
        mod:network_register("cos_la_state_req", function(sender_peer_id, schema_version, payload)
            if schema_version ~= COS_RPC_SCHEMA then
                if printf then printf("[rpc:schema] cos_la_state_req DROP peer=%s sent=v%s expect=v%d",
                    tostring(sender_peer_id), tostring(schema_version), COS_RPC_SCHEMA) end
                return
            end
            -- #267 follow-up (tonight's 3-player session: clients retried the pull 30x /
            -- 10x and NEVER got a reply). Both early returns were silent, so the
            -- responder-side cause was invisible in the client-only logs. Log them: a
            -- non-server that still receives the req (host election flux / a peer that
            -- resolved the wrong host) and a missing sender are the two ways the host
            -- can legitimately decline to answer. If neither fires and the reply count
            -- below is still 0, the store was genuinely empty (not a lost reply).
            if not _is_local_server() then
                if printf then printf("[la-state] STATE-PULL DROP req from=%s reason=not-local-server (is_server=%s host=%s self=%s)",
                    tostring(sender_peer_id),
                    tostring(Managers and Managers.player and Managers.player.is_server),
                    tostring(_host_peer_id()), tostring(_local_peer_id_quick())) end
                return
            end
            if not sender_peer_id then
                if printf then printf("[la-state] STATE-PULL DROP reason=no-sender-peer") end
                return
            end
            local n = 0
            for wearer_peer, slots in pairs(_la_equips_by_peer) do
                if type(slots) == "table" then
                    for slot_name, entry in pairs(slots) do
                        if type(entry) == "table" and entry.kind and entry.armoury_key then
                            mod:network_send("cos_la_apply", sender_peer_id, COS_RPC_SCHEMA, {
                                wearer_peer_id = wearer_peer,
                                slot           = slot_name,
                                kind           = entry.kind,
                                armoury_key    = entry.armoury_key,
                                vanilla_key    = entry.vanilla_key,
                                hand_field     = entry.hand_field,
                                wearer_career  = entry.wearer_career,
                            })
                            n = n + 1
                        end
                    end
                end
            end
            -- v0.9.82-dev (#416): also replay VANILLA offhand meshes so a late joiner sees
            -- peers' shield / held-weapon picks. Reuses cos_la_apply with the offhand_unit
            -- field (the joiner's recv path stores + pulses -- no new handler needed).
            for wearer_peer, slots in pairs(mod._offhand_mesh_by_peer) do
                if type(slots) == "table" then
                    for slot_name, hands in pairs(slots) do
                        if type(hands) == "table" then
                            for hand_field, unit_path in pairs(hands) do
                                if type(unit_path) == "string" and unit_path ~= "" then
                                    mod:network_send("cos_la_apply", sender_peer_id, COS_RPC_SCHEMA, {
                                        wearer_peer_id = wearer_peer, slot = slot_name,
                                        kind = "offhand", offhand_unit = unit_path,
                                        hand_field = hand_field,
                                    })
                                    n = n + 1
                                end
                            end
                        end
                    end
                end
            end
            -- #574 follow-up: reuse the proven pull-on-ready request instead of
            -- adding another RPC. The old AttachmentUtils push can precede the
            -- joiner's ingame membership and disappear; this reply is requested by
            -- the joiner after its host identity is usable. One targeted existing
            -- cos_glow_apply per cached wearer feeds the normal recv + bounded local
            -- equipment-ready repaint path.
            local glow_n = 0
            for wearer_peer, state in pairs(_glow_by_peer) do
                if type(state) == "table" then
                    mod:network_send("cos_glow_apply", sender_peer_id, COS_RPC_SCHEMA, {
                        wearer_peer_id = wearer_peer,
                        state = state,
                    })
                    glow_n = glow_n + 1
                end
            end
            _cos574_log("state-pull reply requester=%s glow_entries=%d new_rpc=false",
                tostring(sender_peer_id), glow_n)
            if printf then printf("[la-state] STATE-PULL reply: %d entr(ies) -> requester=%s",
                n, tostring(sender_peer_id)) end
            -- v0.9.71-dev: explicit ack so the requester can distinguish "empty
            -- store" from "request lost in the load window" and stop retrying.
            mod:network_send("cos_la_state_ack", sender_peer_id, COS_RPC_SCHEMA, { count = n })
        end)

        -- v0.9.71-dev: requester side of the pull ack (see the retry drain in
        -- mod.update). Old-version hosts never send this; the requester then retries
        -- up to its cap and gives up loudly - still strictly better than one silent
        -- fire-and-forget send.
        mod:network_register("cos_la_state_ack", function(sender_peer_id, schema_version, payload)
            if schema_version ~= COS_RPC_SCHEMA then return end
            local attempts = type(mod._la_state_pull_pending) == "table"
                and mod._la_state_pull_pending.attempts or "?"
            mod._la_state_pull_pending = nil
            if printf then printf("[la-state] STATE-PULL acked by host=%s count=%s (attempt %s)",
                tostring(sender_peer_id),
                tostring(type(payload) == "table" and payload.count or "?"),
                tostring(attempts)) end
        end)

        -- v0.9.0-dev: peer-disconnect cleanup. Without this _la_equips_by_peer grows
        -- unboundedly across the host's session, and stale entries replay on hot_join
        -- for peers who left long ago (visible if they share peer_id with a future
        -- joiner, which Steam sometimes recycles). Also clears _last_emit_at so the
        -- dedup window doesn't suppress legitimate fresh emits after re-join.
        -- v0.9.71-dev ROOT-CAUSE FIX (2026-07-06 17:25/17:26 session logs, both
        -- machines): `PlayerManager.remove_player` fires for EVERY peer - including
        -- the machine's OWN peer - on EVERY level transition, not just on
        -- disconnects (host log 17:28:20.460/.471: remove_player for self AND the
        -- client during the keep->mission load, each immediately followed by this
        -- hook's purge line). The v0.9.0 immediate purge therefore WIPED
        -- `_la_equips_by_peer` on every machine at every transition, which is why
        -- TRANSITION-WALK always armed with `offhand_entries=0`, HUSK-GATE logged
        -- `no-store-for-wearer` post-transition, and no illusion survived into a
        -- mission (the store the audit assumed transition-proof never was).
        -- Fix: DEFER the purge 30s. A transition re-adds the peer within seconds
        -- (add_remote_player cancels the deadline); a genuine disconnect never
        -- re-adds, so the purge still runs - the Steam peer_id-recycling rationale
        -- of v0.9.0 is preserved, just 30s later. The local peer is never purged.
        if rawget(_G, "PlayerManager") then
            mod:hook_safe(PlayerManager, "remove_player", function(self, peer_id, local_player_id)
                if not peer_id then return end
                local has_state = (_la_equips_by_peer and _la_equips_by_peer[peer_id]) ~= nil
                    or (mod._glow_by_peer and mod._glow_by_peer[peer_id]) ~= nil
                    or (mod._cos_custom_illusion_sent
                        and mod._cos_custom_illusion_sent[tostring(peer_id)]) ~= nil
                if not has_state then return end
                mod._la_peer_purge_at = mod._la_peer_purge_at or {}
                if not mod._la_peer_purge_at[peer_id] then
                    mod._la_peer_purge_at[peer_id] = os.clock() + 30
                    if printf then printf("[la-state] PEER-PURGE scheduled peer=%s in 30s (remove_player; canceled if the peer re-adds - transitions do)",
                        tostring(peer_id)) end
                end
            end)
            -- Transition/hot-join re-add cancels the pending purge. Remote peers
            -- re-enter via add_remote_player on every level load.
            mod:hook_safe(PlayerManager, "add_remote_player", function(self, peer_id, ...)
                if peer_id and mod._la_peer_purge_at and mod._la_peer_purge_at[peer_id] then
                    mod._la_peer_purge_at[peer_id] = nil
                    if printf then printf("[la-state] PEER-PURGE canceled peer=%s (re-added - transition, not a disconnect)",
                        tostring(peer_id)) end
                end
                if LA_REPLAY_POLICY.should_publish_local_on_peer_ready(
                        _local_player_peer_id(), peer_id) then
                    mod._la_self_rebroadcast_pending = true
                end
                -- #660 S3: a peer appeared -> peer-ready replay edge, scoped to that
                -- peer. Its husk unit is usually not spawned yet, so most records defer
                -- here and drain on the husk-ready (SimpleHuskInventoryExtension.init)
                -- edge; invalidating just this peer keeps the coalescing scope tight.
                if peer_id and mod._cos_replay then
                    mod._cos_replay.on_edge("peer-ready",
                        { only_peer = peer_id, invalidate_peer = peer_id })
                end
            end)
        end

        -- Executes due deferred purges. Called from mod.update.
        mod._la_tick_peer_purges = function()
            local q = mod._la_peer_purge_at
            if not q or not next(q) then return end
            local now = os.clock()
            local local_peer = _local_player_peer_id()
            for peer_id, deadline in pairs(q) do
                if peer_id == local_peer then
                    q[peer_id] = nil  -- never purge our own state
                elseif now >= deadline then
                    q[peer_id] = nil
                    if _la_equips_by_peer and _la_equips_by_peer[peer_id] then
                        _la_equips_by_peer[peer_id] = nil
                    end
                    if _last_emit_at then
                        for k, _ in pairs(_last_emit_at) do
                            if type(k) == "string" and k:sub(1, #tostring(peer_id) + 1) == (tostring(peer_id) .. "|") then
                                _last_emit_at[k] = nil
                            end
                        end
                    end
                    if mod._glow_by_peer and mod._glow_by_peer[peer_id] then
                        mod._glow_by_peer[peer_id] = nil
                    end
                    -- v0.9.82-dev (#416): drop the disconnected peer's vanilla offhand meshes too.
                    if mod._offhand_mesh_by_peer and mod._offhand_mesh_by_peer[peer_id] then
                        mod._offhand_mesh_by_peer[peer_id] = nil
                    end
                    if mod._cos_custom_illusion_sent then
                        mod._cos_custom_illusion_sent[tostring(peer_id)] = nil
                    end
                    if printf then printf("[la-state] PEER-PURGE executed peer=%s (no re-add within 30s - genuine leave)",
                        tostring(peer_id)) end
                end
            end
        end

        -- ALL PEERS: receives the authoritative apply broadcast. Only accept it from
        -- the host (defense against malicious peers spoofing).
        mod:network_register("cos_la_apply", function(sender_peer_id, schema_version, payload)
            if schema_version ~= COS_RPC_SCHEMA then  -- #45: drop cross-version payloads
                _dbg_alert("[rpc:schema] cos_la_apply mismatch from peer=%s: peer sent v%s, we expect v%d. Dropping.",
                    tostring(sender_peer_id), tostring(schema_version), COS_RPC_SCHEMA)
                if printf then printf("[rpc:schema] cos_la_apply DROP peer=%s sent=v%s expect=v%d",
                    tostring(sender_peer_id), tostring(schema_version), COS_RPC_SCHEMA) end
                return
            end
            if type(payload) ~= "table" then return end
            local host = _host_peer_id()
            if host and sender_peer_id ~= host then
                _dbg_alert("[cos_la_apply] reject non-host sender %s (host=%s)",
                    tostring(sender_peer_id), tostring(host))
                return
            end
            local wearer       = payload.wearer_peer_id
            local slot_name    = payload.slot
            local kind         = payload.kind
            local armoury_key  = payload.armoury_key
            local vanilla_key  = payload.vanilla_key
            local wearer_career = payload.wearer_career
            -- v0.9.9.4-dev: tolerate older peers that don't send hand_field;
            -- treat as left_hand_unit for offhand/illusion (legacy default).
            local hand_field   = payload.hand_field
            if (kind == "offhand" or kind == "illusion") and not hand_field then
                hand_field = "left_hand_unit"
            end
            -- v0.9.69-dev (#265 Slice 1): authoritative REVERT. Delete the store
            -- entry and restore the native render (pulse / hat re-create) via the
            -- receiver helper defined after _ensure_offhand_mesh. Placed BEFORE the
            -- armoury_key guard -- a revert carries none by design.
            if payload.revert then
                if wearer and slot_name and kind and mod._la_apply_revert_recv then
                    mod._la_apply_revert_recv(wearer, slot_name, kind, payload.vanilla_key, hand_field)
                end
                return
            end
            -- v0.9.82-dev (#416): VANILLA offhand mesh sync (its own payload field; no
            -- armoury_key). Placed BEFORE the armoury_key gate, mirroring the revert branch.
            -- Non-mod peers never receive this VMF mod RPC, so the #421 vanilla-wire floor
            -- is a separate axis, untouched. offhand_unit "" clears (revert to base offhand).
            if payload.offhand_unit ~= nil then
                if wearer and slot_name and mod._store_offhand_mesh_recv then
                    mod._store_offhand_mesh_recv(wearer, slot_name, hand_field, payload.offhand_unit)
                end
                return
            end
            if not (wearer and slot_name and kind and armoury_key) then return end
            local wearer_unit = _wearer_unit_for_peer(wearer)
            local active_career = wearer_unit and mod._la_career_for_unit(wearer_unit)
            local career_ok, career_reason = mod._cos_husk_identity.transport_career_valid(
                wearer_career, active_career)
            if not career_ok then
                if printf then printf("[cos:698] RECV SKIP wearer=%s slot=%s reason=%s",
                    tostring(wearer), tostring(slot_name), tostring(career_reason)) end
                return
            end

            -- v0.9.0.7-hotfix: MIRROR THE CACHE WRITE ON CLIENTS.
            -- Previously only the HOST's `cos_la_apply_req` register handler (see
            -- the `mod:network_register("cos_la_apply_req", ...)` block above)
            -- wrote to `_la_equips_by_peer`. Clients received the broadcast and
            -- ran the apply once, but never recorded the entry — so:
            --   1. The v0.9.0.5 husk-wield re-paint hook silently no-op'd on
            --      every client (lookup returned nil every time).
            --   2. The v0.9.0.6 husk-mesh-swap in get_item_units also no-op'd
            --      on clients (same nil lookup) → kind="unit" Ostermark shields
            --      stayed vanilla on the client viewing the host.
            -- Fix: mirror the host's write here so EVERY peer (host + clients)
            -- maintains the same `_la_equips_by_peer` cache state. The host's
            -- own broadcast loops back via "all" → this handler fires on the
            -- host too, but the write is idempotent (entry already there from
            -- the cos_la_apply_req handler).
            _la_equips_by_peer[wearer] = _la_equips_by_peer[wearer] or {}
            _la_equips_by_peer[wearer][slot_name] = mod._cos_husk_identity.new_entry(
                kind, armoury_key, vanilla_key, hand_field, wearer_career)
            -- v0.9.82-dev (#416): mutual exclusion -- an LA armoury pick supersedes any
            -- parallel vanilla mesh on the SAME (wearer, slot, hand) so the husk vanilla
            -- branch can't shadow the LA mesh (the switch vanilla->LA case).
            do
                local vslot = mod._offhand_mesh_by_peer[wearer] and mod._offhand_mesh_by_peer[wearer][slot_name]
                if vslot then vslot[hand_field] = nil end
            end
            -- v0.9.0.11-hotfix: diagnostic — count cache entries to confirm the write
            -- actually persisted (and to verify the upvalue scope fix from this version).
            local n = 0
            for _, _ in pairs(_la_equips_by_peer[wearer]) do n = n + 1 end
            _dbg("[cos_la_apply recv] CACHE WRITE _la_equips_by_peer[%s][%s] now has %d slot(s) total",
                tostring(wearer), tostring(slot_name), n)

            -- v0.9.70-dev (Slice 2 / I3): recv now routes through the single
            -- reconcile entry point (paint + gated mesh pulse, wearer-scoped).
            local applied = mod._la_reconcile(wearer, slot_name, "recv", true)
            -- v0.9.61-dev (#203): [cos-la-sync] receiver-side outcome via mod:info so it
            -- lands in the HOST's log (the missing evidence for #203 -- a client log can't
            -- show the host painting the wearer's husk). Deduped on
            -- (wearer,slot,armoury,applied) so a per-frame retry cannot flood; an
            -- applied=false->true flip logs both, showing when (or if) the paint landed.
            -- The mesh-swap + paint decision itself is in the [cos:sync] husk_meshgate /
            -- husk_meshswap / husk_offhand PROBE lines (also host-side, printf).
            do
                mod._cos_la_sync_recv_seen = mod._cos_la_sync_recv_seen or {}
                local seen_key = tostring(wearer) .. "|" .. tostring(slot_name) .. "|"
                    .. tostring(armoury_key) .. "|" .. tostring(applied)
                if not mod._cos_la_sync_recv_seen[seen_key] then
                    mod._cos_la_sync_recv_seen[seen_key] = true
                    mod:info("[cos-la-sync] RECV wearer=%s slot=%s kind=%s armoury=%s applied=%s",
                        tostring(wearer), tostring(slot_name), tostring(kind),
                        tostring(armoury_key), tostring(applied))
                end
            end
            _dbg("[cos_la_apply recv] from=%s wearer=%s slot=%s kind=%s key=%s applied=%s",
                tostring(sender_peer_id), tostring(wearer), tostring(slot_name),
                tostring(kind), tostring(armoury_key), tostring(applied))
            -- [cos:sync] #149/#154: husk cache population + immediate apply outcome on a
            -- broadcast receive. applied=false here is the mission-start race (wearer not
            -- spawned yet) that gets queued below for retry. peer=husk (remote wearer).
            if PROBE then
                PROBE.emit("cos:sync",
                    "recv_cache/" .. tostring(wearer) .. "/" .. tostring(slot_name) .. "/" .. tostring(armoury_key),
                    string.format("peer=husk event=cache_write+apply wearer=%s from=%s slot=%s kind=%s key=%s applied=%s",
                        tostring(wearer), tostring(sender_peer_id), tostring(slot_name),
                        tostring(kind), tostring(armoury_key), tostring(applied)))
            end
            _trace("SYNC recv from=%s wearer=%s slot=%s kind=%s armoury=%s applied=%s",
                tostring(sender_peer_id), tostring(wearer), tostring(slot_name),
                tostring(kind), tostring(armoury_key), tostring(applied))

            -- v0.9.0.10-hotfix: TRIGGER MESH SWAP for kind="unit" variants.
            -- The husk-mesh-swap branch in BackendUtils.get_item_units only fires
            -- when SimpleHuskInventoryExtension._wield_slot runs, which happens on
            -- rpc_wield_equipment (slot_melee↔slot_ranged swaps) — NOT when the
            -- host cycles shield variants via CT's picker (which emits cos_la_apply
            -- but no wield change). For kind="unit" variants (Ostermark, Bastonne
            -- custom-mesh shields), the texture-paint path returns false (mesh swap
            -- is what's needed, not paint). Without a wield event, the husk's
            -- weapon unit stays vanilla.
            --
            -- Fix: when the variant is kind="unit" AND the entry is an offhand/
            -- illusion (weapon-side, where the wield event is meaningful), force a
            -- husk re-wield so _wield_slot → BackendUtils.get_item_units → husk-mesh-
            -- swap branch → LA mesh spawns.
            --
            -- v0.9.41-dev (#149): PULSE through the OTHER weapon slot then back,
            -- mirroring the customization-exit pulse (~line 2317), instead of
            -- inv:wield(inv.wielded_slot). NOTE: vanilla
            -- SimpleHuskInventoryExtension._wield_slot (source line 641) does NOT
            -- short-circuit on same-slot — it destroy+respawns and re-calls
            -- get_item_units every time — so same-slot WOULD re-run the swap. We pulse
            -- anyway for robustness: it guarantees a clean destroy/respawn cycle after
            -- the _la_equips_by_peer cache is populated (the client's mission-start race)
            -- and matches the established pulse pattern. We end on the ORIGINAL slot so
            -- the husk stays on the weapon the host has wielded. Pcall each wield so a
            -- failure can't crash the receiver; even if the pulse fails the rest of the
            -- apply chain ran. (The texture half of the client fix is the
            -- "network_husk" paint now allowed in _la_bridge.lua.)
            -- v0.9.64-dev (#233/#234): route through the gated _ensure_offhand_mesh helper
            -- instead of the old UNCONDITIONAL pulse. The helper no-ops when the mesh is
            -- already the LA mesh (so no flicker on a same-model re-apply), only pulses a
            -- kind="unit" mesh that is stale/vanilla AND package-resident, and is bounded by
            -- a per-owner cooldown + try-cap. Covers BOTH the host's husk (wearer=remote,
            -- #233) and the local player's own body (wearer=local peer -> players_at_peer
            -- returns the local player, #234), since cos_la_apply broadcasts to "all"
            -- including the originating client. Safe context (network callback, not a
            -- _wield_slot body).
            -- v0.9.69-dev (#268, invariant I4 targeting): the mesh pulse is scoped to
            -- THE wearer's unit only (the old players_at_peer loop force-swapped a
            -- host's BOT shields). v0.9.70-dev: the pulse now lives INSIDE
            -- mod._la_reconcile (allow_pulse=true above), so nothing extra runs here.
            if not applied then
                -- Wearer unit not spawned locally yet (loading screen race / late
                -- network spawn / husk not wielding the right slot). Queue and retry
                -- on mod.update for up to 5 seconds.
                -- DEVIATION (#1159): resolve the rebound entry-owned retry queue at the first read.
                local _la_pending_apply = _get_la_pending_apply()
                _la_pending_apply[#_la_pending_apply + 1] = {
                    wearer, slot_name, kind, armoury_key, vanilla_key, os.clock() + 5,
                }
                -- [cos:sync] #149: mission-entry / late-spawn reapply deferral. This is
                -- the "LA shield reverts at mission start" window -- apply failed now,
                -- queued for retry. peer=husk (remote wearer).
                if PROBE then
                    PROBE.emit("cos:sync",
                        "pending/" .. tostring(wearer) .. "/" .. tostring(slot_name) .. "/" .. tostring(armoury_key),
                        string.format("peer=husk event=deferred-reapply wearer=%s slot=%s kind=%s key=%s reason=wearer-not-spawned-or-wrong-slot",
                            tostring(wearer), tostring(slot_name), tostring(kind), tostring(armoury_key)))
                end
            end
        end)
    end

    mod._cos_la_sync_transport_owner = owner
    return owner
end

return LaSyncTransport
