-- Canonical cached loader for issue #1436's bounded Patch 5.2 catalog.
--
-- The generated catalog is pure data and may be requested by the VMF data,
-- localization, and runtime chunks.  mod:dofile itself is not a singleton, so
-- this module owns the only cache boundary and prevents the 400 KiB catalog
-- from being reconstructed three times in one Lua VM.
local M = {}

local GENERATED_MODULE =
    "scripts/mods/weapon_tweaker_dev/_wt_history_5_2_catalog"

function M.load(mod, generated_module)
    if type(mod) ~= "table" or type(mod.dofile) ~= "function" then
        return nil, "mod:dofile is required"
    end
    generated_module = generated_module or GENERATED_MODULE
    if type(generated_module) ~= "string" or generated_module == "" then
        return nil, "generated module path is required"
    end

    local cache = rawget(mod, "_wt_history_catalog_schema2_cache")
    if type(cache) == "table" and cache.module == generated_module then
        return cache.catalog
    end

    local ok, catalog = pcall(mod.dofile, mod, generated_module)
    if not ok or type(catalog) ~= "table" then
        return nil, "history catalog load failed: " .. tostring(catalog)
    end
    if catalog.schema ~= 2 or catalog.current_id ~= "current"
            or type(catalog.families) ~= "table" then
        return nil, "history catalog has an unsupported shape"
    end
    mod._wt_history_catalog_schema2_cache = {
        catalog = catalog,
        module = generated_module,
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
    end
    return entries
end

M.GENERATED_MODULE = GENERATED_MODULE

return M
