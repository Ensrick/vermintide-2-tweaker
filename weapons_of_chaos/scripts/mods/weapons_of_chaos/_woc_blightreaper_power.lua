-- Fixed-power and Chaos Wastes identity policy for Blightreaper.
--
-- Local WOC-capable peers keep the authored Cursed identity. Chaos Wastes
-- serialization always uses the vanilla elf-sword Deus key and unique rarity,
-- then carries one forward-compatible token which vanilla's deserializer
-- ignores. A WOC peer consumes that token after vanilla has created the item.

local M = {}

M.ITEM_KEY = "woc_blightreaper"
M.BASE_ITEM = "es_1h_sword"
M.VANILLA_DEUS_KEY = "deus_es_1h_sword"
M.NORMAL_POWER = 600
M.DEUS_POWER = 900
M.RARITY = "cursed"
M.WIRE_RARITY = "unique"
M.RELIC_MARKER = "woc_unique_relic"
M.SERIALIZATION_MARKER = "woc=blightreaper"

local function shallow_copy(source)
	local copy = {}
	for key, value in pairs(source) do copy[key] = value end
	return copy
end

local function marked(value)
	if type(value) ~= "table" then return false end
	local marker = rawget(value, M.RELIC_MARKER)
	return marker == true or marker == "true"
		or rawget(value, "woc_item_key") == M.ITEM_KEY
end

local function custom_data(item)
	if type(item.CustomData) ~= "table" then item.CustomData = {} end
	return item.CustomData
end

-- Classification deliberately ignores backend ids and deus_item_key. Deus
-- grants receive non-deterministic backend ids, while deus_es_1h_sword is also
-- used by ordinary vanilla swords. Only local WOC markers/data prove identity.
function M.is_relic(item)
	if type(item) ~= "table" then return false end
	return marked(item) or marked(rawget(item, "data"))
		or marked(rawget(item, "CustomData"))
		or rawget(item, "key") == M.ITEM_KEY
end

local function stamp_identity(item)
	item[M.RELIC_MARKER] = true
	item.woc_item_key = M.ITEM_KEY
	local custom = custom_data(item)
	custom[M.RELIC_MARKER] = "true"
	custom.woc_item_key = M.ITEM_KEY
	return custom
end

-- Mutates a proven local relic only. This never changes its backend id, item
-- key, definition pointer, properties, traits, or skin.
function M.stamp(item, in_deus)
	if not M.is_relic(item) then return false end
	local power = in_deus and M.DEUS_POWER or M.NORMAL_POWER
	local custom = stamp_identity(item)
	item.power_level = power
	item.rarity = M.RARITY
	custom.power_level = tostring(power)
	custom.rarity = M.RARITY
	if in_deus then item.deus_item_key = M.VANILLA_DEUS_KEY end
	return true
end

function M.stamp_local(item)
	return M.stamp(item, false)
end

function M.stamp_deus(item)
	return M.stamp(item, true)
end

-- Register only a private starting conversion alias. The mapped value remains
-- the vanilla Deus key; no custom DeusWeapons row is created or serialized.
function M.install_deus(item_master_list, starting_mapping, deus_weapons)
	if type(item_master_list) ~= "table" or type(starting_mapping) ~= "table"
			or type(deus_weapons) ~= "table" then
		return false, "deus_tables_unavailable"
	end
	if type(rawget(item_master_list, M.ITEM_KEY)) ~= "table" then
		return false, "owner_missing"
	end
	if type(rawget(deus_weapons, M.VANILLA_DEUS_KEY)) ~= "table" then
		return false, "donor_missing"
	end
	rawset(starting_mapping, M.ITEM_KEY, M.VANILLA_DEUS_KEY)
	return true
end

-- During Deus setup the standard backend row may still expose its vanilla
-- base key. Return a shadow which selects the private starting alias without
-- mutating the canonical backend item.
function M.setup_identity(item)
	if not M.is_relic(item) then return item end
	local shadow = shallow_copy(item)
	shadow.key = M.ITEM_KEY
	shadow.ItemId = M.ITEM_KEY
	return shadow
end

function M.with_setup_identity(item, callback, ...)
	if type(callback) ~= "function" then return nil end
	return callback(M.setup_identity(item), ...)
end

-- Sender-side shadow for DeusWeaponGeneration.serialize_weapon. Its only
-- network-visible identity is a vanilla key/rarity pair understood by peers
-- without WOC. The local item is never mutated.
function M.deus_wire_item(item)
	if not M.is_relic(item) then return item end
	local shadow = shallow_copy(item)
	shadow.key = M.BASE_ITEM
	shadow.ItemId = M.BASE_ITEM
	shadow.deus_item_key = M.VANILLA_DEUS_KEY
	shadow.power_level = M.DEUS_POWER
	shadow.rarity = M.WIRE_RARITY
	return shadow
end

function M.has_serialization_marker(serialized)
	if type(serialized) ~= "string" then return false end
	for token in serialized:gmatch("[^,]+") do
		if token == M.SERIALIZATION_MARKER then return true end
	end
	return false
end

-- Vanilla Chaos Wastes never generates a weapon above 700 power. The relic's
-- vanilla transport row is deliberately fixed at 900/unique, giving WOC peers
-- a source-backed recovery signature after a non-WOC authority has parsed and
-- reserialized the item (which necessarily drops the unknown woc= token).
function M.has_wire_signature(item)
	return type(item) == "table"
		and item.deus_item_key == M.VANILLA_DEUS_KEY
		and item.power_level == M.DEUS_POWER
		and (item.rarity == M.WIRE_RARITY or item.rarity == M.RARITY)
end

function M.append_serialization_marker(serialized)
	if type(serialized) ~= "string" then return serialized end
	if M.has_serialization_marker(serialized) then return serialized end
	if serialized == "" then return M.SERIALIZATION_MARKER end
	return serialized .. "," .. M.SERIALIZATION_MARKER
end

-- High-level adapter for a hook around vanilla serialize_weapon.
function M.serialize_deus_weapon(item, serializer)
	if type(serializer) ~= "function" then return nil end
	if not M.is_relic(item) then return serializer(item) end
	local serialized = serializer(M.deus_wire_item(item))
	return M.append_serialization_marker(serialized)
end

-- Restore the authored local definition after vanilla has safely parsed the
-- vanilla key and ignored the unknown woc= token. Random Deus backend ids are
-- intentionally left untouched.
function M.restore_deus_item(item, serialized, definition)
	if type(item) ~= "table" or not (M.has_serialization_marker(serialized)
			or M.has_wire_signature(item)) then
		return false
	end
	item[M.RELIC_MARKER] = true
	item.woc_item_key = M.ITEM_KEY
	item.key = M.ITEM_KEY
	if type(definition) == "table" then item.data = definition end
	return M.stamp_deus(item)
end

-- High-level adapter for a hook around vanilla deserialize_weapon.
function M.deserialize_deus_weapon(serialized, deserializer, definition)
	if type(deserializer) ~= "function" then return nil end
	local item = deserializer(serialized)
	M.restore_deus_item(item, serialized, definition)
	return item
end

-- Called before an upgrade/temper purchase is accepted. Cursed order also
-- closes the native comparison path, but identity blocking remains explicit
-- so a future rarity-table change cannot make this unique relic temperable.
function M.should_block_upgrade(item)
	return M.is_relic(item)
end

return M
