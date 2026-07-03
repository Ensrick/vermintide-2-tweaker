local mod = get_mod("gt")

-- _gt_ai_takeover.lua — AI Takeover (hand your character to a bot) + AFK-takeover
--
-- Extracted from the main file in Phase 4. PURE reorganization, no behavior
-- change. Lets a player hand control of their character to a bot (manual /ai +
-- the ai_takeover_enabled checkbox) and auto-hand-off after going AFK
-- (gt_ai_afk_takeover). Server-driven: only the host performs the swap; clients
-- send a VMF network request (_AI_RPC = "gt_ai_toggle_request"). NOTE: the
-- destructive swap is currently DISABLED pending the keep-slot redesign — see
-- mod._gt_ai_takeover_disabled; every entry point bails before anything
-- destructive runs, but the queues / dispatch / nil-guards stay live.
--
-- Cross-boundary state was PROMOTED from main file-locals to mod._gt_ai_* fields
-- (Phase 4) so the on_setting_changed / on_game_state_changed DISPATCHERS (which
-- read/write this state and STAY in main per the dispatcher rule), the debug
-- AI-dump (_gt_debug_probes), and the /gt_regression_test checks all resolve it
-- at call time. This module dofiles AFTER the main chunk, so it (re)assigns the
-- functions/handlers below over the defaults main seeds. Promoted fields:
--   mod._gt_ai_pending_client_send / _pending_host_toggle (queues; read by the
--     debug dump + the ai_takeover_client_send_queue_wired regression check),
--   mod._gt_ai_suppress_setting_callback (read/written by both dispatchers),
--   mod._gt_ai_saved_state (cleared by the gsc dispatcher; dumped by debug),
--   mod._gt_ai_handle_toggle_change (CALLED by the on_setting_changed dispatcher),
--   mod._gt_ai_takeover_disabled (read by the on_setting_changed dispatcher),
--   mod._gt_ai_afk_took_over / _afk_idle_t / _afk_input_stamp / _afk_grace_until
--     (cleared by the gsc dispatcher at the mission boundary).
-- Exposed helper: mod._gt_ai_swap_human_to_bot (for the
--   ai_locomotion_override_set_and_cleared source-pattern regression check).
--
-- The debug AI-toggle dump wrap here calls mod._gt_dump_ai_now (exposed by
-- _gt_debug_probes.lua) — resolved at call time, so module load order between
-- the two is irrelevant.
--
-- Singleton hooks: the only Class.method hook in this block is the VMF network
-- event registration for _AI_RPC (mod:network_register, not a mod:hook). The
-- AICommanderExtension._update_units always-on crash guard is a SEPARATE feature
-- and STAYS in the main file. The two per-frame consumers (`ai_pending`,
-- `afk_autobot`) register through mod._gt_register_update.

-- ============================================================
-- AI Toggle (hand off control to a bot)
-- ============================================================
-- VT2 has no hot-swap path between human and bot units — they use different
-- go_types with incompatible extension stacks (PlayerInputExtension vs
-- PlayerBotInput, GenericCharacterStateMachineExtension vs PlayerBotBase,
-- etc.). So toggling means despawn-human + add-bot, or remove-bot +
-- re-add-human. Both halves of the dance exist in vanilla and we compose
-- them: see GameModeBase._add_bot_to_party / _remove_bot_instant and
-- GameModeAdventure.player_entered_game_session.
--
-- Server-driven: only the host can perform the swap (ProfileSynchronizer
-- and PartyManager APIs assert is_server). Clients send a VMF network
-- request and the host validates + executes.
--
-- v1 scope:
--   * client (remote peer) self-toggle: supported
--   * host self-toggle: refused — destroying the local Player object mid-
--     mission would tear down camera/HUD/input bindings that aren't trivial
--     to recreate
--   * versus / keep: refused (no hero bot AI / no spawning)

local _AI_RPC = "gt_ai_toggle_request"
-- Client send-queue tuning constants — internal to this module (the send/drain
-- logic below is the only consumer). Moved here from the main file's top-level
-- forward-decl block during the Phase-4 extraction.
local _AI_CLIENT_SEND_MAX_RETRIES = 3
local _AI_CLIENT_SEND_DELAY_FIRST = 0.05   -- first send: nearly immediate
local _AI_CLIENT_SEND_DELAY_RETRY = 0.4    -- subsequent retries: post-pong window
-- mod._gt_ai_saved_state / mod._gt_ai_suppress_setting_callback are seeded in the
-- main file (the on_game_state_changed / on_setting_changed DISPATCHERS there
-- read/write them). We assign the field, not a `local`, so the dispatchers and
-- this module share one slot resolved at call time.

