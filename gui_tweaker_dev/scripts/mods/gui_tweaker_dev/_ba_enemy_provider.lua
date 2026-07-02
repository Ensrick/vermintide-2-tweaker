--[[
	_ba_enemy_provider.lua  (Bestiary & Armory feature, migrated into gut)

	PURE-DYNAMIC enemy data layer for the Bestiary. Replaces the original
	Bestiary's hardcoded breed roster + icon-slot tables (Bestiary_enemy_data.lua)
	with a live enumeration of `Breeds`, filtered to combat AI breeds. Per-breed
	attribute resolution is ported verbatim from the original (it shipped
	working) — only the ROSTER is now dynamic, so newer breeds (Beastmen,
	undead/Belakor, chaos_bulwark, DLC specials) appear for free.

	Health / hit-mass / stagger are difficulty-scaled ARRAYS indexed by the
	current difficulty rank (DifficultySettings rank field; verified
	breed_tweaks.lua + original HeroViewStateBestiary.lua:640-670). We store the
	raw arrays and let the view index by the selected difficulty rank.

	Lazy: caches build on first `M.build()`.
]]

local mod = get_mod("gut_dev")

local M = {
	_built = false,
	_entries = {},
	_order = {},
	_by_race = {},
	_variants = {},
}

-- Editorial label for the numeric armor_category (1..6 enum; not a roster).
local ARMOR_CATEGORY_NAMES = { "Infantry", "Armored", "Monster", "", "Berserker", "Fully Armored" }

local ENEMY_RACES = { skaven = true, chaos = true, beastmen = true, undead = true }
local RACE_ORDER = { "skaven", "chaos", "beastmen", "undead" }
local VARIANT_SUFFIXES = { "_with_shield", "_commander", "_warlord", "_boss" }

local function prettify(s)
	s = string.gsub(s, "_", " ")
	s = string.gsub(s, "(%a)([%w_]*)", function(a, b) return string.upper(a) .. b end)
	return s
end

local function localize_breed(breed_name, breed)
	local key = breed.dialogue_source_name or breed_name
	local s = Localize(key)
	if not s or s == "" or s == key or string.find(s, "^<") then
		return prettify(breed_name)
	end
	return s
end

local function breed_texture(breed_name, breed)
	local bt = rawget(_G, "UISettings") and UISettings.breed_textures or nil

	if bt then
		if bt[breed_name] then
			return bt[breed_name]
		end

		local aliases = UISettings.alias_to_breed
		if aliases and aliases[breed_name] and bt[aliases[breed_name]] then
			return bt[aliases[breed_name]]
		end

		local race = breed.race
		if race == "chaos" then
			return bt.chaos_warrior or bt.chaos_marauder
		elseif race == "skaven" then
			return bt.skaven_clan_rat or bt.skaven_slave
		elseif race == "beastmen" then
			return bt.beastmen_gor or bt.beastmen_standard_bearer
		elseif race == "undead" then
			return bt.chaos_warrior or bt.skaven_clan_rat
		end

		return bt.skaven_clan_rat
	end

	return nil
end

local function is_enemy_breed(breed_name, breed)
	if type(breed) ~= "table" then
		return false
	end
	if not breed.is_ai then
		return false
	end
	if not ENEMY_RACES[breed.race] then
		return false
	end
	if breed.not_bot_target or breed.cannot_be_aggroed then
		return false
	end
	if string.find(breed_name, "^pet_") then
		return false
	end
	return true
end

