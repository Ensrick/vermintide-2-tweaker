local mod = get_mod("cosmetics_tweaker")
local U = mod:dofile("scripts/mods/cosmetics_tweaker/_cosmetic_unlocks")
local LA_BRIDGE = mod:dofile("scripts/mods/cosmetics_tweaker/_la_bridge")

local MOD_VERSION = "0.8.47-dev"
mod:info("Cosmetics Tweaker v%s loaded", MOD_VERSION)
mod:echo("Cosmetics Tweaker v" .. MOD_VERSION)

-- ============================================================
-- TEMP DIAGNOSTIC — World.spawn_unit logging for offhand crash
-- ============================================================
-- The "Unit not found #ID[9405eeb80a227a76]" crash has persisted across
-- v0.7.81–v0.7.91 despite progressively more defensive gates. The hash
-- isn't directly decodable, and we never confirmed which unit name is
-- actually failing. This hook logs every World.spawn_unit attempt with
-- a counter, so the LAST line in Console.log before the assertion is
-- the unit name that crashed. Remove once we have the data.
local _spawn_trace_count = 0
local _spawn_trace_max = 500  -- safety: don't spam if a loop spawns 1000s
if World and type(World.spawn_unit) == "function" then
    mod:hook(World, "spawn_unit", function(func, world, unit_name, ...)
        _spawn_trace_count = _spawn_trace_count + 1
        if _spawn_trace_count <= _spawn_trace_max then
            mod:info("[SPAWN_TRACE #%d] World.spawn_unit name=%s",
                _spawn_trace_count, tostring(unit_name))
        end
        return func(world, unit_name, ...)
    end)
end
if World and type(World.spawn_unit_with_position) == "function" then
    mod:hook(World, "spawn_unit_with_position", function(func, world, unit_name, position, ...)
        _spawn_trace_count = _spawn_trace_count + 1
        if _spawn_trace_count <= _spawn_trace_max then
            mod:info("[SPAWN_TRACE #%d] World.spawn_unit_with_position name=%s",
                _spawn_trace_count, tostring(unit_name))
        end
        return func(world, unit_name, position, ...)
    end)
end
mod:command("spawn_trace_reset", "Reset SPAWN_TRACE counter", function()
    _spawn_trace_count = 0
    mod:echo("[SPAWN_TRACE] counter reset to 0")
end)

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
-- CLARIFY: this function MUST stay near the top of the file. v0.7.1 / v0.7.10
-- both crashed because forward references to it broke when callers were
-- defined above. See feedback_lua_forward_reference.md.
local function _skin_requires_unowned_dlc(skin_key)
    -- rawget required: ItemMasterList.__index calls Crashify on unknown keys
    -- (item_master_list.lua:133). LA bridge entries appear in WeaponSkins.skins
    -- but NOT in ItemMasterList — bracket access on those would crash.
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