-- v0.2.116-dev: convert-in-place takeover disabled pending keep-slot redesign
-- (research wkcu0v4as). `mod._gt_ai_takeover_disabled` is forward-declared (= true) at
-- the top of the file alongside mod._gt_ai_suppress_setting_callback so on_setting_changed
-- can read it; do NOT redeclare with `local` here or the early callbacks would
-- bind a different upvalue. The convert-in-place swap produced owner-less units
-- (client kept controlling a unit the host orphaned -> owner_player nil in the
-- health extension), host/client ownership desync, and a string of despawn-race
-- crashes (0.2.113-0.2.115). The confirmed redesign is engine-native KEEP-SLOT:
-- keep the human's Player + party slot intact, despawn ONLY the unit, the client
-- enters the vanilla observer camera (the dead/respawn flow), a REAL host bot
-- fills a FREE slot, and reclaim happens via the normal respawn handshake.
-- Until that lands, EVERY takeover entry point bails before anything destructive
-- runs. The Group-F nil-guards (whereabouts / AICommander / RoundStartedSystem)
-- and the position-keepalive stay active and untouched.

local function _ai_state_key(peer_id, local_player_id)
    return tostring(peer_id) .. ":" .. tostring(local_player_id)
end

local function _ai_game_mode_key()
    local gm = Managers.state and Managers.state.game_mode
    if not (gm and gm.game_mode) then return nil end
    local mode = gm:game_mode()
    if not (mode and mode.settings) then return nil end
    return mode:settings().key
end

local function _ai_can_swap_in_current_mode()
    local key = _ai_game_mode_key()
    if not key then return false, "no active game mode" end
    if key:find("versus") or key:find("_vs") then
        return false, "versus is not supported (heroes have no bot AI)"
    end
    if key == "inn" or key == "inn_deus" or key:find("^inn") then
        return false, "must be in a mission"
    end
    return true
end

local function _ai_find_bot_in_slot(party_id, slot_id)
    local pm = Managers.player
    local bots = pm and pm:bots() or {}
    for _, bot in ipairs(bots) do
        local bp = bot:network_id()
        local bl = bot:local_player_id()
        local status = Managers.party and Managers.party:get_player_status(bp, bl)
        if status and status.party_id == party_id and status.slot_id == slot_id then
            return bot
        end
    end
    return nil
end

