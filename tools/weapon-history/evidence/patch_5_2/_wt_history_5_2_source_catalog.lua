-- Source-exact weapon history metadata for the 5.2.0 rebalance and 5.2.3 hotfix.
--
-- This module is intentionally inert. It does not mutate WeaponTemplates or any
-- global gameplay table. The history runtime owns loading, baseline capture,
-- family-scoped projection, private damage-profile registration, and fallback.
--
-- Historical values come from immutable Vermintide-2-Source-Code revisions.
-- Adjacent revisions identify which weapon families own a selectable state;
-- every generated snapshot/profile module projects that state directly over the
-- current source anchor instead of depending on another historical state.

local current_revision = "25fd7b8433e839b678d1c98a7a9af80918cbc252"

local snapshot_modules = {
	["5_1_1"] = {
		"scripts/mods/weapon_tweaker/_wt_history_snapshot_5_1_1_part_1_generated",
		"scripts/mods/weapon_tweaker/_wt_history_snapshot_5_1_1_part_2_generated",
	},
	["5_2_0"] = {
		"scripts/mods/weapon_tweaker/_wt_history_snapshot_5_2_0_part_1_generated",
		"scripts/mods/weapon_tweaker/_wt_history_snapshot_5_2_0_part_2_generated",
	},
	["5_2_3"] = {
		"scripts/mods/weapon_tweaker/_wt_history_snapshot_5_2_3_generated",
	},
}

local profile_modules = {
	["5_1_1"] = {
		"scripts/mods/weapon_tweaker/_wt_history_profiles_5_1_1_generated",
		"scripts/mods/weapon_tweaker/_wt_history_profiles_5_1_1_dlc_generated",
	},
	["5_2_0"] = {
		"scripts/mods/weapon_tweaker/_wt_history_profiles_5_2_0_generated",
		"scripts/mods/weapon_tweaker/_wt_history_profiles_5_2_0_dlc_generated",
	},
	["5_2_3"] = {},
}

local template_families = {
	bw_deus_01_template_1 = "coruscation_staff",
	dual_wield_daggers_template_1 = "dual_daggers",
	dual_wield_sword_dagger_template_1 = "sword_and_dagger",
	heavy_steam_pistol_template_1 = "masterwork_pistol",
	javelin_template = "javelin",
	one_hand_axe_template_1 = "one_handed_axe_shared",
	one_hand_axe_template_2 = "one_handed_axe_shared",
	one_hand_falchion_template_1 = "falchion",
	one_handed_crowbill = "crowbill",
	one_handed_flail_template_1 = "one_handed_flail",
	one_handed_hammer_priest_template = "one_handed_hammer_shared",
	one_handed_hammer_template_1 = "one_handed_hammer_shared",
	one_handed_hammer_template_2 = "one_handed_hammer_shared",
	one_handed_sword_shield_template_1 = "kruber_sword_and_shield",
	one_handed_swords_template_1 = "one_handed_sword_shared",
	two_handed_swords_template_1 = "two_handed_sword_shared",
	we_one_hand_axe_template = "elf_one_handed_axe",
}

