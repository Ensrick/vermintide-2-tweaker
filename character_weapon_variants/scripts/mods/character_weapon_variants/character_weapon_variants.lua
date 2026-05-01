local mod = get_mod("character_weapon_variants")

local MOD_VERSION = "0.1.25-dev"

mod:info("Character Weapon Variants v%s loading", MOD_VERSION)

-- ============================================================
-- Variant weapon definitions
-- ============================================================

local _es_all_careers = { "es_mercenary", "es_huntsman", "es_knight", "es_questingknight" }

local _variant_definitions = {
	{
		item_key        = "cwv_es_axe_shield",
		base_weapon     = "dr_shield_axe",
		display_name    = "Axe and Shield",
		description     = "A one-handed axe paired with a sturdy imperial shield.",
		character       = "empire_soldier",
		careers         = { "es_mercenary", "es_huntsman", "es_knight" },
		right_hand_unit = "units/weapons/player/wpn_axe_02_t1/wpn_axe_02_t1",
		left_hand_unit  = "units/weapons/player/wpn_empire_shield_02/wpn_emp_shield_02",
		inventory_icon  = "icon_wpn_dw_shield_01_axe",
		hud_icon        = "weapon_generic_icon_axe_and_sheild",
		skin_display_name = "Axe and Shield",
		rarity          = "default",
		power_level     = 5,
	},
	{
		item_key        = "cwv_es_axe_shield_veteran",
		base_weapon     = "dr_shield_axe",
		display_name    = "Imperial Axe and Shield",
		description     = "A battle-hardened hatchet paired with a sturdy imperial shield. Reforged for Kruber's arsenal.",
		character       = "empire_soldier",
		careers         = { "es_mercenary", "es_huntsman", "es_knight" },
		right_hand_unit = "units/weapons/player/wpn_axe_hatchet_t2/wpn_axe_hatchet_t2_magic_01",
		left_hand_unit  = "units/weapons/player/wpn_es_deus_shield_02/wpn_es_deus_shield_02_magic",
		inventory_icon  = "icon_wpn_dw_shield_01_axe",
		hud_icon        = "weapon_generic_icon_axe_and_sheild",
		skin_display_name = "Imperial Axe and Shield",
		rarity          = "unique",
		traits          = { "melee_counter_push_power" },
		properties      = { block_cost = 1, power_vs_skaven = 1 },
	},
	{
		item_key        = "cwv_we_sword_shield",
		base_weapon     = "es_sword_shield",
		display_name    = "Sword and Shield",
		description     = "An elven blade paired with an Athel Loren shield.",
		character       = "wood_elf",
		careers         = { "we_waywatcher", "we_maidenguard", "we_shade", "we_thornsister" },
		right_hand_unit = "units/weapons/player/wpn_we_sword_01_t1/wpn_we_sword_01_t1",
		left_hand_unit  = "units/weapons/player/wpn_we_shield_01/wpn_we_shield_01",
		inventory_icon  = "icon_wpn_empire_shield_02_sword",
		hud_icon        = "weapon_generic_icon_sword_and_sheild",
		skin_display_name = "Sword and Shield",
		rarity          = "default",
		power_level     = 5,
	},
	{
		item_key        = "cwv_we_sword_shield_veteran",
		base_weapon     = "es_sword_shield",
		display_name    = "Elven Sword and Shield",
		description     = "A keen elven blade paired with a sturdy Athel Loren shield. Forged for the Asrai's front line.",
		character       = "wood_elf",
		careers         = { "we_waywatcher", "we_maidenguard", "we_shade", "we_thornsister" },
		right_hand_unit = "units/weapons/player/wpn_we_sword_03_t1/wpn_we_sword_03_t1_magic_01",
		left_hand_unit  = "units/weapons/player/wpn_we_shield_02/wpn_we_shield_02_magic_01",
		inventory_icon  = "icon_wpn_empire_shield_02_sword",
		hud_icon        = "weapon_generic_icon_sword_and_sheild",
		skin_display_name = "Elven Sword and Shield",
		rarity          = "unique",
		traits          = { "melee_counter_push_power" },
		properties      = { block_cost = 1, power_vs_skaven = 1 },
	},
	{
		item_key        = "cwv_es_longsword",
		base_weapon     = "es_bastard_sword",
		display_name    = "Recruit Longsword",
		description     = "An imperial longsword — lighter and faster than the Bretonnian variety.",
		character       = "empire_soldier",
		careers         = _es_all_careers,
		right_hand_unit = "units/weapons/player/wpn_emp_sword_02_t1/wpn_emp_sword_02_t1",
		inventory_icon  = "icon_wpn_emp_sword_02_t1",
		hud_icon        = "weapon_generic_icon_sword",
		skin_display_name = "Recruit Longsword",
		rarity          = "default",
		power_level     = 5,
		template        = "imperial_longsword_template",
		right_hand_scale = { 1.0, 1.0, 1.15 },
	},
	{
		item_key        = "cwv_es_longsword_veteran",
		base_weapon     = "es_bastard_sword",
		display_name    = "Halfling Splitter",
		description     = "A formidable imperial longsword. Swifter and more agile than its Bretonnian counterpart.",
		character       = "empire_soldier",
		careers         = _es_all_careers,
		right_hand_unit = "units/weapons/player/wpn_empire_2h_sword_03_t2/wpn_2h_sword_03_t2",
		inventory_icon  = "icon_wpn_empire_2h_sword_03_t2",
		hud_icon        = "weapon_generic_icon_sword",
		skin_display_name = "Halfling Splitter",
		rarity          = "exotic",
		template        = "imperial_longsword_template",
		right_hand_scale = { 0.65, 1.0, 0.85 },
	},
}

