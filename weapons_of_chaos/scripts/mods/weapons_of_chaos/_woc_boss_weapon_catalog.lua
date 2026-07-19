-- _woc_boss_weapon_catalog.lua - the single WOC boss-weapon catalogue owner.
--
-- Two deliberately separate facets share this module:
--   SOURCE_ROWS + audit(): read-only proof of the vanilla breed, inventory,
--     and enemy unit path. This facet never spawns or loads a unit.
--   get()/all() + registration_readiness(): mod-owned relic descriptors and
--     fail-closed authored-resource readiness.
--
-- Keeping both facets here prevents source diagnostics and relic registration
-- from drifting into competing catalogues. Keep trophy prop paths are absent:
-- those diorama units are not wieldable weapons.

local M = {}

local rows = {
	blightreaper = {
		issue = 613,
		item_key = "woc_blightreaper",
		backend_id = "woc_blightreaper_001",
		base_weapon = "es_1h_sword",
		base_template = "we_one_hand_sword_template_1",
		wire_fallback = "es_1h_sword",
		native_units = {
			right = "units/weapons/player/wpn_emp_sword_02_t1/wpn_emp_sword_02_t1",
		},
		authored_units = {
			right_1p = "units/woc_blightreaper/blightreaper",
			right_3p = "units/woc_blightreaper/blightreaper_3p",
		},
		asset = {
			stage = "compiled",
		},
		registration_enabled = true,
	},
	skarrik_halberd = {
		issue = 614,
		item_key = "woc_skarrik_halberd",
		backend_id = "woc_skarrik_halberd_001",
		base_weapon = "es_halberd",
		base_template = "two_handed_halberds_template_1",
		wire_fallback = "es_halberd",
		native_units = {
			right = "units/weapons/enemy/wpn_skaven_set/wpn_skaven_halberd_stormvermin_champion",
		},
		authored_units = {
			right_1p = "units/woc_skarrik_halberd/skarrik_halberd",
			right_3p = "units/woc_skarrik_halberd/skarrik_halberd_3p",
		},
		asset = {
			stage = "authored",
			export_file = "skarrik_halberd.fbx",
			export_sha256 = "4BDA4ED14BDA32B3560BCB7BF0BF256274539BE67ECEECD4D0B9A7713180865F",
			-- #615 proves and owns Skarrik's shared material/texture closure.
			-- The halberd units reference it rather than packaging a second copy.
			material = "units/woc_skarrik_dual_swords/skarrik_swords",
			material_owner_issue = 615,
			texture_hashes = {
				"A9D9E4D3A8440FF5",
				"28E105E0AD31F399",
			},
		},
		registration_enabled = false,
	},
	skarrik_dual_swords = {
		issue = 615,
		item_key = "woc_skarrik_dual_swords",
		backend_id = "woc_skarrik_dual_swords_001",
		base_weapon = "we_dual_wield_swords",
		base_template = "dual_wield_swords_template_1",
		wire_fallback = "we_dual_wield_swords",
		native_units = {
			right = "units/weapons/enemy/wpn_skaven_set/wpn_skaven_sword_dual_right",
			left = "units/weapons/enemy/wpn_skaven_set/wpn_skaven_sword_dual_left",
		},
		authored_units = {
			right_1p = "units/woc_skarrik_dual_swords/skarrik_sword_right",
			right_3p = "units/woc_skarrik_dual_swords/skarrik_sword_right_3p",
			left_1p = "units/woc_skarrik_dual_swords/skarrik_sword_left",
			left_3p = "units/woc_skarrik_dual_swords/skarrik_sword_left_3p",
		},
		asset = {
			stage = "exported",
			exports = {
				left = {
					file = "skarrik_sword_left.fbx",
					sha256 = "1A8D57C6744D22C9CAA80DE26BF62D369D98FFF3FE73B0895B54FC69252068AF",
				},
				right = {
					file = "skarrik_sword_right.fbx",
					sha256 = "FAD2FF7065C878DE9CEB6BF11750776DD325B958F38BAEBDD3255F63B2C8649E",
				},
			},
			material = "units/weapons/enemy/wpn_skaven_set/wpn_skaven_set",
		},
		registration_enabled = false,
	},
	nurgloth_scythe = {
		issue = 642,
		item_key = "woc_nurgloth_scythe",
		native_units = {
			right = "units/weapons/enemy/wpn_chaos_sorcerer_scythe/wpn_chaos_sorcerer_scythe_01",
		},
		asset = {
			stage = "exported",
			export_file = "nurgloth_scythe.fbx",
			export_sha256 = "B2D9954959B393BC128CECFBE285F05A39583419B3519E6ACB515D9937BDEBA5",
		},
		registration_enabled = false,
	},
	burblespue_staff = {
		issue = 642,
		item_key = "woc_burblespue_staff",
		native_units = {
			right = "units/weapons/enemy/wpn_chaos_sorcerer_stick/wpn_sorcerer_stick",
		},
		asset = {
			stage = "exported",
			export_file = "burblespue_staff.fbx",
			export_sha256 = "C5A441007407508F15C860112A9BFDD7C773FC51A6019EA94B6C6CC040F1C421",
		},
		registration_enabled = false,
	},
	bodvarr_axe = {
		issue = 642,
		item_key = "woc_bodvarr_axe",
		native_units = {
			right = "units/weapons/enemy/wpn_chaos_set/wpn_chaos_2h_axe_03",
		},
		asset = {
			stage = "exported",
			export_file = "bodvarr_greataxe.fbx",
			export_sha256 = "5157AB43ECC8CB90A160C9CBF116BAD11648691F11911C700431ADA138B9EF6B",
		},
		registration_enabled = false,
	},
}