local function build_entry(breed_name, breed)
	local LINESMAN = rawget(_G, "LINESMAN_HIT_MASS_COUNT")
	local TANK = rawget(_G, "TANK_HIT_MASS_COUNT")
	local HEAVY_LINESMAN = rawget(_G, "HEAVY_LINESMAN_HIT_MASS_COUNT")

	return {
		breed_name = breed_name,
		name = localize_breed(breed_name, breed),
		race = breed.race,
		armor_category = ARMOR_CATEGORY_NAMES[breed.armor_category],
		armor_category_index = breed.armor_category,
		boss = breed.boss,
		elite = breed.elite,
		special = breed.special,
		health = breed.max_health,
		hit_mass = breed.hit_mass_counts or breed.hit_mass_count or 1,
		block_mass = breed.hit_mass_counts_block or breed.hit_mass_count_block,
		stagger_resist = breed.diff_stagger_resist or breed.stagger_resistance or 2,
		linesman_mod = LINESMAN and LINESMAN[breed_name],
		tank_mod = TANK and TANK[breed_name],
		heavy_linesman_mod = HEAVY_LINESMAN and HEAVY_LINESMAN[breed_name],
		man_sized = not breed.boss and not breed.primary_armor_category,
		base_unit = breed.base_unit,
		inventory_template = breed.default_inventory_template,
		texture = breed_texture(breed_name, breed),
		size_variation = breed.size_variation_range,
	}
end

local function build_variants(entries)
	local variants = {}
	for breed_name, _ in pairs(entries) do
		for _, suffix in ipairs(VARIANT_SUFFIXES) do
			if string.sub(breed_name, -#suffix) == suffix then
				local base = string.sub(breed_name, 1, #breed_name - #suffix)
				if entries[base] then
					variants[base] = variants[base] or { base }
					variants[base][#variants[base] + 1] = breed_name
					break
				end
			end
		end
	end
	return variants
end

function M.build()
	if M._built then
		return
	end

	local breeds = rawget(_G, "Breeds")
	if not breeds then
		mod:error("[ba_enemy] Breeds global not available")
		return
	end

	local entries, order = {}, {}
	for breed_name, breed in pairs(breeds) do
		if is_enemy_breed(breed_name, breed) then
			entries[breed_name] = build_entry(breed_name, breed)
			order[#order + 1] = breed_name
		end
	end

	table.sort(order)

	local by_race = {}
	for _, race in ipairs(RACE_ORDER) do
		by_race[race] = {}
	end
	for _, breed_name in ipairs(order) do
		local entry = entries[breed_name]
		by_race[entry.race] = by_race[entry.race] or {}
		local list = by_race[entry.race]
		list[#list + 1] = entry
	end

	M._entries = entries
	M._order = order
	M._by_race = by_race
	M._variants = build_variants(entries)
	M._built = true

	mod:info("[ba_enemy] enumerated %d enemy breeds across %d races", #order, #RACE_ORDER)
end

function M.get_entry(breed_name)
	M.build()
	return M._entries[breed_name]
end

function M.get_by_race(race)
	M.build()
	return M._by_race[race] or {}
end

function M.get_order()
	M.build()
	return M._order
end

function M.get_variants(breed_name)
	M.build()
	return M._variants[breed_name]
end

function M.get_race_order()
	return RACE_ORDER
end

-- Paste-ready console dump for verifying the live enumeration in-game.
function M.dump()
	M.build()
	mod:echo("[Bestiary] %d enemy breeds enumerated (live from Breeds):", #M._order)
	for _, race in ipairs(RACE_ORDER) do
		local list = M._by_race[race] or {}
		mod:echo("  -- %s (%d) --", race, #list)
		for _, e in ipairs(list) do
			local flags = {}
			if e.boss then flags[#flags + 1] = "boss" end
			if e.elite then flags[#flags + 1] = "elite" end
			if e.special then flags[#flags + 1] = "special" end
			local variant = M._variants[e.breed_name] and (" +%d variants"):format(#M._variants[e.breed_name] - 1) or ""
			mod:echo("    %s  [%s]  armor=%s%s%s",
				e.breed_name, e.name, tostring(e.armor_category), variant,
				(#flags > 0 and (" {" .. table.concat(flags, ",") .. "}") or ""))
		end
	end
end

return M