-- ============================================================
-- Imperial Longsword template (modified bastard_sword_template)
-- -15% damage, +15% speed, +15% cleave, -15% stagger
-- ============================================================

local _IL_DAMAGE_MULT  = 0.85
local _IL_SPEED_MULT   = 1.15
local _IL_CLEAVE_MULT  = 1.15
local _IL_STAGGER_MULT = 0.85

local function _clone_damage_profile(source_name, prefix)
	if not DamageProfileTemplates then return source_name end
	local source = DamageProfileTemplates[source_name]
	if not source then return source_name end

	local new_name = prefix .. source_name
	if DamageProfileTemplates[new_name] then return new_name end

	local clone = table.clone(source, true)

	if type(clone.cleave_distribution) == "string" and PowerLevelTemplates then
		local key = clone.cleave_distribution
		local src = PowerLevelTemplates[key]
		if src then
			local new_key = prefix .. key
			if not PowerLevelTemplates[new_key] then
				local c = table.clone(src, true)
				if c.attack then c.attack = c.attack * _IL_CLEAVE_MULT end
				if c.impact then c.impact = c.impact * _IL_CLEAVE_MULT end
				PowerLevelTemplates[new_key] = c
			end
			clone.cleave_distribution = new_key
		end
	end

	if type(clone.default_target) == "string" and PowerLevelTemplates then
		local key = clone.default_target
		local src = PowerLevelTemplates[key]
		if src then
			local new_key = prefix .. key
			if not PowerLevelTemplates[new_key] then
				local c = table.clone(src, true)
				if c.power_distribution then
					if c.power_distribution.attack then c.power_distribution.attack = c.power_distribution.attack * _IL_DAMAGE_MULT end
					if c.power_distribution.impact then c.power_distribution.impact = c.power_distribution.impact * _IL_STAGGER_MULT end
				end
				PowerLevelTemplates[new_key] = c
			end
			clone.default_target = new_key
		end
	end

	if type(clone.targets) == "string" and PowerLevelTemplates then
		local key = clone.targets
		local src = PowerLevelTemplates[key]
		if src then
			local new_key = prefix .. key
			if not PowerLevelTemplates[new_key] then
				local c = table.clone(src, true)
				for _, target in ipairs(c) do
					if target.power_distribution then
						if target.power_distribution.attack then target.power_distribution.attack = target.power_distribution.attack * _IL_DAMAGE_MULT end
						if target.power_distribution.impact then target.power_distribution.impact = target.power_distribution.impact * _IL_STAGGER_MULT end
					end
				end
				PowerLevelTemplates[new_key] = c
			end
			clone.targets = new_key
		end
	end

	if type(clone.critical_strike) == "string" and PowerLevelTemplates then
		local key = clone.critical_strike
		local src = PowerLevelTemplates[key]
		if src then
			local new_key = prefix .. key
			if not PowerLevelTemplates[new_key] then
				local c = table.clone(src, true)
				if c.power_distribution then
					if c.power_distribution.attack then c.power_distribution.attack = c.power_distribution.attack * _IL_DAMAGE_MULT end
					if c.power_distribution.impact then c.power_distribution.impact = c.power_distribution.impact * _IL_STAGGER_MULT end
				end
				PowerLevelTemplates[new_key] = c
			end
			clone.critical_strike = new_key
		end
	end

	DamageProfileTemplates[new_name] = clone
	return new_name
