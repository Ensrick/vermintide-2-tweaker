-- _cwv_illusion_families.lua -- Ordered generated illusion-family registrars.
--
-- Loaded exactly once after _cwv_skin_registry at the original registration
-- boundary. It extends the registry-owned custom_skin_keys table in place.

return function(mod, deps)
	deps = deps or {}
	local _om = assert(deps.om, "_cwv_illusion_families requires deps.om")
	local _custom_skin_keys = assert(deps.custom_skin_keys, "_cwv_illusion_families requires deps.custom_skin_keys")
	local _illusion_provenance = assert(deps.illusion_provenance, "_cwv_illusion_families requires deps.illusion_provenance")
	local _es_all_careers = assert(deps.es_all_careers, "_cwv_illusion_families requires deps.es_all_careers")
	local _wh_all_careers = assert(deps.wh_all_careers, "_cwv_illusion_families requires deps.wh_all_careers")
	local _es_careers = assert(deps.es_careers, "_cwv_illusion_families requires deps.es_careers")
	local _wh_careers = assert(deps.wh_careers, "_cwv_illusion_families requires deps.wh_careers")
	local _kruber_1h_dual_skin_keys = assert(deps.kruber_1h_dual_skin_keys,
		"_cwv_illusion_families requires deps.kruber_1h_dual_skin_keys")
	local WeaponSkins = deps.WeaponSkins
	local ItemMasterList = deps.ItemMasterList
	local NetworkLookup = deps.NetworkLookup

