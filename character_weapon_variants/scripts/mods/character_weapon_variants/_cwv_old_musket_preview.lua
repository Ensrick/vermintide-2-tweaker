-- Canonical preview-resource policy for the Old Musket.
--
-- The custom mesh and its PBR material live in CWV's resident master bundle;
-- neither is a globally discoverable standalone package. Every preview surface
-- consumes this descriptor and borrows the vanilla handgun package only as a
-- balanced package-manager lifetime anchor. The borrowed package is never the
-- material owner: unit, material, textures and transform are one self-contained
-- Old Musket appearance closure (#1155).
local M = {}
local RESIDENCY

function M.set_resource_residency(contract)
	RESIDENCY = contract
	return type(RESIDENCY) == "table" and RESIDENCY.VERSION or nil
end

M.ITEM_KEY = "cwv_es_musket_old"
M.SKIN_KEY = "cwv_es_musket_old_skin"
M.UNIT = "units/cwv_es_musket_custom/cwv_es_musket_custom"
M.UNIT_3P = M.UNIT .. "_3p"
M.PREVIEW_PACKAGE_ALIAS =
	"units/weapons/player/wpn_empire_handgun_t1/wpn_empire_handgun_t1_3p"
M.NETWORK_PACKAGE_ALIAS_1P =
	"units/weapons/player/wpn_empire_handgun_t1/wpn_empire_handgun_t1"
M.NETWORK_PACKAGE_ALIAS_3P = M.PREVIEW_PACKAGE_ALIAS
M.MATERIAL = "units/cwv_es_musket_custom/cwv_es_musket_custom"
-- Compatibility name for the cross-mod descriptor consumer. It now points at
-- the authored material, never at the borrowed package alias.
M.PREVIEW_MATERIAL = M.MATERIAL
M.TEXTURES = {
	{ slot = "color_map", texture = "textures/cwv_es_musket_custom/cwv_es_musket_custom_albedo" },
	{ slot = "normal_map", texture = "textures/cwv_es_musket_custom/cwv_es_musket_custom_normal" },
	{ slot = "roughness_map", texture = "textures/cwv_es_musket_custom/cwv_es_musket_custom_roughness" },
	{ slot = "metallic_map", texture = "textures/cwv_es_musket_custom/cwv_es_musket_custom_metallic" },
	{ slot = "ao_map", texture = "textures/cwv_es_musket_custom/cwv_es_musket_custom_ao" },
}

-- Shape consumed by the generic mod-unit preview bridge.
M.MODELS = { { right_hand_unit = M.UNIT } }

local function item_identity(item, canonical_key)
	if type(item) ~= "table" then return nil, nil end
	local data = type(item.data) == "table" and item.data or {}
	local custom = type(item.CustomData) == "table" and item.CustomData
		or (type(data.CustomData) == "table" and data.CustomData)
	local mod_data = type(item.mod_data) == "table" and item.mod_data
		or (type(data.mod_data) == "table" and data.mod_data)
	local key = canonical_key
		or item.cim_acquisition_key or data.cim_acquisition_key
		or (custom and custom.cim_acquisition_key)
		or data.cwv_key or item.cwv_key or (mod_data and mod_data.cwv_key)
		or (custom and custom.cwv_key)
		or item.key or item.ItemId or data.key or data.ItemId
	local skin = item.skin or data.skin
	local bid = item.backend_id or item.ItemInstanceId
		or data.backend_id or data.ItemInstanceId
		or (mod_data and mod_data.backend_id)
	if key == M.ITEM_KEY or skin == M.SKIN_KEY then return M.ITEM_KEY, skin end
	if type(bid) == "string" and bid:match("^cwv_es_musket_old_") then
		return M.ITEM_KEY, skin
	end
	return nil, skin
end

function M.matches_item(item, canonical_key)
	return item_identity(item, canonical_key) == M.ITEM_KEY
end

function M.preview_package_alias(package_name)
	if package_name == M.UNIT or package_name == M.UNIT_3P then
		return M.PREVIEW_PACKAGE_ALIAS
	end
	return nil
end

function M.collected_package_alias(package_name)
	if package_name == M.UNIT then return M.NETWORK_PACKAGE_ALIAS_1P end
	if package_name == M.UNIT_3P then return M.NETWORK_PACKAGE_ALIAS_3P end
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

-- Returns a render mode rather than a boolean: a missing Workshop resource may
-- safely degrade to the vanilla handgun, while a missing fallback is unsafe.
function M.resource_mode(descriptor, can_get)
	if type(descriptor) ~= "table" or type(can_get) ~= "function" then
		return nil, "resolver_unavailable"
	end
	local hand = descriptor.right_hand_unit or {}
	local fallback = descriptor.fallback and descriptor.fallback.right_hand_unit or {}
	local unit_3p = descriptor.unit_3p or hand.unit_3p
	local fallback_unit = descriptor.fallback_unit or fallback.unit_3p or fallback.unit
	local ok_unit, custom_ready = pcall(can_get, "unit", unit_3p)
	local custom_reason = "custom_unit_missing"
	if ok_unit and custom_ready == true then
		local closure_ready = true
		for _, binding in ipairs(descriptor.textures or {}) do
			local ok, ready = pcall(can_get, "texture", binding.texture)
			if not ok or ready ~= true then
				closure_ready = false
				custom_reason = "texture_missing"
				break
			end
		end
		if closure_ready then
			local material = descriptor.material or (descriptor.materials
				and (descriptor.materials.authored or descriptor.materials.preview))
			local ok_mat, material_ready = pcall(can_get, "material", material)
			if not ok_mat or material_ready ~= true then
				closure_ready = false
				custom_reason = "material_missing"
			end
		end
		if closure_ready then return "custom", "ready" end
	end
	local package = descriptor.package or hand.package
	local ok_pkg, package_ready = pcall(can_get, "package", package)
	local ok_fallback, fallback_ready = pcall(can_get, "unit", fallback_unit)
	if ok_pkg and package_ready == true and ok_fallback and fallback_ready == true then
		return "fallback", custom_reason
	end
	return nil, "fallback_missing"
end

-- Pre-spawn admission for the shared preview bridge. The vanilla Handgun
-- package is only a balanced lifetime alias; it is not part of the custom
-- render closure. Require the exact unit, five textures, and authored material
-- before a preview row is allowed to retain the custom path.
function M.preview_resource_ready(unit_name, can_get)
	if unit_name ~= M.UNIT and unit_name ~= M.UNIT_3P then
		return false, "unit_not_owned"
	end
	if type(can_get) ~= "function" then return false, "resolver_unavailable" end
	local ok_unit, unit_ready = pcall(can_get, "unit", unit_name)
	if not ok_unit or unit_ready ~= true then return false, "custom_unit_missing" end
	local textures_ready, texture_reason = M.texture_resources_ready(can_get)
	if textures_ready ~= true then return false, texture_reason end
	local ok_material, material_ready = pcall(can_get, "material", M.MATERIAL)
	if not ok_material or material_ready ~= true then
		return false, "material_missing"
	end
	return true, "ready"
end

function M.texture_resources_ready(can_get)
	if not RESIDENCY or type(RESIDENCY.texture_set_resident) ~= "function" then
		return false, "resource residency contract unavailable"
	end
	local ready, reason = RESIDENCY.texture_set_resident(
		M.TEXTURES, { can_get = can_get }, nil, "old_musket")
	if ready then return true, nil end
	return false, reason
end

function M.bind_authored_material(unit, application_api, unit_api)
	application_api = application_api or Application
	unit_api = unit_api or Unit
	if not unit_api or type(unit_api.set_all_materials) ~= "function" then
		return false, "Unit.set_all_materials unavailable"
	end
	if not RESIDENCY or type(RESIDENCY.material_resident) ~= "function" then
		return false, "resource residency contract unavailable"
	end
	local available = RESIDENCY.material_resident(
		M.MATERIAL, application_api, nil, "old_musket_material")
	if not available then return false, M.MATERIAL end
	-- resource-safety: cwv_1155_self_contained_material
	local ok_set = pcall(unit_api.set_all_materials, unit, M.MATERIAL)
	if not ok_set then return false, "Unit.set_all_materials rejected Old Musket unit" end
	return true
end

-- Stable compatibility seam for older callers. The operation is no longer
-- preview-only; every renderer binds the same authored material.
M.prepare_preview_material = M.bind_authored_material

-- Texture residency is necessary but not sufficient. The remote husk in #742
-- had every texture resident while the spawned Old Musket unit still held an
-- unresolved material. Refuse retention unless every mesh has real handles.
function M.unit_materials_ready(unit, unit_api, mesh_api)
	unit_api = unit_api or Unit
	mesh_api = mesh_api or Mesh
	if not RESIDENCY or type(RESIDENCY.unit_materials_resident) ~= "function" then
		return false, "resource-residency-contract-unavailable"
	end
	local ready, reason, count = RESIDENCY.unit_materials_resident(
		unit, unit_api, mesh_api, nil, "old_musket")
	if ready then return true, count end
	-- Preserve the established #742 diagnostic vocabulary while delegating the
	-- actual proof to the shared V2 contract.
	return false, tostring(reason):gsub("_", "-")
end

local appearance_diag_seen = {}
local function appearance_diag_once(reason, detail, suppressed)
	if suppressed then return end
	if appearance_diag_seen[reason] then return end
	appearance_diag_seen[reason] = true
	pcall(printf, "[cwv:742/1155] Old Musket appearance SKIP reason=%s detail=%s chat=false",
		tostring(reason), tostring(detail))
end

-- The authored .material binds all five maps at compile time. Runtime owns one
-- operation: bind that proven-resident material to the live unit and census the
-- resulting handles. This eliminates the old Unit.set_texture_for_materials C
-- call entirely; a null mesh material can no longer be dereferenced while Lua
-- tries to repair a partially constructed unit.
function M.apply_material(unit, _, deps)
	deps = deps or {}
	local suppress_diagnostics = deps.suppress_diagnostics == true
	local unit_api = deps.unit or Unit
	local mesh_api = deps.mesh or Mesh
	local application_api = deps.application or Application
	if not unit or not unit_api or type(unit_api.alive) ~= "function" then return false, 0 end
	local alive_ok, alive = pcall(unit_api.alive, unit)
	if not alive_ok or alive ~= true then return false, 0 end
	local ready, detail = M.texture_resources_ready(
		application_api and application_api.can_get)
	if not ready then
		appearance_diag_once("texture-resource-missing", detail, suppress_diagnostics)
		return false, 0
	end
	ready, detail = M.bind_authored_material(unit, application_api, unit_api)
	if not ready then
		appearance_diag_once("authored-material-unbound", detail, suppress_diagnostics)
		return false, 0
	end
	ready, detail = M.unit_materials_ready(unit, unit_api, mesh_api)
	if not ready then
		appearance_diag_once("unit-material-unready", detail, suppress_diagnostics)
		return false, 0
	end
	return true, #M.TEXTURES
end

-- Compatibility seam while callers migrate terminology from painter to the
-- self-contained material closure.
M.apply_textures = M.apply_material

return M