end

local function _create_imperial_longsword_template()
	if not Weapons or not Weapons.bastard_sword_template then
		mod:warning("bastard_sword_template not found — Imperial Longsword stat modifications unavailable")
		return
	end
	if Weapons.imperial_longsword_template then return end

	local template = table.clone(Weapons.bastard_sword_template, true)

	if template.actions then
		for _, action_group in pairs(template.actions) do
			if type(action_group) == "table" then
				for _, sub_action in pairs(action_group) do
					if type(sub_action) == "table" then
						if sub_action.anim_time_scale then
							sub_action.anim_time_scale = sub_action.anim_time_scale * _IL_SPEED_MULT
						end
						if sub_action.damage_profile then
							sub_action.damage_profile = _clone_damage_profile(sub_action.damage_profile, "cwv_il_")
						end
					end
				end
			end
		end
	end

	Weapons.imperial_longsword_template = template
	mod:info("Created imperial_longsword_template (dmg=%.0f%% spd=%.0f%% cleave=%.0f%% stagger=%.0f%%)",
		_IL_DAMAGE_MULT * 100, _IL_SPEED_MULT * 100, _IL_CLEAVE_MULT * 100, _IL_STAGGER_MULT * 100)
end

_create_imperial_longsword_template()

-- ============================================================
-- Optional mod detection
-- ============================================================

local function _detect_companion_mods()
	local wt = get_mod("wt")
	local ct = get_mod("cosmetics_tweaker")

	if wt then
		mod:info("weapon_tweaker detected")
	end
	if ct then
		mod:info("cosmetics_tweaker detected")
	end

	return wt, ct
end

-- ============================================================
-- Localization
-- ============================================================

local _display_names = {}

for _, def in ipairs(_variant_definitions) do
	_display_names[def.item_key .. "_name"] = def.display_name
	_display_names[def.item_key .. "_description"] = def.description
	if def.skin_display_name then
		_display_names[def.item_key .. "_skin_name"] = def.skin_display_name
	end
end

mod:hook(_G, "Localize", function(func, key)
	if _display_names[key] then
		return _display_names[key]
	end
	return func(key)
end)

-- ============================================================
-- Cross-character weapon unlocks (can_wield patches)
-- ============================================================

local _weapon_unlocks = {
	{
		item_key = "wh_1h_axe",
		add_careers = {
			"es_mercenary",
			"es_huntsman",
			"es_knight",
			"es_questingknight",
		},
	},
}