local order = {
	"blightreaper",
	"skarrik_halberd",
	"skarrik_dual_swords",
	"nurgloth_scythe",
	"burblespue_staff",
	"bodvarr_axe",
}

-- Read-only source facet. `unit` is the exact enemy inventory unit proven in
-- the decompile; it is evidence, never a package-load or spawn instruction.
M.SOURCE_ROWS = {
	{
		id = "nurgloth_scythe",
		name = "Nurgloth's Scythe",
		issue = 642,
		breed = "chaos_exalted_sorcerer_drachenfels",
		inventory = "chaos_exalted_sorcerer_drachenfels",
		unit = "units/weapons/enemy/wpn_chaos_sorcerer_scythe/wpn_chaos_sorcerer_scythe_01",
	},
	{
		id = "burblespue_staff",
		name = "Burblespue's Staff",
		issue = 642,
		breed = "chaos_exalted_sorcerer",
		inventory = "chaos_exalted_sorcerer",
		unit = "units/weapons/enemy/wpn_chaos_sorcerer_stick/wpn_sorcerer_stick",
	},
	{
		id = "bodvarr_axe",
		name = "Bodvarr's Axe",
		issue = 642,
		breed = "chaos_exalted_champion_warcamp",
		inventory = "exalted_axe",
		unit = "units/weapons/enemy/wpn_chaos_set/wpn_chaos_2h_axe_03",
	},
	{
		id = "skarrik_halberd",
		name = "Skarrik's Halberd",
		issue = 614,
		breed = "skaven_storm_vermin_warlord",
		inventory = "warlord_dual_setups",
		unit = "units/weapons/enemy/wpn_skaven_set/wpn_skaven_halberd_stormvermin_champion",
	},
	{
		id = "skarrik_sword_left",
		name = "Skarrik's Left Sword",
		issue = 615,
		breed = "skaven_storm_vermin_warlord",
		inventory = "warlord_dual_setups",
		unit = "units/weapons/enemy/wpn_skaven_set/wpn_skaven_sword_dual_left",
	},
	{
		id = "skarrik_sword_right",
		name = "Skarrik's Right Sword",
		issue = 615,
		breed = "skaven_storm_vermin_warlord",
		inventory = "warlord_dual_setups",
		unit = "units/weapons/enemy/wpn_skaven_set/wpn_skaven_sword_dual_right",
	},
	{
		id = "rasknitt_deferred",
		name = "Rasknitt",
		issue = "deferred",
		breed = "skaven_grey_seer",
		inventory = false,
		unit = false,
	},
}
-- Compatibility alias for #642's initial diagnostics consumer. New code should
-- use SOURCE_ROWS so the facet is explicit.
M.ROWS = M.SOURCE_ROWS

