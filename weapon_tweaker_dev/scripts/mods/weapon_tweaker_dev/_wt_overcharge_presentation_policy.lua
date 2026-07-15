-- Pure policy for issue #388. Keep engine/VMF globals out so identity,
-- extension-profile projection, and HUD colors run under the Lua 5.1 harness.
local P = {}

P.DEEPWOOD_KEY = "we_life_staff"

function P.is_deepwood_key(item_key)
    return item_key == P.DEEPWOOD_KEY
end

-- PlayerUnitOverchargeExtension.init projects career-keyed OverchargeData into
-- scalar fields once at player creation. Reproduce that projection for the
-- Deepwood profile only; runtime owns capture/restore of the previous values.
function P.extension_profile(data)
    if type(data) ~= "table" then return nil end
    return {
        overcharge_threshold = data.overcharge_threshold or 0,
        overcharge_value_decrease_rate = data.overcharge_value_decrease_rate or 0,
        time_until_overcharge_decreases = data.time_until_overcharge_decreases or 0,
        hit_overcharge_threshold_sound = data.hit_overcharge_threshold_sound or "ui_special_attack_ready",
        screen_space_particle = data.onscreen_particles_id or "fx/screenspace_overheat_indicator",
        screen_space_particle_critical = data.critical_onscreen_particles_id
            or (not data.no_critical_onscreen_particles and "fx/screenspace_overheat_critical" or nil),
        explosion_template = data.explosion_template or "overcharge_explosion",
        no_forced_movement = data.no_forced_movement,
        no_explosion = data.no_explosion,
        explode_vfx_name = data.explode_vfx_name,
        overcharge_explosion_time = data.overcharge_explosion_time,
        percent_health_lost = data.percent_health_lost,
        lockout_overcharge_decay_rate = data.lockout_overcharge_decay_rate,
        state_sounds = {
            [2] = data.overcharge_warning_low_sound_event,
            [3] = data.overcharge_warning_med_sound_event,
            [4] = data.overcharge_warning_high_sound_event,
            [5] = data.overcharge_warning_critical_sound_event,
        },
    }
end

function P.hud_style(ui_data, fraction, min_threshold, max_threshold)
    if type(ui_data) ~= "table" or type(fraction) ~= "number" then return nil end
    local color, alpha
    if fraction <= min_threshold then
        color, alpha = ui_data.color_normal, 0.6
    elseif fraction <= max_threshold then
        color, alpha = ui_data.color_medium, 0.8
    else
        color, alpha = ui_data.color_high, 1
    end
    if type(color) ~= "table" then return nil end
    return { material = ui_data.material, color = color, alpha = alpha }
end

return P
