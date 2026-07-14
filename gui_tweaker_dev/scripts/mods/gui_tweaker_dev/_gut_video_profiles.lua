-- _gut_video_profiles.lua - native Video-options profile controls (#292).
--
-- Adds a profile selector and action selector to the existing Video settings
-- list. Profiles replay through the native widget callbacks, staging values in
-- OptionsView.changed_*; the native Apply path remains the sole writer and owns
-- save, reload/restart handling, and the timed revert popup
-- (options_view.lua:1919-2587, 3139-3163).
--
-- Owned by: gui_tweaker_dev.lua entry point. Consumed via: mod:dofile.
-- luacheck: globals OptionsView printf

local mod = get_mod("gut_dev")
local Core = mod:dofile("scripts/mods/gui_tweaker_dev/_gut_video_profiles_core")
local M = { rt_checks = {} }
local pending_delete

local function active_slot()
    return Core.slot(mod:get(Core.active_key()))
end

local function display_name(slot)
    local custom = mod:get(Core.name_key(slot))
    if type(custom) == "string" and custom ~= "" then return custom end
    return string.format("Profile %d", slot)
end

local function profile(slot)
    local value = mod:get(Core.slot_key(slot))
    return type(value) == "table" and value or nil
end

local function set_active(slot)
    slot = Core.slot(slot)
    mod:set(Core.active_key(), slot, false)
    return slot
end

local function video_widgets(self)
    local list = self and self.settings_lists and self.settings_lists.video_settings
    return list and list.widgets, list
end

local function replay(self, slot)
    local saved = profile(slot)
    if not saved then
        mod:echo("%s is empty. Choose Save Current to create it.", display_name(slot))
        return false
    end
    local widgets, list = video_widgets(self)
    local operations, skipped, err = Core.plan(widgets, saved)
    if err then
        mod:echo("Could not load %s: %s", display_name(slot), err)
        return false
    end
    for i = 1, #operations do
        local op = operations[i]
        local widget, content = op.widget, op.widget.content
        if op.selection then
            content.current_selection = op.selection
        else
            local min, max = content.min, content.max
            local value = math.max(min, math.min(max, op.value))
            content.value = value
            content.internal_value = (value - min) / (max - min)
        end
        content.callback(content, widget.style)
    end
    if list and type(self.set_widget_values) == "function" then self:set_widget_values(list) end
    printf("[gut:292] profile staged slot=%d applied=%d skipped=%d; native Apply required",
        slot, #operations, skipped)
    mod:echo("%s staged (%d settings). Click Apply to activate it.", display_name(slot), #operations)
    return true
end

local function save_current(self, slot)
    local widgets = video_widgets(self)
    local saved, count = Core.capture(widgets)
    mod:set(Core.slot_key(slot), saved, false)
    printf("[gut:292] profile saved slot=%d settings=%d", slot, count)
    mod:echo("Saved %d Video settings to %s.", count, display_name(slot))
end

local function queue_delete(self, slot)
    if not profile(slot) then
        mod:echo("%s is already empty.", display_name(slot))
        return
    end
    if not (Managers and Managers.popup and Managers.popup.queue_popup) then
        mod:echo("Delete confirmation is unavailable right now.")
        return
    end
    local ok, popup_id = pcall(function()
        return Managers.popup:queue_popup(
            mod:localize("gut_video_profile_delete_body"),
            mod:localize("gut_video_profile_delete_title"),
            "delete", mod:localize("gut_video_profile_delete_confirm"),
            "cancel", Localize("popup_choice_cancel"))
    end)
    if ok and popup_id then pending_delete = { id = popup_id, slot = slot, view = self } end
end

local function poll_delete()
    local pending = pending_delete
    if not pending then return end
    if not (Managers and Managers.popup) then pending_delete = nil; return end
    local ok, result = pcall(Managers.popup.query_result, Managers.popup, pending.id)
    if not ok or not result then return end
    pcall(Managers.popup.cancel_popup, Managers.popup, pending.id)
    pending_delete = nil
    if result == "delete" then
        mod:set(Core.slot_key(pending.slot), false, false)
        mod:set(Core.name_key(pending.slot), false, false)
        printf("[gut:292] profile deleted slot=%d", pending.slot)
        mod:echo("Deleted Profile %d.", pending.slot)
    end
end

local previous_update = mod.update
mod.update = function(dt)
    if previous_update then previous_update(dt) end
    poll_delete()
end

OptionsView.cb_gut_video_profile_setup = function(self)
    local options = {}
    for slot = 1, Core.MAX_SLOTS do
        local suffix = profile(slot) and " (saved)" or " (empty)"
        options[slot] = { value = slot, text = display_name(slot) .. suffix }
    end
    return active_slot(), options, "gut_video_profile_selector", 1
end

OptionsView.cb_gut_video_profile_saved_value = function(self, widget)
    widget.content.current_selection = active_slot()
end

OptionsView.cb_gut_video_profile = function(self, content)
    local slot = set_active(content.options_values[content.current_selection])
    replay(self, slot)
end

OptionsView.cb_gut_video_profile_action_setup = function(self)
    return 1, {
        { value = "none", text = mod:localize("gut_video_profile_action_none") },
        { value = "save", text = mod:localize("gut_video_profile_action_save") },
        { value = "delete", text = mod:localize("gut_video_profile_action_delete") },
    }, "gut_video_profile_action", 1
end

OptionsView.cb_gut_video_profile_action_saved_value = function(self, widget)
    widget.content.current_selection = 1
end

OptionsView.cb_gut_video_profile_action = function(self, content)
    local action = content.options_values[content.current_selection]
    local slot = active_slot()
    if action == "save" then save_current(self, slot)
    elseif action == "delete" then queue_delete(self, slot) end
    content.current_selection = 1
    content._last_selection = nil
end

local profile_elements = {
    { widget_type = "title", text = "gut_video_profiles_header", gut_video_profile_control = true },
    {
        widget_type = "drop_down", callback = "cb_gut_video_profile",
        setup = "cb_gut_video_profile_setup", saved_value = "cb_gut_video_profile_saved_value",
        tooltip_text = "gut_video_profile_selector_tooltip", ignore_upper_case = true,
        gut_video_profile_control = true,
    },
    {
        widget_type = "drop_down", callback = "cb_gut_video_profile_action",
        setup = "cb_gut_video_profile_action_setup", saved_value = "cb_gut_video_profile_action_saved_value",
        tooltip_text = "gut_video_profile_action_tooltip", ignore_upper_case = true,
        gut_video_profile_control = true,
    },
    { widget_type = "empty", size_y = 30, gut_video_profile_control = true },
}

-- Mandatory duplicate-hook preflight: this remains gut_dev's one singleton hook on
-- OptionsView.build_settings_list. The CKC bridge contributes its temporary row-type
-- rewrite through this hook instead of registering a colliding second hook (#528).
mod:hook("OptionsView", "build_settings_list", function(func, self, definition, scenegraph_id)
    local bridge = mod._gut_ckc_bridge
    local token = bridge and bridge.prepare_settings_definition
        and bridge.prepare_settings_definition(definition) or nil
    local built_definition = definition
    if scenegraph_id == "video_settings_list" then
        built_definition = {}
        for i = 1, #profile_elements do built_definition[#built_definition + 1] = profile_elements[i] end
        for i = 1, #definition do built_definition[#built_definition + 1] = definition[i] end
    end
    local ok, result = pcall(func, self, built_definition, scenegraph_id)
    if token and bridge and bridge.restore_settings_definition then
        bridge.restore_settings_definition(token)
    end
    if not ok then error(result) end
    return result
end)
mod._gut_video_profiles_hook_installed = true

mod:command("gut_video_profile_name", "Name a Video profile: /gut_video_profile_name <1-5> <name>", function(slot_arg, ...)
    local slot = tonumber(slot_arg)
    if not slot or slot < 1 or slot > Core.MAX_SLOTS then
        mod:echo("Usage: /gut_video_profile_name <1-5> <name>")
        return
    end
    local name = table.concat({ ... }, " "):gsub("[%c]", ""):sub(1, 32)
    if name == "" then mod:echo("Profile name cannot be empty."); return end
    mod:set(Core.name_key(slot), name, false)
    mod:echo("Profile %d is now named %s. Reopen Video options to refresh the list.", slot, name)
end)

M.rt_checks[#M.rt_checks + 1] = {
    name = "issue292_native_video_profile_pipeline",
    fn = function()
        if mod._gut_video_profiles_hook_installed ~= true then return "OptionsView list hook missing" end
        if type(Core.capture) ~= "function" or type(Core.plan) ~= "function" then return "profile core missing" end
        if type(OptionsView.cb_gut_video_profile) ~= "function" then return "profile selector callback missing" end
        if type(OptionsView.cb_gut_video_profile_action) ~= "function" then return "profile action callback missing" end
    end,
}

printf("[gut:292] Video profile controls installed; slots=%d native_apply=true", Core.MAX_SLOTS)
return M
