-- Issue #388: cross-career Deepwood Staff overcharge presentation parity.
--
-- Vanilla binds overcharge behavior/presentation to CAREER at player creation:
-- BulldozerPlayer reads OverchargeData[career] and PlayerUnitOverchargeExtension.init
-- copies its warning sounds, screen particles, decay, and explosion policy into the
-- owner extension. OverchargeBarUI independently reads that same career row each draw.
-- Kruber + Deepwood therefore receives generic defaults despite wielding the exact staff.
--
-- This module projects the native we_thornsister profile onto the LOCAL OWNER extension
-- while Deepwood occupies slot_ranged, restoring every captured scalar when it leaves.
-- Owner authority already replicates overcharge value/threshold; no RPC or network field
-- is added. A deferred HUD hook applies the same native colors for the local or spectated
-- player. PlayerHuskOverchargeExtension is value-only and needs no mutation.

local mod = get_mod("wt_dev")
local Policy = mod:dofile("scripts/mods/weapon_tweaker_dev/_wt_overcharge_presentation_policy")

local M = { Policy = Policy }
local _active_unit, _active_ext, _baseline
local _hud_hook_installed = false

local PROFILE_FIELDS = {
    "overcharge_threshold", "overcharge_value_decrease_rate",
    "time_until_overcharge_decreases", "hit_overcharge_threshold_sound",
    "screen_space_particle", "screen_space_particle_critical", "explosion_template",
    "no_forced_movement", "no_explosion", "explode_vfx_name",
    "overcharge_explosion_time", "percent_health_lost", "lockout_overcharge_decay_rate",
}

local function _slot_item_key(inventory, slot_name)
    if not inventory or type(inventory.get_slot_data) ~= "function" then return nil end
    local ok, slot_data = pcall(inventory.get_slot_data, inventory, slot_name)
    local item = ok and slot_data and slot_data.item_data
    if type(item) ~= "table" then return nil end
    return item.key or item.name or (item.data and (item.data.key or item.data.name))
end

local function _deepwood_equipped(player_unit)
    if not player_unit or not Unit.alive(player_unit) then return false end
    local inventory = ScriptUnit.has_extension(player_unit, "inventory_system")
    return Policy.is_deepwood_key(_slot_item_key(inventory, "slot_ranged"))
end
M.deepwood_equipped = _deepwood_equipped

local function _capture(ext)
    local out = { fields = {}, state_sounds = {} }
    for _, field in ipairs(PROFILE_FIELDS) do
        out.fields[field] = { value = ext[field] }
    end
    local states = ext._overcharge_states
    if type(states) == "table" then
        for index = 2, 5 do
            local state = states[index]
            out.state_sounds[index] = { value = type(state) == "table" and state.sound_event or nil }
        end
    end
    return out
end

local function _clear_particles(ext)
    if type(ext._destroy_all_screen_space_particles) == "function" then
        pcall(ext._destroy_all_screen_space_particles, ext)
    end
end

local function _live_active_ext()
    local unit, expected = _active_unit, _active_ext
    if not unit or not expected or not Unit or type(Unit.alive) ~= "function" then return nil end
    local ok_alive, alive = pcall(Unit.alive, unit)
    if not ok_alive or not alive then return nil end
    local ok_ext, current = pcall(ScriptUnit.has_extension, unit, "overcharge_system")
    return ok_ext and current == expected and current or nil
end

local function _abandon()
    _active_unit, _active_ext, _baseline = nil, nil, nil
end

local function _apply_profile(ext, profile)
    _clear_particles(ext)
    for _, field in ipairs(PROFILE_FIELDS) do ext[field] = profile[field] end
    local states = ext._overcharge_states
    if type(states) == "table" then
        for index = 2, 5 do
            if type(states[index]) == "table" then
                states[index].sound_event = profile.state_sounds[index]
            end
        end
    end
end

