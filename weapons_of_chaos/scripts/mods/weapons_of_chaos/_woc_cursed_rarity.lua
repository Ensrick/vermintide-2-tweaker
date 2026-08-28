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

local function raw_clone(source)
	local clone = {}
	for key, value in next, source do
		rawset(clone, key, value)
	end
	return clone
end

local function dense_array_length(array)
	local count = 0
	local maximum = 0
	for key in next, array do
		if type(key) == "number" then
			if key <= 0 or key ~= key or key == math.huge or key % 1 ~= 0 then
				return nil, "numeric_key_invalid"
			end
			count = count + 1
			if key > maximum then maximum = key end
		end
	end
	if count ~= maximum then return nil, "numeric_side_sparse" end
	return maximum, nil
end

local function append_unique(array, length, value)
	for index = 1, length do
		if rawget(array, index) == value then return end
	end
	rawset(array, length + 1, value)
end

local function optional_table(owner, key)
	local value = rawget(owner, key)
	if value == nil then return {}, true end
	if type(value) ~= "table" then return nil, false end
	return value, false
end

local function call_registration(fn, ...)
	local ok, index, _, reason = pcall(fn, ...)
	if not ok then return nil, "helper_error" end
	if type(index) ~= "number" then
		return nil, reason or "registration_rejected"
	end
	return index, nil
end

local function prepare(env)
	if type(env) ~= "table" then return nil, "env_unavailable" end
	local required = {
		"Colors", "UISettings", "RaritySettings", "RarityIndex",
		"ORDER_RARITY", "NetworkLookup", "NetworkLookupLib",
	}
	local values = {}
	for _, name in ipairs(required) do
		local value = rawget(env, name)
		if type(value) ~= "table" then
			return nil, name .. "_unavailable"
		end
		values[name] = value
	end

	local color_definitions = rawget(values.Colors, "color_definitions")
	local rarities = rawget(values.NetworkLookup, "rarities")
	if type(color_definitions) ~= "table" or type(rarities) ~= "table" then
		return nil, "nested_tables_unavailable"
	end
	local register = rawget(values.NetworkLookupLib, "register")
	local register_named = rawget(values.NetworkLookupLib, "register_named")
	if type(register) ~= "function" or type(register_named) ~= "function" then
		return nil, "network_lookup_helper_invalid"
	end

	local item_rarity_order, new_order = optional_table(values.UISettings,
		"item_rarity_order")
	if not item_rarity_order then return nil, "item_rarity_order_invalid" end
	local item_rarities, new_rarities = optional_table(values.UISettings,
		"item_rarities")
	if not item_rarities then return nil, "item_rarities_invalid" end
	local item_rarity_textures, new_textures = optional_table(values.UISettings,
		"item_rarity_textures")
	if not item_rarity_textures then return nil, "item_rarity_textures_invalid" end
	local item_rarities_length, array_reason = dense_array_length(item_rarities)
	if not item_rarities_length then
		return nil, "item_rarities_" .. array_reason
	end

	-- Validate both bidirectional registries against disposable copies before
	-- changing any live engine table. Once these plans pass, the raw presentation
	-- writes below cannot observe a partially registered Cursed rarity.
	local order_copy = raw_clone(values.ORDER_RARITY)
	local order_index, order_reason = call_registration(register, order_copy, M.NAME)
	if order_reason then return nil, "order_rarity_" .. order_reason end
	local rarity_copy = raw_clone(rarities)
	local _, rarity_reason = call_registration(register_named,
		{ rarities = rarity_copy }, "rarities", M.NAME)
	if rarity_reason then return nil, "network_rarities_" .. rarity_reason end

	return {
		values = values,
		color_definitions = color_definitions,
		item_rarity_order = item_rarity_order,
		item_rarities = item_rarities,
		item_rarities_length = item_rarities_length,
		item_rarity_textures = item_rarity_textures,
		new_order = new_order,
		new_rarities = new_rarities,
		new_textures = new_textures,
		order_index = order_index,
		register_named = register_named,
	}, nil
end

function M.install(env)
	local plan, reason = prepare(env)
	if not plan then return false, reason end
	local values = plan.values
	local rarity_index, rarity_reason = call_registration(
		plan.register_named, values.NetworkLookup, "rarities", M.NAME)
	if not rarity_index then return false, "network_rarities_" .. rarity_reason end
	rawset(values.ORDER_RARITY, plan.order_index, M.NAME)
	rawset(values.ORDER_RARITY, M.NAME, plan.order_index)

	local color = copy_color(M.COLOR)
	if rawget(plan.color_definitions, M.NAME) == nil then
		rawset(plan.color_definitions, M.NAME, copy_color(color))
	end

	if plan.new_order then
		rawset(values.UISettings, "item_rarity_order", plan.item_rarity_order)
	end
	if plan.new_rarities then
		rawset(values.UISettings, "item_rarities", plan.item_rarities)
	end
	if plan.new_textures then
		rawset(values.UISettings, "item_rarity_textures", plan.item_rarity_textures)
	end
	rawset(plan.item_rarity_order, M.NAME, M.ORDER)
	append_unique(plan.item_rarities, plan.item_rarities_length, M.NAME)
	rawset(plan.item_rarity_textures, M.NAME, M.TEXTURE)

	local brightest = math.max(color[2], color[3], color[4], 1)
	local multiplier = 255 / brightest
	rawset(values.RaritySettings, M.NAME, {
		display_name = M.DISPLAY_KEY,
		name = M.NAME,
		order = M.ORDER,
		color = copy_color(color),
		frame_color = {
			color[1], color[2] * multiplier,
			color[3] * multiplier, color[4] * multiplier,
		},
	})
	rawset(values.RarityIndex, M.NAME, M.ORDER)
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
