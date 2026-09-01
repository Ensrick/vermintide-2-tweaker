-- _cos_update_scheduler.lua
--
-- RESPONSIBILITY: own Cosmetics' one VMF per-frame scheduler. It preserves the
-- historical tick order for deferred rewields, authored-cosmetic registration,
-- transition replay, persistence cleanup, bounded state-pull retries, glow
-- convergence, peer purge, TPE, and the shared LA pending-apply drain.
--
-- Owned by: cosmetics_tweaker.lua (one install at the former mod.update site).
-- Consumed via: VMF calling mod.update(dt).
--
-- The LA pending queue and bridge-init flag remain entry locals because sibling
-- owners share them. Both cross this boundary through getter/setter pairs: each
-- is rebound, so a by-value capture would orphan the other owners' view.
-- This owner registers no hook, RPC receiver, command, lifecycle callback, or
-- persistence writer. Its only send is the existing bounded cos_la_state_req
-- retry already present in the historical scheduler.

local M = {}

local REQUIRED = {
    "custom_hats", "la_persist", "la_bridge", "gk_set", "get_mod",
    "get_item_master_list", "merge_la_offhand_options",
    "force_load_all_offhand_packages", "install_skin_loadout_safety",
    "local_player_safe", "la_equips_by_peer", "wearer_unit_for_peer",
    "get_la_bridge_init_done", "set_la_bridge_init_done", "is_local_server",
    "host_peer_id", "local_peer_id_quick", "rpc_schema", "get_managers", "now",
    "la_okri", "tpe", "glow_picker", "get_la_pending_apply",
    "set_la_pending_apply",
}

local function validate(mod, ctx)
    assert(type(mod) == "table", "cos update scheduler requires mod")
    assert(type(ctx) == "table", "cos update scheduler requires context")
    for i = 1, #REQUIRED do
        local name = REQUIRED[i]
        assert(ctx[name] ~= nil, "cos update scheduler missing context." .. name)
    end
end

