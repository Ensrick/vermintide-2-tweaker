-- Athanor presentation owner extracted from the ordered entry seam.
-- Owns widget helpers, accessory/overview controls, tooltip/polish behavior,
-- and the two presentation-only hooks. It does not own forge persistence,
-- loadout writes, backend mutation, or wire/network behavior.

return function(ctx)
    assert(type(ctx) == "table", "_cim_forge_ui_owner requires context")
    local mod = assert(ctx.mod, "_cim_forge_ui_owner requires mod")
    assert(type(ctx.is_active) == "function", "_cim_forge_ui_owner requires is_active")
    assert(type(ctx.get_bg_colored) == "function",
        "_cim_forge_ui_owner requires get_bg_colored")
    assert(type(ctx.set_bg_colored) == "function",
        "_cim_forge_ui_owner requires set_bg_colored")
    assert(type(ctx.get_managers) == "function",
        "_cim_forge_ui_owner requires get_managers")
    assert(type(ctx.get_profiles) == "function",
        "_cim_forge_ui_owner requires get_profiles")

    local state = mod._cim_forge_ui_owner_state
    if not state then
        state = { installed = false, exports = {} }
        mod._cim_forge_ui_owner_state = state
    end

    -- Refresh dependencies before the idempotence guard. Registered callbacks
    -- close over this stable holder, so a reload cannot retain stale entry locals.
    state.is_active = ctx.is_active
    state.get_bg_colored = ctx.get_bg_colored
    state.set_bg_colored = ctx.set_bg_colored
    state.get_managers = ctx.get_managers
    state.get_profiles = ctx.get_profiles
    state.accessory_panel = ctx.accessory_panel
    state.ranalds_browser = ctx.ranalds_browser
    state.print_line = ctx.print_line or function() end

    -- The panel module can be replaced by a dev reload while this owner's hooks
    -- remain installed. Publish one stable callback onto every current panel
    -- before the guard; the callback resolves both the panel and craft helper at
    -- call time instead of retaining the first panel instance.
    if not state.accessory_on_craft then
        state.accessory_on_craft = function(slot_index, slot_name)
            local panel = state.accessory_panel
            local properties_win = panel and panel._properties_win
            if properties_win and mod._cim_amulet_craft_one_slot then
                mod._cim_amulet_craft_one_slot(properties_win, slot_index, slot_name)
            else
                mod:warning("[cim] accessory craft helper not ready")
            end
        end
    end
    if state.accessory_panel then
        state.accessory_panel._on_craft = state.accessory_on_craft
    end

    if state.installed then
        return state.exports, false
    end
    state.installed = true

    -- --- Forge UI polish (runs each frame while forge is open) ---

    local function _forge_get_widget(window, widget_name)
        local wbn = window and window._widgets_by_name
        return wbn and wbn[widget_name]
    end

    local function _forge_hide_widget(window, widget_name)
        local w = _forge_get_widget(window, widget_name)
        if w and w.content then w.content.visible = false end
    end

    local function _forge_set_text(window, widget_name, text)
        local w = _forge_get_widget(window, widget_name)
        if w and w.content then w.content.text = text end
    end

    local function _forge_set_style_color(window, widget_name, style_key, color)
        local w = _forge_get_widget(window, widget_name)
        if w and w.style and w.style[style_key] then
            w.style[style_key].color = color
        end
    end

    local function _forge_is_hovered(widget)
        if not widget or not widget.content then return false end
        local hs = widget.content.button_hotspot or widget.content.hotspot
        return hs and hs.is_hover
    end

    -- ============================================================
    -- Amulet view: 3 stacked craft buttons (v0.7.32+)
    -- ============================================================
    -- User-requested 2026-05-23: replace the rotating Amulet-of-Ashur 3D model in
    -- HeroWindowWeaveProperties' amulet view with 3 vertically-stacked craft
    -- buttons (Necklace / Charm / Trinket). Each crafts exactly one slot from the
    -- current bubble state. Supersedes the single "Craft All" upgrade_button
    -- which dirty-tracked + crafted all edited slots in one click.
    --
    -- Slot order matches `_AMULET_SLOT_BY_INDEX` (declared later in this file).
    -- Hard-coded here to avoid a forward-ref cycle; the indices must match
    -- _AMULET_SLOT_BY_INDEX[1]=ring(charm), [2]=necklace, [3]=trinket_1.
    local _AMULET_SLOT_BUTTONS = {
        -- Visual top-to-bottom order: Necklace, Charm, Trinket. `idx` references
        -- the slot in _AMULET_SLOT_BY_INDEX; `slot` is the legacy slot name VT2's
        -- career_settings uses (slot_ring not slot_charm, slot_trinket_1 not
        -- slot_trinket — see AMULET_OF_ASHUR.md).
        { idx = 2, slot = "slot_necklace",  label = "CRAFT NECKLACE", widget_name = "cim_amulet_btn_necklace" },
        { idx = 1, slot = "slot_ring",      label = "CRAFT CHARM",    widget_name = "cim_amulet_btn_charm"    },
        { idx = 3, slot = "slot_trinket_1", label = "CRAFT TRINKET",  widget_name = "cim_amulet_btn_trinket"  },
    }

    -- v0.7.64-dev: TEMPORARILY DISABLED. v0.7.63's render-array fix made these draw,
    -- but anchored to the full-size center/bottom "viewport" node they land in the
    -- bottom-left corner, render a screen-covering black box over the property/trait
    -- grid, and their hotspots overlap (one click fired two slots). Same failure
    -- class as the overview buttons. Disabled so the accessories view is usable
    -- (vanilla "Craft All" path restored). Re-enable once placement + hotspots are
    -- redone against a real screenshot of the live cim accessories view.
    local _AMULET_BTNS_ENABLED = false

    -- Lazy-create the 3 cim button widgets on the properties_win. Returns the
    -- widget array (or nil if VT2 UIWidgets isn't available — defensive).
    local function _ensure_amulet_buttons(properties_win)
        if properties_win._cim_amulet_buttons then return properties_win._cim_amulet_buttons end
        local UIWidgets = rawget(_G, "UIWidgets")
        local UIWidget = rawget(_G, "UIWidget")
        if not (UIWidgets and UIWidget and UIWidgets.create_default_button) then return nil end

        local btn_size = { 452, 80 }
        local spacing  = 95   -- vertical distance between button centers (button h=80 + 15 gap)
        local buttons  = {}
        -- v0.7.63-dev: HeroWindowWeaveProperties has NO self._widgets — like the
        -- overview, its _draw iterates _top_widgets/_bottom_widgets/_top_hdr_widgets/
        -- _bottom_hdr_widgets. The old code appended to ._widgets (nil here), so the
        -- accessory craft buttons NEVER rendered. Append to _top_widgets (drawn on
        -- the ui_top_renderer pass) + register in _widgets_by_name. Scenegraph is
        -- _ui_scenegraph; the center anchor "viewport" (where the 3D amulet renders,
        -- now hidden in amulet mode) is a valid node in this window.
        local draw_widgets    = properties_win._top_widgets
        local widgets_by_name = properties_win._widgets_by_name
        local scenegraph      = properties_win._ui_scenegraph
        if not (draw_widgets and widgets_by_name and scenegraph) then
            if not properties_win._cim_amulet_btn_logged_miss then
                properties_win._cim_amulet_btn_logged_miss = true
                mod:info("[cim] amulet buttons skipped: _top_widgets=%s _widgets_by_name=%s _ui_scenegraph=%s",
                    tostring(draw_widgets), tostring(widgets_by_name), tostring(scenegraph))
            end
            return nil
        end
        local anchor = rawget(scenegraph, "viewport") and "viewport" or "window"

        for i, entry in ipairs(_AMULET_SLOT_BUTTONS) do
            -- All 3 widgets share the center anchor. `widget.offset` shifts each
            -- vertically: i=1 → +spacing (top), i=2 → 0 (middle), i=3 → -spacing.
            -- Z=100 so they render above the bubble grid background.
            local ok, def = pcall(UIWidgets.create_default_button,
                anchor, btn_size, nil, nil, entry.label, 24,
                nil, "button_detail_02", nil, true)
            if not ok or not def then
                mod:info("[cim] amulet button %s create failed: %s", entry.widget_name, tostring(def))
                return nil
            end
            local ok_init, w = pcall(UIWidget.init, def)
            if not ok_init or not w then
                mod:info("[cim] amulet button %s init failed: %s", entry.widget_name, tostring(w))
                return nil
            end
            local y_offset = -(i - 2) * spacing
            w.offset = { 0, y_offset, 100 }
            w.content.visible = false
            w.content._cim_slot_index = entry.idx
            w.content._cim_slot_name  = entry.slot
            w.content._cim_label      = entry.label
            buttons[i] = w
            draw_widgets[#draw_widgets + 1] = w
            widgets_by_name[entry.widget_name] = w
        end

        properties_win._cim_amulet_buttons = buttons
        mod:info("[cim] amulet view: created %d cim craft buttons (anchor=%s)", #buttons, anchor)
        return buttons
    end

    local function _show_amulet_buttons(properties_win, show)
        local buttons = properties_win._cim_amulet_buttons
        if not buttons then return end
        for _, w in ipairs(buttons) do
            if w and w.content then w.content.visible = show and true or false end
        end
    end

    -- Per-frame click probe. The button's hotspot fires `on_release = true` on the
    -- frame the user lifts their mouse over a hovered hotspot. We consume that by
    -- invoking the craft path and clearing the flag, otherwise the click repeats.
    -- The per-slot craft helper itself is `_amulet_craft_one_slot`, defined alongside
    -- `_upgrade_magic_level`'s hook below — it lives there so the existing
    -- amulet-craft branch and the new per-button branch share one source of truth.
    local function _handle_amulet_button_clicks(properties_win)
        local buttons = properties_win._cim_amulet_buttons
        if not buttons then return end
        for _, w in ipairs(buttons) do
            local hs = w and w.content and w.content.button_hotspot
            if hs and hs.on_release then
                hs.on_release = false  -- consume immediately to prevent re-fire
                local slot_index = w.content._cim_slot_index
                local slot_name  = w.content._cim_slot_name
                if mod._cim_amulet_craft_one_slot then
                    mod._cim_amulet_craft_one_slot(properties_win, slot_index, slot_name)
                else
                    mod:echo("[cim] amulet craft helper not ready (load order bug)")
                end
            end
        end
    end

    -- ============================================================
    -- Accessory craft panel (v0.7.65-dev) — the CORRECT approach
    -- ============================================================
    -- The inline create_default_button buttons (overview + _ensure_amulet_buttons)
    -- are both DISABLED — anchored to the full-size center "viewport" node they
    -- produced a screen-covering black box, corner placement, and overlapping
    -- hotspots. This replaces them with the own-scenegraph overlay module
    -- `_accessory_craft_panel.lua`, which follows cosmetics_tweaker's proven
    -- `_glow_picker.lua` pattern: 3 hand-rolled buttons with EXPLICIT positions,
    -- drawn in their own pass off HeroWindowWeaveProperties._draw. No host-window
    -- widget injection, no viewport anchor, no black box, non-overlapping hotspots.
    local _AMULET_PANEL_ENABLED = true

    -- Draw the overlay off HeroWindowWeaveProperties._draw. hook_safe (post) so
    -- vanilla finishes its own passes first; we then run our own pass on the
    -- window's ui_top_renderer. Only in the accessories (amulet) view of the
    -- custom forge. This is the ONLY cim hook on HeroWindowWeaveProperties._draw
    -- (grep-verified — no duplicate-hook violation). Register it even when the
    -- optional panel failed its first load: it safely no-ops until a later reload
    -- supplies a panel, without registering a second hook.
    mod:hook_safe("HeroWindowWeaveProperties", "_draw", function(self, dt)
        local panel = state.accessory_panel
        if not (_AMULET_PANEL_ENABLED and panel and state.is_active()) then return end
        local params = self._params
        local sel_item = params and params.selected_item
        local in_amulet_mode = not (sel_item and sel_item.backend_id)
        if not in_amulet_mode then return end
        panel._properties_win = self
        local renderer = self._ui_top_renderer
        local input_service = self._parent and self._parent.window_input_service
            and self._parent:window_input_service()
        panel.draw(renderer, input_service, dt)
    end)

    -- ============================================================
    -- Athanor OVERVIEW (B-menu landing page) jewelry craft buttons
    -- ============================================================
    -- v0.7.57-dev. User request 2026-05-28: put 3 jewelry-craft buttons on the
    -- B-menu Athanor overview page, in the space where the Amulet of Ashur 3D
    -- display used to render (center viewport_2). Each button crafts ONE accessory
    -- of the chosen slot type for the current career — same path the standard
    -- forge accessory buttons + `/cim_craft_*` commands use.
    --
    -- These buttons are SIBLING to the existing per-slot buttons in
    -- HeroWindowWeaveProperties (the properties editor) — they fire even when
    -- the user hasn't navigated into the property editor, just from the overview.
    --
    -- Sized 452x80 to roughly match the original "Craft All" upgrade_button the
    -- overview used to display (now hidden in _forge_apply_ui_polish).
    local _OVERVIEW_JEWELRY_BUTTONS = {
        -- Visual top-to-bottom order: Necklace, Charm, Trinket. Same order +
        -- slot semantics as the properties-view buttons above. `synth_filter`
        -- targets the `_make_craft_synth` factory in standard_forge.lua via
        -- the cross-module `mod._cim_craft_via_synth` API.
        { synth_filter = { necklace = true }, friendly = "necklace", label = "CRAFT NECKLACE", widget_name = "cim_ov_btn_necklace" },
        { synth_filter = { ring     = true }, friendly = "charm",    label = "CRAFT CHARM",    widget_name = "cim_ov_btn_charm"    },
        { synth_filter = { trinket  = true }, friendly = "trinket",  label = "CRAFT TRINKET",  widget_name = "cim_ov_btn_trinket"  },
    }

    -- HeroWindowWeaveForgeOverview._draw iterates FOUR hardcoded arrays (it has no
    -- unified `_widgets`). Buttons must be appended to one of these or they never
    -- render. _OVERVIEW_BTN_RENDER_FIELD is the array we use; the
    -- `overview_btn_render_target` regression test pins it to this valid set so a
    -- future edit can't silently point it back at a `_widgets` field that the
    -- window never draws (the v0.7.57/.58 "nothing changed" bug, root-caused
    -- v0.7.60).
    local _OVERVIEW_DRAWN_FIELDS = {
        _top_widgets        = true,
        _bottom_widgets     = true,
        _top_hdr_widgets    = true,
        _bottom_hdr_widgets = true,
    }
    local _OVERVIEW_BTN_RENDER_FIELD = "_top_widgets"

    -- v0.7.61-dev: TEMPORARILY DISABLED. The render-array fix (v0.7.60) made the
    -- buttons draw, but they land on top of the overview's weapon-type selectors
    -- (viewport_1/2/3 = primary/accessories/secondary) and obscure the whole menu
    -- — anchoring 452x80 buttons to viewport_2 (a near-fullscreen center/bottom
    -- node) puts them in a corner over the real UI. Disabled until the placement is
    -- nailed against an actual screenshot of the live cim overview, so the B-menu
    -- is usable in the meantime. Flip back to true once anchor/size are correct.
    local _OVERVIEW_BTNS_ENABLED = false

    local function _ensure_overview_jewelry_buttons(overview_win)
        if overview_win._cim_overview_jewelry_buttons then return overview_win._cim_overview_jewelry_buttons end
        local UIWidgets = rawget(_G, "UIWidgets")
        local UIWidget  = rawget(_G, "UIWidget")
        if not (UIWidgets and UIWidget and UIWidgets.create_default_button) then
            if not overview_win._cim_ov_btn_logged_miss_uiwidgets then
                overview_win._cim_ov_btn_logged_miss_uiwidgets = true
                mod:info("[cim] overview jewelry buttons skipped: UIWidgets/UIWidget missing")
            end
            return nil
        end

        -- v0.7.60-dev: HeroWindowWeaveForgeOverview has NO self._widgets array.
        -- Vanilla _draw (hero_window_weave_forge_overview.lua:704-770) iterates
        -- four hardcoded arrays — _bottom_hdr_widgets, _top_hdr_widgets,
        -- _top_widgets, _bottom_widgets — plus _viewports_data. It never touches
        -- a `_widgets` field. The previous code appended to overview_win._widgets
        -- (nil on this class) so the buttons were in a collection the window never
        -- drew: they NEVER rendered, which is exactly the "nothing changed" report.
        -- Fix: append to _top_widgets (drawn on the ui_top_renderer pass, above the
        -- viewport art and still input-serviced so the hotspot fires), keep
        -- registering in _widgets_by_name so _forge_hide_widget/_forge_get_widget
        -- keep working. Scenegraph is self._ui_scenegraph (NOT .ui_scenegraph),
        -- and the valid center anchor is "viewport_2" (viewport_1/2/3 exist; bare
        -- "viewport" does NOT — old fallback was a dead id).
        local draw_widgets    = overview_win[_OVERVIEW_BTN_RENDER_FIELD]
        local widgets_by_name = overview_win._widgets_by_name
        local scenegraph      = overview_win._ui_scenegraph
        if not (draw_widgets and widgets_by_name and scenegraph) then
            if not overview_win._cim_ov_btn_logged_miss_widgets then
                overview_win._cim_ov_btn_logged_miss_widgets = true
                mod:info("[cim] overview jewelry buttons skipped: %s=%s _widgets_by_name=%s _ui_scenegraph=%s",
                    _OVERVIEW_BTN_RENDER_FIELD, tostring(draw_widgets), tostring(widgets_by_name), tostring(scenegraph))
            end
            return nil
        end

        -- Center anchor; fall back to the always-present root "window" id (never
        -- the bogus "viewport") if viewport_2 is somehow absent.
        local anchor = rawget(scenegraph, "viewport_2") and "viewport_2" or "window"

        local btn_size = { 452, 80 }
        local spacing  = 95
        local buttons  = {}

        for i, entry in ipairs(_OVERVIEW_JEWELRY_BUTTONS) do
            local ok, def = pcall(UIWidgets.create_default_button,
                anchor, btn_size, nil, nil, entry.label, 24,
                nil, "button_detail_02", nil, true)
            if not ok or not def then
                mod:info("[cim] overview jewelry button %s create failed: %s", entry.widget_name, tostring(def))
                mod._cim_overview_btn_created = false
                return nil
            end
            local ok_init, w = pcall(UIWidget.init, def)
            if not ok_init or not w then
                mod:info("[cim] overview jewelry button %s init failed: %s", entry.widget_name, tostring(w))
                mod._cim_overview_btn_created = false
                return nil
            end
            local y_offset = -(i - 2) * spacing  -- 95 / 0 / -95
            w.offset = { 0, y_offset, 100 }
            w.content.visible = false
            w.content._cim_synth_filter = entry.synth_filter
            w.content._cim_friendly     = entry.friendly
            w.content._cim_label        = entry.label
            buttons[i] = w
            draw_widgets[#draw_widgets + 1] = w
            widgets_by_name[entry.widget_name] = w
        end

        overview_win._cim_overview_jewelry_buttons = buttons
        mod._cim_overview_btn_created = #buttons
        mod:info("[cim] athanor overview: created %d jewelry craft buttons (anchor=%s, size=%dx%d)",
            #buttons, anchor, btn_size[1], btn_size[2])
        return buttons
    end

    local function _show_overview_jewelry_buttons(overview_win, show)
        local buttons = overview_win._cim_overview_jewelry_buttons
        if not buttons then return end
        for _, w in ipairs(buttons) do
            if w and w.content then w.content.visible = show and true or false end
        end
    end

    local function _handle_overview_jewelry_button_clicks(overview_win)
        local buttons = overview_win._cim_overview_jewelry_buttons
        if not buttons then return end
        for _, w in ipairs(buttons) do
            local hs = w and w.content and w.content.button_hotspot
            if hs and hs.on_release then
                hs.on_release = false  -- consume to prevent re-fire next frame
                local filter   = w.content._cim_synth_filter
                local friendly = w.content._cim_friendly
                if filter and mod._cim_craft_via_synth then
                    pcall(mod._cim_craft_via_synth, filter, friendly or "accessory")
                    if overview_win._play_sound then
                        pcall(overview_win._play_sound, overview_win, "play_gui_craft_forge_button_completed")
                    end
                else
                    mod:warning("[cim] overview jewelry craft helper not wired (mod._cim_craft_via_synth nil)")
                end
            end
        end
    end

    -- v0.7.58-dev: per-frame driver moved into _forge_apply_ui_polish (below).
    -- Earlier v0.7.57-dev hook on HeroWindowWeaveForgeOverview.update fired before
    -- the overview's _widgets / _widgets_by_name were populated by vanilla, so
    -- _ensure_overview_jewelry_buttons would skip every frame ("overview has no
    -- _widgets ... yet" — 13 hits in 2026-05-28 22:09 log). The existing
    -- `_forge_apply_ui_polish` is invoked from HeroViewStateWeaveForge.update,
    -- which only fires AFTER all child windows have completed their on_enter
    -- and have populated widgets — that's why _forge_hide_widget(overview, ...)
    -- succeeds at hiding the original upgrade_button. Piggy-back on the same
    -- entry point.

    -- The Athanor's hover preview now uses VT2's standard `item_tooltip` pass —
    -- the same box that pops up on hover in the regular inventory and crafting
    -- menus. The widget is created lazily inside `_forge_apply_ui_polish` and
    -- stored on `overview._cim_tooltip_widget`.
    local function _forge_populate_item_panels(overview, item)
        local tt = overview._cim_tooltip_widget
        if not tt then return end
        tt.content.item = item or nil
    end

    local function _forge_hide_item_panels(overview)
        local tt = overview._cim_tooltip_widget
        if not tt then return end
        tt.content.item = nil
    end

    local function _forge_apply_ui_polish(forge_state)
        local Managers = state.get_managers()
        local SPProfiles = state.get_profiles()
        local windows = forge_state._active_windows
        if not windows then return end

        local overview = nil
        local panel = nil
        local background = nil
        for _, win in pairs(windows) do
            local name = win.NAME
            if name == "HeroWindowWeaveForgeOverview" then overview = win
            elseif name == "HeroWindowWeaveForgePanel" then panel = win
            elseif name == "HeroWindowWeaveForgeBackground" then background = win
            end
        end

        -- === OVERVIEW: hide Athanor level, hide weapon level, fix power ===
        if overview then
            _forge_hide_widget(overview, "forge_level_title")
            _forge_hide_widget(overview, "forge_level_text")
            _forge_hide_widget(overview, "upgrade_button")
            _forge_hide_widget(overview, "upgrade_text")
            _forge_hide_widget(overview, "upgrade_bg")
            _forge_hide_widget(overview, "top_hdr_background_write_mask")

            -- v0.7.58-dev: drive the 3 jewelry-craft buttons from here. By the
            -- time _forge_apply_ui_polish runs, overview._widgets / _widgets_by_name
            -- are guaranteed populated (proof: _forge_hide_widget above works).
            -- Lazy-create on first call, then show + probe clicks every frame.
            if _OVERVIEW_BTNS_ENABLED then
                _ensure_overview_jewelry_buttons(overview)
                _show_overview_jewelry_buttons(overview, true)
                _handle_overview_jewelry_button_clicks(overview)
            end

            for i = 1, 3 do
                _forge_hide_widget(overview, "viewport_level_title_" .. i)
                _forge_hide_widget(overview, "viewport_level_value_" .. i)
                _forge_hide_widget(overview, "viewport_panel_divider_" .. i)

                local highlight = _forge_get_widget(overview, "viewport_button_text_highlight_" .. i)
                if highlight and highlight.style then
                    if highlight.style.background_top then
                        highlight.style.background_top.color = {255, 123, 123, 123}
                    end
                    if highlight.style.background_bottom then
                        highlight.style.background_bottom.color = {255, 123, 123, 123}
                    end
                    if highlight.style.background_top_light then
                        highlight.style.background_top_light.color = {200, 123, 123, 123}
                    end
                    if highlight.style.background_bottom_light then
                        highlight.style.background_bottom_light.color = {200, 123, 123, 123}
                    end
                end

                local btn_highlight = _forge_get_widget(overview, "viewport_button_highlight_" .. i)
                if btn_highlight and btn_highlight.style then
                    for sk, sv in pairs(btn_highlight.style) do
                        if type(sv) == "table" and sv.color then
                            sv.color = {sv.color[1], 123, 123, 123}
                        end
                    end
                end
            end

            local items_backend = Managers.backend and Managers.backend:get_interface("items")
            if items_backend then
                local player = Managers.player and Managers.player:local_player()
                if player then
                    local profile_index = player:profile_index()
                    local profile = SPProfiles[profile_index]
                    local career_index = player:career_index()
                    local career = profile.careers[career_index]
                    local career_name = career.name
                    local slot_map = {[1] = "slot_melee", [3] = "slot_ranged"}
                    for vp_idx, slot_name in pairs(slot_map) do
                        local bid = items_backend:get_loadout_item_id(career_name, slot_name)
                        if bid then
                            local item = items_backend:get_item_from_id(bid)
                            if item then
                                _forge_set_text(overview, "viewport_power_value_" .. vp_idx, tostring(item.power_level or 300))
                            end
                        end
                    end
                    -- Viewport 2 = the central amulet (accessory crafting). It
                    -- doesn't track a single equipped item — it represents three
                    -- accessory slots. The user wants the power readout here to
                    -- always reflect the configured `base_power_level` setting
                    -- (default 300), matching what a newly-crafted accessory
                    -- would actually receive. User report 2026-05-25.
                    local base_power = (mod._cim_base_power and mod._cim_base_power())
                                       or mod:get("base_power_level") or 300
                    _forge_set_text(overview, "viewport_power_value_2", tostring(base_power))
                end
            end
        end

        -- === VIEWPORT 2 (amulet): repurposed as the modded accessories + talents
        -- editor entry point. We keep it visible (vanilla draws it via
        -- `_initialize_viewports` when `amulet_introduced = true`, see hook below)
        -- and let it route to the weave properties window on click. Phase B will
        -- swap the routing to a custom 3-subsection editor.
        if overview then
            -- Re-label the amulet viewport so it's clear it's the unified accessories
            -- editor (vanilla title is "Weave Amulet"). The click flows through to
            -- HeroWindowWeaveProperties which auto-uses amulet_slot_layout when
            -- selected_item is nil — that's the 3-section UI the user wants.
            -- v0.7.50-dev: "JEWELLERY" -> "ACCESSORIES" (issue #38). I (Claude)
            -- hardcoded "JEWELLERY" here when first repurposing the viewport;
            -- the prior fix attempts (Localize override + HeroWindowLoadoutInventory
            -- category mutation) patched OTHER surfaces but missed this hardcoded
            -- literal — which is the title the user actually sees on the main
            -- forge page. User-named the source of confusion 2026-05-27 EOD.
            _forge_set_text(overview, "viewport_title_2", "ACCESSORIES")
            _forge_set_text(overview, "viewport_sub_title_2", "Necklace + Charm + Trinket")

            if not overview._wt_panels_init then
                overview._wt_panels_init = true
                local UIWidgets = rawget(_G, "UIWidgets")
                local UIWidget = rawget(_G, "UIWidget")
                if UIWidgets and UIWidget and UIWidgets.create_simple_item_tooltip then
                    -- Standard set of tooltip passes used elsewhere in VT2 (deus
                    -- run stats, etc). Renders the same boxed item card the regular
                    -- inventory / crafting menus show on hover.
                    local tooltip_passes = {
                        "item_titles",
                        "skin_applied",
                        "ammunition",
                        "fatigue",
                        "item_power_level",
                        "properties",
                        "traits",
                        "weapon_skin_title",
                        "keywords",
                        "light_attack_stats",
                        "heavy_attack_stats",
                        "detailed_stats_light",
                        "detailed_stats_heavy",
                        "detailed_stats_push",
                        "detailed_stats_ranged_light",
                        "detailed_stats_ranged_heavy",
                    }
                    local ok_def, tt_def = pcall(UIWidgets.create_simple_item_tooltip, "viewport_panel_2", tooltip_passes)
                    if ok_def and tt_def then
                        local ok, tt = pcall(UIWidget.init, tt_def)
                        if ok and tt then
                            -- Anchor near the bottom-left of viewport_panel_2 so
                            -- the tooltip box reads naturally when the mouse is
                            -- on the melee or ranged weapon viewport.
                            tt.offset = { 10, 200, 30 }
                            tt.content.item = nil
                            -- (#521) Exactly ONE popup: the hovered slot's. The vanilla
                            -- item_tooltip pass AUTO-appends "currently equipped"
                            -- comparison boxes next to the hovered item's box whenever
                            -- content.no_equipped_item is unset: it walks the career
                            -- loadout and draws every same-slot_type item with a
                            -- different backend_id as an extra popup
                            -- (ui_passes.lua:3599-3645, append at :3638-3641). With
                            -- cim/wt cross-slot loadouts both weapon slots can share a
                            -- slot_type, so hovering EITHER weapon popped BOTH weapons'
                            -- boxes (issue 521). The deus run-stats screen this widget's
                            -- pass list was copied from suppresses the compare box with
                            -- this exact flag (deus_run_stats_ui_definitions.lua:955/961)
                            -- - cim missed it when the widget was added in 0.3.12-dev.
                            tt.content.no_equipped_item = true
                            -- rt-check anchor (issue 521): the regression check reads
                            -- this content table because the widget itself only exists
                            -- while a forge overview instance is alive.
                            mod._cim_tooltip_content = tt.content
                            overview._cim_tooltip_widget = tt
                            if overview._top_widgets then
                                overview._top_widgets[#overview._top_widgets + 1] = tt
                            end
                            mod:info("Forge tooltip: ready")
                        else
                            mod:echo("Forge tooltip init err: " .. tostring(tt))
                        end
                    else
                        mod:echo("Forge tooltip create err: " .. tostring(tt_def))
                    end
                else
                    mod:echo("Forge tooltip: create_simple_item_tooltip not available")
                end
            end

            local hovered_vp = nil
            local vp1_btn = _forge_get_widget(overview, "viewport_button_1")
            local vp3_btn = _forge_get_widget(overview, "viewport_button_3")
            if _forge_is_hovered(vp1_btn) then
                hovered_vp = 1
            elseif _forge_is_hovered(vp3_btn) then
                hovered_vp = 3
            end

            if hovered_vp then
                -- #521 follow-up: the tooltip is parented to the center panel, while
                -- the weapon viewports are authored at -545 / +545 from center.
                -- Move the one shared tooltip with the hovered viewport so the
                -- ranged card cannot appear over the melee panel (or vice versa).
                local tooltip = overview._cim_tooltip_widget
                if tooltip and tooltip.offset then
                    tooltip.offset[1] = ((hovered_vp - 2) * 545) + 10
                    mod._cim_tooltip_anchor_x = tooltip.offset[1]
                end
                local slot_name = (hovered_vp == 1) and "slot_melee" or "slot_ranged"
                local items_backend = Managers.backend and Managers.backend:get_interface("items")
                local player = Managers.player and Managers.player:local_player()
                if player and items_backend then
                    local profile_index = player:profile_index()
                    local profile = SPProfiles[profile_index]
                    local career_index = player:career_index()
                    local career = profile.careers[career_index]
                    local career_name = career.name
                    local bid = items_backend:get_loadout_item_id(career_name, slot_name)
                    local item = bid and items_backend:get_item_from_id(bid)
                    if item then
                        _forge_populate_item_panels(overview, item)
                    else
                        _forge_hide_item_panels(overview)
                    end
                else
                    _forge_hide_item_panels(overview)
                end
            else
                _forge_hide_item_panels(overview)
            end
        end

        -- === PANEL: hide essence, wheel rings, rebrand header ===
        if panel then
            _forge_hide_widget(panel, "essence_icon")
            _forge_hide_widget(panel, "essence_text")
            _forge_hide_widget(panel, "essence_panel")
            _forge_hide_widget(panel, "essence_tooltip")
            _forge_hide_widget(panel, "loadout_power_title")
            _forge_hide_widget(panel, "loadout_power_tooltip")

            local power_w = _forge_get_widget(panel, "loadout_power_text")
            if power_w and power_w.content then
                power_w.content.text = "MOD WEAPON CRAFTING"
                power_w.content.visible = true
                if power_w.style and power_w.style.text then
                    power_w.style.text.font_size = 28
                    power_w.style.text.text_color = {255, 255, 255, 255}
                end
                if power_w.style and power_w.style.text_shadow then
                    power_w.style.text_shadow.font_size = 28
                end
            end

            _forge_hide_widget(panel, "background_wheel_1")
            _forge_hide_widget(panel, "hdr_background_wheel_1")
            for i = 1, 3 do
                _forge_hide_widget(panel, "wheel_ring_1_" .. i)
                _forge_hide_widget(panel, "wheel_ring_2_" .. i)
                _forge_hide_widget(panel, "hdr_wheel_ring_1_" .. i)
                _forge_hide_widget(panel, "hdr_wheel_ring_2_" .. i)
            end

            _forge_set_style_color(panel, "top_glow_smoke_1", "texture_id", {200, 180, 20, 10})
        end

        -- === BACKGROUND: change smoke colors to deep red ===
        if background and not state.get_bg_colored() then
            _forge_set_style_color(background, "bottom_glow_smoke_1", "texture_id", {200, 180, 20, 10})
            _forge_set_style_color(background, "bottom_glow_smoke_2", "texture_id", {255, 200, 30, 10})
            _forge_set_style_color(background, "bottom_glow_smoke_3", "texture_id", {200, 180, 25, 15})
            _forge_set_style_color(background, "bottom_glow_embers_1", "texture_id", {130, 255, 60, 20})
            _forge_set_style_color(background, "bottom_glow_embers_3", "texture_id", {130, 255, 60, 20})
            state.set_bg_colored(true)
        end

        -- === PROPERTIES sub-menu: hide level/mastery, fix power ===
        local properties_win = nil
        for _, win in pairs(windows) do
            if win.NAME == "HeroWindowWeaveProperties" then properties_win = win end
        end
        if properties_win then
            _forge_hide_widget(properties_win, "viewport_level_title")
            _forge_hide_widget(properties_win, "viewport_level_value")
            _forge_hide_widget(properties_win, "viewport_panel_divider")
            _forge_hide_widget(properties_win, "mastery_text")
            _forge_hide_widget(properties_win, "mastery_title_text")
            _forge_hide_widget(properties_win, "mastery_icon")
            _forge_hide_widget(properties_win, "mastery_tooltip")

            local params = properties_win._params
            local sel_item = params and params.selected_item
            local in_amulet_mode = not (sel_item and sel_item.backend_id)

            if in_amulet_mode then
                if _AMULET_BTNS_ENABLED then
                    -- Amulet mode (v0.7.32+): 3 stacked craft buttons replace the
                    -- single "CRAFT NEW" upgrade_button. The 3D Amulet of Ashur model
                    -- and its title label are hidden — buttons render in the freed
                    -- center space.
                    _forge_hide_widget(properties_win, "upgrade_button")
                    _forge_hide_widget(properties_win, "upgrade_text")
                    _forge_hide_widget(properties_win, "upgrade_essence_warning")

                    _ensure_amulet_buttons(properties_win)
                    _show_amulet_buttons(properties_win, true)
                    _handle_amulet_button_clicks(properties_win)

                    -- Hide the 3D model. The unit_previewer renders the rotating
                    -- amulet inside viewport_widget; setting `_skip_previewer_update`
                    -- makes the update-hook below short-circuit before draw_widget.
                    properties_win._cim_skip_previewer = true
                else
                    -- v0.7.64-dev: buttons disabled — restore the vanilla "Craft All"
                    -- upgrade_button as the accessory craft control so the view is
                    -- fully usable (no black box, grid visible). It routes through the
                    -- existing `_upgrade_magic_level` hook which crafts the edited
                    -- accessory slots.
                    _show_amulet_buttons(properties_win, false)
                    properties_win._cim_skip_previewer = nil
                    _forge_set_text(properties_win, "upgrade_text", "CRAFT ACCESSORIES")
                end

                -- Rename viewport_title from "Amulet of Ashur" → "Accessory Crafting".
                -- vanilla `_set_title_text` writes Localize("weave_amulet_name") into
                -- this widget every frame in some code paths; the per-frame polish
                -- pass here re-overrides it after each vanilla write.
                _forge_set_text(properties_win, "viewport_title", "ACCESSORY CRAFTING")
                -- viewport_sub_title is the career name — leave it alone (still useful).
            else
                _show_amulet_buttons(properties_win, false)
                properties_win._cim_skip_previewer = nil

                -- Weapon mode: keep the vanilla upgrade_button visible + per-slot
                -- relabel. upgrade_button is repurposed as our "Craft New" button
                -- (see hook on `_upgrade_magic_level` below).
                local craft_label = "CRAFT NEW WEAPON"
                local sn = params and params.selected_slot_name
                if sn == "slot_necklace" then craft_label = "CRAFT NEW NECKLACE"
                elseif sn == "slot_charm" then craft_label = "CRAFT NEW CHARM"
                elseif sn == "slot_trinket" then craft_label = "CRAFT NEW TRINKET"
                end
                _forge_set_text(properties_win, "upgrade_text", craft_label)
            end
            _forge_hide_widget(properties_win, "background_wheel")
            _forge_hide_widget(properties_win, "hdr_background_wheel")
            for i = 1, 3 do
                _forge_hide_widget(properties_win, "wheel_ring_" .. i)
                _forge_hide_widget(properties_win, "hdr_wheel_ring_" .. i)
            end

            _forge_set_style_color(properties_win, "cluster_background_effect_1", "texture_id", {200, 180, 20, 10})

            if sel_item and sel_item.backend_id then
                local items_backend = Managers.backend and Managers.backend:get_interface("items")
                if items_backend then
                    local item = items_backend:get_item_from_id(sel_item.backend_id)
                    if item then
                        _forge_set_text(properties_win, "viewport_power_value", tostring(item.power_level or 300))
                    end
                end
            end
        end
    end

    -- Full-form hook: while the community-build modal is open, vanilla child
    -- windows receive FAKE_INPUT_SERVICE for this frame, while the modal draws
    -- afterward with the real parent service. This prevents click-through into
    -- weapon viewports without registering a second hook on the same method.
    mod:hook("HeroViewStateWeaveForge", "update", function(func, self, dt, t)
        local browser = state.ranalds_browser
        local browser_open = browser and browser.is_open and browser.is_open()
        local input_was_blocked = self._input_blocked
        if browser_open then self._input_blocked = true end
        local ok, result = pcall(func, self, dt, t)
        self._input_blocked = input_was_blocked
        if not ok then error(result, 0) end
        if state.is_active() then
            _forge_apply_ui_polish(self)
            if browser and browser.draw then
                local overview
                for _, window in pairs(self._active_windows or {}) do
                    if window.NAME == "HeroWindowWeaveForgeOverview" then
                        overview = window
                        break
                    end
                end
                local renderer = self.get_ui_top_renderer
                    and self:get_ui_top_renderer() or self.ui_top_renderer
                local input_service = self.input_service and self:input_service()
                local draw_ok, draw_err = pcall(browser.draw, self, overview,
                    renderer, input_service, dt)
                if not draw_ok then
                    pcall(state.print_line,
                        "[cim:1360] community browser failed safely: %s",
                        tostring(draw_err))
                    if browser.close then pcall(browser.close) end
                end
            end
        end
        return result
    end)

    state.exports.apply_ui_polish = _forge_apply_ui_polish
    state.exports.get_widget = _forge_get_widget
    state.exports.install_count = 1
    mod._cim_forge_ui_owner_installed = true
    return state.exports, true
end
