-- _cim_diag_524.lua
--
-- Issue #524 render-seam diagnostic: the RENDERED native Craft Item picker.
--
-- Every prior #524 probe measured CIM's synthetic CATALOG (catalog.build's
-- eligible/families/suppressed counts). None measured the list vanilla actually
-- draws after can_craft_with + the weapon-drop filter + synthetic inject. That
-- blind spot is why ten catalog-policy ships kept passing their offline checks
-- yet failing the user's eyes-on picker. This dumps the FINAL injected list at
-- the one seam that produces it (standard_forge mod._cim_inject_templates), so a
-- single session log proves which rows the user sees and where each came from.
--
-- Two independent groupings, because the user's "duplicates" have two distinct
-- shapes and a fix must not conflate them:
--   * render_dup    -- >1 row sharing one CANONICAL weapon family. A genuine
--                      dedup miss: the compactor let two rows for the same weapon
--                      through (e.g. a crafted-modded instance beside its
--                      synthetic selector, both canonical_family cwv:<key>).
--   * render_softdup -- >1 DISTINCT weapon family sharing one item_type. Two
--                      authored definitions that look alike in the grid (e.g. a
--                      throwing-axes variant and a javelin cloned off it, or two
--                      provider Blightreapers). Not a canonical-family collision,
--                      so CIM's family compactor deliberately keeps both; but it
--                      IS what the user reads as "duplicates", so the keys +
--                      sources are named for the ruling.
--
-- Every row is tagged by SOURCE (synthetic / vanilla-default / crafted-modded /
-- legacy-cwv / r:<rarity>), so a crafted instance leaking past vanilla's
-- rarity=="default" filter shows up explicitly rather than as an anonymous twin.
--
-- Engine printf, prefix [cim:524]. Always-on in dev, no menu toggle. Cheap: a
-- clean open prints one header line; detail rows print only when a dup/softdup
-- exists and are limited to the implicated rows. A signature throttle suppresses
-- identical repeat opens (the recipe page re-queries get_filtered_items).

local mod = get_mod("cim")

local M = {}

local DUP_CAP = 12   -- max render_dup / render_softdup lines per open
local ROW_CAP = 40   -- max render_row detail lines per open
local _last_sig = nil

local function _rarity(item)
    return item.rarity
        or (type(item.CustomData) == "table" and item.CustomData.rarity)
        or nil
end

local function _power(item)
    local custom = type(item.CustomData) == "table" and item.CustomData or nil
    return tonumber(item.power_level or (custom and custom.power_level)) or -1
end

local function _source(item)
    if item.cim_acquisition_template == true then return "synthetic" end
    local rarity = _rarity(item)
    if rarity == "modded" then return "crafted-modded" end
    local bid = item.backend_id or item.ItemInstanceId
    if type(bid) == "string" and bid:match("^cwv_.-_%d%d%d$") then
        return "legacy-cwv"
    end
    if rarity == nil or rarity == "default" then return "vanilla-default" end
    return "r:" .. tostring(rarity)
end

local function _key(item)
    return tostring(item.key or (type(item.data) == "table" and item.data.key)
        or item.ItemId or "?")
end

local function _bid(item)
    local bid = item.backend_id or item.ItemInstanceId
    return type(bid) == "string" and bid or "-"
end

local function _item_type(item)
    local data = type(item.data) == "table" and item.data or nil
    return data and data.item_type or nil
end

local function _is_weapon(item)
    local data = type(item.data) == "table" and item.data or nil
    local st = data and data.slot_type
    return st == "melee" or st == "ranged"
end

