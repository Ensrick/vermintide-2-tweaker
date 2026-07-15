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

local function item_identity(item)
	if type(item) ~= "table" then return nil, nil end
	local data = type(item.data) == "table" and item.data or {}
	local key = data.cwv_key or item.cwv_key or item.key or data.key
	local skin = item.skin or data.skin
	local bid = item.backend_id or item.ItemId
	if key == M.ITEM_KEY or skin == M.SKIN_KEY then return M.ITEM_KEY, skin end
	if type(bid) == "string" and bid:match("^cwv_es_musket_old_") then
		return M.ITEM_KEY, skin
	end
	return nil, skin
end

function M.matches_item(item)
	return item_identity(item) == M.ITEM_KEY
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
function M.resolve(item, mode, transform)
	local key, skin = item_identity(item)
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

return M
