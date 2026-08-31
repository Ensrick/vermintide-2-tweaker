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
-- Canonical authored-mesh pose. Scale is a MULTIPLIER of the imported render
-- node's captured native scale (the durable owner multiplies against the
-- baseline; native is {100,100,100} per issue 712 log evidence), never an
-- absolute Stingray scale - writing absolute 0.9 shrank the model 111x.
-- Values are the author's sight-verified bake (2026-07-19 /woc_pose session):
-- rotation x=-180 total, third person 0.9, first person 0.8.
-- TRANSFORM_1P deliberately SHARES the offset and rotation tables with
-- TRANSFORM (live /woc_pose tuning moves both perspectives together); only
-- the scale table is per-perspective.
M.TRANSFORM = {
	scale = { 0.9, 0.9, 0.9 },
	offset = { 0, 0, -0.3 },
	rotation = { -180, -90, -90 },
}
M.TRANSFORM_1P = {
	scale = { 0.8, 0.8, 0.8 },
	offset = M.TRANSFORM.offset,
	rotation = M.TRANSFORM.rotation,
}

function M.transform_for(perspective)
	return perspective == "1p" and M.TRANSFORM_1P or M.TRANSFORM
end

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

-- Issue 712 root cause: retail Stingray registers `Vector3` as a callable
-- TABLE (constructed via its `__call` metamethod), not a Lua function. The
-- shared appearance library guards its constructor with
-- `type(vector_new) ~= "function"` (_lib_weapon_appearance.lua:51), so with
-- the library's default api every position/scale construction returned nil
-- in-game and the atomic pose path exited "invalid-position" BEFORE
-- Unit.set_local_pose ran (proof: every 0.1.30/0.1.31-dev `[WOC:712]
-- transform proof` line carried `ok=false error=invalid-position` with
-- before==after, while rotation-only writes landed in 0.1.24-dev because
-- Quaternion.from_euler_angles_xyz is a genuine function member). Build the
-- injected api here so the constructor reaches the library wrapped in a plain
-- Lua closure, and the shared library copy stays byte-identical to canonical.
-- Returns nil when `Vector3` is absent (offline harness) so the library's
-- default api remains in charge there.
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

-- Issue #595 regression containment. A package omission must not cascade from
-- VMF's nil/throwing dofile result into entry-point initialization. The real
-- fade adapter is optional presentation behavior; its absence disables only
-- late linked-unit enrollment and reports one bounded reason.
function M.new_fade_adapter(module, deps, report)
	local function unavailable(reason)
		if type(report) == "function" then pcall(report, reason) end
		local fallback = {}
		function fallback:enroll(_, edge)
			return false, {
				edge = edge,
				reason = "adapter_unavailable",
				count = 0,
				error = reason,
			}
		end
		function fallback:last_report()
			return nil
		end
		return fallback, false, reason
	end

	if type(module) ~= "table" then
		return unavailable("module_unavailable")
	end
	local member_ok, constructor = pcall(function() return module.new end)
	if not member_ok or type(constructor) ~= "function" then
		return unavailable("constructor_unavailable")
	end
	local create_ok, instance = pcall(constructor, deps)
	if not create_ok then
		return unavailable("constructor_failed:" .. tostring(instance))
	end
	local shape_ok, enroll = pcall(function() return instance and instance.enroll end)
	if not shape_ok or type(instance) ~= "table" or type(enroll) ~= "function" then
		return unavailable("adapter_shape_invalid")
	end
	return instance, true, "ready"
end

local function guarded_dofile(mod, path)
	local member_ok, loader = pcall(function() return mod and mod.dofile end)
	if not member_ok or type(loader) ~= "function" then
		return false, member_ok and "dofile_unavailable" or loader
	end
	return pcall(loader, mod, path)
end

local function safe_printf(printf_fn, fmt, ...)
	if type(printf_fn) == "function" then pcall(printf_fn, fmt, ...) end
end

-- Keep the entry point declarative: this boundary owns both package-backed
-- helper loads, their fail-closed substitutes, and the one named runtime check.
function M.load_runtime_helpers(mod, fade_deps, rt_register, printf_fn)
	local fade_ok, fade_module = guarded_dofile(
		mod, "scripts/mods/weapons_of_chaos/_lib_appearance_fade")
	local fade, fade_ready, fade_reason = M.new_fade_adapter(
		fade_ok and fade_module or nil, fade_deps)
	if not fade_ready then
		safe_printf(printf_fn,
			"[WOC:595] fade adapter unavailable; continuing without custom fade enrollment reason=%s load=%s",
			tostring(fade_reason), fade_ok and "returned" or tostring(fade_module))
	end

	local residency_ok, residency = guarded_dofile(
		mod, "scripts/mods/weapons_of_chaos/_lib_resource_residency")
	local residency_ready = residency_ok and type(residency) == "table"
		and type(residency.resource_resident) == "function"
	if not residency_ready then
		safe_printf(printf_fn,
			"[WOC:595] residency helper unavailable; pulse admission will use its fail-closed compatibility path load=%s",
			residency_ok and "invalid-shape" or tostring(residency))
	end

	if type(rt_register) == "function" then
		rt_register("issue595_required_runtime_helpers_loaded", function()
			if not fade_ok or not fade_ready then
				error("appearance fade helper unavailable")
			end
			if not residency_ready then
				error("resource residency helper unavailable")
			end
		end)
	else
		safe_printf(printf_fn,
			"[WOC:595] runtime helper check registration unavailable")
	end

	return fade, residency_ready and residency or nil
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
