-- Canonical cached loader and strict composer for issue #1436 catalogs.
--
-- Generated catalogs are pure data and may be requested by the VMF data,
-- localization, and runtime chunks. mod:dofile itself is not a singleton, so
-- this module owns the only cache boundary. Catalogs compose only when their
-- current source anchors match exactly. A repeated family may contribute only
-- disjoint states under the same complete identity; all other ownership axes
-- remain disjoint.
local M = {}

local GENERATED_MODULES = {
    "scripts/mods/weapon_tweaker/_wt_history_5_2_catalog",
    "scripts/mods/weapon_tweaker/_wt_history_6_0_catalog",
    "scripts/mods/weapon_tweaker/_wt_history_6_6_catalog",
    "scripts/mods/weapon_tweaker/_wt_history_6_8_catalog",
    "scripts/mods/weapon_tweaker/_wt_history_4_1_1_catalog",
}
local GENERATED_MODULE = GENERATED_MODULES[1]

local function dense_array_length(value, label)
    if type(value) ~= "table" then return nil, label .. " is not an array" end
    local count, maximum = 0, 0
    for key in pairs(value) do
        if type(key) ~= "number" or key < 1 or key % 1 ~= 0 then
            return nil, label .. " must be a dense array"
        end
        count = count + 1
        if key > maximum then maximum = key end
    end
    if count ~= maximum then return nil, label .. " must be a dense array" end
    return count
end

local function normalize_modules(generated_modules)
    if generated_modules == nil then generated_modules = GENERATED_MODULES end
    if type(generated_modules) == "string" then
        generated_modules = { generated_modules }
    end
    if type(generated_modules) ~= "table" then
        return nil, "generated module paths are required"
    end
    local count, count_error = dense_array_length(
        generated_modules, "generated module paths")
    if not count then return nil, count_error end
    local modules, seen = {}, {}
    for index = 1, count do
        local path = rawget(generated_modules, index)
        if type(path) ~= "string" or path == "" or seen[path] then
            return nil, "generated module path is invalid or duplicated"
        end
        modules[index], seen[path] = path, true
    end
    if #modules == 0 then return nil, "generated module paths are empty" end
    return modules
end

local copy_value

local function copy_disjoint(target, source, label)
    if source == nil then return true end
    if type(source) ~= "table" then return nil, label .. " is not a table" end
    for key, value in pairs(source) do
        if rawget(target, key) ~= nil then
            return nil, "duplicate " .. label .. " " .. tostring(key)
        end
        target[key] = copy_value(value)
    end
    return true
end

copy_value = function(value, seen)
    if type(value) ~= "table" then return value end
    seen = seen or {}
    if seen[value] then return seen[value] end
    local copy = {}
    seen[value] = copy
    for key, child in pairs(value) do
        copy[copy_value(key, seen)] = copy_value(child, seen)
    end
    return copy
end

local function arrays_equal(left, right)
    local left_count = dense_array_length(left, "left identity array")
    local right_count = dense_array_length(right, "right identity array")
    if not left_count or not right_count or left_count ~= right_count then
        return false
    end
    for index = 1, left_count do
        if rawget(left, index) ~= rawget(right, index) then return false end
    end
    return true
end

local function history_state_less(left, right)
    local left_major, left_minor, left_patch = tostring(left):match(
        "^(%d+)_(%d+)_(%d+)$")
    local right_major, right_minor, right_patch = tostring(right):match(
        "^(%d+)_(%d+)_(%d+)$")
    if left_major and right_major then
        left_major, left_minor, left_patch = tonumber(left_major),
            tonumber(left_minor), tonumber(left_patch)
        right_major, right_minor, right_patch = tonumber(right_major),
            tonumber(right_minor), tonumber(right_patch)
        if left_major ~= right_major then return left_major < right_major end
        if left_minor ~= right_minor then return left_minor < right_minor end
        if left_patch ~= right_patch then return left_patch < right_patch end
    elseif left_major or right_major then
        return left_major ~= nil
    end
    return tostring(left) < tostring(right)