function M.install(mod, ctx)
    validate(mod, ctx)

    local state = mod._cos_update_scheduler_state
    if not state then
        state = {}
        mod._cos_update_scheduler_state = state
    end
    state.ctx = ctx
    state.la_bridge_missing_dep_logged = false

    if not state.update then
        state.update = function(dt)
            local ctx = state.ctx
            local CUSTOM_HATS = ctx.custom_hats
            local LA_PERSIST = ctx.la_persist
            local LA_BRIDGE = ctx.la_bridge
            local GK_SET = ctx.gk_set
            local get_mod = ctx.get_mod
            local ItemMasterList = ctx.get_item_master_list()
            local _merge_la_offhand_options = ctx.merge_la_offhand_options
            local _force_load_all_offhand_packages = ctx.force_load_all_offhand_packages
            local _install_skin_loadout_safety = ctx.install_skin_loadout_safety
            local _local_player_safe = ctx.local_player_safe
            local _la_equips_by_peer = ctx.la_equips_by_peer
            local _wearer_unit_for_peer = ctx.wearer_unit_for_peer
            local _la_bridge_init_done = ctx.get_la_bridge_init_done()
            local _is_local_server = ctx.is_local_server
            local _host_peer_id = ctx.host_peer_id
            local _local_peer_id_quick = ctx.local_peer_id_quick
            local COS_RPC_SCHEMA = ctx.rpc_schema
            local Managers = ctx.get_managers()
            local _now = ctx.now
            local printf = ctx.printf
            local LA_OKRI = ctx.la_okri
            local TPE = ctx.tpe
            local GlowPicker = ctx.glow_picker
            local _la_pending_apply = ctx.get_la_pending_apply()
        -- #1145 FIRST: flush at most one deferred wield pulse per wearer, each
        -- re-gated on a live husk game object. Top-of-frame guarantees a full frame
        -- between the queuing burst and the pulse, so a husk destroyed in between is
        -- seen as destroyed and its pulse is dropped.
        mod._cos_rewield.drain()
        CUSTOM_HATS.tick(dt)
        -- v0.9.12-dev: pump persistence-restore queue. SimpleInventoryExtension
        -- .extensions_ready queues a Player for restore; tick processes the queue
        -- once career_name + player_unit are both ready (~1 frame later).
        if LA_PERSIST and LA_PERSIST.tick_pending_restore then
            LA_PERSIST.tick_pending_restore()
        end

        -- #629: keep this edge pending until exact career, both equipped slots,
        -- saved offhand convergence, and every queued/emitted operation are proven.
        mod._cos_complete_set_rebroadcast_tick()

        -- v0.9.66-dev (#233): CLIENT-side self-heal of REMOTE peers' cached LA offhand/
        -- illusion equips after a level transition. Armed by on_game_state_changed
        -- (`_la_reapply_remote_until`). The host's post-transition rebroadcast of its own
        -- equip races the client's load window and is dropped (the "all" send fires ~25ms
        -- before the client's peer_ingame flips true), and nothing re-sends -- so the host's
        -- LA offhand reverted on the client at every mission<->keep transition.
        -- `_la_equips_by_peer` survives (only cleared on peer disconnect), so we hold the
        -- authoritative equip locally and re-drive the recv/retry apply every frame within a
        -- bounded window until the remote wearer's husk spawns and wields the offhand.
        --
        -- v0.9.66-dev fix over v0.9.65-dev, which shipped a SILENT NO-OP (0 lines in the
        -- 2026-07-03 21:15 retest): the old block called ONLY `_ensure_offhand_mesh`, which
        -- early-returns for any non-kind="unit" LA variant -- so a kind="texture" illusion
        -- (the breton shields in that retest get RECV but never a RE-SWAP) was never
        -- re-painted and the whole walk logged nothing. The current path calls the
        -- canonical `mod._la_reconcile` owner, which re-paints the texture and invokes
        -- `_ensure_offhand_mesh` only when the offhand is currently wielded. Gating the
        -- pulse on wield state avoids a wasteful melee<->ranged flicker on a husk holding
        -- a ranged weapon and targets exactly the visible-revert case. Both stages
        -- self-gate (paint idempotent; pulse per-owner 1.5s cooldown + 3-try cap); each (peer|armoury) is
        -- FROZEN once applied so there is no per-frame repaint. Two bounded diagnostics per
        -- window (armed + summary) so a silent no-op can never ship undetected again. No new
        -- hook/RPC/force-load; no World.destroy_unit.
        if mod._la_reapply_remote_until then
            if _now() >= mod._la_reapply_remote_until then
                -- Window closed: emit the one-line summary (from the frozen dispositions),
                -- then disarm.
                local st = mod._la_reapply_stats
                if st then
                    -- allow-perframe: one summary emitted only when the bounded transition window closes
                    mod:info("[cos-la-sync] TRANSITION-WALK done applied=%d skipped_unwielded=%d skipped_unresolved=%d",
                        st.applied or 0, st.unwielded or 0, st.unresolved or 0)
                    mod._la_reapply_stats = nil
                end
                mod._la_reapply_remote_until = nil
            else
                -- Skip frames without a live network game; the bounded window persists
                -- and retries once vanilla's safe player lookup becomes available.
                local pm = Managers and Managers.player
                local lp = _local_player_safe(pm)
                local local_peer = lp and lp.peer_id or nil
                if local_peer and _la_equips_by_peer then
                    local st = mod._la_reapply_stats
                    if not st then
                        -- First active frame of this window: arm + count what we hold, so
                        -- an empty cache (nothing to restore) is distinguishable from a walk
                        -- that reached entries but the apply no-op'd.
                        local peer_n, entry_n = 0, 0
                        for p, sl in pairs(_la_equips_by_peer) do
                            if p ~= local_peer and type(sl) == "table" then
                                local has = false
                                for _, e in pairs(sl) do
                                    if type(e) == "table" and e.armoury_key
                                        and (e.kind == "offhand" or e.kind == "illusion") then
                                        entry_n = entry_n + 1
                                        has = true
                                    end
                                end
                                if has then peer_n = peer_n + 1 end
                            end
                        end
                        st = { applied = 0, unwielded = 0, unresolved = 0, seen = {} }
                        mod._la_reapply_stats = st
                        -- allow-perframe: one arming record emitted only when a new transition window starts
                        mod:info("[cos-la-sync] TRANSITION-WALK armed local=%s remote_peers=%d offhand_entries=%d",
                            tostring(local_peer), peer_n, entry_n)
                    end
                    for peer, slots in pairs(_la_equips_by_peer) do
                        if peer ~= local_peer and type(slots) == "table" then
                            local wu = _wearer_unit_for_peer(peer)
                            for slot_name, eq in pairs(slots) do
                                if type(eq) == "table" and eq.armoury_key
                                    and (eq.kind == "offhand" or eq.kind == "illusion") then
                                    local dkey = tostring(peer) .. "|" .. tostring(eq.armoury_key)
                                    -- Freeze each entry once it has been applied (offhand
                                    -- wielded + re-painted/pulsed) so we don't repaint per frame.
                                    if st.seen[dkey] ~= "applied" then
                                        if not wu then
                                            st.seen[dkey] = "unresolved"
                                        else
                                            -- v0.9.70-dev (Slice 2 / I3): route through the
                                            -- single reconcile entry point (paint + gated
                                            -- mesh pulse; this drain is a safe pulse context).
                                            -- Semantics preserved: applied only when the
                                            -- offhand is currently wielded.
                                            local applied = mod._la_reconcile(peer, slot_name, "transition", true)
                                            if applied then
                                                st.seen[dkey] = "applied"
                                            else
                                                st.seen[dkey] = "unwielded"
                                            end
                                        end
                                    end
                                end
                            end
                        end
                    end
                    -- Recompute the tallies from the frozen dispositions so the summary is
                    -- stable regardless of per-frame churn (an entry migrates
                    -- unresolved -> unwielded -> applied and then freezes).
                    local a, uw, ur = 0, 0, 0
                    for _, d in pairs(st.seen) do
                        if d == "applied" then a = a + 1
                        elseif d == "unwielded" then uw = uw + 1
                        else ur = ur + 1 end
                    end
                    st.applied, st.unwielded, st.unresolved = a, uw, ur
                end
            end
        end

        if not _la_bridge_init_done then
            if CUSTOM_HATS and not CUSTOM_HATS.registered and ItemMasterList then
                CUSTOM_HATS.register_all(LA_BRIDGE)
            end
            if GK_SET and not GK_SET.registered and ItemMasterList then
                GK_SET.register_all(LA_BRIDGE)
            end
            local has_la  = get_mod("Loremasters-Armoury") ~= nil
            local has_mil = get_mod("MoreItemsLibrary") ~= nil
            if not state.la_bridge_missing_dep_logged
                and ItemMasterList
                and (not has_la or not has_mil) then
                if not has_mil then
                    -- allow-perframe: dependency-missing latch permits one log per scheduler install
                    mod:info("[LA bridge] dependency missing: MoreItemsLibrary (Workshop ID 1422758813). bridge will stay dormant.")
                end
                if not has_la then
                    -- Startup chat is version-only (#570). Keep the actionable
                    -- dependency evidence in the console log without buffering a
                    -- non-version chat line for the first keep frame.
                    -- allow-perframe: dependency-missing latch permits one log per scheduler install
                    mod:info("[LA bridge] dependency missing: Loremaster's Armoury. bridge will stay dormant.")
                end
                state.la_bridge_missing_dep_logged = true
            end
            if ItemMasterList
               and has_la
               and has_mil then
                local call_ok, registered, reason = pcall(LA_BRIDGE.register_all)
                if call_ok and registered then
                    local gate_ok, gate_ready, gate_reason = pcall(
                        LA_BRIDGE.install_apply_gate)
                    if not gate_ok then
                        reason = "post_commit:" .. tostring(gate_ready)
                        registered = false
                    elseif gate_ready ~= true then
                        reason = "post_commit:" .. tostring(
                            gate_reason or "la_apply_not_ready")
                        registered = false
                    else
                        local post_ok, post_error = pcall(function()
                            -- v0.8.31 REVERT: skin injection (v0.8.29-30) didn't match
                            -- the user's "shield and main weapon are changed separately"
                            -- mental model. Restore the row-2 LA merge so LA shields
                            -- show up in the offhand picker again.
                            _merge_la_offhand_options()
                            if mod._la_restore_offhand_selections then
                                mod._la_restore_offhand_selections()
                            end
                        end)
                        if post_ok then
                            state.la_registration_failure = nil
                            _la_bridge_init_done = true
                            ctx.set_la_bridge_init_done(_la_bridge_init_done)
                        else
                            reason = "post_commit:" .. tostring(post_error)
                            registered = false
                        end
                    end
                elseif not call_ok then
                    reason = "register_error:" .. tostring(registered)
                    registered = false
                end
                if not registered and state.la_registration_failure ~= reason then
                    -- allow-perframe: edge-triggered; identical retry failures are silent
                    mod:info("[LA bridge] registration deferred: %s", tostring(reason))
                    state.la_registration_failure = reason
                end
            end
        end
        -- Native/CWV hand persistence is independent of LA. Retry until backend
        -- items and (when installed) CWV's generated pools are available.
        if not mod._la_offhand_restore_done and ItemMasterList
                and mod._la_restore_offhand_selections then
            mod._la_restore_offhand_selections()
        end
        -- v0.9.0.4-hotfix: bulk-preload every offhand-pool + custom-illusion unit
        -- on this peer so cross-character shield equips (host's "GK Shield Blue"
        -- etc.) don't crash this peer's husk wield path. Defer until LA bridge
        -- has finished registering (so LA's la_offhand_options_by_weapon_type is
        -- populated and gets included). Even when bridge init is skipped (no MIL),
        -- this still pre-loads the vanilla _offhand_options + _custom_illusions
        -- meshes, which is enough for non-LA picks. Function is idempotent.
        if _force_load_all_offhand_packages then _force_load_all_offhand_packages() end
        if LA_BRIDGE.registered then _install_skin_loadout_safety() end
        -- #376: wait until all local-backend injectors have had time to restore,
        -- then retire exact-item overrides whose item no longer exists. Vanilla's
        -- item interface is a direct backend-mirror lookup
        -- (backend_interface_item_playfab.lua:384-389). CIM's persisted registry
        -- is an additional authority during its mirror-rebuild window.
        if _la_bridge_init_done and not mod._la_persist_prune_done and LA_PERSIST
                and LA_PERSIST.prune_missing_items then
            mod._la_persist_prune_at = mod._la_persist_prune_at or (_now() + 10)
            if _now() >= mod._la_persist_prune_at then
                -- Issue 695: retried per frame once armed; probe _interfaces before
                -- get_interface so the pre-ready miss path can't warn every frame.
                local backend_mgr = Managers and Managers.backend
                local backend_items = backend_mgr and backend_mgr._interfaces
                    and backend_mgr._interfaces.items
                    and backend_mgr:get_interface("items")
                if backend_items and backend_items.get_item_from_id then
                    local removed = LA_PERSIST.prune_missing_items(function(backend_id)
                        local ok, item = pcall(backend_items.get_item_from_id,
                            backend_items, backend_id)
                        if ok and item then return true end
                        for _, mod_name in ipairs({ "crafting_in_modded", "crafting_in_modded_dev" }) do
                            local cim = get_mod(mod_name)
                            local forged = cim and cim:get("forged_weapons")
                            if type(forged) == "table" and forged[backend_id] then return true end
                        end
                        if not ok then return nil end
                        return false
                    end)
                    mod._la_persist_prune_done = true
                    if printf then printf("[la-state] INSTANCE-PRUNE %d missing item override(s) removed", removed) end
                end
            end
        end
        if mod._glow_scan_tick then mod._glow_scan_tick(dt) end; GlowPicker.ensure_cim_bridge()
        if mod._la_shield_probe_tick then mod._la_shield_probe_tick(dt) end
        -- v0.9.49-dev (#186): deferred one-time scrub of LA's Okri's-Challenge
        -- templates once LA has registered them. No-op after it fires (or while
        -- the toggle is off / LA absent).
        if LA_OKRI and LA_OKRI.tick then LA_OKRI.tick(dt) end
        -- v0.9.2-hotfix: drain LA cos_la_apply emits that deferred because the
        -- network host wasn't resolvable at emit time. Runs every frame; bails
        -- fast when queue is empty.
        if mod._drain_deferred_la_emits then mod._drain_deferred_la_emits() end

        -- v0.9.70-dev (#267, Slice 2b / I9): send the pull-on-ready state request
        -- armed by on_game_state_changed. Client-only (the host owns the store);
        -- waits until a host peer_id is resolvable, then fires exactly once per
        -- arming. The request's arrival at the host proves this peer is a live
        -- session member, so the host's targeted replies cannot lose the
        -- pre-ingame race that killed the push model.
        if mod._la_state_pull_pending then
            if _is_local_server() then
                mod._la_state_pull_pending = nil
            else
                -- v0.9.71-dev: retry-until-acked. One send proved lossy in the
                -- 2026-07-06 session (packets to/from a still-loading peer vanish
                -- silently); the pull now repeats every 5s until the host's
                -- cos_la_state_ack arrives, capped at 8 attempts.
                local st = mod._la_state_pull_pending
                if type(st) ~= "table" then st = { attempts = 0, next_at = 0 }; mod._la_state_pull_pending = st end
                local now_p = _now()
                if now_p >= (st.next_at or 0) then
                    local pull_host = _host_peer_id()
                    -- v0.9.72-dev: after leaving a session the resolver can hand
                    -- back OUR OWN peer id while _is_local_server() is still
                    -- transiently false (18:30:42 log: 8 retries against self).
                    -- A self-targeted pull is meaningless - drop the arming.
                    local self_peer = _local_peer_id_quick()
                    if pull_host and self_peer and pull_host == self_peer then
                        mod._la_state_pull_pending = nil
                        pull_host = nil
                    end
                    if pull_host then
                        if st.attempts >= 8 then
                            if printf then printf("[la-state] STATE-PULL GAVE UP after %d unacked attempts (host=%s) - re-arm queued for next replay edge",
                                st.attempts, tostring(pull_host)) end
                            mod._la_state_pull_pending = nil
                            -- #267 follow-up: exhaustion is no longer terminal for
                            -- the session. The next bounded replay edge (peer-ready /
                            -- session-ready / lobby-return) re-arms the pull so a
                            -- cold-joiner that lost the whole 8-attempt window still
                            -- gets another chance instead of running the rest of the
                            -- session with no replayed store.
                            mod._la_state_pull_exhausted = true
                        else
                            st.attempts = st.attempts + 1
                            st.next_at = now_p + 5
                            if printf then printf("[la-state] STATE-PULL req -> host=%s (attempt %d/8)",
                                tostring(pull_host), st.attempts) end
                            mod:network_send("cos_la_state_req", pull_host, COS_RPC_SCHEMA, {})
                        end
                    end
                end
            end
        end

        -- v0.9.71-dev: execute deferred peer purges (see the remove_player hook -
        -- transitions schedule-and-cancel; only genuine leaves reach execution).
        if mod._la_tick_peer_purges then mod._la_tick_peer_purges() end

        -- v0.9.0-dev: TPE per-frame tick was previously in a now-deleted earlier
        -- mod.update definition that this one overwrote. Restoring here.
        if TPE and TPE.update then TPE.update(dt) end

        -- v0.9.0-dev: pump glow-state broadcast pending re-emits.
        if mod._glow_sync_tick then mod._glow_sync_tick(dt) end

        -- #574: local material-only convergence for a snapshot that beat the
        -- remote husk's equipment spawn. Quarter-second cadence, 40 attempts/10s
        -- maximum, and no network send in the tick.
        if mod._cos574_glow_rehydrate_tick then mod._cos574_glow_rehydrate_tick() end

        -- v0.8.67-dev: drain the cos_la_apply pending queue. Entries that can't
        -- apply yet (wearer unit not spawned, husk not wielding the right slot)
        -- get retried each frame until they succeed or their 5-second deadline
        -- expires. Bounded retry prevents the queue from leaking on rare cases
        -- where a wearer's unit never spawns (e.g. player disconnected before
        -- replicating into our game session).
        if _la_pending_apply and #_la_pending_apply > 0 then
            local now = _now()
            local kept = {}
            for i = 1, #_la_pending_apply do
                local entry = _la_pending_apply[i]
                local wp, slot, deadline = entry[1], entry[2], entry[6]
                -- v0.9.70-dev (Slice 2 / I3): retries route through the single
                -- reconcile entry point (paint + gated mesh pulse; mod.update is a
                -- safe pulse context). reason=="no-entry" is terminal -- a revert
                -- deleted the store entry, so retrying would re-impose a cosmetic
                -- the wearer already dropped.
                local applied_now, reason = mod._la_reconcile(wp, slot, "retry", true)
                -- #518: "deus-yield" is terminal like "no-entry" - retrying inside a
                -- deus run can never succeed and would just spin to the deadline.
                if not applied_now and reason ~= "no-entry" and reason ~= "deus-yield" and now < deadline then
                    kept[#kept + 1] = entry
                end
            end
            _la_pending_apply = kept
            ctx.set_la_pending_apply(_la_pending_apply)
        end
        end
    end

    mod.update = state.update
    state.owner = state.owner or { update = state.update }
    return state.owner
end

return M
