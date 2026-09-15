-- _gut_loadout_page_mapper.lua -- pure page/physical-slot mapping for the paged native loadout bar (#231)
--
-- The vanilla hero-view loadout selector builds exactly six physical button widgets at
-- module load (hero_window_loadout_selection_console_definitions.lua:1101-1109) and indexes
-- them directly by logical loadout index everywhere. GUT reuses those six buttons as one
-- logical PAGE of six slots, so thirty slots become five pages. This module owns every
-- logical<->physical translation, the page-count / clamp / auto-reveal arithmetic, the strip
-- geometry, the text Roman numerals, and the realm predicate. It is engine-free so the Lua
-- 5.1 host tests (qa/lua/tests/test_gut_loadout_paging.lua) and the in-game
-- `issue231_loadout_paging` regression check share one implementation. The runtime owner
-- (_gut_loadout_paging.lua) never indexes `_loadout_button_widgets` by a logical index.
--
-- Owned by: gui_tweaker_dev.lua entry point (loaded through the _gut_mission_inventory.lua
-- tail because the entry point and _gut_native_loadouts.lua are at their size ceilings).
-- Consumed via: mod:dofile("scripts/mods/gui_tweaker_dev/_gut_loadout_page_mapper")
local Mapper = {
    PAGE_SIZE = 6,       -- physical buttons vanilla instantiates (definitions.lua:1101-1109)
    TARGET = 30,         -- logical slots the modded store exposes (#231)
    VANILLA_VISIBLE = 6, -- vanilla custom rows / icon assets (inventory_settings.lua:178-207)
    STORE_DATA_KEY = "characters_data", -- Adventure mirror key; Versus is vs_characters_data
}

local function _positive_int(v)
    return type(v) == "number" and v == v and v >= 1 and v == math.floor(v)
end

local function _size(page_size)
    return _positive_int(page_size) and page_size or Mapper.PAGE_SIZE
end

-- Pages needed to show `total` loadouts; never below one page.
function Mapper.page_count(total, page_size)
    if not _positive_int(total) then return 1 end
    return math.ceil(total / _size(page_size))
end

-- Page holding logical slot `logical`, or nil for an invalid slot.
function Mapper.page_of(logical, page_size)
    if not _positive_int(logical) then return nil end
    return math.floor((logical - 1) / _size(page_size)) + 1
end

-- Physical button index (1..PAGE_SIZE) of logical slot `logical`, or nil.
function Mapper.slot_of(logical, page_size)
    if not _positive_int(logical) then return nil end
    return (logical - 1) % _size(page_size) + 1
end

-- Logical slot shown by physical button `slot` on `page`, or nil when out of range.
function Mapper.logical_of(page, slot, page_size)
    local size = _size(page_size)
    if not _positive_int(page) or not _positive_int(slot) or slot > size then return nil end
    return (page - 1) * size + slot
end

-- Clamp a requested page into 1..page_count(total).
function Mapper.clamp_page(page, total, page_size)
    local count = Mapper.page_count(total, page_size)
    if not _positive_int(page) then return 1 end
    if page > count then return count end
    return page
end

-- Physical button index of `logical` when it is on `page`, else nil. This is the only
-- sanctioned way to turn a logical index into a `_loadout_button_widgets` index.
function Mapper.physical_slot(logical, page, page_size)
    if Mapper.page_of(logical, page_size) ~= page then return nil end
    return Mapper.slot_of(logical, page_size)
end

-- Number of logical slots (0..PAGE_SIZE) that exist on `page` for `total` loadouts.
function Mapper.visible_count(page, total, page_size)
    local size = _size(page_size)
    if not _positive_int(page) or not _positive_int(total) then return 0 end
    local first = (page - 1) * size + 1
    if first > total then return 0 end
    local last = math.min(total, first + size - 1)
    return last - first + 1
end

-- Auto-reveal: the page that must be shown so `logical` is visible; falls back to the
-- clamped current page when `logical` is not a valid slot.
function Mapper.reveal_page(logical, total, current_page, page_size)
    local page = Mapper.page_of(logical, page_size)
    if not page or (_positive_int(total) and logical > total) then
        return Mapper.clamp_page(current_page, total, page_size)
    end
    return Mapper.clamp_page(page, total, page_size)
end

-- Strip geometry for one page. `button_width`/`spacing` come from the vanilla definitions
-- (48 / 5, definitions.lua:6-10). Vanilla shifts the `button` scenegraph node left by
-- (visible - 1) steps so the last button touches the add (+) button
-- (hero_window_loadout_selection_console.lua:202) and parks the gamepad hover frame at
-- `visible` steps when the add button is focused (:529). With page controls shown, one extra
-- step is reserved between the strip and the add button for the next-page button.
function Mapper.layout(page, total, button_width, spacing, page_size)
    local step = (button_width or 48) + (spacing or 5)
    local count = Mapper.page_count(total, page_size)
    local clamped = Mapper.clamp_page(page, total, page_size)
    local visible = Mapper.visible_count(clamped, total, page_size)
    local show_controls = count > 1
    local reserved = show_controls and 1 or 0
    return {
        page = clamped,
        page_count = count,
        visible = visible,
        show_controls = show_controls,
        strip_offset = -step * (math.max(visible, 1) - 1 + reserved),
        add_hover_offset = step * (visible + reserved),
        prev_offset = -step,   -- relative to the strip origin (`button` node)
        next_offset = -step,   -- relative to the add button node
        has_previous = clamped > 1,
        has_next = clamped < count,
    }
end

-- Text Roman numeral for 1..3999; "" for anything else (never requests an atlas texture).
local ROMAN = {
    { 1000, "M" }, { 900, "CM" }, { 500, "D" }, { 400, "CD" }, { 100, "C" }, { 90, "XC" },
    { 50, "L" }, { 40, "XL" }, { 10, "X" }, { 9, "IX" }, { 5, "V" }, { 4, "IV" }, { 1, "I" },
}
function Mapper.roman(n)
    if not _positive_int(n) or n > 3999 then return "" end
    local out, rest = {}, n
    for i = 1, #ROMAN do
        local value, glyph = ROMAN[i][1], ROMAN[i][2]
        while rest >= value do
            out[#out + 1] = glyph
            rest = rest - value
        end
    end
    return table.concat(out)
end

-- Realm gate: paging exists only in the modded realm, only in STORE mode (the modded store
-- is capacity-agnostic; READONLY mirrors the official six-slot data), and only on the
-- Adventure mirror (Versus stays vanilla, matching _gut_native_loadouts.lua).
function Mapper.should_page(is_modded, mode, data_key)
    return is_modded == true and mode == "store" and data_key == Mapper.STORE_DATA_KEY
end

-- Bijection proof used by the regression check: every logical slot 1..target maps to
-- exactly one (page, slot) pair, round-trips, and no pair is reused. Returns nil when the
-- mapping holds, else a failure string.
function Mapper.check_bijection(target, page_size)
    target = target or Mapper.TARGET
    local seen = {}
    for logical = 1, target do
        local page, slot = Mapper.page_of(logical, page_size), Mapper.slot_of(logical, page_size)
        if not page or not slot then return "no page/slot for logical " .. logical end
        local key = page .. ":" .. slot
        if seen[key] then return "page/slot " .. key .. " reused by logical " .. logical end
        seen[key] = logical
        if Mapper.logical_of(page, slot, page_size) ~= logical then
            return "round-trip failed for logical " .. logical
        end
        if Mapper.physical_slot(logical, page, page_size) ~= slot then
            return "physical_slot disagrees with slot_of for logical " .. logical
        end
        if Mapper.physical_slot(logical, page + 1, page_size) ~= nil then
            return "physical_slot leaked logical " .. logical .. " onto the next page"
        end
    end
    local pages = Mapper.page_count(target, page_size)
    local counted = 0
    for page = 1, pages do counted = counted + Mapper.visible_count(page, target, page_size) end
    if counted ~= target then return "visible_count sums to " .. counted .. ", expected " .. target end
    return nil
end

return Mapper
