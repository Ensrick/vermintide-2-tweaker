local mod = get_mod("crt")

-- Tourney Balance career/talent port. Issue #936 decomposes the old 17
-- career-wide mutations into independently reversible leaves. The old setting
-- IDs are retained by _crt_tourney_catalog.lua solely as per-career presets.
local catalog = mod:dofile("scripts/mods/career_tweaker/_crt_tourney_catalog")

local function _crt_make_stub()
    return { buffs = {}, _crt_pending = true }
end

-- Load-order/network determinism: register every new network-visible template
-- unconditionally. Leaf state only decides whether the real body is installed.
local _TRN_BUFF_NAMES = {
    "victor_bountyhunter_blessed_melee_attack_speed_buff",
    "victor_priest_5_2_speed_buff",
}
if BuffTemplates and NetworkLookup and NetworkLookup.buff_templates then
    for _, name in ipairs(_TRN_BUFF_NAMES) do
        if BuffTemplates[name] == nil then BuffTemplates[name] = _crt_make_stub() end
        if not rawget(NetworkLookup.buff_templates, name) then
            local idx = #NetworkLookup.buff_templates + 1
            NetworkLookup.buff_templates[idx] = name
            NetworkLookup.buff_templates[name] = idx
        end
    end
end

mod._crt_mod_registered_buff_names = mod._crt_mod_registered_buff_names or {}
for _, name in ipairs(_TRN_BUFF_NAMES) do
    mod._crt_mod_registered_buff_names[name] = true
end

-- Conflicts are leaf-scoped. A conflicting Ensrick leaf wins without blocking
-- unrelated Tourney changes on the same career.
local _CONFLICTS = {
    trn_es_huntsman_crit_aura_range = { "rework_es_huntsman_crit_aura_unlimited_range" },
    trn_es_knight_protective_presence = { "rework_es_knight_protective_presence_10m_rock_20m" },
    trn_es_questingknight_kill_move_speed_duration = { "rework_es_questingknight_virtue_of_impetuous_buffed" },
    trn_dr_ranger_exuberance_dr = { "rework_dr_ranger_exuberance_stacking_dr" },
    trn_wh_bountyhunter_double_shotted_refund = { "rework_wh_bountyhunter_double_shotted_80" },
    trn_wh_bountyhunter_just_reward_cooldown = { "rework_wh_bountyhunter_just_reward_5s_cooldown" },
    trn_wh_zealot_melee_power = { "rework_wh_zealot_power_5_to_10" },
    trn_bw_adept_famished_flames = { "rework_bw_adept_famished_flames_buffed" },
    trn_bw_adept_fires_from_ash = { "rework_bw_adept_fires_from_ash_1pct_plus_thp" },
}

local function _conflict_active(setting_id)
    for _, other in ipairs(_CONFLICTS[setting_id] or {}) do
        if mod:get(other) then return true end
    end
    return false
end

local function patches(character, career, rows)
    return { character = character, career = career, patches = rows }
end