local function _ai_swap_human_to_bot(peer_id, local_player_id)
    -- v0.2.116-dev: HARD STOP. Every destructive op (player:despawn,
    -- unassign_profiles_of_peer, remove_peer_from_party, remove_player,
    -- _add_bot_to_party, set_override_player) lives below this line. While the
    -- takeover is disabled, no caller may reach any of it. This is the
    -- innermost guard backing the entry-point guards above.
    if mod._gt_ai_takeover_disabled then return false, "takeover disabled (rebuild in progress)" end
    local pm = Managers.player
    if not pm.is_server then return false, "must run on host" end
    local player = pm:player(peer_id, local_player_id)
    if not player then return false, "player not found" end
    if player.bot_player then return false, "already a bot" end

    local status = Managers.party:get_player_status(peer_id, local_player_id)
    if not (status and status.party_id and status.slot_id) then
        return false, "no party slot"
    end
    local party_id = status.party_id
    local slot_id = status.slot_id
    local profile_synchronizer = pm.network_manager and pm.network_manager.profile_synchronizer
    if not profile_synchronizer then return false, "no profile_synchronizer" end
    local profile_index, career_index = profile_synchronizer:profile_by_peer(peer_id, local_player_id)
    if not (profile_index and career_index) then
        return false, "no profile/career"
    end

    -- Save enough metadata to recreate the human Player on toggle-back. For
    -- a remote (client) player we need peer/clan/account; for the host's
    -- local player we'd need input_source/viewport (not supported in v1).
    local saved = {
        peer_id = peer_id,
        local_player_id = local_player_id,
        profile_index = profile_index,
        career_index = career_index,
        party_id = party_id,
        slot_id = slot_id,
        is_remote = player.remote and true or false,
    }
    if player.remote then
        saved.remote = {
            player_controlled = player._player_controlled,
            clan_tag = player._clan_tag,
            account_id = player._account_id,
        }
    else
        saved.local_data = {
            input_source = player.input_source,
            viewport_name = player.viewport_name,
            viewport_world_name = player.viewport_world_name,
        }
    end
    mod._gt_ai_saved_state[_ai_state_key(peer_id, local_player_id)] = saved

    if player.player_unit then
        player:despawn()
    end
    profile_synchronizer:unassign_profiles_of_peer(peer_id, local_player_id)
    Managers.party:remove_peer_from_party(peer_id, local_player_id, party_id)
    pm:remove_player(peer_id, local_player_id)

    local game_mode = Managers.state.game_mode:game_mode()
    if not (game_mode and game_mode._add_bot_to_party) then
        return false, "current game mode does not support bots"
    end
    local bot_player = game_mode:_add_bot_to_party(party_id, profile_index, career_index, slot_id)

    -- v0.2.73-dev (Issue #60): for host self-toggle (not player.remote), we
    -- just destroyed the local Player object via pm:remove_player. Vanilla
    -- LocomotionSystem.update_animation_lods reads
    -- `self._override_player or Managers.player:local_player()` every frame to
    -- find the viewport name to drive the bone LOD update; with no local
    -- human, local_player() returns nil and the next frame crashes on
    -- `player.viewport_name` (locomotion_system.lua:242 / line 228 in source —
    -- the engine version numbers differ from our decompile).
    --
    -- Vanilla's benchmark mode hits this exact case and the fix lives at
    -- `scripts/utils/benchmark/benchmark_handler.lua:423`:
    --     locomotion_system:set_override_player(bot_player)
    -- We mirror that: when host swapped to a bot, point the override at the
    -- bot Player so update_animation_lods finds a valid viewport. The bot has
    -- the same viewport_name as the host did ("player_1") because
    -- _add_bot_to_party reuses the slot.
    --
    -- Cleared on toggle-back in _ai_swap_bot_to_human below.
    if (not player.remote) and bot_player then
        local entity = Managers.state and Managers.state.entity
        local locomotion_system = entity and entity.system and entity:system("locomotion_system")
        if locomotion_system and locomotion_system.set_override_player then
            locomotion_system:set_override_player(bot_player)
        end
    end

    return true
end
-- Exposed for the ai_locomotion_override_set_and_cleared regression check (in
-- main): it debug.getinfo's this function to find the source file, then greps
-- that file for the locomotion_system:set_override_player(...) call pair. Both
-- calls moved into this module with the function body, so the check now reads
-- THIS file's source — keeping the function resolvable in main's scope is all
-- that's required.
mod._gt_ai_swap_human_to_bot = _ai_swap_human_to_bot

local function _ai_swap_bot_to_human(peer_id, local_player_id)
    -- v0.2.116-dev: HARD STOP. Mirrors the human->bot guard; every destructive op
    -- (_remove_bot_instant, set_override_player, add_remote_player/add_player,
    -- assign_peer_to_party, assign_full_profile) lives below. No caller may reach
    -- it while the takeover is disabled.
    if mod._gt_ai_takeover_disabled then return false, "takeover disabled (rebuild in progress)" end
    local pm = Managers.player
    if not pm.is_server then return false, "must run on host" end
    local saved = mod._gt_ai_saved_state[_ai_state_key(peer_id, local_player_id)]
    if not saved then return false, "no saved state (toggle to bot first)" end

    local bot = _ai_find_bot_in_slot(saved.party_id, saved.slot_id)
    if bot then
        local game_mode = Managers.state.game_mode:game_mode()
        if game_mode and game_mode._remove_bot_instant then
            game_mode:_remove_bot_instant(bot)
        end
    end

    -- v0.2.73-dev (Issue #60): clear the LocomotionSystem override that was
    -- set in _ai_swap_human_to_bot for the host case. If we leave it pointing
    -- at the now-removed bot Player, update_animation_lods reads the bot's
    -- viewport_name from a destroyed Player object every frame. The vanilla
    -- benchmark exit path does the same: `locomotion_system:set_override_player(nil)`
    -- in `benchmark_handler.lua` cleanup.
    if saved.local_data then
        local entity = Managers.state and Managers.state.entity
        local locomotion_system = entity and entity.system and entity:system("locomotion_system")
        if locomotion_system and locomotion_system.set_override_player then
            locomotion_system:set_override_player(nil)
        end
    end

    if saved.is_remote and saved.remote then
        pm:add_remote_player(peer_id, saved.remote.player_controlled, local_player_id,
            saved.remote.clan_tag, saved.remote.account_id)
    elseif saved.local_data then
        pm:add_player(saved.local_data.input_source, saved.local_data.viewport_name,
            saved.local_data.viewport_world_name, local_player_id)
    else
        return false, "saved state missing player kind"
    end

    Managers.party:assign_peer_to_party(peer_id, local_player_id, saved.party_id, saved.slot_id, false)
    pm.network_manager.profile_synchronizer:assign_full_profile(peer_id, local_player_id,
        saved.profile_index, saved.career_index, false)

    mod._gt_ai_saved_state[_ai_state_key(peer_id, local_player_id)] = nil
    return true
end

mod:network_register(_AI_RPC, function(sender_peer_id, schema, payload)
    -- VMF_RECIPES § 10 (Issue #44): validate the schema arg FIRST. A peer on a
    -- different gt build -- or an older build that sends no schema arg (its
    -- payload table lands in `schema`) -- fails this match and the request is
    -- dropped gracefully: no swap, no crash. Idempotent no-op, so a stale peer
    -- retrying is harmless. Mirrors the gt_godmode_state receiver gate.
    if sender_peer_id == nil or schema ~= mod.GT_AI_RPC_SCHEMA then
        -- Engine printf (NOT mod:info/mod:warning): a schema mismatch means a peer
        -- on an incompatible gt build was silently dropped, which explains why
        -- their AI-takeover isn't syncing -- the user must see it with mod-logging
        -- OFF. mod:info/warning are invisible in that mode.
        if rawget(_G, "printf") then
            printf("[rpc:schema] %s mismatch from peer=%s: peer sent v%s, we expect v%s. Dropping.",
                _AI_RPC, tostring(sender_peer_id), tostring(schema), tostring(mod.GT_AI_RPC_SCHEMA))
        end
        return
    end
    mod:info("[ai_toggle recv] HOST<-req sender=%s payload=%s",
        tostring(sender_peer_id), type(payload) == "table" and "table" or tostring(payload))
    -- v0.2.116-dev: takeover disabled pending keep-slot redesign. Bail before any
    -- swap so a client running an older gt that still sends the RPC can't drive
    -- a destructive swap on this host. Nothing destructive runs.
    if mod._gt_ai_takeover_disabled then
        mod:info("[ai_toggle] ignored from %s: takeover disabled (rebuild in progress)", tostring(sender_peer_id))
        return
    end
    local pm = Managers.player
    if not (pm and pm.is_server) then return end
    local peer_id, local_player_id = sender_peer_id, 1
    local want_bot
    if type(payload) == "table" then
        peer_id = payload.peer_id or peer_id
        local_player_id = payload.local_player_id or local_player_id
        want_bot = payload.want_bot
    end

    local ok, err = _ai_can_swap_in_current_mode()
    if not ok then
        mod:info("[ai_toggle] refused for %s: %s", tostring(peer_id), tostring(err))
        return
    end

    -- want_bot is the client's explicit intent (from their checkbox state).
    -- Saved state is the host's view of truth — used to no-op stale requests.
    local has_saved = mod._gt_ai_saved_state[_ai_state_key(peer_id, local_player_id)] ~= nil
    if want_bot == nil then want_bot = not has_saved end

    if want_bot and not has_saved then
        local s_ok, s_err = _ai_swap_human_to_bot(peer_id, local_player_id)
        mod:info("[ai_toggle] human->bot for %s: %s", tostring(peer_id), s_ok and "ok" or tostring(s_err))
    elseif (not want_bot) and has_saved then
        local s_ok, s_err = _ai_swap_bot_to_human(peer_id, local_player_id)
        mod:info("[ai_toggle] bot->human for %s: %s", tostring(peer_id), s_ok and "ok" or tostring(s_err))
    else
        mod:info("[ai_toggle] no-op for %s (want_bot=%s has_saved=%s)",
            tostring(peer_id), tostring(want_bot), tostring(has_saved))
    end
end)

-- Pending host self-toggle. The actual swap is deferred one mod.update tick so
-- the current frame finishes (input read, etc.) before we tear the local
-- Player object down. Polled in the main mod.update closure below — see the
-- `mod._gt_ai_pending_host_toggle` block.
-- NOTE: declared as a forward `local` near the top of the file alongside
-- mod._gt_ai_pending_client_send (the debug-mode AI dump reads it from above
-- this point). Assign without `local` here so we write the existing
-- upvalue instead of shadowing it.
mod._gt_ai_pending_host_toggle = nil

-- Returns (ok, err_msg). Caller is responsible for reverting the checkbox on
-- failure — mod._gt_ai_suppress_setting_callback must be true while doing so.
-- Assigns to the forward-declared upvalue (see top of file); MUST NOT use
-- `local function` here or on_setting_changed would call nil.
mod._gt_ai_handle_toggle_change = function(want_bot)
    -- v0.2.116-dev: takeover is disabled pending the keep-slot redesign. This is
    -- the USER-initiated entry (manual /ai command + the VMF checkbox both route
    -- through on_setting_changed -> here). Bail before any swap/RPC. Returning
    -- false makes on_setting_changed revert the checkbox via the existing
    -- mod._gt_ai_suppress_setting_callback path, so it can't stick "on". Echo once here
    -- (not from on_setting_changed's generic "AI toggle: " line) so the user gets
    -- the rebuild message. Only echo when turning ON, so toggling the now-stuck-
    -- off checkbox doesn't spam.
    if mod._gt_ai_takeover_disabled then
        if want_bot then
            mod:echo("[gt] AI takeover is temporarily disabled while it's rebuilt (v0.2.116-dev).")
        end
        return false, "disabled (rebuild in progress)"
    end

    local ok, err = _ai_can_swap_in_current_mode()
    if not ok then return false, err end

    local pm = Managers.player
    if pm and pm.is_server then
        -- Host self-toggle: do the swap locally, no RPC. Defer by one tick so
        -- the current frame finishes reading our input before we destroy the
        -- Player object that owns it. The `local_data` round-trip
        -- (input_source / viewport_name / viewport_world_name) was already
        -- being captured by _ai_swap_human_to_bot, so toggling back recreates
        -- the local Player with the same viewport binding.
        mod._gt_ai_pending_host_toggle = { want_bot = want_bot and true or false }
        return true
    end

    -- VMF `network_send` does NOT understand `"server"` — it falls through
    -- the recipient-name lookup, treats the string as a literal peer_id,
    -- fails the `_vmf_users[peer_id]` check, and returns silently. No wire
    -- activity, no error. (Burned v0.2.48-dev: client toggle echoed "request
    -- sent" but host never received the RPC.) See VMF_RECIPES.md § 3.
    --
    -- Resolve the host's real peer_id. The canonical engine API is
    -- `Managers.mechanism:server_peer_id()` (verified in vanilla at
    -- `imgui_career_debug.lua:153` and `versus_mechanism.lua:1845`). DO NOT
    -- use `Managers.state.network.server_peer_id` — `Managers.state.network`
    -- is `GameNetworkManager` which has no such field directly; the field
    -- lives one level deeper on `.network_client` (client) or `.network_server`
    -- (host). Burned v0.2.49-dev: that wrong path always returned nil and
    -- the toggle refused with "host peer_id not yet known". Try the mechanism
    -- API first; fall back through GameNetworkManager subcomponents in case
    -- mechanism hasn't published yet during late session-join.
    local host
    if Managers.mechanism and Managers.mechanism.server_peer_id then
        host = Managers.mechanism:server_peer_id()
    end
    if not host then
        local nm = Managers.state and Managers.state.network
        host = nm and ((nm.network_client and nm.network_client.server_peer_id)
            or (nm.network_server and nm.network_server.server_peer_id))
    end
    if not host then
        return false, "host peer_id not yet known (session still loading?)"
    end

    -- Force VMF to re-handshake with the host before our first send. Covers
    -- the bot-churn bug where VMF dropped the host from `_vmf_users` at
    -- mission load. ping_vmf_users sends a ping to every human player and
    -- the resulting pong re-populates `_vmf_users[host_peer]` so the next
    -- send succeeds. ping_vmf_users is the canonical VMF re-handshake API
    -- (vanilla VMF network.lua:452-463). Wrapped in pcall in case the API
    -- shape changes in a future VMF update — even if the re-handshake fails
    -- we still queue the send (the host MIGHT already be in vmf_users).
    local vmf = get_mod("VMF")
    if vmf and vmf.ping_vmf_users then
        pcall(vmf.ping_vmf_users)
    end

    -- Queue the actual send (with retries) instead of sending inline. The
    -- pong round-trip needs ~50-300 ms over Steam P2P; sending immediately
    -- would race the re-handshake and lose the first attempt. mod.update
    -- consumer fires the queued send after the delay.
    mod._gt_ai_pending_client_send = {
        host = host,
        want_bot = want_bot and true or false,
        retries_left = _AI_CLIENT_SEND_MAX_RETRIES,
        next_at = os.clock() + _AI_CLIENT_SEND_DELAY_FIRST,
    }
    mod:info("[ai_toggle queue] CLIENT host=%s want_bot=%s retries=%d",
        tostring(host), tostring(want_bot), _AI_CLIENT_SEND_MAX_RETRIES)
    return true
end

-- Debug-mode dump wrap. Wraps mod._gt_ai_handle_toggle_change (assigned just
-- above) to capture before/after AI state on every toggle so the user/agent can
-- diff what mutated vs. what was meant to mutate. The debug helpers
-- mod._dbg_on / mod._dbg_log / mod._gt_dump_ai_now are exposed by
-- _gt_debug_probes.lua and resolved at call time (nil-guarded), so the load
-- order between that module and this one is irrelevant.
do
    local prev = mod._gt_ai_handle_toggle_change
    mod._gt_ai_handle_toggle_change = function(want_bot)
        if mod._dbg_on and mod._dbg_on() and mod._gt_dump_ai_now then mod._gt_dump_ai_now("toggle_pre_want_bot=" .. tostring(want_bot)) end
        local ok, err = prev(want_bot)
        if mod._dbg_on and mod._dbg_on() then
            (mod._dbg_log or function() end)("[ai_event] toggle returned ok=%s err=%s", tostring(ok), tostring(err))
            if mod._gt_dump_ai_now then mod._gt_dump_ai_now("toggle_post") end
        end
        return ok, err
    end
end

-- Drain the client-side send queue. Called from mod.update. Sends the RPC
-- when `next_at` has elapsed; on each fire, also re-pings VMF users so a
-- pong stays warm against further bot-churn events between retries. Returns
-- once retries are exhausted. Idempotent — the host's RPC handler no-ops
-- when state already matches the requested want_bot.
local function _ai_consume_pending_client_send()
    local q = mod._gt_ai_pending_client_send
    if not q then return end
    if os.clock() < q.next_at then return end

    -- Refresh VMF user state on each fire so a bot-churn between retries
    -- doesn't strand the next send.
    local vmf = get_mod("VMF")
    if vmf and vmf.ping_vmf_users then
        pcall(vmf.ping_vmf_users)
    end

    mod:info("[ai_toggle emit] CLIENT->req host=%s want_bot=%s (attempt %d of %d)",
        tostring(q.host), tostring(q.want_bot),
        (_AI_CLIENT_SEND_MAX_RETRIES - q.retries_left) + 1, _AI_CLIENT_SEND_MAX_RETRIES)
    mod:network_send(_AI_RPC, q.host,
        mod.GT_AI_RPC_SCHEMA,          -- VMF_RECIPES § 10 (Issue #44): first positional arg, always
        {
            peer_id = Network.peer_id(),
            local_player_id = 1,
            want_bot = q.want_bot,
        })

    q.retries_left = q.retries_left - 1
    if q.retries_left <= 0 then
        mod._gt_ai_pending_client_send = nil
    else
        q.next_at = os.clock() + _AI_CLIENT_SEND_DELAY_RETRY
    end
end

-- Execute the deferred host swap. Called from mod.update — see the chained
-- closure at the bottom of the file (we mutate `mod.update` again to add this
-- tick consumer alongside the existing infinite-ammo refresher).
local function _ai_consume_pending_host_toggle()
    if not mod._gt_ai_pending_host_toggle then return end
    local req = mod._gt_ai_pending_host_toggle
    mod._gt_ai_pending_host_toggle = nil
    -- v0.2.116-dev: takeover disabled pending keep-slot redesign. Drop any queued
    -- host-self toggle before it reaches _ai_swap_human_to_bot / _ai_swap_bot_to_human.
    -- (mod._gt_ai_handle_toggle_change already bails, so this is belt-and-suspenders against
    -- a stale queue entry; nothing destructive runs.)
    if mod._gt_ai_takeover_disabled then return end
    local pm = Managers.player
    if not (pm and pm.is_server) then return end
    local peer_id = Network.peer_id()
    local local_player_id = 1
    local has_saved = mod._gt_ai_saved_state[_ai_state_key(peer_id, local_player_id)] ~= nil
    if req.want_bot and not has_saved then
        local s_ok, s_err = _ai_swap_human_to_bot(peer_id, local_player_id)
        mod:info("[ai_toggle:host] human->bot: %s", s_ok and "ok" or tostring(s_err))
        if s_ok then mod:echo("AI takeover: ON (your character is now a bot).") end
    elseif (not req.want_bot) and has_saved then
        local s_ok, s_err = _ai_swap_bot_to_human(peer_id, local_player_id)
        mod:info("[ai_toggle:host] bot->human: %s", s_ok and "ok" or tostring(s_err))
        if s_ok then mod:echo("AI takeover: OFF (you're back in control).") end
    end
end

mod:command("ai", "Toggle AI takeover for your character (bot controls it; toggle again to resume). Works on host or client.", function()
    -- Flipping the setting fires on_setting_changed which dispatches to host
    -- self-swap or client->server RPC depending on Managers.player.is_server.
    -- Keeps the chat command and the VMF checkbox in lockstep.
    if mod._gt_ai_suppress_setting_callback then return end
    mod:set("ai_takeover_enabled", not mod:get("ai_takeover_enabled"))
end)


-- Deferred AI-takeover host-toggle / client-send consumers. Registered through
-- the central update subscriber registry (Issue #16) via mod._gt_register_update
-- (the exposed form of the main file's _register_update). The 1Hz infinite-ammo
-- refresher that previously shared this consumer (Buffs & Stat Tweaks) lives in
-- _gt_hacks.lua now and registers its own `infinite_ammo` consumer; the two
-- halves share no state, so the split is behavior-neutral. Moved into this
-- module (Phase 4) alongside the _ai_consume_* drains it calls.
mod._gt_register_update("ai_pending", function(dt)
    if mod._gt_ai_pending_host_toggle then
        _ai_consume_pending_host_toggle()
    end
    if mod._gt_ai_pending_client_send then
        _ai_consume_pending_client_send()
    end
end)

-- ============================================================
-- AFK -> AI takeover (gt_ai_afk_takeover) -- per-client
-- ============================================================
-- When ON: if the LOCAL player gives no input (keyboard / mouse / gamepad) for
-- _AFK_IDLE_SECONDS, hand their character to gt's AI takeover; the instant they
-- give ANY input, control returns. Per-client: each peer measures ITS OWN local
-- input and calls mod:set("ai_takeover_enabled", ...), which dispatches through
-- the canonical path (host self-swap deferred 1 tick, or client->host RPC). Host
-- ON => host's char; client ON => client's char. No cross-peer addressing.
--
-- Manual /ai and the manual AI-Takeover checkbox are NOT ended by input: only an
-- AFK-CAUSED takeover (tracked by mod._gt_ai_afk_took_over) yields. Input detection reads
-- RAW devices + the engine's last_active_time stamp, both independent of the
-- player input controller, so it keeps working while the local Player object is
-- despawned during takeover.
local _AFK_IDLE_SECONDS   = 20.0   -- idle this long with the toggle ON => takeover
local _AFK_REARM_GRACE    = 0.25   -- swallow input briefly after trigger/cancel so the
                                   --   swap can settle / a held key can't flap the toggle
local _AFK_STICK_DEADZONE = 0.20   -- gamepad analog rest drift must NOT count as input

-- Did the LOCAL human produce ANY raw input this frame? Polls the engine's own
-- per-frame activity stamp (Managers.input.last_active_time, set device-level on
-- any press / non-cursor axis move at input_manager.lua:769-770) plus the raw
-- Stingray device globals as a fallback. Works while the player UNIT is bot-
-- controlled because none of these are bound to a player input controller.
local function _gt_local_any_input()
    local im = Managers.input
    if im and im.last_active_time then
        local stamp = im.last_active_time
        if mod._gt_ai_afk_input_stamp ~= nil and stamp ~= mod._gt_ai_afk_input_stamp then
            mod._gt_ai_afk_input_stamp = stamp
            return true
        end
        mod._gt_ai_afk_input_stamp = stamp   -- seed/refresh; returns false on the seeding frame
    end

    if rawget(_G, "Keyboard") and Keyboard.any_pressed() then return true end
    if rawget(_G, "Mouse") then
        if Mouse.any_pressed() then return true end
        -- relative MOVEMENT delta is the "mouse" axis, NOT "cursor" (cursor
        -- reports motion constantly and is excluded by the engine too, :752).
        local mouse_axis = (Mouse.axis_id and Mouse.axis_id("mouse"))
            or (Mouse.axis_index and Mouse.axis_index("mouse"))
        if mouse_axis then
            local md = Mouse.axis(mouse_axis)
            if md and Vector3.length(md) > 0 then return true end
        end
        local wheel_axis = (Mouse.axis_id and Mouse.axis_id("wheel"))
            or (Mouse.axis_index and Mouse.axis_index("wheel"))
        if wheel_axis then
            local w = Mouse.axis(wheel_axis)
            if w and Vector3.length(w) > 0 then return true end
        end
    end

    -- Gamepads: no top-level Pad global in gameplay code -- reach device objects
    -- via InputAux.input_device_mapping.gamepad (title_loading_ui.lua:1645-1654).
    local gamepads = rawget(_G, "InputAux") and InputAux.input_device_mapping
        and InputAux.input_device_mapping.gamepad
    if gamepads then
        for i = 1, #gamepads do
            local pad = gamepads[i]
            if pad and (not pad.active or pad.active()) then
                if pad.any_pressed and pad.any_pressed() then return true end
                if pad.num_axes and pad.axis and pad.axis_name then
                    for a = 0, pad.num_axes() - 1 do
                        if pad.axis_name(a) ~= "cursor"
                           and Vector3.length(pad.axis(a)) > _AFK_STICK_DEADZONE then
                            return true
                        end
                    end
                end
            end
        end
    end
    return false
end

mod._gt_register_update("afk_autobot", function(dt)
    dt = dt or 0

    -- v0.2.116-dev: takeover disabled pending keep-slot redesign. Return SILENTLY
    -- (this is per-frame -- never echo here). Reset the idle timer so when the
    -- feature is re-enabled the driver re-arms from a clean state. The driver
    -- never reaches mod:set("ai_takeover_enabled", true) while disabled, so no
    -- swap/RPC is dispatched.
    if mod._gt_ai_takeover_disabled then
        mod._gt_ai_afk_idle_t = 0.0
        return
    end

    if not mod:get("gt_ai_afk_takeover") then
        mod._gt_ai_afk_idle_t = 0.0
        -- If the user disables the toggle mid-AFK-takeover, end OUR takeover cleanly.
        if mod._gt_ai_afk_took_over and mod:get("ai_takeover_enabled") then
            mod._gt_ai_afk_took_over = false
            mod:set("ai_takeover_enabled", false)
        end
        return
    end

    -- Post-trigger / post-cancel grace: swallow input briefly so the swap can
    -- settle and a held key / continued mouse drag can't instantly flap the toggle.
    if mod._gt_ai_afk_grace_until > 0 then
        mod._gt_ai_afk_grace_until = mod._gt_ai_afk_grace_until - dt
        _gt_local_any_input()   -- keep the stamp current so next frame's delta is fresh
        return
    end

    local in_takeover = mod:get("ai_takeover_enabled") and true or false

    if not in_takeover then
        mod._gt_ai_afk_took_over = false   -- not in takeover => can't be an AFK takeover
        if _gt_local_any_input() then
            mod._gt_ai_afk_idle_t = 0.0
            return
        end
        mod._gt_ai_afk_idle_t = mod._gt_ai_afk_idle_t + dt
        if mod._gt_ai_afk_idle_t < _AFK_IDLE_SECONDS then return end

        -- Pre-gate the mode (host + client safe; reads game mode only). A client
        -- can't learn the host refused after the fact, so gate locally first.
        if not _ai_can_swap_in_current_mode() then
            mod._gt_ai_afk_idle_t = 0.0   -- can't swap here (versus / keep); retry after a full interval
            return
        end

        -- Trigger via the canonical dispatch. Do NOT set _ai_suppress_setting_
        -- callback -- we WANT on_setting_changed to fire and run the swap/RPC.
        mod._gt_ai_afk_took_over = true
        mod._gt_ai_afk_idle_t = 0.0
        mod._gt_ai_afk_grace_until = _AFK_REARM_GRACE
        mod:set("ai_takeover_enabled", true)
        -- Host-self refusal reverts the checkbox synchronously; if it came back
        -- false the swap was refused -- don't leave the flag stuck true.
        if not mod:get("ai_takeover_enabled") then
            mod._gt_ai_afk_took_over = false
            mod._gt_ai_afk_grace_until = 0.0
        end
        return
    end

    -- In takeover: only an AFK-CAUSED takeover yields to input. Manual /ai and
    -- manual-checkbox takeovers leave mod._gt_ai_afk_took_over false, so input never ends them.
    if not mod._gt_ai_afk_took_over then return end
    if _gt_local_any_input() then
        mod._gt_ai_afk_took_over = false
        mod._gt_ai_afk_grace_until = _AFK_REARM_GRACE
        mod._gt_ai_afk_idle_t = 0.0
        mod:set("ai_takeover_enabled", false)   -- end takeover via the same dispatch
    end
end)