local function _apply_weapon_unlocks()
	for _, unlock in ipairs(_weapon_unlocks) do
		local item = ItemMasterList[unlock.item_key]
		if item and item.can_wield then
			local existing = {}
			for _, career in ipairs(item.can_wield) do
				existing[career] = true
			end
			for _, career in ipairs(unlock.add_careers) do
				if not existing[career] then
					item.can_wield[#item.can_wield + 1] = career
					existing[career] = true
				end
			end
			mod:info("Unlocked %s for: %s", unlock.item_key, table.concat(unlock.add_careers, ", "))
		else
			mod:warning("Cannot unlock %s — not found in ItemMasterList", unlock.item_key)
		end
	end
end

_apply_weapon_unlocks()

-- ============================================================
-- Custom skin registration
-- ============================================================

local function _register_variant_skins()
	if not WeaponSkins then return end
	for _, def in ipairs(_variant_definitions) do
		if def.no_skin then goto skip_skin end
		local skin_key = def.item_key .. "_skin"
		if not WeaponSkins.skins[skin_key] then
			WeaponSkins.skins[skin_key] = {
				display_name = def.item_key .. "_skin_name",
				description = def.item_key .. "_description",
				rarity = def.rarity or "exotic",
				right_hand_unit = def.right_hand_unit,
				left_hand_unit = def.left_hand_unit,
				hud_icon = def.hud_icon or "weapon_generic_icon_axe1h",
				inventory_icon = def.inventory_icon or "icon_wpn_dw_shield_01_axe",
				template = nil,
			}
			mod:info("Registered custom skin: %s", skin_key)
		end

		if NetworkLookup and NetworkLookup.weapon_skins and not rawget(NetworkLookup.weapon_skins, skin_key) then
			local idx = #NetworkLookup.weapon_skins + 1
			rawset(NetworkLookup.weapon_skins, idx, skin_key)
			rawset(NetworkLookup.weapon_skins, skin_key, idx)
			mod:info("Injected '%s' into NetworkLookup.weapon_skins at index %d", skin_key, idx)
		end
		::skip_skin::
	end
end

_register_variant_skins()

-- ============================================================
-- Cross-character greatsword illusions
-- ============================================================

local _es_careers = { "es_mercenary", "es_huntsman", "es_knight", "es_questingknight" }
local _wh_careers = { "wh_zealot", "wh_bountyhunter", "wh_captain" }

local _custom_illusions = {
	-- Saltzpyre greatsword models on Kruber's greatsword
	{ skin_key = "cwv_es_2h_sword_wh_01",          matching_weapon = "es_2h_sword", source_skin = "wh_2h_sword_skin_01",          can_wield = _es_careers },
	{ skin_key = "cwv_es_2h_sword_wh_02",          matching_weapon = "es_2h_sword", source_skin = "wh_2h_sword_skin_02",          can_wield = _es_careers },
	{ skin_key = "cwv_es_2h_sword_wh_02_runed_01", matching_weapon = "es_2h_sword", source_skin = "wh_2h_sword_skin_02_runed_01", can_wield = _es_careers },
	{ skin_key = "cwv_es_2h_sword_wh_03",          matching_weapon = "es_2h_sword", source_skin = "wh_2h_sword_skin_03",          can_wield = _es_careers },
	{ skin_key = "cwv_es_2h_sword_wh_04",          matching_weapon = "es_2h_sword", source_skin = "wh_2h_sword_skin_04",          can_wield = _es_careers },
	{ skin_key = "cwv_es_2h_sword_wh_05",          matching_weapon = "es_2h_sword", source_skin = "wh_2h_sword_skin_05",          can_wield = _es_careers },
	{ skin_key = "cwv_es_2h_sword_wh_05_runed_01", matching_weapon = "es_2h_sword", source_skin = "wh_2h_sword_skin_05_runed_01", can_wield = _es_careers },
	{ skin_key = "cwv_es_2h_sword_wh_05_runed_02", matching_weapon = "es_2h_sword", source_skin = "wh_2h_sword_skin_05_runed_02", can_wield = _es_careers },
	{ skin_key = "cwv_es_2h_sword_wh_04_magic_01", matching_weapon = "es_2h_sword", source_skin = "wh_2h_sword_skin_04_magic_01", can_wield = _es_careers },

	-- Kruber greatsword models on Saltzpyre's greatsword
	{ skin_key = "cwv_wh_2h_sword_es_01",          matching_weapon = "wh_2h_sword", source_skin = "es_2h_sword_skin_01",          can_wield = _wh_careers },
	{ skin_key = "cwv_wh_2h_sword_es_02",          matching_weapon = "wh_2h_sword", source_skin = "es_2h_sword_skin_02",          can_wield = _wh_careers },
	{ skin_key = "cwv_wh_2h_sword_es_02_runed_01", matching_weapon = "wh_2h_sword", source_skin = "es_2h_sword_skin_02_runed_01", can_wield = _wh_careers },
	{ skin_key = "cwv_wh_2h_sword_es_03",          matching_weapon = "wh_2h_sword", source_skin = "es_2h_sword_skin_03",          can_wield = _wh_careers },
	{ skin_key = "cwv_wh_2h_sword_es_04",          matching_weapon = "wh_2h_sword", source_skin = "es_2h_sword_skin_04",          can_wield = _wh_careers },
	{ skin_key = "cwv_wh_2h_sword_es_04_runed_01", matching_weapon = "wh_2h_sword", source_skin = "es_2h_sword_skin_04_runed_01", can_wield = _wh_careers },
	{ skin_key = "cwv_wh_2h_sword_es_04_runed_02", matching_weapon = "wh_2h_sword", source_skin = "es_2h_sword_skin_04_runed_02", can_wield = _wh_careers },
	{ skin_key = "cwv_wh_2h_sword_es_02_runed_03", matching_weapon = "wh_2h_sword", source_skin = "es_2h_sword_skin_02_runed_03", can_wield = _wh_careers },
	{ skin_key = "cwv_wh_2h_sword_es_05",          matching_weapon = "wh_2h_sword", source_skin = "es_2h_sword_skin_05",          can_wield = _wh_careers },
	{ skin_key = "cwv_wh_2h_sword_es_06",          matching_weapon = "wh_2h_sword", source_skin = "es_2h_sword_skin_06",          can_wield = _wh_careers },
	{ skin_key = "cwv_wh_2h_sword_es_03_magic_01", matching_weapon = "wh_2h_sword", source_skin = "es_2h_sword_skin_03_magic_01", can_wield = _wh_careers },
}

local _custom_skin_keys = {}

local function _register_custom_illusions()
	if not ItemMasterList or not WeaponSkins then return end

	for _, illusion in ipairs(_custom_illusions) do
		local skin_key = illusion.skin_key
		if _custom_skin_keys[skin_key] then goto continue end

		local source = WeaponSkins.skins[illusion.source_skin]
		if not source then
			mod:warning("Source skin '%s' not found in WeaponSkins — skipping %s", illusion.source_skin, skin_key)
			goto continue
		end

		local iml_entry = {
			item_type         = "weapon_skin",
			slot_type         = "weapon_skin",
			matching_item_key = illusion.matching_weapon,
			rarity            = source.rarity,
			display_name      = source.display_name,
			description       = source.description,
			display_unit      = source.display_unit,
			hud_icon          = source.hud_icon,
			inventory_icon    = source.inventory_icon,
			information_text  = "information_weapon_skin",
			right_hand_unit   = source.right_hand_unit,
			left_hand_unit    = source.left_hand_unit,
			template          = source.template,
			can_wield         = illusion.can_wield,
		}
		if source.material_settings_name then
			iml_entry.material_settings_name = source.material_settings_name
		end
		ItemMasterList[skin_key] = iml_entry

		local ws_entry = {
			description            = source.description,
			display_name           = source.display_name,
			display_unit           = source.display_unit,
			hud_icon               = source.hud_icon,
			inventory_icon         = source.inventory_icon,
			rarity                 = source.rarity,
			right_hand_unit        = source.right_hand_unit,
			left_hand_unit         = source.left_hand_unit,
			template               = source.template,
		}
		if source.material_settings_name then
			ws_entry.material_settings_name = source.material_settings_name
		end
		WeaponSkins.skins[skin_key] = ws_entry

		local weapon_data = ItemMasterList[illusion.matching_weapon]
		if weapon_data and weapon_data.skin_combination_table then
			local combos = WeaponSkins.skin_combinations[weapon_data.skin_combination_table]
			if combos then
				local rarity = source.rarity or "exotic"
				local tier = combos[rarity]
				if tier then
					tier[#tier + 1] = skin_key
				end
			end
		end

		if NetworkLookup and NetworkLookup.weapon_skins and not rawget(NetworkLookup.weapon_skins, skin_key) then
			local tbl = NetworkLookup.weapon_skins
			tbl[#tbl + 1] = skin_key
			tbl[skin_key] = #tbl
		end

		if NetworkLookup and NetworkLookup.item_names and not rawget(NetworkLookup.item_names, skin_key) then
			local tbl = NetworkLookup.item_names
			local idx = #tbl + 1
			rawset(tbl, idx, skin_key)
			rawset(tbl, skin_key, idx)
		end

		_custom_skin_keys[skin_key] = true
		mod:info("Registered custom illusion: %s (from %s) -> %s", skin_key, illusion.source_skin, illusion.matching_weapon)
		::continue::
	end
end

_register_custom_illusions()

mod:hook_safe("BackendInterfaceCraftingPlayfab", "get_unlocked_weapon_skins", function(self)
	local mirror = self._backend_mirror
	if not mirror or not mirror._unlocked_weapon_skins then return end
	for skin_key, _ in pairs(_custom_skin_keys) do
		mirror._unlocked_weapon_skins[skin_key] = true
	end
end)

-- ============================================================
-- Item creation helper (shared by give command)
-- ============================================================

local _registered_keys = {}

local function _build_entry(def, backend_id)
	local base = ItemMasterList[def.base_weapon]
	if not base then
		mod:warning("Base weapon '%s' not found in ItemMasterList", def.base_weapon)
		return nil
	end

	local entry = table.clone(base, true)

	entry.display_name = def.item_key .. "_name"
	entry.description = def.item_key .. "_description"

	if def.right_hand_unit then
		entry.right_hand_unit = def.right_hand_unit
	end
	if def.left_hand_unit then
		entry.left_hand_unit = def.left_hand_unit
	end
	if def.inventory_icon then
		entry.inventory_icon = def.inventory_icon
	end
	if def.hud_icon then
		entry.hud_icon = def.hud_icon
	end
	if def.careers then
		entry.can_wield = def.careers
	end
	if def.template then
		entry.template = def.template
	end
	entry.required_dlc = nil

	local traits = def.traits or {}
	local properties = def.properties or {}
	local power_level = def.power_level or 300

	local traits_json = "["
	for i, t in ipairs(traits) do
		if i > 1 then traits_json = traits_json .. "," end
		traits_json = traits_json .. '"' .. t .. '"'
	end
	traits_json = traits_json .. "]"

	local props_json = "{"
	local first = true
	for k, v in pairs(properties) do
		if not first then props_json = props_json .. "," end
		props_json = props_json .. '"' .. k .. '":' .. tostring(v)
		first = false
	end
	props_json = props_json .. "}"

	entry.rarity = "default"

	entry.mod_data = {
		backend_id = backend_id,
		ItemInstanceId = backend_id,
		CustomData = {
			traits = traits_json,
			power_level = tostring(power_level),
			properties = props_json,
			rarity = "default",
		},
		rarity = "default",
		traits = table.clone(traits, true),
		power_level = power_level,
		properties = table.clone(properties, true),
	}

	if not def.no_skin then
		local skin_key = def.item_key .. "_skin"
		entry.mod_data.CustomData.skin = skin_key
		entry.mod_data.skin = skin_key
	end

	return entry
end

-- ============================================================
-- Give command
-- ============================================================

local function _find_def(item_key)
	for _, def in ipairs(_variant_definitions) do
		if def.item_key == item_key then
			return def
		end
	end
	return nil
end

local function _register_item(def, backend_id)
	local mil = get_mod("MoreItemsLibrary")
	if not mil then
		mod:warning("MoreItemsLibrary not found — cannot register %s", def.item_key)
		return false
	end

	local entry = _build_entry(def, backend_id)
	if not entry then return false end

	mil:add_mod_items_to_local_backend({entry}, "character_weapon_variants")

	local key = entry.key or entry.name
	if key and NetworkLookup and NetworkLookup.item_names and not rawget(NetworkLookup.item_names, key) then
		local idx = #NetworkLookup.item_names + 1
		rawset(NetworkLookup.item_names, idx, key)
		rawset(NetworkLookup.item_names, key, idx)
	end

	_registered_keys[def.item_key] = backend_id
	return true
end

local function _give_variant(item_key)
	local def = _find_def(item_key)
	if not def then
		mod:echo("Unknown variant: %s", item_key)
		mod:echo("Available variants:")
		for _, d in ipairs(_variant_definitions) do
			mod:echo("  %s — %s", d.item_key, d.display_name)
		end
		return
	end

	if _registered_keys[item_key] then
		mod:echo("%s is already in your inventory", def.display_name)
		return
	end

	local backend_id = def.item_key .. "_001"
	if not _register_item(def, backend_id) then
		mod:echo("Failed to register %s", def.display_name)
		return
	end

	if Managers and Managers.backend then
		local backend_items = Managers.backend:get_interface("items")
		if backend_items and backend_items._refresh then
			backend_items:_refresh()
		end

		local rarity = def.rarity or "exotic"
		if rarity ~= "default" and backend_items then
			local item = backend_items:get_item_from_id(backend_id)
			if item then
				item.rarity = rarity
				item.data.rarity = rarity
				item.CustomData.rarity = rarity
			end
		end
	end

	mod:echo("Gave %s", def.display_name)
end

-- ============================================================
-- Auto-registration (deferred until backend is ready)
-- ============================================================

local _auto_registered = false

local function _auto_register_all()
	if _auto_registered then return end

	local mil = get_mod("MoreItemsLibrary")
	if not mil then
		mod:warning("MoreItemsLibrary not found — variant weapons will not be available")
		return
	end

	local entries = {}
	local pending_defs = {}
	for _, def in ipairs(_variant_definitions) do
		local backend_id = def.item_key .. "_001"
		if not _registered_keys[def.item_key] then
			local entry = _build_entry(def, backend_id)
			if entry then
				entries[#entries + 1] = entry
				pending_defs[#pending_defs + 1] = { def = def, backend_id = backend_id }
				_registered_keys[def.item_key] = backend_id
			end
		end
	end

	if #entries > 0 then
		mil:add_mod_items_to_local_backend(entries, "character_weapon_variants")

		if NetworkLookup and NetworkLookup.item_names then
			for _, entry in ipairs(entries) do
				local key = entry.key or entry.name
				if key and not rawget(NetworkLookup.item_names, key) then
					local idx = #NetworkLookup.item_names + 1
					rawset(NetworkLookup.item_names, idx, key)
					rawset(NetworkLookup.item_names, key, idx)
				end
			end
		end

		local backend_items = Managers.backend:get_interface("items")
		if backend_items and backend_items._refresh then
			backend_items:_refresh()
		end

		for _, pending in ipairs(pending_defs) do
			local rarity = pending.def.rarity or "exotic"
			if rarity ~= "default" and backend_items then
				local item = backend_items:get_item_from_id(pending.backend_id)
				if item then
					item.rarity = rarity
					item.data.rarity = rarity
					item.CustomData.rarity = rarity
					mod:info("Set %s rarity to %s", pending.def.item_key, rarity)
				end
			end
		end

		mod:info("Registered %d variant weapons", #entries)
	end

	_auto_registered = true
end

mod:hook_safe("StateInGameRunning", "on_enter", function()
	_auto_register_all()
end)

-- ============================================================
-- Animation remapping (weapon-scoped)
-- ============================================================

local _cwv_sword_shield_keys = {
	cwv_we_sword_shield = true,
	cwv_we_sword_shield_veteran = true,
}

local _local_fp_unit = nil
local _current_cwv_weapon = nil

local function _get_career_name(unit)
	if not Managers or not Managers.player then return nil end
	local player = Managers.player:owner(unit)
	if not player then return nil end
	local profile_index = player:profile_index()
	local career_index = player:career_index()
	if not profile_index or not career_index then return nil end
	local profile = SPProfiles and SPProfiles[profile_index]
	if not profile or not profile.careers then return nil end
	local career = profile.careers[career_index]
	return career and career.name
end

mod:hook_safe("ActionWield", "client_owner_start_action", function(self)
	_local_fp_unit = self.first_person_unit

	local inventory_extension = self.inventory_extension
	if inventory_extension then
		local equipment = inventory_extension:equipment()
		local new_slot = self.new_slot
		if equipment and equipment.slots and new_slot then
			local slot_data = equipment.slots[new_slot]
			if slot_data then
				local item_data = slot_data.item_data
				local item_key = item_data and item_data.key
				if item_key and _cwv_sword_shield_keys[item_key] then
					_current_cwv_weapon = item_key
				else
					_current_cwv_weapon = nil
				end
			end
		end
	end
end)

local _we_careers = {
	we_waywatcher = true,
	we_maidenguard = true,
	we_shade = true,
	we_thornsister = true,
}

local _wield_redirect = {
	to_1h_sword_shield = { target = "to_1h_spear_shield", careers = _we_careers },
}

local _suffix_redirect = {
	["_1h_sword_shield"] = { target = "_1h_spear_shield", careers = _we_careers },
}

local _weapon_remap = {
	attack_swing_charge_right_pose = "attack_swing_charge_right_diagonal_pose",
}

mod:hook(Unit, "animation_event", function(func, unit, event_name)
	if _local_fp_unit and unit == _local_fp_unit then
		return func(unit, event_name)
	end

	local redir = _wield_redirect[event_name]
	if redir then
		local career = _get_career_name(unit)
		if career and redir.careers[career] then
			return func(unit, redir.target)
		end
	end

	for suffix, data in pairs(_suffix_redirect) do
		if event_name:sub(-#suffix) == suffix then
			local career = _get_career_name(unit)
			if career and data.careers[career] then
				local base = event_name:sub(1, -(#suffix + 1))
				return func(unit, base .. data.target)
			end
		end
	end

	if _current_cwv_weapon and _cwv_sword_shield_keys[_current_cwv_weapon] then
		local target = _weapon_remap[event_name]
		if target and target ~= event_name then
			return func(unit, target)
		end
	end

	return func(unit, event_name)
end)

-- ============================================================
-- Model scaling (per-variant right_hand_scale / left_hand_scale)
-- ============================================================

local _scale_map = {}
for _, def in ipairs(_variant_definitions) do
	if def.right_hand_scale or def.left_hand_scale then
		_scale_map[def.item_key] = def
	end
end

local function _is_unit(v) return type(v) == "userdata" and pcall(Unit.alive, v) end

local function _apply_scale_to_unit(unit, scale_tbl)
	if not unit or not _is_unit(unit) then return end
	pcall(Unit.set_local_scale, unit, 0, Vector3(scale_tbl[1], scale_tbl[2], scale_tbl[3]))
end

mod:hook("GearUtils", "create_equipment", function(func, world, slot_name, item_data, unit_1p, unit_3p, is_bot, unit_template, extra_extension_data, ammo_percent, override_item_template, override_item_units, career_name)
	local result = func(world, slot_name, item_data, unit_1p, unit_3p, is_bot, unit_template, extra_extension_data, ammo_percent, override_item_template, override_item_units, career_name)
	if not result or not item_data then return result end

	local weapon_key = item_data.key or item_data.name
	local def = _scale_map[weapon_key]
	if not def then return result end

	if def.right_hand_scale then
		_apply_scale_to_unit(result.right_unit_1p, def.right_hand_scale)
		_apply_scale_to_unit(result.right_unit_3p, def.right_hand_scale)
	end
	if def.left_hand_scale then
		_apply_scale_to_unit(result.left_unit_1p, def.left_hand_scale)
		_apply_scale_to_unit(result.left_unit_3p, def.left_hand_scale)
	end

	return result
end)

local function _cwv_spawn_item_post(self, item_name)
	local def = _scale_map[item_name]
	if not def then return end

	local equip_units = self._equipment_units
	if not equip_units then return end

	for _, slot in pairs(equip_units) do
		if type(slot) == "table" then
			if def.right_hand_scale and slot.right and _is_unit(slot.right) then
				_apply_scale_to_unit(slot.right, def.right_hand_scale)
			end
			if def.left_hand_scale and slot.left and _is_unit(slot.left) then
				_apply_scale_to_unit(slot.left, def.left_hand_scale)
			end
		end
	end
end

mod:hook("HeroPreviewer", "_spawn_item", function(func, self, item_name, spawn_data)
	local result = func(self, item_name, spawn_data)
	_cwv_spawn_item_post(self, item_name)
	return result
end)

mod:hook("MenuWorldPreviewer", "_spawn_item", function(func, self, item_name, spawn_data)
	local result = func(self, item_name, spawn_data)
	_cwv_spawn_item_post(self, item_name)
	return result
end)

mod:hook_safe("LootItemUnitPreviewer", "spawn_units", function(self)
	local item = self._item
	if not item then return end
	local item_data = item.data
	local weapon_key = (item_data and item_data.key) or item.key
	if not weapon_key then return end

	local def = _scale_map[weapon_key]
	if not def then return end

	local spawned = self._spawned_units
	if not spawned then return end

	local scale = def.right_hand_scale or def.left_hand_scale
	if scale then
		for _, unit in ipairs(spawned) do
			_apply_scale_to_unit(unit, scale)
		end
	end
end)

-- ============================================================
-- Init
-- ============================================================

local _wt, _ct = _detect_companion_mods()

mod:command("cwv", "Character Weapon Variants status", function()
	mod:echo("Character Weapon Variants v%s", MOD_VERSION)
	mod:echo("  Definitions: %d", #_variant_definitions)
	local count = 0
	for _ in pairs(_registered_keys) do count = count + 1 end
	mod:echo("  Registered items: %d", count)
	mod:echo("  weapon_tweaker: %s", tostring(_wt ~= nil))
	mod:echo("  cosmetics_tweaker: %s", tostring(_ct ~= nil))
	for _, d in ipairs(_variant_definitions) do
		local status = _registered_keys[d.item_key] and "registered" or "not registered"
		mod:echo("    %s — %s (%s)", d.item_key, d.display_name, status)
	end
end)

mod:command("cwv_give", "Give a variant weapon: cwv_give <item_key>", function(item_key)
	if not item_key or item_key == "" then
		mod:echo("Usage: cwv_give <item_key>")
		mod:echo("Available variants:")
		for _, d in ipairs(_variant_definitions) do
			mod:echo("  %s — %s", d.item_key, d.display_name)
		end
		return
	end
	_give_variant(item_key)
end)

mod:info("Character Weapon Variants v%s loaded", MOD_VERSION)
