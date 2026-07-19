-- Pure appearance/package policy for the authored Blightreaper unit.
-- Runtime hooks live in `_woc_mod_unit_preview`; tests can load this file
-- without Stingray globals.
local M = {}

M.UNIT_1P = "units/woc_blightreaper/blightreaper"
M.UNIT_3P = M.UNIT_1P .. "_3p"
-- Base-game runed Empire sword packages are standalone loadable aliases and
-- carry the same two-noise-texture pulse graph as the native trophy material.
-- They are lifetime anchors and shader donors only; WOC keeps its own mesh and
-- unit-local textures. See tools/BLIGHTREAPER_ASSET_PIPELINE.md.
M.VANILLA_1P =
	"units/weapons/player/wpn_emp_sword_02_t1/wpn_emp_sword_02_t1_runed_01"
M.VANILLA_3P = M.VANILLA_1P .. "_3p"
M.DONOR_MATERIAL_1P = M.VANILLA_1P
M.DONOR_MATERIAL_3P = M.VANILLA_3P
M.TEXTURE_ROOT = "textures/woc_blightreaper/"
-- The imported unit's attachment root is owned by GearUtils linking. Live
-- issue #712 evidence resolves the visible authored render node by this exact
-- name on both 1P and 3P units (node index 2 in the observed bundles).
M.TRANSFORM_NODE_NAME = "blightreaper"
M.PULSE_VARIABLES = {
	{ name = "rune_emissive_color", value = { 5, 4.4, 0 } },
	{ name = "intensity", value = 1.746000051498413 },
	{ name = "pulse", value = { 1, 0.5 } },
}
-- Canonical authored-mesh pose. Scale is a multiplier of the imported render
-- node's captured native scale, not an absolute Stingray scale. Live 0.1.33
-- evidence reports native {100,100,100}; writing absolute {0.9,0.9,0.9}
-- shrank the model by roughly 111x. The durable owner resolves this multiplier
-- and the offset against the render-node baseline, then writes the resulting
-- absolute scale/position/rotation atomically without mutating GearUtils' root.
M.TRANSFORM = {
	scale = { 0.9, 0.9, 0.9 },
	offset = { 0, 0, -0.3 },
	rotation = { -90, -90, -90 },
}

function M.canonicalize_item_units(item_units, is_exact_relic)
	if type(item_units) ~= "table" or is_exact_relic ~= true then
		return item_units, false
	end
	local changed = item_units.right_hand_unit ~= M.UNIT_1P
		or item_units.left_hand_unit ~= nil
	item_units.right_hand_unit = M.UNIT_1P
	item_units.left_hand_unit = nil
	return item_units, changed
end

function M.is_custom_unit_name(name)
	return name == M.UNIT_1P or name == M.UNIT_3P
end

local function pulse_textures(rune_slot)
	local root = M.TEXTURE_ROOT
	return {
		{ slot = "texture_map_c0ba2942", texture = root .. "blightreaper_albedo" },
		{ slot = "texture_map_0205ba86", texture = root .. "blightreaper_normal" },
		{ slot = "texture_map_59cd86b9", texture = root .. "blightreaper_packed" },
		{ slot = rune_slot, texture = root .. "blightreaper_emissive" },
		{ slot = "texture_map_1cf504ab", texture = root .. "blightreaper_noise" },
		{ slot = "texture_map_71d74d4d", texture = root .. "blightreaper_noise" },
	}
end

M.PULSE_TEXTURES_1P = pulse_textures("texture_map_4617b8e0")
M.PULSE_TEXTURES_3P = pulse_textures("texture_map_ee282ea2")

function M.pulse_descriptor(perspective)
	local third_person = perspective == "3p"
	return {
		material = third_person and M.DONOR_MATERIAL_3P or M.DONOR_MATERIAL_1P,
		textures = third_person and M.PULSE_TEXTURES_3P or M.PULSE_TEXTURES_1P,
		variables = M.PULSE_VARIABLES,
	}
end

function M.preview_package_alias(name)
	if name == M.UNIT_1P then return M.VANILLA_1P end
	if name == M.UNIT_3P then return M.VANILLA_3P end
	return nil
end

function M.alias_collected_packages(names)
	if type(names) ~= "table" then return names, 0 end
	local count = 0
	for i = 1, #names do
		local alias = M.preview_package_alias(names[i])
		if alias then names[i], count = alias, count + 1 end
	end
	return names, count
end

function M.network_package_aliases()
	return {
		[M.UNIT_1P] = M.VANILLA_1P,
		[M.UNIT_3P] = M.VANILLA_3P,
	}
end

-- Retail Stingray exposes Vector3 as a callable table, while the shared
-- appearance library deliberately accepts only a plain function constructor.
-- Wrap it here so the library stays byte-identical to its canonical source.
function M.appearance_api(globals)
	if type(globals) ~= "table" then return nil end
	local vector3 = globals.Vector3
	if vector3 == nil then return nil end
	local ok_member, to_elements = pcall(function() return vector3.to_elements end)
	return {
		unit = globals.Unit,
		vector_new = function(x, y, z) return vector3(x, y, z) end,
		vector_to_elements = ok_member and to_elements or nil,
		quaternion = globals.Quaternion,
		matrix4x4 = globals.Matrix4x4,
	}
end

-- Install only forward name -> vanilla index aliases. The numeric reverse
-- lookup remains vanilla, so a peer that lacks WOC never decodes a custom path.
function M.install_network_package_aliases(lookup)
	if type(lookup) ~= "table" then return 0 end
	local count = 0
	for custom, vanilla in pairs(M.network_package_aliases()) do
		local index = rawget(lookup, vanilla)
		if type(index) == "number" then
			rawset(lookup, custom, index)
			count = count + 1
		end
	end
	return count
end

return M
