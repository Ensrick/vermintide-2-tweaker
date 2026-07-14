-- Bounded runtime census for native loadout expansion (#231). Observation only.
local mod = get_mod("gut_dev")
local Policy = mod:dofile("scripts/mods/gui_tweaker_dev/_gut_loadout_capacity_policy")
local _printf = rawget(_G, "printf") or function() end
local latest_widget_count = 0
local hook_installed = false

local function atlas_has(index)
    local helper = rawget(_G, "UIAtlasHelper")
    if not helper or type(helper.get_atlas_settings_by_texture_name) ~= "function" then
        return false
    end
    local ok, settings = pcall(helper.get_atlas_settings_by_texture_name,
        "loadout_icon_" .. tostring(index))
    return ok and type(settings) == "table"
end

local function title_has(index)
    local localize = rawget(_G, "Localize")
    if type(localize) ~= "function" then return false end
    local key = "custom_loadout_" .. tostring(index) .. "_title"
    local ok, text = pcall(localize, key)
    return ok and type(text) == "string" and text ~= key
end

local function store_extent()
    local store = mod:get("native_loadouts")
    local max_rows = 0
    if type(store) == "table" then
        for _, career in pairs(store) do
            local rows = type(career) == "table" and career.loadouts
            if type(rows) == "table" then
                for index, row in pairs(rows) do
                    local numeric = tonumber(index)
                    if row ~= nil and numeric and numeric > max_rows then
                        max_rows = numeric
                    end
                end
            end
        end
    end
    return max_rows
end

local function census()
    local settings = rawget(_G, "InventorySettings") or {}
    return Policy.inspect(settings.loadouts, settings.MAX_NUM_CUSTOM_LOADOUTS,
        latest_widget_count, atlas_has, title_has, store_extent())
end

local function log_census(reason)
    local result = census()
    _printf("[gut:231] reason=%s target=%d custom=%d cap=%d widgets=%d store_max=%d duplicates=%d paging=%s cutover_ready=%s",
        tostring(reason), result.target, result.custom_count, result.declared_cap,
        result.widget_count, result.store_max, result.duplicate_count,
        tostring(result.needs_paging), tostring(result.cutover_ready))
    _printf("[gut:231] missing_icons=%s missing_titles=%s data_ready=%s assets_ready=%s direct_ui_ready=%s",
        result.missing_icon_ranges, result.missing_title_ranges,
        tostring(result.data_ready), tostring(result.assets_ready),
        tostring(result.direct_ui_ready))
    return result
end

local window = rawget(_G, "HeroWindowLoadoutSelectionConsole")
if window and type(window.on_enter) == "function" then
    mod:hook_safe(window, "on_enter", function(self)
        latest_widget_count = type(self._loadout_button_widgets) == "table"
            and #self._loadout_button_widgets or 0
        log_census("window_enter")
    end)
    hook_installed = true
end

mod:command("gut_loadout_capacity_probe",
    "Capture bounded native-loadout capacity diagnostics (#231)", function()
        log_census("command")
    end)

log_census("boot")

return {
    policy = Policy,
    rt_checks = {
        {
            name = "issue231_native_loadout_capacity_diagnostics",
            fn = function()
                if not hook_installed then
                    return "HeroWindowLoadoutSelectionConsole.on_enter probe hook missing"
                end
                local result = census()
                if result.target ~= 30 or not result.needs_paging then
                    return "30-slot paging contract drifted"
                end
                if result.duplicate_count > 0 then
                    return "duplicate custom loadout indices"
                end
                return nil
            end,
        },
    },
}