local families = {
	{
		id = "coruscation_staff",
		setting_id = "wt_history_coruscation_staff",
		label = "Sienna's Coruscation Staff",
		aliases = { "coruscation", "bw_deus_01" },
		templates = { "bw_deus_01_template_1" },
		item_aliases = { "bw_deus_01" },
		states = { "5_1_1" },
		source_paths = {
			"scripts/settings/equipment/weapon_templates/bw_deus_01.lua",
			"scripts/settings/dlcs/morris/damage_profile_templates_dlc_morris.lua",
			"scripts/settings/dlcs/morris/morris_buff_settings.lua",
			"scripts/settings/dlcs/morris/player_unit_status_settings_morris.lua",
		},
	},
	{
		id = "dual_daggers",
		setting_id = "wt_history_dual_daggers",
		label = "Kerillian's Dual Daggers",
		aliases = { "dual_dagger", "we_dual_wield_daggers" },
		templates = { "dual_wield_daggers_template_1" },
		item_aliases = { "we_dual_wield_daggers" },
		states = { "5_1_1", "5_2_0" },
		source_paths = {
			"scripts/settings/equipment/weapon_templates/dual_wield_daggers.lua",
			"scripts/settings/equipment/damage_profile_templates.lua",
		},
	},
	{
		id = "one_handed_sword_shared",
		setting_id = "wt_history_one_handed_sword_shared",
		label = "One-handed Sword (Kruber and Sienna)",
		aliases = { "one_handed_sword", "one_handed_swords" },
		templates = { "one_handed_swords_template_1" },
		item_aliases = { "es_1h_sword", "bw_1h_sword" },
		states = { "5_1_1", "5_2_0" },
		source_paths = {
			"scripts/settings/equipment/weapon_templates/1h_swords.lua",
			"scripts/settings/equipment/damage_profile_templates.lua",
		},
	},
	{
		id = "two_handed_sword_shared",
		setting_id = "wt_history_two_handed_sword_shared",
		label = "Two-handed Sword (Kruber and Saltzpyre)",
		aliases = { "two_handed_sword", "greatsword" },
		templates = { "two_handed_swords_template_1" },
		item_aliases = { "es_2h_sword", "wh_2h_sword" },
		states = { "5_1_1" },
		source_paths = {
			"scripts/settings/equipment/weapon_templates/2h_swords.lua",
			"scripts/settings/equipment/damage_profile_templates.lua",
		},
	},
	{
		id = "one_handed_axe_shared",
		setting_id = "wt_history_one_handed_axe_shared",
		label = "One-handed Axe (Bardin and Saltzpyre)",
		aliases = { "one_handed_axe", "one_hand_axe" },
		templates = { "one_hand_axe_template_1", "one_hand_axe_template_2" },
		item_aliases = { "dr_1h_axe", "wh_1h_axe" },
		states = { "5_1_1", "5_2_0" },
		source_paths = {
			"scripts/settings/equipment/weapon_templates/1h_axes.lua",
			"scripts/settings/equipment/damage_profile_templates.lua",
		},
	},
	{
		id = "one_handed_hammer_shared",
		setting_id = "wt_history_one_handed_hammer_shared",
		label = "One-handed Hammer/Mace (Kruber, Bardin, and Saltzpyre)",
		aliases = { "one_handed_hammer", "one_handed_mace" },
		templates = {
			"one_handed_hammer_template_1",
			"one_handed_hammer_template_2",
			"one_handed_hammer_priest_template",
		},
		item_aliases = { "es_1h_mace", "dr_1h_hammer", "wh_1h_hammer" },
		states = { "5_1_1", "5_2_0" },
		source_paths = {
			"scripts/settings/equipment/weapon_templates/1h_hammers.lua",
			"scripts/settings/equipment/weapon_templates/1h_hammers_priest.lua",
		},
	},
	{
		id = "javelin",
		setting_id = "wt_history_javelin",
		label = "Kerillian's Javelin",
		aliases = { "javelin", "we_javelin" },
		templates = { "javelin_template" },
		item_aliases = { "we_javelin" },
		states = { "5_1_1", "5_2_0" },
		source_paths = {
			"scripts/settings/equipment/weapon_templates/javelin.lua",
			"scripts/settings/equipment/damage_profile_templates_dlc_woods.lua",
		},
	},
	{
		id = "elf_one_handed_axe",
		setting_id = "wt_history_elf_one_handed_axe",
		label = "Kerillian's One-handed Axe",
		aliases = { "elf_axe", "we_1h_axe" },
		templates = { "we_one_hand_axe_template" },
		item_aliases = { "we_1h_axe" },
		states = { "5_1_1", "5_2_0" },
		source_paths = {
			"scripts/settings/equipment/weapon_templates/1h_axes_wood_elf.lua",
			"scripts/settings/equipment/damage_profile_templates.lua",
		},
	},
	{
		id = "kruber_sword_and_shield",
		setting_id = "wt_history_kruber_sword_and_shield",
		label = "Kruber's Sword and Shield",
		aliases = { "sword_and_shield", "es_sword_shield" },
		templates = { "one_handed_sword_shield_template_1" },
		item_aliases = { "es_sword_shield" },
		states = { "5_1_1", "5_2_0" },
		source_paths = {
			"scripts/settings/equipment/weapon_templates/1h_swords_shield.lua",
		},
	},
	{
		id = "falchion",
		setting_id = "wt_history_falchion",
		label = "Saltzpyre's Falchion",
		aliases = { "falchion", "wh_1h_falchion" },
		templates = { "one_hand_falchion_template_1" },
		item_aliases = { "wh_1h_falchion" },
		states = { "5_2_0" },
		source_paths = {
			"scripts/settings/equipment/weapon_templates/1h_falchions.lua",
		},
	},
	{
		id = "crowbill",
		setting_id = "wt_history_crowbill",
		label = "Sienna's Crowbill",
		aliases = { "crowbill", "bw_1h_crowbill" },
		templates = { "one_handed_crowbill" },
		item_aliases = { "bw_1h_crowbill" },
		states = { "5_2_0" },
		source_paths = {
			"scripts/settings/equipment/weapon_templates/1h_crowbills.lua",
		},
	},
	{
		id = "one_handed_flail",
		setting_id = "wt_history_one_handed_flail",
		label = "Saltzpyre's One-handed Flail",
		aliases = { "one_handed_flail", "es_1h_flail" },
		templates = { "one_handed_flail_template_1" },
		item_aliases = { "es_1h_flail" },
		states = { "5_2_0" },
		source_paths = {
			"scripts/settings/equipment/weapon_templates/1h_flails.lua",
		},
	},
	{
		id = "sword_and_dagger",
		setting_id = "wt_history_sword_and_dagger",
		label = "Kerillian's Sword and Dagger",
		aliases = { "sword_dagger", "we_dual_wield_sword_dagger" },
		templates = { "dual_wield_sword_dagger_template_1" },
		item_aliases = { "we_dual_wield_sword_dagger" },
		states = { "5_2_0" },
		source_paths = {
			"scripts/settings/equipment/weapon_templates/dual_wield_sword_dagger.lua",
		},
	},
	{
		id = "masterwork_pistol",
		setting_id = "wt_history_masterwork_pistol",
		label = "Bardin's Masterwork Pistol",
		aliases = { "masterwork_pistol", "dr_steam_pistol" },
		templates = { "heavy_steam_pistol_template_1" },
		item_aliases = { "dr_steam_pistol" },
		states = { "5_2_0", "5_2_3" },
		source_paths = {
			"scripts/settings/equipment/weapon_templates/heavy_steam_pistol.lua",
			"scripts/settings/equipment/damage_profile_templates_dlc_cog.lua",
		},
	},
}