local function collect_source_units(inventories, config_name, out, seen)
	if type(config_name) ~= "string" or seen[config_name] then return end
	seen[config_name] = true
	local config = inventories and inventories[config_name]
	if type(config) ~= "table" then return end

	local variants = config.multiple_configurations
	if type(variants) == "table" then
		for i = 1, #variants do
			collect_source_units(inventories, variants[i], out, seen)
		end
	end

	local categories = config.items
	if type(categories) ~= "table" then return end
	for i = 1, #categories do
		local category = categories[i]
		if type(category) == "table" then
			for j = 1, #category do
				local item = category[j]
				if type(item) == "table" and type(item.unit_name) == "string" then
					out[item.unit_name] = true
				end
			end
		end
	end
end

function M.audit(args)
	args = args or {}
	local breeds = args.breeds or {}
	local inventories = args.inventories or {}
	local is_resident = args.is_resident
	local results = {}

	for i = 1, #M.SOURCE_ROWS do
		local expected = M.SOURCE_ROWS[i]
		local breed = breeds[expected.breed]
		local actual_inventory = breed and breed.default_inventory_template or nil
		local no_inventory = breed and breed.has_inventory == false
		local units = {}
		if type(actual_inventory) == "string" then
			collect_source_units(inventories, actual_inventory, units, {})
		end

		local inventory_match
		local unit_match
		local status
		if expected.inventory == false then
			inventory_match = actual_inventory == nil and no_inventory == true
			unit_match = false
			status = inventory_match and "deferred_no_inventory" or "source_drift"
		else
			inventory_match = actual_inventory == expected.inventory
			unit_match = units[expected.unit] == true
			status = breed and inventory_match and unit_match
				and "source_mapped" or "source_drift"
		end

		local resident = nil
		if expected.unit and type(is_resident) == "function" then
			local ok, value = pcall(is_resident, expected.unit)
			resident = ok and value == true or false
		end

		results[#results + 1] = {
			id = expected.id,
			name = expected.name,
			issue = expected.issue,
			breed = expected.breed,
			breed_present = type(breed) == "table",
			expected_inventory = expected.inventory,
			actual_inventory = actual_inventory,
			inventory_match = inventory_match,
			expected_unit = expected.unit,
			unit_match = unit_match,
			resident = resident,
			status = status,
		}
	end

	return results
end

local function runtime_resident(unit_name)
	local package_manager = Managers and Managers.package
	if not package_manager or type(package_manager.has_loaded) ~= "function" then
		return false
	end
	return package_manager:has_loaded(unit_name)
end

function M.runtime_snapshot()
	return M.audit({
		breeds = rawget(_G, "Breeds"),
		inventories = rawget(_G, "InventoryConfigurations"),
		is_resident = runtime_resident,
	})
end

function M.emit_runtime()
	local results = M.runtime_snapshot()
	for i = 1, #results do
		local row = results[i]
		printf(
			"[WOC:642] id=%s issue=%s status=%s breed=%s breed_present=%s inventory=%s expected_inventory=%s inventory_match=%s unit=%s unit_match=%s resident_now=%s",
			tostring(row.id), tostring(row.issue), tostring(row.status),
			tostring(row.breed), tostring(row.breed_present),
			tostring(row.actual_inventory), tostring(row.expected_inventory),
			tostring(row.inventory_match), tostring(row.expected_unit),
			tostring(row.unit_match), tostring(row.resident))
	end
	return results
