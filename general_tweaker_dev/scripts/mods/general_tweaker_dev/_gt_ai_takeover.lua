local mod = get_mod("gt_dev")
local _printf = rawget(_G, "printf") or function() end

-- _gt_ai_takeover.lua — AI Takeover (hand your character to a bot) + AFK-takeover
--
-- Extracted from the main file in Phase 4 and rebuilt for #247. Lets a player
-- hand control of their character to a bot (manual /ai +
-- the ai_takeover_enabled checkbox) and auto-hand-off after going AFK
-- (gt_ai_afk_takeover). Server-driven: only the host performs the swap; clients
-- send an authenticated VMF request and receive the host's actual result. The
-- human Player/profile/party slot remain intact; only the unit is despawned,
-- while one temporary real bot uses a free slot or a remembered native bot slot.
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
-- Exposed helper: mod._gt_ai_swap_human_to_bot (runtime wiring check).
--
-- The debug AI-toggle dump wrap here calls mod._gt_dump_ai_now (exposed by
-- _gt_debug_probes.lua) — resolved at call time, so module load order between
-- the two is irrelevant.
--
-- Singleton hooks: the only Class.method hook in this block is the VMF network
-- event registrations (mod:network_register, not mod:hook). The
-- AICommanderExtension._update_units always-on crash guard is a SEPARATE feature
-- and STAYS in the main file. The two per-frame consumers (`ai_pending`,
-- `afk_autobot`) register through mod._gt_register_update.

-- ============================================================
-- AI Toggle (hand off control to a bot)
-- ============================================================
-- VT2 has no hot-swap path between human and bot units — they use different
-- go_types with incompatible extension stacks (PlayerInputExtension vs
-- PlayerBotInput, GenericCharacterStateMachineExtension vs PlayerBotBase,
-- etc.). #247 therefore keeps the human identity and slot, despawns only its
-- unit, and creates one native bot in a free/yielded slot. Reclaim removes it and
-- uses the game mode's native force-respawn path.
--
-- Server-driven: only the host can perform the swap (ProfileSynchronizer
-- and PartyManager APIs assert is_server). Clients send a VMF network
-- request and the host validates + executes.
--
-- Scope: host and authenticated client self-toggle; Adventure, Deus, and Weave;
-- full parties, Versus, hubs, tutorials, dead owners, and missing APIs refuse.

local _AI_RPC = "gt_ai_toggle_request"
local _AI_RESULT_RPC = "gt_ai_toggle_result"
local _takeover_policy = mod:dofile("scripts/mods/general_tweaker_dev/_gt_ai_takeover_policy")
mod._GT_247_KEEP_SLOT_MARKER = "gt-247-keep-slot-v1"
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

-- The retired convert-in-place swap produced owner-less units
-- (client kept controlling a unit the host orphaned -> owner_player nil in the
-- health extension), host/client ownership desync, and a string of despawn-race
-- crashes (0.2.113-0.2.115). The active redesign is engine-native KEEP-SLOT:
-- keep the human's Player + party slot intact, despawn ONLY the unit, the client
-- enters the vanilla observer camera (the dead/respawn flow), a REAL host bot
-- fills a free or safely yielded bot slot, and reclaim uses normal respawn.
-- The emergency `mod._gt_ai_takeover_disabled` gate remains available without
-- being the normal state. Existing teardown nil-guards remain active.

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

local function _ai_find_bot(peer_id, local_player_id)
    local pm = Managers.player
    local bots = pm and pm:bots() or {}
    for _, bot in ipairs(bots) do
        local bp = bot:network_id()
        local bl = bot:local_player_id()
        if bp == peer_id and bl == local_player_id then
            return bot
        end
    end
    return nil
end

local function _ai_is_takeover_bot(bot)
    local peer_id = bot:network_id()
    local local_player_id = bot:local_player_id()
    for _, saved in pairs(mod._gt_ai_saved_state) do
        if saved.bot_peer_id == peer_id and saved.bot_local_player_id == local_player_id then
            return true
        end
    end
    return false
end

local function _ai_find_displaceable_bot(party_id)
    local bots = Managers.player and Managers.player:bots() or {}
    for i = #bots, 1, -1 do
        local bot = bots[i]
        local status = Managers.party:get_player_status(bot:network_id(), bot:local_player_id())
        if status and status.party_id == party_id and not _ai_is_takeover_bot(bot) then
            return bot, status
        end
    end
end

local function _ai_game_mode()
    local manager = Managers.state and Managers.state.game_mode
    return manager and manager.game_mode and manager:game_mode() or nil
end

