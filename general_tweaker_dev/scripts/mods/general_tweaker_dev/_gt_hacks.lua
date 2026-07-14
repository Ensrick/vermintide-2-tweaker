local mod = get_mod("gt_dev")

-- _gt_hacks.lua — the Janoti "Hacks" port groups B/C/D/F (medium cheat/QoL
-- features). Co-located so the singleton audit is local. Every hook below is a
-- singleton (whole-mod grep before extraction confirmed no collision with each
-- other or with the main chunk):
--
--   * CareerExtension.update                      (Ult Controls — cooldown caps)
--   * GenericStatusExtension.add_fatigue_points   (Buffs — infinite stamina;
--     ALSO carries the #529 godmode stamina gate — merged concern, see 5.2)
--   * ProfileRequester.request_profile            (Buffs — crit re-sync)
--   * GameModeInn._cb_start_menu_closed           (Buffs — crit re-sync)
--   * VolumetricsFlowCallbacks.unregister_fog_volume (nil-guard)
--   * Unit.get_data                               (nil-guard)
--   * PlayerWhereaboutsExtension.update           (nil-guard, AI-takeover race)
--   * RoundStartedSystem._players_left_start_area (nil-guard, AI-takeover race)
--
-- Features bundled:
--   (B) Time & Pause — host time-scale + pause. Exposes mod.gt_pause_toggle /
--       gt_time_apply / gt_time_faster / gt_time_slower. Shares the pause flag
--       with the main on_game_state_changed dispatcher via mod._gt_pause_active.
--   (C) Ult Controls — gt_ult_reset + player/bot cooldown caps (CareerExtension
--       .update hook + mod._gt_clamp_cooldowns helper).
--   (D) Buffs & Stat Tweaks — infinite ammo/stamina, giga power, base crit
--       slider, movement speed, fall damage. Registers the `infinite_ammo`
--       per-frame consumer via mod._gt_register_update.
--   (F) Engine error nil-guards — four always-on defensive hooks.
--
-- DISPATCH WIRING (no behavior change after extraction):
--   * mod.gt_time_apply / gt_apply_crit_chance / gt_apply_move_speed /
--     gt_apply_fall_damage stay PUBLIC `mod.` fields — the main on_setting_changed
--     branches (time_scale_value / base_crit_chance / movement_speed /
--     gt_fall_damage_*) resolve them at call time, and the fall-damage
--     regression test in main reads mod.gt_apply_fall_damage.
--   * mod._gt_pause_active is the shared pause flag (was a forward-declared
--     file-local _pause_active); on_game_state_changed clears it on every state
--     transition, this module's toggle reads/writes it.
--   * The original merged "infinite_ammo_and_ai_pending" update consumer was
--     SPLIT: the infinite-ammo refresher half moved here (registered as
--     `infinite_ammo` via mod._gt_register_update), the AI-takeover deferred-
--     consumer half stays in main (registered as `ai_pending`). The two halves
--     share no state, so the split is behavior-neutral.
--   * mod.gt_apply_crit_chance / move_speed / fall_damage apply once at this
--     module's load (gt_apply_fall_damage was applied at load in the original;
--     kept identical).
--
-- Module dofile's AFTER the main chunk, so mod._gt_register_update and the
-- boot-loaded global classes are all resolvable at load time (table-form hooks
-- are nil-guarded exactly as in the original).
--
-- Extracted from general_tweaker_dev.lua (Phase 3 refactor, no behavior change).

-- ============================================================
-- Time & Pause (Group B — Janoti "Hacks" port)
-- ============================================================
-- Two related features sharing the same engine primitive:
-- `Managers.state.debug:set_time_scale(index)`. The index is into
-- `time_scale_list` in debug_manager.lua:18 — a 24-entry table of
-- multipliers. Index 13 = 1.0x (normal). Lower = slower, higher = faster.
-- Settings persist for the session; vanilla wipes them on level transition,
-- so on_game_state_changed re-applies the slider value on each StateIngame
-- entry.
--
-- Pause: host-only. Toggles between the configured "pause speed" index
-- (default 1 = slowest possible) and normal (13). VT2 has no true pause
-- primitive — set_time_scale(1) is the closest thing and still lets the UI
-- update. Don't confuse with the time slider: the two write to the same
-- engine setter, so if both are used simultaneously the last write wins.
-- We keep them as separate features matching Hacks's UX.

