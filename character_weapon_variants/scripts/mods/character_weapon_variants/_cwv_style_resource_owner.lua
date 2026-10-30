-- _cwv_style_resource_owner.lua -- private acquisition and observed residency.
-- Extracted without policy changes from _cwv_combat_styles.new_resource_acquirer.
-- FAMILIES is the actual authored table, passed by value at the existing entry
-- call site. PackageManager remains lazy; arbitrary UI resources never enter it.
-- Owned by: character_weapon_variants.lua. Consumed via its style-install handoff.
return function(families, package_manager)
	local allowlist, held, REFERENCE = {}, {}, "cwv_combat_styles"
	for _, family in pairs(families) do
		for _, style in pairs(family.styles) do
			if type(style.resource) == "string" then allowlist[style.resource] = true end
		end
	end
	local function manager()
		return type(package_manager) == "function" and package_manager() or nil
	end
	local function acquire(path, callback)
		if not allowlist[path] then return false, "resource is not authored" end
		local packages = manager()
		if not packages then return false, "package manager unavailable" end
		if held[path] then
			local loaded = false
			pcall(function() loaded = packages:has_loaded(path, REFERENCE) and true or false end)
			callback(loaded, loaded and nil or "held resource lost")
			return loaded
		end
		held[path] = true
		packages:load(path, REFERENCE, function()
			local loaded = false
			pcall(function() loaded = packages:has_loaded(path, REFERENCE) and true or false end)
			callback(loaded, loaded and nil or "resource completion was not resident")
		end, true, true)
		return true
	end
	local function resident(path)
		if not allowlist[path] then return nil end
		local packages = manager()
		if type(packages) ~= "table" or type(packages.has_loaded) ~= "function" then
			return nil
		end
		local ok, loaded = pcall(packages.has_loaded, packages, path)
		if not ok then return nil end
		return loaded == true
	end
	return acquire, resident
end
