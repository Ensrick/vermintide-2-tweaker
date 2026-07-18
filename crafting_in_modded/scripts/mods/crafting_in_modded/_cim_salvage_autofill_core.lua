-- _cim_salvage_autofill_core.lua — Pure salvage-button definition transformer.
--
-- Adds the CIM modded-rarity button by cloning vanilla's exotic button and
-- extending vanilla's existing rarity-button progression by one step. The
-- transform is idempotent and shared by desktop and console layouts.
--
-- Owned by: _cim_salvage_modded_button.lua. Consumed via: mod:dofile.

local M = {}

local function deep_copy(value, seen)
    if type(value) ~= "table" then return value end
    seen = seen or {}
    if seen[value] then return seen[value] end
    local copy = {}
    seen[value] = copy
    for key, child in pairs(value) do
        copy[deep_copy(key, seen)] = deep_copy(child, seen)
    end
    return setmetatable(copy, getmetatable(value))
end

local function next_position(previous, current)
    local result = {}
    for i = 1, 3 do
        local a = type(previous[i]) == "number" and previous[i] or 0
        local b = type(current[i]) == "number" and current[i] or 0
        result[i] = b + (b - a)
    end
    return result
end

function M.install(definitions)
    if type(definitions) ~= "table"
            or type(definitions.widgets) ~= "table"
            or type(definitions.scenegraph_definition) ~= "table" then
        return false, "invalid salvage definitions"
    end

    local widgets = definitions.widgets
    local scenegraph = definitions.scenegraph_definition
    if widgets.auto_fill_modded and scenegraph.auto_fill_modded then
        return true, "already installed"
    end

    local rare_node = scenegraph.auto_fill_rare
    local exotic_node = scenegraph.auto_fill_exotic
    local clear_node = scenegraph.auto_fill_clear
    local exotic_widget = widgets.auto_fill_exotic
    if type(rare_node) ~= "table" or type(rare_node.position) ~= "table"
            or type(exotic_node) ~= "table" or type(exotic_node.position) ~= "table"
            or type(clear_node) ~= "table" or type(exotic_widget) ~= "table" then
        return false, "vanilla salvage anchors missing"
    end

    local modded_node = deep_copy(exotic_node)
    modded_node.position = next_position(rare_node.position, exotic_node.position)
    scenegraph.auto_fill_modded = modded_node

    clear_node.position = next_position(exotic_node.position, modded_node.position)

    local modded_widget = deep_copy(exotic_widget)
    modded_widget.scenegraph_id = "auto_fill_modded"
    modded_widget.content.texture_icon.texture_id = "store_tag_icon_weapon_modded"
    widgets.auto_fill_modded = modded_widget

    return true
end

function M.is_installed(definitions)
    local widgets = type(definitions) == "table" and definitions.widgets
    local scenegraph = type(definitions) == "table" and definitions.scenegraph_definition
    local widget = type(widgets) == "table" and widgets.auto_fill_modded
    local node = type(scenegraph) == "table" and scenegraph.auto_fill_modded
    return type(widget) == "table"
        and widget.scenegraph_id == "auto_fill_modded"
        and type(widget.content) == "table"
        and type(widget.content.texture_icon) == "table"
        and widget.content.texture_icon.texture_id == "store_tag_icon_weapon_modded"
        and type(node) == "table"
end

return M
