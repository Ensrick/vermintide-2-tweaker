local mod = get_mod("gut_dev")

-- ============================================================================
-- hb_data.lua -- DATA-ONLY fork of HideBuffs_data.lua (UI Tweaks port, Phase 1)
-- ============================================================================
-- Renamespaced: get_mod("HideBuffs") -> get_mod("gut_dev").
--
-- KEPT (pure data tables, set on `mod` exactly as the original did):
--   mod.SETTING_NAMES                              (verbatim literal entries)
--   mod.sorted_priority_buffs                      (reference list)
--   mod.priority_buff_setting_name_to_buff_name    (buff-name lookup)
--   mod.ALIGNMENTS / mod.ALIGNMENTS_LOOKUP
--   mod.PORTRAIT_ICONS
--   mod.career_name_to_hat_icon                    (from original mod_data.lua,
--                                                    co-located here for Phase 1)
--   mod.frame_texture_names                        (from original mod_data.lua)
--   mod.healshare_buff_names                       (from original mod_data.lua)
--   mod.ubersreik_lvls                             (from original mod_data.lua)
--   widget-def reference tables (def_dynamic_widget_names, item_slot_widgets,
--     item_slot_background_widgets, original_health_bar_size, health_bar_offset)
--
-- STRIPPED (VMF options-tree construction -- gut owns its own _data.lua):
--   * `mod_data` table + name/description/is_togglable/allow_rehooking
--   * mod_data.options_widgets:extend / :insert
--   * mod.add_option(...)  (and every call to it)
--   * mod.get_defaults / mod.setting_defaults / mod.setting_parents /
--     mod.setting_names_localized
--   * the priority_buffs_group_subwidgets builder loop (UI only)
--   * the original `return mod_data`
-- The Phase-1 setting_ids those produced are documented in the agent report and
-- are (re)registered through gut's own gui_tweaker_data.lua by the integrator.
--
-- NOTE on SETTING_NAMES coverage: the original add_option() calls dynamically
-- appended several string keys to mod.SETTING_NAMES that are NOT in the literal
-- table below (e.g. HIDE_HUD_WHEN_INSPECTING, HIDE_HUD_HOTKEY, HIDE_PICKUP_OUTLINES,
-- HIDE_OTHER_OUTLINES, HIDE_NEW_AREA_TEXT, HIDE_NEW_AREA_TEXT, HIDE_LOADING_SCREEN_TIPS,
-- HIDE_LOADING_SCREEN_SUBTITLES, DISABLE_LEVEL_INTRO_AUDIO, DISABLE_OLESYA_UBERSREIK_AUDIO,
-- HIDE_WAITING_FOR_RESCUE, HIDE_TWITCH_MODE_ON_ICON, STOP_WHITE_HP_FLASHING).
-- Since add_option is stripped, the hide_elements / level_loading_screen forks
-- reference those settings by their string id via mod.SETTING_NAMES.<KEY>, so we
-- backfill them here at the bottom (identity key=value) to preserve that access
-- pattern without dragging in the options tree.

local pl = require'pl.import_into'()

-- Belt-and-suspenders: ensure the table object exists at the very top before any
-- other hb file (or an early-firing hook) reads it, even if population somehow
-- runs late. The full literal definition follows and overwrites this empty table
-- on the normal load path.
mod.SETTING_NAMES = mod.SETTING_NAMES or {}