end

function M.runtime_check()
	local results = M.runtime_snapshot()
	if #results ~= #M.SOURCE_ROWS then return "boss catalogue row count drift" end
	for i = 1, 6 do
		if results[i].status ~= "source_mapped" then
			return results[i].id .. ":" .. tostring(results[i].status)
		end
	end
	if results[7].status ~= "deferred_no_inventory" then
		return "Rasknitt inventory boundary drift"
	end
end

local function copy(value)
	if type(value) ~= "table" then return value end
	local out = {}
	for key, child in pairs(value) do out[copy(key)] = copy(child) end
	return out
end

function M.get(id)
	return rows[id] and copy(rows[id]) or nil
end

function M.all()
	local result = {}
	for i = 1, #order do
		local id = order[i]
		local row = copy(rows[id])
		row.id = id
		result[#result + 1] = row
	end
	return result
end

function M.required_authored_units(row)
	local result = {}
	for _, name in pairs(type(row) == "table" and row.authored_units or {}) do
		if type(name) == "string" then result[#result + 1] = name end
	end
	table.sort(result)
	return result
end

-- Registration is intentionally fail-closed. Exported geometry is not enough:
-- every authored perspective/hand must exist before a row may become active.
function M.registration_readiness(row, resource_exists)
	if type(row) ~= "table" then return false, "missing_descriptor" end
	if row.registration_enabled ~= true then return false, "registration_disabled" end
	if type(row.backend_id) ~= "string" or type(row.base_weapon) ~= "string"
			or type(row.wire_fallback) ~= "string" then
		return false, "identity_incomplete"
	end
	if type(resource_exists) ~= "function" then return false, "resource_probe_missing" end
	local required = M.required_authored_units(row)
	if #required == 0 then return false, "authored_units_missing" end
	for i = 1, #required do
		if not resource_exists(required[i]) then
			return false, "resource_missing:" .. required[i]
		end
	end
	return true
end

-- Observation-only authored-resource facet. This intentionally ignores the
-- registration_enabled switch so a disabled candidate can prove whether its
-- compiled source closure exists before runtime adoption is attempted.
function M.authored_snapshot(resource_exists)
	local results = {}
	for i = 1, #order do
		local id = order[i]
		local row = rows[id]
		local required = M.required_authored_units(row)
		local missing = {}
		for j = 1, #required do
			local present = false
			if type(resource_exists) == "function" then
				local ok, value = pcall(resource_exists, required[j])
				present = ok and value == true
			end
			if not present then missing[#missing + 1] = required[j] end
		end
		results[#results + 1] = {
			id = id,
			issue = row.issue,
			asset_stage = row.asset and row.asset.stage or "untracked",
			registration_enabled = row.registration_enabled == true,
			required = required,
			missing = missing,
			status = #required == 0 and "no_authored_units"
				or #missing == 0 and "authored_resources_present"
				or "authored_resources_missing",
		}
	end
	return results
end

function M.runtime_authored_snapshot()
	local application = rawget(_G, "Application")
	return M.authored_snapshot(function(name)
		if not application or type(application.can_get) ~= "function" then
			return false
		end
		return application.can_get("unit", name)
	end)
end

function M.emit_authored_runtime()
	local results = M.runtime_authored_snapshot()
	for i = 1, #results do
		local row = results[i]
		printf(
			"[WOC:boss-catalog] facet=authored id=%s issue=%s stage=%s status=%s registration_enabled=%s required=%s missing=%s",
			tostring(row.id), tostring(row.issue), tostring(row.asset_stage),
			tostring(row.status), tostring(row.registration_enabled),
			table.concat(row.required, ","), table.concat(row.missing, ","))
	end
	return results
end

return M
