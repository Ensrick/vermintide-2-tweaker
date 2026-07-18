-- _cwv_launcher_family.lua - Outrider Grenade Launcher custom-mesh policy (issue #627).
--
-- The `cwv_es_outrider_grenade_launcher` variant previously borrowed Kruber's
-- vanilla blunderbuss mesh. This module swaps the presentation to a user-supplied
-- custom launcher mesh (converted by tools/convert_launcher_assets.ps1) while
-- keeping the blunderbuss as the wire-safe missing-mod fallback (issues #279/#399).
--
-- Engine-free policy only: it declares the custom unit path and the vanilla
-- blunderbuss package anchors. Runtime hook wiring lives in
-- character_weapon_variants.lua; the render/spawn paths keep the custom unit,
-- only the package-residency and ProfileSynchronizer wire identities borrow the
-- resident vanilla blunderbuss package. Structurally mirrors _cwv_greataxe.lua
-- (issue #597) and _cwv_old_musket_preview.lua, trimmed to a single model.
--
-- Owned by: character_weapon_variants.lua entry point. Consumed via: mod:dofile.
local M = {}

M.ITEM_KEY = "cwv_es_outrider_grenade_launcher"
M.SKIN_KEY = "cwv_es_outrider_grenade_launcher_skin"
M.UNIT = "units/cwv_launcher/launcher_01/launcher_01"
M.UNIT_3P = M.UNIT .. "_3p"

-- Mod-defined package names are not visible to vanilla previewers'
-- Application.resource_package lookup. The custom unit is resident through CWV's
-- master package; previewers borrow this vanilla blunderbuss 3P package as a
-- lifetime/reference anchor. The same forward alias lets an unmodded peer decode
-- our custom path back to the blunderbuss they already render.
M.PREVIEW_PACKAGE_ALIAS =
	"units/weapons/player/wpn_empire_blunderbuss_t1/wpn_empire_blunderbuss_t1_3p"
M.NETWORK_PACKAGE_ALIAS_1P =
	"units/weapons/player/wpn_empire_blunderbuss_t1/wpn_empire_blunderbuss_t1"
M.NETWORK_PACKAGE_ALIAS_3P = M.PREVIEW_PACKAGE_ALIAS

-- Shape consumed by the generic mod-unit preview bridge (_cwv_mod_unit_preview).
M.MODELS = { { key = M.SKIN_KEY, right_hand_unit = M.UNIT } }

function M.is_usable_model(model)
	return type(model) == "table"
		and type(model.right_hand_unit) == "string" and model.right_hand_unit ~= ""
end

function M.usable_models()
	local result = {}
	for _, model in ipairs(M.MODELS) do
		if M.is_usable_model(model) then result[#result + 1] = model end
	end
	return result
end

function M.preview_package_alias(package_name)
	if type(package_name) ~= "string" then return nil end
	for _, model in ipairs(M.MODELS) do
		local unit = model.right_hand_unit
		if type(unit) == "string"
			and (package_name == unit or package_name == unit .. "_3p") then
			return M.PREVIEW_PACKAGE_ALIAS
		end
	end
	return nil
end

-- WeaponUtils.get_weapon_packages is a package-residency collector, not a render
-- resolver. ProfileSynchronizer feeds its return values straight to
-- PackageManager, where a resident mod-bundle unit path is not a loadable package
-- name. Borrow the vanilla blunderbuss identity at this boundary only;
-- BackendUtils.get_item_units and every spawn path retain the custom unit.
function M.collected_package_alias(package_name)
	if type(package_name) ~= "string" then return nil end
	for _, model in ipairs(M.MODELS) do
		local unit = model.right_hand_unit
		if type(unit) == "string" then
			if package_name == unit then return M.NETWORK_PACKAGE_ALIAS_1P end
			if package_name == unit .. "_3p" then return M.NETWORK_PACKAGE_ALIAS_3P end
		end
	end
	return nil
end

function M.alias_collected_packages(package_names)
	if type(package_names) ~= "table" then return package_names, 0 end
	local replaced = 0
	for index = 1, #package_names do
		local alias = M.collected_package_alias(package_names[index])
		if alias then
			package_names[index] = alias
			replaced = replaced + 1
		end
	end
	return package_names, replaced
end

-- ProfileSynchronizer serializes inventory package maps through the vanilla
-- NetworkLookup. Custom Workshop unit paths borrow a stable vanilla index on the
-- forward (name -> index) side only. The reverse (index -> name) mapping stays
-- vanilla, so decoding never asks an unmodded peer to load our unit.
function M.network_package_aliases()
	local result = {}
	for _, model in ipairs(M.MODELS) do
		if M.is_usable_model(model) then
			result[model.right_hand_unit] = M.NETWORK_PACKAGE_ALIAS_1P
			result[model.right_hand_unit .. "_3p"] = M.NETWORK_PACKAGE_ALIAS_3P
		end
	end
	return result
end

function M.install_network_package_aliases(inventory_lookup)
	if type(inventory_lookup) ~= "table" then return 0 end
	local installed = 0
	for custom_path, vanilla_path in pairs(M.network_package_aliases()) do
		local vanilla_index = rawget(inventory_lookup, vanilla_path)
		if type(vanilla_index) == "number" then
			inventory_lookup[custom_path] = vanilla_index
			installed = installed + 1
		end
	end
	return installed
end

return M