mod.SETTING_NAMES = {
	VICTOR_BOUNTYHUNTER_PASSIVE_INFINITE_AMMO_BUFF = "victor_bountyhunter_passive_infinite_ammo_buff",
	GRIMOIRE_HEALTH_DEBUFF = "grimoire_health_debuff",
	MARKUS_HUNTSMAN_PASSIVE_CRIT_AURA_BUFF = "markus_huntsman_passive_crit_aura_buff",
	MARKUS_KNIGHT_PASSIVE_DEFENCE_AURA = "markus_knight_passive_defence_aura",
	KERILLIAN_WAYWATCHER_PASSIVE = "kerillian_waywatcher_passive",
	KERILLIAN_MAIDENGUARD_PASSIVE_STAMINA_REGEN_BUFF = "kerillian_maidenguard_passive_stamina_regen_buff",
	HIDE_SHADE_GRIMOIRE_POWER_BUFF = "HIDE_SHADE_GRIMOIRE_POWER_BUFF",
	HIDE_ZEALOT_HOLY_CRUSADER_BUFF = "HIDE_ZEALOT_HOLY_CRUSADER_BUFF",
	HIDE_WHC_GRIMOIRE_POWER_BUFF = "HIDE_WHC_GRIMOIRE_POWER_BUFF",
	HIDE_FRAMES = "hide_frames",
	HIDE_LEVELS = "hide_levels",
	HIDE_HOTKEYS = "hide_hotkeys",
	NO_TUTORIAL_UI = "no_tutorial_ui",
	NO_MISSION_OBJECTIVE = "no_mission_objective",
	FORCE_DEFAULT_FRAME = "force_default_frame",
	HIDE_PLAYER_PORTRAIT = "hide_player_portrait",
	AMMO_COUNTER_GROUP = "AMMO_COUNTER_GROUP",
	AMMO_COUNTER_OFFSET_X = "AMMO_COUNTER_OFFSET_X",
	AMMO_COUNTER_OFFSET_Y = "AMMO_COUNTER_OFFSET_Y",
	BUFFS_GROUP = "BUFFS_GROUP",
	BUFFS_OFFSET_X = "BUFFS_OFFSET_X",
	BUFFS_OFFSET_Y = "BUFFS_OFFSET_Y",
	CENTERED_BUFFS = "CENTERED_BUFFS",
	CENTERED_BUFFS_REALIGN = "CENTERED_BUFFS_REALIGN",
	REVERSE_BUFF_DIRECTION = "REVERSE_BUFF_DIRECTION",
	BUFFS_FLOW_VERTICALLY = "BUFFS_FLOW_VERTICALLY",
	TEAM_UI_GROUP = "TEAM_UI_GROUP",
	TEAM_UI_OFFSET_X = "TEAM_UI_OFFSET_X",
	TEAM_UI_OFFSET_Y = "TEAM_UI_OFFSET_Y",
	TEAM_UI_SPACING = "TEAM_UI_SPACING",
	TEAM_UI_FLOWS_HORIZONTALLY = "TEAM_UI_FLOWS_HORIZONTALLY",
	HIDE_BUFFS_GROUP = "HIDE_BUFFS_GROUP",
	BUFFS_DISABLE_ALIGN_ANIMATION = "BUFFS_DISABLE_ALIGN_ANIMATION",
	CHAT_GROUP = "CHAT_GROUP",
	CHAT_OFFSET_X = "CHAT_OFFSET_X",
	CHAT_OFFSET_Y = "CHAT_OFFSET_Y",
	HIDE_WEAPON_SLOTS = "HIDE_WEAPON_SLOTS",
	REPOSITION_WEAPON_SLOTS = "REPOSITION_WEAPON_SLOTS",
	TEAM_UI_PORTRAIT_SCALE = "TEAM_UI_PORTRAIT_SCALE",
	TEAM_UI_PORTRAIT_OFFSET_X = "TEAM_UI_PORTRAIT_OFFSET_X",
	TEAM_UI_PORTRAIT_OFFSET_Y = "TEAM_UI_PORTRAIT_OFFSET_Y",
	TEAM_UI_NAME_OFFSET_X = "TEAM_UI_NAME_OFFSET_X",
	TEAM_UI_NAME_OFFSET_Y = "TEAM_UI_NAME_OFFSET_Y",
	SECOND_BUFF_BAR = "SECOND_BUFF_BAR",
	SECOND_BUFF_BAR_OFFSET_X = "SECOND_BUFF_BAR_OFFSET_X",
	SECOND_BUFF_BAR_OFFSET_Y = "SECOND_BUFF_BAR_OFFSET_Y",
	PLAYER_UI_GROUP = "PLAYER_UI_GROUP",
	PLAYER_UI_OFFSET_X = "PLAYER_UI_OFFSET_X",
	PLAYER_UI_OFFSET_Y = "PLAYER_UI_OFFSET_Y",
	PERSISTENT_AMMO_COUNTER = "PERSISTENT_AMMO_COUNTER",
	HIDE_BOSS_HP_BAR = "HIDE_BOSS_HP_BAR",
	PRIORITY_BUFFS_GROUP = "PRIORITY_BUFFS_GROUP",
	HIDE_UI_ELEMENTS_GROUP = "HIDE_UI_ELEMENTS_GROUP",
	UNOBTRUSIVE_FLOATING_OBJECTIVE = "UNOBTRUSIVE_FLOATING_OBJECTIVE",
	UNOBTRUSIVE_MISSION_TOOLTIP = "UNOBTRUSIVE_MISSION_TOOLTIP",
	CHAT_BG_ALPHA = "CHAT_BG_ALPHA",
	AMMO_DIVIDER_TEXT = "AMMO_DIVIDER_TEXT",
	GK_QUESTS_OFFSET_X = "GK_QUESTS_OFFSET_X",
	GK_QUESTS_OFFSET_Y = "GK_QUESTS_OFFSET_Y",
	GK_QUESTS_ALPHA = "GK_QUESTS_ALPHA",
	DODGE_COUNT = "DODGE_COUNT",
	DCUI_ALWAYS_ON = "dcui_always_on",
	DCUI_DISPLAY_COOLDOWN = "dcui_display_cooldown",
	DCUI_OFFSET_X = "dcui_offset_x",
	DCUI_OFFSET_Y = "dcui_offset_y",
	DCUI_FONT_SIZE = "dcui_font_size",
	DCUI_CD_FONT_SIZE = "dcui_cd_font_size",
}

