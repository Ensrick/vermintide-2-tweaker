-- _woc_relic_registration_owner.lua
-- Sole owner for Blightreaper item construction, combat-template installation,
-- backend reconciliation, Chaos Wastes identity, and registration lifecycle.

local M = {}

function M.install(mod, ctx)
	local ITEM_KEY = assert(ctx.item_key, "item_key required")
	local BACKEND_ID = assert(ctx.backend_id, "backend_id required")
	local BASE_WEAPON = assert(ctx.base_weapon, "base_weapon required")
	local HELD_UNIT = assert(ctx.held_unit, "held_unit required")
	local INVENTORY_ICON = assert(ctx.inventory_icon, "inventory_icon required")
	local TEMPLATE = assert(ctx.template, "template required")
	local _careers = assert(ctx.careers, "careers required")
	local _display_names = assert(ctx.display_names, "display_names required")
	local _moveset = assert(ctx.moveset, "moveset required")
	local _power = assert(ctx.power, "power required")
	local _cursed = assert(ctx.cursed, "cursed required")
	local _attack_order = assert(ctx.attack_order, "attack_order required")
	local _chain_descriptor = assert(ctx.chain_descriptor, "chain_descriptor required")
	local _relic_policy = assert(ctx.relic_policy, "relic_policy required")
	local _inventory_icons = assert(ctx.inventory_icons, "inventory_icons required")
	local _network_lookup = assert(ctx.network_lookup, "network_lookup required")
	local _career_weapon_actions = assert(ctx.career_weapon_actions,
		"career_weapon_actions required")
	local _career_action_owner = assert(ctx.career_action_owner,
		"career_action_owner required")
	local _rt_register = assert(ctx.rt_register, "rt_register required")
	local _dbg = assert(ctx.dbg, "dbg required")
	local _ensure_appearance_aliases = assert(ctx.ensure_appearance_aliases,
		"ensure_appearance_aliases required")
	local _reset_appearance_diag = assert(ctx.reset_appearance_diag,
		"reset_appearance_diag required")
	local _start_spirit_runtime = assert(ctx.start_spirits, "start_spirits required")
	local _stop_spirit_runtime = assert(ctx.stop_spirits, "stop_spirits required")
	local _mark_blight_poison = assert(ctx.mark_poison, "mark_poison required")
	local _owner_has_wielded_trait = assert(ctx.owner_has_wielded_trait,
		"owner_has_wielded_trait required")

	local _registration_attempts = 0
	local _registration_diag_budget = 12
	local _registration_diag_seen = {}
	local _registration_last_gate = "not_attempted"
	local _registration_last_reason = "not_attempted"

	local function _registration_deferred(gate, reason, detail)
		_registration_last_gate = tostring(gate or "unknown")
		_registration_last_reason = tostring(reason or "unknown")
		local key = _registration_last_gate .. ":" .. _registration_last_reason
		if not _registration_diag_seen[key] and _registration_diag_budget > 0 then
			_registration_diag_seen[key] = true
			_registration_diag_budget = _registration_diag_budget - 1
			pcall(printf,
				"[WOC:690] registration deferred attempt=%d gate=%s reason=%s detail=%s",
				_registration_attempts, _registration_last_gate,
				_registration_last_reason, tostring(detail or "none"))
		end
		return false
	end

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
			traits      = '["' .. _moveset.POISON_TRAIT .. '","'
				.. _moveset.SHYISH_CURSE_TRAIT .. '"]',
			power_level = tostring(_power.NORMAL_POWER),
			properties  = '{"woc_intrinsic_crit":1,"woc_power_vs_order":1}',
			rarity      = _relic_policy.RARITY,
		},
		rarity      = _relic_policy.RARITY,
		traits      = _moveset.intrinsic_traits(),
		power_level = _power.NORMAL_POWER,
		properties  = {
			woc_intrinsic_crit = 1,
			woc_power_vs_order = 1,
		},
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
			-- Poisoned Edge is reusable; Shyish spirit attribution is not. Mark
			-- only when the currently wielded item also owns the intrinsic curse.
			-- Client-owned Blightreaper hits reach the host through the native
			-- rpc_add_buff_synced_params observation below.
			if _owner_has_wielded_trait(owner_unit, _moveset.SHYISH_CURSE_TRAIT) then
				_mark_blight_poison(hit_unit, owner_unit)
			end
		end
	end
	return _moveset.install_poison_buff(templates)
