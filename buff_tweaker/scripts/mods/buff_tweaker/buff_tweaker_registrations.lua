--[[
buff_tweaker_registrations.lua
================================================

Canonical pre-registration list for Core's Big Rebalance.

This file ships byte-identical (modulo the `get_mod(...)` line) in
wt / ct / et. Per `feedback_vt2_gated_registration_diverges`, every
peer who has the BR master toggle on registers the SAME names in the
SAME alphabetical order — so NetworkLookup indices for buffs / damage
profiles / explosions match across peers regardless of which mods are
installed or which sub-toggles are flipped.

Source: hand-extracted from `_big_rebalance_extract/source/*.lua`
(decompiled Workshop ID 2705276978). SpicyEnemies content excluded
per user decision.

Four sub-tables, each alphabetically sorted:
  BR_BUFF_TEMPLATES       — 272 entries. Plain entries (no hero) come
                            from `mod.add_buff_template(...)` calls;
                            talent entries (with hero) come from
                            `mod.add_talent_buff_template(hero, ...)`.
                            Both write to BuffTemplates +
                            NetworkLookup.buff_templates; talent
                            entries additionally write to
                            TalentBuffTemplates[hero].
  BR_DAMAGE_PROFILES      — 37 entries. NewDamageProfileTemplates.*
                            (engine appends each to
                            NetworkLookup.damage_profiles at boot
                            in source; we replicate via apply loop).
  BR_EXPLOSION_TEMPLATES  — 16 entries. NewExplosionTemplates.* (same
                            pattern — appended to
                            NetworkLookup.explosion_templates).
  BR_STAT_BUFF_METHODS    — 3 entries. StatBuffApplicationMethods.*
                            registered as "stacking_multiplier". Does
                            NOT enter NetworkLookup but listed for
                            symmetry across mods so peers register
                            identical StatBuff method names.

The order of entries within each sub-table is LOAD-BEARING. Do not
reorder without bumping every mod's version simultaneously.
]]

local mod = get_mod("bt")

local M = {}

-- ============================================================
-- BR_BUFF_TEMPLATES: 272 entries, alphabetical by name
-- ============================================================
-- Plain entries (no hero) come from `mod.add_buff_template`
-- in thp_stagger / weapon / sienna / victor / kerillian / etc.
-- Talent entries come from `mod.add_talent_buff_template`
-- in the character_changes files.

