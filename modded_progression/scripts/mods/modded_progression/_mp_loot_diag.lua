-- Bounded, observation-only loot diagnostics for issue #607.
--
-- The native chest roll is produced by PlayFab CloudScript, not Lua. This
-- helper records only the already-returned callback payload observed in the
-- MODDED realm; it never opens a chest, queues a request, or mutates backend
-- state. Official-realm observation is structurally impossible for this mod:
-- unapproved Workshop mods never load there (decompile
-- scripts/managers/mod/mod_manager.lua:275 passes
-- `not script_data["eac-untrusted"]` to Mod.start_scan, and the realm flag is
-- fixed at launch, foundation/scripts/util/application_parameter.lua:150), so
-- the capture gate requires eac_untrusted == true - the only realm where this
-- code can exist to observe loot delivery at all.

local M = {}

M.SCHEMA = 1
M.MAX_RECORDS = 12
M.MAX_ITEMS = 6
M.MAX_RARITIES = 10
M.ACTIVE = true -- retire by setting false once #607's contracts are captured

-- Modded realm only (eac_untrusted == true), fail-closed on nil: the flag is
-- always a boolean once application_parameter.lua:150 runs, so a nil here
-- means we were called before realm state existed and must not capture.
function M.should_capture(eac_untrusted, active)
    if active == nil then active = M.ACTIVE end
    return active == true and eac_untrusted == true
end

local function bounded_string(value, limit)
    local text = tostring(value or "unknown")
    text = text:gsub("[^%w_%-%.]", "_")
    return text:sub(1, limit or 96)
end

local function count_table(value)
    local n = 0
    if type(value) == "table" then for _ in pairs(value) do n = n + 1 end end
    return n
end

