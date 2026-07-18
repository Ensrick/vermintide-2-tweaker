-- _cwv_profile_package_wire.lua
--
-- ProfileSynchronizer advertises package identities before equipment RPCs are
-- allowed to spawn a remote husk.  CWV already substitutes a variant's vanilla
-- base item on the loadout/equipment wire for peers without CWV; this policy
-- keeps the accompanying third-person package manifest on that same identity.
-- First-person packages remain authored so the local owner keeps the variant.
local M = {}
M._markers = setmetatable({}, { __mode = "k" })

local function career_unit(item, field, career_name)
	local overrides = item and item[field .. "_override"]
	return type(overrides) == "table" and overrides[career_name] or item and item[field]
end

function M.resolve_base_units(base_item, career_name)
	if type(base_item) ~= "table" then return nil end
	local units = {
		left_hand_unit = career_unit(base_item, "left_hand_unit", career_name),
		right_hand_unit = career_unit(base_item, "right_hand_unit", career_name),
		ammo_unit = base_item.ammo_unit,
		ammo_unit_3p = base_item.ammo_unit_3p,
		projectile_units_template = base_item.projectile_units_template,
		pickup_template_name = base_item.pickup_template_name,
		link_pickup_template_name = base_item.link_pickup_template_name,
		is_ammo_weapon = base_item.is_ammo_weapon,
		unit = base_item.unit,
		material = base_item.material,
		icon = base_item.hud_icon,
	}
	if not units.left_hand_unit and not units.right_hand_unit and not units.ammo_unit then
		return nil
	end
	return units
end

function M.mark(markers, item_units, variant_key, base_item_key)
	if type(markers) ~= "table" or type(item_units) ~= "table"
			or type(variant_key) ~= "string" or variant_key == ""
			or type(base_item_key) ~= "string" or base_item_key == "" then
		return false
	end
	markers[item_units] = {
		variant_key = variant_key,
		base_item_key = base_item_key,
	}
	return true
end

-- Return the inputs that WeaponUtils.get_weapon_packages should collect.  A
-- miss always returns the original inputs so unrelated/native package maps are
-- byte-for-byte unchanged.
function M.select_inputs(item_template, item_units, first_person, career_name,
		markers, item_master_list, resolve_template)
	if first_person or type(markers) ~= "table" or type(item_units) ~= "table" then
		return item_template, item_units, false
	end
	local marker = markers[item_units]
	local base_key = marker and marker.base_item_key
	local base_item = type(item_master_list) == "table" and type(base_key) == "string"
		and rawget(item_master_list, base_key) or nil
	if type(base_item) ~= "table" or type(resolve_template) ~= "function" then
		return item_template, item_units, false
	end
	local ok, base_template = pcall(resolve_template, base_item)
	local base_units = M.resolve_base_units(base_item, career_name)
	if not ok or type(base_template) ~= "table" or not base_units then
		return item_template, item_units, false
	end
	return base_template, base_units, true, marker
end

function M.mark_runtime(item_units, variant_key, base_item_key)
	return M.mark(M._markers, item_units, variant_key, base_item_key)
end

-- Runtime adapter consumed by the already-singleton WeaponUtils package hook.
function M.select_package_inputs(item_template, item_units, first_person, career_name)
	local selected_template, selected_units, shadowed, marker = M.select_inputs(
		item_template, item_units, first_person, career_name, M._markers,
		ItemMasterList, function(base_item)
			return BackendUtils.get_item_template(base_item)
		end)
	if shadowed then
		printf("[cwv:491] profile package shadow: %s -> %s (career=%s perspective=3p)",
			tostring(marker.variant_key), tostring(marker.base_item_key),
			tostring(career_name))
	end
	return selected_template, selected_units
end

return M
