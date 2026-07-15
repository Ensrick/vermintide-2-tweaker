local mod = get_mod("gut")

-- ============================================================================
-- Parry Indicator (absorbed into gut, with one behavioural change)
-- ============================================================================
-- Ported from the "Parry Indicator" mod (Workshop 1459917022). It recolours the
-- HUD block/stamina shields (FatigueUI) during the TIMED-BLOCK WINDOW -- the
-- first 0.5s after raising block, while actively blocking and not mid push /
-- attack / revive / pull-up / assisted-respawn. That window is when a "timed
-- block" lands: with the Parry weapon trait it costs no stamina; without it you
-- still get the base timed-block fatigue reduction.
--
-- CHANGE FROM THE ORIGINAL (user request 2026-06-18): the original only lit the
-- indicator when the weapon carried the Parry trait (it tracked the
-- `timed_block_cost` stat buff via BuffExtension hooks and gated on it). gut
-- DROPS that gate so the timing cue shows for EVERY weapon. The BuffExtension
-- has_parry tracking is therefore omitted entirely.
--
-- Verified VT2 internals:
--   * FatigueUI.update_shields(self, status_extension, dt) + self.shields[i].style.color
--     (scripts/ui/views/fatigue_ui.lua)
--   * GenericStatusExtension.raise_block_time (set on block-raise) + .blocking
--     (scripts/unit_extensions/generic/generic_status_extension.lua); registered
--     as the "status_system" extension.

local SETTING  = "gut_parry_indicator"
local WINDOW   = 0.5

-- Action/interaction state: exclude the cue while pushing / attacking / reviving
-- / pulling up / assisting respawn (mirrors the original).
local pushing, attacking, reviving, pulling_up, assisting_respawn = false, false, false, false, false
local block_time         = -math.huge
local block_time_push    = -math.huge
local block_time_revive  = -math.huge
local block_time_pullup  = -math.huge
local block_time_respawn = -math.huge
local stop_action_time   = -math.huge
local _pi_logged, _pi_was_active = false, false  -- debug one-shots

local function _enabled()
    return mod:get(SETTING)
end

local function _local_unit()
    local p = Managers.player and Managers.player:local_player()
    return p and p.player_unit
end

local function _is_local(unit)
    return unit ~= nil and unit == _local_unit()
end

-- The timed-block window test == the original check_parry MINUS the has_parry gate.
local function _in_window(status_ext)
    if pushing or attacking or reviving or pulling_up or assisting_respawn then
        return false
    end
    if not (status_ext and status_ext.raise_block_time and status_ext.blocking) then
        return false
    end
    block_time = status_ext.raise_block_time
    if block_time == stop_action_time then
        return false
    end
    local t = Managers.time:time("game")
    return (t - status_ext.raise_block_time) <= WINDOW
end

-- ---------------------------------------------------------------------------
-- The indicator: recolour the block shields while in the timed-block window.
-- ---------------------------------------------------------------------------
mod:hook(FatigueUI, "update_shields", function(func, self, status_extension, dt)
    local result = func(self, status_extension, dt)  -- let the game set offsets/state/alpha first
    if _enabled() and type(self.shields) == "table" then
        local unit = _local_unit()
        local status_ext = unit and ScriptUnit.has_extension(unit, "status_system")
        local active = (status_ext and _in_window(status_ext)) or false
        local r, g, b
        if active then
            r = mod:get("gut_parry_r") or 0
            g = mod:get("gut_parry_g") or 255
            b = mod:get("gut_parry_b") or 120
        else
            r, g, b = 255, 255, 255
        end
        -- Mutate the existing RGB (indices 2-4) and leave alpha (1) to the game's
        -- fade animation; replacing the whole color table would break the fade.
        local n = 0
        for _, shield in pairs(self.shields) do
            local col = shield.style and shield.style.color
            if col then col[2], col[3], col[4] = r, g, b; n = n + 1 end
        end
        if not _pi_logged then
            _pi_logged = true
            mod:debug("[gut:parry] update_shields hook live: %d shields, active=%s", n, tostring(active))
        end
        if active and not _pi_was_active then
            mod:debug("[gut:parry] timed-block window ENTER -> %d shields -> {%d,%d,%d}", n, r, g, b)
        end
        _pi_was_active = active
    end
    return result
end)

-- ---------------------------------------------------------------------------
-- State tracking (push / attack / revive / pull-up / assisted-respawn).
-- Table-form hooks guarded for nil; gated to the local player. Ported verbatim
-- from the original (minus the BuffExtension has_parry hooks).
-- ---------------------------------------------------------------------------
if ActionPushStagger then
    mod:hook_safe(ActionPushStagger, "client_owner_start_action", function(self, new_action, t)
        if _is_local(self.owner_unit) then
            block_time_push = block_time
            if (t - block_time) > WINDOW then pushing = true end
        end
    end)
    mod:hook_safe(ActionPushStagger, "client_owner_post_update", function(self)
        if _is_local(self.owner_unit) then
            if (Managers.time:time("game") - block_time_push) > WINDOW then pushing = true end
        end
    end)
    mod:hook_safe(ActionPushStagger, "finish", function(self)
        if _is_local(self.owner_unit) then pushing = false end
    end)
end

if ActionSweep then
    mod:hook_safe(ActionSweep, "client_owner_start_action", function(self)
        if _is_local(self.owner_unit) then attacking = true end
    end)
    mod:hook_safe(ActionSweep, "finish", function(self)
        if _is_local(self.owner_unit) then attacking = false end
    end)
end

-- Interaction client tables: revive / pull_up / assisted_respawn. Each fires
-- start/update/stop with (world, interactor_unit, interactable_unit, ...).
local function _hook_interaction(key, get_flag, set_flag, get_window_var, set_window_var)
    local def = InteractionDefinitions and InteractionDefinitions[key] and InteractionDefinitions[key].client
    if not def then return end
    mod:hook_safe(def, "start", function(world, interactor_unit, interactable_unit, data, config, t)
        if _is_local(interactor_unit) then
            set_window_var(block_time)
            if (t - block_time) > WINDOW then set_flag(true) end
        end
    end)
    mod:hook_safe(def, "update", function(world, interactor_unit)
        if _is_local(interactor_unit) then
            if (Managers.time:time("game") - get_window_var()) > WINDOW then set_flag(true) end
        end
    end)
    mod:hook_safe(def, "stop", function(world, interactor_unit, interactable_unit, data, config, t)
        if _is_local(interactor_unit) then
            set_flag(false)
            stop_action_time = t
        end
    end)
end

_hook_interaction("revive",
    function() return reviving end, function(v) reviving = v end,
    function() return block_time_revive end, function(v) block_time_revive = v end)
_hook_interaction("pull_up",
    function() return pulling_up end, function(v) pulling_up = v end,
    function() return block_time_pullup end, function(v) block_time_pullup = v end)
_hook_interaction("assisted_respawn",
    function() return assisting_respawn end, function(v) assisting_respawn = v end,
    function() return block_time_respawn end, function(v) block_time_respawn = v end)

mod:info("[gut] Parry Indicator installed (timed-block shield cue; all weapons; toggle: %s)", tostring(_enabled()))

return {}
