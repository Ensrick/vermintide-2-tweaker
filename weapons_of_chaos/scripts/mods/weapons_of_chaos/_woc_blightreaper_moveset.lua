-- Private Blightreaper combat template.
--
-- The relic uses Sienna's one-handed Crowbill action graph (author request
-- 2026-07-19; replaces the earlier Kerillian Sword graph), slowed to 83%.
-- Source template `one_handed_crowbill` (`1h_crowbills.lua:1572`) natively
-- ships four chained lights, three heavies, and a push-attack follow-up, so
-- the Sword era's four-light chain surgery is retired with its donor.
-- Poison is described as a native on-hit equipment buff instead of cloning
-- damage profiles (which would require private network lookup entries).

local M = {}

M.SOURCE_ITEM = "bw_1h_crowbill"
M.SOURCE_TEMPLATE = "one_handed_crowbill"
M.EXECUTIONER_SOURCE_TEMPLATE = "two_handed_swords_executioner_template_1"
M.TEMPLATE = "woc_blightreaper_template"
M.SPEED_MULTIPLIER = 0.83
M.INTRINSIC_CRIT_CHANCE = 0.15
M.LIGHT_DAMAGE_PROFILE = "medium_slashing_smiter_2h"
M.HEAVY_DAMAGE_PROFILE = "heavy_slashing_axe_linesman"
M.EXECUTIONER_WWISE_DEP = "wwise/two_handed_swords"
M.DOT_TEMPLATE = "arrow_poison_dot"
M.POISON_BUFF_TEMPLATE = "woc_blightreaper_poison_on_hit"
M.POISON_PROC = "woc_blightreaper_apply_hagbane_poison"
M.POISON_TRAIT = "woc_poisoned_edge"
M.SHYISH_CURSE_TRAIT = "woc_shyish_health_curse"
M.SHYISH_CURSE_BUFF = "woc_shyish_health_curse_display_only"
M.POISON_TRAIT_ICON = "kerillian_shade_increased_damage_on_poisoned_or_bleeding_enemy"
-- Proven boot-resident in gui_icons_atlas.lua:3392 and consumed by the native
-- mutator_death.lua:6 UI. No WOC texture is exposed to another renderer.
M.SHYISH_CURSE_ICON = "mutator_icon_death_spirits"
M.CRIT_PROPERTY = "woc_intrinsic_crit"
M.ORDER_PROPERTY = "woc_power_vs_order"
M.CRIT_PROPERTY_BUFF = "properties_woc_intrinsic_crit_display_only"
M.ORDER_PROPERTY_BUFF = "properties_woc_power_vs_order_display_only"

-- Impact presentation: the Crowbill graph carries its own authored pick
-- identity (`1h_crowbills.lua`: `crowbill_stab_hit` impacts,
-- `melee_hit_hammers_1h` effects, `blunt_hit_armour` no-damage impacts), so
-- the Sword era's Greataxe impact translation layer is retired together with
-- the Sword graph it was authored against. One normalization remains: the
-- native burn stab (`light_attack_left`, `1h_crowbills.lua:680-708`) presents
-- fire impacts (`fire_hit` / `fire_hit_armour`) for a burn damage profile
-- (`light_blunt_smiter_stab_burn`) that this template replaces with its
-- poison identity, so those sounds are normalized to the crowbill family
-- baseline instead of keeping a fire cue with no burn behind it.
M.CROWBILL_IMPACT_SOUND = "crowbill_stab_hit"
M.CROWBILL_ARMOUR_IMPACT_SOUND = "blunt_hit_armour"
M.FIRE_IMPACT_SOUNDS = {
	fire_hit = true,
	fire_hit_armour = true,
}

-- Crowbill 3P attack events are authored for Sienna's (bw_) skeleton only.
-- Every other receiver redirects into its own native vocabulary using Weapon
-- Tweaker's PROVEN per-receiver crowbill coverage, reused verbatim
-- (`weapon_tweaker/scripts/mods/weapon_tweaker/_wt_anim_remap_data.lua`,
-- `one_handed_crowbill`): the authored dr_ table plus the 2026-07-03 remote
-- tester-baked es_/wh_ picks; `_default` is wt's non-Sienna fallback row and
-- reaches we_ receivers. Do not invent new mappings here.
M.NATIVE_3P_PREFIX = "bw_"
M.THIRD_PERSON_REMAP = {
	dr_ = {
		attack_swing_stab                = "attack_swing_down",
		attack_swing_up_left             = "attack_swing_left",
		attack_swing_charge_left         = "attack_swing_charge_left_diagonal",
		attack_swing_heavy_left_up       = "attack_swing_heavy_down",
		attack_swing_charge_left_pose    = "attack_swing_charge_left_diagonal",
		attack_swing_heavy_left_diagonal = "attack_swing_heavy_down",
	},
	es_ = {
		attack_swing_up_left = "attack_swing_left",
	},
	wh_ = {
		attack_swing_up_left = "attack_swing_left",
	},
	_default = {
		attack_swing_stab                = "attack_swing_down",
		attack_swing_heavy_left_up       = "attack_swing_heavy",
		attack_swing_heavy_left_diagonal = "attack_swing_heavy",
		attack_swing_up_left             = "attack_swing_left",
	},
}