mod.sorted_priority_buffs = {
	"DMG_POT",
	"SPEED_POT",
	"CDR_POT",
	"SWIFT_SLAYING",
	"HUNTER",
	"BARRAGE",
	"BARKSKIN",
	"TWITCH_BUFFS",
	"KERILLIAN_SHADE_ACTIVATED_ABILITY",
	"MARKUS_HUNTSMAN_ACTIVATED_ABILITY",
	"HUNTSMAN_HS_CRIT_BUFF",
	"HUNTSMAN_HS_RELOAD_SPEED_BUFF",
	"KNIGHT_ULT_BLOCK",
	"KNIGHT_ULT_POWER",
	"KNIGHT_BUILD_MOMENTUM",
	"PACED_STRIKES",
	"MERC_MORE_MERRIER",
	"MERC_BLADE_BARRIER",
	"MERC_REIKLAND_REAPER",
	"BARDIN_RANGER_ACTIVATED_ABILITY",
	"GROMRIL",
	"BARDIN_IRONBREAKER_ACTIVATED_ABILITY",
	"IB_MINERS_RHYTHM",
	"BARDIN_SLAYER_ACTIVATED_ABILITY",
	"SLAYER_TROPHY_HUNTER",
	"SLAYER_MOVING_TARGET",
	"WHC_ULT",
	"WHC_PING_AS",
	"WHC_PING_CRIT",
	"BH_CRIT_PASSIVE",
	"VICTOR_ZEALOT_ACTIVATED_ABILITY",
	"ZEALOT_INVULNERABLE_ACTIVE",
	"ZEALOT_INVULNERABLE_ON_CD",
	"ZEALOT_HOLY_CRUSADER",
	"ZEALOT_FIERY_FAITH",
	"ZEALOT_NO_SURRENDER",
	"BW_TRANQUILITY",
	"BW_WORLD_AFLAME",
	"BW_BURNOUT",
	"UNCHAINED_FEURBACHS_FURY",
	"custom_wounded_buff",
	"custom_dps_timed_buff",
	"custom_dps_buff",
	"custom_dmg_taken_buff",
	"custom_temp_hp_buff",
	"custom_scavenger_buff",
}

