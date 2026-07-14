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

function M.install(policy)
	local mod = get_mod("character_weapon_variants")
	if mod._cwv_mod_unit_preview_installed then return end
	mod._cwv_mod_unit_preview_installed = true

	-- ProfileSynchronizer calls this collector before loading its inventory
	-- package maps. Custom Greataxe units are resident through CWV's master
	-- bundle but are not standalone global packages, so substitute only the
	-- collector's package identities. The item/spawn unit data stays custom.
	assert(WeaponUtils and type(WeaponUtils.get_weapon_packages) == "function",
		"CWV Greataxe package bridge requires WeaponUtils.get_weapon_packages")
	mod:hook(WeaponUtils, "get_weapon_packages", function(func, ...)
		local package_names = func(...)
		if policy and policy.alias_collected_packages then
			policy.alias_collected_packages(package_names)
		end
		return package_names
	end)

	local function alias_for(name)
		return policy and policy.preview_package_alias
			and policy.preview_package_alias(name) or nil
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
		local cb = callback(self, "_on_load_complete", package_name)
		Managers.package:load(alias, reference_name, cb, true)
	end)

	-- Vanilla would unload the custom key it recorded in `_loaded_packages`.
	-- Translate it back to the real borrowed package before delegating.
	mod:hook("LootItemUnitPreviewer", "_unload_packages", function(func, self)
		for custom, alias in pairs(self._cwv_preview_package_aliases or {}) do
			if self._loaded_packages and self._loaded_packages[custom] then
				self._loaded_packages[custom] = nil
				self._loaded_packages[alias] = true
			end
			if self._packages_to_load and self._packages_to_load[custom] then
				self._packages_to_load[custom] = nil
				self._packages_to_load[alias] = true
			end
		end
		local result = func(self)
		self._cwv_preview_package_aliases = nil
		self._cwv_preview_unit_fallbacks = nil
		return result
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
