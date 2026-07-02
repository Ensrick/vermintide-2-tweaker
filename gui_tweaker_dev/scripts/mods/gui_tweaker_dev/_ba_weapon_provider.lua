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

local mod = get_mod("gut_dev")
local labeler = mod:dofile("scripts/mods/gui_tweaker_dev/_ba_attack_labeler")

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
