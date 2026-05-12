--[[
modded_rarities.lua — register custom item rarities.

Adds a "modded" rarity (used for cim's crafted items) that is fully separate
from vanilla's "promo"/"default" rarities, so it sidesteps the two hard-coded
gates that lock promo items out of the inventory cog and customization window:
  - ui_widgets_honduras.lua:2407 — `(rarity == "default" or "promo") and ...`
  - hero_window_item_customization.lua:179 — `(item_rarity == "default" or "promo")`

To register additional rarities later, call `mod.register_rarity(...)` from
this file or anywhere after VMF init.

Color is pure data — to change the look, edit MODDED_COLOR below (a, r, g, b).
]]

local mod = get_mod("cim")

-- {alpha, r, g, b}. Soft pale gold — legible on dark inventory backgrounds,
-- visually distinct from every vanilla rarity color.
local MODDED_COLOR = { 255, 248, 237, 197 }

local MODDED_ORDER = 4 -- mirrors exotic; grants all 4 customization tabs

-- Public registry API. `opts` fields:
--   color           = {a,r,g,b}  | "<existing palette name>"   default: pale gold
--   order           = number                                   default: 4
--   display_name    = string                                   default: capitalized name
local _registered = {}

mod.register_rarity = function(rarity_name, opts)
    opts = opts or {}
    if _registered[rarity_name] then return end

    local Colors = rawget(_G, "Colors")
    local UISettings = rawget(_G, "UISettings")
    local RaritySettings = rawget(_G, "RaritySettings")
    local RarityIndex = rawget(_G, "RarityIndex")
    local ORDER_RARITY = rawget(_G, "ORDER_RARITY")

    -- 1. Color resolution. Allow either {a,r,g,b} or a palette-name string.
    local color
    if type(opts.color) == "string" and Colors and Colors.color_definitions then
        local existing = Colors.color_definitions[opts.color]
        if existing then
            color = { existing[1], existing[2], existing[3], existing[4] }
        end
    elseif type(opts.color) == "table" then
        color = { opts.color[1] or 255, opts.color[2], opts.color[3], opts.color[4] }
    end
    if not color then color = { 255, 248, 237, 197 } end -- pale gold fallback

    -- Register the named color so other code can resolve Colors.get_table(rarity_name).
    if Colors and Colors.color_definitions and not Colors.color_definitions[rarity_name] then
        Colors.color_definitions[rarity_name] = color
    end

    -- 2. Frame color (darker, used by border accents).
    local r, g, b = color[2], color[3], color[4]
    local red_mult   = 255 / math.max(r, 1)
    local green_mult = 255 / math.max(g, 1)
    local blue_mult  = 255 / math.max(b, 1)
    local mult = math.min(red_mult, green_mult, blue_mult)
    local frame_color = { color[1], r * mult, g * mult, b * mult }

    local order = opts.order or 4

    -- 3. UISettings.item_rarity_order — drives sort order AND _setup_availble_states.
    if UISettings then
        UISettings.item_rarity_order = UISettings.item_rarity_order or {}
        UISettings.item_rarity_order[rarity_name] = order

        UISettings.item_rarities = UISettings.item_rarities or {}
        local already = false
        for _, n in ipairs(UISettings.item_rarities) do
            if n == rarity_name then already = true break end
        end
        if not already then
            UISettings.item_rarities[#UISettings.item_rarities + 1] = rarity_name
        end
    end

    -- 4. RaritySettings — display name, color, frame_color.
    if RaritySettings then
        RaritySettings[rarity_name] = {
            display_name = "rarity_display_name_" .. rarity_name,
            name = rarity_name,
            order = order,
            color = color,
            frame_color = frame_color,
        }
    end

    -- 5. RarityIndex — mirror of order.
    if RarityIndex then
        RarityIndex[rarity_name] = order
    end

    -- 6. ORDER_RARITY — mirrored array.
    if ORDER_RARITY then
        local exists = false
        for _, n in ipairs(ORDER_RARITY) do
            if n == rarity_name then exists = true break end
        end
        if not exists then
            local idx = #ORDER_RARITY + 1
            ORDER_RARITY[idx] = rarity_name
            -- mirror_array also indexes by string
            rawset(ORDER_RARITY, rarity_name, idx)
        end
    end

    -- 7. NetworkLookup.rarities — required so equip/inventory sync doesn't
    --    crash with "unknown rarity" on a lookup miss.
    local NL = rawget(_G, "NetworkLookup")
    if NL and NL.rarities and not rawget(NL.rarities, rarity_name) then
        local t = NL.rarities
        local idx = #t + 1
        t[idx] = rarity_name
        rawset(t, rarity_name, idx)
    end

    _registered[rarity_name] = true
    mod:info("Registered custom rarity '%s' (order=%d, color={%d,%d,%d,%d})",
        rarity_name, order, color[1], color[2], color[3], color[4])
end

-- Localize the display name. Hook _G.Localize since `mod:add_global_localization`
-- isn't a VMF API and per-mod loc isn't read by vanilla code paths that resolve
-- rarity_display_name_* via Localize().
mod:hook(_G, "Localize", function(func, key, ...)
    if key == "rarity_display_name_modded" then
        return "Modded"
    end
    return func(key, ...)
end)

-- Register the default "modded" rarity.
mod.register_rarity("modded", {
    color = MODDED_COLOR,
    order = MODDED_ORDER,
})
