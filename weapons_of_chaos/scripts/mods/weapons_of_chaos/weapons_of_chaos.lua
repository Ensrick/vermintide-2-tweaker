local mod = get_mod("WOC")

local MOD_VERSION = "0.1.6-dev"

mod:info("Weapons of Chaos v%s loading", MOD_VERSION)

-- ============================================================================
-- Weapons of Chaos (WOC)
-- ============================================================================
-- Lets the player characters wield ENEMY weapons and named keep-trophy props.
-- Built the duplicate-weapon way, modeled on character_weapon_variants (CWV):
-- each weapon is a real inventory item cloned from a player base weapon
-- template, with its `right_hand_unit` swapped to a different `.unit` mesh.
--
-- FIRST ITEM: "Blightreaper" — Markus Kruber's one-handed sword
-- (`es_1h_sword` / `one_handed_swords_template_1`), equippable by every career
-- of all five heroes.
--
-- HELD MESH — INTERIM: the Bögenhafen keep-trophy diorama prop
-- (`units/props/inn/hub_trophy/hub_trophy_bogenhafen`) was the intended mesh,
-- but it is NOT runtime-loadable: it has no standalone `.package`, is absent
-- from the boot-loaded `resource_packages/dlcs/bogenhafen` and base
-- `resource_packages/levels/inn` bundles, and is loaded on-demand only by the
-- keep-decoration system. Force-loading its UNIT path via `Managers.package:load`
-- HARD-CRASHED on keep entry (engine `resource_package()` C-fatal, bypasses
-- pcall — repo memory `reference_vt2_package_load_needs_package_not_unit_path`).
-- So the held mesh is temporarily the base Empire sword (`HELD_UNIT`, always
-- resident with the player loadout, real `_3p` sibling). Swap `HELD_UNIT` to the
-- extracted/authored model once it ships as a real loadable unit; the trophy
-- path is recorded below as the extraction target ONLY (never referenced at
-- runtime). No package force-load, no prop spawn anywhere in this file.
-- ============================================================================

-- Two-helper debug-logging policy (PROJECT_STANDARDS.md § 3.6).
-- Routed through VMF logging channels; visible via VMF output_mode_debug / output_mode_warning.
-- `_dbg` = confirmation / expected behavior — mod:debug channel.
-- `_dbg_alert` = unexpected / wrong / mismatch — mod:warning channel.
local function _dbg(fmt, ...)
	mod:debug("[WOC:dbg] " .. fmt, ...)
end

local function _dbg_alert(fmt, ...)
	mod:warning("[WOC:dbg] " .. fmt, ...)
end

-- ============================================================
-- Constants
-- ============================================================

local ITEM_KEY    = "woc_blightreaper"
local BACKEND_ID  = ITEM_KEY .. "_001"
local BASE_WEAPON = "es_1h_sword"                       -- Kruber 1H sword (clone source)
local TEMPLATE    = "one_handed_swords_template_1"      -- 1H sword moveset / hit detection

-- Held mesh (INTERIM). Base es_1h_sword right_hand_unit
-- (item_master_list_exported.lua:6548) — always resident with the player
-- loadout and has a real `<unit>_3p` sibling, so vanilla 1P/3P derivation just
-- works (no force-load, no special-case spawn).
local HELD_UNIT = "units/weapons/player/wpn_emp_sword_02_t1/wpn_emp_sword_02_t1"

-- FUTURE EXTRACTION TARGET (documentation only — do NOT reference at runtime):
--   units/props/inn/hub_trophy/hub_trophy_bogenhafen
-- The Bögenhafen keep-trophy diorama prop. Not runtime-loadable today; when a
-- real held model is extracted/authored as a loadable unit, point HELD_UNIT at
-- it (and add a `<unit>_3p` sibling, or handle the 3P derivation then).