-- The pause flag is shared with the main on_game_state_changed dispatcher
-- (Issue #13: it clears the flag on every state transition). It lives on `mod`
-- (mod._gt_pause_active) so both the dispatcher write and the toggle read see
-- the same value. Initialize to false here at module load.
mod._gt_pause_active = false

mod.gt_pause_toggle = function()
    if not (Managers.player and Managers.player.is_server) then
        mod:echo("Only the host can pause the game.")
        return
    end
    local debug_mgr = Managers.state and Managers.state.debug
    if not (debug_mgr and debug_mgr.set_time_scale) then
        mod:echo("Time scale manager not available yet.")
        return
    end
    if mod._gt_pause_active then
        debug_mgr:set_time_scale(mod:get("time_scale_value") or 13)
        mod._gt_pause_active = false
        mod:echo("Game unpaused.")
    else
        debug_mgr:set_time_scale(mod:get("pause_value") or 1)
        mod._gt_pause_active = true
        mod:echo("Game paused.")
    end
end

mod.gt_time_apply = function()
    if mod._gt_pause_active then
        -- While paused, slider edits update the post-unpause target but don't
        -- override the active pause speed. Matches Hacks's behaviour.
        return
    end
    local debug_mgr = Managers.state and Managers.state.debug
    if debug_mgr and debug_mgr.set_time_scale then
        debug_mgr:set_time_scale(mod:get("time_scale_value") or 13)
    end
end

mod.gt_time_faster = function()
    local cur = mod:get("time_scale_value") or 13
    if cur >= 24 then
        mod:echo("Already at maximum time speed.")
        return
    end
    mod:set("time_scale_value", cur + 1)
    mod.gt_time_apply()
    mod:echo(string.format("Time scale: %d", cur + 1))
end

mod.gt_time_slower = function()
    local cur = mod:get("time_scale_value") or 13
    if cur <= 1 then
        mod:echo("Already at minimum time speed.")
        return
    end
    mod:set("time_scale_value", cur - 1)
    mod.gt_time_apply()
    mod:echo(string.format("Time scale: %d", cur - 1))
end

mod:command("pause",    "Toggle game pause (host-only time slowdown to the configured pause speed)", function() mod.gt_pause_toggle() end)
mod:command("time_faster", "Increase game time scale by one step", function() mod.gt_time_faster() end)
mod:command("time_slower", "Decrease game time scale by one step", function() mod.gt_time_slower() end)

-- ============================================================
-- Ult Controls (Group C — Janoti "Hacks" port)
-- ============================================================
-- Three independent features, all driven through CareerExtension:
--
--  1. `gt ult_reset` (+ hotkey) — one-shot, sets every active-ability cooldown
--     to 0 via :reduce_activated_ability_cooldown_percent(charge_index, 1).
--     ThePageMan's "No Ult Cooldown" primitive.
--
--  2. Player ult cooldown cap (toggle + slider 0-120s) — every
--     CareerExtension.update tick, if self.player is human-controlled, clamp
--     each ability's cooldowns[k] down to the configured max. Smooths the
--     "set ult to 5s for testing" workflow without burning a talent slot.
--
--  3. Bot ult cooldown cap — same idea but for AI-controlled units. Useful
--     to make bots ult more aggressively in solo-with-bots testing.
--
-- Both caps share a helper (mod._gt_clamp_cooldowns) that walks every ability
-- on the extension and trims each charge's cooldown if it exceeds the target.
-- Borrowed from Hacks 1:1 since the iteration pattern (decaying-charge index,
-- cooldown_paused unblock, set_activated_ability_cooldown_unpaused) is what
-- the engine expects and replicating it any other way would desync the ability
-- HUD overlay.

mod.gt_ult_reset = function()
    local local_player = Managers.player and Managers.player:local_player()
    local unit = local_player and local_player.player_unit
    if not (unit and Unit.alive(unit)) then
        mod:echo("No local player unit.")
        return
    end
    local career_ext = ScriptUnit.has_extension(unit, "career_system")
    if not career_ext then
        mod:echo("No career extension on local player.")
        return
    end
    for i = 1, career_ext._num_abilities or 1, 1 do
        career_ext:reduce_activated_ability_cooldown_percent(i, 1)
    end
    mod:echo("Ult reset.")
end

mod._gt_clamp_cooldowns = function(career_ext, max_seconds)
    for i = 1, career_ext._num_abilities or 1, 1 do
        local ability = career_ext._abilities[i]
        if ability and ability.cooldowns then
            local charge_idx = career_ext:_currently_decaying_cooldown(i)
            if charge_idx then
                for k = charge_idx, 1, -1 do
                    if ability.cooldowns[k] and ability.cooldowns[k] > max_seconds then
                        ability.cooldowns[k] = max_seconds
                    end
                end
            end
            local is_ready = career_ext:_cooldown_charge_ready(i)
            if not is_ready then
                ability.cooldown_paused = false
            end
            if is_ready then
                career_ext:set_activated_ability_cooldown_unpaused(i)
            end
        end
    end
end

-- #70: nil-guard boot-loaded class globals before table-form hooks (defensive
-- load-order consistency; these are always loaded so the guard never fails).
if CareerExtension and CareerExtension.update then
    mod:hook_safe(CareerExtension, "update", function(self, unit, input, dt, context, t)
        if mod:get("ult_player_cap_enabled") and self.player and self.player:is_player_controlled() then
            mod._gt_clamp_cooldowns(self, mod:get("ult_player_cap_value") or 0)
        end
        if mod:get("ult_bot_cap_enabled") and self.player and not self.player:is_player_controlled() then
            mod._gt_clamp_cooldowns(self, mod:get("ult_bot_cap_value") or 0)
        end
    end)
