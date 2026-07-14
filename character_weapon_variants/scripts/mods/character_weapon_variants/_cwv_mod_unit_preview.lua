-- _cwv_mod_unit_preview.lua
--
-- Bridges mod-scoped custom units into vanilla previewers without asking the
-- global PackageManager to discover a mod-defined package name.  VT2 has two
-- resource namespaces: CWV's master package makes the unit resident, while
-- LootItemUnitPreviewer/HeroPreviewer call Application.resource_package with
-- the unit path.  The latter cannot discover Workshop package paths and hard
-- crashes before spawn.  A resident custom unit therefore borrows a vanilla
-- package as its load/unload reference; if residency is absent, preview spawn
-- data falls back to that vanilla unit instead of reaching World.spawn_unit.
local M = {}

M._stats = {
	alias_leases = 0,
	bypassed_leases_repaired = 0,
	teardowns = 0,
	teardown_repeats_ignored = 0,
	teardown_repair_failures = 0,
}

local function _has_key(values, key)
	return type(values) == "table" and rawget(values, key) ~= nil
end

-- Normalize every custom preview key before vanilla walks `_loaded_packages`
-- and `_packages_to_load`. Another mod may legitimately short-circuit
-- LootItemUnitPreviewer.load_package after proving that a bundled unit is
-- resident. In that ordering our load hook never runs, so acquire the borrowed
-- vanilla lease here before replacing the custom bookkeeping key. One lease is
-- shared by all custom keys that borrow the same alias in one previewer.
function M.reconcile_for_unload(previewer, alias_for, acquire_alias)
	local loaded = previewer._loaded_packages or {}
	local pending = previewer._packages_to_load or {}
	local aliases = previewer._cwv_preview_package_aliases or {}
	local leases = previewer._cwv_preview_alias_leases or {}
	local custom_keys = {}
	local report = { mapped = 0, repaired = 0, failed = 0 }

	previewer._cwv_preview_package_aliases = aliases
	previewer._cwv_preview_alias_leases = leases

	for key in pairs(loaded) do
		local alias = alias_for(key)
		if alias then custom_keys[key] = alias end
	end
	for key in pairs(pending) do
		local alias = alias_for(key)
		if alias then custom_keys[key] = alias end
	end
	for custom, alias in pairs(aliases) do
		if _has_key(loaded, custom) or _has_key(pending, custom) then
			custom_keys[custom] = alias
		end
	end

	for custom, alias in pairs(custom_keys) do
		local lease = leases[alias]
		if not lease or lease.acquired ~= true then
			local acquired = acquire_alias(alias, custom)
			if acquired == true then
				lease = lease or { customs = {} }
				lease.acquired = true
				lease.complete = true
				leases[alias] = lease
				report.repaired = report.repaired + 1
			else
				report.failed = report.failed + 1
			end
		end

		loaded[custom] = nil
		pending[custom] = nil
		aliases[custom] = alias
		if lease and lease.acquired == true then
			loaded[alias] = true
			-- False means completed. Keeping the key matches vanilla's state
			-- shape without making its pending loop unload the same lease twice.
			pending[alias] = false
			report.mapped = report.mapped + 1
		end
	end

	return report
end

function M.claim_teardown(previewer)
	if previewer._cwv_preview_teardown_done then return false end
	previewer._cwv_preview_teardown_done = true
	return true
end

