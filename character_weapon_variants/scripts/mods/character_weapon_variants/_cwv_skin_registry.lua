-- _cwv_skin_registry.lua -- Ordered base/custom skin registration owner.
--
-- Loaded exactly once at the original registration boundary. This module owns
-- no hooks, commands, peer transport, appearance lifecycle, or gameplay logic.

return function(mod, deps)
	deps = deps or {}
	local _om = assert(deps.om, "_cwv_skin_registry requires deps.om")
	local _variant_definitions = assert(deps.variant_definitions, "_cwv_skin_registry requires deps.variant_definitions")
	local WeaponSkins = deps.WeaponSkins
	local ItemMasterList = deps.ItemMasterList
	local NetworkLookup = deps.NetworkLookup
	local printf = deps.printf

-- CWV_SKIN_REGISTRY_PAYLOAD_BEGIN_v1
	-- ============================================================
	-- Custom skin registration
	-- ============================================================

	-- Registry of cwv_es_dual_swords skin keys (default + the 17 Kruber 1h-sword
	-- illusion clones registered by `_register_kruber_1h_sword_dual_illusions`).
	-- INERT MARKER as of v0.1.145 — no runtime hook consumes it. Previously read by
	-- a `BackendUtils.get_item_units` right→left mirror that worked around the skin
	-- entries omitting `left_hand_unit`; the mirror and its callers were removed
	-- when the skins gained `left_hand_unit` directly and switched to the
	-- `display_dual_weapons` rig (see `J_LEFTWEAPONATTACH_INVESTIGATION.md`).
	-- Kept declared here in case a future hook needs to filter on
	-- cwv_es_dual_swords skin lineage; safe to remove if unused 6 months out.
	local _kruber_1h_dual_skin_keys = {}

	-- QUESTION: skin_only entries (e.g. cwv_es_longsword_nordland) are NOT skipped
	-- here — only def.no_skin gates skin registration. That's deliberate: skin_only
	-- entries exist precisely to provide a selectable cosmetic skin without giving
	-- the player the inventory item itself. Documented for clarity.
	local function _register_variant_skins()
		if not WeaponSkins then return end
		for _, def in ipairs(_variant_definitions) do
			if def.no_skin then goto skip_skin end
			local skin_key = def.item_key .. "_skin"
			-- ALWAYS overwrite (no `if not WeaponSkins.skins[skin_key]` guard) so
			-- partial reloads or earlier mod versions don't leave a stale skin entry
			-- without our newer fields (e.g. ammo_unit added in 0.1.60).
			--
			-- For ammo weapons (e.g. javelin variants) we MUST mirror ammo_unit
			-- into the skin entry. BackendUtils.get_item_units overwrites
			-- units.ammo_unit with skin_template.ammo_unit unconditionally when a
			-- skin is set, so an absent field on the skin nukes the inherited
			-- value from the base ItemMasterList entry. Downstream the previewer
			-- does `left_hand_unit = ammo_unit` for is_ammo_weapon items and then
			-- concatenates "_3p" — nil ammo_unit crashes that line. Fall back to
			-- def.left_hand_unit (the held model) when ammo_unit isn't set so the
			-- spear/javelin/etc. swap still drives the held + thrown visual.
			-- Defense in depth: BackendUtils.get_item_units overwrites a whole set
			-- of fields from skin_template, not just ammo_unit. Mirror them all from
			-- the base ItemMasterList entry when the variant doesn't override —
			-- prevents the throw projectile / pickup spawn paths from getting nil
			-- once the held-model crash is past.
			--
			-- v0.1.182: gated the def.left_hand_unit fallback on `base.ammo_unit`.
			-- For variants whose base weapon DOESN'T have ammo_unit (e.g. brace of
			-- pistols, repeating pistols — `wh_brace_of_pistols` has no
			-- ammo_unit), forcing one in via def.left_hand_unit triggers
			-- GearUtils.spawn_inventory_unit's `fassert(ammo_unit_attachment_node_linking)`
			-- — the brace template defines ammo_data with `ammo_hand = "right"`
			-- but no ammo_unit_attachment_node_linking (because vanilla
			-- never uses ammo_unit there). Crash GUID 2df233ae-80f6-40d3-aa58-e98417f2ad8f.
			-- Now: only default to def.left_hand_unit when base has ammo_unit;
			-- otherwise leave nil and let vanilla's no-ammo_unit path run.
			local base = (ItemMasterList and rawget(ItemMasterList, def.base_weapon)) or {}
			local ammo_unit = def.ammo_unit or (base.ammo_unit and def.left_hand_unit)
			local hud_icon = def.hud_icon or "weapon_generic_icon_axe1h"
			local inventory_icon = def.inventory_icon or "icon_wpn_dw_shield_01_axe"
			local rarity = def.skin_rarity or def.rarity or "exotic"
			-- display_unit is the LINK UNIT the LootItemUnitPreviewer spawns first
			-- as the spinning pivot in the weapon-customization preview pane. It's
			-- a vanilla "stage" mesh (e.g. `display_2h_swords` for greatswords).
			-- `_spawn_link_unit` reads `item_data.display_unit` then
			-- `WeaponSkins.skins[skin].display_unit` and bails with a warning if
			-- both are nil — the weapon units have nothing to attach to, so they
			-- don't render. Vanilla WEAPON entries (e.g. `es_bastard_sword` in
			-- `item_master_list_lake.lua:186`) DON'T carry `display_unit` on the
			-- weapon's row — only weapon_skin rows do (`es_bastard_sword_skin_01`
			-- has `display_unit = "units/weapons/weapon_display/display_2h_swords"`).
			-- v0.1.99 tried `base.display_unit` and got nil for every variant;
			-- the picker stayed invisible (log: "Couldn't find any display unit
			-- for item cwv_es_longsword_skin"). Resolve by scanning ItemMasterList
			-- for any vanilla weapon_skin whose `matching_item_key` matches our
			-- `base_weapon` and copying its `display_unit`. Per-variant
			-- `def.display_unit` overrides if set.
			local display_unit = def.display_unit
			if not display_unit and ItemMasterList then
				for _, entry in pairs(ItemMasterList) do
					if entry.item_type == "weapon_skin"
							and entry.matching_item_key == def.base_weapon
							and entry.display_unit then
						display_unit = entry.display_unit
						break
					end
				end
			end

			-- DUAL-WIELD DISPLAY RIG.
			-- The cosmetic illusion picker attaches each hand's weapon unit to a
			-- named node on the `display_unit` pivot. Single-sword rigs only author
			-- `j_rightweaponattach`; the previewer crashes with `[Script Error]:
			-- j_leftweaponattach` if it tries to attach the left hand against one.
			-- The lookup loop above can return a wrong-family rig (vanilla
			-- dual-wield IML weapon_skin entries often don't set display_unit, so
			-- the loop can fall through to a sibling skin's value), so override
			-- here per-variant.
			--
			-- `_force_display_unit` maps each cwv item_key to the dual-attach rig
			-- vanilla uses for the matching weapon family. All listed rigs are
			-- known to author both `j_rightweaponattach` and `j_leftweaponattach`
			-- (proven by the rig appearing in `weapon_skins.lua` for a vanilla
			-- weapon whose cosmetic picker is shipped + working). See
			-- `J_LEFTWEAPONATTACH_INVESTIGATION.md` for the post-mortem and
			-- `DEVELOPMENT.md` "Dual-wield variants — display rig requirements"
			-- for the rig-per-family table.
			local _force_display_unit = {
				-- Identical-mesh empire short-swords; vanilla precedent: we_dual_sword_skin_01 (`weapon_skins.lua:5750`)
				cwv_es_dual_swords    = "units/weapons/weapon_display/display_dual_weapons",
				-- Identical-mesh hatchets; vanilla precedent: dw_dual_axe_skin_01 (`weapon_skins.lua:2364`)
				cwv_es_dual_axes      = "units/weapons/weapon_display/display_dual_axes",
				cwv_wh_dual_axes      = "units/weapons/weapon_display/display_dual_axes",
				-- Identical-mesh empire maces; vanilla precedent: dual_wield_hammers
				-- skins in `weapon_skins_bless.lua:395` use display_dual_hammers.
				cwv_es_dual_maces             = "units/weapons/weapon_display/display_dual_hammers",
				cwv_wh_dual_maces             = "units/weapons/weapon_display/display_dual_hammers",
				cwv_dr_dawi_dual_maces        = "units/weapons/weapon_display/display_dual_hammers",
				cwv_dr_dawi_mace_shield       = "units/weapons/weapon_display/display_shield_hammer",
				-- Identical-mesh wh_1h_hammer Skullsplitters dual-wielded; vanilla
				-- precedent: wh_dual_hammer in `dual_wield_hammers_priest.lua:1720`
				-- sets the same rig on the priest dual-hammers weapon template,
				-- and vanilla Saltzpyre wh_dual_hammer cosmetic preview is a
				-- shipped, working feature.
				cwv_es_dual_warpriest_hammers = "units/weapons/weapon_display/display_dual_hammers",
				-- Mixed-mesh sword (right) + mace (left); vanilla precedent:
				-- dual_wield_hammer_sword.lua:1572 sets the same rig on the
				-- weapon template, and vanilla Kruber mace+sword cosmetic
				-- preview is a shipped, working feature.
				cwv_es_sword_and_mace = "units/weapons/weapon_display/display_dual_weapons",
				-- Skullsplitter (right) + Empire shield (left); vanilla precedent:
				-- wh_hammer_shield in `1h_hammers_shield_priest.lua` uses
				-- display_shield_hammer. Same rig works for our variant since
				-- the right-hand mesh is also a hammer (the wh_1h_hammer_01
				-- Skullsplitter).
				cwv_es_warpriest_hammer_shield = "units/weapons/weapon_display/display_shield_hammer",
			}
			local skin_left_hand_unit = def.left_hand_unit
			local forced_rig = _force_display_unit[def.item_key]
			if forced_rig then
				display_unit = forced_rig
				-- Inert legacy registry — see declaration above.
				if def.item_key == "cwv_es_dual_swords" then
					_kruber_1h_dual_skin_keys[skin_key] = true
				end
			end

			WeaponSkins.skins[skin_key] = {
				display_name              = def.item_key .. "_skin_name",
				description               = def.item_key .. "_description",
				rarity                    = rarity,
				right_hand_unit           = def.right_hand_unit,
				left_hand_unit            = skin_left_hand_unit,
				ammo_unit                 = ammo_unit,
				ammo_unit_3p              = def.ammo_unit_3p or base.ammo_unit_3p,
				projectile_units_template = def.projectile_units_template or base.projectile_units_template,
				pickup_template_name      = def.pickup_template_name or base.pickup_template_name,
				link_pickup_template_name = def.link_pickup_template_name or base.link_pickup_template_name,
				hud_icon                  = hud_icon,
				inventory_icon            = inventory_icon,
				display_unit              = display_unit,
				template                  = nil,
			}
			mod:info("Registered custom skin: %s (ammo_unit=%s, projectile=%s, display_unit=%s)",
				skin_key, tostring(ammo_unit),
				tostring(def.projectile_units_template or base.projectile_units_template),
				tostring(display_unit))

			-- ItemMasterList registration for the skin entry. WITHOUT this,
			-- vanilla `HeroWindowItemCustomization._apply_skin_to_item` (the
			-- inventory illusion picker) does `ItemMasterList[skin_key]`, gets
			-- nil, and crashes with `attempt to index local 'item_data' (a nil
			-- value)` at the next field access. Same shape cosmetics_tweaker
			-- uses for its custom illusions (see `_register_custom_illusions`).
			-- The v0.1.87 default-rarity-skin gate exposed this latent bug:
			-- previously a default-rarity blacksmith never opened the illusion
			-- picker because the item was treated as locked, so the missing
			-- ItemMasterList entry was never reached.
			if ItemMasterList and not rawget(ItemMasterList, skin_key) then
				-- matching_item_key MUST resolve to an entry with a valid template:
				-- vanilla `_apply_skin_to_item` does
				-- `ItemHelper.get_template_by_item_name(matching_item_key)` and
				-- crashes on missing templates with "Requested template for item
				-- <key> which does not exist". Use `def.base_weapon` — the
				-- vanilla weapon every cwv variant clones from, always present in
				-- ItemMasterList with a real template (e.g. `bastard_sword_template`).
				-- DON'T use `def.item_key`: skin_only variants
				-- (e.g. cwv_es_longsword_nordland) skip the `_auto_register_all`
				-- mirror so their item_key is NOT in ItemMasterList. v0.1.91 used
				-- item_key and crashed when applying a skin_only variant's
				-- illusion (GUID ca46d7b2-65b8-41b2-b16b-d71b6dcb9be6).
				ItemMasterList[skin_key] = {
					-- Explicit `key` and `name`. Vanilla `parse_item_master_list`
					-- (`item_master_list.lua:109`) sets these on every entry at
					-- boot via `item.key = key; item.name = key`. We register
					-- AFTER boot, so without these explicit assignments
					-- `item_data.key` is nil and `LootItemUnitPreviewer._load_item_units`
					-- (line 254) `item_key = item_data.key or item.key` falls
					-- through to nil → `ItemMasterList[nil]` → silent failure
					-- chain ending in invisible preview.
					key               = skin_key,
					name              = skin_key,
					item_type         = "weapon_skin",
					slot_type         = "weapon_skin",
					matching_item_key = def.style_target_item or def.base_weapon,
					cwv_owner_item_type = def.item_key,
					rarity            = rarity,
					display_name      = def.item_key .. "_skin_name",
					description       = def.item_key .. "_description",
					right_hand_unit   = def.right_hand_unit,
					left_hand_unit    = skin_left_hand_unit,
					-- display_unit is required by `LootItemUnitPreviewer._spawn_link_unit`
					-- (line 467, 472). The previewer reads it from the item_data
					-- AND from the WeaponSkins.skins entry — set it on both.
					-- Without it the link unit fails to spawn and weapon units have
					-- nothing to attach to, so the picker preview is empty.
					display_unit      = display_unit,
					hud_icon          = hud_icon,
					inventory_icon    = inventory_icon,
					information_text  = "information_weapon_skin",
					can_wield         = def.careers,
					template          = nil,
				}
			end
			-- A VMF hot reload can retain the previous ItemMasterList row and skip
			-- the constructor above.  Reconcile the additive ownership field on the
			-- retained row as well so Cosmetics never falls back to the compatibility
			-- matching key for a generated CWV skin.
			local registered_skin = ItemMasterList and rawget(ItemMasterList, skin_key)
			if type(registered_skin) == "table" then
				registered_skin.cwv_owner_item_type = def.item_key
			end

			if NetworkLookup and NetworkLookup.weapon_skins and not rawget(NetworkLookup.weapon_skins, skin_key) then
				local idx = #NetworkLookup.weapon_skins + 1
				rawset(NetworkLookup.weapon_skins, idx, skin_key)
				rawset(NetworkLookup.weapon_skins, skin_key, idx)
				mod:info("Injected '%s' into NetworkLookup.weapon_skins at index %d", skin_key, idx)
			end

			-- Mirror the skin key into NetworkLookup.item_names too. Vanilla
			-- weapon-skin backend RPCs and equipment-grid widgets do
			-- `NetworkLookup.item_names[key]` on the skin key — without this, any
			-- network sync path that references the skin key crashes per the same
			-- v0.1.24 weapon-item issue documented in the changelog.
			if NetworkLookup and NetworkLookup.item_names and not rawget(NetworkLookup.item_names, skin_key) then
				local idx = #NetworkLookup.item_names + 1
				rawset(NetworkLookup.item_names, idx, skin_key)
				rawset(NetworkLookup.item_names, skin_key, idx)
			end
			-- Track every cwv skin key so the wire-safety hook (issue 278 weapon_skin_id
			-- axis / issue 371) can null it on rpc_add_equipment for non-cwv peers.
			_om._skin_keys = _om._skin_keys or {}
			_om._skin_keys[skin_key] = true
			::skip_skin::
		end
	end

	_register_variant_skins()

	local function _empty_skin_tiers()
		return {
			default   = {},
			plentiful = {},
			common    = {},
			rare      = {},
			exotic    = {},
			unique    = {},
		}
	end

	local function _register_cwv_skin_combinations()
		if not WeaponSkins or not WeaponSkins.skin_combinations then return end

		-- Each item_type gets its own skin_combination_table seeded with the
		-- variant's auto-generated `<item_key>_skin` entries. Cross-character
		-- illusion functions (e.g. `_register_kruber_1h_sword_dual_illusions`)
		-- append additional skin keys to these tables after seeding.
		local _seed_targets = {
			cwv_imperial_longsword         = "cwv_imperial_longsword_skins",
			cwv_es_longsword_shield        = "cwv_es_longsword_shield_skins",
			cwv_es_axe_shield              = "cwv_es_axe_shield_skins",
			cwv_es_infantry_spear          = "cwv_es_infantry_spear_skins",
			cwv_es_dual_swords             = "cwv_es_dual_swords_skins",
			cwv_es_dual_axes               = "cwv_es_dual_axes_skins",
			cwv_wh_dual_axes               = "cwv_wh_dual_axes_skins",
			cwv_es_dual_maces              = "cwv_es_dual_maces_skins",
			cwv_wh_dual_maces              = "cwv_wh_dual_maces_skins",
			cwv_dr_dawi_mace               = "cwv_dr_dawi_mace_skins",
			cwv_dr_dawi_mace_shield        = "cwv_dr_dawi_mace_shield_skins",
			cwv_dr_dawi_dual_maces         = "cwv_dr_dawi_dual_maces_skins",
			cwv_es_imperial_crowbill       = "cwv_es_imperial_crowbill_skins",
			cwv_dr_dawi_crowbill           = "cwv_dr_dawi_crowbill_skins",
			cwv_es_sword_and_mace          = "cwv_es_sword_and_mace_skins",
			cwv_es_warpriest_hammer        = "cwv_es_warpriest_hammer_skins",
			cwv_es_dual_warpriest_hammers  = "cwv_es_dual_warpriest_hammers_skins",
			cwv_es_warpriest_hammer_shield = "cwv_es_warpriest_hammer_shield_skins",
			cwv_es_priest_greathammer      = "cwv_es_priest_greathammer_skins",
			cwv_es_maul                    = "cwv_es_maul_skins",
			cwv_es_greataxe                = "cwv_es_greataxe_skins",
			cwv_es_rapier                  = "cwv_es_rapier_skins",
			cwv_es_outrider_grenade_launcher = "cwv_es_outrider_grenade_launcher_skins",
			cwv_es_musket                    = "cwv_es_musket_skins",
			cwv_es_musket_old                = "cwv_es_musket_old_skins",
		}

		local seeded = {}
		for item_type, table_name in pairs(_seed_targets) do
			seeded[table_name] = _empty_skin_tiers()
			for _, def in ipairs(_variant_definitions) do
				if def.item_type == item_type and not def.cwv_retired and not def.no_skin then
					local skin_key = def.item_key .. "_skin"
					local rarity = def.skin_rarity or def.rarity or "exotic"
					local tier = seeded[table_name][rarity]
					if tier then
						tier[#tier + 1] = skin_key
					end
				end
			end
			WeaponSkins.skin_combinations[table_name] = seeded[table_name]
			mod:info("Registered %s skin_combination_table", table_name)
		end
	end

	_register_cwv_skin_combinations()

	do
		local outrider
		for _, def in ipairs(_variant_definitions) do
			if def.item_key == "cwv_es_outrider_grenade_launcher" then
				outrider = def
				break
			end
		end
		if outrider then
			printf("[cwv:762] Outrider visual owner: unit=%s skin=%s",
				tostring(outrider.right_hand_unit),
				"cwv_es_outrider_grenade_launcher_skin")
		end
	end

	-- #620 retirement bridge: the three authored Imperial/Black Guard/Helmgart
	-- looks are now ordinary native-Greatsword illusions. Keep their stable skin
	-- keys for existing saves, but expose them through exactly one canonical
	-- picker. The old cwv owner pool remains only for pre-migration restore.
	do
		local combo = WeaponSkins and WeaponSkins.skin_combinations
			and WeaponSkins.skin_combinations.es_2h_sword_skins
		if combo then
			for _, def in ipairs(_variant_definitions) do
				if def.style_target_item == "es_2h_sword" then
					local skin_key = def.item_key .. "_skin"
					local rarity = def.skin_rarity or def.rarity or "exotic"
					local tier = combo[rarity]
					if tier then
						local present = false
						for _, existing in ipairs(tier) do
							if existing == skin_key then present = true; break end
						end
						if not present then tier[#tier + 1] = skin_key end
					end
				end
			end
		end
	end

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

		-- Vanilla 2h-sword looks retained under their stable cwv_il_* illusion
		-- keys. #620 reroutes their canonical matching owner and target pool to
		-- native es_2h_sword during registration; the selected Combat Style owns
		-- moveset/stats independently of the illusion. Initial display_name /
		-- description fall through to the source vanilla skin's localization keys.
		-- Kruber greatsword (es_2h_sword) skins:
		{ skin_key = "cwv_il_es_01",          matching_weapon = "es_bastard_sword", source_skin = "es_2h_sword_skin_01",          target_combo = "cwv_imperial_longsword_skins", can_wield = _es_careers },
		{ skin_key = "cwv_il_es_02",          matching_weapon = "es_bastard_sword", source_skin = "es_2h_sword_skin_02",          target_combo = "cwv_imperial_longsword_skins", can_wield = _es_careers },
		{ skin_key = "cwv_il_es_02_runed_01", matching_weapon = "es_bastard_sword", source_skin = "es_2h_sword_skin_02_runed_01", target_combo = "cwv_imperial_longsword_skins", can_wield = _es_careers },
		{ skin_key = "cwv_il_es_03",          matching_weapon = "es_bastard_sword", source_skin = "es_2h_sword_skin_03",          target_combo = "cwv_imperial_longsword_skins", can_wield = _es_careers },
		-- Curated-variant mesh assignments (must NOT collide with vanilla clones):
		--   Imperial Longsword  → wpn_empire_2h_sword_04_t1 (= es_2h_sword_skin_05)
		--   Helmgart Watchsword → wpn_greatsword (= es_2h_sword_skin_06)
		--   Black Guard Blade   → wpn_empire_2h_sword_03_t2 (= es_2h_sword_skin_04 — currently shares mesh with Nordland; user knows, will resolve elsewhere)
		-- Drop vanilla clones that duplicate a curated variant by mesh path:
		-- cwv_il_es_04 / cwv_il_es_05 / cwv_il_es_06 (the latter shares mesh with
		-- es_2h_sword_skin_06's wpn_greatsword — kept dropped as a conservative
		-- placeholder until user-directed). Runed variants are always kept since
		-- their rune detailing reads as visually distinct from the bare mesh.
		{ skin_key = "cwv_il_es_04_runed_01", matching_weapon = "es_bastard_sword", source_skin = "es_2h_sword_skin_04_runed_01", target_combo = "cwv_imperial_longsword_skins", can_wield = _es_careers },
		{ skin_key = "cwv_il_es_04_runed_02", matching_weapon = "es_bastard_sword", source_skin = "es_2h_sword_skin_04_runed_02", target_combo = "cwv_imperial_longsword_skins", can_wield = _es_careers },
		-- Saltzpyre greatsword (wh_2h_sword) skins:
		{ skin_key = "cwv_il_wh_01",          matching_weapon = "es_bastard_sword", source_skin = "wh_2h_sword_skin_01",          target_combo = "cwv_imperial_longsword_skins", can_wield = _es_careers },
		{ skin_key = "cwv_il_wh_02",          matching_weapon = "es_bastard_sword", source_skin = "wh_2h_sword_skin_02",          target_combo = "cwv_imperial_longsword_skins", can_wield = _es_careers },
		{ skin_key = "cwv_il_wh_02_runed_01", matching_weapon = "es_bastard_sword", source_skin = "wh_2h_sword_skin_02_runed_01", target_combo = "cwv_imperial_longsword_skins", can_wield = _es_careers },
		{ skin_key = "cwv_il_wh_03",          matching_weapon = "es_bastard_sword", source_skin = "wh_2h_sword_skin_03",          target_combo = "cwv_imperial_longsword_skins", can_wield = _es_careers },
		{ skin_key = "cwv_il_wh_04",          matching_weapon = "es_bastard_sword", source_skin = "wh_2h_sword_skin_04",          target_combo = "cwv_imperial_longsword_skins", can_wield = _es_careers },
		{ skin_key = "cwv_il_wh_05",          matching_weapon = "es_bastard_sword", source_skin = "wh_2h_sword_skin_05",          target_combo = "cwv_imperial_longsword_skins", can_wield = _es_careers },
		{ skin_key = "cwv_il_wh_05_runed_01", matching_weapon = "es_bastard_sword", source_skin = "wh_2h_sword_skin_05_runed_01", target_combo = "cwv_imperial_longsword_skins", can_wield = _es_careers },
		{ skin_key = "cwv_il_wh_05_runed_02", matching_weapon = "es_bastard_sword", source_skin = "wh_2h_sword_skin_05_runed_02", target_combo = "cwv_imperial_longsword_skins", can_wield = _es_careers },

		-- Kruber greathammer (es_2h_hammer) skins as illusions on the curated
		-- `cwv_es_warpriest_hammer` variant — give the rescaled 2H mesh as a
		-- cosmetic option for the new 1H priest-hammer Kruber clone. Sources used:
		-- skin_01, _02, _03, _04 (+_runed_01, _runed_02), _06 (+_runed_01) — 8
		-- entries. Single-hand variant, so no off-hand override needed.
		-- `matching_weapon = "wh_1h_hammer"` so vanilla `_apply_skin_to_item` finds
		-- a real template (`one_handed_hammer_priest_template`); `target_combo`
		-- routes the skin into the variant's curated picker.
		-- Note: 2H model in a 1H slot will read oversized in 3P — by design.
		-- HISTORICAL: in v0.1.151 these 8 sources were registered as 24 entries
		-- across `es_1h_mace`, `es_mace_shield`, and `es_dual_wield_hammer_sword`
		-- (with off-hand overrides to preserve the shield / sword). v0.1.154 moved
		-- them onto the new dedicated variant per user request.
		{ skin_key = "cwv_es_warpriest_hammer_2h_hammer_01",          matching_weapon = "wh_1h_hammer", source_skin = "es_2h_hammer_skin_01",          target_combo = "cwv_es_warpriest_hammer_skins", right_hand_scale = { 0.85, 0.85, 0.675 }, right_hand_offset = { 0, 0, -0.275 }, can_wield = _es_careers },
		{ skin_key = "cwv_es_warpriest_hammer_2h_hammer_02",          matching_weapon = "wh_1h_hammer", source_skin = "es_2h_hammer_skin_02",          target_combo = "cwv_es_warpriest_hammer_skins", right_hand_scale = { 0.85, 0.85, 0.675 }, right_hand_offset = { 0, 0, -0.275 }, can_wield = _es_careers },
		{ skin_key = "cwv_es_warpriest_hammer_2h_hammer_03",          matching_weapon = "wh_1h_hammer", source_skin = "es_2h_hammer_skin_03",          target_combo = "cwv_es_warpriest_hammer_skins", right_hand_scale = { 0.85, 0.85, 0.675 }, right_hand_offset = { 0, 0, -0.275 }, can_wield = _es_careers },
		{ skin_key = "cwv_es_warpriest_hammer_2h_hammer_04",          matching_weapon = "wh_1h_hammer", source_skin = "es_2h_hammer_skin_04",          target_combo = "cwv_es_warpriest_hammer_skins", right_hand_scale = { 0.85, 0.85, 0.675 }, right_hand_offset = { 0, 0, -0.275 }, can_wield = _es_careers },
		{ skin_key = "cwv_es_warpriest_hammer_2h_hammer_04_runed_01", matching_weapon = "wh_1h_hammer", source_skin = "es_2h_hammer_skin_04_runed_01", target_combo = "cwv_es_warpriest_hammer_skins", right_hand_scale = { 0.85, 0.85, 0.675 }, right_hand_offset = { 0, 0, -0.275 }, can_wield = _es_careers },
		{ skin_key = "cwv_es_warpriest_hammer_2h_hammer_04_runed_02", matching_weapon = "wh_1h_hammer", source_skin = "es_2h_hammer_skin_04_runed_02", target_combo = "cwv_es_warpriest_hammer_skins", right_hand_scale = { 0.85, 0.85, 0.675 }, right_hand_offset = { 0, 0, -0.275 }, can_wield = _es_careers },
		{ skin_key = "cwv_es_warpriest_hammer_2h_hammer_06",          matching_weapon = "wh_1h_hammer", source_skin = "es_2h_hammer_skin_06",          target_combo = "cwv_es_warpriest_hammer_skins", right_hand_scale = { 0.85, 0.85, 0.675 }, right_hand_offset = { 0, 0, -0.275 }, can_wield = _es_careers },
		{ skin_key = "cwv_es_warpriest_hammer_2h_hammer_06_runed_01", matching_weapon = "wh_1h_hammer", source_skin = "es_2h_hammer_skin_06_runed_01", target_combo = "cwv_es_warpriest_hammer_skins", right_hand_scale = { 0.85, 0.85, 0.675 }, right_hand_offset = { 0, 0, -0.275 }, can_wield = _es_careers },

		-- Same 8 greathammer sources mirrored onto cwv_es_dual_warpriest_hammers
		-- (dual Skullsplitters). `mirror_to_left = true` mirrors the source's
		-- right_hand_unit into left_hand_unit so each hand gets the same
		-- greathammer mesh. `display_unit_override = display_dual_hammers`
		-- forces the dual-attach rig (source's display_2h_swords single-rig
		-- would crash on left attach — see J_LEFTWEAPONATTACH_INVESTIGATION.md).
		-- Scale and offset applied to both hands; matching_weapon = wh_dual_hammer
		-- so vanilla _apply_skin_to_item resolves to dual_wield_hammers_priest_template.
		{ skin_key = "cwv_es_dual_warpriest_hammers_2h_hammer_01",          matching_weapon = "wh_dual_hammer", source_skin = "es_2h_hammer_skin_01",          target_combo = "cwv_es_dual_warpriest_hammers_skins", mirror_to_left = true, display_unit_override = "units/weapons/weapon_display/display_dual_hammers", right_hand_scale = { 0.85, 0.85, 0.675 }, left_hand_scale = { 0.85, 0.85, 0.675 }, right_hand_offset_1p = { 0, 0, -0.1 }, right_hand_offset_3p = { 0, 0, -0.35 }, left_hand_offset_1p = { 0, 0, -0.1 }, left_hand_offset_3p = { 0, 0, -0.35 }, can_wield = _es_careers },
		{ skin_key = "cwv_es_dual_warpriest_hammers_2h_hammer_02",          matching_weapon = "wh_dual_hammer", source_skin = "es_2h_hammer_skin_02",          target_combo = "cwv_es_dual_warpriest_hammers_skins", mirror_to_left = true, display_unit_override = "units/weapons/weapon_display/display_dual_hammers", right_hand_scale = { 0.85, 0.85, 0.675 }, left_hand_scale = { 0.85, 0.85, 0.675 }, right_hand_offset_1p = { 0, 0, -0.1 }, right_hand_offset_3p = { 0, 0, -0.35 }, left_hand_offset_1p = { 0, 0, -0.1 }, left_hand_offset_3p = { 0, 0, -0.35 }, can_wield = _es_careers },
		{ skin_key = "cwv_es_dual_warpriest_hammers_2h_hammer_03",          matching_weapon = "wh_dual_hammer", source_skin = "es_2h_hammer_skin_03",          target_combo = "cwv_es_dual_warpriest_hammers_skins", mirror_to_left = true, display_unit_override = "units/weapons/weapon_display/display_dual_hammers", right_hand_scale = { 0.85, 0.85, 0.675 }, left_hand_scale = { 0.85, 0.85, 0.675 }, right_hand_offset_1p = { 0, 0, -0.1 }, right_hand_offset_3p = { 0, 0, -0.35 }, left_hand_offset_1p = { 0, 0, -0.1 }, left_hand_offset_3p = { 0, 0, -0.35 }, can_wield = _es_careers },
		{ skin_key = "cwv_es_dual_warpriest_hammers_2h_hammer_04",          matching_weapon = "wh_dual_hammer", source_skin = "es_2h_hammer_skin_04",          target_combo = "cwv_es_dual_warpriest_hammers_skins", mirror_to_left = true, display_unit_override = "units/weapons/weapon_display/display_dual_hammers", right_hand_scale = { 0.85, 0.85, 0.675 }, left_hand_scale = { 0.85, 0.85, 0.675 }, right_hand_offset_1p = { 0, 0, -0.1 }, right_hand_offset_3p = { 0, 0, -0.35 }, left_hand_offset_1p = { 0, 0, -0.1 }, left_hand_offset_3p = { 0, 0, -0.35 }, can_wield = _es_careers },
		{ skin_key = "cwv_es_dual_warpriest_hammers_2h_hammer_04_runed_01", matching_weapon = "wh_dual_hammer", source_skin = "es_2h_hammer_skin_04_runed_01", target_combo = "cwv_es_dual_warpriest_hammers_skins", mirror_to_left = true, display_unit_override = "units/weapons/weapon_display/display_dual_hammers", right_hand_scale = { 0.85, 0.85, 0.675 }, left_hand_scale = { 0.85, 0.85, 0.675 }, right_hand_offset_1p = { 0, 0, -0.1 }, right_hand_offset_3p = { 0, 0, -0.35 }, left_hand_offset_1p = { 0, 0, -0.1 }, left_hand_offset_3p = { 0, 0, -0.35 }, can_wield = _es_careers },
		{ skin_key = "cwv_es_dual_warpriest_hammers_2h_hammer_04_runed_02", matching_weapon = "wh_dual_hammer", source_skin = "es_2h_hammer_skin_04_runed_02", target_combo = "cwv_es_dual_warpriest_hammers_skins", mirror_to_left = true, display_unit_override = "units/weapons/weapon_display/display_dual_hammers", right_hand_scale = { 0.85, 0.85, 0.675 }, left_hand_scale = { 0.85, 0.85, 0.675 }, right_hand_offset_1p = { 0, 0, -0.1 }, right_hand_offset_3p = { 0, 0, -0.35 }, left_hand_offset_1p = { 0, 0, -0.1 }, left_hand_offset_3p = { 0, 0, -0.35 }, can_wield = _es_careers },
		{ skin_key = "cwv_es_dual_warpriest_hammers_2h_hammer_06",          matching_weapon = "wh_dual_hammer", source_skin = "es_2h_hammer_skin_06",          target_combo = "cwv_es_dual_warpriest_hammers_skins", mirror_to_left = true, display_unit_override = "units/weapons/weapon_display/display_dual_hammers", right_hand_scale = { 0.85, 0.85, 0.675 }, left_hand_scale = { 0.85, 0.85, 0.675 }, right_hand_offset_1p = { 0, 0, -0.1 }, right_hand_offset_3p = { 0, 0, -0.35 }, left_hand_offset_1p = { 0, 0, -0.1 }, left_hand_offset_3p = { 0, 0, -0.35 }, can_wield = _es_careers },
		{ skin_key = "cwv_es_dual_warpriest_hammers_2h_hammer_06_runed_01", matching_weapon = "wh_dual_hammer", source_skin = "es_2h_hammer_skin_06_runed_01", target_combo = "cwv_es_dual_warpriest_hammers_skins", mirror_to_left = true, display_unit_override = "units/weapons/weapon_display/display_dual_hammers", right_hand_scale = { 0.85, 0.85, 0.675 }, left_hand_scale = { 0.85, 0.85, 0.675 }, right_hand_offset_1p = { 0, 0, -0.1 }, right_hand_offset_3p = { 0, 0, -0.35 }, left_hand_offset_1p = { 0, 0, -0.1 }, left_hand_offset_3p = { 0, 0, -0.35 }, can_wield = _es_careers },

		-- Same 8 greathammer sources on cwv_es_warpriest_hammer_shield (Skullsplitter
		-- and Shield). Right hand = source greathammer mesh; left hand = Empire shield
		-- (preserved via override since the source skins have no left_hand_unit set).
		-- `display_unit_override = display_shield_hammer` matches the variant's
		-- forced rig and the vanilla wh_hammer_shield template default.
		{ skin_key = "cwv_es_warpriest_hammer_shield_2h_hammer_01",          matching_weapon = "wh_hammer_shield", source_skin = "es_2h_hammer_skin_01",          target_combo = "cwv_es_warpriest_hammer_shield_skins", left_hand_unit_override = "units/weapons/player/wpn_empire_shield_02/wpn_emp_shield_02", display_unit_override = "units/weapons/weapon_display/display_shield_hammer", right_hand_scale = { 0.85, 0.85, 0.675 }, right_hand_offset = { 0, 0, -0.275 }, can_wield = _es_careers },
		{ skin_key = "cwv_es_warpriest_hammer_shield_2h_hammer_02",          matching_weapon = "wh_hammer_shield", source_skin = "es_2h_hammer_skin_02",          target_combo = "cwv_es_warpriest_hammer_shield_skins", left_hand_unit_override = "units/weapons/player/wpn_empire_shield_02/wpn_emp_shield_02", display_unit_override = "units/weapons/weapon_display/display_shield_hammer", right_hand_scale = { 0.85, 0.85, 0.675 }, right_hand_offset = { 0, 0, -0.275 }, can_wield = _es_careers },
		{ skin_key = "cwv_es_warpriest_hammer_shield_2h_hammer_03",          matching_weapon = "wh_hammer_shield", source_skin = "es_2h_hammer_skin_03",          target_combo = "cwv_es_warpriest_hammer_shield_skins", left_hand_unit_override = "units/weapons/player/wpn_empire_shield_02/wpn_emp_shield_02", display_unit_override = "units/weapons/weapon_display/display_shield_hammer", right_hand_scale = { 0.85, 0.85, 0.675 }, right_hand_offset = { 0, 0, -0.275 }, can_wield = _es_careers },
		{ skin_key = "cwv_es_warpriest_hammer_shield_2h_hammer_04",          matching_weapon = "wh_hammer_shield", source_skin = "es_2h_hammer_skin_04",          target_combo = "cwv_es_warpriest_hammer_shield_skins", left_hand_unit_override = "units/weapons/player/wpn_empire_shield_02/wpn_emp_shield_02", display_unit_override = "units/weapons/weapon_display/display_shield_hammer", right_hand_scale = { 0.85, 0.85, 0.675 }, right_hand_offset = { 0, 0, -0.275 }, can_wield = _es_careers },
		{ skin_key = "cwv_es_warpriest_hammer_shield_2h_hammer_04_runed_01", matching_weapon = "wh_hammer_shield", source_skin = "es_2h_hammer_skin_04_runed_01", target_combo = "cwv_es_warpriest_hammer_shield_skins", left_hand_unit_override = "units/weapons/player/wpn_empire_shield_02/wpn_emp_shield_02", display_unit_override = "units/weapons/weapon_display/display_shield_hammer", right_hand_scale = { 0.85, 0.85, 0.675 }, right_hand_offset = { 0, 0, -0.275 }, can_wield = _es_careers },
		{ skin_key = "cwv_es_warpriest_hammer_shield_2h_hammer_04_runed_02", matching_weapon = "wh_hammer_shield", source_skin = "es_2h_hammer_skin_04_runed_02", target_combo = "cwv_es_warpriest_hammer_shield_skins", left_hand_unit_override = "units/weapons/player/wpn_empire_shield_02/wpn_emp_shield_02", display_unit_override = "units/weapons/weapon_display/display_shield_hammer", right_hand_scale = { 0.85, 0.85, 0.675 }, right_hand_offset = { 0, 0, -0.275 }, can_wield = _es_careers },
		{ skin_key = "cwv_es_warpriest_hammer_shield_2h_hammer_06",          matching_weapon = "wh_hammer_shield", source_skin = "es_2h_hammer_skin_06",          target_combo = "cwv_es_warpriest_hammer_shield_skins", left_hand_unit_override = "units/weapons/player/wpn_empire_shield_02/wpn_emp_shield_02", display_unit_override = "units/weapons/weapon_display/display_shield_hammer", right_hand_scale = { 0.85, 0.85, 0.675 }, right_hand_offset = { 0, 0, -0.275 }, can_wield = _es_careers },
		{ skin_key = "cwv_es_warpriest_hammer_shield_2h_hammer_06_runed_01", matching_weapon = "wh_hammer_shield", source_skin = "es_2h_hammer_skin_06_runed_01", target_combo = "cwv_es_warpriest_hammer_shield_skins", left_hand_unit_override = "units/weapons/player/wpn_empire_shield_02/wpn_emp_shield_02", display_unit_override = "units/weapons/weapon_display/display_shield_hammer", right_hand_scale = { 0.85, 0.85, 0.675 }, right_hand_offset = { 0, 0, -0.275 }, can_wield = _es_careers },

		-- Sigmarite Greathammer (cwv_es_priest_greathammer) — Kruber 2H mesh +
		-- Saltzpyre wh_2h_hammer (Warrior Priest) moveset. The variant has its
		-- own item_type/skin_combination_table so vanilla skins of either source
		-- don't bleed into their native pickers. Both source families are 2H
		-- greathammers of comparable size, so NO scale/offset overrides needed.
		-- matching_weapon = "wh_2h_hammer" so `_apply_skin_to_item` resolves to
		-- two_handed_hammer_priest_template (the variant's actual moveset).
		-- Kruber's es_2h_hammer skins:
		{ skin_key = "cwv_es_priest_es_01",          matching_weapon = "wh_2h_hammer", source_skin = "es_2h_hammer_skin_01",          target_combo = "cwv_es_priest_greathammer_skins", can_wield = _es_careers },
		{ skin_key = "cwv_es_priest_es_02",          matching_weapon = "wh_2h_hammer", source_skin = "es_2h_hammer_skin_02",          target_combo = "cwv_es_priest_greathammer_skins", can_wield = _es_careers },
		{ skin_key = "cwv_es_priest_es_02_magic_01", matching_weapon = "wh_2h_hammer", source_skin = "es_2h_hammer_skin_02_magic_01", target_combo = "cwv_es_priest_greathammer_skins", can_wield = _es_careers },
		{ skin_key = "cwv_es_priest_es_03",          matching_weapon = "wh_2h_hammer", source_skin = "es_2h_hammer_skin_03",          target_combo = "cwv_es_priest_greathammer_skins", can_wield = _es_careers },
		{ skin_key = "cwv_es_priest_es_04",          matching_weapon = "wh_2h_hammer", source_skin = "es_2h_hammer_skin_04",          target_combo = "cwv_es_priest_greathammer_skins", can_wield = _es_careers },
		{ skin_key = "cwv_es_priest_es_04_runed_01", matching_weapon = "wh_2h_hammer", source_skin = "es_2h_hammer_skin_04_runed_01", target_combo = "cwv_es_priest_greathammer_skins", can_wield = _es_careers },
		{ skin_key = "cwv_es_priest_es_04_runed_02", matching_weapon = "wh_2h_hammer", source_skin = "es_2h_hammer_skin_04_runed_02", target_combo = "cwv_es_priest_greathammer_skins", can_wield = _es_careers },
		{ skin_key = "cwv_es_priest_es_06",          matching_weapon = "wh_2h_hammer", source_skin = "es_2h_hammer_skin_06",          target_combo = "cwv_es_priest_greathammer_skins", can_wield = _es_careers },
		{ skin_key = "cwv_es_priest_es_06_runed_01", matching_weapon = "wh_2h_hammer", source_skin = "es_2h_hammer_skin_06_runed_01", target_combo = "cwv_es_priest_greathammer_skins", can_wield = _es_careers },
		-- Saltzpyre's wh_2h_hammer skins (Warrior Priest greathammer):
		{ skin_key = "cwv_es_priest_wh_01",          matching_weapon = "wh_2h_hammer", source_skin = "wh_2h_hammer_skin_01",          target_combo = "cwv_es_priest_greathammer_skins", can_wield = _es_careers },
		{ skin_key = "cwv_es_priest_wh_01_runed_01", matching_weapon = "wh_2h_hammer", source_skin = "wh_2h_hammer_skin_01_runed_01", target_combo = "cwv_es_priest_greathammer_skins", can_wield = _es_careers },
		{ skin_key = "cwv_es_priest_wh_01_runed_02", matching_weapon = "wh_2h_hammer", source_skin = "wh_2h_hammer_skin_01_runed_02", target_combo = "cwv_es_priest_greathammer_skins", can_wield = _es_careers },
		{ skin_key = "cwv_es_priest_wh_02",          matching_weapon = "wh_2h_hammer", source_skin = "wh_2h_hammer_skin_02",          target_combo = "cwv_es_priest_greathammer_skins", can_wield = _es_careers },
		{ skin_key = "cwv_es_priest_wh_02_runed_01", matching_weapon = "wh_2h_hammer", source_skin = "wh_2h_hammer_skin_02_runed_01", target_combo = "cwv_es_priest_greathammer_skins", can_wield = _es_careers },
		{ skin_key = "cwv_es_priest_wh_02_runed_02", matching_weapon = "wh_2h_hammer", source_skin = "wh_2h_hammer_skin_02_runed_02", target_combo = "cwv_es_priest_greathammer_skins", can_wield = _es_careers },
		{ skin_key = "cwv_es_priest_wh_02_runed_05", matching_weapon = "wh_2h_hammer", source_skin = "wh_2h_hammer_skin_02_runed_05", target_combo = "cwv_es_priest_greathammer_skins", can_wield = _es_careers },
		{ skin_key = "cwv_es_priest_wh_02_magic_01", matching_weapon = "wh_2h_hammer", source_skin = "wh_2h_hammer_skin_02_magic_01", target_combo = "cwv_es_priest_greathammer_skins", can_wield = _es_careers },
		{ skin_key = "cwv_es_priest_wh_02_magic_02", matching_weapon = "wh_2h_hammer", source_skin = "wh_2h_hammer_skin_02_magic_02", target_combo = "cwv_es_priest_greathammer_skins", can_wield = _es_careers },
	}

	local _custom_skin_keys = {}
	local _custom_skin_owner_by_combo = {
		cwv_es_warpriest_hammer_skins = "cwv_es_warpriest_hammer",
		cwv_es_dual_warpriest_hammers_skins = "cwv_es_dual_warpriest_hammers",
		cwv_es_warpriest_hammer_shield_skins = "cwv_es_warpriest_hammer_shield",
		cwv_es_priest_greathammer_skins = "cwv_es_priest_greathammer",
	}

	local function _register_custom_illusions()
		if not ItemMasterList or not WeaponSkins then return end

		for _, illusion in ipairs(_custom_illusions) do
			local skin_key = illusion.skin_key
			if _custom_skin_keys[skin_key] then goto continue end
			-- #620: the former Imperial Longsword pool is now an illusion family
			-- on native Greatsword. Keep the stable cwv_il_* keys, but make their
			-- canonical matching owner and picker the native item so migrated UUIDs
			-- retain their exact visuals without leaving a duplicate craft family.
			local retired_longsword_pool = illusion.target_combo == "cwv_imperial_longsword_skins"
			local matching_weapon = retired_longsword_pool and "es_2h_sword" or illusion.matching_weapon
			local skin_owner = retired_longsword_pool and matching_weapon
				or _custom_skin_owner_by_combo[illusion.target_combo] or matching_weapon

			local source = WeaponSkins.skins[illusion.source_skin]
			if not source then
				mod:warning("Source skin '%s' not found in WeaponSkins — skipping %s", illusion.source_skin, skin_key)
				goto continue
			end

			-- Hand-unit overrides: when the source skin's hand units don't match
			-- the matching_weapon's slot shape (e.g. greathammer source has only
			-- right_hand_unit but target is mace+shield which needs left_hand_unit),
			-- the illusion entry can specify explicit overrides. Use case: cross-
			-- type illusions where you want one half of the source's model but
			-- preserve the target's other half (a default shield for mace+shield,
			-- a default sword for mace+sword, etc.).
			--
			-- `mirror_to_left = true` is a convenience flag for identical-mesh
			-- dual-wield targets: sets left_hand_unit = right_hand_unit dynamically
			-- (since the source's right_hand_unit varies per source skin and can't
			-- be hardcoded in a static illusion entry). Mirrors the dual_swords/
			-- dual_axes/dual_maces patterns elsewhere in the mod.
			local right_unit = illusion.right_hand_unit_override or source.right_hand_unit
			local left_unit  = illusion.left_hand_unit_override  or source.left_hand_unit
			if illusion.mirror_to_left then left_unit = right_unit end

			-- `display_unit_override`: force a specific display rig on the cloned
			-- skin entry (vs inheriting from source). Required when the source's
			-- rig doesn't author both attach nodes for the target's slot shape —
			-- e.g. greathammer source uses display_2h_swords (right-only rig),
			-- but our cwv dual / shield targets need display_dual_hammers /
			-- display_shield_hammer respectively. See
			-- `J_LEFTWEAPONATTACH_INVESTIGATION.md` for the rule.
			local effective_display_unit = illusion.display_unit_override or source.display_unit

			local iml_entry = {
				item_type         = "weapon_skin",
				slot_type         = "weapon_skin",
				matching_item_key = matching_weapon,
				cwv_owner_item_type = skin_owner,
				rarity            = source.rarity,
				display_name      = source.display_name,
				description       = source.description,
				display_unit      = effective_display_unit,
				hud_icon          = source.hud_icon,
				inventory_icon    = source.inventory_icon,
				information_text  = "information_weapon_skin",
				right_hand_unit   = right_unit,
				left_hand_unit    = left_unit,
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
				display_unit           = effective_display_unit,
				hud_icon               = source.hud_icon,
				inventory_icon         = source.inventory_icon,
				rarity                 = source.rarity,
				right_hand_unit        = right_unit,
				left_hand_unit         = left_unit,
				template               = source.template,
			}
			if source.material_settings_name then
				ws_entry.material_settings_name = source.material_settings_name
			end
			WeaponSkins.skins[skin_key] = ws_entry

			-- target_combo: explicit override for the skin_combination_table this
			-- illusion gets appended to. Used when the illusion lives on a
			-- different weapon than its `matching_weapon` — e.g. vanilla 2h-sword
			-- skins historically authored for `cwv_imperial_longsword_skins`.
			-- #620 recognizes that legacy target and reroutes it to native
			-- `es_2h_sword_skins`; all other families retain the authored override.
			local target_combo = retired_longsword_pool and "es_2h_sword_skins" or illusion.target_combo
			if not target_combo then
				local weapon_data = ItemMasterList[matching_weapon]
				if weapon_data and weapon_data.skin_combination_table then
					target_combo = weapon_data.skin_combination_table
				end
			end
			if target_combo then
				local combos = WeaponSkins.skin_combinations[target_combo]
				if combos then
					local rarity = source.rarity or "exotic"
					local tier = combos[rarity]
					if tier then
						tier[#tier + 1] = skin_key
					end
				end
			end

			-- REVIEW: NetworkLookup.weapon_skins has an error-throwing __index per
			-- CHANGELOG v0.1.12 — `tbl[#tbl + 1] = ...` and `tbl[skin_key] = ...` set
			-- new keys, which goes through __newindex (not __index) and is fine. But
			-- `tbl[skin_key] = #tbl` reads `#tbl` AFTER the previous assignment, so
			-- the reverse-lookup index points at the just-written entry — correct,
			-- but slightly fragile. Pattern at line 467-471 uses an explicit `idx`
			-- variable; using rawset there matches CHANGELOG guidance. Consider
			-- aligning these two code paths to use the same rawset-with-explicit-idx
			-- form.
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
			mod:info("Registered custom illusion: %s (from %s) -> %s", skin_key, illusion.source_skin, matching_weapon)
			::continue::
		end
	end

	_register_custom_illusions()
-- CWV_SKIN_REGISTRY_PAYLOAD_END_v1

	return {
		custom_illusions = _custom_illusions,
		custom_skin_keys = _custom_skin_keys,
		es_careers = _es_careers,
		wh_careers = _wh_careers,
		kruber_1h_dual_skin_keys = _kruber_1h_dual_skin_keys,
	}
end