end

mod:command("ultreset", "Reset your ultimate (set cooldown to 0)", function() mod.gt_ult_reset() end)

-- ============================================================
-- Buffs & Stat Tweaks (Group D — Janoti "Hacks" port)
-- ============================================================
-- Five independent toggles/sliders:
--
--  1. `gt infinite_ammo`  — applies the vanilla `twitch_no_overcharge_no_ammo_reloads`
--     buff to the local player (and host-side to every player, since the buff
--     is server-controlled). Periodic re-apply every second keeps the buff
--     refreshed in case it gets stripped.
--  2. `gt infinite_stamina` — hooks GenericStatusExtension.add_fatigue_points
--     and short-circuits it so stamina-cost calls never deplete the bar.
--  3. `gt giga_power`     — multiplies BuffTemplates.power_level_unbalance
--     (Enhanced Power talent) by 1000x. Echoes that the talent must be
--     re-equipped for the buff to refresh.
--  4. Base crit chance slider (1–100%) — rewrites
--     CareerSettings[current_career].attributes.base_critical_strike_chance.
--     Auto-resets to the career's vanilla value when you switch career
--     (ProfileRequester.request_profile + GameModeInn._cb_start_menu_closed
--     hooks).
--  5. Movement speed slider (0–30 m/s) — rewrites PlayerUnitMovementSettings.move_speed
--     and walks the per-unit settings table (via the closed-upvalue trick
--     debug.getupvalue(PlayerUnitMovementSettings.unregister_unit, 1)) so
--     already-spawned units get the new speed too.
--
-- All five settings reset on game restart (we don't try to persist them past
-- session) — matches Hacks. The infinite-ammo periodic refresher rides on
-- gt's central per-frame update registry.

-- ---------- 5.1 Infinite Ammo & 0 Heat -----------------------

local _gt_infinite_ammo_active = false
local _gt_infinite_ammo_refresh_t = 0
local _gt_infinite_ammo_owned_ids = setmetatable({}, { __mode = "k" })

local function _gt_godmode_unlimited_ammo_active()
    return mod:get("godmode_enabled") == true
        and mod:get("gt_godmode_unlimited_ammo") == true
end

local function _gt_apply_infinite_ammo_buff(unit)
    if not (unit and Unit.alive(unit)) then return end
    local buff_ext = ScriptUnit.has_extension(unit, "buff_system")
    if not buff_ext then return end
    if buff_ext:has_buff_type("twitch_no_overcharge_no_ammo_reloads") then return end
    if Managers.player and Managers.player.is_server then
        local bs = Managers.state.entity:system("buff_system")
        bs:add_buff(unit, "twitch_no_overcharge_no_ammo_reloads", unit, false)
    else
        buff_ext:add_buff("twitch_no_overcharge_no_ammo_reloads")
    end
    local buff = buff_ext:get_non_stacking_buff("twitch_no_overcharge_no_ammo_reloads")
    if buff then _gt_infinite_ammo_owned_ids[unit] = buff.id end
end

