-- Owns the two cosmetic-screen host surfaces and diagnostic commands for the
-- glow picker. The picker itself remains in _glow_picker.lua; this owner only
-- adapts the verified host windows and the manual diagnostic entry point.
--
-- Owned by: cosmetics_tweaker.lua entry point.
-- Consumed via: one ordered installer call after the glow probe is available.

local GlowPickerHost = {}

local function publish_owner(mod, state)
    local owner = mod._cos_glow_picker_host_owner
    if type(owner) ~= "table" then owner = {} end
    for key in pairs(owner) do owner[key] = nil end
    owner.hook_count = 5
    owner.command_count = 2
    owner.selected_slot_backend_id_and_data = state.selected_slot_backend_id_and_data
    mod._cos_glow_picker_host_owner = owner
    return owner
end

function GlowPickerHost.install(mod, deps)
    deps = deps or {}
    local state = mod._cos_glow_picker_host_state
    if not state then
        state = { installed = false }
        mod._cos_glow_picker_host_state = state
    end

    state.glow_picker = assert(deps.glow_picker, "glow_picker is required")
    state.printf = assert(deps.printf, "printf is required")
    state.mod_version = assert(deps.mod_version, "mod_version is required")
    state.wielded_units_for_probe = assert(
        deps.wielded_units_for_probe,
        "wielded_units_for_probe is required"
    )

    state.selected_slot_backend_id_and_data =
        state.selected_slot_backend_id_and_data or function(host_window)
            local idx = host_window and host_window._selected_cosmetic_slot_index
            local items = host_window and host_window._equipment_items
            if not idx or not items then return nil, nil end
            local item = items[idx]
            if not item then return nil, nil end
            return item.backend_id, item
        end

    mod._glow_hook_fired_once = mod._glow_hook_fired_once or {}

    if state.installed then return publish_owner(mod, state) end

    local function glow_hook_trace(class_name, event)
        local key = class_name .. ":" .. event
        if not mod._glow_hook_fired_once[key] then
            mod._glow_hook_fired_once[key] = true
            pcall(state.printf,
                "[cos:570] [glow_picker:hook] FIRST FIRE %s (open=%s)",
                key, tostring(state.glow_picker.is_open()))
            mod:info("[glow_picker:hook] FIRST FIRE %s (open=%s)",
                key, tostring(state.glow_picker.is_open()))
        end
    end

    local function resolve_input_service(self)
        return self.parent and self.parent.window_input_service
            and self.parent:window_input_service()
    end

    mod:hook_safe("HeroWindowCosmeticsLoadout", "on_exit", function(self, params)
        glow_hook_trace("HeroWindowCosmeticsLoadout", "on_exit")
        state.glow_picker.close()
    end)

    mod:hook_safe("HeroWindowCosmeticsLoadout", "update", function(self, dt, t)
        glow_hook_trace("HeroWindowCosmeticsLoadout", "update")
        if not state.glow_picker.is_open() then return end
        state.glow_picker.handle_input(resolve_input_service(self))
    end)

    mod:hook_safe("HeroWindowCosmeticsLoadout", "draw", function(self, dt)
        glow_hook_trace("HeroWindowCosmeticsLoadout", "draw")
        if not state.glow_picker.is_open() then return end
        local ui_renderer = self.ui_top_renderer or self.ui_renderer
        state.glow_picker.draw(ui_renderer, resolve_input_service(self), dt)
    end)

    mod:hook_safe("HeroWindowItemCustomization", "update", function(self, dt, t)
        glow_hook_trace("HeroWindowItemCustomization", "update")
        if not state.glow_picker.is_open() then return end
        state.glow_picker.handle_input(resolve_input_service(self), self)
    end)

    mod:hook_safe("HeroWindowItemCustomization", "_draw", function(self, input_service, dt)
        glow_hook_trace("HeroWindowItemCustomization", "_draw")
        if not state.glow_picker.is_open() then return end
        local ui_renderer = self._ui_top_renderer or self._ui_renderer
            or self.ui_top_renderer or self.ui_renderer
        state.glow_picker.draw(ui_renderer, input_service, dt, self)
    end)

    mod:command("glow_picker_hooks",
        "List which cosmetic-screen draw hooks have fired this session",
        function()
            mod:echo("[glow_picker:hooks] fired so far:")
            local n = 0
            for key in pairs(mod._glow_hook_fired_once) do
                mod:echo("  - %s", key)
                n = n + 1
            end
            if n == 0 then
                mod:echo("  (none — go to the loadout grid or click a weapon to open the illusion-change window)")
            end
            mod:echo("[glow_picker:hooks] GlowPicker.is_open=%s built=%s",
                tostring(state.glow_picker.is_open()),
                tostring(state.glow_picker._built))
        end)

    mod:command("glow_picker",
        "Open the glow customizer popup (M1 scaffold; debug-only entry point)",
        function()
            local picker = state.glow_picker
            mod:echo("[glow_picker] command fired. v=%s open_before=%s",
                state.mod_version, tostring(picker.is_open()))
            if picker.is_open() then
                picker.close()
                mod:echo("[glow_picker] closed")
                return
            end

            local units, slot_data = state.wielded_units_for_probe()
            local backend_id
            if units and units[1] and units[1].unit and mod._unit_to_backend_id then
                backend_id = mod._unit_to_backend_id[units[1].unit]
            end
            mod:echo("[glow_picker] resolved backend_id=%s (from _unit_to_backend_id[wielded_unit])",
                tostring(backend_id))
            picker.open_for(backend_id, slot_data)
            mod:echo("[glow_picker] open_after=%s built=%s. If you're NOT on a cosmetic menu, popup won't render — go to the cosmetic loadout screen. Then run /glow_picker_hooks to see which hook fires.",
                tostring(picker.is_open()), tostring(picker._built))
        end)

    state.installed = true
    return publish_owner(mod, state)
end

return GlowPickerHost