mod.priority_buff_setting_name_to_buff_name = {
	PACED_STRIKES = { "markus_mercenary_passive_proc" },
	KNIGHT_ULT_BLOCK = { "markus_knight_activated_ability_infinite_block" },
	KNIGHT_ULT_POWER = { "markus_knight_activated_ability_damage_buff" },
	GROMRIL = { "bardin_ironbreaker_gromril_armour" },
	WHC_ULT = {
		"victor_witchhunter_activated_ability_duration",
		"victor_witchhunter_activated_ability_crit_buff",
	},
	WHC_PING_AS = { "victor_witchhunter_ping_target_attack_speed" },
	WHC_PING_CRIT = { "victor_witchhunter_ping_target_crit_chance" },
	BH_CRIT_PASSIVE = {
		"victor_bountyhunter_passive_crit_buff",
		"victor_bountyhunter_passive_crit_cooldown",
	},
	BW_TRANQUILITY = {
		"sienna_adept_passive",
		"tranquility",
	},
	SWIFT_SLAYING = { "traits_melee_attack_speed_on_crit_proc" },
	HUNTER = {
		"ranged_power_vs_frenzy",
		"ranged_power_vs_large",
		"ranged_power_vs_armored",
		"ranged_power_vs_unarmored",
	},
	BARRAGE = { "consecutive_shot_buff" },
	DMG_POT = { "armor penetration" },
	SPEED_POT = { "movement" },
	CDR_POT = { "cooldown reduction buff" },
	MARKUS_HUNTSMAN_ACTIVATED_ABILITY = { "markus_huntsman_activated_ability" },
	KERILLIAN_SHADE_ACTIVATED_ABILITY = {
		"kerillian_shade_activated_ability",
		"kerillian_shade_activated_ability_duration",
	},
	VICTOR_ZEALOT_ACTIVATED_ABILITY = {
		"victor_zealot_activated_ability",
		"victor_zealot_activated_ability_duration",
	},
	BARDIN_RANGER_ACTIVATED_ABILITY = {
		"bardin_ranger_activated_ability",
		"bardin_ranger_activated_ability_duration",
	},
	BARDIN_IRONBREAKER_ACTIVATED_ABILITY = {
		"bardin_ironbreaker_activated_ability",
		"bardin_ironbreaker_activated_ability_duration",
	},
	BARDIN_SLAYER_ACTIVATED_ABILITY = { "bardin_slayer_activated_ability" },
	HUNTSMAN_HS_CRIT_BUFF = { "markus_huntsman_passive_crit_buff" },
	HUNTSMAN_HS_RELOAD_SPEED_BUFF = { "markus_huntsman_headshots_increase_reload_speed_buff" },
	TWITCH_BUFFS = {
		"twitch_no_overcharge_no_ammo_reloads",
		"twitch_health_regen",
		"twitch_health_degen",
		"twitch_grimoire_health_debuff",
		"twitch_power_boost_dismember",
	},
	BARKSKIN = { "trait_necklace_damage_taken_reduction_buff" },
	custom_dps_timed_buff = { "custom_dps_timed" },
	custom_dps_buff = { "custom_dps" },
	custom_dmg_taken_buff = { "custom_dmg_taken" },
	custom_temp_hp_buff = { "custom_temp_hp" },
	custom_scavenger_buff = { "custom_scavenger" },
	custom_wounded_buff = { "custom_wounded" },
	MERC_MORE_MERRIER = {
		"markus_mercenary_damage_on_enemy_proximity"
	},
	MERC_BLADE_BARRIER = {
		"markus_mercenary_passive_defence"
	},
	MERC_REIKLAND_REAPER = {
		"markus_mercenary_passive_power_level"
	},
	KNIGHT_BUILD_MOMENTUM = {
		"markus_knight_stamina_regen_buff"
	},
	SLAYER_TROPHY_HUNTER = {
		"bardin_slayer_passive_stacking_damage_buff",
		"bardin_slayer_passive_stacking_damage_buff_increased_duration",
	},
	SLAYER_MOVING_TARGET = {
		"bardin_slayer_passive_stacking_defence_buff"
	},
	IB_MINERS_RHYTHM = {
		"bardin_ironbreaker_regen_stamina_on_charged_attacks_buff"
	},
	ZEALOT_INVULNERABLE_ACTIVE = {
		"victor_zealot_invulnerability_on_lethal_damage_taken"
	},
	ZEALOT_INVULNERABLE_ON_CD = {
		"victor_zealot_invulnerability_cooldown"
	},
	ZEALOT_HOLY_CRUSADER = {
		"victor_zealot_critical_hit_damage_from_passive"
	},
	ZEALOT_FIERY_FAITH = {
		"victor_zealot_passive_damage"
	},
	ZEALOT_NO_SURRENDER = {
		"victor_zealot_damage_on_enemy_proximity"
	},
	BW_WORLD_AFLAME = {
		"sienna_adept_damage_on_enemy_proximity"
	},
	BW_BURNOUT = {
		"sienna_adept_ability_trail_double"
	},
	UNCHAINED_FEURBACHS_FURY = {
		"sienna_unchained_stamina_regen"
	},

}

-- For every priority-buff setting_name, ensure it is also resolvable through
-- mod.SETTING_NAMES (the original did this in the priority_buffs loop that we
-- stripped along with the UI subwidget builder).
for _, setting_name in ipairs( mod.sorted_priority_buffs ) do
	mod.SETTING_NAMES[setting_name] = setting_name
end

mod.ALIGNMENTS = {
	TOP = 1,
	BOTTOM = 2,
	LEFT = 3,
	RIGHT = 4,
	CENTER = 5,
}
mod.ALIGNMENTS_LOOKUP = {
	"top",
	"bottom",
	"left",
	"right",
	"center",
}
mod.PORTRAIT_ICONS = {
	DEFAULT = 1,
	HERO = 2,
	HATS = 3,
}

-- ----------------------------------------------------------------------------
-- Data tables originally defined in HideBuffs/mod_data.lua, co-located here for
-- Phase 1 (the hide-element & teammate hooks reference them).
-- ----------------------------------------------------------------------------