local function _gt_remove_infinite_ammo_buff(unit)
    if not (unit and Unit.alive(unit)) then return end
    local owned_id = _gt_infinite_ammo_owned_ids[unit]
    _gt_infinite_ammo_owned_ids[unit] = nil
    if not owned_id then return end
    local buff_ext = ScriptUnit.has_extension(unit, "buff_system")
    if not buff_ext then return end
    if not buff_ext:has_buff_type("twitch_no_overcharge_no_ammo_reloads") then return end
    local buff = buff_ext:get_non_stacking_buff("twitch_no_overcharge_no_ammo_reloads")
    if buff and buff.id == owned_id then buff_ext:remove_buff(buff.id) end
end

-- Reconcile two independent owners of the same vanilla buff. The standalone
-- /infinite_ammo cheat retains its historical all-player host scope; #549 adds
-- only the local owner while BOTH its child toggle and Godmode are active.
-- Turning either source off must not strip the buff while the other still owns
-- it. Reload reserve consumption checks this exact buff on the owning machine
-- [src: scripts/unit_extensions/generic/generic_ammo_user_extension.lua:160-176].
local function _gt_reconcile_infinite_ammo()
    local lp = Managers.player and Managers.player:local_player()
    local local_unit = lp and lp.player_unit
    local local_should_have = _gt_infinite_ammo_active
        or _gt_godmode_unlimited_ammo_active()
    if local_unit then
        if local_should_have then
            _gt_apply_infinite_ammo_buff(local_unit)
        else
            _gt_remove_infinite_ammo_buff(local_unit)
        end
    end
    if Managers.player and Managers.player.is_server then
        for _, p in pairs(Managers.player:human_and_bot_players() or {}) do
            local unit = p.player_unit
            if unit and unit ~= local_unit then
                if _gt_infinite_ammo_active then
                    _gt_apply_infinite_ammo_buff(unit)
                else
                    _gt_remove_infinite_ammo_buff(unit)
                end
            end
        end
    end
end
mod._gt_reconcile_infinite_ammo = _gt_reconcile_infinite_ammo

mod.gt_infinite_ammo_toggle = function()
    _gt_infinite_ammo_active = not _gt_infinite_ammo_active
    _gt_reconcile_infinite_ammo()
    if _gt_infinite_ammo_active then
        mod:echo("Infinite ammo & heat: ON.")
    else
        mod:echo("Infinite ammo & heat: OFF.")
    end
end

mod:command("infinite_ammo", "Toggle infinite ammo and zero overheat for all players (host applies to clients too)", function()
    mod.gt_infinite_ammo_toggle()
end)

-- ---------- 5.2 Infinite Stamina -----------------------------

local _gt_stamina_active = false

mod.gt_infinite_stamina_toggle = function()
    _gt_stamina_active = not _gt_stamina_active
    mod:echo(_gt_stamina_active and "Infinite stamina: ON." or "Infinite stamina: OFF.")
end

-- Issue #529 godmode stamina immunity: fatigue types the PLAYER's own actions
-- spend. Godmode does NOT make these free (that is the separate /stamina cheat
-- above); every OTHER positive-cost type is enemy/hazard-sourced drain (blocked_*,
-- ogre_shove, sv_push, vomit_*, plague_ground, chaos_cleave, "complete", DLC buff
-- drains, ...) and is skipped while godmode is on. Closed self-action vocabulary:
-- PlayerUnitStatusSettings.fatigue_point_costs [src: scripts/settings/
-- player_unit_status_settings.lua:19-52] has exactly action_dodge/drag/push/
-- stun_push as self costs, plus the two values weapon actions pass via
-- new_action.fatigue_cost ("action_stun_push"/"proc") [src: scripts/
-- unit_extensions/weapons/actions/action_base.lua:106-117]. Negative-cost types
-- (headshot replenish, career_victor_captain) pass through via the amount<=0
-- check below so stamina REGAIN keeps working under godmode.
mod._GT_529_SELF_FATIGUE_TYPES = {
    action_dodge     = true,
    action_drag      = true,
    action_push      = true,
    action_stun_push = true,
    force_set        = true,
    proc             = true,
}
mod._GT_529_GODMODE_STAMINA_MARKER = "gt-529-godmode-stamina-gate"

