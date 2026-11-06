-- Runtime regression owner: promoted checks plus the unchanged official baseline.
local M = {}
function M.install(mod, _rt_register, deps)
    local CT_GT_PICKUP_LOOKUP_RAWGET_MARKER_v0_2_48 = deps.CT_GT_PICKUP_LOOKUP_RAWGET_MARKER_v0_2_48
    local CT_GT_AI_CLIENT_SEND_MARKER_v0_2_52 = deps.CT_GT_AI_CLIENT_SEND_MARKER_v0_2_52
    local _dbg, _dbg_alert = deps.dbg, deps.dbg_alert
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



    _rt_register("localization_format_safe", function()
        -- Layer 3 (2026-05-25): catch unescaped %-format chars in loc strings at
        -- runtime. VMF's tooltip render path calls string.format on the loc value;
        -- literal "%APPDATA%" / "5%" / "%USERNAME%" raises 'invalid option' and
        -- shows as a red error tooltip in the VMF settings UI. Static check is
        -- qa/check_localization.ps1 -- this is its runtime twin so the bug can't
        -- ship even if the static check is skipped. RULE: any literal % in a loc
        -- string must be doubled to %%.
        local ok, loc = pcall(mod.dofile, mod, "scripts/mods/general_tweaker/general_tweaker_localization")
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

    _rt_register("bots_in_keep_necro_pets_marker_present", function()
        -- v0.2.147-dev: necromancer BOT keep-skeletons sub-feature. With Bots in Keep
        -- on, a bot necromancer's raise-dead AI loops against the vanilla hub pet ban
        -- (PassiveAbilityNecromancerCharges._pets_forbidden_in_level). We post-hook
        -- _on_talents_changed and clear that flag for bot necromancers only. If this
        -- marker disappears, the sub-feature (or its hook) was removed.
        if GT_BIK_NECRO_KEEP_PETS_MARKER_v0_2_147 ~= "gt-bik-necro-bot-keep-pets" then
            return "necromancer keep-pets marker absent — was the v0.2.147-dev sub-feature reverted?"
        end
    end)

    _rt_register("bot_leash_no_snap_to_downed_marker_present", function()
        -- #139 (v0.2.148-dev): the tighter follow-leash (FIX 7) must NOT snap-teleport
        -- a bot onto a DOWNED follow target — on the frame a split teammate is newly
        -- downed the bot would otherwise teleport onto them instead of pathing in to
        -- revive. The guard sets this marker; if it disappears the guard was removed.
        if GT_BOT139_LEASH_AID_GUARD_MARKER_v0_2_148 ~= "gt-bot139-no-snap-to-downed-follow" then
            return "bot #139 leash-aid guard marker absent — was the v0.2.148-dev fix reverted?"
        end
    end)

    _rt_register("bot_leash_no_teleport_away_from_side_aid_marker_present", function()
        -- v0.2.152-dev (#139 sibling): the tighter follow-leash must also bail when
        -- ANY teammate on the side needs aid (not just when follow_unit itself is
        -- downed). Catches the case the user reported: bot leashed to a LIVING far
        -- player, separate teammate goes down nearby, leash fires and teleports
        -- the bot AWAY from where help is needed.
        if GT_BOT139_LEASH_AID_SIDEAID_MARKER_v0_2_152 ~= "gt-bot139-no-leash-away-from-side-aid" then
            return "bot #139 sibling-case (leash-away-from-downed) guard absent — was the v0.2.152-dev extension reverted?"
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

    _rt_register("btlab_settings_removed", function()
        -- v0.2.175-dev: the Bot Teleport Lab settings section (master + 10 D-toggles +
        -- 10 F-toggles + 4 numeric params) was removed. Diagnostics are now implicit /
        -- always-on in the dev build; the two visual tools moved to "Dev Tools". No
        -- gt_btlab_ widget may remain in the data tree, else a friend's saved F-toggle
        -- could resurface behind a ghost UI. Walk the tree and fail on any survivor.
        local ok, data = pcall(require, "scripts/mods/general_tweaker/general_tweaker_data")
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
        -- v0.2.175-dev: the "Dev Tools" group (gttools_bot_hud + gttools_leash_lines)
        -- exists ONLY in the dev clone and is appended after "Cheats and Debug". This
        -- test runs inside the dev mod, so require() returns the tree WITH Dev Tools.
        -- (1) behavioral: the group + both children are present and ordered after
        -- cheats_debug_group. (2) source-pattern: the data file gates the append on the
        -- sed-safe get_mod("gt" .. "_dev") needle (survives the dev->stable gt->gt
        -- sed, so the group never builds in the promoted stable clone).
        local ok, data = pcall(require, "scripts/mods/general_tweaker/general_tweaker_data")
        if not ok or type(data) ~= "table" then return "could not require data file" end
        local widgets = data.options and data.options.widgets
        if type(widgets) ~= "table" then return "data.options.widgets missing" end
        local cheats_i, devtools_i
        for i = 1, #widgets do
            local sid = widgets[i].setting_id
            if sid == "cheats_debug_group" then cheats_i = i end
            if sid == "gttools_group" then devtools_i = i end
        end
        if not devtools_i then return "gttools_group not present in the dev data tree (append broken?)" end
        if cheats_i and devtools_i < cheats_i then
            return "gttools_group must sort AFTER cheats_debug_group (A->Z)"
        end
        local want = { gttools_bot_hud = false, gttools_leash_lines = false }
        local function walk(node)
            if type(node) ~= "table" then return end
            if node.setting_id and want[node.setting_id] ~= nil then want[node.setting_id] = true end
            for _, child in pairs(node) do if type(child) == "table" then walk(child) end end
        end
        walk(widgets[devtools_i])
        for id, found in pairs(want) do
            if not found then return id .. " missing from the Dev Tools group" end
        end
        -- Source-pattern needle (best-effort; degrades if the deploy hides source).
        local iok, info = pcall(debug.getinfo, mod._gt_btlab_veto_teleport or function() end, "S")
        if iok and type(info) == "table" and info.source then
            local src = info.source:sub(1, 1) == "@" and info.source:sub(2) or info.source
            local data_path = src:gsub("_gt_bot_teleport_lab%.lua$", "general_tweaker_data.lua")
            local f = io.open(data_path, "r")
            if f then
                local txt = f:read("*a")
                f:close()
                if txt and not txt:find('get_mod("gt" .. "_dev")', 1, true) then
                    return "data file Dev Tools append missing the sed-safe get_mod(\"gt\" .. \"_dev\") gate"
                end
            end
        end
    end)

    _rt_register("devtools_bot_hud_wired", function()
        -- v0.2.175-dev: the bot behavior HUD must be wired -- the per-frame ring-buffer
        -- poll dispatch fn present (driven from _gt_bot_fixes.lua's PlayerBotBase.update
        -- merge-dispatch), and the lab source must read the current BT leaf action from
        -- the blackboard (running_nodes) and gate the HUD on its toggle. Source read is
        -- best-effort and degrades if the deploy doesn't expose source.
        if type(mod._gt_btlab_observe_update) ~= "function" then
            return "mod._gt_btlab_observe_update missing -- HUD ring-buffer poll chokepoint gone"
        end
        local ok, info = pcall(debug.getinfo, mod._gt_btlab_veto_teleport or function() end, "S")
        if not ok or type(info) ~= "table" or not info.source then return end
        local src = info.source:sub(1, 1) == "@" and info.source:sub(2) or info.source
        local f = io.open(src, "r")
        if not f then return end
        local txt = f:read("*a")
        f:close()
        if not txt then return end
        if not txt:find("running_nodes", 1, true) then
            return "lab source missing running_nodes read -- current BT action poll gone"
        end
        if not txt:find("gttools_bot_hud", 1, true) then
            return "lab source missing gttools_bot_hud gate -- HUD not wired to its toggle"
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



    _rt_register("gt_no_mission_hotkey_flip", function()
        -- Issue #62 (2026-05-28): a legacy hook force-set the hotkeys-enabled arg of
        -- IngameUI.handle_menu_hotkeys to true mid-mission, enabling crash-prone keep
        -- view hotkeys (Hero Select / Map / etc. spawn unloaded ui_* preview worlds).
        -- Removed in v0.2.82-dev. This source-pattern guard fails if that hook is
        -- reintroduced. The needle is assembled from two literals so this test's own
        -- source does not self-match. Degrades to a no-op when source introspection
        -- is unavailable (deploy/bundle paths).
        -- Anchored on mod.on_setting_changed (a `mod.` field defined in the MAIN
        -- file) so this guard always reads general_tweaker.lua — where the
        -- removed IngameUI hook lived. (Phase 3: gt_open_mission_inventory moved to
        -- _gt_mission_ui.lua, so it can no longer be used as the main-file anchor.)
        local ok, info = pcall(debug.getinfo, mod.on_setting_changed or function() end, "S")
        if not ok or type(info) ~= "table" or not info.source then return end
        local src_path = info.source:sub(1, 1) == "@" and info.source:sub(2) or info.source
        local f = io.open(src_path, "r")
        if not f then return end
        local txt = f:read("*a")
        f:close()
        if not txt then return end
        local needle = 'mod:hook("' .. 'IngameUI", "handle_menu_hotkeys"'
        if txt:find(needle, 1, true) then
            return "Issue #62 regression: the IngameUI handle_menu_hotkeys hook was reintroduced (crash-prone mid-mission hotkey flip)"
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

    _rt_register("bots_in_keep_setting_registered", function()
        -- The gt_bots_in_keep checkbox must exist in general_tweaker_data.lua's
        -- widget tree. If a future refactor drops it from gameplay_group without
        -- updating the feature module, mod:get("gt_bots_in_keep") returns nil and
        -- the toggle silently no-ops. Verify by walking the data table.
        local ok, data = pcall(require, "scripts/mods/general_tweaker/general_tweaker_data")
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

    _rt_register("no_bots_setting_registered", function()
        -- The gt_no_bots checkbox must exist in the widget tree, else
        -- mod:get("gt_no_bots") returns nil and the toggle silently no-ops.
        local ok, data = pcall(require, "scripts/mods/general_tweaker/general_tweaker_data")
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
        local ok, data = pcall(require, "scripts/mods/general_tweaker/general_tweaker_data")
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
        local ok, data = pcall(require, "scripts/mods/general_tweaker/general_tweaker_data")
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

    -- (tp_camera_yields_to_cutscene regression test MIGRATED out with the Third-Person
    -- Camera feature to gui_tweaker / gut 2026-06-29, #191.)


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
        if not found_all then
            rebuild() -- rebuild clean without the probe
            return "late-registered probe breed missing from all_units (boot-snapshot regression)"
        end
        if not found_boss then
            rebuild()
            return "probe breed with boss=true missing from boss_units (dynamic categorization regression)"
        end
        if unsorted then
            rebuild()
            return "all_units not A-Z sorted: " .. unsorted
        end
        -- #1138: a special-flagged breed must list under Regular AND Special,
        -- mirroring the curated overlay (every vanilla special is
        -- { "regular", "special" }). Guards the default-lap reachability of
        -- late-registered mod specials (skaven_doomrocket, et al.).
        local special_probe = "gt_rt_probe_breed_1138"
        if Breeds[special_probe] ~= nil then
            return "special probe breed name collision in Breeds"
        end
        Breeds[special_probe] = {
            base_unit = "units/gameplay/training_dummy/training_dummy_bob",
            unit_template = "gt_rt_probe_template",
            behavior = "gt_rt_probe_behavior",
            special = true,
        }
        lists = rebuild()
        Breeds[special_probe] = nil
        local found_regular, found_special = false, false
        for _, n in ipairs((lists and lists.regular_units) or {}) do
            if n == special_probe then found_regular = true break end
        end
        for _, n in ipairs((lists and lists.special_units) or {}) do
            if n == special_probe then found_special = true break end
        end
        rebuild() -- rebuild clean without the probe
        if not found_regular then
            return "probe breed with special=true missing from regular_units (#1138 regression)"
        end
        if not found_special then
            return "probe breed with special=true missing from special_units (dynamic categorization regression)"
        end
    end)

    _rt_register("issue300_rescue_awaiting_range_policy", function()
        local ok, data = pcall(require, "scripts/mods/general_tweaker/general_tweaker_data")
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

    _rt_register("issue548_godmode_stagger_and_debuff_probe", function()
        if mod._gt548_stagger_gate_wired ~= true then
            return "godmode stagger gate is not wired"
        end
        if mod._gt548_buff_probe_wired ~= true then
            return "catalogued godmode debuff gate is not wired"
        end
        local deny = mod._gt548_should_deny_buff
        if type(deny) ~= "function" then return "#548 debuff deny predicate absent" end
        if not deny("troll_bile_ground", true) then return "Troll Bile not denied under godmode" end
        if not deny("troll_bile_face", true) then return "vomit-in-face not denied under godmode" end
        if not deny("movement_volume_generic_slowdown", true) then return "generic slow volume not denied under godmode" end
        if deny("troll_bile_ground", false) then return "debuff denied with godmode off (must be vanilla)" end
        if deny("heal_self", true) then return "godmode over-stripped a non-listed buff" end
    end)

    _rt_register("issue548_godmode_fly_overpowered_boundary", function()
        if mod._GT_548_GODMODE_FLY_MARKER
                ~= "gt-548-godmode-fly-overpowered-boundary" then
            return "#548 fly-overpowered boundary marker is absent"
        end
        if mod._gt548_fly_overpowered_hook_wired ~= true then
            return "#548 StatusUtils fly-overpowered hook is not wired"
        end
        if mod._gt548_fly_blob_cleanup_hook_wired ~= true then
            return "#548 blocked-blob cleanup ownership hook is not wired"
        end
        local policy = mod._gt548_should_block_fly_overpowered
        if type(policy) ~= "function" then
            return "#548 fly-overpowered policy is unavailable"
        end
        for _, reason in ipairs({ "slow_bomb", "fly_bomb" }) do
            if not policy(true, true, reason, true) then
                return "Godmode did not block authored fly reason " .. reason
            end
            if policy(false, true, reason, true) then
                return "Godmode-off call was blocked for " .. reason
            end
            if policy(true, false, reason, true) then
                return "fly cleanup/exit was blocked for " .. reason
            end
            if policy(true, true, reason, false) then
                return "non-blob overpowered source was blocked for " .. reason
            end
        end
        if policy(true, true, "charged", true) then
            return "unrelated overpowered reason was broadened into #548"
        end
        if policy(1, true, "slow_bomb", true)
                or policy(true, 1, "slow_bomb", true)
                or policy(true, true, "slow_bomb", 1) then
            return "#548 policy accepted non-boolean gate state"
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
