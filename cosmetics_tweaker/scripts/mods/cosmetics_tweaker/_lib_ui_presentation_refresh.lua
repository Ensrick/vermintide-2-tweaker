-- _lib_ui_presentation_refresh.lua -- bounded cross-mod UI presentation invalidation ledger.
--
-- MASTER SOURCE: tools/shared_lib/_lib_ui_presentation_refresh.lua. Consumer
-- copies are synchronized by tools/shared_lib/sync-shared-libs.ps1. The ledger
-- carries local-process presentation invalidations only: no engine objects,
-- callbacks, custom resources, or network identities enter shared state.
--
-- Owned by: standalone UI-producing mods. Consumed via: mod:dofile.

local M = {}

M.SCHEMA = 1
M.DEFAULT_CAPACITY = 32
M.GLOBAL_KEY = "__vt2_tweaker_ui_presentation_refresh_v1"

local STRING_FIELDS = {
    kind = true,
    source = true,
    reason = true,
    career_name = true,
    slot_name = true,
    backend_id = true,
    item_key = true,
    skin_key = true,
}

local function bounded_capacity(value)
    value = math.floor(tonumber(value) or M.DEFAULT_CAPACITY)
    if value < 8 then return 8 end
    if value > 128 then return 128 end
    return value
end

local function bounded_string(value)
    if value == nil then return nil end
    value = tostring(value)
    if #value > 160 then value = value:sub(1, 160) end
    return value
end

local function copy_event(input, generation)
    if type(input) ~= "table" then return nil, "event-not-table" end
    if type(input.kind) ~= "string" or input.kind == "" then
        return nil, "kind-missing"
    end
    local row = { generation = generation }
    for key in pairs(STRING_FIELDS) do
        row[key] = bounded_string(input[key])
    end
    return row
end

local function valid_bus(bus)
    return type(bus) == "table"
        and bus.schema == M.SCHEMA
        and type(bus.generation) == "number"
        and type(bus.floor_generation) == "number"
        and type(bus.capacity) == "number"
        and type(bus.events) == "table"
end

-- Pure retained-card adapter used by Cosmetics after its authoritative
-- appearance commit. Resolve all fallible values before mutating content so a
-- localization failure leaves the prior vanilla card intact.
function M.refresh_item_card(content, item, inventory_icon, display_name,
        localize, rarity_textures)
    if type(content) ~= "table" or type(item) ~= "table"
            or type(item.data) ~= "table" or type(localize) ~= "function"
            or type(rarity_textures) ~= "table" then
        return false, "invalid-arguments"
    end
    if type(display_name) ~= "string" or display_name == ""
            or type(item.data.slot_type) ~= "string"
            or item.data.slot_type == ""
            or (inventory_icon ~= nil and type(inventory_icon) ~= "string") then
        return false, "invalid-presentation-data"
    end
    local ok_name, input_text = pcall(localize, display_name)
    local ok_slot, sub_title = pcall(localize, item.data.slot_type)
    if not ok_name or not ok_slot or type(input_text) ~= "string"
            or type(sub_title) ~= "string" then
        return false, "localize-failed"
    end

    local rarity = item.rarity or item.data.rarity
    local old_icon = content.icon_texture
    local new_icon = inventory_icon or "icons_placeholder"
    content.input_text = input_text
    content.sub_title = sub_title
    content.icon_texture = new_icon
    content.icon_bg = rarity_textures[rarity] or "icons_placeholder"
    content.item = item
    return true, old_icon, new_icon
end

-- Pure consumer policy. Consumers provide their own career and slot allowlist,
-- Unknown careers (including Pusfume) stay outside consumer ownership; pusfume-compat-reviewed
-- unknown profiles are ignored and never mutated.
-- fail open without assumptions about another mod's profile data.
function M.classify_loadout_event(row, expected_career, allowed_slots)
    if type(row) ~= "table" or row.kind ~= "loadout"
            or row.career_name ~= expected_career
            or type(allowed_slots) ~= "table"
            or not allowed_slots[row.slot_name]
            or type(row.item_key) ~= "string" or row.item_key == "" then
        return nil
    end
    return row.slot_name, row.item_key
end

-- A fallback publisher may emit only when an inner provider did not advance
-- the shared generation during the same synchronous mutation.
function M.generation_unchanged(before_generation, after_generation)
    return type(before_generation) == "number"
        and type(after_generation) == "number"
        and before_generation == after_generation
end

function M.attach(root, owner, requested_capacity)
    if type(root) ~= "table" then return nil, "root-not-table" end
    owner = bounded_string(owner)
    if not owner or owner == "" then return nil, "owner-missing" end

    local key = M.GLOBAL_KEY
    local bus = rawget(root, key)
    if bus ~= nil and not valid_bus(bus) then
        return nil, "schema-conflict"
    end
    if not bus then
        bus = {
            schema = M.SCHEMA,
            generation = 0,
            floor_generation = 0,
            capacity = bounded_capacity(requested_capacity),
            events = {},
        }
        rawset(root, key, bus)
    end

    local client = {
        owner = owner,
        cursor = bus.generation,
    }

    function client:publish(input)
        local generation = bus.generation + 1
        local row, reason = copy_event(input, generation)
        if not row then return nil, reason end
        row.source = row.source or self.owner
        bus.generation = generation
        bus.events[#bus.events + 1] = row
        while #bus.events > bus.capacity do
            local removed = table.remove(bus.events, 1)
            bus.floor_generation = removed and removed.generation
                or bus.floor_generation
        end
        return generation
    end

    function client:drain(handler, maximum)
        if type(handler) ~= "function" then
            return { seen = 0, handled = 0, failed = 0, dropped = 0,
                cursor = self.cursor, error = "handler-not-function" }
        end
        maximum = math.floor(tonumber(maximum) or 8)
        if maximum < 1 then maximum = 1 end
        if maximum > 32 then maximum = 32 end

        local report = { seen = 0, handled = 0, failed = 0, dropped = 0 }
        if self.cursor < bus.floor_generation then
            report.dropped = bus.floor_generation - self.cursor
            self.cursor = bus.floor_generation
        end
        for i = 1, #bus.events do
            local row = bus.events[i]
            if row.generation > self.cursor and report.seen < maximum then
                report.seen = report.seen + 1
                local ok, accepted = pcall(handler, row)
                if not ok then
                    report.failed = report.failed + 1
                elseif accepted then
                    report.handled = report.handled + 1
                end
                self.cursor = row.generation
            end
        end
        report.cursor = self.cursor
        report.pending = math.max(0, bus.generation - self.cursor)
        return report
    end

    function client:stats()
        return {
            schema = bus.schema,
            capacity = bus.capacity,
            retained = #bus.events,
            generation = bus.generation,
            floor_generation = bus.floor_generation,
            cursor = self.cursor,
        }
    end

    function client:has_pending()
        return bus.generation > self.cursor
    end

    return client
end

return M