-- Always-on wrapper. When the flag is off, the closure passes through to the
-- original; when on, it short-circuits so fatigue cost calls never deplete
-- the stamina bar. Avoids re-registering hooks (VMF errors on duplicates).
--
-- MERGED CONCERN (issue #529): the godmode stamina gate ALSO lives in this body
-- (one hook per (Class, method) — VMF drops a second registration silently).
-- Why this is the right choke point: every enemy-sourced stamina write funnels
-- through add_fatigue_points ON THE OWNING MACHINE — blocked_attack only calls
-- it when `not player.remote` [src: scripts/unit_extensions/generic/
-- generic_status_extension.lua:630,649] and add_fatigue_points itself hard-
-- rejects remote players [src: same file:781-785]. A client's drain arrives via
-- rpc_player_blocked_attack and is applied by ITS OWN machine [src: scripts/
-- entity_system/systems/status/status_system.lua:466-477], so the local godmode
-- flag is the correct authority as host AND as client. Block-break is inside
-- the skipped call (fatigue >= max -> set_block_broken [src: generic_status_
-- extension.lua:823-825]), so guard can no longer be broken either. Blocking
-- visuals/sounds stay normal: blocked_attack itself still runs (parry anim,
-- spark particles, rumble); only the fatigue write is skipped. Consumption-side
-- fix: no _max_ field, no pool inflation, nothing networked (fatigue simply
-- never rises, so set_fatigue_points sync RPCs are never generated).
if GenericStatusExtension and GenericStatusExtension.add_fatigue_points then
    mod:hook(GenericStatusExtension, "add_fatigue_points", function(func, self, fatigue_type, attacking_unit, ...)
        if _gt_stamina_active then return end
        -- #529: with godmode on for this unit's owner, drop enemy/hazard-sourced
        -- fatigue. Own-action costs (push/dodge) and replenishes still apply.
        if not mod._GT_529_SELF_FATIGUE_TYPES[fatigue_type]
           and mod._gt_godmode_active and mod._gt_godmode_active(self.unit) then
            local costs = PlayerUnitStatusSettings and PlayerUnitStatusSettings.fatigue_point_costs
            local amount = costs and costs[fatigue_type]
            if amount == nil or amount > 0 then
                return
            end
        end
        return func(self, fatigue_type, attacking_unit, ...)
    end)
end

mod:command("stamina", "Toggle infinite stamina (zero fatigue cost on blocks/dodges/pushes)", function()
    mod.gt_infinite_stamina_toggle()
end)

-- ---------- 5.3 Giga Power -----------------------------------

local _gt_giga_power_active = false
local _gt_giga_power_original = nil

mod.gt_giga_power_toggle = function()
    if not (BuffTemplates and BuffTemplates.power_level_unbalance and BuffTemplates.power_level_unbalance.buffs[1]) then
        mod:echo("BuffTemplates.power_level_unbalance not available.")
        return
    end
    local buff_row = BuffTemplates.power_level_unbalance.buffs[1]
    if _gt_giga_power_active then
        if _gt_giga_power_original ~= nil then
            buff_row.multiplier = _gt_giga_power_original
        end
        _gt_giga_power_active = false
        mod:echo("Giga power: OFF (re-equip the Enhanced Power talent).")
    else
        _gt_giga_power_original = buff_row.multiplier
        buff_row.multiplier = 1000
        _gt_giga_power_active = true
        mod:echo("Giga power: ON (re-equip the Enhanced Power talent).")
    end
end

mod:command("gigapower", "Multiply the Enhanced Power talent buff by 1000x (re-equip the talent to refresh)", function()
    mod.gt_giga_power_toggle()
end)

-- ---------- 5.4 Base Crit Chance Slider ----------------------

local _gt_current_career_for_crit = nil

local function _gt_get_local_career_name()
    local lp = Managers.player and Managers.player:local_player()
    if not lp then return nil end
    local profile_idx = lp:profile_index()
    local career_idx  = lp:career_index()
    if not (profile_idx and career_idx) then return nil end
    local profile = SPProfiles and SPProfiles[profile_idx]
    if not (profile and profile.careers and profile.careers[career_idx]) then return nil end
    return profile.careers[career_idx].name
end

mod.gt_apply_crit_chance = function()
    local name = _gt_get_local_career_name()
    if not (name and CareerSettings[name] and CareerSettings[name].attributes) then return end
    local pct = mod:get("base_crit_chance") or 5
    CareerSettings[name].attributes.base_critical_strike_chance = pct / 100
end

-- On career switch, snap the slider to that career's vanilla value so toggling
-- back and forth doesn't carry over an unintended override.
mod.gt_sync_crit_default_for_career = function()
    local name = _gt_get_local_career_name()
    if not (name and CareerSettings[name] and CareerSettings[name].attributes) then return end
    if name == _gt_current_career_for_crit then return end
    _gt_current_career_for_crit = name
    local pct = (CareerSettings[name].attributes.base_critical_strike_chance or 0.05) * 100
    mod:set("base_crit_chance", pct)
end

if ProfileRequester and ProfileRequester.request_profile then mod:hook_safe(ProfileRequester, "request_profile", function() mod.gt_sync_crit_default_for_career() end) end
if GameModeInn and GameModeInn._cb_start_menu_closed then mod:hook_safe(GameModeInn,      "_cb_start_menu_closed", function() mod.gt_sync_crit_default_for_career() end) end

-- ---------- 5.5 Movement Speed Slider -----------------------

mod.gt_apply_move_speed = function()
    local v = mod:get("movement_speed")
    if not (v and PlayerUnitMovementSettings) then return end
    PlayerUnitMovementSettings.move_speed = v
    -- The per-unit settings table is closed over inside unregister_unit. Reach
    -- in via debug.getupvalue so already-spawned units pick up the new speed.
    local _, units_settings = debug.getupvalue(PlayerUnitMovementSettings.unregister_unit, 1)
    if type(units_settings) == "table" then
        for _, settings in pairs(units_settings) do
            settings.move_speed = v
        end
    end
end

-- ---------- 5.6 Fall Damage Multiplier ----------------------
-- Fall damage is applied HOST-SIDE in HealthSystem.rpc_take_falling_damage:
--   fall_damage = clamp(delta * FALL_DAMAGE_MULTIPLIER,
--                       max_health * MIN_FALL_DAMAGE_PERCENTAGE,
--                       max_health * MAX_FALL_DAMAGE_PERCENTAGE)
-- (health_system.lua:657-664, reading PlayerUnitMovementSettings.fall.heights;
-- vanilla = 14 / 0 / 1). Scaling all three fields by m scales the clamped
-- result by m: m=0 -> no damage, m=1 -> vanilla, m=5 -> up to 5x (tall falls
-- exceed max health = lethal). We deliberately do NOT touch MIN_FALL_DAMAGE_
-- HEIGHT (the client-side trigger threshold in GenericStatusExtension.update_
-- falling) so the SAME falls still register -- only the dealt amount changes.
-- Like move_speed, the engine DEEP-clones PlayerUnitMovementSettings per unit
-- at spawn (register_unit -> table.clone, recursive), so each unit owns its own
-- fall.heights; we rewrite the base AND every live per-unit snapshot (reached
-- via the units table closed over inside unregister_unit). Originals captured
-- once so re-applies recompute from vanilla (no compounding) and disabling (or
-- mult 1.0) restores vanilla. Host-authoritative: the host's value governs the
-- whole lobby's fall damage.
local _gt_fd_orig
mod.gt_apply_fall_damage = function()
    if not (PlayerUnitMovementSettings and PlayerUnitMovementSettings.fall) then return end
    local base = PlayerUnitMovementSettings.fall.heights
    if not base then return end
    if not _gt_fd_orig then
        _gt_fd_orig = {
            FALL_DAMAGE_MULTIPLIER     = base.FALL_DAMAGE_MULTIPLIER,
            MIN_FALL_DAMAGE_PERCENTAGE = base.MIN_FALL_DAMAGE_PERCENTAGE,
            MAX_FALL_DAMAGE_PERCENTAGE = base.MAX_FALL_DAMAGE_PERCENTAGE,
        }
    end
    local m = (mod:get("gt_fall_damage_enabled") and (mod:get("gt_fall_damage_mult") or 1)) or 1
    local function _set(h)
        if not h then return end
        h.FALL_DAMAGE_MULTIPLIER     = _gt_fd_orig.FALL_DAMAGE_MULTIPLIER * m
        h.MIN_FALL_DAMAGE_PERCENTAGE = _gt_fd_orig.MIN_FALL_DAMAGE_PERCENTAGE * m
        h.MAX_FALL_DAMAGE_PERCENTAGE = _gt_fd_orig.MAX_FALL_DAMAGE_PERCENTAGE * m
    end
    _set(base)
    -- Per-unit snapshots (already-spawned players) -- same closed-upvalue trick
    -- as gt_apply_move_speed above. pcall-guarded: debug.getupvalue can fail if
    -- the engine ever strips debug info from the settings module.
    local ok, units_settings = pcall(debug.getupvalue, PlayerUnitMovementSettings.unregister_unit, 1)
    if ok and type(units_settings) == "table" then
        for _, settings in pairs(units_settings) do
            _set(settings.fall and settings.fall.heights)
        end
    end
end

mod.gt_apply_fall_damage()

-- 1Hz infinite-ammo refresher. The original consumer ALSO serviced the AI-
-- takeover deferred host-toggle/client-send pending flags; that half stays in
-- the main chunk (registered there as `ai_pending`). The two halves share no
-- state, so splitting the consumer is behavior-neutral.
mod._gt_register_update("infinite_ammo", function(dt)
    if _gt_infinite_ammo_active or _gt_godmode_unlimited_ammo_active() then
        _gt_infinite_ammo_refresh_t = _gt_infinite_ammo_refresh_t + (dt or 0)
        if _gt_infinite_ammo_refresh_t >= 1.0 then
            _gt_infinite_ammo_refresh_t = 0
            _gt_reconcile_infinite_ammo()
        end
    end
end)

-- ============================================================
-- Engine error nil-guards (Group F — Janoti "Hacks" port)
-- ============================================================
-- Two well-known places where vanilla code occasionally dereferences a unit
-- that's mid-cleanup, producing red [Engine Error] spam (and sometimes a
-- silent fatal during long sessions). Hacks ships these guards too — they're
-- cheap and we'd rather suppress the error than have it leak into our crash
-- triage. Both are pure no-op-if-unit-dead pre-guards; the original function
-- is called normally when the unit is alive.

