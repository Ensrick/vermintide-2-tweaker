-- _cos_mod_lifecycle.lua
-- Mod-wide transition and teardown lifecycle owner.

local M = {}

function M.install(mod, deps)
    if mod._cos_mod_lifecycle_owner then
        return mod._cos_mod_lifecycle_owner
    end

    deps = deps or {}
    local trace = assert(deps.trace, "trace required")
    local mh_embed = deps.mh_embed
    local tpe = deps.tpe
    local la_bridge = deps.la_bridge

    mod.on_game_state_changed = function(status, state_name)
        -- [heap-probe] v0.9.35-dev: per-state-transition lua_heap sampler, mirror of
        -- weapon_tweaker's, for the 1 GiB lua_heap OOM diagnosis. cosmetics is the
        -- once the largest UNMEASURED suspect: before #565 it sync-loaded 74
        -- offhand/shield packages at startup. They are now asynchronously queued and
        -- released on unload. Logs absolute heap + delta so a keep-only ramp
        -- is visible. No forced collect (would mask a retained leak). Debug-gated.
        local kb = collectgarbage("count")
        local since_last = mod._heap_probe_last_kb and (kb - mod._heap_probe_last_kb) or 0
        mod:debug("[heap-probe] %s/%s: %.1f MB (%.0f KB), since last transition: %+.0f KB",
            tostring(state_name), tostring(status), kb / 1024, kb, since_last)
        mod._heap_probe_last_kb = kb
        -- v0.9.43-dev TRANSITION trace: world/mission/keep load + game-state change.
        -- Anchors the area-load drop (#3) and the mission-load timeline in the trace.
        trace("TRANSITION game_state %s/%s", tostring(state_name), tostring(status))
        -- #282: Material-Hijack packages are process-session resident. Current
        -- logs prove that both the PRE state notification and the POST
        -- StateIngame.on_exit hook are too early to release renderer-backed
        -- material graphs. Report the bounded ownership state here without
        -- mutating it; PackageManager.destroy is the sole release owner.
        if status == "exit" and state_name == "StateIngame"
                and mh_embed and mh_embed.reference_summary then
            local s = mh_embed.reference_summary()
            pcall(printf,
                "[cos:282] session-retained boundary=StateIngame/exit held=%d exact=%d over=%d missing=%d teardown_owner=PackageManager.destroy",
                tonumber(s.held) or 0, tonumber(s.exact) or 0,
                tonumber(s.over) or 0, tonumber(s.missing) or 0)
        end
        mod._cos.apply_cosmetic_unlocks()
        -- v0.9.0-dev: retry deferred _G.apply_material_settings hook (lazy-loaded
        -- by Stingray flow graph on first hub/level enter).
        if mod._try_install_flow_glow_hook then mod._try_install_flow_glow_hook() end
        -- v0.9.0-dev: rebroadcast local glow state on every state transition.
        -- Covers fresh keep entry, mission start, post-host-migration. Cheap
        -- (~50 char RPC), and ensures peers' caches resync if connectivity
        -- glitched.
        if mod._on_glow_setting_changed then mod._on_glow_setting_changed() end

        -- v0.9.4: rebroadcast LOCAL LA equips on game-state change. Covers the
        -- hot-join asymmetry where PC-A joins PC-B's lobby with an already-
        -- equipped LA shield -> PC-B never receives it because PC-B's host-side
        -- hot-join replay walks `_la_equips_by_peer[joiner]` which is EMPTY
        -- (PC-A's state isn't there yet). Symptom from 2026-05-21 20:14:46
        -- test: PC-A's shield arrived 43s late via a different mechanism.
        -- Fix: PC-A itself re-emits its `_local_la_equips` on every state
        -- change. Drain logic lives in mod.update (after locals are declared).
        mod._la_self_rebroadcast_pending = true

        -- v0.9.70-dev (#267, LA_SYNC_CORE_AUDIT Slice 2b / invariant I9): PULL ON
        -- READY. Every push timed off "peer appeared" loses the 17-25ms race
        -- against the receiver's peer_ingame flip (#267 hot-join, #233
        -- transition), and a hot-joiner's empty store cannot self-heal. So the
        -- JOINER asks: once our own game state is provably ingame, request the
        -- host's full LA store (drained in mod.update once a host peer_id is
        -- resolvable -- flag only here; _is_local_server/_host_peer_id live
        -- lexically below this function).
        if status == "enter" and state_name == "StateIngame" then
            -- v0.9.71-dev: fresh retry state per arming. The 17:28:26 pull in the
            -- 2026-07-06 session fired once into the host's load window and was
            -- lost with no ack and no re-send (host log shows no REQ/reply) - the
            -- exact I9 fire-and-forget failure the pull was meant to fix. Now the
            -- drain re-sends every 5s until the host's cos_la_state_ack lands
            -- (max 8 attempts).
            mod._la_state_pull_pending = { attempts = 0, next_at = 0 }
        end

        -- v0.9.65-dev (#233): arm a bounded, per-frame CLIENT-side re-apply of every
        -- REMOTE peer's cached LA offhand/illusion equip after a level transition. The
        -- self-rebroadcast above only re-emits the LOCAL player's equips to the network;
        -- it does NOT restore a remote wearer's shield/illusion on THIS machine. The host's
        -- own post-transition rebroadcast races ahead of a still-loading client (the client's
        -- peer_ingame flips true ~25ms AFTER the host emits, so the "all" send never
        -- reaches it) and nothing re-sends -- so the host's LA offhand reverted on the
        -- client at every mission<->keep transition. `_la_equips_by_peer` survives
        -- transitions (only cleared on peer disconnect), so we already hold the
        -- authoritative data locally; the mod.update drain (search
        -- `_la_reapply_remote_until`) walks it and re-drives the recv/retry apply (texture
        -- re-paint + kind="unit" mesh pulse) until each remote wearer converges. Refreshed
        -- on every state callback; the last one (StateIngame/enter) sets the ~10s window
        -- from load-done.
        mod._la_reapply_remote_until = os.clock() + 10

        -- #660 S3: fire the bounded appearance-replay reconciler at the mission /
        -- lobby transition edge. Every StateIngame enter destroys and respawns the
        -- remote husks, so invalidate the coalescing scope: the freshly spawned
        -- husks re-apply the surviving persisted stores through the same proven
        -- machinery, coalesced so nothing re-fires per frame. The edge is named
        -- lobby-return in the keep and session-ready in a mission (identical
        -- behaviour; the name is only for the bounded [cos:replay] diagnostic).
        -- Records that defer here (husks still spawning) drain on the per-husk
        -- SimpleHuskInventoryExtension.init peer-ready edge, not by polling.
        if status == "enter" and state_name == "StateIngame" and mod._cos_replay then
            local in_keep = rawget(_G, "DamageUtils") and DamageUtils.is_in_inn or false
            mod._cos_replay.on_edge(in_keep and "lobby-return" or "session-ready",
                { invalidate_all = true })
        end

        -- v0.9.13-dev: snapshot LA state on every game-state change. Gated on the
        -- debug_dumps toggle. Fires on inn entry, mission entry, mission exit -
        -- so any later spawn / equip event in the log has a baseline to compare
        -- against. No-op when the toggle is off.
        if mod._la_dump_mission_state then
            mod._la_dump_mission_state("game_state_change")
        end

        -- Glow state restores on equipment spawn; editor opening is manual.
    end

    mod.on_disabled = function()
        if tpe and tpe.flush then tpe.flush() end
        -- audit 2026-06-07 (F7): restore LA.apply_new_skin_from_texture so an
        -- in-session F4 disable doesn't leave LA's own recolor permanently blocked
        -- for bridge-managed keys until restart. Injected IML/NetworkLookup entries
        -- can't be safely torn down mid-session, so we only undo the apply gate.
        if la_bridge and la_bridge.uninstall_apply_gate then
            la_bridge.uninstall_apply_gate()
        end
    end

    -- CLARIFY: Ctrl+Shift+R (hot-reload) is UNSAFE for cosmetics_tweaker - see
    -- feedback_hot_reload_unfixable.md. Engine holds C++ resource locks on
    -- spawned units / loaded materials that Lua can't release. Do NOT add a
    -- mod.on_reload handler that pretends to clean up; it would mislead users
    -- into thinking hot-reload is safe.
    mod.on_unload = function()
        mod:info("[unload] cosmetics_tweaker unloading")
        if mod._release_offhand_packages then
            mod._release_offhand_packages("mod_unload")
        end
        -- #282: do NOT release Material-Hijack packages here. VMF hot reload and
        -- mod disable can occur while native renderer consumers remain alive.
        -- The bounded session reference is intentionally drained by
        -- PackageManager.destroy during process teardown.
    end

    local owner = {
        on_game_state_changed = mod.on_game_state_changed,
        on_disabled = mod.on_disabled,
        on_unload = mod.on_unload,
    }
    mod._cos_mod_lifecycle_owner = owner
    return owner
end

return M