end

-- ============================================================
-- Blightreaper attack order (author-picked chain permutation)
-- ============================================================
-- Reads the Blightreaper Combat dropdowns and applies the permutation plan to
-- the private clone AFTER it is fully prepared (install site below) and again
-- on every picker settings change (mod.on_setting_changed). The module fails
-- closed: a bad selection or descriptor mutates nothing and the native order
-- keeps playing. Sub_action tables are mutated in place, never replaced, so a
-- re-apply reaches the very next attack without a re-equip.

local _attack_order_receipts = 16

local function _attack_order_selections()
	return {
		lights = {
			mod:get("woc_blightreaper_light_1"),
			mod:get("woc_blightreaper_light_2"),
			mod:get("woc_blightreaper_light_3"),
			mod:get("woc_blightreaper_light_4"),
		},
		heavies = {
			mod:get("woc_blightreaper_heavy_1"),
			mod:get("woc_blightreaper_heavy_2"),
			mod:get("woc_blightreaper_heavy_3"),
		},
		-- The push dropdown is not registered while the crowbill graph has only
		-- one follow-up unit (VMF rejects single-option dropdowns; the 0.1.37
		-- widget aborted the whole mod's options init - issue 822). Fall back
		-- to the native unit so a nil setting can never fail the plan closed.
		push = { mod:get("woc_blightreaper_push_follow")
			or (_chain_descriptor.push_positions
				and _chain_descriptor.push_positions[1]) },
	}
end

local function _apply_attack_order(source)
	local weapons = rawget(_G, "Weapons")
	local template = weapons and rawget(weapons, TEMPLATE)
	if type(template) ~= "table" then
		return nil, "template_not_installed"
	end
	local report, reason = _attack_order.apply(template, _chain_descriptor,
		_attack_order_selections())
	if _attack_order_receipts > 0 then
		_attack_order_receipts = _attack_order_receipts - 1
		if report then
			pcall(printf, "[WOC:order] attack order applied (%s): writes=%d identity=%s",
				tostring(source), report.writes, tostring(report.identity))
		else
			pcall(printf, "[WOC:order] attack order NOT applied (%s): %s; native order stays",
				tostring(source), tostring(reason))
		end
	end
	return report, reason
end

mod.on_setting_changed = function(setting_id)
	if type(setting_id) == "string" and setting_id:find("^woc_blightreaper_") then
		_apply_attack_order("setting:" .. setting_id)
	end
end

mod:command("woc_chains", "Show the Blightreaper attack chain map (what follows what)", function()
	local weapons = rawget(_G, "Weapons")
	local template = weapons and rawget(weapons, TEMPLATE)
	if type(template) ~= "table" then
		mod:echo("[WOC] Blightreaper template is not installed yet (enable the relic and enter the keep).")
		return
	end
	local lines, reason = _attack_order.describe_chains(template, _chain_descriptor,
		_attack_order_selections(), function(key) return mod:localize(key) end)
	if not lines then
		mod:echo("[WOC] chain map unavailable: %s", tostring(reason))
		return
	end
	mod:echo("[WOC] Blightreaper chain map (positions are chain steps):")
	for i = 1, #lines do
		mod:echo("  %s", lines[i])
	end
end)

_rt_register("attack_order_pick_vocabulary_and_apply", function()
	local ids = {}
	for _, unit in ipairs(_chain_descriptor.lights) do ids[unit.id] = true end
	for _, unit in ipairs(_chain_descriptor.heavies) do ids[unit.id] = true end
	for _, unit in ipairs(_chain_descriptor.push) do ids[unit.id] = true end
	local selections = _attack_order_selections()
	for pool, chosen in pairs(selections) do
		for i, value in pairs(chosen) do
			if value ~= nil and not ids[value] then
				return string.format("%s pick %s stores out-of-vocabulary unit %s",
					tostring(pool), tostring(i), tostring(value))
			end
		end
	end
	local weapons = rawget(_G, "Weapons")
	local template = weapons and rawget(weapons, TEMPLATE)
	if type(template) ~= "table" then
		return "skip: Blightreaper template not installed"
	end
	local report, reason = _attack_order.apply(template, _chain_descriptor, selections)
	if not report then
		return "attack order failed to apply: " .. tostring(reason)
	end
end)

local function _install_blightreaper_moveset()
	if _moveset_report and _moveset_report.installed
			and _moveset_report.ability_actions
			and _moveset_report.ability_actions.ok then
		return true
	end
	local rows_ok, rows_reason = _moveset.install_intrinsic_property_rows(
		rawget(_G, "WeaponProperties"), rawget(_G, "BuffTemplates"))
	if not rows_ok then
		return false, "property_rows", rows_reason
	end
	local traits_ok, traits_reason = _moveset.install_intrinsic_trait_rows(
		rawget(_G, "WeaponTraits"), rawget(_G, "BuffTemplates"))
	if not traits_ok then
		return false, "trait_rows", traits_reason
	end
	local poison_ok, poison_reason = _install_blightreaper_poison()
	if not poison_ok then
		return false, "poison", poison_reason
	end
	_moveset_report = _moveset.install(Weapons,
		function(value) return table.clone(value, true) end)
	if not _moveset_report.installed then
		return false, "moveset", _moveset_report.skipped
	end
	local identity = _career_weapon_actions.prepare_inherited_clone(
		Weapons[TEMPLATE], Weapons[_moveset.SOURCE_TEMPLATE],
		rawget(_G, "ActionTemplates"),
		tostring(TEMPLATE) .. "<-" .. tostring(_moveset.SOURCE_TEMPLATE))
	_moveset_report.career_action_identity = identity
	if not identity.ok then
		_moveset_report.installed = false
		return false, "career_action_identity",
			tostring(identity.skipped or "clone_prepare_failed")
	end
	local abilities = _career_weapon_actions.install(
		Weapons[TEMPLATE], _careers, rawget(_G, "CareerSettings"),
		rawget(_G, "ActionTemplates"), _career_action_owner)
	_moveset_report.ability_actions = abilities
	if not abilities.ok then
		_moveset_report.installed = false
		return false, "career_action_install", string.format(
			"reason=%s conflicts=%s missing_actions=%s missing_careers=%s",
			tostring(abilities.skipped or "provider_conflict"),
			table.concat(abilities.conflicting_names or {}, ","),
			table.concat(abilities.missing_actions or {}, ","),
			table.concat(abilities.missing_careers or {}, ","))
	end
	-- Attack-order picker: permute the fully prepared clone per the Blightreaper
	-- Combat dropdowns. Never gates registration; a failed apply keeps the
	-- native order (module is fail-closed, receipt is printf log-only).
	local order_report = _apply_attack_order("install")
	_moveset_report.attack_order = order_report or false
	mod:info("[WOC:690] private Crowbill template ready (attacks=%d poison=%s crit=15%% speed=83%% executioner_audio=true career_actions=%d/%d restored_inherited=%d discarded_claims=%d)",
		_moveset_report.attacks or 0, _moveset.DOT_TEMPLATE,
		abilities.installed + abilities.existing, abilities.required,
		identity.restored or 0, identity.discarded_claims or 0)
	return true
end

local function _backend_items()
	return Managers and Managers.backend and Managers.backend:get_interface("items")
end

local function _live_backend_item(items, backend_id)
	if not items then return nil end
	local live
	local fetched = pcall(function()
		live = items:get_item_from_id(backend_id)
	end)
	if fetched and live then return live end
	local all
	pcall(function() all = items:get_all_backend_items() end)
	return type(all) == "table" and all[backend_id] or nil
end

local function _stamp_live_relic(items, entry)
	local live = _live_backend_item(items, BACKEND_ID)
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
	_registration_attempts = _registration_attempts + 1
	if not mod:get("enable_blightreaper") then
		return _registration_deferred("setting", "disabled")
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
		NetworkLookupLib = _network_lookup,
	})
	if not rarity_ok then
		return _registration_deferred("cursed_rarity", rarity_reason)
	end

	local mil = get_mod("MoreItemsLibrary")
	if not mil then
		return _registration_deferred("more_items_library", "mod_unavailable",
			"load MoreItemsLibrary above WOC")
	end

	local base = rawget(ItemMasterList, BASE_WEAPON)
	if not base then
		return _registration_deferred("base_item", "missing", BASE_WEAPON)
	end
	local moveset_ok, moveset_gate, moveset_reason = _install_blightreaper_moveset()
	if not moveset_ok then
		return _registration_deferred(moveset_gate, moveset_reason)
	end

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

	-- Inject into NetworkLookup.item_names so item-name RPCs serialize. The
	-- canonical helper preserves both directions and fails closed on half-pairs.
	local lookup_index, _, lookup_reason = _network_lookup.register_named(
		NetworkLookup, "item_names", ITEM_KEY)
	if not lookup_index then
		_registration_last_gate = "network_lookup"
		_registration_last_reason = lookup_reason
		_dbg("Blightreaper registration deferred: NetworkLookup.item_names %s",
			tostring(lookup_reason))
		return
	end

	local items = _backend_items()
	if not _stamp_live_relic(items, entry) then
		printf("[WOC:637] canonical backend row was not visible immediately; will restamp on state transition")
	end

	_registered = true
	_registration_last_gate = "registered"
	_registration_last_reason = "complete"
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
	_reset_appearance_diag()
	_ensure_appearance_aliases()
	_register_blightreaper()
	if _registered then
		local entry = _relic_definitions[1] and _relic_definitions[1].master
		_stamp_live_relic(_backend_items(), entry)
		_reconcile_relic_inventory()
		_start_spirit_runtime()
	end
