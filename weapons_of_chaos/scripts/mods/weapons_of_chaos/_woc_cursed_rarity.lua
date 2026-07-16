-- WOC-owned Cursed rarity registration and presentation policy.
--
-- Local WOC peers render a real `cursed` rarity. Loadout transport uses the
-- boot-stable vanilla `promo` rarity; the same-mod identity sideband restores
-- Cursed presentation after vanilla decoding.

local M = {}

M.NAME = "cursed"
M.DISPLAY_KEY = "rarity_display_name_cursed"
M.ORDER = 7
M.COLOR = { 255, 48, 156, 84 }
M.TEXTURE = "icon_bg_cursed"
M.WIRE_RARITY = "promo"

local function copy_color(color)
	return { color[1], color[2], color[3], color[4] }
end

local function append_unique(array, value)
	if type(array) ~= "table" then return end
	for _, existing in ipairs(array) do
		if existing == value then return end
	end
	array[#array + 1] = value
end

function M.install(env)
	env = env or {}
	local required = {
		"Colors", "UISettings", "RaritySettings", "RarityIndex",
		"ORDER_RARITY", "NetworkLookup",
	}
	for _, name in ipairs(required) do
		if type(env[name]) ~= "table" then
			return false, name .. "_unavailable"
		end
	end
	if type(env.Colors.color_definitions) ~= "table"
			or type(env.NetworkLookup.rarities) ~= "table" then
		return false, "nested_tables_unavailable"
	end
	local color = copy_color(M.COLOR)
	local colors = env.Colors
	if type(colors) == "table" and type(colors.color_definitions) == "table"
			and rawget(colors.color_definitions, M.NAME) == nil then
		rawset(colors.color_definitions, M.NAME, copy_color(color))
	end

	local ui = env.UISettings
	if type(ui) == "table" then
		ui.item_rarity_order = ui.item_rarity_order or {}
		rawset(ui.item_rarity_order, M.NAME, M.ORDER)
		ui.item_rarities = ui.item_rarities or {}
		append_unique(ui.item_rarities, M.NAME)
		ui.item_rarity_textures = ui.item_rarity_textures or {}
		rawset(ui.item_rarity_textures, M.NAME, M.TEXTURE)
	end

	local rarity_settings = env.RaritySettings
	if type(rarity_settings) == "table" then
		local brightest = math.max(color[2], color[3], color[4], 1)
		local multiplier = 255 / brightest
		rawset(rarity_settings, M.NAME, {
			display_name = M.DISPLAY_KEY,
			name = M.NAME,
			order = M.ORDER,
			color = copy_color(color),
			frame_color = {
				color[1], color[2] * multiplier,
				color[3] * multiplier, color[4] * multiplier,
			},
		})
	end

	if type(env.RarityIndex) == "table" then
		rawset(env.RarityIndex, M.NAME, M.ORDER)
	end
	if type(env.ORDER_RARITY) == "table" and rawget(env.ORDER_RARITY, M.NAME) == nil then
		local index = #env.ORDER_RARITY + 1
		rawset(env.ORDER_RARITY, index, M.NAME)
		rawset(env.ORDER_RARITY, M.NAME, index)
	end
	local lookup = env.NetworkLookup and env.NetworkLookup.rarities
	if type(lookup) == "table" and rawget(lookup, M.NAME) == nil then
		local index = #lookup + 1
		rawset(lookup, index, M.NAME)
		rawset(lookup, M.NAME, index)
	end
	return true, "installed"
end

function M.is_cursed(item)
	return type(item) == "table" and item.rarity == M.NAME
end

function M.scrub_unknown_pool_rarities(base_pool, excludes)
	local removed = {}
	if type(base_pool) ~= "table" or type(excludes) ~= "table" then return removed end
	if excludes[M.NAME] ~= nil and base_pool[M.NAME] == nil then
		excludes[M.NAME] = nil
		removed[1] = M.NAME
	end
	return removed
end

return M
