return function(H, repo_root)
    local function read(relative_path)
        local file = assert(io.open(repo_root .. "/" .. relative_path, "rb"))
        local source = file:read("*a")
        file:close()
        return source
    end

    local picker = read("cosmetics_tweaker/scripts/mods/cosmetics_tweaker/_glow_picker.lua")
    local entry = read("cosmetics_tweaker/scripts/mods/cosmetics_tweaker/cosmetics_tweaker.lua")

    H.test("Cosmetics glow persistence is exact-item plus illusion and explicit-Apply", function()
        H.truthy(picker:find('return string.format("backend:%s|skin:%s", tostring(backend_id), tostring(skin or ""))', 1, true))
        H.truthy(picker:find("if not GlowPicker._open or not GlowPicker._dirty then return false end", 1, true))
        H.truthy(picker:find("_save_per_item_glow(all_data)", 1, true))
        H.truthy(picker:find("GlowPicker._dirty = false", 1, true))
        H.truthy(picker:find("if mod._emit_per_item_glow then pcall(mod._emit_per_item_glow) end", 1, true))
    end)

    H.test("Cosmetics glow close rolls preview back to committed state", function()
        H.truthy(picker:find("function GlowPicker.close()", 1, true))
        H.truthy(picker:find("mod._per_item_glow_runtime[backend_id] = GlowPicker._committed_glow_state", 1, true))
        H.truthy(picker:find("and _clone(GlowPicker._committed_glow_state) or nil", 1, true))
        H.truthy(picker:find("pcall(mod._reapply_glow_on_wielded)", 1, true))
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
end
