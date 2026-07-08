local mod = get_mod("WOC")

local MOD_VERSION = "0.1.7-dev"

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

-- Applied-marker fingerprint (PROJECT_STANDARDS.md § 3.6 "Applied marker line").
-- Walks the data widget tree, FNV-1a-32 hashes setting=value pairs; the marker
-- line at the bottom of this file surfaces the live config in the console log.
local function _settings_fingerprint()
	local ok, data = pcall(require, "scripts/mods/weapons_of_chaos/weapons_of_chaos_data")
	if not ok or type(data) ~= "table" then return "nodata" end
	local keys = {}
	local function walk(node)
		if type(node) ~= "table" then return end
		if type(node.setting_id) == "string" then keys[#keys + 1] = node.setting_id end
		for _, child in pairs(node) do
			if type(child) == "table" then walk(child) end
		end
	end
	walk(data)
	if #keys == 0 then return "nosettings" end
	table.sort(keys)
	local parts = {}
	for i, k in ipairs(keys) do
		local v = mod:get(k)
		if v == true then       parts[i] = k .. "=1"
		elseif v == false then  parts[i] = k .. "=0"
		elseif v == nil then    parts[i] = k .. "=?"
		else                    parts[i] = k .. "=" .. tostring(v) end
	end
	local s = table.concat(parts, ";")
	-- FNV-1a 32-bit, plain-arithmetic XOR (no bit32 in Lua 5.1 sandbox).
	local h = 2166136261
	for i = 1, #s do
		local byte = string.byte(s, i)
		local xored, place = 0, 1
		local hh, bb = h, byte
		for _ = 1, 32 do
			local hb, bbit = hh % 2, bb % 2
			if hb ~= bbit then xored = xored + place end
			place = place * 2
			hh = (hh - hb) / 2
			bb = (bb - bbit) / 2
		end
		h = (xored * 16777619) % 4294967296
	end
	return string.format("%08x", h)
end

-- Regression self-test scaffold (PROJECT_STANDARDS § 5.1a). Individual checks are
-- registered inline next to the code they cover (search "_rt_register"); run
-- in-game via /woc_regression_test.
local _RT_CHECKS = {}
local function _rt_register(name, fn)
	_RT_CHECKS[#_RT_CHECKS + 1] = { name = name, fn = fn }
end
mod:command("woc_regression_test", "Run WOC regression smoke checks for past bugs", function()
	local pass, fail = 0, 0
	mod:echo("=== WOC regression_test (v%s) ===", MOD_VERSION)
	for _, c in ipairs(_RT_CHECKS) do
		local ok, err = pcall(c.fn)
		if ok and err == nil then
			mod:echo("  PASS: %s", c.name); pass = pass + 1
		else
			mod:echo("  FAIL: %s -- %s", c.name, tostring(err)); fail = fail + 1
		end
	end
	mod:echo("=== %d passed, %d failed ===", pass, fail)
end)

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
-- Returns the item to actually put on the wire for `item`: the item UNCHANGED
-- for a non-WOC key; a shadow keyed to the boot-stable BASE_WEAPON for a "woc_"
-- key; or nil when the base index can't be resolved -- in which case the caller
-- MUST skip the send. A raw woc_ key must never be structurally reachable on the
-- wire (issue 422): if the base guard short-circuits, falling through to send the
-- woc_ key is the exact non-WOC-peer CTD this hook exists to prevent (issue 278).
-- The live item is never mutated (the shadow is a shallow copy).
local function _wire_safe_item(item)
	local key = item and item.key
	if type(key) ~= "string" or key:sub(1, 4) ~= "woc_" then
		return item                                       -- non-WOC: untouched passthrough
	end
	if rawget(ItemMasterList, BASE_WEAPON)
			and NetworkLookup and NetworkLookup.item_names
			and rawget(NetworkLookup.item_names, BASE_WEAPON) then
		local shadow = {}
		for k, v in pairs(item) do shadow[k] = v end
		shadow.key = BASE_WEAPON
		shadow.ItemId = BASE_WEAPON
		return shadow
	end
	return nil                                            -- base unresolvable: caller skips (fail-safe)
end

if rawget(_G, "LoadoutUtils") and LoadoutUtils.sync_loadout_slot then
	mod:hook(LoadoutUtils, "sync_loadout_slot", function(func, player, slot_name, item, sync_to_specific_peer_id)
		local send_item = _wire_safe_item(item)
		if send_item == nil then
			-- Only a woc_ item with an unresolvable base reaches here. Skipping the
			-- sync is the sole crash-safe move (substituting can't help: the base
			-- itself isn't in NetworkLookup, and sending woc_ raw CTDs non-WOC peers).
			-- Mirrors CWV's skip branch (character_weapon_variants.lua:10183-10188).
			printf("[WOC:278] base '%s' unresolvable for woc_ key %s; SKIPPING loadout sync (fail-safe, issue 422)",
				BASE_WEAPON, tostring(item and item.key))
			return
		end
		if send_item ~= item then
			printf("[WOC:278] sync_loadout_slot net-safe: %s -> %s (slot=%s)",
				tostring(item.key), tostring(send_item.key), tostring(slot_name))
		end
		return func(player, slot_name, send_item, sync_to_specific_peer_id)
	end)
end

-- issue 422 / class-31 regression: a woc_ item must never leave a woc_ key on the
-- wire. Registered here because `_wire_safe_item` is a file-local defined just
-- above. Asserts the hook target exists (install precondition) and that a fake
-- woc_ item pushed through the substitution yields no woc_ key/ItemId and does
-- not mutate the live item.
_rt_register("wire_woc_never_leaves_woc_key", function()
	if not (rawget(_G, "LoadoutUtils") and type(LoadoutUtils.sync_loadout_slot) == "function") then
		return "LoadoutUtils.sync_loadout_slot missing -- wire hook cannot install"
	end
	local fake = { key = "woc_test", ItemId = "woc_test", power_level = 300 }
	local out = _wire_safe_item(fake)
	-- out is a base-keyed shadow (base resolvable) or nil (skip). Both are crash-safe.
	if out ~= nil then
		if type(out.key) == "string" and out.key:sub(1, 4) == "woc_" then
			return "substitution left a woc_ key on the outgoing item"
		end
		if type(out.ItemId) == "string" and out.ItemId:sub(1, 4) == "woc_" then
			return "substitution left a woc_ ItemId on the outgoing item"
		end
	end
	if fake.key ~= "woc_test" or fake.ItemId ~= "woc_test" then
		return "live item was mutated -- shadow must be a copy"
	end
end)

-- Applied marker (§3.6): always fires (operational telemetry); surfaces the live
-- config hash in the console log even with VMF mod logging off.
mod:info("[WOC] enabled v%s settings_fp=%s (Blightreaper)", MOD_VERSION, _settings_fingerprint())

-- Per PROJECT_STANDARDS § 3.6 + § 14a: dev/alpha/beta/0.x versions print version
-- to chat on load so the user can see what's active. Stable (>=1.0.0) stays silent.
if MOD_VERSION:find("-dev$") or MOD_VERSION:find("-alpha$") or MOD_VERSION:find("-beta$") or MOD_VERSION:find("-rc%d*$") or MOD_VERSION:find("^0%.") then
	mod:echo(string.format("[WOC] v%s loaded", MOD_VERSION))
end
