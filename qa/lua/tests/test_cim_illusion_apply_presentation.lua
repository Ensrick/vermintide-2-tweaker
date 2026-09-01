return function(H, repo_root)
    local public_path = repo_root
        .. "/crafting_in_modded/scripts/mods/crafting_in_modded/_cim_illusion_apply_presentation.lua"
    local dev_path = repo_root
        .. "/crafting_in_modded_dev/scripts/mods/crafting_in_modded_dev/_cim_illusion_apply_presentation.lua"
    local Presentation = dofile(public_path)

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

    H.test("CIM #1465 public and Dev presentation owners are byte-identical", function()
        H.equal(read(public_path), read(dev_path))
        H.equal(Presentation.SCHEMA, 1)
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

        local _, owner, window, vanilla_pressed = fixture()
        window._widgets_by_name.experience_bar = nil
        local ok = pcall(owner.on_pressed, vanilla_pressed, window, 2, false, false)
        H.equal(ok, true)
        H.equal(window._skin_dirty, false)
        H.equal(#window._material_items, 0)
        H.equal(window._widgets_by_name.craft_button.content.visible, false)
    end)

    H.test("CIM #1465 official realm and presentation-only selections stay vanilla-owned", function()
        local state, owner, window, vanilla_pressed = fixture()
        state.modded = false
        state.hostile_after_selection = true
        owner.on_pressed(vanilla_pressed, window, 2, false, false)
        H.equal(window._widgets_by_name.craft_button.content.visible, false)
        H.equal(window._cim1465_apply_owned, nil)
        H.equal(window._cim563_pending_explicit_skin, nil)

        state.modded = true
        state.hostile_after_selection = false
        owner.on_pressed(vanilla_pressed, window, 2, true, true)
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

    H.test("CIM #1465 production wiring exposes one provider and named check", function()
        for _, row in ipairs({
            { "/crafting_in_modded/scripts/mods/crafting_in_modded/illusion_swap.lua",
              "scripts/mods/crafting_in_modded/_cim_illusion_apply_presentation" },
            { "/crafting_in_modded_dev/scripts/mods/crafting_in_modded_dev/illusion_swap.lua",
              "scripts/mods/crafting_in_modded_dev/_cim_illusion_apply_presentation" },
        }) do
            local source = read(repo_root .. row[1])
            H.truthy(source:find(row[2], 1, true) ~= nil)
            H.truthy(source:find("_cim_illusion_swap_provider", 1, true) ~= nil)
            H.truthy(source:find("issue1465_illusion_apply_presentation", 1, true) ~= nil)
            H.truthy(source:find("_apply_owner.on_enable", 1, true) ~= nil)
            H.truthy(source:find("_apply_owner.on_pressed", 1, true) ~= nil)
            H.truthy(source:find("_apply_owner.complete(self, \"craft-complete\")", 1, true) ~= nil)
            H.equal(source:find("log = function(fmt, ...) mod:info", 1, true), nil)
        end
    end)
end
