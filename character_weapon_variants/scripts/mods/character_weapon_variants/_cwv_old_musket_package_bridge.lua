-- Package-lifecycle bridge for the Old Musket's mod-bundled mesh.
--
-- The custom unit data is resident in CWV's master bundle, so its unit path
-- has no standalone package for PackageManager to load.  The .unit borrows a
-- material from the vanilla Empire Handgun, however, and that material is not
-- owned by CWV's bundle.  A request for the custom unit package must therefore
-- participate in the donor package's real lifecycle: preserve the caller's
-- reference name, callback, async mode and priority, but substitute the donor
-- package path.  Reporting the custom path as loaded without doing this lets
-- preview/world code spawn the mesh before its material exists, producing the
-- invisible / missing-material regression tracked by #474.
local M = {}

function M.new(policy)
	assert(type(policy) == "table", "Old Musket preview policy is required")
	assert(type(policy.UNIT) == "string", "Old Musket 1P unit is required")
	assert(type(policy.UNIT_3P) == "string", "Old Musket 3P unit is required")
	assert(type(policy.NETWORK_PACKAGE_ALIAS_1P) == "string", "Old Musket 1P donor is required")
	assert(type(policy.NETWORK_PACKAGE_ALIAS_3P) == "string", "Old Musket 3P donor is required")

	local aliases = {
		[policy.UNIT] = policy.NETWORK_PACKAGE_ALIAS_1P,
		[policy.UNIT_3P] = policy.NETWORK_PACKAGE_ALIAS_3P,
	}
	local bridge = {}

	function bridge.alias(package_name)
		return aliases[package_name]
	end

	function bridge.is_custom(package_name)
		return aliases[package_name] ~= nil
	end

	function bridge.has_pair(base_unit)
		return type(base_unit) == "string"
			and aliases[base_unit] ~= nil
			and aliases[base_unit .. "_3p"] ~= nil
	end

	function bridge.load(func, self, package_name, reference_name, callback, asynchronous, prioritize)
		return func(self, aliases[package_name] or package_name, reference_name,
			callback, asynchronous, prioritize)
	end

	function bridge.unload(func, self, package_name, reference_name)
		return func(self, aliases[package_name] or package_name, reference_name)
	end

	function bridge.has_loaded(func, self, package_name, reference_name)
		return func(self, aliases[package_name] or package_name, reference_name)
	end

	return bridge
end

return M
