--[[
	_ba_attack_labeler.lua  (Bestiary & Armory feature, migrated into gut)

	Derive a weapon's attack chain + human labels purely from its
	`Weapons[template].actions` data, replacing the original Armory's
	hand-authored `armory_wanted_attack_list.lua`.

	Melee: classify action_one sub-actions by name (light* / heavy*|charged* /
	push). Original Armory already auto-generated melee labels ("Light Attack 1",
	"Heavy Attack 2", "Push Attack"), so we do the same.

	Ranged: action_one fire-modes are "ranged", action_two hold/zoom modes are
	"alternate". Labels use a 3-tier ladder: loc key -> prettified action name ->
	positional generic.
]]

local M = {}

local function prettify(name)
	local s = string.gsub(name, "_", " ")
	s = string.gsub(s, "(%a)([%w]*)", function(a, b) return string.upper(a) .. b end)
	return s
end

-- 3-tier label ladder for an action.
local function ranged_label(action_name, idx)
	local loc_key = "item_attack_" .. action_name
	local loc = Localize(loc_key)
	if loc and loc ~= loc_key and not string.find(loc, "^<") then
		return loc
	end
	if action_name == "default" then
		return "Ranged Attack " .. tostring(idx)
	end
	return prettify(action_name)
end

-- Returns { light = {names}, heavy = {names}, push = name|nil }
function M.melee_chains(template)
	local light, heavy, push = {}, {}, nil
	local actions = template and template.actions and template.actions.action_one

	if actions then
		for name, _ in pairs(actions) do
			if name == "push" then
				push = name
			elseif string.find(name, "heavy") or string.find(name, "charged") then
				heavy[#heavy + 1] = name
			elseif string.find(name, "light") then
				light[#light + 1] = name
			end
		end
	end

	table.sort(light)
	table.sort(heavy)
	return { light = light, heavy = heavy, push = push }
end

-- Returns { ranged = {{name,label}...}, alternate = {{name,label}...} }
function M.ranged_chains(template)
	local ranged, alternate = {}, {}

	local a1 = template and template.actions and template.actions.action_one
	if a1 then
		local names = {}
		for name, _ in pairs(a1) do
			if name ~= "action_wield" and name ~= "reload" then
				names[#names + 1] = name
			end
		end
		table.sort(names)
		for i, name in ipairs(names) do
			ranged[#ranged + 1] = { name, ranged_label(name, i) }
		end
	end

	local a2 = template and template.actions and template.actions.action_two
	if a2 then
		local names = {}
		for name, _ in pairs(a2) do
			if name ~= "action_wield" then
				names[#names + 1] = name
			end
		end
		table.sort(names)
		for i, name in ipairs(names) do
			alternate[#alternate + 1] = { name, ranged_label(name, i) }
		end
	end

	return { ranged = ranged, alternate = alternate }
end

return M
