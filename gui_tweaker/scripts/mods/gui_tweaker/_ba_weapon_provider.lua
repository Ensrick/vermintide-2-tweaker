--[[
	_ba_weapon_provider.lua  (Bestiary & Armory feature, migrated into gut)

	PURE-DYNAMIC weapon data layer for the Armory. Replaces the original
	Armory's hardcoded `armory_wanted_weapon_data.lua` (and the prefix-based
	career guess) with a live enumeration of `ItemMasterList`:
	  - keep items with `has_power_level` and a weapon `slot_type` (melee/ranged)
	  - group by `can_wield` (the engine's source of truth for who can use a
	    weapon — auto-handles cross-career weapons like the flail, and any new
	    career such as Necromancer)
	  - resolve display name / icon / 3D units / illusions from item data
	  - derive attack chains via _ba_attack_labeler

	Lazy: caches build on first use.
]]

local mod = get_mod("gut")
local labeler = mod:dofile("scripts/mods/gui_tweaker/_ba_attack_labeler")

local M = {
	_built = false,
	_by_hero = {},
	_meta = {},
	_skins = {},
}

local HEROES = { "es", "dr", "we", "wh", "bw" }

local IGNORED_ITEM_TYPES = {
	hat = true, skin = true, hood = true, tutorial = true,
	magic = true, weapon_skin = true,
}

local function is_weapon(item_name, item)
	if type(item) ~= "table" then
		return false
	end
	if not item.has_power_level then
		return false
	end
	if item.slot_type ~= "melee" and item.slot_type ~= "ranged" then
		return false
	end
	if IGNORED_ITEM_TYPES[item.item_type] then
		return false
	end
	if string.find(item_name, "_%d%d%d%d") or string.find(item_name, "_preview") then
		return false
	end
	return true
end

local function build_meta(item_name, item)
	return {
		item_name = item_name,
		display_name = Localize(item.display_name),
		display_name_key = item.display_name,
		inventory_icon = item.inventory_icon,
		hud_icon = item.hud_icon,
		slot_type = item.slot_type,
		template = item.template,
		right_hand_unit = item.right_hand_unit,
		left_hand_unit = item.left_hand_unit,
		rarity = item.rarity,
		can_wield = item.can_wield,
	}
end

