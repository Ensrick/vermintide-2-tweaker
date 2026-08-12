-- Three-phase installation preserves the original hook/module ordering:
-- localization+unlocks, skin unlock hook, item-registration consumers.
local function install(mod, ctx)
	local _om = assert(ctx.om, "cwv bootstrap owner requires om")
	local _variant_definitions = assert(ctx.variant_definitions,
		"cwv bootstrap owner requires variant_definitions")

	-- ============================================================
	-- Optional mod detection
	-- ============================================================

	local function _detect_companion_mods()
		local wt = get_mod("wt")
		local cos = get_mod("cosmetics_tweaker")  -- #70: was misnamed `ct` (ct is the chaos_wastes id)

		if wt then
			mod:info("weapon_tweaker detected")
		end
		if cos then
			mod:info("cosmetics_tweaker detected")
		end

		return wt, cos
	end

	-- ============================================================
	-- Localization
	-- ============================================================

	local _display_names = {}
	local _item_text = mod:dofile("scripts/mods/character_weapon_variants/_cwv_item_text")

	for _, def in ipairs(_variant_definitions) do
		_display_names[def.item_key .. "_name"] = def.display_name
		_display_names[def.item_key .. "_description"] =
			_item_text.description(def.display_name, def.description)
		if def.skin_display_name then
			_display_names[def.item_key .. "_skin_name"] = def.skin_display_name
		end
		-- item_type → display_name mapping. `_build_entry` sets
		-- `entry.item_type = def.item_type or def.item_key`, so vanilla UI calls
		-- `Localize(item_data.item_type)` always hit one of these keys.
		-- Without this mapping, those calls would fall through to vanilla's
		-- localization for the BASE weapon's item_type (e.g. "bw_dagger" →
		-- "Dagger") because cwv variants inherit `entry.name` / `entry.key` from
		-- the clone — see `feedback_cwv_clone_name_clobber.md`. The explicit
		-- override here ensures the cwv variant always displays its own name in
		-- weapon-type labels, loot drop banners, and the cosmetics inventory
		-- header.
		-- Multiple variants can share def.item_type (e.g. the Imperial Longsword
		-- owner and its illusion-only siblings). The FIRST owning definition is the
		-- canonical weapon-family label. Never let a later curated/skin-only entry
		-- rename the owned weapon in inventory headers (issue #396).
		local effective_item_type = def.item_type or def.item_key
		if _display_names[effective_item_type] == nil then
			_display_names[effective_item_type] = def.display_name
		end
	end

	-- #597 model names are intentionally provisional while the converted axes are
	-- reviewed in-game. Keep them in the same global localization surface used by
	-- generated variant skins so the picker never shows raw manifest keys.
	for _, model in ipairs(_om.greataxe.usable_models()) do
		_display_names[model.key .. "_name"] = model.display_name
		_display_names[model.key .. "_description"] = model.description or "A Greataxe model awaiting final review and naming."
	end
	for _, model in ipairs(_om.crowbill_family.usable_models()) do
		_display_names[model.key .. "_name"] = model.display_name
		_display_names[model.key .. "_description"] = model.description
			or "A Crowbill model awaiting final review and naming."
	end

	-- Pickup HUD popup strings. Vanilla pickup interaction code calls Localize()
	-- on `pickup_settings.hud_description` (interactions.lua:1572 →
	-- interaction_ui.lua:684). VMF's per-mod _localization.lua strings are
	-- exposed via mod:localize(), NOT auto-registered into the global Localize —
	-- so unrecognized keys come back as `<key>` from vanilla Localize. Translate
	-- directly in this hook for any pickup loc key the mod defines.
	local _pickup_hud_strings = {
		cwv_interaction_ammunition_javelin = "Tuskgor Javelin",
	}

	-- audit 2026-06-07 (F15, v0.1.349-dev): prefix helper derives its compare
	-- length from #prefix so the mace+sword rename can't silently die on an
	-- off-by-one again. The prior inline `key:sub(1, 30) ==
	-- "es_dual_wield_hammer_sword_skin"` compared 30 chars against a 31-char
	-- literal -> ALWAYS false -> the rename never fired for any skinned mace+sword.
	-- Centralizing the length on the literal makes the bug structurally impossible.
	local _MACE_SWORD_SKIN_PREFIX = "es_dual_wield_hammer_sword_skin"
	local function _has_prefix(s, prefix)
		return type(s) == "string" and s:sub(1, #prefix) == prefix
	end
	-- Exposed for the /cwv_regression_test prefix-match behavioral check.
	mod._cwv_has_prefix = _has_prefix
	mod._cwv_mace_sword_skin_prefix = _MACE_SWORD_SKIN_PREFIX

	mod:hook(_G, "Localize", function(func, key)
		if _display_names[key] then
			return _display_names[key]
		end
		if _pickup_hud_strings[key] then
			return _pickup_hud_strings[key]
		end
		-- Vanilla mace+sword rename — gated on the user-facing toggle. The
		-- inventory/cosmetics UI uses the APPLIED SKIN's display_name key (not
		-- always the IML weapon's display_name), so we have to catch every
		-- `es_dual_wield_hammer_sword_skin_*_name` variant — skin_01, skin_02,
		-- skin_03, runed variants, magic variants, etc. Without the wildcard,
		-- a player who applied any non-default illusion (skin_02 etc.) would
		-- still see "Mace and Sword" because the displayed key is the skin's,
		-- not the weapon's. Pattern: anything starting with the weapon prefix
		-- and ending in `_name`.
		-- Toggle is read at hook fire so it responds to runtime changes without
		-- a mod reload.
		-- audit 2026-06-07 (F15, v0.1.349-dev): use the #prefix-based helper. The
		-- old `key:sub(1, 30) == "<31-char literal>"` was off-by-one and never
		-- matched, so the mace_sword_tweak rename was silently dead for every
		-- skinned mace+sword variant (skin_01/02/03, runed, magic, etc.).
		if _has_prefix(key, _MACE_SWORD_SKIN_PREFIX)
				and key:sub(-5) == "_name"
				and mod:get("mace_sword_tweak") then
			return "Cudgel and Short Sword"
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
			-- rawget: ItemMasterList __index crashifies on missing keys; defensive against
			-- future _weapon_unlocks entries referencing DLC-gated items the user lacks.
			local item = rawget(ItemMasterList, unlock.item_key)
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


	local function after_skins(custom_skin_keys)
		local _custom_skin_keys = assert(custom_skin_keys,
			"cwv bootstrap owner requires custom_skin_keys")

		mod:hook_safe("BackendInterfaceCraftingPlayfab", "get_unlocked_weapon_skins", function(self)
			local mirror = self._backend_mirror
			if not mirror or not mirror._unlocked_weapon_skins then return end
			for skin_key, _ in pairs(_custom_skin_keys) do
				local skin_item = rawget(ItemMasterList, skin_key)
				local required_dlc = skin_item and skin_item.required_dlc
				local owns_required_dlc = not required_dlc
					or not Managers.unlock
					or Managers.unlock:is_dlc_unlocked(required_dlc)
				if owns_required_dlc then
					mirror._unlocked_weapon_skins[skin_key] = true
				end
			end
		end)

		local function after_registration()
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

			-- Shared override-mesh residency guard (issue #418). Given a base unit path,
			-- return its resident "_3p" override form or nil. Encapsulates the vanilla-
			-- player-mesh prefix + invisible-weapon sentinel + "_3p" suffix + has_loaded
			-- residency check that was inlined (and drifting) across the inventory-preview
			-- swap and the illusion browser. A non-vanilla, sentinel, or non-resident target
			-- returns nil so callers degrade to the base mesh -- never an engine-fatal
			-- World.spawn_unit on a non-resident/custom mesh (issue 403 class). Keyed on the
			-- single _om.HUSK_OVERRIDE_REF constant so producer and consumer can't drift.
			_om._resident_override_3p = function(base_unit)
				if type(base_unit) ~= "string" or base_unit == "" then return nil end
				if base_unit:find("units/weapons/player/", 1, true) ~= 1 then return nil end
				if base_unit:find("wpn_invisible_weapon", 1, true) then return nil end
				local want = base_unit .. "_3p"
				if not (Managers and Managers.package) then return nil end
				local ok, res = pcall(Managers.package.has_loaded, Managers.package, want, _om.HUSK_OVERRIDE_REF)
				if not (ok and res == true) then return nil end
				return want
			end

			-- ============================================================
			-- Shared preview descriptor (issues 237/419/660) — WEAPON_APPEARANCE_STANDARD §4.1
			-- ============================================================
			-- Paths 3/4 (inventory preview + illusion browser) receive the variant's BASE
			-- weapon key and spawn the BASE mesh; the owner/husk paths swap at the data
			-- level (`_build_entry` writes the override units onto the cloned entry) but the
			-- previewers do not, so a cross-character melee variant (e.g. the elf Sword &
			-- Shield, cwv_we_sword_shield) shows its base's Kruber mesh on the character-
			-- preview model. This rewrites the previewer's precomputed `spawn_data`
			-- entry.unit_name to the variant's authored 3P unit BEFORE vanilla spawns it
			-- (weapon_tweaker's preview-swap pattern: mutate the recipe, never
			-- despawn/respawn). unit_name ONLY — cwv melee variants reuse the base
			-- template's node vocabulary (`_build_entry` keeps the base template), so the
			-- node linking is already correct and we never risk an engine-fatal Unit.node
			-- on a swapped mesh. Idempotent: when `BackendUtils.get_item_units` already
			-- forced the override (skinless owner-style resolution), entry.unit_name already
			-- equals the target and the rewrite is a no-op.
			--
			-- Both preview engines now resolve identity and units exactly once here. Their
			-- wrappers only select the engine recipe adapter: MenuWorldPreviewer exposes
			-- right/left flags, while LootItemUnitPreviewer has rebound the recipe to the
			-- vanilla base-unit identity. This retires the duplicated #237/#419 fallback
			-- resolvers that drifted into two separate fixes for the same concern.
			--
			-- SAFETY (#237/#419): the spawn target is gated by `_om._preview_override_3p`:
			-- husk residency resolver first (co-op unchanged); else only a non-sentinel
			-- vanilla `units/weapons/player/` or mod-bundled `units/cwv_` mesh passing the
			-- #478 spawn floor (`_om._husk_unit_spawnable`, incl. the #474 Old Musket donor
			-- gate) swaps; anything else degrades to the base mesh, never an engine-fatal
			-- World.spawn_unit (issue 403 class). Ammo-unit entries are skipped. A
			-- user-selected illusion (non-empty `skin` arg) wins, as in get_item_units.
			_om._cwv_resolve_spawn_descriptor = function(backend_id, item_data, explicit_skin, stored_skin)
			    local cwv_key = _om._cwv_key_for_item(backend_id, item_data)
			    local def = cwv_key and _find_def(cwv_key) or nil
			    if not def then return nil, nil, cwv_key, "variant_missing" end
			    local base = ItemMasterList and rawget(ItemMasterList, def.base_weapon)
			    local descriptor, reason = _om.exact_appearance.resolve_spawn_descriptor({
			        explicit_skin = explicit_skin,
			        stored_skin = stored_skin,
			        backend_id = backend_id,
			        weapon_skins = WeaponSkins and WeaponSkins.skins,
			        variant = def,
			        base = base,
			        skin_from_backend = function(bid)
			            local backend = Managers and Managers.backend
			            local iface = backend and backend:get_interface("items")
			            return iface and iface.get_skin and iface:get_skin(bid)
			        end,
			    })
			    return descriptor, def, cwv_key, reason
			end

			_om._cwv_preview_meshswap_apply = function(item_name, backend_id, skin, info)
			    local stored_skin = type(info) == "table" and info.skin_name or nil
			    local descriptor, def, cwv_key = _om._cwv_resolve_spawn_descriptor(
			        backend_id, nil, skin, stored_skin)
			    if not descriptor then return end
			    local swapped = _om.exact_appearance.apply_spawn_descriptor(
			        descriptor, info and info.spawn_data, _om._preview_override_3p, "hand_flags")
			    if swapped > 0 then
			        printf("[cwv:660] surface=inventory descriptor=%s key=%s bid=%s swapped=%d source=%s R=%s L=%s",
			            tostring(descriptor.fingerprint), tostring(cwv_key), tostring(backend_id), swapped,
			            tostring(descriptor.source), tostring(def.right_hand_unit), tostring(def.left_hand_unit))
			    end
			end
			mod._cwv_preview_meshswap_apply = _om._cwv_preview_meshswap_apply; mod._cwv_resolve_item_key = _om._cwv_key_for_item -- exact provider identity; #237 preview handle

			-- Illusion-browser mesh-swap pre-pass (issue 419) — WEAPON_APPEARANCE_STANDARD
			-- §3 path 4. The browser's data-level resolution is SUPPOSED to cover this:
			-- `LootItemUnitPreviewer._load_item_units` calls `BackendUtils.get_item_units`
			-- (loot_item_unit_previewer.lua:270) and our hook there forces the def's units.
			-- But `_load_item_units` REBINDS item_data to the BASE ItemMasterList entry
			-- first (`item_key = item_data.key or item.key` then `item_data =
			-- ItemMasterList[item_key]`, loot_item_unit_previewer.lua:254-255) — a cwv
			-- clone keeps `key` = base key, so the get_item_units hook receives the BASE
			-- entry and the #482 ladder's `item_data.cwv_key` rung is structurally dead on
			-- this path. A crafted instance with a UUID backend_id (Athanor, issue 482)
			-- then rides the pcall-guarded backend rung ALONE; when that lookup misses,
			-- the browser spawns the base mesh and the transform pass scales the WRONG
			-- mesh (the issue 419 distortion). `self._item` still carries the ORIGINAL
			-- item.data (the stamped clone), so resolving the ladder HERE sees rung 2 and
			-- cannot miss a stamped instance.
			--
			-- Guards mirror `_cwv_preview_meshswap_apply` (issue 237): an applied illusion
			-- wins (skin data already carries the variant units for cwv skins); the spawn
			-- target is gated by `_om._preview_override_3p` (#237/#419: husk resolver, then
			-- the #478/#474 spawn floor) — else degrade to the base mesh, never an
			-- engine-fatal World.spawn_unit (issue 403 class). Hand identity by exact
			-- base-unit-name match ("_3p" already appended by _load_item_units,
			-- loot_item_unit_previewer.lua:286/302): ammo/already-swapped entries don't
			-- match, pass through untouched (idempotent vs get_item_units — no double-handling).
			_om._cwv_browser_meshswap_apply = function(item, spawn_data)
			    if not item or type(spawn_data) ~= "table" then return end
			    local stored_skin = item.data and item.data.mod_data and item.data.mod_data.skin
			    local descriptor, def, cwv_key = _om._cwv_resolve_spawn_descriptor(
			        item.backend_id, item.data, item.skin, stored_skin)
			    if not descriptor then return end
			    local swapped = _om.exact_appearance.apply_spawn_descriptor(
			        descriptor, spawn_data, _om._preview_override_3p, "base_identity")
			    if swapped > 0 then
			        printf("[cwv:660] surface=browser descriptor=%s key=%s bid=%s swapped=%d source=%s R=%s L=%s",
			            tostring(descriptor.fingerprint), tostring(cwv_key), tostring(item.backend_id), swapped,
			            tostring(descriptor.source), tostring(def.right_hand_unit), tostring(def.left_hand_unit))
			    end
			end
			mod._cwv_browser_meshswap_apply = _om._cwv_browser_meshswap_apply  -- exposed for /cwv regression (issue 419)

			-- issue #538: /cwv_give must REFUSE skin_only (illusion-only) variants. A
			-- skin_only def (e.g. cwv_es_longsword_nordland) is deliberately excluded from
			-- _auto_register_all because it exists only to seed a custom skin/illusion entry,
			-- never a real craftable definition. The command is now entirely informational
			-- (#592), while the discriminator preserves the more specific illusion guidance.
			-- Exposed on
			-- _om so the regression suite can assert the guard exists without driving the full
			-- give path (which has echo + registration side effects). io is nil in the retail
			-- sandbox, so a source self-grep check is impossible; this predicate is the seam.
			_om._give_refuses_skin_only = function(def)
				return not not (def and def.skin_only)
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

				-- issue #538: illusion-only variants are never handed out as real items.
				if _om._give_refuses_skin_only(def) then
					mod:echo("%s is an illusion-only variant - use the illusion browser", def.display_name)
					return
				end
				mod:echo("Craft %s through Crafting in Modded", def.display_name)
			end

			-- Animation remapping handled entirely via template, 3P-only:
			-- - anim_event_3p overrides in elven_sword_shield_template (attack anims)
			-- - wield_anim_3p = "to_1h_spear_shield" (wield anim, 3P body)
			-- 1P animations work universally across all characters and are never touched
			-- by this mod — see top-of-file ANIMATION ARCHITECTURE for the rule.


			return {
				find_def = _find_def,
				give_variant = _give_variant,
			}
		end

		return after_registration
	end

	return after_skins
end

return install
