-- Makes a bundled WOC unit safe on every vanilla preview surface. Previewers
-- ask Application.resource_package for the unit path, but Workshop units are
-- resident through WOC's master bundle rather than discoverable as standalone
-- global packages. Borrow a vanilla sword package lease while retaining the
-- authored unit in spawn data; fall back to the sword only if residency fails.
local M = {}

function M.install(policy)
	local mod = get_mod("WOC")
	if mod._woc_mod_unit_preview_installed then return end
	mod._woc_mod_unit_preview_installed = true

	local function alias_for(name)
		return policy.preview_package_alias(name)
	end
	local function resident(name)
		local ok, value = pcall(Application.can_get, "unit", name)
		return ok and value == true
	end
	local warned = {}
	local function warn_once(name, fallback)
		if warned[name] then return end
		warned[name] = true
		pcall(printf, "[WOC:613] custom unit not resident; preview fallback unit=%s fallback=%s",
			tostring(name), tostring(fallback))
	end

	-- ProfileSynchronizer treats collected unit paths as package identities.
	mod:hook(WeaponUtils, "get_weapon_packages", function(func, ...)
		local packages = func(...)
		policy.alias_collected_packages(packages)
		return packages
	end)

	local function load_character_packages(func, self, packages)
		for i, name in ipairs(packages or {}) do
			local alias = alias_for(name)
			if alias then
				packages[i] = alias
				if not resident(name) then
					warn_once(name, alias)
					for _, slot in pairs(self._item_info_by_slot or {}) do
						for _, spawn in ipairs(slot.spawn_data or {}) do
							if spawn.unit_name == name then spawn.unit_name = alias end
						end
					end
				end
			end
		end
		return func(self, packages)
	end
	mod:hook("HeroPreviewer", "_load_packages", load_character_packages)
	mod:hook("MenuWorldPreviewer", "_load_packages", load_character_packages)

	-- Athanor and illusion browser. One custom key owns one borrowed lease.
	mod:hook("LootItemUnitPreviewer", "load_package", function(func, self, name)
		local alias = alias_for(name)
		if not alias then return func(self, name) end
		if self._packages_to_load[name] ~= nil then return end
		self._packages_to_load[name] = true
		self._woc_preview_aliases = self._woc_preview_aliases or {}
		self._woc_preview_aliases[name] = alias
		if not resident(name) then
			self._woc_preview_fallbacks = self._woc_preview_fallbacks or {}
			self._woc_preview_fallbacks[name] = alias
			warn_once(name, alias)
		end
		local reference = "LootItemUnitPreviewer" .. tostring(self._unique_id or "")
		Managers.package:load(alias, reference, function()
			if self._packages_to_load and self._packages_to_load[name] ~= nil then
				self:_on_load_complete(name)
			end
		end, true)
	end)

	mod:hook("LootItemUnitPreviewer", "spawn_units", function(func, self, spawn_data)
		for _, spawn in ipairs(spawn_data or {}) do
			local fallback = self._woc_preview_fallbacks
				and self._woc_preview_fallbacks[spawn.unit_name]
			if fallback then spawn.unit_name = fallback end
		end
		return func(self, spawn_data)
	end)

	mod:hook("LootItemUnitPreviewer", "_unload_packages", function(func, self)
		local loaded = self._loaded_packages or {}
		local pending = self._packages_to_load or {}
		for custom, alias in pairs(self._woc_preview_aliases or {}) do
			if loaded[custom] ~= nil then loaded[custom], loaded[alias] = nil, true end
			if pending[custom] ~= nil then pending[custom], pending[alias] = nil, false end
		end
		local result = func(self)
		self._woc_preview_aliases = nil
		self._woc_preview_fallbacks = nil
		return result
	end)
end

return M