end

local function family_identity_mismatch(left, right)
    for _, field in ipairs({
        "id", "setting_id", "label_key", "display_name", "authority",
    }) do
        if rawget(left, field) ~= rawget(right, field) then return field end
    end
    if not arrays_equal(left.templates, right.templates) then return "templates" end
    return nil
end

local function validate_family_states(family)
    if type(family.states) ~= "table" then
        return nil, "history family states are not a table"
    end
    local state_count, state_count_error = dense_array_length(
        family.state_order, "history family state order")
    if not state_count then return nil, state_count_error end
    local listed = {}
    for state_index = 1, state_count do
        local state_id = rawget(family.state_order, state_index)
        if type(state_id) ~= "string" or state_id == "" or listed[state_id]
                or type(family.states[state_id]) ~= "table" then
            return nil, "duplicate or invalid history family state "
                .. tostring(state_id)
        end
        listed[state_id] = true
    end
    for state_id, state in pairs(family.states) do
        if not listed[state_id] or type(state) ~= "table" then
            return nil, "history family state missing from order "
                .. tostring(state_id)
        end
    end
    return state_count
end

function M.merge(catalogs)
    local catalog_count, catalog_count_error = dense_array_length(
        catalogs, "history catalogs")
    if not catalog_count then return nil, catalog_count_error end
    if catalog_count == 0 then return nil, "history catalogs are required" end
    local first = catalogs[1]
    if type(first) ~= "table" or type(first.current_source) ~= "table" then
        return nil, "history catalog has an unsupported shape"
    end
    local merged = {
        catalog_id = "wt_history_composite_v1",
        current_id = "current",
        current_source = copy_value(first.current_source),
        derived_profiles = {},
        families = {},
        generation = { catalogs = {} },
        profile_specs = {},
        schema = 2,
        states = {},
    }
    local catalog_ids, family_ids, setting_ids, template_ids = {}, {}, {}, {}
    local localization_keys = {
        wt_history_patch_versions = "reserved history group",
        wt_history_patch_versions_description = "reserved history group description",
        wt_history_state_current = "reserved current-state label",
    }
    local function claim_localization_key(key, owner)
        if type(key) ~= "string" or key == "" then
            return nil, "history localization key is missing for " .. owner
        end
        if localization_keys[key] then
            return nil, "duplicate history localization key " .. key
        end
        localization_keys[key] = owner
        return true
    end
    for catalog_index = 1, catalog_count do
        local catalog = catalogs[catalog_index]
        if type(catalog) ~= "table" or catalog.schema ~= 2
                or catalog.current_id ~= "current"
                or type(catalog.catalog_id) ~= "string"
                or type(catalog.current_source) ~= "table"
                or catalog.current_source.revision ~= first.current_source.revision
                or catalog.current_source.display_name ~= first.current_source.display_name
                or catalog.current_source.label ~= first.current_source.label
                or type(catalog.families) ~= "table" then
            return nil, "history catalog has an unsupported or mismatched shape"
        end
        if catalog_ids[catalog.catalog_id] then
            return nil, "duplicate catalog id " .. catalog.catalog_id
        end
        catalog_ids[catalog.catalog_id] = true
        merged.generation.catalogs[catalog_index] = catalog.catalog_id

        if type(catalog.states) ~= "table" then
            return nil, "history catalog has an unsupported or mismatched shape"
        end
        local ok, merge_error = copy_disjoint(
            merged.states, catalog.states, "history state")
        if not ok then return nil, merge_error end
        for state_id, state in pairs(catalog.states) do
            if type(state) ~= "table" then
                return nil, "history state identity is incomplete"
            end
            local claimed, claim_error = claim_localization_key(
                state.label_key, "state " .. tostring(state_id))
            if not claimed then return nil, claim_error end
        end
        ok, merge_error = copy_disjoint(
            merged.profile_specs, catalog.profile_specs, "profile state")
        if not ok then return nil, merge_error end
        ok, merge_error = copy_disjoint(
            merged.derived_profiles, catalog.derived_profiles,
            "derived-profile state")
        if not ok then return nil, merge_error end

        local family_count, family_count_error = dense_array_length(
            catalog.families, "history families")
        if not family_count then return nil, family_count_error end
        for family_index = 1, family_count do
            local family = catalog.families[family_index]
            if type(family) ~= "table" or type(family.id) ~= "string"
                    or type(family.setting_id) ~= "string"
                    or type(family.label_key) ~= "string"
                    or type(family.templates) ~= "table" then
                return nil, "history family identity is incomplete"
            end
            local template_count, template_count_error = dense_array_length(
                family.templates, "history family templates")
            if not template_count then return nil, template_count_error end
            for template_index = 1, template_count do
                local template = family.templates[template_index]
                if type(template) ~= "string" or template == "" then
                    return nil, "duplicate or invalid history template "
                        .. tostring(template)
                end
            end
            local state_count, state_count_error = validate_family_states(family)
            if not state_count then return nil, state_count_error end

            local owner = family_ids[family.id]
            if owner then
                local mismatch = family_identity_mismatch(owner.family, family)
                if mismatch then
                    return nil, "history family identity mismatch " .. mismatch
                        .. " for " .. family.id
                end
                if setting_ids[family.setting_id] ~= family.id then
                    return nil, "duplicate history setting " .. family.setting_id
                end
                for template_index = 1, template_count do
                    local template = family.templates[template_index]
                    if template_ids[template] ~= family.id then
                        return nil, "duplicate or invalid history template "
                            .. tostring(template)
                    end
                end
                for state_index = 1, state_count do
                    local state_id = family.state_order[state_index]
                    if owner.family.states[state_id] ~= nil then
                        return nil, "duplicate history family state " .. family.id
                            .. "/" .. state_id
                    end
                    owner.family.state_order[#owner.family.state_order + 1] = state_id
                    owner.family.states[state_id] = copy_value(family.states[state_id])
                end
            else
                if setting_ids[family.setting_id] then
                    return nil, "duplicate history setting " .. family.setting_id
                end
                local family_keys = {
                    family.label_key,
                    family.setting_id,
                    family.setting_id .. "_description",
                }
                for _, key in ipairs(family_keys) do
                    local claimed, claim_error = claim_localization_key(
                        key, "family " .. family.id)
                    if not claimed then return nil, claim_error end
                end
                for template_index = 1, template_count do
                    local template = family.templates[template_index]
                    if template_ids[template] then
                        return nil, "duplicate or invalid history template "
                            .. tostring(template)
                    end
                    template_ids[template] = family.id
                end
                local merged_family = copy_value(family)
                merged.families[#merged.families + 1] = merged_family
                family_ids[family.id] = { family = merged_family }
                setting_ids[family.setting_id] = family.id
            end
        end
    end
    for _, family in ipairs(merged.families) do
        table.sort(family.state_order, history_state_less)
    end
    return merged
end

function M.load(mod, generated_modules)
    if type(mod) ~= "table" or type(mod.dofile) ~= "function" then
        return nil, "mod:dofile is required"
    end
    local modules, modules_error = normalize_modules(generated_modules)
    if not modules then return nil, modules_error end
    local cache_key = table.concat(modules, "\31")

    local cache = rawget(mod, "_wt_history_catalog_schema2_cache")
    if type(cache) == "table" and cache.key == cache_key then
        return cache.catalog
    end

    local catalogs = {}
    for index, generated_module in ipairs(modules) do
        local ok, catalog = pcall(mod.dofile, mod, generated_module)
        if not ok or type(catalog) ~= "table" then
            return nil, "history catalog load failed: " .. tostring(catalog)
        end
        catalogs[index] = catalog
    end
    local catalog, merge_error
    if #catalogs == 1 then
        catalog = catalogs[1]
    else
        catalog, merge_error = M.merge(catalogs)
    end
    if not catalog then return nil, merge_error end
    if catalog.schema ~= 2 or catalog.current_id ~= "current"
            or type(catalog.families) ~= "table" then
        return nil, "history catalog has an unsupported shape"
    end
    mod._wt_history_catalog_schema2_cache = {
        catalog = catalog,
        key = cache_key,
    }
    return catalog
end

function M.build_widgets(catalog)
    if type(catalog) ~= "table" or type(catalog.families) ~= "table"
            or catalog.current_id ~= "current" then
        return nil, "history catalog is unavailable"
    end
    local widgets = {}
    for _, family in ipairs(catalog.families) do
        local options = {
            { text = "wt_history_state_current", value = catalog.current_id },
        }
        for _, state_id in ipairs(family.state_order or {}) do
            local state = catalog.states and catalog.states[state_id]
            if type(state) ~= "table" or type(state.label_key) ~= "string" then
                return nil, "history state label missing " .. tostring(state_id)
            end
            options[#options + 1] = { text = state.label_key, value = state_id }
        end
        widgets[#widgets + 1] = {
            default_value = catalog.current_id,
            options = options,
            setting_id = family.setting_id,
            type = "dropdown",
        }
    end
    return {
        setting_id = "wt_history_patch_versions",
        sub_widgets = widgets,
        type = "group",
    }
end

function M.decorate_menu(mod, data)
    if type(data) ~= "table" or type(data.options) ~= "table"
            or type(data.options.widgets) ~= "table" then
        return data
    end
    for _, widget in ipairs(data.options.widgets) do
        if type(widget) == "table"
                and widget.setting_id == "wt_history_patch_versions" then
            return data
        end
    end
    local catalog, catalog_error = M.load(mod)
    if catalog then
        local history_group, history_group_error = M.build_widgets(catalog)
        if history_group then
            table.insert(data.options.widgets, 2, history_group)
        else
            pcall(printf, "[wt:1436] history menu omitted: %s",
                tostring(history_group_error))
        end
    else
        pcall(printf, "[wt:1436] history catalog unavailable in menu: %s",
            tostring(catalog_error))
    end
    return data
end

function M.build_localization(catalog)
    if type(catalog) ~= "table" or type(catalog.families) ~= "table"
            or type(catalog.states) ~= "table" then
        return nil, "history catalog is unavailable"
    end
    local entries = {
        wt_history_patch_versions = {
            en = "Pre-Patch Weapon Versions",
        },
        wt_history_patch_versions_description = {
            en = "Restore source-proven weapon balance from earlier game versions. Current is the safe default. A changed selection takes effect after restarting the game; ordinary Weapon Tweaks are then applied on top.",
        },
        wt_history_state_current = {
            en = type(catalog.current_source) == "table"
                and catalog.current_source.display_name or "Current",
        },
    }
    for state_id, state in pairs(catalog.states) do
        if type(state) ~= "table" or type(state.label_key) ~= "string"
                or type(state.display_name) ~= "string" then
            return nil, "history state localization missing " .. tostring(state_id)
        end
        entries[state.label_key] = { en = state.display_name }
    end
    for _, family in ipairs(catalog.families) do
        if type(family.label_key) ~= "string"
                or type(family.display_name) ~= "string"
                or type(family.setting_id) ~= "string" then
            return nil, "history family localization missing"
        end
        entries[family.label_key] = { en = family.display_name }
        entries[family.setting_id] = { en = family.display_name }
        entries[family.setting_id .. "_description"] = {
            en = "Choose the native balance state for " .. family.display_name
                .. ". Historical choices require a game restart. Other Weapon Tweaks compose on top of this baseline.",
        }
        if family.authority == "server" then
            entries[family.setting_id .. "_description"].en =
                entries[family.setting_id .. "_description"].en
                .. " This selector applies only while hosting or playing solo."
        end
    end
    return entries
end

M.GENERATED_MODULE = GENERATED_MODULE
M.GENERATED_MODULES = GENERATED_MODULES

return M
