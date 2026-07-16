local mod = get_mod("WOC")

local MOD_VERSION = "0.1.18-dev"

mod:info("Weapons of Chaos v%s loading", MOD_VERSION)

-- ============================================================================
-- Weapons of Chaos (WOC)
-- ============================================================================
-- Lets the player characters wield ENEMY weapons and named keep-trophy props.
-- Built the duplicate-weapon way, modeled on character_weapon_variants (CWV):
-- each weapon is a real inventory item cloned from a player base weapon
-- template, with its `right_hand_unit` swapped to a different `.unit` mesh.
--
-- FIRST ITEM: "Blightreaper" — a unique relic with Kerillian's one-handed
-- Sword action graph, slowed to 75%, equippable by every career of all five
-- heroes. Its vanilla `es_1h_sword` transport identity remains mixed-peer safe.
--
-- HELD MESH: the sword placed beside the Bögenhafen mission cage was extracted
-- from the level bundle and re-authored as explicit WOC-owned 1P and 3P units.
-- WOC's master package owns their residency; preview/package collectors borrow
-- the base Empire sword package identity without replacing the local render
-- unit. The keep-trophy diorama itself remains documentation-only and is never
-- force-loaded (a unit-path PackageManager load is an engine C-fatal).
-- ============================================================================

-- Two-helper debug-logging policy (PROJECT_STANDARDS.md § 3.6).
-- Routed through VMF logging channels; visible via VMF output_mode_debug / output_mode_warning.
-- `_dbg` = confirmation / expected behavior — mod:debug channel.
-- `_dbg_alert` = unexpected / wrong / mismatch. Log-only via engine printf (#427).
local function _dbg(fmt, ...)
	mod:debug("[WOC:dbg] " .. fmt, ...)
end

-- Issue #427/#240: mod:warning posts to CHAT under VMF defaults (logging.lua
-- warning mode >= 2), so a "log-only" alert spammed chat. Route through
-- pcall-guarded engine printf (log-only, survives mod-logging-OFF; pcall so a
-- format slip never faults the caller). Reserve chat for a deliberate
-- _chat_alert (none defined here).
local function _dbg_alert(fmt, ...)
	if not pcall(printf, "[WOC:dbg] " .. fmt, ...) then
		pcall(printf, "[WOC:dbg] (alert format error: %s)", tostring(fmt))
	end
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

