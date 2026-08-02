-- Runtime owner for issue #465 replacement-player progression handoff.
-- Loaded once by chaos_wastes_tweaker_dev.lua; owns the four lifecycle hooks
-- and their bounded state/projection helpers.
local M = {}

function M.install(mod, deps)
    local effective_setting = assert(deps and deps.effective_setting, "#465 effective_setting dependency missing")
    local REAL_PLAYER_LOCAL_ID = assert(deps and deps.real_player_local_id, "#465 real player id dependency missing")

-- ============================================================
-- Replacement-player progression compensation (Issue #465)
-- ============================================================
-- Vanilla keeps CW progression under (peer, local-player, profile, career) keys.
-- Removing a bot for a joiner does not move those keys, and adding a bot after a
-- departure initializes a fresh profile row. Preserve the selected replacement's
-- boons, persistent buffs, and serialized melee/ranged CW weapons at the exact
-- GameModeDeus add/remove boundaries. A joining human receives the host's current
-- coin balance, per the feature specification; a departure-created bot receives
-- the departing human's balance until another human takes over.
--
-- Direct run-state writes use only vanilla SharedState fields. No custom RPC or
-- per-frame polling is involved. If CT peer parity has not been positively proven,
-- CT-owned boon/buff names are filtered before the copy so this convenience feature
-- can never put an unknown NetworkLookup index on a joining peer's wire.
CT_REPLACEMENT_COMPENSATION_MARKER = "replacement_compensation:pre_remove_capture_edges_v3"
mod._ct_replacement_policy = mod:dofile("scripts/mods/chaos_wastes_tweaker_dev/_ct_replacement_compensation")
mod._ct_replacement_cache = {}
mod._ct_replacement_pending_humans = {}
mod._ct_replacement_log_count = 0
mod._ct465_edges = {
    manager_left = 0,
    deus_left = 0,
    manager_remove = 0,
    deus_remove = 0,
    pre_remove_capture = 0,
    applied = 0,
}

function mod._ct_replacement_log(fmt, ...)
    if mod._ct_replacement_log_count >= 64 then return end
    mod._ct_replacement_log_count = mod._ct_replacement_log_count + 1
    pcall(printf, "[ct:465] " .. fmt, ...)
end

function mod._ct465_record_edge(name, game_mode)
    local edges = mod._ct465_edges
    if type(edges) ~= "table" or type(edges[name]) ~= "number" then return end
    edges[name] = edges[name] + 1
    local active = Managers.state and Managers.state.game_mode
        and Managers.state.game_mode._game_mode
    mod._ct_replacement_log("edge=%s count=%d mode=%s same_active=%s server=%s enabled=%s",
        tostring(name), edges[name], tostring(game_mode), tostring(game_mode == active),
        tostring(game_mode and game_mode._is_server),
        tostring(effective_setting("replacement_player_compensation")))
end

function mod._ct465_report()
    local e = mod._ct465_edges or {}
    local complete = (e.manager_left or 0) > 0 and (e.deus_left or 0) > 0
        and (e.manager_remove or 0) > 0 and (e.deus_remove or 0) > 0
        and (e.pre_remove_capture or 0) > 0 and (e.applied or 0) >= 2
    pcall(printf, "[ct:465] report manager_left=%d deus_left=%d manager_remove=%d deus_remove=%d pre_capture=%d applied=%d complete=%s",
        e.manager_left or 0, e.deus_left or 0, e.manager_remove or 0,
        e.deus_remove or 0, e.pre_remove_capture or 0, e.applied or 0,
        tostring(complete))
    return complete, e
end

mod:command("ct_report_465", "Report bot-substitution lifecycle receipts for issue #465.", function()
    mod._ct465_report()
end)

function mod._ct_replacement_filtered(snapshot)
    local wire_safe = mod._ct_wire_safe and mod._ct_wire_safe() or false
    local ok, filtered, removed_power_ups, removed_buffs = pcall(
        mod._ct_replacement_policy.wire_safe_copy, snapshot, wire_safe,
        mod._ct_is_modded_power_up, mod._ct_is_ct_buff_template)
    if not ok then return nil, 0, 0, filtered end
    return filtered, removed_power_ups, removed_buffs
end

function mod._ct_replacement_capture(run_state, peer_id, local_player_id, profile_index, career_index)
    local ok, snapshot, reason = pcall(mod._ct_replacement_policy.capture, run_state,
        peer_id, local_player_id, profile_index, career_index)
    if not ok then return nil, snapshot end
    return snapshot, reason
end

function mod._ct_replacement_apply(run_state, peer_id, local_player_id, profile_index, career_index, snapshot, coins)
    local ok, applied, reason = pcall(mod._ct_replacement_policy.apply, run_state,
        peer_id, local_player_id, profile_index, career_index, snapshot, coins)
    if not ok then return false, applied end
    return applied, reason
end

function mod._ct_replacement_pending_key(peer_id, local_player_id)
    return tostring(peer_id) .. ":" .. tostring(local_player_id)
end

function mod._ct_replacement_project_weapon(run_controller, source_string, target_string, slot_name, profile_index, career_index)
    if type(source_string) ~= "string" or type(target_string) ~= "string" then
        return nil, "source/target loadout not initialized"
    end
    local generation = rawget(_G, "DeusWeaponGeneration")
    if type(generation) ~= "table" or type(generation.deserialize_weapon) ~= "function"
        or type(generation.upgrade_item) ~= "function" or type(generation.serialize_weapon) ~= "function" then
        return nil, "DeusWeaponGeneration unavailable"
    end

    local source_ok, source_weapon = pcall(generation.deserialize_weapon, source_string)
    local target_ok, target_weapon = pcall(generation.deserialize_weapon, target_string)
    if not source_ok or not target_ok or type(source_weapon) ~= "table" or type(target_weapon) ~= "table"
        or type(source_weapon.rarity) ~= "string" then
        return nil, "weapon deserialize failed"
    end
    if target_weapon.rarity == source_weapon.rarity then return target_string end

    local run_state = run_controller and run_controller._run_state
    local difficulty = run_state and run_state.get_run_difficulty and run_state:get_run_difficulty()
    local node_key = run_state and run_state.get_current_node_key and run_state:get_current_node_key()
    local graph = run_controller and run_controller._get_graph_data and run_controller:_get_graph_data()
    local progress = graph and node_key and graph[node_key] and graph[node_key].run_progress or 0
    local seed_text = table.concat({ tostring(run_state and run_state:get_run_id() or "465"),
        tostring(profile_index), tostring(career_index), tostring(slot_name), tostring(source_weapon.rarity) }, ":")
    local seed = 465
    local hash = rawget(_G, "HashUtils")
    if hash and type(hash.fnv32_hash) == "function" then
        local hash_ok, value = pcall(hash.fnv32_hash, seed_text)
        if hash_ok and type(value) == "number" then seed = value end
    end
    local upgrade_ok, projected = pcall(generation.upgrade_item, target_weapon,
        difficulty or "normal", progress, source_weapon.rarity, seed)
    if not upgrade_ok or type(projected) ~= "table" then
        return nil, "tier projection failed: " .. tostring(projected)
    end
    local serialize_ok, serialized = pcall(generation.serialize_weapon, projected)
    if not serialize_ok or type(serialized) ~= "string" then
        return nil, "projected serialization failed"
    end
    return serialized
end

function mod._ct_replacement_prepare_target(run_controller, peer_id, local_player_id,
        profile_index, career_index, snapshot)
    local run_state = run_controller and run_controller._run_state
    local target, capture_reason = mod._ct_replacement_capture(run_state, peer_id,
        local_player_id, profile_index, career_index)
    if not target then return nil, { tostring(capture_reason) } end
    return mod._ct_replacement_policy.prepare_for_target(snapshot, target,
        profile_index, career_index, function(source_string, target_string, slot_name)
            return mod._ct_replacement_project_weapon(run_controller, source_string,
                target_string, slot_name, profile_index, career_index)
        end)
end

function mod._ct_replacement_refresh_status(game_mode, peer_id, local_player_id, profile_index, career_index)
    local spawning = game_mode and game_mode._deus_spawning
    if not (spawning and type(spawning._restore_player_game_mode_data) == "function") then
        return false, "DeusSpawning restore unavailable"
    end
    local party = Managers.party
    local status = party and party:get_player_status(peer_id, local_player_id)
    if not status then return false, "party status unavailable" end
    local ok, restored = pcall(spawning._restore_player_game_mode_data, spawning,
        peer_id, local_player_id, profile_index, career_index)
    if not ok or type(restored) ~= "table" then return false, tostring(restored) end
    status.game_mode_data = restored
    return true
end

function mod._ct_replacement_refresh_bot(game_mode, bot, run_state, snapshot)
    local profile_index, career_index = bot:profile_index(), bot:career_index()
    local profile = rawget(_G, "SPProfiles") and SPProfiles[profile_index]
    local career = profile and profile.careers and profile.careers[career_index]
    local mechanism_manager = Managers.mechanism
    local mechanism = mechanism_manager and mechanism_manager:game_mechanism()
    local talent_ok = mechanism and type(mechanism._update_career_loadout) == "function"
        and pcall(mechanism._update_career_loadout, mechanism,
            bot:local_player_id(), career and career.name, true)

    local weapons_ok = type(mod._ct_bot_equip_weapon) == "function"
    local generation = rawget(_G, "DeusWeaponGeneration")
    for _, slot_name in ipairs({ "slot_melee", "slot_ranged" }) do
        local serialized = snapshot and snapshot[slot_name]
        if serialized and weapons_ok and generation and type(generation.deserialize_weapon) == "function" then
            local decode_ok, weapon = pcall(generation.deserialize_weapon, serialized)
            local equip_ok, applied, reason = false, false, "deserialize failed"
            if decode_ok and weapon then
                equip_ok, applied, reason = pcall(mod._ct_bot_equip_weapon, bot, weapon,
                    slot_name, run_state, bot:network_id())
            end
            if not equip_ok or not applied then
                weapons_ok = false
                mod._ct_replacement_log("bot backend refresh failed slot=%s reason=%s",
                    tostring(slot_name), tostring(reason or applied))
            end
        elseif serialized then
            weapons_ok = false
        end
    end
    local status_ok, status_reason = mod._ct_replacement_refresh_status(game_mode,
        bot:network_id(), bot:local_player_id(), profile_index, career_index)
    return talent_ok == true and weapons_ok and status_ok,
        string.format("talents=%s weapons=%s status=%s:%s", tostring(talent_ok == true),
            tostring(weapons_ok), tostring(status_ok), tostring(status_reason))
end

function mod._ct_replacement_apply_handoff(game_mode, run_controller, peer_id, local_player_id,
        profile_index, career_index, snapshot, coin_override, bot)
    local prepared, projection_failures = mod._ct_replacement_prepare_target(run_controller,
        peer_id, local_player_id, profile_index, career_index, snapshot)
    if not prepared then
        return false, nil, 0, 0, "target prepare failed: " .. table.concat(projection_failures or {}, ",")
    end
    local filtered, removed_power_ups, removed_buffs, filter_reason = mod._ct_replacement_filtered(prepared)
    if not filtered then return false, nil, 0, 0, tostring(filter_reason) end
    local run_state = run_controller and run_controller._run_state
    local applied, reason = mod._ct_replacement_apply(run_state, peer_id, local_player_id,
        profile_index, career_index, filtered, coin_override)
    local refresh_ok, refresh_reason
    if applied and bot then
        refresh_ok, refresh_reason = mod._ct_replacement_refresh_bot(game_mode, bot, run_state, filtered)
    elseif applied then
        refresh_ok, refresh_reason = mod._ct_replacement_refresh_status(game_mode,
            peer_id, local_player_id, profile_index, career_index)
    end
    if applied then
        mod._ct465_edges.applied = mod._ct465_edges.applied + 1
    end
    local projection_text = table.concat(projection_failures or {}, ",")
    return applied, filtered, removed_power_ups or 0, removed_buffs or 0,
        string.format("apply=%s refresh=%s:%s projection=%s filter=%s",
            tostring(reason), tostring(refresh_ok), tostring(refresh_reason),
            projection_text ~= "" and projection_text or "exact", tostring(filter_reason))
end

mod:hook("GameModeDeus", "player_left_game_session", function(func, self, peer_id, local_player_id)
    local enabled = self and self._is_server
        and effective_setting("replacement_player_compensation")
    if enabled then mod._ct465_record_edge("deus_left", self) end
    if enabled then
        local run_state = self._deus_run_controller and self._deus_run_controller._run_state
        if run_state then
            local profile_index, career_index = run_state:get_player_profile(peer_id, local_player_id)
            if not profile_index or profile_index == 0 then
                local player = Managers.player and Managers.player:player(peer_id, local_player_id)
                profile_index = player and player.profile_index and player:profile_index() or profile_index
                career_index = player and player.career_index and player:career_index() or career_index
            end
            local snapshot, reason = mod._ct_replacement_capture(run_state, peer_id,
                local_player_id, profile_index, career_index)
            local key = mod._ct_replacement_policy.profile_key(profile_index, career_index)
            if snapshot and key then
                mod._ct_replacement_cache[key] = mod._ct_replacement_cache[key] or {}
                mod._ct_replacement_cache[key][#mod._ct_replacement_cache[key] + 1] = snapshot
                mod._ct_replacement_log("captured departing human peer=%s local=%s profile=%s:%s boons=%d coins=%s",
                    tostring(peer_id), tostring(local_player_id), tostring(profile_index),
                    tostring(career_index), #(snapshot.power_ups or {}), tostring(snapshot.coins))
            else
                mod._ct_replacement_log("departure capture skipped peer=%s local=%s reason=%s",
                    tostring(peer_id), tostring(local_player_id), tostring(reason))
            end
        end
    end
    return func(self, peer_id, local_player_id)
end)

-- The manager is the source-backed public delegation seam. Recording it next to
-- the concrete GameModeDeus hook distinguishes "the game never delegated" from
-- "the concrete hook was not the active class" without polling per frame.
mod:hook("GameModeManager", "player_left_game_session", function(func, self, peer_id, local_player_id)
    if effective_setting("replacement_player_compensation") then
        mod._ct465_record_edge("manager_left", self and self._game_mode)
    end
    return func(self, peer_id, local_player_id)
end)

mod:hook_safe("GameModeDeus", "_add_bot", function(self)
    if not (self and self._is_server) then return end
    local bots = self._bot_players
    local bot = bots and bots[#bots]
    local run_state = self._deus_run_controller and self._deus_run_controller._run_state
    if not (bot and run_state) then return end

    -- Fresh bots begin with their own ledger seeded from the host's live balance.
    -- A #465 departure snapshot, when present, intentionally overwrites this seed
    -- below with the departing human's balance.
    if mod._ct_bot_economy_active() then
        local bot_peer, bot_local = bot:network_id(), bot:local_player_id()
        local ledger_key = tostring(bot_peer) .. ":" .. tostring(bot_local)
        local host_peer = run_state:get_server_peer_id()
        local host_coins = run_state:get_player_soft_currency(host_peer, REAL_PLAYER_LOCAL_ID) or 0
        run_state:set_player_soft_currency(bot_peer, bot_local, host_coins)
        mod._ct_bot_economy_initialized[ledger_key] = true
        mod._ct_bot_economy_log("initialized bot=%s balance=%s from host",
            tostring(bot.name and bot:name() or bot_local), tostring(host_coins))
    end

    if not effective_setting("replacement_player_compensation") then return end

    local profile_index = bot:profile_index()
    local career_index = bot:career_index()
    local key = mod._ct_replacement_policy.profile_key(profile_index, career_index)
    local queue = key and mod._ct_replacement_cache[key]
    local source_key = key
    if not (queue and queue[1]) then
        -- Vanilla chooses the bot's configured career, which may differ from the
        -- departing human's career. Fall back to the queued row for the same hero;
        -- the prepare step projects only weapon TIERS onto the bot's own weapons.
        local profile_prefix = tostring(profile_index) .. ":"
        for candidate_key, candidate_queue in pairs(mod._ct_replacement_cache) do
            if type(candidate_key) == "string" and candidate_key:sub(1, #profile_prefix) == profile_prefix
                and candidate_queue and candidate_queue[1] then
                source_key, queue = candidate_key, candidate_queue
                break
            end
        end
    end
    local snapshot = queue and queue[1]
    if not snapshot then
        local cache_rows = 0
        for _, candidate_queue in pairs(mod._ct_replacement_cache) do
            cache_rows = cache_rows + #(candidate_queue or {})
        end
        mod._ct_replacement_log("human->bot no departure row target=%s:%s cache_rows=%d",
            tostring(profile_index), tostring(career_index), cache_rows)
        return
    end

    local ok, filtered, removed_power_ups, removed_buffs, reason = mod._ct_replacement_apply_handoff(
        self, self._deus_run_controller, bot:network_id(), bot:local_player_id(),
        profile_index, career_index, snapshot, nil, bot)
    if ok then
        table.remove(queue, 1)
        if #queue == 0 then mod._ct_replacement_cache[source_key] = nil end
    end
    mod._ct_replacement_log("human->bot source=%s:%s target=%s:%s applied=%s boons=%d coins=%s parity_filtered=%d/%d reason=%s",
        tostring(snapshot.profile_index), tostring(snapshot.career_index),
        tostring(profile_index), tostring(career_index), tostring(ok),
        #(filtered and filtered.power_ups or {}), tostring(filtered and filtered.coins),
        removed_power_ups or 0, removed_buffs or 0, tostring(reason))
end)

local function select_bot_before_remove(self, peer_id, local_player_id)
    local bots = self and self._bot_players
    if type(bots) ~= "table" or #bots == 0 then return nil, nil end
    local profile_index
    local synchronizer = self._profile_synchronizer
    if synchronizer and type(synchronizer.profile_by_peer) == "function" then
        local ok, result = pcall(synchronizer.profile_by_peer, synchronizer,
            peer_id, local_player_id)
        if ok then profile_index = result end
    end
    if profile_index then
        for i = 1, #bots do
            local candidate = bots[i]
            if candidate and candidate.profile_index
                and candidate:profile_index() == profile_index then
                return candidate, profile_index
            end
        end
    end
    return bots[#bots], profile_index
end

mod:hook("GameModeDeus", "remove_bot", function(func, self, party_id, peer_id, local_player_id, update_safe)
    local enabled = self and self._is_server
        and effective_setting("replacement_player_compensation")
    if enabled then mod._ct465_record_edge("deus_remove", self) end
    local run_controller = enabled and self._deus_run_controller
    local run_state = run_controller and run_controller._run_state
    local selected_bot, selected_profile
    local bot_profile, bot_career, snapshot, capture_reason
    if run_state then
        selected_bot, selected_profile = select_bot_before_remove(self, peer_id, local_player_id)
        if selected_bot then
            bot_profile = selected_bot:profile_index()
            bot_career = selected_bot:career_index()
            snapshot, capture_reason = mod._ct_replacement_capture(run_state,
                selected_bot:network_id(), selected_bot:local_player_id(),
                bot_profile, bot_career)
            if snapshot then
                mod._ct465_edges.pre_remove_capture = mod._ct465_edges.pre_remove_capture + 1
            end
            mod._ct_replacement_log("bot->human pre-remove selected=%s:%s requested_profile=%s captured=%s reason=%s",
                tostring(bot_profile), tostring(bot_career), tostring(selected_profile),
                tostring(snapshot ~= nil), tostring(capture_reason))
        end
    end

    local bot = func(self, party_id, peer_id, local_player_id, update_safe)
    if not (bot and enabled and run_state) then
        return bot
    end
    if selected_bot ~= bot then
        mod._ct_replacement_log("bot->human selection mismatch selected=%s returned=%s; fail-closed",
            tostring(selected_bot), tostring(bot))
        return bot
    end
    local target_profile, target_career = run_state:get_player_profile(peer_id, local_player_id)
    if not snapshot then
        mod._ct_replacement_log("bot->human capture skipped target=%s reason=%s",
            tostring(peer_id), tostring(capture_reason))
        return bot
    end
    local initialized = target_profile and target_career and run_state.get_profile_initialized
        and run_state:get_profile_initialized(peer_id, local_player_id,
            target_profile, target_career)
    if not initialized then
        local pending_key = mod._ct_replacement_pending_key(peer_id, local_player_id)
        mod._ct_replacement_pending_humans[pending_key] = {
            game_mode = self,
            snapshot = snapshot,
            bot_profile = bot_profile,
            bot_career = bot_career,
        }
        mod._ct_replacement_log("bot->human deferred bot=%s:%s target=%s:%s pending=%s awaiting=rpc_deus_set_initial_setup",
            tostring(bot_profile), tostring(bot_career), tostring(target_profile),
            tostring(target_career), tostring(pending_key))
        return bot
    end

    local host_peer = run_state:get_server_peer_id()
    local host_coins = run_state:get_player_soft_currency(host_peer, REAL_PLAYER_LOCAL_ID)
    local ok, filtered, removed_power_ups, removed_buffs, apply_reason =
        mod._ct_replacement_apply_handoff(self, run_controller, peer_id, local_player_id,
            target_profile, target_career, snapshot, host_coins, nil)
    mod._ct_replacement_log("bot->human bot_profile=%s:%s target=%s:%s applied=%s boons=%d host_coins=%s parity_filtered=%d/%d reason=%s",
        tostring(bot_profile), tostring(bot_career), tostring(target_profile), tostring(target_career),
        tostring(ok), #(filtered and filtered.power_ups or {}), tostring(host_coins),
        removed_power_ups or 0, removed_buffs or 0, tostring(apply_reason))
    return bot
end)

mod:hook("GameModeManager", "remove_bot", function(func, self, party_id, peer_id, local_player_id, update_safe)
    if effective_setting("replacement_player_compensation") then
        mod._ct465_record_edge("manager_remove", self and self._game_mode)
    end
    return func(self, party_id, peer_id, local_player_id, update_safe)
end)

-- A joining client's setup RPC can arrive on either side of remove_bot. If the
-- bot was selected first, let vanilla initialize the target career/loadout row,
-- then replace that row exactly once. This avoids marking an empty row initialized
-- and suppressing the only vanilla RPC capable of supplying target-career weapons.
mod:hook("DeusRunController", "rpc_deus_set_initial_setup", function(func, self,
        sender_channel_id, profile_index, career_index, initial_talents_for_career,
        melee_item_string, ranged_item_string)
    local ret_a, ret_b = func(self, sender_channel_id, profile_index, career_index,
        initial_talents_for_career, melee_item_string, ranged_item_string)
    local channels = rawget(_G, "CHANNEL_TO_PEER_ID") or {}
    local peer_id = rawget(channels, sender_channel_id)
    local pending_key = peer_id and mod._ct_replacement_pending_key(peer_id, REAL_PLAYER_LOCAL_ID)
    local pending = pending_key and mod._ct_replacement_pending_humans[pending_key]
    if pending and self and self._run_state and self._run_state:is_server() then
        local host_peer = self._run_state:get_server_peer_id()
        local host_coins = self._run_state:get_player_soft_currency(host_peer, REAL_PLAYER_LOCAL_ID)
        local ok, filtered, removed_power_ups, removed_buffs, reason =
            mod._ct_replacement_apply_handoff(pending.game_mode, self, peer_id,
                REAL_PLAYER_LOCAL_ID, profile_index, career_index,
                pending.snapshot, host_coins, nil)
        if ok then mod._ct_replacement_pending_humans[pending_key] = nil end
        mod._ct_replacement_log("bot->human deferred-finish bot=%s:%s target=%s:%s applied=%s boons=%d host_coins=%s parity_filtered=%d/%d reason=%s",
            tostring(pending.bot_profile), tostring(pending.bot_career), tostring(profile_index),
            tostring(career_index), tostring(ok), #(filtered and filtered.power_ups or {}),
            tostring(host_coins), removed_power_ups or 0, removed_buffs or 0, tostring(reason))
    end
    return ret_a, ret_b
end)


end

return M