function M.restore()
    local ext, baseline = _live_active_ext(), _baseline
    _abandon()
    if not ext or not baseline then return end
    _clear_particles(ext)
    for _, field in ipairs(PROFILE_FIELDS) do ext[field] = baseline.fields[field].value end
    local states = ext._overcharge_states
    if type(states) == "table" then
        for index = 2, 5 do
            if type(states[index]) == "table" then
                states[index].sound_event = baseline.state_sounds[index].value
            end
        end
    end
    printf("[wt:388] Deepwood overcharge profile restored")
end

local function _hud_apply(self, player, fraction, min_threshold, max_threshold)
    local player_unit = player and player.player_unit
    if not _deepwood_equipped(player_unit) then return end
    local native = rawget(_G, "OverchargeData")
    local ui_data = native and native.we_thornsister and native.we_thornsister.overcharge_ui
    local planned = Policy.hud_style(ui_data, fraction, min_threshold, max_threshold)
    local widget = self and self.charge_bar
    local style, content = widget and widget.style, widget and widget.content
    if not planned or not style or not content or not style.bar_1 or not style.icon then return end
    content.bar_1 = planned.material
    local bar, icon, color = style.bar_1.color, style.icon.color, planned.color
    if type(bar) ~= "table" or type(icon) ~= "table" then return end
    bar[1], bar[2], bar[3], bar[4] = color[1] * planned.alpha, color[2], color[3], color[4]
    icon[2], icon[3], icon[4] = color[2], color[3], color[4]
end

local function _install_hud_hook()
    if _hud_hook_installed then return end
    local cls = rawget(_G, "OverchargeBarUI")
    if not cls or type(cls.set_charge_bar_fraction) ~= "function" then return end
    _hud_hook_installed = true
    -- hook-test: issue388_deepwood_overcharge_profile
    mod:hook_safe(cls, "set_charge_bar_fraction", function(self, player, fraction, min_threshold, max_threshold)
        _hud_apply(self, player, fraction, min_threshold, max_threshold)
    end)
    printf("[wt:388] Deepwood overcharge HUD hook installed")
end

function M.tick()
    _install_hud_hook()
    local players = Managers and Managers.player
    local ok_player, player = false, nil
    if players and players.local_player then
        ok_player, player = pcall(players.local_player, players)
    end
    if not ok_player or not player or player.bot_player then
        -- The extension owns its own teardown. Do not touch a retained C-side
        -- extension after its player/world has disappeared.
        if _active_ext then _abandon() end
        return
    end
    local player_unit = player.player_unit
    local career = type(player.career_name) == "function" and player:career_name() or nil
    local eligible = career ~= "we_thornsister" and _deepwood_equipped(player_unit)
    local ext = eligible and ScriptUnit.has_extension(player_unit, "overcharge_system") or nil
    local data = rawget(_G, "OverchargeData")
    local profile = data and Policy.extension_profile(data.we_thornsister)

    if not ext or not profile then
        if _active_ext then M.restore() end
        return
    end
    if _active_ext == ext then return end
    if _active_ext then M.restore() end
    _active_unit, _active_ext, _baseline = player_unit, ext, _capture(ext)
    _apply_profile(ext, profile)
    printf("[wt:388] Deepwood overcharge profile applied career=%s transport=owner-authoritative",
        tostring(career))
end

M.rt_checks = {
    { name = "issue388_deepwood_overcharge_profile", fn = function()
        local data = rawget(_G, "OverchargeData")
        local profile = data and Policy.extension_profile(data.we_thornsister)
        if not profile then return "we_thornsister OverchargeData unavailable" end
        if profile.screen_space_particle ~= "fx/thornsister_overcharge" then return "thorn screen FX missing" end
        if profile.state_sounds[3] ~= "weapon_life_staff_overcharge_warning_medium" then return "medium warning sound missing" end
        if profile.no_explosion ~= true or profile.overcharge_value_decrease_rate ~= 1 then return "native behavior profile drift" end
        if not _hud_hook_installed and rawget(_G, "OverchargeBarUI") then return "HUD class loaded but hook not installed" end
    end },
}

return M