function M.build()
	if M._built then
		return
	end

	local iml = rawget(_G, "ItemMasterList")
	if not iml then
		mod:error("[ba_weapon] ItemMasterList not available")
		return
	end

	local by_hero_set = {}
	for _, h in ipairs(HEROES) do
		by_hero_set[h] = {}
	end

	for item_name, item in pairs(iml) do
		if is_weapon(item_name, item) then
			M._meta[item_name] = build_meta(item_name, item)

			if type(item.can_wield) == "table" then
				local seen = {}
				for _, career in ipairs(item.can_wield) do
					local hero = string.sub(career, 1, 2)
					if by_hero_set[hero] and not seen[hero] then
						seen[hero] = true
						by_hero_set[hero][item_name] = true
					end
				end
			end
		elseif type(item) == "table" and item.item_type == "weapon_skin" and item.matching_item_key then
			local base = item.matching_item_key
			M._skins[base] = M._skins[base] or {}
			M._skins[base][#M._skins[base] + 1] = item_name
		end
	end

	for _, hero in ipairs(HEROES) do
		local names = {}
		for item_name, _ in pairs(by_hero_set[hero]) do
			names[#names + 1] = item_name
		end
		table.sort(names, function(a, b)
			local ma, mb = M._meta[a], M._meta[b]
			if ma.slot_type ~= mb.slot_type then
				return ma.slot_type < mb.slot_type
			end
			return (ma.display_name or a) < (mb.display_name or b)
		end)
		local list = {}
		for _, item_name in ipairs(names) do
			list[#list + 1] = M._meta[item_name]
		end
		M._by_hero[hero] = list
	end

	M._built = true

	local total = 0
	for _, hero in ipairs(HEROES) do
		total = total + #M._by_hero[hero]
	end
	mod:info("[ba_weapon] enumerated %d weapon slots across %d heroes", total, #HEROES)
end

function M.get_heroes()
	return HEROES
end

function M.get_by_hero(hero)
	M.build()
	return M._by_hero[hero] or {}
end

function M.get_meta(item_name)
	M.build()
	return M._meta[item_name]
end

function M.get_skins(item_name)
	M.build()
	return M._skins[item_name] or {}
end

function M.get_chains(item_name)
	M.build()
	local meta = M._meta[item_name]
	if not meta then
		return nil
	end
	local weapons = rawget(_G, "Weapons")
	local template = weapons and weapons[meta.template]
	if not template then
		return nil
	end
	if meta.slot_type == "ranged" then
		return labeler.ranged_chains(template)
	end
	return labeler.melee_chains(template)
end

-- ============================================================================
-- Live weapon STATS extraction (game-sourced; no hardcoded numbers). Feeds the
-- Armory in-menu window (_ba_armory_window). Every value is READ from the weapon
-- template / DamageProfileTemplates / an engine util, mirroring how the standalone
-- Armory sourced them -- see misc-vermintide-mods/Armory/_recovered. Fields verified
-- against Vermintide-2-Source-Code/scripts/settings/equipment/weapon_templates/
-- (e.g. 2h_hammers.lua:1253-1267 dodge/block/stamina, grudge_raker.lua:152 ammo_data).
-- ============================================================================

-- Base (non per-attack) template stats. Nil fields = not applicable / absent; the
-- window renders only the present ones. No power-level dependency here.
function M.get_base_stats(item_name)
	M.build()
	local meta = M._meta[item_name]
	if not meta then return nil end
	local weapons = rawget(_G, "Weapons")
	local template = weapons and weapons[meta.template]
	if not template then return nil end

	local stats = { slot_type = meta.slot_type }

	-- Dodge (present on both melee + ranged templates).
	stats.dodge_count = template.dodge_count or 1
	local dodge_buff = template.buffs and template.buffs.change_dodge_distance
	local dodge_mult = dodge_buff and dodge_buff.external_optional_multiplier
	stats.dodge_bonus = dodge_mult and (dodge_mult * 100 - 100) or 0

	if meta.slot_type == "melee" then
		-- max_fatigue_points is the raw fatigue pool; the in-game "stamina shields"
		-- count is half of it (each shield = 2 fatigue points).
		stats.stamina = template.max_fatigue_points and (template.max_fatigue_points / 2) or nil
		stats.block_angle = template.block_angle
		stats.block_inner = template.block_fatigue_point_multiplier or 1
		stats.block_outer = template.outer_block_fatigue_point_multiplier or 2
		local push = template.actions and template.actions.action_one and template.actions.action_one.push
		if push then
			stats.push_radius = math.max(push.push_radius or 0, 2.5)
			stats.push_angle = push.push_angle
			stats.outer_push_angle = push.outer_push_angle
		end
	else
		if template.ammo_data then
			stats.max_ammo = template.ammo_data.max_ammo
			stats.ammo_per_clip = template.ammo_data.ammo_per_clip or 1
			stats.reload_time = template.ammo_data.ammo_immediately_available and 0 or template.ammo_data.reload_time
		elseif template.overcharge_data then
			stats.max_overcharge = template.overcharge_data.max_value or 40
		end
	end

	return stats
end

-- The damage profile a given action drives (mirrors the reference fallback order).
local function _action_damage_profile_name(action)
	return action.damage_profile
		or action.damage_profile_right
		or (action.impact_data and action.impact_data.damage_profile)
end

-- Human-meaningful attack traits read straight off the action + its damage profile
-- (crit bonus, damage-over-time kind, area damage, cleave/linesman class). No power
-- level involved. Mirrors the standalone Armory's _get_special_property.
local function _special_props(action, damage_profile)
	local out = {}
	local crit = action.additional_critical_strike_chance
	if crit and crit > 0 then
		out[#out + 1] = string.format("+%d%% Crit", math.floor(crit * 100 + 0.5))
	end
	local dot
	if damage_profile then
		local ts = damage_profile.targets and (damage_profile.targets[1] or damage_profile.targets[2])
		dot = (ts and ts.dot_template_name)
			or (damage_profile.default_target and damage_profile.default_target.dot_template_name)
	end
	if dot then
		if string.find(dot, "bleed") then out[#out + 1] = "Bleeds" end
		if string.find(dot, "burning") or string.find(dot, "deus_01_dot") then out[#out + 1] = "Burns" end
		if string.find(dot, "poison") then out[#out + 1] = "Poisons" end
	end
	if action.impact_data and action.impact_data.aoe then
		out[#out + 1] = "Area Damage"
	end
	if action.hit_mass_count then
		if action.hit_mass_count.skaven_storm_vermin_with_shield then
			out[#out + 1] = "Tank"
		elseif action.hit_mass_count.chaos_warrior then
			out[#out + 1] = "Heavy Linesman"
		else
			out[#out + 1] = "Linesman"
		end
	end
	return table.concat(out, ", ")
end

-- One attack row: label + damage-profile name + cleave target counts + traits.
-- `cleave_power_level` is the caller's live, already-scaled cleave power (from
-- ActionUtils.scale_power_levels); nil => cleave omitted. get_max_targets is the
-- engine's own cleave function (action_utils.lua:22).
local function _attack_row(label, action, cleave_power_level)
	if not action then
		return { label = label, profile = "?", special = "" }
	end
	local dpt = rawget(_G, "DamageProfileTemplates")
	local dp_name = _action_damage_profile_name(action)
	local dp = dp_name and dpt and dpt[dp_name]
	local cleave_damage, cleave_stagger
	local action_utils = rawget(_G, "ActionUtils")
	if dp and cleave_power_level and action_utils and action_utils.get_max_targets then
		local ok, a, b = pcall(action_utils.get_max_targets, dp, cleave_power_level)
		if ok then
			cleave_damage, cleave_stagger = a, b
		end
	end
	return {
		label = label,
		profile = dp_name or "?",
		cleave_damage = cleave_damage,
		cleave_stagger = cleave_stagger,
		special = _special_props(action, dp),
	}
end

-- Ordered attack rows for a weapon (melee: light/heavy/push; ranged: primary +
-- alternate), reusing the labeler's game-derived chains.
function M.get_attack_rows(item_name, cleave_power_level)
	M.build()
	local meta = M._meta[item_name]
	if not meta then return {} end
	local weapons = rawget(_G, "Weapons")
	local template = weapons and weapons[meta.template]
	if not template or not template.actions then return {} end

	local a1 = template.actions.action_one or {}
	local a2 = template.actions.action_two or {}
	local rows = {}

	if meta.slot_type == "melee" then
		local chains = labeler.melee_chains(template)
		for i, name in ipairs(chains.light) do
			rows[#rows + 1] = _attack_row("Light Attack " .. i, a1[name], cleave_power_level)
		end
		for i, name in ipairs(chains.heavy) do
			rows[#rows + 1] = _attack_row("Heavy Attack " .. i, a1[name], cleave_power_level)
		end
		if chains.push then
			rows[#rows + 1] = _attack_row("Push Attack", a1.push, cleave_power_level)
		end
	else
		local chains = labeler.ranged_chains(template)
		for _, pair in ipairs(chains.ranged) do
			rows[#rows + 1] = _attack_row(pair[2], a1[pair[1]], cleave_power_level)
		end
		for _, pair in ipairs(chains.alternate) do
			rows[#rows + 1] = _attack_row(pair[2], a1[pair[1]] or a2[pair[1]], cleave_power_level)
		end
	end

	return rows
end

-- Paste-ready console dump for verifying the live enumeration in-game.
function M.dump()
	M.build()
	mod:echo("[Armory] live weapon enumeration (from ItemMasterList):")
	for _, hero in ipairs(HEROES) do
		local list = M._by_hero[hero]
		mod:echo("  -- %s (%d) --", hero, #list)
		for _, m in ipairs(list) do
			local chains = M.get_chains(m.item_name)
			local chain_summary = ""
			if chains then
				if m.slot_type == "ranged" then
					chain_summary = ("ranged=%d alt=%d"):format(#(chains.ranged or {}), #(chains.alternate or {}))
				else
					chain_summary = ("L=%d H=%d%s"):format(#(chains.light or {}), #(chains.heavy or {}), chains.push and " +push" or "")
				end
			end
			mod:echo("    %s  [%s]  %s  skins=%d  %s",
				m.item_name, tostring(m.display_name), m.slot_type,
				#M.get_skins(m.item_name), chain_summary)
		end
	end
end

return M
