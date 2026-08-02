-- _cos_offhand_names.lua -- independent cosmetic-component name policy.
--
-- Names are presentation metadata.  Mesh identity, saved selections, and
-- network payloads continue to use their existing skin/unit/armoury keys.

local M = {}

M.SCHEMA_VERSION = 1

local HAND_SUFFIX = {
    left_hand_unit = "left",
    right_hand_unit = "right",
}

local COMPONENT_PREFIX = {
    weapon_offhand = "cos_offhand_weapon_",
    shield = "cos_shield_",
}

local function _trim(value)
    if type(value) ~= "string" then return nil end
    local trimmed = value:match("^%s*(.-)%s*$")
    return trimmed ~= "" and trimmed or nil
end

local function _stable_hash(value)
    local hash = 5381
    for i = 1, #value do
        hash = (hash * 33 + string.byte(value, i)) % 4294967296
    end
    return string.format("%08x", hash)
end

local function _stable_token(value)
    if type(value) ~= "string" or value == "" then return nil end
    if value:match("^[a-z0-9_]+$") then return value end
    local token = value:lower():gsub("[^a-z0-9]+", "_"):gsub("^_+", ""):gsub("_+$", "")
    if token == "" then token = "component" end
    return token .. "_" .. _stable_hash(value)
end

local function _is_missing_localization(value, key)
    value = _trim(value)
    if not value then return true end
    return value == key or value == "<" .. tostring(key) .. ">"
        or value == "[" .. tostring(key) .. "]"
end

function M.identity(component_kind, source_identity, hand_field)
    if not COMPONENT_PREFIX[component_kind] then return nil end
    if type(source_identity) ~= "string" or source_identity == "" then return nil end
    if not HAND_SUFFIX[hand_field] then return nil end
    return component_kind .. "|" .. source_identity .. "|" .. hand_field
end

function M.localization_key(source_identity, hand_field, component_kind)
    component_kind = component_kind or "weapon_offhand"
    local token = _stable_token(source_identity)
    local suffix = HAND_SUFFIX[hand_field]
    local prefix = COMPONENT_PREFIX[component_kind]
    if not token or not suffix or not prefix then return nil end
    return prefix .. token .. "_" .. suffix .. "_name"
end

function M.description_localization_key(source_identity, hand_field, component_kind)
    local key = M.localization_key(source_identity, hand_field, component_kind)
    return key and key:gsub("_name$", "_description") or nil
end

