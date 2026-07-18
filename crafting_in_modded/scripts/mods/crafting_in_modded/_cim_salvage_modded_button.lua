-- _cim_salvage_modded_button.lua — Adds CIM's modded-rarity salvage autofill.
--
-- Extends both vanilla salvage layouts with a fifth rarity button and moves
-- Clear to the sixth position. Button presses reuse vanilla's bounded salvage
-- fill paths; no duplicate queue or inventory logic is maintained here.
--
-- Owned by: standard_forge.lua. Consumed via: mod:dofile.

local mod = get_mod("cim")
local core = mod:dofile("scripts/mods/crafting_in_modded/_cim_salvage_autofill_core")

local DEFINITION_PATHS = {
    "scripts/ui/views/hero_view/craft_pages/definitions/craft_page_salvage_definitions",
    "scripts/ui/views/hero_view/craft_pages/definitions/craft_page_salvage_console_definitions",
}

local installed_definitions = {}
for _, path in ipairs(DEFINITION_PATHS) do
    local definitions = local_require(path)
    local ok, err = core.install(definitions)
    if ok then
        installed_definitions[#installed_definitions + 1] = definitions
    else
        printf("[cim:618] salvage button install failed path=%s err=%s", path, tostring(err))
    end
end

printf("[cim:618] applied: modded salvage autofill layouts=%d cap=%s",
    #installed_definitions,
    tostring(CraftingSettings and CraftingSettings.NUM_SALVAGE_SLOTS))

-- Singleton preflight 2026-07-14: no existing cim hooks target either
-- salvage class's _handle_input or _update_animations method.
mod:hook("CraftPageSalvage", "_handle_input", function(func, self, ...)
    local widgets = self._widgets_by_name
    local widget = widgets and widgets.auto_fill_modded
    local pressed = widget and self:_is_button_pressed(widget)
    func(self, ...)
    if pressed then
        self:_fill_by_rarity("modded")
        printf("[cim:618] desktop autofill rarity=modded queued=%s cap=%s",
            tostring(self._num_craft_items),
            tostring(CraftingSettings.NUM_SALVAGE_SLOTS))
    end
end)

mod:hook_safe("CraftPageSalvage", "_update_animations", function(self, dt)
    local widgets = self._widgets_by_name
    if widgets and widgets.auto_fill_modded then
        UIWidgetUtils.animate_icon_button(widgets.auto_fill_modded, dt)
    end
end)

mod:hook("CraftPageSalvageConsole", "_handle_input", function(func, self, ...)
    local widgets = self._widgets_by_name
    local widget = widgets and widgets.auto_fill_modded
    local pressed = widget and UIUtils.is_button_pressed(widget)
    func(self, ...)
    if pressed and self.super_parent then
        self.super_parent:set_auto_fill_rarity("modded")
        printf("[cim:618] console autofill rarity=modded cap=%s",
            tostring(CraftingSettings.NUM_SALVAGE_SLOTS))
    end
end)

mod:hook_safe("CraftPageSalvageConsole", "_update_animations", function(self, dt)
    local widgets = self._widgets_by_name
    if widgets and widgets.auto_fill_modded then
        UIWidgetUtils.animate_icon_button(widgets.auto_fill_modded, dt)
    end
end)

mod._cim_rt_register("issue618_modded_salvage_autofill", function()
    if CraftingSettings.NUM_SALVAGE_SLOTS ~= 9 then
        return "salvage slot cap is not 9"
    end
    if #installed_definitions ~= #DEFINITION_PATHS then
        return "one or more salvage layouts rejected the modded button"
    end
    for _, definitions in ipairs(installed_definitions) do
        if not core.is_installed(definitions) then
            return "modded salvage button definition missing"
        end
    end
end)

return core