M.BR_BUFF_TEMPLATES = {
    { name = "1_grenade_start",                                                    hero = "dwarf_ranger" },
    { name = "aoe_heavy_poison_dot"                                                },
    { name = "attack_debuff_enemies_shield_bash"                                   },
    { name = "attack_debuff_enemies_warrior_priest_bubble"                         },
    { name = "banner_attack_speed",                                                hero = "wood_elf" },
    { name = "banner_attack_speed_buff",                                           hero = "wood_elf" },
    { name = "banner_attack_speed_buff_large",                                     hero = "wood_elf" },
    { name = "banner_attack_speed_large",                                          hero = "wood_elf" },
    { name = "bardin_engineer_ability_buff",                                       hero = "dwarf_ranger" },
    { name = "bardin_engineer_ability_check",                                      hero = "dwarf_ranger" },
    { name = "bardin_engineer_clip_size",                                          hero = "dwarf_ranger" },
    { name = "bardin_engineer_clip_size_ability_check",                            hero = "dwarf_ranger" },
    { name = "bardin_engineer_clip_size_buff",                                     hero = "dwarf_ranger" },
    { name = "bardin_engineer_clip_size_debuff",                                   hero = "dwarf_ranger" },
    { name = "bardin_engineer_crank_gun_debuff",                                   hero = "dwarf_ranger" },
    { name = "bardin_engineer_melee_attack_speed_buff",                            hero = "dwarf_ranger" },
    { name = "bardin_engineer_pump_buff_display",                                  hero = "dwarf_ranger" },
    { name = "bardin_ironbreaker_gromril_delay_long",                              hero = "dwarf_ranger" },
    { name = "bardin_ranger_activated_ability_stealth_outside_of_smoke_pierce",    hero = "dwarf_ranger" },
    { name = "bardin_ranger_increased_ult_cooldown",                               hero = "dwarf_ranger" },
    { name = "bardin_slayer_activated_ability_exhausted",                          hero = "dwarf_ranger" },
    { name = "bardin_slayer_activated_ability_max",                                hero = "dwarf_ranger" },
    { name = "burning_1W_dot_unchained_push"                                       },
    { name = "burning_1W_dot_unchained_team_burn"                                  },
    { name = "burning_dot_fire_grenade"                                            },
    { name = "burning_dot_weak_bomb"                                               },
    { name = "burning_magma_dot"                                                   },
    { name = "defence_debuff_enemies_huntsman_explosion"                           },
    { name = "defence_debuff_enemies_warrior_priest_lightning"                     },
    { name = "defence_debuff_enemies_warrior_priest_tome"                          },
    { name = "engineer_melee_explosion_burn"                                       },
    { name = "falling_stacks",                                                     hero = "dwarf_ranger" },
    { name = "falling_stacks_engineer",                                            hero = "dwarf_ranger" },
    { name = "faster_bows",                                                        hero = "wood_elf" },
    { name = "friend_protection",                                                  hero = "empire_soldier" },
    { name = "friend_protection_buff",                                             hero = "empire_soldier" },
    { name = "gs_activate_buff_stacks_based_on_health_percentage",                 hero = "wood_elf" },
    { name = "gs_add_overcharge_on_melee_kills",                                   hero = "bright_wizard" },
    { name = "gs_ammo_on_melee_kills_throwing_axes_buff",                          hero = "dwarf_ranger" },
    { name = "gs_attack_speed_on_empty_clip",                                      hero = "dwarf_ranger" },
    { name = "gs_attack_speed_on_empty_clip_buff",                                 hero = "dwarf_ranger" },
    { name = "gs_bardin_engineer_crit_chance",                                     hero = "dwarf_ranger" },
    { name = "gs_bardin_engineer_passive_heavy_explosion",                         hero = "dwarf_ranger" },
    { name = "gs_bardin_slayer_crit_chance",                                       hero = "dwarf_ranger" },
    { name = "gs_bardin_slayer_crit_chance_2",                                     hero = "dwarf_ranger" },
    { name = "gs_bardin_slayer_crit_chance_buff",                                  hero = "dwarf_ranger" },
    { name = "gs_bardin_slayer_crit_chance_buff_2",                                hero = "dwarf_ranger" },
    { name = "gs_bardin_slayer_double_ability",                                    hero = "dwarf_ranger" },
    { name = "gs_bardin_slayer_double_ability_remove",                             hero = "dwarf_ranger" },
    { name = "gs_bardin_slayer_dr_scaling",                                        hero = "dwarf_ranger" },
    { name = "gs_bardin_slayer_dr_scaling_buff",                                   hero = "dwarf_ranger" },
    { name = "gs_bardin_slayer_increased_defence",                                 hero = "dwarf_ranger" },
    { name = "gs_bardin_slayer_passive_cooldown_reduction",                        hero = "dwarf_ranger" },
    { name = "gs_bardin_slayer_passive_cooldown_reduction_extra",                  hero = "dwarf_ranger" },
    { name = "gs_bardin_slayer_passive_dodge_range",                               hero = "dwarf_ranger" },
    { name = "gs_bardin_slayer_passive_dodge_range_extra",                         hero = "dwarf_ranger" },
    { name = "gs_bardin_slayer_passive_dodge_speed",                               hero = "dwarf_ranger" },
    { name = "gs_bardin_slayer_passive_dodge_speed_extra",                         hero = "dwarf_ranger" },
    { name = "gs_bardin_slayer_passive_increased_max_stacks",                      hero = "dwarf_ranger" },
    { name = "gs_bardin_slayer_passive_movement_speed_extra",                      hero = "dwarf_ranger" },
    { name = "gs_bardin_slayer_passive_stacking_crit_buff",                        hero = "dwarf_ranger" },
    { name = "gs_bardin_slayer_passive_stacking_crit_buff_extra",                  hero = "dwarf_ranger" },
    { name = "gs_bounty_hunter_clip_size_buff",                                    hero = "witch_hunter" },
    { name = "gs_bounty_hunter_ranged_crit_buff",                                  hero = "witch_hunter" },
    { name = "gs_burning_enemies_on_headshot",                                     hero = "bright_wizard" },
    { name = "gs_burning_enemies_on_headshot_buff",                                hero = "bright_wizard" },
    { name = "gs_burning_enemies_on_headshot_counter",                             hero = "bright_wizard" },
    { name = "gs_bush_decal"                                                       },
    { name = "gs_dash_ult_toggle",                                                 hero = "wood_elf" },
    { name = "gs_dash_ult_toggle_function",                                        hero = "wood_elf" },
    { name = "gs_deus_rally_flag_aoe_buff"                                         },
    { name = "gs_deus_rally_flag_aoe_buff_aoe_protection"                          },
    { name = "gs_deus_rally_flag_aoe_buff_effect"                                  },
    { name = "gs_deus_rally_flag_aoe_buff_grabber_protection"                      },
    { name = "gs_deus_rally_flag_aoe_buff_grabber_protection_buff"                 },
    { name = "gs_deus_rally_flag_aoe_buff_grabber_protection_buff_dash"            },
    { name = "gs_deus_rally_flag_aoe_buff_heal"                                    },
    { name = "gs_deus_rally_flag_aoe_buff_heal_large"                              },
    { name = "gs_deus_rally_flag_aoe_buff_large"                                   },
    { name = "gs_deus_rally_flag_aoe_buff_remover"                                 },
    { name = "gs_deus_rally_flag_aoe_buff_remover_long"                            },
    { name = "gs_deus_rally_flag_aoe_buff_wraith"                                  },
    { name = "gs_deus_rally_flag_aoe_buff_wraith_1"                                },
    { name = "gs_deus_rally_flag_buff"                                             },
    { name = "gs_deus_rally_flag_buff_dash"                                        },
    { name = "gs_deus_rally_flag_buff_large"                                       },
    { name = "gs_deus_rally_flag_buff_large_dash"                                  },
    { name = "gs_deus_rally_flag_buff_long_dash"                                   },
    { name = "gs_deus_rally_flag_buff_protection"                                  },
    { name = "gs_deus_rally_flag_buff_protection_dash"                             },
    { name = "gs_deus_rally_flag_buff_protection_duration"                         },
    { name = "gs_deus_rally_flag_buff_protection_duration_long"                    },
    { name = "gs_deus_rally_flag_buff_protection_ranged"                           },
    { name = "gs_deus_rally_flag_buff_protection_ranged_buff"                      },
    { name = "gs_deus_rally_flag_buff_protection_ranged_buff_dash"                 },
    { name = "gs_deus_rally_flag_heal_buff"                                        },
    { name = "gs_deus_rally_flag_heal_buff_dash"                                   },
    { name = "gs_deus_rally_flag_heal_buff_large"                                  },
    { name = "gs_deus_rally_flag_heal_buff_large_dash"                             },
    { name = "gs_deus_rally_flag_heal_buff_long_dash"                              },
    { name = "gs_deus_reckless_swings",                                            hero = "witch_hunter" },
    { name = "gs_deus_reckless_swings_extra",                                      hero = "witch_hunter" },
    { name = "gs_display_buff_fk_heavies",                                         hero = "empire_soldier" },
    { name = "gs_display_buff_unchained_flaming_weapons",                          hero = "empire_soldier" },
    { name = "gs_display_buff_way_ammo",                                           hero = "empire_soldier" },
    { name = "gs_dr_sniper_buff_1",                                                hero = "dwarf_ranger" },
    { name = "gs_dr_sniper_buff_2",                                                hero = "dwarf_ranger" },
    { name = "gs_dr_sniper_buff_3",                                                hero = "dwarf_ranger" },
    { name = "gs_dr_sniper_buff_4",                                                hero = "dwarf_ranger" },
    { name = "gs_drain_bush"                                                       },
    { name = "gs_drain_bush_dot"                                                   },
    { name = "gs_drain_bush_mark"                                                  },
    { name = "gs_drain_bush_marked"                                                },
    { name = "gs_drain_bush_regen_buff",                                           hero = "wood_elf" },
    { name = "gs_exploding_enemies_on_kill",                                       hero = "bright_wizard" },
    { name = "gs_exploding_enemies_on_kill_buff",                                  hero = "bright_wizard" },
    { name = "gs_extra_crit",                                                      hero = "wood_elf" },
    { name = "gs_extra_crit_2_2",                                                  hero = "empire_soldier" },
    { name = "gs_fk_piston",                                                       hero = "empire_soldier" },
    { name = "gs_fk_piston_power",                                                 hero = "empire_soldier" },
    { name = "gs_haste",                                                           hero = "empire_soldier" },
    { name = "gs_haste_buff",                                                      hero = "empire_soldier" },
    { name = "gs_ib_decreased_heat_cost",                                          hero = "dwarf_ranger" },
    { name = "gs_ib_increased_drakefire_speed",                                    hero = "dwarf_ranger" },
    { name = "gs_increased_dupe_bomb",                                             hero = "dwarf_ranger" },
    { name = "gs_increased_dupe_healing",                                          hero = "dwarf_ranger" },
    { name = "gs_increased_dupe_potion",                                           hero = "dwarf_ranger" },
    { name = "gs_increased_headshot_damage_waywatcher",                            hero = "wood_elf" },
    { name = "gs_infinite_wounds",                                                 hero = "witch_hunter" },
    { name = "gs_kerillian_maidenguard_crit_chance_allies",                        hero = "wood_elf" },
    { name = "gs_kerillian_maidenguard_crit_chance_allies_buff",                   hero = "wood_elf" },
    { name = "gs_kerillian_maidenguard_passive_dr_on_dodge",                       hero = "wood_elf" },
    { name = "gs_kerillian_maidenguard_passive_dr_on_dodge_buff",                  hero = "wood_elf" },
    { name = "gs_markus_cooldown_reduction",                                       hero = "empire_soldier" },
    { name = "gs_markus_huntsman_activated_ability",                               hero = "empire_soldier" },
    { name = "gs_markus_huntsman_activated_ability_extra_penetration",             hero = "empire_soldier" },
    { name = "gs_markus_huntsman_activated_ability_extra_penetration_big",         hero = "empire_soldier" },
    { name = "gs_markus_huntsman_activated_ability_extra_penetration_buff",        hero = "empire_soldier" },
    { name = "gs_markus_huntsman_activated_ability_extra_penetration_buff_big",    hero = "empire_soldier" },
    { name = "gs_markus_huntsman_activated_ability_remover",                       hero = "empire_soldier" },
    { name = "gs_markus_mercenary_activated_ability_revive",                       hero = "empire_soldier" },
    { name = "gs_markus_mercenary_activated_ability_revive_buff",                  hero = "empire_soldier" },
    { name = "gs_markus_mercenary_delayed_heal",                                   hero = "empire_soldier" },
    { name = "gs_markus_questing_knight_first_target_increase",                    hero = "empire_soldier" },
    { name = "gs_merc_ammo_on_melee_kills",                                        hero = "empire_soldier" },
    { name = "gs_poison_explosion_on_special",                                     hero = "wood_elf" },
    { name = "gs_poison_explosion_on_special_buff",                                hero = "wood_elf" },
    { name = "gs_priest_prayer_toggle_function",                                   hero = "witch_hunter" },
    { name = "gs_regen_drain_bush",                                                hero = "wood_elf" },
    { name = "gs_sienna_flaming_weapons_to_allies",                                hero = "empire_soldier" },
    { name = "gs_sienna_flaming_weapons_to_allies_buff",                           hero = "bright_wizard" },
    { name = "gs_sienna_unchained_increase_max_health_on_kill",                    hero = "bright_wizard" },
    { name = "gs_sienna_unchained_increase_max_health_on_kill_buff",               hero = "bright_wizard" },
    { name = "gs_sienna_unchained_reduced_cd",                                     hero = "bright_wizard" },
    { name = "gs_sniper_buff_1",                                                   hero = "empire_soldier" },
    { name = "gs_sniper_buff_2",                                                   hero = "empire_soldier" },
    { name = "gs_sniper_buff_3",                                                   hero = "empire_soldier" },
    { name = "gs_sniper_buff_4",                                                   hero = "empire_soldier" },
    { name = "gs_victor_attack_speed_on_hit",                                      hero = "witch_hunter" },
    { name = "gs_victor_attack_speed_on_hit_buff",                                 hero = "witch_hunter" },
    { name = "gs_victor_bounty_heal_on_crit_hs_buff",                              hero = "witch_hunter" },
    { name = "gs_victor_bounty_heal_on_crit_hs_buff_removal",                      hero = "witch_hunter" },
    { name = "gs_victor_bounty_heal_on_crit_hs_delay",                             hero = "witch_hunter" },
    { name = "gs_victor_bounty_hunter_buff_on_locked_and_loaded",                  hero = "witch_hunter" },
    { name = "gs_victor_bounty_melee_on_ranged",                                   hero = "witch_hunter" },
    { name = "gs_victor_bounty_melee_on_ranged_buff",                              hero = "witch_hunter" },
    { name = "gs_victor_bounty_melee_on_ranged_counter",                           hero = "witch_hunter" },
    { name = "gs_victor_cleave_power_on_hit",                                      hero = "witch_hunter" },
    { name = "gs_victor_cleave_power_on_hit_buff",                                 hero = "witch_hunter" },
    { name = "gs_victor_power_on_hit",                                             hero = "witch_hunter" },
    { name = "gs_victor_power_on_hit_buff",                                        hero = "witch_hunter" },
    { name = "gs_victor_zealot_attack_speed_1",                                    hero = "witch_hunter" },
    { name = "gs_victor_zealot_attack_speed_2",                                    hero = "witch_hunter" },
    { name = "gs_victor_zealot_attack_speed_3",                                    hero = "witch_hunter" },
    { name = "gs_victor_zealot_attack_speed_buff_1",                               hero = "witch_hunter" },
    { name = "gs_victor_zealot_attack_speed_buff_2",                               hero = "witch_hunter" },
    { name = "gs_victor_zealot_attack_speed_buff_3",                               hero = "witch_hunter" },
    { name = "gs_victor_zealot_attack_speed_high_buff",                            hero = "witch_hunter" },
    { name = "gs_victor_zealot_attack_speed_high_health",                          hero = "witch_hunter" },
    { name = "gs_victor_zealot_attack_speed_scaling",                              hero = "witch_hunter" },
    { name = "gs_victor_zealot_attack_speed_scaling_buff",                         hero = "witch_hunter" },
    { name = "gs_victor_zealot_damage_on_hit",                                     hero = "witch_hunter" },
    { name = "gs_victor_zealot_damage_on_hit_buff",                                hero = "witch_hunter" },
    { name = "gs_victor_zealot_dr",                                                hero = "witch_hunter" },
    { name = "gs_victor_zealot_dr_buff",                                           hero = "witch_hunter" },
    { name = "gs_victor_zealot_health_increase",                                   hero = "witch_hunter" },
    { name = "gs_victor_zealot_health_increase_buff",                              hero = "witch_hunter" },
    { name = "gs_victor_zealot_increased_damage_to_first_target",                  hero = "witch_hunter" },
    { name = "gs_way_ammo_on_melee_kills",                                         hero = "wood_elf" },
    { name = "gs_whc_ammo_on_melee_kills",                                         hero = "witch_hunter" },
    { name = "gs_whc_power",                                                       hero = "witch_hunter" },
    { name = "gs_whc_power_buff",                                                  hero = "witch_hunter" },
    { name = "guaranteed_ranged_crit_huntsman",                                    hero = "empire_soldier" },
    { name = "guaranteed_ranged_crit_huntsman_buff",                               hero = "empire_soldier" },
    { name = "increased_dr_from_overcharge",                                       hero = "bright_wizard" },
    { name = "increased_dr_from_overcharge_buff",                                  hero = "bright_wizard" },
    { name = "kerillian_maidenguard_moonbow_damage",                               hero = "wood_elf" },
    { name = "kerillian_maidenguard_moonbow_speed",                                hero = "wood_elf" },
    { name = "kerillian_shade_passive_stealth_parry_buff",                         hero = "wood_elf" },
    { name = "kerillian_shade_passive_stealth_parry_buff_remover",                 hero = "wood_elf" },
    { name = "kerillian_thorn_sister_passive_temp_health_funnel_aura",             hero = "wood_elf" },
    { name = "long_burn_extra_low_damage"                                          },
    { name = "long_burn_low_damage"                                                },
    { name = "markus_huntsman_bleed_on_hit",                                       hero = "empire_soldier" },
    { name = "markus_huntsman_damage_taken_on_elite_or_special_kill",              hero = "empire_soldier" },
    { name = "markus_huntsman_damage_taken_on_elite_or_special_kill_buff",         hero = "empire_soldier" },
    { name = "markus_huntsman_reload_passive",                                     hero = "empire_soldier" },
    { name = "markus_knight_cooldown_on_incapacitated_allies_buff",                hero = "empire_soldier" },
    { name = "markus_knight_cooldown_on_incapacitated_allies_cooldown",            hero = "empire_soldier" },
    { name = "markus_knight_heavy_buff",                                           hero = "empire_soldier" },
    { name = "markus_knight_piston_powered_ready",                                 hero = "empire_soldier" },
    { name = "markus_mercenary_activated_ability_damage_reduction_revive",         hero = "empire_soldier" },
    { name = "monster_limiter",                                                    hero = "empire_soldier" },
    { name = "monster_limiter_buff",                                               hero = "empire_soldier" },
    { name = "necro_big_hit_protection",                                           hero = "bright_wizard" },
    { name = "no_ammo_consumed",                                                   hero = "empire_soldier" },
    { name = "no_proc_necro",                                                      hero = "bright_wizard" },
    { name = "rebaltourn_bloodlust"                                                },
    { name = "rebaltourn_finesse_unbalance"                                        },
    { name = "rebaltourn_power_level_unbalance"                                    },
    { name = "rebaltourn_reaper"                                                   },
    { name = "rebaltourn_regrowth"                                                 },
    { name = "rebaltourn_smiter_unbalance"                                         },
    { name = "rebaltourn_tank_unbalance"                                           },
    { name = "rebaltourn_tank_unbalance_buff"                                      },
    { name = "rebaltourn_vanguard"                                                 },
    { name = "sienna_adept_ability_trail"                                          },
    { name = "sienna_adept_increased_ult_cooldown",                                hero = "bright_wizard" },
    { name = "sienna_necromancer_4_3_dot_buffed"                                   },
    { name = "sienna_scholar_first_hit_damage",                                    hero = "bright_wizard" },
    { name = "sienna_scholar_increased_projectile_speed",                          hero = "bright_wizard" },
    { name = "sienna_scholar_spawn_heads",                                         hero = "bright_wizard" },
    { name = "sienna_unchained_increased_health",                                  hero = "bright_wizard" },
    { name = "sienna_unchained_increased_ult_cooldown",                            hero = "bright_wizard" },
    { name = "sienna_unchained_reduced_overcharge",                                hero = "bright_wizard" },
    { name = "sienna_unchained_reduced_overcharge_decay",                          hero = "bright_wizard" },
    { name = "sienna_unchained_thorn_skin",                                        hero = "bright_wizard" },
    { name = "sienna_unchained_ult_cooldown_on_overcharge",                        hero = "bright_wizard" },
    { name = "thorn_sister_vent_nerf",                                             hero = "wood_elf" },
    { name = "victor_bountyhunter_activated_ability_blast_shotgun_cdr",            hero = "witch_hunter" },
    { name = "victor_priest_activated_noclip"                                      },
    { name = "victor_priest_fury_on_ult",                                          hero = "witch_hunter" },
    { name = "victor_priest_monster_damage",                                       hero = "witch_hunter" },
    { name = "victor_priest_prayer_1",                                             hero = "witch_hunter" },
    { name = "victor_priest_prayer_1_cooldown",                                    hero = "witch_hunter" },
    { name = "victor_priest_prayer_1_cooldown_short",                              hero = "witch_hunter" },
    { name = "victor_priest_prayer_2",                                             hero = "witch_hunter" },
    { name = "victor_priest_prayer_2_cooldown",                                    hero = "witch_hunter" },
    { name = "victor_priest_prayer_2_cooldown_short",                              hero = "witch_hunter" },
    { name = "victor_priest_prayer_3",                                             hero = "witch_hunter" },
    { name = "victor_priest_prayer_3_cooldown",                                    hero = "witch_hunter" },
    { name = "victor_priest_prayer_3_cooldown_short",                              hero = "witch_hunter" },
    { name = "victor_priest_prayer_attack_speed",                                  hero = "witch_hunter" },
    { name = "victor_priest_prayer_dr",                                            hero = "witch_hunter" },
    { name = "victor_priest_prayer_global_cooldown",                               hero = "witch_hunter" },
    { name = "victor_priest_prayer_global_cooldown_short",                         hero = "witch_hunter" },
    { name = "victor_witchhunter_activated_ability_crit_self_buff",                hero = "witch_hunter" },
    { name = "victor_witchhunter_activated_ability_mute_ping",                     hero = "witch_hunter" },
    { name = "victor_witchhunter_activated_ability_refund_cooldown_on_enemies_hit_tag", hero = "witch_hunter" },
    { name = "victor_zealot_invulnerability_cooldown_short",                       hero = "witch_hunter" },
    { name = "warrior_priest_fury_burn"                                            },
    { name = "wh_priest_attack_speed_on_fury_buff",                                hero = "witch_hunter" },
    { name = "zealot_big_hit",                                                     hero = "witch_hunter" },
    { name = "zealot_big_hit_buff",                                                hero = "witch_hunter" },
    { name = "zealot_big_hit_buff_removal",                                        hero = "witch_hunter" },
    { name = "zealot_buff_on_damage_buff",                                         hero = "witch_hunter" },
    { name = "zealot_burning_debuff"                                               },
    { name = "zealot_omni_buff",                                                   hero = "witch_hunter" },
    { name = "zealot_omni_buff_1",                                                 hero = "witch_hunter" },
    { name = "zealot_omni_buff_2",                                                 hero = "witch_hunter" },
    { name = "zealot_omni_buff_3",                                                 hero = "witch_hunter" },
    { name = "zealot_omni_buff_4",                                                 hero = "witch_hunter" },
}