-- Profiles are full, resolved historical tables. A consumer must register them
-- under private deterministic names and remap only references owned by the
-- selected family. The same native profile can be shared by unrelated weapons;
-- mutating the native profile would leak one selector into another family.
local profile_routes = {
	["5_1_1"] = {
		coruscation_staff = { "staff_magma", "geiser_magma" },
		javelin = {
			"medium_javelin_smiter_stab",
			"medium_javelin_smiter_stab_bleed",
			"heavy_javelin_smiter_stab_bleed",
			"thrown_javelin",
		},
		one_handed_sword_shared = {
			"light_slashing_linesman_finesse",
			"medium_slashing_tank_1h_finesse",
		},
		two_handed_sword_shared = { "heavy_slashing_linesman" },
		one_handed_axe_shared = { "medium_slashing_smiter_1h_axe" },
		elf_one_handed_axe = { "medium_slashing_smiter_1h_axe" },
	},
	["5_2_0"] = {
		dual_daggers = { "light_slashing_smiter_stab_dual" },
		one_handed_sword_shared = { "medium_slashing_tank_1h_finesse" },
		masterwork_pistol = { "shot_sniper_pistol" },
	},
	["5_2_3"] = {},
}

-- Only these native names are referenced directly by the current source
-- templates and therefore require a synthetic route rewrite. Other routed
-- profiles are either carried by an explicit historical operation or retained
-- solely as a validated derivation donor (geiser_magma ->
-- geiser_magma_no_damage). Keeping this distinction prevents a valid family
-- from being rejected because a source-only donor is not a current leaf.
local direct_profile_routes = {
	["5_1_1"] = {
		coruscation_staff = { "geiser_magma_no_damage", "staff_magma" },
		javelin = {
			"heavy_javelin_smiter_stab_bleed",
			"medium_javelin_smiter_stab",
			"medium_javelin_smiter_stab_bleed",
			"thrown_javelin",
		},
		one_handed_sword_shared = {
			"light_slashing_linesman_finesse",
			"medium_slashing_tank_1h_finesse",
		},
		two_handed_sword_shared = { "heavy_slashing_linesman" },
	},
	["5_2_0"] = {
		one_handed_sword_shared = { "medium_slashing_tank_1h_finesse" },
		masterwork_pistol = { "shot_sniper_pistol" },
	},
	["5_2_3"] = {},
}

