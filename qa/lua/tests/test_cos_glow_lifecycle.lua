return function(H, repo_root)
    local function read(relative_path)
        local file = assert(io.open(repo_root .. "/" .. relative_path, "rb"))
        local source = file:read("*a")
        file:close()
        return source
    end

    local picker = read("cosmetics_tweaker/scripts/mods/cosmetics_tweaker/_glow_picker.lua")
    -- #1159: the create_equipment glow rehydrate and glow-override apply moved
    -- into the equipment-assembly owner, so it joins the surface this test reads.
    -- The owner is added to the census rather than the expectations lowered.
    local entry = read("cosmetics_tweaker/scripts/mods/cosmetics_tweaker/cosmetics_tweaker.lua")
        .. read("cosmetics_tweaker/scripts/mods/cosmetics_tweaker/_cos_preview_runtime.lua")
        .. read("cosmetics_tweaker/scripts/mods/cosmetics_tweaker/_cos_offhand_picker.lua")
        .. read("cosmetics_tweaker/scripts/mods/cosmetics_tweaker/_cos_equipment_assembly.lua")
        .. read("cosmetics_tweaker/scripts/mods/cosmetics_tweaker/_cos_husk_wield_runtime.lua")
        .. read("cosmetics_tweaker/scripts/mods/cosmetics_tweaker/_cos_glow_picker_host.lua")
        .. read("cosmetics_tweaker/scripts/mods/cosmetics_tweaker/_cos_update_scheduler.lua")
    local command_owner = read(
        "cosmetics_tweaker/scripts/mods/cosmetics_tweaker/_cos_command_owner.lua")
    local button_owner = read(
        "cosmetics_tweaker/scripts/mods/cosmetics_tweaker/_cos_glow_editor_button.lua")
    local item_grid_presentation = read(
        "cosmetics_tweaker/scripts/mods/cosmetics_tweaker/"
        .. "_cos_item_grid_presentation.lua")
    local glow_transport = read(
        "cosmetics_tweaker/scripts/mods/cosmetics_tweaker/"
        .. "_cos_glow_transport.lua")
    local instance_policy = read(
        "cosmetics_tweaker/scripts/mods/cosmetics_tweaker/_cos_glow_instance_policy.lua")
    local preview_policy_path = repo_root
        .. "/cosmetics_tweaker/scripts/mods/cosmetics_tweaker/_cos_glow_preview_policy.lua"
    local preview_policy_source = read(
        "cosmetics_tweaker/scripts/mods/cosmetics_tweaker/_cos_glow_preview_policy.lua")
    local preview_policy = assert(loadfile(preview_policy_path))()

    H.test("Cosmetics local-player lookups are safe across network teardown", function()
        local lifecycle_sources = table.concat({
            entry,
            read("cosmetics_tweaker/scripts/mods/cosmetics_tweaker/_cos_glow.lua"),
            read("cosmetics_tweaker/scripts/mods/cosmetics_tweaker/_cos_diagnostics.lua"),
            read("cosmetics_tweaker/scripts/mods/cosmetics_tweaker/_la_bridge.lua"),
            read("cosmetics_tweaker/scripts/mods/cosmetics_tweaker/_tpe.lua"),
        }, "\n")
        local executable = lifecycle_sources:gsub("%-%-[^\n]*", "")
        H.truthy(entry:find('local function _local_player_safe(player_manager)', 1, true))
        H.truthy(entry:find('pm.local_player_safe', 1, true))
        H.truthy(command_owner:find('register("local_player_safe_network_lifecycle_609"', 1, true))
        H.truthy(command_owner:find('title state must yield nil', 1, true))
        H.truthy(command_owner:find('ingame state lost player', 1, true))
        H.equal(executable:find(':local_player%(%s*%)'), nil)
    end)

    H.test("Cosmetics glow persistence is exact-item plus illusion and explicit-Apply", function()
        -- #48: the exact-instance key builder moved into the shared policy
        -- module so the picker and the renderer cannot drift apart. The
        -- invariant is unchanged; assert it against its new owner and assert
        -- that the picker delegates rather than re-deriving.
        H.truthy(instance_policy:find('return string.format("backend:%s|skin:%s", tostring(backend_id), tostring(skin or ""))', 1, true))
        H.truthy(picker:find("return INSTANCE_POLICY.identity_key(backend_id, slot_data)", 1, true))
        H.truthy(picker:find("if not GlowPicker._open or not GlowPicker._dirty then return false end", 1, true))
        H.truthy(picker:find("_save_per_item_glow(all_data)", 1, true))
        H.truthy(picker:find("GlowPicker._dirty = false", 1, true))
        H.truthy(picker:find("if mod._emit_per_item_glow then pcall(mod._emit_per_item_glow) end", 1, true))
        H.truthy(picker:find("function GlowPicker.committed_state_for", 1, true))
        H.truthy(picker:find("GlowPicker._commit_revision = GlowPicker._commit_revision + 1", 1, true))
        H.truthy(picker:find("pcall(mod._cos_glow_badges_refresh", 1, true))
    end)

    H.test("Cosmetics glow close rolls preview back to committed state", function()
        H.truthy(picker:find("function GlowPicker.close()", 1, true))
        -- #610: close() reads the committed state into a local and rolls the
        -- runtime paint entry back to it (or nil when the item had no override).
        H.truthy(picker:find("local committed = GlowPicker._committed_glow_state", 1, true))
        H.truthy(picker:find("mod._per_item_glow_runtime[backend_id] = committed and _clone(committed) or nil", 1, true))
        H.truthy(picker:find("pcall(mod._reapply_glow_on_wielded)", 1, true))
        -- #610: cancelling a preview on an item with NO committed override repaints
        -- the illusion's native template directly so the glow visibly rolls back.
        H.truthy(picker:find("if not committed and mod._repaint_native_glow_on_wielded then", 1, true))
        H.truthy(picker:find("pcall(mod._repaint_native_glow_on_wielded, native_mat)", 1, true))
    end)

    H.test("Cosmetics glow live preview owns exact customization item and skin", function()
        local right, left, dead = {}, {}, {}
        local host = {
            _item_backend_id = "backend-796",
            _parent = { loadout_sync_id = 0 },
            _previewer = {
                _item = {
                    skin = "skin-796",
                    data = { name = "weapon-796", template = "template-796" },
                },
                _spawned_units = { right, dead, left },
            },
        }
        local target, state = preview_policy.resolve(host, "backend-796",
            { skin = "skin-796" }, function(unit) return unit ~= dead end)
        H.equal(state, "ready")
        H.equal(#target.units, 2)
        H.equal(target.units[1], right)
        H.equal(target.units[2], left)
        H.equal(target.skin, "skin-796")
        H.equal(target.item_name, "weapon-796")

        local rejected, reason = preview_policy.resolve(host, "other-backend",
            { skin = "skin-796" })
        H.equal(rejected, nil)
        H.equal(reason, "backend_mismatch")
        rejected, reason = preview_policy.resolve(host, "backend-796",
            { skin = "other-skin" })
        H.equal(rejected, nil)
        H.equal(reason, "skin_mismatch")

        local refreshed, revision = preview_policy.request_inventory_refresh(
            host, "backend-796")
        H.truthy(refreshed)
        H.equal(revision, 1)
        H.equal(host._parent.loadout_sync_id, 1)
        refreshed, reason = preview_policy.request_inventory_refresh(
            host, "other-backend")
        H.equal(refreshed, false)
        H.equal(reason, "backend_mismatch")

        local spawn = preview_policy.resolve_spawn({
            skin = "skin-796",
            data = { name = "weapon-796", template = "template-796" },
        }, "backend-796", "weapon", function() return "weapon" end,
            function(exact_backend_id, _, active_backend_id)
                return exact_backend_id or active_backend_id
            end)
        H.equal(spawn.skin, "skin-796")
        H.equal(spawn.preview_backend_id, "backend-796")
        H.equal(spawn.glow_backend_id, "backend-796")

        local restored, bound, logged = 0, {}, 0
        local picker_stub = {
            is_open_for = function() return false end,
            restore_runtime_for = function() restored = restored + 1 end,
        }
        local glow_stub = {
            bind_glow_unit = function(unit, backend_id, skin)
                bound[#bound + 1] = { unit, backend_id, skin }
            end,
        }
        local rebound, dirty = preview_policy.bind_spawned({ right, left },
            spawn, picker_stub, glow_stub, function() logged = logged + 1 end)
        H.truthy(rebound)
        H.equal(dirty, false)
        H.equal(restored, 1)
        H.equal(#bound, 2)
        H.equal(bound[2][1], left)
        H.equal(bound[2][2], "backend-796")
        H.equal(logged, 1)
    end)

    H.test("Cosmetics glow slider, Apply, Restore, and Cancel repaint the preview pane", function()
        local glow = read("cosmetics_tweaker/scripts/mods/cosmetics_tweaker/_cos_glow.lua")
        H.truthy(entry:find("state.glow_picker.handle_input(resolve_input_service(self), self)", 1, true))
        H.truthy(entry:find("state.glow_picker.draw(ui_renderer, input_service, dt, self)", 1, true))
        H.truthy(picker:find("function GlowPicker.handle_input(input_service, preview_host)", 1, true))
        H.truthy(picker:find("function GlowPicker.draw(ui_renderer, input_service, dt, preview_host)", 1, true))
        H.truthy(picker:find("GlowPicker._preview_host = preview_host", 1, true))
        H.truthy(glow:find("mod._reapply_glow_on_customization_preview = function", 1, true))
        H.truthy(glow:find("GLOW_PREVIEW_POLICY.resolve(host, backend_id, slot_data, _is_unit)", 1, true))
        H.truthy(picker:find("pcall(mod._reapply_glow_on_customization_preview", 1, true))
        H.truthy(picker:find("pcall(mod._repaint_native_glow_on_customization_preview", 1, true))
        H.truthy(picker:find("GlowPicker.request_inventory_preview_refresh(GlowPicker._preview_host, backend_id)", 1, true))
        local _, refresh_calls = picker:gsub(
            "GlowPicker%.request_inventory_preview_refresh%(GlowPicker%._preview_host, backend_id%)", "")
        H.equal(refresh_calls, 2)
        H.truthy(entry:find("state.glow_preview_policy.resolve_spawn(item", 1, true))
        H.truthy(preview_policy_source:find("if not dirty then picker.restore_runtime_for", 1, true))
        H.truthy(preview_policy_source:find("glow.bind_glow_unit(unit, backend_id", 1, true))
        local bind_at = assert(entry:find("state.glow_preview_policy.bind_spawned", 1, true))
        local paint_at = assert(entry:find("mod._cos.apply_glow_override({ units[1], units[2] })", bind_at, true))
        H.truthy(bind_at < paint_at)
        H.truthy(preview_policy_source:find("[glow:796] preview spawn rebound", 1, true))
        H.equal(glow:find("network_send", 1, true), nil)
    end)

    H.test("Cosmetics glow replay is host-authoritative and locally bounded", function()
        H.truthy(glow_transport:find('mod:network_register("cos_glow_apply_req"', 1, true))
        H.truthy(glow_transport:find('mod:network_register("cos_glow_apply"', 1, true))
        H.truthy(glow_transport:find('state_pull = "piggyback_cos_la_state_req"', 1, true))
        H.truthy(glow_transport:find("local COS574_REHYDRATE_MAX_ATTEMPTS = 40", 1, true))
        H.truthy(glow_transport:find("local COS574_REHYDRATE_WINDOW = 10", 1, true))
        H.truthy(glow_transport:find("retry_network = false", 1, true))
        H.truthy(entry:find("if mod._cos574_glow_rehydrate_tick then mod._cos574_glow_rehydrate_tick() end", 1, true))
    end)

    H.test("Cosmetics glow repaints equipment preview and remote wield surfaces", function()
        H.truthy(entry:find('rehydrate path=create_equipment', 1, true))
        H.truthy(entry:find('rehydrate path=hero_preview', 1, true))
        H.truthy(entry:find('repaint path=husk_wield', 1, true))
        H.truthy(entry:find(
            "complete_glow_rehydrate = _cos574_complete_glow_rehydrate", 1, true))
        H.truthy(entry:find("state.complete_glow_rehydrate(", 1, true))
        H.truthy(entry:find('wearer_peer, "husk_wield", glow_matches', 1, true))
    end)

    H.test("Cosmetics glow editor and badges are manual Apply-only presentation", function()
        H.equal(entry:find("_glow_auto_popup_for_local", 1, true), nil)
        H.equal(entry:find("[glow_picker:auto] opened on illusion select", 1, true), nil)
        H.equal(entry:find("glow_picker_auto_popup_enabled", 1, true), nil)
        H.truthy(entry:find("_create_glow_editor_button", 1, true))
        H.truthy(button_owner:find('scenegraph_id = "info_window"', 1, true))
        H.truthy(entry:find("GlowPicker.position_toggle(self, glow_widget, 96, 20)", 1, true))
        H.truthy(picker:find('mod:dofile("scripts/mods/cosmetics_tweaker/_cos_glow_panel_layout")', 1, true))
        H.truthy(picker:find(
            "GlowPicker.frame_style = PANEL_LAYOUT.make_frame_style(GlowPicker)", 1, true))
        H.truthy(picker:find(
            "GlowPicker.position_toggle = PANEL_LAYOUT.make_toggle_positioner(PANEL_INSET)",
            1, true))
        H.truthy(picker:find('scale = "fit"', 1, true))
        H.truthy(picker:find("PANEL_LAYOUT.resolve(preview_host)", 1, true))
        H.truthy(picker:find("PANEL_LAYOUT.contains(GlowPicker._panel_bounds, cx, cy)", 1, true))
        H.equal(picker:find("TOP_INSET", 1, true), nil)
        H.equal(entry:find("offset = { 1272, 380, 20 }", 1, true), nil)
        H.equal(entry:find('has_texture_by_name("cos_glow_badge")', 1, true), nil)
        H.truthy(button_owner:find('{ pass_type = "rect", style_id = "button" }', 1, true))
        H.truthy(button_owner:find('{ pass_type = "texture_frame", style_id = "button_frame", texture_id = "button_frame" }', 1, true))
        H.truthy(button_owner:find("button_frame = glow_picker.FRAME_TEXTURE", 1, true))
        H.truthy(button_owner:find("button_frame = glow_picker.frame_style(", 1, true))
        H.truthy(picker:find('GlowPicker.FRAME_TEXTURE = "menu_frame_12"', 1, true))
        H.truthy(picker:find("GlowPicker.FRAME_TEX_SIZE = { 64, 64 }", 1, true))
        H.truthy(picker:find("corner = { 11, 11 }", 1, true))
        H.truthy(picker:find("vertical = { 5, 1 }", 1, true))
        H.truthy(picker:find("horizontal = { 1, 5 }", 1, true))
        H.truthy(picker:find('content = { text = "Apply", frame = GlowPicker.FRAME_TEXTURE, hotspot = {} }', 1, true))
        H.truthy(picker:find("The native info_window frame/background remains", 1, true))
        H.equal(picker:find('local function _widget_panel_bg()', 1, true), nil)
        H.truthy(entry:find("GlowPicker.is_open_for(bid, { skin = skin })", 1, true))
        H.truthy(item_grid_presentation:find(
            'mod:hook_safe("ItemGridUI", "init"', 1, true))
        H.truthy(item_grid_presentation:find(
            'mod:hook_safe("ItemGridUI", "_populate_inventory_page"', 1, true))
        H.truthy(item_grid_presentation:find(
            "widget._ct_glow_badge_enriched", 1, true))
        H.truthy(item_grid_presentation:find(
            "GlowPicker.committed_state_for", 1, true))
        H.truthy(item_grid_presentation:find(
            "mod._cos_glow_badges_refresh = function", 1, true))
        H.truthy(entry:find("GlowPicker.draw_native_information(func, self, ui_renderer, dt,", 1, true))
        H.truthy(picker:find("PANEL_LAYOUT.without_native_information(", 1, true))
        H.truthy(picker:find("Information contents for this exact editor identity", 1, true))
        H.truthy(read("cosmetics_tweaker/scripts/mods/cosmetics_tweaker/_cos_runtime_checks.lua")
            :find("GlowPicker.position_toggle(probe_host, probe_widget, 96, 20)", 1, true))

        -- #795: illusion-button passes must exist before UIWidget.init creates
        -- its positional pass_data twin. Never append a pass to live widgets.
        local enrich = assert(item_grid_presentation:find(
            "local illusion_added = enrich_illusion_glow_badge(widget_definition)",
            1, true))
        local init = assert(item_grid_presentation:find(
            "return func(widget_definition, ui_renderer)", enrich, true))
        H.truthy(enrich < init)
        local refresh_start = assert(item_grid_presentation:find(
            "local function refresh_illusion_glow_badges(self)", 1, true))
        local refresh_end = assert(item_grid_presentation:find(
            "\n    end", refresh_start, true))
        local refresh = item_grid_presentation:sub(refresh_start, refresh_end)
        H.equal(refresh:find("enrich_illusion_glow_badge(widget)", 1, true), nil)
        H.truthy(item_grid_presentation:find(
            "GLOW_BADGE.is_illusion_definition(widget)", 1, true))

        local package_file = read("cosmetics_tweaker/resource_packages/cosmetics_tweaker/cosmetics_tweaker.package")
        local data = read("cosmetics_tweaker/scripts/mods/cosmetics_tweaker/cosmetics_tweaker_data.lua")
        H.truthy(package_file:find('"materials/ui/cos_glow_badge"', 1, true))
        H.truthy(package_file:find('"gui/1080p/single_textures/cosmetics_tweaker/cos_glow_badge"', 1, true))
        -- The texture list may be formatted on one line or expanded as other
        -- authored Cosmetics icons are added.  Assert membership instead of
        -- coupling this lifecycle test to whitespace/list layout.
        H.truthy(data:find('"cos_glow_badge"', 1, true))
        H.truthy(data:find('{ "hero_view", "materials/ui/cos_glow_badge" }', 1, true))
    end)

    H.test("Cosmetics glow editor button owner is idempotent and contextual", function()
        local module_path = repo_root
            .. "/cosmetics_tweaker/scripts/mods/cosmetics_tweaker/"
            .. "_cos_glow_editor_button.lua"
        local module = assert(loadfile(module_path))()
        local policy_calls = 0
        local glow_badge = {
            button = function(family, open)
                policy_calls = policy_calls + 1
                return { available = family == "weaves", selected = open == true }
            end,
            color = function() return { 255, 11, 22, 33 } end,
        }
        local glow_picker = {
            FRAME_TEXTURE = "frame",
            classify = function() return "weaves" end,
            is_open_for = function() return true end,
            committed_state_for = function() return { active = true } end,
            frame_style = function(width, height, depth)
                return { size = { width, height }, offset = { 0, 0, depth } }
            end,
        }
        local init_count = 0
        local ui_widget = {
            init = function(definition)
                init_count = init_count + 1
                return definition
            end,
        }
        local mod = {
            localize = function(_, key) return "localized:" .. key end,
        }
        local owner = module.install(mod, {
            glow_picker = glow_picker,
            glow_badge = glow_badge,
            ui_widget = ui_widget,
        })
        H.equal(mod._glow_editor_button_policy_377, glow_badge.button)
        H.equal(module.install(mod, {}), owner)

        local widget = owner.create()
        H.equal(init_count, 1)
        H.equal(widget.scenegraph_id, "info_window")
        H.equal(widget.content.button_frame, "frame")
        H.equal(widget.content.glow_editor_label,
            "localized:glow_picker_editor_button")
        H.equal(widget.content.equipped, false)

        local host = {
            _item_backend_id = "item-377",
            _ct_glow_editor_widget = {
                content = { button_hotspot = {} },
                style = {
                    icon_texture = {}, glow_editor_label = {}, button = {},
                },
            },
        }
        H.equal(owner.refresh(host, "weave-skin"), "weaves")
        H.equal(host._ct_glow_editor_widget.content.glow_backend_id, "item-377")
        H.equal(host._ct_glow_editor_widget.content.button_hotspot.disable_button, false)
        H.equal(host._ct_glow_editor_widget.content.button_hotspot.is_selected, true)
        H.equal(host._ct_glow_editor_widget.style.icon_texture.color[2], 11)
        H.equal(policy_calls, 1)

        host._item_backend_id = nil
        owner.refresh(host, "weave-skin")
        H.equal(host._ct_glow_editor_widget.content.button_hotspot.disable_button, true)
        H.equal(host._ct_glow_editor_widget.content.button_hotspot.is_selected, false)
    end)
end
