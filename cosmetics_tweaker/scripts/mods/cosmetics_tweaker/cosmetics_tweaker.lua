local mod = get_mod("cosmetics_tweaker")
local U = mod:dofile("scripts/mods/cosmetics_tweaker/_cosmetic_unlocks")
local LA_BRIDGE = mod:dofile("scripts/mods/cosmetics_tweaker/_la_bridge")

local MOD_VERSION = "0.7.83-dev"
mod:info("Cosmetics Tweaker v%s loaded", MOD_VERSION)
mod:echo("Cosmetics Tweaker v" .. MOD_VERSION)

-- ============================================================
-- Material tinting research (TODO: cloned + recolored cosmetics)
-- ============================================================
-- v1: in-place tint applied to a specific hat key when spawned. Future v2 will
-- register a CLONED ItemMasterList entry so the original hat stays vanilla and
-- the tinted variant is a separate equippable item.

local _is_unit_alive = function(u) return type(u) == "userdata" and pcall(Unit.alive, u) and Unit.alive(u) end

-- Returns true if the given Gui has the named material loaded.
--
-- IMPORTANT: `Gui.material(gui, name)` does NOT throw on missing materials in
-- this VT2 build — it returns nil silently. So pcall alone is NOT a reliable
-- probe; we MUST inspect the return value too. (An earlier version of this
-- function returned `ok` only and silently always reported "true", which made
-- the VMFOptionsView pre-check useless.)
local function _gui_has_material(gui, material_name)
    if not gui or not Gui or not Gui.material then return false end
    local ok, mat = pcall(Gui.material, gui, material_name)
    return ok and mat ~= nil
end

-- DLC ownership gate. Used across the unlock paths to refuse skins whose
-- ItemMasterList entry has `required_dlc` set when the player doesn't own
-- that DLC. Defined early because several hooks below reference it.
local function _skin_requires_unowned_dlc(skin_key)
    local item_data = rawget(ItemMasterList, skin_key)
    if not item_data or not item_data.required_dlc then return false end
    if not Managers.unlock then return false end
    return not Managers.unlock:is_dlc_unlocked(item_data.required_dlc)
end

-- Force-flush the engine console log so command output is on disk before the
-- user navigates anywhere. Stingray buffers writes; menu transitions flush
-- naturally but mid-keep a probe can sit in the buffer for minutes. Try every
-- known channel — whichever works in this VT2 build wins, the rest no-op.
local function _flush_log()
    pcall(function() if io and io.flush then io.flush() end end)
    pcall(function() if Log and Log.flush then Log.flush() end end)
    pcall(function()
        if Application and Application.console_command then
            -- Try several known engine-console flush command names.
            Application.console_command("flush_log")
            Application.console_command("log_flush")
            Application.console_command("flush")
        end
    end)
    mod:info("[flush] %s", tostring(os.time()))  -- nudge the buffer with a final line.
end

mod:command("flush_log", "Force-flush the engine console log to disk", function()
    _flush_log()
    mod:echo("[flush_log] attempted")
end)