local TOURNEY_MODS = {
    trn_es_mercenary_paced_strikes = patches("markus", "es_mercenary", {
        { buff = "markus_mercenary_passive_improved", field = "multiplier", value = 0.1 },
        { buff = "markus_mercenary_passive_improved", field = "targets", value = 3 },
    }),
    trn_es_huntsman_crit_aura_range = patches("markus", "es_huntsman", {
        { buff = "markus_huntsman_passive_crit_aura", field = "range", value = 20 },
    }),
    trn_es_huntsman_prowl_reload_speed = patches("markus", "es_huntsman", {
        { buff = "markus_huntsman_activated_ability_increased_reload_speed", field = "multiplier", value = -0.25 },
        { buff = "markus_huntsman_activated_ability_increased_reload_speed_duration", field = "multiplier", value = -0.25 },
    }),
    trn_es_knight_protective_presence = patches("markus", "es_knight", {
        { buff = "markus_knight_passive", field = "range", value = 20 },
        { buff = "markus_knight_passive_defence_aura", field = "multiplier", value = -0.1 },
        { buff = "markus_knight_passive_range", field = "range", value = 40 },
        { buff = "markus_knight_passive_defence_aura_range", field = "multiplier", value = -0.1 },
    }),
    trn_es_knight_have_at_them_range = patches("markus", "es_knight", {
        { buff = "markus_knight_guard_defence", field = "range", value = 20 },
        { buff = "markus_knight_guard", field = "range", value = 20 },
        { buff = "markus_knight_damage_taken_ally_proximity", field = "range", value = 20 },
    }),
    trn_es_knight_cooldown_on_damage = patches("markus", "es_knight", {
        { buff = "markus_knight_ability_cooldown_on_damage_taken", field = "bonus", value = 0.35 },
    }),
    trn_es_knight_elite_stagger_power_duration = patches("markus", "es_knight", {
        { buff = "markus_knight_power_level_on_stagger_elite_buff", field = "duration", value = 15 },
    }),
    trn_es_knight_push_attack_speed_duration = patches("markus", "es_knight", {
        { buff = "markus_knight_attack_speed_on_push_buff", field = "duration", value = 5 },
    }),
    trn_es_knight_impact_power = patches("markus", "es_knight", {
        { buff = "markus_knight_power_level_impact", field = "multiplier", value = 0.2 },
    }),
    trn_es_knight_stagger_cooldown_duration = patches("markus", "es_knight", {
        { buff = "markus_knight_cooldown_buff", field = "duration", value = 1.5 },
    }),
    trn_es_questingknight_instant_kill_threshold = patches("markus", "es_questingknight", {
        { buff = "markus_questing_knight_crit_can_insta_kill", field = "damage_multiplier", value = 3 },
    }),
    trn_es_questingknight_kill_move_speed_duration = patches("markus", "es_questingknight", {
        { buff = "markus_questing_knight_ability_buff_on_kill_movement_speed", field = "duration", value = 25 },
    }),
    trn_es_questingknight_health_refund = patches("markus", "es_questingknight", {
        { buff = "markus_questing_knight_health_refund_over_time", field = "heal_amount_fraction", value = 0.25 },
    }),
    trn_dr_ranger_attack_speed = patches("bardin", "dr_ranger", {
        { buff = "bardin_ranger_attack_speed", field = "multiplier", value = 0.15 },
    }),
    trn_dr_ranger_exuberance_dr = patches("bardin", "dr_ranger", {
        { buff = "bardin_ranger_reduced_damage_taken_headshot_buff", field = "multiplier", value = -0.2 },
    }),
    trn_dr_ranger_free_grenade_duration = patches("bardin", "dr_ranger", {
        { buff = "bardin_ranger_ability_free_grenade_buff", field = "duration", value = 10 },
        { buff = "bardin_ranger_ability_free_grenade_buff", field = "refresh_durations", value = true },
    }),
    trn_dr_ironbreaker_cooldown_on_damage = patches("bardin", "dr_ironbreaker", {
        { buff = "bardin_ironbreaker_ability_cooldown_on_damage_taken", field = "bonus", value = 0.4 },
    }),
    trn_dr_ironbreaker_gromril_regeneration = patches("bardin", "dr_ironbreaker", {
        { buff = "bardin_ironbreaker_stacking_buff_gromril", field = "update_frequency", value = 2 },
    }),
    trn_dr_ironbreaker_gromril_attack_speed = patches("bardin", "dr_ironbreaker", {
        { buff = "bardin_ironbreaker_gromril_attack_speed", field = "duration", value = 15 },
        { buff = "bardin_ironbreaker_gromril_attack_speed", field = "multiplier", value = 0.048 },
    }),
    trn_dr_slayer_dodge_damage_reduction = patches("bardin", "dr_slayer", {
        { buff = "bardin_slayer_push_on_dodge", field = "stat_buff", value = "damage_taken" },
        { buff = "bardin_slayer_push_on_dodge", field = "multiplier", value = -0.15 },
    }),
    trn_we_waywatcher_headshot_attack_speed = patches("kerillian", "we_waywatcher", {
        { buff = "kerillian_waywatcher_attack_speed_on_ranged_headshot_buff", field = "multiplier", value = 0.2 },
        { buff = "kerillian_waywatcher_attack_speed_on_ranged_headshot_buff", field = "duration", value = 10 },
    }),
    trn_we_maidenguard_stamina_aura_range = patches("kerillian", "we_maidenguard", {
        { buff = "kerillian_maidenguard_passive_stamina_regen_aura", field = "range", value = 20 },
    }),
    trn_we_maidenguard_focused_spirit_cooldown = patches("kerillian", "we_maidenguard", {
        { buff = "kerillian_maidenguard_power_level_on_unharmed_cooldown", field = "duration", value = 4 },
    }),
    trn_we_maidenguard_push_block_stacks = patches("kerillian", "we_maidenguard", {
        { buff = "kerillian_maidenguard_speed_on_push", field = "max_sub_buff_stacks", value = 3 },
        { buff = "kerillian_maidenguard_speed_on_push", field = "amount_to_add", value = 3 },
        { buff = "kerillian_maidenguard_speed_on_block", field = "max_sub_buff_stacks", value = 3 },
        { buff = "kerillian_maidenguard_speed_on_block", field = "amount_to_add", value = 3 },
        { buff = "kerillian_maidenguard_speed_on_block_dummy_buff", field = "max_stacks", value = 3 },
    }),
    trn_we_maidenguard_power_on_dodge = patches("kerillian", "we_maidenguard", {
        { buff = "kerillian_maidenguard_power_on_dodge", field = "multiplier", value = 0.15 },
        { buff = "kerillian_maidenguard_power_on_dodge", field = "duration", value = 3.5 },
    }),
    trn_we_maidenguard_max_health = patches("kerillian", "we_maidenguard", {
        { buff = "kerillian_maidenguard_max_health", field = "multiplier", value = 0.2 },
    }),
    trn_we_maidenguard_max_ammo = patches("kerillian", "we_maidenguard", {
        { buff = "kerillian_maidenguard_max_ammo", field = "multiplier", value = 0.7 },
    }),
    trn_we_shade_infiltrate_duration = patches("kerillian", "we_shade", {
        { buff = "kerillian_shade_activated_ability_phasing", field = "duration", value = 2.5 },
        { buff = "kerillian_shade_activated_ability_short_blocker", field = "duration", value = 2.5 },
        { buff = "kerillian_shade_activated_ability", field = "duration", value = 2.5 },
        { buff = "kerillian_shade_activated_ability_restealth", field = "duration", value = 2.5 },
    }),
    trn_we_shade_stealth_parry = patches("kerillian", "we_shade", {
        { buff = "kerillian_shade_passive_stealth_parry", field = "event", value = "on_timed_block_long" },
    }),
    trn_we_shade_critical_damage = patches("kerillian", "we_shade", {
        { buff = "kerillian_shade_increased_critical_strike_damage", field = "multiplier", value = 0.8 },
    }),
    trn_we_thornsister_team_aura_duration = patches("kerillian", "we_thornsister", {
        { buff = "kerillian_thorn_sister_team_buff_aura", field = "duration", value = 20 },
    }),
    trn_we_thornsister_thp_funnel = patches("kerillian", "we_thornsister", {
        { buff = "kerillian_thorn_sister_passive_temp_health_funnel_aura_buff", field = "multiplier", value = 0.1 },
    }),
    trn_wh_bountyhunter_double_shotted_refund = patches("victor", "wh_bountyhunter", {
        { buff = "victor_bountyhunter_activated_ability_railgun_delayed_add", field = "multiplier", value = 0.8 },
    }),
    trn_wh_bountyhunter_job_well_done_stacks = patches("victor", "wh_bountyhunter", {
        { buff = "victor_bountyhunter_stacking_damage_reduction_on_elite_or_special_kill_buff", field = "max_stacks", value = 20 },
    }),
    trn_wh_bountyhunter_just_reward_cooldown = patches("victor", "wh_bountyhunter", {
        { buff = "victor_bountyhunter_activated_ability_passive_cooldown_reduction", field = "cooldown", value = 4.5 },
    }),
    trn_wh_bountyhunter_blessed_kill = {
        character = "victor", career = "wh_bountyhunter", patches = {},
        custom_apply = function(saved)
            local template = BuffTemplates and BuffTemplates.victor_bountyhunter_activate_passive_on_melee_kill
            local buff = template and template.buffs and template.buffs[1]
            if buff then
                saved.buff_to_add, saved.activation_buff, saved.update_func = buff.buff_to_add, buff.activation_buff, buff.update_func
                saved.fields_set = true
                buff.buff_to_add = "victor_bountyhunter_blessed_melee_attack_speed_buff"
                buff.activation_buff = "victor_bountyhunter_blessed_melee_damage_buff"
                buff.update_func = "activate_buff_on_other_buff"
            end
            if BuffTemplates and (not BuffTemplates.victor_bountyhunter_blessed_melee_attack_speed_buff
                    or BuffTemplates.victor_bountyhunter_blessed_melee_attack_speed_buff._crt_pending) then
                BuffTemplates.victor_bountyhunter_blessed_melee_attack_speed_buff = { buffs = {{
                    name = "victor_bountyhunter_blessed_melee_attack_speed_buff",
                    max_stacks = 1, multiplier = 0.15, stat_buff = "attack_speed",
                }} }
                saved.created = true
            end
            local passive = rawget(_G, "PassiveAbilitySettings")
            local buffs = passive and passive.wh_2 and passive.wh_2.buffs
            if buffs then
                local present = false
                for _, name in ipairs(buffs) do
                    if name == "victor_bountyhunter_activate_passive_on_melee_kill" then present = true; break end
                end
                if not present then
                    saved.passive_count = #buffs
                    table.insert(buffs, "victor_bountyhunter_activate_passive_on_melee_kill")
                end
            end
        end,
        custom_restore = function(saved)
            local passive = rawget(_G, "PassiveAbilitySettings")
            local buffs = passive and passive.wh_2 and passive.wh_2.buffs
            if buffs and saved.passive_count then
                while #buffs > saved.passive_count do table.remove(buffs) end
            end
            local template = BuffTemplates and BuffTemplates.victor_bountyhunter_activate_passive_on_melee_kill
            local buff = template and template.buffs and template.buffs[1]
            if buff and saved.fields_set then
                buff.buff_to_add, buff.activation_buff, buff.update_func = saved.buff_to_add, saved.activation_buff, saved.update_func
            end
            if saved.created and BuffTemplates then
                BuffTemplates.victor_bountyhunter_blessed_melee_attack_speed_buff = _crt_make_stub()
            end
        end,
    },
    trn_wh_zealot_melee_power = patches("victor", "wh_zealot", {
        { buff = "victor_zealot_power", field = "multiplier", value = 0.2 },
        { buff = "victor_zealot_power", field = "stat_buff", value = "power_level_melee" },
    }),
    trn_wh_priest_prayer_movement_speed = {
        character = "victor", career = "wh_priest", network_unsafe = true,
        patches = {
            { buff = "victor_priest_5_2", field = "buff_to_add", value = "victor_priest_5_2_speed_buff" },
            { buff = "victor_priest_5_2", field = "update_func", value = "crt_wire_safe_distance_aura_driver" },
        },
        custom_apply = function(saved)
            if BuffTemplates and (not BuffTemplates.victor_priest_5_2_speed_buff
                    or BuffTemplates.victor_priest_5_2_speed_buff._crt_pending) then
                BuffTemplates.victor_priest_5_2_speed_buff = { buffs = {{
                    name = "victor_priest_5_2_speed_buff", max_stacks = 1,
                    multiplier = 1.1, apply_buff_func = "apply_movement_buff",
                    remove_buff_func = "remove_movement_buff",
                    path_to_movement_setting_to_modify = { "move_speed" },
                }} }
                saved.created = true
            end
        end,
        custom_restore = function(saved)
            if saved.created and BuffTemplates then BuffTemplates.victor_priest_5_2_speed_buff = _crt_make_stub() end
        end,
    },
    trn_bw_adept_famished_flames = patches("sienna", "bw_adept", {
        { buff = "sienna_adept_increased_burn_damage", field = "multiplier", value = 1.5 },
        { buff = "sienna_adept_reduced_non_burn_damage", field = "multiplier", value = -0.3 },
    }),
    trn_bw_adept_ignite_damage_reduction = patches("sienna", "bw_adept", {
        { buff = "sienna_adept_damage_reduction_on_ignited_enemy_buff", field = "max_stacks", value = 4 },
        { buff = "sienna_adept_damage_reduction_on_ignited_enemy_buff", field = "multiplier", value = -0.05 },
    }),
    trn_bw_adept_fires_from_ash = patches("sienna", "bw_adept", {
        { buff = "sienna_adept_cooldown_reduction_on_burning_enemy_killed", field = "cooldown_reduction", value = 0.02 },
    }),
    trn_bw_adept_burning_vigour = patches("sienna", "bw_adept", {
        { buff = "sienna_adept_attack_speed_on_enemies_hit", field = "required_targets", value = 1 },
    }),
    trn_bw_scholar_martial_study = patches("sienna", "bw_scholar", {
        { buff = "sienna_scholar_increased_attack_speed", field = "multiplier", value = 0.1 },
    }),
    trn_bw_necromancer_spell_cast_ranged_power = patches("sienna", "bw_necromancer", {
        { buff = "sienna_necromancer_2_2_buff", field = "stat_buff", value = "increased_weapon_damage_ranged" },
    }),
    trn_bw_necromancer_critical_cleave = patches("sienna", "bw_necromancer", {
        { buff = "sienna_necromancer_2_3", field = "multiplier", value = 0 },
    }),
    trn_bw_necromancer_cursed_blood = patches("sienna", "bw_necromancer", {
        { buff = "sienna_necromancer_4_1_cursed_blood", field = "propagation_multiplier", value = 0.1 },
    }),
}

