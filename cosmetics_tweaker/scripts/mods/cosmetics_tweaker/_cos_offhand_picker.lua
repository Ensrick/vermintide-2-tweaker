-- _cos_offhand_picker.lua — weapon-customization offhand picker owner.
--
-- Owns the existing magic-family illusion filter, offhand row construction,
-- hover/input/draw handling, exact selected-primary resolver, and offhand cell
-- press method. It deliberately does not own screen-exit commit/revert,
-- persistence, package catalogs, render hooks, RPCs, lifecycle/update callbacks,
-- or the LA pool merge.
--
-- Owned by: cosmetics_tweaker.lua entry point. Installed once at the historical
-- post-offhand-catalog/merge, pre-BackendUtils boundary.

local Picker = {}

function Picker.install(mod, deps)
    if mod._cos_offhand_picker_owner then
        return mod._cos_offhand_picker_owner
    end

    deps = deps or {}
    local MAGIC_SKIN_GATEWAY = assert(deps.magic_skin_gateway, "magic_skin_gateway is required")
    local _create_glow_editor_button = assert(deps.create_glow_editor_button, "create_glow_editor_button is required")
    local _refresh_glow_editor_button = assert(deps.refresh_glow_editor_button, "refresh_glow_editor_button is required")
    local _refresh_illusion_glow_badges = assert(deps.refresh_illusion_glow_badges, "refresh_illusion_glow_badges is required")
    local set_active_customization_backend_id = assert(deps.set_active_customization_backend_id, "set_active_customization_backend_id is required")
    local _get_offhand_options = assert(deps.get_offhand_options, "get_offhand_options is required")
    local _MULTI_MOUNT_ITEM_TYPES = assert(deps.multi_mount_item_types, "multi_mount_item_types is required")
    local _offhand_session_state = assert(deps.offhand_session_state, "offhand_session_state is required")
    local _offhand_selection = assert(deps.offhand_selection, "offhand_selection is required")
    local _preload_offhand_for_option = assert(deps.preload_offhand_for_option, "preload_offhand_for_option is required")
    local _source_illusion_name = assert(deps.source_illusion_name, "source_illusion_name is required")
    local OFFHAND_NAMES = assert(deps.offhand_names, "offhand_names is required")
    local GlowPicker = assert(deps.glow_picker, "glow_picker is required")
    local LA_BRIDGE = assert(deps.la_bridge, "la_bridge is required")
    local _local_player_safe = assert(deps.local_player_safe, "local_player_safe is required")
    local _SHIELD_ICON_OWNER_ITEM_TYPES = assert(deps.shield_icon_owner_item_types, "shield_icon_owner_item_types is required")
    local _inventory_icon_for_offhand_unit = assert(deps.inventory_icon_for_offhand_unit, "inventory_icon_for_offhand_unit is required")
    local _dbg = assert(deps.dbg, "dbg is required")
    local _trace = assert(deps.trace, "trace is required")
    local get_managers = assert(deps.get_managers, "get_managers is required")
    local get_weapon_skins = assert(deps.get_weapon_skins, "get_weapon_skins is required")
    local get_item_master_list = assert(deps.get_item_master_list, "get_item_master_list is required")
    local get_ui_widget = assert(deps.get_ui_widget, "get_ui_widget is required")
    local get_ui_renderer = assert(deps.get_ui_renderer, "get_ui_renderer is required")
    local get_local_require = assert(deps.get_local_require, "get_local_require is required")
    local HeroWindowItemCustomization = assert(
        deps.hero_window_item_customization, "hero_window_item_customization is required")
    mod._la_option_icon_policy = assert(
        deps.la_option_icon_policy, "la_option_icon_policy is required")

    local function _has_offhand(item_data)
        return item_data and item_data.left_hand_unit ~= nil
    end

    local function _get_weapon_key_from_item(item)
        local ItemMasterList = get_item_master_list()
        if not item then return nil end
        -- rawget: item.key may be an LA-bridge backend_id or CWV variant key
        -- that doesn't exist in IML; ItemMasterList.__index crashifies on
        -- unknown keys.
        local data = item.data or (item.key and ItemMasterList and rawget(ItemMasterList, item.key))
        if data and data.item_type == "weapon_skin" and data.matching_item_key
                and ItemMasterList then
            local base = rawget(ItemMasterList, data.matching_item_key)
            if base and base.item_type then return base.item_type end
        end
        if data and data.item_type then return data.item_type end
        return item.key
    end

    -- v0.9.29-dev (issue #48): filter weavebound / shyish glow families from
    -- the illusion grid by default. Data evidence: 2026-05-27 ui-dump on
    -- es_2h_sword (Kruber Greatsword) showed 13 skins with mat= field on each
    -- (`mat=weaves` for Weavebound, `mat=shyish` for Shyish-Infused). These are
    -- visually jarring on most weapons (the Bret Longsword "Evengleam"
    -- weavebound/shyish pair is the canonical complaint).
    -- v0.9.176-dev: the hidden families need a real selection gateway. The
    -- default-off `show_magic_family_skins` option reveals them long enough for
    -- selection; the contextual Edit Glow button then owns customization.

    local function _skin_mat_family(skin_key)
        local WeaponSkins = get_weapon_skins()
        if not skin_key or not WeaponSkins or not WeaponSkins.skins then return nil end
        local entry = rawget(WeaponSkins.skins, skin_key)
        if type(entry) ~= "table" then return nil end
        local mat = entry.material_settings_name
        return (type(mat) == "string") and mat or nil
    end

    -- Pure helper so the regression test can drive it with synthetic widget
    -- arrays. `current_skin_key` is the always-keep guard (vanilla selection
    -- state would dangle otherwise).
    mod._filter_illusion_widgets = function(widgets, current_skin_key, get_setting)
        local show_magic
        if type(get_setting) == "function" then
            show_magic = get_setting("show_magic_family_skins") == true
        else
            show_magic = mod:get("show_magic_family_skins") == true
        end
        return MAGIC_SKIN_GATEWAY.filter(
            widgets, current_skin_key, _skin_mat_family, show_magic)
    end

    mod:hook("HeroWindowItemCustomization", "_setup_illusions", function(func, self, item)
        local Managers = get_managers()
        local WeaponSkins = get_weapon_skins()
        local ItemMasterList = get_item_master_list()
        local UIWidget = get_ui_widget()
        local local_require = get_local_require()
        func(self, item)

        -- v0.9.29-dev: drop hidden glow-family skins from the grid. Done
        -- AFTER vanilla setup (and AFTER vanilla's `_select_illusion_by_key`
        -- runs inside the original function) so a currently-equipped weaves
        -- or shyish skin survives — only unselected hidden-family widgets
        -- get pruned.
        if self._illusion_widgets and #self._illusion_widgets > 0 then
            local current_skin = item and (item.skin or (item.data and item.data.default_skin))
            local kept, removed = mod._filter_illusion_widgets(self._illusion_widgets, current_skin)
            if removed > 0 then
                self._illusion_widgets = kept
                _dbg("[illusion-filter] dropped %d hidden-family skin(s); %d remain",
                    removed, #kept)
            end
        end

        -- v0.9.18-dev DATA PROBE — dump every illusion built into the picker for
        -- this item along with the skin's material_settings_name + rarity. Runs
        -- once per picker open (~1 line per illusion). Gated on debug_dumps so
        -- it's silent in normal play. Goal: when the user opens the picker on
        -- the Evengleam-bearing weapon, we get a complete inventory of the
        -- magic-family skins it carries — enough data to scope the Evengleam
        -- glow popup feature precisely.
        if item then
            local weapon_key = _get_weapon_key_from_item(item)
            _dbg("[illusion-picker-setup] item.key=%s weapon_key=%s backend_id=%s current.skin=%s",
                tostring(item.key), tostring(weapon_key),
                tostring(item.backend_id), tostring(item.skin))
            local widgets = self._illusion_widgets
            if widgets then
                for i, widget in ipairs(widgets) do
                    local skin_key = widget.content and widget.content.skin_key
                    local entry = skin_key and WeaponSkins and WeaponSkins.skins
                        and WeaponSkins.skins[skin_key]
                    if entry then
                        _dbg("[illusion-picker-setup]   [%d] %s -> matching=%s material_settings=%s rarity=%s",
                            i, tostring(skin_key), tostring(entry.matching_item_key),
                            tostring(entry.material_settings_name), tostring(entry.rarity))
                    end
                end
            end
        end

        self._ct_offhand_widgets = nil
        self._ct_offhand_title_widget = nil
        self._ct_offhand_name_widget = nil
        self._ct_offhand_divider_widget = nil
        self._ct_selected_offhand_index = nil

        -- #377: one persistent, in-view square toggle. Recreate it with the
        -- customization screen's widgets so no stale hotspot survives a rebuild.
        self._ct_glow_editor_widget = _create_glow_editor_button()

        local initial_skin = item and item.skin
        if (not initial_skin or initial_skin == "") and item and item.backend_id
                and Managers and Managers.backend then
            local items_iface = Managers.backend:get_interface("items")
            if items_iface and items_iface.get_skin then
                initial_skin = items_iface:get_skin(item.backend_id)
            end
        end
        if not initial_skin and item and item.key and WeaponSkins and WeaponSkins.default_skins then
            initial_skin = WeaponSkins.default_skins[item.key]
        end
        _refresh_glow_editor_button(self, initial_skin)
        self._ct_primary_skin = initial_skin
        _refresh_illusion_glow_badges(self)

        _dbg("[offhand] _setup_illusions called, item=%s", tostring(item and item.key))

        -- Stash the exact item identity for pending-skin preview reconstruction.
        local active_customization_backend_id = item and item.backend_id or nil
        set_active_customization_backend_id(active_customization_backend_id)
        mod._active_customization_item_type = _get_weapon_key_from_item(item)
        _trace("SCREEN setup_illusions item=%s set active_customization_bid=%s item_type=%s",
            tostring(item and item.key), tostring(active_customization_backend_id),
            tostring(mod._active_customization_item_type))

        if not item then _dbg("[offhand] no item, bailing"); return end
        local item_data = item.data or (item.key and ItemMasterList and rawget(ItemMasterList, item.key))
        _dbg("[offhand] item_data=%s, left_hand_unit=%s", tostring(item_data ~= nil), tostring(item_data and item_data.left_hand_unit))
        if not _has_offhand(item_data) then _dbg("[offhand] no offhand, bailing"); return end

        local weapon_key = _get_weapon_key_from_item(item)
        _dbg("[offhand] weapon_key=%s", tostring(weapon_key))
        local hand_pools = _get_offhand_options(weapon_key)
        if type(hand_pools) ~= "table" then
            _dbg("[offhand] no options for key=%s, bailing", tostring(weapon_key)); return
        end

        if type(mod._cos.capture_issue704_setup) == "function" then
            pcall(mod._cos.capture_issue704_setup, weapon_key, item, initial_skin,
                self._illusion_widgets, hand_pools)
        end

        -- #583: dual weapons use vanilla row 1 as the main/right-hand owner and
        -- add exactly one left/offhand row. Legacy non-dual multi-mount surfaces
        -- retain their previous right+left custom rows.
        local is_multi_mount = _MULTI_MOUNT_ITEM_TYPES[weapon_key] == true
        local is_independent_dual = mod._independent_dual_item_types
            and mod._independent_dual_item_types[weapon_key] == true
        local hand_rows = {}
        -- Order: right first (top row), left second (bottom row). For single-
        -- mount weapons only left exists; matches legacy single-row layout.
        if is_multi_mount and not is_independent_dual
                and type(hand_pools.right_hand_unit) == "table"
                and #hand_pools.right_hand_unit > 0 then
            hand_rows[#hand_rows + 1] = { hand = "right_hand_unit", pool = hand_pools.right_hand_unit }
        end
        if type(hand_pools.left_hand_unit) == "table" and #hand_pools.left_hand_unit > 0 then
            hand_rows[#hand_rows + 1] = { hand = "left_hand_unit", pool = hand_pools.left_hand_unit }
        end
        if #hand_rows == 0 then
            _dbg("[offhand] no hand pools for key=%s, bailing", tostring(weapon_key)); return
        end

        local definitions = local_require("scripts/ui/views/hero_view/windows/definitions/hero_window_item_customization_definitions")
        local create_btn = definitions.create_illusion_button

        local width = 51
        local spacing = -5
        local row_height = 55
        -- Bottom row stays at legacy y=95. Higher rows stack above.
        local base_y = 95

        -- Migrate any pre-v0.9.9.4 in-memory selection shape on this backend_id.
        if item.backend_id then _offhand_session_state.migrate_legacy(item.backend_id) end

        local widgets = {}  -- flat list of every widget (multiple rows interleaved)
        local widgets_by_hand = {}  -- hand_field -> array of widgets (parallel to pool)
        local selected_by_hand = {}  -- hand_field -> selected index (or nil)

        for row_idx, row in ipairs(hand_rows) do
            local pool = row.pool
            local hand_field = row.hand
            local hand_widgets = {}
            local total_width = -spacing
            local row_y = base_y + (#hand_rows - row_idx) * row_height
            for i, opt in ipairs(pool) do
                local widget_def = create_btn()
                local widget = UIWidget.init(widget_def)
                local rarity = opt.rarity or "exotic"
                local icon_texture = "button_illusion_" .. rarity
                if UIAtlasHelper and UIAtlasHelper.has_texture_by_name and not UIAtlasHelper.has_texture_by_name(icon_texture) then
                    icon_texture = "button_illusion_default"
                end
                -- v0.9.9.1 REVERT: dropped opt.icon prefer; use rarity badge only.
                -- v0.9.9.4: skin_key now encodes hand + index so dispatcher can
                -- demux. `r`/`l` short forms match legacy `__offhand_<i>` length
                -- budget closely.
                local short_hand = (hand_field == "right_hand_unit") and "r" or "l"
                widget.content.skin_key = "__offhand_" .. short_hand .. "_" .. i
                widget.content.icon_texture = icon_texture
                widget.content.offhand_index = i
                widget.content.offhand_hand = hand_field
                widget.content.offhand_unit = opt.unit
                widget.content.offhand_name = opt.name
                widget.content.offhand_component_kind = opt.component_kind
                widget.content.offhand_component_identity = opt.component_identity
                widget.content.locked = false
                widget.content.rarity = rarity
                hand_widgets[#hand_widgets + 1] = widget
                widgets[#widgets + 1] = widget
                total_width = total_width + spacing + width
            end
            local x_offset = width / 2
            for _, widget in ipairs(hand_widgets) do
                widget.offset = widget.offset or { 0, 0, 0 }
                widget.offset[1] = -total_width / 2 + x_offset
                widget.offset[2] = row_y
                x_offset = x_offset + width + spacing
            end
            widgets_by_hand[hand_field] = hand_widgets
        end

        -- Determine the unit currently rendered for EACH hand we built a row for.
        -- Priority per hand:
        --   1. backend's stored skin -> WeaponSkins.skins[skin][hand_field]
        --   2. ItemMasterList's get_skin lookup by backend_id
        --   3. item_data[hand_field] (template default)
        local skin_resolved = item.skin
        if not skin_resolved and item.backend_id and Managers and Managers.backend then
            local items_iface = Managers.backend:get_interface("items")
            if items_iface and items_iface.get_skin then
                skin_resolved = items_iface:get_skin(item.backend_id)
            end
        end
        local current_units_by_hand = {}
        for _, row in ipairs(hand_rows) do
            local hand_field = row.hand
            local cur
            if skin_resolved and WeaponSkins and WeaponSkins.skins
                    and WeaponSkins.skins[skin_resolved] then
                cur = WeaponSkins.skins[skin_resolved][hand_field]
            end
            if not cur then cur = item_data[hand_field] end
            current_units_by_hand[hand_field] = cur
        end

        local current_backend_id = item.backend_id
        if current_backend_id then _offhand_session_state.migrate_legacy(current_backend_id) end
        local per_hand_sel = current_backend_id and _offhand_selection[current_backend_id] or nil

        for _, row in ipairs(hand_rows) do
            local hand_field = row.hand
            local pool = row.pool
            local current_sel = per_hand_sel and per_hand_sel[hand_field]
            local current_unit = current_units_by_hand[hand_field]

            -- No explicit offhand choice means the offhand follows whatever row 1
            -- currently previews/applies. Do not auto-convert the current paired
            -- mesh into an override merely because it is present in the pool.
            if is_independent_dual and not current_sel
                    and pool[1] and pool[1].follow_main then
                if current_backend_id then
                    _offhand_selection[current_backend_id] = _offhand_selection[current_backend_id] or {}
                    _offhand_selection[current_backend_id][hand_field] = pool[1]
                end
                current_sel = pool[1]
            end

            if not current_sel and current_unit then
                for _, opt in ipairs(pool) do
                    local opt_mesh = opt.unit or opt.intended_unit
                    if opt_mesh == current_unit then
                        if current_backend_id then
                            _offhand_selection[current_backend_id] = _offhand_selection[current_backend_id] or {}
                            _offhand_selection[current_backend_id][hand_field] = opt
                        end
                        current_sel = opt
                        _dbg("[offhand] auto-selected %s/%s: %s (backend_id=%s)",
                            tostring(weapon_key), hand_field, tostring(opt.name),
                            tostring(current_backend_id))
                        -- v0.9.43-dev WRITE trace: _offhand_selection populated by
                        -- the setup-time auto-select (matched the currently-rendered
                        -- mesh). trigger=setup_auto_select.
                        _trace("WRITE _offhand_selection[%s][%s] = opt(name=%s kind=%s armoury=%s unit=%s) trigger=setup_auto_select",
                            tostring(current_backend_id), tostring(hand_field), tostring(opt.name),
                            tostring(opt.la_armoury_key and "LA" or "vanilla"),
                            tostring(opt.la_armoury_key), tostring(opt.unit or opt.intended_unit))
                        break
                    end
                end
                if not current_sel then
                    _dbg("[offhand] no option matched %s/%s current=%s — leaving row unhighlighted",
                        tostring(weapon_key), hand_field, tostring(current_unit))
                end
            end

            if current_sel then _preload_offhand_for_option(current_sel) end

            if current_sel then
                local hw = widgets_by_hand[hand_field]
                for i, widget in ipairs(hw) do
                    if pool[i] == current_sel then
                        widget.content.button_hotspot.is_selected = true
                        widget.content.equipped = true
                        selected_by_hand[hand_field] = i
                    end
                end
            end
        end

        -- v0.9.53-dev (#200): snapshot the offhand baseline for this screen session
        -- (the state equipped when the screen opened, AFTER the auto-select above
        -- matched the currently-rendered shield). Only on a FRESH open — if a
        -- baseline already exists for this bid we're inside the same session
        -- (e.g. a craft-complete re-ran _state_setup_upgrade -> _setup_illusions),
        -- so preserve the original baseline and the committed flag. on_exit reverts
        -- _offhand_selection to this baseline unless a genuine Apply committed.
        if current_backend_id and mod._offhand_baseline[current_backend_id] == nil then
            mod._offhand_baseline[current_backend_id] = _offhand_session_state.snapshot(current_backend_id)
            mod._offhand_committed[current_backend_id] = nil
            _trace("SCREEN setup_illusions offhand baseline snapshotted bid=%s present=%s",
                tostring(current_backend_id),
                tostring(mod._offhand_baseline[current_backend_id] ~= false))
        end

        self._ct_offhand_widgets = widgets
        self._ct_offhand_widgets_by_hand = widgets_by_hand
        self._ct_offhand_hand_rows = hand_rows
        self._ct_offhand_weapon_key = weapon_key
        -- Legacy field — kept for any external reader. Mirrors the left-hand
        -- pool (current default) so callers that read .ct_offhand_options
        -- behave as before for single-mount weapons.
        self._ct_offhand_options = hand_pools.left_hand_unit
        self._ct_offhand_selected_by_hand = selected_by_hand
    end)

    -- v0.9.43-dev INPUT trace: vanilla _handle_input row-1 illusion HOVER. In
    -- vanilla, hovering an illusion widget only updates the name LABEL (no spawn,
    -- no paint) — see hero_window_item_customization.lua:736-749. We log the
    -- hovered skin only when it CHANGES so the trace shows clearly that row-1
    -- hover is benign (label-only) and is NOT the source of the paint flood —
    -- contrasting it with the offhand-row hover/press above. LOGGING ONLY; no new
    -- behavior. (No existing hook on _handle_input — safe to add per the
    -- no-duplicate-hook rule.)
    mod:hook_safe("HeroWindowItemCustomization", "_handle_input", function(self, input_service, dt, t)
        local WeaponSkins = get_weapon_skins()
        local il = self._illusion_widgets
        if not il then return end
        local hover_skin = nil
        for i = 1, #il do
            local w = il[i]
            local hs = w and w.content and w.content.button_hotspot
            if hs and hs.is_hover then hover_skin = w.content.skin_key; break end
        end
        if hover_skin ~= self._ct_il_last_hover then
            self._ct_il_last_hover = hover_skin
            if hover_skin then
                _trace("INPUT HOVER illusion-grid skin=%s bid=%s (vanilla label-only)",
                    tostring(hover_skin), tostring(self._item_backend_id))
            end
        end

        local primary_skin = hover_skin
        if not primary_skin then
            for i = 1, #il do
                local content = il[i] and il[i].content
                local hotspot = content and content.button_hotspot
                if (hotspot and hotspot.is_selected) or (content and content.equipped) then
                    primary_skin = content.skin_key
                    break
                end
            end
        end
        primary_skin = primary_skin or self._ct_primary_skin
        local primary_data = primary_skin and WeaponSkins and WeaponSkins.skins
            and WeaponSkins.skins[primary_skin]
        primary_data = type(primary_data) == "table" and (primary_data.data or primary_data) or nil
        local primary_name = primary_skin and _source_illusion_name(primary_skin, primary_data) or nil

        -- #641 consolidated into the existing _handle_input hook: vanilla writes
        -- the main illusion's name before this post-hook runs. When an independent
        -- component cell is hovered, compose the current primary illusion's
        -- existing name first and the independently resolved offhand/shield name
        -- second. No hover means vanilla remains authoritative.
        for _, widget in ipairs(self._ct_offhand_widgets or {}) do
            local content = widget.content
            local hotspot = content and content.button_hotspot
            if hotspot and hotspot.is_hover and content.offhand_name then
                local base = self._weapon_illusion_base_widgets_by_name
                local name_widget = base and base.illusions_name
                if name_widget and name_widget.content then
                    name_widget.content.text = OFFHAND_NAMES.compose(
                        primary_name, content.offhand_name)
                end
                break
            end
        end
    end)

    mod:hook("HeroWindowItemCustomization", "_state_draw_overview", function(func, self, ui_renderer, dt)
        local UIRenderer = get_ui_renderer()
        GlowPicker.draw_native_information(func, self, ui_renderer, dt,
            self._ct_glow_editor_widget and self._ct_glow_editor_widget.content)

        -- #377: draw and consume the contextual editor toggle before the
        -- offhand-row early return below, so ordinary one-handed weapons get it.
        local glow_widget = self._ct_glow_editor_widget
        local sg = ui_renderer and ui_renderer.ui_scenegraph
        if glow_widget and sg and sg[glow_widget.scenegraph_id]
                and GlowPicker.position_toggle(self, glow_widget, 96, 20) then
            UIRenderer.draw_widget(ui_renderer, glow_widget)
            local family = glow_widget.content and glow_widget.content.glow_family
            -- Consume the release edge even while disabled so it cannot become a
            -- stale click if the user next previews a glow-capable illusion.
            local pressed = self:_is_button_pressed(glow_widget)
            if pressed and family then
                local bid = glow_widget.content.glow_backend_id
                local skin = glow_widget.content.glow_skin
                if GlowPicker.is_open_for(bid, { skin = skin }) then
                    GlowPicker.close()
                else
                    if GlowPicker.is_open() then GlowPicker.close() end
                    GlowPicker.open_for(bid, { skin = skin })
                end
                _refresh_glow_editor_button(self, skin)
                self:_play_sound("play_gui_equipment_inventory_select")
                mod:info("[glow_picker] manual toggle bid=%s skin=%s family=%s open=%s",
                    tostring(bid), tostring(skin), tostring(family),
                    tostring(GlowPicker.is_open_for(bid, { skin = skin })))
            end
        end

        local offhand_widgets = self._ct_offhand_widgets
        if not offhand_widgets or #offhand_widgets == 0 then return end

        if not ui_renderer or not ui_renderer.ui_scenegraph then return end
        local sg = ui_renderer.ui_scenegraph

        -- CLARIFY: scenegraph guard — offhand widget definitions inherit
        -- scenegraph_id from create_illusion_button. If the inherited id isn't
        -- registered in this scene's ui_scenegraph (rare but possible during
        -- transitions), draw_widget would crash. Skipping is the safe default.
        for _, widget in ipairs(offhand_widgets) do
            if sg[widget.scenegraph_id] then
                UIRenderer.draw_widget(ui_renderer, widget)
            end
        end

        -- v0.9.43-dev INPUT trace: offhand-row HOVER scan. This is the CRUX — the
        -- bug report is "hovering applies without clicking". We log the hotspot
        -- state of whichever offhand widget is currently hovered, but only when the
        -- hovered target CHANGES (deduped via self._ct_offhand_last_hover) so it's
        -- one line per hover-enter, not per frame. If a PAINT fires while a widget
        -- is merely hovered (is_hover=true) with no on_release edge, the hover→paint
        -- bug is confirmed here. LOGGING ONLY.
        local hover_key, hover_name, hover_state = nil, nil, nil
        for _, widget in ipairs(offhand_widgets) do
            local hs = widget.content.button_hotspot
            if hs and hs.is_hover then
                hover_key = tostring(widget.content.offhand_hand) .. "#" .. tostring(widget.content.offhand_index)
                hover_name = tostring(widget.content.offhand_name)
                hover_state = string.format("is_hover=%s on_release=%s on_pressed=%s is_held=%s is_selected=%s",
                    tostring(hs.is_hover), tostring(hs.on_release), tostring(hs.on_pressed),
                    tostring(hs.is_held), tostring(hs.is_selected))
                break
            end
        end
        if hover_key ~= self._ct_offhand_last_hover then
            self._ct_offhand_last_hover = hover_key
            if hover_key then
                _trace("INPUT HOVER offhand-row %s opt=%s bid=%s %s",
                    hover_key, hover_name, tostring(self._item_backend_id), tostring(hover_state))
            end
        end

        -- v0.9.52-dev (#150): one-frame is_held memory per offhand cell. The
        -- on_release handler below uses it to tell a GENUINE CLICK (the cell was
        -- actively held — mouse button physically down — on this or the previous
        -- frame, then released over it) apart from a HOVER-fired / sticky on_release
        -- that never had a hold. The 0.9.45 is_hover guard alone was insufficient:
        -- while merely hovering a cell the cursor IS over it (is_hover=true), so a
        -- hover-leaked on_release passed the guard and applied the skin to the live
        -- character — confirmed in the 2026-06-30 trace ([offhand-press] per hover ->
        -- network_husk paint). is_held is only ever true while the button is down on
        -- the cell. Stored into self each frame and read back as held_prev next frame
        -- (2-frame window: covers the release-frame, when is_held has just gone
        -- false), so there is no stale-flag window.
        local held_prev = self._ct_offhand_held_now or {}
        local held_now = {}
        for _, widget in ipairs(offhand_widgets) do
            local hs = widget.content.button_hotspot
            if hs and hs.is_held then
                held_now[tostring(widget.content.offhand_hand) .. "#" .. tostring(widget.content.offhand_index)] = true
            end
        end
        self._ct_offhand_held_now = held_now

        -- v0.9.18-dev FIX #37 — switch from `on_pressed` to `on_release` and
        -- manually clear after consumption. Vanilla's `_is_button_pressed`
        -- (hero_window_item_customization.lua:611-616) uses this exact pattern:
        --   if hotspot.on_release then hotspot.on_release = false; return true end
        -- `on_pressed` is sticky in this engine build — it stays true across
        -- multiple draw frames after a click and even across screen entries in
        -- some cases — which made the prior code re-fire `_ct_on_offhand_pressed`
        -- on the FIRST widget every frame the picker was open, "applying" the
        -- yellow-Reynard01 shield instantly on browse (issue #37). `on_release`
        -- is the single-frame edge-trigger vanilla uses and we now clear it
        -- manually so a sticky engine state can't leak across frames either.
        for _, widget in ipairs(offhand_widgets) do
            local hotspot = widget.content.button_hotspot
            if hotspot and hotspot.on_release then
                hotspot.on_release = false  -- consume edge — mirror vanilla pattern
                -- v0.9.9.4-dev: dispatch on the widget's recorded hand_field +
                -- index, not on a flat list index — multi-mount weapons
                -- interleave widgets across rows in self._ct_offhand_widgets.
                local hand_field = widget.content.offhand_hand or "left_hand_unit"
                local index = widget.content.offhand_index
                -- v0.9.18-dev diagnostic — always-on, low volume (one line per
                -- legitimate click). Captures what the user pressed + which
                -- backend_id the resulting _offhand_selection write will land
                -- under, so any future regression of #37 (or its cousins) is
                -- visible without enabling debug_dumps.
                mod:info("[offhand-press] hand=%s index=%s widget=%s backend_id=%s",
                    tostring(hand_field), tostring(index),
                    tostring(widget.content.name or widget.scenegraph_id),
                    tostring(self._item_backend_id))
                -- v0.9.43-dev INPUT trace: offhand-row PRESS via on_release edge.
                -- Captures the full hotspot state at fire time so we can tell a
                -- genuine click (came from is_held→release) apart from a leaked /
                -- sticky on_release that fires on mere hover (the #37-class bug).
                _trace("INPUT PRESS offhand-row %s#%s opt=%s bid=%s is_hover=%s is_held=%s on_pressed=%s → _ct_on_offhand_pressed",
                    tostring(hand_field), tostring(index), tostring(widget.content.offhand_name),
                    tostring(self._item_backend_id), tostring(hotspot.is_hover),
                    tostring(hotspot.is_held), tostring(hotspot.on_pressed))
                -- v0.9.52-dev (BUG 1 / #150, hover): act ONLY on a genuine click --
                -- the cell was actively HELD (mouse button down) on this or the
                -- previous frame AND the cursor is still over it at release. The
                -- 0.9.45 is_hover-only guard let hover through, because hovering a cell
                -- means the cursor IS over it; additionally requiring a preceding
                -- is_held kills the hover-fired / sticky on_release leak that was
                -- painting the live character. A real click holds then releases over
                -- the cell (was_held + is_hover both true); a pure hover never sets
                -- is_held -> ignored; a drag-off releases off the cell (is_hover
                -- false) -> cancelled. (Now that _trace routes through mod:info, the
                -- IGNORED line is visible in the user's log to confirm the gate.)
                local press_key = tostring(hand_field) .. "#" .. tostring(index)
                local was_held = held_now[press_key] or held_prev[press_key]
                if index and was_held and hotspot.is_hover then
                    self:_ct_on_offhand_pressed(hand_field, index)
                elseif index then
                    _trace("INPUT PRESS offhand-row IGNORED (no preceding hold OR cursor off cell; hover/sticky leak) %s#%s was_held=%s is_hover=%s bid=%s",
                        tostring(hand_field), tostring(index), tostring(was_held), tostring(hotspot.is_hover), tostring(self._item_backend_id))
                end
                break
            end
        end
    end)

    mod._cos_selected_primary_skin = function(self, backend_item)
        local Managers = get_managers()
        local WeaponSkins = get_weapon_skins()
        return mod._la_option_icon_policy.selected_primary_skin(
            self, backend_item, function(item)
                local backend_mgr = Managers and Managers.backend
                local items_iface = backend_mgr and backend_mgr._interfaces
                    and backend_mgr._interfaces.items
                    and backend_mgr:get_interface("items")
                local backend_id = item and item.backend_id
                    or (self and self._item_backend_id)
                if backend_id and items_iface and items_iface.get_skin then
                    return items_iface:get_skin(backend_id)
                end
            end, WeaponSkins and WeaponSkins.default_skins)
    end

    HeroWindowItemCustomization._ct_on_offhand_pressed = function(self, hand_field, index)
        local Managers = get_managers()
        local WeaponSkins = get_weapon_skins()
        -- v0.9.9.4-dev: hand-aware dispatch. Pre-v0.9.9.4 signature was
        -- (self, index) with implicit left_hand_unit; tolerate older callers
        -- by detecting numeric first-arg.
        if type(hand_field) == "number" then
            index = hand_field
            hand_field = "left_hand_unit"
        end
        if not hand_field or not index then return end

        local widgets_by_hand = self._ct_offhand_widgets_by_hand
        local hand_widgets = widgets_by_hand and widgets_by_hand[hand_field]
        if not hand_widgets then return end
        local widget = hand_widgets[index]
        if not widget then return end

        local weapon_key = self._ct_offhand_weapon_key
        local hand_pools = _get_offhand_options(weapon_key)
        local pool = hand_pools and hand_pools[hand_field]
        local opt = pool and pool[index]
        if not opt then return end

        -- #923: bind the option's local presentation to this exact target item and
        -- current row-one skin. The canonical pool remains immutable, so another
        -- weapon family/instance cannot inherit this icon. Provider-owned icon
        -- names stay in memory only; persistence and RPCs keep semantic identities.
        if opt.la_armoury_key and opt.cos_authored ~= true then
            local backend_mgr = Managers and Managers.backend
            local items_iface = backend_mgr and backend_mgr._interfaces
                and backend_mgr._interfaces.items and backend_mgr:get_interface("items")
            local backend_item = nil
            if self._item_backend_id and items_iface and items_iface.get_item_from_id then
                backend_item = items_iface:get_item_from_id(self._item_backend_id)
            end
            local la_mod = get_mod("Loremasters-Armoury")
            opt = mod._la_option_icon_policy.resolve_for_item(opt, weapon_key,
                mod._cos_selected_primary_skin(self, backend_item),
                la_mod and la_mod.SKIN_LIST, LA_BRIDGE.normalize_weapon_type)
        end

        -- v0.8.32: key selection by backend_id (per-weapon-instance).
        -- v0.9.9.4: nested under hand_field.
        if self._item_backend_id then
            _offhand_session_state.migrate_legacy(self._item_backend_id)
            _offhand_selection[self._item_backend_id] = _offhand_selection[self._item_backend_id] or {}
            _offhand_selection[self._item_backend_id][hand_field] = opt
            -- v0.9.43-dev WRITE trace: the user-press primary write. This is the
            -- selection the get_item_units RESOLVE + PAINT paths subsequently read.
            -- trigger=offhand_press.
            _trace("WRITE _offhand_selection[%s][%s] = opt(name=%s kind=%s armoury=%s intended_unit=%s vanilla_skin=%s) trigger=offhand_press",
                tostring(self._item_backend_id), tostring(hand_field), tostring(opt.name),
                tostring(opt.la_armoury_key and "LA" or "vanilla"),
                tostring(opt.la_armoury_key), tostring(opt.unit or opt.intended_unit),
                tostring(opt.vanilla_skin))
        end
        -- v0.9.8.9 REMOVAL: the v0.9.5/v0.9.5.1/v0.9.8.1 mirror-write block
        -- that iterated `inv._equipment.slots` and copied the offhand opt into
        -- _offhand_selection[every_same-item_type_slot_bid] is GONE.
        --
        -- User crash report 2026-05-22 17:18: Grail Knight has TWO genuinely
        -- separate equipped shield instances (slot_melee + slot_ranged, both
        -- with item_type=es_1h_sword_shield_breton, different backend_ids).
        -- Customizing ONE shield via the offhand picker wrote the opt to BOTH
        -- backend_ids via the mirror. Then close → deferred-emit drained TWO
        -- broadcasts for the same selection under different slot keys → PC-B
        -- cached both → the LATER broadcast (slot=one_handed_sword_shield_
        -- template_2) overwrote the cache key the LA paint pipeline reads
        -- from, producing a visually wrong shield on PC-B's view.
        --
        -- Empirical evidence (PC-A log lines around 17:17:46):
        --   `[ct offhand] backend_id mirror-write _offhand_selection[08fab327-...]
        --    (slot=slot_ranged, item_type=es_1h_sword_shield_breton,
        --    primary bid=92b5b57d-...)`
        --   — slot_ranged was getting mirrored from slot_melee's customization.
        --
        -- Why the v0.9.5 mirror was added: a prior audit interpreted
        -- `[LA paint] skip: no _offhand_selection for backend_id=...` as
        -- "the customization screen's bid != the equipped bid (preview clone
        -- created on Apply Skin)". But the mirror loop iterates
        -- `inv._equipment.slots` — it only ever targeted EQUIPPED items, not
        -- transient preview clones. So the mirror was actually copying between
        -- TWO equipped items of same item_type from the start. The v0.9.5 use
        -- case might have been the same Grail-Knight-style two-equipped-
        -- instances bug, not a true preview-clone mismatch.
        --
        -- If the original symptom returns (offhand selection not applied to
        -- the in-keep model), the next investigation will reveal the actual
        -- root cause without the cross-instance contamination as a confound.
        --
        -- The primary write `_offhand_selection[self._item_backend_id] = opt`
        -- (above) covers the user's customization-screen item correctly —
        -- that's the bid the in-keep wield of THAT specific item reads.
        _preload_offhand_for_option(opt)

        -- v0.9.3.4-hotfix: DEFER the peer-sync emit to screen exit. Previously
        -- every preview click fired _send_la_apply immediately, broadcasting to
        -- the host on each click — PC-A→PC-B test 2026-05-21 18:27 surfaced
        -- 30 emits in 25s while user was just browsing shields. Host crashed
        -- on the rapid wield-RPC + ProfileSync package-load race. The user's
        -- expectation: previews stay local until "selected" — operationalized
        -- here as "when user leaves the customization screen with this offhand
        -- still pending."
        --
        -- Behavior change:
        --   * Local _offhand_selection write (above, line ~2170) is KEPT.
        --     Locally the picker still updates immediately so the user sees
        --     their choice in the previewer. (Wrong-mesh-wrap on the in-keep
        --     character is a separate symptom of that local write reaching
        --     BackendUtils.get_item_units — out of scope for this hotfix; will
        --     address by scoping local writes to the customization screen's
        --     own previewer in a follow-up.)
        --   * The broadcast is queued on `mod._pending_la_emit_on_exit`. The
        --     existing HeroWindowItemCustomization.on_exit hook (line ~1756)
        --     drains the queue, firing _send_la_apply for whatever the user
        --     LEFT selected (rapidly clicking through 30 options → only the
        --     30th fires).
        if opt and opt.la_armoury_key then
            local pm = Managers and Managers.player
            local local_player = _local_player_safe(pm)
            local player_unit = local_player and local_player.player_unit
            local template_key = nil
            local backend_mgr = Managers and Managers.backend
            local bi = backend_mgr and backend_mgr._interfaces
                and backend_mgr._interfaces.items and backend_mgr:get_interface("items")
            if self._item_backend_id and bi and bi.get_item_from_id then
                local item = bi:get_item_from_id(self._item_backend_id)
                template_key = item and item.data and item.data.template
            end
            -- #702: queue the exact Apply intent even when no player unit exists.
            -- The on-exit commit owns persistence; player_unit is optional delivery
            -- context for the subsequent peer emit.
            if self._item_backend_id then
                mod._pending_la_emit_on_exit = mod._pending_la_emit_on_exit or {}
                -- v0.9.9.4-dev: queue per-hand so multi-mount weapons with two
                -- LA picks (rare today — LA ships only left_hand variants) each
                -- get their own deferred emit. Keys as bid|hand. "last clicked
                -- wins" semantic preserved within each (bid, hand) pair.
                local q_key = (self._item_backend_id or "__no_backend__") .. "|" .. hand_field
                mod._pending_la_emit_on_exit[q_key] = {
                    player_unit  = player_unit,
                    weapon_key   = weapon_key or "slot_unknown",
                    template_key = template_key,
                    hand_field   = hand_field,
                    armoury_key  = opt.la_armoury_key,
                    vanilla_key  = opt.vanilla_skin,
                    -- External LA assets are local provider data, not Cosmetics
                    -- persistence/sync payload. #883 re-resolves the exact icon.
                    inventory_icon = opt.cos_authored and opt.inventory_icon or nil,
                    cos_authored = opt.cos_authored == true,
                    backend_id   = self._item_backend_id,  -- v0.9.71: persistence key
                }
                -- v0.9.43-dev WRITE trace: deferred peer-sync emit queued (drains on
                -- SCREEN exit, not now — see on_exit hook). This is the commit that
                -- becomes the authoritative cos_la_apply broadcast.
                _trace("WRITE pending_la_emit_on_exit[%s] armoury=%s vanilla=%s hand=%s weapon=%s",
                    tostring(q_key), tostring(opt.la_armoury_key), tostring(opt.vanilla_skin),
                    tostring(hand_field), tostring(weapon_key))
            elseif printf then
                printf("[cos:702] OFFHAND-QUEUE rejected: missing exact backend id hand=%s armoury=%s",
                    tostring(hand_field), tostring(opt.la_armoury_key))
            end
        elseif opt then
            -- v0.9.61-dev (#203): a NON-LA (vanilla) offhand press must SUPERSEDE any
            -- LA emit still queued for this (bid, hand). The queue is "last pick wins",
            -- but before this only LA picks WROTE the queue, so a vanilla press left the
            -- prior LA key queued and the exit-drain broadcast a shield the wearer is no
            -- longer using. The 2026-07-02 client log proved the divergence: the user's
            -- final press was "GK Shield (Green)" (vanilla, live body resolved
            -- wpn_emp_gk_shield_04) yet the exit emit sent the stale
            -- Kruber_empire_shield_basic2_Kotbs01, so the wearer rendered vanilla while
            -- peers/host got the stale LA shield. Clear at the source (no RPC change).
            -- NOTE: a true "revert to vanilla" broadcast is still needed to purge a
            -- host's cross-session stale _la_equips_by_peer entry (separate #203 item).
            if mod._pending_la_emit_on_exit then
                local vkey = (self._item_backend_id or "__no_backend__") .. "|" .. tostring(hand_field)
                local stale = mod._pending_la_emit_on_exit[vkey]
                if stale then
                    mod:info("[cos-la-sync] EXIT-QUEUE CLEAR bid=%s hand=%s vanilla_pick=%s superseded_stale_LA=%s",
                        tostring(self._item_backend_id), tostring(hand_field),
                        tostring(opt.name), tostring(stale.armoury_key))
                    mod._pending_la_emit_on_exit[vkey] = nil
                end
            end
            -- v0.9.82-dev (#416): a committed vanilla offhand press REPLICATES to peers
            -- via the parallel mesh store. Queue ONE deferred offhand_unit message under
            -- the (bid, hand) key (same key namespace as the LA emit, so last-pick-wins
            -- across LA and vanilla presses). offhand_unit = the picked mesh, or "" when
            -- the pick has no mesh (base / default / pure-texture opt) -- an empty path is
            -- the CLEAR sentinel. The recv side (mod._store_offhand_mesh_recv) both stores
            -- the vanilla mesh AND clears any stale LA armoury entry for this (wearer,
            -- slot, hand), so this single message supersedes a prior LA shield (the #265
            -- "revert stale LA on a vanilla pick" case) AND applies the new vanilla mesh
            -- in one shot. Drained on Apply / screen-exit like the LA emit; the on_exit
            -- Apply gate still drops the whole queue on an un-Applied browse.
            do
                local pm_v = Managers and Managers.player
                local lp_v = _local_player_safe(pm_v)
                local player_unit_v = lp_v and lp_v.player_unit
                local template_key_v = nil
                local backend_mgr_v = Managers and Managers.backend
                local bi_v = backend_mgr_v and backend_mgr_v._interfaces
                    and backend_mgr_v._interfaces.items and backend_mgr_v:get_interface("items")
                if self._item_backend_id and bi_v and bi_v.get_item_from_id then
                    local item_v = bi_v:get_item_from_id(self._item_backend_id)
                    template_key_v = item_v and item_v.data and item_v.data.template
                end
                if self._item_backend_id then
                    local vkey2 = (self._item_backend_id or "__no_backend__") .. "|" .. tostring(hand_field)
                    local selected_inventory_icon = opt.inventory_icon
                    if not selected_inventory_icon and _SHIELD_ICON_OWNER_ITEM_TYPES[weapon_key] then
                        selected_inventory_icon = _inventory_icon_for_offhand_unit(
                            opt.unit or opt.intended_unit, template_key_v)
                    end
                    mod._pending_la_emit_on_exit = mod._pending_la_emit_on_exit or {}
                    mod._pending_la_emit_on_exit[vkey2] = {
                        offhand_unit = (opt.unit or opt.intended_unit) or "",
                        skin_key     = opt.skin_key,
                        inventory_icon = selected_inventory_icon,
                        player_unit  = player_unit_v,
                        weapon_key   = weapon_key or "slot_unknown",
                        template_key = template_key_v,
                        hand_field   = hand_field,
                        backend_id   = self._item_backend_id,
                    }
                    mod:info("[cos-la-sync] EXIT-QUEUE OFFHAND-MESH bid=%s hand=%s vanilla_pick=%s unit=%s",
                        tostring(self._item_backend_id), tostring(hand_field), tostring(opt.name),
                        tostring((opt.unit or opt.intended_unit) or "<clear>"))
                elseif printf then
                    printf("[cos:702] OFFHAND-QUEUE rejected: missing exact backend id hand=%s mesh=%s",
                        tostring(hand_field), tostring((opt.unit or opt.intended_unit) or "<clear>"))
                end
            end
        end

        -- v0.9.9.4-dev: deselect any prior selection in THIS hand's row; rows
        -- for other hands keep their selections.
        for i, w in ipairs(hand_widgets) do
            local is_sel = (i == index)
            w.content.button_hotspot.is_selected = is_sel
            w.content.equipped = is_sel
        end

        self._ct_offhand_selected_by_hand = self._ct_offhand_selected_by_hand or {}
        self._ct_offhand_selected_by_hand[hand_field] = index
        self._ct_selected_offhand_index = index

        -- PENDING-ROW-1 PRESERVATION: vanilla `_on_illusion_index_pressed`
        -- builds the customization-preview previewer with `_item = { data =
        -- ItemMasterList[pending_skin], skin = pending_skin }`. That's the
        -- pending (not-yet-Applied) row-1 selection — and it's the truth source
        -- for "what skin should the preview render right now". If we re-resolve
        -- from the backend item, we revert the preview to the LAST APPLIED
        -- illusion every time the user clicks a row-2 shield, throwing away
        -- their pending row-1 pick. User report 2026-05-06.
        --
        -- Resolution order:
        --   1. self._previewer._item (pending row-1 OR equipped illusion the
        --      screen auto-selected on open — both correct)
        --   2. exact row-one `is_selected` cell (never stale `equipped`)
        --   3. backend item's `.skin` (vanilla-crafted edge case)
        --   4. backend get_skin(backend_id) (vanilla-crafted Bret etc.)
        --   5. WeaponSkins.default_skins[item.key]
        local pending_data
        if self._previewer and self._previewer._item then
            local pi = self._previewer._item
            if pi.data then pending_data = pi.data end
        end

        local item = self:_get_item(self._item_backend_id)
        local pending_skin = mod._cos_selected_primary_skin(self, item)
        if item then
            local skin_data = pending_skin and WeaponSkins.skins[pending_skin]
            if skin_data then
                local preview_item = {
                    data = pending_data or item.data,
                    skin = pending_skin,
                    -- v0.8.33: stamp the user's actual backend_id onto the
                    -- preview item so `BackendUtils.get_item_units` can resolve
                    -- our per-backend-id offhand selection. Without this the
                    -- preview_item.backend_id is nil, our hook bails out, and
                    -- the preview falls back to whatever the SKIN resolves to
                    -- — the user observed the model in the customization
                    -- preview not updating when clicking a different shield
                    -- option, only changing in-game after Apply.
                    -- v0.8.37: stamp backend_id unconditionally; the v0.8.34
                    -- crash hypothesis is now that post-spawn texture painting
                    -- (Unit.set_texture_for_materials on a kind="unit" bundled
                    -- mesh) was the AV trigger, not the spawn itself. Painting
                    -- is now skipped for kind="unit" in `_paint_offhand_textures_locally`.
                    -- If Reiland's preview now spawns the mesh (possibly
                    -- magenta / un-bound textures) and doesn't crash, the
                    -- texture paint was indeed the culprit. If it still
                    -- crashes, the spawn itself is unsafe and we'll revert.
                    backend_id = self._item_backend_id,
                }
                self:_spawn_item_unit(preview_item, true)
            end

            -- ROW-2-ONLY APPLY: vanilla `_craft(self._material_items, ...)` no-ops
            -- if material_items is empty. When the user only changed the offhand
            -- (no row-1 click), nothing has populated _material_items and Apply
            -- silently does nothing. Seed it with the currently-effective skin's
            -- backend_id (or the pending row-1 if the user already picked one but
            -- didn't apply yet). The craft will be a no-op skin re-apply, but the
            -- ensuing _apply_weapon_skin_craft_complete -> _set_loadout_item path
            -- forces a weapon re-spawn, which is what actually pulls in the new
            -- offhand via our BackendUtils.get_item_units hook.
            if pending_skin and (not self._material_items or #self._material_items == 0) then
                local items_iface = Managers.backend:get_interface("items")
                if items_iface and items_iface.get_weapon_skin_from_skin_key then
                    local skin_backend_id = items_iface:get_weapon_skin_from_skin_key(pending_skin)
                    if skin_backend_id then
                        self._material_items = self._material_items or {}
                        self._material_items[#self._material_items + 1] = skin_backend_id
                        self._skin_dirty = true
                    end
                end
            end

        end

        self:_enable_craft_button(true, true)
        self:_play_sound("play_gui_equipment_equip")
    end

    local owner = {
        hook_count = 3,
        method_count = 1,
        filter_illusion_widgets = mod._filter_illusion_widgets,
        selected_primary_skin = mod._cos_selected_primary_skin,
        on_offhand_pressed = HeroWindowItemCustomization._ct_on_offhand_pressed,
    }
    mod._cos_offhand_picker_owner = owner
    return owner
end

return Picker
