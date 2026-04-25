local mod = get_mod("gt")

local MOD_VERSION = "0.1.4-dev"

mod:echo("General Tweaker v" .. MOD_VERSION .. " loaded")

-- ============================================================
-- Third-Person Camera
-- ============================================================

local _tp_enabled = false

local function _get_local_player()
    local pm = Managers.player
    if not pm then return nil end
    local ok, player = pcall(pm.local_player, pm)
    if not ok or not player then return nil end
    return player
end

local function _set_tp_visibility(punit, enabled)
    local fp_ext = ScriptUnit.has_extension(punit, "first_person_system")
    if fp_ext and type(fp_ext.set_first_person_mode) == "function" then
        pcall(fp_ext.set_first_person_mode, fp_ext, not enabled)
    end
end

-- Block the game from forcing first-person mode back on
mod:hook("PlayerUnitFirstPerson", "set_first_person_mode", function(func, self, active, ...)
    if _tp_enabled and active then return end
    return func(self, active, ...)
end)

-- Intercept camera state changes to keep TP camera locked in
mod:hook("CharacterStateHelper", "change_camera_state", function(func, player, state, params)
    if _tp_enabled and state == "follow" then
        return func(player, "follow_third_person_over_shoulder", params)
    end
    return func(player, state, params)
end)

-- Per-frame: re-apply model visibility if something bypasses the hook
mod:hook_safe("StateInGameRunning", "update", function(self, dt)
    if not _tp_enabled then return end

    local player = _get_local_player()
    if not player or not player.player_unit then return end

    local fp_ext = ScriptUnit.has_extension(player.player_unit, "first_person_system")
    if fp_ext and type(fp_ext.first_person_mode_active) == "function" then
        local ok, is_fp = pcall(fp_ext.first_person_mode_active, fp_ext)
        if ok and is_fp then
            pcall(fp_ext.set_first_person_mode, fp_ext, false)
        end
    end
end)

mod:command("tp", "Toggle third-person camera", function()
    _tp_enabled = not _tp_enabled

    local player = _get_local_player()
    if not player or not player.player_unit then
        mod:echo("No player unit — must be in a level.")
        _tp_enabled = false
        return
    end

    _set_tp_visibility(player.player_unit, _tp_enabled)

    -- Reset camera state when turning off
    if not _tp_enabled then
        pcall(CharacterStateHelper.change_camera_state, player, "follow")
    end

    mod:echo("Third-person: " .. (_tp_enabled and "ON" or "OFF"))
end)
