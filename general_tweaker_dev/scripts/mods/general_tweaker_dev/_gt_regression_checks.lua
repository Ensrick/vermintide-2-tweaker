-- _gt_regression_checks.lua — General Tweaker runtime regression registrations.
--
-- Owns the engine-facing assertion closures invoked by /gt_regression_test.
-- The entry point supplies the registration function and its private marker
-- constants; live subsystem state is read from the mod table when tests run.
--
-- Owned by: general_tweaker_dev.lua entry point. Consumed via: mod:dofile.

local M = {}

function M.install(mod, _rt_register, deps)
    deps = deps or {}
    local CT_GT_PICKUP_LOOKUP_RAWGET_MARKER_v0_2_48 =
        deps.CT_GT_PICKUP_LOOKUP_RAWGET_MARKER_v0_2_48
    local CT_GT_AI_CLIENT_SEND_MARKER_v0_2_52 =
        deps.CT_GT_AI_CLIENT_SEND_MARKER_v0_2_52
    local _dbg = deps.dbg
    local _dbg_alert = deps.dbg_alert
    -- ============================================================
    -- /regression_test checks (see scaffold near MOD_VERSION).
    -- ============================================================
    -- The task spec mentioned a `skip_splash_hook_installed` check + a
    -- `collision_disable_one_indexed` check, but the current gt source has no
    -- StateSplashScreen hook (skip-splash is delegated to a different mod) and no
    -- collision-disable loop (collision filtering is field-based, not loop-based).
    -- Both skipped here. (The Skip Cutscenes feature — and its two regression checks
    -- cutscene_auto_skip_deferred / cutscene_skip_setting_id_present — MIGRATED to
    -- gui_tweaker (gut) 2026-06-25, issue #106. Those checks now live in gut.)

    _rt_register("gt_pickup_lookup_uses_rawget", function()
        -- v0.2.47/.48: `_gt_is_spawn` resolves the chat-supplied pickup name through
        -- `rawget(NetworkLookup.pickup_names, pickup_name)` (~L3553) so an unknown
        -- name echoes "Unknown pickup name: ..." instead of raising the strict
        -- `__index` metatable. The strict-table-lookup lint covers static-pattern
        -- regressions; this runtime check is the belt-and-suspenders companion
        -- required by §15 of PROJECT_STANDARDS.md.
        --
        -- 1. Source-pattern: the marker constant must be present.
        if CT_GT_PICKUP_LOOKUP_RAWGET_MARKER_v0_2_48 ~= "gt-pickup-lookup-rawget-hardened" then
            return "RAWGET marker absent — was the v0.2.47 pickup-lookup hardening reverted?"
        end
        -- 2. Runtime-state: probe rawget on a known-bad key — must return nil
        --    without raising. If pickup_names ever loses its strict metatable,
        --    this still passes; if it grows one with broken handling, this fails.
        local NL = rawget(_G, "NetworkLookup")
        local pn = NL and NL.pickup_names
        if type(pn) == "table" then
            local ok, value = pcall(rawget, pn, "__gt_rawget_probe_does_not_exist__")
            if not ok then
                return "rawget(NetworkLookup.pickup_names, <bad-key>) RAISED — strict-metatable behavior changed"
            end
            if value ~= nil then
                return "rawget(NetworkLookup.pickup_names, <bad-key>) returned non-nil — unexpected"
            end
        end
    end)

    _rt_register("ai_takeover_marker_present", function()
        -- v0.2.52 source-pattern guard. If a future refactor strips the marker
        -- constant or the v0.2.52 fix gets reverted, this fails. Belt-and-
        -- suspenders for the runtime queue test below — the queue test would
        -- still pass even if `mod._gt_ai_handle_toggle_change` deleted the ping call.
        if CT_GT_AI_CLIENT_SEND_MARKER_v0_2_52 ~= "gt-ai-client-send-vmf-rehandshake" then
            return "AI client-send marker absent — was the v0.2.52 fix reverted?"
        end
    end)

    _rt_register("ai_takeover_vmf_ping_api_available", function()
        -- v0.2.52: AI Takeover client send now calls `get_mod("VMF").ping_vmf_users()`
        -- before each emit to force VMF to re-handshake when `_vmf_users` has gone
        -- stale (bot-churn at mission load drops the host — see send-queue comment
        -- in this file). If VMF ever renames or removes this entry point, the
        -- workaround silently no-ops via the pcall and every client toggle would
        -- silently drop again. Pin both the mod presence and the function shape.
        local vmf = get_mod("VMF")
        if not vmf then
            return "VMF mod not loaded — `get_mod('VMF')` returned nil"
        end
        if type(vmf.ping_vmf_users) ~= "function" then
            return "vmf.ping_vmf_users is not a function (type=" .. type(vmf.ping_vmf_users) .. ")"
        end
    end)

    _rt_register("ai_takeover_client_send_queue_wired", function()
        -- v0.2.52: client-side toggle now enqueues into `mod._gt_ai_pending_client_send`
        -- with retries instead of sending inline. The mod.update consumer must
        -- be wired into the existing update chain — without it the queue would
        -- fill and never drain. Verify the consumer function exists in the file's
        -- closure scope by walking the queue forward via a synthetic enqueue and
        -- asserting mod.update drains it.
        --
        -- We don't actually exercise the network send (no real peer in regression
        -- harness); we just verify the queue shape + drain behavior using a
        -- guaranteed-elapsed `next_at`. Restore the prior queue state on exit.
        local saved = mod._gt_ai_pending_client_send
        mod._gt_ai_pending_client_send = {
            host = "__rt_probe_peer__",
            want_bot = true,
            retries_left = 1,
            next_at = os.clock() - 1.0,  -- already-elapsed so the first tick fires
        }
        -- Drive one mod.update tick. The consumer should fire (next_at elapsed),
        -- decrement retries to 0, and clear the queue.
        if type(mod.update) ~= "function" then
            mod._gt_ai_pending_client_send = saved
            return "mod.update is not a function — update chain broken"
        end
        local ok, err = pcall(mod.update, 0.016)
        if not ok then
            mod._gt_ai_pending_client_send = saved
            return "mod.update raised during client-send drain probe: " .. tostring(err)
        end
        if mod._gt_ai_pending_client_send ~= nil then
            mod._gt_ai_pending_client_send = saved
            return "client-send queue did not drain after one tick (consumer not wired into mod.update?)"
        end
        mod._gt_ai_pending_client_send = saved
    end)

    _rt_register("dbg_helpers_two_channel", function()
        if type(_dbg) ~= "function" then return "_dbg helper missing" end
        if type(_dbg_alert) ~= "function" then return "_dbg_alert helper missing" end
        local ok = pcall(_dbg, "smoke test")
        if not ok then return "_dbg raised" end
        ok = pcall(_dbg_alert, "smoke test")
        if not ok then return "_dbg_alert raised" end
    end)

    _rt_register("necro_potion_give_half_targeted_promote", function()
        -- v0.2.138-dev (FIX 1 give-half completion). The Necromancer-bot potion
        -- promote must target the REAL potion BY IDENTITY (SwapFromStorageType.Same
        -- + the potion's item_data), not storage index 1 (SwapFromStorageType.First).
        -- slot_potion storage can also hold the grimoire (non-giveable) and the
        -- demoted skull, so a First-swap could promote the wrong occupant -> primary
        -- stays non-giveable -> the give never resolves -> the bot loops "trying to
        -- pass but can't". Pin both halves:
        --   1) the source-pattern marker constant is present, AND
        --   2) the SwapFromStorageType.Same enum member exists (the swap mode we rely
        --      on for identity promotion). If vanilla ever drops it, the promote
        --      would silently no-op the targeted path.
        if GT_NECRO_POTION_GIVE_HALF_MARKER_v0_2_138 ~= "gt-necro-potion-give-half-targeted-promote" then
            return "give-half marker absent — was the v0.2.138 targeted-promote reverted to a blind First-swap?"
        end
        local sfs = rawget(_G, "SwapFromStorageType")
        if type(sfs) ~= "table" then
            return "SwapFromStorageType enum table missing"
        end
        if sfs.Same == nil then
            return "SwapFromStorageType.Same absent — identity promotion can't target the real potion"
        end
    end)

    _rt_register("gt355_suicide_down_vanilla_rpc_path", function()
        -- Issue 355 /suicide + /down. Both commands lean on VANILLA client->server
        -- request RPCs (rpc_request_insta_kill / rpc_request_knock_down) instead of a
        -- modded NetworkLookup key, which is what makes them safe as host AND client
        -- and immune to the #278/#371 wire-safety class. Pin all three load-bearing
        -- pieces so a refactor (or a vanilla API rename) is caught at load:
        --   1) both command bodies are wired as public mod. fields,
        --   2) the source marker constant is present (guards against silently
        --      reverting to a local kill_unit / set_knocked_down field write), and
        --   3) the two vanilla RPCs + the damage_type we send still exist.
        if type(mod.gt_suicide) ~= "function" then return "mod.gt_suicide missing" end
        if type(mod.gt_down) ~= "function" then return "mod.gt_down missing" end
        if mod._GT_355_SELF_STATE_MARKER ~= "gt-355-suicide-down-vanilla-rpc" then
            return "self-state marker absent -- did /suicide or /down revert to a local (desyncing) write?"
        end
        local rpc = rawget(_G, "RPC")
        if type(rpc) ~= "table" then return "RPC global table missing" end
        if rpc.rpc_request_insta_kill == nil then
            return "RPC.rpc_request_insta_kill absent -- vanilla self-kill path renamed?"
        end
        if rpc.rpc_request_knock_down == nil then
            return "RPC.rpc_request_knock_down absent -- vanilla self-knockdown path renamed?"
        end
        if not (NetworkLookup and NetworkLookup.damage_types and NetworkLookup.damage_types.forced) then
            return "NetworkLookup.damage_types.forced absent -- /suicide has no damage type to send"
        end
    end)



    _rt_register("localization_format_safe", function()
        -- Layer 3 (2026-05-25): catch unescaped %-format chars in loc strings at
        -- runtime. VMF's tooltip render path calls string.format on the loc value;
        -- literal "%APPDATA%" / "5%" / "%USERNAME%" raises 'invalid option' and
        -- shows as a red error tooltip in the VMF settings UI. Static check is
        -- qa/check_localization.ps1 -- this is its runtime twin so the bug can't
        -- ship even if the static check is skipped. RULE: any literal % in a loc
        -- string must be doubled to %%.
        local ok, loc = pcall(mod.dofile, mod, "scripts/mods/general_tweaker_dev/general_tweaker_dev_localization")
        if not ok or type(loc) ~= "table" then return end  -- can't reach loc; skip
        for k, v in pairs(loc) do
            if type(v) == "table" and type(v.en) == "string" then
                local fmt_ok, fmt_err = pcall(string.format, v.en)
                if not fmt_ok then
                    return string.format(
                        "loc key %q has invalid format string (escape literal %% as %%%%): %s",
                        k, tostring(fmt_err))
                end
            end
        end
    end)

    -- v0.2.60-dev: VMF_RECIPES § 10 / Issue #43 -- assert the gt_lobby RPC schema
    -- constant is in place. Migrated from lt v0.1.7-dev when its `lt_motd_show`
    -- RPC was absorbed as `gt_lobby_motd_show`.
    _rt_register("gt_lobby_rpc_schema_present", function()
        if type(mod.GT_LOBBY_RPC_SCHEMA) ~= "number" then
            return "mod.GT_LOBBY_RPC_SCHEMA not defined as number"
        end
        if mod.GT_LOBBY_RPC_SCHEMA < 1 then
            return "mod.GT_LOBBY_RPC_SCHEMA < 1"
        end
    end)

    -- v0.2.167-dev: VMF_RECIPES § 10 / Issue #44 -- assert the AI-control RPC schema
    -- constant is in place (mirrors gt_lobby_rpc_schema_present). The
    -- `gt_ai_toggle_request` sender + receiver in _gt_ai_takeover.lua both read
    -- mod.GT_AI_RPC_SCHEMA; if it goes missing the receiver gate compares against nil
    -- and would accept anything, so guard it here.
    _rt_register("gt_ai_rpc_schema_present", function()
        if type(mod.GT_AI_RPC_SCHEMA) ~= "number" then
            return "mod.GT_AI_RPC_SCHEMA not defined as number"
        end
        if mod.GT_AI_RPC_SCHEMA < 1 then
            return "mod.GT_AI_RPC_SCHEMA < 1"
        end
    end)

    -- v0.2.208-dev: VMF_RECIPES § 10 / issue 534 -- assert the shared-debug-draw RPC
    -- schema constant is in place (mirrors the gt_lobby / gt_ai checks). The
    -- `gt_draw_leash` sender + receiver in _gt_bot_teleport_lab.lua both read
    -- mod.GT_DRAW_RPC_SCHEMA; a missing const would make the receiver gate compare
    -- against nil and accept any payload.
    _rt_register("gt_draw_rpc_schema_present", function()
        if type(mod.GT_DRAW_RPC_SCHEMA) ~= "number" then
            return "mod.GT_DRAW_RPC_SCHEMA not defined as number"
        end
        if mod.GT_DRAW_RPC_SCHEMA < 1 then
            return "mod.GT_DRAW_RPC_SCHEMA < 1"
        end
    end)

    -- v0.2.208-dev: issue 534 -- assert the bot-leash-line share path (host send +
    -- receiver + client draw consumer) is wired. The marker is set at LOAD in
    -- _gt_bot_teleport_lab.lua after the network event and the shared_draw update
    -- consumer are both registered. Runtime-only (no io source-grep; io is nil in
    -- the VMF sandbox).
    _rt_register("gt534_leash_share_wired", function()
        if mod._gt534_leash_share_wired ~= true then
            return "leash-line share not wired (issue 534: _gt_bot_teleport_lab.lua)"
        end
    end)

    -- audit 2026-06-07 (F3, v0.2.80-dev): event-registration clobber. The three
    -- lobby modules (slot_reservations, session_ignore, motd) used to each register
    -- (mod, "on_player_joined_party") -- EventManager keys by (object, event_name)
    -- so last-writer-wins meant only ONE fired. They now append to a single shared
    -- dispatcher. This test FAILS if a module reverts to self-registration (its
    -- handler would be absent from the shared list) or the consolidation is dropped.
    _rt_register("gt_lobby_join_dispatch_consolidated", function()
        local handlers = mod._gt_lobby_join_handlers
        if type(handlers) ~= "table" then
            return "mod._gt_lobby_join_handlers missing (shared dispatcher not installed)"
        end
        if type(mod.gt_lobby_on_player_joined_party) ~= "function" then
            return "mod.gt_lobby_on_player_joined_party (single registered method) missing"
        end
        -- All three join-handlers must be reachable from the single dispatch list.
        local want = { session_ignore = false, slot_reservations = false, motd = false }
        for i = 1, #handlers do
            local h = handlers[i]
            if h and want[h.name] ~= nil then
                if type(h.fn) ~= "function" then
                    return "join-handler '" .. tostring(h.name) .. "' is not a function"
                end
                want[h.name] = true
            end
        end
        for name, present in pairs(want) do
            if not present then
                return "join-handler '" .. name .. "' not registered on the shared dispatcher"
            end
        end
    end)

    -- audit 2026-06-07 (F3): the single dispatcher must (a) strip the EventManager
    -- object-prepend so handlers get the true peer_id, and (b) invoke EVERY handler
    -- even if an earlier one raises (pcall isolation). We swap the live handler list
    -- for two synthetic handlers (so the real session_ignore/slot_reservations/motd
    -- logic never runs against a fake peer), drive the dispatcher the way
    -- EventManager.trigger does (object prepended), then restore the real list.
    _rt_register("gt_lobby_join_dispatch_pcall_isolated", function()
        local handlers = mod._gt_lobby_join_handlers
        if type(handlers) ~= "table" or type(mod.gt_lobby_on_player_joined_party) ~= "function" then
            return "shared dispatcher not installed"
        end
        -- Snapshot + clear the live list so we test only our synthetic handlers.
        local saved = {}
        for i = 1, #handlers do saved[i] = handlers[i]; handlers[i] = nil end
        local function restore()
            for i = #handlers, 1, -1 do handlers[i] = nil end
            for i = 1, #saved do handlers[i] = saved[i] end
        end
        local reached = false
        local got_peer = nil
        handlers[1] = { name = "_rt_raiser", fn = function() error("synthetic raise") end }
        handlers[2] = { name = "_rt_recorder", fn = function(peer_id) reached = true; got_peer = peer_id end }
        -- EventManager.trigger calls object[name](object, ...); first real arg is mod.
        local ok = pcall(mod.gt_lobby_on_player_joined_party, mod, "peer123", 1, 0, 1, false)
        restore()
        if not ok then
            return "dispatcher itself raised (handler pcall isolation broken)"
        end
        if not reached then
            return "second handler never ran after first raised (no pcall isolation)"
        end
        if got_peer ~= "peer123" then
            return "handler received wrong peer_id (object-prepend not stripped): got " .. tostring(got_peer)
        end
    end)

    -- audit 2026-06-07 (F4, v0.2.80-dev): double consume-once popup race. The
    -- enriched failed-join popup is now polled ONLY by the mod (it is no longer
    -- assigned to StateLoading._popup_id), so the mod's poller must drive the
    -- vanilla restart_as_server teardown itself. This test exercises that driver
    -- against a synthetic StateLoading and asserts it sets the exact fields vanilla
    -- _handle_popup's restart_as_server branch sets (state_loading.lua:1570-1577).
    -- FAILS if the teardown driver is dropped or stops setting either field --
    -- which is the exact symptom of the loading-screen hang the race caused.
    _rt_register("gt_lobby_failnotify_teardown_driver", function()
        local drive = mod._gt_failnotify_drive_teardown
        if type(drive) ~= "function" then
            return "mod._gt_failnotify_drive_teardown missing (F4 teardown driver not installed)"
        end
        -- Synthetic StateLoading-like object with a force_done()-capable view.
        local forced = false
        local fake_sl = {
            _teardown_network = false,
            _permission_to_go_to_next_state = false,
            _first_time_view = { force_done = function() forced = true end },
        }
        local ok, err = pcall(drive, fake_sl)
        if not ok then
            return "teardown driver raised: " .. tostring(err)
        end
        if fake_sl._teardown_network ~= true then
            return "driver did not set _teardown_network=true (loading screen would hang)"
        end
        if fake_sl._permission_to_go_to_next_state ~= true then
            return "driver did not set _permission_to_go_to_next_state=true"
        end
        if forced ~= true then
            return "driver did not force_done the first_time_view"
        end
        -- Must tolerate a nil StateLoading (entry.sl absent) without raising.
        local ok2, err2 = pcall(drive, nil)
        if not ok2 then
            return "teardown driver raised on nil sl: " .. tostring(err2)
        end
    end)

    _rt_register("issue72_lobby_failnotify_never_hands_popup_to_vanilla", function()
        -- F4's other half: the enriched popup is consumed exclusively by GT's
        -- pending registry. StateLoading._popup_id must remain untouched or vanilla
        -- and GT race to consume the same one-shot result. Drive the exact helper
        -- used by the live create_popup hook against a state that traps that write.
        local take_over = mod._gt_failnotify_take_over
        if type(take_over) ~= "function" then
            return "failed-join popup takeover helper missing (Issue #72)"
        end
        local wrote_popup_id = false
        local fake_sl = setmetatable({}, {
            __newindex = function(t, key, value)
                if key == "_popup_id" then wrote_popup_id = true end
                rawset(t, key, value)
            end,
        })
        local queue_called = false
        local ok, owned = pcall(take_over, fake_sl, "body", {}, function(sl, body, diff)
            queue_called = sl == fake_sl and body == "body" and type(diff) == "table"
            return true
        end)
        if not ok then return "popup takeover helper raised: " .. tostring(owned) end
        if owned ~= true or not queue_called then
            return "popup takeover did not retain GT ownership"
        end
        if wrote_popup_id or rawget(fake_sl, "_popup_id") ~= nil then
            return "enriched popup id handed to StateLoading (double-consume race restored)"
        end
    end)

    _rt_register("gt_lobby_failnotify_unknown_result_drives_teardown", function()
        -- v0.2.81 (Issue #72): an unrecognized popup result must NOT silently drop
        -- the pending entry — it logs (ungated) and still drives teardown so the
        -- user is never stranded on the loading screen. Drive the real consumer
        -- with a stub popup manager and a synthetic pending entry.
        local consume = mod._gt_failnotify_consume_results
        local pending = mod._gt_failnotify_pending_popups
        if type(consume) ~= "function" or type(pending) ~= "table" then
            return "consume_results/pending_popups test exports missing (Issue #72 regression)"
        end
        local fake_sl = { _teardown_network = false, _permission_to_go_to_next_state = false }
        local popup_id = "gt_rt_unknown_result_probe"  -- string key can't collide with engine numeric ids
        pending[popup_id] = { diff = nil, sl = fake_sl }
        local stub_mgr = { query_result = function(_, id)
            if id == popup_id then return "some_future_unknown_action" end
        end }
        local ok, err = pcall(consume, stub_mgr)
        pending[popup_id] = nil  -- belt-and-suspenders cleanup regardless of outcome
        if not ok then
            return "consumer raised on unknown result: " .. tostring(err)
        end
        if fake_sl._teardown_network ~= true or fake_sl._permission_to_go_to_next_state ~= true then
            return "unknown result did not drive teardown (user would be stranded on loading screen)"
        end
    end)

    _rt_register("gt_lobby_failnotify_popup_up_soft_defers", function()
        -- v0.2.81 (Issue #72, F17): the popup-already-up branch must soft-defer
        -- (boolean decision), never raise. Pins the truth table.
        local should_defer = mod._gt_failnotify_should_defer
        if type(should_defer) ~= "function" then
            return "should_defer test export missing (F17 soft guard regressed)"
        end
        local ok, a, b, c = pcall(function()
            return should_defer({ _popup_id = 123 }), should_defer({}), should_defer(nil)
        end)
        if not ok then
            return "F17 guard raised instead of soft-deferring: " .. tostring(a)
        end
        if a ~= true then return "popup-up state did not defer (would hit vanilla's assert with our enrichment half-applied)" end
        if b ~= false then return "no-popup state wrongly deferred (enrichment would never fire)" end
        if c ~= false then return "nil self wrongly deferred" end
    end)

    _rt_register("gt_lobby_failnotify_unpack_preserves_leading_nils", function()
        -- v0.2.81 (Issue #72): replica of the create_popup forward idiom
        -- (n = 3 + select('#', ...); unpack(args, 1, n)) under its worst case:
        -- header/action/right_button all nil with trailing format varargs present
        -- (vanilla call site state_loading.lua:1084 passes 2 trailing args). Bare
        -- unpack(args) boundary-searches across the leading nils and can drop the
        -- format args, crashing vanilla's string.format at state_loading.lua:2467.
        local function _forward(header, action, right_button, ...)
            local n = 3 + select("#", ...)
            local args = { header, action, right_button, ... }
            return select("#", unpack(args, 1, n)), (select(n, unpack(args, 1, n)))
        end
        local count, last = _forward(nil, nil, nil, "client_hash", "lobby_hash")
        if count ~= 5 then
            return string.format("forward dropped args across leading nil holes: expected 5, got %d", count)
        end
        if last ~= "lobby_hash" then
            return string.format("trailing format arg lost: expected 'lobby_hash', got %s", tostring(last))
        end
    end)

    _rt_register("gt_lobby378_watchdog_abort_reroutes_to_menu", function()
        -- #378: the join watchdog's load-bearing invariant is that a HUNG join is
        -- rerouted to the main menu. A pure hang leaves _wanted_state = StateIngame
        -- (state_loading.lua:246); the abort delegates to vanilla _destroy_lobby_client,
        -- which sets _wanted_state = StateTitleScreen (state_loading.lua:1144). Pin
        -- that the reroute delegates there and is nil/missing-method safe (else a
        -- refactor that force-teardowns WITHOUT the reroute would silently dump the
        -- user into a broken StateIngame instead of the menu).
        local reroute = mod._gt_join_watchdog_reroute
        if type(reroute) ~= "function" then return "watchdog reroute fn not exported" end
        if type(mod._gt_join_watchdog_tick) ~= "function" then return "watchdog tick fn not exported" end
        local called = false
        local fake_sl = { _wanted_state = "StateIngame_sentinel" }
        fake_sl._destroy_lobby_client = function(s)
            called = true
            s._wanted_state = "StateTitleScreen_sentinel"
        end
        reroute(fake_sl)
        if not called then return "reroute did not delegate to _destroy_lobby_client" end
        if fake_sl._wanted_state ~= "StateTitleScreen_sentinel" then
            return "reroute did not let _destroy_lobby_client redirect _wanted_state to the menu"
        end
        -- A StateLoading missing the method, or nil, must not throw.
        local ok_a = pcall(reroute, {})
        local ok_b = pcall(reroute, nil)
        if not (ok_a and ok_b) then return "reroute raised on a StateLoading without _destroy_lobby_client" end
    end)

    _rt_register("bots_in_keep_helpers_exposed", function()
        -- v0.2.71-dev "Allow Bots in Keep": the early on_setting_changed and
        -- on_game_state_changed closures (declared ~line 830/789) reach into the
        -- feature via mod._bik_* table fields because the file-locals aren't
        -- visible at compile time at those positions. If a future refactor stops
        -- exposing the helpers OR renames them, the on_setting_changed branch
        -- becomes a silent no-op (toggle would still flip the setting but no
        -- bots would ever be added/removed in response).
        for _, name in ipairs({ "_bik_fill", "_bik_clear", "_bik_active", "_bik_reset_bookkeeping" }) do
            if type(mod[name]) ~= "function" then
                return "mod." .. name .. " is not a function (type=" .. type(mod[name]) .. ")"
            end
        end
    end)

    _rt_register("bots_in_keep_active_default_false", function()
        -- _bik_active() must return false when the gt_bots_in_keep setting is
        -- off (default state on fresh install). Catches regressions where the
        -- gate logic gets inverted, the setting_id changes without updating the
        -- gate read, or _bik_active starts throwing on a missing dependency
        -- (Managers.player nil at boot, etc.).
        local saved = mod:get("gt_bots_in_keep")
        if saved == true then mod:set("gt_bots_in_keep", false) end
        local ok, result = pcall(mod._bik_active)
        if saved == true then mod:set("gt_bots_in_keep", true) end
        if not ok then
            return "_bik_active raised: " .. tostring(result)
        end
        if result ~= false then
            return "_bik_active returned " .. tostring(result) .. " with toggle off (expected false)"
        end
    end)

    _rt_register("bots_in_keep_reset_bookkeeping_safe", function()
        -- _bik_reset_bookkeeping is called from on_game_state_changed on EVERY
        -- state transition (StateSplashScreen, StateTitleScreen, StateLoading,
        -- StateIngame, etc.). It must be a pure table reset — no engine calls,
        -- no _remove_bot_instant invocations on Player references that may have
        -- been torn down by state shutdown. Probe by calling it twice in a row
        -- and asserting no raise.
        local ok1, err1 = pcall(mod._bik_reset_bookkeeping)
        if not ok1 then
            return "_bik_reset_bookkeeping raised on first call: " .. tostring(err1)
        end
        local ok2, err2 = pcall(mod._bik_reset_bookkeeping)
        if not ok2 then
            return "_bik_reset_bookkeeping raised on second call (idempotency failure): " .. tostring(err2)
        end
    end)

    _rt_register("bots_in_keep_crashfix_marker_present", function()
        -- v0.2.146-dev: "Allow Bots in Keep" was un-kill-switched after the two
        -- v0.2.74-dev crash classes (#65) were fixed structurally (Photo-Mode port):
        -- teardown via GameModeInn/InnDeus.cleanup_game_mode_units (unregisters bot
        -- stats before the venture stats manager is destroyed -> Bug 1) and fill
        -- gated on _bik_host_in_party1() (-> Bug 2 slot-1 race). If this marker
        -- disappears, the revival was reverted (or the kill-switch came back).
        if GT_BIK_CRASHFIX_MARKER_v0_2_146 ~= "gt-bik-cleanup-and-host-slot-gate" then
            return "bots_in_keep crash-fix marker absent — was the v0.2.146-dev revival reverted?"
        end
    end)

    _rt_register("necromancer_keep_pet_policy_659", function()
        -- #659: human Necromancers may raise in the keep independently of Bots in
        -- Keep. Bot Necromancers retain the roster-toggle gate. A false vanilla
        -- forbidden flag (mission behavior) is never mutated.
        local policy = mod._gt_necro_should_clear_keep_ban
        local reconcile = mod._gt_necro_reconcile_keep_ban
        if type(policy) ~= "function" then return "necromancer keep-pet policy helper missing" end
        if type(reconcile) ~= "function" then return "necromancer keep-pet reconciler missing" end
        if policy(false, false, true) ~= true then return "human keep owner blocked with bots setting off" end
        if policy(false, true, true) ~= true then return "human keep owner blocked with bots setting on" end
        if policy(true, true, true) ~= true then return "bot keep owner blocked while Bots in Keep is on" end
        if policy(true, false, true) ~= false then return "bot keep owner allowed while Bots in Keep is off" end
        if policy(false, true, false) ~= false then return "mission/non-hub state would be mutated" end
        local human = { _player = { bot_player = false }, _pets_forbidden_in_level = true }
        local changed, before, after, owner = reconcile(human, false)
        if changed ~= true or before ~= true or after ~= false or owner ~= "human" then
            return "human initialized extension was not reconciled"
        end
        local bot = { _player = { bot_player = true }, _pets_forbidden_in_level = true }
        changed, before, after, owner = reconcile(bot, false)
        if changed ~= false or before ~= true or after ~= true or owner ~= "bot" then
            return "bot extension ignored the Bots in Keep gate"
        end
        if GT_NECRO_KEEP_PETS_MARKER_v0_2_242 ~= "gt-necro-human-and-bot-keep-pets" then
            return "necromancer human/bot keep-pet marker absent"
        end
        if GT_NECRO_KEEP_PETS_LIFECYCLE_MARKER_659 ~= "gt-necro-extension-ready-reconcile" then
            return "necromancer extension-ready lifecycle marker absent"
        end
    end)

    _rt_register("bot_leash_veto_while_teammate_needs_aid_present", function()
        -- #139 (v0.2.185-dev): the v0.2.148 snap-toward-downed guard + the v0.2.152
        -- side-aid guard were consolidated into ONE blanket leash veto in the
        -- BTConditions.should_teleport hook: with aid-priority ON, a bot never
        -- teleports (vanilla 40 m OR gt tighter leash) while any teammate is
        -- downed/disabled — it paths in to revive (user decision on #139: all bots
        -- converge). Marker + source-pattern check so a refactor that drops the veto,
        -- or lets vanilla's 40 m path through again, gets caught.
        -- #511 (v0.2.202-dev): the veto-conjunction source-grep (io.open) was removed --
        -- io is nil in the VMF sandbox, so it threw and reported FAIL on healthy code.
        -- The marker constant (set at LOAD right beside the veto in _gt_bot_fixes.lua)
        -- already proves the block is present; the exact "_gt_aid_priority_on() and
        -- _gt_any_side_teammate_needs_aid" text invariant is STATIC and belongs in a
        -- repo QA gate (PROJECT_STANDARDS 2.2b tier a).
        if GT_BOT139_LEASH_VETO_AIDPRIORITY_MARKER_v0_2_185 ~= "gt-bot139-teleport-veto-while-teammate-needs-aid" then
            return "bot #139 leash-veto marker absent — was the v0.2.185-dev consolidation reverted?"
        end
    end)

    _rt_register("gt_bot139_needs_aid_status_predicate", function()
        -- #139 (v0.2.192-dev): the leash veto keys off _gt_unit_needs_aid, whose
        -- status -> boolean core is _gt_status_needs_aid: a teammate "needs aid" when
        -- knocked down, hanging from a hook, or ledge-hanging AND not yet pulled up.
        -- Exercise the exact truth table with a STUB status extension so a refactor
        -- that narrows the covered states (or drops the "not pulled up" clause, which
        -- would re-flag an ally who has already been helped up) is caught at load.
        -- Stub tables, not live units: _gt_unit_needs_aid's ALIVE[u] guard reads the
        -- engine POSITION_LOOKUP map (global_utils.lua:15) and rejects a fake key, so
        -- the leaf predicate is the injectable seam.
        local pred = mod._gt_status_needs_aid
        if type(pred) ~= "function" then
            return "mod._gt_status_needs_aid not exposed -- was the #139 leaf seam reverted?"
        end
        local function st(knocked, hook, ledge, pulled)
            return {
                is_knocked_down      = function() return knocked end,
                is_hanging_from_hook = function() return hook end,
                get_is_ledge_hanging = function() return ledge end,
                is_pulled_up         = function() return pulled end,
            }
        end
        local function b(v) return v and true or false end
        local cases = {
            { s = st(true,  false, false, false), want = true,  why = "knocked down" },
            { s = st(false, true,  false, false), want = true,  why = "hanging from hook" },
            { s = st(false, false, true,  false), want = true,  why = "ledge-hanging, not pulled up" },
            { s = st(false, false, true,  true),  want = false, why = "ledge-hanging but already pulled up" },
            { s = st(false, false, false, false), want = false, why = "healthy (no disabler state)" },
            { s = st(false, false, false, true),  want = false, why = "healthy, pulled_up irrelevant" },
        }
        for _, c in ipairs(cases) do
            if b(pred(c.s)) ~= c.want then
                return string.format("_gt_status_needs_aid(%s): want=%s got=%s",
                    c.why, tostring(c.want), tostring(b(pred(c.s))))
            end
        end
    end)

    _rt_register("gt_bot139_teleport_veto_singleton_and_gated", function()
        -- #139 (v0.2.192-dev): the blanket leash veto must live in EXACTLY ONE
        -- BTConditions.should_teleport hook -- VMF silently drops a 2nd hook on the
        -- same (Class, method) (CLAUDE.md non-negotiable 8), which would shadow the
        -- veto. And the veto must gate on aid-priority AND a downed side teammate.
        -- Assert both so a refactor can neither add a duplicate should_teleport hook
        -- nor weaken the gate. Complements bot_leash_veto_..._present (which only
        -- checks the veto conjunction marker) with the singleton count.
        -- #511 (v0.2.202-dev): the source-grep half (io.open) was removed -- io is nil
        -- in the VMF sandbox, so it threw and reported FAIL on healthy code. The
        -- runtime residual (both helper seams exposed) stays. The two STATIC invariants
        -- it grepped move to their correct homes: the "exactly one
        -- BTConditions.should_teleport hook" duplicate-hook count is ALREADY enforced
        -- by tools/mod-lint/lint-mod.ps1 (PROJECT_STANDARDS 2.2b tier a, mod-wide), and
        -- the veto-conjunction / master+sub-gate text belongs in a repo QA gate.
        if type(mod._gt_aid_priority_on) ~= "function" then
            return "mod._gt_aid_priority_on not exposed"
        end
        if type(mod._gt_any_side_teammate_needs_aid) ~= "function" then
            return "mod._gt_any_side_teammate_needs_aid not exposed"
        end
    end)

    _rt_register("gt_bot139_aid_scan_is_side_scoped_not_follow", function()
        -- #139 (v0.2.192-dev) STRUCTURAL + behavioral guard against the exact root
        -- cause: _gt_any_side_teammate_needs_aid must scan the SIDE player list
        -- (side.PLAYER_UNITS via side_by_unit), never the bot's follow target.
        -- Vanilla AIBotGroupSystem._update_move_targets (ai_bot_group_system.lua
        -- :695-719) drops disabled players from the follow-candidate set unless EVERY
        -- human is down, so a follow-scoped aid check is structurally blind to a
        -- teammate who went down while the bot was leashed to a LIVING far player.
        if type(mod._gt_any_side_teammate_needs_aid) ~= "function" then
            return "mod._gt_any_side_teammate_needs_aid not exposed"
        end
        local pred = mod._gt_status_needs_aid
        if type(pred) ~= "function" then return "mod._gt_status_needs_aid not exposed" end

        -- Behavioral: a healthy follow-target stub is NOT aid-worthy, while a knocked
        -- non-follow teammate IS -- so a full side-list scan finds the downed teammate
        -- the (healthy) follow target would otherwise hide.
        local function st(knocked)
            return {
                is_knocked_down      = function() return knocked end,
                is_hanging_from_hook = function() return false end,
                get_is_ledge_hanging = function() return false end,
                is_pulled_up         = function() return false end,
            }
        end
        if (pred(st(false)) and true or false) ~= false then
            return "healthy follow-target stub wrongly classified as needing aid"
        end
        if (pred(st(true)) and true or false) ~= true then
            return "knocked non-follow teammate stub not classified as needing aid"
        end
        -- #511 (v0.2.202-dev): the structural body-grep (io.open, isolating the scan
        -- body to assert it reads side.PLAYER_UNITS/side_by_unit and never "follow")
        -- was removed -- io is nil in the VMF sandbox, so it threw and reported FAIL on
        -- healthy code. The behavioral stub checks above are the runtime residual; the
        -- side-scoped-not-follow SOURCE-TEXT invariant belongs in a repo QA gate
        -- (PROJECT_STANDARDS 2.2b tier a).
    end)

    _rt_register("gt_bot384_needs_aid_or_rescue_predicate", function()
        -- #384 (v0.2.212-dev): the teleport-veto backstop was leashing a bot away from
        -- a downed teammate mid-aid because its scan missed two things -- the
        -- HUMAN-only side.PLAYER_UNITS roster (no bots, no awaiting-rescue) and the
        -- knocked/hook/ledge-only predicate (no pounce / pack-master / tentacle /
        -- chaos-spawn / vortex / corruptor, no awaiting assisted respawn). The backstop
        -- now walks side:player_units() with the BROADER _gt_status_needs_aid_or_rescue
        -- predicate. Exercise the full truth table with a STUB status extension (the
        -- unit boundary can't be stubbed -- _gt_unit_needs_aid_or_rescue_full's ALIVE[u]
        -- guard reads the engine POSITION_LOOKUP map and rejects a fake key), so a
        -- refactor that narrows the covered states is caught at load. The marker guards
        -- the roster+predicate broadening against a silent revert.
        if GT_BOT384_AWAITING_DISABLER_VETO_MARKER ~= "gt-bot384-veto-covers-disablers-and-awaiting-rescue" then
            return "bot #384 broadened-veto marker absent -- was the scan narrowed back?"
        end
        local pred = mod._gt_status_needs_aid_or_rescue
        if type(pred) ~= "function" then
            return "mod._gt_status_needs_aid_or_rescue not exposed -- was the #384 predicate seam reverted?"
        end
        -- All-false stub; flip one branch true per case.
        local function st(o)
            o = o or {}
            local function g(k) return function() return o[k] or false end end
            return {
                is_knocked_down               = g("knocked"),
                is_hanging_from_hook          = g("hook"),
                get_is_ledge_hanging          = g("ledge"),
                is_pulled_up                  = g("pulled"),
                is_pounced_down               = g("pounced"),
                is_grabbed_by_pack_master     = g("packmaster"),
                is_grabbed_by_tentacle        = g("tentacle"),
                is_grabbed_by_chaos_spawn     = g("chaos_spawn"),
                is_in_vortex                  = g("vortex"),
                is_grabbed_by_corruptor       = g("corruptor"),
                is_ready_for_assisted_respawn = g("awaiting"),
            }
        end
        local function b(v) return v and true or false end
        local cases = {
            { s = st{ knocked = true },              want = true,  why = "knocked down" },
            { s = st{ hook = true },                 want = true,  why = "hanging from hook" },
            { s = st{ ledge = true },                want = true,  why = "ledge-hanging, not pulled up" },
            { s = st{ ledge = true, pulled = true }, want = false, why = "ledge-hanging but already pulled up" },
            { s = st{ pounced = true },              want = true,  why = "pounced by gutter runner" },
            { s = st{ packmaster = true },           want = true,  why = "grabbed by pack master" },
            { s = st{ tentacle = true },             want = true,  why = "grabbed by tentacle" },
            { s = st{ chaos_spawn = true },          want = true,  why = "grabbed by chaos spawn" },
            { s = st{ vortex = true },               want = true,  why = "in vortex" },
            { s = st{ corruptor = true },            want = true,  why = "grabbed by corruptor" },
            { s = st{ awaiting = true },             want = true,  why = "awaiting assisted respawn" },
            { s = st{},                              want = false, why = "healthy (no disabler/awaiting state)" },
        }
        for _, c in ipairs(cases) do
            if b(pred(c.s)) ~= c.want then
                return string.format("_gt_status_needs_aid_or_rescue(%s): want=%s got=%s",
                    c.why, tostring(c.want), tostring(b(pred(c.s))))
            end
        end
    end)

    _rt_register("issue139_aid_trace_correlation", function()
        -- #139/#384 (v0.2.243-dev diagnostics): a veto and later action must retain
        -- the same bot/ally identity for a short bounded window. This does not assert
        -- an engine outcome; it locks the pure correlation seam and the production
        -- marker that joins veto -> final selector -> teleport -> #492 state.
        if GT_BOT139_CORRELATED_AID_TRACE_MARKER_v0_2_243
                ~= "gt-bot139-veto-selector-action-correlation" then
            return "bot #139 correlated trace marker absent"
        end
        local policy = mod._gt_teleport_loop_policy
        if type(policy) ~= "table"
                or type(policy.make_aid_veto_trace) ~= "function"
                or type(policy.correlate_aid_veto) ~= "function" then
            return "bot #139 aid trace policy unavailable"
        end
        local aid, follow = {}, {}
        local trace = policy.make_aid_veto_trace(10, aid, follow, "vanilla_40m")
        local age, same = policy.correlate_aid_veto(trace, 12, aid)
        if age ~= 2 or same ~= true then
            return "bot #139 same-ally veto correlation failed"
        end
        age, same = policy.correlate_aid_veto(trace, 20, aid)
        if age ~= nil or same ~= nil then
            return "bot #139 expired veto correlation remained live"
        end
    end)

    _rt_register("gt_bot492_aid_stall_recovery", function()
        -- #492 (reworked v0.2.202-dev): fast, within-down-window recovery for the
        -- aid-priority pursuit lock. Locks THREE things so a refactor can't silently
        -- drop the safety valve:
        --   (1) the marker constant is present,
        --   (2) the pure decision machine (_gt492_step) bails on EITHER a sustained
        --       engine aid-path failure (fast) OR a far no-progress stall (backstop),
        --       never bails a CLOSE (in-range) target, and LATCHES until the ally
        --       clears or the bot gets close again (functional check, no engine reads),
        --   (3) both halves of the actuator are wired in _gt_bot_fixes.lua: the picker
        --       drops the bailed aid pick, and the #139 veto steps aside on the flag.
        if GT_BOT492_AID_STALL_RECOVERY_MARKER_v0_2_198 ~= "gt-bot492-aid-pursuit-stall-recovery" then
            return "bot #492 aid-stall-recovery marker absent -- was the recovery reverted?"
        end

        -- (2) Functional: drive the pure machine. Signature is (state, aid_unit,
        -- aid_dist, path_failed, t). Constants in source: PATH_FAIL_CONFIRM 4 s,
        -- NO_PROGRESS_TIMEOUT 8 s, FAR 20 m, REACHED 12 m, EPSILON 2 m; the margins
        -- below stay clear of those edges so the check does not depend on exact values.
        local step = mod._gt492_step
        if type(step) ~= "function" then
            return "mod._gt492_step not exposed -- the #492 decision machine seam is missing"
        end
        local U, V = "downA", "downB"
        local s, bail

        -- Backstop: far + no closing progress past the timeout must bail, and latch.
        s, bail = step({ aid_unit = nil }, U, 100, false, 0) ; if bail then return "#492: fresh far target must not bail immediately" end
        s, bail = step(s, U, 100, false, 5)                  ; if bail then return "#492: far stall under the no-progress timeout must not bail" end
        s, bail = step(s, U, 100, false, 20)                 ; if not bail then return "#492: far no-progress past the timeout must bail" end
        s, bail = step(s, U, 100, false, 40)                 ; if not bail then return "#492: bail must LATCH while the bot is still far" end
        s, bail = step(s, U, 5,   false, 41)                 ; if bail then return "#492: reaching the ally (close) must clear the latch" end

        -- Close target: an in-range stall (bot fighting next to a reachable revive)
        -- must NEVER bail, no matter how long -- the revive is imminent.
        local c
        c, bail = step({ aid_unit = nil }, U, 8, false, 0)   ; if bail then return "#492: fresh close target must not bail" end
        c, bail = step(c, U, 8, false, 500)                  ; if bail then return "#492: an in-range stall must never bail (revive imminent)" end

        -- Fast path: sustained engine aid-path failure bails quickly (well before the
        -- no-progress backstop). The confirm clock only starts on the FIRST observed
        -- failure (fail_since), so a fresh target's path-fail tick must not bail.
        local p
        p, bail = step({ aid_unit = nil }, U, 100, true, 0)  ; if bail then return "#492: first path-fail tick (fresh target) must not bail" end
        p, bail = step(p, U, 100, true, 2)                   ; if bail then return "#492: path-fail confirm window not yet elapsed must not bail" end
        p, bail = step(p, U, 100, true, 7)                   ; if not bail then return "#492: sustained aid-path failure must bail fast (before the no-progress backstop)" end

        -- A new (different) aid target resets and does not inherit the prior bail.
        local n = { aid_unit = U, best_dist = 100, progress_t = 0, fail_since = nil, bailed = true }
        n, bail = step(n, V, 300, false, 201)                ; if bail then return "#492: a new (different) aid target must reset and not bail" end

        -- No aid target: no bail.
        local _, zb = step({ aid_unit = nil }, nil, nil, false, 600) ; if zb then return "#492: no aid target must not bail" end

        -- (3) Actuator seams present at runtime. #511 (v0.2.202-dev): the source-grep
        -- that asserted the picker calls mod._gt492_should_suppress_pick and the veto
        -- reads blackboard._gt492_bailout was removed -- io is nil in the VMF sandbox,
        -- so it threw and reported FAIL on healthy code. The functional drive above
        -- already exercises the whole decision machine, and the marker constant proves
        -- the actuator block loaded; the two exact source-text wirings belong in a repo
        -- QA gate (PROJECT_STANDARDS 2.2b tier a).
        if type(mod._gt492_should_suppress_pick) ~= "function" or type(mod._gt492_aid_stall_tick) ~= "function" then
            return "mod._gt492 actuator seams not exposed -- picker suppression / stall tick missing"
        end
    end)

    _rt_register("gt_bot515_teleport_latch_rearm", function()
        -- issue 515 GAP 1: the vanilla one-shot has_teleported latch (set in the teleport
        -- action bt_bot_teleport_to_ally_action.lua:93, cleared only in
        -- BTBotFollowAction.enter :14) is made re-armable under the backward-gate toggle,
        -- so a bot that teleported once and then went straight into combat / an aid
        -- pursuit (never re-entering the follow node) can still teleport again later.
        -- Marker + the pure re-arm decision (no engine reads).
        if GT_BOT515_LATCH_REARM_MARKER_v0_2_203 ~= "gt-bot515-teleport-latch-rearm" then
            return "issue-515 latch re-arm marker absent -- was GAP 1 reverted?"
        end
        local ra = mod._gt515_should_rearm
        if type(ra) ~= "function" then
            return "mod._gt515_should_rearm not exposed -- the #515 re-arm seam is missing"
        end
        -- Latch not set: nothing to re-arm.
        if ra(false, true, 100, 50) ~= false then return "re-arm must be false when has_teleported is not set" end
        -- Toggle off: vanilla latch behavior preserved (never re-arm).
        if ra(true, false, 100, 50) ~= false then return "re-arm must be false when the backward-gate toggle is off" end
        -- No game time yet (boot / pre-mission): never re-arm.
        if ra(true, true, nil, 50) ~= false then return "re-arm must be false when game time is unavailable" end
        -- Within the cooldown window: hold the latch (anti-spam).
        if ra(true, true, 100, 98) ~= false then return "re-arm must hold within the cooldown window" end
        -- Cooldown elapsed: re-arm.
        if ra(true, true, 100, 90) ~= true then return "re-arm must fire once the cooldown elapses" end
        -- Latch set but no recorded last teleport: re-arm (safe; downstream gates still apply).
        if ra(true, true, 100, nil) ~= true then return "re-arm must fire when there is no recorded last teleport" end
    end)

    _rt_register("gt_bot515_cant_reach_backward_bypass", function()
        -- issue 515 GAP 2/3: the follow/aid teleport_no_path node (condition
        -- cant_reach_ally) gains a backward-segment bypass so a bot pushed past a
        -- no-return threshold but unable to PATH back can teleport to regroup. Marker +
        -- seam exposure + the pure decision core (mirrors vanilla cant_reach_ally
        -- bt_bot_conditions.lua:1189-1203 MINUS the is_backwards early return :1183-1187;
        -- no engine reads, so it is unit-testable).
        if GT_BOT515_CANT_REACH_BACKWARD_MARKER_v0_2_203 ~= "gt-bot515-cant-reach-ally-backward-bypass" then
            return "issue-515 cant_reach_ally backward-bypass marker absent -- was GAP 2 reverted?"
        end
        local decide = mod._gt515_cant_reach_backward_decide
        if type(decide) ~= "function" then
            return "mod._gt515_cant_reach_backward_decide not exposed"
        end
        if type(mod._gt_cant_reach_ally_backward_wants) ~= "function" then
            return "mod._gt_cant_reach_ally_backward_wants not exposed -- the GAP 2 engine wrapper is missing"
        end
        -- Forward / same segment: NEVER handled here (vanilla func owns the forward path).
        if decide(false, true, 99, 100, 0) ~= false then
            return "backward decide must be false for a forward/same-segment target (vanilla owns forward)"
        end
        -- Backward + moving + sustained fails (>5) + >5s since last success => teleport.
        if decide(true, true, 6, 100, 90) ~= true then
            return "backward decide must fire on a backward target with fails>5 and >5s since last path success"
        end
        -- Backward but only 5 fails (not > 5): vanilla's non-forward threshold not met.
        if decide(true, true, 5, 100, 90) ~= false then
            return "backward decide must require fails > 5 (vanilla non-forward branch)"
        end
        -- Backward + fails but last path success only 3s ago (<= 5s dwell): no teleport.
        if decide(true, true, 9, 100, 97) ~= false then
            return "backward decide must require t - last_success > 5"
        end
        -- Backward + failing but the bot is not moving toward the follow target: no teleport.
        if decide(true, false, 9, 100, 90) ~= false then
            return "backward decide must require moving_toward_follow_position"
        end
    end)

    _rt_register("gt_bot385_close_no_path_retry_bound", function()
        local policy = mod._gt_teleport_loop_policy
        if not (policy and type(policy.should_suppress_no_path) == "function") then
            return "issue-385 no-path retry policy missing"
        end
        if type(mod._gt385_should_suppress_no_path) ~= "function" then
            return "issue-385 engine-facing no-path suppression seam missing"
        end
        if policy.should_suppress_no_path(2.8, 15, 102, 100) ~= true then
            return "close repeated no-path teleport must be suppressed inside retry window"
        end
        if policy.should_suppress_no_path(2.8, 15, 106, 100) ~= false then
            return "close no-path teleport must retry after bounded cooldown"
        end
        if policy.should_suppress_no_path(20, 15, 102, 100) ~= false then
            return "outside-leash no-path teleport must remain available"
        end
        if not policy.is_no_path_reason("vanilla_no_path")
                or not policy.is_no_path_reason("backward_no_path")
                or policy.is_no_path_reason("tighter_leash") then
            return "no-path reason classifier is not exact"
        end
    end)

    _rt_register("gt_bot384_aid_errand_pin", function()
        -- #384 (v0.2.250-dev): the aid-errand PIN. Vanilla's path-fail cooldowns
        -- nil target_ally_need_type mid-errand (player_bot_base.lua:960-964 +
        -- :721-724), which dropped BOTH the revive errand and every distance-
        -- teleport aid exception; field log (gt 0.2.248) showed the tighter_leash
        -- branch teleporting 0.02 s after its own veto and a #492 no-progress
        -- bail releasing the veto while the ally was still down. The pin holds
        -- the errand from the ally's LIVE status and releases state-based only.
        -- Locks: marker + the two pure policy seams + their truth tables.
        if GT_BOT384_AID_ERRAND_PIN_MARKER_v0_2_250 ~= "gt-bot384-aid-errand-pin-holds-veto" then
            return "bot #384 aid-errand pin marker absent -- was the pin reverted?"
        end
        local policy = mod._gt_teleport_loop_policy
        if type(policy) ~= "table"
                or type(policy.pin_need_type) ~= "function"
                or type(policy.pin_should_release) ~= "function" then
            return "bot #384 pin policy seams missing (pin_need_type / pin_should_release)"
        end
        -- pin_need_type truth table (stub status objects; the unit boundary
        -- cannot be stubbed -- same constraint as the #139/#384 predicates).
        local function st(o)
            o = o or {}
            local function g(k) return function() return o[k] or false end end
            return {
                is_knocked_down               = g("knocked"),
                get_is_ledge_hanging          = g("ledge"),
                is_pulled_up                  = g("pulled"),
                is_hanging_from_hook          = g("hook"),
                is_ready_for_assisted_respawn = g("awaiting"),
            }
        end
        local cases = {
            { s = st{ knocked = true },  awaiting_ok = false, want = "knocked_down", why = "knocked down" },
            { s = st{ ledge = true },    awaiting_ok = false, want = "ledge",        why = "ledge-hanging, not pulled up" },
            { s = st{ ledge = true, pulled = true }, awaiting_ok = false, want = nil, why = "ledge but already pulled up" },
            { s = st{ hook = true },     awaiting_ok = false, want = "hook",         why = "hanging from hook" },
            { s = st{ awaiting = true }, awaiting_ok = true,  want = "knocked_down", why = "awaiting rescue, FIX 3 relabel on" },
            { s = st{ awaiting = true }, awaiting_ok = false, want = nil,            why = "awaiting rescue but relabel off" },
            { s = st{},                  awaiting_ok = true,  want = nil,            why = "healthy (no pinnable errand)" },
        }
        for _, c in ipairs(cases) do
            local got = policy.pin_need_type(c.s, c.awaiting_ok)
            if got ~= c.want then
                return string.format("pin_need_type(%s): want=%s got=%s",
                    c.why, tostring(c.want), tostring(got))
            end
        end
        -- pin_should_release matrix: recovery releases; no-path bail on the
        -- pinned unit releases; no-progress bail HOLDS; other-unit bail holds.
        local rel = policy.pin_should_release
        if rel(nil, false, nil, false) ~= true then
            return "pin must release when the ally no longer classifies"
        end
        if rel("knocked_down", true, "no-path", true) ~= true then
            return "pin must release on a no-path #492 bail for the pinned ally"
        end
        if rel("knocked_down", true, "no-progress", true) ~= false then
            return "pin must HOLD through a no-progress #492 bail (the #384 log gap)"
        end
        if rel("knocked_down", true, "no-path", false) ~= false then
            return "a no-path bail for a DIFFERENT unit must not release the pin"
        end
        if rel("knocked_down", false, nil, false) ~= false then
            return "pin must hold while the ally classifies and no bail is active"
        end
    end)

    _rt_register("gt_bot385_below_leash_instrument", function()
        -- #385 (v0.2.250-dev): the capped, log-only below-leash branch
        -- instrument -- the issue's missing datum was WHICH should_teleport /
        -- cant_reach_ally branch fired for teleports below the leash slider.
        -- Locks the marker + the pure log-gate truth table (below min(leash,40)
        -- only, capped, malformed input fails closed).
        if GT_BOT385_BELOW_LEASH_INSTRUMENT_MARKER_v0_2_250 ~= "gt-bot385-below-leash-branch-instrument" then
            return "bot #385 below-leash instrument marker absent"
        end
        local policy = mod._gt_teleport_loop_policy
        if type(policy) ~= "table" or type(policy.should_log_below_leash) ~= "function" then
            return "bot #385 below-leash log-gate seam missing"
        end
        if type(policy.BELOW_LEASH_LOG_CAP) ~= "number" or policy.BELOW_LEASH_LOG_CAP <= 0 then
            return "bot #385 log cap missing or non-positive"
        end
        local log = policy.should_log_below_leash
        if log(2.8, 15, 0, 24) ~= true then
            return "a 2.8 m teleport under a 15 m leash must log"
        end
        if log(15, 15, 0, 24) ~= false then
            return "an at-leash teleport must not log (distance triggers own it)"
        end
        if log(20, 15, 0, 24) ~= false or log(20, 40, 0, 24) ~= true then
            return "the floor must be min(leash, 40): 20 m is legit at leash 15 (tighter-leash trigger) but anomalous at leash 40"
        end
        if log(45, 60, 0, 24) ~= false then
            return "at/above vanilla's 40 m floor the vanilla trigger owns the teleport -- no log"
        end
        if log(2.8, 15, 24, 24) ~= false then
            return "the session cap must silence the instrument"
        end
        if log(nil, 15, 0, 24) ~= false or log(2.8, nil, 0, 24) ~= false then
            return "malformed distance/leash input must fail closed"
        end
    end)

    _rt_register("gt_bot383_fix9_splits_follow_position", function()
        -- issue 383 (v0.2.194-dev): FIX 9 (split bots among humans) must set
        -- data.follow_position -- a vanilla-spacing fan point around each bot's OWN
        -- assigned human -- not only data.follow_unit. Re-pointing follow_unit alone
        -- left a split bot standing next to the WRONG human (movement reads
        -- follow_position, player_bot_base.lua:1655). Marker + source-pattern guard,
        -- plus a behavioral check of the fan helper's nil-return fallback contract.
        if GT_BOT383_FIX9_SPLIT_FOLLOW_POSITION_MARKER ~= "gt-bot383-fix9-split-follow-position" then
            return "issue-383 split follow_position marker absent -- was the FIX A recompute reverted?"
        end
        -- Behavioral: the fan helper returns nil (caller then leaves follow_position
        -- untouched) on its guard paths -- no nav_world, non-positive count. Exercises
        -- the "fall back rather than stamp the raw player position" contract without a
        -- live navmesh / POSITION_LOOKUP entry.
        local fan = mod._gt_fan_points_for_unit
        if type(fan) ~= "function" then
            return "mod._gt_fan_points_for_unit not exposed -- FIX A fan helper missing"
        end
        if fan({}, nil, {}, 1) ~= nil then
            return "fan helper must return nil when nav_world is nil (fallback contract)"
        end
        if fan({}, "navworld", {}, 0) ~= nil then
            return "fan helper must return nil when needed <= 0 (fallback contract)"
        end
        -- #511 (v0.2.202-dev): the structural source-grep (io.open) that asserted the
        -- split branch computes a per-human fan, writes data.follow_position, and keeps
        -- the hold_position guard was removed -- io is nil in the VMF sandbox, so it
        -- threw and reported FAIL on healthy code. The marker + fan-helper nil-contract
        -- checks are the runtime residual; the split-branch SOURCE-TEXT invariants
        -- belong in a repo QA gate (PROJECT_STANDARDS 2.2b tier a).
    end)

    _rt_register("gt_bot142_backward_wants_no_segment_gate", function()
        -- issue 142 (v0.2.194-dev): _gt_backward_teleport_wants mirrors vanilla
        -- should_teleport MINUS the behind-segment gate, so a follow target behind the
        -- bot still triggers once beyond the leash threshold. Drive the pure decision
        -- with a stub blackboard + injected squared distance (ScriptUnit/ALIVE/Vector3
        -- are file-local upvalues a test cannot stub). "Behind" is implicit: the
        -- function reads no segment, so a beyond-threshold distance fires regardless.
        local wants = mod._gt_backward_teleport_wants
        if type(wants) ~= "function" then
            return "mod._gt_backward_teleport_wants not exposed"
        end
        local FAR = 5000    -- ~70 m^2; above any slider threshold (max 40 m => 1600 sq)
        local NEAR = 50     -- ~7 m^2; below the tightest threshold (10 m => 100 sq)
        local function bb(extra)
            local b = { unit = {}, ai_bot_group_extension = { data = { follow_unit = {} } } }
            for k, v in pairs(extra or {}) do b[k] = v end
            return b
        end
        if wants(bb(), FAR) ~= true then
            return "backward wants should be true for a beyond-threshold follow target (behind or not)"
        end
        if wants(bb({ has_teleported = true }), FAR) ~= false then
            return "backward wants must be false when has_teleported is set"
        end
        if wants(bb({ target_ally_need_type = "knocked_down" }), FAR) ~= false then
            return "backward wants must be false when target_ally_need_type is set (aid exception)"
        end
        local prio = {}
        if wants(bb({ target_unit = prio, priority_target_enemy = prio }), FAR) ~= false then
            return "backward wants must be false when the bot holds its priority enemy target"
        end
        if wants(bb(), NEAR) ~= false then
            return "backward wants must be false within the leash threshold"
        end
    end)

    _rt_register("gt_bot142_veto_still_final", function()
        -- issue 142 (v0.2.194-dev): the backward-teleport branch must be evaluated
        -- BEFORE the #139 blanket aid veto in the should_teleport hook, so the veto
        -- stays the FINAL word on the combined decision (a downed teammate overrides a
        -- backward leash -- the bot paths in to revive).
        -- #511 (v0.2.202-dev): the source-ORDER grep (io.open) was removed -- io is nil
        -- in the VMF sandbox, so it threw and reported FAIL on healthy code. Runtime
        -- residual: both feature seams are exposed (the backward branch + the ignore-
        -- gate toggle exist). Source ORDER is a purely STATIC property with no runtime
        -- signal; that "veto must come after the backward branch" invariant belongs in
        -- a repo QA gate (PROJECT_STANDARDS 2.2b tier a).
        if type(mod._gt_backward_teleport_wants) ~= "function" then
            return "mod._gt_backward_teleport_wants not exposed -- the issue-142 backward-teleport branch is missing"
        end
        if type(mod._gt_ignore_backward_gate_on) ~= "function" then
            return "mod._gt_ignore_backward_gate_on not exposed -- the issue-142 backward-gate toggle seam is missing"
        end
    end)

    _rt_register("gt_bot261_leash_conflict_invariants", function()
        -- issue 261 (v0.2.194-dev): guard the whole bot-leash / teleport conflict net
        -- so the issue-142 backward-gate work cannot silently loosen a neighbouring
        -- bound. (a) the tighter leash still reads the gt_bot_follow_distance_m slider;
        -- (b) improved-combat still caps the special-chase path via CHASE_MAX_DIST_SQ
        -- on _enemy_path_allowed; (c) FIX 10's greedy pickup post-passes still honour
        -- vanilla's follow-range gates; (d) exactly ONE hook each on should_teleport
        -- and BTBotTeleportToAllyAction.run (VMF drops a 2nd on the same pair).
        -- #511 (v0.2.202-dev): the source-grep half (io.open over the bot modules and
        -- the sibling _gt_improved_bot_combat.lua) was removed -- io is nil in the VMF
        -- sandbox, so it threw and reported FAIL on healthy code. The greedy-pickup
        -- marker constant is the runtime residual; the STATIC invariants it grepped move
        -- to their correct homes: the "exactly one hook each on should_teleport /
        -- BTBotTeleportToAllyAction.run" duplicate-hook counts are ALREADY enforced by
        -- tools/mod-lint/lint-mod.ps1 (PROJECT_STANDARDS 2.2b tier a), and the tighter-
        -- leash slider read (a), the FIX 10 follow-range gate references (c), and the
        -- improved-combat CHASE_MAX_DIST_SQ / _enemy_path_allowed cap (b) belong in a
        -- repo QA gate.
        if GT_BOT_GREEDY_PICKUP_MARKER_v0_2_182 ~= "gt-bot-greedy-pickup-mule-health-postpass" then
            return "greedy-pickup marker absent -- FIX 10 follow-range gate net broken"
        end
    end)

    _rt_register("issue298_improved_bot_combat_controls", function()
        local policy = mod._gt_ibc_policy
        if type(policy) ~= "table" or type(policy.feature_enabled) ~= "function"
                or type(policy.distance_sq) ~= "function" then
            return "improved-combat control policy not loaded"
        end
        if policy.feature_enabled(true, false) ~= false
                or policy.feature_enabled(true, nil) ~= true
                or policy.feature_enabled(false, true) ~= false then
            return "master/child fallback contract drifted"
        end
        if policy.distance_sq(7.1, 1) ~= 7.1 * 7.1 then
            return "distance control no longer compares squared engine distances"
        end
    end)

    _rt_register("issue488_bot_improvement_families", function()
        local policy = mod._gt_bot_hazard_policy
        if type(policy) ~= "table" or policy.MAX_STACKS ~= 5
            or policy.STACK_LIFETIME ~= 2 or policy.RESISTANCE_PER_STACK ~= 0.20 then
            return "bot hazard resistance policy constants drifted"
        end
        if policy.classify("skaven_poison_wind_globadier", "damage_over_time") ~= "gas"
            or policy.classify("skaven_warpfire_thrower", "warpfire_ground") ~= "warpfire" then
            return "bot hazard source classifier drifted"
        end
        if type(mod._gt488_scale_bot_hazard_damage) ~= "function"
            or mod._GT_488_HAZARD_MARKER ~= "gt-488-bot-hazard-resistance-v1" then
            return "bot hazard final-damage integration missing"
        end
        if mod._GT_488_RATLING_SHIELD_PROBE_CAP ~= 12 then
            return "ratling shield diagnostic cap missing"
        end
    end)

    _rt_register("gt_dh_no_position_lookup_reads", function()
        -- issue 302 (v0.2.195-dev): the debug-highlights draw runs as a mod.update
        -- consumer, where POSITION_LOOKUP's raw Vector3 entries are DEAD temporaries
        -- for any unit the engine has not refreshed this section (issue-337 bug
        -- class). Every position in _gt_debug_highlights.lua must be a LIVE read
        -- (_unit_pos / Unit.local_position).
        -- #511 (v0.2.202-dev): converted from an io source-grep (the VMF sandbox has
        -- no io library, so the old grep threw and reported FAIL on healthy code) to a
        -- runtime provenance marker the module sets at LOAD next to its live-read
        -- helper. The textual "no POSITION_LOOKUP index in that file" invariant is a
        -- STATIC check and belongs in a repo QA gate (PROJECT_STANDARDS 2.2b tier a).
        if mod._gt_dh_live_pos_reads ~= true then
            return "_gt_debug_highlights.lua live-position provenance marker absent -- did the module fail to load, or was the _unit_pos live-read path replaced with POSITION_LOOKUP (issue-337 class)?"
        end
    end)

    _rt_register("gt304_keep_dummy_constraint_scope", function()
        local policy = mod._gt_dummy_collision_policy
        if type(policy) ~= "table" or type(policy.should_remove_player_constraint) ~= "function" then
            return "keep-dummy collision policy/module did not load"
        end
        if mod._gt_dummy_collision_hook_count ~= 2 then
            return "keep-dummy authoritative+husk init seams are not both wired"
        end
        local dummy = { name = "training_dummy" }
        if policy.should_remove_player_constraint(false, true, dummy) then
            return "default-off state incorrectly removes the dummy constraint"
        end
        if policy.should_remove_player_constraint(true, false, dummy) then
            return "non-inn level incorrectly removes the dummy constraint"
        end
        if not policy.should_remove_player_constraint(true, true, dummy) then
            return "enabled keep training dummy does not remove the constraint"
        end
        if policy.should_remove_player_constraint(true, true, { name = "skaven_slave" }) then
            return "non-dummy AI incorrectly loses its movement constraint"
        end
    end)

    _rt_register("gt_dh_hud_update_invocation_302", function()
        if mod._gt_dh_hud_update_wired ~= true then
            return "Debug Highlights is not wired to the consolidated IngameHud.update draw seam"
        end
        if type(mod._gt_debug_highlights_draw) ~= "function" then
            return "Debug Highlights HUD draw consumer is missing"
        end
    end)

    _rt_register("gt_dh_local_player_safe_508", function()
        -- issue 508 (v0.2.200-dev): _gt_debug_highlights runs as a mod.update
        -- consumer, which also ticks in the boot/menu phase where vanilla
        -- PlayerManager.local_player() asserts "Network backend has not been set"
        -- (player_manager.lua:580-586; the readiness-guarded local_player_safe is
        -- :588-596).
        -- #511 (v0.2.202-dev): converted from an io source-grep (io is nil in the VMF
        -- sandbox -> the grep threw and reported FAIL on healthy code) to the runtime
        -- provenance marker the module sets at LOAD right where local_player_safe is
        -- called. The textual "no bare :local_player() in that file" invariant is a
        -- STATIC check and belongs in a repo QA gate (PROJECT_STANDARDS 2.2b tier a).
        if mod._gt_dh_local_player_safe ~= true then
            return "_gt_debug_highlights.lua local_player_safe provenance marker absent -- did the module fail to load, or was a bare local_player() call reintroduced (issue 508)?"
        end
    end)

    _rt_register("bot_follow_mode_dropdown_consolidated", function()
        -- v0.2.152-dev: gt_bot_split_among_players + gt_bot_follow_host checkboxes
        -- replaced by a single gt_bot_follow_mode dropdown (default/follow_host/split).
        -- The hook reads mod._gt_resolve_follow_mode() (legacy-fallback aware).
        if GT_BOT_FOLLOW_MODE_DROPDOWN_MARKER_v0_2_152 ~= "gt-bot-follow-mode-dropdown-consolidation" then
            return "gt_bot_follow_mode dropdown consolidation marker absent — was the v0.2.152-dev change reverted?"
        end
        if type(mod._gt_resolve_follow_mode) ~= "function" then
            return "mod._gt_resolve_follow_mode helper missing — dropdown migration may be broken"
        end
    end)

    _rt_register("bot_behavior_master_sub_widgets_registered", function()
        -- #297 (v0.2.182-dev): gt_bot_behavior_improvements is a MASTER toggle with
        -- nested sub_widgets (checkboxes default ON + the 2 delay sliders, defaults
        -- 3 / 4). issue 142 (v0.2.194-dev) added gt_bot_ignore_backward_gate.
        -- Checkbox ids reuse the pre-bundle setting ids so persisted
        -- pre-bundle user choices are restored; defaults must stay ON so the master
        -- alone reproduces the former v0.2.128-dev bundle behavior.
        local ok, data = pcall(require, "scripts/mods/general_tweaker_dev/general_tweaker_dev_data")
        if not ok or type(data) ~= "table" then return "could not require data file" end
        local master
        local function find(node)
            if master or type(node) ~= "table" then return end
            if node.setting_id == "gt_bot_behavior_improvements" then master = node return end
            for _, child in pairs(node) do if type(child) == "table" then find(child) end end
        end
        find(data)
        if not master then return "gt_bot_behavior_improvements widget missing from the data tree" end
        if type(master.sub_widgets) ~= "table" then return "master toggle has no sub_widgets array" end
        local want = {
            gt_bot_necro_potion_handoff      = { wtype = "checkbox", default = true },
            gt_bot_mission_fail_prevention   = { wtype = "checkbox", default = true },
            gt_bot_ledge_pullup              = { wtype = "checkbox", default = true },
            gt_bot_ledge_pullup_delay        = { wtype = "numeric",  default = 3 },
            gt_bot_ladder_unstick            = { wtype = "checkbox", default = true },
            gt_bot_ladder_unstick_delay      = { wtype = "numeric",  default = 4 },
            gt_bot_instant_pickup            = { wtype = "checkbox", default = true },
            gt_bot_greedy_pickup             = { wtype = "checkbox", default = true },
            gt_bot_aid_priority              = { wtype = "checkbox", default = true },
            gt_bot_ignore_backward_gate      = { wtype = "checkbox", default = true },
            gt_bot_ironbreaker_revive_in_ult = { wtype = "checkbox", default = true },
        }
        for _, w in ipairs(master.sub_widgets) do
            local spec = w.setting_id and want[w.setting_id]
            if spec then
                if w.type ~= spec.wtype then
                    return w.setting_id .. " has type " .. tostring(w.type) .. ", want " .. spec.wtype
                end
                if w.default_value ~= spec.default then
                    return w.setting_id .. " default_value is " .. tostring(w.default_value) .. ", want " .. tostring(spec.default)
                end
                want[w.setting_id] = nil
            end
        end
        for id in pairs(want) do
            return id .. " missing from the master toggle's sub_widgets"
        end
    end)

    _rt_register("bot_drink_potion_advanced_conditions_registered", function()
        -- #320 (v0.2.183-dev): gt_bot_drink_potions_in_danger is a MASTER toggle with
        -- 7 nested sub_widgets (the scan-range slider + four trigger checkboxes + the
        -- two cluster-count sliders). Defaults must reproduce the former hard-coded
        -- behavior (boss on, patrol on at 3, range 18; special + horde off), so a user
        -- who never expands the option sees no change. A refactor that drops a
        -- sub-widget or flips a default should trip this.
        local ok, data = pcall(require, "scripts/mods/general_tweaker_dev/general_tweaker_dev_data")
        if not ok or type(data) ~= "table" then return "could not require data file" end
        local master
        local function find(node)
            if master or type(node) ~= "table" then return end
            if node.setting_id == "gt_bot_drink_potions_in_danger" then master = node return end
            for _, child in pairs(node) do if type(child) == "table" then find(child) end end
        end
        find(data)
        if not master then return "gt_bot_drink_potions_in_danger widget missing from the data tree" end
        if type(master.sub_widgets) ~= "table" then return "drink-potions master toggle has no sub_widgets array" end
        local want = {
            gt_bot_drink_range_m       = { wtype = "numeric",  default = 18 },
            gt_bot_drink_on_boss       = { wtype = "checkbox", default = true },
            gt_bot_drink_on_special    = { wtype = "checkbox", default = false },
            gt_bot_drink_on_patrol     = { wtype = "checkbox", default = true },
            gt_bot_drink_patrol_count  = { wtype = "numeric",  default = 3 },
            gt_bot_drink_on_horde      = { wtype = "checkbox", default = false },
            gt_bot_drink_horde_count   = { wtype = "numeric",  default = 8 },
        }
        for _, w in ipairs(master.sub_widgets) do
            local spec = w.setting_id and want[w.setting_id]
            if spec then
                if w.type ~= spec.wtype then
                    return w.setting_id .. " has type " .. tostring(w.type) .. ", want " .. spec.wtype
                end
                if w.default_value ~= spec.default then
                    return w.setting_id .. " default_value is " .. tostring(w.default_value) .. ", want " .. tostring(spec.default)
                end
                want[w.setting_id] = nil
            end
        end
        for id in pairs(want) do
            return id .. " missing from the drink-potions master toggle's sub_widgets"
        end
    end)

    _rt_register("bot_greedy_pickup_hooks_present", function()
        -- #297 item 8 (v0.2.182-dev): the greedy-pickup post-passes must exist --
        -- marker global set beside the FIX 10 hooks in _gt_bot_pickups.lua, plus both
        -- hook_safe registrations on AIBotGroupSystem._update_mule_pickups /
        -- _update_health_pickups (fresh (Class, method) pairs, grep-verified at
        -- authoring time). Source read is best-effort.
        -- #511 (v0.2.202-dev): the source-grep for the two AIBotGroupSystem pickup
        -- hooks (io.open) was removed -- io is nil in the VMF sandbox, so it threw and
        -- reported FAIL on healthy code. The marker constant is the runtime residual;
        -- the presence of the _update_mule_pickups / _update_health_pickups hook
        -- registrations is a STATIC check already covered by tools/mod-lint (hook
        -- inventory) and belongs in a repo QA gate (PROJECT_STANDARDS 2.2b tier a).
        if GT_BOT_GREEDY_PICKUP_MARKER_v0_2_182 ~= "gt-bot-greedy-pickup-mule-health-postpass" then
            return "greedy-pickup marker absent -- was the #297 item-8 feature removed?"
        end
    end)

    _rt_register("bot_fix_delays_read_from_settings", function()
        -- #297 (v0.2.182-dev): the ledge pull-up / ladder unstick delays are sliders
        -- again. The tick bodies must read them via mod:get.
        -- #511 (v0.2.202-dev): the source-grep (io.open, asserting the mod:get reads
        -- exist and no `local delay = 3/4` literal returned) was removed -- io is nil
        -- in the VMF sandbox, so it threw and reported FAIL on healthy code. Converted
        -- to a RUNTIME assertion: both settings resolve to numbers via mod:get, which
        -- proves the sliders are registered and readable the same way the tick reads
        -- them. The "no hard-coded delay literal" SOURCE-TEXT invariant belongs in a
        -- repo QA gate (PROJECT_STANDARDS 2.2b tier a).
        if type(tonumber(mod:get("gt_bot_ledge_pullup_delay"))) ~= "number" then
            return "gt_bot_ledge_pullup_delay does not resolve to a number via mod:get -- slider missing / renamed?"
        end
        if type(tonumber(mod:get("gt_bot_ladder_unstick_delay"))) ~= "number" then
            return "gt_bot_ladder_unstick_delay does not resolve to a number via mod:get -- slider missing / renamed?"
        end
    end)

    _rt_register("gt_bot468_smart_self_heal_wired", function()
        -- #468 (v0.2.205-dev): the FIX 12 bot_should_heal reimplementation is gated on
        -- gt_bot_smart_self_heal + three tuning settings, read live in the hook. Runtime
        -- assertion (io is nil in the VMF sandbox, so no source grep): the LOAD marker
        -- is set beside the hook, the gating helper is exposed, and all four settings
        -- resolve via mod:get with the types the hook consumes. The "exactly one hook on
        -- (BTConditions, bot_should_heal)" source invariant belongs in a repo QA gate
        -- (PROJECT_STANDARDS 2.2b tier a), same as the sibling bot checks.
        if GT_BOT_SMART_SELF_HEAL_MARKER_v0_2_205 == nil then
            return "GT_BOT_SMART_SELF_HEAL_MARKER_v0_2_205 not set -- FIX 12 hook block did not load"
        end
        if type(mod._gt_smart_self_heal_on) ~= "function" then
            return "mod._gt_smart_self_heal_on missing -- gating helper not exposed"
        end
        if type(mod:get("gt_bot_smart_self_heal")) ~= "boolean" then
            return "gt_bot_smart_self_heal does not resolve to a boolean via mod:get -- checkbox missing / renamed?"
        end
        if type(tonumber(mod:get("gt_bot_self_heal_pct"))) ~= "number" then
            return "gt_bot_self_heal_pct does not resolve to a number via mod:get -- slider missing / renamed?"
        end
        if type(mod:get("gt_bot_reserve_kits_for_players")) ~= "boolean" then
            return "gt_bot_reserve_kits_for_players does not resolve to a boolean via mod:get -- checkbox missing / renamed?"
        end
        if type(mod:get("gt_bot_ignore_surplus_selfuse")) ~= "boolean" then
            return "gt_bot_ignore_surplus_selfuse does not resolve to a boolean via mod:get -- checkbox missing / renamed?"
        end
    end)

    _rt_register("issue523_bot_heal_allies_policy", function()
        local policy = mod._gt_bot_heal_policy
        if type(policy) ~= "table" or type(policy.is_eligible) ~= "function" then
            return "issue #523 pure policy did not load"
        end
        local expected = {
            gt_bot_heal_allies = "boolean",
            gt_bot_heal_allies_pct = "number",
            gt_bot_heal_wounded_allies_pct = "number",
            gt_bot_heal_allies_exclude_zealot = "boolean",
            gt_bot_heal_wounded_zealot = "boolean",
        }
        for setting_id, expected_type in pairs(expected) do
            local value = mod:get(setting_id)
            if expected_type == "number" then value = tonumber(value) end
            if type(value) ~= expected_type then
                return setting_id .. " did not resolve as " .. expected_type
            end
        end
        local defaults = { regular_percent = 15, wounded_percent = 100,
            exclude_zealot = true, heal_wounded_zealot = true }
        if not policy.is_eligible(0.15, false, false, defaults)
                or policy.is_eligible(0.151, false, false, defaults)
                or not policy.is_eligible(1, true, false, defaults)
                or policy.is_eligible(0.01, false, true, defaults)
                or not policy.is_eligible(0.5, true, true, defaults) then
            return "issue #523 default eligibility truth table failed"
        end
    end)

    _rt_register("gt_bot469_aoe_immunity_wired", function()
        -- #469 (v0.2.206-dev): the bot-AOE-immunity checks are MERGED into the two
        -- godmode DamageUtils hooks (add_damage_network / add_damage_network_player)
        -- and gated on gt_bot_behavior_improvements + gt_bot_aoe_immunity, read live.
        -- Runtime assertion (io is nil in the VMF sandbox, so no source grep, issue
        -- 511): the curated tables loaded with their load-bearing keys, the bot
        -- predicate is exposed + nil-safe, and both settings resolve via mod:get. The
        -- "exactly one hook per DamageUtils pair" source invariant is covered by the
        -- duplicate-hook lint (repo CLAUDE.md NON-NEGOTIABLE 8).
        local p = mod._gt_bot_aoe_immune_profiles
        if type(p) ~= "table" or not (p.heavens_lightning_strike and p.curse_skulls_of_fury_explosion and p.bolt_of_change) then
            return "mod._gt_bot_aoe_immune_profiles missing or lost a curated key -- was #469 reverted?"
        end
        local s = mod._gt_bot_aoe_immune_sources
        if type(s) ~= "table" or not s.lamp_oil_fire then
            return "mod._gt_bot_aoe_immune_sources missing lamp_oil_fire -- was #469 reverted?"
        end
        if type(mod._gt_unit_is_bot) ~= "function" then
            return "mod._gt_unit_is_bot missing -- bot predicate not exposed"
        end
        local ok, res = pcall(mod._gt_unit_is_bot, nil)
        if not ok then
            return "mod._gt_unit_is_bot(nil) RAISED -- predicate not nil-safe"
        end
        if res ~= false then
            return "mod._gt_unit_is_bot(nil) did not return false for a nil unit"
        end
        if type(mod:get("gt_bot_aoe_immunity")) ~= "boolean" then
            return "gt_bot_aoe_immunity does not resolve to a boolean via mod:get -- checkbox missing / renamed?"
        end
        if type(mod:get("gt_bot_behavior_improvements")) ~= "boolean" then
            return "gt_bot_behavior_improvements does not resolve to a boolean via mod:get -- master missing / renamed?"
        end
    end)

    _rt_register("btlab_settings_removed", function()
        -- v0.2.175-dev: the Bot Teleport Lab settings section (master + 10 D-toggles +
        -- 10 F-toggles + 4 numeric params) was removed. Diagnostics are now implicit /
        -- always-on in the dev build; the two visual tools moved to "Dev Tools". No
        -- gt_btlab_ widget may remain in the data tree, else a friend's saved F-toggle
        -- could resurface behind a ghost UI. Walk the tree and fail on any survivor.
        local ok, data = pcall(require, "scripts/mods/general_tweaker_dev/general_tweaker_dev_data")
        if not ok or type(data) ~= "table" then return "could not require data file" end
        local offending
        local function walk(node)
            if offending or type(node) ~= "table" then return end
            local sid = node.setting_id
            if type(sid) == "string" and sid:find("^gt_btlab_") then offending = sid return end
            for _, child in pairs(node) do if type(child) == "table" then walk(child) end end
        end
        walk(data)
        if offending then
            return "a gt_btlab_ widget still exists in the data tree: " .. tostring(offending)
        end
    end)

    _rt_register("btlab_fixes_dormant", function()
        -- v0.2.175-dev: the retired F1..F10 bisection candidates must be DORMANT --
        -- their three dispatch fns early-return on the module flag _BTLAB_FIXES_ARMED
        -- (false) regardless of any (removed) setting, so a stale saved F-toggle can't
        -- resurrect a behavior change. Behavioral proof: call each with nil args and
        -- assert the dormant return. The proven #139 fixes in _gt_bot_fixes.lua are a
        -- SEPARATE path and are unaffected.
        if type(mod._gt_btlab_veto_teleport) ~= "function"
            or type(mod._gt_btlab_override_follow_unit) ~= "function"
            or type(mod._gt_btlab_redirect_teleport) ~= "function" then
            return "a gt_btlab fix dispatch fn is missing (expected all three present but dormant)"
        end
        local veto = mod._gt_btlab_veto_teleport(nil, nil, nil, nil)
        if veto ~= false then return "veto_teleport not dormant (returned " .. tostring(veto) .. ", want false)" end
        local ovr = mod._gt_btlab_override_follow_unit(nil, nil)
        if ovr ~= nil then return "override_follow_unit not dormant (returned " .. tostring(ovr) .. ", want nil)" end
        local redir = mod._gt_btlab_redirect_teleport(nil, nil)
        if redir ~= false then return "redirect_teleport not dormant (returned " .. tostring(redir) .. ", want false)" end
    end)

    _rt_register("devtools_group_dev_gated", function()
        -- v0.2.175-dev: the "Dev Tools" group (gt_devtools_bot_hud + gt_devtools_leash_lines)
        -- exists ONLY in the dev clone and is appended after "Cheats and Debug". This
        -- test runs inside the dev mod, so require() returns the tree WITH Dev Tools.
        -- (1) behavioral: the group + both children are present and ordered after
        -- cheats_debug_group. (2) source-pattern: the data file gates the append on the
        -- sed-safe get_mod("gt" .. "_dev") needle (survives the dev->stable gt_dev->gt
        -- sed, so the group never builds in the promoted stable clone).
        local ok, data = pcall(require, "scripts/mods/general_tweaker_dev/general_tweaker_dev_data")
        if not ok or type(data) ~= "table" then return "could not require data file" end
        local widgets = data.options and data.options.widgets
        if type(widgets) ~= "table" then return "data.options.widgets missing" end
        local cheats_i, devtools_i
        for i = 1, #widgets do
            local sid = widgets[i].setting_id
            if sid == "cheats_debug_group" then cheats_i = i end
            if sid == "gt_devtools_group" then devtools_i = i end
        end
        if not devtools_i then return "gt_devtools_group not present in the dev data tree (append broken?)" end
        if cheats_i and devtools_i < cheats_i then
            return "gt_devtools_group must sort AFTER cheats_debug_group (A->Z)"
        end
        local want = { gt_devtools_bot_hud = false, gt_devtools_leash_lines = false }
        local function walk(node)
            if type(node) ~= "table" then return end
            if node.setting_id and want[node.setting_id] ~= nil then want[node.setting_id] = true end
            for _, child in pairs(node) do if type(child) == "table" then walk(child) end end
        end
        walk(widgets[devtools_i])
        for id, found in pairs(want) do
            if not found then return id .. " missing from the Dev Tools group" end
        end
        -- #511 (v0.2.202-dev): the data-file needle grep (io.open, asserting the
        -- sed-safe get_mod("gt" .. "_dev") gate) was removed -- io is nil in the VMF
        -- sandbox, so it threw and reported FAIL on healthy code. The data-tree walk
        -- above (group present + ordered + both children) is the runtime residual; the
        -- sed-safe-gate SOURCE-TEXT invariant belongs in a repo QA gate
        -- (PROJECT_STANDARDS 2.2b tier a).
    end)

    _rt_register("devtools_bot_hud_wired", function()
        -- v0.2.175-dev: the bot behavior HUD must be wired -- the per-frame ring-buffer
        -- poll dispatch fn present (driven from _gt_bot_fixes.lua's PlayerBotBase.update
        -- merge-dispatch), and the lab source must read the current BT leaf action from
        -- the blackboard (running_nodes) and gate the HUD on its toggle. Source read is
        -- best-effort and degrades if the deploy doesn't expose source.
        -- #511 (v0.2.202-dev): the lab source-grep (io.open, asserting the running_nodes
        -- read and the gt_devtools_bot_hud toggle gate) was removed -- io is nil in the
        -- VMF sandbox, so it threw and reported FAIL on healthy code. The dispatch-fn
        -- presence above is the runtime residual; those SOURCE-TEXT invariants belong in
        -- a repo QA gate (PROJECT_STANDARDS 2.2b tier a).
        if type(mod._gt_btlab_observe_update) ~= "function" then
            return "mod._gt_btlab_observe_update missing -- HUD ring-buffer poll chokepoint gone"
        end
    end)

    _rt_register("gt303_freeze_ai_wired", function()
        -- #303 (v0.2.215-dev): Freeze AI must stay wired across all four seams.
        -- (1) the toggle body (keybind function_call target + /freezeai command) is
        -- exposed; it is defined only on the dev stream, which this test runs in.
        -- (2) the composed spawn-block applicator exists in main (catches a revert of
        -- the freeze-OR-no_enemies composition that would let one clobber the other).
        -- (3) the Dev Tools keybind widget is present and points function_call at
        -- gt_freeze_ai_toggle (catches a renamed/broken widget). (4) the vanilla brain
        -- tick the merged gate rides still exists (catches an engine rename that would
        -- silently no-op the freeze).
        if type(mod.gt_freeze_ai_toggle) ~= "function" then
            return "mod.gt_freeze_ai_toggle missing -- did _gt_freeze_ai.lua load on the dev stream?"
        end
        if type(mod._gt_apply_spawn_block) ~= "function" then
            return "mod._gt_apply_spawn_block missing -- freeze/no_enemies spawn-block composition reverted"
        end
        if not (AISystem and type(AISystem.update_brains) == "function") then
            return "AISystem.update_brains missing -- the merged Freeze AI brain gate has no target"
        end
        local ok, data = pcall(require, "scripts/mods/general_tweaker_dev/general_tweaker_dev_data")
        if not ok or type(data) ~= "table" then return "could not require data file" end
        local widgets = data.options and data.options.widgets
        if type(widgets) ~= "table" then return "data.options.widgets missing" end
        local found
        local function walk(node)
            if type(node) ~= "table" then return end
            if node.setting_id == "gt_devtools_freeze_ai_hotkey" then found = node end
            for _, child in pairs(node) do if type(child) == "table" then walk(child) end end
        end
        walk(widgets)
        if not found then return "gt_devtools_freeze_ai_hotkey keybind missing from the Dev Tools group" end
        if found.function_name ~= "gt_freeze_ai_toggle" then
            return "gt_devtools_freeze_ai_hotkey function_name must be gt_freeze_ai_toggle (got " .. tostring(found.function_name) .. ")"
        end
    end)

    _rt_register("breach_probe_present_dev_gated", function()
        -- #261 (v0.2.176-dev): the always-on radius-breach probe must be present and
        -- dev-gated. It runs inside mod._gt_btlab_observe_update (dispatched from the
        -- existing PlayerBotBase.update merge-dispatch) behind the IS_DEV_STREAM gate,
        -- and printfs the [gt:btlab:breach] block. Source read is best-effort.
        -- #511 (v0.2.202-dev): the lab source-grep (io.open, asserting the
        -- [gt:btlab:breach] printf tag and the IS_DEV_STREAM gate) was removed -- io is
        -- nil in the VMF sandbox, so it threw and reported FAIL on healthy code. The
        -- probe-host dispatch fn above is the runtime residual; those SOURCE-TEXT
        -- invariants belong in a repo QA gate (PROJECT_STANDARDS 2.2b tier a).
        if type(mod._gt_btlab_observe_update) ~= "function" then
            return "mod._gt_btlab_observe_update missing -- radius-breach probe host removed"
        end
    end)

    _rt_register("tether_dump_present", function()
        -- #261 (v0.2.176-dev): every leash yank must dump its cause. mod._gt_btlab_report_tether
        -- printfs the [gt:btlab:tether] block (current action + ring buffer, ~2s cooldown),
        -- dispatched from the existing BTBotTeleportToAllyAction.run hook in _gt_bot_fixes.lua.
        -- #511 (v0.2.202-dev): the lab source-grep (io.open, asserting the
        -- [gt:btlab:tether] printf tag) was removed -- io is nil in the VMF sandbox, so
        -- it threw and reported FAIL on healthy code. The dump fn presence is the
        -- runtime residual; the tag SOURCE-TEXT invariant belongs in a repo QA gate
        -- (PROJECT_STANDARDS 2.2b tier a).
        if type(mod._gt_btlab_report_tether) ~= "function" then
            return "mod._gt_btlab_report_tether missing -- leash/tether printf dump removed"
        end
    end)

    _rt_register("btlab_no_class_hooks", function()
        -- #261 (v0.2.176-dev): the lab must stay merge-dispatch -- ZERO class hooks
        -- (VMF single-hook rule; all injection points ride existing _gt_bot_fixes.lua
        -- hooks).
        -- #511 (v0.2.202-dev): the "no mod:hook( in the lab file" source-grep (io.open)
        -- was removed -- io is nil in the VMF sandbox, so it threw and reported FAIL on
        -- healthy code. Runtime residual: the lab loaded (its dispatch fns are exposed).
        -- The "zero class hooks in this file" invariant is a STATIC source-text check;
        -- tools/mod-lint/lint-mod.ps1 already inventories hooks mod-wide, and a per-file
        -- no-hooks assertion belongs in a repo QA gate (PROJECT_STANDARDS 2.2b tier a).
        if type(mod._gt_btlab_veto_teleport) ~= "function" or type(mod._gt_btlab_observe_update) ~= "function" then
            return "bot teleport lab dispatch fns not exposed -- did _gt_bot_teleport_lab.lua load?"
        end
    end)

    _rt_register("btlab_gui_material_guarded", function()
        -- #293/#295 (v0.2.179-dev): the lab's World.create_screen_gui call takes a HARD
        -- C-level fatal (bypasses pcall) if handed a non-resident material. ROOT CAUSE was
        -- creating with FONT_MTRL (materials/fonts/arial), not a resident create material;
        -- fixed to GUI_MTRL (gw_fonts, every vanilla debug GUI's material). Two invariants:
        --   (1) the create call passes GUI_MTRL, never FONT_MTRL (regression on the root cause);
        --   (2) the create is still pre-filtered by can_get("material", GUI_MTRL) (belt+suspenders).
        -- #511 (v0.2.202-dev): the source-grep (io.open, asserting FONT_MTRL is not
        -- passed and can_get pre-filters the create) was removed -- io is nil in the VMF
        -- sandbox, so it threw and reported FAIL on healthy code. Converted to the
        -- runtime provenance marker the lab sets at LOAD to the exact material its
        -- create_screen_gui call passes: it must be gw_fonts, never arial/FONT_MTRL
        -- (the #293/#295 C-fatal root cause). The remaining "create is pre-filtered by
        -- can_get(GUI_MTRL)" SOURCE-TEXT invariant belongs in a repo QA gate
        -- (PROJECT_STANDARDS 2.2b tier a).
        if mod._gt_btlab_gui_create_material == nil then
            return  -- lab HUD create path removed / marker not set -> nothing to guard
        end
        if mod._gt_btlab_gui_create_material ~= "materials/fonts/gw_fonts" then
            return "bot teleport lab create_screen_gui material is '" .. tostring(mod._gt_btlab_gui_create_material)
                .. "', not gw_fonts -- #293/#295 root cause (arial/FONT_MTRL is not a resident create material -> C-fatal)"
        end
    end)

    _rt_register("gt_459_lineobject_cleanup_liveness_gated", function()
        -- issue 459 (v0.2.196-dev): _clear_and_null (_gt_bot_teleport_lab.lua) and
        -- _clear (_gt_debug_highlights.lua) dispatch a CACHED LineObject into a CACHED
        -- world. On Leave Game, StateIngame.on_exit destroys the level world while VMF
        -- mods_update keeps ticking, so an unguarded reset/dispatch is a C-level access
        -- violation that pcall CANNOT catch. Both cleanup sites must gate the engine
        -- calls on an IDENTITY check against the currently-live level_world
        -- (live == w) -- has_world alone passes when a NEW same-named world exists
        -- while the cached handle points at the freed old one.
        -- #511 (v0.2.202-dev): the two-file source-grep (io.open, asserting the
        -- live == w gate text) was removed -- io is nil in the VMF sandbox, so it threw
        -- and reported FAIL on healthy code. Converted to the runtime provenance markers
        -- each cleanup site sets at LOAD next to its live == w gate. The exact gate
        -- SOURCE-TEXT invariant belongs in a repo QA gate (PROJECT_STANDARDS 2.2b tier a).
        if mod._gt459_liveness_gated_lab ~= true then
            return "_gt_bot_teleport_lab.lua lost the issue-459 world-liveness gate provenance marker (LineObject cleanup AV guard)"
        end
        if mod._gt459_liveness_gated_dh ~= true then
            return "_gt_debug_highlights.lua lost the issue-459 world-liveness gate provenance marker (LineObject cleanup AV guard)"
        end
    end)

    _rt_register("gt_bot448_downed_morrs_grant_suppressed", function()
        -- issue 448 (v0.2.197-dev): a downed BOT carrying the CW boon Morr's
        -- Protection (deus_knockdown_damage_immunity_aura) must stop granting the
        -- invulnerable-perk buff, or two adjacent downed bot carriers are mutually
        -- unkillable and the run soft-locks. Vanilla never checks the carrier's own
        -- knocked-down state (morris_buff_settings.lua:887 gates only on
        -- is_ready_for_assisted_respawn). Asserts: FIX 11 marker present (file
        -- loaded, fix not reverted); exactly ONE hook on the aura update func (VMF
        -- drops a silent duplicate); the strip is SOURCE-GATED on
        -- attacker_unit == owner (a standing carrier's aura must be left alone);
        -- and both the bot_player and is_knocked_down gates are present (humans and
        -- standing bots keep vanilla behavior).
        -- #511 (v0.2.202-dev): the source-grep half (io.open) was removed -- io is nil
        -- in the VMF sandbox, so it threw and reported FAIL on healthy code. The FIX 11
        -- marker constant (set at LOAD beside the fix in _gt_bot_fixes.lua) is the
        -- runtime residual; the STATIC invariants it grepped move to their correct
        -- homes: the "exactly one deus_knockdown_damage_immunity_aura_func hook"
        -- duplicate-hook count is ALREADY enforced by tools/mod-lint/lint-mod.ps1
        -- (PROJECT_STANDARDS 2.2b tier a), and the attacker_unit == owner /
        -- bot_player / is_knocked_down source gates belong in a repo QA gate.
        if GT_BOT_DOWNED_MORRS_MARKER_v0_2_197 ~= "gt-448-downed-bot-no-morrs-grant" then
            return "FIX 11 marker absent -- was the issue-448 downed-bot Morr's grant fix reverted?"
        end
    end)

    _rt_register("bt_health_conditions_nilguarded_marker_present", function()
        -- #59 secondary fix (v0.2.149-dev): nil-guard the BTConditions.at_*_health
        -- + can_transition_*_health + less_than_one_health condition family so a
        -- first-tick read of an uninitialized blackboard.current_health[_percent]
        -- biases to false instead of crashing on `nil <= number`. Primary fix
        -- (level-family prefix match) is regression-tested by
        -- gt_cs_is_in_level_prefix_match below. If this marker disappears the
        -- belt-and-suspenders guard was removed.
        if GT_BT_HEALTH_NILGUARD_MARKER_v0_2_149 ~= "gt-bt-health-conditions-nilguarded-i59" then
            return "BT health-condition nil-guard marker absent — was the v0.2.149-dev fix reverted?"
        end
    end)

    _rt_register("issue247_keep_slot_takeover_wired", function()
        -- The retired implementation removed/recreated Player objects and needed a
        -- locomotion override as crash mitigation.  #247 keeps the human Player and
        -- slot, so the stronger invariant is the keep-slot marker plus an exposed
        -- entry point and an enabled emergency gate.
        if mod._GT_247_KEEP_SLOT_MARKER ~= "gt-247-keep-slot-v1" then
            return "#247 keep-slot takeover marker missing"
        end
        if type(mod._gt_ai_swap_human_to_bot) ~= "function" then
            return "#247 takeover entry point missing"
        end
        if mod._gt_ai_takeover_disabled then
            return "#247 emergency gate is still disabling takeover"
        end
    end)

    _rt_register("saved_positions_module_wired", function()
        -- #306 (v0.2.184-dev): the Saved Positions dev tool (_gt_saved_positions.lua)
        -- registers /save_position_1..10 + /recall_position_1..10, capturing the local
        -- player position + look rotation and teleporting back per map via
        -- PlayerUnitLocomotionExtension:teleport_to. Structural check: the module
        -- dofiled and exposed its save/recall entry points, the 10-slot count, and its
        -- marker. If any of these are absent the module failed to load or was gutted.
        if mod._GT_SAVED_POSITIONS_MARKER ~= "gt-saved-positions-per-map-slots" then
            return "saved-positions marker absent — did _gt_saved_positions.lua load?"
        end
        if mod._gt_saved_positions_slot_count ~= 10 then
            return "saved-positions slot count is not 10 (got " .. tostring(mod._gt_saved_positions_slot_count) .. ")"
        end
        if type(mod._gt_save_position) ~= "function" or type(mod._gt_recall_position) ~= "function" then
            return "saved-positions save/recall entry points not exposed on mod"
        end
    end)

    _rt_register("gt_no_mission_hotkey_flip", function()
        -- Issue #62 (2026-05-28): a legacy hook force-set the hotkeys-enabled arg of
        -- IngameUI.handle_menu_hotkeys to true mid-mission, enabling crash-prone keep
        -- view hotkeys (Hero Select / Map / etc. spawn unloaded ui_* preview worlds).
        -- Removed in v0.2.82-dev; the invariant is that the hook stays absent.
        -- #511 (v0.2.202-dev): the absence-of-hook source-grep (io.open) was removed --
        -- io is nil in the VMF sandbox, so it threw and reported FAIL on healthy code.
        -- This is a purely STATIC "a specific hook must NOT exist" invariant with no
        -- runtime signal; it belongs in a repo QA gate (PROJECT_STANDARDS 2.2b tier a).
        -- Runtime residual: the main file loaded (its on_setting_changed is defined).
        if type(mod.on_setting_changed) ~= "function" then
            return "mod.on_setting_changed not defined -- general_tweaker_dev.lua failed to load"
        end
    end)

    _rt_register("gt_cs_is_in_level_prefix_match", function()
        -- Issue #59 (2026-05-26): _gt_cs_is_in_level("dlc_castle") used to be
        -- `level_key == level_name` (exact-match). In CW variants of the same
        -- physical arena (dlc_castle_slaanesh_path1 / dlc_castle_chaos_path2 /
        -- etc.) that returned false, causing the transitioned_one_third_health
        -- hook to bias TRUE and skip vanilla phase-init, which left
        -- blackboard.current_health_percent nil and crashed bt_conditions.lua:309
        -- (at_one_fifth_health) when the BT entered the final offense phase.
        --
        -- Probe by stubbing Managers.state.game_mode:level_key() and verifying
        -- both exact and `<name>_<suffix>` levels match, while non-prefix
        -- levels (dlc_morningstar, dlc_castled_unrelated) do not.
        local saved_state = Managers.state
        local saved_game_mode = saved_state and saved_state.game_mode
        Managers.state = Managers.state or {}
        local probe_level
        Managers.state.game_mode = {
            level_key = function() return probe_level end,
        }
        local cases = {
            { level = "dlc_castle",                       name = "dlc_castle", want = true,  why = "exact match" },
            { level = "dlc_castle_path1",                 name = "dlc_castle", want = true,  why = "vanilla path variant" },
            { level = "dlc_castle_slaanesh_path1",        name = "dlc_castle", want = true,  why = "CW theme variant (Issue #59 case)" },
            { level = "dlc_castle_chaos_boss_path1",      name = "dlc_castle", want = true,  why = "CW boss variant" },
            { level = "dlc_morningstar",                  name = "dlc_castle", want = false, why = "unrelated level" },
            { level = "dlc_castled_unrelated",            name = "dlc_castle", want = false, why = "shared prefix without underscore boundary" },
            { level = "inn_level",                        name = "dlc_castle", want = false, why = "keep level" },
        }
        local fail = nil
        for _, c in ipairs(cases) do
            probe_level = c.level
            local got = mod._gt_cs_is_in_level(c.name)
            if got ~= c.want then
                fail = string.format("level=%q name=%q want=%s got=%s (%s)",
                    c.level, c.name, tostring(c.want), tostring(got), c.why)
                break
            end
        end
        Managers.state.game_mode = saved_game_mode
        if fail then return fail end
    end)

    _rt_register("gt_cs_transitioned_one_third_not_forced", function()
        -- Issue #275 (2026-07-06): the transitioned_one_third_health hook body used to
        -- be `(_gt_cs_is_in_level("dlc_castle") and func(...)) or true`, which collapses
        -- to constant-true. Inside the real Nurgloth arena a legitimate vanilla `false`
        -- (boss has not yet passed the one-third-health transition) became true via the
        -- `or true` tail, forcing the BT into its final-offense phase at full health and
        -- breaking the real fight everywhere, always. The fix routes the hook through
        -- the pure helper mod._gt_cs_one_third_wrapper(in_arena, vanilla_result);
        -- assert its truth table so the collapse can never return.
        local wrap = mod._gt_cs_one_third_wrapper
        if type(wrap) ~= "function" then
            return "mod._gt_cs_one_third_wrapper missing (hook not routed through the pure helper)"
        end
        local cases = {
            { in_arena = true,  vanilla = false, want = false, why = "in arena, vanilla false -> defer (must NOT force true)" },
            { in_arena = true,  vanilla = true,  want = true,  why = "in arena, vanilla true -> true" },
            { in_arena = false, vanilla = false, want = true,  why = "outside arena -> force true (spawner Nurgloth skips arena phase)" },
            { in_arena = false, vanilla = true,  want = true,  why = "outside arena -> force true" },
        }
        for _, c in ipairs(cases) do
            local got = wrap(c.in_arena, c.vanilla)
            if got ~= c.want then
                return string.format("in_arena=%s vanilla=%s want=%s got=%s (%s)",
                    tostring(c.in_arena), tostring(c.vanilla), tostring(c.want), tostring(got), c.why)
            end
        end
    end)

    _rt_register("gt_cs_breed_list_dynamic", function()
        -- Issue #454 (v0.2.210-dev): the Creature Spawner lists are enumerated
        -- from the LIVE Breeds table at command time; the old hardcoded
        -- unit_categories map is a category overlay only. Probe: inject a fake
        -- spawnable breed into Breeds, rebuild via the exposed builder, assert
        -- it lists in all_units + boss_units (dynamic categorization) and that
        -- all_units is A-Z sorted, then remove the probe and rebuild clean.
        if GT_CS_DYNAMIC_BREED_LIST_MARKER_v0_2_210 ~= "gt-cs-dynamic-breed-list-i454" then
            return "dynamic breed-list marker absent -- was the #454 fix reverted?"
        end
        local rebuild = mod._gt_cs_rebuild_unit_lists
        if type(rebuild) ~= "function" then
            return "mod._gt_cs_rebuild_unit_lists missing (lazy list builder not exposed)"
        end
        if not Breeds then return end -- no Breeds table in this state; static half passed
        local probe = "gt_rt_probe_breed_454"
        if Breeds[probe] ~= nil then
            return "probe breed name collision in Breeds"
        end
        Breeds[probe] = {
            base_unit = "units/gameplay/training_dummy/training_dummy_bob",
            unit_template = "gt_rt_probe_template",
            behavior = "gt_rt_probe_behavior",
            boss = true,
        }
        local lists = rebuild()
        Breeds[probe] = nil
        local found_all, found_boss, unsorted = false, false, nil
        local prev
        for _, n in ipairs((lists and lists.all_units) or {}) do
            if n == probe then found_all = true end
            if prev and prev > n then unsorted = prev .. " > " .. n end
            prev = n
        end
        for _, n in ipairs((lists and lists.boss_units) or {}) do
            if n == probe then found_boss = true break end
        end
        rebuild() -- rebuild clean without the probe
        if not found_all then
            return "late-registered probe breed missing from all_units (boot-snapshot regression)"
        end
        if not found_boss then
            return "probe breed with boss=true missing from boss_units (dynamic categorization regression)"
        end
        if unsorted then
            return "all_units not A-Z sorted: " .. unsorted
        end
    end)

    _rt_register("bots_in_keep_setting_registered", function()
        -- The gt_bots_in_keep checkbox must exist in general_tweaker_dev_data.lua's
        -- widget tree. If a future refactor drops it from gameplay_group without
        -- updating the feature module, mod:get("gt_bots_in_keep") returns nil and
        -- the toggle silently no-ops. Verify by walking the data table.
        local ok, data = pcall(require, "scripts/mods/general_tweaker_dev/general_tweaker_dev_data")
        if not ok or type(data) ~= "table" then return "could not require data file" end
        local found = false
        local function walk(node)
            if found or type(node) ~= "table" then return end
            if node.setting_id == "gt_bots_in_keep" then found = true; return end
            for _, child in pairs(node) do
                if type(child) == "table" then walk(child) end
            end
        end
        walk(data)
        if not found then
            return "gt_bots_in_keep widget not found in data file widget tree"
        end
    end)

    _rt_register("issue300_rescue_awaiting_range_policy", function()
        local ok, data = pcall(require, "scripts/mods/general_tweaker_dev/general_tweaker_dev_data")
        if not ok or type(data) ~= "table" then return "could not require data file" end

        local widgets = {}
        local function walk(node)
            if type(node) ~= "table" then return end
            if node.setting_id then widgets[node.setting_id] = node end
            for _, child in pairs(node) do
                if type(child) == "table" then walk(child) end
            end
        end
        walk(data)

        local parent = widgets.gt_bot_rescue_awaiting
        local ignore = widgets.gt_bot_rescue_awaiting_ignore_leash
        local custom = widgets.gt_bot_rescue_awaiting_custom_range
        local range = widgets.gt_bot_rescue_awaiting_range_m
        if not parent or type(parent.sub_widgets) ~= "table" then return "rescue parent/sub_widgets missing" end
        if not ignore or ignore.type ~= "checkbox" or ignore.default_value ~= true then
            return "ignore-leash child must be a default-ON checkbox"
        end
        if not custom or custom.type ~= "checkbox" or custom.default_value ~= false then
            return "custom-range child must be a default-OFF checkbox"
        end
        if not range or range.type ~= "numeric" or range.default_value ~= 40.0
                or type(range.range) ~= "table" or range.range[1] ~= 10.0 or range.range[2] ~= 100.0 then
            return "custom range must be numeric, default 40, range 10-100"
        end

        local cap = mod._gt_rescue_awaiting_distance_cap
        local within = mod._gt_rescue_awaiting_within_cap
        if type(cap) ~= "function" or type(within) ~= "function"
                or mod.GT_BOT300_RESCUE_RANGE_POLICY_MARKER_v0_2_221 ~= true then
            return "#300 policy helpers/marker not loaded"
        end
        if cap(true, true, 75, 25) ~= nil then return "ignore-leash mode was not unlimited" end
        if cap(false, false, 75, 25) ~= 25 then return "normal mode did not use follow leash" end
        if cap(false, true, 75, 25) ~= 75 then return "custom mode did not use custom range" end
        if cap(false, true, 1, 25) ~= 10 or cap(false, true, 200, 25) ~= 100 then
            return "custom range clamp is not 10-100"
        end
        if not within(40, 40) or within(40.1, 40) or not within(1000, nil) then
            return "range boundary/unlimited predicate failed"
        end

        -- #300 evidence channel: the four [gt:bot-rescue] lines in
        -- _gt_bot_fixes.lua must emit via pcall(printf, ...), never mod:debug
        -- (this user's config drops the [DEBUG] channel entirely - 1931 [INFO]
        -- lines, zero [DEBUG] in the newest log). io is nil in the retail
        -- sandbox (#511), so the source-shape half of this check is pinned
        -- offline in qa/rt_textual_invariants.psd1: present needle
        -- 'pcall(printf, "[gt:bot-rescue]' (minCount 4) + absent needle
        -- 'mod:debug("[gt:bot-rescue]'.
    end)

    _rt_register("no_bots_setting_registered", function()
        -- The gt_no_bots checkbox must exist in the widget tree, else
        -- mod:get("gt_no_bots") returns nil and the toggle silently no-ops.
        local ok, data = pcall(require, "scripts/mods/general_tweaker_dev/general_tweaker_dev_data")
        if not ok or type(data) ~= "table" then return "could not require data file" end
        local found = false
        local function walk(node)
            if found or type(node) ~= "table" then return end
            if node.setting_id == "gt_no_bots" then found = true; return end
            for _, child in pairs(node) do
                if type(child) == "table" then walk(child) end
            end
        end
        walk(data)
        if not found then
            return "gt_no_bots widget not found in data file widget tree"
        end
    end)

    _rt_register("no_bots_apply_sets_ai_bots_disabled", function()
        -- mod._gt_apply_no_bots must drive script_data.ai_bots_disabled — that's the
        -- ONLY engine flag _handle_bots re-reads per server tick to both despawn
        -- existing bots and block new ones. The old /bottoggle path
        -- (level_settings.no_bots_allowed) does NOT despawn mid-mission, which was
        -- the reported bug. This test pins the correct flag. (Phase 3: the apply fn
        -- moved to _gt_bots_keep.lua and is exposed as mod._gt_apply_no_bots.)
        local apply = mod._gt_apply_no_bots
        if type(apply) ~= "function" then
            return "mod._gt_apply_no_bots is not a function (type=" .. type(apply) .. ")"
        end
        script_data = script_data or {}
        local saved = script_data.ai_bots_disabled
        apply(true)
        local on = script_data.ai_bots_disabled
        apply(false)
        local off = script_data.ai_bots_disabled
        script_data.ai_bots_disabled = saved
        if on ~= true then
            return "ai_bots_disabled not true after mod._gt_apply_no_bots(true) (got " .. tostring(on) .. ")"
        end
        if off ~= nil then
            return "ai_bots_disabled not cleared after mod._gt_apply_no_bots(false) (got " .. tostring(off) .. ")"
        end
    end)

    _rt_register("gk_quest_dropdowns_dont_share_options", function()
        -- Choose Grail Knight Quests has THREE dropdowns (gt_gk_quest1/2/3). VMF's
        -- localize_dropdown_data mutates option.text in place, so if the dropdowns
        -- share one options table the 2nd/3rd re-localize already-localized strings
        -- and render the `<<...>>` / `<<<...>>>` bracket cascade users reported.
        -- Each dropdown MUST hold its own table (built by _gt_gk_quest_options()).
        -- This walks the data tree and fails if any two of the three share a table
        -- identity. See REGRESSION_CHECKLIST "vmf-dropdown-options-mutated".
        local ok, data = pcall(require, "scripts/mods/general_tweaker_dev/general_tweaker_dev_data")
        if not ok or type(data) ~= "table" then return "could not require data file" end
        local opts_by_id = {}
        local function walk(node)
            if type(node) ~= "table" then return end
            local sid = node.setting_id
            if (sid == "gt_gk_quest1" or sid == "gt_gk_quest2" or sid == "gt_gk_quest3") and node.options then
                opts_by_id[sid] = node.options
            end
            for _, child in pairs(node) do
                if type(child) == "table" then walk(child) end
            end
        end
        walk(data)
        local q1, q2, q3 = opts_by_id.gt_gk_quest1, opts_by_id.gt_gk_quest2, opts_by_id.gt_gk_quest3
        if not (q1 and q2 and q3) then
            return "one or more gt_gk_quest dropdowns missing an options table"
        end
        if q1 == q2 or q1 == q3 or q2 == q3 then
            return "gt_gk_quest dropdowns share an options table — bracket cascade will occur"
        end
        -- Option text must be loc KEYS (no spaces / punctuation), else VMF's
        -- missing-key fallback wraps the raw display string in angle brackets.
        for _, opt in ipairs(q1) do
            if type(opt.text) ~= "string" or opt.text:find("[%s%.]") then
                return "gt_gk_quest option text is not a bare loc key: " .. tostring(opt.text)
            end
        end
    end)

    -- (menu_qol_settings_registered + menu_qol_return_quits_roundtrips regression
    -- tests MIGRATED out with the Main Menu & Startup feature to gui_tweaker / gut
    -- 2026-06-29, #190.)

    _rt_register("fall_damage_widgets_and_scaling", function()
        -- Both fall-damage widgets must exist, the apply fn must be callable, and a
        -- direct scaling probe must hold: scaling fall.heights by m must produce
        -- m*vanilla for the three damage fields (m=0 -> 0). Pins the host-side fall
        -- damage multiplier (health_system.lua rpc_take_falling_damage reads these).
        local ok, data = pcall(require, "scripts/mods/general_tweaker_dev/general_tweaker_dev_data")
        if not ok or type(data) ~= "table" then return "could not require data file" end
        local want = { gt_fall_damage_enabled = false, gt_fall_damage_mult = false }
        local function walk(node)
            if type(node) ~= "table" then return end
            if node.setting_id and want[node.setting_id] ~= nil then want[node.setting_id] = true end
            for _, child in pairs(node) do if type(child) == "table" then walk(child) end end
        end
        walk(data)
        for id, found in pairs(want) do
            if not found then return id .. " widget not found in data file widget tree" end
        end
        if type(mod.gt_apply_fall_damage) ~= "function" then
            return "mod.gt_apply_fall_damage is not a function"
        end
        if not (PlayerUnitMovementSettings and PlayerUnitMovementSettings.fall and PlayerUnitMovementSettings.fall.heights) then
            return nil -- settings not loaded in this context; skip (not a failure)
        end
        -- Pure-math probe on a standalone table (no live mutation): clamp(d*FDM*m,
        -- max*0*m, max*1*m) must equal m * clamp(d*FDM, 0, max).
        local FDM, d, max = 14, 3, 150
        local function fall_dmg(mult)
            return math.clamp(d * FDM * mult, max * 0 * mult, max * 1 * mult)
        end
        if fall_dmg(0) ~= 0 then return "m=0 should yield 0 fall damage" end
        if math.abs(fall_dmg(2) - 2 * fall_dmg(1)) > 0.001 then return "fall damage not linear in multiplier" end
        -- Re-applying the live setting must leave a positive, numeric multiplier.
        mod.gt_apply_fall_damage()
        local live = PlayerUnitMovementSettings.fall.heights.FALL_DAMAGE_MULTIPLIER
        if type(live) ~= "number" or live < 0 then
            return "FALL_DAMAGE_MULTIPLIER not a non-negative number after apply (got " .. tostring(live) .. ")"
        end
    end)

    _rt_register("gt529_godmode_stamina_gate_wired", function()
        -- #529: godmode must make stamina untouchable by enemies. The gate is MERGED
        -- into the _gt_hacks.lua add_fatigue_points hook (singleton pair discipline);
        -- this pins its three runtime dependencies without any io/source grep (#511):
        -- the marker constant, the exported godmode predicate, and the self-action
        -- allowlist shape (own push costs must stay payable; blocked_* must NOT be
        -- listed as self, or enemy drain would pass through again).
        if mod._GT_529_GODMODE_STAMINA_MARKER ~= "gt-529-godmode-stamina-gate" then
            return "#529 marker absent — was the _gt_hacks stamina gate removed?"
        end
        if type(mod._gt_godmode_active) ~= "function" then
            return "mod._gt_godmode_active not exported from the godmode section"
        end
        if mod._gt_godmode_active(nil) ~= false then
            return "_gt_godmode_active(nil) should be false"
        end
        local self_types = mod._GT_529_SELF_FATIGUE_TYPES
        if type(self_types) ~= "table" then
            return "mod._GT_529_SELF_FATIGUE_TYPES not a table"
        end
        for _, t in ipairs({ "action_push", "action_stun_push", "action_dodge" }) do
            if not self_types[t] then return t .. " missing from self-action allowlist" end
        end
        for _, t in ipairs({ "blocked_attack", "blocked_slam", "ogre_shove", "complete" }) do
            if self_types[t] then return t .. " wrongly allowlisted as a self action" end
        end
    end)

    _rt_register("issue548_godmode_stagger_and_debuff_probe", function()
        if mod._gt548_stagger_gate_wired ~= true then
            return "godmode stagger gate is not wired"
        end
        if mod._gt548_buff_probe_wired ~= true then
            return "bounded godmode buff observer is not wired"
        end
        local deny = mod._gt548_should_deny_buff
        if type(deny) ~= "function" then return "#548 debuff deny predicate absent" end
        if not deny("troll_bile_ground", true) then return "Troll Bile not denied under godmode" end
        if not deny("troll_bile_face", true) then return "vomit-in-face not denied under godmode" end
        if not deny("movement_volume_generic_slowdown", true) then return "generic slow volume not denied under godmode" end
        if deny("troll_bile_ground", false) then return "debuff denied with godmode off (must be vanilla)" end
        if deny("heal_self", true) then return "godmode over-stripped a non-listed buff" end
    end)

    _rt_register("issue380_downed_mood_swallow_complete", function()
        local moods = mod._gt_downed_moods
        if type(moods) ~= "table" then return "#380 downed-mood swallow set absent" end
        for _, name in ipairs({ "knocked_down", "bleeding_out", "wounded" }) do
            if moods[name] ~= true then
                return "#380 downed-mood swallow set missing " .. name
            end
        end
    end)

    _rt_register("issue939_godmode_ledge_boundary", function()
        if mod._GT_939_GODMODE_LEDGE_MARKER ~= "gt-939-godmode-ledge-boundary" then
            return "#939 singleton ledge-boundary composition is absent"
        end
        if type(mod._gt_godmode_active) ~= "function" then
            return "#939 godmode predicate is unavailable"
        end
    end)

    _rt_register("issue1009_godmode_blightstorm_entry", function()
        if mod._GT_1009_GODMODE_VORTEX_MARKER
                ~= "gt-1009-godmode-vortex-entry" then
            return "#1009 Blightstorm entry gate is absent"
        end
        local policy = mod._gt1009_should_block_vortex_entry
        if type(policy) ~= "function" then
            return "#1009 Blightstorm entry policy is unavailable"
        end
        if not policy(true, true, true) then
            return "#1009 Godmode entry should be blocked"
        end
        if policy(true, true, false)
                or policy(true, false, true)
                or policy(false, true, true)
                or policy(false, false, true) then
            return "#1009 non-Blightstorm, exit, or non-Godmode behavior was broadened"
        end
    end)

    _rt_register("issue549_godmode_power_and_ammo", function()
        if mod._GT_549_GODMODE_POWER_MARKER ~= "gt-549-godmode-power-and-ammo" then
            return "#549 structural marker absent"
        end
        if type(mod._gt_godmode_strike_damage_active) ~= "function" then
            return "#549 synced strike-damage predicate absent"
        end
        if type(mod._gt_reconcile_infinite_ammo) ~= "function" then
            return "#549 ammo reconciler absent"
        end
        local policy = mod._gt549_should_override_outgoing
        if type(policy) ~= "function" then return "#549 outgoing policy absent" end
        if policy(10, true, false, false) then return "disabled strike damage overrode a hit" end
        if policy(10, false, true, false) then return "friendly/non-enemy hit was overridden" end
        if policy(0, true, true, false) then return "immune zero-damage hit was overridden" end
        if not policy(10, true, true, false) then return "direct attacker state did not override" end
        if not policy(10, true, false, true) then return "source-attacker state did not override" end
    end)

    _rt_register("issue1008_godmode_armor_boundary", function()
        if mod._GT_1008_GODMODE_ARMOR_MARKER ~= "gt-1008-godmode-armor-boundary" then
            return "#1008 structural marker absent"
        end
        if mod._GT_1008_GODMODE_ARMOR_LOG_CAP ~= 8 then
            return "#1008 diagnostic cap drifted"
        end
        local policy = mod._gt1008_should_override_armor_zero
        if type(policy) ~= "function" then return "#1008 armor-zero policy absent" end
        if not policy(0, false, false, true, true, 2, nil, 0, 0.2, false) then
            return "ordinary armor zero was not overridden"
        end
        if not policy(0, false, false, true, true, 1, 6, 0, 0.2, false) then
            return "primary super-armor zero was not overridden"
        end
        if policy(0, true, false, true, true, 2, nil, 0, 0.2, false) then
            return "hard invulnerability was overridden"
        end
        if policy(0, false, true, true, true, 2, nil, 0, 0.2, false) then
            return "authored no-damage profile was overridden"
        end
        if policy(0, false, false, false, true, 2, nil, 0, 0.2, false) then
            return "friendly/non-enemy armor zero was overridden"
        end
        if policy(0, false, false, true, false, 2, nil, 0, 0.2, false) then
            return "disabled strike damage overrode armor"
        end
        if policy(0, false, false, true, true, 1, nil, 0, 0.2, false) then
            return "unarmored zero was overridden"
        end
        if policy(0, false, false, true, true, 2, nil, 0.5, 0.2, false) then
            return "non-immune armor result was overridden"
        end
        if policy(0, false, false, true, true, 2, nil, 0, 0, false) then
            return "authored zero-power profile was overridden"
        end
        if policy(0, false, false, true, true, 2, nil, 0, 0.2, true) then
            return "enemy player armor result was overridden"
        end
    end)

    _rt_register("issue241_noclip_boundary_routes", function()
        if mod._gt241_boundary_suppression_wired ~= true then
            return "noclip boundary suppression is not fully wired"
        end
    end)

end

return M