end)

-- The event manager and network-unit spawner are state-owned.  Delete bounded
-- live spirits and unregister before StateInGameRunning tears those systems
-- down; retaining them into the next level would be a dead-world fault.
mod:hook_safe("StateInGameRunning", "on_exit", function()
	_stop_spirit_runtime("state_exit")
end)

-- Crowbill attack events are authored for Sienna's (bw_) skeleton. Reuse
-- Weapon Tweaker's proven per-receiver crowbill remap at the single pre-RPC
-- animation boundary so owner 3P, bots, and remote husks all receive the same
-- vanilla animation id. The 3P wield stance is handled in data instead
-- (`wield_anim_career_3p` on the private clone; see the moveset module).
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
		return "item is not bound to the private Crowbill template"
	end
	if type(template) ~= "table" or type(donor) ~= "table" or template == donor then
		return "private Crowbill clone is missing or aliases its donor"
	end
	-- MoreItemsLibrary copies `mod_data.traits` into the live backend row; the
	-- ItemMasterList definition intentionally stores that acquisition payload
	-- under `mod_data`. Test the actual runtime owner instead of the definition
	-- table, which produced a false FAIL in the July 21 evidence log.
	local live = _live_backend_item(_backend_items(), BACKEND_ID)
	if not _moveset.item_has_trait(live, _moveset.POISON_TRAIT)
			or not _moveset.item_has_trait(live, _moveset.SHYISH_CURSE_TRAIT) then
		return "live relic is missing intrinsic poison/Shyish traits"
	end
	local actions = template.actions and template.actions.action_one
	for _, required in ipairs({
		"light_attack_left", "light_attack_right", "light_attack_last",
		"light_attack_upper", "light_attack_bopp",
		"heavy_attack", "heavy_attack_left", "heavy_attack_right_up",
	}) do
		if type(actions and actions[required]) ~= "table" then
			return "native Crowbill action is missing: " .. tostring(required)
		end
	end
	if actions.light_attack_left.impact_sound_event ~= _moveset.GREATAXE_IMPACT_SOUND
			or actions.light_attack_left.no_damage_impact_sound_event
				~= _moveset.GREATAXE_ARMOUR_IMPACT_SOUND
			or actions.light_attack_left.hit_effect ~= _moveset.GREATAXE_HIT_EFFECT
			or actions.light_attack_left.armor_impact_sound_event ~= nil then
		return "Blightreaper Greataxe impact identity is incomplete"
	end
	for name, action in pairs(actions) do
		if type(action) == "table" and action.kind == "sweep" then
			if action.additional_critical_strike_chance ~= _moveset.INTRINSIC_CRIT_CHANCE then
				return "intrinsic 15% critical chance drifted on " .. tostring(name)
			end
			if name:find("^light_attack") and action.damage_profile ~= _moveset.LIGHT_DAMAGE_PROFILE then
				return "relic light damage profile drifted on " .. tostring(name)
			end
			if name:find("^heavy_attack") and action.damage_profile ~= _moveset.HEAVY_DAMAGE_PROFILE then
				return "armor-piercing heavy profile drifted on " .. tostring(name)
			end
		end
	end
	local has_executioner_audio = false
	for _, dependency in ipairs(template.wwise_dep_right_hand or {}) do
		if dependency == _moveset.EXECUTIONER_WWISE_DEP then has_executioner_audio = true end
	end
	if not has_executioner_audio then return "Executioner Sword audio dependency is absent" end
	if not (live and live.properties and live.properties[_moveset.CRIT_PROPERTY] == 1
			and live.properties[_moveset.ORDER_PROPERTY] == 1) then
		return "live relic is missing intrinsic and cosmetic property rows"
	end
	local procs = rawget(_G, "ProcFunctions")
	if type(procs) ~= "table" or type(procs[_moveset.POISON_PROC]) ~= "function" then
		return "client-safe Hagbane poison proc is unavailable"
	end
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
	local remap_shape = { dr_ = 6, es_ = 1, wh_ = 1, _default = 4 }
	for prefix, expected in pairs(remap_shape) do
		local remap = _moveset.THIRD_PERSON_REMAP[prefix]
		local count = 0
		if type(remap) == "table" then
			for _ in pairs(remap) do count = count + 1 end
		end
		if count ~= expected then
			return string.format(
				"crowbill 3P remap table %s expected %d entries, found %d",
				tostring(prefix), expected, count)
		end
	end
	local wield_3p = template.wield_anim_career_3p
	if type(wield_3p) ~= "table" or wield_3p.es_mercenary ~= "to_1h_sword"
			or wield_3p.wh_priest ~= "to_1h_hammer" or wield_3p.bw_adept ~= nil then
		return "per-career crowbill 3P wield redirect table is incomplete"
	end
