-- Private Blightreaper combat template.
--
-- The relic uses Kerillian's one-handed Sword action graph, slowed to 75%.
-- Poison is described as a native on-hit equipment buff instead of cloning
-- damage profiles (which would require private network lookup entries).

local M = {}

M.SOURCE_ITEM = "we_1h_sword"
M.SOURCE_TEMPLATE = "we_one_hand_sword_template_1"
M.TEMPLATE = "woc_blightreaper_template"
M.SPEED_MULTIPLIER = 0.75
M.DOT_TEMPLATE = "arrow_poison_dot"
M.POISON_BUFF_TEMPLATE = "woc_blightreaper_poison_on_hit"
M.POISON_PROC = "woc_blightreaper_apply_hagbane_poison"

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
