-- _ct_blessed_bots.lua - Consolidated host-side bot features for CT.
--
-- Owns CT's single PlayerBotBase.update hook. Blessed Bots and automatic
-- Pilgrim's Coin pickup use independent bounded throttles so neither feature
-- adds another per-frame engine query or competing hook.
--
-- Owned by: chaos_wastes_tweaker_dev.lua entry point. Consumed via: mod:dofile.

local mod = get_mod("ct_dev")

-- ============================================================================
-- Blessed Bots: Survival Boons (any gamemode)
-- ============================================================================
-- Grants every bot a curated set of three Chaos Wastes survival boons in ANY
-- game mode (not just the Wastes), to improve team survivability. Source
-- citations into the decompiled vanilla source (verified 2026-06-17):
--   * Ereth Khial's Pride     = last_player_standing_power_reg
--       (deus_power_up_settings.lua:2865; +power & health regen when all allies down)
--   * Grimnir's Implacability  = deus_second_wind
--       (deus_power_up_settings.lua:2048; at low HP: attack/move speed + brief invuln)
--   * Morr's Protection        = deus_knockdown_damage_immunity_aura
--       (deus_power_up_settings.lua:2371; range-10 aura: downed allies invulnerable)
--
-- All three are buff_template boons (not talents). Vanilla grants a non-talent
-- boon via buff_system:add_buff(unit, power_up.buff_name) where buff_name is the
-- rarity-suffixed registered name (deus_power_up_utils.lua:441). The boot loop at
-- deus_power_up_settings.lua:7146/7161 registers "power_up_<key>_<rarity>" into
-- DeusPowerUpBuffTemplates. The boons + their sub-buffs are server-authoritative
-- (set_overpowered / aura run `if is_server`), so we grant on the HOST only --
-- and bots only exist on the host anyway.
--
-- RESOLUTION: BuffUtils.get_buff_template reads ONLY the global BuffTemplates
-- (buff_utils.lua:257). The deus templates are folded into BuffTemplates via the
-- morris DLC at boot (morris_buff_settings.lua:7310), but to be robust OUTSIDE a
-- CW run we additively mirror DeusPowerUpBuffTemplates into BuffTemplates
-- ourselves (idempotent; never clobbers an existing entry) before granting, so
-- every deus power-up AND its sub-buffs resolve in any game mode.
--
-- EXPERIMENTAL -- verify in-game. Host-side only; no network registration.

local ScriptUnit = ScriptUnit
local HEALTH_ALIVE = HEALTH_ALIVE
local Managers = Managers
local BuffUtils = BuffUtils
local coin_policy = mod:dofile("scripts/mods/chaos_wastes_tweaker_dev/_ct_bot_coin_pickup")
mod._ct_bot_coin_pickup = coin_policy

local _coin_claims = setmetatable({}, { __mode = "k" })
local _coin_log_count = 0

local function _clear_array(tbl)
    for i = #tbl, 1, -1 do tbl[i] = nil end
end

local function _try_pick_up_coin(unit, blackboard, t)
    local due, next_t = coin_policy.poll_due(t, blackboard._ct_coin_pickup_next_t)
    if not due then return end
    blackboard._ct_coin_pickup_next_t = next_t

    local entity = Managers.state.entity
    local pickup_system = entity and entity:system("pickup_system")
    local interactor_extension = ScriptUnit.has_extension(unit, "interactor_system")
    if not (pickup_system and interactor_extension) then return end
    if interactor_extension.is_interacting and interactor_extension:is_interacting() then return end

    local position = POSITION_LOOKUP[unit]
    if not position then return end
    local results = blackboard._ct_coin_pickup_results
    if not results then
        results = {}
        blackboard._ct_coin_pickup_results = results
    else
        _clear_array(results)
    end
    local count = tonumber(pickup_system:get_pickups(position, coin_policy.range, results)) or 0
    for i = 1, count do
        local pickup_unit = results[i]
        local pickup_extension = pickup_unit
            and ScriptUnit.has_extension(pickup_unit, "pickup_system")
        if pickup_extension
            and coin_policy.can_claim(pickup_extension.pickup_name, _coin_claims[pickup_unit], t) then
            _coin_claims[pickup_unit] = coin_policy.claim_until(t)
            local forced = true
            local ok = pcall(interactor_extension.start_interaction, interactor_extension,
                false, pickup_unit, "pickup_object", forced)
            if not ok then
                _coin_claims[pickup_unit] = nil
                if _coin_log_count < 32 then
                    _coin_log_count = _coin_log_count + 1
                    pcall(printf, "[ct:331] bot coin interaction rejected count=%d",
                        _coin_log_count)
                end
                return
            end
            if _coin_log_count < 32 then
                _coin_log_count = _coin_log_count + 1
                pcall(printf, "[ct:331] bot coin interaction started count=%d range=%dm claim_ttl=%.1fs",
                    _coin_log_count, coin_policy.range, coin_policy.claim_ttl)
            end
            return
        end
    end