-- Dump every weapon skin that has a material_settings_name (a glow template),
-- grouped by template name, with the localized display name. Goal: map in-game
-- names ("Weavebound", "Stylish", "Exotic", etc.) to the underlying glow
-- templates so cosmetics_tweaker can offer per-style toggles/recolors. Output
-- is pipe-delimited under [DUMP:glows] so it's easy to grep out of the log.
mod:command("dump_glows", "Dump glow-tagged weapon skins grouped by material_settings_name", function()
    if not WeaponSkins or not WeaponSkins.skins then
        mod:echo("WeaponSkins not loaded yet")
        return
    end

    local L = rawget(_G, "Localize")
    local function loc(key)
        if not key then return "" end
        if not L then return "(no Localize)" end
        local ok, v = pcall(L, key)
        return (ok and v) or "(loc fail)"
    end

    local buckets = {}
    local total_skins, total_with_glow = 0, 0
    for skin_key, data in pairs(WeaponSkins.skins) do
        total_skins = total_skins + 1
        if type(data) == "table" and data.material_settings_name then
            total_with_glow = total_with_glow + 1
            local tpl = data.material_settings_name
            buckets[tpl] = buckets[tpl] or {}
            table.insert(buckets[tpl], {
                key = skin_key,
                display_name = data.display_name,
                description = data.description,
                rarity = data.rarity,
                icon = data.inventory_icon,
                right = data.right_hand_unit,
                left = data.left_hand_unit,
            })
        end
    end

    mod:info("[DUMP:glows] === %d/%d weapon skins have material_settings_name ===", total_with_glow, total_skins)

    -- Emit RGB values for each template that's actually in use, so the colors
    -- sit right next to the items that use them in the log.
    if MaterialSettingsTemplates then
        mod:info("[DUMP:glows] --- MaterialSettingsTemplates RGB ---")
        for name in pairs(buckets) do
            local tpl = MaterialSettingsTemplates[name]
            if tpl then
                local parts = {}
                for var, d in pairs(tpl) do
                    if d.type == "vector3" then
                        parts[#parts+1] = string.format("%s=(%s,%s,%s)", var, tostring(d.x), tostring(d.y), tostring(d.z))
                    else
                        parts[#parts+1] = string.format("%s[%s]", var, tostring(d.type))
                    end
                end
                mod:info("[DUMP:glows] TEMPLATE|%s|%s", name, table.concat(parts, " "))
            else
                mod:info("[DUMP:glows] TEMPLATE|%s|<missing>", name)
            end
        end
    end

    local tpl_names = {}
    for n in pairs(buckets) do tpl_names[#tpl_names+1] = n end
    table.sort(tpl_names)

    for _, tpl in ipairs(tpl_names) do
        local entries = buckets[tpl]
        table.sort(entries, function(a, b) return a.key < b.key end)
        mod:info("[DUMP:glows] === %s (%d skins) ===", tpl, #entries)
        for _, e in ipairs(entries) do
            mod:info("[DUMP:glows] SKIN|%s|name=%q|desc=%q|rarity=%s|icon=%s|right=%s|left=%s|key=%s",
                tpl,
                tostring(loc(e.display_name)),
                tostring(loc(e.description)),
                tostring(e.rarity),
                tostring(e.icon),
                tostring(e.right),
                tostring(e.left),
                tostring(e.key)
            )
        end
    end

    _flush_log()
    mod:echo("[dump_glows] %d glow skins dumped to log (search [DUMP:glows])", total_with_glow)
end)

-- Dump every weapon skin grouped by rarity, with rarity display labels resolved
-- via Localize, and per-rarity counts of skins with/without material_settings_name.
-- Goal: settle which rarity-tier corresponds to which user-facing label
-- ("Veteran", "Weave-Forged", "Stylish") and find the white_glow item.
-- Per-section _flush_log() avoids the truncation we hit on /dump_glows where
-- ~36 lines were dropped from a 350-line burst.
mod:command("dump_skin_rarities", "Dump WeaponSkins.skins grouped by rarity with localized rarity labels and template stats", function()
    if not WeaponSkins or not WeaponSkins.skins then
        mod:echo("WeaponSkins not loaded yet")
        return
    end

    local L = rawget(_G, "Localize")
    local function loc(key)
        if not key then return "" end
        if not L then return "(no Localize)" end
        local ok, v = pcall(L, key)
        return (ok and v) or "(loc fail)"
    end

    -- 1. Rarity display labels.
    --    Resolve via RaritySettings if available; also probe a few extra keys
    --    that might exist (veteran/weave_forged/stylish/champion) to catch
    --    label variants the user has mentioned.
    mod:info("[DUMP:rarity] === rarity display labels ===")
    local rarity_keys = {}
    if rawget(_G, "RaritySettings") then
        for k, v in pairs(RaritySettings) do
            rarity_keys[k] = v.display_name or ("rarity_display_name_" .. k)
        end
    end
    -- Always probe these too (some are referenced in ORDER_RARITY but not RaritySettings).
    for _, name in ipairs({"plentiful","common","rare","exotic","unique","magic","event","promo","veteran","weave_forged","stylish","champion","loot"}) do
        rarity_keys[name] = rarity_keys[name] or ("rarity_display_name_" .. name)
    end
    for rarity, key in pairs(rarity_keys) do
        mod:info("[DUMP:rarity] LABEL|%s|key=%s|loc=%q", rarity, key, tostring(loc(key)))
    end
    _flush_log()

    -- 2. Bucket every skin by rarity. Count with/without material_settings_name,
    --    and tally which template each rarity uses.
    local by_rarity = {}
    local total = 0
    for skin_key, data in pairs(WeaponSkins.skins) do
        if type(data) == "table" then
            total = total + 1
            local r = data.rarity or "<nil>"
            by_rarity[r] = by_rarity[r] or {
                with_template = 0, without_template = 0,
                templates = {}, samples_with = {}, samples_without = {},
            }
            local b = by_rarity[r]
            local tpl = data.material_settings_name
            if tpl then
                b.with_template = b.with_template + 1
                b.templates[tpl] = (b.templates[tpl] or 0) + 1
                if #b.samples_with < 8 then
                    table.insert(b.samples_with, { key = skin_key, name = loc(data.display_name), tpl = tpl, units = (data.right_hand_unit or data.left_hand_unit or "?") })
                end
            else
                b.without_template = b.without_template + 1
                if #b.samples_without < 8 then
                    table.insert(b.samples_without, { key = skin_key, name = loc(data.display_name), units = (data.right_hand_unit or data.left_hand_unit or "?") })
                end
            end
        end
    end
    local rarity_count = 0
    for _ in pairs(by_rarity) do rarity_count = rarity_count + 1 end
    mod:info("[DUMP:rarity] === %d total weapon skins, %d distinct rarities ===", total, rarity_count)
    _flush_log()

    -- 3. Per-rarity report.
    local rarity_names = {}
    for r in pairs(by_rarity) do rarity_names[#rarity_names+1] = r end
    table.sort(rarity_names)
    for _, r in ipairs(rarity_names) do
        local b = by_rarity[r]
        local tpl_parts = {}
        for t, c in pairs(b.templates) do tpl_parts[#tpl_parts+1] = string.format("%s=%d", t, c) end
        table.sort(tpl_parts)
        mod:info("[DUMP:rarity] === %s | label=%q | total=%d | with_tpl=%d | without_tpl=%d | tpls={%s} ===",
            r, tostring(loc(rarity_keys[r] or ("rarity_display_name_" .. r))),
            b.with_template + b.without_template, b.with_template, b.without_template,
            table.concat(tpl_parts, ", "))
        for _, s in ipairs(b.samples_with) do
            mod:info("[DUMP:rarity] WITH|%s|tpl=%s|name=%q|key=%s|unit=%s", r, s.tpl, tostring(s.name), s.key, tostring(s.units))
        end
        for _, s in ipairs(b.samples_without) do
            mod:info("[DUMP:rarity] WITHOUT|%s|name=%q|key=%s|unit=%s", r, tostring(s.name), s.key, tostring(s.units))
        end
        _flush_log()
    end

    -- 4. Find the white_glow referrer.
    mod:info("[DUMP:rarity] === white_glow referrers (template is NOT registered in MaterialSettingsTemplates) ===")
    local white_count = 0
    for skin_key, data in pairs(WeaponSkins.skins) do
        if type(data) == "table" and data.material_settings_name == "white_glow" then
            white_count = white_count + 1
            mod:info("[DUMP:rarity] WHITE|key=%s|rarity=%s|name=%q|desc=%q|right=%s|left=%s|icon=%s",
                skin_key, tostring(data.rarity), tostring(loc(data.display_name)),
                tostring(loc(data.description)),
                tostring(data.right_hand_unit), tostring(data.left_hand_unit),
                tostring(data.inventory_icon))
        end
    end
    mod:info("[DUMP:rarity] white_glow item count: %d", white_count)
    _flush_log()

    -- 5. _runed_01 vs _runed_02 sibling pairs.
    --    This is what we expect to differentiate "stylish" (no tpl) from
    --    "weave-forged" (purple_glow tpl).
    mod:info("[DUMP:rarity] === _runed_01 vs _runed_02 sibling pairs (max 30) ===")
    local pairs_found = 0
    for skin_key_02, data_02 in pairs(WeaponSkins.skins) do
        if pairs_found < 30 and type(data_02) == "table" and string.find(skin_key_02, "_runed_02$") then
            local skin_key_01 = string.gsub(skin_key_02, "_runed_02$", "_runed_01")
            local data_01 = WeaponSkins.skins[skin_key_01]
            if data_01 then
                pairs_found = pairs_found + 1
                mod:info("[DUMP:rarity] PAIR|01_name=%q|01_tpl=%s|01_rarity=%s|02_name=%q|02_tpl=%s|02_rarity=%s|prefix=%s",
                    tostring(loc(data_01.display_name)), tostring(data_01.material_settings_name), tostring(data_01.rarity),
                    tostring(loc(data_02.display_name)), tostring(data_02.material_settings_name), tostring(data_02.rarity),
                    string.gsub(skin_key_02, "_runed_02$", ""))
            end
        end
    end
    mod:info("[DUMP:rarity] sibling pairs sampled: %d", pairs_found)

    _flush_log()
    mod:echo("[dump_skin_rarities] %d skins across %d rarities dumped (search [DUMP:rarity])", total, rarity_count)
end)

-- Diagnostic: probe whether vmf_atlas is loaded on the active screen Guis.
-- Use this BEFORE opening VMF options view to verify the material check
-- works. If vmf_atlas reports "missing" here, opening options will crash.
-- Output goes to BOTH chat (mod:echo) and log file (mod:info), then flushes.
mod:command("check_vmf", "Check vmf_atlas presence on active Guis", function()
    local function emit(fmt, ...)
        mod:echo(fmt, ...)
        mod:info("[check_vmf] " .. fmt, ...)
    end

    local function probe(name, gui)
        if not gui then emit("  %s: nil", name); return end
        local ok, mat = pcall(Gui.material, gui, "vmf_atlas")
        emit("  %s: ok=%s mat=%s", name, tostring(ok), tostring(mat))
    end

    emit("=== check_vmf ===")
    local found = false
    for _, mgr_name in ipairs({"ui", "matchmaking", "transition"}) do
        local mgr = Managers[mgr_name]
        for _, field in ipairs({"ui_renderer", "_ui_renderer", "renderer"}) do
            if mgr and mgr[field] then
                found = true
                local r = mgr[field]
                emit("Managers.%s.%s:", mgr_name, field)
                probe("gui_immediate", r.gui)
                probe("gui_retained",  r.gui_retained)
            end
        end
    end
    if not found then emit("no UI renderer found via Managers") end
    _flush_log()
end)

-- Tint config: which hats to tint, and to what color. Toggle-gated.
-- The tint multiplies the material's albedo input — names vary per shader, so
-- we try a list of common parameter names and silently skip ones that don't exist.
local _TINT_PARAM_NAMES = {
    "tint_color", "tint_color_a", "color_tint", "color", "albedo_color",
    "diffuse_color", "base_color_tint", "main_color",
}
-- key: item_key, value: { rgb = {r, g, b}, setting = "<vmf checkbox>" }
local _hat_tints = {
    questing_knight_hat_0001 = {
        rgb     = { 1.0, 1.0, 1.0 },                 -- white (matches purified Chaos Wastes outfit)
        setting = "tint_pureheart_white",
    },
}

local function _apply_tint_to_unit(unit, rgb)
    if not _is_unit_alive(unit) then return end
    local n_mats = 0
    do local ok, n = pcall(Unit.num_materials, unit); if ok and n then n_mats = n end end
    local color = Color and Color(255, math.floor(rgb[1]*255), math.floor(rgb[2]*255), math.floor(rgb[3]*255)) or nil
    local v3 = Vector3 and Vector3(rgb[1], rgb[2], rgb[3]) or nil

    local function try_set(material)
        if not material then return end
        for _, pname in ipairs(_TINT_PARAM_NAMES) do
            -- Try set_color (Color) and set_vector3 (Vector3); ignore failures.
            if color  then pcall(Material.set_color,   material, pname, color) end
            if v3     then pcall(Material.set_vector3, material, pname, v3)    end
            -- Some shaders use set_scalar for an alpha/value channel (uncommon).
        end
    end

    -- Iterate every material slot on the unit.
    for i = 0, n_mats - 1 do
        local ok, mat = pcall(Unit.material, unit, i)
        if ok then try_set(mat) end
    end
    -- Fallback: some hats have a single named material slot ("default").
    for _, slot in ipairs({ "default", "main", "primary" }) do
        local ok, mat = pcall(Unit.material, unit, slot)
        if ok then try_set(mat) end
    end
end

local function _maybe_tint(item_key, unit)
    if not item_key then return end
    local cfg = _hat_tints[item_key]
    if not cfg or not mod:get(cfg.setting) then return end
    _apply_tint_to_unit(unit, cfg.rgb)
end

-- Probe: deep-walk attachment_system._attachments and inventory_system._equipment.slots.slot_hat.
mod:command("probe_hat", "Dump materials of player's equipped hat", function()
    mod:echo("[probe_hat] starting")
    mod:info("[probe_hat] starting")
    local pm = Managers.player; local p = pm and pm:local_player()
    local pu = p and p.player_unit
    if not pu then mod:echo("[probe_hat] no player_unit"); return end

    local function dump_unit_materials(prefix, unit)
        -- Try every Stingray API path we know to enumerate materials. Whichever
        -- works in this build is what we use for tinting.
        mod:info("%s probing Unit/Mesh APIs:", prefix)

        local ok_n, n_meshes = pcall(Unit.num_meshes, unit)
        mod:info("%s   Unit.num_meshes -> %s", prefix, tostring(ok_n and n_meshes or "err"))
        if ok_n and type(n_meshes) == "number" then
            for i = 0, n_meshes - 1 do
                local ok_m, mesh = pcall(Unit.mesh, unit, i)
                mod:info("%s   Unit.mesh(%d) -> %s", prefix, i, tostring(ok_m and mesh or "err"))
                if ok_m and mesh and Mesh then
                    local ok_nm, n_mats = pcall(Mesh.num_materials, mesh)
                    mod:info("%s     Mesh.num_materials -> %s", prefix, tostring(ok_nm and n_mats or "err"))
                    if ok_nm and type(n_mats) == "number" then
                        for j = 0, n_mats - 1 do
                            local ok_mat, mat = pcall(Mesh.material, mesh, j)
                            mod:info("%s     Mesh.material(%d) -> %s", prefix, j, tostring(ok_mat and mat or "err"))
                            if ok_mat and mat and Material then
                                -- DO NOT call Material.num_parameters / parameter_name /
                                -- parameter_type here — they trigger a Stingray
                                -- resource_manager.cpp:245 fault that's not pcall-recoverable
                                -- and crashes the game. Brute-force param names instead.
                                for _, pname in ipairs({
                                    "tint_color", "color_tint", "albedo_color", "color",
                                    "diffuse_color", "main_color", "tint_color_a", "base_color_tint",
                                    "albedo", "_albedo", "_color", "_tint", "tint", "tint_a", "tint_b", "tint_c",
                                    "color_variation_mask", "pattern_color_a", "pattern_color_b", "pattern_color_c",
                                    "skin_color", "primary_color", "secondary_color", "outfit_color",
                                    "metallic_value", "emissive", "emissive_color", "team_color_a",
                                    "fresnel_color", "rim_color", "metalness_color",
                                }) do
                                    local r, v = pcall(Material.get_color, mat, pname)
                                    if r and v then mod:info("%s         %s.color=%s", prefix, pname, tostring(v)) end
                                    local r2, v2 = pcall(Material.get_vector3, mat, pname)
                                    if r2 and v2 then mod:info("%s         %s.v3=%s", prefix, pname, tostring(v2)) end
                                end
                            end
                        end
                    end
                end
            end
        end

        -- Other Unit-level color APIs (test call & report).
        for _, fn_name in ipairs({ "num_actors", "num_scene_graph_items" }) do
            local ok, v = pcall(Unit[fn_name], unit)
            mod:info("%s   Unit.%s -> %s", prefix, fn_name, tostring(ok and v or "err"))
        end

        -- Try Unit.set_color and Unit.set_unit_setting as a probe — does it error?
        if Unit.set_color then
            local ok = pcall(Unit.set_color, unit, Color and Color(255,255,255,255) or 0xFFFFFFFF)
            mod:info("%s   Unit.set_color exists, call ok=%s", prefix, tostring(ok))
        else
            mod:info("%s   Unit.set_color does not exist", prefix)
        end
        if Unit.flow_event then
            mod:info("%s   Unit.flow_event exists (try with set_color event in tint code)", prefix)
        end
    end

    local function dump_table(prefix, tbl, depth)
        if depth <= 0 or type(tbl) ~= "table" then return end
        for k, v in pairs(tbl) do
            local key = prefix .. "." .. tostring(k)
            if _is_unit_alive(v) then
                mod:info("%s = (UNIT)", key)
                dump_unit_materials(key .. "  ", v)
            elseif type(v) == "table" then
                mod:info("%s (table)", key)
                dump_table(key, v, depth - 1)
            end
        end
    end

    -- attachment_system: walk _attachments deeply.
    local ok_at = ScriptUnit.has_extension and ScriptUnit.has_extension(pu, "attachment_system")
    if ok_at then
        local ext = ScriptUnit.extension(pu, "attachment_system")
        if ext and ext._attachments then
            mod:info("[probe_hat] attachment_system._attachments:")
            dump_table("[probe_hat]   _attachments", ext._attachments, 4)
        end
    end

    -- inventory_system: walk _equipment.slots.slot_hat deeply.
    local ok_inv = ScriptUnit.has_extension and ScriptUnit.has_extension(pu, "inventory_system")
    if ok_inv then
        local ext = ScriptUnit.extension(pu, "inventory_system")
        local slots = ext and ext._equipment and ext._equipment.slots
        if slots then
            for sname, sdata in pairs(slots) do
                if sname:find("hat") or sname == "slot_hat" then
                    mod:info("[probe_hat] inventory.slots.%s:", sname)
                    dump_table("[probe_hat]   " .. sname, sdata, 3)
                end
            end
        end
        if ext and ext._attached_units then
            mod:info("[probe_hat] inventory._attached_units:")
            dump_table("[probe_hat]   _attached_units", ext._attached_units, 3)
        end
    end

    mod:echo("[probe_hat] done")
    _flush_log()
end)

-- ============================================================
-- Dynamic Character Portraits (hat-dependent)
-- ============================================================

-- Custom portrait textures: each portrait size has its own .material file so
-- that Stingray creates a Gui material whose name matches the texture name
-- (file-based naming). No UIAtlasHelper hooks needed — standalone textures
-- bypass atlas lookup and the UI uses Gui.bitmap with the material name.

local _PORTRAIT_MATERIALS = {
    "materials/ui/portrait_kruber_mercenary_hat_0004",
    "materials/ui/medium_portrait_kruber_mercenary_hat_0004",
    "materials/ui/small_portrait_kruber_mercenary_hat_0004",
    "materials/ui/portrait_kruber_mercenary_hat_0009",
    "materials/ui/medium_portrait_kruber_mercenary_hat_0009",
    "materials/ui/small_portrait_kruber_mercenary_hat_0009",
    "materials/ui/portrait_kruber_mercenary_hat_1001",
    "materials/ui/medium_portrait_kruber_mercenary_hat_1001",
    "materials/ui/small_portrait_kruber_mercenary_hat_1001",
    "materials/ui/portrait_kruber_mercenary_hat_1002",
    "materials/ui/medium_portrait_kruber_mercenary_hat_1002",
    "materials/ui/small_portrait_kruber_mercenary_hat_1002",
    "materials/ui/portrait_kruber_mercenary_hat_1003",
    "materials/ui/medium_portrait_kruber_mercenary_hat_1003",
    "materials/ui/small_portrait_kruber_mercenary_hat_1003",
    "materials/ui/portrait_kruber_mercenary_hat_0006",
    "materials/ui/medium_portrait_kruber_mercenary_hat_0006",
    "materials/ui/small_portrait_kruber_mercenary_hat_0006",
    "materials/ui/portrait_kruber_mercenary_hat_0007",
    "materials/ui/medium_portrait_kruber_mercenary_hat_0007",
    "materials/ui/small_portrait_kruber_mercenary_hat_0007",
}

local _hat_portrait_map = {
    mercenary_hat_0004 = {
        hud    = "portrait_kruber_mercenary_hat_0004",
        medium = "medium_portrait_kruber_mercenary_hat_0004",
        small  = "small_portrait_kruber_mercenary_hat_0004",
    },
    mercenary_hat_0006 = {
        hud    = "portrait_kruber_mercenary_hat_0006",
        medium = "medium_portrait_kruber_mercenary_hat_0006",
        small  = "small_portrait_kruber_mercenary_hat_0006",
    },
    mercenary_hat_0007 = {
        hud    = "portrait_kruber_mercenary_hat_0007",
        medium = "medium_portrait_kruber_mercenary_hat_0007",
        small  = "small_portrait_kruber_mercenary_hat_0007",
    },
    mercenary_hat_0009 = {
        hud    = "portrait_kruber_mercenary_hat_0009",
        medium = "medium_portrait_kruber_mercenary_hat_0009",
        small  = "small_portrait_kruber_mercenary_hat_0009",
    },
    mercenary_hat_1001 = {
        hud    = "portrait_kruber_mercenary_hat_1001",
        medium = "medium_portrait_kruber_mercenary_hat_1001",
        small  = "small_portrait_kruber_mercenary_hat_1001",
    },
    mercenary_hat_1002 = {
        hud    = "portrait_kruber_mercenary_hat_1002",
        medium = "medium_portrait_kruber_mercenary_hat_1002",
        small  = "small_portrait_kruber_mercenary_hat_1002",
    },
    mercenary_hat_1003 = {
        hud    = "portrait_kruber_mercenary_hat_1003",
        medium = "medium_portrait_kruber_mercenary_hat_1003",
        small  = "small_portrait_kruber_mercenary_hat_1003",
    },
}

local _skin_portrait_map = {}

local _portrait_materials_ready = false
local _portrait_settings_active = false
local _original_portrait_image = nil
local _original_picking_image = nil
local _last_known_hat_key = nil
local _last_known_skin_key = nil

-- ============================================================
-- Hot-reload / missing-material safety net
-- ============================================================
-- When a mod's atlas isn't on the active Gui (LA reload, VMF options view
-- with vmf_atlas not injected, etc.), the next draw fatals the engine with
-- "Material 'X' not found in Gui". ui_passes.lua captures
-- UIRenderer.draw_texture as a file-local at load time so we can't intercept
-- there. But UIRenderer.draw_widget is called via the global table from many
-- callers (vmf_options_view, NewsFeedUI per-widget, etc.) — hooking it
-- catches the most common surfaces.
-- VMFOptionsView safety hook removed: Gui.material() does not reliably detect
-- materials loaded via VMF's resource packages, so the pre-check was blocking
-- the VMF options menu from rendering entirely. VMF handles its own draw
-- lifecycle — cosmetics_tweaker should not guard it.

local _hot_reload_purges = 0
-- Replace the original draw entirely (mod:hook_origin) so we control the pass
-- lifecycle. Per-widget pcall lets us skip a stale widget without leaving
-- begin_pass/end_pass unbalanced (which crashed world_marker_ui post_update).
-- ALSO purge any active_news entries whose widget references a missing
-- material BEFORE begin_pass — pcall'ing draw_widget AFTER begin_pass still
-- works (the renderer pcall scope is per-widget, end_pass always runs), but
-- a pre-check is cheaper and avoids per-frame log spam.
mod:hook_origin("NewsFeedUI", "draw", function(self, dt)
    local ui_renderer    = self.ui_renderer
    local ui_scenegraph  = self.ui_scenegraph
    local input_service  = self.input_manager:get_service("ingame_menu")

    UIRenderer.begin_pass(ui_renderer, ui_scenegraph, input_service, dt)

    local active_news = self._active_news
    local stale_indices
    for i = 1, #active_news do
        local widget = active_news[i].widget
        if widget then
            local ok, err = pcall(UIRenderer.draw_widget, ui_renderer, widget)
            if not ok then
                stale_indices = stale_indices or {}
                stale_indices[#stale_indices + 1] = i
                if _hot_reload_purges < 5 then
                    mod:info("[hot-reload-safety] news widget %d draw failed: %s", i, tostring(err))
                end
            end
        end
    end

    UIRenderer.end_pass(ui_renderer)

    -- Purge dead widgets after the pass closes. Iterate descending so indices stay valid.
    if stale_indices then
        for j = #stale_indices, 1, -1 do
            local i = stale_indices[j]
            local data = active_news[i]
            local widget = data and data.widget
            table.remove(active_news, i)
            if widget and self._unused_news_widgets then
                table.insert(self._unused_news_widgets, widget)
            end
        end
        _hot_reload_purges = _hot_reload_purges + #stale_indices
    end
end)

-- Collect ALL gui handles from every UIRenderer we can find.
local function _collect_all_guis()
    local guis = {}
    local function add(label, renderer)
        if not renderer then return end
        for _, gf in ipairs({"gui", "gui_retained"}) do
            if renderer[gf] then
                guis[#guis + 1] = { label = label .. "." .. gf, gui = renderer[gf] }
            end
        end
    end
    for _, mgr_name in ipairs({"ui", "matchmaking", "transition"}) do
        local mgr = Managers[mgr_name]
        if mgr then
            for _, field in ipairs({"ui_renderer", "_ui_renderer", "renderer"}) do
                if mgr[field] then add("Managers." .. mgr_name .. "." .. field, mgr[field]) end
            end
        end
    end
    local ingame_ui = Managers.ui and Managers.ui._ingame_ui
    if ingame_ui then
        for _, field in ipairs({"ui_renderer", "_ui_renderer"}) do
            if ingame_ui[field] then add("ingame_ui." .. field, ingame_ui[field]) end
        end
    end
    local hud = ingame_ui and ingame_ui._hud
    if hud then
        for _, field in ipairs({"ui_renderer", "_ui_renderer"}) do
            if hud[field] then add("hud." .. field, hud[field]) end
        end
    end
    local unit_frames = hud and (hud._unit_frames_handler or hud.unit_frames_handler)
    if unit_frames then
        for _, field in ipairs({"ui_renderer", "_ui_renderer"}) do
            if unit_frames[field] then add("unit_frames." .. field, unit_frames[field]) end
        end
    end
    return guis
end

local function _check_portrait_materials_ready()
    if _portrait_materials_ready then return true end
    local guis = _collect_all_guis()
    for _, entry in ipairs(guis) do
        if _gui_has_material(entry.gui, "portrait_kruber_mercenary_hat_1002") then
            _portrait_materials_ready = true
            mod:info("[portrait] materials confirmed on %s", entry.label)
            return true
        end
    end
    return false
end

local function _get_hat_item_key_for_unit(player_unit)
    if not player_unit then return nil end
    local pm = Managers.player
    if not pm then return nil end
    for _, player in pairs(pm:players()) do
        if player.player_unit == player_unit then
            if CosmeticUtils and CosmeticUtils.get_cosmetic_slot then
                local hat_data = CosmeticUtils.get_cosmetic_slot(player, "slot_hat")
                if hat_data and hat_data.item_name then
                    return hat_data.item_name
                end
            end
            break
        end
    end
    return nil
end

local function _get_kruber_merc_hat_key()
    local pm = Managers.player
    if not pm then return _last_known_hat_key end

    if CosmeticUtils and CosmeticUtils.get_cosmetic_slot then
        for _, player in pairs(pm:players()) do
            local career_name = nil
            pcall(function() career_name = player:career_name() end)
            if not career_name then pcall(function() career_name = player.career_name end) end
            if career_name == "es_mercenary" then
                local ok, hat_data = pcall(CosmeticUtils.get_cosmetic_slot, player, "slot_hat")
                if ok and hat_data and hat_data.item_name then
                    _last_known_hat_key = hat_data.item_name
                    return hat_data.item_name
                end
            end
        end
    end

    if BackendUtils and BackendUtils.get_loadout_item then
        local ok, item = pcall(BackendUtils.get_loadout_item, "es_mercenary", "slot_hat")
        if ok and item then
            local key = item.key or (item.data and item.data.key)
            if key then
                _last_known_hat_key = key
                return key
            end
        end
    end

    return _last_known_hat_key
end

local function _get_kruber_merc_skin_key()
    local pm = Managers.player
    if not pm then return _last_known_skin_key end

    if CosmeticUtils and CosmeticUtils.get_cosmetic_slot then
        for _, player in pairs(pm:players()) do
            local career_name = nil
            pcall(function() career_name = player:career_name() end)
            if not career_name then pcall(function() career_name = player.career_name end) end
            if career_name == "es_mercenary" then
                local ok, skin_data = pcall(CosmeticUtils.get_cosmetic_slot, player, "slot_skin")
                if ok and skin_data and skin_data.item_name then
                    _last_known_skin_key = skin_data.item_name
                    return skin_data.item_name
                end
            end
        end
    end

    if BackendUtils and BackendUtils.get_loadout_item then
        local ok, item = pcall(BackendUtils.get_loadout_item, "es_mercenary", "slot_skin")
        if ok and item then
            local key = item.key or (item.data and item.data.key)
            if key then
                _last_known_skin_key = key
                return key
            end
        end
    end

    return _last_known_skin_key
end

local function _restore_portrait_settings()
    if not _portrait_settings_active then return end
    if not SPProfiles then return end
    local career = SPProfiles[5] and SPProfiles[5].careers and SPProfiles[5].careers[1]
    if career and _original_portrait_image then
        career.portrait_image = _original_portrait_image
        career.picking_image = _original_picking_image
        _portrait_settings_active = false
        mod:info("[portrait] restored career_settings to '%s'", _original_portrait_image)
    end
end

local function _sync_portrait_settings()
    if not SPProfiles then return end
    local career = SPProfiles[5] and SPProfiles[5].careers and SPProfiles[5].careers[1]
    if not career then return end

    if not _original_portrait_image then
        _original_portrait_image = career.portrait_image
        _original_picking_image = career.picking_image
    end

    if not mod:get("dynamic_portraits") then
        _restore_portrait_settings()
        return
    end

    if not _check_portrait_materials_ready() then return end

    local hat_key = _get_kruber_merc_hat_key()
    local portraits = hat_key and _hat_portrait_map[hat_key]
    if not portraits then
        local skin_key = _get_kruber_merc_skin_key()
        portraits = skin_key and _skin_portrait_map[skin_key]
    end
    if portraits then
        career.portrait_image = portraits.hud
        career.picking_image = portraits.medium
        if not _portrait_settings_active then
            mod:info("[portrait] swapped career_settings to '%s'", portraits.hud)
        end
        _portrait_settings_active = true
    else
        _restore_portrait_settings()
    end
end

-- Diagnostic: check if VMF registered our custom portrait textures
mod:command("portrait_diag", "Diagnose portrait texture registration + hat state", function()
    local function emit(fmt, ...)
        mod:echo(fmt, ...)
        mod:info("[portrait_diag] " .. fmt, ...)
    end

    local ready = _check_portrait_materials_ready()
    emit("settings_active=%s dynamic_portraits=%s materials_ready=%s",
        tostring(_portrait_settings_active), tostring(mod:get("dynamic_portraits")),
        tostring(ready))
    local career = SPProfiles and SPProfiles[5] and SPProfiles[5].careers and SPProfiles[5].careers[1]
    if career then
        emit("career_settings.portrait_image='%s' picking_image='%s'",
            tostring(career.portrait_image), tostring(career.picking_image))
    end

    -- Check UIAtlasHelper — use the CORRECT VMF-hooked function names
    local tex_names = {
        "portrait_kruber_mercenary_hat_1002",
        "medium_portrait_kruber_mercenary_hat_1002",
        "small_portrait_kruber_mercenary_hat_1002",
    }
    if UIAtlasHelper then
        emit("UIAtlasHelper functions: has_atlas=%s get_atlas=%s has_tex=%s",
            tostring(UIAtlasHelper.has_atlas_settings_by_texture_name ~= nil),
            tostring(UIAtlasHelper.get_atlas_settings_by_texture_name ~= nil),
            tostring(UIAtlasHelper.has_texture_by_name ~= nil))
        for _, tex_name in ipairs(tex_names) do
            local has_atlas = false
            if UIAtlasHelper.has_atlas_settings_by_texture_name then
                local ok, val = pcall(UIAtlasHelper.has_atlas_settings_by_texture_name, tex_name)
                has_atlas = ok and val
            end
            local get_result = "nil"
            if UIAtlasHelper.get_atlas_settings_by_texture_name then
                local ok, val = pcall(UIAtlasHelper.get_atlas_settings_by_texture_name, tex_name)
                if ok then get_result = tostring(val) end
            end
            emit("  '%s': has_atlas=%s get_atlas=%s", tex_name, tostring(has_atlas), get_result)
        end
    else
        emit("UIAtlasHelper not available")
    end

    -- Hat detection
    local hat_key = _get_kruber_merc_hat_key()
    emit("local hat key: %s", tostring(hat_key))

    -- Material probe: check if our individual portrait materials are on active GUIs
    local material_probes = {
        "portrait_kruber_mercenary_hat_1002",
        "medium_portrait_kruber_mercenary_hat_1002",
        "small_portrait_kruber_mercenary_hat_1002",
    }
    local guis = _collect_all_guis()
    emit("found %d gui handles", #guis)
    for _, entry in ipairs(guis) do
        for _, mat_name in ipairs(material_probes) do
            local ok, mat = pcall(Gui.material, entry.gui, mat_name)
            if ok and mat then
                emit("FOUND: %s has '%s' -> %s", entry.label, mat_name, tostring(mat))
            end
        end
    end

    -- Check VMF's UIRenderer injection table
    if UIRenderer and UIRenderer._injected_material_sets then
        emit("_injected_material_sets count: %d", #UIRenderer._injected_material_sets)
        for i, v in ipairs(UIRenderer._injected_material_sets) do
            emit("  [%d] = %s", i, tostring(v))
        end
    else
        emit("UIRenderer._injected_material_sets: %s", tostring(UIRenderer and UIRenderer._injected_material_sets))
    end

    _flush_log()
end)

-- Deep dump of ALL portrait widgets across every UI surface.
-- Run this in the keep, during hero selection, and at end-of-round to map
-- all portrait locations, their content keys, pass types, and mask fields.
mod:command("portrait_dump", "Dump ALL portrait widgets from every UI surface", function()
    local function emit(fmt, ...)
        mod:echo(fmt, ...)
        mod:info("[portrait_dump] " .. fmt, ...)
    end

    local MASK_FIELDS = {
        "masked", "texture_mask", "mask_texture", "alpha_mask",
        "circular_mask", "use_mask", "mask", "mask_alpha",
    }

    local function dump_widget(source_label, wname, widget)
        emit("=== %s / %s ===", source_label, tostring(wname))
        if widget.content then
            local port = widget.content.character_portrait or widget.content.portrait
            emit("  portrait: %s", tostring(port))
            local ckeys = {}
            for k, v in pairs(widget.content) do
                ckeys[#ckeys + 1] = tostring(k) .. "=" .. tostring(v)
            end
            table.sort(ckeys)
            for _, s in ipairs(ckeys) do emit("  c: %s", s) end
        end
        if widget.style then
            for sk, sv in pairs(widget.style) do
                if type(sv) == "table" then
                    local extras = {}
                    for _, tf in ipairs({"texture_id", "texture", "texture_name", "material_name"}) do
                        if sv[tf] then extras[#extras + 1] = tf .. "=" .. tostring(sv[tf]) end
                    end
                    for _, mf in ipairs(MASK_FIELDS) do
                        if sv[mf] ~= nil then extras[#extras + 1] = mf .. "=" .. tostring(sv[mf]) end
                    end
                    if sv.texture_size then
                        extras[#extras + 1] = "size=" .. tostring(sv.texture_size[1]) .. "x" .. tostring(sv.texture_size[2])
                    end
                    if #extras > 0 then emit("  s.%s: %s", tostring(sk), table.concat(extras, ", ")) end
                end
            end
        end
        local element = widget.element
        if element then
            local passes = element.passes or element.pass_data
            if passes and type(passes) == "table" then
                emit("  passes (%d):", #passes)
                for pi, pass in ipairs(passes) do
                    local pkeys = {}
                    for k, v in pairs(pass) do
                        pkeys[#pkeys + 1] = tostring(k) .. "=" .. tostring(v)
                    end
                    table.sort(pkeys)
                    emit("    [%d] %s", pi, table.concat(pkeys, ", "))
                end
            end
        end
    end

    local function scan_widgets(source_label, widgets)
        if not widgets or type(widgets) ~= "table" then return 0 end
        local found = 0
        for wname, widget in pairs(widgets) do
            if type(widget) == "table" and widget.content then
                if widget.content.character_portrait or widget.content.portrait then
                    dump_widget(source_label, wname, widget)
                    found = found + 1
                end
            end
        end
        return found
    end

    local found = 0
    local ingame_ui = Managers.ui and Managers.ui._ingame_ui
    local hud = ingame_ui and ingame_ui._hud

    -- 1. HUD unit frames
    local uf_handler = hud and (hud._unit_frames_handler or hud.unit_frames_handler)
    if uf_handler then
        local frames = uf_handler._unit_frames or uf_handler.unit_frames
        if frames then
            for i, frame in ipairs(frames) do
                if frame then
                    for _, wf in ipairs({"_widgets", "widgets", "_default_widgets", "_portrait_widgets"}) do
                        found = found + scan_widgets("hud.frame[" .. i .. "]." .. wf, frame[wf])
                    end
                end
            end
        end
    else
        emit("unit_frames_handler: NOT FOUND")
    end

    -- 2. Hero view (if open)
    local hero_view = ingame_ui and (ingame_ui._hero_view or ingame_ui.hero_view)
    if hero_view then
        emit("-- hero_view found --")
        for _, wf in ipairs({"_widgets", "widgets", "_static_widgets"}) do
            local ok_w, widgets = pcall(function() return hero_view[wf] end)
            if ok_w and widgets then
                found = found + scan_widgets("hero_view." .. wf, widgets)
            end
        end
        local ok_wins, windows = pcall(function() return hero_view._windows or hero_view.windows end)
        if ok_wins and windows then
            for wkey, window in pairs(windows) do
                if type(window) == "table" then
                    for _, wf in ipairs({"_widgets", "widgets", "_static_widgets"}) do
                        local ok_w, widgets = pcall(function() return window[wf] end)
                        if ok_w and widgets then
                            found = found + scan_widgets("hero_view.win[" .. tostring(wkey) .. "]." .. wf, widgets)
                        end
                    end
                end
            end
        end
    else
        emit("hero_view: not active")
    end

    -- 3. End-of-round views
    for _, vname in ipairs({"_end_screen_view", "end_screen_view", "_game_over_view"}) do
        local ok_v, view = pcall(function() return ingame_ui and ingame_ui[vname] end)
        if ok_v and view then
            emit("-- %s found --", vname)
            for _, wf in ipairs({"_widgets", "widgets", "_static_widgets", "_player_widgets"}) do
                local ok_w, widgets = pcall(function() return view[wf] end)
                if ok_w and widgets then
                    found = found + scan_widgets(vname .. "." .. wf, widgets)
                end
            end
        end
    end

    -- 4. Brute-force: walk all ingame_ui fields for portrait widgets
    -- pcall each access because some fields are strict tables that error on unknown keys
    if ingame_ui then
        emit("-- brute-force ingame_ui scan --")
        for field_name, field_val in pairs(ingame_ui) do
            if type(field_val) == "table" and field_name ~= "_hud" then
                for _, wf in ipairs({"_widgets", "widgets", "_static_widgets", "_player_widgets"}) do
                    local ok, widgets = pcall(function() return field_val[wf] end)
                    if ok and widgets then
                        local n = scan_widgets("ingame_ui." .. tostring(field_name) .. "." .. wf, widgets)
                        found = found + n
                    end
                end
            end
        end
    end

    -- 5. HUD sub-elements
    if hud then
        local elements = hud._hud_elements or hud.hud_elements or hud._elements
        if elements and type(elements) == "table" then
            for ek, el in pairs(elements) do
                if type(el) == "table" then
                    for _, wf in ipairs({"_widgets", "widgets", "_static_widgets"}) do
                        local ok_w, widgets = pcall(function() return el[wf] end)
                        if ok_w and widgets then
                            found = found + scan_widgets("hud.el[" .. tostring(ek) .. "]." .. wf, widgets)
                        end
                    end
                end
            end
        end
    end

    emit("=== portrait_dump complete: %d portrait widgets found ===", found)
    _flush_log()
end)

-- Manual test: force career_settings swap and report state
mod:command("test_portrait", "Force portrait career_settings swap", function()
    _sync_portrait_settings()
    local career = SPProfiles and SPProfiles[5] and SPProfiles[5].careers and SPProfiles[5].careers[1]
    mod:echo("[test_portrait] active=%s portrait_image='%s'",
        tostring(_portrait_settings_active),
        career and tostring(career.portrait_image) or "nil")
    _flush_log()
end)

-- Sync portrait career_settings on each UnitFrameUI draw so the swap
-- activates as soon as materials are ready and hat is detected. Once
-- _portrait_settings_active is true, this is a cheap no-op.
mod:hook_safe("UnitFrameUI", "draw", function(self, dt)
    _sync_portrait_settings()
end)

-- ============================================================
-- Cosmetic unlocks (per-career within character)
-- ============================================================
-- Mirrors weapon_tweaker's apply_weapon_unlocks: strips mod-managed careers
-- from each item's `can_wield`, then re-adds only the careers whose toggle is
-- on. Items in U.map are exclusively cross-career-within-character (probe
-- excluded vs_* / wh_priest-only / cross-character entries).

local _CHARACTER_CAREERS = {
    kruber    = { "es_mercenary", "es_huntsman", "es_knight", "es_questingknight" },
    bardin    = { "dr_ranger", "dr_ironbreaker", "dr_slayer", "dr_engineer" },
    saltzpyre = { "wh_captain", "wh_bountyhunter", "wh_zealot" },  -- wh_priest excluded
    elf       = { "we_waywatcher", "we_maidenguard", "we_shade", "we_thornsister" },
    sienna    = { "bw_adept", "bw_scholar", "bw_unchained", "bw_necromancer" },
}

local function apply_cosmetic_unlocks()
    if not ItemMasterList then return end

    for item_key, info in pairs(U.managed) do
        local item = ItemMasterList[item_key]
        if item then
            item.can_wield = item.can_wield or {}
            -- Build the set of careers this item should have, derived from toggles.
            local desired = {}
            for _, career in ipairs(_CHARACTER_CAREERS[info.character] or {}) do
                if mod:get("cos_unlock_" .. career .. "_" .. item_key) then
                    desired[career] = true
                end
            end
            -- Strip all of this character's careers from can_wield, then re-add
            -- only the desired ones. Other characters' careers (e.g. wh_priest
            -- on a Saltzpyre item) are left untouched.
            local char_careers = {}
            for _, c in ipairs(_CHARACTER_CAREERS[info.character] or {}) do
                char_careers[c] = true
            end
            for i = #item.can_wield, 1, -1 do
                if char_careers[item.can_wield[i]] then
                    table.remove(item.can_wield, i)
                end
            end
            for career in pairs(desired) do
                item.can_wield[#item.can_wield + 1] = career
            end
        end
    end
end

mod.on_game_state_changed = function()
    apply_cosmetic_unlocks()
    _sync_portrait_settings()
end
mod.on_setting_changed = function(setting_id)
    if setting_id and setting_id:sub(1, 11) == "cos_unlock_" then
        apply_cosmetic_unlocks()
    end
    if setting_id == "dynamic_portraits" then
        _sync_portrait_settings()
    end
end
mod.on_unload = function()
    _restore_portrait_settings()
    mod:info("[unload] cosmetics_tweaker unloading")
end

-- ============================================================
-- Probe: dump cosmetic items grouped by character/career.
-- Run once via `cos probe_cosmetics` in chat, exit to keep so the log flushes,
-- then send the [PROBE] log lines so the per-career unlock map can be built.
-- ============================================================
mod:command("probe_cosmetics", "Dump all hat/skin items by character + career to the log", function()
    if not ItemMasterList then mod:echo("ItemMasterList not loaded yet"); return end
    local hats, skins, other_slots, sample = {}, {}, {}, nil
    for key, item in pairs(ItemMasterList) do
        if type(item) == "table" then
            local st = item.slot_type
            if st == "hat" then hats[#hats+1] = { key = key, item = item }
            elseif st == "skin" then skins[#skins+1] = { key = key, item = item }
            elseif st and st ~= "melee" and st ~= "ranged" and st ~= "frame" and st ~= "necklace" and st ~= "ring" and st ~= "trinket" then
                other_slots[st] = (other_slots[st] or 0) + 1
            end
            if not sample and st == "hat" then sample = item end
        end
    end
    mod:info("[PROBE] %d hats, %d skins, other slot_types: %s", #hats, #skins, (function()
        local parts = {}
        for k, v in pairs(other_slots) do parts[#parts+1] = k .. "=" .. v end
        return table.concat(parts, ", ")
    end)())

    if sample then
        mod:info("[PROBE] sample hat fields:")
        for k, v in pairs(sample) do
            local t = type(v)
            if t == "string" or t == "number" or t == "boolean" then
                mod:info("[PROBE]   .%s = %s", tostring(k), tostring(v))
            else
                mod:info("[PROBE]   .%s (%s)", tostring(k), t)
            end
        end
    end

    local function dump_group(label, list)
        mod:info("[PROBE] === %s ===", label)
        -- Group by can_wield list (the careers natively allowed)
        local by_careers = {}
        for _, entry in ipairs(list) do
            local careers = entry.item.can_wield or {}
            local ck = table.concat(careers, ",")
            if not by_careers[ck] then by_careers[ck] = { careers = careers, keys = {} } end
            table.insert(by_careers[ck].keys, entry.key)
        end
        for _, group in pairs(by_careers) do
            mod:info("[PROBE]   careers=[%s]", table.concat(group.careers, ","))
            for _, k in ipairs(group.keys) do
                mod:info("[PROBE]     %s", k)
            end
        end
    end

    dump_group("HATS", hats)
    dump_group("SKINS", skins)

    -- Dump localized name per item so the generator can build proper labels
    -- without needing runtime Localize() calls (VMF needs labels at register time).
    mod:info("[PROBE] === NAMES ===")
    local function dump_names(list)
        for _, entry in ipairs(list) do
            local nm = entry.item.localized_name or entry.item.display_name or entry.key
            mod:info("[PROBE]   NAME|%s|%s", entry.key, tostring(nm))
        end
    end
    dump_names(hats)
    dump_names(skins)
    mod:echo("Probe complete — exit to keep so log flushes, send [PROBE] lines.")
end)

-- ============================================================
-- Weapon Visual Overrides
-- ============================================================
-- Same dual-path requirement as weapon_tweaker: scale and grip-offset must be
-- applied via BOTH the in-game GearUtils.create_equipment hook AND the new
-- inventory-preview MenuWorldPreviewer hooks. See weapon_tweaker.lua's comment
-- block above _weapon_scale_overrides for the full explanation.

-- Static per-weapon visual overrides (career-prefix → scale).
-- Each entry is either:
--   - a number (uniform scale)
--   - a {x, y, z} table (per-axis scale)
--   - a function(get) -> number | {x,y,z}, called each apply with `mod:get` accessor
local function _breton_sword_thiccc(get)
    if get("es_bastard_sword_thiccc") then
        return { 0.65, 1.0, 1.0 }
    end
    return nil
end

local _weapon_scale_overrides = {
    es_bastard_sword = {
        _default = _breton_sword_thiccc,
    },
    es_sword_shield_breton = {
        _default = _breton_sword_thiccc,
        _fields = { "right_unit_1p", "right_unit_3p" },
    },
}

-- weapon_key -> career_prefix -> {x, y, z} local-space offset (Z is along blade)
local _weapon_grip_offsets = {}

-- ============================================================
-- Custom Weapon Illusions (shield/weapon model combos)
-- ============================================================
-- Each entry creates a new selectable illusion for an existing weapon,
-- injected into ItemMasterList, WeaponSkins.skins, and skin_combinations.

local _custom_illusions = {
    {
        skin_key         = "ct_es_mace_gk_shield_01",
        matching_weapon  = "es_mace_shield",
        display_name     = "Mace & Bretonnian Shield",
        rarity           = "exotic",
        right_hand_unit  = "units/weapons/player/wpn_emp_mace_02_t2/wpn_emp_mace_02_t2",
        left_hand_unit   = "units/weapons/player/wpn_emp_gk_shield_03/wpn_emp_gk_shield_03",
        display_unit     = "units/weapons/weapon_display/display_shield_hammer",
        template         = "one_handed_hammer_shield_template_1",
        can_wield        = { "es_mercenary", "es_knight", "es_huntsman", "es_questingknight" },
    },

    -- Kruber spear & shield skins on Kerillian's spear & shield
    {
        skin_key         = "ct_we_spear_shield_es_01",
        matching_weapon  = "we_1h_spears_shield",
        display_name     = "Empire Spear & Shield",
        rarity           = "exotic",
        right_hand_unit  = "units/weapons/player/wpn_es_deus_spear_01/wpn_es_deus_spear_01",
        left_hand_unit   = "units/weapons/player/wpn_empire_shield_02/wpn_emp_shield_02",
        display_unit     = "units/weapons/weapon_display/display_shield_spear",
        template         = "one_handed_spears_shield_template",
        can_wield        = { "we_maidenguard" },
    },
    {
        skin_key         = "ct_we_spear_shield_es_02",
        matching_weapon  = "we_1h_spears_shield",
        display_name     = "Empire Spear & Shield (Ornate)",
        rarity           = "exotic",
        right_hand_unit  = "units/weapons/player/wpn_es_deus_spear_02/wpn_es_deus_spear_02",
        left_hand_unit   = "units/weapons/player/wpn_es_deus_shield_02/wpn_es_deus_shield_02",
        display_unit     = "units/weapons/weapon_display/display_shield_spear",
        template         = "one_handed_spears_shield_template",
        can_wield        = { "we_maidenguard" },
    },
    {
        skin_key         = "ct_we_spear_shield_es_03",
        matching_weapon  = "we_1h_spears_shield",
        display_name     = "Empire Spear & Shield (Plumed)",
        rarity           = "exotic",
        right_hand_unit  = "units/weapons/player/wpn_es_deus_spear_03/wpn_es_deus_spear_03",
        left_hand_unit   = "units/weapons/player/wpn_es_deus_shield_03/wpn_es_deus_shield_03",
        display_unit     = "units/weapons/weapon_display/display_shield_spear",
        template         = "one_handed_spears_shield_template",
        can_wield        = { "we_maidenguard" },
    },

    -- Spear & Shield spear models on Tuskgor Spear (right hand only, no shield)
    {
        skin_key         = "ct_es_heavy_spear_deus_01",
        matching_weapon  = "es_2h_heavy_spear",
        display_name     = "Spear & Shield Spear",
        rarity           = "exotic",
        right_hand_unit  = "units/weapons/player/wpn_es_deus_spear_01/wpn_es_deus_spear_01",
        display_unit     = "units/weapons/weapon_display/display_2h_heavy_spears",
        template         = "two_handed_heavy_spears_template",
        can_wield        = { "es_mercenary", "es_knight", "es_huntsman", "es_questingknight" },
    },
    {
        skin_key         = "ct_es_heavy_spear_deus_02",
        matching_weapon  = "es_2h_heavy_spear",
        display_name     = "Spear & Shield Spear (Ornate)",
        rarity           = "exotic",
        right_hand_unit  = "units/weapons/player/wpn_es_deus_spear_02/wpn_es_deus_spear_02",
        display_unit     = "units/weapons/weapon_display/display_2h_heavy_spears",
        template         = "two_handed_heavy_spears_template",
        can_wield        = { "es_mercenary", "es_knight", "es_huntsman", "es_questingknight" },
    },
    {
        skin_key         = "ct_es_heavy_spear_deus_03",
        matching_weapon  = "es_2h_heavy_spear",
        display_name     = "Spear & Shield Spear (Plumed)",
        rarity           = "exotic",
        right_hand_unit  = "units/weapons/player/wpn_es_deus_spear_03/wpn_es_deus_spear_03",
        display_unit     = "units/weapons/weapon_display/display_2h_heavy_spears",
        template         = "two_handed_heavy_spears_template",
        can_wield        = { "es_mercenary", "es_knight", "es_huntsman", "es_questingknight" },
    },

    -- Kerillian spear & shield skins on Kruber's spear & shield
    {
        skin_key         = "ct_es_deus_we_01",
        matching_weapon  = "es_deus_01",
        display_name     = "Elven Spear & Shield",
        rarity           = "exotic",
        right_hand_unit  = "units/weapons/player/wpn_we_spear_01/wpn_we_spear_01",
        left_hand_unit   = "units/weapons/player/wpn_we_shield_01/wpn_we_shield_01",
        display_unit     = "units/weapons/weapon_display/display_shield_sword",
        template         = "es_deus_01_template",
        can_wield        = { "es_huntsman", "es_knight", "es_mercenary" },
    },
    {
        skin_key         = "ct_es_deus_we_02",
        matching_weapon  = "es_deus_01",
        display_name     = "Elven Spear & Shield (Exotic)",
        rarity           = "exotic",
        right_hand_unit  = "units/weapons/player/wpn_we_spear_02/wpn_we_spear_02",
        left_hand_unit   = "units/weapons/player/wpn_we_shield_02/wpn_we_shield_02",
        display_unit     = "units/weapons/weapon_display/display_shield_sword",
        template         = "es_deus_01_template",
        can_wield        = { "es_huntsman", "es_knight", "es_mercenary" },
    },
}

local _custom_skin_keys = {}

local function _register_custom_illusions()
    if not ItemMasterList or not WeaponSkins then return end

    for _, illusion in ipairs(_custom_illusions) do
        local skin_key = illusion.skin_key
        if _custom_skin_keys[skin_key] then goto continue end

        ItemMasterList[skin_key] = {
            item_type         = "weapon_skin",
            slot_type         = "weapon_skin",
            matching_item_key = illusion.matching_weapon,
            rarity            = illusion.rarity,
            display_name      = skin_key .. "_name",
            description       = skin_key .. "_description",
            display_unit      = illusion.display_unit,
            hud_icon          = "weapon_generic_icon_staff_3",
            inventory_icon    = "icon_wpn_empire_shield_01_t1_mace",
            information_text  = "information_weapon_skin",
            right_hand_unit   = illusion.right_hand_unit,
            left_hand_unit    = illusion.left_hand_unit,
            template          = illusion.template,
            can_wield         = illusion.can_wield,
        }

        WeaponSkins.skins[skin_key] = {
            description     = skin_key .. "_description",
            display_name    = skin_key .. "_name",
            display_unit    = illusion.display_unit,
            hud_icon        = "weapon_generic_icon_staff_3",
            inventory_icon  = "icon_wpn_empire_shield_01_t1_mace",
            rarity          = illusion.rarity,
            right_hand_unit = illusion.right_hand_unit,
            left_hand_unit  = illusion.left_hand_unit,
            template        = illusion.template,
        }

        local weapon_data = ItemMasterList[illusion.matching_weapon]
        if weapon_data and weapon_data.skin_combination_table then
            local combos = WeaponSkins.skin_combinations[weapon_data.skin_combination_table]
            if combos then
                local tier = combos[illusion.rarity] or combos.exotic or combos.common
                if tier then
                    tier[#tier + 1] = skin_key
                end
            end
        end

        if NetworkLookup and NetworkLookup.weapon_skins and not rawget(NetworkLookup.weapon_skins, skin_key) then
            local tbl = NetworkLookup.weapon_skins
            tbl[#tbl + 1] = skin_key
            tbl[skin_key] = #tbl
        end

        _custom_skin_keys[skin_key] = true
        mod:info("Registered custom illusion: %s -> %s", skin_key, illusion.matching_weapon)
        ::continue::
    end
end

_register_custom_illusions()

mod:hook_safe("BackendInterfaceCraftingPlayfab", "get_unlocked_weapon_skins", function(self)
    local mirror = self._backend_mirror
    if not mirror or not mirror._unlocked_weapon_skins then return end
    for skin_key, _ in pairs(_custom_skin_keys) do
        mirror._unlocked_weapon_skins[skin_key] = true
    end
    if mod:get("unlock_all_illusions") and script_data["eac-untrusted"] and WeaponSkins then
        for skin_key, _ in pairs(WeaponSkins.skins) do
            if not _skin_requires_unowned_dlc(skin_key) then
                mirror._unlocked_weapon_skins[skin_key] = true
            end
        end
    end
end)

local _custom_loc = {}
for _, illusion in ipairs(_custom_illusions) do
    _custom_loc[illusion.skin_key .. "_name"] = illusion.display_name
    _custom_loc[illusion.skin_key .. "_description"] = illusion.display_name
end

mod:hook(_G, "Localize", function(func, key, ...)
    local custom = _custom_loc[key]
    if custom then return custom end
    local la_loc = LA_BRIDGE.localization[key]
    if la_loc then return la_loc end
    return func(key, ...)
end)

-- ============================================================
-- Unlock All Portrait Frames (modded realm only)
-- ============================================================
-- Injects all frame-type items from ItemMasterList into the
-- _unlocked_cosmetics table so they appear as equippable in the
-- cosmetics loadout UI. Hooked on PlayFabMirrorBase so it fires
-- during mirror init (before _create_fake_inventory_items runs),
-- ensuring fake backend items are generated for each frame.
-- DLC ownership is respected via required_dlc checks.

mod:hook_safe("PlayFabMirrorBase", "get_unlocked_cosmetics", function(self)
    if not mod:get("unlock_all_frames") or not script_data["eac-untrusted"] then return end
    local cosmetics = self._unlocked_cosmetics
    if not cosmetics then return end
    for key, data in pairs(ItemMasterList) do
        if data.item_type == "frame" and not cosmetics[key] then
            if not _skin_requires_unowned_dlc(key) then
                cosmetics[key] = true
            end
        end
    end
end)

-- ============================================================
-- Modded-realm illusion swap (bypass server-side craft block)
-- ============================================================
-- In modded realm the "Apply" button for weapon illusions is disabled
-- (HeroWindowItemCustomization._enable_craft_button force-sets enable=false
-- when script_data["eac-untrusted"]) and the server rejects craftingApplySkin2.
--
-- We intercept three points:
--   1. _enable_craft_button — temporarily clear eac-untrusted so the Apply
--      button is usable for illusion swaps. On disable, force-clear the
--      hotspot's is_held/input_pressed flags to prevent re-trigger: the
--      engine hotspot (ui_passes.lua:4386) only clears is_held on mouse
--      release, NOT when disable_button is set, so a fast craft completion
--      while the user is still holding the mouse causes an infinite
--      craft→complete→re-craft sound loop.
--   2. get_weapon_skin_from_skin_key — return synthetic backend IDs for
--      skins the player doesn't "own" in their backend inventory, so the
--      illusion browser can reference them. For vanilla locked skins this
--      is needed because get_weapon_skin_from_skin_key only searches
--      _fake_items (unlocked skins), not all known skins.
--   3. craft + update — when in modded and applying a weapon skin, write
--      item.skin directly on the local backend mirror instead of sending to
--      PlayFab. Result is deferred one frame via the update hook to match
--      the vanilla async timing and avoid same-frame completion artifacts.
--   4. _on_illusion_index_pressed — force content.locked = false so the
--      Apply button enables for skins the player hasn't earned.
--   5. _update_state_craft_button — temporarily clear eac-untrusted so the
--      craft button's disable_button flag doesn't bake in the modded check.
--
-- DLC ownership is respected: skins with a required_dlc field in
-- ItemMasterList are only unlockable if the player owns that DLC
-- (checked via Managers.unlock:is_dlc_unlocked). This prevents the mod
-- from bypassing paid cosmetic DLC paywalls.

local _fake_skin_backend_ids = {}

mod:hook("BackendInterfaceItemPlayfab", "get_weapon_skin_from_skin_key", function(func, self, skin_key)
    local id, item = func(self, skin_key)
    if id then return id, item end

    if _custom_skin_keys[skin_key] or (script_data["eac-untrusted"] and ItemMasterList[skin_key] and not _skin_requires_unowned_dlc(skin_key)) then
        local fake_id = "ct_fake_" .. skin_key
        _fake_skin_backend_ids[fake_id] = skin_key
        local fake_item = {
            skin = skin_key,
            ItemId = skin_key,
            data = ItemMasterList[skin_key],
            key = skin_key,
            rarity = ItemMasterList[skin_key] and ItemMasterList[skin_key].rarity or "exotic",
        }
        return fake_id, fake_item
    end
end)

mod:hook("HeroWindowItemCustomization", "_enable_craft_button", function(func, self, enable, disable_edges)
    if enable and script_data["eac-untrusted"] and self._current_recipe_name == "apply_weapon_skin" then
        local saved = script_data["eac-untrusted"]
        script_data["eac-untrusted"] = false
        func(self, enable, disable_edges)
        script_data["eac-untrusted"] = saved
        return
    end
    func(self, enable, disable_edges)
    if not enable and self._current_recipe_name == "apply_weapon_skin" then
        local widget = self._widgets_by_name and self._widgets_by_name.craft_button
        if widget and widget.content and widget.content.button_hotspot then
            widget.content.button_hotspot.is_held = false
            widget.content.button_hotspot.input_pressed = false
        end
    end
end)

mod:hook("HeroWindowItemCustomization", "_on_illusion_index_pressed", function(func, self, index, ignore_item_spawn, mark_as_equipped)
    if script_data["eac-untrusted"] and not ignore_item_spawn then
        local widget = self._illusion_widgets and self._illusion_widgets[index]
        if widget and widget.content then
            local skin_key = widget.content.skin_key
            if not _skin_requires_unowned_dlc(skin_key) then
                widget.content.locked = false
            end
        end
    end
    return func(self, index, ignore_item_spawn, mark_as_equipped)
end)

mod:hook("HeroWindowItemCustomization", "_update_state_craft_button", function(func, self, recipe_name, ...)
    if script_data["eac-untrusted"] and recipe_name == "apply_weapon_skin" then
        local saved = script_data["eac-untrusted"]
        script_data["eac-untrusted"] = false
        local result = func(self, recipe_name, ...)
        script_data["eac-untrusted"] = saved
        return result
    end
    return func(self, recipe_name, ...)
end)

local _pending_local_craft = nil

mod:hook("BackendInterfaceCraftingPlayfab", "craft", function(func, self, career_name, item_backend_ids, recipe_override)
    if not script_data["eac-untrusted"] then
        return func(self, career_name, item_backend_ids, recipe_override)
    end

    local backend_items = Managers.backend:get_interface("items")
    local weapon_backend_id, skin_key

    for _, bid in ipairs(item_backend_ids) do
        if _fake_skin_backend_ids[bid] then
            skin_key = _fake_skin_backend_ids[bid]
        else
            local item = backend_items:get_item_from_id(bid)
            if not item then
                local fake_items = backend_items:get_all_fake_backend_items()
                item = fake_items and fake_items[bid]
            end
            if item then
                local slot_type = item.data and item.data.slot_type
                if slot_type == "melee" or slot_type == "ranged" then
                    weapon_backend_id = bid
                elseif slot_type == "weapon_skin" then
                    skin_key = item.skin or item.key
                end
            end
        end
    end

    if not weapon_backend_id or not skin_key then
        return func(self, career_name, item_backend_ids, recipe_override)
    end

    if _skin_requires_unowned_dlc(skin_key) then
        mod:echo("Cannot apply illusion — requires DLC you don't own.")
        return func(self, career_name, item_backend_ids, recipe_override)
    end

    local mirror = self._backend_mirror
    local weapon_item = mirror._inventory_items and mirror._inventory_items[weapon_backend_id]
    if not weapon_item then
        return func(self, career_name, item_backend_ids, recipe_override)
    end

    weapon_item.skin = skin_key
    weapon_item.bypass_skin_ownership_check = true
    if weapon_item.CustomData then
        weapon_item.CustomData.skin = skin_key
    end

    local id = self:_new_id()
    _pending_local_craft = { interface = self, id = id }

    mod:info("Applied illusion '%s' locally (modded realm bypass)", skin_key)
    return id, { name = "apply_weapon_skin" }
end)

mod:hook_safe("BackendInterfaceCraftingPlayfab", "update", function(self, dt)
    if _pending_local_craft and _pending_local_craft.interface == self then
        self._craft_requests[_pending_local_craft.id] = {}
        Managers.backend:dirtify_interfaces()
        _pending_local_craft = nil
    end
end)

-- ============================================================
-- Independent offhand (shield) illusion system
-- ============================================================
-- Adds a second row of illusion buttons below the main row on the
-- weapon customization screen. The main row swaps the right-hand
-- weapon model; this row independently swaps the left-hand (shield)
-- model. Only shown for weapons that have a left_hand_unit.

-- Preload the unit packages backing an offhand override, so when the
-- in-game body re-spawns under a different illusion the engine can still
-- find our chosen shield mesh. The 1p and 3p meshes are SEPARATE packages
-- in vanilla VT2 — LA's own bootstrap loads both halves explicitly, and
-- WeaponUtils.get_weapon_packages confirms it (`unit_name` AND
-- `unit_name .. "_3p"` are queued separately). The in-game body spawns
-- BOTH halves; the customization previewer only spawns 3p. Load both.
--
-- SYNCHRONOUS load (async=false): the previous async preload had a fatal
-- timing race — if the user clicked Apply before the async load finished,
-- BackendUtils.get_item_units returned an override path the engine
-- couldn't spawn yet, and it asserted in `world.spawn_unit`. Sync loads
-- block briefly (one shield package is small) and guarantee the package
-- is ready when the hook fires.
local _preloaded_offhand_packages = {}
local function _preload_one(package_path)
    if not package_path or package_path == "" then return end
    if _preloaded_offhand_packages[package_path] then return end
    if not Managers or not Managers.package then return end
    if Managers.package:has_loaded(package_path) then
        _preloaded_offhand_packages[package_path] = true
        return
    end
    -- Sync (async=false / omitted). pcall to swallow "package not found"
    -- on paths that don't exist (some optional shield variants may be
    -- unpackaged for users without the relevant DLC).
    local ok, err = pcall(function()
        Managers.package:load(package_path, "cosmetics_tweaker", nil, false)
    end)
    if ok then
        _preloaded_offhand_packages[package_path] = true
        mod:info("[offhand] preloaded package %s (sync)", package_path)
    else
        mod:info("[offhand] preload FAILED for %s: %s", package_path, tostring(err))
    end
end

local function _preload_offhand_package(unit_path)
    _preload_one(unit_path)
    if unit_path and unit_path ~= "" then
        _preload_one(unit_path .. "_3p")
    end
end

local function _preload_offhand_for_option(opt)
    if not opt then return end
    if opt.unit then _preload_offhand_package(opt.unit) end
    if opt.intended_unit then _preload_offhand_package(opt.intended_unit) end
end

-- Returns true only when both the 1p and 3p packages are fully loaded
-- and ready for World.spawn_unit. Use as a safety gate before applying
-- a left_hand_unit override: even with sync preload, a defensive check
-- here prevents future regressions / unknown-paths from crashing.
local function _override_package_ready(unit_path)
    if not unit_path or unit_path == "" then return false end
    if not Managers or not Managers.package then return false end
    if not Managers.package:has_loaded(unit_path) then return false end
    if not Managers.package:has_loaded(unit_path .. "_3p") then return false end
    return true
end

local _offhand_options = {
    es_1h_sword_shield = {
        { name = "Empire Shield",          unit = "units/weapons/player/wpn_empire_shield_01_t1/wpn_emp_shield_01_t1" },
        { name = "Empire Round Shield",    unit = "units/weapons/player/wpn_empire_shield_02/wpn_emp_shield_02" },
        { name = "Empire Shield (Ornate)", unit = "units/weapons/player/wpn_empire_shield_03/wpn_emp_shield_03" },
        { name = "Empire Shield (Plated)", unit = "units/weapons/player/wpn_empire_shield_04/wpn_emp_shield_04" },
        { name = "Empire Shield (Gold)",   unit = "units/weapons/player/wpn_empire_shield_05/wpn_emp_shield_05" },
        { name = "GK Shield (Blue)",       unit = "units/weapons/player/wpn_emp_gk_shield_03/wpn_emp_gk_shield_03" },
        { name = "GK Shield (Red)",        unit = "units/weapons/player/wpn_emp_gk_shield_02/wpn_emp_gk_shield_02" },
        { name = "GK Shield (Green)",      unit = "units/weapons/player/wpn_emp_gk_shield_04/wpn_emp_gk_shield_04" },
        { name = "GK Shield (White)",      unit = "units/weapons/player/wpn_emp_gk_shield_05/wpn_emp_gk_shield_05" },
        { name = "GK Shield (Blessed)",    unit = "units/weapons/player/wpn_emp_gk_shield_01/wpn_emp_gk_shield_01" },
        { name = "Deus Shield (Ornate)",   unit = "units/weapons/player/wpn_es_deus_shield_02/wpn_es_deus_shield_02" },
        { name = "Deus Shield (Plumed)",   unit = "units/weapons/player/wpn_es_deus_shield_03/wpn_es_deus_shield_03" },
        { name = "WP Shield",              unit = "units/weapons/player/wpn_wh_shield_01/wpn_wh_shield_01_t1" },
    },
    we_1h_spears_shield = {
        { name = "Elven Shield",           unit = "units/weapons/player/wpn_we_shield_01/wpn_we_shield_01" },
        { name = "Elven Shield (Exotic)",  unit = "units/weapons/player/wpn_we_shield_02/wpn_we_shield_02" },
        { name = "Empire Round Shield",    unit = "units/weapons/player/wpn_empire_shield_02/wpn_emp_shield_02" },
        { name = "Empire Shield",          unit = "units/weapons/player/wpn_empire_shield_01_t1/wpn_emp_shield_01_t1" },
        { name = "GK Shield (Blue)",       unit = "units/weapons/player/wpn_emp_gk_shield_03/wpn_emp_gk_shield_03" },
        { name = "Deus Shield (Ornate)",   unit = "units/weapons/player/wpn_es_deus_shield_02/wpn_es_deus_shield_02" },
        { name = "Deus Shield (Plumed)",   unit = "units/weapons/player/wpn_es_deus_shield_03/wpn_es_deus_shield_03" },
    },
    dr_1h_axe_shield = {
        { name = "Dwarf Shield 1",         unit = "units/weapons/player/wpn_dw_shield_01_t1/wpn_dw_shield_01" },
        { name = "Dwarf Shield 2",         unit = "units/weapons/player/wpn_dw_shield_02_t1/wpn_dw_shield_02" },
        { name = "Dwarf Shield 2 (Runed)", unit = "units/weapons/player/wpn_dw_shield_02_t1/wpn_dw_shield_02_runed_01" },
        { name = "Dwarf Shield 3",         unit = "units/weapons/player/wpn_dw_shield_03_t1/wpn_dw_shield_03" },
        { name = "Dwarf Shield 4",         unit = "units/weapons/player/wpn_dw_shield_04_t1/wpn_dw_shield_04" },
        { name = "Dwarf Shield 4 (Magic)", unit = "units/weapons/player/wpn_dw_shield_04_t1/wpn_dw_shield_04_magic_01" },
        { name = "Dwarf Shield 5",         unit = "units/weapons/player/wpn_dw_shield_05_t1/wpn_dw_shield_05" },
        { name = "Dwarf Shield 5 (Runed)", unit = "units/weapons/player/wpn_dw_shield_05_t1/wpn_dw_shield_05_runed_01" },
        { name = "Empire Shield",          unit = "units/weapons/player/wpn_empire_shield_01_t1/wpn_emp_shield_01_t1" },
        { name = "Empire Round Shield",    unit = "units/weapons/player/wpn_empire_shield_02/wpn_emp_shield_02" },
        { name = "Elven Shield",           unit = "units/weapons/player/wpn_we_shield_01/wpn_we_shield_01" },
        { name = "WP Shield",              unit = "units/weapons/player/wpn_wh_shield_01/wpn_wh_shield_01_t1" },
    },
    wh_flail_shield = {
        { name = "WP Shield",              unit = "units/weapons/player/wpn_wh_shield_01/wpn_wh_shield_01_t1" },
        { name = "WP Shield (Runed)",      unit = "units/weapons/player/wpn_wh_shield_01/wpn_wh_shield_01_t1_runed" },
        { name = "WP Shield (Magic)",      unit = "units/weapons/player/wpn_wh_shield_01/wpn_wh_shield_01_t1_magic" },
        { name = "Empire Shield",          unit = "units/weapons/player/wpn_empire_shield_01_t1/wpn_emp_shield_01_t1" },
        { name = "Empire Round Shield",    unit = "units/weapons/player/wpn_empire_shield_02/wpn_emp_shield_02" },
        { name = "GK Shield (Blue)",       unit = "units/weapons/player/wpn_emp_gk_shield_03/wpn_emp_gk_shield_03" },
        { name = "GK Shield (Red)",        unit = "units/weapons/player/wpn_emp_gk_shield_02/wpn_emp_gk_shield_02" },
        { name = "Elven Shield",           unit = "units/weapons/player/wpn_we_shield_01/wpn_we_shield_01" },
        { name = "Dwarf Shield",           unit = "units/weapons/player/wpn_dw_shield_01_t1/wpn_dw_shield_01" },
    },
}
_offhand_options.es_1h_mace_shield          = _offhand_options.es_1h_sword_shield
_offhand_options.es_1h_sword_shield_breton  = _offhand_options.es_1h_sword_shield
_offhand_options.es_deus_01                 = _offhand_options.es_1h_sword_shield
_offhand_options.dr_1h_hammer_shield        = _offhand_options.dr_1h_axe_shield
_offhand_options.wh_hammer_shield           = _offhand_options.wh_flail_shield

-- _offhand_selection[weapon_key] = option_table (the same object stored in
-- _offhand_options[weapon_key]). Vanilla entries have only `unit`; LA-bridge
-- entries have `la_armoury_key` + `vanilla_skin` (no `unit` — LA paints onto
-- whatever shield mesh the user's vanilla illusion provides).
local _offhand_selection = {}

-- Fan-out: each character's LA shield pool gets attached to all of that
-- character's vanilla shield-bearing weapon types. Implements the
-- "no cross-character, yes cross-career-within-character" rule.
local _la_character_weapon_pools = {
    Kruber    = { "es_1h_sword_shield", "es_1h_mace_shield", "es_1h_sword_shield_breton", "es_deus_01" },
    Kerillian = { "we_1h_spears_shield" },
    Bardin    = { "dr_1h_axe_shield", "dr_1h_hammer_shield" },
    Saltzpyre = { "wh_flail_shield", "wh_hammer_shield" },
}

local _la_offhand_merged = false

local function _merge_la_offhand_options()
    if _la_offhand_merged then return end
    if not LA_BRIDGE.registered then return end
    if type(LA_BRIDGE.la_offhand_options_by_character) ~= "table" then return end
    -- Track which option-list tables we've already appended to (the
    -- existing _offhand_options aliases share table references), so a
    -- character's pool only lands in each physical list once.
    local seen_lists = {}
    for character, la_pool in pairs(LA_BRIDGE.la_offhand_options_by_character) do
        local weapon_keys = _la_character_weapon_pools[character]
        if weapon_keys then
            for _, weapon_key in ipairs(weapon_keys) do
                local target = _offhand_options[weapon_key]
                if not target then target = {}; _offhand_options[weapon_key] = target end
                if not seen_lists[target] then
                    seen_lists[target] = true
                    for _, la_opt in ipairs(la_pool) do
                        target[#target + 1] = {
                            name            = la_opt.name .. " (LA)",
                            la_armoury_key  = la_opt.armoury_key,
                            vanilla_skin    = la_opt.vanilla_skin,
                            -- mesh the LA texture was authored for; swapped
                            -- in via BackendUtils.get_item_units so LA paints
                            -- onto the right shield shape (not whatever shield
                            -- the user's vanilla weapon happens to use).
                            intended_unit   = la_opt.intended_unit,
                            rarity          = "promo",
                        }
                    end
                end
            end
        end
    end
    _la_offhand_merged = true
    mod:info("[offhand] merged LA shield options into _offhand_options")
end

local function _get_offhand_options(item_key)
    return _offhand_options[item_key]
end

mod:command("la_offhand_dump", "Dump LA offhand variant -> intended_unit resolution", function()
    if LA_BRIDGE and LA_BRIDGE.dump_offhand_resolution then
        LA_BRIDGE.dump_offhand_resolution()
    else
        mod:echo("[LA bridge] dump_offhand_resolution unavailable")
    end
end)

mod:command("offhand_debug", "Dump offhand system state", function()
    mod:echo("[offhand] _offhand_options keys:")
    for k, v in pairs(_offhand_options) do
        mod:echo("  %s -> %d options", k, #v)
    end
    mod:echo("[offhand] _offhand_selection:")
    for k, v in pairs(_offhand_selection) do
        local label = v.la_armoury_key and ("LA:" .. v.la_armoury_key) or tostring(v.unit)
        mod:echo("  %s -> %s", k, label)
    end
    mod:echo("[offhand] BackendUtils hooked: %s", tostring(BackendUtils ~= nil))
    mod:echo("[offhand] UIWidget available: %s", tostring(UIWidget ~= nil))
    mod:echo("[offhand] UIWidgets available: %s", tostring(UIWidgets ~= nil))
    mod:echo("[offhand] UIRenderer available: %s", tostring(UIRenderer ~= nil))
    mod:echo("[offhand] Colors available: %s", tostring(Colors ~= nil))
end)

local function _has_offhand(item_data)
    return item_data and item_data.left_hand_unit ~= nil
end

local function _get_weapon_key_from_item(item)
    if not item then return nil end
    local data = item.data or (ItemMasterList and ItemMasterList[item.key])
    if data and data.item_type then return data.item_type end
    return item.key
end

mod:hook("HeroWindowItemCustomization", "_setup_illusions", function(func, self, item)
    func(self, item)

    self._ct_offhand_widgets = nil
    self._ct_offhand_title_widget = nil
    self._ct_offhand_name_widget = nil
    self._ct_offhand_divider_widget = nil
    self._ct_selected_offhand_index = nil

    mod:info("[offhand] _setup_illusions called, item=%s", tostring(item and item.key))

    if not item then mod:info("[offhand] no item, bailing"); return end
    local item_data = item.data or (ItemMasterList and ItemMasterList[item.key])
    mod:info("[offhand] item_data=%s, left_hand_unit=%s", tostring(item_data ~= nil), tostring(item_data and item_data.left_hand_unit))
    if not _has_offhand(item_data) then mod:info("[offhand] no offhand, bailing"); return end

    local weapon_key = _get_weapon_key_from_item(item)
    mod:info("[offhand] weapon_key=%s", tostring(weapon_key))
    local options = _get_offhand_options(weapon_key)
    if not options or #options == 0 then mod:info("[offhand] no options for key=%s, bailing", tostring(weapon_key)); return end
    mod:info("[offhand] found %d offhand options", #options)

    local definitions = local_require("scripts/ui/views/hero_view/windows/definitions/hero_window_item_customization_definitions")
    local create_btn = definitions.create_illusion_button
    mod:info("[offhand] create_btn=%s", tostring(create_btn))

    local width = 51
    local spacing = -5
    local total_width = -spacing
    local widgets = {}

    for i, opt in ipairs(options) do
        local widget_def = create_btn()
        local widget = UIWidget.init(widget_def)
        local rarity = opt.rarity or "exotic"
        local icon_texture = "button_illusion_" .. rarity
        if UIAtlasHelper and UIAtlasHelper.has_texture_by_name and not UIAtlasHelper.has_texture_by_name(icon_texture) then
            icon_texture = "button_illusion_default"
        end
        widget.content.skin_key = "__offhand_" .. i
        widget.content.icon_texture = icon_texture
        widget.content.offhand_index = i
        widget.content.offhand_unit = opt.unit
        widget.content.offhand_name = opt.name
        widget.content.locked = false
        widget.content.rarity = rarity
        widgets[#widgets + 1] = widget
        total_width = total_width + spacing + width
    end

    local offhand_y = 95
    local x_offset = width / 2
    for _, widget in ipairs(widgets) do
        widget.offset = widget.offset or { 0, 0, 0 }
        widget.offset[1] = -total_width / 2 + x_offset
        widget.offset[2] = offhand_y
        x_offset = x_offset + width + spacing
    end

    -- Determine the shield mesh currently rendered for this item. Priority:
    --   1. backend's stored skin (`item.skin`) -> WeaponSkins.skins[skin].left_hand_unit
    --   2. ItemMasterList's get_skin lookup by backend_id (covers items where
    --      .skin is nil but the player has an illusion applied via the live
    --      backend — the situation user reported on a vanilla-crafted weapon)
    --   3. item_data.left_hand_unit (template default)
    local current_left_unit
    local skin_resolved = item.skin
    if not skin_resolved and item.backend_id and Managers and Managers.backend then
        local items_iface = Managers.backend:get_interface("items")
        if items_iface and items_iface.get_skin then
            skin_resolved = items_iface:get_skin(item.backend_id)
        end
    end
    if skin_resolved and WeaponSkins and WeaponSkins.skins
            and WeaponSkins.skins[skin_resolved] then
        current_left_unit = WeaponSkins.skins[skin_resolved].left_hand_unit
    end
    if not current_left_unit then
        current_left_unit = item_data.left_hand_unit
    end
    mod:info("[offhand] auto-select: weapon_key=%s item.skin=%s skin_resolved=%s current_left_unit=%s options=%d",
        tostring(weapon_key), tostring(item.skin), tostring(skin_resolved),
        tostring(current_left_unit), #options)

    -- The picker should always reflect what's actually rendered. If the
    -- stored selection is stale (e.g. user switched weapons / illusions
    -- since last pick) and doesn't match the current shield, prefer the
    -- match against the current shield. The user's previous explicit pick
    -- is preserved only when its mesh still matches what's visible.
    local current_sel = _offhand_selection[weapon_key]
    if current_sel then
        local sel_mesh = current_sel.unit or current_sel.intended_unit
        if sel_mesh ~= current_left_unit then
            current_sel = nil  -- stale; fall through to fresh auto-select
        end
    end

    if not current_sel and current_left_unit then
        for _, opt in ipairs(options) do
            local opt_mesh = opt.unit or opt.intended_unit
            if opt_mesh == current_left_unit then
                _offhand_selection[weapon_key] = opt
                current_sel = opt
                mod:info("[offhand] auto-selected: %s", tostring(opt.name))
                break
            end
        end
        if not current_sel then
            mod:info("[offhand] no option matched current_left_unit=%s — leaving picker unhighlighted",
                tostring(current_left_unit))
        end
    end

    -- Make the override mesh available to the in-game spawn path. Without
    -- this preload, applying a NEW illusion (whose package chain doesn't
    -- include our override mesh) crashes with "Unit not found" the moment
    -- GearUtils.create_equipment fires on the new skin.
    if current_sel then _preload_offhand_for_option(current_sel) end

    if current_sel then
        for i, widget in ipairs(widgets) do
            if options[i] == current_sel then
                widget.content.button_hotspot.is_selected = true
                widget.content.equipped = true
                self._ct_selected_offhand_index = i
            end
        end
    end

    self._ct_offhand_widgets = widgets
    self._ct_offhand_weapon_key = weapon_key
    self._ct_offhand_options = options
end)

mod:hook("HeroWindowItemCustomization", "_state_draw_overview", function(func, self, ui_renderer, dt)
    func(self, ui_renderer, dt)

    local offhand_widgets = self._ct_offhand_widgets
    if not offhand_widgets or #offhand_widgets == 0 then return end

    if not ui_renderer or not ui_renderer.ui_scenegraph then return end
    local sg = ui_renderer.ui_scenegraph

    for _, widget in ipairs(offhand_widgets) do
        if sg[widget.scenegraph_id] then
            UIRenderer.draw_widget(ui_renderer, widget)
        end
    end

    for i, widget in ipairs(offhand_widgets) do
        local hotspot = widget.content.button_hotspot
        if hotspot and hotspot.on_pressed then
            self:_ct_on_offhand_pressed(i)
            break
        end
    end
end)

HeroWindowItemCustomization._ct_on_offhand_pressed = function(self, index)
    local widgets = self._ct_offhand_widgets
    if not widgets then return end

    local widget = widgets[index]
    if not widget then return end

    local options = self._ct_offhand_options
    local weapon_key = self._ct_offhand_weapon_key
    local opt = options and options[index]
    if not opt then return end

    _offhand_selection[weapon_key] = opt
    _preload_offhand_for_option(opt)

    for i, w in ipairs(widgets) do
        local is_sel = (i == index)
        w.content.button_hotspot.is_selected = is_sel
        w.content.equipped = is_sel
    end

    self._ct_selected_offhand_index = index

    local item = self:_get_item(self._item_backend_id)
    if item then
        -- Vanilla-crafted weapons (e.g. Bret sword + shield) sometimes have
        -- the equipped illusion stored only in the backend and `item.skin`
        -- is nil. Fall through items_iface:get_skin(backend_id) before
        -- giving up — without this the respawn was skipped entirely for
        -- Bret weapons and clicking the offhand picker had no visible effect.
        local skin_key = item.skin
        if not skin_key and item.backend_id and Managers and Managers.backend then
            local items_iface = Managers.backend:get_interface("items")
            if items_iface and items_iface.get_skin then
                skin_key = items_iface:get_skin(item.backend_id)
            end
        end
        if not skin_key and item.data and item.key then
            skin_key = WeaponSkins.default_skins[item.key]
        end
        local skin_data = skin_key and WeaponSkins.skins[skin_key]
        if skin_data then
            local preview_item = {
                data = item.data,
                skin = skin_key,
            }
            self:_spawn_item_unit(preview_item, true)
        end
    end

    self:_enable_craft_button(true, true)
    self:_play_sound("play_gui_equipment_equip")
end

if BackendUtils then
    mod:hook(BackendUtils, "get_item_units", function(func, item_data, backend_id, skin, career_name)
        local result = func(item_data, backend_id, skin, career_name)
        if not result then return result end

        -- Resolve the actual skin: caller may pass nil and rely on backend
        -- lookup. Mirror BackendUtils' own resolution so we can decide
        -- whether to apply the override.
        local resolved_skin = skin
        if not resolved_skin and backend_id and Managers and Managers.backend then
            local backend_items = Managers.backend:get_interface("items")
            if backend_items and backend_items.get_skin then
                resolved_skin = backend_items:get_skin(backend_id)
            end
        end

        -- HARD GATE: only override when an illusion (skin) is actually
        -- present. The base weapon template has no skin and the user's
        -- expectation is that we ADD options on top of illusions, never
        -- mutate the base/template visuals. Without this gate, picking
        -- an LA option on a skinned weapon also leaks the LA mesh+texture
        -- onto the base weapon (same item_type) in inventory and other
        -- spawns. See user report 2026-05-01.
        if not resolved_skin or resolved_skin == "" then return result end

        local item_type = item_data and item_data.item_type
        if item_type == "weapon_skin" and item_data.matching_item_key then
            local weapon_data = ItemMasterList[item_data.matching_item_key]
            if weapon_data then
                item_type = weapon_data.item_type
            end
        end
        if not item_type then return result end

        local sel = _offhand_selection[item_type]
        local override_unit
        if sel and sel.unit then
            override_unit = sel.unit
        elseif sel and sel.intended_unit then
            -- LA offhand: swap to the mesh the LA texture was authored for.
            override_unit = sel.intended_unit
        end

        -- Safety gate: only override if the package is fully loaded. The
        -- engine asserts in `world.spawn_unit` when the resource manager
        -- can't find the unit. With sync preload at click/auto-select time
        -- this should always pass for live selections, but protects against
        -- preload races / future regressions.
        if override_unit and _override_package_ready(override_unit) then
            result.left_hand_unit = override_unit
        elseif override_unit then
            mod:info("[offhand] SKIP override %s -> %s (package not ready)",
                tostring(item_type), tostring(override_unit))
        end

        return result
    end)
end

-- ============================================================
-- Helpers (parallel to weapon_tweaker; consolidate into a shared
-- module if a third mod ever needs them)
-- ============================================================

local function _is_unit(v) return type(v) == "userdata" and pcall(Unit.alive, v) end

local function _resolve_for_career(overrides, career_name)
    if not overrides or not career_name then return nil end
    local best, best_len = nil, -1
    for prefix, value in pairs(overrides) do
        if prefix ~= "_default" and #prefix > best_len and career_name:sub(1, #prefix) == prefix then
            best, best_len = value, #prefix
        end
    end
    if best ~= nil then
        if best == false then return nil end
        return best
    end
    return overrides._default
end

local function _scale_units(slot_data, weapon_key, career_name)
    local overrides = _weapon_scale_overrides[weapon_key]
    if not overrides then return end
    local scale_factor = _resolve_for_career(overrides, career_name)
    if not scale_factor then return end
    -- Resolve dynamic factors (functions read live settings each call).
    if type(scale_factor) == "function" then
        scale_factor = scale_factor(function(id) return mod:get(id) end)
        if not scale_factor then return end
    end
    local scale
    if type(scale_factor) == "table" then
        scale = Vector3(scale_factor[1], scale_factor[2], scale_factor[3])
    else
        scale = Vector3(scale_factor, scale_factor, scale_factor)
    end
    local fields = overrides._fields or { "left_unit_1p", "right_unit_1p", "left_unit_3p", "right_unit_3p" }
    for _, field in ipairs(fields) do
        local unit = slot_data[field]
        if unit then pcall(Unit.set_local_scale, unit, 0, scale) end
    end
end

local function _offset_units(slot_data, weapon_key, career_name)
    local overrides = _weapon_grip_offsets[weapon_key]
    if not overrides then return end
    local offset = _resolve_for_career(overrides, career_name)
    if not offset then return end
    local pos = Vector3(offset[1], offset[2], offset[3])
    for _, field in ipairs({ "left_unit_1p", "right_unit_1p", "left_unit_3p", "right_unit_3p" }) do
        local unit = slot_data[field]
        if unit then
            local current = Unit.local_position(unit, 0)
            pcall(Unit.set_local_position, unit, 0, current + pos)
        end
    end
end

local function _local_career_name()
    local pm = Managers.player
    if not pm then return nil end
    local pl = pm:local_player()
    if not pl then return nil end
    local ok, name = pcall(pl.career_name, pl)
    return ok and name or nil
end

-- Resolve a weapon's item_type, walking weapon_skin -> matching weapon if needed.
local function _resolve_item_type(item_data)
    if not item_data then return nil end
    local item_type = item_data.item_type
    if item_type == "weapon_skin" and item_data.matching_item_key and ItemMasterList then
        local wd = ItemMasterList[item_data.matching_item_key]
        if wd then item_type = wd.item_type end
    end
    return item_type
end

-- If an LA offhand is selected for the given weapon item_type, paint LA
-- heraldic textures onto each provided shield unit. Vanilla offhand
-- selections (with `unit` set) are handled earlier in get_item_units;
-- LA selections are handled here, after the vanilla shield unit spawned.
--
-- `has_skin` MUST be true (a non-empty skin key/equipped illusion) — the
-- paint is gated to skinned items only, mirroring the BackendUtils.get_item_units
-- override gate. Painting the base weapon template would surprise users
-- ("base template can't have illusions applied").
local function _apply_la_offhand_to_units(world, item_data, units, has_skin)
    if not LA_BRIDGE.registered then mod:info("[LA paint] skip: bridge not registered"); return end
    if not world or not item_data then mod:info("[LA paint] skip: world/item_data nil"); return end
    if not has_skin then mod:info("[LA paint] skip: has_skin=false"); return end
    local item_type = _resolve_item_type(item_data)
    if not item_type then mod:info("[LA paint] skip: no item_type"); return end
    local sel = _offhand_selection[item_type]
    if not sel then mod:info("[LA paint] skip: no _offhand_selection for %s", tostring(item_type)); return end
    if not sel.la_armoury_key then return end  -- vanilla selection, nothing for us to paint
    mod:info("[LA paint] painting %s on %d units (item_type=%s)",
        tostring(sel.la_armoury_key), #units, tostring(item_type))
    for _, u in ipairs(units) do
        if u and _is_unit(u) then
            local ok = LA_BRIDGE.apply_offhand_to_unit(world, u, sel.la_armoury_key, sel.vanilla_skin)
            mod:info("[LA paint]   unit=%s ok=%s", tostring(u), tostring(ok))
        end
    end
end

-- In-game keep / mission body
mod:hook("GearUtils", "create_equipment", function(func, world, slot_name, item_data, unit_1p, unit_3p, is_bot, unit_template, extra_extension_data, ammo_percent, override_item_template, override_item_units, career_name)
    local result = func(world, slot_name, item_data, unit_1p, unit_3p, is_bot, unit_template, extra_extension_data, ammo_percent, override_item_template, override_item_units, career_name)
    if result and item_data then
        local weapon_key = item_data.name
        _scale_units(result, weapon_key, career_name)
        _offset_units(result, weapon_key, career_name)
        -- Per-hat tint: hats spawn into right_unit_3p in this code path.
        for _, field in ipairs({ "right_unit_3p", "left_unit_3p", "right_unit_1p", "left_unit_1p" }) do
            local u = result[field]
            if u then _maybe_tint(weapon_key, u) end
        end
        local has_skin = result.skin ~= nil and result.skin ~= ""
        _apply_la_offhand_to_units(world, item_data, { result.left_unit_3p, result.left_unit_1p }, has_skin)
    end
    return result
end)

-- Inventory preview (new menu)
local _mwp_pending_keys = setmetatable({}, { __mode = "k" })

mod:hook("MenuWorldPreviewer", "equip_item", function(func, self, item_key, slot, backend_id, skin, skip_wield_anim)
    local slot_name = (type(slot) == "table" and slot.name) or tostring(slot)
    mod:info("[LA preview] equip_item key=%s slot=%s bid=%s is_clone=%s",
        tostring(item_key), tostring(slot_name), tostring(backend_id),
        tostring(LA_BRIDGE.backend_to_armoury[backend_id] ~= nil))

    if type(item_key) == "string" then
        local sn = (type(slot) == "table" and slot.name) or (type(slot) == "string" and slot)
        if sn then
            local map = _mwp_pending_keys[self]
            if not map then map = {}; _mwp_pending_keys[self] = map end
            map[sn:gsub("^slot_", "")] = item_key
        end
    end

    if LA_BRIDGE.registered and backend_id and LA_BRIDGE.backend_to_armoury[backend_id] then
        mod:info("[LA preview] equip_item swapping key %s -> %s for clone", tostring(item_key), tostring(backend_id))
        return func(self, backend_id, slot, backend_id, skin, skip_wield_anim)
    end

    return func(self, item_key, slot, backend_id, skin, skip_wield_anim)
end)

local function _spawn_item_post(self, item_name, spawn_data)
    if not spawn_data then return end

    -- LA offhand paint: independent of scaling, runs whenever the
    -- previewed weapon has an LA offhand selected.
    if item_name and ItemMasterList then
        local item_data = ItemMasterList[item_name]
        local world = self._world or self.world
        if world and item_data then
            local equip_units = self._equipment_units
            if equip_units then
                local left_units = {}
                for _, slot in pairs(equip_units) do
                    if type(slot) == "table" and slot.left then
                        left_units[#left_units + 1] = slot.left
                    end
                end
                if #left_units > 0 then
                    -- Inventory preview path: only weapon_skin items carry an
                    -- illusion context. Base weapons here would just be
                    -- displayed as-is without our override.
                    local has_skin = item_data.item_type == "weapon_skin"
                    _apply_la_offhand_to_units(world, item_data, left_units, has_skin)
                end
            end
        end
    end

    local career_name = self._character_name or (self._profile and self._profile.name) or _local_career_name()
    if not career_name then return end

    local weapon_key = item_name
    local overrides = _weapon_scale_overrides[weapon_key]
    if not overrides then return end

    local scale_factor = _resolve_for_career(overrides, career_name)
    if not scale_factor then return end
    if type(scale_factor) == "function" then
        scale_factor = scale_factor(function(id) return mod:get(id) end)
        if not scale_factor then return end
    end
    local scale
    if type(scale_factor) == "table" then
        scale = Vector3(scale_factor[1], scale_factor[2], scale_factor[3])
    else
        scale = Vector3(scale_factor, scale_factor, scale_factor)
    end

    local fields = overrides._fields
    local right_only = false
    if fields then
        for _, f in ipairs(fields) do
            if f:find("right") then right_only = true; break end
        end
    end

    local equip_units = self._equipment_units
    if not equip_units then return end
    for slot_idx, slot in pairs(equip_units) do
        if type(slot) == "table" then
            if not right_only and slot.left and _is_unit(slot.left) then
                pcall(Unit.set_local_scale, slot.left, 0, scale)
            end
            if slot.right and _is_unit(slot.right) then
                pcall(Unit.set_local_scale, slot.right, 0, scale)
            end
        end
    end
end

local function _spawn_item_wrapper(func, self, item_name, spawn_data)
    local is_direct_clone = LA_BRIDGE.registered and item_name and LA_BRIDGE.backend_to_armoury[item_name]
    mod:info("[LA preview] _spawn_item name=%s direct=%s", tostring(item_name), tostring(is_direct_clone ~= nil))
    if is_direct_clone then
        self._cos_la_spawning = item_name
        mod:info("[LA preview]   -> spawning clone %s", item_name)
    end
    local result = func(self, item_name, spawn_data)
    self._cos_la_spawning = nil
    _spawn_item_post(self, item_name, spawn_data)
    return result
end

mod:hook("HeroPreviewer", "_spawn_item", _spawn_item_wrapper)
mod:hook("MenuWorldPreviewer", "_spawn_item", _spawn_item_wrapper)

-- Illusion/skin browser preview (LootItemUnitPreviewer)
-- NOTE: must use mod:hook (not hook_safe) so we can capture the returned
-- `units` array. The caller (`_on_packages_loaded`) only assigns
-- `self._spawned_units = units` AFTER spawn_units returns, so reading
-- `self._spawned_units` from inside a hook_safe sees stale or nil data.
mod:hook("LootItemUnitPreviewer", "spawn_units", function(func, self, spawn_data)
    local units = func(self, spawn_data)

    local item = self._item
    if not item then return units end
    local item_data = item.data
    local weapon_key = (item_data and item_data.key) or item.key
    if not weapon_key then return units end

    -- LA offhand paint: spawn order is left (shield) = index 1, right (weapon) = index 2.
    -- Use the freshly-returned `units` array, not self._spawned_units (not yet assigned).
    -- Only paint when the previewed item carries an illusion context (it's a
    -- weapon_skin entry, OR the previewer was given a skin via item.skin).
    do
        local world = self._background_world or self._world or self.world
        local has_skin = (item.skin and item.skin ~= "")
                or (item_data and item_data.item_type == "weapon_skin")
        if has_skin and world and item_data and units and units[1] then
            _apply_la_offhand_to_units(world, item_data, { units[1] }, true)
        end
    end

    -- Skin keys (e.g. "es_bastard_sword_skin_01") won't match — resolve to weapon key
    local overrides = _weapon_scale_overrides[weapon_key]
    if not overrides and ItemMasterList then
        local master = ItemMasterList[weapon_key]
        if master and master.matching_item_key then
            weapon_key = master.matching_item_key
            overrides = _weapon_scale_overrides[weapon_key]
        end
    end
    if not overrides then return units end

    local career_name = self._career_name_override or _local_career_name()
    local scale_factor = _resolve_for_career(overrides, career_name)
    if not scale_factor then return units end
    if type(scale_factor) == "function" then
        scale_factor = scale_factor(function(id) return mod:get(id) end)
        if not scale_factor then return units end
    end
    local scale
    if type(scale_factor) == "table" then
        scale = Vector3(scale_factor[1], scale_factor[2], scale_factor[3])
    else
        scale = Vector3(scale_factor, scale_factor, scale_factor)
    end

    local fields = overrides._fields
    if not units then return units end

    if not fields then
        for _, unit in ipairs(units) do
            if _is_unit(unit) then pcall(Unit.set_local_scale, unit, 0, scale) end
        end
    else
        local right_only = false
        for _, f in ipairs(fields) do
            if f:find("right") then right_only = true; break end
        end
        -- spawn order: left (shield) = index 1, right (weapon) = index 2
        if right_only and spawn_data and #spawn_data >= 2 then
            local unit = units[2]
            if unit and _is_unit(unit) then pcall(Unit.set_local_scale, unit, 0, scale) end
        else
            for _, unit in ipairs(units) do
                if _is_unit(unit) then pcall(Unit.set_local_scale, unit, 0, scale) end
            end
        end
    end

    return units
end)

-- ============================================================
-- Loremaster's Armoury bridge (Phase 1)
-- ============================================================
-- Registers LA's recolored cosmetics as separate inventory items via MIL,
-- and queues their texture swap into LA's existing apply pipeline. See
-- _la_bridge.lua for details.

local _la_bridge_init_done       = false
local _la_skin_safety_done       = false
mod.loadout_cache                = mod.loadout_cache or {}

-- Mirrors AllHats lines 38-71: cache custom slot_skin loadouts locally so
-- they're never synced to other clients (vanilla clients crash on unknown
-- skin backend_ids).
local function _install_skin_loadout_safety()
    if _la_skin_safety_done then return end
    if not (Managers.backend and Managers.backend._interfaces and Managers.backend._interfaces["items"]) then return end
    if not BackendUtils then return end
    _la_skin_safety_done = true

    local items_iface = Managers.backend:get_interface("items")

    mod:hook(BackendUtils, "set_loadout_item", function(func, backend_id, career_name, slot_name)
        local is_clone = LA_BRIDGE.backend_to_armoury[backend_id]
        if is_clone and (slot_name == "slot_hat" or slot_name == "slot_skin") then
            mod.loadout_cache[career_name] = mod.loadout_cache[career_name] or {}
            mod.loadout_cache[career_name][slot_name] = backend_id
            mod:info("[loadout] CACHED %s %s = %s", career_name, slot_name, backend_id)
            return
        end
        if (slot_name == "slot_hat" or slot_name == "slot_skin") and mod.loadout_cache[career_name] then
            mod:info("[loadout] CLEARED cache %s %s (vanilla bid=%s)", career_name, slot_name, backend_id)
            mod.loadout_cache[career_name][slot_name] = nil
        end
        return func(backend_id, career_name, slot_name)
    end)

    mod:hook(items_iface, "get_loadout", function(func, self)
        local loadout = func(self)
        if LA_BRIDGE.registered then
            local all_items = nil
            for career_name, slots in pairs(loadout) do
                if type(slots) == "table" then
                    for slot_name, bid in pairs(slots) do
                        if LA_BRIDGE.backend_to_armoury[bid] and not (mod.loadout_cache[career_name] and mod.loadout_cache[career_name][slot_name]) then
                            all_items = all_items or items_iface:get_all_backend_items()
                            local vanilla_key = LA_BRIDGE.backend_to_vanilla[bid]
                            for vbid, item in pairs(all_items or {}) do
                                if item.key == vanilla_key and not LA_BRIDGE.backend_to_armoury[vbid] then
                                    slots[slot_name] = vbid
                                    break
                                end
                            end
                        end
                    end
                end
            end
        end
        for career_name, slots in pairs(mod.loadout_cache) do
            loadout[career_name] = loadout[career_name] or {}
            for slot_name, backend_id in pairs(slots) do
                loadout[career_name][slot_name] = backend_id
            end
        end
        return loadout
    end)

    mod:hook(items_iface, "get_loadout_item_id", function(func, self, career_name, slot_name)
        if mod.loadout_cache[career_name] and mod.loadout_cache[career_name][slot_name] then
            return mod.loadout_cache[career_name][slot_name]
        end
        local raw = func(self, career_name, slot_name)
        if raw and LA_BRIDGE.registered and LA_BRIDGE.backend_to_armoury[raw] then
            local vanilla_key = LA_BRIDGE.backend_to_vanilla[raw]
            if vanilla_key then
                local all_items = items_iface:get_all_backend_items()
                for bid, item in pairs(all_items or {}) do
                    if item.key == vanilla_key and not LA_BRIDGE.backend_to_armoury[bid] then
                        mod:info("[loadout] redirected server clone %s -> vanilla %s (%s)", raw, bid, vanilla_key)
                        return bid
                    end
                end
            end
        end
        return raw
    end)

    mod:hook(items_iface, "get_item_rarity", function(func, self, backend_id)
        local la_key = LA_BRIDGE.backend_to_armoury[backend_id]
        if la_key then
            if la_key:match("_white$") or la_key:match("_Purified$") then
                return "unique"
            end
            return "promo"
        end
        return func(self, backend_id)
    end)

    local function _fixup_server_clones()
        local all_items = items_iface:get_all_backend_items()
        if not all_items then return end
        local raw_loadout = (function()
            local save = mod.loadout_cache; mod.loadout_cache = {}
            local l = items_iface:get_loadout(); mod.loadout_cache = save; return l
        end)()
        for career_name, slots in pairs(raw_loadout or {}) do
            if type(slots) == "table" then
                for slot_name, bid in pairs(slots) do
                    if LA_BRIDGE.backend_to_armoury[bid] then
                        local vanilla_key = LA_BRIDGE.backend_to_vanilla[bid]
                        for vbid, item in pairs(all_items) do
                            if item.key == vanilla_key and not LA_BRIDGE.backend_to_armoury[vbid] then
                                mod:info("[loadout] fixup server: %s %s clone %s -> vanilla %s", career_name, slot_name, bid, vbid)
                                local orig_hook = BackendUtils.set_loadout_item
                                local iface = Managers.backend:get_loadout_interface_by_slot(slot_name)
                                if iface then iface:set_loadout_item(vbid, career_name, slot_name) end
                                break
                            end
                        end
                    end
                end
            end
        end
    end
    _fixup_server_clones()
end

-- VMF calls mod.update once per frame.
mod.update = function(dt)
    if not _la_bridge_init_done then
        if mod:get("la_bridge_enable")
           and ItemMasterList
           and get_mod("Loremasters-Armoury")
           and get_mod("MoreItemsLibrary") then
            LA_BRIDGE.register_all()
            LA_BRIDGE.install_apply_gate()
            _merge_la_offhand_options()
            _la_bridge_init_done = true
        end
    end
    if _la_bridge_init_done then _install_skin_loadout_safety() end
end

-- Spawn pipeline: detect units that match one of our cloned items and push
-- them into LA's queue. AttachmentUtils is a global table so we hook with
-- table form (string form would never resolve).
if rawget(_G, "AttachmentUtils") then
    mod:hook_safe(AttachmentUtils, "link", function(world, source, target, node_linking)
        if not LA_BRIDGE.registered then return end
        if type(target) ~= "userdata" then return end
        if not Unit.has_data(target, "unit_name") then return end
        LA_BRIDGE.maybe_queue_unit(world, target, Unit.get_data(target, "unit_name"))
    end)
end

-- LA hooks World.link_unit too — some hats are linked via the lower-level
-- World API rather than AttachmentUtils. Cover both. World.link_unit signature:
-- World.link_unit(world, child_unit, child_node, parent_unit, parent_node)
if rawget(_G, "World") and World.link_unit then
    mod:hook_safe(World, "link_unit", function(world, child_unit, child_node, parent_unit, parent_node)
        if not LA_BRIDGE.registered then return end
        if type(child_unit) ~= "userdata" then return end
        if not Unit.alive(child_unit) then return end
        if not Unit.has_data(child_unit, "unit_name") then return end
        LA_BRIDGE.maybe_queue_unit(world, child_unit, Unit.get_data(child_unit, "unit_name"))
    end)
end

local function _spawn_item_unit_la_hook(self, unit)
    if not LA_BRIDGE.registered then return end
    if type(unit) ~= "userdata" then return end

    local world = self._world or self.world
    local spawning = self._cos_la_spawning
    mod:info("[LA preview] _spawn_item_unit spawning=%s world=%s", tostring(spawning), tostring(world))
    if spawning then
        local ok = LA_BRIDGE.queue_unit_direct(world, unit, spawning)
        mod:info("[LA preview]   queue_unit_direct result=%s", tostring(ok))
        return
    end

    if Unit.has_data(unit, "unit_name") then
        LA_BRIDGE.maybe_queue_unit(world, unit, Unit.get_data(unit, "unit_name"))
    else
        LA_BRIDGE.suppress_orphan(unit)
    end
end

mod:hook_safe("HeroPreviewer", "_spawn_item_unit", _spawn_item_unit_la_hook)
mod:hook_safe("MenuWorldPreviewer", "_spawn_item_unit", _spawn_item_unit_la_hook)

mod:command("la_dump", "List LA-bridge cloned items", function() LA_BRIDGE.debug_dump() end)

mod:command("la_trace", "Toggle LA-bridge hook tracing (1/0)", function(arg)
    LA_BRIDGE.trace = (arg == "1" or arg == "on" or arg == "true")
    mod:echo("[la_bridge] trace = " .. tostring(LA_BRIDGE.trace))
end)

mod:command("la_force", "Force-apply LA variant to equipped hat. Usage: cos la_force <armoury_key>", function(armoury_key)
    if not armoury_key then mod:echo("usage: cos la_force <armoury_key>"); return end
    LA_BRIDGE.force_apply(armoury_key)
end)

mod:command("la_attach", "Dump player attachments (unit_name/skin_name/hand_unit per node)", function()
    LA_BRIDGE.dump_player_attachments()
end)

mod:command("la_loadout", "Dump current loadout for diagnostic", function()
    if not Managers.backend then mod:echo("no backend"); return end
    local items_iface = Managers.backend:get_interface("items")
    if not items_iface then mod:echo("no items iface"); return end

    mod:echo("[la_loadout] gate_installed=%s bridge_active=%s registered=%s",
        tostring(LA_BRIDGE._gate_installed), tostring(LA_BRIDGE._bridge_active), tostring(LA_BRIDGE.registered))
    mod:echo("[la_loadout] loadout_cache entries: %d", (function()
        local n = 0; for _ in pairs(mod.loadout_cache) do n = n + 1 end; return n end)())

    local loadout = items_iface:get_loadout()
    for career, slots in pairs(loadout or {}) do
        if type(slots) == "table" and slots.slot_hat then
            local hat_id = slots.slot_hat
            local is_clone = LA_BRIDGE.backend_to_armoury[hat_id] ~= nil
            mod:echo("  %s slot_hat = %s (clone=%s)", career, tostring(hat_id), tostring(is_clone))
            if is_clone then
                mod:echo("    -> armoury=%s vanilla=%s", tostring(LA_BRIDGE.backend_to_armoury[hat_id]), tostring(LA_BRIDGE.backend_to_vanilla[hat_id]))
            end
        end
    end

    local n_clones = 0
    for _ in pairs(LA_BRIDGE.backend_to_armoury) do n_clones = n_clones + 1 end
    mod:echo("[la_loadout] %d clones registered", n_clones)

    local LA = get_mod("Loremasters-Armoury")
    if LA then
        local pq, aq, lq = 0, 0, 0
        if LA.preview_queue then for _ in pairs(LA.preview_queue) do pq = pq + 1 end end
        if LA.armory_preview_queue then for _ in pairs(LA.armory_preview_queue) do aq = aq + 1 end end
        if LA.level_queue then for _ in pairs(LA.level_queue) do lq = lq + 1 end end
        mod:echo("[la_loadout] LA queues: preview=%d armory=%d level=%d", pq, aq, lq)
    end
end)

mod:command("la_hats", "List all hat items for the current career (vanilla vs clone)", function()
    if not Managers.backend then mod:echo("no backend"); return end
    local items_iface = Managers.backend:get_interface("items")
    if not items_iface then mod:echo("no items iface"); return end

    local career_name = _local_career_name()
    mod:echo("[la_hats] career=%s", tostring(career_name))

    local all_items = items_iface:get_all_backend_items()
    if not all_items then mod:echo("[la_hats] no items"); return end

    local equipped_hat_bid = nil
    if items_iface.get_loadout_item_id then
        equipped_hat_bid = items_iface:get_loadout_item_id(career_name, "slot_hat")
    end

    local n_vanilla, n_clone = 0, 0
    for bid, item in pairs(all_items) do
        local data = item.data or (ItemMasterList and rawget(ItemMasterList, item.key or bid))
        if data and data.slot_type == "hat" then
            local can = data.can_wield
            local wieldable = false
            if can then
                for _, c in ipairs(can) do
                    if c == career_name then wieldable = true; break end
                end
            end
            if wieldable then
                local is_clone = LA_BRIDGE.backend_to_armoury[bid] ~= nil
                local rarity = item.rarity or (data and data.rarity) or "?"
                local key = item.key or "?"
                local eq = (bid == equipped_hat_bid) and " [EQUIPPED]" or ""
                if is_clone then
                    n_clone = n_clone + 1
                    mod:echo("  CLONE  bid=%s rarity=%s ak=%s%s", bid, rarity, tostring(LA_BRIDGE.backend_to_armoury[bid]), eq)
                else
                    n_vanilla = n_vanilla + 1
                    mod:echo("  VANILLA bid=%s key=%s rarity=%s%s", bid, key, rarity, eq)
                end
                mod:info("[la_hats] bid=%s key=%s rarity=%s clone=%s eq=%s", bid, key, rarity, tostring(is_clone), eq)
            end
        end
    end
    mod:echo("[la_hats] %d vanilla + %d clones for %s", n_vanilla, n_clone, tostring(career_name))

    local cache_hat = mod.loadout_cache[career_name] and mod.loadout_cache[career_name]["slot_hat"]
    mod:echo("[la_hats] cache slot_hat=%s (is_clone=%s)", tostring(cache_hat), tostring(cache_hat and LA_BRIDGE.backend_to_armoury[cache_hat] ~= nil))
    mod:echo("[la_hats] gate_installed=%s", tostring(LA_BRIDGE._gate_installed))

    local raw_bid = nil
    if items_iface.get_loadout_item_id then
        local save = mod.loadout_cache
        mod.loadout_cache = {}
        raw_bid = items_iface:get_loadout_item_id(career_name, "slot_hat")
        mod.loadout_cache = save
    end
    mod:echo("[la_hats] raw server slot_hat=%s", tostring(raw_bid))

    _flush_log()
end)
