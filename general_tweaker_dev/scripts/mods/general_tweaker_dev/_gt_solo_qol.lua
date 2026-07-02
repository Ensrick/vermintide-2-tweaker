local mod = get_mod("gt_dev")

-- ============================================================================
-- Solo & QoL  (ported from "True Solo QoL Tweaks", workshop 1384087820)
-- ============================================================================
-- A from-scratch, error-free reimplementation of the useful TrueSoloQoL
-- features as individual gt toggles (all default OFF). Reasons for porting:
--   * the original crashes (caught by its own pcall, but logs noise every load)
--     when iterating CareerSettings -- it indexes career.activated_ability
--     .ability_class with no nil-check, and VT2's Versus entries vs_undecided /
--     spectator have no activated_ability. The ult-VO port below fixes that with
--     a proper nil-guard.
--   * drops the Penlight (pl) dependency -- uses plain string functions.
--   * lets the user run gt instead of the stale 2021 third-party mod.
--
-- NOT ported: AUTO_KILL_BOTS -- gt already has "Disable Bots (Solo)"
-- (gt_no_bots), which does the same via script_data.ai_bots_disabled.
--
-- Every hook gates on its own toggle and no-ops when off; the only one merged
-- into an existing gt hook is the assassin/packmaster spawn detector (gt already
-- hooks ConflictDirector.spawn_queued_unit), exposed as mod._gt_solo_on_spawn_queued
-- and called from that hook in general_tweaker_dev.lua (VMF drops a 2nd hook on
-- the same Class.method, so it MUST be merged, not re-hooked).
-- ============================================================================

local Managers = Managers
local ScriptUnit = ScriptUnit

-- ----------------------------------------------------------------------------
-- Auto-restart on team wipe (instead of returning to the keep)
-- ----------------------------------------------------------------------------
-- On a "lost" end-condition, return "reload" so the mission restarts in place.
-- `/inn` lets you deliberately bail to the keep while this is on.
--
-- Hooked on ALL THREE mission game modes (2026-07-01): Adventure, Chaos Wastes
-- (Deus), and Weaves. Before this it only hooked GameModeAdventure, so a wipe in
-- Chaos Wastes / Weaves ignored the toggle entirely (a user hit exactly this in a
-- Deus run). "reload" is a valid end reason for every mode -- adventure_mechanism.lua:427
-- and deus_mechanism.lua:539/545 both route it to level_transition_handler:reload_level().
-- Each Class.method pair is distinct, so there's no VMF duplicate-hook collision
-- (same pattern _gt_bots_keep uses for its _handle_bots hooks). We also capture the
-- vanilla THIRD return (reason_data) and pass it through so a non-restart end isn't
-- silently stripped (game_mode_manager.lua:800 reads all three).
local function _gt_auto_restart_end_conditions(func, self, round_started, dt, t, ...)
    if not mod:get("gt_solo_auto_restart_on_wipe") then
        mod._gt_solo_do_insta_fail = false
        mod._gt_solo_skip_restart = false
        return func(self, round_started, dt, t, ...)
    end

    if self.lost_condition_timer and mod._gt_solo_do_insta_fail then
        mod._gt_solo_do_insta_fail = false
        self.lost_condition_timer = t - 1
    end

    local ended, reason, reason_data = func(self, round_started, dt, t, ...)

    if ended and mod._gt_solo_skip_restart then
        mod._gt_solo_skip_restart = false
        return ended, reason, reason_data
    end

    if ended and reason == "lost" then
        return ended, "reload"   -- vanilla "reload" cases carry no reason_data
    end

    return ended, reason, reason_data
end
mod:hook("GameModeAdventure", "evaluate_end_conditions", _gt_auto_restart_end_conditions)
mod:hook("GameModeDeus",      "evaluate_end_conditions", _gt_auto_restart_end_conditions)
mod:hook("GameModeWeave",     "evaluate_end_conditions", _gt_auto_restart_end_conditions)

