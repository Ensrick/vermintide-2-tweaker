-- Bounded, observation-only loot diagnostics for issue #607.
--
-- The native mission award and chest roll are produced by PlayFab CloudScript,
-- not Lua. A successful FunctionResult therefore cannot be the diagnostic's
-- trigger in the modded realm: the request is normally rejected at the EAC
-- boundary first. This pure helper owns the bounded event ledger used by the
-- runtime adapters at mission-end, request enqueue, chest-open, backend
-- rejection, callback success, and MP's local inventory seam. It never opens a
-- chest, queues a request, grants an item, or mutates a backend mirror.
--
-- Owned by: _mp_loot_diag_runtime.lua. Consumed via: one mod:dofile installer.

local M = {}

M.SCHEMA = 2
M.MAX_RECORDS = 12
M.MAX_ITEMS = 6
M.MAX_RARITIES = 10
M.ACTIVE = true -- retire by setting false once #607's contracts are captured
M.LOCAL_CONTAINER_AWARD_IMPLEMENTED = false
M.LOCAL_CONTAINER_OPEN_IMPLEMENTED = false

M.EVENTS = {
    end_level = true,
    pre_request = true,
    open = true,
    rejection = true,
    success = true,
    local_ledger = true,
}

M.REQUEST_FLOWS = {
    generateEndOfLevelLoot = "end_level",
    generateLootChestRewards = "open",
}

-- Modded realm only (eac_untrusted == true), fail-closed on nil: the flag is
-- always a boolean once application_parameter.lua:150 runs, so a nil here
-- means we were called before realm state existed and must not capture.
function M.should_capture(eac_untrusted, active)
    if active == nil then active = M.ACTIVE end
    return active == true and eac_untrusted == true
end

function M.request_flow(request_name)
    return M.REQUEST_FLOWS[request_name]
end

function M.is_target_request(request_name)
    return M.request_flow(request_name) ~= nil
end

-- `PlayFabRequestQueue:enqueue` reports the request it actually accepted with a
-- local numeric id. Do not infer acceptance from the request arguments alone:
-- nil/zero/negative/string/non-finite return values are not enqueue evidence.
function M.is_positive_request_id(value)
    return type(value) == "number" and value == value
        and value > 0 and value < math.huge
end

function M.active_request_name(request_queue)
    local active = type(request_queue) == "table" and rawget(request_queue, "_active_entry") or nil
    local request = type(active) == "table" and rawget(active, "request") or nil
    local request_name = type(request) == "table" and rawget(request, "FunctionName") or nil
    return M.is_target_request(request_name) and request_name or nil
end