-- can_wield = every career of all five heroes. Base careers sourced from
-- scripts/settings/profiles/career_settings.lua; the five DLC careers verified
-- present in scripts/settings/ (es_questingknight / dr_engineer / we_thornsister
-- / wh_priest / bw_necromancer). The game gates equipping by DLC ownership
-- separately, so we list them all (CWV strips required_dlc the same way).
local _careers = {
	-- Markus Kruber (Empire Soldier)
	"es_mercenary", "es_huntsman", "es_knight", "es_questingknight",
	-- Bardin Goreksson (Dwarf Ranger)
	"dr_ironbreaker", "dr_ranger", "dr_slayer", "dr_engineer",
	-- Kerillian (Wood Elf)
	"we_waywatcher", "we_maidenguard", "we_shade", "we_thornsister",
	-- Victor Saltzpyre (Witch Hunter)
	"wh_zealot", "wh_bountyhunter", "wh_captain", "wh_priest",
	-- Sienna Fuegonasus (Bright Wizard)
	"bw_adept", "bw_scholar", "bw_unchained", "bw_necromancer",
}

-- ============================================================
-- Display names (global Localize is NOT fed by mod _localization.lua;
-- the inventory UI Localizes display_name/description/item_type keys).
-- ============================================================

local _display_names = {
	[ITEM_KEY .. "_name"]        = mod:localize("woc_blightreaper_name"),
	[ITEM_KEY .. "_description"] = mod:localize("woc_blightreaper_description"),
	[ITEM_KEY]                   = mod:localize("woc_blightreaper_name"),  -- item_type label
}

mod:hook(_G, "Localize", function(func, key)
	if _display_names[key] then
		return _display_names[key]
	end
	return func(key)
end)

-- ============================================================
-- Item entry builder (minimal CWV `_build_entry` subset)
-- ============================================================

