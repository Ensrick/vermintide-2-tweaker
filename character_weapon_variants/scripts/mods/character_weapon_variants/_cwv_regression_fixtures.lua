-- #1656: fixture selection for the /cwv_regression_test identity checks.
--
-- A check fixture must name a definition the registrar actually registers.
-- Registration skips skin_only and cwv_retired definitions
-- (_cwv_item_registration_owner.lua:609), and the identity ladder accepts only
-- registered keys (_registered_cwv_key, same file :130-133). A fixture pinned
-- on a retired key (cwv_es_longsword and cwv_es_longsword_blackguard, retired
-- by #620) therefore resolves to the native record and fails every run without
-- reporting anything about the code under test.
--
-- Generated pair illusions are read from the generator's own output, never
-- composed by hand: their keys are a rarity-sorted zip of the live vanilla skin
-- pools (_cwv_illusion_families.lua:1279-1292) and move when a pool grows.
--
-- Pure and engine-free: the selectors take the live tables as arguments, and
-- the live_* adapters only read the engine globals they would otherwise be
-- handed. Offline proof: qa/lua/tests/test_cwv_regression_harness_1656.lua.
local M = {}

local function nonempty(value)
	return type(value) == "string" and value ~= "" and value or nil
end

local function has_hand_unit(row)
	return type(row) == "table"
		and (nonempty(row.right_hand_unit) or nonempty(row.left_hand_unit)) ~= nil
end

-- The first definition, in authored catalog order, that this session
-- registered as a real melee item: not skin_only, not retired, not cross-slot,
-- cloning a present vanilla melee base, with its own default "<item_key>_skin"
-- WeaponSkins row. Returns { def, key, base, skin } or nil.
function M.registered_owner(definitions, registered_keys, item_master, weapon_skins)
	if type(definitions) ~= "table" or type(registered_keys) ~= "table"
			or type(item_master) ~= "table" then
		return nil
	end
	local skins = type(weapon_skins) == "table" and weapon_skins.skins or nil
	if type(skins) ~= "table" then return nil end
	for _, def in ipairs(definitions) do
		local key = type(def) == "table" and nonempty(def.item_key) or nil
		local base_key = key and nonempty(def.base_weapon) or nil
		local base = base_key and rawget(item_master, base_key) or nil
		local skin = key and key .. "_skin" or nil
		if base_key and not def.skin_only and not def.cwv_retired
				and not def.cross_slot and registered_keys[key]
				and type(base) == "table" and base.slot_type == "melee"
				and has_hand_unit(def) and has_hand_unit(rawget(skins, skin)) then
			return { def = def, key = key, base = base_key, skin = skin }
		end
	end
	return nil
end

-- The lowest-sorting generated pair illusion owned by `owner_item_type`: an
-- ItemMasterList row stamped cwv_owner_item_type whose WeaponSkins row carries
-- both hands. The owner's default "<owner>_skin" is excluded. Returns the key
-- or nil.
function M.generated_pair_skin(item_master, weapon_skins, owner_item_type)
	if type(item_master) ~= "table" or not nonempty(owner_item_type) then return nil end
	local skins = type(weapon_skins) == "table" and weapon_skins.skins or nil
	if type(skins) ~= "table" then return nil end
	local prefix, default = owner_item_type .. "_", owner_item_type .. "_skin"
	local best
	for key, row in pairs(item_master) do
		if type(key) == "string" and key ~= default and key:sub(1, #prefix) == prefix
				and type(row) == "table" and row.cwv_owner_item_type == owner_item_type then
			local skin = rawget(skins, key)
			if type(skin) == "table" and nonempty(skin.right_hand_unit)
					and nonempty(skin.left_hand_unit) and (best == nil or key < best) then
				best = key
			end
		end
	end
	return best
end

function M.live_owner(definitions, registered_keys)
	return M.registered_owner(definitions, registered_keys,
		rawget(_G, "ItemMasterList"), rawget(_G, "WeaponSkins"))
end

function M.live_generated_pair_skin(owner_item_type)
	return M.generated_pair_skin(rawget(_G, "ItemMasterList"),
		rawget(_G, "WeaponSkins"), owner_item_type)
end

return M