function M.rejection_reason(request_queue)
    local active = type(request_queue) == "table" and rawget(request_queue, "_active_entry") or nil
    if type(active) == "table" and rawget(active, "eac_challenge_success") == true then
        return "eac_failed_verification"
    end
    return "eac_unavailable"
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
    local event = bounded_string(source.event, 24)
    if not M.EVENTS[event] then
        -- Schema-1 rows were successful open callbacks and carried no event.
        event = source.item_count ~= nil and "success" or "local_ledger"
    end
    local request_name = bounded_string(source.request_name, 48)
    local flow = bounded_string(source.flow or M.request_flow(request_name), 24)
    return {
        serial = bounded_serial(source.serial),
        captured_at = math.max(0, math.floor(tonumber(source.captured_at) or 0)),
        event = event,
        flow = flow,
        request_name = request_name,
        request_id = bounded_serial(source.request_id),
        reason = bounded_string(source.reason, 64),
        backend = bounded_string(source.backend, 32),
        won = source.won == true,
        difficulty = bounded_string(source.difficulty, 32),
        level_key = bounded_string(source.level_key, 64),
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
        local_items = bounded_count(source.local_items),
        local_containers = bounded_count(source.local_containers),
        local_container_uses = bounded_count(source.local_container_uses),
        local_award_capable = source.local_award_capable == true,
        local_open_capable = source.local_open_capable == true,
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

function M.local_ledger_facts(inventory_store)
    local facts = {
        items = 0,
        containers = 0,
        container_uses = 0,
        award_capable = M.LOCAL_CONTAINER_AWARD_IMPLEMENTED,
        open_capable = M.LOCAL_CONTAINER_OPEN_IMPLEMENTED,
    }
    for _, item in pairs(type(inventory_store) == "table" and inventory_store or {}) do
        if type(item) == "table" then
            facts.items = facts.items + 1
            local item_key = rawget(item, "ItemId")
            if M.is_mission_chest(item_key) then
                facts.containers = facts.containers + 1
                local uses = tonumber(rawget(item, "RemainingUses"))
                if uses == nil then uses = 1 end
                facts.container_uses = facts.container_uses + math.max(0, math.floor(uses))
            end
        end
    end
    return facts
end

local function append_record(ledger, source)
    local next_ledger = M.normalize(ledger)
    next_ledger.serial = next_ledger.serial + 1
    source = type(source) == "table" and source or {}
    source.serial = next_ledger.serial
    local record = normalize_record(source)
    next_ledger.records[#next_ledger.records + 1] = record
    while #next_ledger.records > M.MAX_RECORDS do table.remove(next_ledger.records, 1) end
    return next_ledger, record
end

function M.record(ledger, event, context, captured_at)
    if M.EVENTS[event] ~= true then return nil, "unknown diagnostic event" end
    context = type(context) == "table" and context or {}
    return append_record(ledger, {
        event = event,
        captured_at = captured_at,
        flow = context.flow,
        request_name = context.request_name,
        request_id = context.request_id,
        reason = context.reason,
        backend = context.backend,
        won = context.won,
        difficulty = context.difficulty,
        level_key = context.level_key,
        chest_key = context.chest_key,
        hero_name = context.hero_name,
        game_mode = context.game_mode,
        amount = context.amount,
        local_items = context.local_items,
        local_containers = context.local_containers,
        local_container_uses = context.local_container_uses,
        local_award_capable = context.local_award_capable,
        local_open_capable = context.local_open_capable,
    })
end

function M.capture(ledger, context, result, captured_at)
    local function_result = type(result) == "table" and result.FunctionResult or nil
    if type(function_result) ~= "table" then return nil, "missing FunctionResult" end

    local items = type(function_result.items) == "table" and function_result.items or {}
    local record_items = {}
    for i = 1, math.min(#items, M.MAX_ITEMS) do
        record_items[i] = summarize_item(items[i])
    end

    local consumed = type(function_result.consumed_chest) == "table"
        and function_result.consumed_chest or {}
    local record = {
        event = "success",
        captured_at = math.max(0, math.floor(tonumber(captured_at) or 0)),
        flow = "open",
        request_name = "generateLootChestRewards",
        reason = "callback_success",
        backend = "native_callback",
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
    return append_record(ledger, record)
end

function M.diagnose(ledger)
    local normalized = M.normalize(ledger)
    local saw_end_level = false
    local saw_end_level_request = false
    local saw_open = false
    local saw_open_request = false
    local saw_local_ledger = false
    local latest_local_containers = 0

    for _, record in ipairs(normalized.records) do
        if record.event == "end_level" then saw_end_level = true end
        if record.event == "open" then saw_open = true end
        if record.event == "pre_request" and record.flow == "end_level" then
            saw_end_level_request = true
        elseif record.event == "pre_request" and record.flow == "open" then
            saw_open_request = true
        elseif record.event == "local_ledger" then
            saw_local_ledger = true
            latest_local_containers = record.local_containers
        end
    end

    if saw_end_level then
        if not saw_end_level_request then return "request_enqueue" end
        if not M.LOCAL_CONTAINER_AWARD_IMPLEMENTED then return "local_container_award" end
        if not saw_local_ledger then return "local_container_ledger" end
        if latest_local_containers < 1 then return "local_container_persistence" end
        if not M.LOCAL_CONTAINER_OPEN_IMPLEMENTED then return "local_chest_open" end
        return "local_loot_roll"
    end
    if saw_open then
        if not saw_open_request then return "open_request_enqueue" end
        if not M.LOCAL_CONTAINER_OPEN_IMPLEMENTED then return "local_chest_open" end
        return "local_loot_roll"
    end
    return "awaiting_mission_end"
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