-- Per-career 3P wield redirect, applied in DATA on the private clone via
-- `wield_anim_career_3p` (read by simple_inventory_extension.lua:2011, the
-- husk path simple_husk_inventory_extension.lua:710, and the keep previewer
-- world_hero_previewer.lua:1003). `to_1h_crowbill` exists only on bw_ 3P
-- skeletons; the non-Sienna rows reuse Weapon Tweaker's proven wield coverage
-- (`wt_wield_patches.lua` patch (e) + bulk `one_handed_crowbill` rows, and
-- the `_wt_anim_remap.lua:79` wh_priest override). bw_ careers are
-- deliberately absent so the engine falls back to the native `wield_anim`.
M.WIELD_ANIM_CAREER_3P = {
	es_mercenary      = "to_1h_sword",
	es_huntsman       = "to_1h_sword",
	es_knight         = "to_1h_sword",
	es_questingknight = "to_1h_sword",
	dr_ranger         = "to_1h_sword",
	dr_ironbreaker    = "to_1h_sword",
	dr_slayer         = "to_1h_sword",
	dr_engineer       = "to_1h_sword",
	we_waywatcher     = "to_1h_sword",
	we_maidenguard    = "to_1h_sword",
	we_shade          = "to_1h_sword",
	we_thornsister    = "to_1h_sword",
	wh_captain        = "to_1h_sword",
	wh_bountyhunter   = "to_1h_sword",
	wh_zealot         = "to_1h_sword",
	wh_priest         = "to_1h_hammer",
}

local function is_attack(sub_action)
	return type(sub_action) == "table"
		and (sub_action.kind == "melee_start" or sub_action.kind == "sweep")
end

-- These two rows are presentation-only. The actual +15% critical chance is
-- baked into every attack below; neither row adds a buff, so the joke Order
-- property can never affect damage and the crit bonus cannot be rerolled.
function M.install_intrinsic_property_rows(weapon_properties, buff_templates)
	if type(weapon_properties) ~= "table" or type(weapon_properties.properties) ~= "table"
			or type(buff_templates) ~= "table" then
		return false, "property_tables_unavailable"
	end
	local rows = {
		[M.CRIT_PROPERTY] = {
			buff_name = M.CRIT_PROPERTY_BUFF,
			display_name = "woc_intrinsic_crit_property",
		},
		[M.ORDER_PROPERTY] = {
			buff_name = M.ORDER_PROPERTY_BUFF,
			display_name = "woc_power_vs_order_property",
		},
	}
	for key, row in pairs(rows) do
		row.name = key
		weapon_properties.properties[key] = weapon_properties.properties[key] or row
		local buff_name = row.buff_name
		buff_templates[buff_name] = buff_templates[buff_name] or {
			buffs = { { name = buff_name } },
		}
	end
	return true, "installed"
end

-- Trait rows are the canonical owners of Blightreaper's two cursed effects.
-- The poison row owns the existing on-hit equipment buff. The Shyish row is
-- display-only because its host-authoritative kill listener is keyed by the
-- equipped trait/relic identity instead of adding a second equipment proc.
function M.install_intrinsic_trait_rows(weapon_traits, buff_templates)
	if type(weapon_traits) ~= "table" or type(weapon_traits.traits) ~= "table"
			or type(buff_templates) ~= "table" then
		return false, "trait_tables_unavailable"
	end
	weapon_traits.traits[M.POISON_TRAIT] = weapon_traits.traits[M.POISON_TRAIT] or {
		name = M.POISON_TRAIT,
		buff_name = M.POISON_BUFF_TEMPLATE,
		display_name = "woc_poisoned_edge_trait",
		advanced_description = "description_woc_poisoned_edge_trait",
		icon = M.POISON_TRAIT_ICON,
		buffer = "client",
	}
	weapon_traits.traits[M.SHYISH_CURSE_TRAIT] = weapon_traits.traits[M.SHYISH_CURSE_TRAIT] or {
		name = M.SHYISH_CURSE_TRAIT,
		buff_name = M.SHYISH_CURSE_BUFF,
		display_name = "woc_shyish_health_curse_trait",
		advanced_description = "description_woc_shyish_health_curse_trait",
		icon = M.SHYISH_CURSE_ICON,
		buffer = "client",
		crafting_disabled = true,
	}
	buff_templates[M.SHYISH_CURSE_BUFF] = buff_templates[M.SHYISH_CURSE_BUFF] or {
		buffs = { { name = M.SHYISH_CURSE_BUFF } },
	}
	return true, "installed"
