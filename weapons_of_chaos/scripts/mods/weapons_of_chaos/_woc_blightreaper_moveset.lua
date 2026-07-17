-- Private Blightreaper combat template.
--
-- The relic uses Kerillian's one-handed Sword action graph, slowed to 75%.
-- Poison is described as a native on-hit equipment buff instead of cloning
-- damage profiles (which would require private network lookup entries).

local M = {}

M.SOURCE_ITEM = "we_1h_sword"
M.SOURCE_TEMPLATE = "we_one_hand_sword_template_1"
M.OVERHEAD_SOURCE_TEMPLATE = "one_handed_swords_template_1"
M.EXECUTIONER_SOURCE_TEMPLATE = "two_handed_swords_executioner_template_1"
M.TEMPLATE = "woc_blightreaper_template"
M.SPEED_MULTIPLIER = 0.75
M.INTRINSIC_CRIT_CHANCE = 0.15
M.LIGHT_DAMAGE_PROFILE = "medium_slashing_smiter_2h"
M.HEAVY_DAMAGE_PROFILE = "heavy_slashing_axe_linesman"
M.EXECUTIONER_WWISE_DEP = "wwise/two_handed_swords"
M.DOT_TEMPLATE = "arrow_poison_dot"
M.POISON_BUFF_TEMPLATE = "woc_blightreaper_poison_on_hit"
M.POISON_PROC = "woc_blightreaper_apply_hagbane_poison"
M.CRIT_PROPERTY = "woc_intrinsic_crit"
M.ORDER_PROPERTY = "woc_power_vs_order"
M.CRIT_PROPERTY_BUFF = "properties_woc_intrinsic_crit_display_only"
M.ORDER_PROPERTY_BUFF = "properties_woc_power_vs_order_display_only"

-- Blightreaper is a heavy cursed relic, not an elven/Empire sword.  Impact
-- presentation is copied from Bardin's Greataxe sweeps
-- (`2h_axes.lua`:194-198, 333-337, 474-477, 619-622, 765-768, 911-915).
-- Its action timings and damage geometry remain the Elf Sword graph. Greataxe
-- swing events cannot be substituted safely because their charge timing and
-- baked sweep geometry belong to the 2H Axe graph. Instead, translate each
-- Sword event to the action-by-action native 1H Axe event at the same action
-- index (`1h_swords.lua` versus `1h_axes.lua`). This removes the sword swing
-- presentation without transplanting a mechanically different action graph.
M.GREATAXE_IMPACT_SOUND = "axe_2h_hit"
M.GREATAXE_HIT_EFFECT = "melee_hit_axes_2h"
M.AXE_ARMOUR_IMPACT_SOUND = "blunt_hit_armour"
M.ONE_HAND_AXE_SWING_REMAP = {
	attack_swing_charge_left = "attack_swing_charge_left_diagonal",
	attack_swing_charge_right_pose = "attack_swing_charge_right_diagonal_pose",
	attack_swing_charge_left_pose = "attack_swing_charge_left_diagonal_pose",
	attack_swing_heavy = "attack_swing_heavy_down",
	attack_swing_heavy_right = "attack_swing_heavy_down_right",
	attack_swing_right = "attack_swing_right_diagonal",
	attack_swing_down = "attack_swing_left",
	attack_swing_right_diagonal = "attack_swing_down_right",
}

M.THIRD_PERSON_REMAP = {
	attack_swing_stab = "attack_swing_down",
	attack_swing_charge_down = "attack_swing_charge_left_diagonal",
	attack_swing_charge_left = "attack_swing_charge_right_pose",
	attack_swing_heavy_left_up = "attack_swing_heavy_right",
	attack_swing_charge_right_diagonal_pose = "attack_swing_charge_left_diagonal",
	attack_swing_heavy_down_right = "attack_swing_heavy_down",
}

local function is_attack(sub_action)
	return type(sub_action) == "table"
		and (sub_action.kind == "melee_start" or sub_action.kind == "sweep")
end

local function retarget_chain(action, target)
	for _, chain in ipairs(action and action.allowed_chain_actions or {}) do
		if chain.action == "action_one"
				and (chain.input == "action_one" or chain.input == "action_one_hold")
				and type(chain.sub_action) == "string" then
			chain.sub_action = target
		end
	end
end

local function install_four_light_chain(template, weapons, clone)
	local actions = template.actions and template.actions.action_one
	local overhead_source = weapons[M.OVERHEAD_SOURCE_TEMPLATE]
	local overhead_actions = overhead_source and overhead_source.actions
		and overhead_source.actions.action_one
	local overhead = overhead_actions and overhead_actions.light_attack_last
	if type(actions) ~= "table" or type(actions.light_attack_last) ~= "table"
			or type(actions.default_left) ~= "table" or type(overhead) ~= "table" then
		return false, "four_light_donor_missing"
	end

	-- Kerillian Sword's third light is the stab. Preserve that complete authored
	-- sweep as light four, and insert the Empire Sword's authored vertical light
	-- (including its matching baked sweep) as light three.
	actions.light_attack_stab = actions.light_attack_last
	actions.light_attack_last = clone(overhead, true)
	actions.default_stab = clone(actions.default_left, true)
	for _, chain in ipairs(actions.default_stab.allowed_chain_actions or {}) do
		if chain.action == "action_one" and chain.input == "action_one_release"
				and chain.sub_action == "light_attack_last" then
			chain.sub_action = "light_attack_stab"
		end
	end
	retarget_chain(actions.light_attack_last, "default_stab")

	-- Every single heavy enters the requested overhead -> stab finisher instead
	-- of resuming at a different point in the ordinary Elf Sword light chain.
	for name, action in pairs(actions) do
		if type(name) == "string" and name:find("^heavy_attack_")
				and type(action) == "table" then
			retarget_chain(action, "default_left")
		end
	end
	return true
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
	local chain_ok, chain_reason = install_four_light_chain(template, weapons, clone)
	if not chain_ok then
		report.skipped = chain_reason
		return report
	end
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
	template.buffs = template.buffs or {}
	template.buffs[M.POISON_BUFF_TEMPLATE] = {}
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
							sub_action.impact_sound_event = M.GREATAXE_IMPACT_SOUND
							sub_action.no_damage_impact_sound_event = M.AXE_ARMOUR_IMPACT_SOUND
							sub_action.hit_effect = M.GREATAXE_HIT_EFFECT
						end
						-- The inserted Empire-Sword finisher is specifically the authored
						-- vertical overhead. Do not flatten it back into the generic axe
						-- left swing while translating the remaining Sword events.
						local axe_event = sub_action_name ~= "light_attack_last"
							and M.ONE_HAND_AXE_SWING_REMAP[sub_action.anim_event]
						if axe_event then sub_action.anim_event = axe_event end
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

function M.remap_3p(event_name, career_name, template_name)
	if template_name ~= M.TEMPLATE or type(event_name) ~= "string" then
		return event_name, false
	end
	if type(career_name) == "string" and career_name:sub(1, 3) == "we_" then
		return event_name, false
	end
	local mapped = M.THIRD_PERSON_REMAP[event_name]
	return mapped or event_name, mapped ~= nil
end

return M