-- The native damage-profile loader derives every `<name>_no_damage` profile
-- before mods run. Coruscation's charged action names that derived profile, not
-- `geiser_magma` itself. Reproduce the native derivation after cloning the
-- historical source profile, then remap the derived reference as part of the
-- same family transaction; otherwise the historical dot data is unreachable.
local derived_profile_routes = {
	["5_1_1"] = {
		coruscation_staff = {
			{
				source_profile = "geiser_magma",
				native_reference = "geiser_magma_no_damage",
				private_name_format = "wt_hist_5_1_1_geiser_magma_no_damage",
				derivation = "native_no_damage_clone",
				derivation_source = "scripts/settings/equipment/damage_profile_templates.lua",
				operations = {
					"clone the full historical geiser_magma profile",
					"set every targets[*].power_distribution.attack to 0 when present",
					"set default_target.power_distribution.attack to 0 when present",
				},
			},
		},
	},
	["5_2_0"] = {},
	["5_2_3"] = {},
}

-- The 5.1.1 values below are the only source-exact global (non-template,
-- non-damage-profile) operations required by the official 5.2.0 weapon groups.
-- Patch 5.2.0 and 5.2.3 match the current source anchor at these paths.
local global_records = {
	["5_1_1"] = {
		{
			family_id = "coruscation_staff",
			root = "PlayerUnitStatusSettings",
			path = { "overcharge_values", "magma_charged_2" },
			value = 8,
			expected_current = 11,
			source_path = "scripts/settings/dlcs/morris/player_unit_status_settings_morris.lua",
		},
		{
			family_id = "coruscation_staff",
			root = "PlayerUnitStatusSettings",
			path = { "overcharge_values", "magma_basic" },
			value = 7,
			expected_current = 6,
			source_path = "scripts/settings/dlcs/morris/player_unit_status_settings_morris.lua",
		},
		{
			family_id = "coruscation_staff",
			root = "PlayerUnitStatusSettings",
			path = { "overcharge_values", "magma_charged" },
			value = 6,
			expected_current = 9,
			source_path = "scripts/settings/dlcs/morris/player_unit_status_settings_morris.lua",
		},
		{
			family_id = "coruscation_staff",
			root = "ExplosionTemplates",
			path = { "magma", "aoe", "duration" },
			value = 10,
			expected_current = 6,
			source_path = "scripts/settings/dlcs/morris/morris_buff_settings.lua",
			source_owner = { root = "DLCSettings", path = { "morris", "explosion_templates" } },
		},
		{
			family_id = "coruscation_staff",
			root = "BuffTemplates",
			path = { "burning_magma_dot", "buffs", 1, "duration" },
			value = 3,
			expected_current = 2,
			source_path = "scripts/settings/dlcs/morris/morris_buff_settings.lua",
			source_owner = { root = "DLCSettings", path = { "morris", "buff_templates" } },
		},
		{
			family_id = "coruscation_staff",
			root = "BuffTemplates",
			path = { "burning_magma_dot", "buffs", 1, "max_stacks" },
			value = 6,
			expected_current = 5,
			source_path = "scripts/settings/dlcs/morris/morris_buff_settings.lua",
			source_owner = { root = "DLCSettings", path = { "morris", "buff_templates" } },
		},
		{
			family_id = "coruscation_staff",
			root = "BuffTemplates",
			path = { "burning_magma_dot", "buffs", 1, "update_start_delay" },
			value = 0.75,
			expected_current = 0.5,
			source_path = "scripts/settings/dlcs/morris/morris_buff_settings.lua",
			source_owner = { root = "DLCSettings", path = { "morris", "buff_templates" } },
		},
		{
			family_id = "coruscation_staff",
			root = "BuffTemplates",
			path = { "burning_magma_dot", "buffs", 1, "time_between_dot_damages" },
			value = 0.75,
			expected_current = 0.5,
			source_path = "scripts/settings/dlcs/morris/morris_buff_settings.lua",
			source_owner = { root = "DLCSettings", path = { "morris", "buff_templates" } },
		},
	},
	["5_2_0"] = {},
	["5_2_3"] = {},
}