local function _fail_to_inn()
    mod:pcall(function()
        if rawget(_G, "DamageUtils") and DamageUtils.is_in_inn then
            mod:echo("Already in the keep.")
            return
        end
        mod._gt_solo_do_insta_fail = true
        mod._gt_solo_skip_restart = true
        Managers.state.game_mode:fail_level()
    end)
end
mod:command("inn", "Fail the mission and return to the keep (use when 'Auto-restart on wipe' is on).", _fail_to_inn)

-- ----------------------------------------------------------------------------
-- Assassin / Packmaster spawn TEXT warning (area-indicator overlay)
-- ----------------------------------------------------------------------------
-- Repurposes the on-screen "area indicator" text to flash a colored ASS!/PACK!
-- callout (with a running count) when a gutter runner / packmaster is queued to
-- spawn. Three cooperating hooks (Localize, PlayerHud.set_current_location,
-- AreaIndicatorUI.update) plus mod._gt_solo_on_spawn_queued which the merged
-- ConflictDirector.spawn_queued_unit hook in the main file calls.
local _BREED_NOTIFY = {
    skaven_gutter_runner = { setting = "gt_solo_assassin_text_warning", alone = "ASSASSIN_WARNING_ASS!", alone_dupe = "ASSASSIN_WARNING_ASS!_DUPE", multi = "ASSASSIN_WARNING_ASS_" },
    skaven_pack_master   = { setting = "gt_solo_packmaster_text_warning", alone = "PACK_WARNING_PACK!",  alone_dupe = "PACK_WARNING_PACK!_DUPE",  multi = "PACK_WARNING_PACK_" },
}

local function _warnings_on()
    return mod:get("gt_solo_assassin_text_warning") or mod:get("gt_solo_packmaster_text_warning")
end

mod._gt_solo_on_spawn_queued = function (conflict_director, breed)
    local nd = breed and breed.name and _BREED_NOTIFY[breed.name]
    if not nd then
        return
    end

    if mod:get(nd.setting) then
        if UISettings and UISettings.area_indicator then
            UISettings.area_indicator.wait_time = 0
        end
        mod:pcall(function()
            local player_unit = Managers.player:local_player().player_unit
            local hud_ext = ScriptUnit.extension(player_unit, "hud_system")
            local n = Managers.state.conflict:count_units_by_breed(breed.name)
            if n > 0 then
                hud_ext.current_location = nd.multi .. (n + 1)
            elseif hud_ext.current_location == nd.alone then
                hud_ext.current_location = nd.alone_dupe
            else
                hud_ext.current_location = nd.alone
            end
            mod._gt_solo_current_location = hud_ext.current_location
        end)
    elseif UISettings and UISettings.area_indicator then
        UISettings.area_indicator.wait_time = 1
    end
end

-- Turn the fake ASSASSIN_WARNING_/PACK_WARNING_ keys into display text. Cheap
-- plain-text find, gated on the toggles so normal Localize is untouched when off.
mod:hook(_G, "Localize", function (func, key)
    if type(key) == "string" and _warnings_on()
       and (string.find(key, "ASSASSIN_WARNING_", 1, true) or string.find(key, "PACK_WARNING_", 1, true)) then
        local s = key:gsub("ASSASSIN_WARNING_", ""):gsub("PACK_WARNING_", ""):gsub("_DUPE", ""):gsub("_", " ")
        return s
    end
    return func(key)
end)

-- Suppress the normal location-name text so it doesn't overwrite the warning.
mod:hook("PlayerHud", "set_current_location", function (func, self, location)
    if _warnings_on() then
        return
    end
    return func(self, location)
end)

-- Color/position the warning text in the area indicator.
mod:hook("AreaIndicatorUI", "update", function (func, self, dt)
    if _warnings_on() then
        mod:pcall(function()
            self.area_text_box.offset[2] = 0
            self.area_text_box.style.text.text_color = { 255, 255, 255, 0 }
            local cl = mod._gt_solo_current_location
            if cl then
                if cl == "ASSASSIN_WARNING_ASS_2" then
                    self.area_text_box.style.text.text_color = { 255, 255, 0, 0 }
                end
                if string.find(cl, "PACK_WARNING_", 1, true) then
                    self.area_text_box.offset[2] = -550
                    self.area_text_box.style.text.text_color = { 255, 0, 255, 0 }
                end
                if cl == "PACK_WARNING_PACK_2" then
                    self.area_text_box.style.text.text_color = { 255, 255, 165, 0 }
                end
            end
        end)
    end
    return func(self, dt)
end)