-- ============================================================
-- BR_DAMAGE_PROFILES: 37 entries, alphabetical
-- ============================================================
-- Sourced from `NewDamageProfileTemplates.<name> =` assignments
-- in weapon_changes.lua + sienna_changes.lua. The engine appends
-- each to NetworkLookup.damage_profiles at boot.

M.BR_DAMAGE_PROFILES = {
    "beam_blast",
    "blunder_action_three",
    "burning_dot_weak_bomb",
    "dot_low_damage",
    "dot_low_low_damage",
    "dummy",
    "falchion_heavy",
    "glaive_uppercut",
    "grudge_action_three",
    "gs_1h_heavy",
    "gs_heavy_slashing_smiter",
    "handmaiden_banner_explosion_damage",
    "heavy_dash",
    "heavy_poison",
    "heavy_poison_aoe",
    "kaboom_push",
    "light_slashing_linesman_flat_new",
    "long_burn_explosion",
    "long_burn_explosion_glance",
    "mace_sword_bopp",
    "mace_sword_heavy",
    "medium_blunt_smiter_bop_pick",
    "medium_slashing_tank_1h_new",
    "melee_kill_explosion",
    "melee_kill_explosion_glance",
    "repeating_crossbow_elf_projectile",
    "shot_shotgun_cbr",
    "shot_sniper_pistol_burst",
    "tb_halberd_heavy_slash",
    "tb_halberd_heavy_stab",
    "tb_halberd_light_chop",
    "tb_halberd_light_slash",
    "tb_halberd_light_stab",
    "tb_two_handed_sword_heavy",
    "warrior_priest_explosion_damage",
    "warrior_priest_explosion_damage_strong",
    "weak_bomb_explosion",
}