local function _ai_observe(peer_id, local_player_id, player)
    if peer_id == Network.peer_id() then
        if rawget(_G, "CharacterStateHelper") and CharacterStateHelper.change_camera_state then
            CharacterStateHelper.change_camera_state(player, "observer")
            return true
        end
        return false, "local observer camera API unavailable"
    end

    local channels = rawget(_G, "PEER_ID_TO_CHANNEL")
    local channel_id = channels and channels[peer_id]
    if not channel_id or not (rawget(_G, "RPC") and RPC.rpc_set_observer_camera) then
        return false, "remote observer camera API unavailable"
    end
    RPC.rpc_set_observer_camera(channel_id, local_player_id)
    return true
end

local function _ai_append_bot(game_mode, bot_player)
    local bots = game_mode and game_mode._bot_players
    if type(bots) ~= "table" then return false, "game mode bot roster unavailable" end
    bots[#bots + 1] = bot_player

    -- GameModeDeus._add_bot mirrors this after the shared base constructor.
    -- Preserve that native bookkeeping when the controller exists.
    local run = game_mode._deus_run_controller
    if run and run.restore_persisted_score then
        run:restore_persisted_score(game_mode._statistics_db,
            bot_player:network_id(), bot_player:local_player_id())
    end
    return true
end

local function _ai_create_registered_bot(game_mode, party_id, profile_index, career_index, slot_id)
    local add_ok, bot_or_err = pcall(game_mode._add_bot_to_party, game_mode,
        party_id, profile_index, career_index, slot_id)
    if not add_ok or not bot_or_err then
        return nil, "bot creation failed: " .. tostring(bot_or_err)
    end
    local bot_player = bot_or_err
    local append_ok, roster_ok, roster_err = pcall(_ai_append_bot, game_mode, bot_player)
    if not append_ok or not roster_ok then
        local remove = game_mode._remove_bot_instant or game_mode._remove_bot
        if remove then pcall(remove, game_mode, bot_player, false) end
        return nil, append_ok and roster_err
            or "bot roster registration raised: " .. tostring(roster_ok)
    end
    return bot_player
end

local function _ai_restore_displaced_bot(saved, game_mode)
    local displaced = saved.displaced
    if not displaced then return true end
    local bot, err = _ai_create_registered_bot(game_mode, saved.party_id,
        displaced.profile_index, displaced.career_index, displaced.slot_id)
    if not bot then return false, err end
    saved.displaced = nil
    return true
end

local function _ai_remove_takeover_bot(saved)
    local game_mode = _ai_game_mode()
    if not game_mode then return false, "game mode unavailable" end
    local bot = _ai_find_bot(saved.bot_peer_id, saved.bot_local_player_id)
    if not bot then return true end -- already removed during a native transition
    if not game_mode._remove_bot then return false, "game mode bot removal unavailable" end
    game_mode:_remove_bot(bot, false)
    return true
end

local function _ai_swap_human_to_bot(peer_id, local_player_id)
    if mod._gt_ai_takeover_disabled then return false, "takeover disabled (rebuild in progress)" end
    local pm = Managers.player
    local player = pm and pm:player(peer_id, local_player_id)
    local status = Managers.party and Managers.party:get_player_status(peer_id, local_player_id)
    local party = status and status.party_id and Managers.party:get_party(status.party_id)
    local game_mode = _ai_game_mode()
    local profile_synchronizer = pm and pm.network_manager and pm.network_manager.profile_synchronizer
    local profile_index, career_index
    if profile_synchronizer then
        profile_index, career_index = profile_synchronizer:profile_by_peer(peer_id, local_player_id)
    end
    local unit = player and player.player_unit
    local unit_alive = unit and ALIVE[unit] and true or false
    local mode_key = _ai_game_mode_key()
    local displaceable_bot, displaceable_status
    if status and status.party_id then
        displaceable_bot, displaceable_status = _ai_find_displaceable_bot(status.party_id)
    end
    local ok, err = _takeover_policy.validate_begin({
        is_server = pm and pm.is_server,
        mode_key = mode_key,
        player_exists = player ~= nil,
        is_bot = player and player.bot_player,
        unit_alive = unit_alive,
        has_party_slot = status and status.party_id and status.slot_id and true or false,
        num_used_slots = party and party.num_used_slots,
        num_slots = party and party.num_slots,
        has_displaceable_bot = displaceable_bot ~= nil,
        has_profile = profile_index ~= nil and career_index ~= nil,
        has_game_mode_api = game_mode and game_mode._add_bot_to_party
            and game_mode._remove_bot and game_mode.force_respawn
            and type(game_mode._bot_players) == "table",
    })
    if not ok then return false, err end

    local position = POSITION_LOOKUP[unit] or Unit.local_position(unit, 0)
    local rotation = Unit.local_rotation(unit, 0)
    local saved = {
        peer_id = peer_id,
        local_player_id = local_player_id,
        profile_index = profile_index,
        career_index = career_index,
        party_id = status.party_id,
        human_slot_id = status.slot_id,
    }

    local bot_slot_id
    if party.num_used_slots >= party.num_slots then
        saved.displaced = {
            profile_index = displaceable_bot:profile_index(),
            career_index = displaceable_bot:career_index(),
            slot_id = displaceable_status.slot_id,
        }
        bot_slot_id = displaceable_status.slot_id
        local remove_ok, remove_err = pcall(game_mode._remove_bot, game_mode,
            displaceable_bot, false)
        if not remove_ok then
            return false, "could not yield native bot slot: " .. tostring(remove_err)
        end
    end

    -- Create and register the temporary bot before touching the human unit.
    -- If construction fails, the owner and party slot are still completely
    -- unchanged.  The human profile remains assigned; duplicate profile use is
    -- intentional and bounded to this one temporary bot.
    local bot_player, bot_err = _ai_create_registered_bot(game_mode,
        status.party_id, profile_index, career_index, bot_slot_id)
    if not bot_player then
        local restored, restore_err = _ai_restore_displaced_bot(saved, game_mode)
        if not restored then
            mod:info("[gt:247] rollback bot restore failed: %s", tostring(restore_err))
        end
        return false, "temporary " .. tostring(bot_err)
    end

    saved.bot_peer_id = bot_player:network_id()
    saved.bot_local_player_id = bot_player:local_player_id()
    local bot_status = Managers.party:get_player_status(saved.bot_peer_id, saved.bot_local_player_id)
    saved.bot_slot_id = bot_status and bot_status.slot_id
    local bot_data = bot_status and bot_status.game_mode_data
    if bot_data then
        if bot_data.position and bot_data.position.store then bot_data.position:store(position) end
        if bot_data.rotation and bot_data.rotation.store then bot_data.rotation:store(rotation) end
    end

    mod._gt_ai_saved_state[_ai_state_key(peer_id, local_player_id)] = saved
    local human_data = status.game_mode_data
    if human_data then
        human_data.spawn_state = "despawned"
        if human_data.position and human_data.position.store then human_data.position:store(position) end
        if human_data.rotation and human_data.rotation.store then human_data.rotation:store(rotation) end
    end

    -- Despawn before changing cameras.  If despawn raises, the owner is still
    -- looking through the live human and rollback does not need a reverse
    -- camera RPC.  Once despawn succeeds, a failed observer transition is
    -- recoverable through the mode's native force-respawn path.
    local despawn_ok, despawn_err = pcall(player.despawn, player)
    if not despawn_ok then
        pcall(_ai_remove_takeover_bot, saved)
        pcall(_ai_restore_displaced_bot, saved, game_mode)
        mod._gt_ai_saved_state[_ai_state_key(peer_id, local_player_id)] = nil
        if human_data then
            if player.player_unit and ALIVE[player.player_unit] then
                human_data.spawn_state = "spawned"
            else
                -- A throwing despawn may already have deleted the unit. Ask the
                -- active mode to rebuild it instead of advertising a live unit
                -- that no longer exists.
                pcall(game_mode.force_respawn, game_mode, peer_id, local_player_id)
            end
        end
        return false, "human unit despawn failed: " .. tostring(despawn_err)
    end

    local observe_ok, observe_err = _ai_observe(peer_id, local_player_id, player)
    if not observe_ok then
        pcall(_ai_remove_takeover_bot, saved)
        pcall(_ai_restore_displaced_bot, saved, game_mode)
        mod._gt_ai_saved_state[_ai_state_key(peer_id, local_player_id)] = nil
        local respawn_ok, respawn_err = pcall(game_mode.force_respawn, game_mode,
            peer_id, local_player_id)
        if not respawn_ok then
            return false, tostring(observe_err) .. "; rollback respawn failed: "
                .. tostring(respawn_err)
        end
        return false, observe_err
    end

    mod:info("[gt:247] enter human=%s:%s slot=%s bot=%s:%s slot=%s mode=%s",
        tostring(peer_id), tostring(local_player_id), tostring(saved.human_slot_id),
        tostring(saved.bot_peer_id), tostring(saved.bot_local_player_id),
        tostring(saved.bot_slot_id), tostring(mode_key))

    return true
end
mod._gt_ai_swap_human_to_bot = _ai_swap_human_to_bot

local function _ai_swap_bot_to_human(peer_id, local_player_id)
    if mod._gt_ai_takeover_disabled then return false, "takeover disabled (rebuild in progress)" end
    local pm = Managers.player
    if not (pm and pm.is_server) then return false, "must run on host" end
    local saved = mod._gt_ai_saved_state[_ai_state_key(peer_id, local_player_id)]
    if not saved then return false, "no saved state (toggle to bot first)" end

    local game_mode = _ai_game_mode()
    if not (game_mode and game_mode.force_respawn and game_mode._remove_bot) then
        return false, "reclaim API unavailable"
    end
    local call_ok, removed, remove_err = pcall(_ai_remove_takeover_bot, saved)
    if not call_ok then return false, "temporary bot removal raised: " .. tostring(removed) end
    if not removed then return false, "temporary bot removal failed: " .. tostring(remove_err) end
    local restored, restore_err = _ai_restore_displaced_bot(saved, game_mode)
    if not restored then
        -- Do not strand the human in observer state over party composition.
        -- Vanilla's next _handle_bots pass can refill the now-free slot.
        mod:info("[gt:247] displaced bot restore deferred to vanilla: %s", tostring(restore_err))
    end
    local respawn_ok, respawn_err = pcall(game_mode.force_respawn, game_mode, peer_id, local_player_id)
    if not respawn_ok then return false, "human respawn failed: " .. tostring(respawn_err) end
    mod:info("[gt:247] reclaim human=%s:%s slot=%s bot=%s:%s",
        tostring(peer_id), tostring(local_player_id), tostring(saved.human_slot_id),
        tostring(saved.bot_peer_id), tostring(saved.bot_local_player_id))
    mod._gt_ai_saved_state[_ai_state_key(peer_id, local_player_id)] = nil
    return true
end

local function _ai_host_peer_id()
    if Managers.mechanism and Managers.mechanism.server_peer_id then
        local host = Managers.mechanism:server_peer_id()
        if host then return host end
    end
    local nm = Managers.state and Managers.state.network
    return nm and ((nm.network_client and nm.network_client.server_peer_id)
        or (nm.network_server and nm.network_server.server_peer_id))
end

local function _ai_set_local_active(active)
    active = active and true or false
    mod._gt_ai_suppress_setting_callback = true
    mod:set("ai_takeover_enabled", active)
    mod._gt_ai_suppress_setting_callback = false
    if not active then
        mod._gt_ai_afk_took_over = false
        mod._gt_ai_afk_idle_t = 0
    end
end

local function _ai_reply(peer_id, active, ok, reason)
    reason = tostring(reason or "")
    if #reason > 120 then reason = reason:sub(1, 120) end
    mod:network_send(_AI_RESULT_RPC, peer_id, mod.GT_AI_RPC_SCHEMA,
        active and true or false, ok and true or false, reason)
end

mod:network_register(_AI_RPC, function(sender_peer_id, schema, payload)
    -- VMF_RECIPES § 10 (Issue #44): validate the schema arg FIRST. A peer on a
    -- different gt_dev build -- or an older build that sends no schema arg (its
    -- payload table lands in `schema`) -- fails this match and the request is
    -- dropped gracefully: no swap, no crash. Idempotent no-op, so a stale peer
    -- retrying is harmless. Mirrors the gt_godmode_state receiver gate.
    if sender_peer_id == nil or schema ~= mod.GT_AI_RPC_SCHEMA then
        -- Engine printf (NOT mod:info/mod:warning): a schema mismatch means a peer
        -- on an incompatible gt_dev build was silently dropped, which explains why
        -- their AI-takeover isn't syncing -- the user must see it with mod-logging
        -- OFF. mod:info/warning are invisible in that mode.
        if rawget(_G, "printf") then
            _printf("[rpc:schema] %s mismatch from peer=%s: peer sent v%s, we expect v%s. Dropping.",
                _AI_RPC, tostring(sender_peer_id), tostring(schema), tostring(mod.GT_AI_RPC_SCHEMA))
        end
        return
    end
    mod:info("[gt:247] request sender=%s payload=%s",
        tostring(sender_peer_id), type(payload) == "table" and "table" or tostring(payload))
    if mod._gt_ai_takeover_disabled then
        _ai_reply(sender_peer_id, false, false, "takeover disabled")
        return
    end
    local pm = Managers.player
    if not (pm and pm.is_server) then return end
    payload = type(payload) == "table" and payload or {}
    local auth_ok, peer_id, local_player_id = _takeover_policy.authenticate_request(
        sender_peer_id, payload.peer_id, payload.local_player_id)
    if not auth_ok then
        _ai_reply(sender_peer_id, false, false, peer_id)
        return
    end
    local want_bot = payload.want_bot
    local intent_ok, intent_err = _takeover_policy.validate_intent(want_bot)
    if not intent_ok then
        local active = mod._gt_ai_saved_state[_ai_state_key(peer_id, local_player_id)] ~= nil
        _ai_reply(sender_peer_id, active, false, intent_err)
        return
    end

    local ok, err = _ai_can_swap_in_current_mode()
    if not ok then
        _ai_reply(sender_peer_id, false, false, err)
        return
    end

    -- want_bot is the client's explicit intent (from their checkbox state).
    -- Saved state is the host's view of truth — used to no-op stale requests.
    local has_saved = mod._gt_ai_saved_state[_ai_state_key(peer_id, local_player_id)] ~= nil
    local s_ok, s_err = true, nil
    if want_bot and not has_saved then
        s_ok, s_err = _ai_swap_human_to_bot(peer_id, local_player_id)
    elseif (not want_bot) and has_saved then
        s_ok, s_err = _ai_swap_bot_to_human(peer_id, local_player_id)
    end
    local active = mod._gt_ai_saved_state[_ai_state_key(peer_id, local_player_id)] ~= nil
    mod:info("[gt:247] result peer=%s requested=%s active=%s ok=%s reason=%s",
        tostring(peer_id), tostring(want_bot), tostring(active), tostring(s_ok), tostring(s_err))
    _ai_reply(sender_peer_id, active, s_ok, s_err)
end)

mod:network_register(_AI_RESULT_RPC, function(sender_peer_id, schema, active, ok, reason)
    if schema ~= mod.GT_AI_RPC_SCHEMA or sender_peer_id ~= _ai_host_peer_id() then
        if rawget(_G, "printf") then
            _printf("[gt:247] rejected result sender=%s schema=%s",
                tostring(sender_peer_id), tostring(schema))
        end
        return
    end
    if type(active) ~= "boolean" or type(ok) ~= "boolean" or type(reason) ~= "string" then
        return
    end
    mod._gt_ai_pending_client_send = nil
    _ai_set_local_active(active)
    mod:info("[gt:247] host ack active=%s ok=%s reason=%s",
        tostring(active), tostring(ok), tostring(reason))
    if not ok then mod:echo("AI toggle refused: " .. tostring(reason)) end
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
    -- Emergency kill switch. Returning false makes on_setting_changed revert
    -- the checkbox without entering either native lifecycle boundary.
    if mod._gt_ai_takeover_disabled then
        if want_bot then
            mod:echo("[gt] AI takeover is temporarily disabled by its safety gate.")
        end
        return false, "disabled (rebuild in progress)"
    end

    local ok, err = _ai_can_swap_in_current_mode()
    if not ok then return false, err end

    local pm = Managers.player
    if pm and pm.is_server then
        -- Host self-toggle: defer one tick so the frame finishes reading input
        -- before the human unit enters the native observer/despawn boundary.
        -- The Player object and party slot remain intact throughout.
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
    local host = _ai_host_peer_id()
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
    -- Drop a stale queued request if the emergency gate was armed after enqueue.
    if mod._gt_ai_takeover_disabled then return end
    local pm = Managers.player
    if not (pm and pm.is_server) then return end
    local peer_id = Network.peer_id()
    local local_player_id = 1
    local has_saved = mod._gt_ai_saved_state[_ai_state_key(peer_id, local_player_id)] ~= nil
    if req.want_bot and not has_saved then
        local s_ok, s_err = _ai_swap_human_to_bot(peer_id, local_player_id)
        mod:info("[gt:247] host human->bot: %s", s_ok and "ok" or tostring(s_err))
        if s_ok then mod:echo("AI takeover: ON (your character is now a bot).") end
        if not s_ok then
            _ai_set_local_active(false)
            mod:echo("AI toggle refused: " .. tostring(s_err))
        end
    elseif (not req.want_bot) and has_saved then
        local s_ok, s_err = _ai_swap_bot_to_human(peer_id, local_player_id)
        mod:info("[gt:247] host bot->human: %s", s_ok and "ok" or tostring(s_err))
        if s_ok then mod:echo("AI takeover: OFF (you're back in control).") end
        if not s_ok then
            _ai_set_local_active(true)
            mod:echo("AI toggle refused: " .. tostring(s_err))
        end
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
    local input_aux = rawget(_G, "InputAux")
    local gamepads = input_aux and input_aux.input_device_mapping
        and input_aux.input_device_mapping.gamepad
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

    -- Emergency gate: return silently (this is per-frame) and re-arm cleanly.
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