-- ----------------------------------------------------------------------------
-- Assassin / Packmaster hero voice callout
-- ----------------------------------------------------------------------------
-- Force your hero to say its "I hear a gutter runner" / "I see a skaven slaver"
-- line the moment one spawns.
local _BREED_DIALOGUE = {
    skaven_gutter_runner = "_gameplay_hearing_a_gutter_runner",
    skaven_pack_master   = "_gameplay_seeing_a_skaven_slaver",
}
local _PROFILE_SHORT = {
    empire_soldier = "pes", witch_hunter = "pwh", bright_wizard = "pbw", dwarf_ranger = "pdr", wood_elf = "pwe",
}

local function _force_play_hero_warning(dialogue_system, dialogue_part)
    mod:pcall(function()
        if not dialogue_system.is_server then
            return
        end
        local unit = Managers.player:local_player().player_unit
        local profile_name = ScriptUnit.extension(unit, "dialogue_system").context.player_profile
        local short_name = _PROFILE_SHORT[profile_name]
        if not short_name then
            return
        end
        local dialogue_key = short_name .. dialogue_part
        if dialogue_system.dialogues[dialogue_key] then
            local dialogue_id = DialogueLookup[dialogue_key]
            local network_manager = Managers.state.network
            local go_id, is_level_unit = network_manager:game_object_or_level_id(unit)
            local num_lines = dialogue_system.dialogues[dialogue_key].sound_events_n
            local line_index = math.random(num_lines)
            dialogue_system:rpc_interrupt_dialogue_event(nil, go_id, is_level_unit)
            dialogue_system:rpc_play_dialogue_event(nil, go_id, is_level_unit, dialogue_id, line_index)
        end
    end)
end

mod:hook_safe("BTSpawningAction", "enter", function (self, unit, blackboard, t)
    if not mod:get("gt_solo_assassin_hero_vo") then
        return
    end
    local d = blackboard.breed and _BREED_DIALOGUE[blackboard.breed.name]
    if d then
        _force_play_hero_warning(Managers.state.entity:system("dialogue_system"), d)
    end
end)

-- The forced line can trip an assert deep in the dialogue update; mirror the
-- original's pcall guard while the feature is on.
mod:hook("DialogueSystem", "_update_currently_playing_dialogues", function (func, self, dt)
    if not mod:get("gt_solo_assassin_hero_vo") then
        return func(self, dt)
    end
    pcall(func, self, dt)
end)

-- ----------------------------------------------------------------------------
-- Disable level intro audio -- REMOVED 2026-06-30: duplicated GUI Tweaker's
-- "Disable Level Intro Audio" (gut's hb/level_loading_screen.lua hooks the same
-- StateLoading._trigger_sound_events). Use the gut toggle instead.
-- ----------------------------------------------------------------------------

-- ----------------------------------------------------------------------------
-- Disable the local player's ultimate voice line  (THE crash fix)
-- ----------------------------------------------------------------------------
-- TrueSoloQoL crashed here: it iterated CareerSettings and read
-- career.activated_ability.ability_class without a nil-check. VT2's Versus
-- entries (vs_undecided, spectator) have no activated_ability, so it threw
-- (caught by pcall but logged every load). The nil-guard below fixes it. We also
-- de-dupe ability_class so a class shared by two careers isn't hooked twice
-- (VMF would drop the 2nd). All hooks install once at load; the body gates on
-- the toggle, so it costs nothing when off.
local function _vo_hook(func, self, ...)
    if mod:get("gt_solo_disable_ult_vo") then
        return
    end
    return func(self, ...)
end