local _originals = {}

local function restore_all_tourney_mods()
    if not BuffTemplates then return end
    for setting_id, saved in pairs(_originals) do
        local def = TOURNEY_MODS[setting_id]
        if def and def.custom_restore then def.custom_restore(saved) end
        for _, entry in ipairs(saved) do
            local template = BuffTemplates[entry.buff]
            if template and template.buffs and template.buffs[1] then
                template.buffs[1][entry.field] = entry.old_value
            end
        end
    end
    _originals = {}
end

local function apply_tourney_mods()
    if not BuffTemplates then return end
    restore_all_tourney_mods()
    local parity = mod._crt_peer_parity
    local parity_ok = parity ~= nil and parity:applied_state() == "enabled"
    for setting_id, def in pairs(TOURNEY_MODS) do
        if mod:get(setting_id) and not _conflict_active(setting_id) then
            if def.network_unsafe and not parity_ok then
                pcall(printf, "[crt:425] parity gate: tourney entry %s held at vanilla (a lobby peer lacks crt)", setting_id)
            else
                local saved = {}
                for _, patch in ipairs(def.patches or {}) do
                    local template = BuffTemplates[patch.buff]
                    local buff = template and template.buffs and template.buffs[1]
                    if buff then
                        saved[#saved + 1] = { buff = patch.buff, field = patch.field, old_value = buff[patch.field] }
                        buff[patch.field] = patch.value
                    end
                end
                if def.custom_apply then def.custom_apply(saved) end
                _originals[setting_id] = saved
            end
        end
    end
end

local function get_active_count()
    local count = 0
    for setting_id in pairs(TOURNEY_MODS) do
        if mod:get(setting_id) then count = count + 1 end
    end
    return count
end

return {
    TOURNEY_MODS = TOURNEY_MODS,
    TOGGLE_IDS = catalog.LEAF_IDS,
    CAREER_MASTER_IDS = catalog.MASTER_IDS,
    CATALOG = catalog,
    CONFLICTS = _CONFLICTS,
    apply = apply_tourney_mods,
    restore = restore_all_tourney_mods,
    active_count = get_active_count,
}