function M.install(policy)
	local mod = get_mod("character_weapon_variants")
	if mod._cwv_mod_unit_preview_installed then return end
	mod._cwv_mod_unit_preview_installed = true
	local policies = type(policy) == "table" and type(policy[1]) == "table"
		and policy or { policy }
	local function alias_collected(one_policy, package_names)
		if one_policy and one_policy.alias_collected_packages then
			one_policy.alias_collected_packages(package_names)
		end
	end

	-- ProfileSynchronizer calls this collector before loading its inventory
	-- package maps. Custom Greataxe units are resident through CWV's master
	-- bundle but are not standalone global packages, so substitute only the
	-- collector's package identities. The item/spawn unit data stays custom.
	assert(WeaponUtils and type(WeaponUtils.get_weapon_packages) == "function",
		"CWV Greataxe package bridge requires WeaponUtils.get_weapon_packages")
	mod:hook(WeaponUtils, "get_weapon_packages", function(func, ...)
		local package_names = func(...)
		for _, one_policy in ipairs(policies) do
			alias_collected(one_policy, package_names)
		end
		return package_names
	end)

	local function alias_for(name)
		for _, one_policy in ipairs(policies) do
			local alias = one_policy and one_policy.preview_package_alias
				and one_policy.preview_package_alias(name) or nil
			if alias then return alias end
		end
		return nil
	end

	local custom_path_count = 0
	for _, one_policy in ipairs(policies) do
		for _, model in ipairs((one_policy and one_policy.MODELS) or {}) do
			if model.right_hand_unit then custom_path_count = custom_path_count + 2 end
		end
	end

	local function unit_resident(name)
		local ok, resident = pcall(Application.can_get, "unit", name)
		return ok and resident == true
	end

	local warned = {}
	local function warn_once(name, fallback)
		if warned[name] then return end
		warned[name] = true
		mod:error("[cwv:597] custom preview unit is not resident; using vanilla fallback unit=%s fallback=%s",
			tostring(name), tostring(fallback))
	end

	-- Character/inventory preview. The caller stores the same package_names
	-- table in `_item_info_by_slot`, so replacing the custom package name also
	-- makes polling and unload use the real vanilla reference. Spawn data keeps
	-- the custom unit while resident, and is changed to the fallback if not.
	mod:hook("HeroPreviewer", "_load_packages", function(func, self, package_names)
		for index, package_name in ipairs(package_names) do
			local alias = alias_for(package_name)
			if alias then
				package_names[index] = alias
				if not unit_resident(package_name) then
					warn_once(package_name, alias)
					for _, slot_data in pairs(self._item_info_by_slot or {}) do
						for _, spawn in ipairs(slot_data.spawn_data or {}) do
							if spawn.unit_name == package_name then
								spawn.unit_name = alias
							end
						end
					end
				end
			end
		end
		return func(self, package_names)
	end)

	-- Athanor/illusion item preview. Load the vanilla package using the
	-- previewer's own reference name, but acknowledge completion under the
	-- requested custom unit name because `_packages_loaded` keys by unit_name.
	mod:hook("LootItemUnitPreviewer", "load_package", function(func, self, package_name)
		local alias = alias_for(package_name)
		if not alias then return func(self, package_name) end
		if self._packages_to_load[package_name] ~= nil then return end

		self._cwv_preview_teardown_done = nil
		self._packages_to_load[package_name] = true
		self._cwv_preview_package_aliases = self._cwv_preview_package_aliases or {}
		self._cwv_preview_package_aliases[package_name] = alias
		if not unit_resident(package_name) then
			self._cwv_preview_unit_fallbacks = self._cwv_preview_unit_fallbacks or {}
			self._cwv_preview_unit_fallbacks[package_name] = alias
			warn_once(package_name, alias)
		end

		local reference_name = "LootItemUnitPreviewer"
		if self._unique_id then reference_name = reference_name .. tostring(self._unique_id) end
		self._cwv_preview_alias_leases = self._cwv_preview_alias_leases or {}
		local lease = self._cwv_preview_alias_leases[alias]
		if not lease then
			lease = { acquired = false, complete = false, customs = {} }
			self._cwv_preview_alias_leases[alias] = lease
		end
		lease.customs[package_name] = true

		if lease.complete then
			self:_on_load_complete(package_name)
			return
		end
		if lease.acquired then return end

		local function complete_alias_load()
			lease.complete = true
			if self._cwv_preview_teardown_done then return end
			for custom in pairs(lease.customs) do
				if self._packages_to_load and _has_key(self._packages_to_load, custom) then
					self:_on_load_complete(custom)
				end
			end
		end
		local ok, err = pcall(Managers.package.load, Managers.package, alias,
			reference_name, complete_alias_load, true)
		if not ok then
			self._cwv_preview_alias_leases[alias] = nil
			self._cwv_preview_package_aliases[package_name] = nil
			self._packages_to_load[package_name] = nil
			error(err)
		end
		lease.acquired = true
		M._stats.alias_leases = M._stats.alias_leases + 1
	end)

	-- Vanilla would unload the custom key it recorded in `_loaded_packages`.
	-- Translate it back to the real borrowed package before delegating.
	mod:hook("LootItemUnitPreviewer", "_unload_packages", function(func, self)
		if not M.claim_teardown(self) then
			M._stats.teardown_repeats_ignored = M._stats.teardown_repeats_ignored + 1
			return
		end

		local reference_name = "LootItemUnitPreviewer"
		if self._unique_id then reference_name = reference_name .. tostring(self._unique_id) end
		M.reconcile_for_unload(self, alias_for, function(alias, custom)
			local ok, err = pcall(Managers.package.load, Managers.package, alias,
				reference_name, nil, false)
			if ok then
				M._stats.alias_leases = M._stats.alias_leases + 1
				M._stats.bypassed_leases_repaired = M._stats.bypassed_leases_repaired + 1
				pcall(printf, "[cwv:604-preview] repaired bypassed lease: custom=%s alias=%s ref=%s",
					tostring(custom), tostring(alias), tostring(reference_name))
				return true
			end
			M._stats.teardown_repair_failures = M._stats.teardown_repair_failures + 1
			pcall(printf, "[cwv:604-preview] lease repair failed: custom=%s alias=%s error=%s",
				tostring(custom), tostring(alias), tostring(err))
			return false
		end)
		local result = func(self)
		M._stats.teardowns = M._stats.teardowns + 1
		self._cwv_preview_package_aliases = nil
		self._cwv_preview_alias_leases = nil
		self._cwv_preview_unit_fallbacks = nil
		return result
	end)

	pcall(printf, "[cwv:604-preview] applied: policies=%d custom_paths=%d",
		#policies, custom_path_count)
	mod:command("verify_cwv_preview_bridge",
		"Report CWV custom-preview package lease and teardown state.", function()
		local stats = M._stats
		mod:echo("CWV preview bridge | installed=true | policies=%d | custom_paths=%d | PASS",
			#policies, custom_path_count)
		mod:echo("leases=%d | bypass_repairs=%d | teardowns=%d | repeated_teardowns=%d | repair_failures=%d | %s",
			stats.alias_leases, stats.bypassed_leases_repaired, stats.teardowns,
			stats.teardown_repeats_ignored, stats.teardown_repair_failures,
			stats.teardown_repair_failures == 0 and "PASS" or "FAIL")
	end)
end

function M.apply_loot_fallbacks(previewer, spawn_data)
	local fallbacks = previewer and previewer._cwv_preview_unit_fallbacks
	if not fallbacks then return spawn_data end
	for _, spawn in ipairs(spawn_data or {}) do
		local fallback = fallbacks[spawn.unit_name]
		if fallback then spawn.unit_name = fallback end
	end
	return spawn_data
end

return M