--- Default HP bar values.
mod.original_health_bar_size = {
	92,
	9
}
mod.health_bar_offset = {
	-(mod.original_health_bar_size[1] / 2),
	-25,
	0
}

--- Elements to reposition inside default_dynamic widget.
mod.def_dynamic_widget_names = pl.List{
	"talk_indicator",
	"talk_indicator_highlight",
	"talk_indicator_highlight_glow",
}

--- Carrer name to hat icon texture lookup.
mod.career_name_to_hat_icon = pl.Map{
	bw_adept = "icon_adept_hat_0001",
	bw_scholar = "icon_scholar_hat_0000",
	bw_unchained = "icon_unchained_hat_0008",
	dr_ironbreaker = "icon_ironbreaker_hat_0006",
	dr_ranger = "icon_ranger_hat_0005",
	dr_slayer = "icon_slayer_hat_0000",
	empire_soldier_tutorial = "icon_knight_hat_0010",
	es_huntsman = "icon_huntsman_hat_0000",
	es_knight = "icon_knight_hat_0010",
	es_mercenary = "icon_mercenary_hat_0007",
	we_maidenguard = "icon_maidenguard_hat_0000",
	we_shade = "icon_shade_hat_0009",
	we_waywatcher = "icon_waywatcher_hat_0001",
	wh_bountyhunter = "icon_bountyhunter_hat_0000",
	wh_captain = "icon_witchhunter_hat_0003",
	wh_zealot = "icon_zealot_hat_0009",
	dr_engineer = "icon_engineer_hat_0001",
	es_questingknight = "icon_questing_knight_hat_0000",
}

--- Elements to reposition inside loadout_dynamic widget.
--- Index is missing, i.e. item_slot_bg_1.
mod.item_slot_widgets = {
	"item_slot_bg_",
	"item_slot_frame_",
	"item_slot_highlight_",
}
mod.item_slot_background_widgets = {
	"item_slot_bg_",
	"item_slot_frame_",
}

--- Healshare talents.
mod.healshare_buff_names = {
	"bardin_ranger_conqueror",
	"bardin_ironbreaker_conqueror",
	"bardin_slayer_conqueror",
	"kerillian_waywatcher_conqueror",
	"kerillian_maidenguard_conqueror",
	"kerillian_shade_conqueror",
	"markus_mercenary_conqueror",
	"markus_huntsman_conqueror",
	"markus_knight_conqueror",
	"sienna_adept_conqueror",
	"sienna_scholar_conqueror",
	"sienna_unchained_conqueror",
	"victor_witchhunter_conqueror",
	"victor_bountyhunter_conqueror",
	"victor_zealot_conqueror",
}

--- Ubersreik level keys.
mod.ubersreik_lvls = pl.List({
	"magnus",
	"cemetery",
	"forest_ambush",
})

--- Portrait frame widget elements: texture_1(static frame) and texture_2(dynamic frame).
mod.frame_texture_names = { "texture_1", "texture_2" }

-- ----------------------------------------------------------------------------
-- Backfill the SETTING_NAMES keys that the original added dynamically via
-- add_option() (which we stripped). The hide_elements / level_loading_screen
-- forks reference these by mod.SETTING_NAMES.<KEY>, so define them identity.
-- These are the Phase-1 hide ids that did NOT appear in the literal table above.
-- ----------------------------------------------------------------------------
local _backfill_setting_names = {
	-- HIDE_UI_ELEMENTS_GROUP children added via add_option:
	"HIDE_HUD_WHEN_INSPECTING",
	"HIDE_HUD_HOTKEY",
	"HIDE_PICKUP_OUTLINES",
	"HIDE_OTHER_OUTLINES",
	"HIDE_NEW_AREA_TEXT",
	"HIDE_LOADING_SCREEN_TIPS",
	"HIDE_LOADING_SCREEN_SUBTITLES",
	"DISABLE_LEVEL_INTRO_AUDIO",
	"DISABLE_OLESYA_UBERSREIK_AUDIO",
	"HIDE_WAITING_FOR_RESCUE",
	"HIDE_TWITCH_MODE_ON_ICON",
	"STOP_WHITE_HP_FLASHING",
	-- root toggle added via add_option:
	"VICTOR_BOUNTYHUNTER_PASSIVE_INFINITE_AMMO_BUFF", -- already literal; harmless re-affirm
}
for _, key in ipairs(_backfill_setting_names) do
	mod.SETTING_NAMES[key] = mod.SETTING_NAMES[key] or key
end

-- DATA-only file: nothing to return (gut's gui_tweaker_data.lua owns the VMF tree).
