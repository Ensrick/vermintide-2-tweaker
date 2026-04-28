local mod = get_mod("cosmetics_tweaker")
local U = mod:dofile("scripts/mods/cosmetics_tweaker/_cosmetic_unlocks")

local MOD_VERSION = "0.6.5-dev"
mod:info("Cosmetics Tweaker v%s loaded", MOD_VERSION)
mod:echo("Cosmetics Tweaker v" .. MOD_VERSION)

-- ============================================================
-- Material tinting research (TODO: cloned + recolored cosmetics)
-- ============================================================
-- v1: in-place tint applied to a specific hat key when spawned. Future v2 will
-- register a CLONED ItemMasterList entry so the original hat stays vanilla and
-- the tinted variant is a separate equippable item.

local _is_unit_alive = function(u) return type(u) == "userdata" and pcall(Unit.alive, u) and Unit.alive(u) end

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
                                -- Enumerate ALL parameters if the API exists in this build.
                                local got_enum = false
                                local ok_np, np = pcall(Material.num_parameters, mat)
                                mod:info("%s       Material.num_parameters -> %s", prefix, tostring(ok_np and np or "err"))
                                if ok_np and type(np) == "number" then
                                    got_enum = true
                                    for pi = 0, np - 1 do
                                        local ok_pn, pn = pcall(Material.parameter_name, mat, pi)
                                        local ok_pt, pt = pcall(Material.parameter_type, mat, pi)
                                        mod:info("%s         param[%d] name=%s type=%s",
                                                 prefix, pi,
                                                 tostring(ok_pn and pn),
                                                 tostring(ok_pt and pt))
                                    end
                                end
                                -- Fallback: brute-force more candidate names if enum API missing.
                                if not got_enum then
                                    for _, pname in ipairs({
                                        "tint_color", "color_tint", "albedo_color", "color",
                                        "diffuse_color", "main_color", "tint_color_a", "base_color_tint",
                                        "albedo", "_albedo", "_color", "_tint", "tint", "tint_a", "tint_b", "tint_c",
                                        "color_variation_mask", "pattern_color_a", "pattern_color_b",
                                        "metallic_value", "emissive", "emissive_color", "team_color_a",
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

mod.on_game_state_changed = function() apply_cosmetic_unlocks() end
mod.on_setting_changed = function(setting_id)
    if setting_id and setting_id:sub(1, 11) == "cos_unlock_" then
        apply_cosmetic_unlocks()
    end
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
    end
    return result
end)

-- Inventory preview (new menu)
local _mwp_pending_keys = setmetatable({}, { __mode = "k" })

mod:hook_safe("MenuWorldPreviewer", "equip_item", function(self, item_key, slot, backend_id)
    if type(item_key) ~= "string" then return end
    local slot_name = (type(slot) == "table" and slot.name) or (type(slot) == "string" and slot)
    if not slot_name then return end
    local map = _mwp_pending_keys[self]
    if not map then map = {}; _mwp_pending_keys[self] = map end
    map[slot_name:gsub("^slot_", "")] = item_key
end)

mod:hook_safe("MenuWorldPreviewer", "_spawn_item_unit", function(self, unit, slot_type, item_data, ...)
    if not unit or not _is_unit(unit) then return end
    local map = _mwp_pending_keys[self]
    local weapon_key = map and map[slot_type]
    if not weapon_key then return end
    local career_name = self._character_name or (self._profile and self._profile.name) or _local_career_name()
    if not career_name then return end
    local fake_slot = { right_unit_3p = unit, right_unit_1p = unit, left_unit_3p = unit, left_unit_1p = unit }
    _scale_units(fake_slot, weapon_key, career_name)
    _offset_units(fake_slot, weapon_key, career_name)
    _maybe_tint(weapon_key, unit)
end)