end

function M.intrinsic_traits()
	return { M.POISON_TRAIT, M.SHYISH_CURSE_TRAIT }
end

function M.item_has_trait(item, trait_key)
	if type(item) ~= "table" or type(item.traits) ~= "table" then return false end
	for _, value in ipairs(item.traits) do
		if value == trait_key then return true end
	end
	return false
end

function M.install(weapons, clone)
	local report = { installed = false, attacks = 0, skipped = nil }
	if type(weapons) ~= "table" or type(clone) ~= "function" then
		report.skipped = "tables_unavailable"
		return report
	end
	if type(weapons[M.TEMPLATE]) == "table" then
		report.installed = true
		report.existing = true
		return report
	end
	local source = weapons[M.SOURCE_TEMPLATE]
	if type(source) ~= "table" then
		report.skipped = "source_template_missing"
		return report
	end

	local template = clone(source, true)
	if type(template) ~= "table" then
		report.skipped = "clone_failed"
		return report
	end
	template.name = M.TEMPLATE
	-- The clone inherits the crowbill state machine and `wwise/one_handed_
	-- crowbills` bank; `WeaponUtils.get_weapon_packages` (weapon_utils.lua:73/
	-- :104-109) makes both resident wherever the relic spawns. Append the
	-- Executioner bank the same way so the manual swing whooshes stay resident.
	local dependencies = template.wwise_dep_right_hand or {}
	local has_executioner_audio = false
	for i = 1, #dependencies do
		if dependencies[i] == M.EXECUTIONER_WWISE_DEP then
			has_executioner_audio = true
			break
		end
	end
	if not has_executioner_audio then
		dependencies[#dependencies + 1] = M.EXECUTIONER_WWISE_DEP
	end
	template.wwise_dep_right_hand = dependencies
	-- Non-Sienna receivers get their 3P wield stance redirected in data; the
	-- attack events are redirected at the `_play_3p_anim` boundary (remap_3p).
	local wield_3p = {}
	for career_name, wield_event in pairs(M.WIELD_ANIM_CAREER_3P) do
		wield_3p[career_name] = wield_event
	end
	template.wield_anim_career_3p = wield_3p
	-- Poison is attached through the intrinsic item trait below. Keeping the
	-- same buff on the template would give one effect two proc owners.
	template.buffs = template.buffs or {}
	for action_name, group in pairs(template.actions or {}) do
		if type(group) == "table" then
			for sub_action_name, sub_action in pairs(group) do
				if type(sub_action) == "table" then
					sub_action.lookup_data = {
						item_template_name = M.TEMPLATE,
						action_name = action_name,
						sub_action_name = sub_action_name,
					}
					if is_attack(sub_action) then
						if sub_action.kind == "sweep" then
							if type(sub_action_name) == "string"
									and sub_action_name:find("^light_attack") then
								sub_action.damage_profile = M.LIGHT_DAMAGE_PROFILE
							elseif type(sub_action_name) == "string"
									and sub_action_name:find("^heavy_attack") then
								sub_action.damage_profile = M.HEAVY_DAMAGE_PROFILE
							end
							sub_action.additional_critical_strike_chance = M.INTRINSIC_CRIT_CHANCE
							if M.FIRE_IMPACT_SOUNDS[sub_action.impact_sound_event] then
								sub_action.impact_sound_event = M.CROWBILL_IMPACT_SOUND
							end
							if M.FIRE_IMPACT_SOUNDS[sub_action.no_damage_impact_sound_event] then
								sub_action.no_damage_impact_sound_event = M.CROWBILL_ARMOUR_IMPACT_SOUND
							end
							if M.FIRE_IMPACT_SOUNDS[sub_action.armor_impact_sound_event] then
								sub_action.armor_impact_sound_event = nil
							end
						end
						sub_action.anim_time_scale = (sub_action.anim_time_scale or 1)
							* M.SPEED_MULTIPLIER
						report.attacks = report.attacks + 1
					end
				end
			end
		end
	end

	weapons[M.TEMPLATE] = template
	report.installed = true
	return report
end

-- Returns a fresh client-equipment-buff descriptor. The WOC proc is resolved
-- locally by name and sends only the native `arrow_poison_dot` buff through
-- BuffSyncType.All. This is necessary because vanilla `apply_dot_on_hit`
-- returns immediately on a non-server peer, which would make client-owned
-- Blightreapers fail to poison. The custom proc/buff names never cross RPC.
function M.poison_buff_descriptor()
	return {
		buffs = {
			{
				buff_func = M.POISON_PROC,
				event = "on_hit",
				name = M.POISON_BUFF_TEMPLATE,
			},
		},
	}
end

function M.install_poison_buff(buff_templates)
	if type(buff_templates) ~= "table" then
		return false, "buff_templates_unavailable"
	end
	if type(buff_templates[M.POISON_BUFF_TEMPLATE]) == "table" then
		return true, "existing"
	end
	buff_templates[M.POISON_BUFF_TEMPLATE] = M.poison_buff_descriptor()
	return true, "installed"
end

-- Attack-chain descriptor for `_woc_attack_order.lua` (additive; consumes the
-- clone this module installs, mutates nothing here). Slot names, charge-node
-- pairings, and transition targets are the verified `one_handed_crowbill`
-- enumeration (1h_crowbills.lua: charge nodes :8/:65/:120/:175, lights
-- :939/:1078/:810/:680, heavies :230/:530/:380, push-attack bopp :1212).
-- Positions are the four charge nodes in chain order; `transitions` is the
-- after-state map (values = next chain position) that the permutation plan
-- preserves. Returns a fresh table per call (mod:dofile is not a singleton).
function M.chain_descriptor()
	return {
		template_name = M.TEMPLATE,
		action = "action_one",
		-- Attack units. `slot` = native home sub_action; labels are raw loc keys.
		lights = {
			{ id = "overhead",       slot = "light_attack_last",  label = "woc_atk_overhead" },
			{ id = "upper_left",     slot = "light_attack_upper", label = "woc_atk_upper_left" },
			{ id = "right_diagonal", slot = "light_attack_right", label = "woc_atk_right_diagonal" },
			{ id = "stab",           slot = "light_attack_left",  label = "woc_atk_stab" },
		},
		-- Heavy PAIRS: release payload + the windup anim of `charge_slot`.
		heavies = {
			{ id = "left_up_smash",  slot = "heavy_attack",          charge_slot = "default",       label = "woc_atk_left_up_smash" },
			{ id = "right_smash",    slot = "heavy_attack_left",     charge_slot = "default_left",  label = "woc_atk_right_smash" },
			{ id = "diagonal_smash", slot = "heavy_attack_right_up", charge_slot = "default_right", label = "woc_atk_diagonal_smash" },
		},
		push = {
			{ id = "upper_bopp", slot = "light_attack_bopp", label = "woc_atk_upper_bopp" },
		},
		-- Chain positions (charge nodes) in native chain order.
		charge_nodes = { "default", "default_right", "default_left", "default_last" },
		light_positions = { "overhead", "upper_left", "right_diagonal", "stab" },
		heavy_positions = {
			{ native = "left_up_smash",  charge_slots = { "default" } },
			-- Positions 2 and 4 share this heavy sub_action natively.
			{ native = "diagonal_smash", charge_slots = { "default_right", "default_last" } },
			{ native = "right_smash",    charge_slots = { "default_left" } },
		},
		push_positions = { "upper_bopp" },
		-- After-state map (next chain position). Mirrors the native wiring the
		-- permutation plan preserves; /woc_chains re-derives it from the live
		-- template so drift is visible.
		transitions = {
			entry = 1,
			after_light = { 2, 3, 4, 1 },
			after_heavy = { 3, 1, 4 },
			after_push_attack = 3,
		},
	}
end

function M.remap_3p(event_name, career_name, template_name)
	if template_name ~= M.TEMPLATE or type(event_name) ~= "string" then
		return event_name, false
	end
	local prefix = type(career_name) == "string" and career_name:sub(1, 3) or nil
	if prefix == M.NATIVE_3P_PREFIX then
		return event_name, false
	end
	local remap = (prefix and M.THIRD_PERSON_REMAP[prefix])
		or M.THIRD_PERSON_REMAP._default
	local mapped = type(remap) == "table" and remap[event_name] or nil
	return mapped or event_name, mapped ~= nil
end

return M