-- CWV_ILLUSION_FAMILIES_PAYLOAD_BEGIN_v1
	-- Spear+Shield spear halves -> native Tuskgor Spear illusions (#620). The
	-- source shield is deliberately not copied. Legacy Infantry Spear skin ids are
	-- mapped during exact-instance migration rather than remaining a second pool.
	do
		local infantry = _om.infantry_spear
		local function _register_infantry_spear_illusions()
			if not ItemMasterList or not WeaponSkins then return end
			local target_item = "es_2h_heavy_spear"
			local target_combo = "es_2h_heavy_spear_skins"
			local combo = WeaponSkins.skin_combinations[target_combo]
			local elf_display = WeaponSkins.skins.we_spear_skin_01
			elf_display = elf_display and elf_display.display_unit
			local registered = 0
	
			for _, source_key in ipairs(infantry.SPEAR_SHIELD_SKINS) do
				local source = WeaponSkins.skins[source_key]
				if source and type(source.right_hand_unit) == "string" then
					local suffix = source_key:gsub("^es_deus_01_skin_", "")
					if suffix == "" then suffix = "01" end
					local skin_key = "cwv_tuskgor_spear_" .. suffix
					if not _custom_skin_keys[skin_key] then
						local row = {
							key = skin_key, name = skin_key,
							item_type = "weapon_skin", slot_type = "weapon_skin",
							matching_item_key = target_item,
							cwv_owner_item_type = target_item,
							rarity = source.rarity or "exotic",
							display_name = "cwv_es_infantry_spear_skin_name",
							description = "cwv_es_infantry_spear_description",
							display_unit = elf_display or source.display_unit,
							hud_icon = "weapon_generic_icon_falken",
							inventory_icon = source.inventory_icon or "icon_wpn_empire_spearshield_t1",
							information_text = "information_weapon_skin",
							right_hand_unit = source.right_hand_unit,
							template = "two_handed_heavy_spears_template",
							can_wield = { "es_huntsman", "es_knight" },
						}
						if source.material_settings_name then
							row.material_settings_name = source.material_settings_name
						end
						ItemMasterList[skin_key] = row
						WeaponSkins.skins[skin_key] = {
							description = row.description, display_name = row.display_name,
							display_unit = row.display_unit, hud_icon = row.hud_icon,
							inventory_icon = row.inventory_icon, rarity = row.rarity,
							right_hand_unit = source.right_hand_unit,
							template = "two_handed_heavy_spears_template",
							material_settings_name = source.material_settings_name,
						}
						local tier = combo and combo[row.rarity]
						if tier then tier[#tier + 1] = skin_key end
						for _, lookup_name in ipairs({ "weapon_skins", "item_names" }) do
							local lookup = NetworkLookup and NetworkLookup[lookup_name]
							if lookup and not rawget(lookup, skin_key) then
								local idx = #lookup + 1
								rawset(lookup, idx, skin_key)
								rawset(lookup, skin_key, idx)
							end
						end
						_om._skin_keys = _om._skin_keys or {}
						_om._skin_keys[skin_key] = true
						_custom_skin_keys[skin_key] = true
						registered = registered + 1
					end
				end
			end
			mod:info("Registered %d shield-free Spear+Shield models for Tuskgor Spear", registered)
		end
		_register_infantry_spear_illusions()
	end
	
	-- ============================================================
	-- Kruber 1h sword cosmetics → cwv_es_dual_swords illusions
	-- ============================================================
	-- Each vanilla `es_1h_sword_skin_*` is cloned into a new skin keyed
	-- `cwv_es_dual_swords_es_1h_sword_skin_*` and registered as an illusion
	-- option on `cwv_es_dual_swords`. The right-hand mesh is copied from the
	-- source skin; the left hand mirrors the right (identical-mesh dual-wield).
	--
	-- DUAL-WIELD DISPLAY RIG: each clone is registered with
	-- `display_unit = "units/weapons/weapon_display/display_dual_weapons"`
	-- (NOT inheriting `source.display_unit`, which is `display_1h_swords` —
	-- a single-sword rig that lacks `j_leftweaponattach` and crashes the
	-- previewer on left attach). See `DEVELOPMENT.md` "Dual-wield variants
	-- — display rig requirements" for the rule, and
	-- `J_LEFTWEAPONATTACH_INVESTIGATION.md` for the post-mortem on the
	-- ~20-version saga that surfaced it (v0.1.122 → v0.1.145).
	--
	-- `_kruber_1h_dual_skin_keys` retained as an inert registry marker (no
	-- runtime consumer; kept in case a future hook needs to filter on
	-- cwv_es_dual_swords skin lineage).
	
	local function _register_kruber_1h_sword_dual_illusions()
		if not ItemMasterList or not WeaponSkins then return end
	
		local source_keys = {}
		for skin_key, entry in pairs(ItemMasterList) do
			if _illusion_provenance.vanilla_owned(entry)
					and entry.matching_item_key == "es_1h_sword" then
				source_keys[#source_keys + 1] = skin_key
			end
		end
		table.sort(source_keys)
	
		local registered = 0
		for _, source_key in ipairs(source_keys) do
			local new_key = "cwv_es_dual_swords_" .. source_key
			if _custom_skin_keys[new_key] then goto continue end
	
			local source = WeaponSkins.skins[source_key]
			if not source or not source.right_hand_unit then goto continue end
	
			-- Mirror right_hand_unit → left_hand_unit so the picker (and
			-- in-game) renders two identical swords. Force display_unit to
			-- display_dual_weapons (the rig vanilla we_dual_sword_skin_*
			-- uses) — the source es_1h_sword skin's display_unit is
			-- display_1h_swords (single-sword rig with no j_leftweaponattach),
			-- which would crash the previewer on left attach.
			local dual_display_unit = "units/weapons/weapon_display/display_dual_weapons"
			local iml_entry = {
				key               = new_key,
				name              = new_key,
				item_type         = "weapon_skin",
				slot_type         = "weapon_skin",
				matching_item_key = "cwv_es_dual_swords",
				cwv_owner_item_type = "cwv_es_dual_swords",
				rarity            = source.rarity,
				display_name      = source.display_name,
				description       = source.description,
				display_unit      = dual_display_unit,
				hud_icon          = source.hud_icon,
				inventory_icon    = source.inventory_icon,
				information_text  = "information_weapon_skin",
				right_hand_unit   = source.right_hand_unit,
				left_hand_unit    = source.right_hand_unit,
				template          = source.template,
				can_wield         = _es_careers,
			}
			if source.material_settings_name then
				iml_entry.material_settings_name = source.material_settings_name
			end
			ItemMasterList[new_key] = iml_entry
	
			local ws_entry = {
				description     = source.description,
				display_name    = source.display_name,
				display_unit    = dual_display_unit,
				hud_icon        = source.hud_icon,
				inventory_icon  = source.inventory_icon,
				rarity          = source.rarity,
				right_hand_unit = source.right_hand_unit,
				left_hand_unit  = source.right_hand_unit,
				template        = source.template,
			}
			if source.material_settings_name then
				ws_entry.material_settings_name = source.material_settings_name
			end
			WeaponSkins.skins[new_key] = ws_entry
	
			_kruber_1h_dual_skin_keys[new_key] = true
	
			local combos = WeaponSkins.skin_combinations.cwv_es_dual_swords_skins
			if combos then
				local rarity = source.rarity or "exotic"
				local tier = combos[rarity]
				if tier then
					tier[#tier + 1] = new_key
				end
			end
	
			if NetworkLookup and NetworkLookup.weapon_skins and not rawget(NetworkLookup.weapon_skins, new_key) then
				local tbl = NetworkLookup.weapon_skins
				local idx = #tbl + 1
				rawset(tbl, idx, new_key)
				rawset(tbl, new_key, idx)
			end
	
			if NetworkLookup and NetworkLookup.item_names and not rawget(NetworkLookup.item_names, new_key) then
				local tbl = NetworkLookup.item_names
				local idx = #tbl + 1
				rawset(tbl, idx, new_key)
				rawset(tbl, new_key, idx)
			end
	
			_custom_skin_keys[new_key] = true
			registered = registered + 1
			::continue::
		end
	
		mod:info("Registered %d Kruber 1h sword cosmetics as cwv_es_dual_swords illusions", registered)
	end
	
	_register_kruber_1h_sword_dual_illusions()
	
	-- ============================================================
	-- Saltzpyre 1h axe cosmetics → cwv_es_dual_axes illusions
	-- ============================================================
	-- Each vanilla `wh_1h_axe_skin_*` is cloned into a new skin keyed
	-- `cwv_es_dual_axes_<source_key>` and registered as an illusion option on
	-- `cwv_es_dual_axes`. The right-hand axe mesh is copied from the source
	-- skin; the left hand mirrors the right (identical-mesh dual-wield).
	--
	-- DUAL-WIELD DISPLAY RIG: each clone is registered with
	-- `display_unit = "units/weapons/weapon_display/display_dual_axes"`
	-- (NOT inheriting `source.display_unit`, which is `display_1h_axes` —
	-- a single-sword rig that lacks `j_leftweaponattach` and crashes the
	-- previewer on left attach). Vanilla precedent: `dw_dual_axe_skin_01`
	-- (`weapon_skins.lua:2364`) uses the same rig with both hands set.
	-- See `DEVELOPMENT.md` "Dual-wield variants — display rig requirements"
	-- for the full rule and `J_LEFTWEAPONATTACH_INVESTIGATION.md` for the
	-- post-mortem on the rig requirement.
	
	local function _register_saltzpyre_1h_axe_dual_illusions()
		if not ItemMasterList or not WeaponSkins then return end
	
		-- CWV's authored thumbnail follows the PRIMARY/right-hand axe. This is
		-- intentionally different from the future shield-family rule, where the
		-- offhand shield will own the combined icon identity.
		local dual_inventory_icons = {
			icon_axe_hatchet_t2_magic_01 = "icon_axe_hatchet_t2_magic_01_dual_cwv",
			icon_wh_1h_axe_skin_06_magic_02 = "icon_wh_1h_axe_skin_06_magic_02_dual_cwv",
			icon_wpn_axe_02_t1 = "icon_wpn_axe_02_t1_dual_cwv",
			icon_wpn_axe_02_t2 = "icon_wpn_axe_02_t2_dual_cwv",
			icon_wpn_axe_02_t2_runed_06 = "icon_wpn_axe_02_t2_runed_06_dual_cwv",
			icon_wpn_axe_03_t1 = "icon_wpn_axe_03_t1_dual_cwv",
			icon_wpn_axe_03_t2 = "icon_wpn_axe_03_t2_dual_cwv",
			icon_wpn_axe_hatchet_t1 = "icon_wpn_axe_hatchet_t1_dual_cwv",
			icon_wpn_axe_hatchet_t2 = "icon_wpn_axe_hatchet_t2_dual_cwv",
		}
		_om._dual_axes_inventory_icon_by_source = dual_inventory_icons
	
		-- The combination table is the vanilla cosmetic owner's authoritative
		-- family.  Scanning ItemMasterList here used to depend on DLC load order,
		-- and the fixed destination tier list then silently dropped Scorpion's
		-- `magic` skin.  Preserve every source tier membership and add the vanilla
		-- default skin, which lives in WeaponSkins.default_skins rather than the
		-- combination table.
		local source_memberships = {}
		local source_combos = WeaponSkins.skin_combinations.wh_1h_axe_skins or {}
		for tier_name, tier in pairs(source_combos) do
			for _, source_key in ipairs(tier) do
				local memberships = source_memberships[source_key]
				if not memberships then
					memberships = {}
					source_memberships[source_key] = memberships
				end
				memberships[#memberships + 1] = tier_name
			end
		end
		local default_skin = WeaponSkins.default_skins and WeaponSkins.default_skins.wh_1h_axe
		if default_skin and not source_memberships[default_skin] then
			local default_data = WeaponSkins.skins[default_skin]
			source_memberships[default_skin] = { default_data and default_data.rarity or "plentiful" }
		end
	
		local source_keys = {}
		for source_key in pairs(source_memberships) do source_keys[#source_keys + 1] = source_key end
		table.sort(source_keys)
		local targets = {
			{ item_key = "cwv_es_dual_axes", combo = "cwv_es_dual_axes_skins", careers = _es_careers },
			{ item_key = "cwv_wh_dual_axes", combo = "cwv_wh_dual_axes_skins", careers = _wh_careers },
		}
		local source_by_target = {}
		_om._dual_axes_source_by_skin = source_by_target
	
		for _, target in ipairs(targets) do
			local source_by_clone = {}
			source_by_target[target.item_key] = source_by_clone
			local registered = 0
			for _, source_key in ipairs(source_keys) do
			local new_key = target.item_key .. "_" .. source_key
			local source = WeaponSkins.skins[source_key]
			local source_item = rawget(ItemMasterList, source_key)
			if not source or not source.right_hand_unit or not source_item
					or source_item.matching_item_key ~= "wh_1h_axe" then goto continue end
			local dual_inventory_icon = dual_inventory_icons[source.inventory_icon]
			if not dual_inventory_icon then
				mod:warning("Dual Axes icon missing for primary cosmetic %s (source icon=%s); using source icon",
					tostring(source_key), tostring(source.inventory_icon))
				dual_inventory_icon = source.inventory_icon
			end
			source_by_clone[new_key] = source_key
			if _custom_skin_keys[new_key] then goto continue end
	
			-- Mirror right_hand_unit → left_hand_unit so the picker (and
			-- in-game) renders two identical axes. Force display_unit to
			-- display_dual_axes (single-axe `display_1h_axes` from the source
			-- lacks j_leftweaponattach and would crash the previewer).
			local dual_display_unit = "units/weapons/weapon_display/display_dual_axes"
			local iml_entry = {
				key               = new_key,
				name              = new_key,
				item_type         = "weapon_skin",
				slot_type         = "weapon_skin",
				matching_item_key = target.item_key,
				cwv_owner_item_type = target.item_key,
				rarity            = source.rarity,
				display_name      = source.display_name,
				description       = source.description,
				display_unit      = dual_display_unit,
				hud_icon          = source.hud_icon,
				inventory_icon    = dual_inventory_icon,
				information_text  = "information_weapon_skin",
				right_hand_unit   = source.right_hand_unit,
				left_hand_unit    = source.right_hand_unit,
				template          = source.template,
				can_wield         = target.careers,
			}
			-- Ownership remains attached to the cosmetic, not the CWV weapon.  The
			-- unlock hook below consults this copied field before exposing the clone.
			if source_item.required_dlc then
				iml_entry.required_dlc = source_item.required_dlc
			end
			if source_item.event_quest_requirement then
				iml_entry.event_quest_requirement = source_item.event_quest_requirement
			end
			if source.material_settings_name then
				iml_entry.material_settings_name = source.material_settings_name
			end
			ItemMasterList[new_key] = iml_entry
	
			local ws_entry = {
				description     = source.description,
				display_name    = source.display_name,
				display_unit    = dual_display_unit,
				hud_icon        = source.hud_icon,
				inventory_icon  = dual_inventory_icon,
				rarity          = source.rarity,
				right_hand_unit = source.right_hand_unit,
				left_hand_unit  = source.right_hand_unit,
				template        = source.template,
			}
			if source.material_settings_name then
				ws_entry.material_settings_name = source.material_settings_name
			end
			WeaponSkins.skins[new_key] = ws_entry
	
			local combos = WeaponSkins.skin_combinations[target.combo]
			if combos then
				for _, tier_name in ipairs(source_memberships[source_key]) do
					local tier = combos[tier_name]
					if not tier then
						tier = {}
						combos[tier_name] = tier
					end
					local found = false
					for _, existing_key in ipairs(tier) do
						if existing_key == new_key then found = true break end
					end
					if not found then tier[#tier + 1] = new_key end
				end
			end
	
			if NetworkLookup and NetworkLookup.weapon_skins and not rawget(NetworkLookup.weapon_skins, new_key) then
				local tbl = NetworkLookup.weapon_skins
				local idx = #tbl + 1
				rawset(tbl, idx, new_key)
				rawset(tbl, new_key, idx)
			end
	
			if NetworkLookup and NetworkLookup.item_names and not rawget(NetworkLookup.item_names, new_key) then
				local tbl = NetworkLookup.item_names
				local idx = #tbl + 1
				rawset(tbl, idx, new_key)
				rawset(tbl, new_key, idx)
			end
	
			_custom_skin_keys[new_key] = true
			registered = registered + 1
			::continue::
			end
	
			mod:info("Registered %d Saltzpyre 1h axe cosmetics as %s illusions", registered, target.item_key)
		end
	end
	
	_register_saltzpyre_1h_axe_dual_illusions()
	
	-- ============================================================
	-- Empire 1h-mace cosmetics → cwv_es_dual_maces + cwv_wh_dual_maces illusions
	-- ============================================================
	-- Each vanilla `es_1h_mace_skin_*` is cloned into TWO new skin keys —
	-- `cwv_es_dual_maces_<source_key>` (Kruber's variant) and
	-- `cwv_wh_dual_maces_<source_key>` (Saltzpyre's variant) — and each clone
	-- is registered as an illusion option in the matching variant's picker.
	-- The right-hand mace mesh is copied from the source skin; the left hand
	-- mirrors the right (identical-mesh dual-wield).
	--
	-- DUAL-WIELD DISPLAY RIG: each clone is registered with
	-- `display_unit = "units/weapons/weapon_display/display_dual_hammers"`
	-- (NOT inheriting `source.display_unit`, which is `display_1h_hammer` —
	-- a single-hand rig that lacks `j_leftweaponattach` and crashes the
	-- previewer on left attach). Vanilla precedent: Bardin's dual-hammer
	-- skins in `weapon_skins_bless.lua:395` use the same rig with both
	-- hands set. See `DEVELOPMENT.md` "Dual-wield variants — display rig
	-- requirements" and `J_LEFTWEAPONATTACH_INVESTIGATION.md` for the rule.
	
	local function _register_es_1h_mace_dual_illusions()
		if not ItemMasterList or not WeaponSkins then return end
	
		local source_keys = {}
		for skin_key, entry in pairs(ItemMasterList) do
			-- #915 class fix: excludes cwv_es_cudgel_skin and cwv_dr_dawi_mace_skin,
			-- which borrow this matching key without vanilla family membership.
			if _illusion_provenance.vanilla_owned(entry)
					and entry.matching_item_key == "es_1h_mace" then
				source_keys[#source_keys + 1] = skin_key
			end
		end
		table.sort(source_keys)
	
		-- Two-target registration: each source skin produces a clone for both
		-- variants, routed to the variant's curated picker via matching_item_key.
		-- Listed in the order the picker should display.
		local _targets = {
			{ prefix = "cwv_es_dual_maces_", matching = "cwv_es_dual_maces", combo = "cwv_es_dual_maces_skins", careers = _es_all_careers },
			{ prefix = "cwv_wh_dual_maces_", matching = "cwv_wh_dual_maces", combo = "cwv_wh_dual_maces_skins", careers = _wh_all_careers },
		}
	
		local total = 0
		for _, target in ipairs(_targets) do
			local registered = 0
			for _, source_key in ipairs(source_keys) do
				local new_key = target.prefix .. source_key
				if _custom_skin_keys[new_key] then goto continue end
	
				local source = WeaponSkins.skins[source_key]
				if not source or not source.right_hand_unit then goto continue end
	
				-- Mirror right_hand_unit → left_hand_unit so the picker (and
				-- in-game) renders two identical maces. Force display_unit to
				-- display_dual_hammers — single-hand `display_1h_hammer` from
				-- the source lacks j_leftweaponattach and would crash the
				-- previewer on left attach.
				local dual_display_unit = "units/weapons/weapon_display/display_dual_hammers"
				local iml_entry = {
					key               = new_key,
					name              = new_key,
					item_type         = "weapon_skin",
					slot_type         = "weapon_skin",
					matching_item_key = target.matching,
					cwv_owner_item_type = target.matching,
					rarity            = source.rarity,
					display_name      = source.display_name,
					description       = source.description,
					display_unit      = dual_display_unit,
					hud_icon          = source.hud_icon,
					inventory_icon    = source.inventory_icon,
					information_text  = "information_weapon_skin",
					right_hand_unit   = source.right_hand_unit,
					left_hand_unit    = source.right_hand_unit,
					template          = source.template,
					can_wield         = target.careers,
				}
				if source.material_settings_name then
					iml_entry.material_settings_name = source.material_settings_name
				end
				ItemMasterList[new_key] = iml_entry
	
				local ws_entry = {
					description     = source.description,
					display_name    = source.display_name,
					display_unit    = dual_display_unit,
					hud_icon        = source.hud_icon,
					inventory_icon  = source.inventory_icon,
					rarity          = source.rarity,
					right_hand_unit = source.right_hand_unit,
					left_hand_unit  = source.right_hand_unit,
					template        = source.template,
				}
				if source.material_settings_name then
					ws_entry.material_settings_name = source.material_settings_name
				end
				WeaponSkins.skins[new_key] = ws_entry
	
				local combos = WeaponSkins.skin_combinations[target.combo]
				if combos then
					local rarity = source.rarity or "exotic"
					local tier = combos[rarity]
					if tier then
						tier[#tier + 1] = new_key
					end
				end
	
				if NetworkLookup and NetworkLookup.weapon_skins and not rawget(NetworkLookup.weapon_skins, new_key) then
					local tbl = NetworkLookup.weapon_skins
					local idx = #tbl + 1
					rawset(tbl, idx, new_key)
					rawset(tbl, new_key, idx)
				end
	
				if NetworkLookup and NetworkLookup.item_names and not rawget(NetworkLookup.item_names, new_key) then
					local tbl = NetworkLookup.item_names
					local idx = #tbl + 1
					rawset(tbl, idx, new_key)
					rawset(tbl, new_key, idx)
				end
	
				_custom_skin_keys[new_key] = true
				registered = registered + 1
				total = total + 1
				::continue::
			end
			mod:info("Registered %d empire 1h mace cosmetics as %s illusions", registered, target.matching)
		end
	
		mod:info("Total: %d dual-mace illusion entries (%d source skins × %d variants)", total, #source_keys, #_targets)
	end
	
	_register_es_1h_mace_dual_illusions()
	
	-- ============================================================
	-- Empire mace+sword's mace meshes → cwv_es_maul illusions
	-- ============================================================
	-- The Maul's cosmetic options are the MACE HALF (right_hand_unit) of
	-- vanilla `es_dual_wield_hammer_sword` (mace+sword) skins — NOT the
	-- separate `es_1h_mace` skin pool. This gives the Maul a curated set
	-- of 3-4 chunky mace heads that match the variant's identity (a 2H
	-- maul cloned from the mace+sword's club), instead of the smaller
	-- flanged maces from Kruber's 1H mace pool.
	--
	-- Mace+sword skin → mace mesh (right_hand_unit only):
	--   skin_01           → wpn_emp_mace_04_t2 (rare; same as the Maul's default mesh)
	--   skin_02           → wpn_emp_mace_05_t2 (exotic)
	--   skin_02_runed_01  → wpn_emp_mace_05_t2_runed_01 (unique)
	--   skin_02_magic_01  → wpn_emp_mace_04_t3_magic_01 (magic)
	--
	-- Single-handed (NOT mirrored) — the Maul wields one-handed via the
	-- wizard mace template's right_hand_unit. left_hand_unit from the
	-- source is DISCARDED (the sword half doesn't belong on a Maul).
	-- Source display_unit is overridden to display_1h_hammer (single-rig)
	-- because the source's mace+sword display_unit authors both attach
	-- nodes and would try to spawn a non-existent left unit.
	
	local function _register_macesword_mace_maul_illusions()
		if not ItemMasterList or not WeaponSkins then return end
	
		local source_keys = {}
		for skin_key, entry in pairs(ItemMasterList) do
			-- #915: cwv_es_sword_and_mace_skin borrows this matching key with a
			-- SWORD right hand (inverse layout); a bare family scan put a 1H
			-- sword in the Maul picker. See _cwv_illusion_provenance.
			if _illusion_provenance.vanilla_owned(entry)
					and entry.matching_item_key == "es_dual_wield_hammer_sword" then
				source_keys[#source_keys + 1] = skin_key
			end
		end
		table.sort(source_keys)
	
		-- #915 stale-generation scrub: drop picker-tier entries whose source row
		-- is CWV-owned (left behind by a pre-filter mod generation on VMF reload).
		_illusion_provenance.scrub_stale_picker_entries("cwv_es_maul_skins", "cwv_es_maul_")
	
		local single_hand_display = "units/weapons/weapon_display/display_1h_hammer"
	
		local registered = 0
		for _, source_key in ipairs(source_keys) do
			local new_key = "cwv_es_maul_" .. source_key
			if _custom_skin_keys[new_key] then goto continue end
	
			local source = WeaponSkins.skins[source_key]
			if not source or not source.right_hand_unit then goto continue end
	
			local iml_entry = {
				key               = new_key,
				name              = new_key,
				item_type         = "weapon_skin",
				slot_type         = "weapon_skin",
				matching_item_key = "cwv_es_maul",
				cwv_owner_item_type = "cwv_es_maul",
				rarity            = source.rarity,
				display_name      = source.display_name,
				description       = source.description,
				display_unit      = single_hand_display,
				hud_icon          = source.hud_icon,
				inventory_icon    = source.inventory_icon,
				information_text  = "information_weapon_skin",
				right_hand_unit   = source.right_hand_unit,
				-- Deliberately no left_hand_unit — source's left is the
				-- sword half of the mace+sword, which doesn't belong on a
				-- single-handed Maul. nil here means
				-- BackendUtils.get_item_units leaves the equipped variant's
				-- own left (none, for Maul) intact.
				template          = source.template,
				can_wield         = _es_all_careers,
			}
			if source.material_settings_name then
				iml_entry.material_settings_name = source.material_settings_name
			end
			ItemMasterList[new_key] = iml_entry
	
			local ws_entry = {
				description     = source.description,
				display_name    = source.display_name,
				display_unit    = single_hand_display,
				hud_icon        = source.hud_icon,
				inventory_icon  = source.inventory_icon,
				rarity          = source.rarity,
				right_hand_unit = source.right_hand_unit,
				template        = source.template,
			}
			if source.material_settings_name then
				ws_entry.material_settings_name = source.material_settings_name
			end
			WeaponSkins.skins[new_key] = ws_entry
	
			local combos = WeaponSkins.skin_combinations.cwv_es_maul_skins
			if combos then
				local rarity = source.rarity or "exotic"
				local tier = combos[rarity]
				if tier then
					tier[#tier + 1] = new_key
				end
			end
	
			if NetworkLookup and NetworkLookup.weapon_skins and not rawget(NetworkLookup.weapon_skins, new_key) then
				local tbl = NetworkLookup.weapon_skins
				local idx = #tbl + 1
				rawset(tbl, idx, new_key)
				rawset(tbl, new_key, idx)
			end
	
			if NetworkLookup and NetworkLookup.item_names and not rawget(NetworkLookup.item_names, new_key) then
				local tbl = NetworkLookup.item_names
				local idx = #tbl + 1
				rawset(tbl, idx, new_key)
				rawset(tbl, new_key, idx)
			end
	
			_custom_skin_keys[new_key] = true
			registered = registered + 1
			::continue::
		end
	
		mod:info("Registered %d mace+sword mace meshes as cwv_es_maul illusions", registered)
	end
	
	_register_macesword_mace_maul_illusions()
	
	-- ============================================================
	-- #597 converted Greataxe model manifest -> curated illusions
	-- ============================================================
	
	local function _register_greataxe_model_illusions()
		if not ItemMasterList or not WeaponSkins then return end
		local models = _om.greataxe.usable_models()
		local combos = WeaponSkins.skin_combinations[_om.greataxe.SKIN_COMBINATION]
		local registered = 0
	
		-- Model 1 is already represented by the variant's generated base skin.
		-- Register only the remaining confirmed rows so the picker has no duplicate.
		for index = 2, #models do
			local model = models[index]
			local key = model.key
			if _custom_skin_keys[key] then goto continue end
			local rarity = model.rarity or "exotic"
			local display_unit = model.display_unit or "units/weapons/weapon_display/display_2h_axes"
			local inventory_icon = model.inventory_icon or "icon_wpn_dw_2h_axe_01_t1"
			local hud_icon = model.hud_icon or "weapon_generic_icon_axe2h"
	
			ItemMasterList[key] = {
				key = key,
				name = key,
				item_type = "weapon_skin",
				slot_type = "weapon_skin",
				matching_item_key = _om.greataxe.BASE_WEAPON,
				cwv_owner_item_type = _om.greataxe.ITEM_KEY,
				rarity = rarity,
				display_name = key .. "_name",
				description = key .. "_description",
				display_unit = display_unit,
				hud_icon = hud_icon,
				inventory_icon = inventory_icon,
				information_text = "information_weapon_skin",
				right_hand_unit = model.right_hand_unit,
				can_wield = _om.greataxe.DEFAULT_CAREERS,
			}
			WeaponSkins.skins[key] = {
				description = key .. "_description",
				display_name = key .. "_name",
				display_unit = display_unit,
				hud_icon = hud_icon,
				inventory_icon = inventory_icon,
				rarity = rarity,
				right_hand_unit = model.right_hand_unit,
			}
	
			local tier = combos and combos[rarity]
			if tier then tier[#tier + 1] = key end
			for _, lookup_name in ipairs({ "weapon_skins", "item_names" }) do
				local lookup = NetworkLookup and NetworkLookup[lookup_name]
				if lookup and not rawget(lookup, key) then
					local lookup_index = #lookup + 1
					rawset(lookup, lookup_index, key)
					rawset(lookup, key, lookup_index)
				end
			end
			_custom_skin_keys[key] = true
			registered = registered + 1
			::continue::
		end
	
		mod:info("Registered %d additional converted Greataxe model illusions", registered)
	
		-- Issue #604: the first Imperial and sole Dawi rows are the generated base
		-- skins. Additional Imperial rows are real curated illusions in the same
		-- custom skin table; no Free Standard/unknown model can enter this manifest.
		local crowbill_registered = 0
		for _, model in ipairs(_om.crowbill_family.usable_models()) do
			if model.key == model.variant_key .. "_skin" or _custom_skin_keys[model.key] then
				goto continue_crowbill_model
			end
			local rarity = model.rarity or "exotic"
			local display_unit = model.display_unit or "units/weapons/weapon_display/display_1h_crowbills"
			local careers = model.variant_key == "cwv_dr_dawi_crowbill"
				and _om.crowbill_family.DAWI_DEFAULTS or _om.crowbill_family.IMPERIAL_DEFAULTS
			ItemMasterList[model.key] = {
				key = model.key,
				name = model.key,
				item_type = "weapon_skin",
				slot_type = "weapon_skin",
				matching_item_key = _om.crowbill_family.SOURCE_ITEM,
				cwv_owner_item_type = model.variant_key,
				rarity = rarity,
				display_name = model.key .. "_name",
				description = model.key .. "_description",
				display_unit = display_unit,
				hud_icon = model.hud_icon,
				inventory_icon = model.inventory_icon,
				information_text = "information_weapon_skin",
				right_hand_unit = model.right_hand_unit,
				can_wield = careers,
			}
			WeaponSkins.skins[model.key] = {
				description = model.key .. "_description",
				display_name = model.key .. "_name",
				display_unit = display_unit,
				hud_icon = model.hud_icon,
				inventory_icon = model.inventory_icon,
				rarity = rarity,
				right_hand_unit = model.right_hand_unit,
			}
			local crowbill_combos = WeaponSkins.skin_combinations[model.variant_key .. "_skins"]
			local tier = crowbill_combos and crowbill_combos[rarity]
			if tier then tier[#tier + 1] = model.key end
			for _, lookup_name in ipairs({ "weapon_skins", "item_names" }) do
				local lookup = NetworkLookup and NetworkLookup[lookup_name]
				if lookup and not rawget(lookup, model.key) then
					local lookup_index = #lookup + 1
					rawset(lookup, lookup_index, model.key)
					rawset(lookup, model.key, lookup_index)
				end
			end
			_om._skin_keys = _om._skin_keys or {}
			_om._skin_keys[model.key] = true
			_custom_skin_keys[model.key] = true
			crowbill_registered = crowbill_registered + 1
			::continue_crowbill_model::
		end
		mod:info("[cwv:604] Registered %d additional licensed Imperial Crowbill model illusions",
			crowbill_registered)
	end
	
	_register_greataxe_model_illusions()
	
	-- ============================================================
	-- Saltzpyre fencing-sword cosmetics → cwv_es_rapier illusions
	-- ============================================================
	-- Each vanilla `wh_fencing_sword_skin_*` registered as an illusion on
	-- the Rapier variant. Source skins always carry a pistol on
	-- left_hand_unit; we FORCE left_hand_unit = invisible weapon on every
	-- clone so the variant's "no pistol" identity holds across illusions.
	--
	-- Source's `display_fencing_swords` rig is preserved (it authors both
	-- right + left attach nodes; the invisible left unit attaches but is
	-- not visible).
	
	local function _register_rapier_illusions()
		if not ItemMasterList or not WeaponSkins then return end
	
		-- Illusions DELIBERATELY do not set `left_hand_unit`. Reason: the
		-- cosmetic picker's `_load_item_units` (line 281) only spawns a
		-- left-hand unit when `item_units.left_hand_unit` is truthy. With
		-- left_hand_unit nil on the illusion's skin entry,
		-- `BackendUtils.get_item_units` overwrites the inherited brace pistol
		-- with nil (line 174 of `backend_utils.lua` — the overwrite is
		-- unconditional, including nil), so the picker skips left-hand spawn
		-- entirely. No spawn → no `j_leftweaponattach` lookup → no crash.
		-- Crash GUID `962fe355-a0d4-43fd-9a29-bd64fca6a0ac` (v0.1.191).
		--
		-- The variant's DEFAULT skin (cwv_es_rapier_skin, set on equip when
		-- no illusion is applied) still carries `left_hand_unit = invisible_pistol`
		-- via the variant's IML entry — that's where the no-pistol identity is
		-- enforced. When an illusion IS applied, both the picker AND in-game
		-- skip the left spawn entirely (no invisible pistol attached, no
		-- visible difference since it was invisible anyway).
	
		local source_keys = {}
		for skin_key, entry in pairs(ItemMasterList) do
			-- #915 class fix: excludes cwv_es_rapier_skin, which would otherwise
			-- re-enter its own pool and duplicate the default mesh.
			if _illusion_provenance.vanilla_owned(entry)
					and entry.matching_item_key == "wh_fencing_sword" then
				source_keys[#source_keys + 1] = skin_key
			end
		end
		table.sort(source_keys)
	
		local registered = 0
		for _, source_key in ipairs(source_keys) do
			local new_key = "cwv_es_rapier_" .. source_key
			if _custom_skin_keys[new_key] then goto continue end
	
			local source = WeaponSkins.skins[source_key]
			if not source or not source.right_hand_unit then goto continue end
	
			local iml_entry = {
				key               = new_key,
				name              = new_key,
				item_type         = "weapon_skin",
				slot_type         = "weapon_skin",
				matching_item_key = "cwv_es_rapier",
				cwv_owner_item_type = "cwv_es_rapier",
				rarity            = source.rarity,
				display_name      = source.display_name,
				description       = source.description,
				display_unit      = source.display_unit,
				hud_icon          = source.hud_icon,
				inventory_icon    = source.inventory_icon,
				information_text  = "information_weapon_skin",
				right_hand_unit   = source.right_hand_unit,
				-- left_hand_unit DELIBERATELY omitted (see comment above).
				template          = source.template,
				can_wield         = _es_all_careers,
			}
			if source.material_settings_name then
				iml_entry.material_settings_name = source.material_settings_name
			end
			ItemMasterList[new_key] = iml_entry
	
			local ws_entry = {
				description     = source.description,
				display_name    = source.display_name,
				display_unit    = source.display_unit,
				hud_icon        = source.hud_icon,
				inventory_icon  = source.inventory_icon,
				rarity          = source.rarity,
				right_hand_unit = source.right_hand_unit,
				-- left_hand_unit DELIBERATELY omitted (see comment above).
				template        = source.template,
			}
			if source.material_settings_name then
				ws_entry.material_settings_name = source.material_settings_name
			end
			WeaponSkins.skins[new_key] = ws_entry
	
			local combos = WeaponSkins.skin_combinations.cwv_es_rapier_skins
			if combos then
				local rarity = source.rarity or "exotic"
				local tier = combos[rarity]
				if tier then
					tier[#tier + 1] = new_key
				end
			end
	
			if NetworkLookup and NetworkLookup.weapon_skins and not rawget(NetworkLookup.weapon_skins, new_key) then
				local tbl = NetworkLookup.weapon_skins
				local idx = #tbl + 1
				rawset(tbl, idx, new_key)
				rawset(tbl, new_key, idx)
			end
	
			if NetworkLookup and NetworkLookup.item_names and not rawget(NetworkLookup.item_names, new_key) then
				local tbl = NetworkLookup.item_names
				local idx = #tbl + 1
				rawset(tbl, idx, new_key)
				rawset(tbl, new_key, idx)
			end
	
			_custom_skin_keys[new_key] = true
			registered = registered + 1
			::continue::
		end
	
		mod:info("Registered %d fencing-sword cosmetics as cwv_es_rapier illusions (pistol forced invisible)", registered)
	end
	
	_register_rapier_illusions()
	
	-- ============================================================
	-- Empire shield options → cwv_es_longsword_shield illusions
	-- ============================================================
	-- Imperial Longsword + Shield variant carries a curated set of Empire
	-- shield + Imperial Longsword pairings. Each entry is a HARDCODED pair of
	-- (Empire shield mesh, Imperial Longsword sword mesh) — no IML scan.
	--
	-- Why hardcoded: the previous implementation (v0.1.175 → v0.1.250) scanned
	-- IML for `matching_item_key == "es_sword_shield"`, but that pool also
	-- contains our `cwv_we_sword_shield` (elf wood-elf) variant's auto-
	-- generated skin entries (they clone from the same base for template
	-- reasons). Result: the picker showed elven shields among the Empire
	-- options. v0.1.251 sidesteps the leak by enumerating Empire shield
	-- meshes directly.
	--
	-- Pairing rationale (best-effort thematic without localization access):
	--   * Plain state-issue shields (01_t1, 02) → Imperial Longsword
	--     (wpn_2h_sword_04_t1) — both basic Reikland regiment kit.
	--   * Mid-tier sealhide / coastal-style shields (03 + runed variant) →
	--     Helmgart Watchsword (wpn_greatsword) — western-pass watch theme.
	--   * Ornate / runed / magic shields (04, 04_magic_01, 05, 02_runed_01) →
	--     Black Guard Blade (wpn_2h_sword_03_t2) — knightly / Knights of
	--     Morr theme.
	-- Adjust the pairings below if the in-game shield names suggest a
	-- different match.
	
	-- Imperial Longsword sword meshes (Empire `es_2h_sword` family that the
	-- 2H cwv_es_longsword variants use as their default looks).
	local _ILS_RECRUIT_SWORD    = "units/weapons/player/wpn_empire_2h_sword_04_t1/wpn_2h_sword_04_t1"
	local _ILS_NORDLAND_SWORD   = "units/weapons/player/wpn_greatsword/wpn_greatsword"
	local _ILS_BLACKGUARD_SWORD = "units/weapons/player/wpn_empire_2h_sword_03_t2/wpn_2h_sword_03_t2"
	
	-- Saltzpyre's greatsword (`wh_2h_sword`) meshes — same family used by the
	-- 2H cwv_imperial_longsword cross-character illusions (CHANGELOG v0.1.113).
	-- All distinct from the Imperial mesh family above.
	local _ILS_WH_SWORD_01      = "units/weapons/player/wpn_empire_2h_sword_02_t1/wpn_2h_sword_02_t1"           -- wh skin_01 (plentiful)
	local _ILS_WH_SWORD_02      = "units/weapons/player/wpn_empire_2h_sword_02_t2/wpn_2h_sword_02_t2"           -- wh skin_02 (rare)
	local _ILS_WH_SWORD_02_RUNE = "units/weapons/player/wpn_empire_2h_sword_02_t2/wpn_2h_sword_02_t2_runed_01"  -- wh skin_02_runed_01 (unique)
	local _ILS_WH_SWORD_03      = "units/weapons/player/wpn_empire_2h_sword_02_t3/wpn_2h_sword_02_t3"           -- wh skin_03 (common)
	local _ILS_WH_SWORD_04      = "units/weapons/player/wpn_empire_2h_sword_04_t2/wpn_2h_sword_04_t2"           -- wh skin_04 (exotic)
	local _ILS_WH_SWORD_05      = "units/weapons/player/wpn_empire_2h_sword_05_t1/wpn_2h_sword_05_t1"           -- wh skin_05 (exotic)
	local _ILS_WH_SWORD_05_RUNE = "units/weapons/player/wpn_empire_2h_sword_05_t1/wpn_2h_sword_05_t1_runed_01"  -- wh skin_05_runed_01 (unique)
	
	-- Each entry: { left = shield mesh, right = paired sword, rarity = picker tier, suffix = unique key fragment }.
	-- `suffix` differentiates entries that share a shield (multiple swords
	-- pair against the same shield mesh — recruit vs wh_01, etc.). Without
	-- it, the per-shield key would collide and only the first registers.
	local _IMPERIAL_LONGSWORD_SHIELD_PAIRINGS = {
		-- ── Imperial sword family ─────────────────────────────────────
		-- Plentiful / basic: Imperial Longsword + plain Reikland shields.
		{ left = "units/weapons/player/wpn_empire_shield_01_t1/wpn_emp_shield_01_t1",     right = _ILS_RECRUIT_SWORD,    rarity = "plentiful", suffix = "recruit" },
		{ left = "units/weapons/player/wpn_empire_shield_02/wpn_emp_shield_02",           right = _ILS_RECRUIT_SWORD,    rarity = "plentiful", suffix = "recruit" },
		-- Rare / mid-tier: Helmgart Watchsword + mid-tier shields.
		{ left = "units/weapons/player/wpn_empire_shield_03/wpn_emp_shield_03",           right = _ILS_NORDLAND_SWORD,   rarity = "rare",      suffix = "nordland" },
		-- Exotic: Black Guard Blade + ornate shields.
		{ left = "units/weapons/player/wpn_empire_shield_04/wpn_emp_shield_04",           right = _ILS_BLACKGUARD_SWORD, rarity = "exotic",    suffix = "blackguard" },
		{ left = "units/weapons/player/wpn_empire_shield_05/wpn_emp_shield_05",           right = _ILS_BLACKGUARD_SWORD, rarity = "exotic",    suffix = "blackguard" },
		-- Unique (red illusion tier): runed shields.
		{ left = "units/weapons/player/wpn_empire_shield_02/wpn_emp_shield_02_runed_01",  right = _ILS_BLACKGUARD_SWORD, rarity = "unique",    suffix = "blackguard" },
		{ left = "units/weapons/player/wpn_empire_shield_03/wpn_emp_shield_03_runed_01",  right = _ILS_NORDLAND_SWORD,   rarity = "unique",    suffix = "nordland" },
		-- Magic (weave-forged): scorpion DLC's magic Empire shield.
		{ left = "units/weapons/player/wpn_empire_shield_04/wpn_emp_shield_04_magic_01",  right = _ILS_BLACKGUARD_SWORD, rarity = "magic",     suffix = "blackguard" },
	
		-- ── Saltzpyre wh_2h_sword family (added v0.1.254) ─────────────
		-- Same wh meshes used by cwv_imperial_longsword cross-character
		-- illusions per CHANGELOG v0.1.113. Paired with rotating Empire
		-- shields by rarity tier so each Saltzpyre sword appears alongside
		-- a shield it'd plausibly be carried with.
		{ left = "units/weapons/player/wpn_empire_shield_01_t1/wpn_emp_shield_01_t1",     right = _ILS_WH_SWORD_01,      rarity = "plentiful", suffix = "wh_01" },
		{ left = "units/weapons/player/wpn_empire_shield_02/wpn_emp_shield_02",           right = _ILS_WH_SWORD_03,      rarity = "common",    suffix = "wh_03" },
		{ left = "units/weapons/player/wpn_empire_shield_03/wpn_emp_shield_03",           right = _ILS_WH_SWORD_02,      rarity = "rare",      suffix = "wh_02" },
		{ left = "units/weapons/player/wpn_empire_shield_04/wpn_emp_shield_04",           right = _ILS_WH_SWORD_04,      rarity = "exotic",    suffix = "wh_04" },
		{ left = "units/weapons/player/wpn_empire_shield_05/wpn_emp_shield_05",           right = _ILS_WH_SWORD_05,      rarity = "exotic",    suffix = "wh_05" },
		{ left = "units/weapons/player/wpn_empire_shield_02/wpn_emp_shield_02_runed_01",  right = _ILS_WH_SWORD_02_RUNE, rarity = "unique",    suffix = "wh_02_runed" },
		{ left = "units/weapons/player/wpn_empire_shield_03/wpn_emp_shield_03_runed_01",  right = _ILS_WH_SWORD_05_RUNE, rarity = "unique",    suffix = "wh_05_runed" },
	}
	
	local function _register_imperial_longsword_shield_illusions()
		if not ItemMasterList or not WeaponSkins then return end
	
		local registered = 0
		for _, pair in ipairs(_IMPERIAL_LONGSWORD_SHIELD_PAIRINGS) do
			-- Key = `cwv_es_longsword_shield_<shield_tail>__<sword_suffix>`.
			-- Both fragments are required because multiple swords pair against
			-- the same shield (e.g. emp_shield_02 + recruit AND emp_shield_02
			-- + wh_03). Without the sword suffix the second registration would
			-- collide with the first and silently skip.
			local mesh_tail = pair.left:match("([^/]+)$") or pair.left
			local sword_frag = pair.suffix or "default"
			local new_key = "cwv_es_longsword_shield_" .. mesh_tail .. "__" .. sword_frag
			if _custom_skin_keys[new_key] then goto continue end
	
			local iml_entry = {
				key               = new_key,
				name              = new_key,
				item_type         = "weapon_skin",
				slot_type         = "weapon_skin",
				matching_item_key = "cwv_es_longsword_shield",
				cwv_owner_item_type = "cwv_es_longsword_shield",
				rarity            = pair.rarity,
				display_name      = "cwv_es_longsword_shield_skin_name",
				description       = "cwv_es_longsword_shield_description",
				display_unit      = "units/weapons/weapon_display/display_shield_sword",
				hud_icon          = "weapon_generic_icon_sword_and_sheild",
				inventory_icon    = "icon_wpn_empire_shield_02_sword",
				information_text  = "information_weapon_skin",
				right_hand_unit   = pair.right,
				left_hand_unit    = pair.left,
				template          = "one_handed_sword_shield_template_2",
				can_wield         = _es_all_careers,
			}
			ItemMasterList[new_key] = iml_entry
	
			WeaponSkins.skins[new_key] = {
				description     = "cwv_es_longsword_shield_description",
				display_name    = "cwv_es_longsword_shield_skin_name",
				display_unit    = "units/weapons/weapon_display/display_shield_sword",
				hud_icon        = "weapon_generic_icon_sword_and_sheild",
				inventory_icon  = "icon_wpn_empire_shield_02_sword",
				rarity          = pair.rarity,
				right_hand_unit = pair.right,
				left_hand_unit  = pair.left,
				template        = "one_handed_sword_shield_template_2",
			}
	
			local combos = WeaponSkins.skin_combinations.cwv_es_longsword_shield_skins
			if combos then
				local tier = combos[pair.rarity]
				if tier then
					tier[#tier + 1] = new_key
				end
			end
	
			if NetworkLookup and NetworkLookup.weapon_skins and not rawget(NetworkLookup.weapon_skins, new_key) then
				local tbl = NetworkLookup.weapon_skins
				local idx = #tbl + 1
				rawset(tbl, idx, new_key)
				rawset(tbl, new_key, idx)
			end
	
			if NetworkLookup and NetworkLookup.item_names and not rawget(NetworkLookup.item_names, new_key) then
				local tbl = NetworkLookup.item_names
				local idx = #tbl + 1
				rawset(tbl, idx, new_key)
				rawset(tbl, new_key, idx)
			end
	
			_custom_skin_keys[new_key] = true
			registered = registered + 1
			::continue::
		end
	
		mod:info("Registered %d Empire shield + Imperial Longsword pairings on cwv_es_longsword_shield", registered)
	end
	
	_register_imperial_longsword_shield_illusions()
	
	-- ============================================================
	-- Empire hatchet + shield options → cwv_es_axe_shield illusions
	-- ============================================================
	-- Same pattern as the longsword+shield pool above. Each entry is a
	-- HARDCODED pair of (Empire shield mesh, Empire hatchet mesh) — no IML
	-- scan, to keep the pool curated and avoid leak from sibling cwv
	-- variants that share the dr_shield_axe base.
	--
	-- Hatchet meshes come from the `wh_1h_axe` skin family (Saltzpyre's
	-- 1H axe pool — Empire-style hatchets, same family the default
	-- cwv_es_axe_shield + veteran variants already use). Shield meshes
	-- are the same Empire shield set the longsword+shield picker uses.
	--
	-- The default-rarity (blacksmith) cwv_es_axe_shield seeds itself into
	-- the pool but its appearance is locked by the blacksmith hook —
	-- applied illusions visually no-op on it. The unique-rarity veteran
	-- (and any future non-blacksmith Empire axe+shield variants sharing
	-- item_type = "cwv_es_axe_shield") visibly swap to the picked combo.
	
	do  -- scope mesh-path locals so they don't count against the Lua 5.1 200-local main-chunk limit
	
	local _EAS_AXE_02_T1   = "units/weapons/player/wpn_axe_02_t1/wpn_axe_02_t1"           -- wh_1h_axe_skin_01 (common)
	local _EAS_AXE_02_T2   = "units/weapons/player/wpn_axe_02_t2/wpn_axe_02_t2"           -- wh_1h_axe_skin_02 (rare)
	local _EAS_AXE_02_T2_R = "units/weapons/player/wpn_axe_02_t2/wpn_axe_02_t2_runed_01"  -- wh_1h_axe_skin_02_runed_01 (unique)
	local _EAS_AXE_03_T1   = "units/weapons/player/wpn_axe_03_t1/wpn_axe_03_t1"           -- wh_1h_axe_skin_03 (exotic)
	local _EAS_AXE_03_T2   = "units/weapons/player/wpn_axe_03_t2/wpn_axe_03_t2"           -- wh_1h_axe_skin_04 (exotic)
	local _EAS_AXE_03_T2_R = "units/weapons/player/wpn_axe_03_t2/wpn_axe_03_t2_runed_01"  -- wh_1h_axe_skin_04_runed_01 (unique)
	local _EAS_HATCHET_T1  = "units/weapons/player/wpn_axe_hatchet_t1/wpn_axe_hatchet_t1" -- wh_1h_axe_skin_05 (plentiful)
	local _EAS_HATCHET_T2  = "units/weapons/player/wpn_axe_hatchet_t2/wpn_axe_hatchet_t2" -- wh_1h_axe_skin_06 (exotic)
	
	-- Each entry: { left = shield mesh, right = paired hatchet, rarity = picker tier, suffix = unique key fragment }.
	-- `suffix` differentiates entries that share a shield mesh.
	local _AXE_SHIELD_PAIRINGS = {
		-- Plentiful: state-issue shields + plain hatchets.
		{ left = "units/weapons/player/wpn_empire_shield_01_t1/wpn_emp_shield_01_t1",    right = _EAS_HATCHET_T1,  rarity = "plentiful", suffix = "hatchet_t1" },
		{ left = "units/weapons/player/wpn_empire_shield_01_t1/wpn_emp_shield_01_t1",    right = _EAS_AXE_02_T1,   rarity = "plentiful", suffix = "axe_02_t1" },
		-- Common: Reikland-issue shields + plain hatchets.
		{ left = "units/weapons/player/wpn_empire_shield_02/wpn_emp_shield_02",          right = _EAS_HATCHET_T1,  rarity = "common",    suffix = "hatchet_t1" },
		-- Rare: mid-tier sealhide shields + tier-2 hatchets.
		{ left = "units/weapons/player/wpn_empire_shield_03/wpn_emp_shield_03",          right = _EAS_AXE_02_T2,   rarity = "rare",      suffix = "axe_02_t2" },
		{ left = "units/weapons/player/wpn_empire_shield_03/wpn_emp_shield_03",          right = _EAS_HATCHET_T2,  rarity = "rare",      suffix = "hatchet_t2" },
		-- Exotic: ornate shields + ornate hatchets.
		{ left = "units/weapons/player/wpn_empire_shield_04/wpn_emp_shield_04",          right = _EAS_AXE_03_T1,   rarity = "exotic",    suffix = "axe_03_t1" },
		{ left = "units/weapons/player/wpn_empire_shield_04/wpn_emp_shield_04",          right = _EAS_AXE_03_T2,   rarity = "exotic",    suffix = "axe_03_t2" },
		{ left = "units/weapons/player/wpn_empire_shield_05/wpn_emp_shield_05",          right = _EAS_AXE_03_T2,   rarity = "exotic",    suffix = "axe_03_t2" },
		{ left = "units/weapons/player/wpn_empire_shield_05/wpn_emp_shield_05",          right = _EAS_HATCHET_T2,  rarity = "exotic",    suffix = "hatchet_t2" },
		-- Unique (red illusion tier): runed shields + runed hatchets.
		{ left = "units/weapons/player/wpn_empire_shield_02/wpn_emp_shield_02_runed_01", right = _EAS_AXE_02_T2_R, rarity = "unique",    suffix = "axe_02_t2_runed" },
		{ left = "units/weapons/player/wpn_empire_shield_03/wpn_emp_shield_03_runed_01", right = _EAS_AXE_03_T2_R, rarity = "unique",    suffix = "axe_03_t2_runed" },
		-- Magic (weave-forged): scorpion DLC's magic Empire shield.
		{ left = "units/weapons/player/wpn_empire_shield_04/wpn_emp_shield_04_magic_01", right = _EAS_HATCHET_T2,  rarity = "magic",     suffix = "hatchet_t2" },
	}
	
	local function _register_axe_shield_illusions()
		if not ItemMasterList or not WeaponSkins then return end
	
		local registered = 0
		for _, pair in ipairs(_AXE_SHIELD_PAIRINGS) do
			-- Key = `cwv_es_axe_shield_<shield_tail>__<axe_suffix>`.
			-- Both fragments are required because multiple hatchets pair
			-- against the same shield mesh — without the axe suffix the
			-- per-shield key would collide and only the first registers.
			local mesh_tail = pair.left:match("([^/]+)$") or pair.left
			local axe_frag = pair.suffix or "default"
			local new_key = "cwv_es_axe_shield_" .. mesh_tail .. "__" .. axe_frag
			if _custom_skin_keys[new_key] then goto continue end
	
			local iml_entry = {
				key               = new_key,
				name              = new_key,
				item_type         = "weapon_skin",
				slot_type         = "weapon_skin",
				matching_item_key = "cwv_es_axe_shield",
				cwv_owner_item_type = "cwv_es_axe_shield",
				rarity            = pair.rarity,
				display_name      = "cwv_es_axe_shield_skin_name",
				description       = "cwv_es_axe_shield_description",
				display_unit      = "units/weapons/weapon_display/display_shield",
				hud_icon          = "weapon_generic_icon_axe_and_sheild",
				inventory_icon    = "icon_wpn_dw_shield_01_axe",
				information_text  = "information_weapon_skin",
				right_hand_unit   = pair.right,
				left_hand_unit    = pair.left,
				can_wield         = _es_all_careers,
			}
			ItemMasterList[new_key] = iml_entry
	
			WeaponSkins.skins[new_key] = {
				description     = "cwv_es_axe_shield_description",
				display_name    = "cwv_es_axe_shield_skin_name",
				display_unit    = "units/weapons/weapon_display/display_shield",
				hud_icon        = "weapon_generic_icon_axe_and_sheild",
				inventory_icon  = "icon_wpn_dw_shield_01_axe",
				rarity          = pair.rarity,
				right_hand_unit = pair.right,
				left_hand_unit  = pair.left,
			}
	
			local combos = WeaponSkins.skin_combinations.cwv_es_axe_shield_skins
			if combos then
				local tier = combos[pair.rarity]
				if tier then
					tier[#tier + 1] = new_key
				end
			end
	
			if NetworkLookup and NetworkLookup.weapon_skins and not rawget(NetworkLookup.weapon_skins, new_key) then
				local tbl = NetworkLookup.weapon_skins
				local idx = #tbl + 1
				rawset(tbl, idx, new_key)
				rawset(tbl, new_key, idx)
			end
	
			if NetworkLookup and NetworkLookup.item_names and not rawget(NetworkLookup.item_names, new_key) then
				local tbl = NetworkLookup.item_names
				local idx = #tbl + 1
				rawset(tbl, idx, new_key)
				rawset(tbl, new_key, idx)
			end
	
			_custom_skin_keys[new_key] = true
			registered = registered + 1
			::continue::
		end
	
		mod:info("Registered %d Empire shield + hatchet pairings on cwv_es_axe_shield", registered)
	end
	
	_register_axe_shield_illusions()
	
	end  -- do (axe+shield illusion scope)
	
	-- ============================================================
	-- Musket cosmetic illusions (alternate handgun meshes) — REMOVED v0.1.348-dev
	-- ============================================================
	-- These two cosmetic illusions (Aunty Bessie / Von Meinkopt's Single-Shooter,
	-- vanilla es_handgun t2/t3 skin meshes) existed ONLY to skin the on-ice
	-- `cwv_es_musket` variant (commented-out def near line ~582). They matched
	-- `matching_item_key = "cwv_es_musket"`, used `template = "musket_template"`,
	-- and referenced the `cwv_es_musket_description` loc key — all tied to the
	-- on-ice variant. The LIVE musket is `cwv_es_musket_old`, which ships its own
	-- custom mesh (units/cwv_es_musket_custom/...) under `old_musket_template`; the
	-- vanilla-handgun-mesh illusions would defeat that custom mesh and never
	-- attached to it. Their only other reference (instance_skins) is itself inside
	-- the commented on-ice block. So the registration was dead code with two
	-- dangling description loc refs (the cwv_es_musket_description key) flagged by
	-- qa/check_name_integrity.ps1 check #2. Removed alongside its on-ice owner. If
	-- the on-ice `cwv_es_musket` variant is ever re-enabled, restore these skins
	-- from git history (last present in v0.1.347-dev) and repoint the loc key /
	-- matching_item_key as needed.
	
	-- ============================================================
	-- Empire 1h sword + 1h mace → cwv_es_sword_and_mace illusions
	-- ============================================================
	-- Variant `cwv_es_sword_and_mace` is the inverse of vanilla mace+sword
	-- (sword right, mace left). Cosmetic options pair each vanilla
	-- `es_1h_sword` skin's mesh on the right hand with an `es_1h_mace`
	-- skin's mesh on the left hand.
	--
	-- Both source pools have 8 skins each. We sort each by rarity
	-- (common→plentiful→rare→exotic→unique→magic) then zip by index. The
	-- distributions don't perfectly match (sword has 3 unique + 1 exotic,
	-- mace has 2 unique + 2 exotic), so one pair (index 5) ends up
	-- mismatched (sword unique × mace exotic). All 8 pair cleanly otherwise.
	--
	-- Display rig: `display_dual_weapons` is forced via the existing
	-- `_force_display_unit[cwv_es_sword_and_mace]` entry on the variant's
	-- auto-generated default skin. Each illusion clone here also explicitly
	-- sets `display_unit` to `display_dual_weapons` (set on both IML and
	-- WeaponSkins.skins entries — the previewer reads it via two chains and
	-- needs it on both layers, per `feedback_cwv_dual_wield_display_rig.md`).
	
	local _RARITY_ORDER = {
		common = 1, plentiful = 2, rare = 3, exotic = 4, unique = 5, magic = 6,
	}
	
	local function _register_sword_and_mace_illusions()
		if not ItemMasterList or not WeaponSkins then return end
	
		-- Collect both source pools. We capture (skin_key, mesh, rarity) and
		-- sort by (rarity_priority, skin_key) for deterministic pairing order.
		local function _gather(matching_key)
			local pool = {}
			for skin_key, entry in pairs(ItemMasterList) do
				if type(entry) == "table"
						and entry.item_type == "weapon_skin"
						and entry.matching_item_key == matching_key
						and not entry.cwv_owner_item_type
						and entry.right_hand_unit then
					pool[#pool + 1] = {
						skin_key = skin_key,
						mesh     = entry.right_hand_unit,  -- es_1h_mace stores mesh as right_hand_unit even though we put it on the left
						rarity   = entry.rarity or "exotic",
					}
				end
			end
			table.sort(pool, function(a, b)
				local ra, rb = _RARITY_ORDER[a.rarity] or 99, _RARITY_ORDER[b.rarity] or 99
				if ra ~= rb then return ra < rb end
				return a.skin_key < b.skin_key
			end)
			return pool
		end
	
		local swords = _gather("es_1h_sword")
		local maces  = _gather("es_1h_mace")
	
		-- Zip by index. If counts differ (currently both 8, but defensive
		-- against future vanilla DLC adding skins to one but not the other),
		-- iterate the smaller of the two; surplus on either side stays
		-- unpaired.
		local n = math.min(#swords, #maces)
		if n == 0 then return end
	
		local display_unit = "units/weapons/weapon_display/display_dual_weapons"
	
		local registered = 0
		for i = 1, n do
			local sword = swords[i]
			local mace  = maces[i]
			-- Compose a stable key from both source paths' mesh tail components.
			-- Pattern: cwv_es_sword_and_mace_<sword_mesh_tail>_<mace_mesh_tail>.
			local sword_tail = sword.mesh:match("([^/]+)/[^/]+$") or sword.mesh
			local mace_tail  = mace.mesh:match("([^/]+)/[^/]+$") or mace.mesh
			local new_key = "cwv_es_sword_and_mace_" .. sword_tail .. "_" .. mace_tail
			if _custom_skin_keys[new_key] then goto continue end
	
			-- Picker rarity inherits the sword's rarity (the right-hand "primary"
			-- of the pair). Mace rarity may differ for mismatched index pairs;
			-- sword's reads as the headline cosmetic.
			local rarity = sword.rarity
	
			local iml_entry = {
				key               = new_key,
				name              = new_key,
				item_type         = "weapon_skin",
				slot_type         = "weapon_skin",
				matching_item_key = "cwv_es_sword_and_mace",
				cwv_owner_item_type = "cwv_es_sword_and_mace",
				rarity            = rarity,
				-- Display name / description fall through to a generic
				-- "Sword and Mace" — auto-populated from the variant def's
				-- skin_display_name / description via _display_names registration.
				display_name      = "cwv_es_sword_and_mace_skin_name",
				description       = "cwv_es_sword_and_mace_description",
				display_unit      = display_unit,
				hud_icon          = "weapon_generic_icon_falken",
				inventory_icon    = "icon_es_dual_wield_hammer_sword_01",
				information_text  = "information_weapon_skin",
				right_hand_unit   = sword.mesh,
				left_hand_unit    = mace.mesh,
				template          = "sword_and_mace_template",
				can_wield         = _es_all_careers,
			}
			ItemMasterList[new_key] = iml_entry
	
			WeaponSkins.skins[new_key] = {
				description     = "cwv_es_sword_and_mace_description",
				display_name    = "cwv_es_sword_and_mace_skin_name",
				display_unit    = display_unit,
				hud_icon        = "weapon_generic_icon_falken",
				inventory_icon  = "icon_es_dual_wield_hammer_sword_01",
				rarity          = rarity,
				right_hand_unit = sword.mesh,
				left_hand_unit  = mace.mesh,
				template        = "sword_and_mace_template",
			}
	
			local combos = WeaponSkins.skin_combinations.cwv_es_sword_and_mace_skins
			if combos then
				local tier = combos[rarity]
				if tier then
					tier[#tier + 1] = new_key
				end
			end
	
			if NetworkLookup and NetworkLookup.weapon_skins and not rawget(NetworkLookup.weapon_skins, new_key) then
				local tbl = NetworkLookup.weapon_skins
				local idx = #tbl + 1
				rawset(tbl, idx, new_key)
				rawset(tbl, new_key, idx)
			end
	
			if NetworkLookup and NetworkLookup.item_names and not rawget(NetworkLookup.item_names, new_key) then
				local tbl = NetworkLookup.item_names
				local idx = #tbl + 1
				rawset(tbl, idx, new_key)
				rawset(tbl, new_key, idx)
			end
	
			_custom_skin_keys[new_key] = true
			registered = registered + 1
			::continue::
		end
	
		mod:info("Registered %d sword+mace illusion pairs on cwv_es_sword_and_mace (1h sword right × 1h mace left, rarity-sorted zip)", registered)
	end
	
	_register_sword_and_mace_illusions()
-- CWV_ILLUSION_FAMILIES_PAYLOAD_END_v1

	return true
end

