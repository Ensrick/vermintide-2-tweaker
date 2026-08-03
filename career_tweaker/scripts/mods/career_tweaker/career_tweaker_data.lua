local mod = get_mod("crt")

local function cb(id)
    local tooltip_suffix = id:match("^trn_[^_]+_[^_]+$") and "_tooltip" or "_description"
    return { setting_id = id, type = "checkbox", default_value = false,
        tooltip = id .. tooltip_suffix }
end

return {
    name              = mod:localize("mod_name"),
    description       = mod:localize("mod_description"),
    is_togglable      = true,
    options = {
        widgets = {
            -- ============================================================
            -- Armor & Overcharge (hook-based; v0.3.32-dev)
            -- ============================================================
            {
                setting_id  = "armor_overcharge_group",
                type        = "group",
                sub_widgets = {
                    { setting_id = "armor_gromril_ignore_chip",             type = "checkbox", default_value = false, tooltip = "armor_gromril_ignore_chip_tooltip" },
                    { setting_id = "armor_specials_dont_break_gromril",     type = "checkbox", default_value = false, tooltip = "armor_specials_dont_break_gromril_tooltip" },
                    { setting_id = "unchained_no_overcharge_from_ff",       type = "checkbox", default_value = false, tooltip = "unchained_no_overcharge_from_ff_tooltip" },
                    { setting_id = "unchained_no_overcharge_from_disablers", type = "checkbox", default_value = false, tooltip = "unchained_no_overcharge_from_disablers_tooltip" },
                    { setting_id = "unchained_no_overcharge_from_self_dot",  type = "checkbox", default_value = false, tooltip = "unchained_no_overcharge_from_self_dot_tooltip" },
                    { setting_id = "maidenguard_focused_spirit_ignore_chip_damage", type = "checkbox", default_value = true, tooltip = "maidenguard_focused_spirit_ignore_chip_damage_tooltip" },
                    { setting_id = "oe_benefit_from_cooldown_reduction",    type = "checkbox", default_value = false, tooltip = "oe_benefit_from_cooldown_reduction_tooltip" },
                },
            },
            -- ============================================================
            -- Character Experience Level Override
            -- Roster-order exemption: per-character level fields follow the
            -- vanilla hero roster (Kruber, Bardin, Kerillian, Saltzpyre,
            -- Sienna), not A-Z. All careers under one hero share the same XP;
            -- the override is keyed by hero display_name. 0 = no override;
            -- 1-35 = report that level everywhere (inventory badge,
            -- char-select, mission spawn).
            -- ============================================================
            {
                setting_id  = "experience_levels_group",
                type        = "group",
                sub_widgets = {
                    { setting_id = "level_override_empire_soldier", type = "numeric", default_value = 0, range = { 0, 35 } },
                    { setting_id = "level_override_dwarf_ranger",   type = "numeric", default_value = 0, range = { 0, 35 } },
                    { setting_id = "level_override_wood_elf",       type = "numeric", default_value = 0, range = { 0, 35 } },
                    { setting_id = "level_override_witch_hunter",   type = "numeric", default_value = 0, range = { 0, 35 } },
                    { setting_id = "level_override_bright_wizard",  type = "numeric", default_value = 0, range = { 0, 35 } },
                    -- v0.3.21-dev: bypass the LEVEL gate on owned careers. DLC
                    -- ownership is preserved (unowned-DLC careers stay locked).
                    -- Hooks ProgressionUnlocks.is_unlocked_for_profile only.
                    { setting_id = "unlock_all_careers",            type = "checkbox", default_value = false, tooltip = "unlock_all_careers_tooltip" },
                },
            },
            -- ============================================================
            -- Big Rebalance Integration (Core's Big Rebalance - ~160 opt-in
            -- toggles, all default false). Master toggle enables pre-
            -- registration of all new buffs / talent buffs / damage profiles /
            -- explosion templates in canonical sorted order across peers
            -- (SHARED with wt + et). Individual toggles overlay content into
            -- those pre-registered names.
            -- ============================================================
--[==[ BIG REBALANCE WIDGETS — ON ICE (bt retired 2026-06-08). The cbr_group menu
-- group is commented out so the inert BR toggles don't appear in the VMF menu.
-- To restore, delete this opener line and the closing long-comment marker below.
            {
                setting_id  = "cbr_group",
                type        = "group",
                sub_widgets = (function()
                    local function cb(id) return { setting_id = id, type = "checkbox", default_value = false } end
                    return {
                        -- Master toggle moved to the new `bt` (Tweaker: Buffs)
                        -- mod. Subscribe to that mod and enable its master to
                        -- make these ct BR sub-toggles functional.
                        -- General
                        {
                            setting_id  = "cbr_general_group",
                            type        = "group",
                            sub_widgets = {
                                cb("cbr_thp_talents_rebalanced"),
                                cb("cbr_stagger_talents_rebalanced"),
                                cb("cbr_timed_block_framework"),
                                cb("cbr_default_dodge_count_2"),
                                cb("cbr_infinite_wounds_perk"),
                                cb("cbr_grab_proof_ledge_self_rescue"),
                                cb("cbr_melee_action_three_zoom"),
                                cb("cbr_power_level_on_hit_extended"),
                                cb("cbr_damage_taken_pipeline_extras"),
                                cb("cbr_weak_bomb_template"),
                                cb("cbr_trait_conqueror_rename"),
                                cb("cbr_force_load_dlc_packages"),
                            },
                        },
                        -- Kruber
                        {
                            setting_id  = "cbr_es_group",
                            type        = "group",
                            sub_widgets = {
                                { setting_id = "cbr_es_mercenary_group", type = "group", sub_widgets = {
                                    cb("cbr_merc_row2_talent_2_2_desc"),
                                    cb("cbr_merc_row2_talent_2_3_clear_perks"),
                                    cb("cbr_merc_row4_talent_4_1_desc"),
                                    cb("cbr_merc_row5_talent_5_3_ammo_on_elite_melee"),
                                    cb("cbr_merc_row6_talent_6_3_ult_revive"),
                                    cb("cbr_merc_passive_paced_strikes_single_target"),
                                    cb("cbr_merc_passive_custom_proc"),
                                    cb("cbr_merc_passive_power_level"),
                                    cb("cbr_merc_cdr_on_damage_taken"),
                                    cb("cbr_merc_power_cleave_multiplier_1"),
                                    cb("cbr_merc_dodge_range_infinite_dodges"),
                                    cb("cbr_merc_ult_cooldown_40"),
                                } },
                                { setting_id = "cbr_es_knight_group", type = "group", sub_widgets = {
                                    cb("cbr_fk_row2_talent_2_3_buffer_both"),
                                    cb("cbr_fk_row5_talent_5_1_ult_cdr_on_incap"),
                                    cb("cbr_fk_row5_talent_5_2_piston"),
                                    cb("cbr_fk_row6_talent_6_2_heavy_buff"),
                                    cb("cbr_fk_passive_dr_15"),
                                    cb("cbr_fk_aura_range_dr_10"),
                                    cb("cbr_fk_aura_dr_10"),
                                    cb("cbr_fk_passive_range_10"),
                                    cb("cbr_fk_passive_range_config"),
                                    cb("cbr_fk_passive_guard_defence_config"),
                                    cb("cbr_fk_passive_guard_power_config"),
                                    cb("cbr_fk_passive_proximity_stacks_config"),
                                    cb("cbr_fk_passive_proximity_dr_per_ally"),
                                    cb("cbr_fk_cdr_on_damage_taken_35"),
                                    cb("cbr_fk_on_stagger_changed_to_on_kill"),
                                    cb("cbr_fk_attack_speed_on_cleave_hit2"),
                                    cb("cbr_fk_free_push_duration_2"),
                                    cb("cbr_fk_cdr_on_stagger_elite_func"),
                                    cb("cbr_fk_cdr_on_stagger_elite_buff_config"),
                                    cb("cbr_fk_ult_invuln_4s_ledge_rescue"),
                                    cb("cbr_fk_ult_as_per_hit_2pc"),
                                    cb("cbr_fk_ult_charge_overhaul"),
                                } },
                                { setting_id = "cbr_es_huntsman_group", type = "group", sub_widgets = {
                                    cb("cbr_huntsman_ult_cooldown_60"),
                                    cb("cbr_huntsman_passive_buff_list_overhaul"),
                                    cb("cbr_huntsman_cdr_on_damage_taken_25"),
                                    cb("cbr_huntsman_passive_crit_aura_range_10"),
                                    cb("cbr_huntsman_passive_icon_stacks"),
                                    cb("cbr_huntsman_thp_on_ranged_kill_bloodlust"),
                                    cb("cbr_huntsman_row2_talent_2_2_haste"),
                                    cb("cbr_huntsman_row4_talent_4_3_desc"),
                                    cb("cbr_huntsman_row5_talent_5_1_bleed_on_crit"),
                                    cb("cbr_huntsman_row5_talent_5_2_dr_on_elite_kill"),
                                    cb("cbr_huntsman_row5_talent_5_3_sniper_perfect_accuracy"),
                                    cb("cbr_huntsman_row6_talent_6_1_add_ult_penetration"),
                                    cb("cbr_huntsman_row6_talent_6_2_ult_pierce_big"),
                                    cb("cbr_huntsman_row6_talent_6_3_ult_pierce"),
                                    cb("cbr_huntsman_ult_explosion_overhaul"),
                                } },
                                { setting_id = "cbr_es_questingknight_group", type = "group", sub_widgets = {
                                    cb("cbr_gk_ult_cooldown_60"),
                                    cb("cbr_gk_row2_talent_2_2_crit_insta_kill"),
                                    cb("cbr_gk_row2_talent_2_3_first_target_45pc"),
                                    cb("cbr_gk_row5_talent_5_2_infinite_dodges"),
                                    cb("cbr_gk_row6_talent_6_2_cdr_30pc"),
                                    cb("cbr_gk_ult_kill_buff_no_ranged_knockback"),
                                    cb("cbr_gk_ult_vfx_and_kill_buff"),
                                    cb("cbr_gk_side_quest_rework_strength_potion"),
                                } },
                            },
                        },
                        -- Bardin
                        {
                            setting_id  = "cbr_dr_group",
                            type        = "group",
                            sub_widgets = {
                                { setting_id = "cbr_dr_ironbreaker_group", type = "group", sub_widgets = {
                                    cb("cbr_ib_ult_overhaul_50pc_dr_talents"),
                                    cb("cbr_ib_passive_overcharge_no_slow"),
                                    cb("cbr_ib_row2_talent_2_1_drakefire_heat_and_speed"),
                                    cb("cbr_ib_passive_power_on_ally_75pc_range_10"),
                                    cb("cbr_ib_party_power_on_block_3pc_15s"),
                                    cb("cbr_ib_rising_anger_3pc_as"),
                                    cb("cbr_ib_gromril_as_6pc_15s"),
                                    cb("cbr_ib_row5_talent_5_3_piston_power"),
                                    cb("cbr_ib_piston_icon_swaps"),
                                } },
                                { setting_id = "cbr_dr_ranger_group", type = "group", sub_widgets = {
                                    cb("cbr_ranger_row2_talent_2_1_dupe_10pc"),
                                    cb("cbr_ranger_row2_talent_2_3_as_on_empty_clip"),
                                    cb("cbr_ranger_passive_custom_drops"),
                                    cb("cbr_ranger_passive_throwing_axes_ammo"),
                                    cb("cbr_ranger_row5_talent_5_1_sniper_perfect_accuracy"),
                                    cb("cbr_ranger_thp_headshot_dr_20pc"),
                                    cb("cbr_ranger_row5_talent_5_2_desc"),
                                    cb("cbr_ranger_extended_ranged_boost_multipliers"),
                                    cb("cbr_ranger_row6_talent_6_3_free_grenade_on_disengage"),
                                    cb("cbr_ranger_free_grenade_buff_10s"),
                                    cb("cbr_ranger_smoke_screen_buff_additions"),
                                    cb("cbr_ranger_ult_explosion_templates"),
                                } },
                                { setting_id = "cbr_dr_slayer_group", type = "group", sub_widgets = {
                                    cb("cbr_slayer_passive_perks_reflow"),
                                    cb("cbr_slayer_melee_charge_dr_25pc"),
                                    cb("cbr_slayer_row5_talent_5_2_desc"),
                                    cb("cbr_slayer_row2_talent_2_1_dual_wield_combos"),
                                    cb("cbr_slayer_row2_talent_2_2_add_max_stacks"),
                                    cb("cbr_slayer_row2_talent_2_3_crit_below_hp"),
                                    cb("cbr_slayer_passive_custom_stack_proc"),
                                    cb("cbr_slayer_row4_talent_4_2_add_blood_drunk"),
                                    cb("cbr_slayer_row4_talent_4_3_desc"),
                                    cb("cbr_slayer_row5_talent_5_3_scaling_dr"),
                                    cb("cbr_slayer_ult_double_leap_overhaul"),
                                } },
                                { setting_id = "cbr_dr_engineer_group", type = "group", sub_widgets = {
                                    cb("cbr_engineer_max_hp_125"),
                                    cb("cbr_engineer_base_crit_10pc"),
                                    cb("cbr_engineer_passive_add_falling_stacks"),
                                    cb("cbr_engineer_pump_buff_no_timeout"),
                                    cb("cbr_engineer_row2_talent_2_3_clip_size_vs_power"),
                                    cb("cbr_engineer_row4_talent_4_1_as_and_crank_debuff"),
                                    cb("cbr_engineer_row5_talent_5_3_crit_heavy_explosion"),
                                    cb("cbr_engineer_row6_talent_6_2_ability_check"),
                                    cb("cbr_engineer_crank_gun_no_slowdown_ramp"),
                                    cb("cbr_engineer_survival_ale_buffs"),
                                } },
                            },
                        },
                        -- Kerillian
                        {
                            setting_id  = "cbr_we_group",
                            type        = "group",
                            sub_widgets = {
                                { setting_id = "cbr_we_waywatcher_group", type = "group", sub_widgets = {
                                    cb("cbr_ww_ult_cd_60"),
                                    cb("cbr_ww_passive_zoom"),
                                    cb("cbr_ww_passive_faster_bows"),
                                    cb("cbr_ww_passive_ammo_50pct"),
                                    cb("cbr_ww_amaranthe_rework"),
                                    cb("cbr_ww_rangedhs_as_20"),
                                    cb("cbr_ww_row2_talent_2_2_poison_on_special"),
                                    cb("cbr_ww_row2_talent_2_3_desc"),
                                    cb("cbr_ww_row4_talent_4_1_desc"),
                                    cb("cbr_ww_row4_talent_4_2_desc"),
                                    cb("cbr_ww_row5_talent_5_1_hs_dmg"),
                                    cb("cbr_ww_row5_talent_5_2_ricochet_plus_crit"),
                                    cb("cbr_ww_row5_talent_5_3_ammo_on_melee_kills"),
                                    cb("cbr_ww_row6_talent_6_3_clear_buffs"),
                                    cb("cbr_ww_extra_shots_loop"),
                                    cb("cbr_ww_cd_on_headshot_proc"),
                                    cb("cbr_ww_throw_speed_action_time_scale"),
                                } },
                                { setting_id = "cbr_we_maidenguard_group", type = "group", sub_widgets = {
                                    cb("cbr_hm_ult_cd_40"),
                                    cb("cbr_hm_cdr_on_damage_25"),
                                    cb("cbr_hm_passive_zoom"),
                                    cb("cbr_hm_dash_toggle"),
                                    cb("cbr_hm_banner_as"),
                                    cb("cbr_hm_banner_as_large"),
                                    cb("cbr_hm_passive_perks_rework"),
                                    cb("cbr_hm_stam_aura_range_10"),
                                    cb("cbr_hm_stam_aura_50pct"),
                                    cb("cbr_hm_banner_ult_rework"),
                                    cb("cbr_hm_power_on_unharmed_20"),
                                    cb("cbr_hm_unharmed_cd_5"),
                                    cb("cbr_hm_row2_talent_2_2_crit_allies"),
                                    cb("cbr_hm_row2_talent_2_3_desc"),
                                    cb("cbr_hm_block_speed_stacks_3"),
                                    cb("cbr_hm_push_speed_stacks_3"),
                                    cb("cbr_hm_block_speed_20pct"),
                                    cb("cbr_hm_block_cleave_75pct"),
                                    cb("cbr_hm_block_dummy_stacks_3"),
                                    cb("cbr_hm_row4_talent_4_3_armoured_on_dodge"),
                                    cb("cbr_hm_row5_talent_5_3_moonbow_speed_plus_ammo"),
                                    cb("cbr_hm_max_ammo_50pct"),
                                    cb("cbr_hm_row6_talent_6_1_aoe_immunity"),
                                    cb("cbr_hm_row6_talent_6_2_max_hp_50"),
                                    cb("cbr_hm_row6_talent_6_3_grabber_immunity"),
                                } },
                                { setting_id = "cbr_we_shade_group", type = "group", sub_widgets = {
                                    cb("cbr_shade_max_hp_125"),
                                    cb("cbr_shade_passive_zoom"),
                                    cb("cbr_shade_passive_parry_crit"),
                                    cb("cbr_shade_hs_stack_20_5"),
                                    cb("cbr_shade_poison_bleed_dmg_30"),
                                    cb("cbr_shade_crit_dmg_75"),
                                    cb("cbr_shade_backstab_ammo_5"),
                                    cb("cbr_shade_ult_phasing_restealth"),
                                } },
                                { setting_id = "cbr_we_thornsister_group", type = "group", sub_widgets = {
                                    cb("cbr_ts_passive_zoom"),
                                    cb("cbr_ts_vent_nerf"),
                                    cb("cbr_ts_ult_cd_50"),
                                    cb("cbr_ts_poison_debuff_15"),
                                    cb("cbr_ts_poison_debuff_improved_15"),
                                    cb("cbr_ts_cdr_on_hit_35"),
                                    cb("cbr_ts_cdr_on_damage_25"),
                                    cb("cbr_ts_set_back_3s"),
                                    cb("cbr_ts_temp_health_funnel_40"),
                                    cb("cbr_ts_row2_talent_2_1_as_on_health_stack"),
                                    cb("cbr_ts_as_on_full_5_per_25"),
                                    cb("cbr_ts_crit_on_ability_3"),
                                    cb("cbr_ts_row2_talent_2_3_desc"),
                                    cb("cbr_ts_row6_talent_6_1_drain_bush"),
                                    cb("cbr_ts_wall_radius_5_5"),
                                    cb("cbr_ts_wall_radius_improved_5_5"),
                                    cb("cbr_ts_wall_overhaul"),
                                } },
                            },
                        },
                        -- Saltzpyre (Victor)
                        {
                            setting_id  = "cbr_wh_group",
                            type        = "group",
                            sub_widgets = {
                                { setting_id = "cbr_wh_captain_group", type = "group", sub_widgets = {
                                    cb("cbr_whc_row2_talent_2_1_add_push_power"),
                                    cb("cbr_whc_parry_trigger_long"),
                                    cb("cbr_whc_parry_crit_duration_3"),
                                    cb("cbr_whc_row5_talent_5_3_ammo_on_melee"),
                                    cb("cbr_whc_row6_talent_6_1_tag_on_hit"),
                                    cb("cbr_whc_ult_party_crit_15"),
                                    cb("cbr_whc_ult_explosion_rework"),
                                    cb("cbr_whc_ult_rework"),
                                    cb("cbr_whc_ping_persist"),
                                    cb("cbr_whc_ping_handle_rework"),
                                } },
                                { setting_id = "cbr_wh_zealot_group", type = "group", sub_widgets = {
                                    cb("cbr_zealot_passive_rework"),
                                    cb("cbr_zealot_passive_perks_rework"),
                                    cb("cbr_zealot_row2_talent_2_1_as_scaling"),
                                    cb("cbr_zealot_row2_talent_2_2_perks_clear"),
                                    cb("cbr_zealot_row2_talent_2_3_first_target"),
                                    cb("cbr_zealot_row4_talent_4_1_heart_iron_rework"),
                                    cb("cbr_zealot_row4_talent_4_2_high_health_as"),
                                    cb("cbr_zealot_row4_talent_4_3_dr_low_hp"),
                                    cb("cbr_zealot_row5_talent_5_1_as_on_hit"),
                                    cb("cbr_zealot_row5_talent_5_2_power_on_hit"),
                                    cb("cbr_zealot_row5_talent_5_3_cleave_on_hit"),
                                    cb("cbr_zealot_ult_power_2_5"),
                                    cb("cbr_zealot_big_hit_buffs"),
                                    cb("cbr_zealot_ult_rework"),
                                } },
                                { setting_id = "cbr_wh_bountyhunter_group", type = "group", sub_widgets = {
                                    cb("cbr_bh_passive_melee_kill"),
                                    -- MUTEX cluster member: bh_passive_choice (see career_tweaker.lua mutex.declare).
                                    -- Inlined instead of using cb() to attach the mutex-aware tooltip.
                                    { setting_id = "cbr_bh_passive_perks_rework", type = "checkbox", default_value = false, tooltip = "cbr_bh_passive_perks_rework_tooltip" },
                                    cb("cbr_bh_railgun_delayed_80"),
                                    cb("cbr_bh_row6_talent_6_3_shotgun_cdr"),
                                    cb("cbr_bh_row2_talent_2_2_as_every_3_shots"),
                                    cb("cbr_bh_row5_talent_5_1_party_heal_on_crit"),
                                    cb("cbr_bh_clip_power_rework"),
                                    cb("cbr_bh_row4_talent_4_1_blessed_combat_desc"),
                                    cb("cbr_bh_reload_on_melee_kill"),
                                    cb("cbr_bh_ammo_on_elite_when_empty"),
                                    cb("cbr_bh_stacking_dr_20"),
                                    cb("cbr_bh_row5_talent_5_3_desc"),
                                    cb("cbr_bh_row6_talent_6_1_locked_loaded_buffs"),
                                    cb("cbr_bh_clip_full_fix"),
                                    cb("cbr_bh_railgun_cd_proc"),
                                } },
                                { setting_id = "cbr_wh_priest_group", type = "group", sub_widgets = {
                                    cb("cbr_wp_super_armour_50"),
                                    cb("cbr_wp_monster_damage_buff"),
                                    cb("cbr_wp_row2_talent_2_2_charge_power_rework"),
                                    cb("cbr_wp_row2_talent_2_3_buff_tune"),
                                    cb("cbr_wp_row2_talent_2_3_desc"),
                                    cb("cbr_wp_row5_talent_5_1_cleave_power_20"),
                                    cb("cbr_wp_row5_talent_5_2_as_5"),
                                    cb("cbr_wp_aftershock_hit_force"),
                                    cb("cbr_wp_aftershock_mult_10"),
                                    cb("cbr_wp_activated_noclip"),
                                    cb("cbr_wp_row6_talent_6_1_desc"),
                                    cb("cbr_wp_row6_talent_6_3_heal_window_4"),
                                    cb("cbr_wp_prayer_toggle"),
                                    cb("cbr_wp_attack_speed_on_fury"),
                                    cb("cbr_wp_fury_on_ult"),
                                    cb("cbr_wp_fury_rework"),
                                    cb("cbr_wp_target_action_init"),
                                    cb("cbr_wp_target_buff_list"),
                                    cb("cbr_wp_nuke_enemy_debuff"),
                                    cb("cbr_wp_lightning_explosion_templates"),
                                } },
                            },
                        },
                        -- Sienna (Bright Wizard)
                        {
                            setting_id  = "cbr_bw_group",
                            type        = "group",
                            sub_widgets = {
                                { setting_id = "cbr_bw_adept_group", type = "group", sub_widgets = {
                                    cb("cbr_adept_ult_cooldown_60"),
                                    cb("cbr_adept_passive_zoom"),
                                    cb("cbr_adept_row5_talent_5_2_dr_from_overcharge"),
                                    cb("cbr_adept_ult_rework"),
                                    cb("cbr_adept_burn_damage_100"),
                                    cb("cbr_adept_row2_talent_2_2_burn_damage"),
                                    cb("cbr_adept_tranquility_attack_speed"),
                                    cb("cbr_adept_dr_on_ignite_rework"),
                                    cb("cbr_adept_row5_talent_5_1_dr_on_ignite_desc"),
                                    cb("cbr_adept_row6_talent_6_3_double_firewalk"),
                                } },
                                { setting_id = "cbr_bw_scholar_group", type = "group", sub_widgets = {
                                    cb("cbr_scholar_ult_cooldown_40"),
                                    cb("cbr_scholar_passive_zoom"),
                                    cb("cbr_scholar_row4_talent_4_3_spawn_heads"),
                                    cb("cbr_scholar_attack_speed_10"),
                                    cb("cbr_scholar_row5_talent_5_3_first_hit_and_proj_speed"),
                                } },
                                { setting_id = "cbr_bw_unchained_group", type = "group", sub_widgets = {
                                    cb("cbr_unchained_overcharge_explode_onexit_rewrite"),
                                    cb("cbr_unchained_passive_zoom"),
                                    cb("cbr_unchained_passive_health_to_ult"),
                                    cb("cbr_unchained_passive_overcharge_on_melee_kills"),
                                    cb("cbr_unchained_passive_melee_power_rework"),
                                    cb("cbr_unchained_health_to_cooldown_rewrite"),
                                    cb("cbr_unchained_talent_2_1_flaming_weapons_headshot"),
                                    cb("cbr_unchained_talent_2_2_explode_on_elite_kill"),
                                    cb("cbr_unchained_exploding_burning_enemies_rework"),
                                    cb("cbr_unchained_talent_4_1_attack_speed_high_oc"),
                                    cb("cbr_unchained_talent_4_2_team_burn"),
                                    cb("cbr_unchained_talent_max_health_on_burn_kill"),
                                    cb("cbr_unchained_talent_5_2_overcharged_blocks"),
                                    cb("cbr_unchained_thorn_skin"),
                                    cb("cbr_unchained_talent_4_3_overcharge_decay_and_cd"),
                                    cb("cbr_unchained_talent_5_3_blood_magic_tradeoff"),
                                    cb("cbr_unchained_talent_6_1_cd_reduction"),
                                    cb("cbr_unchained_talent_6_2_fire_aura"),
                                } },
                                { setting_id = "cbr_bw_necromancer_group", type = "group", sub_widgets = {
                                    cb("cbr_necromancer_max_hp_125"),
                                    cb("cbr_necromancer_passive_zoom"),
                                    cb("cbr_necromancer_crit_burst"),
                                    cb("cbr_necromancer_stagger_zero_set"),
                                    cb("cbr_necromancer_talent_2_3_unlimited_crit_cleave"),
                                    cb("cbr_necromancer_talent_2_1_as_per_skeleton"),
                                    cb("cbr_necromancer_talent_2_2_ranged_power"),
                                    cb("cbr_necromancer_talent_4_2_soul_rip_stacks_6"),
                                    cb("cbr_necromancer_talent_4_3_buffed_dot"),
                                    cb("cbr_necromancer_talent_5_1_cd_on_elite_kill"),
                                    cb("cbr_necromancer_talent_5_2_big_hit_protection"),
                                    cb("cbr_necromancer_talent_6_1_extra_skeletons_40s"),
                                    cb("cbr_necromancer_cursed_blood_propagation_10pct"),
                                } },
                            },
                        },
                        -- Cross-character buffs
                        {
                            setting_id  = "cbr_cross_buffs_group",
                            type        = "group",
                            sub_widgets = {
                                cb("cbr_buff_zealot_burning_debuff"),
                                cb("cbr_buff_wp_fury_burn"),
                                cb("cbr_buff_engineer_melee_burn"),
                                cb("cbr_buff_huntsman_defence_debuff"),
                                cb("cbr_buff_wp_lightning_debuff"),
                                cb("cbr_buff_wp_bubble_debuff"),
                                cb("cbr_buff_wp_tome_debuff"),
                                cb("cbr_buff_shield_bash_debuff"),
                                cb("cbr_buff_long_burn_low_damage"),
                                cb("cbr_buff_long_burn_extra_low_damage"),
                                cb("cbr_buff_burning_magma_dot"),
                                cb("cbr_buff_unchained_push_burn"),
                                cb("cbr_buff_infinite_burn_dot_clones"),
                                cb("cbr_buff_warp_lightning_strike_delayed"),
                                cb("cbr_buff_timed_warp_explosion"),
                            },
                        },
                    }
                end)(),
            },
]==]
            -- ============================================================
            -- Talent Reworks
            --
            -- Roster-order exemption: character subgroups follow the vanilla
            -- hero roster (Kruber, Bardin, Kerillian, Saltzpyre, Sienna), not
            -- A-Z; General (cross-career) stays first. Each toggle label names
            -- its career so the player sees which talent it reworks.
            -- ============================================================
            {
                setting_id = "talent_reworks_group",
                type       = "group",
                sub_widgets = {
                    -- Issue #445: live rework-family controls. The masters stay
                    -- in one dedicated nested group instead of being mixed into
                    -- the individual rework rows. These are ordinary checkboxes
                    -- so stock VMF can use them. The first two are exclusive
                    -- family presets; the third explicitly selects both.
                    {
                        setting_id = "rework_master_group",
                        type = "group",
                        sub_widgets = {
                            { setting_id = "rework_master_ensrick", type = "checkbox", default_value = false },
                            { setting_id = "rework_master_tourney", type = "checkbox", default_value = false },
                            { setting_id = "rework_master_all", type = "checkbox", default_value = false },
                        },
                    },
                    -- General (cross-career)
                    {
                        setting_id  = "rework_general_group",
                        type        = "group",
                        sub_widgets = {
                            { setting_id = "rework_general_stagger_thp",         type = "checkbox", default_value = false },
                            { setting_id = "rework_general_thp_kill_minimum",    type = "checkbox", default_value = false },
                            { setting_id = "rework_general_enhanced_power_10pct", type = "checkbox", default_value = false },
                            { setting_id = "rework_general_mainstay_stagger_15pct", type = "checkbox", default_value = false },
                        },
                    },
                    -- Kruber (Markus)
                    {
                        setting_id  = "rework_es_group",
                        type        = "group",
                        sub_widgets = {
                            {
                                setting_id  = "rework_es_huntsman_group",
                                type        = "group",
                                sub_widgets = {
                                    { setting_id = "rework_es_huntsman_crit_aura_unlimited_range", type = "checkbox", default_value = false },
                                    { setting_id = "rework_es_huntsman_base_hp_plus_25",            type = "checkbox", default_value = false },
                                    { setting_id = "rework_es_huntsman_prowl_monster_power",        type = "checkbox", default_value = false },
                                    cb("trn_es_huntsman"),
                                    cb("trn_es_huntsman_crit_aura_range"),
                                    cb("trn_es_huntsman_prowl_reload_speed"),
                                },
                            },
                            {
                                setting_id  = "rework_es_mercenary_group",
                                type        = "group",
                                sub_widgets = {
                                    { setting_id = "rework_es_mercenary_hellborgs_tutelage",            type = "checkbox", default_value = false },
                                    { setting_id = "rework_es_mercenary_blade_barrier_60x_minus_10_on_hit", type = "checkbox", default_value = false },
                                    { setting_id = "rework_es_mercenary_enhanced_training_tiered",      type = "checkbox", default_value = false },
                                    cb("trn_es_mercenary"),
                                    cb("trn_es_mercenary_paced_strikes"),
                                },
                            },
                            {
                                setting_id  = "rework_es_knight_group",
                                type        = "group",
                                sub_widgets = {
                                    { setting_id = "rework_es_knight_innate_uninterruptible_heavies",                 type = "checkbox", default_value = false },
                                    { setting_id = "rework_es_knight_protective_presence_10m_rock_20m",                  type = "checkbox", default_value = false },
                                    { setting_id = "rework_es_knight_rock_shield_offense",                              type = "checkbox", default_value = false },
                                    { setting_id = "rework_es_knight_teamwork_great_weapon_offense",                    type = "checkbox", default_value = false },
                                    { setting_id = "rework_es_knight_final_march",                                      type = "checkbox", default_value = false },
                                    { setting_id = "rework_es_knight_secondary_melee",                                 type = "checkbox", default_value = false },
                                    { setting_id = "rework_es_knight_valiant_charge_great_foes_45s_battering_ram_30s",   type = "checkbox", default_value = false },
                                    { setting_id = "rework_es_knight_counter_punch_stagger_stack",                       type = "checkbox", default_value = false },
                                    cb("trn_es_knight"),
                                    cb("trn_es_knight_protective_presence"),
                                    cb("trn_es_knight_have_at_them_range"),
                                    cb("trn_es_knight_cooldown_on_damage"),
                                    cb("trn_es_knight_elite_stagger_power_duration"),
                                    cb("trn_es_knight_push_attack_speed_duration"),
                                    cb("trn_es_knight_impact_power"),
                                    cb("trn_es_knight_stagger_cooldown_duration"),
                                },
                            },
                            {
                                setting_id  = "rework_es_questingknight_group",
                                type        = "group",
                                sub_widgets = {
                                    { setting_id = "rework_es_questingknight_virtue_of_ideal_3pct_per_kill",        type = "checkbox", default_value = false },
                                    { setting_id = "rework_es_questingknight_virtue_of_discipline_double_parry",    type = "checkbox", default_value = false },
                                    { setting_id = "rework_es_questingknight_virtue_of_impetuous_buffed",           type = "checkbox", default_value = false },
                                    cb("trn_es_questingknight"),
                                    cb("trn_es_questingknight_instant_kill_threshold"),
                                    cb("trn_es_questingknight_kill_move_speed_duration"),
                                    cb("trn_es_questingknight_health_refund"),
                                },
                            },
                        },
                    },
                    -- Bardin
                    {
                        setting_id  = "rework_dr_group",
                        type        = "group",
                        sub_widgets = {
                            {
                                setting_id  = "rework_dr_ranger_group",
                                type        = "group",
                                sub_widgets = {
                                    { setting_id = "rework_dr_ranger_ale_independent_decay", type = "checkbox", default_value = false },
                                    { setting_id = "rework_dr_ranger_ale_one_second_drink", type = "checkbox", default_value = false },
                                    { setting_id = "rework_dr_ranger_attack_speed_5_to_10",  type = "checkbox", default_value = false },
                                    { setting_id = "rework_dr_ranger_base_hp_plus_25",       type = "checkbox", default_value = false },
                                    { setting_id = "rework_dr_ranger_exuberance_stacking_dr", type = "checkbox", default_value = false },
                                    cb("trn_dr_ranger"),
                                    cb("trn_dr_ranger_attack_speed"),
                                    cb("trn_dr_ranger_exuberance_dr"),
                                    cb("trn_dr_ranger_free_grenade_duration"),
                                },
                            },
                            {
                                setting_id = "rework_dr_ironbreaker_group",
                                type = "group",
                                sub_widgets = {
                                    cb("trn_dr_ironbreaker"),
                                    cb("trn_dr_ironbreaker_cooldown_on_damage"),
                                    cb("trn_dr_ironbreaker_gromril_regeneration"),
                                    cb("trn_dr_ironbreaker_gromril_attack_speed"),
                                },
                            },
                            {
                                setting_id  = "rework_dr_slayer_group",
                                type        = "group",
                                sub_widgets = {
                                    { setting_id = "rework_dr_slayer_trophy_hunter_30_stacks_bundle",   type = "checkbox", default_value = false },
                                    { setting_id = "rework_dr_slayer_dawi_drop_buffed",                 type = "checkbox", default_value = false },
                                    { setting_id = "rework_dr_slayer_no_escape_15s",                    type = "checkbox", default_value = false },
                                    { setting_id = "rework_dr_slayer_adrenaline_surge_150pct_nerf",     type = "checkbox", default_value = false },
                                    cb("trn_dr_slayer"),
                                    cb("trn_dr_slayer_dodge_damage_reduction"),
                                },
                            },
                            {
                                setting_id  = "rework_dr_engineer_group",
                                type        = "group",
                                sub_widgets = {
                                    { setting_id = "rework_dr_engineer_ingenious_ordnance_240s",       type = "checkbox", default_value = false },
                                    { setting_id = "rework_dr_engineer_full_head_of_steam_4pct",       type = "checkbox", default_value = false },
                                    { setting_id = "rework_dr_engineer_gromril_plated_shot_full_speed", type = "checkbox", default_value = false },
                                    { setting_id = "rework_dr_engineer_leading_shots",                 type = "checkbox", default_value = false, tooltip = "rework_dr_engineer_leading_shots_description" },
                                },
                            },
                        },
                    },
                    -- Kerillian
                    {
                        setting_id  = "rework_we_group",
                        type        = "group",
                        sub_widgets = {
                            {
                                setting_id  = "rework_we_maidenguard_group",
                                type        = "group",
                                sub_widgets = {
                                    { setting_id = "rework_we_maidenguard_crit_chance_5_to_10", type = "checkbox", default_value = false },
                                    { setting_id = "rework_we_maidenguard_focused_spirit_stacks", type = "checkbox", default_value = false },
                                    { setting_id = "rework_we_maidenguard_dance_of_blades", type = "checkbox", default_value = false },
                                    cb("trn_we_maidenguard"),
                                    cb("trn_we_maidenguard_stamina_aura_range"),
                                    cb("trn_we_maidenguard_focused_spirit_cooldown"),
                                    cb("trn_we_maidenguard_push_block_stacks"),
                                    cb("trn_we_maidenguard_power_on_dodge"),
                                    cb("trn_we_maidenguard_max_health"),
                                    cb("trn_we_maidenguard_max_ammo"),
                                },
                            },
                            {
                                setting_id  = "rework_we_shade_group",
                                type        = "group",
                                sub_widgets = {
                                    { setting_id = "rework_we_shade_hungry_wind_buffed", type = "checkbox", default_value = false },
                                    cb("trn_we_shade"),
                                    cb("trn_we_shade_infiltrate_duration"),
                                    cb("trn_we_shade_stealth_parry"),
                                    cb("trn_we_shade_critical_damage"),
                                },
                            },
                            {
                                setting_id  = "rework_we_waywatcher_group",
                                type        = "group",
                                sub_widgets = {
                                    { setting_id = "rework_we_waywatcher_drakiras_alacrity_passive_as", type = "checkbox", default_value = false },
                                    { setting_id = "rework_we_waywatcher_fervent_huntress_passive_ms",  type = "checkbox", default_value = false },
                                    { setting_id = "rework_we_waywatcher_kurnous_reward_5pct",          type = "checkbox", default_value = false },
                                    { setting_id = "rework_we_waywatcher_ricochet_no_ff_5_bounces",     type = "checkbox", default_value = false },
                                    { setting_id = "rework_we_waywatcher_serrated_shots_all_arrows",    type = "checkbox", default_value = false },
                                    cb("trn_we_waywatcher"),
                                    cb("trn_we_waywatcher_headshot_attack_speed"),
                                },
                            },
                            {
                                setting_id = "rework_we_thornsister_group",
                                type = "group",
                                sub_widgets = {
                                    cb("trn_we_thornsister"),
                                    cb("trn_we_thornsister_team_aura_duration"),
                                    cb("trn_we_thornsister_thp_funnel"),
                                },
                            },
                        },
                    },
                    -- Saltzpyre (Victor)
                    {
                        setting_id  = "rework_wh_group",
                        type        = "group",
                        sub_widgets = {
                            {
                                setting_id  = "rework_wh_zealot_group",
                                type        = "group",
                                sub_widgets = {
                                    { setting_id = "rework_wh_zealot_smite_random_crits",                     type = "checkbox", default_value = false },
                                    { setting_id = "rework_wh_zealot_power_5_to_10",                          type = "checkbox", default_value = false },
                                    { setting_id = "rework_wh_zealot_feel_nothing_refresh",                   type = "checkbox", default_value = false },
                                    { setting_id = "rework_wh_zealot_ability_green_to_thp",                   type = "checkbox", default_value = false },
                                    { setting_id = "rework_wh_zealot_fiery_faith_1pct_per_5_hp_max_30",       type = "checkbox", default_value = false },
                                    { setting_id = "rework_wh_zealot_castigate_4pct_as_per_fiery_faith",      type = "checkbox", default_value = false },
                                    { setting_id = "rework_wh_zealot_holy_fortitude_30_max_hp",               type = "checkbox", default_value = false },
                                    { setting_id = "rework_wh_zealot_flagellation",                            type = "checkbox", default_value = false },
                                    cb("trn_wh_zealot"),
                                    cb("trn_wh_zealot_melee_power"),
                                },
                            },
                            {
                                setting_id  = "rework_wh_bountyhunter_group",
                                type        = "group",
                                sub_widgets = {
                                    { setting_id = "rework_wh_bountyhunter_double_shotted_80",                            type = "checkbox", default_value = false },
                                    { setting_id = "rework_wh_bountyhunter_double_shotted_damage_double",                 type = "checkbox", default_value = false },
                                    { setting_id = "rework_wh_bountyhunter_blessed_combat_25_and_passive_melee_reset",    type = "checkbox", default_value = false },
                                    { setting_id = "rework_wh_bountyhunter_rile_the_mob_movement",                        type = "checkbox", default_value = false },
                                    { setting_id = "rework_wh_bountyhunter_salvaged_ammo_no_gate_and_passive_reload",     type = "checkbox", default_value = false },
                                    { setting_id = "rework_wh_bountyhunter_job_well_done_passive_and_special_kill_dr",    type = "checkbox", default_value = false, tooltip = "rework_wh_bountyhunter_job_well_done_passive_and_special_kill_dr_tooltip" },
                                    { setting_id = "rework_wh_bountyhunter_just_reward_5s_cooldown",                      type = "checkbox", default_value = false },
                                    { setting_id = "rework_wh_bountyhunter_indiscriminate_blast_refund_per_kill",         type = "checkbox", default_value = false },
                                    cb("trn_wh_bountyhunter"),
                                    cb("trn_wh_bountyhunter_double_shotted_refund"),
                                    cb("trn_wh_bountyhunter_job_well_done_stacks"),
                                    cb("trn_wh_bountyhunter_just_reward_cooldown"),
                                    cb("trn_wh_bountyhunter_blessed_kill"),
                                },
                            },
                            {
                                setting_id  = "rework_wh_captain_group",
                                type        = "group",
                                sub_widgets = {
                                    { setting_id = "rework_wh_captain_parry_window", type = "checkbox", default_value = false },
                                },
                            },
                            {
                                setting_id  = "rework_wh_priest_group",
                                type        = "group",
                                sub_widgets = {
                                    { setting_id = "rework_wh_priest_shield_of_faith_10s_110s_cd_plus_unyielding_20s", type = "checkbox", default_value = false },
                                    { setting_id = "rework_wh_priest_prayer_of_vengeance_self_40_others_20",            type = "checkbox", default_value = false },
                                    cb("trn_wh_priest"),
                                    cb("trn_wh_priest_prayer_movement_speed"),
                                },
                            },
                        },
                    },
                    -- Sienna (Bright Wizard)
                    {
                        setting_id  = "rework_bw_group",
                        type        = "group",
                        sub_widgets = {
                            {
                                setting_id  = "rework_bw_adept_group",
                                type        = "group",
                                sub_widgets = {
                                    { setting_id = "rework_bw_adept_famished_flames_buffed",            type = "checkbox", default_value = false },
                                    { setting_id = "rework_bw_adept_volcanic_force_doubled",            type = "checkbox", default_value = false },
                                    { setting_id = "rework_bw_adept_fires_from_ash_1pct_plus_thp",      type = "checkbox", default_value = false },
                                    cb("trn_bw_adept"),
                                    cb("trn_bw_adept_famished_flames"),
                                    cb("trn_bw_adept_ignite_damage_reduction"),
                                    cb("trn_bw_adept_fires_from_ash"),
                                    cb("trn_bw_adept_burning_vigour"),
                                },
                            },
                            {
                                setting_id  = "rework_bw_necromancer_group",
                                type        = "group",
                                sub_widgets = {
                                    { setting_id = "rework_bw_necromancer_lost_souls_double_radius",   type = "checkbox", default_value = false },
                                    { setting_id = "rework_bw_necromancer_withering_touch_30s",        type = "checkbox", default_value = false },
                                    { setting_id = "rework_bw_necromancer_malediction_5_souls",        type = "checkbox", default_value = false },
                                    { setting_id = "rework_bw_necromancer_vanhels_per_skeleton_as",    type = "checkbox", default_value = false },
                                    { setting_id = "rework_bw_necromancer_death_ascendant_10s",        type = "checkbox", default_value = false },
                                    { setting_id = "rework_bw_necromancer_army_of_dead_buffed",        type = "checkbox", default_value = false },
                                    cb("trn_bw_necromancer"),
                                    cb("trn_bw_necromancer_spell_cast_ranged_power"),
                                    cb("trn_bw_necromancer_critical_cleave"),
                                    cb("trn_bw_necromancer_cursed_blood"),
                                },
                            },
                            {
                                setting_id = "rework_bw_scholar_group",
                                type = "group",
                                sub_widgets = {
                                    cb("trn_bw_scholar"),
                                    cb("trn_bw_scholar_martial_study"),
                                },
                            },
                            {
                                setting_id  = "rework_bw_unchained_group",
                                type        = "group",
                                sub_widgets = {
                                    { setting_id = "rework_bw_unchained_unstable_strength_rescale",                  type = "checkbox", default_value = false },
                                    { setting_id = "rework_bw_unchained_unstable_strength_dot",                      type = "checkbox", default_value = false },
                                    { setting_id = "rework_bw_unchained_natural_talent_ranged",                     type = "checkbox", default_value = false },
                                    { setting_id = "rework_bw_unchained_numb_to_pain_4x_burn_kill_lose_on_hit",      type = "checkbox", default_value = false },
                                    { setting_id = "rework_bw_unchained_abandon_innate_flame_unending",             type = "checkbox", default_value = false },
                                    { setting_id = "rework_bw_unchained_chain_reaction_ignite",                      type = "checkbox", default_value = false },
                                    { setting_id = "rework_bw_unchained_fuel_for_the_fire_vent",                     type = "checkbox", default_value = false },
                                    { setting_id = "rework_bw_unchained_career_skill_max_us",                        type = "checkbox", default_value = false },
                                    { setting_id = "rework_bw_unchained_wildfire_burst_and_radius",                  type = "checkbox", default_value = false },
                                },
                            },
                        },
                    },
                },
            },
        },
    },
}