-- ============================================================
-- BR_EXPLOSION_TEMPLATES: 16 entries, alphabetical
-- ============================================================
-- Sourced from `NewExplosionTemplates.<name> =` assignments in
-- experimental_talent_changes.lua. Each is appended to
-- NetworkLookup.explosion_templates and merged into ExplosionTemplates.

M.BR_EXPLOSION_TEMPLATES = {
    "bardin_ranger_activated_ability_aoe",
    "bardin_ranger_activated_ability_fire",
    "engineer_heavy_explosion",
    "handmaiden_banner_explosion",
    "huntsman_ability_explosion",
    "huntsman_ability_explosion_debuff",
    "overcharge_explosion_skull",
    "timed_warp_explosion",
    "warp_lightning_strike_delayed",
    "warrior_priest_lightning_explosion",
    "warrior_priest_lightning_explosion_strong",
    "waystalker_poison_explosion",
    "we_thornsister_career_skill_explosive_wall_explosion",
    "we_thornsister_career_skill_explosive_wall_explosion_no_apply",
    "weak_bomb",
    "witch_hunter_tag_explosion",
}

-- ============================================================
-- BR_STAT_BUFF_METHODS: 3 entries, alphabetical
-- ============================================================
-- Sourced from `NewStatBuffApplicationMethods` table in
-- experimental_talent_changes.lua line 1248. Each is registered
-- as "stacking_multiplier" application in StatBuffApplicationMethods.
-- These do NOT enter NetworkLookup, but list them for symmetry
-- across mods so all peers register the same StatBuff names.

M.BR_STAT_BUFF_METHODS = {
    "charged_projectile_speed",
    "first_ranged_hit_damage",
    "power_level_player",
}

return M