end)

_rt_register("blightreaper_all_career_ability_actions", function()
	if mod:get("enable_blightreaper") ~= true then return "skip:Blightreaper disabled" end
	local abilities = _moveset_report and _moveset_report.ability_actions
	if type(abilities) ~= "table" or abilities.ok ~= true then
		return "career ability integration report is unavailable or incomplete"
	end
	if abilities.required ~= 10
			or abilities.installed + abilities.existing ~= abilities.required then
		return string.format("expected 10/10 weapon-bound career actions, got %s/%s",
			tostring((abilities.installed or 0) + (abilities.existing or 0)),
			tostring(abilities.required))
	end
	local template = Weapons and Weapons[TEMPLATE]
	for _, action_name in ipairs(abilities.names or {}) do
		if not (template and template.actions
				and template.actions[action_name] == abilities.actions[action_name]) then
			return "missing Blightreaper career action: " .. tostring(action_name)
		end
	end
end)

	local api = {}

	function api:is_registered()
		return _registered
	end

	function api:backend_items()
		return _backend_items()
	end

	function api:live_backend_item(items, backend_id)
		return _live_backend_item(items, backend_id)
	end

	function api:install_poison()
		return _install_blightreaper_poison()
	end

	function api:moveset_report()
		return _moveset_report
	end

	function api:registration_state()
		return {
			registered = _registered,
			gate = _registration_last_gate,
			reason = _registration_last_reason,
			attempts = _registration_attempts,
		}
	end

	return api
end

return M