function M.readable_source_name(source_identity)
    if type(source_identity) ~= "string" or source_identity == "" then return "Cosmetic Component" end
    local words = {}
    local ignored_prefix = { bw = true, cwv = true, dr = true, es = true, we = true, wh = true, ww = true }
    local first = true
    for word in source_identity:gmatch("[a-zA-Z0-9]+") do
        local lower = word:lower()
        if not (first and ignored_prefix[lower]) and lower ~= "skin" then
            words[#words + 1] = lower:match("^%d+$") and lower
                or (lower:sub(1, 1):upper() .. lower:sub(2))
        end
        first = false
    end
    return #words > 0 and table.concat(words, " ") or "Cosmetic Component"
end

-- Returns display_name, localization_key, resolution_source.
function M.resolve(source_identity, hand_field, fallback_name, localize, component_kind, explicit_key)
    component_kind = component_kind or "weapon_offhand"
    local localization_key = explicit_key
        or M.localization_key(source_identity, hand_field, component_kind)
    if localization_key and type(localize) == "function" then
        local ok, localized = pcall(localize, localization_key)
        if ok and not _is_missing_localization(localized, localization_key) then
            return _trim(localized), localization_key, "authored"
        end
    end
    local fallback = _trim(fallback_name)
    if fallback and fallback ~= source_identity then
        return fallback, localization_key, "source"
    end
    return M.readable_source_name(source_identity), localization_key, "generated"
end

-- Returns localized_description, localization_key, resolution_source.
-- Component-authored text wins, then the source illusion's own description.
-- If neither exists, generate readable component copy rather than leaking the
-- primary weapon description or an internal localization key.
function M.resolve_description(source_identity, hand_field, fallback_description,
        localize, component_kind, explicit_key, source_key, fallback_name,
        source_localize)
    component_kind = component_kind or "weapon_offhand"
    local localization_key = explicit_key
        or M.description_localization_key(source_identity, hand_field, component_kind)
    if type(localize) == "function" and type(localization_key) == "string" then
        local ok, localized = pcall(localize, localization_key)
        if ok and not _is_missing_localization(localized, localization_key) then
            return _trim(localized), localization_key, "authored"
        end
    end
    if type(source_localize) == "function" and type(source_key) == "string" then
        local ok, localized = pcall(source_localize, source_key)
        if ok and not _is_missing_localization(localized, source_key) then
            return _trim(localized), source_key, "source"
        end
    end
    local fallback = _trim(fallback_description)
    if fallback and not _is_missing_localization(fallback, localization_key)
            and not _is_missing_localization(fallback, source_key) then
        return fallback, source_key or localization_key, "source"
    end
    local readable = _trim(fallback_name) or M.readable_source_name(source_identity)
    return "An independently selected " .. readable .. " cosmetic component.",
        localization_key, "generated"
end

function M.decorate(option, source_identity, hand_field, fallback_name,
        source_display_key, localize, component_kind, explicit_key,
        source_localize)
    if type(option) ~= "table" then return option end
    component_kind = component_kind or "weapon_offhand"
    local name, localization_key, resolution_source = M.resolve(
        source_identity, hand_field, fallback_name, localize, component_kind, explicit_key)
    option.name = name
    option.component_kind = component_kind
    option.component_identity = source_identity
    option.source_skin_key = component_kind == "weapon_offhand" and source_identity or option.source_skin_key
    option.source_display_key = source_display_key
    option.component_localization_key = localization_key
    option.component_name_source = resolution_source
    -- Compatibility aliases for the first #641 implementation.
    option.offhand_localization_key = localization_key
    option.offhand_name_source = resolution_source

    local explicit_description_key = option.description_localization_key
        or option.description_key
    if not explicit_description_key and type(explicit_key) == "string"
            and explicit_key:match("_name$") then
        explicit_description_key = explicit_key:gsub("_name$", "_description")
    end
    local description, description_key, description_source = M.resolve_description(
        source_identity, hand_field, option.description, localize, component_kind,
        explicit_description_key, option.source_description_key, name,
        source_localize)
    option.description = description
    option.component_description_localization_key = description_key
    option.component_description_source = description_source
    return option
end

-- The primary name is always supplied by the source illusion whose primary
-- mesh is being previewed.  Composition never derives a monolithic pair name.
function M.compose(primary_name, secondary_name)
    primary_name, secondary_name = _trim(primary_name), _trim(secondary_name)
    if not primary_name then return secondary_name end
    if not secondary_name then return primary_name end
    return primary_name .. " + " .. secondary_name
end

function M.presentation_key(primary_name, secondary_name)
    local combined = M.compose(primary_name, secondary_name)
    if not combined then return nil end
    return "cos_component_presentation_" .. _stable_hash(combined), combined
end

function M.description_presentation_key(description)
    description = _trim(description)
    if not description then return nil end
    return "cos_component_description_" .. _stable_hash(description), description
end

function M.match_option(record, options)
    if type(record) ~= "table" then return nil end
    for _, option in ipairs(options or {}) do
        if type(option) == "table" and not option.follow_main then
            if record.armoury_key and option.la_armoury_key == record.armoury_key then
                return option
            end
            if record.unit_path and (option.unit == record.unit_path
                    or option.intended_unit == record.unit_path) then
                return option
            end
            if record.vanilla_key and (option.skin_key == record.vanilla_key
                    or option.vanilla_skin == record.vanilla_key) then
                return option
            end
        end
    end
    return nil
end

local function _option_identity(option, hand_field)
    if type(option) ~= "table" then return nil end
    local component_kind = option.component_kind or "weapon_offhand"
    local source_identity = option.component_identity or option.la_armoury_key
        or option.source_skin_key or option.skin_key or option.intended_unit
        or option.unit or option.vanilla_skin
    return M.identity(component_kind, source_identity, hand_field)
end

-- Merge one selectable component by semantic identity, not array position.
-- Cosmetics-authored metadata must survive a later generic provider merge:
-- otherwise the duplicate row can win matching and silently replace the
-- component's independent name, description, and icon (#641).
function M.merge_unique(options, candidate, hand_field)
    if type(options) ~= "table" or type(candidate) ~= "table" then
        return false, "invalid"
    end
    local candidate_identity = _option_identity(candidate, hand_field)
    if candidate_identity then
        for index, existing in ipairs(options) do
            if _option_identity(existing, hand_field) == candidate_identity then
                if candidate.cos_authored == true
                        and existing.cos_authored ~= true then
                    options[index] = candidate
                    return true, "replaced_with_authored"
                end
                return false, existing.cos_authored == true
                    and "preserved_authored" or "duplicate"
            end
        end
    end
    options[#options + 1] = candidate
    return true, candidate_identity and "appended" or "appended_unkeyed"
end

-- Deterministically reuse an existing illusion name for an identical primary
-- model.  `records` entries are { key, primary_unit, name }; the key is used
-- only to make selection stable when several illusions share the same mesh.
function M.primary_name_for_unit(primary_unit, records)
    if type(primary_unit) ~= "string" or primary_unit == "" then return nil end
    local matches = {}
    for _, record in ipairs(records or {}) do
        if record.primary_unit == primary_unit and _trim(record.name) then
            matches[#matches + 1] = record
        end
    end
    table.sort(matches, function(a, b)
        if (a.is_pair == true) ~= (b.is_pair == true) then
            -- The combined item name must reuse the independently named
            -- primary weapon when the same right-hand mesh has a standalone
            -- illusion.  A pair's display name already contains its shield or
            -- offhand and would otherwise produce "Pair + Component".
            return a.is_pair ~= true
        end
        return tostring(a.key) < tostring(b.key)
    end)
    return matches[1] and _trim(matches[1].name) or nil
end

function M.inventory_rows(records)
    local by_identity = {}
    for _, record in ipairs(records or {}) do
        local component_kind = record.component_kind or "weapon_offhand"
        local source_identity = record.component_identity or record.source_skin_key
        local identity = M.identity(component_kind, source_identity, record.hand_field)
        if identity then
            local row = by_identity[identity]
            if not row then
                row = {
                    identity = identity,
                    component_kind = component_kind,
                    component_identity = source_identity,
                    source_skin_key = record.source_skin_key,
                    hand_field = record.hand_field,
                    localization_key = record.localization_key
                        or M.localization_key(source_identity, record.hand_field, component_kind),
                    source_name = record.source_name or M.readable_source_name(source_identity),
                    status = record.status or "fallback",
                    item_types = {},
                }
                by_identity[identity] = row
            end
            if record.item_type then row.item_types[record.item_type] = true end
            if record.status == "authored" then row.status = "authored" end
        end
    end
    local out = {}
    for _, row in pairs(by_identity) do
        local item_types = {}
        for item_type in pairs(row.item_types) do item_types[#item_types + 1] = item_type end
        table.sort(item_types)
        row.item_types = item_types
        out[#out + 1] = row
    end
    table.sort(out, function(a, b)
        if a.component_kind ~= b.component_kind then return a.component_kind < b.component_kind end
        if a.component_identity ~= b.component_identity then return a.component_identity < b.component_identity end
        return a.hand_field < b.hand_field
    end)
    return out
end

return M
