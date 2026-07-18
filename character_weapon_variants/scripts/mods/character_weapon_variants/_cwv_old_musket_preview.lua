-- Canonical preview-resource policy for the Old Musket.
--
-- The custom mesh lives in CWV's resident master bundle; it is not a globally
-- discoverable standalone package.  Every preview surface therefore consumes
-- this descriptor and borrows the vanilla handgun package only as a balanced
-- lifetime anchor.  The render unit, material, textures and transform identity
-- remain the authored Old Musket values.
local M = {}

M.ITEM_KEY = "cwv_es_musket_old"
M.SKIN_KEY = "cwv_es_musket_old_skin"
M.UNIT = "units/cwv_es_musket_custom/cwv_es_musket_custom"
M.UNIT_3P = M.UNIT .. "_3p"
M.PREVIEW_PACKAGE_ALIAS =
	"units/weapons/player/wpn_empire_handgun_t1/wpn_empire_handgun_t1_3p"
M.NETWORK_PACKAGE_ALIAS_1P =
	"units/weapons/player/wpn_empire_handgun_t1/wpn_empire_handgun_t1"
M.NETWORK_PACKAGE_ALIAS_3P = M.PREVIEW_PACKAGE_ALIAS
M.PREVIEW_MATERIAL = M.PREVIEW_PACKAGE_ALIAS
M.TEXTURES = {
	{ slot = "texture_map_c0ba2942", texture = "textures/cwv_es_musket_custom/cwv_es_musket_custom_albedo" },
	{ slot = "texture_map_59cd86b9", texture = "textures/cwv_es_musket_custom/cwv_es_musket_custom_normal" },
	{ slot = "texture_map_0205ba86", texture = "textures/cwv_es_musket_custom/cwv_es_musket_custom_metallic" },
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

-- One descriptor is shared by the ordinary cosmetic/item browser and CIM's
-- Athanor because both are LootItemUnitPreviewer consumers.  Runtime transform
-- triplets are injected by the owner so this pure policy does not depend on
-- Stingray vector/quaternion types.
function M.resolve(item, mode, transform, canonical_key)
	local key, skin = item_identity(item, canonical_key)
	if key ~= M.ITEM_KEY then return nil end
	return {
		item_key = key,
		skin_key = skin or M.SKIN_KEY,
		mode = mode == "melee" and "melee" or "ranged",
		unit = M.UNIT,
		unit_3p = M.UNIT_3P,
		package = M.PREVIEW_PACKAGE_ALIAS,
		fallback_unit = M.PREVIEW_PACKAGE_ALIAS,
		material = M.PREVIEW_MATERIAL,
		textures = M.TEXTURES,
		transform = transform,
	}
end

-- Returns a render mode rather than a boolean: a missing Workshop resource may
-- safely degrade to the vanilla handgun, while a missing fallback is unsafe.
function M.resource_mode(descriptor, can_get)
	if type(descriptor) ~= "table" or type(can_get) ~= "function" then
		return nil, "resolver_unavailable"
	end
	local ok_unit, custom_ready = pcall(can_get, "unit", descriptor.unit_3p)
	local ok_pkg, package_ready = pcall(can_get, "package", descriptor.package)
	if ok_unit and custom_ready == true and ok_pkg and package_ready == true then
		for _, binding in ipairs(descriptor.textures or {}) do
			local ok, ready = pcall(can_get, "texture", binding.texture)
			if not ok or ready ~= true then return "fallback", "texture_missing" end
		end
		local ok_mat, material_ready = pcall(can_get, "material", descriptor.material)
		if not ok_mat or material_ready ~= true then return "fallback", "material_missing" end
		return "custom", "ready"
	end
	local ok_fallback, fallback_ready = pcall(can_get, "unit", descriptor.fallback_unit)
	if ok_pkg and package_ready == true and ok_fallback and fallback_ready == true then
		return "fallback", "custom_unit_missing"
	end
	return nil, "fallback_missing"
end

function M.texture_resources_ready(can_get)
	if type(can_get) ~= "function" then return false, "Application.can_get unavailable" end
	for _, binding in ipairs(M.TEXTURES) do
		local ok, available = pcall(can_get, "texture", binding.texture)
		if not ok or available ~= true then return false, binding.texture end
	end
	return true
end

function M.prepare_preview_material(unit, application_api, unit_api)
	application_api = application_api or Application
	unit_api = unit_api or Unit
	if not unit_api or type(unit_api.set_all_materials) ~= "function" then
		return false, "Unit.set_all_materials unavailable"
	end
	local can_get = application_api and application_api.can_get
	if type(can_get) ~= "function" then return false, "Application.can_get unavailable" end
	local ok_get, available = pcall(can_get, "material", M.PREVIEW_MATERIAL)
	if not ok_get or available ~= true then return false, M.PREVIEW_MATERIAL end
	local ok_set = pcall(unit_api.set_all_materials, unit, M.PREVIEW_MATERIAL)
	if not ok_set then return false, "Unit.set_all_materials rejected preview unit" end
	return true
end

-- Texture residency is necessary but not sufficient. The remote husk in #742
-- had all three textures resident while the spawned Old Musket unit still held
-- an unresolved material. Refuse the C write unless every mesh has real handles.
function M.unit_materials_ready(unit, unit_api, mesh_api)
	unit_api = unit_api or Unit
	mesh_api = mesh_api or Mesh
	if not unit then return false, "unit-missing" end
	if not unit_api or type(unit_api.num_meshes) ~= "function"
			or type(unit_api.mesh) ~= "function" then
		return false, "unit-mesh-api-unavailable"
	end
	if not mesh_api or type(mesh_api.num_materials) ~= "function"
			or type(mesh_api.material) ~= "function" then
		return false, "mesh-material-api-unavailable"
	end
	local ok_mesh_count, mesh_count = pcall(unit_api.num_meshes, unit)
	if not ok_mesh_count or type(mesh_count) ~= "number" or mesh_count < 1 then
		return false, "unit-has-no-meshes"
	end
	local material_count = 0
	for mesh_index = 0, mesh_count - 1 do
		local ok_mesh, mesh = pcall(unit_api.mesh, unit, mesh_index)
		if not ok_mesh or not mesh then return false, "mesh-unresolved-" .. tostring(mesh_index) end
		local ok_count, count = pcall(mesh_api.num_materials, mesh)
		if not ok_count or type(count) ~= "number" or count < 1 then
			return false, "mesh-has-no-materials-" .. tostring(mesh_index)
		end
		for material_index = 0, count - 1 do
			local ok_material, material = pcall(mesh_api.material, mesh, material_index)
			if not ok_material or not material then
				return false, string.format("material-unresolved-%d-%d", mesh_index, material_index)
			end
			local ok_string, material_id = pcall(tostring, material)
			if not ok_string or not material_id or material_id:find("00000000", 1, true) then
				return false, string.format("material-null-%d-%d", mesh_index, material_index)
			end
			material_count = material_count + 1
		end
	end
	return material_count > 0, material_count > 0 and material_count or "unit-has-no-materials"
end

local paint_diag_seen = {}
local function paint_diag_once(reason, detail)
	if paint_diag_seen[reason] then return end
	paint_diag_seen[reason] = true
	pcall(printf, "[cwv:742] Old Musket paint SKIP reason=%s detail=%s chat=false",
		tostring(reason), tostring(detail))
end

-- Unit.set_texture_for_materials is a native call whose 0x8 access violation
-- bypasses pcall. Every precondition below is mandatory and the paint is atomic.
function M.apply_textures(unit, preview_world)
	if not unit or not Unit.alive(unit)
			or type(Unit.set_texture_for_materials) ~= "function" then return false, 0 end
	local ready, detail = M.texture_resources_ready(Application and Application.can_get)
	if not ready then paint_diag_once("texture-resource-missing", detail); return false, 0 end
	if preview_world then
		ready, detail = M.prepare_preview_material(unit)
		if not ready then paint_diag_once("preview-material-unbound", detail); return false, 0 end
	end
	ready, detail = M.unit_materials_ready(unit)
	if not ready then paint_diag_once("unit-material-unready", detail); return false, 0 end
	for _, binding in ipairs(M.TEXTURES) do
		Unit.set_texture_for_materials(unit, binding.slot, binding.texture)
	end
	return true, #M.TEXTURES
end

return M
