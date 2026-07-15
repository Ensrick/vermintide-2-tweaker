-- _cwv_greataxe.lua - Kruber Greataxe behavior and model-manifest policy.
--
-- This engine-free module is the single source of truth for the replacement
-- of the retired Poleaxe family. Runtime registration lives in
-- character_weapon_variants.lua; converted model assets only populate MODELS
-- below. Incomplete model rows are ignored instead of exposing a broken unit.
--
-- Owned by: character_weapon_variants.lua entry point. Consumed via: mod:dofile.
local M = {}

M.ITEM_KEY = "cwv_es_greataxe"
M.TEMPLATE_KEY = "cwv_greataxe_template"
M.BASE_WEAPON = "dr_2h_axe"
M.ITEM_TYPE = "cwv_es_greataxe"
M.SKIN_COMBINATION = "cwv_es_greataxe_skins"
-- Mod-defined package names are not visible to vanilla previewers' global
-- `Application.resource_package` lookup.  The custom unit itself is resident
-- through CWV's mod-scoped master package; previewers load this vanilla Bardin
-- Greataxe package as a lifetime/reference anchor instead.
M.PREVIEW_PACKAGE_ALIAS =
	"units/weapons/player/wpn_dw_2h_axe_01_t1/wpn_dw_2h_axe_01_t1_3p"
M.NETWORK_PACKAGE_ALIAS_1P =
	"units/weapons/player/wpn_dw_2h_axe_01_t1/wpn_dw_2h_axe_01_t1"
M.NETWORK_PACKAGE_ALIAS_3P = M.PREVIEW_PACKAGE_ALIAS

M.DEFAULT_CAREERS = {
	"es_mercenary", "es_huntsman", "es_knight", "es_questingknight",
}
M.ALL_CAREERS = {
	"es_mercenary", "es_huntsman", "es_knight", "es_questingknight",
	"dr_ranger", "dr_ironbreaker", "dr_slayer", "dr_engineer",
	"we_waywatcher", "we_maidenguard", "we_shade", "we_thornsister",
	"wh_captain", "wh_bountyhunter", "wh_zealot", "wh_priest",
	"bw_adept", "bw_scholar", "bw_unchained", "bw_necromancer",
}

-- Exact action redirects used by WT for `dr_2h_axe` on Kruber. The source
-- template already wields through `to_2h_hammer`; only events absent from the
-- receiver graph are substituted.
M.ANIM_REMAP_3P = {
	attack_swing_up = "attack_swing_left",
	attack_swing_heavy_left_diagonal = "attack_swing_heavy",
	attack_swing_heavy_right_diagonal = "attack_swing_heavy_right",
}

-- Asset hand-off seam. Add only converted models that load successfully.
-- The first complete row is the base illusion; later rows are picker options.
-- Canonical shape:
-- {
--   key = "cwv_es_greataxe_skin_01",
--   display_name = "Greataxe Model 01",
--   right_hand_unit = "units/cwv_es_greataxe/axe_01/axe_01",
--   display_unit = "units/weapons/weapon_display/display_2h_axes",
--   inventory_icon = "icon_wpn_dw_2h_axe_01",
--   hud_icon = "weapon_generic_icon_axe2h",
--   rarity = "exotic",
-- }
M.MODELS = {
	{
		key = "cwv_es_greataxe_skin_01",
		display_name = "Greataxe Model 01",
		description = "A Greataxe model awaiting final review and naming.",
		right_hand_unit = "units/cwv_es_greataxe/axe_01/axe_01",
		-- User-tuned on Kruber through WT's 3P Hold-Pose tuner. These values
		-- are model-specific and must not leak to the other four illusions.
		right_hand_scale_3p = { 0.5, 0.5, 0.5 },
		right_hand_offset_3p = { -0.010, 0.153, -0.309 },
		right_hand_rotation_3p = { -90, 180, -90 },
		display_unit = "units/weapons/weapon_display/display_2h_axes",
		inventory_icon = "icon_wpn_dw_2h_axe_01_t1",
		hud_icon = "weapon_generic_icon_axe2h",
		rarity = "exotic",
	},
	{
		key = "cwv_es_greataxe_skin_02",
		display_name = "Greataxe Model 02",
		description = "A Greataxe model awaiting final review and naming.",
		right_hand_unit = "units/cwv_es_greataxe/axe_02/axe_02",
		display_unit = "units/weapons/weapon_display/display_2h_axes",
		inventory_icon = "icon_wpn_dw_2h_axe_01_t1",
		hud_icon = "weapon_generic_icon_axe2h",
		rarity = "exotic",
	},
	{
		key = "cwv_es_greataxe_skin_03",
		display_name = "Greataxe Model 03",
		description = "A Greataxe model awaiting final review and naming.",
		right_hand_unit = "units/cwv_es_greataxe/axe_03/axe_03",
		display_unit = "units/weapons/weapon_display/display_2h_axes",
		inventory_icon = "icon_wpn_dw_2h_axe_01_t1",
		hud_icon = "weapon_generic_icon_axe2h",
		rarity = "exotic",
	},
	{
		key = "cwv_es_greataxe_skin_04",
		display_name = "Greataxe Model 04",
		description = "A Greataxe model awaiting final review and naming.",
		right_hand_unit = "units/cwv_es_greataxe/axe_04/axe_04",
		display_unit = "units/weapons/weapon_display/display_2h_axes",
		inventory_icon = "icon_wpn_dw_2h_axe_01_t1",
		hud_icon = "weapon_generic_icon_axe2h",
		rarity = "exotic",
	},
	{
		key = "cwv_es_greataxe_skin_05",
		display_name = "Greataxe Model 05",
		description = "A Greataxe model awaiting final review and naming.",
		right_hand_unit = "units/cwv_es_greataxe/axe_05/axe_05",
		display_unit = "units/weapons/weapon_display/display_2h_axes",
		inventory_icon = "icon_wpn_dw_2h_axe_01_t1",
		hud_icon = "weapon_generic_icon_axe2h",
		rarity = "exotic",
	},
}

function M.is_usable_model(model)
	return type(model) == "table"
		and type(model.key) == "string" and model.key ~= ""
		and type(model.display_name) == "string" and model.display_name ~= ""
		and type(model.right_hand_unit) == "string" and model.right_hand_unit ~= ""
end

function M.usable_models()
	local result = {}
	for _, model in ipairs(M.MODELS) do
		if M.is_usable_model(model) then
			result[#result + 1] = model
		end
	end
	return result
end

function M.default_model()
	for _, model in ipairs(M.MODELS) do
		if M.is_usable_model(model) then return model end
	end
	return nil
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

-- WeaponUtils.get_weapon_packages is a package-residency collector, not a
-- render-unit resolver. ProfileSynchronizer feeds its return values directly
-- to PackageManager, where a resident mod-bundle unit path is not itself a
-- loadable package name. Borrow the matching vanilla 1P/3P package identity at
-- this boundary only; BackendUtils.get_item_units and all spawn paths retain
-- the custom model unit.
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
-- NetworkLookup. Custom Workshop unit paths must therefore borrow a stable
-- vanilla index on the forward (name -> index) side only. The reverse mapping
-- remains vanilla, so decoding never asks an unmodded peer to load our unit.
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

function M.default_career_set()
	local result = {}
	for _, career in ipairs(M.DEFAULT_CAREERS) do result[career] = true end
	return result
end

function M.conditional_careers()
	local authored = M.default_career_set()
	local result = {}
	for _, career in ipairs(M.ALL_CAREERS) do
		if not authored[career] then result[#result + 1] = career end
	end
	return result
end

return M
