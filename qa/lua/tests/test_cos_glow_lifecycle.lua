return function(H, repo_root)
    local function read(relative_path)
        local file = assert(io.open(repo_root .. "/" .. relative_path, "rb"))
        local source = file:read("*a")
        file:close()
        return source
    end

    local picker = read("cosmetics_tweaker/scripts/mods/cosmetics_tweaker/_glow_picker.lua")
    local entry = read("cosmetics_tweaker/scripts/mods/cosmetics_tweaker/cosmetics_tweaker.lua")
    local instance_policy = read(
        "cosmetics_tweaker/scripts/mods/cosmetics_tweaker/_cos_glow_instance_policy.lua")

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
        H.truthy(entry:find('_rt_register("local_player_safe_network_lifecycle_609"', 1, true))
        H.truthy(entry:find('title state must yield nil', 1, true))
        H.truthy(entry:find('ingame state lost player', 1, true))
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

    H.test("Cosmetics glow replay is host-authoritative and locally bounded", function()
        H.truthy(entry:find('mod:network_register("cos_glow_apply_req"', 1, true))
        H.truthy(entry:find('mod:network_register("cos_glow_apply"', 1, true))
        H.truthy(entry:find('state_pull = "piggyback_cos_la_state_req"', 1, true))
        H.truthy(entry:find("local _COS574_REHYDRATE_MAX_ATTEMPTS = 40", 1, true))
        H.truthy(entry:find("local _COS574_REHYDRATE_WINDOW = 10", 1, true))
        H.truthy(entry:find("retry_network = false", 1, true))
        H.truthy(entry:find("if mod._cos574_glow_rehydrate_tick then mod._cos574_glow_rehydrate_tick() end", 1, true))
    end)

    H.test("Cosmetics glow repaints equipment preview and remote wield surfaces", function()
        H.truthy(entry:find('rehydrate path=create_equipment', 1, true))
        H.truthy(entry:find('rehydrate path=hero_preview', 1, true))
        H.truthy(entry:find('repaint path=husk_wield', 1, true))
        H.truthy(entry:find('_cos574_complete_glow_rehydrate(wearer_peer, "husk_wield"', 1, true))
    end)

    H.test("Cosmetics glow editor and badges are manual Apply-only presentation", function()
        H.equal(entry:find("_glow_auto_popup_for_local", 1, true), nil)
        H.equal(entry:find("[glow_picker:auto] opened on illusion select", 1, true), nil)
        H.equal(entry:find("glow_picker_auto_popup_enabled", 1, true), nil)
        H.truthy(entry:find("_create_glow_editor_button", 1, true))
        H.truthy(entry:find("GlowPicker.toggle_anchor(button_width, 20)", 1, true))
        H.truthy(picker:find("local TOGGLE_Y_NUDGE   = -4", 1, true))
        H.equal(entry:find("offset = { 1272, 380, 20 }", 1, true), nil)
        H.equal(entry:find('has_texture_by_name("cos_glow_badge")', 1, true), nil)
        H.truthy(entry:find('{ pass_type = "rect", style_id = "button" }', 1, true))
        H.truthy(entry:find('{ pass_type = "texture_frame", style_id = "button_frame", texture_id = "button_frame" }', 1, true))
        H.truthy(entry:find("button_frame = GlowPicker.FRAME_TEXTURE", 1, true))
        H.truthy(entry:find("button_frame = GlowPicker.frame_style(button_width, button_height, 3)", 1, true))
        H.truthy(picker:find('GlowPicker.FRAME_TEXTURE = "menu_frame_12"', 1, true))
        H.truthy(picker:find("GlowPicker.FRAME_TEX_SIZE = { 64, 64 }", 1, true))
        H.truthy(picker:find("corner = { 11, 11 }", 1, true))
        H.truthy(picker:find("vertical = { 5, 1 }", 1, true))
        H.truthy(picker:find("horizontal = { 1, 5 }", 1, true))
        H.truthy(picker:find('content = { text = "Apply", frame = GlowPicker.FRAME_TEXTURE, hotspot = {} }', 1, true))
        H.truthy(picker:find('content = { frame = GlowPicker.FRAME_TEXTURE }', 1, true))
        H.truthy(entry:find("GlowPicker.is_open_for(bid, { skin = skin })", 1, true))
        H.truthy(entry:find('mod:hook_safe("ItemGridUI", "init"', 1, true))
        H.truthy(entry:find('mod:hook_safe("ItemGridUI", "_populate_inventory_page"', 1, true))
        H.truthy(entry:find("widget._ct_glow_badge_enriched", 1, true))
        H.truthy(entry:find("GlowPicker.committed_state_for", 1, true))
        H.truthy(entry:find("mod._cos_glow_badges_refresh = function", 1, true))

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
end