mod:pcall(function ()
    if CareerSettings then
        local hooked = {}
        for career_key, career in pairs(CareerSettings) do
            local aa = career and career.activated_ability       -- nil-guard (the fix)
            local ability_class = aa and aa.ability_class
            if ability_class and career_key ~= "empire_soldier_tutorial" and not hooked[ability_class] then
                hooked[ability_class] = true
                mod:hook(ability_class, "_play_vo", _vo_hook)
            end
        end
    end
    -- Careers whose VO rides an action class rather than the ability class.
    local action_objects = {
        rawget(_G, "ActionCareerBWScholar"),
        rawget(_G, "ActionCareerWHBountyhunter"),
        rawget(_G, "ActionCareerDRRanger"),
        rawget(_G, "ActionCareerWEWaywatcher"),
    }
    for _, obj in ipairs(action_objects) do
        if obj then
            mod:hook(obj, "_play_vo", _vo_hook)
        end
    end
end)

-- ----------------------------------------------------------------------------
-- Disable the purple mutator explosion (elite/special death burst)
-- ----------------------------------------------------------------------------
mod:hook("AiUtils", "generic_mutator_explosion", function (func, killed_unit, blackboard, explosion_template_name)
    if mod:get("gt_solo_disable_mutator_explosions")
       and (explosion_template_name == "generic_mutator_explosion"
         or explosion_template_name == "generic_mutator_explosion_medium"
         or explosion_template_name == "generic_mutator_explosion_large") then
        return
    end
    return func(killed_unit, blackboard, explosion_template_name)
end)

-- ----------------------------------------------------------------------------
-- Disable fog / sun shadows  (visibility)
-- ----------------------------------------------------------------------------
mod:hook_safe("MoodHandler", "apply_environment_variables", function (self, shading_env)
    if mod:get("gt_solo_disable_fog") then
        ShadingEnvironment.set_scalar(shading_env, "fog_enabled", 0)
    end
    if mod:get("gt_solo_disable_sun_shadows") then
        ShadingEnvironment.set_scalar(shading_env, "sun_shadows_enabled", 0)
    end
end)

-- ----------------------------------------------------------------------------
-- Boss path debug: draw spawn spheres + (StreamingInfo) path-progress readout
-- ----------------------------------------------------------------------------
-- Both ride one EnemyRecycler.update hook. Path-progress needs the StreamingInfo
-- overlay mod (no-ops without it). Sphere drawing recreates its LineObject when
-- the world changes (mission transition) so it never reuses a stale handle.
mod:hook("EnemyRecycler", "update", function (func, self, t, dt, player_positions, threat_population, player_areas, use_player_areas)
    mod:pcall(function()
        if mod:get("gt_solo_boss_path_progress") then
            local streaming_info = get_mod("StreamingInfo")
            if streaming_info then
                local current_path = self.current_main_path_event_activation_dist or 0
                local ahead_path = (self.main_path_info and self.main_path_info.ahead_travel_dist) or 0
                streaming_info.perm_external_lines["BOSS_PATH_PROGRESS"] = {
                    string.format("Next:      %.2f", current_path),
                    string.format("Current:  %.2f", ahead_path),
                    string.format("Delta:     %.2f", current_path - ahead_path),
                }
            end
        end

        if mod:get("gt_solo_draw_boss_spheres") and self.main_path_events then
            local world = Managers.world:world("level_world")
            if mod._gt_solo_line_world ~= world then
                mod._gt_solo_line_object = nil
                mod._gt_solo_line_world = world
            end
            if not mod._gt_solo_line_object then
                mod._gt_solo_line_object = World.create_line_object(world, false)
            end
            LineObject.reset(mod._gt_solo_line_object)
            for _, main_path_event in ipairs(self.main_path_events) do
                local position = main_path_event[2]:unbox()
                LineObject.add_sphere(mod._gt_solo_line_object, Color(255, 0, 0), position, 45, 160, 16)
            end
            LineObject.dispatch(world, mod._gt_solo_line_object)
        end
    end)
    return func(self, t, dt, player_positions, threat_population, player_areas, use_player_areas)
end)