local function summarize_rarity_row(row)
    local out = {}
    if type(row) ~= "table" then return out end
    for rarity, chance in pairs(row) do
        if type(chance) == "table" then
            rarity = rawget(chance, "rarity")
            chance = rawget(chance, "chance")
        end
        if type(rarity) == "string" and type(chance) == "number" then
            out[#out + 1] = { rarity = bounded_string(rarity, 32), chance = chance }
        end
    end
    table.sort(out, function(a, b) return a.rarity < b.rarity end)
    while #out > M.MAX_RARITIES do table.remove(out) end
    return out
end

local function summarize_item(item)
    local custom = type(item) == "table" and item.CustomData or nil
    return {
        item_key = bounded_string(type(item) == "table" and item.ItemId, 96),
        rarity = bounded_string(type(custom) == "table" and custom.rarity
            or type(item) == "table" and item.rarity, 32),
        power = tonumber(type(custom) == "table" and custom.power_level
            or type(item) == "table" and item.power_level) or 0,
        has_properties = type(custom) == "table" and type(custom.properties) == "string"
            and #custom.properties > 2 or false,
        has_traits = type(custom) == "table" and type(custom.traits) == "string"
            and #custom.traits > 2 or false,
        has_skin = type(custom) == "table" and type(custom.skin) == "string"
            and custom.skin ~= "" or false,
    }
end

function M.empty()
    return { schema = M.SCHEMA, serial = 0, records = {} }
end

local function bounded_count(value)
    return math.max(0, math.min(1000, math.floor(tonumber(value) or 0)))
end

local function bounded_serial(value)
    return math.max(0, math.min(2147483646, math.floor(tonumber(value) or 0)))
end

local function normalize_record(source)
    source = type(source) == "table" and source or {}
    local items = {}
    local source_items = type(source.items) == "table" and source.items or {}
    for i = 1, math.min(#source_items, M.MAX_ITEMS) do
        local item = type(source_items[i]) == "table" and source_items[i] or {}
        items[i] = {
            item_key = bounded_string(item.item_key, 96),
            rarity = bounded_string(item.rarity, 32),
            power = tonumber(item.power) or 0,
            has_properties = item.has_properties == true,
            has_traits = item.has_traits == true,
            has_skin = item.has_skin == true,
        }
    end
    return {
        serial = bounded_serial(source.serial),
        captured_at = math.max(0, math.floor(tonumber(source.captured_at) or 0)),
        chest_key = bounded_string(source.chest_key, 96),
        hero_name = bounded_string(source.hero_name, 48),
        game_mode = bounded_string(source.game_mode, 32),
        amount = math.max(1, math.min(10, math.floor(tonumber(source.amount) or 1))),
        items = items,
        item_count = bounded_count(source.item_count),
        truncated_items = bounded_count(source.truncated_items),
        rarity_row = summarize_rarity_row(source.rarity_row),
        unlocked_weapon_skins = bounded_count(source.unlocked_weapon_skins),
        new_weapon_skin_rewards = bounded_count(source.new_weapon_skin_rewards),
        new_cosmetics = bounded_count(source.new_cosmetics),
        new_weapon_poses = bounded_count(source.new_weapon_poses),
        consumed_remaining = tonumber(source.consumed_remaining),
        returned_chest_inventory = source.returned_chest_inventory == true,
    }
end

function M.normalize(ledger)
    ledger = type(ledger) == "table" and ledger or {}
    local records = type(ledger.records) == "table" and ledger.records or {}
    local out = {
        schema = M.SCHEMA,
        serial = bounded_serial(ledger.serial),
        records = {},
    }
    local first = math.max(1, #records - M.MAX_RECORDS + 1)
    for i = first, #records do
        out.records[#out.records + 1] = normalize_record(records[i])
    end
    return out
end

function M.is_mission_chest(chest_key)
    return type(chest_key) == "string"
        and chest_key:match("^loot_chest_0[1-4]_0[1-6]$") ~= nil
end

function M.capture(ledger, context, result, captured_at)
    local next_ledger = M.normalize(ledger)
    local function_result = type(result) == "table" and result.FunctionResult or nil
    if type(function_result) ~= "table" then return nil, "missing FunctionResult" end

    local items = type(function_result.items) == "table" and function_result.items or {}
    local record_items = {}
    for i = 1, math.min(#items, M.MAX_ITEMS) do
        record_items[i] = summarize_item(items[i])
    end

    next_ledger.serial = next_ledger.serial + 1
    local consumed = type(function_result.consumed_chest) == "table"
        and function_result.consumed_chest or {}
    local record = {
        serial = next_ledger.serial,
        captured_at = math.max(0, math.floor(tonumber(captured_at) or 0)),
        chest_key = bounded_string(context and context.chest_key, 96),
        hero_name = bounded_string(context and context.hero_name, 48),
        game_mode = bounded_string(context and context.game_mode, 32),
        amount = math.max(1, math.min(10, math.floor(tonumber(context and context.amount) or 1))),
        items = record_items,
        item_count = #items,
        truncated_items = math.max(0, #items - #record_items),
        rarity_row = summarize_rarity_row(context and context.rarity_row),
        unlocked_weapon_skins = count_table(function_result.unlocked_weapon_skins),
        new_weapon_skin_rewards = count_table(function_result.new_weapon_skin_rewards),
        new_cosmetics = count_table(function_result.new_cosmetics),
        new_weapon_poses = count_table(function_result.new_unlocked_weapon_poses),
        consumed_remaining = tonumber(consumed.RemainingUses),
        returned_chest_inventory = function_result.chest_inventory ~= nil,
    }
    next_ledger.records[#next_ledger.records + 1] = record
    while #next_ledger.records > M.MAX_RECORDS do table.remove(next_ledger.records, 1) end
    return next_ledger, record
end

function M.rarity_counts(record)
    local counts = {}
    for _, item in ipairs(type(record) == "table" and record.items or {}) do
        local rarity = item.rarity or "unknown"
        counts[rarity] = (counts[rarity] or 0) + 1
    end
    local keys = {}
    for key in pairs(counts) do keys[#keys + 1] = key end
    table.sort(keys)
    local parts = {}
    for i, key in ipairs(keys) do parts[i] = key .. "=" .. counts[key] end
    return table.concat(parts, ",")
end

-- Pure catalogue census used by the status command in either realm. It reads
-- only static item definitions and deliberately does not consult inventory.
function M.catalogue_facts(item_master_list)
    local facts = { total = 0, gear = 0, dlc_gated = 0, by_slot = {} }
    for _, item in pairs(type(item_master_list) == "table" and item_master_list or {}) do
        if type(item) == "table" then
            facts.total = facts.total + 1
            -- ItemMasterList rows may inherit a metatable that raises on an
            -- absent key; diagnostics must never turn catalogue drift into a
            -- user-facing command failure.
            local slot = rawget(item, "slot_type")
            if slot == "melee" or slot == "ranged" or slot == "necklace"
                    or slot == "ring" or slot == "trinket" then
                facts.gear = facts.gear + 1
                facts.by_slot[slot] = (facts.by_slot[slot] or 0) + 1
                if rawget(item, "required_dlc") then
                    facts.dlc_gated = facts.dlc_gated + 1
                end
            end
        end
    end
    return facts
end

return M