return {
	schema = 1,
	catalog_id = "official_weapon_history_5_2",
	current_state = "current",
	current_revision = current_revision,
	state_order = { "5_1_1", "5_2_0", "5_2_3" },
	states = {
		["5_1_1"] = {
			label = "Patch 5.1.1",
			menu_label = "Pre-5.2.0 (Patch 5.1.1)",
			revision = "8224b4436e20905a6ba463cb28fa2d7771bb2330",
			version_settings = "5.1.1",
			direct_to_revision = current_revision,
			snapshot_modules = snapshot_modules["5_1_1"],
			profile_modules = profile_modules["5_1_1"],
		},
		["5_2_0"] = {
			label = "Patch 5.2.0",
			menu_label = "Patch 5.2.0",
			revision = "4f496970e2e7514bef7d612ab91331aa065d5e52",
			version_settings = "5.2.0",
			direct_to_revision = current_revision,
			snapshot_modules = snapshot_modules["5_2_0"],
			profile_modules = profile_modules["5_2_0"],
		},
		["5_2_3"] = {
			label = "Patch 5.2.3",
			menu_label = "Patch 5.2.3",
			revision = "cdc0a86e24e017119e6d6998870bf76f6e76e868",
			-- The source commit and official hotfix identify 5.2.3, while this
			-- source snapshot's version_settings.lua remained at 5.2.0.
			version_settings = "5.2.0",
			official_patch = "5.2.3",
			direct_to_revision = current_revision,
			snapshot_modules = snapshot_modules["5_2_3"],
			profile_modules = profile_modules["5_2_3"],
		},
	},
	families = families,
	template_families = template_families,
	profile_routes = profile_routes,
	direct_profile_routes = direct_profile_routes,
	derived_profile_routes = derived_profile_routes,
	global_records = global_records,
	private_profile_contract = {
		key_format = "wt_hist_<state_id>_<native_profile_name>",
		fallback_registry = "mod._wt431_custom_profile_fallback",
		register = "unconditionally_at_load",
		remap = "selected_family_references_only",
		parity_guard = "wt431_damage_profile_parity",
		failure = "restore_current_and_fail_closed",
	},
	provenance = {
		source_repository = "https://github.com/Aussiemon/Vermintide-2-Source-Code",
		official_notes = {
			["5_2_0"] = "https://www.vermintide.com/news/gifts-of-the-wolf-father-and-patch-520",
			["5_2_3"] = "https://forums.fatsharkgames.com/t/hotfix-megathread-5-2-x-current-5-2-3/91155",
		},
		extraction = {
			method = "symbolic Lua evaluation and semantic table comparison",
			adjacent_boundaries = {
				{ old_revision = "8224b443", new_revision = "4f496970", patch = "5.2.0" },
				{ old_revision = "4f496970", new_revision = "cdc0a86e", patch = "5.2.3" },
			},
			direct_projection_target = "25fd7b84",
			decompiler_rewrite_revision = "9239fe14",
			spread_surface_5_2_3 = "semantic_equal_across_decompiler_rewrite",
		},
		artifact_sha256 = {
			_wt_history_profiles_5_1_1_dlc_generated = "a608765e34a96411d4122754670061583205eb19d63c81153964dc5a05364468",
			_wt_history_profiles_5_1_1_generated = "57053025025299ed530d28e91fe7577dcd6b9ec744689fb8407b01712dd5ccaa",
			_wt_history_profiles_5_2_0_dlc_generated = "43afb721f4354c9c7bd5f08d65493cc1e01dcd57ac82be864a8301e529872d1d",
			_wt_history_profiles_5_2_0_generated = "070c52e482d66bc0d3c876947a77e9f420fa7dbb839b35ca95620c4ed4bd54d4",
			_wt_history_snapshot_5_1_1_part_1_generated = "09158148ef828df373ce75a00ebb3abd971a6ed6e59800d1479aad7c0447d46b",
			_wt_history_snapshot_5_1_1_part_2_generated = "71edcbf4a32b6056e3de045dc2b4b76a8d96c7302b2bafcc9d474611e1278809",
			_wt_history_snapshot_5_2_0_part_1_generated = "4a5db6aee097e826bfe049573fde317abef8e22402ba9c2d83ecf131be7b296f",
			_wt_history_snapshot_5_2_0_part_2_generated = "6d1c05ebf6040062c6c70e74dfdedf0f77e6a9e7651439995209989b802ce398",
			_wt_history_snapshot_5_2_3_generated = "27d717fcc435e6db9d34b40824f74dd05db62e494d3f358385fad223992c5ab5",
		},
	},
	completeness = {
		official_5_2_0_weapon_groups = "complete",
		official_5_2_3_weapon_groups = "complete",
		template_unsupported_value_shapes = 0,
		spread_profile_changes_for_target_groups = 0,
		function_body_policy = "current executable function bodies are retained; adjacent-source audit found no official named weapon group requiring a function-body projection",
		presentation_policy = "historical balance data only; unit, animation-state-machine, sound-event, tooltip, and other presentation roots are deliberately retained from current",
		resolved_surfaces = {
			"weapon_templates",
			"damage_profiles",
			"power_level_templates_through_resolved_damage_profiles",
			"spread_templates",
			"explosion_templates",
			"buff_templates",
			"player_overcharge_values",
		},
		exact_exclusions = {
			{
				source_path = "scripts/settings/equipment/weapon_templates/1h_swords_wizard.lua",
				template = "flaming_sword_template_1",
				path = { "actions", "action_one", "heavy_attack_spell", "fatigue_cost" },
				old_value_absent = true,
				new_value = "action_stun_push",
				reason = "source-semantic 5.2.0 boundary delta absent from the official named weapon groups; excluded instead of guessing ownership",
			},
		},
		known_source_metadata_mismatches = {
			"8224b443 has VersionSettings 5.1.1 although its aggregate commit subject says 5.10.1 through 5.10.5",
			"cdc0a86e is the 5.2.3 source commit but its VersionSettings value remained 5.2.0",
		},
	},
}