-- (#511) io-safe source reader. The VMF retail Stingray VM registers no `io`
-- library (mods are loadstring'd into the game's shared _G; the engine registers
-- `os` but not `io`), so a bare `io.open` throws "attempt to index global 'io'
-- (a nil value)" and the regression runner's pcall reports it as a FALSE FAIL on
-- healthy code (issue 479/511). Source-pattern checks route through this helper,
-- which returns nil (-> the check's "unreadable source => skip" branch, a PASS)
-- instead of throwing. In retail the source-text half is skipped; the source-text
-- needles still run under the modding-tools build / CI and are the QA-gate
-- candidates (PROJECT_STANDARDS 2.2b tier a).
local function _rt_src_read(path)
	local io_lib = rawget(_G, "io")
	if type(io_lib) ~= "table" or type(io_lib.open) ~= "function" then
		return nil
	end
	local f = io_lib.open(path, "r")
	if not f then return nil end
	local t = f:read("*a")
	f:close()
	return t
end
mod:command("woc_regression_test", "Run WOC regression smoke checks for past bugs", function()
	local pass, fail, skip = 0, 0, 0
	mod:echo("=== WOC regression_test (v%s) ===", MOD_VERSION)
	for _, c in ipairs(_RT_CHECKS) do
		local ok, err = pcall(c.fn)
		if ok and err == nil then
			mod:echo("  PASS: %s", c.name); pass = pass + 1
		elseif ok and type(err) == "string" and err:sub(1, 5) == "skip:" then
			mod:echo("  SKIP: %s -- %s", c.name, err:sub(7)); skip = skip + 1
		else
			mod:echo("  FAIL: %s -- %s", c.name, tostring(err)); fail = fail + 1
		end
	end
	mod:echo("=== %d passed, %d failed, %d skipped ===", pass, fail, skip)
end)

-- ============================================================
-- Constants
-- ============================================================

local ITEM_KEY    = "woc_blightreaper"
local BACKEND_ID  = ITEM_KEY .. "_001"
local BASE_WEAPON = "es_1h_sword"                       -- Kruber 1H sword (clone source)
local _wire_policy = mod:dofile("scripts/mods/weapons_of_chaos/_woc_wire_policy")
local _moveset = mod:dofile("scripts/mods/weapons_of_chaos/_woc_blightreaper_moveset")
local _power = mod:dofile("scripts/mods/weapons_of_chaos/_woc_blightreaper_power")
local _cursed = mod:dofile("scripts/mods/weapons_of_chaos/_woc_cursed_rarity")
local TEMPLATE = _moveset.TEMPLATE
local _appearance = mod:dofile("scripts/mods/weapons_of_chaos/_woc_appearance_policy")
local _preview = mod:dofile("scripts/mods/weapons_of_chaos/_woc_mod_unit_preview")
local _appearance_lib = mod:dofile("scripts/mods/weapons_of_chaos/_lib_weapon_appearance")
local _pulse_lib = mod:dofile("scripts/mods/weapons_of_chaos/_woc_blightreaper_pulse")
local _inventory_icons = mod:dofile("scripts/mods/weapons_of_chaos/_woc_inventory_icons")
local _relic_policy = mod:dofile("scripts/mods/weapons_of_chaos/_woc_relic_policy")
local _wa = _pulse_lib.new(_appearance, _appearance_lib.new())
mod._woc_inventory_icons = _inventory_icons
_cursed.install({
	Colors = rawget(_G, "Colors"),
	UISettings = rawget(_G, "UISettings"),
	RaritySettings = rawget(_G, "RaritySettings"),
	RarityIndex = rawget(_G, "RarityIndex"),
	ORDER_RARITY = rawget(_G, "ORDER_RARITY"),
	NetworkLookup = rawget(_G, "NetworkLookup"),
})
if type(_wire_policy) ~= "table" or type(_wire_policy.safe_item) ~= "function" then
	-- Packaging failures must not become startup crashes. Preserve ordinary
	-- vanilla loadout syncs, but fail closed for explicit WOC identities because
	-- sending one to a peer without WOC is a peer-fatal wire contract violation.
	printf("[WOC:595] wire policy unavailable; explicit woc_ loadout sync will fail closed")
	_wire_policy = {
		safe_item = function(item)
			local key = item and item.key
			if type(key) == "string" and key:sub(1, 4) == "woc_" then
				return nil
			end
			return item
		end,
	}
end

local HELD_UNIT = _appearance.UNIT_1P
local INVENTORY_ICON = _inventory_icons.ICON

-- Package lookup aliases are forward-only. WOC-capable peers retain the
-- authored unit locally; peers without WOC continue decoding the vanilla sword
-- index and never receive a Workshop unit path.
local _appearance_alias_count = 0
local function _ensure_appearance_aliases()
	local installed = _appearance.install_network_package_aliases(
		NetworkLookup and NetworkLookup.inventory_packages)
	if installed > _appearance_alias_count then _appearance_alias_count = installed end
	return installed
end
_ensure_appearance_aliases()
_preview.install(_appearance, _wa)

-- Original display reference (documentation only — do NOT reference at runtime):
--   units/props/inn/hub_trophy/hub_trophy_bogenhafen
-- The Bögenhafen keep-trophy diorama prop. Not runtime-loadable today; when a
-- The actual sword was recovered from the mission level placement instead.

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
	[_cursed.DISPLAY_KEY]        = "Cursed",
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
	entry.woc_item_key = ITEM_KEY

	entry.display_name    = ITEM_KEY .. "_name"
	entry.description     = ITEM_KEY .. "_description"
	entry.right_hand_unit = HELD_UNIT
	entry.left_hand_unit  = nil                 -- 1H sword: no off-hand / shield
	entry.can_wield       = _careers
	entry.template        = TEMPLATE
	entry.item_type       = ITEM_KEY            -- own type so Localize(item_type) -> "Blightreaper"
	entry.inventory_icon  = INVENTORY_ICON
	-- CIM's Athanor top renderer is not one of WOC's injected Gui renderers.
	-- Preserve the cloned vanilla sword icon as an explicit resident fallback;
	-- never submit the private WOC material to an unproven Gui.
	entry.cim_inventory_icon_fallback = base.inventory_icon
	-- hud_icon remains the inherited generic sword HUD material.

	-- Drop the DLC gate: this is a new mod item reusing base-package meshes;
	-- per-career DLC ownership is enforced by the game's own equip check.
	entry.required_dlc = nil

	entry.rarity = _relic_policy.RARITY
	entry.mod_data = {
		backend_id     = backend_id,
		ItemInstanceId = backend_id,
		CustomData = {
			traits      = "[]",
			power_level = tostring(_power.NORMAL_POWER),
			properties  = "{}",
			rarity      = _relic_policy.RARITY,
		},
		rarity      = _relic_policy.RARITY,
		traits      = {},
		power_level = _power.NORMAL_POWER,
		properties  = {},
	}
	-- No skin pre-applied: the item renders from entry.right_hand_unit. WOC
	-- trophy weapons are unique immutable relics, not craft/customize templates.
	_relic_policy.mark_definition(entry, backend_id)

	return entry
end

-- ============================================================
-- Registration (deferred until the backend is ready)
-- ============================================================

local _registered = false
local _relic_definitions = {}
local _moveset_report

-- The equipment buff is local to the wielder, so its WOC-only name never
-- crosses NetworkLookup. Its proc applies the game's native Hagbane DOT with
-- BuffSyncType.All; every peer therefore receives a boot-stable
-- `arrow_poison_dot` id and the native poisoned status FX.
local function _install_blightreaper_poison()
	local templates = rawget(_G, "BuffTemplates")
	local procs = rawget(_G, "ProcFunctions")
	if type(templates) ~= "table" or type(procs) ~= "table" then
		return false, "buff_tables_unavailable"
	end
	if type(procs[_moveset.POISON_PROC]) ~= "function" then
		procs[_moveset.POISON_PROC] = function(owner_unit, buff, params)
			local hit_unit = type(params) == "table" and params[1]
			local attack_type = type(params) == "table" and params[2]
			if attack_type ~= "light_attack" and attack_type ~= "heavy_attack" then return end
			if not (owner_unit and hit_unit and ALIVE[owner_unit] and HEALTH_ALIVE[hit_unit]) then return end
			local side = Managers and Managers.state and Managers.state.side
			if not side or not side:is_enemy(owner_unit, hit_unit) then return end
			if not ScriptUnit.has_extension(hit_unit, "buff_system") then return end
			local career = ScriptUnit.has_extension(owner_unit, "career_system")
			local buff_system = Managers.state.entity and Managers.state.entity:system("buff_system")
			local sync_types = rawget(_G, "BuffSyncType")
			if not career or not buff_system or not sync_types then return end
			buff_system:add_buff_synced(hit_unit, _moveset.DOT_TEMPLATE, sync_types.All, {
				power_level = career:get_career_power_level(),
				attacker_unit = owner_unit,
				-- `damage_source` is itself a NetworkLookup. Keep it vanilla;
				-- ITEM_KEY would be just as unsafe here as in loadout transport.
				damage_source = "buff",
			})
		end
	end
	return _moveset.install_poison_buff(templates)
end

local function _install_blightreaper_moveset()
	if _moveset_report and _moveset_report.installed then return true end
	local poison_ok, poison_reason = _install_blightreaper_poison()
	if not poison_ok then
		printf("[WOC:632] Blightreaper poison unavailable: %s", tostring(poison_reason))
		return false
	end
	_moveset_report = _moveset.install(Weapons,
		function(value) return table.clone(value, true) end)
	if not _moveset_report.installed then
		printf("[WOC:632] Blightreaper moveset unavailable: %s",
			tostring(_moveset_report.skipped))
		return false
	end
	mod:info("[WOC:632] private Kerillian Sword template ready (attacks=%d poison=%s speed=75%%)",
		_moveset_report.attacks or 0, _moveset.DOT_TEMPLATE)
	return true
end

local function _backend_items()
	return Managers and Managers.backend and Managers.backend:get_interface("items")
end

local function _stamp_live_relic(items, entry)
	if not items then return false end
	local live
	local ok = pcall(function() live = items:get_item_from_id(BACKEND_ID) end)
	if not ok or not live then
		local all
		pcall(function() all = items:get_all_backend_items() end)
		live = type(all) == "table" and all[BACKEND_ID] or nil
	end
	if not live then return false end
	local enforced = _relic_policy.enforce_instance(live, entry, BACKEND_ID)
	if enforced then _power.stamp(live, false) end
	return enforced
end

local function _equip_state(items, backend_id)
	local ok_current, current = pcall(items.equipped_by, items, backend_id)
	local ok_saved, saved = pcall(items.is_equipped_by_any_loadout, items, backend_id)
	if not ok_current or not ok_saved
			or type(current) ~= "table" or type(saved) ~= "table" then
		return nil
	end
	return #current > 0 or #saved > 0
end

local function _remove_relic_duplicates(items, ids)
	if #ids == 0 then return 0 end
	local cim = get_mod("cim_dev") or get_mod("cim")
	if not cim or type(cim._cim_get_craft) ~= "function"
			or type(cim._cim277_delete_owned_ids) ~= "function" then
		return 0
	end
	local owned = {}
	for i = 1, #ids do
		if cim._cim_get_craft(ids[i]) then owned[#owned + 1] = ids[i] end
	end
	if #owned == 0 then return 0 end
	local count, err = cim._cim277_delete_owned_ids(owned)
	if err then
		printf("[WOC:637] CIM duplicate cleanup deferred: %s", tostring(err))
		return 0
	end
	return tonumber(count) or 0
end

local function _reconcile_relic_inventory()
	if not _registered then return end
	local items = _backend_items()
	if not items then return end
	local all
	local ok = pcall(function() all = items:get_all_backend_items() end)
	if not ok or type(all) ~= "table" then return end

	local cim = get_mod("cim_dev") or get_mod("cim")
	local can_delete = cim and type(cim._cim_get_craft) == "function"
		and type(cim._cim277_delete_owned_ids) == "function"
	local report = _relic_policy.plan_reconciliation(all, _relic_definitions,
		function(backend_id) return _equip_state(items, backend_id) end,
		function(backend_id)
			return can_delete and cim._cim_get_craft(backend_id) and true or nil
		end)
	local removed = _remove_relic_duplicates(items, report.removable)
	if #report.deferred > 0 then
		printf("[WOC:637] deferred %d equipped/uncertain relic duplicate(s); retrying on next state transition",
			#report.deferred)
	end
	printf("[WOC:637] unique relics canonical=%d removed_duplicates=%d deferred=%d missing=%d",
		#report.canonical, removed, #report.deferred, #report.missing)
end

local function _register_blightreaper()
	if _registered then
		return
	end
	if not mod:get("enable_blightreaper") then
		_dbg("Blightreaper disabled via setting; skipping registration")
		return
	end
	-- The mod chunk can be evaluated before Morris' rarity tables finish
	-- loading. Re-run this idempotent registration at the in-game boundary so
	-- the Cursed presentation and lookup survive that load order.
	local rarity_ok, rarity_reason = _cursed.install({
		Colors = rawget(_G, "Colors"),
		UISettings = rawget(_G, "UISettings"),
		RaritySettings = rawget(_G, "RaritySettings"),
		RarityIndex = rawget(_G, "RarityIndex"),
		ORDER_RARITY = rawget(_G, "ORDER_RARITY"),
		NetworkLookup = rawget(_G, "NetworkLookup"),
	})
	if not rarity_ok then
		_dbg("Blightreaper Cursed rarity deferred: %s", tostring(rarity_reason))
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
	if not _install_blightreaper_moveset() then return end

	local entry = _build_entry(base, BACKEND_ID)
	mil:add_mod_items_to_local_backend({ entry }, "weapons_of_chaos")
	_relic_definitions[1] = {
		item_key = ITEM_KEY,
		backend_id = BACKEND_ID,
		master = entry,
	}

	-- Mirror into ItemMasterList so vanilla equip/preview paths resolve it
	-- (HeroPreviewer.equip_item does `ItemMasterList[item_name]`). rawget
	-- bypasses the crashify __index metamethod on the missing key.
	if ItemMasterList and not rawget(ItemMasterList, ITEM_KEY) then
		ItemMasterList[ITEM_KEY] = entry
	end
	local deus_ok, deus_reason = _power.install_deus(ItemMasterList,
		rawget(_G, "DeusStartingWeaponTypeMapping"), rawget(_G, "DeusWeapons"))
	if not deus_ok then
		_dbg("Blightreaper Deus identity deferred: %s", tostring(deus_reason))
	end

	-- Inject into NetworkLookup.item_names so item-name RPCs serialize. rawset:
	-- the table has an error-throwing __index.
	if NetworkLookup and NetworkLookup.item_names and not rawget(NetworkLookup.item_names, ITEM_KEY) then
		local idx = #NetworkLookup.item_names + 1
		rawset(NetworkLookup.item_names, idx, ITEM_KEY)
		rawset(NetworkLookup.item_names, ITEM_KEY, idx)
	end

	local items = _backend_items()
	if not _stamp_live_relic(items, entry) then
		printf("[WOC:637] canonical backend row was not visible immediately; will restamp on state transition")
	end

	_registered = true
	mod:info("[WOC] registered Blightreaper (%s) as backend item %s", ITEM_KEY, BACKEND_ID)
end

-- ============================================================
-- Chaos Wastes fixed-power identity
-- ============================================================

local _deus_setup_active = false
local _deus_pending_relics = 0

local function _pack_results(...)
	return { n = select("#", ...), ... }
end

-- Vanilla setup reads the canonical backend item by id, then immediately maps
-- item.key through DeusStartingWeaponTypeMapping. Expose a non-mutating WOC-key
-- shadow only inside that synchronous setup window. The mapping itself still
-- resolves to the vanilla elf-Sword Deus row.
mod:hook("BackendInterfaceItemPlayfab", "get_item_from_id", function(func, self, backend_id)
	local item = func(self, backend_id)
	if _deus_setup_active and _power.is_relic(item) then
		_deus_pending_relics = _deus_pending_relics + 1
		return _power.setup_identity(item)
	end
	return item
end)

mod:hook("DeusMechanism", "_setup_run", function(func, self, ...)
	_power.install_deus(ItemMasterList, rawget(_G, "DeusStartingWeaponTypeMapping"),
		rawget(_G, "DeusWeapons"))
	_deus_setup_active = true
	_deus_pending_relics = 0
	local results = _pack_results(pcall(func, self, ...))
	_deus_setup_active = false
	_deus_pending_relics = 0
	if not results[1] then error(results[2]) end
	return unpack(results, 2, results.n)
end)

mod:hook("DeusWeaponGeneration", "generate_item_from_item_key",
		function(func, deus_item_key, ...)
			local restore = _deus_setup_active and _deus_pending_relics > 0
				and deus_item_key == _power.VANILLA_DEUS_KEY
			local item = func(deus_item_key, ...)
			if restore and type(item) == "table" then
				_deus_pending_relics = _deus_pending_relics - 1
				_power.restore_deus_item(item, _power.SERIALIZATION_MARKER,
					rawget(ItemMasterList, ITEM_KEY))
			end
			return item
		end)

	mod:hook("DeusWeaponGeneration", "serialize_weapon", function(func, item)
		return _power.serialize_deus_weapon(item, function(wire_item)
			return func(wire_item)
		end)
	end)

	mod:hook("DeusWeaponGeneration", "deserialize_weapon", function(func, serialized)
		return _power.deserialize_deus_weapon(serialized, function(wire_string)
			return func(wire_string)
		end, rawget(ItemMasterList, ITEM_KEY))
	end)

	mod:hook("DeusWeaponGeneration", "upgrade_item", function(func, item, ...)
		if _power.should_block_upgrade(item) then return item end
		return func(item, ...)
	end)

-- Setup overwrites generated starter power with the difficulty default before
-- granting it. Stamp at the grant boundary so the backend row and the run
-- controller's shared item table both retain 900/Cursed.
mod:hook("BackendInterfaceDeusBase", "grant_deus_weapon", function(func, self, item)
	if _power.is_relic(item) then _power.stamp_deus(item) end
	return func(self, item)
end)

mod:hook("DeusChestExtension", "can_be_unlocked", function(func, self)
	local weapon = self._get_wielded_weapon and self:_get_wielded_weapon()
	if _power.should_block_upgrade(weapon) then return false end
	return func(self)
end)

-- RarityUtils.get_lower_rarities sees every registered rarity. Without this
-- repair, a Deus upgrade can write `cursed` into pool_excludes even though the
-- base weapon pool has no cursed bucket; the next chest then indexes nil.
mod:hook("DeusRunController", "get_weapon_pool", function(func, self, ...)
	local ok_base, base_pool = pcall(self.get_base_weapon_pool, self)
	local state = self._run_state
	if ok_base and type(base_pool) == "table" and state
			and type(state.get_own_weapon_pool_excludes) == "function" then
		local excludes = state:get_own_weapon_pool_excludes()
		local removed = _cursed.scrub_unknown_pool_rarities(base_pool, excludes)
		if #removed > 0 and type(state.set_own_weapon_pool_excludes) == "function" then
			state:set_own_weapon_pool_excludes(excludes)
			mod:info("[WOC:632] scrubbed Cursed Deus rarity exclude")
		end
	end
	return func(self, ...)
end)

-- StateInGameRunning.on_enter fires on entering the keep AND each mission load;
-- the `_registered` guard makes re-fires a no-op (CWV registration-timing pattern).
mod:hook_safe("StateInGameRunning", "on_enter", function()
	_ensure_appearance_aliases()
	_register_blightreaper()
	if _registered then
		local entry = _relic_definitions[1] and _relic_definitions[1].master
		_stamp_live_relic(_backend_items(), entry)
		_reconcile_relic_inventory()
	end
end)

-- Kerillian's sword events are authored for the elf skeleton. Reuse Weapon
-- Tweaker's proven non-elf remap at the single pre-RPC animation boundary so
-- owner 3P, bots, and remote husks all receive the same vanilla animation id.
mod:hook("WeaponUnitExtension", "_play_3p_anim",
		function(func, self, event_3p, event, owner_unit, looping_event, anim_time_scale)
			local lookup = self.current_action_settings and self.current_action_settings.lookup_data
			local template_name = lookup and lookup.item_template_name
			if template_name == TEMPLATE then
				local career_name
				local career = owner_unit and ScriptUnit.has_extension(owner_unit, "career_system")
				if career and type(career.career_name) == "function" then
					career_name = career:career_name()
				end
				event_3p = _moveset.remap_3p(event_3p, career_name, template_name)
			end
			return func(self, event_3p, event, owner_unit, looping_event, anim_time_scale)
		end)

_rt_register("issue637_unique_immutable_relic_inventory", function()
	if not mod:get("enable_blightreaper") then return "skip: Blightreaper is disabled" end
	if not _registered then return "WOC relic registration has not completed" end
	local entry = rawget(ItemMasterList, ITEM_KEY)
	if not _relic_policy.is_definition(entry) or entry.rarity ~= _relic_policy.RARITY then
		return "canonical provider row is not marked as an immutable Cursed relic"
	end
	local items = _backend_items()
	local all
	local ok = items and pcall(function() all = items:get_all_backend_items() end)
	if not ok or type(all) ~= "table" then return "backend inventory unavailable" end
	local cim = get_mod("cim_dev") or get_mod("cim")
	local can_delete = cim and type(cim._cim_get_craft) == "function"
		and type(cim._cim277_delete_owned_ids) == "function"
	local report = _relic_policy.plan_reconciliation(all, _relic_definitions,
		function(backend_id) return _equip_state(items, backend_id) end,
		function(backend_id)
			return can_delete and cim._cim_get_craft(backend_id) and true or nil
		end)
	if #report.canonical ~= 1 or #report.removable ~= 0
			or #report.deferred ~= 0 or #report.missing ~= 0 then
		return string.format("relic inventory not singular: canonical=%d removable=%d deferred=%d missing=%d",
			#report.canonical, #report.removable, #report.deferred, #report.missing)
	end
	local live = all[BACKEND_ID]
	if not _relic_policy.is_instance(live) or live.rarity ~= _relic_policy.RARITY then
		return "MoreItemsLibrary live row did not retain the immutable Cursed marker"
	end
end)

_rt_register("issue613_blightreaper_inventory_icon_contract", function()
	if not mod:get("enable_blightreaper") then return "skip: Blightreaper is disabled" end
	if not _registered then return "WOC relic registration has not completed" end
	local entry = rawget(ItemMasterList, ITEM_KEY)
	if type(entry) ~= "table" or entry.inventory_icon ~= INVENTORY_ICON then
		return "Blightreaper provider row does not own the authored inventory icon"
	end
	if type(entry.cim_inventory_icon_fallback) ~= "string"
			or entry.cim_inventory_icon_fallback == "" then
		return "Blightreaper provider row lacks a resident Athanor fallback icon"
	end
	local athanor_icon, custom = _inventory_icons.resolve(
		entry.inventory_icon, "athanor_top", entry.cim_inventory_icon_fallback)
	if not custom or athanor_icon ~= entry.cim_inventory_icon_fallback then
		return "Blightreaper custom icon did not fail closed outside injected renderers"
	end
end)

_rt_register("issue632_blightreaper_cursed_combat_contract", function()
	if not mod:get("enable_blightreaper") then return "skip: Blightreaper is disabled" end
	if not _registered then return "WOC relic registration has not completed" end
	local entry = rawget(ItemMasterList, ITEM_KEY)
	local template = rawget(Weapons, TEMPLATE)
	local donor = rawget(Weapons, _moveset.SOURCE_TEMPLATE)
	if type(entry) ~= "table" or entry.template ~= TEMPLATE then
		return "item is not bound to the private elf-Sword template"
	end
	if type(template) ~= "table" or type(donor) ~= "table" or template == donor then
		return "private elf-Sword clone is missing or aliases its donor"
	end
	if not (template.buffs and template.buffs[_moveset.POISON_BUFF_TEMPLATE]) then
		return "native Hagbane poison equipment buff is not attached"
	end
	local procs = rawget(_G, "ProcFunctions")
	if type(procs) ~= "table" or type(procs[_moveset.POISON_PROC]) ~= "function" then
		return "client-safe Hagbane poison proc is unavailable"
	end
	local live = _backend_items() and _backend_items():get_item_from_id(BACKEND_ID)
	if not live or live.power_level ~= _power.NORMAL_POWER
			or live.rarity ~= _cursed.NAME then
		return string.format("live relic expected 600/Cursed, got power=%s rarity=%s",
			tostring(live and live.power_level), tostring(live and live.rarity))
	end
	local rarity_settings = rawget(_G, "RaritySettings")
	local ui_settings = rawget(_G, "UISettings")
	if not (rarity_settings and rarity_settings.cursed
			and rarity_settings.cursed.order == _cursed.ORDER
			and ui_settings and ui_settings.item_rarity_textures
			and ui_settings.item_rarity_textures.cursed == _cursed.TEXTURE) then
		return "Cursed rarity presentation registry is incomplete"
	end
	local remaps = 0
	for _ in pairs(_moveset.THIRD_PERSON_REMAP) do remaps = remaps + 1 end
	if remaps ~= 6 then return "non-elf 3P remap set is not exactly six events" end
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
-- WOC applies no skin (weapon_skin_id "n/a"). Its local Cursed rarity is also
-- replaced with the vanilla promo id in the transient wire shadow.
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
	local base_resolvable = rawget(ItemMasterList, BASE_WEAPON)
		and NetworkLookup and NetworkLookup.item_names
		and rawget(NetworkLookup.item_names, BASE_WEAPON)
	return _wire_policy.safe_item(item, BASE_WEAPON, base_resolvable,
		_relic_policy.WIRE_RARITY)
end

local _blightreaper_sync_seen = false
local _IDENTITY_SCHEMA = 1
local _remote_blightreaper = {}

-- The vanilla loadout RPC intentionally carries `es_1h_sword` for mixed-lobby
-- crash safety. This VMF same-mod sideband restores the one missing bit only on
-- WOC-capable peers. It is bounded to loadout sync edges, never sent per-frame.
mod:network_register("woc_blightreaper_identity", function(sender_peer_id, schema, slot_name, equipped)
	if schema ~= _IDENTITY_SCHEMA or type(sender_peer_id) ~= "string" then return end
	if slot_name ~= "slot_melee" and slot_name ~= "slot_ranged" then return end
	local by_slot = _remote_blightreaper[sender_peer_id]
	if not by_slot then by_slot = {}; _remote_blightreaper[sender_peer_id] = by_slot end
	local active = equipped == 1
	if by_slot[slot_name] == active then return end
	by_slot[slot_name] = active

	-- The ordinary equipment RPC and this sideband may arrive in either order.
	-- Re-wield once when the husk already exists; otherwise its upcoming vanilla
	-- wield consumes the cached identity.
	local pm = Managers and Managers.player
	local player = pm and pm.player_from_peer_id and pm:player_from_peer_id(sender_peer_id)
	local unit = player and player.player_unit
	if unit and Unit.alive(unit) then
		local inventory
		pcall(function() inventory = ScriptUnit.extension(unit, "inventory_system") end)
		if inventory and inventory.wielded_slot == slot_name and type(inventory.wield) == "function" then
			pcall(inventory.wield, inventory, slot_name)
		end
	end
end)

local function _husk_peer_id(owner_unit_3p)
	if not owner_unit_3p then return nil end
	local player
	pcall(function() player = Managers.player:owner(owner_unit_3p) end)
	return player and (player.peer_id or (player.network_id and player:network_id()))
end

-- Remote husks resolve the intentionally vanilla wire item. Re-key the render
-- unit only when the WOC sideband positively identifies this peer+slot. Passing
-- a shallow item-data shadow with a WOC name prevents another variant mod from
-- reinterpreting the same base-sword echo after our decision.
mod:hook("GearUtils", "spawn_inventory_unit", function(func, world, hand, item_template,
		item_units, slot_name, item_data, owner_unit_1p, owner_unit_3p, ...)
	if not owner_unit_1p and hand == "right" then
		local peer_id = _husk_peer_id(owner_unit_3p)
		local active = peer_id and _remote_blightreaper[peer_id]
		active = active and active[slot_name]
		if active and type(item_units) == "table" then
			local unit_shadow = {}
			for key, value in pairs(item_units) do unit_shadow[key] = value end
			item_units = unit_shadow
			item_units.right_hand_unit = HELD_UNIT
			if type(item_data) == "table" then
				local shadow = {}
				for key, value in pairs(item_data) do shadow[key] = value end
				shadow.name = ITEM_KEY
				item_data = shadow
			end
		end
	end
	local is_blightreaper = hand == "right" and type(item_units) == "table"
		and item_units.right_hand_unit == HELD_UNIT
	local unit_3p, ammo_3p, unit_1p, ammo_1p = func(world, hand, item_template,
		item_units, slot_name, item_data, owner_unit_1p, owner_unit_3p, ...)
	if is_blightreaper then
		_wa.apply(unit_3p, _appearance.TRANSFORM, "3p", "inventory-spawn")
		if unit_1p then
			_wa.apply(unit_1p, _appearance.TRANSFORM, "1p", "inventory-spawn")
		end
	end
	return unit_3p, ammo_3p, unit_1p, ammo_1p
end)

if rawget(_G, "LoadoutUtils") and LoadoutUtils.sync_loadout_slot then
	mod:hook(LoadoutUtils, "sync_loadout_slot", function(func, player, slot_name, item, sync_to_specific_peer_id)
		local is_blightreaper = _power.is_relic(item)
		if is_blightreaper then
			_blightreaper_sync_seen = true
		end
		if slot_name == "slot_melee" or slot_name == "slot_ranged" then
			pcall(mod.network_send, mod, "woc_blightreaper_identity", "others",
				_IDENTITY_SCHEMA, slot_name, is_blightreaper and 1 or 0)
		end
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
	local fake = { key = "woc_test", ItemId = "woc_test", power_level = 600, rarity = "cursed" }
	local out = _wire_safe_item(fake)
	-- The native base + lookup are boot data, so a live game must produce the
	-- exact vanilla-keyed shadow. nil remains reserved for a genuinely broken
	-- base lookup and may not masquerade as passing verification.
	if out == nil then
		return "base sword is not wire-resolvable -- WOC sync would be skipped"
	end
	if out.key ~= BASE_WEAPON or out.ItemId ~= BASE_WEAPON then
		return string.format("expected exact base identity %s, got key=%s ItemId=%s",
			BASE_WEAPON, tostring(out.key), tostring(out.ItemId))
	end
	if out.rarity ~= _relic_policy.WIRE_RARITY or fake.rarity ~= _relic_policy.RARITY then
		return "Cursed rarity did not degrade to promo on the shadow only"
	end
	if fake.key ~= "woc_test" or fake.ItemId ~= "woc_test" then
		return "live item was mutated -- shadow must be a copy"
	end
end)

_rt_register("issue509_registered_blightreaper_wire_contract", function()
	if not mod:get("enable_blightreaper") then
		return "skip: Blightreaper setting is disabled"
	end
	if not _registered then
		return "Blightreaper did not register -- check MoreItemsLibrary load order"
	end

	local entry = rawget(ItemMasterList, ITEM_KEY)
	if not entry then return "registered WOC ItemMasterList row is missing" end
	if entry.key ~= BASE_WEAPON or entry.name ~= BASE_WEAPON then
		return string.format("registered clone lost inherited base identity: key=%s name=%s",
			tostring(entry.key), tostring(entry.name))
	end

	local names = NetworkLookup and NetworkLookup.item_names
	local woc_id = names and rawget(names, ITEM_KEY)
	if type(woc_id) ~= "number" or rawget(names, woc_id) ~= ITEM_KEY then
		return "WOC NetworkLookup.item_names pair is not symmetric"
	end

	local items = Managers.backend and Managers.backend:get_interface("items")
	local live = items and items:get_item_from_id(BACKEND_ID)
	if not live then return "registered Blightreaper backend item is missing" end
	if live.key ~= BASE_WEAPON or live.ItemId ~= BASE_WEAPON then
		return string.format("backend item is not vanilla-wire keyed: key=%s ItemId=%s",
			tostring(live.key), tostring(live.ItemId))
	end
	local wire = _wire_safe_item(live)
	if type(wire) ~= "table" or wire == live or wire.key ~= BASE_WEAPON
			or wire.rarity ~= _relic_policy.WIRE_RARITY then
		return "Cursed live Blightreaper did not produce a vanilla promo wire shadow"
	end
	if live.rarity ~= _relic_policy.RARITY then
		return "wire substitution mutated the local Cursed rarity"
	end
	if not _blightreaper_sync_seen then
		return "skip: equip Blightreaper once, then rerun for live hook evidence"
	end
end)

-- issue 509 backfill: two more locks on the wire-safety row-of-concern plus the
-- keep-entry force-load dead end. Registered here beside `_wire_safe_item` (a
-- file-local just above). See ENGINE_SURFACE.md "Wire safety" + "dead ends".
_rt_register("issue422_wire_safety_unconditional_singleton", function()
	-- The sender-side wire-safety hook on (LoadoutUtils, sync_loadout_slot) must
	-- be UNCONDITIONAL (never toggle-gated) and SINGLE (VMF silently drops a 2nd
	-- hook on the same Class.method). Prefix classification is runtime-testable
	-- even in retail; the singleton remains a source-pattern guard on THIS file (path via
	-- debug.getinfo on the file-local _rt_register); needles split so this check
	-- never self-matches; no-op when source is unreadable (deploy/bundle paths).
	if not _wire_policy.is_woc_key("woc_future_weapon")
		or _wire_policy.is_woc_key(BASE_WEAPON) then
		return "issue 422 regression: unconditional woc_ prefix classification changed"
	end
	local ok, info = pcall(debug.getinfo, _rt_register, "S")
	if not ok or type(info) ~= "table" or not info.source then return end
	local src_path = info.source:sub(1, 1) == "@" and info.source:sub(2) or info.source
	local txt = _rt_src_read(src_path)  -- (#511) io-safe; nil in retail sandbox => skip
	if not txt then return end
	local hook_needle = "mod:hook(LoadoutUtils, " .. '"sync_loadout_slot"'
	local count, pos = 0, 1
	while true do
		local s = txt:find(hook_needle, pos, true)
		if not s then break end
		count = count + 1
		pos = s + 1
	end
	if count == 0 then
		return "issue 422 regression: the (LoadoutUtils, sync_loadout_slot) wire-safety hook is gone -- non-WOC peers CTD"
	end
	if count > 1 then
		return "issue 422 regression: duplicate (LoadoutUtils, sync_loadout_slot) hook -- VMF drops the 2nd silently"
	end
end)

_rt_register("wire_non_woc_item_passthrough_identity", function()
	-- Wire safety must NEVER touch a vanilla (non-woc_) item: _wire_safe_item
	-- returns the SAME table identity unchanged for a non-woc_ key. Complements
	-- wire_woc_never_leaves_woc_key (which covers the woc_ substitution path).
	local vanilla = { key = BASE_WEAPON, ItemId = BASE_WEAPON, power_level = 300 }
	local out = _wire_safe_item(vanilla)
	if out ~= vanilla then
		return "a non-woc_ item was not passed through by identity -- wire guard is mutating vanilla loadout items"
	end
end)

_rt_register("no_unit_path_package_force_load", function()
	-- Keep-entry C-fatal dead end (DEVELOPMENT.md crash post-mortem + file header):
	-- Managers.package:load on a UNIT path (not a real .package name) hard-crashes
	-- on keep entry via the engine resource_package() C-fatal, bypassing pcall. WOC
	-- force-loads NOTHING; the held mesh is an always-resident base unit. Lock it:
	-- no raw package force-load call in this file. Needle split so this check never
	-- self-matches; no-op when source unreadable. When a real loadable enemy
	-- .package ships, update this to allow a verified package-NAME load while still
	-- forbidding a unit-PATH load.
	local ok, info = pcall(debug.getinfo, _rt_register, "S")
	if not ok or type(info) ~= "table" or not info.source then return end
	local src_path = info.source:sub(1, 1) == "@" and info.source:sub(2) or info.source
	local txt = _rt_src_read(src_path)  -- (#511) io-safe; nil in retail sandbox => skip
	if not txt then return end
	local load_needle = "Managers.package" .. ":load("
	if txt:find(load_needle, 1, true) then
		return "a package force-load reappeared -- verify it targets a real .package NAME, not a unit path (keep-entry C-fatal, DEVELOPMENT.md)"
	end
end)

_rt_register("issue613_blightreaper_appearance_contract", function()
	if HELD_UNIT ~= "units/woc_blightreaper/blightreaper" then
		return "Blightreaper item no longer points at the authored WOC unit"
	end
	if _appearance.UNIT_3P ~= HELD_UNIT .. "_3p" then
		return "explicit 3P sibling contract drifted"
	end
	if _appearance_alias_count ~= 2 then
		return string.format("expected two forward inventory-package aliases, got %s",
			tostring(_appearance_alias_count))
	end
	local transform = _appearance.TRANSFORM
	if not transform or transform.scale[1] ~= 0.9
			or transform.scale[2] ~= 0.9 or transform.scale[3] ~= 0.9
			or transform.rotation[1] ~= -90
			or transform.rotation[2] ~= -90 or transform.rotation[3] ~= -90
			or transform.offset[1] ~= 0 or transform.offset[2] ~= 0
			or transform.offset[3] ~= -0.3 then
		return "canonical scale/rotation/offset contract drifted"
	end
	local ok_1p, resident_1p = pcall(Application.can_get, "unit", HELD_UNIT)
	local ok_3p, resident_3p = pcall(Application.can_get, "unit", _appearance.UNIT_3P)
	if not ok_1p or resident_1p ~= true then return "authored 1P unit is not resident" end
	if not ok_3p or resident_3p ~= true then return "authored 3P unit is not resident" end
	for _, perspective in ipairs({ "1p", "3p" }) do
		local descriptor = _appearance.pulse_descriptor(perspective)
		local ok_material, material_ready = pcall(
			Application.can_get, "material", descriptor.material)
		if not ok_material or material_ready ~= true then
			return string.format("%s pulse donor material is not resident: %s",
				perspective, tostring(descriptor.material))
		end
		if #descriptor.textures ~= 6 or #descriptor.variables ~= 3 then
			return string.format("%s pulse descriptor is not bounded 6-texture/3-variable shape",
				perspective)
		end
		for _, binding in ipairs(descriptor.textures) do
			local ok_texture, texture_ready = pcall(
				Application.can_get, "texture", binding.texture)
			if not ok_texture or texture_ready ~= true then
				return string.format("%s pulse texture is not resident: %s",
					perspective, tostring(binding.texture))
			end
		end
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