-- Dump localized name + description for EVERY skin in WeaponSkins.skins.
-- Used to fill in the gaps in cosmetics_tweaker/VETERAN_SKIN_CATALOG.md — the
-- per-template dumps only sampled 8 per rarity, leaving ~560 names unresolved.
-- This dump emits ALL ~1013 entries with per-batch flushing to avoid the
-- truncation bug. Output tag: [DUMP:names]. Pipe-delimited so the catalog
-- builder script can grep it directly.
mod:command("dump_all_names", "Dump skin_key|name|desc|rarity|tpl for every WeaponSkins.skins entry", function()
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
    -- Stable iteration order so re-runs diff cleanly. Sort skin keys.
    local keys = {}
    for k in pairs(WeaponSkins.skins) do keys[#keys+1] = k end
    table.sort(keys)
    mod:info("[DUMP:names] === %d total skins ===", #keys)
    _flush_log()
    -- Tight flush cadence: prior runs at FLUSH_EVERY=100 still lost ~108 lines
    -- (the alphabetically-last `wh_*` tail). At 20 we get more flush calls but
    -- they're cheap and the buffer doesn't accumulate enough to drop lines.
    local FLUSH_EVERY = 20
    for i, k in ipairs(keys) do
        local d = WeaponSkins.skins[k]
        if type(d) == "table" then
            mod:info("[DUMP:names] NAME|key=%s|name=%q|desc=%q|rarity=%s|tpl=%s",
                k,
                tostring(loc(d.display_name)),
                tostring(loc(d.description)),
                tostring(d.rarity),
                tostring(d.material_settings_name))
        end
        if i % FLUSH_EVERY == 0 then _flush_log() end
    end
    _flush_log()
    mod:echo("[dump_all_names] %d skins dumped (search [DUMP:names])", #keys)
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
        -- rawget: ItemMasterList __index crashifies on missing keys; some U.managed
        -- entries may reference items that don't exist on this user's install (DLC ownership).
        local item = rawget(ItemMasterList, item_key)
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
end
mod.on_setting_changed = function(setting_id)
    if setting_id and setting_id:sub(1, 11) == "cos_unlock_" then
        apply_cosmetic_unlocks()
    end
    -- Glow override no longer auto-repaints on setting change — the walk
    -- destabilized adjacent unit state (hand meshes disappeared after pressing
    -- X to inspect, 1P breakage). User re-equips the weapon to see the new
    -- preset; the apply_material_settings hook paints reliably at spawn.
end
-- CLARIFY: Ctrl+Shift+R (hot-reload) is UNSAFE for cosmetics_tweaker — see
-- feedback_hot_reload_unfixable.md. Engine holds C++ resource locks on
-- spawned units / loaded materials that Lua can't release. Do NOT add a
-- mod.on_reload handler that pretends to clean up; it would mislead users
-- into thinking hot-reload is safe.
mod.on_unload = function()
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
-- ---------------------------------------------------------------------------
-- VISUAL OVERRIDES — TWO DIFFERENT SCHEMAS, INTENTIONALLY
-- ---------------------------------------------------------------------------
-- 1) Scale overrides:  keyed by UNIT PATH SUBSTRING. Match against the actual
--    model the engine loads (skin's right/left_hand_unit if a skin is equipped,
--    falling back to the item's own paths). This targets the MODEL, not the
--    item template, so:
--      - vanilla `es_bastard_sword` with any Bretonian skin       → matches
--      - `es_sword_shield_breton` (paired with shield)            → matches (right hand only)
--      - character_weapon_variants Imperial Longsword             → does NOT match
--        (uses bastard_sword_template but loads `wpn_2h_sword_*` model)
--      - any third-party item that swaps to a Bretonian model     → matches
--
-- 2) Grip-offset overrides: keyed by ITEM NAME and CAREER PREFIX. These adjust
--    `Unit.local_position` (Z axis is along the blade — see
--    `feedback_grip_offset_sign.md`: +Z lowers grip, -Z raises grip).
--
-- COVERAGE: scale runs on all three rendering paths (in-game / inventory
-- preview / illusion browser). Grip-offset runs ONLY on the in-game
-- GearUtils hook, intentionally — see `feedback_grip_offset_sign.md`
-- "preview shows un-offset weapon".
--
-- See "Three Rendering Paths" in DEVELOPMENT.md for the hook list and
-- `_spawn_item_post` / `LootItemUnitPreviewer.spawn_units` hooks below.

-- Toggle-gated factor function. Returns the {x,y,z} scale when the user has
-- enabled the Bretonian Longsword "thiccc" option in cosmetics_tweaker_data,
-- nil otherwise. Called fresh each apply so live setting changes take effect
-- without re-spawning.
local function _breton_sword_thiccc(get)
    if get("es_bastard_sword_thiccc") then
        return { 0.65, 1.0, 1.0 }
    end
    return nil
end

-- Unit-path scale entries. Schema:
--   pattern : literal substring matched via string.find(path, pattern, 1, true)
--   factor  : function(get) -> {x,y,z}|number|nil  OR  literal {x,y,z} OR number
--   hand    : "right" | "left" | nil (nil = both hands)
local _unit_path_scale_overrides = {
    {
        -- Bretonian Longsword model family. Covers wpn_emp_gk_sword_01_t1,
        -- _01_t2, _02_t1, _02_t2 plus their _runed_* and _magic_* variants.
        -- Used by ItemMasterList entries `es_bastard_sword` (and skins) and
        -- the right-hand sword of `es_sword_shield_breton` (paired with a
        -- GK shield in the left hand — `hand = "right"` keeps the shield
        -- at native scale).
        pattern = "wpn_emp_gk_sword_",
        factor  = _breton_sword_thiccc,
        hand    = "right",
    },
}

-- Grip-offset table. Keyed by weapon item-key, values are
-- { <career_prefix> = {x, y, z}, _default = {x, y, z} } where Z is along the
-- blade. EMPTY today — kept as the extension point. See
-- `feedback_grip_offset_sign.md` for sign convention (+Z lowers grip).
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

        local weapon_data = rawget(ItemMasterList, illusion.matching_weapon)
        if weapon_data and weapon_data.skin_combination_table then
            local combos = WeaponSkins.skin_combinations[weapon_data.skin_combination_table]
            if combos then
                local tier = combos[illusion.rarity] or combos.exotic or combos.common
                if tier then
                    tier[#tier + 1] = skin_key
                end
            end
        end

        -- CLARIFY: rawget is required because NetworkLookup.weapon_skins has
        -- a __index metatable that errors on missing keys (per v0.6.23 fix).
        -- Same class as ItemMasterList. Do NOT change to plain bracket lookup.
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

-- ============================================================
-- LA Shield Skin Injection (Phase 1)
-- ============================================================
-- LA shields registered as first-class VT2 skins per (LA shield × weapon
-- type) pair. Each combo becomes a real entry in ItemMasterList,
-- WeaponSkins.skins, and the appropriate skin_combinations table — same
-- pipeline `_register_custom_illusions` already uses for the existing
-- `ct_*` cross-character illusions.
--
-- Why this replaces the older runtime-override approach:
--   1. PER-WEAPON-INSTANCE. Vanilla's `craftingApplySkin2` writes
--      `item.skin = skin_key` onto the specific backend item. Selection
--      no longer leaks across weapons that share `item_type` (e.g.
--      modded CWV imperial sword+shield no longer renders Reiland just
--      because the user picked Reiland on a different Bret weapon).
--   2. STANDARD APPLY UI. Skins appear in the row-1 illusion grid; user
--      picks them like any other illusion. No separate row-2 widget,
--      no parallel "_offhand_selection" state machine.
--   3. CUSTOMIZATION PREVIEW USES VANILLA SPAWN PATH. Vanilla apply →
--      previewer respawn with the skin's `left_hand_unit` and
--      `right_hand_unit` — the same code path that successfully renders
--      every other custom illusion. Our v0.8.12 short-circuit handles
--      LA-bundled paths in the load_package gate.
--
-- Each spec needs: skin_key (must be unique), matching_weapon (a vanilla
-- weapon item_type), left_hand_unit (LA's mesh path), display_name_key
-- (looked up via _custom_loc by the Localize hook). right_hand_unit,
-- display_unit, template, and can_wield are inherited from the vanilla
-- weapon's default skin so the right side of the weapon is preserved.

local _la_shield_skin_specs = {
    -- Phase 1 PROOF: Reiland (Empire shield 01 mesh) on the Bret
    -- longsword+shield. Verify this displays correctly across all four
    -- spawn paths (in-game body, inventory mannequin, customization
    -- preview, illusion browser) before extending to all 4 weapon types
    -- and the rest of the LA shield catalogue.
    {
        skin_key         = "la_kruber_empire_shield_basic1_breton",
        matching_weapon  = "es_1h_sword_shield_breton",
        left_hand_unit   = "units/empire_shield/Kruber_Empire_shield01_mesh",
        display_name     = "Empire Shield 01 (LA)",
        rarity           = "exotic",
    },
}

local function _get_weapon_default_skin(weapon_key)
    if not WeaponSkins or not WeaponSkins.default_skins then return nil end
    local default_skin_key = WeaponSkins.default_skins[weapon_key]
    if not default_skin_key then return nil end
    return WeaponSkins.skins and WeaponSkins.skins[default_skin_key] or nil
end

local function _register_la_shield_skin(spec)
    if not ItemMasterList or not WeaponSkins then return end
    local skin_key = spec.skin_key
    if _custom_skin_keys[skin_key] then return end

    local weapon_data = rawget(ItemMasterList, spec.matching_weapon)
    if not weapon_data then
        mod:info("[LA skin] missing weapon %s; cannot register %s",
            spec.matching_weapon, skin_key)
        return
    end

    -- Inherit everything from the weapon's default skin EXCEPT left_hand_unit
    -- (LA's mesh) so the weapon's right side is unchanged.
    local default_skin = _get_weapon_default_skin(spec.matching_weapon)
    local right_hand_unit = (default_skin and default_skin.right_hand_unit)
                            or weapon_data.right_hand_unit
    local display_unit = (default_skin and default_skin.display_unit)
                         or weapon_data.display_unit
    local template = (default_skin and default_skin.template)
                     or weapon_data.template
    local can_wield = weapon_data.can_wield

    local rarity = spec.rarity or "exotic"
    local description_key = skin_key .. "_description"

    ItemMasterList[skin_key] = {
        item_type         = "weapon_skin",
        slot_type         = "weapon_skin",
        matching_item_key = spec.matching_weapon,
        rarity            = rarity,
        display_name      = skin_key .. "_name",
        description       = description_key,
        display_unit      = display_unit,
        hud_icon          = "weapon_generic_icon_staff_3",
        inventory_icon    = spec.inventory_icon or "icon_wpn_empire_shield_01_t1_mace",
        information_text  = "information_weapon_skin",
        right_hand_unit   = right_hand_unit,
        left_hand_unit    = spec.left_hand_unit,
        template          = template,
        can_wield         = can_wield,
    }

    WeaponSkins.skins[skin_key] = {
        description     = description_key,
        display_name    = skin_key .. "_name",
        display_unit    = display_unit,
        hud_icon        = "weapon_generic_icon_staff_3",
        inventory_icon  = spec.inventory_icon or "icon_wpn_empire_shield_01_t1_mace",
        rarity          = rarity,
        right_hand_unit = right_hand_unit,
        left_hand_unit  = spec.left_hand_unit,
        template        = template,
    }

    if weapon_data.skin_combination_table then
        local combos = WeaponSkins.skin_combinations[weapon_data.skin_combination_table]
        if combos then
            local tier = combos[rarity] or combos.exotic or combos.common
            if tier then
                tier[#tier + 1] = skin_key
            end
        end
    end

    if NetworkLookup and NetworkLookup.weapon_skins
        and not rawget(NetworkLookup.weapon_skins, skin_key)
    then
        local tbl = NetworkLookup.weapon_skins
        tbl[#tbl + 1] = skin_key
        tbl[skin_key] = #tbl
    end

    _custom_skin_keys[skin_key] = true
    mod:info("[LA skin] registered %s for %s -> mesh=%s right=%s",
        skin_key, spec.matching_weapon, spec.left_hand_unit, tostring(right_hand_unit))
end

local function _register_all_la_shield_skins()
    for _, spec in ipairs(_la_shield_skin_specs) do
        _register_la_shield_skin(spec)
    end
end

-- v0.8.31 REVERT: skin injection put LA shields in the row-1 illusion
-- grid where applying them swaps the WHOLE weapon visual (left+right
-- bundled). User wants row-2 offhand picker behavior — shield
-- independent of main weapon. Skin injection collapses that distinction.
-- The registration code stays here for future reference / a different
-- design but is not invoked. Row-2 picker (`_merge_la_offhand_options`)
-- is restored as the LA surface.
-- _register_all_la_shield_skins()

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
for _, spec in ipairs(_la_shield_skin_specs) do
    _custom_loc[spec.skin_key .. "_name"] = spec.display_name
end
for _, illusion in ipairs(_custom_illusions) do
    _custom_loc[illusion.skin_key .. "_name"] = illusion.display_name
    -- Don't shadow the `_description` entries written in
    -- cosmetics_tweaker_localization.lua. Letting that key fall through
    -- to the vanilla localizer means tooltips show the descriptive text
    -- (e.g. "An Empire mace paired with a Bretonnian shield.") rather
    -- than the title repeated.
end

mod:hook(_G, "Localize", function(func, key, ...)
    -- CLARIFY: hook order matters — _custom_loc takes priority over
    -- LA_BRIDGE.localization, which in turn precedes the vanilla
    -- localizer. If a key collides between custom illusion and LA bridge,
    -- the illusion wins. Today there's no overlap (ct_* vs *_LA_*).
    local custom = _custom_loc[key]
    if custom then return custom end
    local la_loc = LA_BRIDGE.localization[key]
    if la_loc then return la_loc end
    return func(key, ...)
end)

-- ============================================================
-- Unlock All Portrait Frames (modded realm only)
-- ============================================================
-- Two-pronged injection so frames show up regardless of when the
-- player toggles the setting:
--
--   1) Pre-hook on `_create_fake_inventory_items` mutates the
--      `fake_inventory_items` table parameter BEFORE the original
--      runs, ensuring fake backend IDs are minted and registered
--      into `_inventory_items`. This is the path that actually
--      makes frames show up in the UI's filtered item list.
--
--   2) Safe hook on `get_unlocked_cosmetics` keeps the table in
--      sync for any later callers that re-query (e.g. UI tooltips,
--      profile views) without going through fake inventory.
--
-- Note: `get_unlocked_cosmetics` is called once at PlayFab login
-- (inventory_request_cb). If the user toggles the setting AFTER
-- that, `_create_fake_inventory_items` won't re-run automatically,
-- so the toggle requires a full restart to take effect — the (1)
-- pre-hook still runs at next login. Documented in CHANGELOG.
--
-- DLC ownership is respected via required_dlc checks.

local _frame_inject_stats = { last_added = 0, last_skipped_dlc = 0, hook_fired = 0 }

local function _inject_all_frames(target)
    if not target then return 0, 0 end
    local added, skipped = 0, 0
    for key, data in pairs(ItemMasterList) do
        if data.item_type == "frame" and target[key] == nil then
            if _skin_requires_unowned_dlc(key) then
                skipped = skipped + 1
            else
                target[key] = true
                added = added + 1
            end
        end
    end
    return added, skipped
end

-- IMPORTANT: hook the DERIVED class, not `PlayFabMirrorBase`.
-- foundation\scripts\util\class.lua:51-57 copies parent methods into the
-- child table at class-definition time (no __index chaining). The runtime
-- instance is `PlayFabMirrorAdventure`, which holds its OWN copies of these
-- functions. Hooking the base class wraps a function value the runtime never
-- reaches, so the hook never fires (verified empirically: cos frames_status
-- showed "inject hook fired 0 time(s)" with the base-class hook). See log
-- 2026-05-06 02:41 for the diagnostic that surfaced this.

mod:hook("PlayFabMirrorAdventure", "_create_fake_inventory_items", function(func, self, fake_inventory_items, items_type)
    if items_type == "cosmetics"
       and mod:get("unlock_all_frames")
       and script_data["eac-untrusted"]
       and fake_inventory_items
    then
        local added, skipped = _inject_all_frames(fake_inventory_items)
        _frame_inject_stats.hook_fired = _frame_inject_stats.hook_fired + 1
        _frame_inject_stats.last_added = added
        _frame_inject_stats.last_skipped_dlc = skipped
        mod:info("[unlock_all_frames] _create_fake_inventory_items pre-hook fired: added=%d skipped_dlc=%d", added, skipped)
    end
    return func(self, fake_inventory_items, items_type)
end)

mod:hook_safe("PlayFabMirrorAdventure", "get_unlocked_cosmetics", function(self)
    if not mod:get("unlock_all_frames") or not script_data["eac-untrusted"] then return end
    local cosmetics = self._unlocked_cosmetics
    if not cosmetics then return end
    _inject_all_frames(cosmetics)
end)

mod:command("frames_status", "Diagnostic for the Unlock All Portrait Frames toggle.", function()
    local on = mod:get("unlock_all_frames")
    local modded = script_data and script_data["eac-untrusted"]
    mod:echo("[frames_status] toggle=%s modded_realm=%s", tostring(on), tostring(modded))
    mod:echo("[frames_status] inject hook fired %d time(s); last added=%d skipped_dlc=%d",
        _frame_inject_stats.hook_fired, _frame_inject_stats.last_added, _frame_inject_stats.last_skipped_dlc)

    local total_frames, dlc_locked = 0, 0
    for _, data in pairs(ItemMasterList) do
        if data.item_type == "frame" then
            total_frames = total_frames + 1
            if data.required_dlc and Managers.unlock and not Managers.unlock:is_dlc_unlocked(data.required_dlc) then
                dlc_locked = dlc_locked + 1
            end
        end
    end
    mod:echo("[frames_status] ItemMasterList: %d frames total, %d DLC-locked", total_frames, dlc_locked)

    local backend = Managers.backend
    local mirror = backend and backend._interfaces and backend._interfaces.mirror
                 or backend and backend.get_interface and backend:get_interface("items")
    local mirror_base
    if mirror and mirror._backend_mirror then mirror_base = mirror._backend_mirror end
    if not mirror_base and backend and backend._mirror then mirror_base = backend._mirror end
    if mirror_base and mirror_base._unlocked_cosmetics then
        local n = 0
        for k, _ in pairs(mirror_base._unlocked_cosmetics) do
            if rawget(ItemMasterList, k) and ItemMasterList[k].item_type == "frame" then n = n + 1 end
        end
        mod:echo("[frames_status] _unlocked_cosmetics contains %d frame entries", n)
    else
        mod:echo("[frames_status] could not locate PlayFabMirrorBase via Managers.backend")
    end

    local items_iface = backend and backend.get_interface and backend:get_interface("items")
    if items_iface and items_iface.get_filtered_items then
        local list = items_iface:get_filtered_items("slot_type == frame", {})
        mod:echo("[frames_status] backend get_filtered_items('slot_type == frame') returned %d items", list and #list or -1)
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

    -- ItemMasterList.__index Crashifies on unknown keys (item_master_list.lua:133),
    -- and skin_key here can be ANY key the illusion grid hands us — including
    -- LA bridge keys (live in WeaponSkins.skins, NOT in IML) and ct_* keys
    -- not yet registered. Use rawget to avoid the crashify.
    local iml_entry = rawget(ItemMasterList, skin_key)
    if _custom_skin_keys[skin_key] or (script_data["eac-untrusted"] and iml_entry and not _skin_requires_unowned_dlc(skin_key)) then
        local fake_id = "ct_fake_" .. skin_key
        _fake_skin_backend_ids[fake_id] = skin_key
        local fake_item = {
            skin = skin_key,
            ItemId = skin_key,
            data = iml_entry,
            key = skin_key,
            rarity = iml_entry and iml_entry.rarity or "exotic",
        }
        return fake_id, fake_item
    end
end)

mod:hook("HeroWindowItemCustomization", "_enable_craft_button", function(func, self, enable, disable_edges)
    if mod:get("apply_trace") then
        mod:info("[apply-trace] _enable_craft_button enable=%s recipe=%s skin_dirty=%s eac=%s",
            tostring(enable), tostring(self._current_recipe_name),
            tostring(self._skin_dirty), tostring(script_data["eac-untrusted"]))
    end
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
    local widget = self._illusion_widgets and self._illusion_widgets[index]
    if mod:get("apply_trace") then
        local picked_skin = widget and widget.content and widget.content.skin_key
        local current_item = self:_get_item(self._item_backend_id)
        local current_skin = current_item and current_item.skin
        if (not current_skin or current_skin == "") and current_item and current_item.backend_id and Managers and Managers.backend then
            local items_iface = Managers.backend:get_interface("items")
            if items_iface and items_iface.get_skin then
                current_skin = items_iface:get_skin(current_item.backend_id)
            end
        end
        local default_skin = current_item and current_item.key and WeaponSkins.default_skins[current_item.key]
        local effective_current = current_skin or default_skin
        mod:info("[apply-trace] _on_illusion_index_pressed picked=%s current=%s default=%s differs=%s ignore_spawn=%s locked=%s",
            tostring(picked_skin), tostring(current_skin), tostring(default_skin),
            tostring(picked_skin ~= effective_current), tostring(ignore_item_spawn),
            tostring(widget and widget.content and widget.content.locked))
    end

    if script_data["eac-untrusted"] and not ignore_item_spawn then
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
    -- Skip if the unit is already engine-resident via a resource_package
    -- loaded by another mod / the boot chain. LA loads
    -- `resource_packages/levels/dlcs/morris/wastes_common` and four
    -- similar globals — they CONTAIN the deus shields used by LA's
    -- Imperial Hero variants, but the deus shield meshes have no
    -- standalone `units/.../wpn_es_deus_shield_03.package`. Calling
    -- Managers.package:load on a non-existent package_name still writes
    -- to self._packages, so has_loaded subsequently lies — and the
    -- override fires for a unit that isn't actually in the resource
    -- manager → "Unit not found" assert in World.spawn_unit. The
    -- can_get("unit", ...) check is the engine's authoritative
    -- "spawnable?" answer regardless of which package provides the unit.
    if Application and Application.can_get and Application.can_get("unit", package_path) then
        _preloaded_offhand_packages[package_path] = true
        mod:info("[offhand] %s already engine-resident (no standalone load needed)", package_path)
        return
    end
    -- Don't try to load if no standalone .package file exists (avoids the
    -- phantom-entry crash described above).
    if Application and Application.can_get and not Application.can_get("package", package_path) then
        mod:info("[offhand] no standalone package at %s and unit not engine-resident — skipping preload", package_path)
        return
    end
    -- Sync load (async=false). Async returns immediately and races the
    -- user's Apply click — sync blocks via ResourcePackage.load + flush.
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

-- Defensive gate before applying a left_hand_unit override. Uses
-- Application.can_get("unit", ...) — the engine's authoritative answer
-- about whether World.spawn_unit will succeed, regardless of which
-- package (standalone or resource_package) provides the unit. Replaces
-- the old has_loaded check which lied for resource_package-resident
-- units that we'd phantom-loaded.
local function _override_package_ready(unit_path)
    if not unit_path or unit_path == "" then return false end
    if not Application or not Application.can_get then return false end
    if not Application.can_get("unit", unit_path) then return false end
    if not Application.can_get("unit", unit_path .. "_3p") then return false end
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
-- CLARIFY: keys in _offhand_options are `item_type` strings (the value of
-- ItemMasterList[key].item_type) — NOT IML keys. Each entry covers ALL
-- backend items that share that item_type. Verified against
-- item_master_list_carousel.lua: dr_1h_axe_shield, dr_1h_hammer_shield,
-- es_1h_sword_shield_breton, wh_flail_shield, wh_hammer_shield, es_deus_01
-- are real item_type values. The aliasing below makes both sides of each
-- pair share the same option list; mutations through one alias affect the
-- other (see seen_lists guard in _merge_la_offhand_options).
-- De-aliased copies. Vanilla offhand options are the same across these
-- weapon types, but LA shield options must be pooled per-weapon-type
-- (driven by each LA variant's `icons` table). Sharing one table reference
-- across weapon types would cross-pollinate Bret-authored LA textures onto
-- mace UVs and vice-versa.
local function _shallow_copy(t)
    local out = {}
    for i = 1, #t do out[i] = t[i] end
    return out
end
_offhand_options.es_1h_mace_shield          = _shallow_copy(_offhand_options.es_1h_sword_shield)
_offhand_options.es_1h_sword_shield_breton  = _shallow_copy(_offhand_options.es_1h_sword_shield)
_offhand_options.es_deus_01                 = _shallow_copy(_offhand_options.es_1h_sword_shield)
_offhand_options.dr_1h_hammer_shield        = _shallow_copy(_offhand_options.dr_1h_axe_shield)
_offhand_options.wh_hammer_shield           = _shallow_copy(_offhand_options.wh_flail_shield)

-- _offhand_selection[weapon_key] = option_table (the same object stored in
-- _offhand_options[weapon_key]). Vanilla entries have only `unit`; LA-bridge
-- entries have `la_armoury_key` + `vanilla_skin` (no `unit` — LA paints onto
-- whatever shield mesh the user's vanilla illusion provides).
--
-- v0.8.32 KEYING CHANGE: this table is now keyed by `backend_id`, not by
-- `item_type`. Item_type-keying caused selection to leak across all
-- weapons of the same type (Reiland on Bret weapon also showed up on a
-- modded CWV imperial sword+shield because both share `es_1h_sword_shield`
-- patterns through CWV's clone path). Backend_id is per-instance and
-- stable for the weapon's lifetime, so each weapon gets its own selection.
-- In-memory only this round; disk persistence via mod settings is a
-- follow-up. Variable name preserved to keep diffs minimal.
local _offhand_selection = {}

-- LA pool merge: each weapon_type pulls the LA shields whose `icons` table
-- specifically targets that weapon_type. The bridge does the icon-driven
-- bucketing; the merge here just appends each bucket to the matching
-- vanilla-offhand list. No cross-weapon-type leakage because each
-- _offhand_options[weapon_type] is now its own table (de-aliased above).
--
-- FOCUS GATE: per "one shield at a time" working policy, only the LA shield
-- whose armoury_key matches `_LA_FOCUS_KEYS[la_key] == true` surfaces in the
-- picker. Registration data in `_la_bridge.lua` (icon parsing, _LA_EXTRA_WEAPON_TYPES,
-- the alias map) stays intact, so widening the visible set later is a
-- one-line edit here. Set to nil/empty to surface every LA shield.
local _LA_FOCUS_KEYS = {
    Kruber_empire_shield_hero1_Ostermark01 = true,
    Kruber_empire_shield_hero1_Kotbs01     = true,
    -- v0.8.25: first kind="unit" custom-mesh shield. NetworkLookup pre-
    -- registration in _la_bridge.lua makes the LA mesh path safe for
    -- vanilla sync reads. If this displays correctly on all 4 Kruber
    -- shield weapons, the same approach extends to the rest of the
    -- Empire custom-mesh family (basic2, Middenheim, etc.).
    Kruber_empire_shield_basic1            = true,
}

local _la_offhand_merged = false

local function _merge_la_offhand_options()
    if _la_offhand_merged then return end
    if not LA_BRIDGE.registered then return end
    if type(LA_BRIDGE.la_offhand_options_by_weapon_type) ~= "table" then return end
    local has_focus = next(_LA_FOCUS_KEYS) ~= nil
    for weapon_key, la_pool in pairs(LA_BRIDGE.la_offhand_options_by_weapon_type) do
        local target = _offhand_options[weapon_key]
        if not target then target = {}; _offhand_options[weapon_key] = target end
        for _, la_opt in ipairs(la_pool) do
            if (not has_focus) or _LA_FOCUS_KEYS[la_opt.armoury_key] then
                target[#target + 1] = {
                    name            = la_opt.name .. " (LA)",
                    la_armoury_key  = la_opt.armoury_key,
                    vanilla_skin    = la_opt.vanilla_skin,
                    -- mesh the LA texture was authored for; swapped in via
                    -- BackendUtils.get_item_units so LA paints onto the right
                    -- shield shape. nil for pure-paint variants, in which case
                    -- the user's existing shield mesh is preserved.
                    intended_unit   = la_opt.intended_unit,
                    rarity          = "promo",
                }
            end
        end
    end
    _la_offhand_merged = true
    mod:info("[offhand] merged LA shield options (focus gate: %d keys)",
        (function() local n = 0; for _ in pairs(_LA_FOCUS_KEYS) do n = n + 1 end; return n end)())
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
    -- rawget: item.key may be an LA-bridge backend_id or CWV variant key
    -- that doesn't exist in IML; ItemMasterList.__index crashifies on
    -- unknown keys.
    local data = item.data or (item.key and ItemMasterList and rawget(ItemMasterList, item.key))
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
    local item_data = item.data or (item.key and ItemMasterList and rawget(ItemMasterList, item.key))
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

    -- Discard the stored selection only when the customization screen
    -- has been opened for a DIFFERENT item (different backend_id) of the
    -- same item_type. For the SAME item — including reload-after-Apply
    -- which rebuilds the screen with the new skin but same backend_id —
    -- preserve the user's explicit pick. Mesh-mismatch alone shouldn't
    -- discard, because Apply changes the skin's left_hand_unit but the
    -- user still wants their LA / vanilla offhand selection to apply on
    -- top of the new skin.
    local current_backend_id = item.backend_id
    -- v0.8.32: keyed by backend_id directly; no separate stale-tracking
    -- needed since each weapon instance has its own selection slot.
    local current_sel = current_backend_id and _offhand_selection[current_backend_id]

    if not current_sel and current_left_unit then
        for _, opt in ipairs(options) do
            local opt_mesh = opt.unit or opt.intended_unit
            if opt_mesh == current_left_unit then
                if current_backend_id then
                    _offhand_selection[current_backend_id] = opt
                end
                current_sel = opt
                mod:info("[offhand] auto-selected: %s (backend_id=%s)",
                    tostring(opt.name), tostring(current_backend_id))
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

    -- CLARIFY: scenegraph guard — offhand widget definitions inherit
    -- scenegraph_id from create_illusion_button. If the inherited id isn't
    -- registered in this scene's ui_scenegraph (rare but possible during
    -- transitions), draw_widget would crash. Skipping is the safe default.
    for _, widget in ipairs(offhand_widgets) do
        if sg[widget.scenegraph_id] then
            UIRenderer.draw_widget(ui_renderer, widget)
        end
    end

    -- QUESTION: hotspot.on_pressed semantics — is this ONE-FRAME-ONLY (set
    -- by the engine on the click frame and cleared next frame), or sticky
    -- until consumed? If sticky, this could re-fire _ct_on_offhand_pressed
    -- every frame after a click until the next button registers a new
    -- press. Vanilla illusion buttons in HeroWindowItemCustomization handle
    -- this via _on_illusion_index_pressed which is gated on a state machine,
    -- not directly on on_pressed. Worth adding a per-frame consumed flag
    -- (e.g. set hotspot.on_pressed = false after handling) if observed.
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

    -- v0.8.32: key selection by backend_id (per-weapon-instance).
    if self._item_backend_id then
        _offhand_selection[self._item_backend_id] = opt
    end
    _preload_offhand_for_option(opt)

    for i, w in ipairs(widgets) do
        local is_sel = (i == index)
        w.content.button_hotspot.is_selected = is_sel
        w.content.equipped = is_sel
    end

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
    --   2. backend item's `.skin` (vanilla-crafted edge case)
    --   3. backend get_skin(backend_id) (vanilla-crafted Bret etc.)
    --   4. WeaponSkins.default_skins[item.key]
    local pending_item, pending_data, pending_skin
    if self._previewer and self._previewer._item then
        local pi = self._previewer._item
        if pi.data then pending_data = pi.data end
        if pi.skin and pi.skin ~= "" then pending_skin = pi.skin end
    end

    local item = self:_get_item(self._item_backend_id)
    if item then
        if not pending_skin then
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
            pending_skin = skin_key
        end

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

-- CLARIFY: BackendUtils is a plain table, not a class. The string-form
-- hook (`mod:hook("BackendUtils", ...)`) cannot resolve it because VMF's
-- string resolution looks for class names in the loaded class table.
-- Must use TABLE-form hook with a nil guard. The nil guard handles boot
-- order — at module-load time BackendUtils may not exist yet on every
-- VT2 build. CLAUDE.md "Hooking" section.
if BackendUtils then
    mod:hook(BackendUtils, "get_item_units", function(func, item_data, backend_id, skin, career_name)
        local result = func(item_data, backend_id, skin, career_name)
        if not result then return result end

        -- Resolve the actual skin: caller may pass nil and rely on backend
        -- lookup. Mirror BackendUtils' OWN resolution chain so we can decide
        -- whether to apply the override:
        --   1. explicit `skin` arg
        --   2. explicit `backend_id` arg -> get_skin
        --   3. `item_data.backend_id` (vanilla stamps this onto item_data
        --      during equipment loadout resync) -> get_skin
        -- Step 3 is critical for `GearUtils.create_equipment`, which calls
        -- `BackendUtils.get_item_units(item_data, nil, nil, career_name)` —
        -- both args nil — and relies on item_data.backend_id internally.
        -- Without this our hook bailed at has_skin=false for every in-game
        -- equip, so the user's row-2 selection never applied to the player
        -- body and worse, never gated `wpn_*_runed_01` paths whose package
        -- the engine hadn't preloaded → "Unit not found" crash in
        -- world.spawn_unit. Documented in CHANGELOG v0.7.101-dev.
        local resolved_skin = skin
        local effective_backend_id = backend_id or (item_data and item_data.backend_id)
        if not resolved_skin and effective_backend_id and Managers and Managers.backend then
            local backend_items = Managers.backend:get_interface("items")
            if backend_items and backend_items.get_skin then
                resolved_skin = backend_items:get_skin(effective_backend_id)
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
            local weapon_data = rawget(ItemMasterList, item_data.matching_item_key)
            if weapon_data then
                item_type = weapon_data.item_type
            end
        end
        if not item_type then return result end

        -- v0.8.32: read selection by backend_id (per-weapon-instance), not
        -- by item_type. effective_backend_id resolved earlier in this hook
        -- via the (skin arg | backend_id arg | item_data.backend_id) chain.
        local sel = effective_backend_id and _offhand_selection[effective_backend_id]
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

-- Returns the unit path the engine would actually load for this hand: a
-- skin's path takes precedence over the base item's path (mirrors
-- BackendUtils.get_item_units' resolution at backend_utils.lua:171-189).
-- `skin` may be nil/"" → fall through to item_data[hand_field].
-- `hand_field` is "right_hand_unit" or "left_hand_unit".
-- Returns nil when neither source has a path for that hand (common for
-- single-hand weapons or for hat/portrait items).
-- Mirrors BackendUtils.get_item_units' skin-vs-base resolution: when a skin
-- is equipped, the skin's per-hand unit path takes precedence; otherwise fall
-- back to the base item_data's per-hand unit. Used ONLY by the in-game
-- `GearUtils.create_equipment` hook, which doesn't expose a pre-resolved
-- spawn_data array — it gets `result.skin` from the spawn result and we have
-- to look up the rendered path ourselves. The two menu hooks
-- (`HeroPreviewer._spawn_item`, `LootItemUnitPreviewer.spawn_units`) read
-- paths directly from `spawn_data[i].unit_name` instead, which is vanilla's
-- truth source after it called BackendUtils.get_item_units once. Don't add
-- new callers for menu paths — re-introducing this resolution chain risks
-- the cwv-clone `entry.name` drift bug fixed in v0.7.98.
local function _resolve_render_unit_path(item_data, skin, hand_field)
    if skin and skin ~= "" and WeaponSkins and WeaponSkins.skins then
        local s = WeaponSkins.skins[skin]
        if s and s[hand_field] then return s[hand_field] end
    end
    return item_data and item_data[hand_field] or nil
end

-- Resolve a factor (function | {x,y,z} | number) into a Vector3 scale.
-- Functions receive a `get(id)` accessor for live mod settings, so toggling
-- a setting without re-spawning the unit is supported (next equip applies).
-- Returns nil if the factor function returned nil (toggle off).
local function _resolve_factor(factor)
    if type(factor) == "function" then
        factor = factor(function(id) return mod:get(id) end)
    end
    if not factor then return nil end
    if type(factor) == "table" then
        return Vector3(factor[1], factor[2], factor[3])
    end
    return Vector3(factor, factor, factor)
end

-- Apply any matching unit-path scale to one hand's units. Pass nil for any
-- slot you don't have (the menu paths only have one Unit per hand; in-game
-- has both 3p and 1p). `hand_label` is "right" or "left" — used to filter
-- entries with `hand = "right"` etc. set.
-- No-op if `path` is nil (e.g. single-hand weapon's left side).
local function _apply_unit_path_scale_hand(unit_3p, unit_1p, path, hand_label)
    if not path then return end
    for _, ov in ipairs(_unit_path_scale_overrides) do
        if (ov.hand == nil or ov.hand == hand_label)
                and path:find(ov.pattern, 1, true) then
            local scale = _resolve_factor(ov.factor)
            if scale then
                if unit_3p and _is_unit(unit_3p) then pcall(Unit.set_local_scale, unit_3p, 0, scale) end
                if unit_1p and _is_unit(unit_1p) then pcall(Unit.set_local_scale, unit_1p, 0, scale) end
            end
        end
    end
end

-- Convenience wrapper for the GearUtils path: resolves both hand paths from
-- the spawn result + base item, then applies matching scale to all four hand
-- units. Used by the in-game create_equipment hook only — menu paths build
-- their own Unit list (one per hand, not 3p/1p split).
local function _scale_units(result, item_data, skin)
    local right_path = _resolve_render_unit_path(item_data, skin, "right_hand_unit")
    local left_path  = _resolve_render_unit_path(item_data, skin, "left_hand_unit")
    _apply_unit_path_scale_hand(result.right_unit_3p, result.right_unit_1p, right_path, "right")
    _apply_unit_path_scale_hand(result.left_unit_3p,  result.left_unit_1p,  left_path,  "left")
end

-- Glow override (v0.8.23-dev: redesigned per-family routing).
--
-- Decouples "user color choice" from "shader variable to write". The user picks
-- one RGB; we write it to whichever shader variables actually drive emissive on
-- the target weapon. Variables that don't exist on a given mesh silently no-op
-- via Unit.set_vector3_for_materials (verified empirically by `cos glow_scan`).
--
-- Probe-confirmed paintable variables per mesh family:
--   * `_runed_*` (themed Veteran AND Stylish loot-chest white) → `rune_emissive_color`
--   * `_magic_01` (Weavebound, no template) → 4 versus channels
--   * `_magic_02` (Shyish-Infused, `versus` template) → same 4 versus channels
-- We write all 5 candidate variables on every unit; only the relevant ones land.
-- color_dots intentionally omitted — probe showed minimal visible color
-- contribution and possibly drives particle behaviour we shouldn't perturb.
local _COLOR_PRESETS = {
    -- Preset keys preserved from older builds for user-save compatibility.
    -- HDR values >1 produce bloom; rune RGBs match the source-defined templates
    -- (weapon_material_settings_templates.lua), white is a new bright-bloom value.
    purple_glow  = { 3,    1,    9    },
    golden_glow  = { 8,    5,    1.5  },
    deep_crimson = { 7,    0,    0.1  },
    life_green   = { 7,    9,    0.1  },
    lileath      = { 5.8,  6.3,  9    },
    white_glow   = { 10,   10,   10   },
}

-- Variables to write per unit, with each variable's typical max brightness.
-- Writing user RGB scaled to that brightness preserves the natural visual
-- structure of multi-channel templates (versus has 5 channels at very
-- different brightness levels — writing them all to user RGB uniformly
-- caused the v0.8.29 over-bright bug on Shyish-Infused weapons).
-- Brightness reference values come from the source-defined templates
-- (versus channels at gear_utils.lua's MaterialSettingsTemplates.versus,
-- rune_emissive_color from the rune-family templates max=9 from lileath).
-- A weapon's mesh exposes only the variables for its own family; the rest
-- silently no-op via Unit.set_vector3_for_materials.
-- Each entry: native brightness + per-channel multiplier setting + visual
-- group. The "group" maps to a per-channel COLOR picker when the user
-- enables `glow_per_channel_color_enable`, so multi-channel magic-family
-- weapons can have different colors per gradient/dots element.
-- Visual groups (per probe v0.8.22 on Weavebound Bret longsword):
--   "rune"  → drives rune_emissive_color (themed + Stylish meshes only)
--   "lower" → drives lower part of gradient on `_magic_*` (glow_high + glow_low)
--   "upper" → drives upper part of gradient on `_magic_*` (smoke_high + smoke_low)
--   "dots"  → drives the dot particles (color_dots)
local _GLOW_VAR_BRIGHTNESS = {
    rune_emissive_color = { brightness = 9,    setting = "glow_mult_rune",       group = "rune"  },
    color_glow_high     = { brightness = 4,    setting = "glow_mult_glow_high",  group = "lower" },
    color_glow_low      = { brightness = 1,    setting = "glow_mult_glow_low",   group = "lower" },
    color_smoke_high    = { brightness = 0.22, setting = "glow_mult_smoke_high", group = "upper" },
    color_smoke_low     = { brightness = 0.06, setting = "glow_mult_smoke_low",  group = "upper" },
    color_dots          = { brightness = 8.35, setting = "glow_mult_dots",       group = "dots"  },
}

-- Maps visual group → VMF setting key holding the chosen preset for that
-- group. Only consulted when `glow_per_channel_color_enable` is true.
-- "rune" intentionally absent: rune-family weapons only have one channel,
-- so per-channel separation is meaningless — they always use the main color.
local _GLOW_GROUP_COLOR_SETTING = {
    lower = "glow_color_lower_gradient",
    upper = "glow_color_upper_gradient",
    dots  = "glow_color_dots",
}

local function _glow_master_mult()
    local v = mod:get("glow_mult_master")
    return type(v) == "number" and v or 1.0
end

local function _glow_var_mult(setting)
    if not setting then return 1.0 end
    local v = mod:get(setting)
    return type(v) == "number" and v or 1.0
end

local function _glow_override_enabled()
    return mod:get("glow_override_enable") == true
end

-- Resolves a preset key to RGB. The special key "default" (and unknown keys)
-- return nil — caller treats nil as "don't override this channel, leave
-- vanilla's value in place".
local function _resolve_preset_rgb(key)
    if not key or key == "default" then return nil end
    return _COLOR_PRESETS[key]
end

local function _glow_main_rgb()
    if not _glow_override_enabled() then return nil end
    return _resolve_preset_rgb(mod:get("glow_override_preset"))
end

-- RGB to use for a given variable. When per-channel is enabled, the magic-
-- family groups (lower/upper/dots) consult their own dropdowns; rune-family
-- always uses the main picker (only one channel — per-channel split would be
-- meaningless). Returns nil when:
--   * override toggle is OFF, or
--   * the relevant dropdown is set to "default" — meaning this specific
--     variable should NOT be overridden, vanilla's value stays.
local function _glow_rgb_for_var(var_name)
    if not _glow_override_enabled() then return nil end
    local info = _GLOW_VAR_BRIGHTNESS[var_name]
    local group = info and info.group
    if mod:get("glow_per_channel_color_enable") then
        local setting = group and _GLOW_GROUP_COLOR_SETTING[group]
        if setting then
            local key = mod:get(setting)
            -- Per-channel dropdown drives this variable. "default" → skip.
            -- Any concrete preset → use it. Unknown key → fall through to main.
            if key == "default" then return nil end
            local rgb = _resolve_preset_rgb(key)
            if rgb then return rgb end
        end
    end
    -- Fallback: main color picker (also returns nil if main is "default")
    return _glow_main_rgb()
end

local function _apply_glow_to_unit(unit)
    if not unit or not _is_unit(unit) then return end
    if not _glow_override_enabled() then return end
    -- Per-variable: skip if rgb is nil (main = "default" AND no per-channel
    -- color set for this var's group), else write user RGB scaled to native
    -- brightness × master × per-channel multiplier. mult=0 also skips.
    local master_mult = _glow_master_mult()
    for var_name, info in pairs(_GLOW_VAR_BRIGHTNESS) do
        local rgb = _glow_rgb_for_var(var_name)
        if rgb then
            local var_mult = _glow_var_mult(info.setting)
            if var_mult > 0 then
                local user_max = math.max(rgb[1], rgb[2], rgb[3], 0.0001)
                local effective = info.brightness * var_mult * master_mult
                local s = effective / user_max
                pcall(Unit.set_vector3_for_materials, unit, var_name,
                    Vector3(rgb[1] * s, rgb[2] * s, rgb[3] * s))
            end
        end
    end
end

-- Backward-compatible alias used by the existing call site at create_equipment.
local function _glow_preset_rgb() return _glow_main_rgb() end

local function _apply_glow_override(units)
    if not _glow_override_enabled() then return end
    for _, u in ipairs(units) do _apply_glow_to_unit(u) end
end

-- Glow override (v0.8.16-dev): TEMPLATE MUTATION approach.
--
-- Why we changed mechanism: hook_safe-overlay (v0.8.4-v0.8.15) reliably painted
-- 3p but never visually changed 1p, even though `Unit.set_vector3_for_materials`
-- returned ok=true on every 1p call (verified via [GLOW-trace] in v0.8.5).
-- User confirmed vanilla 1P glow IS paintable (a deep_crimson skin glows red
-- in 1P with override off), so it's not a 1P-shader-doesn't-have-the-variable
-- limit. Theory: when our overlay runs after vanilla's apply_material_settings,
-- something in the 1P spawn path re-binds the original template values (likely
-- the unit's flow graph fires on visibility-toggle / wield and reads the original
-- template via a separate code path). Best counter: don't overlay AFTER vanilla;
-- instead, mutate `MaterialSettingsTemplates[name]` to hold our values BEFORE
-- vanilla reads them, then restore the table after vanilla returns. Vanilla's
-- own writes carry our values. NoGlow uses a similar template-mutation trick
-- to zero out emissive.
-- Per-hook call counters for `cos glow_status` diagnostics.
mod._glow_call_counts = { gear = 0, flow = 0, cosmetic = 0 }
mod._glow_hooks_installed = { gear = false, flow = false, cosmetic = false }

local function _hook_apply_with_template_mutation(class_id, label)
    mod:hook(class_id, "apply_material_settings", function(func, unit, material_settings_name)
        mod._glow_call_counts[label] = (mod._glow_call_counts[label] or 0) + 1
        if not _glow_override_enabled() then
            if mod:get("glow_trace") then
                mod:info("[GLOW] %s call template=%s (override OFF, passthrough)", label, tostring(material_settings_name))
            end
            return func(unit, material_settings_name)
        end
        local template = MaterialSettingsTemplates and MaterialSettingsTemplates[material_settings_name]
        if not template then
            if mod:get("glow_trace") then
                mod:info("[GLOW] %s call template=%s (template nil, passthrough)", label, tostring(material_settings_name))
            end
            return func(unit, material_settings_name)
        end
        if mod:get("glow_trace") then
            mod:info("[GLOW] %s mutate template=%s", label, tostring(material_settings_name))
        end
        -- Mutate per-variable. Skip variables whose color resolves to nil
        -- (= "Default" preset OR main is "Default" with no per-channel color
        -- for this variable's group) — the template's vanilla value passes
        -- through to the spawn unchanged. Skip variables whose mult is 0.
        -- Color and brightness come from _glow_rgb_for_var (respects per-
        -- channel-color toggle) and the var's mult setting.
        local master_mult = _glow_master_mult()
        local saved = {}
        for var_name, entry in pairs(template) do
            if entry.type == "vector3" then
                local var_rgb = _glow_rgb_for_var(var_name)
                local info = _GLOW_VAR_BRIGHTNESS[var_name]
                local var_mult = info and _glow_var_mult(info.setting) or 1.0
                if var_rgb and var_mult > 0 then
                    saved[var_name] = { x = entry.x, y = entry.y, z = entry.z }
                    local orig_max = math.max(entry.x, entry.y, entry.z, 0.0001)
                    local user_max = math.max(var_rgb[1], var_rgb[2], var_rgb[3], 0.0001)
                    local s = (orig_max * var_mult * master_mult) / user_max
                    entry.x, entry.y, entry.z = var_rgb[1] * s, var_rgb[2] * s, var_rgb[3] * s
                end
            end
        end
        local ok, err = pcall(func, unit, material_settings_name)
        -- Restore originals so other consumers of the template see vanilla values
        for var_name, orig in pairs(saved) do
            local entry = template[var_name]
            if entry then entry.x, entry.y, entry.z = orig.x, orig.y, orig.z end
        end
        if not ok then mod:info("[GLOW] %s vanilla apply errored: %s", label, tostring(err)) end
    end)
    mod._glow_hooks_installed[label] = true
end

_hook_apply_with_template_mutation("GearUtils", "gear")
if _G.apply_material_settings then
    _hook_apply_with_template_mutation(_G, "flow")
else
    mod:info("[GLOW] _G.apply_material_settings nil at hook time")
end
if rawget(_G, "CosmeticUtils") and CosmeticUtils.apply_material_settings then
    _hook_apply_with_template_mutation("CosmeticUtils", "cosmetic")
else
    mod:info("[GLOW] CosmeticUtils.apply_material_settings nil at hook time")
end

-- Custom template + spawn-time injection for non-templated meshes.
--
-- Stylish (`_runed_01`) loot-chest white-glow weapons and Weavebound (`_magic_01`)
-- WoM Athanor weapons have NO `material_settings_name` on their skins. Vanilla
-- never calls `apply_material_settings` on them, so our template-mutation hook
-- never fires. The previous direct post-spawn paint at `create_equipment`
-- (`_apply_glow_override`) writes via `Unit.set_vector3_for_materials` BUT
-- doesn't bind on 1P units (same engine-internal rejection that bit themed
-- weapons in v0.8.4-v0.8.15 before we switched to template mutation).
--
-- Solution: register our own template containing every variable these meshes
-- might expose, then hook `GearUtils.spawn_inventory_unit` to inject the
-- template name when the override is on AND the weapon's mesh suffix matches
-- a non-templated paintable family. Vanilla then calls apply_material_settings
-- with our template, our template-mutation hook fires, mutates per-variable
-- to user RGB, vanilla writes via the trusted path that DOES bind 1P. Solves
-- both problems with the same mechanism that fixed themed weapons.
--
-- Initial values are the typical brightness per variable; the mutation hook's
-- per-variable scaling preserves these magnitudes when applying user RGB.
if rawget(_G, "MaterialSettingsTemplates") then
    MaterialSettingsTemplates._cosmetics_tweaker_glow = {
        rune_emissive_color = { type = "vector3", x = 9,    y = 9,    z = 9    },
        color_glow_high     = { type = "vector3", x = 4,    y = 4,    z = 4    },
        color_glow_low      = { type = "vector3", x = 1,    y = 1,    z = 1    },
        color_smoke_high    = { type = "vector3", x = 0.22, y = 0.22, z = 0.22 },
        color_smoke_low     = { type = "vector3", x = 0.06, y = 0.06, z = 0.06 },
        -- color_dots included so users can experiment with it on Weavebound /
        -- Stylish meshes via the advanced multiplier. Per-channel mult defaults
        -- to 0 (skip) so the channel is inert by default — probe (v0.8.22)
        -- showed it darkens Weavebound when set high.
        color_dots          = { type = "vector3", x = 8.35, y = 8.35, z = 8.35 },
    }
end

mod:hook("GearUtils", "spawn_inventory_unit", function(func, world, hand, item_template, item_units, slot_name, item_data, owner_unit_1p, owner_unit_3p, unit_template, extra_extension_data, ammo_percent, material_settings_name)
    -- Only inject when override is on AND the weapon currently has no native template.
    if material_settings_name == nil and mod:get("glow_override_enable") and item_units then
        local mesh = item_units[hand .. "_hand_unit"]
        if mesh and (mesh:find("_runed_01$") or mesh:find("_magic_01$")) then
            material_settings_name = "_cosmetics_tweaker_glow"
            if mod:get("glow_trace") then
                mod:info("[GLOW] inject template for mesh=%s hand=%s", tostring(mesh), tostring(hand))
            end
        end
    end
    return func(world, hand, item_template, item_units, slot_name, item_data, owner_unit_1p, owner_unit_3p, unit_template, extra_extension_data, ammo_percent, material_settings_name)
end)

mod:command("glow_status", "Report glow override state, hook health, and per-hook call counts since session start", function()
    local enable = mod:get("glow_override_enable")
    local preset = mod:get("glow_override_preset")
    local trace  = mod:get("glow_trace")
    mod:echo(string.format("[glow_status] enable=%s preset=%s trace=%s",
        tostring(enable), tostring(preset), tostring(trace)))
    for _, label in ipairs({ "gear", "flow", "cosmetic" }) do
        mod:echo(string.format("[glow_status] hook[%s] installed=%s calls_this_session=%d",
            label,
            tostring(mod._glow_hooks_installed[label]),
            mod._glow_call_counts[label] or 0))
    end
    -- Sanity-check the preset has a valid entry
    local preset_entry = preset and _COLOR_PRESETS and _COLOR_PRESETS[preset]
    mod:echo(string.format("[glow_status] preset table entry exists=%s rgb=%s",
        tostring(preset_entry ~= nil),
        preset_entry and string.format("(%s,%s,%s)", tostring(preset_entry[1]), tostring(preset_entry[2]), tostring(preset_entry[3])) or "n/a"))
end)

mod:command("glow_trace", "Toggle per-call glow trace logging (on/off). No arg toggles; pass 1/0 to set.", function(arg)
    local current = mod:get("glow_trace") and true or false
    local new_value
    if arg == nil or arg == "" then
        new_value = not current
    else
        new_value = (arg == "1" or arg == "on" or arg == "true")
    end
    mod:set("glow_trace", new_value)
    mod:echo(string.format("[glow_trace] now %s", new_value and "ON" or "OFF"))
end)

-- Live re-paint REMOVED in v0.8.10-dev. Earlier `mod._refresh_glow` walked
-- ScriptUnit.extension(player_unit, "inventory_system")._equipment.slots and
-- painted every right_unit_1p / right_unit_3p / left_unit_1p / left_unit_3p.
-- That worked for the wielded slot but destabilized adjacent units: pressing
-- X (inspect) afterwards made hand meshes disappear and 1P state break, only
-- recoverable by switching characters. Root cause not pinned — likely the
-- engine doesn't tolerate set_vector3_for_materials on currently-invisible
-- (sheathed) 1P units. To re-add live updates, hook the wield event and
-- paint only the weapon at the moment it becomes visible. For now: changing
-- the override or preset takes effect on the NEXT weapon equip / spawn via
-- the apply_material_settings hook above.

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
        local wd = rawget(ItemMasterList, item_data.matching_item_key)
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
local function _apply_la_offhand_to_units(world, item_data, units, has_skin, backend_id_arg)
    if not LA_BRIDGE.registered then mod:info("[LA paint] skip: bridge not registered"); return end
    if not world or not item_data then mod:info("[LA paint] skip: world/item_data nil"); return end
    if not has_skin then mod:info("[LA paint] skip: has_skin=false"); return end
    -- v0.8.32: read selection by backend_id. Resolve from arg first, then
    -- from item_data.backend_id (vanilla stamps this on equipment resync).
    local bid = backend_id_arg or (item_data and item_data.backend_id)
    if not bid then mod:info("[LA paint] skip: no backend_id"); return end
    local sel = _offhand_selection[bid]
    if not sel then mod:info("[LA paint] skip: no _offhand_selection for backend_id=%s", tostring(bid)); return end
    if not sel.la_armoury_key then return end  -- vanilla selection, nothing for us to paint
    mod:info("[LA paint] painting %s on %d units (backend_id=%s)",
        tostring(sel.la_armoury_key), #units, tostring(bid))
    for _, u in ipairs(units) do
        if u and _is_unit(u) then
            local ok = LA_BRIDGE.apply_offhand_to_unit(world, u, sel.la_armoury_key, sel.vanilla_skin)
            mod:info("[LA paint]   unit=%s ok=%s", tostring(u), tostring(ok))
        end
    end
end

-- In-game keep / mission body
-- THREE RENDERING PATHS COVERAGE:
--   - In-game (GearUtils.create_equipment): THIS HOOK
--   - Inventory previewer (HeroPreviewer._spawn_item): _spawn_item_wrapper below
--   - Illusion browser (LootItemUnitPreviewer.spawn_units): hook below
mod:hook("GearUtils", "create_equipment", function(func, world, slot_name, item_data, unit_1p, unit_3p, is_bot, unit_template, extra_extension_data, ammo_percent, override_item_template, override_item_units, career_name)
    local result = func(world, slot_name, item_data, unit_1p, unit_3p, is_bot, unit_template, extra_extension_data, ammo_percent, override_item_template, override_item_units, career_name)
    if result and item_data then
        -- Scale runs unconditionally — it's gated by unit-path matching, so
        -- a cwv variant equipped in this slot only gets scaled if its
        -- resolved model genuinely matches a pattern (e.g. someone applies
        -- a Bretonian skin to a cwv item, which intentionally would scale).
        _scale_units(result, item_data, result.skin)
    end
    if result and item_data and not item_data.cwv_variant then
        -- Offset / tint / LA-paint stay item-name-keyed and so DO need the
        -- cwv_variant gate. cwv items inherit their base weapon's `name`
        -- (e.g. cwv_es_longsword.name == "es_bastard_sword"), so without
        -- this gate any item-name-keyed override on the base weapon would
        -- spuriously fire on every cwv variant. See
        -- `feedback_cwv_clone_name_clobber.md` for the full rationale.
        local weapon_key = item_data.name
        _offset_units(result, weapon_key, career_name)
        local has_skin = result.skin ~= nil and result.skin ~= ""
        _apply_la_offhand_to_units(world, item_data, { result.left_unit_3p, result.left_unit_1p }, has_skin)
    end
    if result then
        _apply_glow_override({
            result.right_unit_3p, result.left_unit_3p,
            result.right_unit_1p, result.left_unit_1p,
        })
    end
    return result
end)

-- Inventory preview (new menu)
local _mwp_pending_keys = setmetatable({}, { __mode = "k" })

-- Track the `skin` arg passed to HeroPreviewer:equip_item /
-- MenuWorldPreviewer:equip_item, keyed by previewer -> item_name. The
-- equipment menu's character preview spawns via _spawn_item with the
-- WEAPON master key (e.g. `es_breton_sword`, item_type =
-- `es_1h_sword_shield_breton`), NOT the skin item. Without this map our
-- has_skin check `item_data.item_type == "weapon_skin"` returns false
-- and the LA paint is skipped on the equipment-menu character preview
-- even though the weapon DOES have an illusion equipped via backend.
local _equip_skin_by_item = setmetatable({}, { __mode = "k" })
-- BACKEND-RESOLVE FALLBACK: vanilla-crafted Bretonnian sword & shield (and
-- some other vanilla-crafted items) have their applied illusion stored only
-- on the backend `BackendItem` object — `equip_item` is called with `skin=nil`
-- because the caller relies on `BackendUtils.get_item_units` to resolve the
-- skin internally during spawn. Without this fallback our map stored `nil`
-- for those items, `has_skin` was false in `_spawn_item_post`, and LA paint
-- was skipped on the inventory loadout mannequin (the visible character
-- preview behind/around the customization screen). User report 2026-05-06.
local function _store_equip_skin(previewer, item_name, skin, backend_id)
    if not previewer or not item_name then return end
    if (not skin or skin == "") and backend_id and Managers and Managers.backend then
        local items_iface = Managers.backend:get_interface("items")
        if items_iface and items_iface.get_skin then
            local resolved = items_iface:get_skin(backend_id)
            if resolved and resolved ~= "" then
                skin = resolved
                mod:info("[LA preview] backend-resolved skin for %s: %s", tostring(item_name), tostring(resolved))
            end
        end
    end
    local map = _equip_skin_by_item[previewer]
    if not map then map = {}; _equip_skin_by_item[previewer] = map end
    -- v0.8.32: store both skin and backend_id so per-backend-id offhand
    -- selection can be resolved in _spawn_item_post (which doesn't have
    -- backend_id in scope but does have item_name → previewer).
    map[item_name] = { skin = skin, backend_id = backend_id }
end
local function _get_equip_skin(previewer, item_name)
    if not previewer or not item_name then return nil end
    local map = _equip_skin_by_item[previewer]
    local entry = map and map[item_name]
    return entry and entry.skin or nil
end
local function _get_equip_backend_id(previewer, item_name)
    if not previewer or not item_name then return nil end
    local map = _equip_skin_by_item[previewer]
    local entry = map and map[item_name]
    return entry and entry.backend_id or nil
end

mod:hook("MenuWorldPreviewer", "equip_item", function(func, self, item_key, slot, backend_id, skin, skip_wield_anim)
    local slot_name = (type(slot) == "table" and slot.name) or tostring(slot)
    mod:info("[LA preview] equip_item key=%s slot=%s bid=%s skin=%s is_clone=%s",
        tostring(item_key), tostring(slot_name), tostring(backend_id), tostring(skin),
        tostring(LA_BRIDGE.backend_to_armoury[backend_id] ~= nil))

    if type(item_key) == "string" then
        local sn = (type(slot) == "table" and slot.name) or (type(slot) == "string" and slot)
        if sn then
            local map = _mwp_pending_keys[self]
            if not map then map = {}; _mwp_pending_keys[self] = map end
            map[sn:gsub("^slot_", "")] = item_key
        end
        _store_equip_skin(self, item_key, skin, backend_id)
    end

    if LA_BRIDGE.registered and backend_id and LA_BRIDGE.backend_to_armoury[backend_id] then
        mod:info("[LA preview] equip_item swapping key %s -> %s for clone", tostring(item_key), tostring(backend_id))
        return func(self, backend_id, slot, backend_id, skin, skip_wield_anim)
    end

    return func(self, item_key, slot, backend_id, skin, skip_wield_anim)
end)

-- Also intercept HeroPreviewer (the equipment menu's character preview).
-- This is the previewer the user reported showing the "default shield
-- texture" instead of the LA-painted shield — it spawns the WEAPON master
-- key, not a skin entry, so our weapon_skin gate would skip the paint
-- without this skin tracking.
mod:hook("HeroPreviewer", "equip_item", function(func, self, item_name, slot, backend_id, skin, skip_wield_anim)
    if type(item_name) == "string" then
        _store_equip_skin(self, item_name, skin, backend_id)
    end
    return func(self, item_name, slot, backend_id, skin, skip_wield_anim)
end)

local function _spawn_item_post(self, item_name, spawn_data)
    if not spawn_data then return end

    -- LA offhand paint: independent of scaling, runs whenever the
    -- previewed weapon has an LA offhand selected.
    if item_name and ItemMasterList then
        -- rawget: _spawn_item can be called with LA backend_ids (our
        -- equip_item hook swaps item_key -> backend_id for clones) or
        -- arbitrary keys from third-party mods.
        local item_data = rawget(ItemMasterList, item_name)
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
                    -- has_skin is true if either:
                    --   (a) The previewed item itself is a weapon_skin entry
                    --       (inventory grid hover on a skin item), OR
                    --   (b) An equip_item call on this previewer passed a
                    --       non-empty `skin` arg for this item_name (the
                    --       equipment-menu character preview path — the
                    --       user has an illusion equipped via backend, but
                    --       _spawn_item runs with the WEAPON master key, so
                    --       item_type alone can't tell us that).
                    -- Base weapons hovered in the inventory grid hit
                    -- neither and pass-through unchanged, matching the
                    -- "we add options on top of illusions, never mutate
                    -- base templates" rule.
                    local stored_skin = _get_equip_skin(self, item_name)
                    local stored_bid  = _get_equip_backend_id(self, item_name)
                    local has_skin = (item_data.item_type == "weapon_skin")
                            or (stored_skin and stored_skin ~= "")
                    _apply_la_offhand_to_units(world, item_data, left_units, has_skin, stored_bid)
                end
            end
        end
    end

    -- Per-slot scale by unit path. Read paths from spawn_data[i].unit_name —
    -- vanilla equip_item already resolved skin + ammo + base via
    -- BackendUtils.get_item_units (world_hero_previewer.lua:675) and stored the
    -- final per-hand resource path on each spawn_data entry. That's the only
    -- truth source for "what unit is being rendered in this slot RIGHT NOW";
    -- looking it up from `info.name` -> ItemMasterList -> right_hand_unit then
    -- chasing a separate `info.skin_name` -> WeaponSkins.skins lookup is a
    -- redundant resolution chain that drifts whenever a clone (cwv) inherits
    -- its base's `name` field. We rely entirely on this truth source now —
    -- no cwv_variant gate needed: a cwv variant's spawn_data unit_name is
    -- always the variant's own model, so it can't accidentally match a
    -- base-weapon pattern. _item_info_by_slot is keyed by string slot_type
    -- ("melee"/"ranged"); spawn_data[1].slot_index bridges to _equipment_units
    -- which is numeric-slot-keyed.
    -- spawn_data shape (per HeroPreviewer.equip_item):
    --   [N] = { left_hand=true|nil, right_hand=true|nil, unit_name="..._3p",
    --           slot_index=N, ... }
    local equip_units = self._equipment_units
    local slot_info   = self._item_info_by_slot
    if not equip_units or not slot_info then return end
    for _, info in pairs(slot_info) do
        if info.spawn_data and info.spawn_data[1] then
            local slot_index = info.spawn_data[1].slot_index
            local slot = slot_index and equip_units[slot_index]
            if type(slot) == "table" then
                local right_path, left_path
                for _, sd in ipairs(info.spawn_data) do
                    if sd.right_hand then right_path = sd.unit_name end
                    if sd.left_hand  then left_path  = sd.unit_name end
                end
                if mod:get("cos_thiccc_trace") then
                    mod:info("[thiccc] preview name=%s skin=%s right=%s left=%s",
                        tostring(info.name), tostring(info.skin_name),
                        tostring(right_path), tostring(left_path))
                end
                _apply_unit_path_scale_hand(slot.right, nil, right_path, "right")
                _apply_unit_path_scale_hand(slot.left,  nil, left_path,  "left")
                _apply_glow_override({ slot.right, slot.left })
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

-- LootItemUnitPreviewer.load_package — short-circuit for engine-resident
-- units. Vanilla shield/weapon meshes ship as their OWN standalone
-- `units/.../wpn_xxx.package` files; the previewer's `load_package` calls
-- `Managers.package:load` on those, the load completes, `_on_load_complete`
-- flips `self._loaded_packages[path] = true`, and `_spawn_items` runs.
-- LA's custom-mesh shields, however, are all bundled into a single
-- `resource_packages/Loremasters-Armoury/Loremasters-Armoury` package —
-- there is no standalone `units/Kerillian_elf_shield/<...>_3p.package`.
-- A `Managers.package:load` call on those paths phantom-succeeds without
-- ever firing the completion callback, so the previewer's gate at
-- `_spawn_items` (loot_item_unit_previewer.lua:511) stays blocked and
-- `World.spawn_unit` is never called → user sees "no model at all".
-- VMF auto-loads each mod's `.mod` packages, so when LA is enabled its
-- main package is globally loaded and every `units/*` path inside it
-- becomes engine-resident — meaning `Application.can_get("unit", path)`
-- returns true even though the path isn't a valid standalone-package id.
-- We detect that case and immediately mark the previewer's gate flags
-- so `_spawn_items` proceeds to call `World.spawn_unit`, which succeeds
-- against the globally-loaded resource package.
-- v0.8.26 + v0.8.27 attempted to take a per-previewer reference on LA's
-- main package (async then sync) so its materials/textures would bind into
-- the previewer's scope. v0.8.26 (async) didn't fix the texture-less
-- preview; v0.8.27 (sync) crashed with `Resource '#ID[3ac73385950a26ea]'
-- was not found` (GUID 930aff6f-7e47-4f72-a661-b8222e862fc2). Reverted to
-- the plain v0.8.12 short-circuit. kind="unit" LA shields render mesh
-- correctly in-game and on the inventory mannequin but are texture-less
-- in the customization preview specifically. Documented limitation; needs
-- a different approach (likely related to the LA compiled `.unit` referencing
-- vanilla material paths that aren't in scope when only the shield is in
-- the preview world).
-- Tracks per-previewer parent-package references already taken so we
-- don't sync-load the same vanilla parent twice for one previewer
-- instance. Weak-keyed by previewer.
local _la_parent_pkg_ref_by_previewer = setmetatable({}, { __mode = "k" })

mod:hook("LootItemUnitPreviewer", "load_package", function(func, self, package_name)
    if package_name and Application and Application.can_get
        and Application.can_get("unit", package_name)
        and not Application.can_get("package", package_name)
    then
        -- Existing short-circuit: gate-flip so spawn proceeds.
        self._packages_to_load[package_name] = true
        self._loaded_packages[package_name] = true

        -- v0.8.39: take a per-previewer reference on the LA mesh's parent
        -- vanilla package. LA's compiled `.unit` inherits its shader graph
        -- from that vanilla unit (per `mat_to_use` in the source `.unit`).
        -- Without the parent in the previewer's scope, the shader doesn't
        -- bind, the material doesn't fully initialize, and Reiland renders
        -- with missing/magenta textures. Sync load so the parent is fully
        -- bound before `_spawn_items` runs in the same frame. Vanilla
        -- packages are well-tested so this is safer than v0.8.27's attempt
        -- to sync-load LA's whole main package (which has its own broken
        -- references).
        local parent_pkg = LA_BRIDGE
            and LA_BRIDGE.la_path_to_parent_package
            and LA_BRIDGE.la_path_to_parent_package[package_name]
        if parent_pkg and Managers and Managers.package then
            local refs = _la_parent_pkg_ref_by_previewer[self]
            if not refs then
                refs = {}
                _la_parent_pkg_ref_by_previewer[self] = refs
            end
            if not refs[parent_pkg] then
                local reference_name = "LootItemUnitPreviewer"
                if self._unique_id then
                    reference_name = reference_name .. tostring(self._unique_id)
                end
                local ok, err = pcall(Managers.package.load,
                    Managers.package, parent_pkg, reference_name, nil, false)
                if ok then
                    refs[parent_pkg] = true
                    mod:info("[LA preview-load] sync-loaded parent %s for %s",
                        parent_pkg, package_name)
                else
                    mod:info("[LA preview-load] FAILED to load parent %s for %s: %s",
                        parent_pkg, package_name, tostring(err))
                end
            end
        end
        return
    end
    return func(self, package_name)
end)

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

    -- LA offhand paint: spawn order is left (shield) = index 1, right (weapon) = index 2.
    -- Use the freshly-returned `units` array, not self._spawned_units (not yet assigned).
    -- Only paint when the previewed item carries an illusion context (it's a
    -- weapon_skin entry, OR the previewer was given a skin via item.skin).
    do
        local world = self._background_world or self._world or self.world
        local has_skin = (item.skin and item.skin ~= "")
                or (item_data and item_data.item_type == "weapon_skin")
        if has_skin and world and item_data and units and units[1] then
            _apply_la_offhand_to_units(world, item_data, { units[1] }, true, item.backend_id)
        end
    end

    if not units then return units end

    -- Read the rendered unit paths straight from spawn_data — same truth-source
    -- approach as `_spawn_item_post`. Vanilla `_load_item_units`
    -- (loot_item_unit_previewer.lua:270) already called BackendUtils.get_item_units
    -- and stored the resolved per-hand path on each entry as `unit_name`.
    -- Spawn order is fixed: index 1 = left (shield), index 2 = right (weapon),
    -- per `_load_item_units` always queueing left-then-right. DEVELOPMENT.md
    -- "Three Rendering Paths" documents this contract.
    -- No cwv_variant gate needed: a cwv item's spawn_data unit_name is always
    -- the variant's own model, never the base weapon's path.
    local left_path  = spawn_data and spawn_data[1] and spawn_data[1].unit_name or nil
    local right_path = spawn_data and spawn_data[2] and spawn_data[2].unit_name or nil
    _apply_unit_path_scale_hand(units[2], nil, right_path, "right")
    _apply_unit_path_scale_hand(units[1], nil, left_path,  "left")
    _apply_glow_override({ units[1], units[2] })

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
-- CLARIFY: la_bridge initialization is deferred to first frame where:
--   1. user has la_bridge_enable toggle on
--   2. ItemMasterList is loaded
--   3. Loremasters-Armoury and MoreItemsLibrary mods are present and loaded
-- If user toggles la_bridge_enable mid-session, this picks it up next
-- frame. But TOGGLING OFF requires a restart — registered IML entries are
-- not removed (no public unregister API on MIL).
mod.update = function(dt)
    if not _la_bridge_init_done then
        if mod:get("la_bridge_enable")
           and ItemMasterList
           and get_mod("Loremasters-Armoury")
           and get_mod("MoreItemsLibrary") then
            LA_BRIDGE.register_all()
            LA_BRIDGE.install_apply_gate()
            -- v0.8.31 REVERT: skin injection (v0.8.29-30) didn't match
            -- the user's "shield and main weapon are changed separately"
            -- mental model. Restore the row-2 LA merge so LA shields
            -- show up in the offhand picker again. Cross-weapon leak +
            -- preview-texture issues remain known limitations to address
            -- under a different design (likely per-backend_id selection
            -- + backend-mirror persistence).
            _merge_la_offhand_options()
            _la_bridge_init_done = true
        end
    end
    if _la_bridge_init_done then _install_skin_loadout_safety() end
    if mod._glow_scan_tick then mod._glow_scan_tick(dt) end
end

-- ============================================================
-- GLOW PROBE — find what shader uniform controls baked emissive on Stylish
-- (`_runed_01`), Weavebound (`_magic_01`), or other non-template-driven
-- glow categories.
--
-- Mechanism: brute-force a battery of plausible shader-uniform names by
-- calling Unit.set_vector3_for_materials with each candidate set to a
-- bright HDR red value. Variables that don't exist on the unit's materials
-- silently no-op. The variable that controls the emissive will visibly
-- turn the weapon red.
--
-- Cannot enumerate parameters via Material.num_parameters / parameter_name
-- — those crash Stingray (resource_manager.cpp:245, NOT pcall-recoverable).
-- Brute force is the only viable approach.
--
-- Three commands provide different probe modes:
--   cos glow_dump       - dump unit metadata (mesh + material counts)
--   cos glow_probe NAME - paint single named variable bright red
--   cos glow_scan       - cycle through all candidates with red/clear
--                         flashing per candidate. Watch and note when
--                         the weapon flashes red — the chat message at
--                         that moment names the variable.
--   cos glow_scan_stop  - cancel an in-flight scan
--   cos glow_restore    - re-apply the wielded item's original template
--                         to clear lingering probe values
-- ============================================================

-- Vector3 in Stingray is a frame-allocated temporary; do NOT cache it as a
-- module-level constant — across frames the storage is reclaimed and every
-- pcall(Unit.set_vector3_for_materials, ..., cached_vec) returns false. Found
-- empirically in v0.8.20: the scan reported `painted=0` on EVERY candidate ×
-- every unit because of this. Construct fresh per call site (same pattern as
-- _apply_glow_to_unit).
local function _probe_red()   return Vector3(15, 0, 0) end
local function _probe_clear() return Vector3(0,  0, 0) end
local _GLOW_PROBE_CANDIDATES = {
    -- emissive family
    "emissive_color", "_emissive_color", "emissive", "self_illum_color",
    "self_illumination", "illumination_color", "mtr_emissive",
    -- existing rune (control: should turn _runed_02 red)
    "rune_emissive_color", "_rune_emissive_color", "rune_color", "rune_glow",
    -- glow family
    "glow_color", "_glow_color", "glow", "main_glow", "primary_glow",
    "secondary_glow", "edge_glow", "rim_glow", "blade_glow",
    -- color/tint family
    "tint_color", "_tint_color", "tint", "color", "_color",
    "main_color", "primary_color", "secondary_color", "accent_color",
    "albedo_color", "albedo", "diffuse_color", "base_color", "base_color_tint",
    "highlight_color", "lamp_color", "light_color",
    -- gradient/swirl (Weavebound suspects — animated effects)
    "gradient_color_a", "gradient_color_b", "gradient_a", "gradient_b",
    "color_a", "color_b", "color_main", "color_alt",
    "swirl_color", "wind_color", "wind_color_a", "wind_color_b",
    -- versus 5-channel (covers Shyish-Infused if scanned on those)
    "color_glow_high", "color_glow_low", "color_smoke_high", "color_smoke_low", "color_dots",
    -- effect / fx family
    "effect_color", "fx_color", "vfx_color", "magic_color",
    -- material color generics
    "material_color", "mat_color", "baked_color",
    -- per-Loremaster's-Armoury map (these names work for shield textures)
    "texture_map_c0ba2942", "texture_map_64cc5eb8",
}

local function _wielded_units_for_probe()
    local pm = Managers and Managers.player
    local pl = pm and pm:local_player()
    local pu = pl and pl.player_unit
    if not (pu and ScriptUnit and ScriptUnit.has_extension and ScriptUnit.has_extension(pu, "inventory_system")) then
        return nil, nil
    end
    local ext = ScriptUnit.extension(pu, "inventory_system")
    local slot_data = ext.get_wielded_slot_data and ext:get_wielded_slot_data()
    if not slot_data then return nil, nil end
    local out = {}
    for _, field in ipairs({ "right_unit_1p", "right_unit_3p", "left_unit_1p", "left_unit_3p" }) do
        local u = slot_data[field]
        if u and _is_unit(u) then out[#out + 1] = { field = field, unit = u } end
    end
    return out, slot_data
end

mod:command("glow_dump", "Dump wielded weapon unit metadata: mesh + material counts per hand unit", function()
    local units, slot_data = _wielded_units_for_probe()
    if not units or #units == 0 then mod:echo("[glow_dump] no wielded weapon"); return end
    mod:echo(string.format("[glow_dump] skin=%s, %d hand-units to probe", tostring(slot_data and slot_data.skin), #units))
    mod:info("[glow_dump] === wielded slot metadata ===")
    mod:info("[glow_dump] skin=%s item=%s", tostring(slot_data and slot_data.skin), tostring(slot_data and slot_data.item_data and slot_data.item_data.name))
    for _, u in ipairs(units) do
        local ok_n, n_meshes = pcall(Unit.num_meshes, u.unit)
        mod:info("[glow_dump] %s: alive=%s num_meshes=%s", u.field, tostring(_is_unit(u.unit)), tostring(ok_n and n_meshes or "err"))
        if ok_n and type(n_meshes) == "number" and Mesh and Mesh.num_materials then
            for i = 0, n_meshes - 1 do
                local ok_m, mesh = pcall(Unit.mesh, u.unit, i)
                if ok_m and mesh then
                    local ok_nm, n_mats = pcall(Mesh.num_materials, mesh)
                    mod:info("[glow_dump]   mesh[%d] num_materials=%s", i, tostring(ok_nm and n_mats or "err"))
                end
            end
        end
    end
    mod:echo("[glow_dump] done — full data in console log under [glow_dump]")
    if _flush_log then _flush_log() end
end)

mod:command("glow_probe", "Paint wielded weapon's chosen variable to bright HDR red. Usage: cos glow_probe <varname>", function(varname)
    if not varname or varname == "" then
        mod:echo("[glow_probe] usage: cos glow_probe <varname> — e.g. cos glow_probe emissive_color")
        return
    end
    local units = _wielded_units_for_probe()
    if not units or #units == 0 then mod:echo("[glow_probe] no wielded weapon"); return end
    local n_set = 0
    for _, u in ipairs(units) do
        local ok, err = pcall(Unit.set_vector3_for_materials, u.unit, varname, _probe_red())
        if ok then n_set = n_set + 1 end
        mod:info("[glow_probe] var=%s unit=%s set_ok=%s err=%s", varname, u.field, tostring(ok), tostring(err))
    end
    mod:echo(string.format("[glow_probe] var=%s painted on %d/%d hand units. Look at the weapon — RED?", varname, n_set, #units))
end)

local _GLOW_SCAN = nil

mod:command("glow_scan", "Cycle ALL candidate variables on wielded weapon with red/clear flash. Watch — note when the weapon flashes red.", function()
    local units, slot_data = _wielded_units_for_probe()
    if not units or #units == 0 then mod:echo("[glow_scan] no wielded weapon"); return end
    _GLOW_SCAN = {
        units      = units,
        candidates = _GLOW_PROBE_CANDIDATES,
        idx        = 0,
        phase      = "advance",  -- "advance" -> set red, "clear" -> set (0,0,0)
        timer      = 0,
        red_dur    = 1.5,        -- seconds at red per candidate
        clear_dur  = 0.4,        -- seconds at (0,0,0) before next candidate
        slot_data  = slot_data,
    }
    local total_s = (_GLOW_SCAN.red_dur + _GLOW_SCAN.clear_dur) * #_GLOW_PROBE_CANDIDATES
    mod:echo(string.format("[glow_scan] starting — %d candidates × %.1fs ≈ %.0fs total. Wield the weapon you want probed; weapon flashes red on a hit.",
        #_GLOW_PROBE_CANDIDATES, _GLOW_SCAN.red_dur + _GLOW_SCAN.clear_dur, total_s))
end)

mod:command("glow_scan_stop", "Stop the in-flight glow_scan", function()
    if _GLOW_SCAN then
        local last = _GLOW_SCAN.candidates[_GLOW_SCAN.idx]
        mod:echo(string.format("[glow_scan] stopped at idx=%d var=%s. Run cos glow_restore to re-apply original template.",
            _GLOW_SCAN.idx, tostring(last)))
        _GLOW_SCAN = nil
    else
        mod:echo("[glow_scan] not running")
    end
end)

mod:command("glow_restore", "Re-apply the wielded item's original material template to undo probe edits", function()
    local units, slot_data = _wielded_units_for_probe()
    if not units or #units == 0 then mod:echo("[glow_restore] no wielded weapon"); return end
    local skin_key = slot_data and slot_data.skin
    local skin_data = skin_key and WeaponSkins and WeaponSkins.skins and rawget(WeaponSkins.skins, skin_key)
    local tpl = skin_data and skin_data.material_settings_name
    if not tpl then
        mod:echo("[glow_restore] skin has no material_settings_name (Stylish/_runed_01?). Re-equip via inventory loadout to fully restore.")
        return
    end
    local n = 0
    for _, u in ipairs(units) do
        if GearUtils and GearUtils.apply_material_settings then
            local ok = pcall(GearUtils.apply_material_settings, u.unit, tpl)
            if ok then n = n + 1 end
        end
    end
    mod:echo(string.format("[glow_restore] re-applied template '%s' on %d/%d units", tpl, n, #units))
end)

mod._glow_scan_tick = function(dt)
    if not _GLOW_SCAN then return end
    _GLOW_SCAN.timer = _GLOW_SCAN.timer + (dt or 0)
    if _GLOW_SCAN.phase == "advance" then
        if _GLOW_SCAN.timer < _GLOW_SCAN.red_dur then return end
        _GLOW_SCAN.timer = 0
        _GLOW_SCAN.phase = "clear"
        local var = _GLOW_SCAN.candidates[_GLOW_SCAN.idx]
        if var then
            for _, u in ipairs(_GLOW_SCAN.units) do
                pcall(Unit.set_vector3_for_materials, u.unit, var, _probe_clear())
            end
        end
        return
    elseif _GLOW_SCAN.phase == "clear" then
        if _GLOW_SCAN.timer < _GLOW_SCAN.clear_dur then return end
        _GLOW_SCAN.timer = 0
        _GLOW_SCAN.idx = _GLOW_SCAN.idx + 1
        local var = _GLOW_SCAN.candidates[_GLOW_SCAN.idx]
        if not var then
            mod:echo("[glow_scan] DONE — all candidates tried. Run cos glow_restore to clean up.")
            _GLOW_SCAN = nil
            return
        end
        local n, last_err = 0, nil
        for _, u in ipairs(_GLOW_SCAN.units) do
            local ok, err = pcall(Unit.set_vector3_for_materials, u.unit, var, _probe_red())
            if ok then n = n + 1 else last_err = err end
        end
        mod:echo(string.format("[glow_scan] %d/%d → var=%s (set on %d units)", _GLOW_SCAN.idx, #_GLOW_SCAN.candidates, var, n))
        mod:info("[glow_scan] %d/%d var=%s painted=%d err=%s", _GLOW_SCAN.idx, #_GLOW_SCAN.candidates, var, n, tostring(last_err))
        _GLOW_SCAN.phase = "advance"
        return
    end
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