local function _build_entry(base, backend_id)
	local entry = table.clone(base, true)

	-- Cross-mod marker (parity with CWV's `cwv_variant`). The clone keeps the
	-- inherited `entry.name` ("es_1h_sword") on purpose — clobbering it breaks
	-- the vanilla equip fallback `ItemMasterList[item.name]` (CWV clone-name
	-- lesson, feedback_cwv_clone_name_clobber).
	entry.woc_variant = true

	entry.display_name    = ITEM_KEY .. "_name"
	entry.description     = ITEM_KEY .. "_description"
	entry.right_hand_unit = HELD_UNIT
	entry.left_hand_unit  = nil                 -- 1H sword: no off-hand / shield
	entry.can_wield       = _careers
	entry.template        = TEMPLATE
	entry.item_type       = ITEM_KEY            -- own type so Localize(item_type) -> "Blightreaper"

	-- hud_icon / inventory_icon are inherited from the es_1h_sword clone
	-- (reused on purpose — no new icon atlas, no missing-material crash).

	-- Drop the DLC gate: this is a new mod item reusing base-package meshes;
	-- per-career DLC ownership is enforced by the game's own equip check.
	entry.required_dlc = nil

	entry.rarity = "default"
	entry.mod_data = {
		backend_id     = backend_id,
		ItemInstanceId = backend_id,
		CustomData = {
			traits      = "[]",
			power_level = "300",
			properties  = "{}",
			rarity      = "default",
		},
		rarity      = "default",
		traits      = {},
		power_level = 300,
		properties  = {},
	}
	-- No skin pre-applied: the item renders from entry.right_hand_unit. Default
	-- rarity keeps it forge-eligible and treated as unlocked.

	return entry
end

-- ============================================================
-- Registration (deferred until the backend is ready)
-- ============================================================

local _registered = false

local function _register_blightreaper()
	if _registered then
		return
	end
	if not mod:get("enable_blightreaper") then
		_dbg("Blightreaper disabled via setting; skipping registration")
		return
	end

	local mil = get_mod("MoreItemsLibrary")
	if not mil then
		mod:warning("MoreItemsLibrary not found — Blightreaper cannot be registered (load MIL above WOC)")
		return
	end

	local base = rawget(ItemMasterList, BASE_WEAPON)
	if not base then
		mod:warning("Base weapon '%s' not found in ItemMasterList — Blightreaper cannot be registered", BASE_WEAPON)
		return
	end

	local entry = _build_entry(base, BACKEND_ID)
	mil:add_mod_items_to_local_backend({ entry }, "weapons_of_chaos")

	-- Mirror into ItemMasterList so vanilla equip/preview paths resolve it
	-- (HeroPreviewer.equip_item does `ItemMasterList[item_name]`). rawget
	-- bypasses the crashify __index metamethod on the missing key.
	if ItemMasterList and not rawget(ItemMasterList, ITEM_KEY) then
		ItemMasterList[ITEM_KEY] = entry
	end

	-- Inject into NetworkLookup.item_names so item-name RPCs serialize. rawset:
	-- the table has an error-throwing __index.
	if NetworkLookup and NetworkLookup.item_names and not rawget(NetworkLookup.item_names, ITEM_KEY) then
		local idx = #NetworkLookup.item_names + 1
		rawset(NetworkLookup.item_names, idx, ITEM_KEY)
		rawset(NetworkLookup.item_names, ITEM_KEY, idx)
	end

	_registered = true
	mod:info("[WOC] registered Blightreaper (%s) as backend item %s", ITEM_KEY, BACKEND_ID)
end

-- StateInGameRunning.on_enter fires on entering the keep AND each mission load;
-- the `_registered` guard makes re-fires a no-op (CWV registration-timing pattern).
mod:hook_safe("StateInGameRunning", "on_enter", function()
	_register_blightreaper()
end)

-- ============================================================
-- Wire-safety: never crash a non-WOC peer (issue 278 / issue 371)
-- ============================================================
-- WOC injects ITEM_KEY into NetworkLookup.item_names (a per-peer index-append, :191).
-- Equipping the Blightreaper fires LoadoutUtils.sync_loadout_slot -> the RPC encodes
-- item_id = NetworkLookup.item_names[item.key] onto rpc_sync_loadout_slot (both
-- directions + hot_join_sync). A peer WITHOUT WOC lacks that appended index and
-- cold-decodes it at loadout_utils.lua:72 -> the strict __index metamethod fatals
-- (network_lookup.lua:2362) -> every non-WOC peer CTDs. WOC cloned CWV's item
-- registration but not its net-safe hook (issue 422).
--
-- Fix: substitute a shadow item keyed to the vanilla BASE_WEAPON (a boot-stable index
-- every peer has) before the RPC encodes. Local state is untouched (the shadow lives
-- only for this call); remote loadout panels show the base weapon, consistent with what
-- the husk already renders (the clone keeps entry.name = BASE_WEAPON). Byte-identical to
-- CWV's issue-278 fix (character_weapon_variants.lua:10166). No skin/rarity axis to fix:
-- WOC applies no skin (weapon_skin_id "n/a") and rarity = "default" (a vanilla index).
--
-- Prefix-match "woc_" so EVERY present/future WOC item is crash-safe. All current items
-- clone BASE_WEAPON; if a future item clones a different base, resolve the base per-key
-- (mirror CWV's _find_def) so the wire shows the right weapon -- but crash-safety holds
-- regardless, since BASE_WEAPON is a universal vanilla index. LoadoutUtils is a plain
-- table -> table-form hook with a nil guard. Sole WOC hook on (LoadoutUtils,
-- sync_loadout_slot); other mods hook it from their own registrations (VMF chains fine).
if rawget(_G, "LoadoutUtils") and LoadoutUtils.sync_loadout_slot then
	mod:hook(LoadoutUtils, "sync_loadout_slot", function(func, player, slot_name, item, sync_to_specific_peer_id)
		local key = item and item.key
		if type(key) == "string" and key:sub(1, 4) == "woc_"
				and rawget(ItemMasterList, BASE_WEAPON)
				and NetworkLookup and NetworkLookup.item_names
				and rawget(NetworkLookup.item_names, BASE_WEAPON) then
			local shadow = {}
			for k, v in pairs(item) do shadow[k] = v end
			shadow.key = BASE_WEAPON
			shadow.ItemId = BASE_WEAPON
			printf("[WOC:278] sync_loadout_slot net-safe: %s -> %s (slot=%s)",
				tostring(key), BASE_WEAPON, tostring(slot_name))
			return func(player, slot_name, shadow, sync_to_specific_peer_id)
		end
		return func(player, slot_name, item, sync_to_specific_peer_id)
	end)
end

mod:info("[WOC] enabled v%s (Blightreaper)", MOD_VERSION)
