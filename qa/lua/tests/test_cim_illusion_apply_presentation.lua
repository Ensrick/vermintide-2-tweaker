return function(H, repo_root)
    local dev_path = repo_root
        .. "/crafting_in_modded_dev/scripts/mods/crafting_in_modded_dev/_cim_illusion_apply_presentation.lua"
    local Presentation = dofile(dev_path)
    local CosmeticsSwap = dofile(repo_root
        .. "/cosmetics_tweaker/scripts/mods/cosmetics_tweaker/_cos_modded_illusion_swap.lua")

    local function read(path)
        local file = assert(io.open(path, "rb"))
        local value = file:read("*a")
        file:close()
        return value
    end

    local function fixture()
        local state = {
            modded = true,
            current_item = { key = "weapon", skin = "skin_a" },
            defaults = { weapon = "skin_default" },
            skins = { skin_a = true, skin_b = true, skin_dlc = true },
            ids = { skin_a = "id-a", skin_b = "id-b", skin_dlc = "id-dlc" },
            denied = { skin_dlc = true },
            enable_calls = 0,
            bracket_calls = 0,
            logs = {},
        }
        local owner = Presentation.new({
            is_modded_realm = function() return state.modded end,
            with_eac_off = function(func, self, ...)
                state.bracket_calls = state.bracket_calls + 1
                return func(self, ...)
            end,
            skin_exists = function(skin) return state.skins[skin] == true end,
            skin_requires_unowned_dlc = function(skin)
                if state.dlc_throws then error("dlc-reader-boom") end
                return state.denied[skin] == true
            end,
            get_current_item = function()
                if state.item_throws then error("item-reader-boom") end
                return state.current_item
            end,
            default_skin_for = function(item)
                if state.default_throws then error("default-reader-boom") end
                return state.defaults[item.key]
            end,
            resolve_skin_backend_id = function(skin)
                if state.id_throws then error("id-reader-boom") end
                return state.ids[skin]
            end,
            log = function(fmt, ...)
                state.logs[#state.logs + 1] = string.format(fmt, ...)
            end,
        })

        local function widget()
            return { content = { visible = false } }
        end
        local window = {
            _current_recipe_name = "apply_weapon_skin",
            _item_backend_id = "weapon-bid",
            _material_items = {},
            _illusion_widgets = {
                { content = { skin_key = "skin_a", locked = false } },
                { content = { skin_key = "skin_b", locked = true } },
                { content = { skin_key = "skin_dlc", locked = true } },
                { content = { skin_key = "skin_missing", locked = true } },
            },
            _widgets_by_name = {
                craft_button = { content = { visible = false, button_hotspot = {
                    disable_button = true, is_held = false, input_pressed = false,
                } } },
                button_top_edge_left = widget(), button_top_edge_right = widget(),
                button_top_edge_glow = widget(), experience_bar = widget(),
                experience_bar_edge = widget(),
            },
        }

        local function vanilla_enable(self, enabled, disable_edges)
            state.enable_calls = state.enable_calls + 1
            local widgets = self._widgets_by_name
            widgets.craft_button.content.visible = enabled
            widgets.craft_button.content.button_hotspot.disable_button = not enabled
            widgets.experience_bar.content.visible = enabled
            widgets.experience_bar_edge.content.visible = enabled
            if state.hostile_enable then
                widgets.craft_button.content.visible = false
                widgets.craft_button.content.button_hotspot.disable_button = true
            end
            return "enable", nil, "tail"
        end
        window._enable_craft_button = function(self, enabled, disable_edges)
            return owner.on_enable(vanilla_enable, self, enabled, disable_edges)
        end

        local function vanilla_pressed(self, index, ignore_item_spawn)
            local content = self._illusion_widgets[index].content
            self._skin_dirty = false
            for key in pairs(self._material_items) do self._material_items[key] = nil end
            if not ignore_item_spawn then
                if not content.locked then
                    local current = state.current_item.skin
                        or state.defaults[state.current_item.key]
                    if content.skin_key ~= current then
                        self._material_items[1] = state.ids[content.skin_key]
                        self:_enable_craft_button(true, true)
                        self._skin_dirty = true
                    else
                        self:_enable_craft_button(false)
                    end
                else
                    self:_enable_craft_button(false)
                end
            end
            if state.hostile_after_selection then
                self._widgets_by_name.craft_button.content.visible = false
                self._widgets_by_name.craft_button.content.button_hotspot.disable_button = true
            end
            return "pressed", nil, "tail"
        end
        return state, owner, window, vanilla_pressed, vanilla_enable
    end

    local function wrap(callback, downstream)
        return function(self, ...)
            return callback(downstream, self, ...)
        end
    end

    local function chain(callbacks, vanilla)
        local current = vanilla
        for index = 1, #callbacks do
            current = wrap(callbacks[index], current)
        end
        return current
    end

    local function composed_case(modded, cosmetics_outermost)
        local state, owner, window, vanilla_pressed, vanilla_enable = fixture()
        state.modded = modded
        state.hostile_enable = modded
        state.hostile_after_selection = modded

        local dev_hooks = {}
        local dev_mod = {
            hook = function(_, _, method, callback)
                dev_hooks[method] = callback
            end,
        }
        Presentation.install(dev_mod, owner, function() end)

        local cosmetics_hooks = {}
        local glow_refreshes = 0
        local cosmetics_brackets = 0
        local cosmetics_dlc_checks = 0
        local cosmetics_mod = {
            hook = function(_, _, method, callback)
                cosmetics_hooks[method] = callback
            end,
            hook_safe = function(_, _, method, callback)
                cosmetics_hooks[method] = callback
            end,
            get = function() return false end,
            info = function() end,
            echo = function() end,
        }
        local cosmetics_owner = CosmeticsSwap.install(cosmetics_mod, {
            get_mod = function(name)
                if name == "cim_dev" then return dev_mod end
            end,
            with_eac_off = function(func, self, ...)
                cosmetics_brackets = cosmetics_brackets + 1
                return func(self, ...)
            end,
            skin_requires_unowned_dlc = function()
                cosmetics_dlc_checks = cosmetics_dlc_checks + 1
                return false
            end,
            custom_skin_keys = {},
            glow_picker = {
                is_open = function() return false end,
                is_open_for = function() return false end,
                close = function() end,
            },
            refresh_glow_editor_button = function()
                glow_refreshes = glow_refreshes + 1
            end,
            offhand_commit = { commit_for_backend = function() return 0 end },
            la_persist = {},
            debug = function() end,
            trace = function() end,
        })

        local function ordered(dev_callback, cosmetics_callback)
            if cosmetics_outermost then
                return { dev_callback, cosmetics_callback }
            end
            return { cosmetics_callback, dev_callback }
        end
        window._enable_craft_button = chain(ordered(
            dev_hooks._enable_craft_button,
            cosmetics_hooks._enable_craft_button), vanilla_enable)

        local vanilla_presses = 0
        local pressed = chain(ordered(
            dev_hooks._on_illusion_index_pressed,
            cosmetics_hooks._on_illusion_index_pressed), function(self, ...)
                vanilla_presses = vanilla_presses + 1
                return vanilla_pressed(self, ...)
            end)
        local a, b, c = pressed(window, 2, false, false)

        local state_updates = 0
        local ua, ub, uc = cosmetics_hooks._update_state_craft_button(
            function(_, recipe_name, marker)
                state_updates = state_updates + 1
                return recipe_name, nil, marker
            end, window, "apply_weapon_skin", "state-tail")

        local crafts = 0
        local request, recipe = cosmetics_hooks.craft(function()
            crafts = crafts + 1
            return "vanilla-request", { name = "apply_weapon_skin" }
        end, {}, "witch_hunter", { "weapon-bid", "skin-bid" },
            "apply_weapon_skin")

        return {
            state = state,
            owner = owner,
            window = window,
            dev_mod = dev_mod,
            cosmetics_owner = cosmetics_owner,
            glow_refreshes = glow_refreshes,
            cosmetics_brackets = cosmetics_brackets,
            cosmetics_dlc_checks = cosmetics_dlc_checks,
            vanilla_presses = vanilla_presses,
            pressed_returns = { a, b, c, n = 3 },
            state_updates = state_updates,
            update_returns = { ua, ub, uc, n = 3 },
            crafts = crafts,
            request = request,
            recipe = recipe,
        }
    end

    H.test("CIM Dev #1465 presentation owner exposes the exact schema", function()
        H.truthy(#read(dev_path) > 0)
        H.equal(Presentation.SCHEMA, 1)
    end)

    H.test("CIM Dev and Cosmetics compose one modded owner in both hook orders", function()
        for _, cosmetics_outermost in ipairs({ false, true }) do
            local result = composed_case(true, cosmetics_outermost)
            local window = result.window
            local craft = window._widgets_by_name.craft_button.content
            H.equal(result.dev_mod._cim_illusion_swap_provider.presentation_owner,
                result.owner)
            H.equal(result.cosmetics_owner.owns_illusion_swap(), true)
            H.equal(result.vanilla_presses, 1)
            H.equal(result.glow_refreshes, 1)
            H.equal(result.cosmetics_brackets, 0)
            H.equal(result.cosmetics_dlc_checks, 0)
            H.equal(result.pressed_returns[1], "pressed")
            H.equal(result.pressed_returns[2], nil)
            H.equal(result.pressed_returns[3], "tail")
            H.equal(window._skin_dirty, true)
            H.equal(window._has_all_crafting_requirements, true)
            H.equal(window._material_items[1], "id-b")
            H.equal(window._cim563_pending_explicit_skin, "skin_b")
            H.equal(window._cim1465_apply_owned, true)
            H.equal(craft.visible, true)
            H.equal(craft.button_hotspot.disable_button, false)
            H.equal(result.state.enable_calls, 2)
            H.equal(result.state.bracket_calls, 2)
            H.equal(result.state_updates, 1)
            H.equal(result.update_returns[1], "apply_weapon_skin")
            H.equal(result.update_returns[2], nil)
            H.equal(result.update_returns[3], "state-tail")
            H.equal(result.crafts, 1)
            H.equal(result.request, "vanilla-request")
            H.equal(result.recipe.name, "apply_weapon_skin")
        end
    end)

    H.test("CIM Dev and Cosmetics composed official realm stays vanilla-owned", function()
        for _, cosmetics_outermost in ipairs({ false, true }) do
            local result = composed_case(false, cosmetics_outermost)
            local window = result.window
            H.equal(result.cosmetics_owner.owns_illusion_swap(), true)
            H.equal(result.vanilla_presses, 1)
            H.equal(result.glow_refreshes, 1)
            H.equal(result.cosmetics_brackets, 0)
            H.equal(result.cosmetics_dlc_checks, 0)
            H.equal(result.state.bracket_calls, 0)
            H.equal(result.state.enable_calls, 1)
            H.equal(window._illusion_widgets[2].content.locked, true)
            H.equal(window._skin_dirty, false)
            H.equal(#window._material_items, 0)
            H.equal(window._cim1465_apply_owned, nil)
            H.equal(window._cim563_pending_explicit_skin, nil)
            H.equal(window._widgets_by_name.craft_button.content.visible, false)
            H.equal(window._widgets_by_name.craft_button.content.button_hotspot.disable_button,
                true)
            H.equal(result.state_updates, 1)
            H.equal(result.crafts, 1)
        end
    end)

    H.test("CIM #1465 actual selection hook restores the complete Apply postcondition", function()
        local state, owner, window, vanilla_pressed = fixture()
        state.hostile_enable = true
        state.hostile_after_selection = true
        local a, b, c = owner.on_pressed(vanilla_pressed, window, 2, false, false)
        local craft = window._widgets_by_name.craft_button.content
        H.equal(a, "pressed")
        H.equal(b, nil)
        H.equal(c, "tail")
        H.equal(window._skin_dirty, true)
        H.equal(window._has_all_crafting_requirements, true)
        H.equal(window._material_items[1], "id-b")
        H.equal(#window._material_items, 1)
        H.equal(window._cim563_pending_explicit_skin, "skin_b")
        H.equal(window._cim1465_apply_owned, true)
        H.equal(craft.visible, true)
        H.equal(craft.button_hotspot.disable_button, false)
        H.equal(craft.button_hotspot.is_held, false)
        H.equal(window._widgets_by_name.experience_bar.content.visible, true)
        H.truthy(state.enable_calls >= 2)
        H.equal(state.enable_calls, state.bracket_calls)
        H.truthy(#state.logs >= 1)
    end)

    H.test("CIM #1465 current, DLC, and missing-id selections fail closed", function()
        local state, owner, window, vanilla_pressed = fixture()
        owner.on_pressed(vanilla_pressed, window, 2, false, false)
        state.current_item.skin = "skin_b"
        owner.on_pressed(vanilla_pressed, window, 2, false, false)
        H.equal(window._skin_dirty, false)
        H.equal(#window._material_items, 0)
        H.equal(window._widgets_by_name.craft_button.content.visible, false)

        state.current_item.skin = "skin_a"
        owner.on_pressed(vanilla_pressed, window, 3, false, false)
        H.equal(window._illusion_widgets[3].content.locked, true)
        H.equal(window._widgets_by_name.craft_button.content.visible, false)
        H.equal(window._cim563_pending_explicit_skin, nil)

        state.skins.skin_missing = true
        owner.on_pressed(vanilla_pressed, window, 4, false, false)
        H.equal(window._skin_dirty, false)
        H.equal(window._widgets_by_name.craft_button.content.visible, false)
        H.equal(window._widgets_by_name.craft_button.content.button_hotspot.disable_button, true)
    end)

    H.test("CIM #1465 resolver failures and missing widgets never leave hidden active state", function()
        for _, mode in ipairs({
            "item_throws", "id_throws", "dlc_throws", "default_throws",
        }) do
            local state, owner, window, vanilla_pressed = fixture()
            state[mode] = true
            if mode == "default_throws" then state.current_item.skin = nil end
            local ok = pcall(owner.on_pressed, vanilla_pressed, window, 2, false, false)
            H.equal(ok, true)
            H.equal(window._skin_dirty, false)
            H.equal(#window._material_items, 0)
            H.equal(window._cim1465_apply_owned, false)
        end

        local state, owner, window, vanilla_pressed = fixture()
        state.current_item.skin = nil
        state.defaults.weapon = nil
        local ok = pcall(owner.on_pressed, vanilla_pressed, window, 2, false, false)
        H.equal(ok, true)
        H.equal(window._skin_dirty, false)
        H.equal(#window._material_items, 0)
        H.equal(window._cim1465_apply_owned, false)

        local _, missing_owner, missing_window, missing_pressed = fixture()
        missing_window._widgets_by_name.experience_bar = nil
        local missing_ok = pcall(
            missing_owner.on_pressed, missing_pressed, missing_window, 2, false, false)
        H.equal(missing_ok, true)
        H.equal(missing_window._skin_dirty, false)
        H.equal(#missing_window._material_items, 0)
        H.equal(missing_window._widgets_by_name.craft_button.content.visible, false)
    end)

    H.test("CIM #1465 official realm and presentation-only selections stay vanilla-owned", function()
        local state, owner, window, vanilla_pressed = fixture()
        state.modded = false
        state.hostile_after_selection = true
        owner.on_pressed(vanilla_pressed, window, 2, false, false)
        H.equal(window._widgets_by_name.craft_button.content.visible, false)
        H.equal(window._illusion_widgets[2].content.locked, true)
        H.equal(window._cim1465_apply_owned, nil)
        H.equal(window._cim563_pending_explicit_skin, nil)
        H.equal(state.bracket_calls, 0)

        state.modded = true
        state.hostile_after_selection = false
        owner.on_pressed(vanilla_pressed, window, 2, true, true)
        H.equal(window._illusion_widgets[2].content.locked, true)
        H.equal(window._cim1465_apply_owned, nil)
        H.equal(window._cim563_pending_explicit_skin, nil)
    end)

    H.test("CIM #1465 official-realm disable preserves the downstream presentation", function()
        local state, owner, window = fixture()
        state.modded = false
        local function downstream(self)
            self._widgets_by_name.craft_button.content.visible = true
            self._widgets_by_name.craft_button.content.button_hotspot.disable_button = false
            return "official"
        end
        H.equal(owner.on_enable(downstream, window, false, nil), "official")
        H.equal(window._widgets_by_name.craft_button.content.visible, true)
        H.equal(window._widgets_by_name.craft_button.content.button_hotspot.disable_button, false)
        H.equal(state.bracket_calls, 0)
    end)

    H.test("CIM #1465 release mutates only an adapter-owned presentation", function()
        local _, owner, window, vanilla_pressed = fixture()
        local calls_before = 0
        local original_enable = window._enable_craft_button
        window._enable_craft_button = function(self, ...)
            calls_before = calls_before + 1
            return original_enable(self, ...)
        end
        H.equal(select(1, owner.release(window, "never-active")), false)
        H.equal(calls_before, 0)

        owner.on_pressed(vanilla_pressed, window, 2, false, false)
        local calls_active = calls_before
        H.equal(select(1, owner.release(window, "window-exit")), true)
        H.equal(calls_before, calls_active + 1)
        H.equal(window._skin_dirty, false)
        H.equal(#window._material_items, 0)
        H.equal(window._widgets_by_name.craft_button.content.visible, false)
        H.equal(window._cim1465_apply_owned, false)
    end)

    H.test("CIM #1465 craft completion preserves intent then releases every owned field", function()
        local _, owner, window, vanilla_pressed = fixture()
        owner.on_pressed(vanilla_pressed, window, 2, false, false)
        window._craft_progress = 0.75
        window._playing_craft_sound = true

        local pending, released = owner.complete(window, "craft-complete")
        H.equal(pending, "skin_b")
        H.equal(released, true)
        H.equal(window._cim563_pending_explicit_skin, nil)
        H.equal(window._skin_dirty, false)
        H.equal(window._has_all_crafting_requirements, false)
        H.equal(#window._material_items, 0)
        H.equal(window._craft_progress, 0)
        H.equal(window._playing_craft_sound, false)
        H.equal(window._widgets_by_name.craft_button.content.visible, false)
        H.equal(window._widgets_by_name.experience_bar.content.visible, false)
    end)

    H.test("CIM #1465 enable hook preserves nil-hole returns and runtime check passes", function()
        local _, owner, window, _, vanilla_enable = fixture()
        local a, b, c = owner.on_enable(vanilla_enable, window, true, true)
        H.equal(a, "enable")
        H.equal(b, nil)
        H.equal(c, "tail")
        H.equal(owner.runtime_check(), nil)
    end)

    H.test("CIM Dev #1465 publishes no provider after incomplete installation", function()
        local _, owner = fixture()
        for _, contract in ipairs({
            { failure = "first-hook", hooks = 1, checks = 0 },
            { failure = "second-hook", hooks = 2, checks = 0 },
            { failure = "runtime-check", hooks = 2, checks = 1 },
        }) do
            local hook_calls = 0
            local check_calls = 0
            local mod = {
                hook = function()
                    hook_calls = hook_calls + 1
                    if contract.failure == "first-hook" and hook_calls == 1 then
                        error("hook-registration-boom")
                    end
                    if contract.failure == "second-hook" and hook_calls == 2 then
                        error("hook-registration-boom")
                    end
                end,
            }
            local function register_check()
                check_calls = check_calls + 1
                if contract.failure == "runtime-check" then
                    error("check-registration-boom")
                end
            end
            local ok = pcall(Presentation.install, mod, owner, register_check)
            H.equal(ok, false)
            H.equal(hook_calls, contract.hooks)
            H.equal(check_calls, contract.checks)
            H.equal(mod._cim_illusion_apply_presentation_owner, nil)
            H.equal(mod._cim_illusion_swap_provider, nil)
        end

        local missing_hook_calls = 0
        local missing_check = { hook = function()
            missing_hook_calls = missing_hook_calls + 1
        end }
        H.equal(pcall(Presentation.install, missing_check, owner, nil), false)
        H.equal(missing_hook_calls, 0)
        H.equal(missing_check._cim_illusion_apply_presentation_owner, nil)
        H.equal(missing_check._cim_illusion_swap_provider, nil)

        local incomplete_hook_calls = 0
        local incomplete_mod = { hook = function()
            incomplete_hook_calls = incomplete_hook_calls + 1
        end }
        H.equal(pcall(Presentation.install, incomplete_mod, {
            on_enable = function() end,
            on_pressed = function() end,
            owns_illusion_swap = function() return true end,
        }, function() end), false)
        H.equal(incomplete_hook_calls, 0)
        H.equal(incomplete_mod._cim_illusion_swap_provider, nil)

        local calls = {}
        local installed = {
            hook = function(_, class, method, callback)
                calls[#calls + 1] = { class, method, callback }
            end,
        }
        local provider = Presentation.install(installed, owner, function(name, callback)
            calls[#calls + 1] = { name, callback }
        end)
        H.equal(#calls, 3)
        H.equal(calls[1][2], "_enable_craft_button")
        H.equal(calls[2][2], "_on_illusion_index_pressed")
        H.equal(calls[3][1], "issue1465_illusion_apply_presentation")
        H.equal(calls[3][2], owner.runtime_check)
        H.equal(installed._cim_illusion_apply_presentation_owner, owner)
        H.equal(installed._cim_illusion_swap_provider, provider)
        H.equal(provider.schema, 1)
        H.equal(provider.owns_illusion_swap(), true)
    end)

    H.test("CIM Dev #1465 production wiring exposes one provider and named check", function()
        local source = read(repo_root
            .. "/crafting_in_modded_dev/scripts/mods/crafting_in_modded_dev/illusion_swap.lua")
        local forge_source = read(repo_root
            .. "/crafting_in_modded_dev/scripts/mods/crafting_in_modded_dev/standard_forge.lua")
        H.truthy(source:find(
            "scripts/mods/crafting_in_modded_dev/_cim_illusion_apply_presentation",
            1, true) ~= nil)
        local install = "_APPLY_PRESENTATION.install(mod, _apply_owner, mod._cim_rt_register)"
        local install_at = source:find(install, 1, true)
        local last_command = source:find('mod:command("mirror_dump"', 1, true)
        H.truthy(install_at ~= nil)
        H.truthy(last_command ~= nil and install_at > last_command)
        H.truthy(source:sub(install_at + #install):match("^%s*$") ~= nil)
        H.equal(source:find("mod._cim_illusion_swap_provider =", 1, true), nil)
        H.truthy(source:find(
            "_apply_owner.complete(self, \"craft-complete\")", 1, true) ~= nil)
        H.equal(source:find("log = function(fmt, ...) mod:info", 1, true), nil)
        H.truthy(read(dev_path):find(
            'mod:hook("HeroWindowItemCustomization", "_enable_craft_button", owner.on_enable)',
            1, true) ~= nil)
        H.truthy(read(dev_path):find(
            'register_check("issue1465_illusion_apply_presentation", owner.runtime_check)',
            1, true) ~= nil)
        H.truthy(forge_source:find(
            "owner.release(self, \"window-exit\")", 1, true) ~= nil)
    end)
end
