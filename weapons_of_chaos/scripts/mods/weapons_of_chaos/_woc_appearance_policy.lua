-- Pure appearance/package policy for the authored Blightreaper unit.
-- Runtime hooks live in `_woc_mod_unit_preview`; tests can load this file
-- without Stingray globals.
local M = {}

M.UNIT_1P = "units/woc_blightreaper/blightreaper"
M.UNIT_3P = M.UNIT_1P .. "_3p"
M.VANILLA_1P = "units/weapons/player/wpn_emp_sword_02_t1/wpn_emp_sword_02_t1"
M.VANILLA_3P = M.VANILLA_1P .. "_3p"

function M.preview_package_alias(name)
	if name == M.UNIT_1P then return M.VANILLA_1P end
	if name == M.UNIT_3P then return M.VANILLA_3P end
	return nil
end

function M.alias_collected_packages(names)
	if type(names) ~= "table" then return names, 0 end
	local count = 0
	for i = 1, #names do
		local alias = M.preview_package_alias(names[i])
		if alias then names[i], count = alias, count + 1 end
	end
	return names, count
end

function M.network_package_aliases()
	return {
		[M.UNIT_1P] = M.VANILLA_1P,
		[M.UNIT_3P] = M.VANILLA_3P,
	}
end

-- Install only forward name -> vanilla index aliases. The numeric reverse
-- lookup remains vanilla, so a peer that lacks WOC never decodes a custom path.
function M.install_network_package_aliases(lookup)
	if type(lookup) ~= "table" then return 0 end
	local count = 0
	for custom, vanilla in pairs(M.network_package_aliases()) do
		local index = rawget(lookup, vanilla)
		if type(index) == "number" then
			rawset(lookup, custom, index)
			count = count + 1
		end
	end
	return count
end

return M