-- final_items: the list returned by template_selector.inject (mutated in place),
--              i.e. exactly what the native Craft Item picker will render.
-- ctx: { career = <string>, pre_inject = <number>, picker = <string> }
function M.dump(final_items, ctx)
    if type(final_items) ~= "table" then return end
    ctx = ctx or {}
    local career = tostring(ctx.career or "?")
    local picker = tostring(ctx.picker or "native_craft_item")
    local pre = tonumber(ctx.pre_inject) or -1

    local selector = mod._cim_template_selector
    local canon = selector and selector.canonical_family

    local function family_of(item)
        return (canon and canon(item)) or ("key:" .. _key(item))
    end

    local by_family = {}   -- family -> array of items (hard-dup grouping)
    local fam_order = {}
    local by_type = {}     -- item_type -> { fams = {family -> items}, order = {} }
    local type_order = {}
    local rows = {}        -- { idx, item } in render order
    for i = 1, #final_items do
        local item = final_items[i]
        if type(item) == "table" then
            rows[#rows + 1] = { idx = i, item = item }
            local fam = family_of(item)
            local fb = by_family[fam]
            if not fb then fb = {}; by_family[fam] = fb; fam_order[#fam_order + 1] = fam end
            fb[#fb + 1] = item
            if _is_weapon(item) then
                local it = _item_type(item)
                if it then
                    local tb = by_type[it]
                    if not tb then
                        tb = { fams = {}, order = {} }
                        by_type[it] = tb
                        type_order[#type_order + 1] = it
                    end
                    if not tb.fams[fam] then
                        tb.fams[fam] = {}
                        tb.order[#tb.order + 1] = fam
                    end
                    tb.fams[fam][#tb.fams[fam] + 1] = item
                end
            end
        end
    end

    local hard = {}
    for _, fam in ipairs(fam_order) do
        if #by_family[fam] > 1 then hard[#hard + 1] = fam end
    end
    local soft = {}
    for _, it in ipairs(type_order) do
        if #by_type[it].order > 1 then soft[#soft + 1] = it end
    end

    -- Throttle: skip identical repeat opens (the recipe re-queries the filter).
    local sig = career .. "|" .. #rows .. "|" .. #hard .. "|" .. #soft
        .. "|" .. tostring(hard[1]) .. "|" .. tostring(soft[1])
    if sig == _last_sig then return end
    _last_sig = sig

    printf("[cim:524] render picker=%s career=%s pre_inject=%d rendered=%d families=%d hard_dups=%d soft_dups=%d",
        picker, career, pre, #rows, #fam_order, #hard, #soft)

    local hard_n = math.min(#hard, DUP_CAP)
    for i = 1, hard_n do
        local fam = hard[i]
        local members = by_family[fam]
        local parts = {}
        for j = 1, #members do
            parts[j] = _source(members[j]) .. ":" .. _key(members[j]) .. ":p" .. _power(members[j])
        end
        printf("[cim:524] render_dup family=%s count=%d rows=%s",
            tostring(fam), #members, table.concat(parts, " "))
    end
    if #hard > hard_n then printf("[cim:524] render_dup_more count=%d", #hard - hard_n) end

    local soft_n = math.min(#soft, DUP_CAP)
    for i = 1, soft_n do
        local it = soft[i]
        local tb = by_type[it]
        local parts = {}
        for j = 1, #tb.order do
            local fam = tb.order[j]
            local first = tb.fams[fam][1]
            parts[j] = _source(first) .. ":" .. _key(first)
        end
        printf("[cim:524] render_softdup item_type=%s families=%d rows=%s",
            tostring(it), #tb.order, table.concat(parts, " "))
    end
    if #soft > soft_n then printf("[cim:524] render_softdup_more count=%d", #soft - soft_n) end

    -- Per-row detail only for rows implicated in a dup/softdup, so a clean open
    -- stays at one line and a dirty open names exactly the offending keys.
    if #hard > 0 or #soft > 0 then
        local hard_set = {}
        for _, fam in ipairs(hard) do hard_set[fam] = true end
        local soft_set = {}
        for _, it in ipairs(soft) do soft_set[it] = true end
        local printed = 0
        for i = 1, #rows do
            local item = rows[i].item
            local fam = family_of(item)
            local it = _is_weapon(item) and _item_type(item) or nil
            if hard_set[fam] or (it and soft_set[it]) then
                if printed >= ROW_CAP then
                    printf("[cim:524] render_row_more (cap %d reached)", ROW_CAP)
                    break
                end
                printf("[cim:524] render_row idx=%d source=%s rarity=%s power=%d key=%s family=%s bid=%s",
                    rows[i].idx, _source(item), tostring(_rarity(item)), _power(item),
                    _key(item), tostring(fam), _bid(item))
                printed = printed + 1
            end
        end
    end
end

return M