if VolumetricsFlowCallbacks and VolumetricsFlowCallbacks.unregister_fog_volume then
    mod:hook(VolumetricsFlowCallbacks, "unregister_fog_volume", function(func, params, ...)
        if not (params and params.unit and Unit.alive(params.unit)) then return end
        return func(params, ...)
    end)
end

mod:hook(Unit, "get_data", function(func, unit, ...)
    if not unit then return end
    return func(unit, ...)
end)

-- AI-takeover despawn race (GUID 955c4549-7b10-4ecb-a0ce-06c1d37f9bbc, v0.2.114-dev):
-- _ai_swap_human_to_bot calls player:despawn(), which pulls the unit out of
-- POSITION_LOOKUP. PlayerWhereaboutsExtension.update can still tick once before
-- its teardown completes; vanilla does `local pos = POSITION_LOOKUP[unit]`
-- (player_whereabouts_extension.lua:67) then feeds pos to _get_closest_positions
-- -> GwNavQueries.triangle_from_position (decompile :214, runtime :200), whose
-- arg #2 is userdata-required -> hard engine crash on nil ("bad argument #2 to
-- 'triangle_from_position' (userdata expected, got nil)"). A positionless unit
-- has nothing to track this frame, so skip the whole update. One class covers
-- local + husk + bot player units (unit_extension_templates.lua registers
-- PlayerWhereaboutsExtension on all of them). `...` preserves input/dt/context/t.
mod:hook("PlayerWhereaboutsExtension", "update", function(func, self, unit, ...)
    if not (unit and Unit.alive(unit) and POSITION_LOOKUP[unit]) then return end
    return func(self, unit, ...)
end)

-- Same AI-takeover despawn race, SECOND site (GUID 6fac3e46-84ce-458d-b70f-fb87bf3ad940,
-- v0.2.115-dev): RoundStartedSystem._players_left_start_area iterates self._units and
-- reads `pos = POSITION_LOOKUP[unit]` (round_started_system.lua:117) then
-- `Level.is_point_inside_volume(level, volume_name, pos)` (:119, runtime :111) with no
-- nil-guard. A unit despawned mid-frame (human->bot swap, or a disconnect during the
-- round-start window) is gone from POSITION_LOOKUP but lingers in self._units for a tick
-- -> pos nil -> arg #3 userdata-required -> engine crash. Can't pre-check a single pos
-- (the crash is per-unit inside the loop), so pre-guard at the function: if ANY tracked
-- unit lacks a position this frame, bail (return false = "round not started yet"). The
-- despawned unit drops out of self._units within a tick and the next call runs vanilla
-- normally -- no premature round start, sub-second delay at worst.
mod:hook("RoundStartedSystem", "_players_left_start_area", function(func, self)
    for unit in pairs(self._units or {}) do
        if not POSITION_LOOKUP[unit] then return false end
    end
    return func(self)
end)