end

-- Rarity suffixes per the DeusPowerUpRarityPool listing (each boon appears once):
--   deus_second_wind / last_player_standing_power_reg -> exotic
--   deus_knockdown_damage_immunity_aura               -> unique
local BOON_BUFFS = {
    "power_up_last_player_standing_power_reg_exotic",      -- Ereth Khial's Pride
    "power_up_deus_second_wind_exotic",                    -- Grimnir's Implacability
    "power_up_deus_knockdown_damage_immunity_aura_unique", -- Morr's Protection
}

local _deus_buffs_mirrored = false
local function _ensure_deus_buffs_registered()
    if _deus_buffs_mirrored then
        return true
    end
    local BT = rawget(_G, "BuffTemplates")
    local DPBT = rawget(_G, "DeusPowerUpBuffTemplates")
    if not (BT and DPBT) then
        return false
    end
    for k, v in pairs(DPBT) do
        if BT[k] == nil then
            BT[k] = v
        end
    end
    _deus_buffs_mirrored = true
    mod:debug("[ct:blessed-bots] mirrored DeusPowerUpBuffTemplates into BuffTemplates (any-gamemode resolution)")
    return true
end

local function _is_server()
    return Managers and Managers.player and Managers.player.is_server
end

-- Grant the survival boons to one bot unit, skipping any it already carries.
local function _grant_boons_to_bot(unit)
    local buff_extension = ScriptUnit.has_extension(unit, "buff_system")
    if not buff_extension then
        return
    end
    local buff_system = Managers.state.entity and Managers.state.entity:system("buff_system")
    if not buff_system then
        return
    end

    for _, buff_name in ipairs(BOON_BUFFS) do
        local already = buff_extension.has_buff_type and buff_extension:has_buff_type(buff_name)
        if not already then
            if BuffUtils.get_buff_template(buff_name) then
                buff_system:add_buff(unit, buff_name, unit)
                mod:debug("[ct:blessed-bots] granted %s to a bot", buff_name)
            else
                mod:debug("[ct:blessed-bots] template %s not registered; skipped", buff_name)
            end
        end
    end
end

-- Drive per-bot, throttled. PlayerBotBase.update runs per-bot on the host every
-- frame; ct hooks it ONLY here, so this is the single PlayerBotBase.update hook
-- for this mod (no duplicate). Re-checks every ~2s so boons re-apply after a
-- bot dies and respawns.
mod:hook_safe("PlayerBotBase", "update", function (self, unit, input, dt, context, t)
    -- This remains CT's only PlayerBotBase.update hook. Coin pickup and Blessed
    -- Bots keep independent throttles (1s / 2s); the per-frame common path only
    -- reads settings/timestamps and never queries PickupSystem.
    local blackboard = self._blackboard
    if not blackboard then
        return
    end

    local server = _is_server()
    local alive = HEALTH_ALIVE[unit]
    if mod:get("bots_pick_up_pilgrims_coins") then
        if server and alive then _try_pick_up_coin(unit, blackboard, t) end
    elseif next(_coin_claims) ~= nil then
        _coin_claims = setmetatable({}, { __mode = "k" })
    end

    local next_t = blackboard._ct_blessed_next_t or 0
    if t < next_t then
        return
    end
    blackboard._ct_blessed_next_t = t + 2.0

    if not mod:get("ct_blessed_bots") then
        return
    end
    if not server then
        return
    end

    if not alive then
        return
    end
    if not _ensure_deus_buffs_registered() then
        return
    end

    _grant_boons_to_bot(unit)
end)
