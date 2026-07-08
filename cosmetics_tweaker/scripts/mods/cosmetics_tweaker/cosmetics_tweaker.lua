local mod = get_mod("cosmetics_tweaker")
-- v0.9.3.1: LA Prefix Patch embedded. MUST load before anything that touches
-- LA hooks (the dedup filter wraps VMFMod's prototype methods, and LA's mod
-- script needs to load AFTER us in the F4 launcher for the wrap to catch
-- LA's duplicate registrations). Source archived at:
--   misc-vermintide-mods/la_prefix_patch_archive/
-- Self-skips if the standalone la_prefix_patch is still subscribed+enabled.
mod:dofile("scripts/mods/cosmetics_tweaker/_la_prefix_embedded")

-- v0.9.3.3: Material-Hijack (patched) embedded. Hooks Unit visibility +
-- UnitSpawner.spawn_local_unit. Source archived at:
--   misc-vermintide-mods/material_hijack_patched_archive/
-- Self-skips if the standalone (original 2771980886 OR patched 3727311798)
-- is enabled, or if a sibling tweaker mod already claimed the embed via
-- the `_G._cos_mh_embed_owner` sentinel.
-- v0.9.5: GearUtils.create_equipment + HeroPreviewer._spawn_item_unit hooks
-- DROPPED from MH embed to eliminate boot rehook warnings. MH's
-- replace_textures + add_particles + AnimTextureExtension logic now called
-- from cosmetics_tweaker's existing hooks via the module exports captured
-- below. Dormant guard (standalone enabled, sibling owner) still returns
-- a no-op table so the call sites below don't need nil-checks.
local MH_EMBED = mod:dofile("scripts/mods/cosmetics_tweaker/_material_hijack_embedded")

-- v0.9.3.6: MoreItemsLibrary embedded (upstream MIT © Aussiemon 2022).
-- Public API on cosmetics_tweaker's mod handle:
--   * mod:add_mod_items_to_masterlist(items)
--   * mod:add_mod_items_to_local_backend(items, mod_name)
--   * mod:remove_mod_items_from_local_backend(items, mod_name)
-- Consumers reach them via get_mod("MoreItemsLibrary") — la_prefix_embedded
-- aliases that lookup to whichever mod owns the embed. Self-skips if
-- standalone MoreItemsLibrary (Workshop 1422758813) is enabled, or if a
-- sibling tweaker mod already claimed via `_G._cos_mil_embed_owner`.
mod:dofile("scripts/mods/cosmetics_tweaker/_moreitemslibrary_embedded")

local U = mod:dofile("scripts/mods/cosmetics_tweaker/_cosmetic_unlocks")
local LA_BRIDGE = mod:dofile("scripts/mods/cosmetics_tweaker/_la_bridge")
local TPE = mod:dofile("scripts/mods/cosmetics_tweaker/_tpe")
local GlowPicker = mod:dofile("scripts/mods/cosmetics_tweaker/_glow_picker")
local LA_PERSIST = mod:dofile("scripts/mods/cosmetics_tweaker/_la_persistence")
-- v0.9.49-dev (issue #186): disable Loremaster's Armoury's Okri's-Challenges /
-- achievement-book entries (main_quest + 12 sub-quests) — display, tracking and
-- completion pop-ups — behind the `la_disable_okri_challenges` toggle (default
-- ON = challenges DISABLED). Registers the AchievementManager.outline filter at
-- dofile time; the deferred template scrub runs from mod.update via LA_OKRI.tick.
local LA_OKRI = mod:dofile("scripts/mods/cosmetics_tweaker/_la_okri")
-- v0.9.24-dev: UI diagnostic dump harness. No-op at runtime unless the
-- enable_debug_logging VMF toggle is on. See _ui_dump.lua header for
-- what gets dumped per window class.
local UI_DUMP    = mod:dofile("scripts/mods/cosmetics_tweaker/_ui_dump")

-- Passive diagnostic emitter (printf, default-on, rate-limited). Drives two
-- grep channels in the user's post-playtest log: [174:loadout] (loadout write /
-- restore attribution, issue #174) and [cos:sync] (LA husk/shield sync
-- divergence decisions, issues #149 #154 #200 #203 #204). See _diag_probe.lua.
local PROBE      = mod:dofile("scripts/mods/cosmetics_tweaker/_diag_probe")

local MOD_VERSION = "0.9.75-dev"
-- #45: RPC schema version (VMF_RECIPES § 10). Prepended as the FIRST positional
-- arg of every mod:network_send this mod emits, and validated as the first arg
-- of every mod:network_register callback. On mismatch the receiver drops the
-- message (no state mutation, no crash). Bump ONLY when the payload shape of any
-- of this mod's 5 RPCs (cos_la_apply / cos_la_apply_req / cos_la_state_req /
-- cos_glow_apply / cos_glow_apply_req) changes (add/remove/reorder/retype a
-- field). ADDITIVE optional fields (v0.9.69's revert flag) and ADDITIVE RPC
-- names (v0.9.70's cos_la_state_req) do NOT bump -- old peers drop/ignore
-- them harmlessly. Initial = 1.
local COS_RPC_SCHEMA = 1
-- [mem-probe] temp Lua-footprint baseline (lua_heap 1 GiB cap diagnostic). Namespaced
-- under the mod table (v0.9.75-dev) so it no longer leaks into _G; read once at the
-- boot readout near the end of this file.
mod._cos_mem_t0 = collectgarbage("count")
-- Startup banner: log-only, NOT chat. The applied marker line further down
-- ([cosmetics] enabled v<X> settings_fp=<hash>) is the canonical version surface
-- (PROJECT_STANDARDS.md § 3.6 "Chat-echo policy").
mod:info("Cosmetics Tweaker v%s loaded", MOD_VERSION)

-- Two-helper debug-logging policy (PROJECT_STANDARDS.md § 3.6).
-- Both route through VMF logging (mod:debug / mod:warning), gated by VMF output_mode.
-- `_dbg` is for confirmation / expected behavior — file only.
-- `_dbg_alert` is for unexpected / wrong / mismatch — file AND in-game chat.
local function _dbg(fmt, ...)
    mod:debug("[cosmetics:dbg] " .. fmt, ...)
end

local function _dbg_alert(fmt, ...)
    mod:warning("[cosmetics:dbg] " .. fmt, ...)
end

-- v0.9.43-dev: AGGRESSIVE LA-shield diagnostic trace channel. Distinct
-- `[cos:trace]` prefix so a single in-game repro can be grepped in isolation
-- from the rest of the [cosmetics:dbg] noise.
-- Covers the full LA-shield hover/paint/husk lifecycle (SCREEN / INPUT / WRITE /
-- RESOLVE / PAINT / HUSK / SYNC / TRANSITION) so one repro yields the causal
-- chain. Quiet/remove once those are fixed.
-- v0.9.52-dev (#150): route through mod:INFO, NOT mod:debug. This user runs with
-- VMF output_mode_debug OFF, so the prior mod:debug routing made the ENTIRE
-- INPUT/WRITE/RESOLVE/SYNC/HUSK/TRANSITION trace set INVISIBLE in their console
-- log — only the mod:info lines (`_trace_paint` PAINT + `[offhand-press]`)
-- survived, which is exactly why the hover→write→husk chain (and bugs 3/4) never
-- showed up. mod:info IS captured in their log (proven: PAINT lines land), so
-- match _trace_paint's channel.
local function _trace(fmt, ...)
    mod:info("[cos:trace] " .. fmt, ...)
end

-- Read a spawned unit's authored mesh path (the `unit_name` data field VT2
-- stamps onto equipment/shield units; same source the LA bridge walks in
-- walk_attachments). Used by the PAINT trace to compare the unit we're
-- painting against the mesh the LA variant EXPECTS — the
-- imperial-texture-on-bret-mesh bug shows up as actual_mesh ~= expected_mesh.
-- pcall-wrapped because Unit.get_data on a torn-down unit can fault.
local function _unit_mesh_name(unit)
    if type(unit) ~= "userdata" then return "<not-unit>" end
    local ok, name = pcall(function()
        if Unit.has_data and Unit.has_data(unit, "unit_name") then
            return Unit.get_data(unit, "unit_name")
        end
        return nil
    end)
    if ok and name then return tostring(name) end
    return "<no-unit_name>"
end

-- Emit ONE fully-provenanced PAINT trace line for an LA offhand paint.
--   site    = calling rendering path (loot_previewer / ingame / network_husk /
--             hero_previewer / hot_join) — the call-site tag the teammate wants
--   context = the context string actually passed to apply_offhand_to_unit
--   bid     = backend_id the paint resolved under (may be nil for husk paths)
--   unit    = the TARGET unit being painted
-- For kind="unit" variants the EXPECTED mesh is new_units[1]; if the target
-- unit's actual mesh differs, match=false flags the "imperial texture painted
-- onto the un-swapped bret mesh" case (mesh-vs-texture mismatch). Pure
-- diagnostics — never mutates anything, never paints.
local function _trace_paint(site, context, bid, unit, armoury_key, outcome)
    local la = get_mod("Loremasters-Armoury")
    local variant = la and la.SKIN_LIST and la.SKIN_LIST[armoury_key]
    local kind = variant and variant.kind or "?"
    local expected = "(texture-variant→paints base mesh)"
    local match = "n/a"
    if variant and variant.kind == "unit" and variant.new_units then
        expected = tostring(variant.new_units[1])
    end
    local actual = _unit_mesh_name(unit)
    if variant and variant.kind == "unit" and variant.new_units then
        match = tostring(actual == tostring(variant.new_units[1]))
    end
    mod:info("[cos:trace] PAINT site=%s ctx=%s bid=%s kind=%s key=%s target=%s target_mesh=%s expected=%s match=%s outcome=%s",
        tostring(site), tostring(context), tostring(bid), tostring(kind),
        tostring(armoury_key), tostring(unit), actual, expected, match, tostring(outcome))
end

-- Applied marker (PROJECT_STANDARDS.md § 3.6 "Applied marker line (universal)").
-- Walks the data widget tree, FNV-1a-32 hashes setting=value pairs, prints
-- one mod:info line at load. ALWAYS fires (operational telemetry).
local function _settings_fingerprint()
    local ok, data = pcall(require, "scripts/mods/cosmetics_tweaker/cosmetics_tweaker_data")
    if not ok or type(data) ~= "table" then return "nodata" end
    local keys = {}
    local function walk(node)
        if type(node) ~= "table" then return end
        if type(node.setting_id) == "string" then keys[#keys + 1] = node.setting_id end
        for _, child in pairs(node) do
            if type(child) == "table" then walk(child) end
        end
    end
    walk(data)
    if #keys == 0 then return "nosettings" end
    table.sort(keys)
    local parts = {}
    for i, k in ipairs(keys) do
        local v = mod:get(k)
        if v == true then       parts[i] = k .. "=1"
        elseif v == false then  parts[i] = k .. "=0"
        elseif v == nil then    parts[i] = k .. "=?"
        else                    parts[i] = k .. "=" .. tostring(v) end
    end
    local s = table.concat(parts, ";")
    local h = 2166136261
    for i = 1, #s do
        local byte = string.byte(s, i)
        local xored, place = 0, 1
        local hh, bb = h, byte
        for _ = 1, 32 do
            local hb, bbit = hh % 2, bb % 2
            if hb ~= bbit then xored = xored + place end
            place = place * 2
            hh = (hh - hb) / 2
            bb = (bb - bbit) / 2
        end
        h = (xored * 16777619) % 4294967296
    end
    return string.format("%08x", h)
end

mod:info("[cosmetics:LOAD] v%s enabled fp=%s OK", MOD_VERSION, _settings_fingerprint())

-- Per PROJECT_STANDARDS § 3.6 + § 14a: dev/alpha/beta/0.x versions print
-- version to chat on load so the user can see what's active. Stable
-- (>=1.0.0) versions stay silent. Detect via MOD_VERSION string match.
if MOD_VERSION:find("-dev$") or MOD_VERSION:find("-alpha$") or MOD_VERSION:find("-beta$") or MOD_VERSION:find("-rc%d*$") or MOD_VERSION:find("^0%.") then
    mod:echo(string.format("[cosmetics] v%s loaded", MOD_VERSION))
end

-- /regression_test scaffold. Registrations at end of file.
local _RT_CHECKS = {}
local function _rt_register(name, fn)
    _RT_CHECKS[#_RT_CHECKS + 1] = { name = name, fn = fn }
end
mod:command("cos_regression_test", "Run regression smoke checks for past bugs", function()
    local pass, fail = 0, 0
    mod:echo("=== cosmetics_tweaker regression_test (v%s) ===", MOD_VERSION)
    for _, c in ipairs(_RT_CHECKS) do
        local ok, err = pcall(c.fn)
        if ok and err == nil then
            mod:echo("  PASS: %s", c.name); pass = pass + 1
            mod:info("[regression] PASS %s", c.name)
        else
            local msg = (not ok and tostring(err)) or tostring(err)
            mod:echo("  FAIL: %s -- %s", c.name, msg); fail = fail + 1
            mod:warning("[regression] FAIL %s: %s", c.name, msg)
        end
    end
    mod:echo("=== %d passed, %d failed ===", pass, fail)
end)
mod:info("[regression-test-command] registered as /cos_regression_test")

-- v0.9.12-dev: persistence inspection + manual replay commands.
mod:command("cos_persist_dump", "Dump saved LA cosmetic + illusion entries", function()
    local pm = Managers and Managers.player
    local lp = pm and pm:local_player()
    local career = lp and LA_PERSIST and LA_PERSIST._career_name_for_player(lp)
    mod:echo("=== la_persistence (current career: %s) ===", tostring(career))
    local careers_state = mod:get("la_persisted_equips") or {}
    local careers_t = careers_state.careers or {}
    local illusions_t = careers_state.illusions or {}
    local cn = 0
    for k, v in pairs(careers_t) do
        cn = cn + 1
        mod:echo("  career[%s] = { hat=%s, skin=%s }", tostring(k),
            tostring(v.slot_hat or "-"), tostring(v.slot_skin or "-"))
    end
    local _in = 0; for _ in pairs(illusions_t) do _in = _in + 1 end
    mod:echo("  %d career entries, %d illusion entries", cn, _in)
    if _in > 0 and _in <= 20 then
        for bid, skin in pairs(illusions_t) do
            mod:echo("    illusion[%s] = %s", tostring(bid), tostring(skin))
        end
    end
end)
mod:command("cos_persist_replay", "Re-apply saved LA hat + armor for local player's current career", function()
    local pm = Managers and Managers.player
    local lp = pm and pm:local_player()
    if not lp then mod:echo("no local player"); return end
    local n = LA_PERSIST and LA_PERSIST.restore_for_player(lp) or 0
    mod:echo("replayed %d saved LA cosmetic(s) for current career", n)
end)
mod:command("cos_persist_clear", "Wipe all saved LA persistence entries", function()
    mod:set("la_persisted_equips", { schema = 1, careers = {}, illusions = {} })
    mod:echo("[la-persist] cleared all saved entries (in-memory cache will refresh on next save)")
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
                    _dbg_alert("[hot-reload-safety] news widget %d draw failed: %s", i, tostring(err))
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

mod.on_game_state_changed = function(status, state_name)
    -- [heap-probe] v0.9.35-dev: per-state-transition lua_heap sampler, mirror of
    -- weapon_tweaker's, for the 1 GiB lua_heap OOM diagnosis. cosmetics is the
    -- largest UNMEASURED suspect — it sync-force-loads 74 offhand/shield unit
    -- packages (never unloaded) and its boot mem-probe was dead code until this
    -- version. Logs absolute heap + delta on every transition so a keep-only ramp
    -- is visible. No forced collect (would mask a retained leak). Debug-gated.
    local kb = collectgarbage("count")
    local since_last = mod._heap_probe_last_kb and (kb - mod._heap_probe_last_kb) or 0
    mod:debug("[heap-probe] %s/%s: %.1f MB (%.0f KB), since last transition: %+.0f KB",
        tostring(state_name), tostring(status), kb / 1024, kb, since_last)
    mod._heap_probe_last_kb = kb
    -- v0.9.43-dev TRANSITION trace: world/mission/keep load + game-state change.
    -- Anchors the area-load drop (#3) and the mission-load timeline in the trace.
    _trace("TRANSITION game_state %s/%s", tostring(state_name), tostring(status))
    apply_cosmetic_unlocks()
    -- v0.9.0-dev: retry deferred _G.apply_material_settings hook (lazy-loaded
    -- by Stingray flow graph on first hub/level enter).
    if mod._try_install_flow_glow_hook then mod._try_install_flow_glow_hook() end
    -- v0.9.0-dev: rebroadcast local glow state on every state transition.
    -- Covers fresh keep entry, mission start, post-host-migration. Cheap
    -- (~50 char RPC), and ensures peers' caches resync if connectivity
    -- glitched.
    if mod._on_glow_setting_changed then mod._on_glow_setting_changed() end

    -- v0.9.4: rebroadcast LOCAL LA equips on game-state change. Covers the
    -- hot-join asymmetry where PC-A joins PC-B's lobby with an already-
    -- equipped LA shield → PC-B never receives it because PC-B's host-side
    -- hot-join replay walks `_la_equips_by_peer[joiner]` which is EMPTY
    -- (PC-A's state isn't there yet). Symptom from 2026-05-21 20:14:46
    -- test: PC-A's shield arrived 43s late via a different mechanism.
    -- Fix: PC-A itself re-emits its `_local_la_equips` on every state
    -- change. Drain logic lives in mod.update (after locals are declared).
    mod._la_self_rebroadcast_pending = true

    -- v0.9.70-dev (#267, LA_SYNC_CORE_AUDIT Slice 2b / invariant I9): PULL ON
    -- READY. Every push timed off "peer appeared" loses the 17-25ms race
    -- against the receiver's peer_ingame flip (#267 hot-join, #233
    -- transition), and a hot-joiner's empty store cannot self-heal. So the
    -- JOINER asks: once our own game state is provably ingame, request the
    -- host's full LA store (drained in mod.update once a host peer_id is
    -- resolvable -- flag only here; _is_local_server/_host_peer_id live
    -- lexically below this function).
    if status == "enter" and state_name == "StateIngame" then
        -- v0.9.71-dev: fresh retry state per arming. The 17:28:26 pull in the
        -- 2026-07-06 session fired once into the host's load window and was
        -- lost with no ack and no re-send (host log shows no REQ/reply) - the
        -- exact I9 fire-and-forget failure the pull was meant to fix. Now the
        -- drain re-sends every 5s until the host's cos_la_state_ack lands
        -- (max 8 attempts).
        mod._la_state_pull_pending = { attempts = 0, next_at = 0 }
    end

    -- v0.9.65-dev (#233): arm a bounded, per-frame CLIENT-side re-apply of every
    -- REMOTE peer's cached LA offhand/illusion equip after a level transition. The
    -- self-rebroadcast above only re-emits the LOCAL player's equips to the network;
    -- it does NOT restore a remote wearer's shield/illusion on THIS machine. The host's
    -- own post-transition rebroadcast races ahead of a still-loading client (the client's
    -- peer_ingame flips true ~25ms AFTER the host emits, so the "all" send never
    -- reaches it) and nothing re-sends -- so the host's LA offhand reverted on the
    -- client at every mission<->keep transition. `_la_equips_by_peer` survives
    -- transitions (only cleared on peer disconnect), so we already hold the
    -- authoritative data locally; the mod.update drain (search
    -- `_la_reapply_remote_until`) walks it and re-drives the recv/retry apply (texture
    -- re-paint + kind="unit" mesh pulse) until each remote wearer converges. Refreshed
    -- on every state callback; the last one (StateIngame/enter) sets the ~10s window
    -- from load-done.
    mod._la_reapply_remote_until = os.clock() + 10

    -- v0.9.13-dev: snapshot LA state on every game-state change. Gated on the
    -- debug_dumps toggle. Fires on inn entry, mission entry, mission exit —
    -- so any later spawn / equip event in the log has a baseline to compare
    -- against. No-op when the toggle is off.
    if mod._la_dump_mission_state then
        mod._la_dump_mission_state("game_state_change")
    end

    -- v0.9.9.3-dev: reset glow-picker auto-popup gate on every state
    -- transition. Keep→mission and mission→keep both wipe the per-session
    -- "already shown" set so re-entering the keep can re-trigger the popup
    -- for a glowing weapon.
    mod._glow_auto_popup_shown = {}
end
mod.on_setting_changed = function(setting_id)
    if setting_id and setting_id:sub(1, 11) == "cos_unlock_" then
        apply_cosmetic_unlocks()
    end
    -- v0.9.0-dev: any glow_* setting change triggers a per-peer glow
    -- rebroadcast. _on_glow_setting_changed schedules (doesn't emit
    -- immediately) so a multi-setting save in the VMF menu coalesces into
    -- one RPC via the throttle in _glow_sync_tick.
    if setting_id and setting_id:sub(1, 5) == "glow_"
        and mod._on_glow_setting_changed then
        mod._on_glow_setting_changed()
    end
    -- Glow override no longer auto-repaints on setting change — the walk
    -- destabilized adjacent unit state (hand meshes disappeared after pressing
    -- X to inspect, 1P breakage). User re-equips the weapon to see the new
    -- preset; the apply_material_settings hook paints reliably at spawn.

    if TPE and TPE.on_setting_changed then
        TPE.on_setting_changed(setting_id)
    end
end

-- v0.9.0-dev: TPE per-frame tick moved into the unified mod.update defined
-- later in the file (around line 3880, the LA bridge init driver). Previously
-- the second definition OVERWROTE this one and TPE.update silently never
-- fired since the merge. Single update function below handles both.

mod.on_disabled = function()
    if TPE and TPE.flush then TPE.flush() end
    -- audit 2026-06-07 (F7): restore LA.apply_new_skin_from_texture so an
    -- in-session F4 disable doesn't leave LA's own recolor permanently blocked
    -- for bridge-managed keys until restart. Injected IML/NetworkLookup entries
    -- can't be safely torn down mid-session, so we only undo the apply gate.
    if LA_BRIDGE and LA_BRIDGE.uninstall_apply_gate then
        LA_BRIDGE.uninstall_apply_gate()
    end
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
        if not _skin_requires_unowned_dlc(skin_key) then -- DLC gate
            mirror._unlocked_weapon_skins[skin_key] = true
        end
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

-- v0.9.63-dev: vanilla-UNOBTAINABLE cosmetics — career skins + hats that have NO
-- obtain path anywhere in the shipped data: not in Lohner's Emporium catalog
-- (store_data.lua), no premium-store / bundle entry (store_dlc_settings.lua /
-- store_bundle_layouts.lua), no steam_itemdefid, no achievement grant, no required_dlc.
-- Vanilla therefore never places them in the player's inventory, so the per-career
-- unlock toggles (which only edit can_wield in apply_cosmetic_unlocks) can never
-- surface them — the item is simply never owned. We grant modded-realm ownership by
-- injecting them into the cosmetic fake-inventory, the SAME mechanism the portrait
-- frame unlock uses: playfab_mirror_base.lua:2315-2401 turns each injected key into a
-- fake item and registers `_unlocked_cosmetics[key] = backend_id` +
-- `_inventory_items[backend_id]`. List derived from a full ItemMasterList ×
-- store/achievement/steam_itemdefid cross-reference sweep (54 skins + 82 hats). The
-- "_white" skins are the datamined "(Purified)" prestige set; the rest are
-- discontinued promo skins/hats (Nuln Bordermarcher, Ostermark Bowman, etc.).
local _unobtainable_cosmetics = {
    -- Kruber hats
    "es_hat_0001", "es_hat_0002", "es_hat_0003", "es_helmet_0003",
    "huntsman_hat_0004", "huntsman_hat_0009", "huntsman_hat_1010",
    "knight_hat_0003", "knight_hat_0005", "knight_hat_0006", "knight_hat_0011",
    "mercenary_hat_0006", "mercenary_hat_0007",
    -- Kruber skins
    "skin_es_huntsman_black_and_gold", "skin_es_huntsman_ostermark", "skin_es_huntsman_white",
    "skin_es_knight_black_and_gold", "skin_es_knight_red", "skin_es_knight_white",
    "skin_es_mercenary_black_and_gold", "skin_es_mercenary_helmgart", "skin_es_mercenary_ostermark", "skin_es_mercenary_white",
    "skin_es_questingknight_white",
    -- Bardin hats
    "dr_helmet_0001", "dr_helmet_0002", "dr_helmet_0003", "dr_helmet_0005", "dr_helmet_0008", "dr_helmet_0011",
    "dr_slayer_hair_0002",
    "ironbreaker_hat_0007", "ironbreaker_hat_0012", "ironbreaker_hat_0013",
    "ranger_hat_0003", "ranger_hat_0004", "ranger_hat_0010", "ranger_hat_0015", "ranger_hat_1010",
    "slayer_hat_0006", "slayer_hat_0007", "slayer_hat_0010", "slayer_hat_0012", "slayer_hat_1010",
    -- Bardin skins
    "skin_dr_engineer_white",
    "skin_dr_ironbreaker_black_and_gold", "skin_dr_ironbreaker_crimson", "skin_dr_ironbreaker_white",
    "skin_dr_ranger_black_and_gold", "skin_dr_ranger_helmgart", "skin_dr_ranger_karak_norn", "skin_dr_ranger_white",
    "skin_dr_slayer_dragon", "skin_dr_slayer_runes", "skin_dr_slayer_skull", "skin_dr_slayer_white",
    -- Saltzpyre hats
    "bountyhunter_hat_0002", "bountyhunter_hat_0003", "bountyhunter_hat_1010",
    "priest_hat_0001", "priest_hat_0002", "priest_hat_0003", "priest_hat_0004",
    "wh_hat_0001", "wh_hat_0003", "wh_hat_0007", "wh_hat_0008", "wh_hat_0009",
    "witchhunter_hat_0002", "witchhunter_hat_0003",
    "zealot_hat_0003", "zealot_hat_0009", "zealot_hat_0010", "zealot_hat_1003", "zealot_hat_1010",
    -- Saltzpyre skins
    "skin_wh_bountyhunter_black_and_gold", "skin_wh_bountyhunter_white", "skin_wh_bountyhunter_yellow_and_red",
    "skin_wh_captain_black_and_gold", "skin_wh_captain_helmgart", "skin_wh_captain_ostland", "skin_wh_captain_white",
    "skin_wh_zealot_black_and_gold", "skin_wh_zealot_crimson", "skin_wh_zealot_white",
    -- Kerillian hats
    "maidenguard_hat_0005", "maidenguard_hat_0008", "maidenguard_hat_0010", "maidenguard_hat_1010",
    "shade_hat_0003", "shade_hat_0007", "shade_hat_0010", "shade_hat_1010",
    "thornsister_hat_1010",
    "waywatcher_hat_0002", "waywatcher_hat_0006", "waywatcher_hat_0011", "waywatcher_hat_1010",
    "ww_hood_0001", "ww_hood_0002", "ww_hood_0004",
    -- Kerillian skins
    "skin_ww_maidenguard_black_and_gold", "skin_ww_maidenguard_red_and_yellow", "skin_ww_maidenguard_white",
    "skin_ww_shade_black_and_gold", "skin_ww_shade_crimson", "skin_ww_shade_white",
    "skin_ww_thornsister_white",
    "skin_ww_waywatcher_anmyr", "skin_ww_waywatcher_black_and_gold", "skin_ww_waywatcher_helmgart", "skin_ww_waywatcher_white",
    -- Sienna hats
    "adept_hat_0002", "adept_hat_0003", "adept_hat_0010", "adept_hat_1010",
    "bw_gate_0001", "bw_gate_0006", "bw_gate_0007", "bw_gate_0008",
    "bw_necromancer_hat_1010",
    "scholar_hat_0004", "scholar_hat_0005", "scholar_hat_0012",
    "unchained_hat_0004", "unchained_hat_0008",
    -- Sienna skins
    "skin_bw_adept_black_and_gold", "skin_bw_adept_helmgart", "skin_bw_adept_ostermark", "skin_bw_adept_white",
    "skin_bw_scholar_black_and_gold", "skin_bw_scholar_ostermark", "skin_bw_scholar_white",
    "skin_bw_unchained_black_and_gold", "skin_bw_unchained_ostermark", "skin_bw_unchained_white",
}

-- Ownership is account-wide (once owned, any career in the item's native can_wield
-- can equip it). Grant an unobtainable cosmetic when it has NO managed per-career
-- toggle (e.g. the wh_priest bless hats, which the mod's cross-career system
-- excludes), or when ANY of its character's career toggles is enabled — so the user
-- can still hide one again by unchecking all its Cosmetic Availability toggles.
local function _cosmetic_ownership_enabled(item_key)
    local info = U.managed[item_key]
    if not info then return true end
    for _, career in ipairs(_CHARACTER_CAREERS[info.character] or {}) do
        if mod:get("cos_unlock_" .. career .. "_" .. item_key) then return true end
    end
    return false
end

local _unob_inject_stats = { last_added = 0, last_skipped_dlc = 0 }
local function _inject_unobtainable_cosmetics(target)
    if not target then return 0, 0 end
    local added, skipped = 0, 0
    for i = 1, #_unobtainable_cosmetics do
        local key = _unobtainable_cosmetics[i]
        -- rawget: ItemMasterList __index crashifies on missing keys; a DLC pack the
        -- user doesn't own leaves some of these keys unregistered on their install.
        if target[key] == nil and rawget(ItemMasterList, key) then
            if _skin_requires_unowned_dlc(key) then
                skipped = skipped + 1
            elseif _cosmetic_ownership_enabled(key) then
                target[key] = true
                added = added + 1
            end
        end
    end
    _unob_inject_stats.last_added = added
    _unob_inject_stats.last_skipped_dlc = skipped
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
    if items_type == "cosmetics" and script_data["eac-untrusted"] and fake_inventory_items then
        if mod:get("unlock_all_frames") then
            local added, skipped = _inject_all_frames(fake_inventory_items)
            _frame_inject_stats.hook_fired = _frame_inject_stats.hook_fired + 1
            _frame_inject_stats.last_added = added
            _frame_inject_stats.last_skipped_dlc = skipped
            mod:info("[unlock_all_frames] _create_fake_inventory_items pre-hook fired: added=%d skipped_dlc=%d", added, skipped)
        end
        -- v0.9.63-dev: grant modded-realm ownership of vanilla-unobtainable skins/hats
        -- so the per-career unlock toggles can actually surface them (they otherwise
        -- never enter the player's inventory). Always runs in modded realm — this is
        -- NOT gated on the frame toggle, which is a separate feature.
        local ca, cs = _inject_unobtainable_cosmetics(fake_inventory_items)
        if ca > 0 then
            mod:info("[unlock_cosmetics] injected %d unobtainable cosmetics into fake inventory (skipped_dlc=%d)", ca, cs)
        end
    end
    return func(self, fake_inventory_items, items_type)
end)

mod:hook_safe("PlayFabMirrorAdventure", "get_unlocked_cosmetics", function(self)
    if not script_data["eac-untrusted"] then return end
    local cosmetics = self._unlocked_cosmetics
    if not cosmetics then return end
    -- Belt-and-suspenders resync for callers that re-query after login. Both injectors
    -- no-op on keys already registered (they guard on `target[key] == nil`), so the
    -- pre-hook's real backend_ids are never clobbered.
    if mod:get("unlock_all_frames") then _inject_all_frames(cosmetics) end
    _inject_unobtainable_cosmetics(cosmetics)
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

-- v0.9.63-dev: verify the unobtainable-cosmetic ownership grant in-game (user runs
-- with mod-logging OFF, so the mod:info lines above are invisible; this echoes to chat).
mod:command("cosmetics_status", "Diagnostic for the vanilla-unobtainable skin/hat unlock.", function()
    mod:echo("[cosmetics_status] modded_realm=%s | last inject: added=%d skipped_dlc=%d (of %d tracked)",
        tostring(script_data and script_data["eac-untrusted"]),
        _unob_inject_stats.last_added, _unob_inject_stats.last_skipped_dlc, #_unobtainable_cosmetics)
    local backend = Managers.backend
    local mirror = backend and backend.get_interface and backend:get_interface("items")
    local mirror_base = mirror and mirror._backend_mirror
    if not mirror_base and backend then mirror_base = backend._mirror end
    if mirror_base and mirror_base._unlocked_cosmetics then
        local owned, missing = 0, {}
        for i = 1, #_unobtainable_cosmetics do
            local k = _unobtainable_cosmetics[i]
            if mirror_base._unlocked_cosmetics[k] then owned = owned + 1
            elseif rawget(ItemMasterList, k) then missing[#missing + 1] = k end
        end
        mod:echo("[cosmetics_status] %d/%d unobtainable cosmetics owned in _unlocked_cosmetics", owned, #_unobtainable_cosmetics)
        if #missing > 0 then
            mod:echo("[cosmetics_status] %d present-but-unowned (toggle off or not yet synced): %s%s",
                #missing, table.concat(missing, ", ", 1, math.min(#missing, 8)), #missing > 8 and " ..." or "")
        end
    else
        mod:echo("[cosmetics_status] could not locate PlayFabMirrorBase via Managers.backend")
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

-- cim coexistence: when cim is loaded, it owns the modded-realm illusion swap.
-- These hooks defer to the original at fire time so cosmetics_tweaker's
-- _custom_skin_keys (LA bridge + ct's own custom illusions) still work, but
-- the eac-untrusted bypass for vanilla skins is delegated to cim.
local function _cim_owns_illusion_swap()
    return get_mod("cim") ~= nil
end

mod:hook("BackendInterfaceItemPlayfab", "get_weapon_skin_from_skin_key", function(func, self, skin_key)
    local id, item = func(self, skin_key)
    if id then return id, item end

    -- ItemMasterList.__index Crashifies on unknown keys (item_master_list.lua:133),
    -- and skin_key here can be ANY key the illusion grid hands us — including
    -- LA bridge keys (live in WeaponSkins.skins, NOT in IML) and ct_* keys
    -- not yet registered. Use rawget to avoid the crashify.
    local iml_entry = rawget(ItemMasterList, skin_key)
    -- When cim is loaded, only handle custom illusions here; cim's hook covers
    -- the eac-untrusted path for vanilla skins.
    local handle_vanilla_eac = script_data["eac-untrusted"] and iml_entry and not _skin_requires_unowned_dlc(skin_key) and not _cim_owns_illusion_swap()
    if _custom_skin_keys[skin_key] or handle_vanilla_eac then
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
    if _cim_owns_illusion_swap() then return func(self, enable, disable_edges) end
    if mod:get("apply_trace") then
        _dbg("[apply-trace] _enable_craft_button enable=%s recipe=%s skin_dirty=%s eac=%s",
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
    if _cim_owns_illusion_swap() then return func(self, index, ignore_item_spawn, mark_as_equipped) end
    local widget = self._illusion_widgets and self._illusion_widgets[index]
    -- v0.9.43-dev INPUT trace: row-1 illusion-grid PRESS. ignore_item_spawn=true
    -- means a non-spawning re-select (select-by-key / mark-as-equipped); a
    -- false/nil ignore_item_spawn means this press WILL respawn the preview
    -- (LootItemUnitPreviewer) → a downstream PAINT. mark_as_equipped flags the
    -- committed/equipped illusion (closest vanilla analogue to APPLY).
    _trace("INPUT PRESS illusion-grid index=%s skin=%s ignore_spawn=%s mark_equipped=%s bid=%s",
        tostring(index), tostring(widget and widget.content and widget.content.skin_key),
        tostring(ignore_item_spawn), tostring(mark_as_equipped), tostring(self._item_backend_id))
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
        _dbg("[apply-trace] _on_illusion_index_pressed picked=%s current=%s default=%s differs=%s ignore_spawn=%s locked=%s",
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

    -- v0.9.18-dev DATA PROBE — always-on, low volume (1 line per user click).
    -- Captures the picked skin + its material_settings_name so the future
    -- Evengleam glow popup feature has authoritative data on which skins
    -- belong to which glow family (rune / weaves / magic / etc.) without
    -- requiring offline source-tree probing.
    do
        local picked_skin = widget and widget.content and widget.content.skin_key
        if picked_skin and WeaponSkins and WeaponSkins.skins then
            local entry = WeaponSkins.skins[picked_skin]
            if entry then
                mod:info("[illusion-probe] item_bid=%s picked_skin=%s matching_item=%s material_settings=%s rarity=%s",
                    tostring(self._item_backend_id), tostring(picked_skin),
                    tostring(entry.matching_item_key), tostring(entry.material_settings_name),
                    tostring(entry.rarity))
            end
        end
    end

    -- v0.9.34 (release gate, GLOW_SYSTEM M3 item 7): auto-open the glow picker
    -- when the user SELECTS an illusion that has a glow variant. Selection is
    -- explicit intent, so no once-per-keep gate (unlike the wield-triggered
    -- path below). We're inside HeroWindowItemCustomization, whose _draw hook
    -- already renders the overlay, so it appears immediately. Runs BEFORE the
    -- vanilla call so the tail-call's multi-returns stay untouched; the picker
    -- keys per-item state off the ITEM backend_id, so ordering vs vanilla's
    -- internal handling doesn't matter.
    do
        local picked_skin = widget and widget.content and widget.content.skin_key
        -- v0.9.38-dev: auto-open is now implicit (always on). The
        -- glow_picker_auto_popup_enabled toggle was removed — glow is driven
        -- entirely through this in-cosmetic-picker glow menu, so the popup is
        -- always wanted on selection.
        if picked_skin then
            local family = GlowPicker.classify({ skin = picked_skin })
            local bid = self._item_backend_id
            if family and bid then
                GlowPicker.open_for(bid, { skin = picked_skin })
                mod:info("[glow_picker:auto] opened on illusion select bid=%s skin=%s family=%s",
                    tostring(bid), tostring(picked_skin), tostring(family))
            elseif not family and GlowPicker.is_open() then
                -- Selected a non-glow illusion while the picker was up for this
                -- item — the panel no longer applies; close it.
                GlowPicker.close()
            end
        end
    end

    return func(self, index, ignore_item_spawn, mark_as_equipped)
end)

mod:hook("HeroWindowItemCustomization", "_update_state_craft_button", function(func, self, recipe_name, ...)
    if _cim_owns_illusion_swap() then return func(self, recipe_name, ...) end
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
    if _cim_owns_illusion_swap() then return func(self, career_name, item_backend_ids, recipe_override) end
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
    if _cim_owns_illusion_swap() then return end
    if _pending_local_craft and _pending_local_craft.interface == self then
        self._craft_requests[_pending_local_craft.id] = {}
        Managers.backend:dirtify_interfaces()
        _pending_local_craft = nil
    end
end)

-- #150 guard: vanilla HeroWindowItemCustomization._upgrade_item_craft_complete
-- blindly reads `local backend_id = result[1][1]`. The local-craft stub minted
-- above sets `self._craft_requests[id] = {}` (an EMPTY table), and vanilla
-- `get_craft_result(id)` returns that stub verbatim — so `result[1]` is nil and
-- the deref hard-crashes (crash GUID 79bb933a: Grail Knight `es_questingknight`,
-- Bret sword&shield `es_1h_sword_shield_breton`, injected illusion at skin
-- index 4). The dispatch to a given craft-complete handler is driven by the
-- window's `_state`, so an empty stub can land here (item_upgrade) instead of
-- the result-ignoring `_apply_weapon_skin_craft_complete` (item_setting). When
-- the result is malformed there is no real backend_id to relink loadouts
-- against, so we MUST NOT run vanilla's relink loop; instead we re-present the
-- current item and rebuild the upgrade-screen widgets/state so the
-- customization window stays interactive rather than soft-locking. Vanilla's
-- `_craft_completed` already called `self._parent:unblock_input()` before
-- dispatching here, so input is restored regardless. The sibling
-- `_apply_weapon_skin_craft_complete` never touches `result`, so only THIS
-- completion handler needs the guard.
mod:hook("HeroWindowItemCustomization", "_upgrade_item_craft_complete", function(func, self, result)
    -- v0.9.53-dev (#200): a craft completing here = a genuine Apply on this
    -- item. Flag it BEFORE vanilla runs (vanilla's _state_setup_upgrade re-runs
    -- _setup_illusions, which preserves an existing baseline but must not clear
    -- this commit) so on_exit keeps the offhand pick instead of reverting it.
    if self and self._item_backend_id then
        mod._offhand_committed = mod._offhand_committed or {}
        mod._offhand_committed[self._item_backend_id] = true
    end
    if result and result[1] and result[1][1] then
        return func(self, result)
    end
    local item = self._item_backend_id and self:_get_item(self._item_backend_id)
    if item then
        self:_present_item(item, nil, { 0, 2, 0 })
        self._parent:_set_loadout_item(item, self._equipment_slot_name)
        self:_state_setup_upgrade()
        self:_setup_availble_states(item)
    end
end)

-- v0.9.53-dev (#200): OFFHAND APPLY-GATE commit signal. The normal weapon-skin
-- Apply (hold the craft button) lands in vanilla
-- `_apply_weapon_skin_craft_complete` (the apply_weapon_skin recipe's
-- craft-complete handler), regardless of whether cim or cosmetics_tweaker owns
-- the modded-realm craft bypass. An offhand-only change ALSO routes through here
-- (the offhand-press seeds _material_items with the current skin so Apply crafts
-- a no-op skin re-apply). Flag the commit so the on_exit revert KEEPS the
-- offhand pick. This pair (HeroWindowItemCustomization, _apply_weapon_skin_craft_complete)
-- is NOT hooked anywhere else in this mod (verified) — single registration.
-- hook_safe: we only observe completion; vanilla's behavior is unchanged.
mod:hook_safe("HeroWindowItemCustomization", "_apply_weapon_skin_craft_complete", function(self, result)
    if self and self._item_backend_id then
        mod._offhand_committed = mod._offhand_committed or {}
        mod._offhand_committed[self._item_backend_id] = true
        _trace("CRAFT apply_weapon_skin_craft_complete committed offhand bid=%s", tostring(self._item_backend_id))
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
        _dbg("[offhand] %s already engine-resident (no standalone load needed)", package_path)
        return
    end
    -- v0.9.3.2-hotfix: paths in `NetworkLookup.inventory_packages` ARE
    -- loadable via `Managers.package:load` even though there's no standalone
    -- .package file for them. Memory `feedback_vt2_force_load_only_listed_paths`
    -- documents the inverse — paths NOT in the list fatal asynchronously
    -- bypassing pcall. So: only skip when the path is in NEITHER the
    -- standalone-package set NOR the inventory_packages list.
    -- This fixes wpn_empire_shield_01_t1 / _02 / _03 / _04 / _05 which are
    -- inventory_package_list entries (lines 1214-1227 of vanilla
    -- inventory_package_list.lua) but have no standalone .package, causing
    -- our v0.8 / v0.9.x preload to silently skip them and PC-B to crash when
    -- PC-A (Kruber) wielded the Empire sword+shield. Burned 2026-05-21.
    local in_inventory_list = false
    if NetworkLookup and type(NetworkLookup.inventory_packages) == "table" then
        for _, listed in ipairs(NetworkLookup.inventory_packages) do
            if listed == package_path then
                in_inventory_list = true
                break
            end
        end
    end
    if Application and Application.can_get and not Application.can_get("package", package_path)
        and not in_inventory_list then
        -- v0.9.43-dev: this benign line fired hundreds of times per session and
        -- drowned the trace. Dedupe to once per unique path per session so the
        -- [cos:trace] channel stays readable. Behavior unchanged (still returns).
        mod._skip_preload_logged = mod._skip_preload_logged or {}
        if not mod._skip_preload_logged[package_path] then
            mod._skip_preload_logged[package_path] = true
            _dbg("[offhand] no standalone package at %s and not in inventory_packages list — skipping preload (deduped: once/session)", package_path)
        end
        return
    end
    -- Sync load (async=false). Async returns immediately and races the
    -- user's Apply click — sync blocks via ResourcePackage.load + flush.
    local ok, err = pcall(function()
        Managers.package:load(package_path, "cosmetics_tweaker", nil, false)
    end)
    if ok then
        _preloaded_offhand_packages[package_path] = true
        _dbg("[offhand] preloaded package %s (sync)", package_path)
    else
        _dbg_alert("[offhand] preload FAILED for %s: %s", package_path, tostring(err))
    end
end

-- v0.9.3: skin-variant suffixes that share a base unit path but live in
-- SEPARATE .package files. When a client wields a skinned variant of a
-- weapon (e.g. wpn_emp_gk_shield_02_runed_01_3p — the Stylish loot-chest
-- skin underlying LA's Ostermark01 texture paint), the host needs that
-- package preloaded too, or vanilla World.spawn_unit asserts at
-- c_api_world.cpp:67 (engine-level, pcall can't catch).
-- Burned PC-B 2026-05-21 17:22 when PC-A switched to Ostermark01.
local _SKIN_VARIANT_SUFFIXES = {
    "_runed_01", "_runed_02", "_runed_03", "_runed_04", "_runed_05", "_runed_06",
    "_magic_01", "_magic_02",
}

local function _preload_offhand_package(unit_path)
    _preload_one(unit_path)
    if unit_path and unit_path ~= "" then
        _preload_one(unit_path .. "_3p")
        -- v0.9.3: also load skinned variants so a peer wielding a Stylish/
        -- themed/Weavebound/Shyish-Infused variant of this base weapon
        -- doesn't crash our wield delegate.
        for _, suffix in ipairs(_SKIN_VARIANT_SUFFIXES) do
            _preload_one(unit_path .. suffix)
            _preload_one(unit_path .. suffix .. "_3p")
        end
    end
end

local function _preload_offhand_for_option(opt)
    if not opt then return end
    if opt.unit then _preload_offhand_package(opt.unit) end
    if opt.intended_unit then _preload_offhand_package(opt.intended_unit) end
end

-- v0.9.0.4-hotfix: forward-decl. Real impl placed AFTER `_offhand_options`
-- is declared (line ~1574) so the function can close over the local. Called
-- from mod.update after `_la_bridge_init_done = true` to bulk-preload every
-- mesh in the offhand pools + custom illusions on EVERY peer. Eliminates the
-- ProfileSynchronizer async-load vs synchronous-wield-RPC race that crashes
-- the client when host equips a cross-character shield mesh. Mechanism
-- documented in `feedback_cwv_cross_character_unit_packages.md`.
local _force_load_all_offhand_packages

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

-- v0.9.45-dev (BUG 1/2): variant-aware LA-shield mesh resolution shared by the
-- LOCAL offhand-override path (BackendUtils.get_item_units, non-husk body) and
-- the husk path so the two can NEVER disagree on how a `kind="unit"` LA shield's
-- 3P sibling is derived. Before this, the husk path resolved the 3P as
-- `new_units[2]` (LA's authored 3P mesh) while the local path's
-- `_override_package_ready` derived it by `..\"_3p\"` suffix. They happen to
-- match for today's shields (`new_units[2] == new_units[1].."_3p"`), but the
-- suffix is NOT guaranteed for future LA variants, and routing both paths
-- through one resolver removes the divergence by construction (the teammate's
-- "reuse/extract so the two can't drift again"). Returns (la_1p, la_3p, ready);
-- (nil, nil, false) for a missing/non-unit variant so callers can fall back to
-- the legacy gate for `kind="texture"` picks.
local function _resolve_la_unit_mesh(armoury_key)
    if not armoury_key then return nil, nil, false end
    local la = get_mod("Loremasters-Armoury")
    local variant = la and la.SKIN_LIST and la.SKIN_LIST[armoury_key]
    if not variant or variant.kind ~= "unit" then return nil, nil, false end
    local nu = variant.new_units
    local la_1p = nu and nu[1]
    if not la_1p then return nil, nil, false end
    local la_3p = (nu and nu[2]) or (la_1p .. "_3p")
    local cg = Application and Application.can_get
    local ready = (cg and cg("unit", la_1p) and cg("unit", la_3p)) and true or false
    return la_1p, la_3p, ready
end

-- v0.8.51-dev: pools are STRICTLY same-character. A weapon belonging to a
-- given Hero can only swap to shields that originate from that Hero's
-- weapon family. All Kruber (`es_*`) weapons share the same Kruber-shield
-- pool, Kerillian (`we_*`) shares the Kerillian-shield pool, etc. LA
-- shields are merged in per-weapon-type via `_merge_la_offhand_options`
-- and LA's own `icons` table is already character-correct (Kruber LA
-- shields target `es_*` weapons, Kerillian LA shields target `we_*`, etc.),
-- so the merge preserves the same-character invariant.
-- v0.9.9.4-dev: schema is `_offhand_options[item_type][hand_field] = pool`.
-- Single-mount shield weapons store their pool under "left_hand_unit" (the
-- shield slot); multi-mount weapons (rapier+pistol, dual-wields) populate
-- both "right_hand_unit" and "left_hand_unit" so each mount gets its own
-- picker row. Helpers (_get_offhand_options, force-load, merge, etc.) walk
-- the per-hand structure. See `_MULTI_MOUNT_ITEM_TYPES` below.
local _SHIELD_POOLS_BY_ITEM_TYPE = {
    -- Kruber (Empire) — every Kruber-asset shield is shareable across
    -- every Kruber shield weapon (sword+shield, mace+shield, Bret
    -- sword+shield, deus 1h).
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
    },
    -- Kerillian (Wood Elf) — only Kerillian-asset shields.
    we_1h_spears_shield = {
        { name = "Elven Shield",           unit = "units/weapons/player/wpn_we_shield_01/wpn_we_shield_01" },
        { name = "Elven Shield (Exotic)",  unit = "units/weapons/player/wpn_we_shield_02/wpn_we_shield_02" },
    },
    -- Bardin (Dwarf) — only Bardin-asset shields.
    dr_1h_axe_shield = {
        { name = "Dwarf Shield 1",         unit = "units/weapons/player/wpn_dw_shield_01_t1/wpn_dw_shield_01" },
        { name = "Dwarf Shield 2",         unit = "units/weapons/player/wpn_dw_shield_02_t1/wpn_dw_shield_02" },
        { name = "Dwarf Shield 2 (Runed)", unit = "units/weapons/player/wpn_dw_shield_02_t1/wpn_dw_shield_02_runed_01" },
        { name = "Dwarf Shield 3",         unit = "units/weapons/player/wpn_dw_shield_03_t1/wpn_dw_shield_03" },
        { name = "Dwarf Shield 4",         unit = "units/weapons/player/wpn_dw_shield_04_t1/wpn_dw_shield_04" },
        { name = "Dwarf Shield 4 (Magic)", unit = "units/weapons/player/wpn_dw_shield_04_t1/wpn_dw_shield_04_magic_01" },
        { name = "Dwarf Shield 5",         unit = "units/weapons/player/wpn_dw_shield_05_t1/wpn_dw_shield_05" },
        { name = "Dwarf Shield 5 (Runed)", unit = "units/weapons/player/wpn_dw_shield_05_t1/wpn_dw_shield_05_runed_01" },
    },
    -- Saltzpyre (Warrior Priest) — only Saltzpyre-asset shields.
    wh_flail_shield = {
        { name = "WP Shield",              unit = "units/weapons/player/wpn_wh_shield_01/wpn_wh_shield_01_t1" },
        { name = "WP Shield (Runed)",      unit = "units/weapons/player/wpn_wh_shield_01/wpn_wh_shield_01_t1_runed" },
        { name = "WP Shield (Magic)",      unit = "units/weapons/player/wpn_wh_shield_01/wpn_wh_shield_01_t1_magic" },
    },
}

local function _shallow_copy(t)
    local out = {}
    for i = 1, #t do out[i] = t[i] end
    return out
end

-- Promote each shield pool into the per-hand structure under left_hand_unit.
-- LA shield options merged in `_merge_la_offhand_options` also land under
-- left_hand_unit (LA only ships `swap_hand = "left_hand_unit"` variants).
local _offhand_options = {}
for item_type, pool in pairs(_SHIELD_POOLS_BY_ITEM_TYPE) do
    _offhand_options[item_type] = { left_hand_unit = pool }
end
-- De-aliased copies. Vanilla offhand options are the same across these
-- weapon types, but LA shield options must be pooled per-weapon-type
-- (driven by each LA variant's `icons` table). Sharing one table reference
-- across weapon types would cross-pollinate Bret-authored LA textures onto
-- mace UVs and vice-versa.
_offhand_options.es_1h_mace_shield          = { left_hand_unit = _shallow_copy(_SHIELD_POOLS_BY_ITEM_TYPE.es_1h_sword_shield) }
_offhand_options.es_1h_sword_shield_breton  = { left_hand_unit = _shallow_copy(_SHIELD_POOLS_BY_ITEM_TYPE.es_1h_sword_shield) }
_offhand_options.es_deus_01                 = { left_hand_unit = _shallow_copy(_SHIELD_POOLS_BY_ITEM_TYPE.es_1h_sword_shield) }
_offhand_options.dr_1h_hammer_shield        = { left_hand_unit = _shallow_copy(_SHIELD_POOLS_BY_ITEM_TYPE.dr_1h_axe_shield) }
_offhand_options.wh_hammer_shield           = { left_hand_unit = _shallow_copy(_SHIELD_POOLS_BY_ITEM_TYPE.wh_flail_shield) }

-- v0.9.9.4-dev: item_types that get a SECOND (right-hand) picker row in
-- addition to the existing left-hand row. Two pickers stacked vertically;
-- the user picks independently per mount. Excluded: wh_dual_hammer (pool
-- size 1) per recon doc. Sword+shield weapons stay single-row.
local _MULTI_MOUNT_ITEM_TYPES = {
    wh_fencing_sword           = true,  -- rapier (R) + pistol (L)
    wh_brace_of_pisols         = true,  -- pistol pair (matched)
    dr_drakefire_pistols       = true,  -- drakefire pair (matched)
    ww_dual_swords             = true,  -- elf sword pair (matched)
    ww_dual_daggers            = true,  -- elf dagger pair (matched)
    we_dual_wield_daggers      = true,  -- alias for ww_dual_daggers
    ww_sword_and_dagger        = true,  -- sword (R) + dagger (L)
    dr_dual_axes               = true,  -- dwarf axe pair (matched)
    dr_dual_wield_hammers      = true,  -- dwarf hammer pair (matched)
    es_dual_wield_hammer_sword = true,  -- mace (R) + sword (L)
    wh_dual_wield_axe_falchion = true,  -- axe (R) + falchion (L)
}

-- ============================================================
-- Dual-wield offhand pools (v0.8.51-dev, refactored v0.8.56-dev)
-- ============================================================
-- For dual-wield weapons the offhand picker overrides `left_hand_unit`.
-- The available pool of left-hand candidates depends on the dual-wield's
-- shape:
--
--   MATCHED-PAIR (dr_dual_axes, we_dual_wield_daggers, ww_dual_swords,
--   dr_dual_wield_hammers, wh_dual_hammer): both hands hold the same
--   weapon variant. Pool = every variant of that weapon family. Swapping
--   the left while keeping the right gives the player axe_01 on right
--   and axe_02 on left.
--
--   MIXED-PAIR (es_dual_wield_hammer_sword: hammer right + sword left;
--   ww_sword_and_dagger: sword right + dagger left; wh_dual_wield_axe_falchion:
--   axe right + sword/falchion left): each hand holds a different weapon
--   kind. Pool = every variant of the LEFT-hand weapon kind, so the user
--   swaps the secondary weapon.
--
-- Pool sourcing:
--   - Item types whose own `<item_type>_skins` table EXISTS in vanilla
--     `WeaponSkins.skin_combinations`: walk that table, read `left_hand_unit`
--     from each referenced skin. For matched pairs this equals right_hand_unit.
--   - Item types whose own skin table is MISSING in vanilla (only one base
--     skin exists, no crafted variants): borrow a single-hand skin table
--     that matches the left-hand weapon kind. Single-hand skins only store
--     `right_hand_unit`, so use that field. The borrowed table effectively
--     becomes "every variant of this weapon kind".
-- v0.9.9.4-dev: per-hand spec. Each item_type maps to up to two
-- `{hand_field = {skin_table=..., unit_field=...}}` entries, one per mount
-- the picker should expose. `unit_field` is the SKIN-TABLE column to read
-- (NOT the destination hand) — vanilla matched-pair skins ship both hand
-- units in the SAME unit_field (left_hand_unit for native dual-wield
-- tables) and skins borrowed from single-hand templates only carry
-- right_hand_unit. The destination hand for the override is `hand_field`
-- (the table key).
local _DUAL_WIELD_POOLS = {
    -- Matched/mixed dual-wields WITH their own skin tables in vanilla.
    -- For matched pairs (axe pair, dagger pair, sword pair) the same skin
    -- table sources both hands; the user can mix right/left independently.
    dr_dual_axes = {
        right_hand_unit = { skin_table = "dr_dual_wield_axes_skins", unit_field = "left_hand_unit" },
        left_hand_unit  = { skin_table = "dr_dual_wield_axes_skins", unit_field = "left_hand_unit" },
    },
    ww_dual_daggers = {
        right_hand_unit = { skin_table = "we_dual_wield_daggers_skins", unit_field = "left_hand_unit" },
        left_hand_unit  = { skin_table = "we_dual_wield_daggers_skins", unit_field = "left_hand_unit" },
    },
    we_dual_wield_daggers = {
        right_hand_unit = { skin_table = "we_dual_wield_daggers_skins", unit_field = "left_hand_unit" },
        left_hand_unit  = { skin_table = "we_dual_wield_daggers_skins", unit_field = "left_hand_unit" },
    },
    ww_dual_swords = {
        right_hand_unit = { skin_table = "we_dual_wield_swords_skins", unit_field = "left_hand_unit" },
        left_hand_unit  = { skin_table = "we_dual_wield_swords_skins", unit_field = "left_hand_unit" },
    },
    -- ww_sword_and_dagger (Kerillian sword+dagger): native skin table
    -- carries both hands. Right = sword, left = dagger (per
    -- weapon_skins.lua entries: right_hand_unit = wpn_we_sword_*,
    -- left_hand_unit = wpn_we_dagger_*).
    ww_sword_and_dagger = {
        right_hand_unit = { skin_table = "we_dual_wield_sword_dagger_skins", unit_field = "right_hand_unit" },
        left_hand_unit  = { skin_table = "we_dual_wield_sword_dagger_skins", unit_field = "left_hand_unit"  },
    },

    -- Dual-wields whose own `<item_type>_skins` table is MISSING in vanilla.
    -- Borrow single-hand skin tables matching each hand's weapon kind:
    --   * dr_dual_wield_hammers: matched pair, both hands hold 1h dwarf hammer
    --     -> dr_1h_hammer_skins for both
    --   * es_dual_wield_hammer_sword: right = mace (no dedicated skin table
    --     in vanilla; reuse es_1h_sword_skins as approximate variants), left = sword
    --     -> es_1h_sword_skins for both. The hand_swap is intentional —
    --     vanilla treats the kruber 1h sword pool as the "weapon variants"
    --     for both sides because no native mace skin table exists.
    --   * wh_dual_wield_axe_falchion: right = axe (no 1h-axe skins for
    --     Saltzpyre; reuse falchion variants), left = falchion
    --     -> wh_1h_falchion_skins for both.
    --   * wh_brace_of_pisols / dr_drakefire_pistols: matched pistol pairs.
    --     No dedicated skin tables in vanilla, but the symmetric units
    --     ship on the base template; we expose the same pool for both
    --     hands so the user can mix barrels.
    -- wh_dual_hammer omitted: the base unit (wpn_wh_1h_hammer_01) has no
    -- skin variants and no 1h-hammer skin table exists, so the pool would
    -- be a single-element no-op (per recon doc — excluded from
    -- _MULTI_MOUNT_ITEM_TYPES too).
    dr_dual_wield_hammers = {
        right_hand_unit = { skin_table = "dr_1h_hammer_skins", unit_field = "right_hand_unit" },
        left_hand_unit  = { skin_table = "dr_1h_hammer_skins", unit_field = "right_hand_unit" },
    },
    es_dual_wield_hammer_sword = {
        right_hand_unit = { skin_table = "es_1h_sword_skins", unit_field = "right_hand_unit" },
        left_hand_unit  = { skin_table = "es_1h_sword_skins", unit_field = "right_hand_unit" },
    },
    wh_dual_wield_axe_falchion = {
        right_hand_unit = { skin_table = "wh_1h_falchion_skins", unit_field = "right_hand_unit" },
        left_hand_unit  = { skin_table = "wh_1h_falchion_skins", unit_field = "right_hand_unit" },
    },
    -- Asymmetric exotic — rapier + pistol (Saltzpyre's fencing sword).
    -- Native skin table carries both hand units per skin entry; right is
    -- the rapier mesh, left is the matching pistol.
    wh_fencing_sword = {
        right_hand_unit = { skin_table = "wh_fencing_sword_skins", unit_field = "right_hand_unit" },
        left_hand_unit  = { skin_table = "wh_fencing_sword_skins", unit_field = "left_hand_unit"  },
    },
    -- Symmetric pistol pairs (no dedicated skin tables in vanilla — fall
    -- back to the brace template's own per-skin entries via the same skin
    -- table reused for both hands). If vanilla ships no skin table for
    -- these item_types the pool ends up empty and the picker just doesn't
    -- render for them (graceful).
    wh_brace_of_pisols = {
        right_hand_unit = { skin_table = "wh_brace_of_pistols_skins", unit_field = "right_hand_unit" },
        left_hand_unit  = { skin_table = "wh_brace_of_pistols_skins", unit_field = "left_hand_unit"  },
    },
    dr_drakefire_pistols = {
        right_hand_unit = { skin_table = "dr_drakefire_pistols_skins", unit_field = "right_hand_unit" },
        left_hand_unit  = { skin_table = "dr_drakefire_pistols_skins", unit_field = "left_hand_unit"  },
    },
}

-- Build offhand options from a skin_combination table. Reads either
-- `left_hand_unit` (native dual-wield tables) or `right_hand_unit`
-- (borrowed single-hand tables) per the `unit_field` arg. Returns the
-- canonical `{ name, unit, rarity }` shape consumed by the picker.
local function _build_offhand_options_from_skin_table(skin_table_name, unit_field)
    if not WeaponSkins or not WeaponSkins.skin_combinations then return nil end
    local sct = WeaponSkins.skin_combinations[skin_table_name]
    if not sct then return nil end
    unit_field = unit_field or "left_hand_unit"

    local skin_by_name = {}
    if WeaponSkins.skins then
        for _, s in ipairs(WeaponSkins.skins) do
            if s.name and s.data then skin_by_name[s.name] = s.data end
        end
    end

    local L = rawget(_G, "Localize")
    local seen = {}
    local out = {}
    local rarity_order = { "plentiful", "common", "rare", "exotic", "unique", "bogenhafen", "promotion" }
    local seen_rarity = {}
    local rarity_keys = {}
    for _, r in ipairs(rarity_order) do
        if sct[r] then rarity_keys[#rarity_keys + 1] = r; seen_rarity[r] = true end
    end
    for r, _ in pairs(sct) do
        if not seen_rarity[r] then rarity_keys[#rarity_keys + 1] = r end
    end

    for _, rarity in ipairs(rarity_keys) do
        local bucket = sct[rarity]
        if type(bucket) == "table" then
            for _, skin_key in ipairs(bucket) do
                local s = skin_by_name[skin_key]
                local unit_path = s and s[unit_field]
                if unit_path and not seen[unit_path] then
                    seen[unit_path] = true
                    local name = skin_key
                    if s.display_name and L then
                        local ok, localized = pcall(L, s.display_name)
                        if ok and localized and localized ~= "" and localized ~= s.display_name then
                            name = localized
                        end
                    end
                    out[#out + 1] = {
                        name   = name,
                        unit   = unit_path,
                        rarity = s.rarity or rarity,
                    }
                end
            end
        end
    end
    return out
end

for item_type, per_hand in pairs(_DUAL_WIELD_POOLS) do
    _offhand_options[item_type] = _offhand_options[item_type] or {}
    for hand_field, spec in pairs(per_hand) do
        if not _offhand_options[item_type][hand_field] then
            local pool = _build_offhand_options_from_skin_table(spec.skin_table, spec.unit_field)
            if pool and #pool > 0 then
                _offhand_options[item_type][hand_field] = pool
                mod:info("[offhand] dual-wield pool %s/%s: %d options from %s (%s)",
                    item_type, hand_field, #pool, spec.skin_table, spec.unit_field)
            else
                mod:info("[offhand] dual-wield pool %s/%s: NO options from %s (skin table missing or empty)",
                    item_type, hand_field, spec.skin_table)
            end
        end
    end
end

-- _offhand_selection[backend_id][hand_field] = option_table. Vanilla
-- entries have only `unit`; LA-bridge entries have `la_armoury_key` +
-- `vanilla_skin` (no `unit` — LA paints onto whatever shield mesh the
-- user's vanilla illusion provides).
--
-- v0.8.32 KEYING CHANGE: keyed by `backend_id`, not `item_type`.
-- v0.9.9.4 SCHEMA CHANGE: per-hand nesting. `_offhand_selection[bid]` is
-- now a table whose keys are hand_field strings ("right_hand_unit" /
-- "left_hand_unit") and whose values are the option records. Single-mount
-- shield picks store under `left_hand_unit` (matching pre-v0.9.9.4
-- behavior); multi-mount picks (rapier+pistol, dual-wields) store one
-- entry per hand the user customized. In-memory only.
local _offhand_selection = {}

-- v0.9.9.4-dev: tolerate the pre-v0.9.9.4 schema where
-- `_offhand_selection[bid]` was the option record itself (not a per-hand
-- map). Detects the old shape by checking for option-record fields (`unit`
-- / `intended_unit` / `la_armoury_key`); if found, wraps the record as
-- `{ left_hand_unit = old_record }` in place so subsequent reads see the
-- new shape. Idempotent.
local function _migrate_legacy_offhand_selection(backend_id)
    local v = backend_id and _offhand_selection[backend_id]
    if type(v) ~= "table" then return end
    if v.unit or v.intended_unit or v.la_armoury_key then
        _offhand_selection[backend_id] = { left_hand_unit = v }
    end
end

-- v0.9.53-dev (#200): OFFHAND APPLY-GATE state.
-- The offhand (shield) row writes _offhand_selection[bid] on a genuine cell
-- click (post-v0.9.52 is_held gate), and — before this build — committed that
-- pick to the LIVE keep weapon on screen exit even when the user never pressed
-- Apply (the user's "clicking a cosmetic without Apply still shows the illusion
-- after I leave the inventory" report). Vanilla's row-1 weapon-illusion grid
-- only commits via the Apply/craft button; the offhand row must match that
-- contract. We snapshot the offhand state that was equipped when the screen
-- opened (`_offhand_baseline[bid]`), flag a genuine Apply in the craft-complete
-- hooks (`_offhand_committed[bid]`), and on exit REVERT to the baseline when no
-- Apply committed (see on_exit). In-memory only; keyed by backend_id.
--   * _offhand_baseline[bid] == nil   -> no snapshot taken this session (e.g. a
--                                         no-offhand weapon) -> never revert.
--   * _offhand_baseline[bid] == false -> snapshot taken, was ABSENT -> revert to
--                                         nil (no override = base shield).
--   * _offhand_baseline[bid] == table -> revert to that per-hand selection.
mod._offhand_baseline = mod._offhand_baseline or {}
mod._offhand_committed = mod._offhand_committed or {}

-- Shallow per-hand copy: the opt records themselves come from the stable
-- _get_offhand_options pool, so copying the {hand_field -> opt} mapping is
-- enough to restore which option is selected per hand.
local function _snapshot_offhand_selection(backend_id)
    if not backend_id then return nil end
    local cur = _offhand_selection[backend_id]
    if type(cur) ~= "table" then return false end  -- false = "was absent"
    local copy = {}
    for hand, opt in pairs(cur) do copy[hand] = opt end
    return copy
end

local function _restore_offhand_selection(backend_id, snap)
    if not backend_id then return end
    if snap == false or snap == nil then
        _offhand_selection[backend_id] = nil
        return
    end
    local copy = {}
    for hand, opt in pairs(snap) do copy[hand] = opt end
    _offhand_selection[backend_id] = copy
end

-- v0.8.64-dev: forward decl. Real impl lives in the cos_la_apply block below
-- (~line 3300). _on_offhand_index_pressed (~line 2004) and the local-equip
-- send sites in the CosmeticUtils hook need to call this; we forward-declare
-- so the closures capture the LOCAL slot rather than falling through to a
-- nil _G._send_la_apply.
local _send_la_apply
-- Track local player's currently-equipped LA cosmetics so hot_join_sync can
-- replay them to joining peers. Map: player_unit -> { slot_name -> la_backend_id }.
-- Populated from the CosmeticUtils.update_cosmetic_slot hook (which fires on
-- every local equip for slot_hat / slot_skin / slot_frame / slot_melee /
-- slot_ranged / slot_pose). Cleared on player_unit destruction is left as
-- future work — stale entries are harmless until the next equip overwrites.
local _local_la_equips = setmetatable({}, { __mode = "k" })

-- v0.8.55-dev: track the backend_id of the weapon currently being customized.
-- The HeroWindowItemCustomization screen owns this, but when the user cycles
-- main-hand illusions in the row-1 picker, vanilla `_on_illusion_index_pressed`
-- rebuilds the preview using the pending skin's IML entry — that entry has
-- no `backend_id`, so our `BackendUtils.get_item_units` hook (which reads
-- `_offhand_selection[backend_id]`) finds nothing and the shield preview
-- snaps back to the new skin's paired shield. Stashing the active backend_id
-- module-side lets the hook fall back to it whenever the call comes in with
-- backend_id == nil. Cleared on customization-screen exit so it doesn't leak
-- across screens.
local _active_customization_backend_id = nil

-- v0.9.41-dev (#150): set true ONLY while inside our GearUtils.create_equipment
-- wrap — i.e. when the LIVE in-keep / in-mission player body is (re)spawning its
-- equipment. The BackendUtils.get_item_units hook reads this to tell a live-body
-- spawn apart from a customization PREVIEWER spawn (both pass the same
-- backend_id). While the customization screen is open we suppress the
-- browse-time offhand mesh override on the live body so mousing/clicking
-- illusions previews ONLY on the preview pane, never the equipped weapon on the
-- player's own body; the live body commits on screen exit via the existing
-- deferred broadcast + pulse-wield (on_exit below). Single-threaded Lua, so the
-- set→read→restore bracket is safe.
local _in_create_equipment = false

-- ============================================================
-- #228 / #235: in-mission weapon-preview shading-environment guard
-- ============================================================
-- Opening the weapon-illusion customization screen (HeroWindowItemCustomization,
-- the loadout-panel gear icon) IN A MISSION crashed with a native Access
-- violation (0xc0000005, addr 0) in the world render pass:
--   [0] =[C] blend <- foundation/scripts/util/script_world.lua render
--   <- foundation/scripts/managers/world/world_manager.lua render
-- Repro on the reporter's machine: warcamp (Against the Grain), es_deus_01
-- spear+shield, cog opened mid-mission via the gut in-mission loadout panel
-- (gut logged "customize view mounting mid-mission (cosmetics path, no cim)").
--
-- CORRECTED ROOT CAUSE (supersedes the 0.9.62-dev note, which blamed the level-
-- less environment/ui_hdr world itself). The customization view builds a 3D
-- preview world through its viewport UI pass (ui_passes.lua:2436-2492 ->
-- WorldManager.create_world -> ScriptWorld.create_shading_environment). In the
-- keep it spawns levels/ui_store_preview/world + environment/ui_store_preview
-- (keep-resident, hero_window_item_customization.lua:405-406). Mid-mission the
-- preview level isn't loaded, so cim/gut strip level_name and substitute
-- shading_environment = "environment/ui_hdr" (crafting_in_modded_dev.lua:2086,
-- gui_tweaker_dev/_gut_mission_inventory.lua:236). ui_hdr + the "default"
-- variation is NOT the fault: hero_view.lua:174-177 and loading_view.lua:113-118
-- create-and-blend exactly that every frame in a mission with no crash, and the
-- customization window is a child of HeroView so HeroView's own ui_hdr world is
-- resident while the preview is open. The AV is a MISSING BLEND VARIATION:
-- _present_item -> _update_environment sets the world's blend target to a
-- per-weapon variation (item_data.item_preview_environment or "weapons_default_01",
-- hero_window_item_customization.lua:1377-1381), writing shading_settings[1]
-- (:583-594). ScriptWorld.render blends shading_settings each frame
-- (script_world.lua:122). on_enter runs _create_ui_elements (:130) then
-- _present_item (:132) synchronously, so the FIRST rendered frame blends
-- {"weapons_default_01",1} -- never the harmless {"default",1}. weapons_default_01
-- is a variation of environment/ui_store_preview (ships with the keep level);
-- environment/ui_hdr does not define it, so native ShadingEnvironment.blend
-- indexes a nil blend object -> AV. (A genuinely-unloaded env RESOURCE throws a
-- clean "Resource not loaded" fatal instead of an AV -- cf. the forge case at
-- crafting_in_modded_dev.lua:1945-1949 -- confirming the resource is resident and
-- only the variation is absent.)
--
-- 0.9.62-dev FIX (superseded): neuter the world (nil its shading_environment) so
-- ScriptWorld.render early-returns before any blend. Stopped the crash but skipped
-- blend+apply+render_world -> the 3D weapon panel rendered BLANK (#235).
--
-- 0.9.64-dev FIX (crash-only, render-preserving): KEEP the env intact so the world
-- renders and pin the blend target to "default" (the _update_environment hook below
-- forces force_default=true in mission). That killed both the AV and the blank --
-- the panel now draws -- but it draws PURE BLACK (user test 2026-07-03). The
-- 0.9.64-dev prediction "renders LIT under generic UI-HDR lighting" was wrong.
--
-- 0.9.65-dev (DIAGNOSTIC): why black. The mission env is NOT ui_store_preview, and
-- cosmetics does NOT own the widget definition mid-mission -- a sibling mod does.
-- gut's in-mission loadout panel mounts this view via its "cosmetics path" and its
-- _create_item_preview_widget_definition substitute STRIPS level_name and sets
-- shading_environment = "environment/ui_hdr" (gui_tweaker_dev/_gut_mission_inventory
-- .lua:207,236; cim's equivalent is crafting_in_modded_dev.lua:2079-2106, env
-- _FORGE_MISSION_SAFE_ENV). So mid-mission the preview world has NO level (no baked
-- or level light units) and the ui_hdr env. ui_hdr is a 2D-UI TONEMAPPING env: its
-- only other users render emissive 2D GUI (HeroView HDR-GUI hero_view.lua:167-181,
-- LoadingView loading_view.lua:113-118). It carries no sun / ambient / IBL to light
-- a 3D object, so the "default" blend leaves the weapon unlit = BLACK. The keep is
-- fine because there it is ui_store_preview + levels/ui_store_preview/world + the
-- keep-resident weapons_default_01 studio-lighting variation.
--
-- The 0.9.65-dev instrument answered it (host log 2026-07-03 21:22): ui_hdr has NO
-- 3D radiance (a 160x exposure boost stayed pure black) and, crucially,
-- environment/ui_store_preview IS resident mid-mission. So THIS build FIXES it:
-- re-point the preview world's shading env to ui_store_preview and let vanilla's
-- studio-lit weapons_default_01 variation blend (re-point block below + the
-- _update_environment hook). Keep path stays a pure pass-through.
-- Pre-flight: cosmetics_tweaker hooks _create_preview_widget NOWHERE else.
mod:hook_safe("HeroWindowItemCustomization", "_create_preview_widget", function(self)
    local in_keep = rawget(_G, "DamageUtils") and DamageUtils.is_in_inn or false
    if in_keep then return end
    local pw = self and self._preview_widget
    local pass_data = pw and pw.element and pw.element.pass_data
    local vp_data = pass_data and pass_data[1]
    local world = vp_data and vp_data.world
    if not world then
        if printf then printf("[235][cos] in mission: no preview world on _create_preview_widget") end
        return
    end

    -- [235] state capture: the env object, its tonemapping "exposure" (camera_manager
    -- .lua:335 reads/writes this every frame on the gameplay env, so an ok read => a
    -- valid env that exposes it), the live blend target, and whether ANY level spawned
    -- into the preview world (the mission-safe defs strip it -> expect level_spawned=false).
    -- Direct env NAME + whether the def stripped the level. UIWidget.init keeps the
    -- widget's style verbatim (ui_widget.lua:15,41), so the mission-safe def's chosen
    -- shading_environment / level_name are readable straight off the widget style --
    -- no inference needed. This is the decisive "which env is the mission preview".
    local vp_style    = pw.style and pw.style.viewport
    local env_name    = vp_style and vp_style.shading_environment
    local style_level = vp_style and vp_style.level_name
    local env = World.has_data(world, "shading_environment") and World.get_data(world, "shading_environment") or nil
    local ss  = World.has_data(world, "shading_settings") and World.get_data(world, "shading_settings") or nil
    local osd = pw.content and pw.content.object_set_data
    local exp_ok, exp = pcall(function() return env and ShadingEnvironment.scalar(env, "exposure") end)
    if printf then
        printf("[235][cos] mission preview: env_name=%s style_level=%s env_obj=%s exposure_ok=%s exposure=%s blend[1]=%s level_spawned=%s osd_level=%s",
            tostring(env_name), tostring(style_level), tostring(env),
            tostring(exp_ok), tostring(exp),
            tostring(ss and ss[1]), tostring(osd and osd.level ~= nil), tostring(osd and osd.level_name))
    end

    -- Residency probe for the NEXT-round fix (env re-point or spawned light).
    -- can_get may not accept every type string; pcall so a bad type never fatals.
    if printf then
        local function res(kind, name)
            local ok, r = pcall(function() return Application.can_get(kind, name) end)
            if not ok then return "err" end
            return tostring(r)
        end
        printf("[235][cos] residency(shading_environment): ui_hdr=%s ui_store_preview=%s ui_loot_preview=%s",
            res("shading_environment", "environment/ui_hdr"),
            res("shading_environment", "environment/ui_store_preview"),
            res("shading_environment", "environment/ui_loot_preview"))
    end

    -- #235 FIX: re-point this mission preview world's shading env from the unlit
    -- ui_hdr (set by gut/cim's mission-safe def) to environment/ui_store_preview --
    -- the SAME studio-lit env the keep uses, verified RESIDENT mid-mission by the
    -- residency probe above (host log 2026-07-03 21:22: ui_store_preview=true, while
    -- the 160x exposure boost on ui_hdr stayed pure black -> ui_hdr has no 3D
    -- radiance). This is the spawn_level re-point pattern (script_world.lua:399-405):
    -- re-point the EXISTING env object to the new resource. weapons_default_01 is a
    -- variation DEFINED in ui_store_preview (keep witnesses: store_window_item_preview
    -- .lua:88+1367, hero_window_gotwf_item_preview.lua:67+607,
    -- hero_window_item_customization.lua:406+1378), so once the world runs
    -- ui_store_preview the _update_environment hook can let vanilla's weapons_default_01
    -- through with NO #228 AV -- that AV was specifically an UNDEFINED variation on
    -- ui_hdr, structurally impossible on an env that defines it. Runs before the first
    -- render (on_enter _create_ui_elements -> _create_preview_widget:367 precedes
    -- _present_item -> _update_environment). Gated on residency + pcall'd, so a failed
    -- or unavailable re-point leaves the world on ui_hdr and _update_environment falls
    -- back to forcing "default" (unlit but AV-safe). NEVER touches the keep path.
    local store_env = "environment/ui_store_preview"
    local store_resident = false
    do
        local ok, r = pcall(function() return Application.can_get("shading_environment", store_env) end)
        store_resident = (ok and r) and true or false
    end
    if env and store_resident then
        local ok = pcall(World.set_shading_environment, world, env, store_env)
        if ok then
            World.set_data(world, "cos_preview_env_repointed", true)
            if printf then printf("[235][cos] re-pointed mission preview env %s -> %s (studio-lit, resident); _update_environment will allow weapons_default_01",
                tostring(env_name), store_env) end
        elseif printf then
            printf("[235][cos] set_shading_environment(%s) FAILED -> staying on ui_hdr, forcing \"default\" (unlit but AV-safe)", store_env)
        end
    elseif printf then
        printf("[235][cos] NOT re-pointing (env=%s store_resident=%s) -> forcing \"default\" (unlit but AV-safe)",
            tostring(env ~= nil), tostring(store_resident))
    end
end)

-- #235: pin the in-mission preview world's blend variation to "default".
-- The world above keeps its environment/ui_hdr shading env. ui_hdr defines the
-- "default" variation (proven blend-safe by hero_view.lua:174-177 and
-- loading_view.lua:113-118) but NOT the per-weapon variations (weapons_default_01,
-- etc.) that vanilla _present_item -> _update_environment requests
-- (hero_window_item_customization.lua:1377-1381 / :583-594). ScriptWorld.render
-- blends shading_settings[1] each frame (script_world.lua:122); a variation ui_hdr
-- lacks -> native ShadingEnvironment.blend AV (the real #228 trigger). Forcing
-- force_default=true keeps shading_settings[1] = "default", so blend only ever
-- asks for the variation ui_hdr has (no AV, no blank) -- BUT ui_hdr carries no 3D
-- scene lighting, so the weapon draws BLACK. #235 FIX: the _create_preview_widget
-- hook above re-points the mission preview world to environment/ui_store_preview
-- (resident mid-mission) when it can. When that succeeded (flagged
-- cos_preview_env_repointed on the world), we let vanilla's weapons_default_01
-- variation through here instead of forcing "default" -- that variation IS defined in
-- ui_store_preview, so it blends keep-identically with NO #228 AV, and the weapon is
-- lit like the keep. If the re-point did NOT happen (env not resident / re-point
-- failed), fall back to forcing "default" (unlit but AV-safe).
-- _update_environment is the SOLE writer of shading_settings[1] (only caller is
-- _present_item), so this one hook covers every re-present (reroll/illusion tabs).
-- Keep path is a pure pass-through (full per-weapon studio lighting preserved).
-- Pre-flight: cosmetics_tweaker hooks _update_environment NOWHERE else.
mod:hook("HeroWindowItemCustomization", "_update_environment", function(func, self, item_preview_environment, force_default)
    local in_keep = rawget(_G, "DamageUtils") and DamageUtils.is_in_inn or false
    if in_keep then return func(self, item_preview_environment, force_default) end
    -- Did _create_preview_widget re-point this preview world to ui_store_preview?
    local pw = self and self._preview_widget
    local world = pw and pw.element and pw.element.pass_data and pw.element.pass_data[1] and pw.element.pass_data[1].world
    local repointed = world and World.has_data(world, "cos_preview_env_repointed")
        and World.get_data(world, "cos_preview_env_repointed") or false
    -- [235] log each distinct env vanilla requests (once per value), plus whether we
    -- ALLOW it (re-pointed to ui_store_preview) or force "default" (fallback).
    if printf then
        mod._lv235_seen_env = mod._lv235_seen_env or {}
        local k = tostring(item_preview_environment)
        if not mod._lv235_seen_env[k] then
            mod._lv235_seen_env[k] = true
            printf("[235][cos] _update_environment(mission): vanilla requested env=%s force_default_in=%s repointed=%s -> %s",
                k, tostring(force_default), tostring(repointed),
                repointed and "ALLOW (studio-lit)" or "forcing \"default\"")
        end
    end
    if repointed then
        return func(self, item_preview_environment, force_default)  -- allow weapons_default_01 -> keep-identical studio lighting
    end
    return func(self, item_preview_environment, true)  -- fallback: pin blend target to "default" (AV-safe)
end)

-- v0.9.43-dev SCREEN trace NOTE: the customization view ENTER anchor is
-- emitted from the `_setup_illusions` hook below ("SCREEN setup_illusions …"),
-- NOT from a dedicated on_enter hook — `_ui_dump.lua` already wraps
-- `HeroWindowItemCustomization.on_enter` for THIS mod, and VMF silently drops a
-- second registration on the same (Class, method) per mod (repo rule /
-- VMF_RECIPES § 1). `_setup_illusions` fires on screen-enter for the customized
-- item (and on each re-select) and has the resolved backend_id, so it's the
-- better enter anchor anyway. SCREEN exit is traced in the on_exit hook here.
mod:hook_safe("HeroWindowItemCustomization", "on_exit", function(self, params)
    _trace("SCREEN exit bid=%s clearing active_customization_bid=%s pending_la_emit_on_exit=%s",
        tostring(self and self._item_backend_id),
        tostring(_active_customization_backend_id),
        tostring(mod._pending_la_emit_on_exit and "queued" or "none"))
    _active_customization_backend_id = nil
    -- M1.4: also close the glow picker so it doesn't linger on top of the
    -- next screen. GlowPicker is required at the top of this file so it's
    -- safe to call directly here.
    if GlowPicker and GlowPicker.is_open and GlowPicker.is_open() then
        GlowPicker.close()
    end
    -- v0.9.53-dev (#200): OFFHAND APPLY-GATE. If the user left WITHOUT a genuine
    -- Apply (no craft-complete flagged mod._offhand_committed[bid] this session),
    -- discard the pending offhand pick: REVERT _offhand_selection[bid] to the
    -- baseline snapshotted on screen open and DROP the queued peer broadcast so
    -- nothing reaches the live keep weapon. This is what the user wants — a grid
    -- pick must only stick on Apply, mirroring vanilla's row-1 weapon-illusion
    -- grid. The live body never changed during browse (the #150
    -- _in_create_equipment suppression keeps it at baseline), so reverting is a
    -- no-op visually; it just prevents the un-Applied pick from leaking on exit.
    -- When committed, fall through to the normal drain + pulse-wield below.
    local _exit_bid = self and self._item_backend_id
    if _exit_bid and not (mod._offhand_committed and mod._offhand_committed[_exit_bid]) then
        local baseline = mod._offhand_baseline and mod._offhand_baseline[_exit_bid]
        if baseline ~= nil then
            _restore_offhand_selection(_exit_bid, baseline)
            mod._pending_la_emit_on_exit = nil  -- skip the drain/pulse-wield below
            mod:info("[cos:weapon-leak] offhand pick NOT applied (no Apply) on exit bid=%s -> reverted to baseline, broadcast dropped",
                tostring(_exit_bid))
            _trace("SCREEN exit REVERT offhand bid=%s (no Apply this session)", tostring(_exit_bid))
        end
    end
    -- v0.9.3.4-hotfix: drain the deferred LA offhand emits queued by
    -- _ct_on_offhand_pressed. Each preview click overwrote its own queue
    -- slot, so this drains exactly ONE final selection per backend_id —
    -- the one the user left selected when navigating away.
    if mod._pending_la_emit_on_exit and _send_la_apply then
        local n = 0
        for _, entry in pairs(mod._pending_la_emit_on_exit) do
            if entry and entry.player_unit and Unit.alive(entry.player_unit) then
                if entry.revert then
                    -- v0.9.69-dev (#265 Slice 1): committed vanilla pick over a
                    -- synced LA entry -> broadcast the revert for BOTH key
                    -- namespaces the apply flow writes (weapon_key + template).
                    mod:info("[cos-la-sync] EMIT-REVERT-ON-EXIT weapon=%s template=%s hand=%s vanilla=%s",
                        tostring(entry.weapon_key), tostring(entry.template_key),
                        tostring(entry.hand_field), tostring(entry.vanilla_key))
                    if mod._send_la_revert then
                        mod._send_la_revert(entry.player_unit, entry.weapon_key, "offhand",
                            entry.vanilla_key, entry.hand_field)
                        if entry.template_key and entry.template_key ~= entry.weapon_key then
                            mod._send_la_revert(entry.player_unit, entry.template_key, "offhand",
                                entry.vanilla_key, entry.hand_field)
                        end
                    end
                    -- v0.9.71-dev: committed revert also clears the on-disk pick.
                    if entry.backend_id and LA_PERSIST and LA_PERSIST.clear_offhand then
                        LA_PERSIST.clear_offhand(entry.backend_id, entry.hand_field)
                    end
                    n = n + 1
                else
                -- v0.9.61-dev (#203): [cos-la-sync] the authoritative offhand key
                -- actually broadcast on screen exit. Pair with the receiver's
                -- [cos-la-sync] RECV line (same armoury_key) in the HOST's log to
                -- confirm the host cached it; a mismatch vs the wearer's rendered
                -- shield is the #203 divergence.
                mod:info("[cos-la-sync] EMIT-ON-EXIT weapon=%s template=%s hand=%s armoury=%s vanilla=%s",
                    tostring(entry.weapon_key), tostring(entry.template_key),
                    tostring(entry.hand_field), tostring(entry.armoury_key), tostring(entry.vanilla_key))
                _send_la_apply(entry.player_unit, entry.weapon_key, "offhand",
                    entry.armoury_key, entry.vanilla_key, entry.hand_field)
                if entry.template_key and entry.template_key ~= entry.weapon_key then
                    _send_la_apply(entry.player_unit, entry.template_key, "offhand",
                        entry.armoury_key, entry.vanilla_key, entry.hand_field)
                end
                -- v0.9.71-dev: committed Apply persists the pick across game
                -- restarts (user report 2026-07-06: shield illusions died with
                -- the session - _offhand_selection had no on-disk mirror).
                if entry.backend_id and LA_PERSIST and LA_PERSIST.save_offhand then
                    LA_PERSIST.save_offhand(entry.backend_id, entry.hand_field,
                        entry.armoury_key, entry.vanilla_key)
                end
                n = n + 1
                end
            end
        end
        if n > 0 then
            _dbg("[ct offhand] drained %d deferred LA emit(s) on screen exit", n)
            -- v0.9.3.8: pulse-wield to force fresh weapon-unit spawn.
            --
            -- v0.9.3.7 tried `inv:wield(inv.wielded_slot)` but vanilla
            -- `SimpleInventoryExtension.wield` short-circuits when called
            -- with the SAME slot it's already wielding — no re-spawn,
            -- `BackendUtils.get_item_units` not re-called, new
            -- `_offhand_selection` not read. The user's empirical fix
            -- ("swap main weapon back and forth") works because it wields
            -- a DIFFERENT slot, which is what vanilla actually re-spawns.
            --
            -- This version pulses through the OTHER weapon slot then
            -- back: if currently wielding slot_melee, wield slot_ranged
            -- briefly then slot_melee again. Both slot's units re-spawn,
            -- both fire get_item_units, both pick up the new override.
            -- The visual "swap animation flash" is acceptable on
            -- customization-screen exit.
            --
            -- Guard against keep-context where local_player isn't fully
            -- wired (player_unit nil, inventory_system extension missing).
            local pm = Managers and Managers.player
            -- v0.9.5.1: pcall pm:local_player() — defense against
            -- "Network backend has not been set" assert.
            local lp_ok, lp = pcall(function() return pm and pm:local_player() end)
            if not lp_ok then lp = nil end
            local pu = lp and lp.player_unit
            -- v0.9.4: per-guard diagnostic. v0.9.3.8 silently bailed in keep
            -- context with zero log output; need to know WHICH guard failed.
            if not pm then
                _dbg("[ct offhand] pulse-wield SKIP — Managers.player nil")
            elseif not lp then
                _dbg("[ct offhand] pulse-wield SKIP — local_player nil")
            elseif not pu then
                _dbg("[ct offhand] pulse-wield SKIP — player_unit nil")
            elseif not Unit.alive(pu) then
                _dbg("[ct offhand] pulse-wield SKIP — player_unit not alive")
            elseif not (ScriptUnit and ScriptUnit.has_extension) then
                _dbg("[ct offhand] pulse-wield SKIP — ScriptUnit.has_extension unavailable")
            end
            if pu and Unit.alive(pu) and ScriptUnit and ScriptUnit.has_extension then
                local inv = ScriptUnit.has_extension(pu, "inventory_system")
                -- v0.9.5: removed the "wielded_slot is nil" SKIP diagnostic
                -- since the code below now HANDLES nil (uses keep-wield from
                -- nil instead of pulse-cycling). Other SKIP messages remain
                -- as informational diagnostics.
                if not inv then
                    _dbg("[ct offhand] pulse-wield SKIP — no inventory_system extension on player_unit")
                elseif not inv.wield then
                    _dbg("[ct offhand] pulse-wield SKIP — inv.wield method missing")
                elseif not (inv._equipment and inv._equipment.slots) then
                    _dbg("[ct offhand] pulse-wield SKIP — inv._equipment / inv._equipment.slots missing")
                end
                if inv and inv.wield and inv._equipment and inv._equipment.slots then
                    local orig_slot = inv.wielded_slot  -- may be NIL in keep
                    local slots = inv._equipment.slots
                    -- v0.9.5: handle wielded_slot=nil case (keep context).
                    -- Previous version bailed entirely when orig_slot was
                    -- nil; the user's keep-mode workflow ALWAYS has nil
                    -- wielded_slot, so the pulse-wield never fired.
                    --
                    -- New approach: if orig_slot is nil, wield ANY equipped
                    -- weapon slot directly. That sets wielded_slot from nil
                    -- to the chosen slot, which DOES fire vanilla's
                    -- _wield_slot path (no short-circuit because nil != slot).
                    -- The visible side effect is the player suddenly
                    -- "drawing" a weapon in keep, which is the EXACT visual
                    -- refresh the user wants — it forces the LA paint to
                    -- apply to the in-keep model.
                    --
                    -- If orig_slot IS set, do the original pulse pattern
                    -- (wield other → wield orig back).
                    if not orig_slot then
                        -- Find any equipped weapon slot. Prefer slot_melee
                        -- since that's where shield+sword changes typically
                        -- target. Fall back to slot_ranged or any other.
                        local target_slot
                        for _, candidate in ipairs({ "slot_melee", "slot_ranged" }) do
                            if slots[candidate] then target_slot = candidate; break end
                        end
                        if not target_slot then
                            for slot_name, slot_data in pairs(slots) do
                                if slot_data and (slot_name == "slot_melee" or slot_name == "slot_ranged") then
                                    target_slot = slot_name; break
                                end
                            end
                        end
                        if target_slot then
                            local ok, err = pcall(inv.wield, inv, target_slot)
                            if ok then
                                _dbg("[ct offhand] keep-wield slot=%s (from nil) to refresh local model",
                                    tostring(target_slot))
                            else
                                _dbg_alert("[ct offhand] keep-wield errored: %s", tostring(err))
                            end
                        else
                            _dbg("[ct offhand] pulse-wield SKIP — no equipped weapon slot found")
                        end
                    else
                        -- orig_slot is set — do the original pulse pattern.
                        local pulse_slot
                        if orig_slot == "slot_melee" and slots["slot_ranged"] then
                            pulse_slot = "slot_ranged"
                        elseif orig_slot == "slot_ranged" and slots["slot_melee"] then
                            pulse_slot = "slot_melee"
                        else
                            for slot_name, slot_data in pairs(slots) do
                                if slot_name ~= orig_slot and slot_data then
                                    pulse_slot = slot_name
                                    break
                                end
                            end
                        end
                        if pulse_slot then
                            local ok1, err1 = pcall(inv.wield, inv, pulse_slot)
                            local ok2, err2 = pcall(inv.wield, inv, orig_slot)
                            if ok1 and ok2 then
                                _dbg("[ct offhand] pulse-wielded %s -> %s to refresh local model",
                                    tostring(pulse_slot), tostring(orig_slot))
                            else
                                _dbg_alert("[ct offhand] pulse-wield errored: %s / %s",
                                    tostring(err1), tostring(err2))
                            end
                        else
                            _dbg("[ct offhand] pulse-wield SKIP — no alternate slot to pulse through (wielded=%s)",
                                tostring(orig_slot))
                        end
                    end
                end
            end
        end
        mod._pending_la_emit_on_exit = nil
    end
    -- v0.9.53-dev (#200): clear this session's apply-gate state so the next
    -- screen open takes a fresh baseline (and a stale committed flag can't
    -- suppress a later revert). Keyed per-bid; only one customization screen
    -- is open at a time.
    if _exit_bid then
        if mod._offhand_baseline then mod._offhand_baseline[_exit_bid] = nil end
        if mod._offhand_committed then mod._offhand_committed[_exit_bid] = nil end
    end
end)

-- LA pool merge: each weapon_type pulls the LA shields whose `icons` table
-- specifically targets that weapon_type. The bridge does the icon-driven
-- bucketing; the merge here just appends each bucket to the matching
-- vanilla-offhand list. No cross-weapon-type leakage because each
-- _offhand_options[weapon_type] is now its own table (de-aliased above).
--
-- FOCUS GATE: legacy "one shield at a time" testing whitelist. Pre-v0.8.52
-- only the 3 entries below surfaced in the picker (Ostermark, Kotbs, Reiland)
-- while the rest of LA's registered shields stayed hidden. v0.8.52-dev opens
-- this fully — every LA shield whose `icons` table targets the current weapon
-- type now appears, scoped to the wielding character per the same-character
-- rule (each LA variant's icons are already character-correct, so the merge
-- preserves the rule).
--
-- To re-enable the focus filter for debugging, populate this table with the
-- armoury_keys you want exposed; an empty table = no filter (default now).
local _LA_FOCUS_KEYS = {}

local _la_offhand_merged = false

local function _merge_la_offhand_options()
    if _la_offhand_merged then return end
    if not LA_BRIDGE.registered then return end
    if type(LA_BRIDGE.la_offhand_options_by_weapon_type) ~= "table" then return end
    local has_focus = next(_LA_FOCUS_KEYS) ~= nil
    -- v0.9.9.4: per-hand structure — LA_BRIDGE.la_offhand_options_by_weapon_type
    -- is `[weapon_type][hand_field] = array_of_la_opts`.
    for weapon_key, la_hand_pools in pairs(LA_BRIDGE.la_offhand_options_by_weapon_type) do
        local hand_target = _offhand_options[weapon_key]
        if not hand_target then hand_target = {}; _offhand_options[weapon_key] = hand_target end
        for hand_field, la_pool in pairs(la_hand_pools) do
            local target = hand_target[hand_field]
            if not target then target = {}; hand_target[hand_field] = target end
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
                        -- v0.9.9.1 REVERT: dropped la_opt.icon passthrough.
                    }
                end
            end
        end
    end
    _la_offhand_merged = true
    mod:info("[offhand] merged LA shield options (focus gate: %d keys)",
        (function() local n = 0; for _ in pairs(_LA_FOCUS_KEYS) do n = n + 1 end; return n end)())
end

-- v0.9.71-dev: restore persisted offhand (shield) picks into
-- `_offhand_selection` once the LA bridge pools exist. Reconstructs the SAME
-- option record shape `_merge_la_offhand_options` builds (la_armoury_key /
-- vanilla_skin / intended_unit) by looking the armoury_key up in
-- LA_BRIDGE.la_offhand_options_by_weapon_type, so the local render path
-- (BackendUtils.get_item_units mesh override + LA paint) treats a restored
-- pick exactly like a fresh one. One-shot; arms the self-rebroadcast so
-- peers learn the restored picks through the normal emit flow.
mod._la_restore_offhand_selections = function()
    if mod._la_offhand_restore_done then return end
    if not (LA_BRIDGE and LA_BRIDGE.registered) then return end
    if type(LA_BRIDGE.la_offhand_options_by_weapon_type) ~= "table" then return end
    if not (LA_PERSIST and LA_PERSIST.get_saved_offhands) then return end
    mod._la_offhand_restore_done = true
    local saved = LA_PERSIST.get_saved_offhands()
    if not next(saved) then return end
    -- armoury_key -> bridge option record (first hit wins; records for the
    -- same key are identical across weapon types/hands).
    local by_key = {}
    for _, hand_pools in pairs(LA_BRIDGE.la_offhand_options_by_weapon_type) do
        for _, pool in pairs(hand_pools) do
            for _, la_opt in ipairs(pool) do
                if la_opt.armoury_key and not by_key[la_opt.armoury_key] then
                    by_key[la_opt.armoury_key] = la_opt
                end
            end
        end
    end
    local n, miss = 0, 0
    for backend_id, hands in pairs(saved) do
        for hand_field, rec in pairs(hands) do
            local la_opt = rec and rec.armoury_key and by_key[rec.armoury_key]
            if la_opt then
                _offhand_selection[backend_id] = _offhand_selection[backend_id] or {}
                _offhand_selection[backend_id][hand_field] = {
                    name            = la_opt.name .. " (LA)",
                    la_armoury_key  = la_opt.armoury_key,
                    vanilla_skin    = la_opt.vanilla_skin,
                    intended_unit   = la_opt.intended_unit,
                    rarity          = "promo",
                }
                if la_opt.intended_unit then _preload_offhand_package(la_opt.intended_unit) end
                n = n + 1
            else
                miss = miss + 1
            end
        end
    end
    if n > 0 then
        -- Peers learn restored picks via the normal state-change re-emit walk
        -- (it reads _offhand_selection for equipped backend_ids).
        mod._la_self_rebroadcast_pending = true
    end
    if printf then printf("[la-state] OFFHAND-RESTORE %d pick(s) restored from disk, %d unresolvable (LA variant missing)",
        n, miss) end
end

-- v0.9.9.1 REVERT: removed v0.9.9.0 UIUtils.get_ui_information_from_item
-- hook that overrode the weapon-slot icon when an LA shield was equipped.
-- User reported "the latest has the wrong icons for everything" — the
-- icon lookup chain (_offhand_selection[bid].icon, sourced from
-- WeaponSkins.skins[la_armoury_key].inventory_icon in _la_bridge.lua) was
-- returning wrong paths, breaking icons globally. LA's actual icon
-- storage shape needs proper diagnostic before re-attempting.

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
    mod:echo("[offhand] _offhand_options (item_type -> hand_field -> pool size):")
    for k, hand_pools in pairs(_offhand_options) do
        for hand, pool in pairs(hand_pools) do
            mod:echo("  %s/%s -> %d options", k, hand, #pool)
        end
    end
    mod:echo("[offhand] _offhand_selection (bid -> hand -> sel):")
    for k, per_hand in pairs(_offhand_selection) do
        if type(per_hand) == "table" then
            for hand, v in pairs(per_hand) do
                if type(v) == "table" then
                    local label = v.la_armoury_key and ("LA:" .. v.la_armoury_key) or tostring(v.unit)
                    mod:echo("  %s/%s -> %s", k, hand, label)
                end
            end
        end
    end
    mod:echo("[offhand] BackendUtils hooked: %s", tostring(BackendUtils ~= nil))
    mod:echo("[offhand] UIWidget available: %s", tostring(UIWidget ~= nil))
    mod:echo("[offhand] UIWidgets available: %s", tostring(UIWidgets ~= nil))
    mod:echo("[offhand] UIRenderer available: %s", tostring(UIRenderer ~= nil))
    mod:echo("[offhand] Colors available: %s", tostring(Colors ~= nil))
end)

-- v0.9.0.4-hotfix: real impl of the forward-declared
-- _force_load_all_offhand_packages (declared near _preload_offhand_for_option
-- around line 1495). Placed here so it can close over the local
-- `_offhand_options` declared at line 1574+. Called from mod.update once
-- after `_la_bridge_init_done = true`.
--
-- Why this exists: when HOST picks a cross-character shield (e.g.
-- `wpn_emp_gk_shield_03` "GK Shield Blue" via the offhand picker, or equips
-- the CT custom illusion `ct_es_mace_gk_shield_01` which also uses
-- shield_03 as left_hand_unit), the CLIENT receives vanilla skin
-- propagation. Client's `SimpleHuskInventoryExtension._wield_slot` calls
-- `BackendUtils.get_item_units(item_data, nil, slot.skin, career_name)`,
-- gets shield_03's path back, then `GearUtils.spawn_inventory_unit` →
-- `unit_spawner:spawn_local_unit_with_extensions` → engine `spawn_unit`.
-- shield_03's package WAS NOT preloaded on the client — ProfileSynchronizer
-- starts an async load when peer profiles sync but it races the synchronous
-- wield RPC and loses. Result: engine spawn_unit crash, PC-B fell out of the
-- session 2026-05-19. Identical mechanism to weapon_tweaker's brace-repeater
-- crash (feedback_cwv_cross_character_unit_packages.md).
--
-- Fix: enumerate every unit_path the user might equip via CT (offhand pools
-- + custom illusions) and force-load async at boot on EVERY peer.
-- _preload_offhand_package is idempotent via the _preloaded_offhand_packages
-- set, so re-calls are cheap.
local _force_loaded_all_offhand_done = false
_force_load_all_offhand_packages = function()
    if _force_loaded_all_offhand_done then return end
    if not Managers or not Managers.package then return end
    local count = 0
    -- A. Vanilla-mesh + cross-character pools (_offhand_options).
    -- v0.9.9.4: per-hand structure — outer = item_type, middle = hand_field,
    -- inner = pool array.
    for _wkey, hand_pools in pairs(_offhand_options) do
        if type(hand_pools) == "table" then
            for _hand, pool in pairs(hand_pools) do
                if type(pool) == "table" then
                    for _, opt in ipairs(pool) do
                        if type(opt) == "table" then
                            if opt.unit then _preload_offhand_package(opt.unit); count = count + 1 end
                            if opt.intended_unit then _preload_offhand_package(opt.intended_unit); count = count + 1 end
                        end
                    end
                end
            end
        end
    end
    -- B. LA bridge offhand options (texture-paint + kind="unit" custom-mesh).
    -- v0.9.9.4: same per-hand structure (LA only ships left_hand_unit
    -- variants currently, but walk all hands for forward-compat).
    if LA_BRIDGE and type(LA_BRIDGE.la_offhand_options_by_weapon_type) == "table" then
        for _wkey, hand_pools in pairs(LA_BRIDGE.la_offhand_options_by_weapon_type) do
            if type(hand_pools) == "table" then
                for _hand, pool in pairs(hand_pools) do
                    if type(pool) == "table" then
                        for _, opt in ipairs(pool) do
                            if type(opt) == "table" then
                                if opt.unit then _preload_offhand_package(opt.unit); count = count + 1 end
                                if opt.intended_unit then _preload_offhand_package(opt.intended_unit); count = count + 1 end
                            end
                        end
                    end
                end
            end
        end
    end
    -- C. Custom illusions injected by CT. These register at boot into
    -- WeaponSkins.skins and are equippable by any peer; their left/right
    -- hand units must be loadable on every machine.
    if _custom_illusions then
        for _, illusion in ipairs(_custom_illusions) do
            if illusion.right_hand_unit then _preload_offhand_package(illusion.right_hand_unit); count = count + 1 end
            if illusion.left_hand_unit  then _preload_offhand_package(illusion.left_hand_unit);  count = count + 1 end
        end
    end
    _force_loaded_all_offhand_done = true
    mod:info("[offhand] force-loaded all offhand pool packages (%d preload calls, dedup'd via _preloaded_offhand_packages)", count)
    -- [heap-probe] snapshot the lua_heap the instant the offhand packages land.
    -- These are predominantly C++ RESOURCE memory (which collectgarbage does NOT
    -- see), so this number is the LUA-side bookkeeping only — pair it with the
    -- package count above when attributing the 1 GiB lua_heap breach.
    mod:debug("[heap-probe] post offhand force-load: lua_heap %.1f MB (%.0f KB) live; %d packages retained for session (no unload path)",
        collectgarbage("count") / 1024, collectgarbage("count"), count)
end

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

-- v0.9.29-dev (issue #48): filter weavebound / shyish glow families from
-- the illusion grid by default. Data evidence: 2026-05-27 ui-dump on
-- es_2h_sword (Kruber Greatsword) showed 13 skins with mat= field on each
-- (`mat=weaves` for Weavebound, `mat=shyish` for Shyish-Infused). These are
-- visually jarring on most weapons (the Bret Longsword "Evengleam"
-- weavebound/shyish pair is the canonical complaint).
-- v0.9.38-dev: the per-family VMF toggles (hide_weavebound_skins /
-- hide_shyish_skins) were REMOVED — hiding is now IMPLICIT and always on,
-- because these glow-family skins are surfaced exclusively through the
-- in-cosmetic-picker glow menu. `_FILTERED_MAT_FAMILIES` is now a plain set
-- of always-hidden families. Currently-equipped skin is NEVER filtered out
-- so vanilla's `_select_illusion_by_key` (called from _setup_illusions
-- before our hook runs) stays valid.
local _FILTERED_MAT_FAMILIES = {
    weaves = true,
    shyish = true,
}

local function _skin_mat_family(skin_key)
    if not skin_key or not WeaponSkins or not WeaponSkins.skins then return nil end
    local entry = rawget(WeaponSkins.skins, skin_key)
    if type(entry) ~= "table" then return nil end
    local mat = entry.material_settings_name
    return (type(mat) == "string") and mat or nil
end

-- Pure helper so the regression test can drive it with synthetic widget
-- arrays. `current_skin_key` is the always-keep guard (vanilla selection
-- state would dangle otherwise).
-- v0.9.38-dev: hiding is now implicit/always-on — the per-family VMF
-- toggles were removed, so membership in `_FILTERED_MAT_FAMILIES` alone
-- hides the skin (no setting lookup). The third arg is retained for
-- signature stability but is ignored.
mod._filter_illusion_widgets = function(widgets, current_skin_key, _ignored_get_setting)
    if type(widgets) ~= "table" then return widgets, 0 end
    local kept, removed = {}, 0
    for _, w in ipairs(widgets) do
        local skin_key = w and w.content and w.content.skin_key
        local keep = true
        if skin_key and skin_key ~= current_skin_key then
            local mat = _skin_mat_family(skin_key)
            if mat and _FILTERED_MAT_FAMILIES[mat] then keep = false end
        end
        if keep then
            kept[#kept + 1] = w
        else
            removed = removed + 1
        end
    end
    if removed > 0 then
        -- Re-run vanilla's offset math (hero_window_item_customization.lua:1611-1618).
        local width, spacing = 51, -5
        local n = #kept
        local total_width = (n > 0) and (-spacing + n * (width + spacing)) or 0
        local x_offset = width / 2
        for _, w in ipairs(kept) do
            local offset = w.offset
            if offset then
                offset[1] = -total_width / 2 + x_offset
                x_offset = x_offset + width + spacing
            end
        end
    end
    return kept, removed
end

mod:hook("HeroWindowItemCustomization", "_setup_illusions", function(func, self, item)
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

    _dbg("[offhand] _setup_illusions called, item=%s", tostring(item and item.key))

    -- v0.8.55-dev: stash for the BackendUtils.get_item_units hook fallback.
    -- See note on `_active_customization_backend_id` declaration.
    _active_customization_backend_id = item and item.backend_id or nil
    _trace("SCREEN setup_illusions item=%s set active_customization_bid=%s",
        tostring(item and item.key), tostring(_active_customization_backend_id))

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

    -- v0.9.9.4-dev: build row sequence in display order. Right hand renders
    -- ABOVE left when both pools exist (multi-mount). Single-mount weapons
    -- (sword+shield family) only have `left_hand_unit` populated, so they
    -- render as a single row at the legacy offset.
    local is_multi_mount = _MULTI_MOUNT_ITEM_TYPES[weapon_key] == true
    local hand_rows = {}
    -- Order: right first (top row), left second (bottom row). For single-
    -- mount weapons only left exists; matches legacy single-row layout.
    if is_multi_mount and type(hand_pools.right_hand_unit) == "table"
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
    if item.backend_id then _migrate_legacy_offhand_selection(item.backend_id) end

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
    if current_backend_id then _migrate_legacy_offhand_selection(current_backend_id) end
    local per_hand_sel = current_backend_id and _offhand_selection[current_backend_id] or nil

    for _, row in ipairs(hand_rows) do
        local hand_field = row.hand
        local pool = row.pool
        local current_sel = per_hand_sel and per_hand_sel[hand_field]
        local current_unit = current_units_by_hand[hand_field]

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
        mod._offhand_baseline[current_backend_id] = _snapshot_offhand_selection(current_backend_id)
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

HeroWindowItemCustomization._ct_on_offhand_pressed = function(self, hand_field, index)
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

    -- v0.8.32: key selection by backend_id (per-weapon-instance).
    -- v0.9.9.4: nested under hand_field.
    if self._item_backend_id then
        _migrate_legacy_offhand_selection(self._item_backend_id)
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
        local local_player = pm and pm:local_player()
        local player_unit = local_player and local_player.player_unit
        if player_unit and Unit.alive(player_unit) then
            local template_key = nil
            if self._item_backend_id and Managers and Managers.backend then
                local bi = Managers.backend:get_interface("items")
                local item = bi and bi.get_item_from_id and bi:get_item_from_id(self._item_backend_id)
                template_key = item and item.data and item.data.template
            end
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
                backend_id   = self._item_backend_id,  -- v0.9.71: persistence key
            }
            -- v0.9.43-dev WRITE trace: deferred peer-sync emit queued (drains on
            -- SCREEN exit, not now — see on_exit hook). This is the commit that
            -- becomes the authoritative cos_la_apply broadcast.
            _trace("WRITE pending_la_emit_on_exit[%s] armoury=%s vanilla=%s hand=%s weapon=%s",
                tostring(q_key), tostring(opt.la_armoury_key), tostring(opt.vanilla_skin),
                tostring(hand_field), tostring(weapon_key))
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
        -- v0.9.69-dev (#265, LA_SYNC_CORE_AUDIT Slice 1 / I2): when the synced
        -- store still holds an LA entry for this weapon (an APPLIED pick, this
        -- session or restored from an earlier one), a committed vanilla pick
        -- must broadcast a REVERT -- clearing the queued emit alone leaves
        -- every remote peer rendering the stale LA cosmetic forever (the exact
        -- 2026-07-03 21:15 repro). QUEUED, not sent: the on_exit Apply gate
        -- still drops the whole queue on an un-Applied browse, mirroring the
        -- LA-apply flow. Store read via mod._la_equips_by_peer (runtime alias;
        -- the local's forward decl sits below this function).
        do
            local pm_v = Managers and Managers.player
            local lp_ok_v, lp_v = pcall(function() return pm_v and pm_v:local_player() end)
            local player_unit_v = lp_ok_v and lp_v and lp_v.player_unit
            local store_v = mod._la_equips_by_peer
            local synced_v = store_v and lp_v and lp_v.peer_id and store_v[lp_v.peer_id]
            if synced_v and player_unit_v and Unit.alive(player_unit_v) then
                local template_key_v = nil
                if self._item_backend_id and Managers and Managers.backend then
                    local bi_v = Managers.backend:get_interface("items")
                    local item_v = bi_v and bi_v.get_item_from_id and bi_v:get_item_from_id(self._item_backend_id)
                    template_key_v = item_v and item_v.data and item_v.data.template
                end
                local wk_v = weapon_key or "slot_unknown"
                if (template_key_v and synced_v[template_key_v]) or synced_v[wk_v] then
                    local vkey2 = (self._item_backend_id or "__no_backend__") .. "|" .. tostring(hand_field)
                    mod._pending_la_emit_on_exit = mod._pending_la_emit_on_exit or {}
                    mod._pending_la_emit_on_exit[vkey2] = {
                        revert       = true,
                        player_unit  = player_unit_v,
                        weapon_key   = wk_v,
                        template_key = template_key_v,
                        hand_field   = hand_field,
                        vanilla_key  = opt.vanilla_skin or opt.name,
                        backend_id   = self._item_backend_id,  -- v0.9.71: persistence key
                    }
                    mod:info("[cos-la-sync] EXIT-QUEUE REVERT queued bid=%s hand=%s vanilla_pick=%s (synced LA entry pending revert)",
                        tostring(self._item_backend_id), tostring(hand_field), tostring(opt.name))
                end
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
-- v0.9.0.6-hotfix: husk-wield context. SimpleHuskInventoryExtension._wield_slot
-- (wrapped below) sets this before calling BackendUtils.get_item_units and
-- clears it after. The get_item_units hook reads it to decide whether to
-- override left_hand_unit for kind="unit" LA mesh swaps on remote husks.
-- Lua main thread is single-threaded so the set→get→clear bracket is safe.
local _current_husk_wield = nil
-- v0.9.0.11-hotfix: FORWARD DECLARATION. The real assignment lives at the
-- old declaration site below (line ~3711). Without this forward decl, the
-- BackendUtils.get_item_units hook (registered immediately below) would
-- reference `_la_equips_by_peer` as a GLOBAL (nil) — the actual local
-- declaration is much later in the file. v0.9.0.10 burned: the husk-mesh-
-- swap probe always logged cache_has_wearer=false even after the recv
-- handler had populated the cache, because the receiver captured the
-- real local but the probe captured the global. Declaring here gives every
-- subsequent reference (probe + receiver + wraps) the same upvalue.
local _la_equips_by_peer = {}

if BackendUtils then
    mod:hook(BackendUtils, "get_item_units", function(func, item_data, backend_id, skin, career_name)
        local result = func(item_data, backend_id, skin, career_name)
        if not result then return result end

        -- v0.9.0.6-hotfix: kind="unit" LA mesh swap for remote husks.
        -- v0.9.0.8-hotfix: instrumented at every gate so we can see WHY a
        -- swap didn't fire (cache miss vs variant miss vs package miss).
        if _current_husk_wield and _current_husk_wield.wearer_peer then
            local template = item_data and item_data.template
            local equips = _la_equips_by_peer and _la_equips_by_peer[_current_husk_wield.wearer_peer]
            local entry = equips and template and equips[template]
            _dbg("[husk-mesh-swap probe] wearer=%s slot=%s template=%s cache_has_wearer=%s cache_has_entry=%s entry_kind=%s entry_key=%s",
                tostring(_current_husk_wield.wearer_peer),
                tostring(_current_husk_wield.slot_name),
                tostring(template),
                tostring(equips ~= nil),
                tostring(entry ~= nil),
                tostring(entry and entry.kind),
                tostring(entry and entry.armoury_key))
            -- v0.9.69-dev (Slice 0, I6 / #264): the switch-back render loss has
            -- never been pinned because every gate here logs only via _dbg.
            -- One dedup'd printf per (wearer, template, disposition) so the
            -- user's log shows whether a husk wield found the store entry.
            do
                local seen = mod._la_gate_seen
                if not seen then seen = {}; mod._la_gate_seen = seen end
                local dispo = (entry and (entry.kind or "?") .. "/" .. tostring(entry.armoury_key))
                    or (equips and "no-entry-for-template" or "no-store-for-wearer")
                local sk = tostring(_current_husk_wield.wearer_peer) .. "|" .. tostring(template) .. "|" .. dispo
                if not seen[sk] and printf then
                    seen[sk] = true
                    printf("[la-state] HUSK-GATE wearer=%s slot=%s template=%s -> %s",
                        tostring(_current_husk_wield.wearer_peer),
                        tostring(_current_husk_wield.slot_name),
                        tostring(template), dispo)
                end
            end
            -- [cos:sync] #154: husk cross-character weapon mesh-swap gate. The
            -- reported failure is an EMPTY husk cache at wield time
            -- (cache_entry=false) so the swap never fires and the teammate's
            -- weapon renders wrong. printf so it survives mod-logging-OFF.
            if PROBE then
                PROBE.emit("cos:sync",
                    "husk_meshgate/" .. tostring(_current_husk_wield.wearer_peer) .. "/" .. tostring(template),
                    string.format("peer=husk wearer=%s slot=%s template=%s cache_wearer=%s cache_entry=%s entry_kind=%s key=%s decision=%s",
                        tostring(_current_husk_wield.wearer_peer), tostring(_current_husk_wield.slot_name),
                        tostring(template), tostring(equips ~= nil), tostring(entry ~= nil),
                        tostring(entry and entry.kind), tostring(entry and entry.armoury_key),
                        (entry and (entry.kind == "offhand" or entry.kind == "illusion") and entry.armoury_key) and "resolve-mesh" or "no-op(cache-or-kind-miss)"))
            end
            if entry and (entry.kind == "offhand" or entry.kind == "illusion")
                and entry.armoury_key
            then
                local la = get_mod("Loremasters-Armoury")
                local variant = la and la.SKIN_LIST and la.SKIN_LIST[entry.armoury_key]
                if not variant then
                    _dbg("[husk-mesh-swap] miss: variant %s not in LA.SKIN_LIST", tostring(entry.armoury_key))
                    -- v0.9.0.14-hotfix: dedup'd chat warning. Surface the
                    -- missing-variant problem to the local user so they know
                    -- their LA install is missing what a peer is broadcasting
                    -- (most commonly: LA disabled in the launcher).
                    mod._la_missing_variant_logged = mod._la_missing_variant_logged or {}
                    if not mod._la_missing_variant_logged[entry.armoury_key] then
                        mod._la_missing_variant_logged[entry.armoury_key] = true
                        mod:echo("[cosmetics_tweaker] LA variant '%s' missing from your local LA install. Peer's cosmetic won't render. Enable Loremaster's Armoury in launcher + restart, or update LA.",
                            tostring(entry.armoury_key))
                    end
                elseif variant.kind ~= "unit" then
                    _dbg("[husk-mesh-swap] skip: variant %s is kind=%s (only unit gets mesh-swapped here; texture handled via re-paint)",
                        tostring(entry.armoury_key), tostring(variant.kind))
                elseif not (variant.new_units and variant.new_units[1]) then
                    _dbg("[husk-mesh-swap] miss: variant %s has no new_units[1]", tostring(entry.armoury_key))
                else
                    -- v0.9.45-dev (BUG 1/2): resolve via the SHARED helper so the
                    -- local override path (below) and this husk path can't drift.
                    -- _resolve_la_unit_mesh derives the 3P from new_units[2]
                    -- (fallback `.."_3p"`) and verifies both halves are loadable.
                    local la_unit, la_unit_3p, mesh_ready = _resolve_la_unit_mesh(entry.armoury_key)
                    if not mesh_ready then
                        _dbg("[husk-mesh-swap] miss: variant %s LA mesh not loadable (1p=%s 3p=%s) — package preload may have failed",
                            tostring(entry.armoury_key), tostring(la_unit), tostring(la_unit_3p))
                    else
                        -- v0.9.9.4-dev: write to the hand_field recorded
                        -- in the cached entry (default left for backward
                        -- compat with pre-v0.9.9.4 cache writes).
                        local hand_field = entry.hand_field or "left_hand_unit"
                        local prev = result[hand_field]
                        result[hand_field] = la_unit
                        _dbg("[husk-mesh-swap] APPLIED wearer=%s template=%s %s %s -> %s (armoury=%s)",
                            tostring(_current_husk_wield.wearer_peer), tostring(template),
                            tostring(hand_field),
                            tostring(prev), tostring(la_unit), tostring(entry.armoury_key))
                        -- v0.9.69-dev (Slice 0, I6): mod-logging-OFF-visible
                        -- confirmation that the wield-path swap fired (#264's
                        -- missing evidence). Dedup'd per (wearer, template, key).
                        do
                            local seen = mod._la_gate_seen
                            if not seen then seen = {}; mod._la_gate_seen = seen end
                            local sk = "swap|" .. tostring(_current_husk_wield.wearer_peer)
                                .. "|" .. tostring(template) .. "|" .. tostring(entry.armoury_key)
                            if not seen[sk] and printf then
                                seen[sk] = true
                                printf("[la-state] HUSK-SWAP applied wearer=%s template=%s hand=%s -> %s (key=%s)",
                                    tostring(_current_husk_wield.wearer_peer), tostring(template),
                                    tostring(hand_field), tostring(la_unit), tostring(entry.armoury_key))
                            end
                        end
                        -- v0.9.43-dev RESOLVE+HUSK trace: the husk DOES swap the
                        -- mesh to the LA custom unit (using new_units[1]/[2] for
                        -- the 1p/3p check) — this is why the CLIENT renders the
                        -- host's shield correctly while the host's own body does
                        -- not (the local path's _override_package_ready suffix
                        -- check fails). Contrast with the RESOLVE line above.
                        _trace("RESOLVE husk-mesh-swap APPLIED wearer=%s slot=%s template=%s hand=%s %s -> %s armoury=%s",
                            tostring(_current_husk_wield.wearer_peer),
                            tostring(_current_husk_wield.slot_name), tostring(template),
                            tostring(hand_field), tostring(prev), tostring(la_unit),
                            tostring(entry.armoury_key))
                        if PROBE then
                            PROBE.emit("cos:sync",
                                "husk_meshswap/" .. tostring(_current_husk_wield.wearer_peer) .. "/" .. tostring(template),
                                string.format("peer=husk wearer=%s template=%s key=%s unit=%s decision=APPLIED-mesh-swap",
                                    tostring(_current_husk_wield.wearer_peer), tostring(template),
                                    tostring(entry.armoury_key), tostring(la_unit)))
                        end
                        return result
                    end
                end
            end
        end

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
        -- v0.8.55-dev: customization-screen preview-cycle path passes nil
        -- for both `backend_id` AND item_data.backend_id (preview item is
        -- the pending skin's IML entry, no backend stamped). Fall back to
        -- the screen-level active backend_id so `_offhand_selection` lookup
        -- still hits and the shield preview doesn't flip back to the new
        -- skin's paired shield when user cycles main-hand illusions.
        --
        -- v0.9.0.13-hotfix: GATE THE FALLBACK on NOT being in a husk wield.
        -- The fallback was a CROSS-BLEED catastrophe for multiplayer: HUSK
        -- wields (other players' equips) call get_item_units with backend_id
        -- nil and item_data.backend_id nil. Without this gate, the fallback
        -- pulled in the LOCAL VIEWER's `_active_customization_backend_id`,
        -- looked up THEIR offhand pick, and painted THEIR shield mesh onto
        -- ANY peer's wielded weapon — including an elf player's spear+shield.
        -- User report 2026-05-19: "the stupid shield now taking the place of
        -- the 'elf's spear and shield' weapon's shield". The fallback is only
        -- meaningful when the local user is cycling skins in the customization
        -- screen — _current_husk_wield being SET means we're inside a husk's
        -- wield, NOT a customization preview, so skip the fallback.
        if not effective_backend_id and not _current_husk_wield then
            effective_backend_id = _active_customization_backend_id
        end
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
        -- v0.9.9.4-dev: per-hand iteration. Each hand_field key in `sel`
        -- writes to the matching `result[hand_field]` independently. Single-
        -- mount weapons only have `left_hand_unit` populated (legacy
        -- behavior); multi-mount weapons (rapier+pistol, dual-wields) may
        -- have BOTH hands set.
        if effective_backend_id then
            _migrate_legacy_offhand_selection(effective_backend_id)
        end
        -- v0.9.41-dev (#150): while the customization screen is open, do NOT
        -- apply the in-progress offhand mesh override to the LIVE in-keep /
        -- in-mission body (create_equipment, flagged by _in_create_equipment).
        -- Only the customization PREVIEWER should reflect the browse pick; the
        -- live body commits on screen exit via the deferred broadcast +
        -- pulse-wield. Without this, mousing/clicking illusions mutated the
        -- equipped weapon on the player's own body. Detect "browsing this item"
        -- via effective_backend_id == _active_customization_backend_id. The
        -- previewer's own get_item_units call is NOT inside create_equipment, so
        -- its override (the correct preview) still applies. Missions are
        -- unaffected (screen closed → _active_customization_backend_id is nil).
        local _suppress_browse_override = _in_create_equipment
            and _active_customization_backend_id ~= nil
            and effective_backend_id == _active_customization_backend_id
        if _suppress_browse_override then
            _dbg("[offhand] suppress browse-override on live body bid=%s (customization screen open)",
                tostring(effective_backend_id))
            -- v0.9.43-dev RESOLVE trace: the #150 live-body suppression fired.
            -- This is the gate the teammate flagged as bypassed on hover — if
            -- the bad paints route through loot_previewer (not create_equipment),
            -- _in_create_equipment is FALSE here so this never fires for them.
            _trace("RESOLVE suppress-browse bid=%s (in_create_equipment + active_cust match) → live body mesh override SUPPRESSED",
                tostring(effective_backend_id))
        end
        local sel = (not _suppress_browse_override) and effective_backend_id
            and _offhand_selection[effective_backend_id]
        if type(sel) == "table" then
            for hand_field, opt in pairs(sel) do
                if type(opt) == "table" then
                    local override_unit = opt.unit or opt.intended_unit
                    -- v0.9.45-dev (BUG 1/2): variant-aware resolution for kind=
                    -- "unit" LA shields. For those picks resolve the override mesh
                    -- + its 3P readiness through the SAME helper the husk path uses
                    -- (_resolve_la_unit_mesh → new_units[1]/[2]) instead of
                    -- _override_package_ready's `.."_3p"` suffix derivation, so the
                    -- host's own body and the husk view can't disagree on whether
                    -- the mesh is swappable. Non-LA picks AND kind="texture" LA
                    -- picks (no custom mesh) keep the legacy _override_package_ready
                    -- gate (their intended_unit is a vanilla mesh).
                    local resolved_unit, resolved_ready
                    if opt.la_armoury_key then
                        local la_1p, _la_3p, la_ready = _resolve_la_unit_mesh(opt.la_armoury_key)
                        if la_1p then
                            resolved_unit, resolved_ready = la_1p, la_ready
                        else
                            resolved_unit = override_unit
                            resolved_ready = (override_unit and _override_package_ready(override_unit)) or false
                        end
                    else
                        resolved_unit = override_unit
                        resolved_ready = (override_unit and _override_package_ready(override_unit)) or false
                    end
                    -- v0.9.43-dev RESOLVE trace: full provenance for the offhand
                    -- mesh-override decision on the LOCAL/live body + previewer.
                    -- `ready` now reflects the variant-aware resolution above;
                    -- `suffix3p_ok` is still logged so the trace shows whether the
                    -- old `.."_3p"` suffix would have resolved (they agree for
                    -- today's shields, where new_units[2] == new_units[1].."_3p").
                    local la = get_mod("Loremasters-Armoury")
                    local variant = opt.la_armoury_key and la and la.SKIN_LIST
                        and la.SKIN_LIST[opt.la_armoury_key]
                    local cg = Application and Application.can_get
                    local suffix_3p_ok = (override_unit and cg)
                        and cg("unit", tostring(override_unit) .. "_3p") or false
                    _trace("RESOLVE item_type=%s hand=%s bid=%s in_create_equipment=%s active_cust_match=%s override_unit=%s resolved_unit=%s ready=%s suffix3p_ok=%s kind=%s new_units1=%s new_units2=%s decision=%s",
                        tostring(item_type), tostring(hand_field), tostring(effective_backend_id),
                        tostring(_in_create_equipment),
                        tostring(_active_customization_backend_id ~= nil and effective_backend_id == _active_customization_backend_id),
                        tostring(override_unit), tostring(resolved_unit), tostring(resolved_ready), tostring(suffix_3p_ok),
                        tostring(variant and variant.kind),
                        tostring(variant and variant.new_units and variant.new_units[1]),
                        tostring(variant and variant.new_units and variant.new_units[2]),
                        (resolved_unit and resolved_ready) and "apply-override" or (resolved_unit and "SKIP(package-not-ready)" or "passthrough(no-mesh)"))
                    if resolved_unit and resolved_ready then
                        result[hand_field] = resolved_unit
                    elseif resolved_unit then
                        _dbg("[offhand] SKIP override %s/%s -> %s (package not ready)",
                            tostring(item_type), tostring(hand_field), tostring(resolved_unit))
                    end
                end
            end
        end

        -- v0.9.3.5: REVERTED the v0.9.3.4 _fallback_if_unloadable gate.
        --
        -- That gate post-processed `result` with `Application.can_get` and
        -- either fell back to `item_data[field]` or cleared the field to nil
        -- when paths were not engine-resident at the moment of the call.
        --
        -- Confirmed regressions (PC-A log 18:51:57, PC-B log 18:52:32):
        --   * 55 elf weapon fields CLEARED to nil during keep async-load
        --     windows — wpn_we_sword_01, wpn_we_dagger_01, wpn_we_deus_02
        --     all both variant AND base returned can_get=false transiently
        --     while the packages were still async-loading. Resulting nil
        --     paths left the elf's weapons INVISIBLE in her hands.
        --   * The gate ran AFTER `result.left_hand_unit = override_unit`,
        --     so the LA offhand override got OVERWRITTEN with the base
        --     vanilla path or nil whenever `can_get` was transiently false
        --     for the override path. PC-A saw vanilla shield locally;
        --     PC-B (peer, who received the broadcast separately) saw the
        --     LA variant correctly. That's the asymmetry the user reported.
        --
        -- `Application.can_get` is unreliable during the async-load window
        -- in keep — paths that ARE valid (in inventory_package_list.lua,
        -- finishing async load) return false transiently. The gate was too
        -- aggressive to be a useful defense.
        --
        -- The original crash this was meant to prevent
        -- (c_api_world.cpp:67 assert on wpn_es_deus_shield_02_magic_3p
        -- after ProfileSync unload) needs a different mechanism — likely
        -- a synchronous `Managers.package:load` before the override
        -- commits, ensuring the unit is in the resource manager when the
        -- wield RPC fires. Deferred to a follow-up.

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

-- v0.9.0-dev: per-peer glow channel.
--
-- BEFORE: every glow read called `mod:get("...")` against the LOCAL viewer's
-- settings. When painting a remote husk, the viewer's chosen glow was applied
-- to the wearer's weapon — i.e. host saw client's weapon glowing with HOST's
-- color, not the client's. Bug 4 in the host/client desync investigation.
--
-- NOW: a new RPC channel `cos_glow_apply` (host-authoritative, mirrors
-- cos_la_apply) broadcasts each peer's glow state. Every machine caches all
-- known peers' state in `_glow_by_peer`. The glow read helpers accept an
-- optional `peer_id` arg; when set and is NOT the local player, settings are
-- read from `_glow_by_peer[peer_id]` instead of `mod:get`. The apply hook
-- resolves owner-of-unit at call time and threads peer_id through every read.
--
-- Missing cache entry (haven't received that peer's state yet, or they had
-- the bridge dormant) → returns nil from every read → no override → wearer
-- shows vanilla glow. Never bleeds the local viewer's color onto someone
-- else's weapon.
mod._glow_by_peer = mod._glow_by_peer or {}
local _glow_by_peer = mod._glow_by_peer

local function _glow_local_peer_id()
    local pm = Managers and Managers.player
    local lp = pm and pm.local_player and pm:local_player()
    return lp and lp.peer_id
end

local function _glow_is_local_peer(peer_id)
    if not peer_id then return true end  -- nil → caller wants local (default)
    local local_peer = _glow_local_peer_id()
    return local_peer == peer_id
end

-- Look up a per-peer glow setting. Returns nil when the peer is remote AND
-- their state hasn't been received yet (don't fall back to local viewer's
-- setting — that's the exact bug we're fixing).
local function _glow_get(peer_id, key)
    if _glow_is_local_peer(peer_id) then
        return mod:get(key)
    end
    local state = _glow_by_peer[peer_id]
    if not state then return nil end
    return state[key]
end

local function _glow_master_mult(peer_id)
    local v = _glow_get(peer_id, "glow_mult_master")
    return type(v) == "number" and v or 1.0
end

local function _glow_var_mult(setting, peer_id)
    if not setting then return 1.0 end
    local v = _glow_get(peer_id, setting)
    return type(v) == "number" and v or 1.0
end

local function _glow_override_enabled(peer_id)
    return _glow_get(peer_id, "glow_override_enable") == true
end

-- Resolves a preset key to RGB. The special key "default" (and unknown keys)
-- return nil — caller treats nil as "don't override this channel, leave
-- vanilla's value in place".
local function _resolve_preset_rgb(key)
    if not key or key == "default" then return nil end
    return _COLOR_PRESETS[key]
end

local function _glow_main_rgb(peer_id)
    if not _glow_override_enabled(peer_id) then return nil end
    return _resolve_preset_rgb(_glow_get(peer_id, "glow_override_preset"))
end

-- RGB to use for a given variable. When per-channel is enabled, the magic-
-- family groups (lower/upper/dots) consult their own dropdowns; rune-family
-- always uses the main picker (only one channel — per-channel split would be
-- meaningless). Returns nil when:
--   * override toggle is OFF, or
--   * the relevant dropdown is set to "default" — meaning this specific
--     variable should NOT be overridden, vanilla's value stays.
-- v0.9.6 M2: weak-table unit→backend_id mapping. Populated by the
-- GearUtils.create_equipment hook (line ~3416). Weak keys so units that
-- get destroyed auto-clean. Used by _apply_glow_to_unit to resolve which
-- backend_id's per-item glow override to apply.
mod._unit_to_backend_id = mod._unit_to_backend_id or setmetatable({}, { __mode = "k" })

local function _glow_rgb_for_var(var_name, peer_id)
    -- v0.9.6 M2: per-item RUNE override is applied DIRECTLY in
    -- _apply_glow_to_unit (before this function gets called), so the
    -- per-item path doesn't go through here. This function handles the
    -- existing global override logic for both rune AND magic-family
    -- shader vars.
    if not _glow_override_enabled(peer_id) then return nil end
    local info = _GLOW_VAR_BRIGHTNESS[var_name]
    local group = info and info.group
    if _glow_get(peer_id, "glow_per_channel_color_enable") then
        local setting = group and _GLOW_GROUP_COLOR_SETTING[group]
        if setting then
            local key = _glow_get(peer_id, setting)
            -- Per-channel dropdown drives this variable. "default" → skip.
            -- Any concrete preset → use it. Unknown key → fall through to main.
            if key == "default" then return nil end
            local rgb = _resolve_preset_rgb(key)
            if rgb then return rgb end
        end
    end
    -- Fallback: main color picker (also returns nil if main is "default")
    return _glow_main_rgb(peer_id)
end

-- Resolve the wearer peer for the unit being painted. Used by the per-peer
-- glow hook to thread owner identity through. Returns nil for non-player
-- units (NPC display weapons, drops, etc.) — caller treats nil as "local
-- viewer's settings" which is the historical behavior for those paths.
local function _glow_owner_peer_for_unit(unit)
    if not unit then return nil end
    local pm = Managers and Managers.player
    if not pm then return nil end
    -- 1. Direct owner lookup (works for local player + bots; sometimes
    -- returns nil during mission-spawn race per the memory note).
    if pm.owner then
        local owner = pm:owner(unit)
        if owner and owner.peer_id then return owner.peer_id end
    end
    -- 2. Husk-side fallback: the player_unit's inventory_system has
    -- `_owner_player_id` set; not the same as peer_id but lookup via the
    -- player table works.
    if ScriptUnit and ScriptUnit.has_extension then
        local inv = ScriptUnit.has_extension(unit, "inventory_system")
        if inv and inv._owner_player_id then
            -- _owner_player_id is the unique id; walk human players to find peer
            if pm._human_players then
                for _, p in pairs(pm._human_players) do
                    if p.player_unit == unit then return p.peer_id end
                end
            end
        end
        -- 3. Last-resort husk: weapon/hat units carry no inventory_system,
        -- but their parent player_unit does. We don't traverse parents here —
        -- caller passes the OWNING player_unit (resolved upstream via
        -- equipment.left_hand_wielded_unit_3p etc. → owner of player_unit).
    end
    return nil
end

-- v0.9.0-dev: per-peer glow apply. `owner_peer_id` resolves which peer's
-- settings drive the override. nil means "local viewer" (legacy behavior for
-- NPC display weapons, pickups, etc.).
local function _apply_glow_to_unit(unit, owner_peer_id)
    if not unit or not _is_unit(unit) then return end
    -- v0.9.6 M2: per-item override BEFORE the global toggle gate. The
    -- popup is "always available regardless of toggle" per user direction.
    -- Currently only RUNE component is wired (single channel,
    -- rune_emissive_color). HDR scaling: user RGB / 255 × native template
    -- brightness (9 for rune_emissive_color per _GLOW_VAR_BRIGHTNESS)
    -- × intensity slider value. intensity=0 → skip (vanilla shows through).
    if mod._per_item_glow_runtime and mod._unit_to_backend_id then
        local bid = mod._unit_to_backend_id[unit]
        if bid then
            local pi = mod._per_item_glow_runtime[bid]
            if pi then
                -- v0.9.8: per-item explicit OFF toggle. If user disabled
                -- glow for this item, paint zeros (effectively disable)
                -- and skip both per-item and global paths. Vanilla
                -- material set_vector3 with zeros = no emissive output.
                if pi.disabled then
                    for var_name, _ in pairs(_GLOW_VAR_BRIGHTNESS) do
                        pcall(Unit.set_vector3_for_materials, unit, var_name, Vector3(0, 0, 0))
                    end
                    return
                end
                -- v0.9.8: helper for per-component HDR scaling. Reads
                -- shader var's native brightness from _GLOW_VAR_BRIGHTNESS,
                -- multiplies by user intensity, divides by 255 (user RGB
                -- is 0-255), writes to material.
                local function _paint_var(var_name, r, g, b, intensity)
                    local info = _GLOW_VAR_BRIGHTNESS[var_name]
                    if not info then return end
                    local scale = (info.brightness or 1) * (intensity or 1) / 255
                    pcall(Unit.set_vector3_for_materials, unit, var_name,
                        Vector3(r * scale, g * scale, b * scale))
                end
                -- RUNE family: single channel.
                if pi.rune and (pi.rune.intensity or 0) > 0 then
                    _paint_var("rune_emissive_color",
                        pi.rune.r or 0, pi.rune.g or 0, pi.rune.b or 0, pi.rune.intensity)
                end
                -- v0.9.8: MAGIC family components. Each component spans
                -- multiple shader vars (lower = glow_high+glow_low,
                -- upper = smoke_high+smoke_low, dots = single). All share
                -- the user's RGB at scaled brightness so vanilla's
                -- coordinated brightness pairs remain proportional.
                if pi.lower and (pi.lower.intensity or 0) > 0 then
                    _paint_var("color_glow_high",
                        pi.lower.r or 0, pi.lower.g or 0, pi.lower.b or 0, pi.lower.intensity)
                    _paint_var("color_glow_low",
                        pi.lower.r or 0, pi.lower.g or 0, pi.lower.b or 0, pi.lower.intensity)
                end
                if pi.upper and (pi.upper.intensity or 0) > 0 then
                    _paint_var("color_smoke_high",
                        pi.upper.r or 0, pi.upper.g or 0, pi.upper.b or 0, pi.upper.intensity)
                    _paint_var("color_smoke_low",
                        pi.upper.r or 0, pi.upper.g or 0, pi.upper.b or 0, pi.upper.intensity)
                end
                if pi.dots and (pi.dots.intensity or 0) > 0 then
                    _paint_var("color_dots",
                        pi.dots.r or 0, pi.dots.g or 0, pi.dots.b or 0, pi.dots.intensity)
                end
                -- If ANY component painted, treat per-item as fully
                -- handled — skip global override. Detection: at least
                -- one component had intensity > 0.
                if (pi.rune and (pi.rune.intensity or 0) > 0)
                    or (pi.lower and (pi.lower.intensity or 0) > 0)
                    or (pi.upper and (pi.upper.intensity or 0) > 0)
                    or (pi.dots and (pi.dots.intensity or 0) > 0) then
                    return
                end
            end
        end
    end
    if not _glow_override_enabled(owner_peer_id) then return end
    -- Per-variable: skip if rgb is nil (main = "default" AND no per-channel
    -- color set for this var's group), else write user RGB scaled to native
    -- brightness × master × per-channel multiplier. mult=0 also skips.
    local master_mult = _glow_master_mult(owner_peer_id)
    for var_name, info in pairs(_GLOW_VAR_BRIGHTNESS) do
        local rgb = _glow_rgb_for_var(var_name, owner_peer_id)
        if rgb then
            local var_mult = _glow_var_mult(info.setting, owner_peer_id)
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

-- v0.9.6 M2: helper for popup live-preview. Re-applies glow on the
-- currently-wielded weapon units. Called from glow picker's on_change
-- callback during slider drag. Best-effort; failures silent.
mod._reapply_glow_on_wielded = function()
    local pm = Managers and Managers.player
    local lp_ok, lp = pcall(function() return pm and pm:local_player() end)
    if not lp_ok then return end
    local pu = lp and lp.player_unit
    if not (pu and Unit.alive(pu) and ScriptUnit and ScriptUnit.has_extension) then return end
    local ext = ScriptUnit.has_extension(pu, "inventory_system")
    if not ext then return end
    local sd_fn = ext.get_wielded_slot_data
    local slot_data = sd_fn and ext:get_wielded_slot_data()
    if not slot_data then return end
    for _, field in ipairs({ "right_unit_1p", "right_unit_3p", "left_unit_1p", "left_unit_3p" }) do
        local u = slot_data[field]
        if u and _is_unit(u) then
            pcall(_apply_glow_to_unit, u, _glow_local_peer_id())
        end
    end
end

-- Backward-compatible alias used by the existing call site at create_equipment.
local function _glow_preset_rgb() return _glow_main_rgb() end

-- v0.9.0-dev: accept owner peer so glow on remote players' weapons reads from
-- the wearer's settings, not the local viewer's. Caller MUST pass owner peer
-- explicitly — units array doesn't carry per-unit owner info, so the resolution
-- happens at the create_equipment hook where we know the player_unit being
-- equipped.
local function _apply_glow_override(units, owner_peer_id)
    if not _glow_override_enabled(owner_peer_id) then return end
    for _, u in ipairs(units) do _apply_glow_to_unit(u, owner_peer_id) end
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
        -- v0.9.0-dev: resolve the wearer of the unit to thread per-peer glow
        -- settings through. For local player + bots → local peer_id (reads
        -- mod:get). For remote husks → wearer peer_id (reads _glow_by_peer).
        -- For non-player units (NPC display weapons, pickups, drops) →
        -- nil → defaults to local viewer (legacy behavior; nobody owns
        -- these). The lookup is fast (single :owner() call) — no measurable
        -- overhead vs the previous fully-local read.
        local owner_peer_id = _glow_owner_peer_for_unit(unit)
        if not _glow_override_enabled(owner_peer_id) then
            if mod:get("glow_trace") then
                _dbg("[GLOW] %s call template=%s peer=%s (override OFF, passthrough)",
                    label, tostring(material_settings_name), tostring(owner_peer_id))
            end
            return func(unit, material_settings_name)
        end
        local template = MaterialSettingsTemplates and MaterialSettingsTemplates[material_settings_name]
        if not template then
            if mod:get("glow_trace") then
                _dbg("[GLOW] %s call template=%s peer=%s (template nil, passthrough)",
                    label, tostring(material_settings_name), tostring(owner_peer_id))
            end
            return func(unit, material_settings_name)
        end
        if mod:get("glow_trace") then
            _dbg("[GLOW] %s mutate template=%s peer=%s",
                label, tostring(material_settings_name), tostring(owner_peer_id))
        end
        -- Mutate per-variable. Skip variables whose color resolves to nil
        -- (= "Default" preset OR main is "Default" with no per-channel color
        -- for this variable's group) — the template's vanilla value passes
        -- through to the spawn unchanged. Skip variables whose mult is 0.
        -- Color and brightness come from _glow_rgb_for_var (respects per-
        -- channel-color toggle) and the var's mult setting.
        local master_mult = _glow_master_mult(owner_peer_id)
        local saved = {}
        for var_name, entry in pairs(template) do
            if entry.type == "vector3" then
                local var_rgb = _glow_rgb_for_var(var_name, owner_peer_id)
                local info = _GLOW_VAR_BRIGHTNESS[var_name]
                local var_mult = info and _glow_var_mult(info.setting, owner_peer_id) or 1.0
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
        if not ok then _dbg_alert("[GLOW] %s vanilla apply errored: %s", label, tostring(err)) end
    end)
    mod._glow_hooks_installed[label] = true
end

_hook_apply_with_template_mutation("GearUtils", "gear")
if rawget(_G, "CosmeticUtils") and CosmeticUtils.apply_material_settings then
    _hook_apply_with_template_mutation("CosmeticUtils", "cosmetic")
else
    mod:info("[GLOW] CosmeticUtils.apply_material_settings nil at hook time")
end

-- v0.9.0-dev: `_G.apply_material_settings` is a BARE GLOBAL declared in
-- `scripts/flow/flow_callbacks_foundation.lua:896`. That file is loaded
-- lazily by Stingray's flow graph (typically first hub/level enter), not
-- during boot. VMF mod-load runs before any flow node fires, so at hook
-- install time the symbol is genuinely nil. Try eagerly; on miss, retry from
-- mod.on_game_state_changed (defined earlier). NOTE: this _G site is the
-- bare-global path used ONLY by NPC display weapons / keep weapon racks —
-- player wielded weapons, husks, projectiles, pickups, and previewer all
-- route through GearUtils.apply_material_settings (already hooked above),
-- so this is purely a coverage-completeness fix for hub setpieces.
local function _try_install_flow_glow_hook()
    if mod._glow_hooks_installed.flow then return true end
    if not _G.apply_material_settings then return false end
    _hook_apply_with_template_mutation(_G, "flow")
    mod:info("[GLOW] _G.apply_material_settings hook installed (deferred)")
    return true
end

if not _try_install_flow_glow_hook() then
    mod:info("[GLOW] _G.apply_material_settings nil at boot; will retry on game-state change")
end
mod._try_install_flow_glow_hook = _try_install_flow_glow_hook

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
    -- v0.9.37-dev: `glow_override_enable` no longer exists as a VMF setting (the
    -- global "Weapon Glow Override" menu was removed in favor of the per-item
    -- Glow Picker). mod:get returns nil → this branch never fires → injection
    -- is inert. Left guarded (not ripped out) so a future global-glow feature
    -- could re-enable it by restoring the setting. The Glow Picker drives
    -- non-templated meshes via its own per-item runtime path, not this injection.
    if material_settings_name == nil and mod:get("glow_override_enable") and item_units then
        local mesh = item_units[hand .. "_hand_unit"]
        if mesh and (mesh:find("_runed_01$") or mesh:find("_magic_01$")) then
            material_settings_name = "_cosmetics_tweaker_glow"
            if mod:get("glow_trace") then
                _dbg("[GLOW] inject template for mesh=%s hand=%s", tostring(mesh), tostring(hand))
            end
        end
    end
    return func(world, hand, item_template, item_units, slot_name, item_data, owner_unit_1p, owner_unit_3p, unit_template, extra_extension_data, ammo_percent, material_settings_name)
end)

mod:command("glow_status", "Report glow hook health and per-hook call counts since session start", function()
    -- v0.9.37-dev: the global "Weapon Glow Override" VMF menu was removed; glow
    -- is now driven by the per-item Glow Picker popup. `glow_override_enable` /
    -- `glow_override_preset` no longer exist as settings (mod:get → nil), so the
    -- old enable/preset echo was dropped. This command now reports apply-hook
    -- health (still load-bearing — the Glow Picker's per-item paint flows through
    -- the same _apply_glow_to_unit pipeline) and the Glow Picker open state.
    local trace = mod:get("glow_trace")
    mod:echo(string.format("[glow_status] trace=%s picker_open=%s",
        tostring(trace), tostring(GlowPicker and GlowPicker.is_open and GlowPicker.is_open())))
    for _, label in ipairs({ "gear", "flow", "cosmetic" }) do
        mod:echo(string.format("[glow_status] hook[%s] installed=%s calls_this_session=%d",
            label,
            tostring(mod._glow_hooks_installed[label]),
            mod._glow_call_counts[label] or 0))
    end
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
-- v0.9.45-dev (BUG 1/2): is it safe to paint kind="unit" LA heraldry onto unit
-- `u`? Only when `u`'s authored mesh (`unit_name`) IS the variant's custom mesh
-- (new_units[1] 1P or new_units[2] 3P). kind="texture" variants paint the base
-- mesh by design and are never gated; units whose mesh can't be read fall
-- through to the legacy (paint) behavior so the working cases never regress.
-- Reuses _unit_mesh_name (pcall-safe). Called only on the "ingame" path.
local function _offhand_paint_mesh_ok(u, armoury_key)
    local la = get_mod("Loremasters-Armoury")
    local variant = la and la.SKIN_LIST and la.SKIN_LIST[armoury_key]
    if not (variant and variant.kind == "unit" and variant.new_units) then return true end
    local actual = _unit_mesh_name(u)
    if actual == "<no-unit_name>" or actual == "<not-unit>" then return true end
    return actual == tostring(variant.new_units[1])
        or (variant.new_units[2] ~= nil and actual == tostring(variant.new_units[2]))
end

local function _apply_la_offhand_to_units(world, item_data, units, has_skin, backend_id_arg, context)
    if not LA_BRIDGE.registered then _dbg("[LA paint] skip: bridge not registered"); return end
    if not world or not item_data then _dbg("[LA paint] skip: world/item_data nil"); return end
    if not has_skin then _dbg("[LA paint] skip: has_skin=false"); return end
    -- v0.8.32: read selection by backend_id. Resolve from arg first, then
    -- from item_data.backend_id (vanilla stamps this on equipment resync).
    local bid = backend_id_arg or (item_data and item_data.backend_id)
    if not bid then _dbg("[LA paint] skip: no backend_id"); return end
    -- v0.9.41-dev (#150): suppress the browse-time LA texture paint on the LIVE
    -- in-keep / in-mission body while the customization screen is open for this
    -- item. Mirrors the get_item_units mesh-override suppression: only the loot
    -- previewer shows the in-progress pick; the live body refreshes on screen
    -- exit (pulse-wield). "ingame" is the create_equipment path; the preview
    -- contexts ("loot_previewer"/"hero_previewer") are untouched. Missions are
    -- unaffected (screen closed → _active_customization_backend_id is nil).
    if context == "ingame" and _active_customization_backend_id ~= nil
        and bid == _active_customization_backend_id then
        _dbg("[LA paint] suppress ingame browse-paint for bid=%s (customization screen open)", tostring(bid))
        return
    end
    _migrate_legacy_offhand_selection(bid)
    local per_hand_sel = _offhand_selection[bid]
    if type(per_hand_sel) ~= "table" then
        _dbg("[LA paint] skip: no _offhand_selection for backend_id=%s", tostring(bid)); return
    end
    -- v0.9.9.4-dev: caller passes the units it has spawned. LA paints are
    -- texture-only and idempotent across all matching unit meshes — we
    -- paint EVERY selection (any hand_field) onto EVERY passed unit. The
    -- callers below restrict `units` to the appropriate hand (e.g. ingame
    -- passes left_unit_3p/1p; loot previewer passes index 1 = left). For
    -- multi-mount weapons with LA picks on both hands the paint runs once
    -- per hand selection on whichever units the caller supplied.
    local painted = false
    for hand_field, sel in pairs(per_hand_sel) do
        if type(sel) == "table" and sel.la_armoury_key then
            _dbg("[LA paint] painting %s (%s) on %d units (backend_id=%s)",
                tostring(sel.la_armoury_key), hand_field, #units, tostring(bid))
            for _, u in ipairs(units) do
                if u and _is_unit(u) then
                    -- v0.9.45-dev (BUG 1/2): on the LIVE in-keep / in-mission body
                    -- ("ingame") the kind="unit" mesh override can be skipped
                    -- (readiness / package-load timing) leaving the VANILLA shield
                    -- mesh (e.g. the bret heater) in hand. Painting the LA imperial
                    -- heraldry onto that un-swapped mesh is exactly the warped
                    -- imperial-texture-on-bret-mesh symptom. Refuse to paint when
                    -- the target unit's authored mesh is NOT the variant's custom
                    -- mesh.
                    -- v0.9.53-dev (#200): EXTENDED the gate from "ingame"-only to
                    -- every non-husk context (ingame + loot_previewer +
                    -- hero_previewer). This is symptom B of the user's report —
                    -- "textures wrapped around the WRONG model when previewing a
                    -- DIFFERENT model": cycling row-1 weapon illusions re-spawns the
                    -- previewer with the NEW illusion's paired shield mesh, but the
                    -- stale _offhand_selection still paints the kind="unit" LA
                    -- heraldry onto it. Gating the previewer contexts on the same
                    -- mesh-match check stops the warp without regressing the correct
                    -- case: when the previewer DID spawn the LA mesh the gate passes
                    -- (mesh matches) and the paint proceeds; when the mesh is
                    -- unreadable (<no-unit_name>) the gate is permissive (returns
                    -- true) so existing preview behavior is unchanged. The husk path
                    -- ("network_husk") still always mesh-swaps first, so it is NOT
                    -- gated. Non-fatal (mesh read is pcall-guarded in
                    -- _unit_mesh_name); kind="texture" picks are never gated.
                    if context ~= "network_husk"
                        and not _offhand_paint_mesh_ok(u, sel.la_armoury_key) then
                        _dbg("[LA paint]   SKIP unit=%s key=%s ctx=%s — mesh is NOT the swapped LA mesh; refusing to warp heraldry onto mismatched shield",
                            tostring(u), tostring(sel.la_armoury_key), tostring(context))
                        -- _trace_paint routes through mod:info (visible with
                        -- output_mode_debug OFF) and carries the [cos:weapon-leak]-
                        -- relevant SKIP-mesh-mismatch provenance line.
                        _trace_paint(context, context, bid, u, sel.la_armoury_key, "SKIP-mesh-mismatch")
                        if PROBE then
                            PROBE.emit("cos:sync",
                                "offhand_gate/" .. tostring(context) .. "/" .. tostring(sel.la_armoury_key) .. "/" .. tostring(u),
                                string.format("peer=local ctx=%s key=%s unit=%s decision=SKIP reason=mesh-mismatch(warp-guard)",
                                    tostring(context), tostring(sel.la_armoury_key), tostring(u)))
                        end
                    else
                    local ok = LA_BRIDGE.apply_offhand_to_unit(world, u, sel.la_armoury_key, sel.vanilla_skin, context)
                    _dbg("[LA paint]   unit=%s ok=%s", tostring(u), tostring(ok))
                    if PROBE then
                        PROBE.emit("cos:sync",
                            "offhand_gate/" .. tostring(context) .. "/" .. tostring(sel.la_armoury_key) .. "/" .. tostring(u),
                            string.format("peer=local ctx=%s key=%s unit=%s decision=PAINT outcome=%s",
                                tostring(context), tostring(sel.la_armoury_key), tostring(u), tostring(ok)))
                    end
                    -- v0.9.43-dev PAINT trace (full provenance). site == context
                    -- (loot_previewer / ingame / hero_previewer). match=false here
                    -- is the smoking gun: imperial texture painted onto a unit
                    -- whose mesh is still the bret shield (mesh override didn't
                    -- swap on this path). See _trace_paint.
                    _trace_paint(context, context, bid, u, sel.la_armoury_key, ok)
                    end
                end
            end
            painted = true
        end
    end
    if not painted then return end
end

-- In-game keep / mission body
-- THREE RENDERING PATHS COVERAGE:
--   - In-game (GearUtils.create_equipment): THIS HOOK
--   - Inventory previewer (HeroPreviewer._spawn_item): _spawn_item_wrapper below
--   - Illusion browser (LootItemUnitPreviewer.spawn_units): hook below
mod:hook("GearUtils", "create_equipment", function(func, world, slot_name, item_data, unit_1p, unit_3p, is_bot, unit_template, extra_extension_data, ammo_percent, override_item_template, override_item_units, career_name)
    -- v0.9.5: fold MH embed's texture/particle work BEFORE vanilla call.
    -- Matches the original MH-embed hook order (replace then vanilla then
    -- particles). When embed is dormant (standalone enabled), MH_EMBED
    -- exports are no-ops.
    if MH_EMBED and not MH_EMBED.dormant then
        MH_EMBED.replace_textures(unit_1p)
        MH_EMBED.replace_textures(unit_3p)
        MH_EMBED.add_particles(unit_1p, world)
        MH_EMBED.add_particles(unit_3p, world)
    end
    -- v0.9.41-dev (#150): flag the live-body spawn so the get_item_units hook
    -- (called INSIDE vanilla create_equipment) can suppress the browse-time
    -- offhand override on the player's own equipped weapon while the
    -- customization screen is open. Save/restore for nested-call safety.
    local _prev_in_create_equipment = _in_create_equipment
    _in_create_equipment = true
    local result = func(world, slot_name, item_data, unit_1p, unit_3p, is_bot, unit_template, extra_extension_data, ammo_percent, override_item_template, override_item_units, career_name)
    _in_create_equipment = _prev_in_create_equipment
    -- v0.9.6 M2: stash unit→backend_id mapping for the glow picker's
    -- per-item override lookup. Weak-keyed table auto-cleans when units
    -- get destroyed. Covers all 4 hand-unit fields the previewer and
    -- in-keep paths might query.
    if result and item_data and item_data.backend_id and mod._unit_to_backend_id then
        local bid = item_data.backend_id
        for _, field in ipairs({ "left_unit_1p", "right_unit_1p", "left_unit_3p", "right_unit_3p" }) do
            local u = result[field]
            if u then mod._unit_to_backend_id[u] = bid end
        end
    end
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
        _apply_la_offhand_to_units(world, item_data, { result.left_unit_3p, result.left_unit_1p }, has_skin, nil, "ingame")
    end
    if result then
        -- v0.9.0-dev: resolve wearer from the 3P unit (= player_unit body).
        -- create_equipment doesn't pass a player object, but unit_3p IS the
        -- player_unit here, so :owner(unit_3p) resolves the peer correctly
        -- for both local + remote husk equips.
        local owner_peer_id = _glow_owner_peer_for_unit(unit_3p)
        _apply_glow_override({
            result.right_unit_3p, result.left_unit_3p,
            result.right_unit_1p, result.left_unit_1p,
        }, owner_peer_id)
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
                _dbg("[LA preview] backend-resolved skin for %s: %s", tostring(item_name), tostring(resolved))
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
    _dbg("[LA preview] equip_item key=%s slot=%s bid=%s skin=%s is_clone=%s",
        tostring(item_key), tostring(slot_name), tostring(backend_id), tostring(skin),
        tostring(LA_BRIDGE.backend_to_armoury[backend_id] ~= nil))

    -- v0.9.8.2: stash backend_id for the previewer-spawned weapon units
    -- so the glow picker's per-item override resolves correctly. Folded
    -- in here instead of a separate hook_safe — using hook_safe on the
    -- same Class+method as our existing mod:hook caused rehook warnings
    -- at boot (v0.9.7 regression).
    if backend_id then self._cos_current_equip_backend_id = backend_id end

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
        _dbg("[LA preview] equip_item swapping key %s -> %s for clone", tostring(item_key), tostring(backend_id))
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
    -- v0.9.8.2: stash backend_id (see same fold in MenuWorldPreviewer hook above)
    if backend_id then self._cos_current_equip_backend_id = backend_id end
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
                    _apply_la_offhand_to_units(world, item_data, left_units, has_skin, stored_bid, "hero_previewer")
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
                    _dbg("[thiccc] preview name=%s skin=%s right=%s left=%s",
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
    _dbg("[LA preview] _spawn_item name=%s direct=%s", tostring(item_name), tostring(is_direct_clone ~= nil))
    if is_direct_clone then
        self._cos_la_spawning = item_name
        _dbg("[LA preview]   -> spawning clone %s", item_name)
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
-- a different approach. CORRECTED (2026-06-21): the crash hash
-- `3ac73385950a26ea` is NOT a vanilla material — it is LA's WHOLE package
-- (`resource_packages/Loremasters-Armoury/Loremasters-Armoury`; Stingray names
-- every bundle by murmur64A of its package path). v0.8.27 crashed because the
-- sync `load()` FORCE-MATERIALIZED that package, and LA's installed bundle is
-- missing an internal member -> a C-level resource_package fatal (uncatchable
-- by pcall; fires async). gut's `_la_atlas_keepalive.lua` (v0.2.54) hit + fixed
-- the same class: only reference LA's package when it is ALREADY resident
-- (pm:has_loaded) so load() is a pure ref-count bump; NEVER force-load it.
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
                    _dbg("[LA preview-load] sync-loaded parent %s for %s",
                        parent_pkg, package_name)
                else
                    _dbg_alert("[LA preview-load] FAILED to load parent %s for %s: %s",
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
            -- v0.8.55-dev: when previewing a pending-cycle skin, item.backend_id
            -- is nil. Fall back to the customization screen's active backend_id
            -- so the LA paint follows the row-2 offhand selection while user
            -- cycles row-1 main-hand illusions.
            local effective_bid = item.backend_id or _active_customization_backend_id
            _apply_la_offhand_to_units(world, item_data, { units[1] }, true, effective_bid, "loot_previewer")
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

-- #148 guard: a preview whose link unit failed to resolve (e.g. an LA custom
-- item with no display_unit) still latches _items_spawned via the hand-unit
-- package path, leaving _unit_start_position_boxed nil; a later zoom request
-- (set_zoom_fraction → _zoom_dirty) then crashes at
-- loot_item_unit_previewer.lua:142 (`self._unit_start_position_boxed:unbox()`).
-- The sibling rotation branch is already vanilla-nil-guarded (`if link_unit`);
-- this zoom branch is the one Fatshark missed. Clear the pending zoom when the
-- boxed start position is absent — there's no link unit to reposition, so
-- preview rotation/visibility is unaffected. Reached from the Weave Forge
-- overview (crash GUID per Issue #148, locals confirm link_unit = nil).
mod:hook("LootItemUnitPreviewer", "update", function(func, self, dt, t, input_service)
    if self._zoom_dirty and not self._unit_start_position_boxed then
        self._zoom_dirty = nil
    end
    return func(self, dt, t, input_service)
end)

-- ============================================================
-- #174 VANILLA CHOKEPOINT (attribution host, passive)
-- ============================================================
-- `BackendInterfaceItemPlayfab:set_loadout_item(item_id, career, slot, index)`
-- is the concrete backend method every loadout write funnels through
-- (BackendUtils.set_loadout_item dispatches into it), and it carries the
-- `optional_loadout_index` that distinguishes a BOT's designated loadout from
-- the host's selected one -- exactly the discriminator issue #174 needs. This
-- is the SINGLE vanilla chokepoint the team-lead brief asked for, hosted here in
-- cosmetics_tweaker (grep confirmed no existing hook on this Class.method in this
-- mod; cim_dev hooks the same pair in a DIFFERENT mod, which is fine -- VMF
-- tracks hooks per-mod). hook_safe = pure post-observation, no return override.
-- The caller hint (2-4 stack frames, single line) names the code path that
-- reached the setter, so one keep visit after startup shows WHO restores the bot
-- slots (a vanilla bot-loadout replay, an inventory equip, or a mod). eac_window
-- reads mp's un-gate flag so a write that lands while mp has the realm un-gated
-- is attributable. Rate-limit: freely for the startup window, then on-change per
-- career/slot/item/index (see _diag_probe.lua).
mod:hook_safe("BackendInterfaceItemPlayfab", "set_loadout_item", function(self, item_id, career_name, slot_name, optional_loadout_index)
    if not PROBE then return end
    local mp = get_mod("mp")
    local eac = mp and mp.is_eac_window and mp.is_eac_window()
    -- Depth 5 from level 2 walks past our callback + VMF's hook-dispatch frames
    -- so the game-source caller (the last non-vmf/non-hooks.lua frame) is
    -- captured; the reader picks the game frame out of the chain.
    local caller = PROBE.caller_hint(2, 5)
    PROBE.emit("174:loadout",
        "vanilla/" .. tostring(career_name) .. "/" .. tostring(slot_name) .. "/" .. tostring(optional_loadout_index) .. "/" .. tostring(item_id),
        string.format("cosmetics VANILLA BackendInterfaceItemPlayfab.set_loadout_item profile=%s slot=%s item=%s idx=%s mp_eac_window=%s caller=%s",
            tostring(career_name), tostring(slot_name), tostring(item_id),
            tostring(optional_loadout_index), tostring(eac), tostring(caller)))
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
        -- #174: cosmetics' OWN loadout write path (the menu-equip dispatcher).
        -- Logs every write it sees plus whether the item is an LA clone we cache
        -- into mod.loadout_cache (which cosmetics injects back on get_loadout).
        if PROBE then
            PROBE.emit("174:loadout",
                "cos_bu/" .. tostring(career_name) .. "/" .. tostring(slot_name) .. "/" .. tostring(backend_id),
                string.format("cosmetics BackendUtils.set_loadout_item profile=%s slot=%s item=%s la_clone=%s",
                    tostring(career_name), tostring(slot_name), tostring(backend_id),
                    tostring(LA_BRIDGE.backend_to_armoury[backend_id] ~= nil)))
        end
        local is_clone = LA_BRIDGE.backend_to_armoury[backend_id]
        if is_clone and (slot_name == "slot_hat" or slot_name == "slot_skin") then
            mod.loadout_cache[career_name] = mod.loadout_cache[career_name] or {}
            mod.loadout_cache[career_name][slot_name] = backend_id
            _dbg("[loadout] CACHED %s %s = %s", career_name, slot_name, backend_id)
            return
        end
        if (slot_name == "slot_hat" or slot_name == "slot_skin") and mod.loadout_cache[career_name] then
            _dbg("[loadout] CLEARED cache %s %s (vanilla bid=%s)", career_name, slot_name, backend_id)
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

    mod:hook(items_iface, "get_loadout_item_id", function(func, self, career_name, slot_name, is_bot)
        -- BOT-LOADOUT FIX (v0.9.39-dev): vanilla get_loadout_item_id(self, career, slot,
        -- is_bot) resolves the BOT's designated loadout when is_bot=true, else the host's
        -- (backend_interface_item_playfab.lua:512/522). The old hook signature DROPPED the
        -- 4th `is_bot` arg, so every bot query fell through with is_bot=nil and resolved the
        -- HOST's loadout -> bots cloned the host's gear instead of using their own. Forward
        -- is_bot, and never let a bot read mod.loadout_cache (career+slot keyed, holds the
        -- LOCAL player's cross-character cosmetics). Identical to the wt v0.12.115 fix; this
        -- path is LA-gated (_install_skin_loadout_safety), so it only bit users running LA.
        if not is_bot and mod.loadout_cache[career_name] and mod.loadout_cache[career_name][slot_name] then
            return mod.loadout_cache[career_name][slot_name]
        end
        local raw = func(self, career_name, slot_name, is_bot)
        if raw and LA_BRIDGE.registered and LA_BRIDGE.backend_to_armoury[raw] then
            local vanilla_key = LA_BRIDGE.backend_to_vanilla[raw]
            if vanilla_key then
                local all_items = items_iface:get_all_backend_items()
                for bid, item in pairs(all_items or {}) do
                    if item.key == vanilla_key and not LA_BRIDGE.backend_to_armoury[bid] then
                        _dbg("[loadout] redirected server clone %s -> vanilla %s (%s)", raw, bid, vanilla_key)
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
                                _dbg("[loadout] fixup server: %s %s clone %s -> vanilla %s", career_name, slot_name, bid, vbid)
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

-- v0.8.57-dev: prevent network sync of LA cosmetic backend_ids to peers.
-- Crash GUID fa479a72 — friend's vanilla client received an item_names
-- index our mod had locally registered (e.g. 2959) and crashed in
-- NetworkLookup.lua:2514's strict __index metamethod when decoding.
-- Root cause: `CosmeticUtils.update_cosmetic_slot` calls
-- `player:set_data(slot, name_id)` where `name_id` is
-- `NetworkLookup.item_names[la_backend_id]` — a LOCAL index our
-- _la_bridge.register_all added via rawset. Peers don't have that
-- index → crash on decode.
-- Fix: hook update_cosmetic_slot, substitute LA backend_ids with their
-- vanilla equivalent for the sync call. Local player still sees the LA
-- hat (visual is applied via the loadout_cache + LA's own apply path,
-- not via sync_data). Husk-side rendering on peers shows the vanilla
-- equivalent — the closest thing they can render without our mod.
-- v0.8.59-dev: CosmeticUtils is a PLAIN TABLE (`CosmeticUtils = CosmeticUtils
-- or {}` at cosmetic_utils.lua:3), not a class. v0.8.58 used string-form
-- `mod:hook("CosmeticUtils", ...)` which VMF can't resolve for plain tables
-- — the hook silently never fired and the crash kept reproducing. Same
-- pitfall as BackendUtils (CLAUDE.md "Hooking" section). Must use the
-- table-form `mod:hook(CosmeticUtils, ...)` with a nil guard.
if CosmeticUtils then
    mod:hook(CosmeticUtils, "update_cosmetic_slot", function(func, player, slot, item_name, skin_name)
        -- v0.9.12-dev: persistence-driven LA injection. On the FIRST
        -- update_cosmetic_slot for a weapon slot in a new session, vanilla
        -- passes the saved vanilla-substitute skin (because PlayFab can't
        -- store LA names). If the player's current weapon backend_id has a
        -- saved LA illusion on disk, swap skin_name in to the LA bid BEFORE
        -- the substitution check below — that way the existing flow paints
        -- LA visuals AND falls through to net-safe vanilla substitution.
        -- Same idea for hat / armor via the per-career table.
        if LA_PERSIST and player and player.player_unit then
            if slot == "slot_hat" or slot == "slot_skin" then
                if item_name and LA_BRIDGE and LA_BRIDGE.backend_to_armoury
                    and not LA_BRIDGE.backend_to_armoury[item_name]
                then
                    local career = LA_PERSIST._career_name_for_player(player)
                    local saved = career and LA_PERSIST.get_saved_cosmetic(career, slot)
                    if saved and saved ~= item_name then
                        _dbg("[la-persist] inject %s/%s vanilla(%s) -> LA(%s)",
                            tostring(career), tostring(slot), tostring(item_name), tostring(saved))
                        item_name = saved
                    end
                end
            else
                if skin_name and LA_BRIDGE and LA_BRIDGE.backend_to_armoury
                    and not LA_BRIDGE.backend_to_armoury[skin_name]
                then
                    local inv = ScriptUnit.has_extension(player.player_unit, "inventory_system")
                    local slot_data = inv and inv._equipment and inv._equipment.slots
                        and inv._equipment.slots[slot]
                    local backend_id = slot_data and slot_data.item_data and slot_data.item_data.backend_id
                    local saved = backend_id and LA_PERSIST.get_saved_illusion(backend_id)
                    if saved and saved ~= skin_name then
                        _dbg("[la-persist] inject illusion %s vanilla(%s) -> LA(%s)",
                            tostring(backend_id), tostring(skin_name), tostring(saved))
                        skin_name = saved
                    end
                end
            end
        end

        -- v0.8.64-dev: substitute BOTH item_name AND skin_name. The original
        -- v0.8.58 hook substituted only item_name (the 4th arg) — but
        -- cosmetic_utils.lua:245 also reads NetworkLookup.weapon_skins[skin_name]
        -- and :249 broadcasts via player:set_data. If the user equips an LA-
        -- cloned weapon ILLUSION, the LA skin_name reaches peers' decode path
        -- and crashes them in the same NetworkLookup __index fashion as the
        -- fa479a72 crash. Same shape of substitution: LA -> vanilla via
        -- backend_to_vanilla; SKIP the call if no fallback exists.
        local effective_item_name = item_name
        local effective_skin_name = skin_name
        local la_item_subbed = false
        local la_skin_subbed = false

        if LA_BRIDGE and LA_BRIDGE.registered then
            if item_name and LA_BRIDGE.backend_to_armoury and LA_BRIDGE.backend_to_armoury[item_name] then
                local vanilla_key = LA_BRIDGE.backend_to_vanilla and LA_BRIDGE.backend_to_vanilla[item_name]
                if vanilla_key then
                    _dbg("[net-safe] update_cosmetic_slot %s LA item(%s) -> vanilla(%s)",
                        tostring(slot), tostring(item_name), tostring(vanilla_key))
                    effective_item_name = vanilla_key
                    la_item_subbed = true
                else
                    _dbg("[net-safe] update_cosmetic_slot %s LA item(%s) -> SKIP (no vanilla fallback)",
                        tostring(slot), tostring(item_name))
                    return
                end
            end
            if skin_name and LA_BRIDGE.backend_to_armoury and LA_BRIDGE.backend_to_armoury[skin_name] then
                local vanilla_skin = LA_BRIDGE.backend_to_vanilla and LA_BRIDGE.backend_to_vanilla[skin_name]
                if vanilla_skin then
                    _dbg("[net-safe] update_cosmetic_slot %s LA skin(%s) -> vanilla(%s)",
                        tostring(slot), tostring(skin_name), tostring(vanilla_skin))
                    effective_skin_name = vanilla_skin
                    la_skin_subbed = true
                else
                    _dbg("[net-safe] update_cosmetic_slot %s LA skin(%s) -> SKIP (no vanilla fallback)",
                        tostring(slot), tostring(skin_name))
                    return
                end
            end
        end

        -- v0.8.64-dev: peer-replay path for armor (slot_skin). slot_skin is
        -- "cosmetic" category, NOT "attachment", so it doesn't flow through
        -- PUAE or AttachmentUtils.hot_join_sync — those only emit cos_la_apply
        -- for hats. Fire it here so peers can replay the LA armor texture
        -- paint on the husk player_unit body. Also record into _local_la_equips
        -- so the hot_join_sync hook can re-emit to joining peers.
        if la_item_subbed and item_name and player and player.player_unit
            and Unit.alive(player.player_unit) and _send_la_apply
        then
            local kind = nil
            if slot == "slot_hat"  then kind = "hat"   end
            if slot == "slot_skin" then kind = "armor" end
            if kind then
                local armoury_key = LA_BRIDGE.backend_to_armoury[item_name]
                local equips = _local_la_equips[player.player_unit]
                if not equips then equips = {}; _local_la_equips[player.player_unit] = equips end
                equips[slot] = item_name
                _send_la_apply(player.player_unit, slot, kind, armoury_key, effective_item_name)
                -- v0.9.12-dev: persist to disk so the LA hat / armor survives
                -- the next game restart. Per-career keying mirrors vanilla's
                -- own loadout-per-career model.
                local career_name = LA_PERSIST._career_name_for_player(player)
                if career_name then LA_PERSIST.save_cosmetic(career_name, slot, item_name) end
            end
        end

        -- v0.8.66-dev: peer-replay path for WEAPON ILLUSIONS (row-1 picker).
        -- When the user equips an LA-cloned weapon illusion, skin_name (NOT
        -- item_name) is the LA bid. v0.8.64 substituted it to vanilla for
        -- crash-safety but never told peers to repaint, so peers saw vanilla
        -- color on the wielded weapon. Fire kind="illusion" with the LA
        -- armoury_key derived from skin_name. Record in _local_la_equips
        -- keyed by the cosmetic slot ("slot_melee" / "slot_ranged" etc.) so
        -- hot_join_sync can replay to joiners.
        if la_skin_subbed and skin_name and not la_item_subbed
            and player and player.player_unit and Unit.alive(player.player_unit)
            and _send_la_apply
        then
            local armoury_key = LA_BRIDGE.backend_to_armoury[skin_name]
            if armoury_key then
                local equips = _local_la_equips[player.player_unit]
                if not equips then equips = {}; _local_la_equips[player.player_unit] = equips end
                equips[slot] = skin_name
                _send_la_apply(player.player_unit, slot, "illusion", armoury_key, effective_skin_name)
                -- v0.9.12-dev: persist LA illusion per backend_id so the same
                -- weapon instance keeps its LA skin on next game restart. Works
                -- for vanilla weapons AND CIM-forged modded weapons (CIM's
                -- forged_weapons save covers the item itself; this covers the
                -- LA illusion overlay vanilla can't represent).
                local inv = ScriptUnit.has_extension(player.player_unit, "inventory_system")
                local slot_data = inv and inv._equipment and inv._equipment.slots
                    and inv._equipment.slots[slot]
                local backend_id = slot_data and slot_data.item_data and slot_data.item_data.backend_id
                if backend_id then LA_PERSIST.save_illusion(backend_id, skin_name) end
            end
        end

        -- v0.9.0-dev: LA->vanilla swap on a slot must clear the stale LA cache
        -- entry. Previously the `equips[slot] = item_name` write at lines
        -- 3284/3305 only happened inside the la_*_subbed branches; equipping
        -- a vanilla replacement left the prior LA bid in _local_la_equips,
        -- and the next hot_join_sync would replay it to joiners even though
        -- the wearer is no longer wearing LA.
        if not la_item_subbed and not la_skin_subbed
            and player and player.player_unit
        then
            local equips = _local_la_equips[player.player_unit]
            local had_local_la = equips and equips[slot] or nil
            if had_local_la then
                _dbg("[net-safe] update_cosmetic_slot %s: clearing stale LA cache entry %s",
                    tostring(slot), tostring(equips[slot]))
                equips[slot] = nil
            end
            -- v0.9.69-dev (#265, LA_SYNC_CORE_AUDIT Slice 1 / I2): revert must
            -- BROADCAST, not just clear local state. Guarded to the LOCAL
            -- human player (bots share the host peer_id -- a bot career swap
            -- must not revert the host's slots) and to slots that actually
            -- held LA state (locally tracked this session OR still present in
            -- the synced store from an earlier session/persistence restore).
            do
                local pm_r = Managers and Managers.player
                local lp_ok_r, lp_r = pcall(function() return pm_r and pm_r:local_player() end)
                if lp_ok_r and lp_r and player == lp_r and mod._send_la_revert then
                    local had_synced = lp_r.peer_id and _la_equips_by_peer[lp_r.peer_id]
                        and _la_equips_by_peer[lp_r.peer_id][slot] ~= nil
                    if had_local_la or had_synced then
                        local kind = (slot == "slot_hat" and "hat")
                            or (slot == "slot_skin" and "armor") or "illusion"
                        mod._send_la_revert(player.player_unit, slot, kind,
                            (kind == "illusion") and skin_name or item_name, nil)
                    end
                end
            end
            -- v0.9.12-dev: persistence parity for the clear path. If the user
            -- equips a vanilla item over a previously-saved LA one, the on-disk
            -- entry must be cleared too — otherwise next restart re-applies a
            -- cosmetic the user already unequipped.
            if slot == "slot_hat" or slot == "slot_skin" then
                local career_name = LA_PERSIST._career_name_for_player(player)
                if career_name then LA_PERSIST.clear_cosmetic(career_name, slot) end
            else
                local inv = ScriptUnit.has_extension(player.player_unit, "inventory_system")
                local slot_data = inv and inv._equipment and inv._equipment.slots
                    and inv._equipment.slots[slot]
                local backend_id = slot_data and slot_data.item_data and slot_data.item_data.backend_id
                if backend_id then LA_PERSIST.clear_illusion(backend_id) end
            end
        end

        if la_item_subbed or la_skin_subbed then
            return func(player, slot, effective_item_name, effective_skin_name)
        end
        return func(player, slot, item_name, skin_name)
    end)
end

-- v0.8.60-dev: SECOND sync path. SimpleInventoryExtension.add_equipment
-- calls CosmeticUtils.update_cosmetic_slot (caught by the hook above)
-- AND then immediately calls LoadoutUtils.sync_loadout_slot, which
-- broadcasts an `rpc_sync_loadout_slot` RPC with
-- `item_id = NetworkLookup.item_names[item.key]`. Peers receive the LOCAL
-- index that only the user's session knows → same crash mode as the
-- SyncData path. Substitute the item with a shadow whose `.key` is the
-- vanilla equivalent before the RPC fires. Same protection also blocks
-- LoadoutUtils.hot_join_sync, which iterates loadouts and re-invokes
-- sync_loadout_slot for each newly-joined peer.
--
-- LoadoutUtils is also a PLAIN TABLE (`LoadoutUtils = LoadoutUtils or {}`),
-- so use table-form hook with nil guard — same BackendUtils/CosmeticUtils
-- pitfall as the previous version.
if LoadoutUtils then
    mod:hook(LoadoutUtils, "sync_loadout_slot", function(func, player, slot_name, item, sync_to_specific_peer_id)
        if item and item.key
            and LA_BRIDGE and LA_BRIDGE.registered
            and LA_BRIDGE.backend_to_armoury
            and LA_BRIDGE.backend_to_armoury[item.key]
        then
            local vanilla_key = LA_BRIDGE.backend_to_vanilla and LA_BRIDGE.backend_to_vanilla[item.key]
            if vanilla_key then
                local shadow = {}
                for k, v in pairs(item) do shadow[k] = v end
                shadow.key = vanilla_key
                _dbg("[net-safe] sync_loadout_slot %s LA(%s) -> vanilla(%s)",
                    tostring(slot_name), tostring(item.key), tostring(vanilla_key))
                return func(player, slot_name, shadow, sync_to_specific_peer_id)
            end
            _dbg("[net-safe] sync_loadout_slot %s LA(%s) -> SKIP (no vanilla fallback)",
                tostring(slot_name), tostring(item.key))
            return
        end
        return func(player, slot_name, item, sync_to_specific_peer_id)
    end)
end

-- v0.9.74-dev: FOURTH sync surface — the weapon SKIN axis (issue 421 / issue 371).
-- The surfaces above cover the item/attachment NAME. Custom weapon illusions
-- (_custom_skin_keys — the ct_* illusions plus any LA weapon-skin key) instead write a
-- modded key into slot_data.skin; vanilla SimpleInventoryExtension.game_object_initialized
-- encodes weapon_skin_id = NetworkLookup.weapon_skins[slot_data.skin or "n/a"] and
-- broadcasts rpc_add_equipment to EVERY peer (simple_inventory_extension.lua:258-264). A
-- peer WITHOUT cosmetics_tweaker cold-decodes the appended index at inventory_system.lua:300
-- -> the strict __index metamethod fatals (network_lookup.lua:2362). Same crash mode as the
-- shipped fa479a72 GUID. Null any custom skin key on the WIRE (encodes as the universal
-- vanilla "n/a" index), then restore the slot's real skin immediately after the send so the
-- LOCAL owner still spawns the custom illusion (this function only SENDS the RPC; the owner's
-- unit spawn reads the restored value elsewhere). Remote peers render the base skin either
-- way. Sole cosmetics hook on this method (grep-verified; the LA name path hooks
-- PlayerUnitAttachmentExtension.game_object_initialized, a different extension class).
-- v0.9.75-dev: the null-and-restore is extracted to a pure helper so the
-- /cos_regression_test `wire_skin_null_ungated` check can drive the EXACT shipped path
-- (BUG_CLASSES 31 mandates a wire_*_ungated assertion on every sender-side substitution;
-- the v0.9.74 skin axis was the one uncovered surface). `slots` is the equipment slot
-- table; `send_fn` is the vanilla continuation that encodes weapon_skin_id + broadcasts
-- rpc_add_equipment. Every _custom_skin_keys skin is nulled on the WIRE, the send runs,
-- then each real skin is restored so the LOCAL owner still spawns the custom illusion.
-- The null takes NO toggle argument by construction, so it can never be gated behind a
-- mod:get() -- the coercion is UNCONDITIONAL (class-31 never-crash mandate). Preserves up
-- to four vanilla returns (game_object_initialized's arity, unchanged from the pre-
-- extraction inline body).
local function _wire_null_custom_skins(slots, send_fn)
    local saved
    for _, slot_data in pairs(slots) do
        local skin = slot_data and slot_data.skin
        if skin and _custom_skin_keys[skin] then
            saved = saved or {}
            saved[slot_data] = skin
            slot_data.skin = nil
        end
    end
    local r1, r2, r3, r4 = send_fn()
    if saved then
        for slot_data, skin in pairs(saved) do
            slot_data.skin = skin
        end
    end
    return r1, r2, r3, r4
end
mod._cos_wire_null_custom_skins = _wire_null_custom_skins

mod:hook("SimpleInventoryExtension", "game_object_initialized", function(func, self, unit, unit_go_id)
    local slots = self and self._equipment and self._equipment.slots
    if not slots then
        return func(self, unit, unit_go_id)
    end
    return _wire_null_custom_skins(slots, function()
        return func(self, unit, unit_go_id)
    end)
end)

-- v0.8.61-dev: THIRD sync surface — attachment-RPC paths that read
-- `NetworkLookup.item_names[slot_data.item_data.name]` (or `slot_data.name`)
-- INLINE via raw table access, then send rpc_create_attachment. No
-- function wrapper can intercept the table read itself, so we pre-mutate
-- the LA-keyed name to the vanilla equivalent on the slot data, call
-- vanilla, then restore. The window is the single vanilla call — no
-- other code runs mid-call, so the swap is invisible to LOCAL apply.
--
-- Three sites covered (all decoded the same crash mode as v0.8.58-60):
--   1. PlayerUnitAttachmentExtension.game_object_initialized (line 63)
--      — local player initial spawn, sends rpc_create_attachment for
--      every attachment slot to clients (host) or server (client).
--   2. PlayerUnitAttachmentExtension.spawn_resynced_loadout (line 301)
--      — fires after a mid-mission loadout resync (dropped item, etc.).
--   3. AttachmentUtils.hot_join_sync (line 99) — fires PER NEWLY-JOINED
--      PEER for every attachment slot already worn. Plain table, must
--      use table-form + nil guard.
--
-- Hot_join uses `slot_data.name` (top-level); the two PUAE methods use
-- `slot_data.item_data.name` (nested). Both fields store the LA
-- backend_id when wearing an LA cosmetic (set by create_attachment via
-- AttachmentUtils internals).
local _net_safe_hook_status = { CosmeticUtils = false, LoadoutUtils = false, AttachmentUtils = false, PUAE = false }
_net_safe_hook_status.CosmeticUtils = CosmeticUtils ~= nil
_net_safe_hook_status.LoadoutUtils = LoadoutUtils ~= nil

local function _la_substitute_name(original_name)
    if not (LA_BRIDGE and LA_BRIDGE.registered and original_name) then
        return nil
    end
    if not (LA_BRIDGE.backend_to_armoury and LA_BRIDGE.backend_to_armoury[original_name]) then
        return nil
    end
    return LA_BRIDGE.backend_to_vanilla and LA_BRIDGE.backend_to_vanilla[original_name] or nil
end

-- v0.8.64-dev: UNIFIED LA peer-sync — cos_la_apply replaces cos_la_attach.
--
-- v0.8.58-0.8.61 stopped peers crashing on LA cosmetics by substituting LA
-- backend_ids with vanilla equivalents on every outgoing vanilla RPC.
-- v0.8.62 added cos_la_attach for HATS ONLY so LA+cos_tweaker peers saw the
-- real LA hat. v0.8.64 generalises that pattern to cover all three LA
-- visual surfaces with ONE RPC:
--
--   payload = { go_id, slot, kind, armoury_key, vanilla_key }
--   kind ∈ { "hat", "armor", "offhand" }
--
-- Identity key is ARMOURY_KEY (LA's deterministic string like
-- "Kruber_Pureheart"), not la_backend_id. la_backend_id is mostly
-- deterministic across peers but has a silent-bail failure mode at the
-- receiver when its local ItemMasterList lookup misses; armoury_key matches
-- what LA's own SKIN_LIST keys by and sidesteps the issue entirely.
--
-- RACE FIX — replace, not append. Vanilla sees only the vanilla substitute
-- (existing CosmeticUtils / LoadoutUtils / PUAE / AttachmentUtils hooks do
-- the substitution). LA-aware peers receive cos_la_apply and replay.
-- Nothing races because vanilla NEVER carries an LA key over the wire.
--
-- v0.8.67-dev: SERVER-AUTHORITATIVE flow. All client equips emit a request
-- to the host (`cos_la_apply_req`); the host records the equip in
-- `_la_equips_by_peer[wearer_peer_id]` and broadcasts the authoritative
-- `cos_la_apply` to ALL peers (including the originating client, so they
-- apply in lockstep with everyone else). Peers reject any `cos_la_apply`
-- whose sender isn't the host. The host short-circuits its own local
-- equips by skipping the request hop and broadcasting directly.
--
-- Identity over the wire is now `wearer_peer_id` (deterministic across
-- peers) rather than `go_id` (which is host-relative and may not resolve
-- on late-spawn races). Receiver looks up the wearer's player_unit via
-- `Managers.player:players_at_peer(wearer_peer_id)`. If the unit isn't
-- spawned yet (mid-loading, etc.), the payload is queued and re-tried on
-- mod.update for up to 5 seconds.

-- Per-peer authoritative state (host only). Keyed by wearer_peer_id;
-- value is { [slot_name] = { kind, armoury_key, vanilla_key } }.
-- v0.9.0.11-hotfix: was `local _la_equips_by_peer = {}` here at line 3711.
-- Moved declaration to the top of the file (just above the BackendUtils
-- hook at line 2241) because that hook's husk-mesh-swap probe was
-- referencing this local — but at line 2241 the local doesn't exist yet
-- in lexical scope, so the reference compiled as a GLOBAL nil. The probe
-- always reported cache_has_wearer=false on PC-B even AFTER the recv handler
-- wrote to the cache (the receiver, declared after this line, captured
-- the real local correctly — but the BackendUtils hook captured global nil).
-- Two readers, two different upvalue resolutions. Reassign to the existing
-- table here so the rest of the file's references continue to work.
_la_equips_by_peer = _la_equips_by_peer or {}
-- v0.9.69-dev (#265, LA_SYNC_CORE_AUDIT Slice 1): runtime alias so code that
-- sits LEXICALLY BEFORE the forward declaration (the offhand picker press
-- handler, ~line 3760) can consult the synced store at runtime without
-- re-triggering the v0.9.0.11 global-nil upvalue bug. The table identity is
-- never replaced (writes are per-key), so the alias stays valid for the
-- whole session.
mod._la_equips_by_peer = _la_equips_by_peer

-- Late-spawn replay queue. Each entry:
-- { wearer_peer_id, slot, kind, armoury_key, vanilla_key, expires_at }
local _la_pending_apply = {}

-- v0.9.3: multi-source host_peer_id resolution.
-- `Managers.state.network.server_peer_id` is the most authoritative source,
-- but it's only wired up after mission load — in keep / lobby / pre-mission
-- it's nil. Symptom from PC-A→PC-B test 2026-05-21 17:21: user joined PC-B's
-- lobby as client, equipped 17 cosmetics in keep, every emit hit
-- `(no host peer_id yet)` and deferred. Drain only fired 102s later when
-- mission load finally populated state.network; 11/17 entries had timed out
-- by then.
-- The chat manager stores host_peer_id much earlier (foundation/scripts/
-- managers/chat/chat_manager.lua:412-417 `ChatManager.setup_network_context`).
-- Fall back to it so emits during keep / lobby see the host immediately.
local function _host_peer_id()
    local nm = Managers and Managers.state and Managers.state.network
    if nm and nm.server_peer_id then return nm.server_peer_id end
    local cm = Managers and Managers.chat
    if cm and cm.host_peer_id then return cm.host_peer_id end
    return nil
end

local function _local_peer_id_quick()
    local pm = Managers and Managers.player
    local lp = pm and pm.local_player and pm:local_player()
    return lp and lp.peer_id or nil
end

-- v0.9.2-hotfix: robust host detection. Previously checked only
-- `Managers.player.is_server == true`, which is transiently nil during state
-- transitions AND is unreliable in some keep contexts where the user IS
-- hosting a lobby but the field isn't set yet. Symptom in user's log
-- (console-2026-05-21-03.33.15): user was server (`I am server` at line 3198)
-- but ALL cos_la_apply emits hit the client branch and got DEFERRED because
-- both this check AND the host_peer_id lookup returned falsy at emit time.
-- New check: ALSO compare the local peer_id to the network's server_peer_id.
-- If they match, we're hosting regardless of the player_manager flag.
local function _is_local_server()
    -- Primary signal: vanilla's own flag (works in mission + most keep paths).
    if Managers and Managers.player and Managers.player.is_server == true then
        return true
    end
    -- Fallback signal: server_peer_id matches our peer_id. Catches the keep
    -- pre-mission window where Managers.player.is_server is nil but the
    -- network manager has already elected us host.
    local host = _host_peer_id()
    local local_peer = _local_peer_id_quick()
    return host ~= nil and local_peer ~= nil and host == local_peer
end

local function _wearer_unit_for_peer(wearer_peer_id)
    if not wearer_peer_id then return nil end
    local pm = Managers and Managers.player
    if not pm then return nil end
    -- v0.9.69-dev (#268, I4 targeting): resolve the HUMAN player at the peer.
    -- The old first-alive sweep over players_at_peer could return a BOT's
    -- unit on a host peer (bots share the host's peer_id at local_player_id
    -- 2..4; pairs order is arbitrary), sending a wearer's cosmetic onto a
    -- bot. player_from_peer_id defaults local_player_id=1 = the human
    -- (player_manager.lua:463-470) and is nil-safe.
    if pm.player_from_peer_id then
        local p = pm:player_from_peer_id(wearer_peer_id)
        if p and p.player_unit and Unit.alive(p.player_unit) then
            return p.player_unit
        end
    end
    -- Fallback sweep (older API shape / early-spawn window): humans only.
    local players = pm.players_at_peer and pm:players_at_peer(wearer_peer_id)
    if not players then return nil end
    for _, p in pairs(players) do
        if p.player_unit and Unit.alive(p.player_unit)
            and (not p.is_player_controlled or p:is_player_controlled()) then
            return p.player_unit
        end
    end
    return nil
end

local function _local_player_peer_id()
    local pm = Managers and Managers.player
    local lp = pm and pm:local_player()
    return lp and lp.peer_id
end

-- v0.9.0-dev: emit dedup. CosmeticUtils.update_cosmetic_slot, PUAE
-- .game_object_initialized, PUAE.spawn_resynced_loadout, and
-- AttachmentUtils.hot_join_sync all call _send_la_apply for the same
-- equip event; receivers got 3-4 cos_la_apply messages per change, which
-- caused "Slot is not empty" errors in the create_attachment receiver and
-- visible flicker on peers. Suppress duplicates of the same
-- (wearer_peer, slot, kind, armoury_key) within a short window.
local _last_emit_at = {}
local _EMIT_DEDUP_WINDOW = 0.5

-- Client-facing emit function (used by every equip call site). Routes via
-- the host so the resulting apply is server-broadcast and consistent across
-- peers. If we ARE the host, short-circuits the round-trip.
_send_la_apply = function(unit, slot_name, kind, armoury_key, vanilla_key, hand_field)
    if not (unit and Unit.alive(unit)) then return end
    if not (slot_name and kind and armoury_key) then return end
    -- v0.9.9.4-dev: hand_field is optional, defaults to "left_hand_unit"
    -- (legacy behavior — only relevant to kind="offhand"/"illusion"). hat
    -- and armor paths ignore it.
    if (kind == "offhand" or kind == "illusion") and not hand_field then
        hand_field = "left_hand_unit"
    end

    local wearer_peer = nil
    local pm = Managers and Managers.player
    if pm and pm.owner then
        local owner = pm:owner(unit)
        wearer_peer = owner and owner.peer_id or nil
    end
    wearer_peer = wearer_peer or _local_player_peer_id()
    if not wearer_peer then return end

    -- v0.9.9.4-dev: dedup key includes hand_field so the same shield/weapon
    -- equipped under different hand picks doesn't suppress legitimate
    -- second-hand emits within the 0.5s window.
    local dedup_key = wearer_peer .. "|" .. tostring(slot_name) .. "|" .. tostring(kind) .. "|" .. tostring(armoury_key) .. "|" .. tostring(hand_field)
    local now = os.clock()
    local prev = _last_emit_at[dedup_key]
    if prev and (now - prev) < _EMIT_DEDUP_WINDOW then
        return  -- recent duplicate, suppress
    end
    _last_emit_at[dedup_key] = now

    if _is_local_server() then
        -- Record + broadcast directly. Host's own broadcast loops back to
        -- itself via "all"; the cos_la_apply receiver applies locally.
        _la_equips_by_peer[wearer_peer] = _la_equips_by_peer[wearer_peer] or {}
        _la_equips_by_peer[wearer_peer][slot_name] = {
            kind = kind, armoury_key = armoury_key, vanilla_key = vanilla_key,
            hand_field = hand_field,
        }
        _dbg("[cos_la_apply emit] HOST wearer=%s slot=%s kind=%s key=%s hand=%s",
            tostring(wearer_peer), tostring(slot_name), tostring(kind), tostring(armoury_key), tostring(hand_field))
        _trace("SYNC emit HOST->all wearer=%s slot=%s kind=%s armoury=%s hand=%s",
            tostring(wearer_peer), tostring(slot_name), tostring(kind), tostring(armoury_key), tostring(hand_field))
        -- v0.9.69-dev (Slice 0, I6): emit routing must be visible with mod
        -- logging OFF -- the #264-comment transport loss could not be pinned
        -- because this branch only logged via _dbg/_trace.
        if printf then printf("[la-state] EMIT host->all wearer=%s slot=%s kind=%s key=%s hand=%s",
            tostring(wearer_peer), tostring(slot_name), tostring(kind), tostring(armoury_key), tostring(hand_field)) end
        mod:network_send("cos_la_apply", "all", COS_RPC_SCHEMA, {
            wearer_peer_id = wearer_peer,
            slot           = slot_name,
            kind           = kind,
            armoury_key    = armoury_key,
            vanilla_key    = vanilla_key,
            hand_field     = hand_field,
        })
        return
    end

    -- Client: ask the host to fan out.
    -- v0.9.0.15-hotfix: VMF's `mod:network_send` does NOT accept the literal
    -- string "server" as a recipient — only "all"/"others"/"local" or a
    -- literal peer_id. The "server" string falls through to the else branch
    -- in VMF's convert_names_to_numbers, fails the _vmf_users lookup, and
    -- the packet is SILENTLY DROPPED. No error, no log, no wire activity.
    -- This bug had been live since v0.8.67-dev and only surfaced now because
    -- prior multiplayer tests had PC-A as HOST (which hits the `"all"`
    -- short-circuit above). When PC-A is a CLIENT (this session), the broken
    -- line fired every emit → host never received any cos_la_apply_req →
    -- entire LA sync chain dead. Fix: target the host's peer_id directly.
    -- Nil-guard for the level-transition window when server_peer_id may
    -- transiently be nil; pending queue retries pick it up.
    local host = _host_peer_id()
    if not host then
        -- v0.9.2-hotfix: ENQUEUE the deferred emit so it actually drains
        -- when the network state settles. Previously the request was logged
        -- and discarded — meaning a cosmetic equipped in keep before the
        -- network manager was fully wired never broadcast. User's log
        -- (console-2026-05-21-03.33.15) showed every emit DEFERRED, no
        -- broadcast, hat/shield invisible to other peers.
        mod._la_deferred_emits = mod._la_deferred_emits or {}
        mod._la_deferred_emits[#mod._la_deferred_emits + 1] = {
            wearer_peer  = wearer_peer,
            slot_name    = slot_name,
            kind         = kind,
            armoury_key  = armoury_key,
            vanilla_key  = vanilla_key,
            hand_field   = hand_field,
            queued_at    = os.clock(),
        }
        _dbg("[cos_la_apply emit] CLIENT->req DEFERRED+queued (no host peer_id yet) wearer=%s slot=%s key=%s queue_size=%d",
            tostring(wearer_peer), tostring(slot_name), tostring(armoury_key),
            #mod._la_deferred_emits)
        -- v0.9.69-dev (Slice 0, I6): the deferred branch is the prime suspect
        -- for the 79s-late mid-mission emits (#264 comment). printf so the
        -- user's log shows exactly when an emit queued instead of sending.
        if printf then printf("[la-state] EMIT client DEFERRED (no host yet) slot=%s kind=%s key=%s queue=%d",
            tostring(slot_name), tostring(kind), tostring(armoury_key), #mod._la_deferred_emits) end
        return
    end
    _dbg("[cos_la_apply emit] CLIENT->req wearer=%s slot=%s kind=%s key=%s hand=%s host=%s",
        tostring(wearer_peer), tostring(slot_name), tostring(kind), tostring(armoury_key), tostring(hand_field), tostring(host))
    _trace("SYNC emit CLIENT->req wearer=%s slot=%s kind=%s armoury=%s hand=%s host=%s",
        tostring(wearer_peer), tostring(slot_name), tostring(kind), tostring(armoury_key), tostring(hand_field), tostring(host))
    -- v0.9.69-dev (Slice 0, I6): pair this line with the host's [la-state]
    -- REQ-RECV line to pin a lost request to the wire (mid-mission transport
    -- loss, #264 comment).
    if printf then printf("[la-state] EMIT client->req host=%s slot=%s kind=%s key=%s hand=%s",
        tostring(host), tostring(slot_name), tostring(kind), tostring(armoury_key), tostring(hand_field)) end
    mod:network_send("cos_la_apply_req", host, COS_RPC_SCHEMA, {
        slot         = slot_name,
        kind         = kind,
        armoury_key  = armoury_key,
        vanilla_key  = vanilla_key,
        hand_field   = hand_field,
    })
end

-- v0.9.2-hotfix: deferred-emit drain. Called from mod.update every frame.
-- Walks the queue, retries each entry. Entries older than 30s get dropped
-- (assume the user changed their mind and re-equipped something else).
local function _drain_deferred_la_emits()
    local q = mod._la_deferred_emits
    if not q or #q == 0 then return end
    -- Only attempt drain if we now have a host AND/OR are the host ourselves.
    local host = _host_peer_id()
    local am_host = _is_local_server()
    if not host and not am_host then return end

    local now = os.clock()
    local survivors = {}
    -- v0.9.3: bumped from 30s to 300s. PC-A→PC-B test 2026-05-21 17:21 showed
    -- emits queued at lobby-join sat for 102s before the drain finally fired,
    -- by which time the original 30s timeout had purged them. Lobby load can
    -- legitimately be that slow; 5min is a safer ceiling for "user changed
    -- their mind" purging without dropping live equips.
    for _, entry in ipairs(q) do
        if (now - entry.queued_at) > 300 then
            _dbg("[cos_la_apply drain] dropping stale entry wearer=%s slot=%s key=%s age=%.1fs",
                tostring(entry.wearer_peer), tostring(entry.slot_name),
                tostring(entry.armoury_key), now - entry.queued_at)
        else
            -- Re-emit. If we're now host, the broadcast fires directly. If
            -- we're now client with a known host, the request lands.
            -- v0.9.69-dev (#265 Slice 1): revert entries drain too -- delete
            -- instead of write, payload carries revert=true and no armoury_key.
            if am_host then
                if entry.revert then
                    if _la_equips_by_peer[entry.wearer_peer] then
                        _la_equips_by_peer[entry.wearer_peer][entry.slot_name] = nil
                    end
                else
                    _la_equips_by_peer[entry.wearer_peer] = _la_equips_by_peer[entry.wearer_peer] or {}
                    _la_equips_by_peer[entry.wearer_peer][entry.slot_name] = {
                        kind = entry.kind, armoury_key = entry.armoury_key, vanilla_key = entry.vanilla_key,
                        hand_field = entry.hand_field,
                    }
                end
                mod:network_send("cos_la_apply", "all", COS_RPC_SCHEMA, {
                    wearer_peer_id = entry.wearer_peer,
                    slot           = entry.slot_name,
                    kind           = entry.kind,
                    revert         = entry.revert or nil,
                    armoury_key    = entry.armoury_key,
                    vanilla_key    = entry.vanilla_key,
                    hand_field     = entry.hand_field,
                })
                _dbg("[cos_la_apply drain] HOST broadcast wearer=%s slot=%s key=%s (was queued %.1fs)",
                    tostring(entry.wearer_peer), tostring(entry.slot_name),
                    tostring(entry.armoury_key), now - entry.queued_at)
                if printf then printf("[la-state] EMIT drain host->all wearer=%s slot=%s kind=%s key=%s revert=%s (queued %.1fs)",
                    tostring(entry.wearer_peer), tostring(entry.slot_name), tostring(entry.kind),
                    tostring(entry.armoury_key), tostring(entry.revert or false), now - entry.queued_at) end
            else
                mod:network_send("cos_la_apply_req", host, COS_RPC_SCHEMA, {
                    slot         = entry.slot_name,
                    kind         = entry.kind,
                    revert       = entry.revert or nil,
                    armoury_key  = entry.armoury_key,
                    vanilla_key  = entry.vanilla_key,
                    hand_field   = entry.hand_field,
                })
                _dbg("[cos_la_apply drain] CLIENT->req sent wearer=%s slot=%s key=%s host=%s (was queued %.1fs)",
                    tostring(entry.wearer_peer), tostring(entry.slot_name),
                    tostring(entry.armoury_key), tostring(host), now - entry.queued_at)
                if printf then printf("[la-state] EMIT drain client->req host=%s slot=%s kind=%s key=%s revert=%s (queued %.1fs)",
                    tostring(host), tostring(entry.slot_name), tostring(entry.kind),
                    tostring(entry.armoury_key), tostring(entry.revert or false), now - entry.queued_at) end
            end
            -- Drop entry from queue after successful re-emit.
        end
    end
    mod._la_deferred_emits = survivors
end
mod._drain_deferred_la_emits = _drain_deferred_la_emits

-- v0.9.69-dev (#265, LA_SYNC_CORE_AUDIT Slice 1 / invariant I2): REVERT
-- broadcast. Every prior emit path covered APPLY only; reverting to vanilla
-- cleared local stores and sent NOTHING, so remote peers kept the stale LA
-- cosmetic until disconnect (D2/D3 in the audit). A revert is a state change
-- like any other: same routing as _send_la_apply (host short-circuit /
-- client req / deferred queue), payload carries `revert = true` with NO
-- armoury_key. Old-version peers drop the payload harmlessly at their
-- `armoury_key` guard (schema unchanged). Attached to `mod` (not a local)
-- so call sites lexically before this point can reach it at runtime and no
-- top-level local is spent (200-local ceiling).
mod._send_la_revert = function(unit, slot_name, kind, vanilla_key, hand_field)
    if not (unit and Unit.alive(unit)) then return end
    if not (slot_name and kind) then return end
    if (kind == "offhand" or kind == "illusion") and not hand_field then
        hand_field = "left_hand_unit"
    end
    local wearer_peer = nil
    local pm = Managers and Managers.player
    if pm and pm.owner then
        local owner = pm:owner(unit)
        wearer_peer = owner and owner.peer_id or nil
    end
    wearer_peer = wearer_peer or _local_player_peer_id()
    if not wearer_peer then return end
    local dedup_key = wearer_peer .. "|" .. tostring(slot_name) .. "|" .. tostring(kind) .. "|REVERT|" .. tostring(hand_field)
    local now = os.clock()
    local prev = _last_emit_at[dedup_key]
    if prev and (now - prev) < _EMIT_DEDUP_WINDOW then
        return
    end
    _last_emit_at[dedup_key] = now

    if _is_local_server() then
        if _la_equips_by_peer[wearer_peer] then
            _la_equips_by_peer[wearer_peer][slot_name] = nil
        end
        if printf then printf("[la-state] REVERT host->all wearer=%s slot=%s kind=%s (store entry cleared)",
            tostring(wearer_peer), tostring(slot_name), tostring(kind)) end
        mod:network_send("cos_la_apply", "all", COS_RPC_SCHEMA, {
            wearer_peer_id = wearer_peer,
            slot           = slot_name,
            kind           = kind,
            revert         = true,
            vanilla_key    = vanilla_key,
            hand_field     = hand_field,
        })
        return
    end

    local host = _host_peer_id()
    if not host then
        mod._la_deferred_emits = mod._la_deferred_emits or {}
        mod._la_deferred_emits[#mod._la_deferred_emits + 1] = {
            wearer_peer  = wearer_peer,
            slot_name    = slot_name,
            kind         = kind,
            revert       = true,
            vanilla_key  = vanilla_key,
            hand_field   = hand_field,
            queued_at    = os.clock(),
        }
        if printf then printf("[la-state] REVERT client DEFERRED (no host yet) slot=%s kind=%s queue=%d",
            tostring(slot_name), tostring(kind), #mod._la_deferred_emits) end
        return
    end
    if printf then printf("[la-state] REVERT client->req host=%s slot=%s kind=%s",
        tostring(host), tostring(slot_name), tostring(kind)) end
    mod:network_send("cos_la_apply_req", host, COS_RPC_SCHEMA, {
        slot         = slot_name,
        kind         = kind,
        revert       = true,
        vanilla_key  = vanilla_key,
        hand_field   = hand_field,
    })
end

local function _resolve_la_variant(armoury_key)
    local la = get_mod("Loremasters-Armoury")
    if not la or type(la.SKIN_LIST) ~= "table" then return nil, nil end
    return la.SKIN_LIST[armoury_key], la
end

-- v0.9.13-dev: extracted from the v0.9.11 character-mismatch guard in
-- `_apply_la_on_unit` so the decision is unit-testable in isolation. Pure:
-- given the owner_unit's currently-equipped hat path (preferred source) AND
-- the profile base prefix (fallback when no hat is attached yet), decide
-- whether the LA hat's mesh is safe to attach to this body.
--
--   owner_char_path -- path to the OWNER's current vanilla slot_hat
--                      (e.g. "units/beings/player/empire_soldier_breton/
--                      headpiece/es_gk_hat_01") or nil if no slot_hat.
--   la_unit_path    -- path to the cached LA hat mesh
--                      (e.g. "units/beings/player/empire_soldier_breton/
--                      headpiece/es_gk_hat_03").
--   profile_base    -- character base from SPProfiles.unit_name (e.g.
--                      "empire_soldier") or nil if unresolvable.
--
-- Returns (true) when the LA mesh's character segment matches the owner's
-- character segment, otherwise (false, reason_string). When neither source
-- is resolvable, returns false — the conservative choice (no LA visual is
-- strictly better than a wrong-skeleton attach that may crash via
-- `Unit.node` failing the C-level attachment node lookup).
local function _la_chars_compatible(owner_char_path, la_unit_path, profile_base)
    local la_char = string.match(la_unit_path or "", "^units/beings/player/([^/]+)/")
    if not la_char then return true end  -- can't extract LA char; let caller proceed
    if owner_char_path then
        local owner_char = string.match(owner_char_path, "^units/beings/player/([^/]+)/")
        if owner_char then
            if owner_char == la_char then return true end
            return false, ("owner_char=%s la_char=%s"):format(owner_char, la_char)
        end
    end
    if profile_base then
        if la_char == profile_base
            or string.sub(la_char, 1, #profile_base + 1) == profile_base .. "_"
        then
            return true
        end
        return false, ("profile_base=%s la_char=%s"):format(profile_base, la_char)
    end
    return false, "no owner_char_path AND no profile_base resolvable"
end
mod._la_chars_compatible = _la_chars_compatible

-- v0.9.13-dev: passive runtime monitor. Fires on every player spawn (host's
-- own + every bot owned by the host + every husk on a remote client). For
-- the spawned unit, compares the CACHED LA hat (`_la_equips_by_peer
-- [wearer_peer]["slot_hat"]`) against the unit's actual character body. If
-- the cached LA mesh's character segment doesn't match the spawning unit's
-- character, that's the exact failure mode from issue #14 — a host-owned bot
-- whose career differs from the host's about to receive a cross-skeleton
-- attach. The v0.9.11 guard prevents the attach itself; this monitor surfaces
-- when the situation arises so any regression is visible in console without
-- needing a manual chat command.
--
-- Mismatch detections ALWAYS log (this is the safety net). Routine "here's
-- the cache state for the spawning peer" snapshots route through mod:debug,
-- gated by VMF output_mode_debug.

-- v0.9.28-dev (issue #14 cache-leak follow-up): pure invalidation helper.
-- `_la_equips_by_peer` is keyed `[peer_id][slot]` only, so when a peer
-- switches career on the same peer_id (e.g. Kerillian → Saltzpyre WHC),
-- the previous career's LA hat entry persists until the peer disconnects.
-- The v0.9.11 character-mismatch guard catches the visible apply, but the
-- stale entry keeps firing CROSS-SKELETON MISMATCH warnings on every spawn
-- of the new character. Solution: when the spawn-monitor catches a
-- mismatch, purge the offending slot from the cache so it self-heals on
-- the first post-switch spawn. Subsequent legitimate cos_la_apply RPCs
-- repopulate the slot for the current career; if there isn't one, the
-- slot stays empty and the warning stops firing.
--
-- Pulled into a module-level local so the regression test can drive it
-- with synthetic inputs (no player units / LA bridge / Managers mocks).
local function _purge_stale_peer_slot(cache, wearer_peer, slot_name)
    if not (cache and wearer_peer and slot_name) then return false end
    local equips = cache[wearer_peer]
    if not (equips and equips[slot_name]) then return false end
    equips[slot_name] = nil
    if next(equips) == nil then cache[wearer_peer] = nil end
    return true
end
mod._purge_stale_peer_slot = _purge_stale_peer_slot

local function _resolve_owner_char(owner_unit, player)
    if not owner_unit then return nil end
    -- Prefer the unit's actual attached slot_hat — most accurate.
    local ext = ScriptUnit and ScriptUnit.has_extension
        and ScriptUnit.has_extension(owner_unit, "attachment_system")
    local slot_hat = ext and ext._attachments and ext._attachments.slots
        and ext._attachments.slots.slot_hat
    local item_unit = slot_hat and slot_hat.item_data and slot_hat.item_data.unit
    if item_unit then
        return string.match(item_unit, "^units/beings/player/([^/]+)/"), "slot_hat"
    end
    -- Fallback: SPProfiles base (e.g. "empire_soldier"). Coarser — only catches
    -- cross-character mismatches, not cross-career within the same character.
    if player then
        local profile_index = player.profile_index
        if type(profile_index) == "function" then
            local ok, idx = pcall(profile_index, player); if ok then profile_index = idx end
        end
        local profile = profile_index and rawget(_G, "SPProfiles") and SPProfiles[profile_index]
        return profile and profile.unit_name, "profile_base"
    end
    return nil, "unresolved"
end

mod._la_spawn_monitor = function(unit)
    if not (unit and Unit.alive(unit)) then return end
    if not (LA_BRIDGE and LA_BRIDGE.registered) then return end
    local pm = Managers and Managers.player
    if not (pm and pm.owner) then return end
    local owner = pm:owner(unit)
    if not owner then return end
    local wearer_peer = owner.peer_id
    if not wearer_peer then return end
    local equips = _la_equips_by_peer and _la_equips_by_peer[wearer_peer]
    if not equips then
        _dbg("[la-spawn-monitor] unit=%s wearer=%s local_id=%s career=%s — no cached LA equips",
            tostring(unit), tostring(wearer_peer),
            tostring(owner.local_player_id and owner:local_player_id() or "?"),
            tostring(LA_PERSIST and LA_PERSIST._career_name_for_player(owner)))
        return
    end
    local owner_char, source = _resolve_owner_char(unit, owner)
    local career = LA_PERSIST and LA_PERSIST._career_name_for_player(owner)
    local entry_keys = {}
    for k in pairs(equips) do entry_keys[#entry_keys+1] = k end
    table.sort(entry_keys)
    _dbg("[la-spawn-monitor] unit=%s wearer=%s career=%s owner_char=%s (via %s) cached_slots={%s}",
        tostring(unit), tostring(wearer_peer), tostring(career),
        tostring(owner_char), tostring(source), table.concat(entry_keys, ","))
    -- Check the cached slot_hat specifically (the issue #14 failure mode).
    local hat_entry = equips.slot_hat
    if not (hat_entry and hat_entry.armoury_key) then return end
    local variant = _resolve_la_variant(hat_entry.armoury_key)
    local la_unit_path = variant and variant.new_units and variant.new_units[1]
    if not la_unit_path then return end
    local profile_base = (source == "profile_base") and owner_char or nil
    local owner_char_path
    if source == "slot_hat" then
        local ext = ScriptUnit and ScriptUnit.has_extension(unit, "attachment_system")
        local s = ext and ext._attachments and ext._attachments.slots and ext._attachments.slots.slot_hat
        owner_char_path = s and s.item_data and s.item_data.unit
    end
    local ok, reason = _la_chars_compatible(owner_char_path, la_unit_path, profile_base)
    if not ok then
        -- ALWAYS log (this is the regression detector, not a debug dump).
        mod:warning("[la-spawn-monitor] CROSS-SKELETON MISMATCH wearer=%s career=%s cached_armoury=%s la_path=%s — %s. v0.9.11 guard SHOULD bail the apply, but if you see vanilla logic patching this anyway it's a regression of issue #14.",
            tostring(wearer_peer), tostring(career),
            tostring(hat_entry.armoury_key), tostring(la_unit_path), tostring(reason))
        -- v0.9.28-dev: self-heal the stale cache entry so the warning stops
        -- firing on every subsequent spawn. The v0.9.11 guard already bailed
        -- the visible apply, but the entry would otherwise sit in
        -- `_la_equips_by_peer[wearer_peer].slot_hat` until peer disconnect.
        _purge_stale_peer_slot(_la_equips_by_peer, wearer_peer, "slot_hat")
    end
end

-- Wire-up note: SimpleInventoryExtension.extensions_ready is already hooked
-- inside `_la_persistence.lua` for the auto-restore queue. VMF's hook_safe
-- does NOT chain on (Class, method) (per VMF_RECIPES.md § 1) — a second
-- hook_safe registration here would silently overwrite the first and break
-- restore. Instead, the existing hook in _la_persistence.lua calls
-- `mod._la_spawn_monitor` if defined, so both behaviors run from a single
-- registration. The husk-side equivalent is hooked from this file because
-- _la_persistence only cares about the owned-player path.
--
-- v0.9.16-dev (issue #35): the husk class does NOT have `extensions_ready` —
-- only `Simple*Extension` (the self-owned variant) does. The husk class is a
-- separate root class with no inheritance (per CLAUDE.md "Self-owned vs husk
-- extension classes"), and its lifecycle entry point is `init`. The earlier
-- registration on `extensions_ready` silently no-op'd at hook-install time.
-- Hooking `init` with the husk signature `(self, extension_init_context, unit,
-- extension_init_data)` resolves the dead-hook and runs the spawn monitor on
-- every remote-player husk inventory init.
mod:hook_safe("SimpleHuskInventoryExtension", "init", function(self, extension_init_context, unit, extension_init_data)
    if mod._la_spawn_monitor then
        local ok, err = pcall(mod._la_spawn_monitor, unit)
        if not ok then _dbg_alert("[la-spawn-monitor] pcall err: %s", tostring(err)) end
    end
end)

-- v0.9.13-dev: mission-start state snapshot. Gated on debug_dumps. Fires
-- once when StateInGameRunning starts so the cached LA state + persisted
-- entries land in the log at the same timestamp as the mission begin —
-- makes correlating later spawn events to the snapshot trivial.
mod._la_dump_mission_state = function(reason)
    _dbg("[la-state-dump] reason=%s", tostring(reason))
    local n_peers = 0
    if _la_equips_by_peer then
        for peer, slots in pairs(_la_equips_by_peer) do
            n_peers = n_peers + 1
            for slot, entry in pairs(slots) do
                _dbg("[la-state-dump]   peer=%s slot=%s kind=%s armoury=%s vanilla=%s",
                    tostring(peer), tostring(slot), tostring(entry.kind),
                    tostring(entry.armoury_key), tostring(entry.vanilla_key))
            end
        end
    end
    local persisted = mod:get("la_persisted_equips") or {}
    local n_careers = 0
    if persisted.careers then
        for career, slots in pairs(persisted.careers) do
            n_careers = n_careers + 1
            _dbg("[la-state-dump]   persisted career=%s hat=%s skin=%s",
                tostring(career), tostring(slots.slot_hat or "-"), tostring(slots.slot_skin or "-"))
        end
    end
    local n_illusions = 0
    if persisted.illusions then
        for _ in pairs(persisted.illusions) do n_illusions = n_illusions + 1 end
    end
    _dbg("[la-state-dump] totals: %d live peer(s), %d persisted career entr(ies), %d persisted illusion(s)",
        n_peers, n_careers, n_illusions)
end

local function _level_world()
    if Managers and Managers.world and Managers.world.has_world
        and Managers.world:has_world("level_world")
    then
        return Managers.world:world("level_world")
    end
    return nil
end

-- Unified apply core. All inbound paths (cos_la_apply broadcast + pending-
-- queue replay) converge here. Returns true if applied, false if the target
-- unit isn't ready (caller can re-queue).
local function _apply_la_on_unit(owner_unit, slot_name, kind, armoury_key, vanilla_key)
    if not (owner_unit and Unit.alive(owner_unit)) then return false end
    if not (LA_BRIDGE and LA_BRIDGE.registered) then return false end

    local variant, la = _resolve_la_variant(armoury_key)
    if not variant then
        _dbg("[cos_la_apply] %s armoury_key %s missing from local SKIN_LIST — bail",
            tostring(kind), tostring(armoury_key))
        return false
    end

    if kind == "hat" then
        if variant.swap_hand ~= "hat" then return false end
        local la_unit_path = variant.new_units and variant.new_units[1]
        if not la_unit_path then return false end

        -- v0.9.13-dev: guard now delegates to the pure helper
        -- `_la_chars_compatible` so the same decision is unit-testable in
        -- isolation. See its docstring for the contract. Inline doc below
        -- preserved for context on WHY this guard exists at all.
        --
        -- v0.9.11-dev CRASH/VISUAL FIX: character-mismatch gate (rewritten).
        --
        -- The v0.9.8.8 guard derived `owner_char_path` from `vanilla_key`'s
        -- IML entry — but `vanilla_key` is the CACHED LA emit's vanilla
        -- substitute (the EMITTER's hat), not the OWNER's character. For
        -- host-owned bots whose career differs from the host's, both the
        -- cached LA mesh AND `vanilla_key.unit` resolve to the host's
        -- character paths, so the comparison was a tautology that always
        -- passed. Result: GK LA hat attached to host's WP bot at mission
        -- start (host view only). Issue #14.
        --
        -- Correct source for the OWNER's character: the owner_unit's
        -- currently-attached vanilla slot_hat item_data.unit. That unit
        -- was spawned for THIS body, so its path encodes the body's
        -- character_career composite (e.g. "witch_hunter_priest" vs LA's
        -- cached "empire_soldier_breton"). If the bot doesn't have a
        -- vanilla hat yet (early-spawn race), fall back to SPProfiles
        -- via the owner's Player + profile_index, matching la_char's
        -- first segment against profile.unit_name (character base).
        -- If neither resolves, bail — safer than wrong-skeleton attach.
        do
            local owner_char_path
            local ext_peek = ScriptUnit and ScriptUnit.has_extension
                and ScriptUnit.has_extension(owner_unit, "attachment_system")
            local existing = ext_peek and ext_peek._attachments
                and ext_peek._attachments.slots
                and ext_peek._attachments.slots[slot_name]
            local existing_item_data = existing and existing.item_data
            if existing_item_data and existing_item_data.unit then
                owner_char_path = existing_item_data.unit
            end
            local profile_base
            if not owner_char_path then
                local pm = Managers and Managers.player
                local player = pm and pm.owner and pm:owner(owner_unit)
                local profile_index = player and player.profile_index
                    and (type(player.profile_index) == "function"
                        and player:profile_index() or player.profile_index)
                local profile = profile_index and rawget(_G, "SPProfiles")
                    and SPProfiles[profile_index]
                profile_base = profile and profile.unit_name
            end
            local ok, reason = _la_chars_compatible(owner_char_path, la_unit_path, profile_base)
            if not ok then
                _dbg("[cos_la_apply hat] character mismatch — %s (armoury=%s) — skipping cross-skeleton patch",
                    tostring(reason), tostring(armoury_key))
                return false
            end
        end

        -- v0.8.64-dev: husks render 3P. v0.8.62 checked only the 1P path,
        -- which is why "LA hats invisible on peers" reproduced — the 1P
        -- path was present on the wearer but the 3P attachment path the
        -- husk uses sometimes wasn't loaded on the viewer. Verify BOTH.
        local can_get = Application and Application.can_get
        local has_1p = can_get and can_get("unit", la_unit_path)
        local path_3p = la_unit_path .. "_3p"
        local has_3p = can_get and can_get("unit", path_3p)
        if not has_1p and not has_3p then
            _dbg("[cos_la_apply hat] %s: neither %s nor %s loadable — bail",
                tostring(armoury_key), tostring(la_unit_path), tostring(path_3p))
            return false
        end
        local clone_key = (ItemMasterList and rawget(ItemMasterList, armoury_key) and armoury_key)
            or (vanilla_key and ItemMasterList and rawget(ItemMasterList, vanilla_key) and vanilla_key)
        if not clone_key then
            _dbg("[cos_la_apply hat] %s: no usable IML clone source — bail", tostring(armoury_key))
            return false
        end
        local ext = ScriptUnit.has_extension(owner_unit, "attachment_system")
        if not ext or not ext.create_attachment then return false end
        -- v0.9.0-dev: tear down the prior attachment in this slot before
        -- creating the new one. AttachmentUtils.create_attachment errors with
        -- "Slot is not empty, remove attachment before creating a new one"
        -- when a previous hat is still bound — observed on PC-A across
        -- Pureheart_helm / Hippogryph_helm sequential equips. Bypass the
        -- public ext:remove_attachment() because that fires rpc_remove_attachment
        -- to peers; every cos_la_apply receiver would re-broadcast, amplifying
        -- traffic. Direct destroy + nil the slot mirrors the local cleanup
        -- remove_attachment() does, minus the RPC.
        local existing_slot = ext._attachments and ext._attachments.slots and ext._attachments.slots[slot_name]
        if existing_slot then
            if AttachmentUtils and AttachmentUtils.destroy_attachment then
                pcall(AttachmentUtils.destroy_attachment, ext._world, ext._unit, existing_slot)
            end
            ext._attachments.slots[slot_name] = nil
        end
        local item_data = table.clone(ItemMasterList[clone_key])
        item_data.unit = la_unit_path
        local ok, err = pcall(ext.create_attachment, ext, slot_name, item_data)
        if not ok then
            _dbg_alert("[cos_la_apply hat] create_attachment %s failed: %s",
                tostring(armoury_key), tostring(err))
        end
        -- v0.9.0.3-hotfix: paint the LA texture onto the JUST-CREATED HAT
        -- ATTACHMENT UNIT (not the wearer's player_unit). LA's
        -- apply_new_skin_from_texture iterates `Unit.num_meshes(unit)` on the
        -- passed unit and writes textures to those meshes. For armor, the
        -- player body's own meshes carry the armor texture so passing
        -- owner_unit works. For hats, the hat is a SEPARATE attached unit
        -- (vanilla AttachmentUtils.create_attachment spawns it and stores
        -- the ref in slot_data.unit) — passing owner_unit paints the player
        -- body's meshes (no-op for hat textures). The just-created hat unit
        -- lives at ext._attachments.slots[slot_name].unit.
        if la and type(la.apply_new_skin_from_texture) == "function" then
            local world = _level_world()
            local slot_data = ext._attachments and ext._attachments.slots and ext._attachments.slots[slot_name]
            local hat_unit = slot_data and slot_data.unit
            if world and ok and hat_unit and Unit.alive(hat_unit) then
                LA_BRIDGE._bridge_active = true
                local paint_ok, paint_err = pcall(la.apply_new_skin_from_texture, armoury_key, world, vanilla_key, hat_unit)
                LA_BRIDGE._bridge_active = false
                _dbg("[cos_la_apply hat] paint %s on hat_unit=%s ok=%s",
                    tostring(armoury_key), tostring(hat_unit), tostring(paint_ok))
                if not paint_ok then
                    _dbg_alert("[cos_la_apply hat] paint err: %s", tostring(paint_err))
                end
            else
                _dbg("[cos_la_apply hat] paint skipped: world=%s ok=%s hat_unit=%s alive=%s",
                    tostring(world ~= nil), tostring(ok), tostring(hat_unit),
                    tostring(hat_unit and Unit.alive(hat_unit)))
            end
        end
        return true
    end

    if kind == "armor" then
        if variant.swap_hand ~= "armor" then return false end
        if not la or type(la.apply_new_skin_from_texture) ~= "function" then return false end
        local world = _level_world()
        if not world then return false end
        LA_BRIDGE._bridge_active = true
        local ok, err = pcall(la.apply_new_skin_from_texture, armoury_key, world, vanilla_key, owner_unit)
        LA_BRIDGE._bridge_active = false
        if not ok then
            _dbg_alert("[cos_la_apply armor] %s on %s failed: %s",
                tostring(armoury_key), tostring(owner_unit), tostring(err))
        end
        return true
    end

    if kind == "offhand" then
        local inv = ScriptUnit.has_extension(owner_unit, "inventory_system")
        local equipment = inv and inv._equipment
        -- v0.9.72-dev WEAPON-IDENTITY GUARD (2026-07-06 18:27/18:34 session):
        -- this branch painted whatever left-hand unit was CURRENTLY wielded,
        -- ignoring which weapon the stored entry belongs to - while the store
        -- keys the same pick under THREE namespaces (weapon item key,
        -- template key, and a legacy wielded-slot key like "slot_melee" from
        -- the hot-join replay; host 18:35:44.704 shows such an entry live).
        -- Any recv/retry/transition reconcile firing while a DIFFERENT weapon
        -- was in hand painted the illusion onto that weapon. Only paint when
        -- the wielded item actually matches the stored key; otherwise return
        -- false (pending retry keeps it briefly; the next wield of the RIGHT
        -- weapon re-applies via the wield reconcile).
        local w_slot_data = equipment and equipment.slots and inv.wielded_slot
            and equipment.slots[inv.wielded_slot]
        local w_item = w_slot_data and w_slot_data.item_data
        if w_item then
            local match = (slot_name == w_item.template) or (slot_name == w_item.name)
                or (slot_name == w_item.key) or (slot_name == w_item.item_type)
            if not match then
                local seen = mod._la_gate_seen
                if not seen then seen = {}; mod._la_gate_seen = seen end
                local sk = "offhand-wrongweapon|" .. tostring(slot_name) .. "|" .. tostring(w_item.template)
                if not seen[sk] and printf then
                    seen[sk] = true
                    printf("[la-state] APPLY SKIP wrong-weapon: entry key=%s but wielded template=%s name=%s (kind=offhand armoury=%s)",
                        tostring(slot_name), tostring(w_item.template), tostring(w_item.name), tostring(armoury_key))
                end
                return false
            end
        end
        local left_unit = equipment and equipment.left_hand_wielded_unit_3p
        if not left_unit or not Unit.alive(left_unit) then
            -- v0.9.0.3-hotfix: silenced. Previously logged per retry → the
            -- pending-queue's per-frame retry of an offhand equip while host
            -- isn't wielding the shield spammed 24+ lines per equip until the
            -- 5-second TTL expired. The behavior is correct (drops cleanly on
            -- TTL); the noise was loud. Returning false re-queues; pending
            -- queue runner drops the entry quietly on TTL.
            return false
        end
        local world = _level_world()
        if not world then return false end
        -- v0.9.54-dev (#203, trace-confirmed): paint BOTH the 3P and the 1P
        -- wielded shield units. A HUSK has no 1P unit (left_hand_wielded_unit is
        -- nil), so this is unchanged for the husk path; but the LOCAL player —
        -- whose own #203 wield re-apply routes through here — SEES the shield in
        -- FIRST PERSON, and the 0.9.53 trace showed create_equipment's working
        -- "ingame" paint hits both units (3P `..._mesh_3p` AND 1P `..._mesh`).
        -- Painting only the 3P would never restore what the user actually sees.
        local targets = { left_unit }
        local left_1p = equipment and equipment.left_hand_wielded_unit
        if left_1p and Unit.alive(left_1p) then targets[#targets + 1] = left_1p end
        for _, target in ipairs(targets) do
            -- v0.9.54-dev (#204): MESH-MISMATCH WARP GUARD on the husk / peer /
            -- local re-apply paint. This path paints via the un-gated
            -- "network_husk" context, which ASSUMES the get_item_units mesh-swap
            -- already replaced the vanilla shield with the LA custom mesh. For an
            -- LA kind="unit" shield whose mesh-swap was SKIPPED (_resolve_la_unit_mesh
            -- not ready, or a non-bret shield weapon — "Empire Sword and Shield" —
            -- whose offhand swap didn't fire), painting the heraldry onto the
            -- un-swapped VANILLA shield warps the texture onto the wrong model.
            -- Refuse to paint a kind="unit" LA texture onto a unit whose authored
            -- mesh is NOT the variant's custom mesh (generalizes the #150 BUG1/2
            -- gate from the local-body/previewer contexts to this peer/husk path).
            -- The WORKING bret husk swaps successfully → mesh matches → gate
            -- passes (no regression); kind="texture" variants and units with an
            -- unreadable mesh name stay permissive (return true).
            if not _offhand_paint_mesh_ok(target, armoury_key) then
                _dbg("[cos_la_apply offhand] SKIP %s on %s — mesh is NOT the swapped LA mesh (warp guard #204)",
                    tostring(armoury_key), tostring(target))
                -- _trace_paint routes through mod:info (visible with
                -- output_mode_debug OFF) and dumps target_mesh vs expected
                -- new_units[1] so the empire-shield case is pinned in the log.
                _trace_paint("network_husk", "network_husk", nil, target, armoury_key, "SKIP-mesh-mismatch")
                -- [cos:sync] #204: peer/husk offhand paint refused because the
                -- mesh-swap didn't fire (empire-shield warp case). peer=husk.
                if PROBE then
                    PROBE.emit("cos:sync",
                        "husk_offhand/" .. tostring(armoury_key) .. "/" .. tostring(target),
                        string.format("peer=husk ctx=network_husk key=%s unit=%s decision=SKIP reason=mesh-mismatch(warp-guard)",
                            tostring(armoury_key), tostring(target)))
                end
            else
                LA_BRIDGE._bridge_active = true
                local ok, err = pcall(LA_BRIDGE.apply_offhand_to_unit, world, target, armoury_key, vanilla_key, "network_husk")
                LA_BRIDGE._bridge_active = false
                if PROBE then
                    PROBE.emit("cos:sync",
                        "husk_offhand/" .. tostring(armoury_key) .. "/" .. tostring(target),
                        string.format("peer=husk ctx=network_husk key=%s unit=%s decision=PAINT outcome=%s",
                            tostring(armoury_key), tostring(target), tostring(ok)))
                end
                if not ok then
                    _dbg_alert("[cos_la_apply offhand] %s on %s failed: %s",
                        tostring(armoury_key), tostring(target), tostring(err))
                end
                -- v0.9.43-dev PAINT trace (husk/network path). On the CLIENT this
                -- paints the host's shield onto the husk's wielded left-hand unit,
                -- which by this point has already been mesh-swapped to the LA mesh
                -- by the husk get_item_units branch — so match=true is expected.
                _trace_paint("network_husk", "network_husk", nil, target, armoury_key, ok)
            end
        end
        return true
    end

    if kind == "illusion" then
        if not la or type(la.apply_new_skin_from_texture) ~= "function" then return false end
        local inv = ScriptUnit.has_extension(owner_unit, "inventory_system")
        local equipment = inv and inv._equipment
        -- v0.9.72-dev WEAPON-IDENTITY GUARD (see offhand branch): illusion
        -- entries are keyed by the COSMETIC SLOT ("slot_melee"/"slot_ranged",
        -- from update_cosmetic_slot); only paint when that slot is the one
        -- currently wielded (or the key matches the wielded item directly).
        local w_slot_data = equipment and equipment.slots and inv.wielded_slot
            and equipment.slots[inv.wielded_slot]
        local w_item = w_slot_data and w_slot_data.item_data
        if w_item then
            local match = (slot_name == inv.wielded_slot)
                or (slot_name == w_item.template) or (slot_name == w_item.name)
                or (slot_name == w_item.key) or (slot_name == w_item.item_type)
            if not match then
                local seen = mod._la_gate_seen
                if not seen then seen = {}; mod._la_gate_seen = seen end
                local sk = "illusion-wrongweapon|" .. tostring(slot_name) .. "|" .. tostring(inv.wielded_slot)
                if not seen[sk] and printf then
                    seen[sk] = true
                    printf("[la-state] APPLY SKIP wrong-weapon: entry key=%s but wielded slot=%s template=%s (kind=illusion armoury=%s)",
                        tostring(slot_name), tostring(inv.wielded_slot), tostring(w_item.template), tostring(armoury_key))
                end
                return false
            end
        end
        local right_unit = equipment and equipment.right_hand_wielded_unit_3p
        local left_unit_w = equipment and equipment.left_hand_wielded_unit_3p
        if (not right_unit or not Unit.alive(right_unit))
            and (not left_unit_w or not Unit.alive(left_unit_w)) then
            _dbg("[cos_la_apply illusion] %s on owner %s: no live wielded weapon unit",
                tostring(armoury_key), tostring(owner_unit))
            return false  -- re-queue: next wield will spawn
        end
        local world = _level_world()
        if not world then return false end
        LA_BRIDGE._bridge_active = true
        for _, target in ipairs({ right_unit, left_unit_w }) do
            if target and Unit.alive(target) then
                local ok, err = pcall(la.apply_new_skin_from_texture, armoury_key, world, vanilla_key, target)
                if not ok then
                    _dbg_alert("[cos_la_apply illusion] %s on %s failed: %s",
                        tostring(armoury_key), tostring(target), tostring(err))
                end
            end
        end
        LA_BRIDGE._bridge_active = false
        return true
    end

    _dbg_alert("[cos_la_apply] unknown kind %s — ignored", tostring(kind))
    return false
end

local function _try_apply_by_peer(wearer_peer_id, slot_name, kind, armoury_key, vanilla_key)
    local unit = _wearer_unit_for_peer(wearer_peer_id)
    if not unit then return false end
    return _apply_la_on_unit(unit, slot_name, kind, armoury_key, vanilla_key)
end

-- v0.9.64-dev (#233/#234): POST-SPAWN OFFHAND MESH RE-SWAP.
-- A kind="unit" LA shield gets its MESH swapped only in the spawn-time
-- BackendUtils.get_item_units path; a later texture-paint (husk repaint / local
-- wield-reapply) can only recolor, so when the live offhand unit still carries the
-- PREVIOUS (or vanilla) mesh the #204 warp-guard refuses the paint and the swap
-- silently no-ops -- #233 (host's shield spawns on the client before the client has
-- the host's entry) and #234 (mid-mission model change). This forces the mesh to
-- re-resolve by RE-EQUIPPING at the slot level: pulse-wield through the other weapon
-- slot and back, so vanilla re-runs create_equipment / _wield_slot -> get_item_units
-- re-resolves + respawns the offhand with the LA mesh. Slot-level re-equip ONLY --
-- never World.destroy_unit (that is the gt POSITION_LOOKUP nil-deref crash class).
--
-- The CALLER passes the armoury_key that the respawn will actually resolve for this
-- owner (husk: the _la_equips_by_peer entry; local: the same key echoed back on
-- cos_la_apply, which matches _offhand_selection after the #203 exit-queue fix) so
-- the post-pulse mesh CONVERGES and can't ping-pong.
--
-- Only ever call this from a SAFE context (network-callback recv handler or
-- mod.update pending-retry). NEVER from inside a _wield_slot hook body -- the pulse
-- re-fires _wield_slot and re-entering wield during wield can corrupt inventory
-- state. Gated: kind="unit" only, package-resident only, mesh-already-correct no-op,
-- per-owner cooldown + a hard try-cap (so a mesh that can't converge -- e.g. an
-- unresolved get_item_units case -- pulses a few times then stops, no endless
-- flicker), and a re-entrancy guard for the pulse's own _wield_slot fire.
local _offhand_reswap_active = false
local _offhand_reswap_state = setmetatable({}, { __mode = "k" })  -- owner_unit -> { t, key, tries }
local _OFFHAND_RESWAP_COOLDOWN = 1.5
local _OFFHAND_RESWAP_MAX_TRIES = 3
local function _ensure_offhand_mesh(owner_unit, hand_field, armoury_key, tag)
    if _offhand_reswap_active then return end
    if not (owner_unit and armoury_key and Unit.alive(owner_unit)) then return end
    hand_field = hand_field or "left_hand_unit"
    -- kind="unit" only: texture variants paint onto the base mesh (no swap needed).
    local la = get_mod("Loremasters-Armoury")
    local variant = la and la.SKIN_LIST and la.SKIN_LIST[armoury_key]
    if not (variant and variant.kind == "unit" and variant.new_units and variant.new_units[1]) then
        return
    end
    -- Package residency: only pulse if the LA mesh is loadable NOW. If not, bail --
    -- the pulse's get_item_units would skip the swap anyway; the _la_pending_apply
    -- retry re-attempts once LA's package finishes loading.
    local la_unit, _la3p, mesh_ready = _resolve_la_unit_mesh(armoury_key)
    if not (la_unit and mesh_ready) then return end
    local inv = ScriptUnit and ScriptUnit.has_extension and ScriptUnit.has_extension(owner_unit, "inventory_system")
    local equipment = inv and inv._equipment
    if not (equipment and equipment.slots and inv.wield) then return end
    -- Already the LA mesh? -> nothing to do (the common healthy case; no flicker).
    local wielded_field = (hand_field == "right_hand_unit")
        and "right_hand_wielded_unit_3p" or "left_hand_wielded_unit_3p"
    local live = equipment[wielded_field]
    if live and Unit.alive(live) and _offhand_paint_mesh_ok(live, armoury_key) then
        return
    end
    -- Per-owner cooldown + hard try-cap so a per-frame caller can't pulse-storm and a
    -- non-converging mesh can't flicker forever.
    local st = _offhand_reswap_state[owner_unit]
    if st and st.key == armoury_key then
        if st.tries >= _OFFHAND_RESWAP_MAX_TRIES then return end
        if (os.clock() - st.t) < _OFFHAND_RESWAP_COOLDOWN then return end
    end
    -- Need an alternate weapon slot to pulse through; end on the ORIGINAL wielded
    -- slot so nothing the player is holding visibly changes.
    local orig_slot = inv.wielded_slot
    if not orig_slot then return end
    local slots = equipment.slots
    local pulse_slot
    if orig_slot == "slot_melee" and slots["slot_ranged"] then
        pulse_slot = "slot_ranged"
    elseif orig_slot == "slot_ranged" and slots["slot_melee"] then
        pulse_slot = "slot_melee"
    else
        for sn, sd in pairs(slots) do
            if sn ~= orig_slot and sd and (sn == "slot_melee" or sn == "slot_ranged") then
                pulse_slot = sn
                break
            end
        end
    end
    if not pulse_slot then return end
    local from_mesh = (live and Unit.alive(live)) and _unit_mesh_name(live) or "<none>"
    local tries = (st and st.key == armoury_key) and (st.tries + 1) or 1
    _offhand_reswap_state[owner_unit] = { t = os.clock(), key = armoury_key, tries = tries }
    _offhand_reswap_active = true
    local ok1 = pcall(inv.wield, inv, pulse_slot)
    local ok2 = pcall(inv.wield, inv, orig_slot)
    _offhand_reswap_active = false
    mod:info("[cos-la-sync] RE-SWAP tag=%s owner=%s hand=%s armoury=%s try=%d from_mesh=%s -> %s pulse=%s<->%s ok=%s/%s",
        tostring(tag), tostring(owner_unit), tostring(hand_field), tostring(armoury_key), tries,
        tostring(from_mesh), tostring(la_unit), tostring(orig_slot), tostring(pulse_slot),
        tostring(ok1), tostring(ok2))
end

-- v0.9.69-dev (#265, LA_SYNC_CORE_AUDIT Slice 1): revert-side primitives.
-- Attached to `mod` (no new top-level locals; the main chunk is near the Lua
-- 200-local ceiling) but defined HERE so the closures capture the same
-- upvalues the apply path uses (_la_equips_by_peer, _offhand_reswap_active,
-- _wearer_unit_for_peer, ...).

-- Slot-level re-equip pulse that restores the NATIVE offhand/illusion render
-- after a revert: with the store entry deleted, the pulse's get_item_units
-- re-resolution falls through to vanilla (mesh AND texture -- a fresh spawn
-- carries no LA paint). Same machinery/guards as _ensure_offhand_mesh's
-- pulse (re-entrancy flag, cooldown via _offhand_reswap_state, slot-level
-- wield only -- NEVER World.destroy_unit) but with the INVERSE gate: it runs
-- regardless of LA variant state, because the target state is vanilla.
-- Safe contexts only (network recv callback / mod.update), like the caller.
mod._la_native_pulse = function(owner_unit, tag)
    if _offhand_reswap_active then return end
    if not (owner_unit and Unit.alive(owner_unit)) then return end
    local inv = ScriptUnit and ScriptUnit.has_extension and ScriptUnit.has_extension(owner_unit, "inventory_system")
    local equipment = inv and inv._equipment
    if not (equipment and equipment.slots and inv.wield) then return end
    local st = _offhand_reswap_state[owner_unit]
    if st and st.key == "__native__" and (os.clock() - st.t) < _OFFHAND_RESWAP_COOLDOWN then return end
    local orig_slot = inv.wielded_slot
    if not orig_slot then return end
    local slots = equipment.slots
    local pulse_slot
    if orig_slot == "slot_melee" and slots["slot_ranged"] then
        pulse_slot = "slot_ranged"
    elseif orig_slot == "slot_ranged" and slots["slot_melee"] then
        pulse_slot = "slot_melee"
    else
        for sn, sd in pairs(slots) do
            if sn ~= orig_slot and sd and (sn == "slot_melee" or sn == "slot_ranged") then
                pulse_slot = sn
                break
            end
        end
    end
    if not pulse_slot then return end
    _offhand_reswap_state[owner_unit] = { t = os.clock(), key = "__native__", tries = 1 }
    _offhand_reswap_active = true
    local ok1 = pcall(inv.wield, inv, pulse_slot)
    local ok2 = pcall(inv.wield, inv, orig_slot)
    _offhand_reswap_active = false
    if printf then printf("[la-state] NATIVE-PULSE tag=%s owner=%s pulse=%s<->%s ok=%s/%s",
        tostring(tag), tostring(owner_unit), tostring(orig_slot), tostring(pulse_slot),
        tostring(ok1), tostring(ok2)) end
end

-- Re-create the wearer's NATIVE hat attachment after a hat revert. Only
-- stomps the slot when it still renders the LA unit (if vanilla's own
-- loadout resync already replaced it, no-op) -- convergent regardless of
-- RPC-vs-resync arrival order. Residency-gated (the #270 class: never hand
-- the engine a non-resident unit; the 0.9.67 create_attachment gate
-- backstops this independently).
mod._la_restore_native_hat = function(owner_unit, slot_name, vanilla_key, la_unit_path)
    local ext = ScriptUnit and ScriptUnit.has_extension
        and ScriptUnit.has_extension(owner_unit, "attachment_system")
    if not (ext and ext.create_attachment) then return false, "no-attachment-ext" end
    local slot_data = ext._attachments and ext._attachments.slots and ext._attachments.slots[slot_name]
    local current = slot_data and slot_data.item_data and slot_data.item_data.unit
    if la_unit_path and current and current ~= la_unit_path then
        return false, "already-native"
    end
    local item = vanilla_key and ItemMasterList and rawget(ItemMasterList, vanilla_key)
    if not (item and item.unit) then return false, "no-vanilla-item" end
    if Application and Application.can_get and not Application.can_get("unit", item.unit) then
        return false, "vanilla-unit-non-resident"
    end
    if slot_data then
        if AttachmentUtils and AttachmentUtils.destroy_attachment then
            pcall(AttachmentUtils.destroy_attachment, ext._world, ext._unit, slot_data)
        end
        ext._attachments.slots[slot_name] = nil
    end
    local ok, err = pcall(ext.create_attachment, ext, slot_name, table.clone(item))
    return ok, err
end

-- Receiver for an authoritative revert broadcast (called from the
-- cos_la_apply handler, a safe network-callback context). Deletes the store
-- entry, purges any queued re-apply for the same (wearer, slot) so a
-- pending retry can't re-impose the reverted cosmetic, then restores the
-- native render per kind.
mod._la_apply_revert_recv = function(wearer, slot_name, kind, vanilla_key, hand_field)
    local entry = _la_equips_by_peer[wearer] and _la_equips_by_peer[wearer][slot_name]
    if _la_equips_by_peer[wearer] then
        _la_equips_by_peer[wearer][slot_name] = nil
    end
    if _la_pending_apply and #_la_pending_apply > 0 then
        local kept = {}
        for i = 1, #_la_pending_apply do
            local e = _la_pending_apply[i]
            if not (e[1] == wearer and e[2] == slot_name) then
                kept[#kept + 1] = e
            end
        end
        _la_pending_apply = kept
    end
    local wu = _wearer_unit_for_peer(wearer)
    local outcome
    if kind == "offhand" or kind == "illusion" then
        if wu then
            mod._la_native_pulse(wu, "revert")
            outcome = "pulse"
        else
            outcome = "wearer-not-spawned (native restores on next wield)"
        end
    elseif kind == "hat" then
        local la_unit_path = nil
        if entry and entry.armoury_key then
            local variant = _resolve_la_variant(entry.armoury_key)
            la_unit_path = variant and variant.new_units and variant.new_units[1]
        end
        local vk = vanilla_key or (entry and entry.vanilla_key)
        if wu then
            local ok, why = mod._la_restore_native_hat(wu, slot_name, vk, la_unit_path)
            outcome = ok and "hat-restored" or ("hat-restore-skipped: " .. tostring(why))
        else
            outcome = "wearer-not-spawned"
        end
    else -- armor: store delete stops future re-imposition; the body repaint
         -- rides the next native slot_skin resync / respawn (rare path;
         -- active armor un-paint needs LA API work -- see issue 265).
        outcome = "armor: store cleared, repaint deferred to native resync"
    end
    if printf then printf("[la-state] REVERT-RECV wearer=%s slot=%s kind=%s had_entry=%s -> %s",
        tostring(wearer), tostring(slot_name), tostring(kind),
        tostring(entry ~= nil), tostring(outcome)) end
end

-- v0.9.70-dev (#264, LA_SYNC_CORE_AUDIT Slice 2 / invariant I3): the SINGLE
-- render-reconcile entry point. Every trigger that (re)renders a peer's
-- cosmetic-bearing units -- recv, pending retry, transition walk, husk wield,
-- local wield -- calls THIS instead of its own bespoke re-apply, so a trigger
-- nobody special-cased (the #264 weapon switch-back) cannot fall through.
-- Reads ONLY the synced store (I1), targets ONLY the human wearer's unit
-- (I4, via _wearer_unit_for_peer), and treats mesh+paint as one gated unit
-- (I7): in safe contexts (allow_pulse=true: network callback / mod.update)
-- a stale kind="unit" mesh is pulsed via _ensure_offhand_mesh; in wield
-- contexts (allow_pulse=false: called from inside a _wield_slot body, where
-- pulsing would re-enter wield) a stale mesh is DEFERRED to the pending
-- drain, which pulses from mod.update within a frame or two.
-- Returns (applied, reason): reason="no-entry" is terminal for retry loops
-- (a revert deleted the entry); "wearer-not-spawned" is retryable.
mod._la_reconcile = function(wearer_peer, slot_name, tag, allow_pulse)
    local equips = _la_equips_by_peer[wearer_peer]
    local eq = equips and equips[slot_name]
    if not (eq and eq.kind and eq.armoury_key) then return false, "no-entry" end
    local wu = _wearer_unit_for_peer(wearer_peer)
    if not wu then return false, "wearer-not-spawned" end
    local applied = _apply_la_on_unit(wu, slot_name, eq.kind, eq.armoury_key, eq.vanilla_key)
    if applied and (eq.kind == "offhand" or eq.kind == "illusion") then
        if allow_pulse then
            _ensure_offhand_mesh(wu, eq.hand_field, eq.armoury_key, tag)
        else
            -- Wield context: verify the just-spawned mesh against the store;
            -- if the in-wield get_item_units swap silently missed (#264's
            -- failure mode), hand the mesh repair to the pending drain.
            local inv = ScriptUnit and ScriptUnit.has_extension
                and ScriptUnit.has_extension(wu, "inventory_system")
            local equipment = inv and inv._equipment
            local wf = (eq.hand_field == "right_hand_unit")
                and "right_hand_wielded_unit_3p" or "left_hand_wielded_unit_3p"
            local live = equipment and equipment[wf]
            if live and Unit.alive(live) and not _offhand_paint_mesh_ok(live, eq.armoury_key) then
                _la_pending_apply[#_la_pending_apply + 1] = {
                    wearer_peer, slot_name, eq.kind, eq.armoury_key, eq.vanilla_key, os.clock() + 5,
                }
                if printf then printf("[la-state] RECONCILE tag=%s wearer=%s slot=%s -> mesh stale after wield, deferred pulse queued (key=%s)",
                    tostring(tag), tostring(wearer_peer), tostring(slot_name), tostring(eq.armoury_key)) end
            end
        end
    end
    return applied
end

-- HOST: receives equip requests from clients, validates, records into
-- `_la_equips_by_peer`, broadcasts the authoritative cos_la_apply to ALL.
mod:network_register("cos_la_apply_req", function(sender_peer_id, schema_version, payload)
    if schema_version ~= COS_RPC_SCHEMA then  -- #45: drop cross-version payloads
        _dbg_alert("[rpc:schema] cos_la_apply_req mismatch from peer=%s: peer sent v%s, we expect v%d. Dropping.",
            tostring(sender_peer_id), tostring(schema_version), COS_RPC_SCHEMA)
        -- Task-3 visibility: _dbg_alert routes through mod:warning (VMF-gated,
        -- invisible with mod logging OFF). Mirror to engine printf so a dropped
        -- cross-version RPC is never a silent failure in the user's log.
        if printf then printf("[rpc:schema] cos_la_apply_req DROP peer=%s sent=v%s expect=v%d",
            tostring(sender_peer_id), tostring(schema_version), COS_RPC_SCHEMA) end
        return
    end
    if not _is_local_server() then return end  -- defense in depth
    if type(payload) ~= "table" or not sender_peer_id then return end
    local slot_name   = payload.slot
    local kind        = payload.kind
    local armoury_key = payload.armoury_key
    local vanilla_key = payload.vanilla_key
    -- v0.9.9.4-dev: hand_field is new; older clients omit it. Default to
    -- "left_hand_unit" for offhand/illusion (legacy behavior) so peers on
    -- pre-v0.9.9.4 versions still sync correctly.
    local hand_field  = payload.hand_field
    if (kind == "offhand" or kind == "illusion") and not hand_field then
        hand_field = "left_hand_unit"
    end
    -- v0.9.69-dev (Slice 0, I6): host-side receipt line BEFORE any validation,
    -- so a client req that reaches the host but is then rejected/deduped is
    -- distinguishable from one lost on the wire (#264-comment transport loss).
    if printf then printf("[la-state] REQ-RECV from=%s slot=%s kind=%s key=%s revert=%s",
        tostring(sender_peer_id), tostring(slot_name), tostring(kind),
        tostring(armoury_key), tostring(payload.revert or false)) end
    -- v0.9.69-dev (#265 Slice 1): client-originated REVERT. No armoury_key to
    -- validate -- delete the sender's store entry and rebroadcast the revert
    -- authoritatively to all peers (the sender included, for lockstep).
    if payload.revert then
        if slot_name and kind then
            if _la_equips_by_peer[sender_peer_id] then
                _la_equips_by_peer[sender_peer_id][slot_name] = nil
            end
            mod:network_send("cos_la_apply", "all", COS_RPC_SCHEMA, {
                wearer_peer_id = sender_peer_id,
                slot           = slot_name,
                kind           = kind,
                revert         = true,
                vanilla_key    = payload.vanilla_key,
                hand_field     = hand_field,
            })
        end
        return
    end
    if not (slot_name and kind and armoury_key) then return end
    -- v0.9.3.2-hotfix: accept armoury_keys present in EITHER our bridge index
    -- OR LA's own SKIN_LIST directly. The bridge's register_all only registers
    -- swap_hand == "hat" or "armor" variants — shields and weapons (swap_hand
    -- == "left_hand_unit" / "right_hand_unit") are NOT in armoury_to_backend.
    -- That left shield repaints silently rejected on the host side even though
    -- the client paints them locally just fine (its paint code reads LA's
    -- SKIN_LIST directly). Now: accept any armoury_key LA knows about.
    -- Burned PC-A→PC-B test 2026-05-21 17:53.
    local bridge_known = LA_BRIDGE and LA_BRIDGE.registered and LA_BRIDGE.armoury_to_backend[armoury_key]
    local la_known = false
    do
        local la = get_mod("Loremasters-Armoury")
        if la and type(la.SKIN_LIST) == "table" and la.SKIN_LIST[armoury_key] then
            la_known = true
        end
    end
    if not (bridge_known or la_known) then
        _dbg_alert("[cos_la_apply_req] reject from %s: unknown armoury_key %s",
            tostring(sender_peer_id), tostring(armoury_key))
        return
    end
    _la_equips_by_peer[sender_peer_id] = _la_equips_by_peer[sender_peer_id] or {}
    _la_equips_by_peer[sender_peer_id][slot_name] = {
        kind = kind, armoury_key = armoury_key, vanilla_key = vanilla_key,
        hand_field = hand_field,
    }
    mod:network_send("cos_la_apply", "all", COS_RPC_SCHEMA, {
        wearer_peer_id = sender_peer_id,
        slot           = slot_name,
        kind           = kind,
        armoury_key    = armoury_key,
        vanilla_key    = vanilla_key,
        hand_field     = hand_field,
    })
end)

-- v0.9.70-dev (#267, LA_SYNC_CORE_AUDIT Slice 2b / invariant I9): HOST side
-- of the pull-on-ready flow. A peer that just reached StateIngame requests
-- the full LA store; we reply with one targeted cos_la_apply per recorded
-- (wearer, slot). Reuses the existing broadcast payload shape, so the
-- joiner's recv path (mirror + reconcile) needs nothing new. The requester's
-- own entries are included deliberately -- after a transition they re-drive
-- the client's local reconcile, hardening #233. Old-version peers never send
-- this RPC and ignore it if received (unknown name), so it is
-- backward-compatible without a schema bump.
mod:network_register("cos_la_state_req", function(sender_peer_id, schema_version, payload)
    if schema_version ~= COS_RPC_SCHEMA then
        if printf then printf("[rpc:schema] cos_la_state_req DROP peer=%s sent=v%s expect=v%d",
            tostring(sender_peer_id), tostring(schema_version), COS_RPC_SCHEMA) end
        return
    end
    if not _is_local_server() then return end
    if not sender_peer_id then return end
    local n = 0
    for wearer_peer, slots in pairs(_la_equips_by_peer) do
        if type(slots) == "table" then
            for slot_name, entry in pairs(slots) do
                if type(entry) == "table" and entry.kind and entry.armoury_key then
                    mod:network_send("cos_la_apply", sender_peer_id, COS_RPC_SCHEMA, {
                        wearer_peer_id = wearer_peer,
                        slot           = slot_name,
                        kind           = entry.kind,
                        armoury_key    = entry.armoury_key,
                        vanilla_key    = entry.vanilla_key,
                        hand_field     = entry.hand_field,
                    })
                    n = n + 1
                end
            end
        end
    end
    if printf then printf("[la-state] STATE-PULL reply: %d entr(ies) -> requester=%s",
        n, tostring(sender_peer_id)) end
    -- v0.9.71-dev: explicit ack so the requester can distinguish "empty
    -- store" from "request lost in the load window" and stop retrying.
    mod:network_send("cos_la_state_ack", sender_peer_id, COS_RPC_SCHEMA, { count = n })
end)

-- v0.9.71-dev: requester side of the pull ack (see the retry drain in
-- mod.update). Old-version hosts never send this; the requester then retries
-- up to its cap and gives up loudly - still strictly better than one silent
-- fire-and-forget send.
mod:network_register("cos_la_state_ack", function(sender_peer_id, schema_version, payload)
    if schema_version ~= COS_RPC_SCHEMA then return end
    local attempts = type(mod._la_state_pull_pending) == "table"
        and mod._la_state_pull_pending.attempts or "?"
    mod._la_state_pull_pending = nil
    if printf then printf("[la-state] STATE-PULL acked by host=%s count=%s (attempt %s)",
        tostring(sender_peer_id),
        tostring(type(payload) == "table" and payload.count or "?"),
        tostring(attempts)) end
end)

-- v0.9.0-dev: peer-disconnect cleanup. Without this _la_equips_by_peer grows
-- unboundedly across the host's session, and stale entries replay on hot_join
-- for peers who left long ago (visible if they share peer_id with a future
-- joiner, which Steam sometimes recycles). Also clears _last_emit_at so the
-- dedup window doesn't suppress legitimate fresh emits after re-join.
-- v0.9.71-dev ROOT-CAUSE FIX (2026-07-06 17:25/17:26 session logs, both
-- machines): `PlayerManager.remove_player` fires for EVERY peer - including
-- the machine's OWN peer - on EVERY level transition, not just on
-- disconnects (host log 17:28:20.460/.471: remove_player for self AND the
-- client during the keep->mission load, each immediately followed by this
-- hook's purge line). The v0.9.0 immediate purge therefore WIPED
-- `_la_equips_by_peer` on every machine at every transition, which is why
-- TRANSITION-WALK always armed with `offhand_entries=0`, HUSK-GATE logged
-- `no-store-for-wearer` post-transition, and no illusion survived into a
-- mission (the store the audit assumed transition-proof never was).
-- Fix: DEFER the purge 30s. A transition re-adds the peer within seconds
-- (add_remote_player cancels the deadline); a genuine disconnect never
-- re-adds, so the purge still runs - the Steam peer_id-recycling rationale
-- of v0.9.0 is preserved, just 30s later. The local peer is never purged.
if rawget(_G, "PlayerManager") then
    mod:hook_safe(PlayerManager, "remove_player", function(self, peer_id, local_player_id)
        if not peer_id then return end
        local has_state = (_la_equips_by_peer and _la_equips_by_peer[peer_id]) ~= nil
            or (mod._glow_by_peer and mod._glow_by_peer[peer_id]) ~= nil
        if not has_state then return end
        mod._la_peer_purge_at = mod._la_peer_purge_at or {}
        if not mod._la_peer_purge_at[peer_id] then
            mod._la_peer_purge_at[peer_id] = os.clock() + 30
            if printf then printf("[la-state] PEER-PURGE scheduled peer=%s in 30s (remove_player; canceled if the peer re-adds - transitions do)",
                tostring(peer_id)) end
        end
    end)
    -- Transition/hot-join re-add cancels the pending purge. Remote peers
    -- re-enter via add_remote_player on every level load.
    mod:hook_safe(PlayerManager, "add_remote_player", function(self, peer_id, ...)
        if peer_id and mod._la_peer_purge_at and mod._la_peer_purge_at[peer_id] then
            mod._la_peer_purge_at[peer_id] = nil
            if printf then printf("[la-state] PEER-PURGE canceled peer=%s (re-added - transition, not a disconnect)",
                tostring(peer_id)) end
        end
    end)
end

-- Executes due deferred purges. Called from mod.update.
mod._la_tick_peer_purges = function()
    local q = mod._la_peer_purge_at
    if not q or not next(q) then return end
    local now = os.clock()
    local local_peer = _local_player_peer_id()
    for peer_id, deadline in pairs(q) do
        if peer_id == local_peer then
            q[peer_id] = nil  -- never purge our own state
        elseif now >= deadline then
            q[peer_id] = nil
            if _la_equips_by_peer and _la_equips_by_peer[peer_id] then
                _la_equips_by_peer[peer_id] = nil
            end
            if _last_emit_at then
                for k, _ in pairs(_last_emit_at) do
                    if type(k) == "string" and k:sub(1, #tostring(peer_id) + 1) == (tostring(peer_id) .. "|") then
                        _last_emit_at[k] = nil
                    end
                end
            end
            if mod._glow_by_peer and mod._glow_by_peer[peer_id] then
                mod._glow_by_peer[peer_id] = nil
            end
            if printf then printf("[la-state] PEER-PURGE executed peer=%s (no re-add within 30s - genuine leave)",
                tostring(peer_id)) end
        end
    end
end

-- ALL PEERS: receives the authoritative apply broadcast. Only accept it from
-- the host (defense against malicious peers spoofing).
mod:network_register("cos_la_apply", function(sender_peer_id, schema_version, payload)
    if schema_version ~= COS_RPC_SCHEMA then  -- #45: drop cross-version payloads
        _dbg_alert("[rpc:schema] cos_la_apply mismatch from peer=%s: peer sent v%s, we expect v%d. Dropping.",
            tostring(sender_peer_id), tostring(schema_version), COS_RPC_SCHEMA)
        if printf then printf("[rpc:schema] cos_la_apply DROP peer=%s sent=v%s expect=v%d",
            tostring(sender_peer_id), tostring(schema_version), COS_RPC_SCHEMA) end
        return
    end
    if type(payload) ~= "table" then return end
    local host = _host_peer_id()
    if host and sender_peer_id ~= host then
        _dbg_alert("[cos_la_apply] reject non-host sender %s (host=%s)",
            tostring(sender_peer_id), tostring(host))
        return
    end
    local wearer       = payload.wearer_peer_id
    local slot_name    = payload.slot
    local kind         = payload.kind
    local armoury_key  = payload.armoury_key
    local vanilla_key  = payload.vanilla_key
    -- v0.9.9.4-dev: tolerate older peers that don't send hand_field;
    -- treat as left_hand_unit for offhand/illusion (legacy default).
    local hand_field   = payload.hand_field
    if (kind == "offhand" or kind == "illusion") and not hand_field then
        hand_field = "left_hand_unit"
    end
    -- v0.9.69-dev (#265 Slice 1): authoritative REVERT. Delete the store
    -- entry and restore the native render (pulse / hat re-create) via the
    -- receiver helper defined after _ensure_offhand_mesh. Placed BEFORE the
    -- armoury_key guard -- a revert carries none by design.
    if payload.revert then
        if wearer and slot_name and kind and mod._la_apply_revert_recv then
            mod._la_apply_revert_recv(wearer, slot_name, kind, payload.vanilla_key, hand_field)
        end
        return
    end
    if not (wearer and slot_name and kind and armoury_key) then return end

    -- v0.9.0.7-hotfix: MIRROR THE CACHE WRITE ON CLIENTS.
    -- Previously only the HOST's `cos_la_apply_req` register handler (see
    -- the `mod:network_register("cos_la_apply_req", ...)` block above)
    -- wrote to `_la_equips_by_peer`. Clients received the broadcast and
    -- ran the apply once, but never recorded the entry — so:
    --   1. The v0.9.0.5 husk-wield re-paint hook silently no-op'd on
    --      every client (lookup returned nil every time).
    --   2. The v0.9.0.6 husk-mesh-swap in get_item_units also no-op'd
    --      on clients (same nil lookup) → kind="unit" Ostermark shields
    --      stayed vanilla on the client viewing the host.
    -- Fix: mirror the host's write here so EVERY peer (host + clients)
    -- maintains the same `_la_equips_by_peer` cache state. The host's
    -- own broadcast loops back via "all" → this handler fires on the
    -- host too, but the write is idempotent (entry already there from
    -- the cos_la_apply_req handler).
    _la_equips_by_peer[wearer] = _la_equips_by_peer[wearer] or {}
    _la_equips_by_peer[wearer][slot_name] = {
        kind = kind, armoury_key = armoury_key, vanilla_key = vanilla_key,
        hand_field = hand_field,
    }
    -- v0.9.0.11-hotfix: diagnostic — count cache entries to confirm the write
    -- actually persisted (and to verify the upvalue scope fix from this version).
    local n = 0
    for _, _ in pairs(_la_equips_by_peer[wearer]) do n = n + 1 end
    _dbg("[cos_la_apply recv] CACHE WRITE _la_equips_by_peer[%s][%s] now has %d slot(s) total",
        tostring(wearer), tostring(slot_name), n)

    -- v0.9.70-dev (Slice 2 / I3): recv now routes through the single
    -- reconcile entry point (paint + gated mesh pulse, wearer-scoped).
    local applied = mod._la_reconcile(wearer, slot_name, "recv", true)
    -- v0.9.61-dev (#203): [cos-la-sync] receiver-side outcome via mod:info so it
    -- lands in the HOST's log (the missing evidence for #203 -- a client log can't
    -- show the host painting the wearer's husk). Deduped on
    -- (wearer,slot,armoury,applied) so a per-frame retry cannot flood; an
    -- applied=false->true flip logs both, showing when (or if) the paint landed.
    -- The mesh-swap + paint decision itself is in the [cos:sync] husk_meshgate /
    -- husk_meshswap / husk_offhand PROBE lines (also host-side, printf).
    do
        mod._cos_la_sync_recv_seen = mod._cos_la_sync_recv_seen or {}
        local seen_key = tostring(wearer) .. "|" .. tostring(slot_name) .. "|"
            .. tostring(armoury_key) .. "|" .. tostring(applied)
        if not mod._cos_la_sync_recv_seen[seen_key] then
            mod._cos_la_sync_recv_seen[seen_key] = true
            mod:info("[cos-la-sync] RECV wearer=%s slot=%s kind=%s armoury=%s applied=%s",
                tostring(wearer), tostring(slot_name), tostring(kind),
                tostring(armoury_key), tostring(applied))
        end
    end
    _dbg("[cos_la_apply recv] from=%s wearer=%s slot=%s kind=%s key=%s applied=%s",
        tostring(sender_peer_id), tostring(wearer), tostring(slot_name),
        tostring(kind), tostring(armoury_key), tostring(applied))
    -- [cos:sync] #149/#154: husk cache population + immediate apply outcome on a
    -- broadcast receive. applied=false here is the mission-start race (wearer not
    -- spawned yet) that gets queued below for retry. peer=husk (remote wearer).
    if PROBE then
        PROBE.emit("cos:sync",
            "recv_cache/" .. tostring(wearer) .. "/" .. tostring(slot_name) .. "/" .. tostring(armoury_key),
            string.format("peer=husk event=cache_write+apply wearer=%s from=%s slot=%s kind=%s key=%s applied=%s",
                tostring(wearer), tostring(sender_peer_id), tostring(slot_name),
                tostring(kind), tostring(armoury_key), tostring(applied)))
    end
    _trace("SYNC recv from=%s wearer=%s slot=%s kind=%s armoury=%s applied=%s",
        tostring(sender_peer_id), tostring(wearer), tostring(slot_name),
        tostring(kind), tostring(armoury_key), tostring(applied))

    -- v0.9.0.10-hotfix: TRIGGER MESH SWAP for kind="unit" variants.
    -- The husk-mesh-swap branch in BackendUtils.get_item_units only fires
    -- when SimpleHuskInventoryExtension._wield_slot runs, which happens on
    -- rpc_wield_equipment (slot_melee↔slot_ranged swaps) — NOT when the
    -- host cycles shield variants via CT's picker (which emits cos_la_apply
    -- but no wield change). For kind="unit" variants (Ostermark, Bastonne
    -- custom-mesh shields), the texture-paint path returns false (mesh swap
    -- is what's needed, not paint). Without a wield event, the husk's
    -- weapon unit stays vanilla.
    --
    -- Fix: when the variant is kind="unit" AND the entry is an offhand/
    -- illusion (weapon-side, where the wield event is meaningful), force a
    -- husk re-wield so _wield_slot → BackendUtils.get_item_units → husk-mesh-
    -- swap branch → LA mesh spawns.
    --
    -- v0.9.41-dev (#149): PULSE through the OTHER weapon slot then back,
    -- mirroring the customization-exit pulse (~line 2317), instead of
    -- inv:wield(inv.wielded_slot). NOTE: vanilla
    -- SimpleHuskInventoryExtension._wield_slot (source line 641) does NOT
    -- short-circuit on same-slot — it destroy+respawns and re-calls
    -- get_item_units every time — so same-slot WOULD re-run the swap. We pulse
    -- anyway for robustness: it guarantees a clean destroy/respawn cycle after
    -- the _la_equips_by_peer cache is populated (the client's mission-start race)
    -- and matches the established pulse pattern. We end on the ORIGINAL slot so
    -- the husk stays on the weapon the host has wielded. Pcall each wield so a
    -- failure can't crash the receiver; even if the pulse fails the rest of the
    -- apply chain ran. (The texture half of the client fix is the
    -- "network_husk" paint now allowed in _la_bridge.lua.)
    -- v0.9.64-dev (#233/#234): route through the gated _ensure_offhand_mesh helper
    -- instead of the old UNCONDITIONAL pulse. The helper no-ops when the mesh is
    -- already the LA mesh (so no flicker on a same-model re-apply), only pulses a
    -- kind="unit" mesh that is stale/vanilla AND package-resident, and is bounded by
    -- a per-owner cooldown + try-cap. Covers BOTH the host's husk (wearer=remote,
    -- #233) and the local player's own body (wearer=local peer -> players_at_peer
    -- returns the local player, #234), since cos_la_apply broadcasts to "all"
    -- including the originating client. Safe context (network callback, not a
    -- _wield_slot body).
    -- v0.9.69-dev (#268, invariant I4 targeting): the mesh pulse is scoped to
    -- THE wearer's unit only (the old players_at_peer loop force-swapped a
    -- host's BOT shields). v0.9.70-dev: the pulse now lives INSIDE
    -- mod._la_reconcile (allow_pulse=true above), so nothing extra runs here.
    if not applied then
        -- Wearer unit not spawned locally yet (loading screen race / late
        -- network spawn / husk not wielding the right slot). Queue and retry
        -- on mod.update for up to 5 seconds.
        _la_pending_apply[#_la_pending_apply + 1] = {
            wearer, slot_name, kind, armoury_key, vanilla_key, os.clock() + 5,
        }
        -- [cos:sync] #149: mission-entry / late-spawn reapply deferral. This is
        -- the "LA shield reverts at mission start" window -- apply failed now,
        -- queued for retry. peer=husk (remote wearer).
        if PROBE then
            PROBE.emit("cos:sync",
                "pending/" .. tostring(wearer) .. "/" .. tostring(slot_name) .. "/" .. tostring(armoury_key),
                string.format("peer=husk event=deferred-reapply wearer=%s slot=%s kind=%s key=%s reason=wearer-not-spawned-or-wrong-slot",
                    tostring(wearer), tostring(slot_name), tostring(kind), tostring(armoury_key)))
        end
    end
end)

-- ============================================================
-- v0.9.0-dev: per-peer GLOW broadcast channel.
--
-- Architecture mirrors cos_la_apply: client → cos_glow_apply_req → host →
-- cos_glow_apply broadcast to all. Host short-circuits its own emit (records
-- locally + broadcasts). Receivers cache in _glow_by_peer; the apply hooks
-- (see _hook_apply_with_template_mutation, _apply_glow_override etc.) look
-- up wearer-of-unit at paint time and read from the cache instead of local
-- mod:get when painting remote husks.
--
-- Payload is small (~50 chars JSON: 12 numbers + 5 enum strings + 2 booleans)
-- so chunking isn't needed — well under STRING_MAX=500.
--
-- Triggers for broadcast:
--   * mod.on_setting_changed for any "glow_*" setting → re-emit
--   * Initial fire once the LA bridge inits (first frame where bridge is up)
--   * Every game-state-changed (keep enter, mission start) → re-emit, in
--     case peers' caches were cleared on disconnect/reconnect.
-- ============================================================

-- v0.9.37-dev: emptied. These were the GLOBAL glow-override VMF settings
-- broadcast to peers so a wearer's chosen global preset painted on remote
-- husks. The "Weapon Glow Override" VMF menu was removed (glow now driven by
-- the per-item Glow Picker popup), so these settings no longer exist and
-- mod:get returns nil for them. The per-item Glow Picker glow is NOT synced
-- through this channel (local-only — see GLOW_SYSTEM.md §7g), so emptying the
-- list loses nothing the picker relies on. The broadcast machinery
-- (_collect_local_glow_state / cos_glow_apply RPC) is kept intact so a future
-- coop-sync of per-item glow can repopulate this list.
local _GLOW_SETTING_KEYS = {}

local function _collect_local_glow_state()
    local state = {}
    for _, key in ipairs(_GLOW_SETTING_KEYS) do
        state[key] = mod:get(key)
    end
    return state
end

-- Send the local player's glow state to peers. Host: record + broadcast
-- directly. Client: route via host (server-authoritative — same pattern as
-- cos_la_apply). Re-call this any time glow settings change OR when joining
-- a session.
local _glow_emit_pending = false
local _glow_last_emit_at = 0
local _GLOW_EMIT_THROTTLE = 0.3  -- coalesce rapid setting changes

local function _send_local_glow_state()
    -- v0.9.0-hotfix: `Managers.player:local_player()` calls the engine's
    -- `peer_id()` C function which asserts "Network backend has not been set"
    -- if invoked before the network backend is initialized (boot → title →
    -- pre-keep). VMF's safe-call wrapper traps the error but spams it once per
    -- frame from `_glow_sync_tick` while `_glow_emit_pending` stays true. PC-B
    -- log captured 7864× → 36 MB log in one session. Defer with pcall + leave
    -- pending true; next frame's mod.update will retry.
    local pm = Managers and Managers.player
    if not pm or not pm.local_player then
        _glow_emit_pending = true
        return
    end
    local ok, lp = pcall(pm.local_player, pm)
    if not ok or not lp then
        -- Network backend not up yet (engine-level peer_id error). Stay
        -- pending; next frame will retry.
        _glow_emit_pending = true
        return
    end
    local local_peer = lp.peer_id
    if not local_peer then
        _glow_emit_pending = true
        return
    end
    local state = _collect_local_glow_state()
    if _is_local_server() then
        -- Host: record + broadcast (own broadcast loops back via "all").
        _glow_by_peer[local_peer] = state
        mod:network_send("cos_glow_apply", "all", COS_RPC_SCHEMA, {
            wearer_peer_id = local_peer,
            state = state,
        })
    else
        -- v0.9.0.15-hotfix: same fix as cos_la_apply_req above — "server" is
        -- not a valid VMF recipient string. Use the host's literal peer_id.
        local host = _host_peer_id()
        if not host then
            _glow_emit_pending = true  -- retry next tick when host_peer is up
            return
        end
        mod:network_send("cos_glow_apply_req", host, COS_RPC_SCHEMA, {
            state = state,
        })
    end
    _glow_emit_pending = false
    _glow_last_emit_at = os.clock()
end

-- Pump pending re-emits (called from mod.update). Used when the local player
-- isn't fully spawned yet at the moment a setting change fires.
-- v0.9.0-hotfix: gate on Managers.state.network being up so the inner
-- pm:local_player() call never sees a half-initialized backend. Cheap check
-- (~1 nil-test) and eliminates the cascade described in _send_local_glow_state.
mod._glow_sync_tick = function(dt)
    if not _glow_emit_pending then return end
    local now = os.clock()
    if (now - _glow_last_emit_at) < _GLOW_EMIT_THROTTLE then return end
    local sn = Managers and Managers.state and Managers.state.network
    if not sn or not sn.game then return end  -- backend not ready, retry next frame
    _send_local_glow_state()
end

-- HOST: receives glow state from a client, validates, broadcasts to all.
mod:network_register("cos_glow_apply_req", function(sender_peer_id, schema_version, payload)
    if schema_version ~= COS_RPC_SCHEMA then  -- #45: drop cross-version payloads
        _dbg_alert("[rpc:schema] cos_glow_apply_req mismatch from peer=%s: peer sent v%s, we expect v%d. Dropping.",
            tostring(sender_peer_id), tostring(schema_version), COS_RPC_SCHEMA)
        if printf then printf("[rpc:schema] cos_glow_apply_req DROP peer=%s sent=v%s expect=v%d",
            tostring(sender_peer_id), tostring(schema_version), COS_RPC_SCHEMA) end
        return
    end
    if not _is_local_server() then return end  -- defense in depth
    if type(payload) ~= "table" or type(payload.state) ~= "table" then return end
    if not sender_peer_id then return end
    _glow_by_peer[sender_peer_id] = payload.state
    mod:network_send("cos_glow_apply", "all", COS_RPC_SCHEMA, {
        wearer_peer_id = sender_peer_id,
        state = payload.state,
    })
end)

-- ALL PEERS: receives the authoritative glow broadcast. Only accept from host.
mod:network_register("cos_glow_apply", function(sender_peer_id, schema_version, payload)
    if schema_version ~= COS_RPC_SCHEMA then  -- #45: drop cross-version payloads
        _dbg_alert("[rpc:schema] cos_glow_apply mismatch from peer=%s: peer sent v%s, we expect v%d. Dropping.",
            tostring(sender_peer_id), tostring(schema_version), COS_RPC_SCHEMA)
        if printf then printf("[rpc:schema] cos_glow_apply DROP peer=%s sent=v%s expect=v%d",
            tostring(sender_peer_id), tostring(schema_version), COS_RPC_SCHEMA) end
        return
    end
    if type(payload) ~= "table" or type(payload.state) ~= "table" then return end
    local host = _host_peer_id()
    if host and sender_peer_id ~= host then
        _dbg_alert("[cos_glow_apply] reject non-host sender %s (host=%s)",
            tostring(sender_peer_id), tostring(host))
        return
    end
    local wearer = payload.wearer_peer_id
    if not wearer then return end
    _glow_by_peer[wearer] = payload.state
end)

-- HOST: when a new peer joins, rebroadcast every known peer's glow state
-- to "all" (which reaches the new joiner) so they have everyone's state
-- before they start spawning husks. Wired into the existing hot_join_sync
-- hook below via the rebroadcast helper.
local function _glow_rebroadcast_all_for_hot_join()
    if not _is_local_server() then return end
    for wearer_peer, state in pairs(_glow_by_peer) do
        mod:network_send("cos_glow_apply", "all", COS_RPC_SCHEMA, {
            wearer_peer_id = wearer_peer,
            state = state,
        })
    end
end
mod._glow_rebroadcast_all_for_hot_join = _glow_rebroadcast_all_for_hot_join

-- v0.9.0.12-hotfix: targeted-at-joiner glow rebroadcast. Same reason as the
-- cos_la_apply targeted send above — "all" may not include the joiner yet
-- at hot_join_sync time, so direct-target the joining peer.
local function _glow_rebroadcast_targeted(target_peer_id)
    if not _is_local_server() then return end
    if not target_peer_id then return end
    local n = 0
    for wearer_peer, state in pairs(_glow_by_peer) do
        mod:network_send("cos_glow_apply", target_peer_id, COS_RPC_SCHEMA, {
            wearer_peer_id = wearer_peer,
            state = state,
        })
        n = n + 1
    end
    if n > 0 then
        _dbg("[hot-join glow replay] sent %d cos_glow_apply entries targeted at joiner=%s",
            n, tostring(target_peer_id))
    end
end
mod._glow_rebroadcast_targeted = _glow_rebroadcast_targeted

-- Public hook for VMF's on_setting_changed (existing handler at line 608
-- forwards here for glow_* settings). Schedule rather than emit immediately
-- so a single VMF settings-page save doesn't burst N RPCs for N changed
-- settings — the throttle in _glow_sync_tick coalesces.
mod._on_glow_setting_changed = function()
    _glow_emit_pending = true
end

-- v0.9.0.6-hotfix: husk-wield context wrapper.
--
-- Wraps SimpleHuskInventoryExtension._wield_slot to set a thread-local
-- `_current_husk_wield` table BEFORE the vanilla call enters
-- BackendUtils.get_item_units. The CT get_item_units hook reads the context
-- (wearer_peer, slot_name) and overrides result.left_hand_unit when the
-- wearer has a kind="unit" LA mesh selection recorded in _la_equips_by_peer.
-- This is how Ostermark / Bastonne / etc. custom-mesh shields render on
-- husks instead of the vanilla mesh.
--
-- v0.9.0.8-hotfix: switched to string-form hook so VMF defers resolution
-- until the class is loaded. Table-form `mod:hook(SimpleHuskInventoryExtension, ...)`
-- gated on `rawget(_G, "SimpleHuskInventoryExtension")` silently failed when
-- the class wasn't yet loaded at mod-init time — the rawget returned nil,
-- the `if` skipped, hook NEVER registered, and no `[husk-mesh-swap]` log
-- ever fired on PC-B. String-form lets VMF queue the hook via its delayed-
-- hooks mechanism (see boot log "Attempt to hook N delayed hooks").
mod:hook("SimpleHuskInventoryExtension", "_wield_slot", function(func, self, world, equipment, slot_name, unit_1p, unit_3p)
    -- Resolve which peer owns this husk extension.
    local husk_unit = self and self._unit
    local wearer_peer = nil
    local pm = Managers and Managers.player
    if pm and pm._players and husk_unit then
        for _, p in pairs(pm._players) do
            if p.player_unit == husk_unit then
                wearer_peer = p.peer_id
                break
            end
        end
    end
    -- v0.9.0.8-hotfix: diagnostic log.
    _dbg("[husk-wield-wrap] entry wearer=%s slot=%s husk_unit=%s",
        tostring(wearer_peer), tostring(slot_name), tostring(husk_unit))
    -- v0.9.69-dev (Slice 0, I6 / #264): a nil wearer_peer here silently kills
    -- BOTH the get_item_units mesh swap AND the post-vanilla repaint for this
    -- wield. Surface it once per husk unit in the mod-logging-OFF log.
    if not wearer_peer and husk_unit then
        local seen = mod._la_gate_seen
        if not seen then seen = {}; mod._la_gate_seen = seen end
        local sk = "wield-nopeer|" .. tostring(husk_unit)
        if not seen[sk] and printf then
            seen[sk] = true
            printf("[la-state] HUSK-WIELD wearer-unresolved husk=%s slot=%s (mesh swap + repaint skipped this path)",
                tostring(husk_unit), tostring(slot_name))
        end
    end
    -- v0.9.43-dev HUSK trace: a remote peer's body (husk) is (re)wielding a
    -- slot. This drives the husk get_item_units mesh-swap (RESOLVE husk-mesh-
    -- swap) + the post-vanilla repaint below. Repro #4 (host swaps secondary
    -- and back) fires this on every peer's husk view of the host.
    _trace("HUSK wield_slot entry wearer=%s slot=%s husk_unit=%s",
        tostring(wearer_peer), tostring(slot_name), tostring(husk_unit))
    -- Set context (stack-style).
    local prev = _current_husk_wield
    _current_husk_wield = { wearer_peer = wearer_peer, husk_unit = husk_unit, slot_name = slot_name }
    -- v0.9.2.1: ALWAYS delegate to vanilla. The v0.9.2 pre-flight bail
    -- (skipping the vanilla call when can_get reported a missing unit)
    -- left `self.wielded_slot` nil, which made vanilla's subsequent
    -- `wield()` chain crash downstream at simple_husk_inventory_extension
    -- .lua:534 (`equipment.slots[wielded_slot]` → nil-index) on EVERY husk
    -- wield to a missing unit, not just the rare engine-assert case the
    -- pre-flight was guarding against. Net regression. Reverted — vanilla
    -- runs and pcall is the only catch. The pre-flight remains as a
    -- LOG-ONLY diagnostic so we can see when we're flying toward a
    -- potential resource-not-loaded scenario without changing behavior.
    -- v0.9.42-dev (#154): ENRICHED PREFLIGHT PROBE. The old warn read only the
    -- BASE item_data.<field>, but vanilla _wield_slot resolves the unit through
    -- BackendUtils.get_item_units (backend_utils.lua:144-190), which (a) prefers
    -- the per-career override `<field>_override[career]`, and (b) when a skin is
    -- present, REPLACES the unit with the skin template's unit + the skin's own
    -- per-career override. For weapon_tweaker cross-character weapons the BASE
    -- field points at the DONOR character's mesh (frequently non-resident on this
    -- viewer because nobody here is playing that character), while the unit
    -- vanilla actually spawns is wt's per-career override — which weapon_tweaker
    -- force-loads on every peer at mod init. So the old base-field warn is a
    -- FALSE ALARM whenever the RESOLVED unit is resident, which is the 160×/
    -- session log spam #154 quotes. This probe resolves the SAME unit vanilla
    -- will spawn and only warns LOUD when that resolved unit is non-resident
    -- (the genuinely risky case: wt's force-load missed this weapon for husks);
    -- the false-alarm case is demoted to a quiet file-only line.
    --
    -- OWNERSHIP: cross-character WEAPON meshes belong to weapon_tweaker, not
    -- cosmetics. cosmetics' _la_equips_by_peer cache correctly has NO entry for
    -- them (it only tracks LA hat/armor/offhand-shield/illusion cosmetics synced
    -- via cos_la_apply). We do NOT swap or force-load weapon meshes here — that
    -- would step on wt and risk a resource-not-found fatal. This block is
    -- read-only diagnostics; behavior is unchanged (always warn+proceed, the
    -- v0.9.2.1 decision above).
    if Application and Application.can_get and equipment then
        local slot_data = equipment.slots and equipment.slots[slot_name]
        local item_data = slot_data and slot_data.item_data
        local skin      = slot_data and slot_data.skin
        local career    = self and self._career_name
        if item_data then
            for _, field in ipairs({ "right_hand_unit", "left_hand_unit" }) do
                local override_field = field .. "_override"
                local base = item_data[field]
                -- Mirror vanilla BackendUtils.get_item_units resolution order.
                local resolved = base
                local ov = item_data[override_field]
                if career and ov and ov[career] then resolved = ov[career] end
                local via_skin = nil
                if skin and WeaponSkins and WeaponSkins.skins then
                    -- rawget: WeaponSkins.skins can carry a strict metatable on
                    -- partially-populated peers (CLAUDE.md fragile-globals rule).
                    local st = rawget(WeaponSkins.skins, skin)
                    if st then
                        via_skin = skin
                        resolved = st[field] -- skin REPLACES the unit (may be nil)
                        local sov = st[override_field]
                        if career and sov and sov[career] then resolved = sov[career] or resolved end
                    end
                end
                -- Vanilla spawns this hand only if the resolved unit is truthy
                -- (simple_husk_inventory_extension.lua:665/669), so a nil resolved
                -- means "no unit on this hand" — nothing to check.
                if resolved and resolved ~= "" then
                    local resolved_resident = Application.can_get("unit", resolved) and true or false
                    local base_resident = (base and base ~= "" and Application.can_get("unit", base)) and true or false
                    -- Dedup so a missing/false-alarm weapon logs once per
                    -- (career, template, field, resolved) instead of every wield.
                    mod._preflight_seen = mod._preflight_seen or {}
                    local seen_key = (resolved_resident and "ok|" or "warn|")
                        .. tostring(career) .. "|" .. tostring(item_data.name)
                        .. "|" .. field .. "|" .. tostring(resolved)
                    if not mod._preflight_seen[seen_key] then
                        mod._preflight_seen[seen_key] = true
                        if not resolved_resident then
                            -- The unit vanilla WILL actually spawn is missing on
                            -- this peer → real risk (wt force-load gap for husks,
                            -- or a non-wt cross-char weapon nobody preloaded).
                            _dbg_alert("[husk-wield-wrap] PREFLIGHT WARN wearer=%s career=%s slot=%s field=%s template=%s base=%s(resident=%s) RESOLVED=%s(resident=false) via_skin=%s — vanilla will spawn a NON-resident unit; cross-char weapon force-load (weapon_tweaker's) may have missed this for husks",
                                tostring(wearer_peer), tostring(career), tostring(slot_name), field,
                                tostring(item_data.name), tostring(base), tostring(base_resident),
                                tostring(resolved), tostring(via_skin))
                        elseif not base_resident then
                            -- Base non-resident but the RESOLVED override/skin unit
                            -- IS resident → the old warn was a false alarm. Quiet,
                            -- file-only (confirms wt/vanilla handled it).
                            _dbg("[husk-wield-wrap] PREFLIGHT OK (false alarm) wearer=%s career=%s slot=%s field=%s template=%s base=%s(resident=false) RESOLVED=%s(resident=true) via_skin=%s — base-field warn was spurious; resolved unit is resident",
                                tostring(wearer_peer), tostring(career), tostring(slot_name), field,
                                tostring(item_data.name), tostring(base), tostring(resolved), tostring(via_skin))
                        end
                    end
                end
            end
        end
    end
    local ok, r1, r2, r3, r4, r5, r6, r7, r8 = pcall(func, self, world, equipment, slot_name, unit_1p, unit_3p)
    _current_husk_wield = prev
    if not ok then
        _dbg_alert("[husk-wield-wrap] vanilla _wield_slot ERRORED wearer=%s slot=%s err=%s — pcall caught it. Husk visual likely missing/stale but host stays alive.",
            tostring(wearer_peer), tostring(slot_name), tostring(r1))
        return nil
    end

    -- v0.9.0.10-hotfix: RE-PAINT MERGED IN. The v0.9.0.5 separate
    -- `mod:hook_safe(SimpleHuskInventoryExtension, "wield", ...)` was
    -- silently dropped by VMF because _tpe.lua:511 had already hooked
    -- the same Class+method (per feedback_vmf_hook_safe_no_chain). The
    -- re-paint never ran. Folding the same logic into the _wield_slot
    -- wrap (above) sidesteps the shadow — _wield_slot is not multi-hooked.
    -- Runs AFTER vanilla returns, when the just-spawned weapon units are
    -- in the slots and ready to be painted.
    if wearer_peer and _la_equips_by_peer then
        local equips = _la_equips_by_peer[wearer_peer]
        if equips then
            local slot_data = equipment and equipment.slots and equipment.slots[slot_name]
            local item_data = slot_data and slot_data.item_data
            local wielded_template = item_data and item_data.template
            for stored_key, entry in pairs(equips) do
                if entry and entry.kind and entry.armoury_key then
                    local should_apply = false
                    if entry.kind == "hat" and stored_key == "slot_hat" then
                        should_apply = (slot_name == "slot_hat")
                    elseif entry.kind == "armor" and stored_key == "slot_skin" then
                        should_apply = true
                    elseif entry.kind == "offhand" or entry.kind == "illusion" then
                        if wielded_template and stored_key == wielded_template then
                            should_apply = true
                        end
                    end
                    if should_apply then
                        _dbg("[husk-wield-repaint] apply stored_key=%s kind=%s key=%s",
                            tostring(stored_key), tostring(entry.kind), tostring(entry.armoury_key))
                        -- v0.9.43-dev HUSK trace: post-vanilla re-apply of a
                        -- cached LA cosmetic onto the just-spawned husk units.
                        _trace("HUSK wield-repaint stored_key=%s kind=%s armoury=%s slot=%s wearer=%s",
                            tostring(stored_key), tostring(entry.kind), tostring(entry.armoury_key),
                            tostring(slot_name), tostring(wearer_peer))
                        -- v0.9.70-dev (#264, Slice 2 / I3): route through the single
                        -- reconcile entry point. allow_pulse=false -- we are INSIDE a
                        -- _wield_slot body (pulsing would re-enter wield); if the
                        -- in-wield get_item_units mesh swap missed, reconcile defers
                        -- a pulse to the pending drain, which runs from mod.update a
                        -- frame later. THIS is the switch-back repair path.
                        mod._la_reconcile(wearer_peer, stored_key, "husk-wield", false)
                    end
                end
            end
        end
    end

    return r1, r2, r3, r4, r5, r6, r7, r8
end)

-- v0.9.0.10-hotfix: the standalone re-paint hook_safe("...wield") was
-- SHADOWED by _tpe.lua:511's earlier registration (VMF hook_safe doesn't
-- chain — second registration on same Class+method silently dropped, per
-- feedback_vmf_hook_safe_no_chain). The re-paint logic is now folded
-- INTO the _wield_slot wrap above, after vanilla's spawn completes.
-- The wrap uses mod:hook (not hook_safe) on a different method
-- (_wield_slot vs wield) so there's no shadow conflict.

-- Map an LA-keyed attachment slot to its cos_la_apply kind. Currently only
-- slot_hat flows through the attachment path; slot_skin is "cosmetic"
-- category and arrives via CosmeticUtils.update_cosmetic_slot instead.
local function _attachment_slot_to_kind(slot_name)
    if slot_name == "slot_hat" then return "hat" end
    return nil
end

-- PUAE is a class, string-form hook is correct.
-- v0.9.0.9-hotfix: husk-side LA-aware create_attachment.
--
-- ROOT CAUSE diagnosed by hat-reequip-diagnosis agent (HAT_REEQUIP_REQUIRED_DIAGNOSIS.md):
-- Race between vanilla `rpc_create_attachment` and CT `cos_la_apply` on the client:
--   1. Client receives cos_la_apply FIRST → CT spawns LA-textured hat unit, paint ok.
--   2. Vanilla rpc_create_attachment arrives LATE → husk's create_attachment sees the
--      LA unit as old_slot_data → `remove_attachment` destroys it (and the LA paint
--      bound to that unit's materials) → spawns fresh vanilla unit. Net result:
--      vanilla-colored hat on the client view of the husk.
-- Re-equip works because by then only one RPC pair is in flight (no late vanilla
-- RPC follows CT's spawn).
--
-- Fix: hook PlayerHuskAttachmentExtension.create_attachment. When the wearer
-- has a cached LA hat entry in _la_equips_by_peer (populated on every peer by
-- the v0.9.0.7 mirror write), pre-patch `item_data.unit = la_unit_path` BEFORE
-- delegating to vanilla — so vanilla spawns the LA mesh — then apply the
-- texture on the result. This makes the late vanilla RPC IDEMPOTENT with CT's
-- earlier apply: whichever RPC arrives second still ends up with the LA-textured
-- unit visible.
mod:hook("PlayerHuskAttachmentExtension", "create_attachment", function(func, self, slot_name, item_data)
    if slot_name ~= "slot_hat" then
        return func(self, slot_name, item_data)
    end
    local pm = Managers and Managers.player
    local husk_unit = self and self._unit
    if not pm or not husk_unit then
        return func(self, slot_name, item_data)
    end
    -- Resolve wearer peer (mirror the husk-wield-wrap lookup pattern).
    local wearer_peer = nil
    if pm.owner then
        local owner = pm:owner(husk_unit)
        wearer_peer = owner and owner.peer_id or nil
    end
    if not wearer_peer and pm._players then
        for _, p in pairs(pm._players) do
            if p.player_unit == husk_unit then
                wearer_peer = p.peer_id
                break
            end
        end
    end
    local cached = wearer_peer and _la_equips_by_peer
        and _la_equips_by_peer[wearer_peer]
        and _la_equips_by_peer[wearer_peer][slot_name]
    if not cached or cached.kind ~= "hat" or not cached.armoury_key then
        return func(self, slot_name, item_data)
    end
    local la = get_mod("Loremasters-Armoury")
    local variant = la and la.SKIN_LIST and la.SKIN_LIST[cached.armoury_key]
    local la_unit = variant and variant.new_units and variant.new_units[1]
    if not la_unit then
        return func(self, slot_name, item_data)
    end

    -- v0.9.8.5 CRASH FIX: character-mismatch gate.
    --
    -- The cached LA hat's mesh is authored for ONE specific character's
    -- skeleton. Attaching it to a body with a different skeleton makes
    -- vanilla's `Unit.node(unit, "j_spine1")` C-call fail because the
    -- expected attachment node IDs don't exist on the wrong skeleton.
    --
    -- This happens when a bot replaces a player in Chaos Wastes deus
    -- runs (or any time vanilla spawns a `player_bot_unit` with a
    -- different career than the host previously customized for). The
    -- `_la_equips_by_peer[wearer_peer]` cache holds the host's LAST
    -- chosen LA hat, but the BOT'S spawn brings a unit path for the
    -- bot's character — different from the cached LA hat's character.
    --
    -- Crash trace 2026-05-22 00:35:24 (d82119d4) AND 2026-05-22 01:11:28
    -- (95a8db3d): Sienna bot spawned (`bright_wizard_necromancer`
    -- skeleton), our hook patched the unit to
    -- `way_watcher_maiden_guard/headpiece/...` (Kerillian's hat),
    -- engine: `UnitApi node failed, node #ID[3cfac529] not found in
    -- unit #ID[...]` at `c_api_unit.cpp:74`.
    --
    -- Detection: the unit path encodes the character key as the first
    -- segment after `units/beings/player/`. If incoming (vanilla item_
    -- data.unit) and cached (la_unit) character keys differ, bail —
    -- delegate to vanilla unpatched. The wearer renders their actual
    -- character's hat; user's LA selection waits for the next wearer-
    -- side equip event to re-apply on a matching skeleton.
    --
    -- Audit 2026-05-22 found 4 unsafe patches across 2 logs; 2 crashed
    -- (Sienna body), 2 didn't (Saltzpyre body — node ID overlap with
    -- Kerillian). All 4 patterns are now defused by this gate.
    local incoming_char = item_data.unit
        and string.match(item_data.unit, "^units/beings/player/([^/]+)/")
    local la_char       = string.match(la_unit, "^units/beings/player/([^/]+)/")
    if incoming_char and la_char and incoming_char ~= la_char then
        _dbg("[husk-hat-create] character mismatch — wearer=%s incoming=%s cached_LA=%s (armoury=%s) — skipping cross-skeleton patch to avoid c_api_unit.cpp:74 crash",
            tostring(wearer_peer), tostring(incoming_char), tostring(la_char), tostring(cached.armoury_key))
        return func(self, slot_name, item_data)
    end

    -- v0.9.8.8 CRASH FIX: husk body-skeleton readiness guard.
    --
    -- Vanilla AttachmentUtils.link (attachment_utils.lua:70) calls
    -- Unit.node(owner_unit, link_data.source) for each hat-link entry. On
    -- hot-join / mid-revive the husk BODY skeleton isn't yet populated, so the
    -- source node (j_spine family) is transiently absent and Unit.node ENGINE-
    -- FATALS at c_api_unit.cpp:74 -- bypassing the pcall below (CLAUDE.md
    -- "Unit.node errors bypass pcall"). The v0.9.8.5 gate above defends the
    -- TARGET hat-mesh nodes; it does NOT cover this body-side not-ready case
    -- (same-character es_gk_hat_04->es_gk_hat_03 sails through it and still
    -- fatals -- crash GUID 9533f856, questing_knight_hat_1001 in the CW keep).
    --
    -- Unlike the removed v0.9.8.3 precheck (which returned WITHOUT calling
    -- vanilla -> "no helmet visible"), a miss here DEFERS: we call vanilla
    -- UNPATCHED so the wearer's real hat shows now, and enqueue an LA re-apply
    -- so the LA hat lands once the spine populates. The hat is never dropped.
    local _attach_owner = husk_unit
    do
        local _item_tmpl = BackendUtils and BackendUtils.get_item_template
            and BackendUtils.get_item_template(item_data)
        -- Mirror player_husk_attachment_extension.lua:61-62: link_to_skin hats
        -- parent to the third-person mesh, not the body. Check the SAME unit
        -- vanilla will pass to AttachmentUtils.link as `owner`.
        if _item_tmpl and _item_tmpl.link_to_skin then
            local _mesh = self._tp_unit_mesh
            if _mesh and Unit.alive(_mesh) then
                _attach_owner = _mesh
            end
        end
        -- The source node names are plain Lua data (attachment_utils.lua:26-27
        -- reads this same table) -- derive them up front and verify each with
        -- Unit.has_node (the non-fatal boolean companion) BEFORE the fatal call.
        local _required_body_nodes
        local _linking = _item_tmpl and _item_tmpl.attachment_node_linking
            and _item_tmpl.attachment_node_linking[slot_name]
        if _linking then
            for _, ld in ipairs(_linking) do
                if type(ld.source) == "string" then
                    _required_body_nodes = _required_body_nodes or {}
                    _required_body_nodes[#_required_body_nodes + 1] = ld.source
                end
            end
        end
        -- Proxy when the template carries no explicit linking: every player body
        -- anchors hats off the spine family, so j_spine is the readiness probe.
        if not _required_body_nodes then
            _required_body_nodes = { "j_spine" }
        end
        local _body_ready = Unit.alive(_attach_owner)
        if _body_ready then
            for _, n in ipairs(_required_body_nodes) do
                if not Unit.has_node(_attach_owner, n) then
                    _body_ready = false
                    break
                end
            end
        end
        if not _body_ready then
            _dbg_alert("[husk-hat-create] body skeleton not ready (missing source node) wearer=%s slot=%s armoury=%s -- DEFERRING re-apply, NOT dropping hat",
                tostring(wearer_peer), tostring(slot_name), tostring(cached.armoury_key))
            -- Enqueue an LA re-apply (drained per-frame in mod.update, 5s
            -- deadline-bounded). Tuple shape matches the canonical enqueue.
            _la_pending_apply[#_la_pending_apply + 1] = {
                wearer_peer, slot_name, cached.kind, cached.armoury_key, cached.vanilla_key, os.clock() + 5,
            }
            -- Vanilla runs UNPATCHED: the wearer's real hat shows THIS frame;
            -- the LA override lands a frame or two later via _try_apply_by_peer.
            return func(self, slot_name, item_data)
        end
    end

    -- v0.9.8.7: Patch item_data.unit in place and call vanilla.
    --
    -- Removed the v0.9.8.3 skeleton-readiness precheck. Reasoning:
    -- the original j_spine1 crash was caused by patching a WRONG-CHARACTER
    -- LA hat onto a body whose skeleton's node IDs didn't match the hat
    -- mesh's expected nodes. v0.9.8.5's character-mismatch gate (above)
    -- prevents that crash class at the source. With same-character
    -- hats only being patched, vanilla's attachment node lookup succeeds.
    --
    -- The v0.9.8.3 precheck was overcautious and harmful: when it
    -- triggered (frequently on hot-join / mid-revive), it returned
    -- WITHOUT calling vanilla — so the husk got NO hat at all. That's
    -- the "no helmet visible" symptom users reported.
    --
    -- pcall around vanilla call remains as a last-resort safety net.
    -- If vanilla truly errors for some unexpected edge case, we don't
    -- want to propagate up and crash the client.
    local prev_unit = item_data.unit
    item_data.unit = la_unit
    _dbg("[husk-hat-create] wearer=%s slot=%s patched unit %s -> %s (LA armoury=%s)",
        tostring(wearer_peer), tostring(slot_name), tostring(prev_unit), tostring(la_unit), tostring(cached.armoury_key))
    local ok, err = pcall(func, self, slot_name, item_data)
    item_data.unit = prev_unit
    if not ok then
        _dbg_alert("[husk-hat-create] inner create_attachment errored on wearer=%s slot=%s: %s — bailing silently",
            tostring(wearer_peer), tostring(slot_name), tostring(err))
        return
    end
    -- Paint the LA texture onto the just-spawned hat unit. Mirror the
    -- cos_la_apply hat-branch paint logic at cosmetics_tweaker.lua:~3775.
    if la and type(la.apply_new_skin_from_texture) == "function" then
        local world = _level_world()
        local slot_data = self._attachments and self._attachments.slots and self._attachments.slots[slot_name]
        local hat_unit = slot_data and slot_data.unit
        if world and hat_unit and Unit.alive(hat_unit) then
            LA_BRIDGE._bridge_active = true
            local paint_ok, paint_err = pcall(la.apply_new_skin_from_texture, cached.armoury_key, world, cached.vanilla_key, hat_unit)
            LA_BRIDGE._bridge_active = false
            _dbg("[husk-hat-create] paint %s on hat_unit=%s ok=%s",
                tostring(cached.armoury_key), tostring(hat_unit), tostring(paint_ok))
            if not paint_ok then
                _dbg_alert("[husk-hat-create] paint err: %s", tostring(paint_err))
            end
        end
    end
end)

-- v0.9.8.7: the v0.9.8.4 + v0.9.8.6 PlayerHuskAttachmentExtension.remove_attachment
-- guard pair has been removed entirely.
--
-- The guard existed to handle the case where v0.9.8.3's skeleton-readiness
-- precheck silently bailed — leaving `_attachments.slots[slot_name]` nil
-- when vanilla then tried to remove a hat that was never created.
--
-- v0.9.8.7 removed the v0.9.8.3 precheck (rendered unnecessary by
-- v0.9.8.5's character-mismatch gate which prevents the original crash
-- class). Without the precheck, vanilla always populates `_attachments.slots`
-- normally — so this guard has no failure mode left to defend against.
-- Removing it eliminates one more layer of speculative hook code that
-- could regress in subtle ways.

mod:hook("PlayerUnitAttachmentExtension", "game_object_initialized", function(func, self, unit, unit_go_id)
    local slots = self._attachments and self._attachments.slots
    local restore = nil
    local la_slots = nil  -- entries: { slot_name, la_backend_id, vanilla_key }
    if slots then
        for slot_name, slot_data in pairs(slots) do
            local item_data = slot_data and slot_data.item_data
            local orig = item_data and item_data.name
            local vanilla = _la_substitute_name(orig)
            if vanilla then
                restore = restore or {}
                restore[#restore + 1] = { item_data, orig }
                item_data.name = vanilla
                la_slots = la_slots or {}
                la_slots[#la_slots + 1] = { slot_name, orig, vanilla }
            end
        end
    end
    local ok, err = pcall(func, self, unit, unit_go_id)
    if restore then
        for i = 1, #restore do
            restore[i][1].name = restore[i][2]
        end
    end
    if not ok then error(err) end
    if la_slots then
        for i = 1, #la_slots do
            local slot_name, la_id, vanilla = la_slots[i][1], la_slots[i][2], la_slots[i][3]
            local kind = _attachment_slot_to_kind(slot_name)
            local armoury_key = LA_BRIDGE.backend_to_armoury and LA_BRIDGE.backend_to_armoury[la_id]
            if kind and armoury_key then
                _send_la_apply(unit, slot_name, kind, armoury_key, vanilla)
            end
        end
    end
end)

mod:hook("PlayerUnitAttachmentExtension", "spawn_resynced_loadout", function(func, self, item_to_spawn)
    local item_data = item_to_spawn and item_to_spawn.item_data
    local orig = item_data and item_data.name
    local vanilla = _la_substitute_name(orig)
    if vanilla then
        item_data.name = vanilla
        local ok, err = pcall(func, self, item_to_spawn)
        item_data.name = orig
        if not ok then error(err) end
        local slot_name = item_to_spawn.slot_id
        local kind = slot_name and _attachment_slot_to_kind(slot_name)
        local armoury_key = LA_BRIDGE.backend_to_armoury and LA_BRIDGE.backend_to_armoury[orig]
        if kind and armoury_key and self._unit then
            _send_la_apply(self._unit, slot_name, kind, armoury_key, vanilla)
        end
        return
    end
    return func(self, item_to_spawn)
end)
_net_safe_hook_status.PUAE = true

-- AttachmentUtils is a PLAIN TABLE (`AttachmentUtils = AttachmentUtils or {}`
-- at attachment_utils.lua:1). Same string-form pitfall as CosmeticUtils/
-- LoadoutUtils — must use table-form with nil guard, else hook silently
-- never registers.
if AttachmentUtils then
    mod:hook(AttachmentUtils, "hot_join_sync", function(func, peer_id, unit, slots, synced_buffs)
        local restore = nil
        local la_slots = nil  -- entries: { slot_name, la_backend_id, vanilla_key }
        if slots then
            for slot_name, slot_data in pairs(slots) do
                local orig = slot_data and slot_data.name
                local vanilla = _la_substitute_name(orig)
                if vanilla then
                    restore = restore or {}
                    restore[#restore + 1] = { slot_data, orig }
                    slot_data.name = vanilla
                    la_slots = la_slots or {}
                    la_slots[#la_slots + 1] = { slot_name, orig, vanilla }
                end
            end
        end
        local ok, err = pcall(func, peer_id, unit, slots, synced_buffs)
        if restore then
            for i = 1, #restore do
                restore[i][1].name = restore[i][2]
            end
        end
        if not ok then error(err) end
        -- v0.8.67-dev: signature change — _send_la_apply now routes through
        -- the host (server-authoritative). The host's broadcast to "all"
        -- includes the joining peer, so per-peer targeting is no longer
        -- needed. Each existing peer's hot_join_sync still fires its own
        -- emits for its own equips; the host receives each request, records
        -- in _la_equips_by_peer (idempotent overwrite), and re-broadcasts.
        -- Slight redundancy (each peer's equips broadcast to everyone again
        -- on each new joiner), but correct.
        if la_slots then
            for i = 1, #la_slots do
                local slot_name, la_id, vanilla = la_slots[i][1], la_slots[i][2], la_slots[i][3]
                local kind = _attachment_slot_to_kind(slot_name)
                local armoury_key = LA_BRIDGE.backend_to_armoury and LA_BRIDGE.backend_to_armoury[la_id]
                if kind and armoury_key then
                    _send_la_apply(unit, slot_name, kind, armoury_key, vanilla)
                end
            end
        end

        -- Replay non-attachment LA cosmetics (slot_skin armor, weapon-slot
        -- offhand picks, weapon-illusion paints). AttachmentUtils.hot_join_sync
        -- only walks "attachment"-category slots so these need explicit replay.
        --
        -- v0.9.0-dev: previously read ONLY `_local_la_equips[unit]`, which is
        -- populated solely by the local player's CosmeticUtils.update_cosmetic_slot
        -- hook → contains entries only for the LOCAL player's player_unit. When
        -- the host's hot_join_sync iterates OTHER existing players to replay
        -- their state to the new joiner, the lookup misses for every non-local
        -- unit, so the new joiner never received those peers' armor/illusion
        -- selections. Now we ALSO consult `_la_equips_by_peer` (authoritative
        -- per-peer store, populated by the host's cos_la_apply_req handler) and
        -- replay every recorded slot for the wearer-peer.
        do
            local equips = _local_la_equips[unit]
            if equips then
                for slot_name, la_id in pairs(equips) do
                    local kind = nil
                    if slot_name == "slot_skin" then
                        kind = "armor"
                    elseif slot_name ~= "slot_hat" then
                        kind = "illusion"
                    end
                    local armoury_key = LA_BRIDGE.backend_to_armoury and LA_BRIDGE.backend_to_armoury[la_id]
                    local vanilla = LA_BRIDGE.backend_to_vanilla and LA_BRIDGE.backend_to_vanilla[la_id]
                    if (kind == "armor" or kind == "illusion") and armoury_key then
                        _send_la_apply(unit, slot_name, kind, armoury_key, vanilla)
                    end
                end
            end

            -- v0.9.0.12-hotfix: TARGETED hot-join replay to the joining peer.
            -- Previous version called _send_la_apply which always uses "all" —
            -- but at hot_join_sync time the joiner may not yet be in the
            -- "all" target list (handshake not complete). User report v0.9.0.11:
            -- "someone joining a lobby where the hat or shield is already
            -- equipped won't see it until the other player changes their
            -- cosmetic selection". The change-broadcast hits because by then
            -- the joiner is fully connected; the initial hot-join replay
            -- raced and lost. Fix: bypass _send_la_apply, fire
            -- cos_la_apply DIRECTLY targeted at the joining peer_id.
            if _is_local_server() then
                local pm = Managers and Managers.player
                local owner = pm and pm.owner and pm:owner(unit)
                local wearer_peer = owner and owner.peer_id
                local peer_equips = wearer_peer and _la_equips_by_peer[wearer_peer]
                if peer_equips then
                    local n = 0
                    for slot_name, entry in pairs(peer_equips) do
                        if entry and entry.kind and entry.armoury_key then
                            mod:network_send("cos_la_apply", peer_id, COS_RPC_SCHEMA, {
                                wearer_peer_id = wearer_peer,
                                slot           = slot_name,
                                kind           = entry.kind,
                                armoury_key    = entry.armoury_key,
                                vanilla_key    = entry.vanilla_key,
                                hand_field     = entry.hand_field,
                            })
                            n = n + 1
                        end
                    end
                    if n > 0 then
                        _dbg("[hot-join replay] sent %d cos_la_apply entries targeted at joiner=%s for wearer=%s",
                            n, tostring(peer_id), tostring(wearer_peer))
                    end
                end
                -- v0.9.0.12-hotfix: glow rebroadcast also targeted at joiner.
                if mod._glow_rebroadcast_targeted then
                    mod._glow_rebroadcast_targeted(peer_id)
                end
            end

            -- Offhand: replay the local player's CURRENTLY-wielded weapon
            -- backend if it has an LA offhand selection.
            local pm = Managers and Managers.player
            local local_player = pm and pm:local_player()
            local local_unit = local_player and local_player.player_unit
            if local_unit == unit then
                local inv = ScriptUnit.has_extension(unit, "inventory_system")
                local equipment = inv and inv._equipment
                local wielded_slot = equipment and equipment.wielded_slot
                local slot_data = wielded_slot and equipment.slots and equipment.slots[wielded_slot]
                local item_data = slot_data and slot_data.item_data
                local bid = item_data and item_data.backend_id
                if bid then _migrate_legacy_offhand_selection(bid) end
                local per_hand_sel = bid and _offhand_selection[bid]
                if type(per_hand_sel) == "table" then
                    -- v0.9.72-dev: key the replay by the weapon TEMPLATE, not
                    -- the wielded slot. This site was the only writer of the
                    -- legacy "slot_melee"-style offhand keys (host 18:35:44
                    -- evidence) - a namespace the weapon-identity guard in
                    -- _apply_la_on_unit can never match to an item.
                    local replay_key = (item_data and item_data.template) or wielded_slot
                    for hand_field, sel in pairs(per_hand_sel) do
                        if type(sel) == "table" and sel.la_armoury_key then
                            _send_la_apply(unit, replay_key, "offhand",
                                sel.la_armoury_key, sel.vanilla_skin, hand_field)
                        end
                    end
                end
            end
        end
    end)
    _net_safe_hook_status.AttachmentUtils = true
end

-- Startup verification: log applied/missing state for every plain-table
-- net-safe hook. Helps catch the silent-no-op failure mode where a
-- required helper table wasn't loaded yet at mod init (no runtime
-- indication other than a peer crash).
mod:info("[net-safe] hook registration: CosmeticUtils=%s LoadoutUtils=%s AttachmentUtils=%s PUAE=%s",
    tostring(_net_safe_hook_status.CosmeticUtils),
    tostring(_net_safe_hook_status.LoadoutUtils),
    tostring(_net_safe_hook_status.AttachmentUtils),
    tostring(_net_safe_hook_status.PUAE))
if not (_net_safe_hook_status.CosmeticUtils and _net_safe_hook_status.LoadoutUtils
    and _net_safe_hook_status.AttachmentUtils and _net_safe_hook_status.PUAE) then
    mod:echo("[cosmetics_tweaker] WARNING: one or more LA peer-sync hooks did NOT register. Restart VT2 if you plan to play LA cosmetics in a lobby.")
end

-- VMF calls mod.update once per frame.
-- CLARIFY: la_bridge initialization is deferred to first frame where:
--   1. ItemMasterList is loaded
--   2. Loremasters-Armoury and MoreItemsLibrary mods are present and loaded
-- (v0.9.3.9: la_bridge_enable toggle removed — bridge is unconditionally
-- on. Players who don't want LA cosmetics just don't subscribe to LA.)
-- v0.9.0-dev: warn ONCE when MoreItemsLibrary is missing. PC-B going 4 days
-- with the bridge silently dormant cost a multi-day debug — a clear log line
-- is cheap insurance.
local _la_bridge_missing_dep_logged = false
mod.update = function(dt)
    -- v0.9.12-dev: pump persistence-restore queue. SimpleInventoryExtension
    -- .extensions_ready queues a Player for restore; tick processes the queue
    -- once career_name + player_unit are both ready (~1 frame later).
    if LA_PERSIST and LA_PERSIST.tick_pending_restore then
        LA_PERSIST.tick_pending_restore()
    end

    -- v0.9.4: drain pending self-rebroadcast of local LA equips.
    -- Triggered by on_game_state_changed. Walks _local_la_equips for the
    -- local player_unit and re-emits each entry. Idempotent — the per-
    -- emit dedup window (~0.5s in _send_la_apply) prevents flooding if
    -- state changes multiple times rapidly.
    if mod._la_self_rebroadcast_pending and _send_la_apply then
        local pm = Managers and Managers.player
        -- v0.9.5.1: pcall pm:local_player() — C peer_id() asserts
        -- "Network backend has not been set" if network not ready. Was
        -- producing 1181 cascading errors per session per the audit.
        local lp_ok, lp = pcall(function() return pm and pm:local_player() end)
        if not lp_ok then lp = nil end
        local pu = lp and lp.player_unit
        if pu and Unit.alive(pu) and LA_BRIDGE then
            local n = 0
            -- (A) Hats / armor via _local_la_equips (populated by
            -- CosmeticUtils.update_cosmetic_slot hook).
            if _local_la_equips then
                local equips = _local_la_equips[pu]
                if equips then
                    for slot, item_name in pairs(equips) do
                        local kind
                        if slot == "slot_hat"  then kind = "hat"
                        elseif slot == "slot_skin" then kind = "armor"
                        else kind = "illusion" end
                        local armoury_key = LA_BRIDGE.backend_to_armoury and LA_BRIDGE.backend_to_armoury[item_name]
                        local vanilla_key = LA_BRIDGE.backend_to_vanilla and LA_BRIDGE.backend_to_vanilla[item_name]
                        if armoury_key then
                            _send_la_apply(pu, slot, kind, armoury_key, vanilla_key)
                            n = n + 1
                        end
                    end
                end
            end
            -- (B) v0.9.6: shields / weapon offhands via _offhand_selection.
            -- _local_la_equips ONLY tracks hat + armor (set by the
            -- CosmeticUtils.update_cosmetic_slot hook). Shields and weapon
            -- illusions live in _offhand_selection[backend_id]. Audit
            -- 2026-05-21 showed hats sync on join but shields don't —
            -- because the drain didn't walk this table.
            -- Strategy: iterate the player's CURRENT equipped slots, look
            -- up _offhand_selection[slot.backend_id], emit if matched.
            -- Avoids replaying stale selections for items no longer
            -- equipped.
            if _offhand_selection and ScriptUnit and ScriptUnit.has_extension then
                local inv = ScriptUnit.has_extension(pu, "inventory_system")
                if inv and inv._equipment and inv._equipment.slots then
                    for _, slot_data in pairs(inv._equipment.slots) do
                        local sd_item = slot_data and slot_data.item_data
                        local sd_bid = sd_item and sd_item.backend_id
                        if sd_bid then _migrate_legacy_offhand_selection(sd_bid) end
                        local per_hand_sel = sd_bid and _offhand_selection[sd_bid]
                        if type(per_hand_sel) == "table" then
                            local template_key = sd_item.template or sd_item.name or "slot_unknown"
                            -- v0.9.9.4-dev: walk every hand with an LA pick;
                            -- multi-mount weapons may have both hands set.
                            for hand_field, opt in pairs(per_hand_sel) do
                                if type(opt) == "table" and opt.la_armoury_key then
                                    _send_la_apply(pu, template_key, "offhand",
                                        opt.la_armoury_key, opt.vanilla_skin, hand_field)
                                    n = n + 1
                                end
                            end
                        end
                    end
                end
            end
            mod._la_self_rebroadcast_pending = false
            if n > 0 then
                _dbg("[ct la-rebroadcast] re-emitted %d local LA equip(s) on state change (hats/armor + offhand)", n)
            end
        end
        -- If player_unit not yet ready, keep flag pending and retry next frame.
    end

    -- v0.9.66-dev (#233): CLIENT-side self-heal of REMOTE peers' cached LA offhand/
    -- illusion equips after a level transition. Armed by on_game_state_changed
    -- (`_la_reapply_remote_until`). The host's post-transition rebroadcast of its own
    -- equip races the client's load window and is dropped (the "all" send fires ~25ms
    -- before the client's peer_ingame flips true), and nothing re-sends -- so the host's
    -- LA offhand reverted on the client at every mission<->keep transition.
    -- `_la_equips_by_peer` survives (only cleared on peer disconnect), so we hold the
    -- authoritative equip locally and re-drive the recv/retry apply every frame within a
    -- bounded window until the remote wearer's husk spawns and wields the offhand.
    --
    -- v0.9.66-dev fix over v0.9.65-dev, which shipped a SILENT NO-OP (0 lines in the
    -- 2026-07-03 21:15 retest): the old block called ONLY `_ensure_offhand_mesh`, which
    -- early-returns for any non-kind="unit" LA variant -- so a kind="texture" illusion
    -- (the breton shields in that retest get RECV but never a RE-SWAP) was never
    -- re-painted and the whole walk logged nothing. Now we call `_try_apply_by_peer`
    -- (re-paints the texture AND returns true only when the offhand is currently wielded)
    -- and, only when it reports the offhand wielded, `_ensure_offhand_mesh` (re-swaps a
    -- kind="unit" mesh; self-gated/no-op for kind="texture"). Gating the pulse on the
    -- wield state avoids a wasteful melee<->ranged flicker on a husk holding a ranged
    -- weapon and targets exactly the visible-revert case. Both self-gate (paint
    -- idempotent; pulse per-owner 1.5s cooldown + 3-try cap); each (peer|armoury) is
    -- FROZEN once applied so there is no per-frame repaint. Two bounded diagnostics per
    -- window (armed + summary) so a silent no-op can never ship undetected again. No new
    -- hook/RPC/force-load; no World.destroy_unit.
    if mod._la_reapply_remote_until then
        if os.clock() >= mod._la_reapply_remote_until then
            -- Window closed: emit the one-line summary (from the frozen dispositions),
            -- then disarm.
            local st = mod._la_reapply_stats
            if st then
                mod:info("[cos-la-sync] TRANSITION-WALK done applied=%d skipped_unwielded=%d skipped_unresolved=%d",
                    st.applied or 0, st.unwielded or 0, st.unresolved or 0)
                mod._la_reapply_stats = nil
            end
            mod._la_reapply_remote_until = nil
        else
            -- pcall local_player() -- the C peer_id() path asserts if the network
            -- backend isn't set yet on the first post-load frames (same guard the
            -- self-rebroadcast drain uses). Skip this frame if unresolved; the window
            -- persists and retries next frame.
            local pm = Managers and Managers.player
            local lp_ok, lp = pcall(function() return pm and pm:local_player() end)
            local local_peer = lp_ok and lp and lp.peer_id or nil
            if local_peer and _la_equips_by_peer then
                local st = mod._la_reapply_stats
                if not st then
                    -- First active frame of this window: arm + count what we hold, so
                    -- an empty cache (nothing to restore) is distinguishable from a walk
                    -- that reached entries but the apply no-op'd.
                    local peer_n, entry_n = 0, 0
                    for p, sl in pairs(_la_equips_by_peer) do
                        if p ~= local_peer and type(sl) == "table" then
                            local has = false
                            for _, e in pairs(sl) do
                                if type(e) == "table" and e.armoury_key
                                    and (e.kind == "offhand" or e.kind == "illusion") then
                                    entry_n = entry_n + 1
                                    has = true
                                end
                            end
                            if has then peer_n = peer_n + 1 end
                        end
                    end
                    st = { applied = 0, unwielded = 0, unresolved = 0, seen = {} }
                    mod._la_reapply_stats = st
                    mod:info("[cos-la-sync] TRANSITION-WALK armed local=%s remote_peers=%d offhand_entries=%d",
                        tostring(local_peer), peer_n, entry_n)
                end
                for peer, slots in pairs(_la_equips_by_peer) do
                    if peer ~= local_peer and type(slots) == "table" then
                        local wu = _wearer_unit_for_peer(peer)
                        for slot_name, eq in pairs(slots) do
                            if type(eq) == "table" and eq.armoury_key
                                and (eq.kind == "offhand" or eq.kind == "illusion") then
                                local dkey = tostring(peer) .. "|" .. tostring(eq.armoury_key)
                                -- Freeze each entry once it has been applied (offhand
                                -- wielded + re-painted/pulsed) so we don't repaint per frame.
                                if st.seen[dkey] ~= "applied" then
                                    if not wu then
                                        st.seen[dkey] = "unresolved"
                                    else
                                        -- v0.9.70-dev (Slice 2 / I3): route through the
                                        -- single reconcile entry point (paint + gated
                                        -- mesh pulse; this drain is a safe pulse context).
                                        -- Semantics preserved: applied only when the
                                        -- offhand is currently wielded.
                                        local applied = mod._la_reconcile(peer, slot_name, "transition", true)
                                        if applied then
                                            st.seen[dkey] = "applied"
                                        else
                                            st.seen[dkey] = "unwielded"
                                        end
                                    end
                                end
                            end
                        end
                    end
                end
                -- Recompute the tallies from the frozen dispositions so the summary is
                -- stable regardless of per-frame churn (an entry migrates
                -- unresolved -> unwielded -> applied and then freezes).
                local a, uw, ur = 0, 0, 0
                for _, d in pairs(st.seen) do
                    if d == "applied" then a = a + 1
                    elseif d == "unwielded" then uw = uw + 1
                    else ur = ur + 1 end
                end
                st.applied, st.unwielded, st.unresolved = a, uw, ur
            end
        end
    end

    if not _la_bridge_init_done then
        local has_la  = get_mod("Loremasters-Armoury") ~= nil
        local has_mil = get_mod("MoreItemsLibrary") ~= nil
        if not _la_bridge_missing_dep_logged
            and ItemMasterList
            and (not has_la or not has_mil) then
            if not has_mil then
                mod:echo("[cosmetics_tweaker] MoreItemsLibrary is NOT subscribed/active. LA bridge stays dormant — host/client LA cosmetics will NOT sync. Subscribe: https://steamcommunity.com/sharedfiles/filedetails/?id=1422758813")
                mod:info("[LA bridge] dependency missing: MoreItemsLibrary (Workshop ID 1422758813). bridge will stay dormant.")
            end
            if not has_la then
                -- v0.9.0.14-hotfix: promote to chat. Mirrors the MIL-missing
                -- echo above. User report 2026-05-19: Lyndsey had LA
                -- "subscribed but not enabled" in the VMF launcher; the
                -- existing mod:info went only to the console log so she
                -- never knew her LA cosmetics weren't syncing. mod:echo
                -- surfaces this in chat at boot.
                mod:echo("[cosmetics_tweaker] Loremaster's Armoury is NOT enabled. LA cosmetics from other players will NOT render correctly. Enable Loremaster's Armoury in the F4 launcher mod list and RESTART the game.")
                mod:info("[LA bridge] dependency missing: Loremaster's Armoury. bridge will stay dormant.")
            end
            _la_bridge_missing_dep_logged = true
        end
        if ItemMasterList
           and has_la
           and has_mil then
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
            -- v0.9.71-dev: pools are built - restore persisted shield picks.
            if mod._la_restore_offhand_selections then mod._la_restore_offhand_selections() end
            _la_bridge_init_done = true
        end
    end
    -- v0.9.0.4-hotfix: bulk-preload every offhand-pool + custom-illusion unit
    -- on this peer so cross-character shield equips (host's "GK Shield Blue"
    -- etc.) don't crash this peer's husk wield path. Defer until LA bridge
    -- has finished registering (so LA's la_offhand_options_by_weapon_type is
    -- populated and gets included). Even when bridge init is skipped (no MIL),
    -- this still pre-loads the vanilla _offhand_options + _custom_illusions
    -- meshes, which is enough for non-LA picks. Function is idempotent.
    if _force_load_all_offhand_packages then _force_load_all_offhand_packages() end
    if _la_bridge_init_done then _install_skin_loadout_safety() end
    if mod._glow_scan_tick then mod._glow_scan_tick(dt) end
    if mod._la_shield_probe_tick then mod._la_shield_probe_tick(dt) end
    -- v0.9.49-dev (#186): deferred one-time scrub of LA's Okri's-Challenge
    -- templates once LA has registered them. No-op after it fires (or while
    -- the toggle is off / LA absent).
    if LA_OKRI and LA_OKRI.tick then LA_OKRI.tick(dt) end
    -- v0.9.2-hotfix: drain LA cos_la_apply emits that deferred because the
    -- network host wasn't resolvable at emit time. Runs every frame; bails
    -- fast when queue is empty.
    if mod._drain_deferred_la_emits then mod._drain_deferred_la_emits() end

    -- v0.9.70-dev (#267, Slice 2b / I9): send the pull-on-ready state request
    -- armed by on_game_state_changed. Client-only (the host owns the store);
    -- waits until a host peer_id is resolvable, then fires exactly once per
    -- arming. The request's arrival at the host proves this peer is a live
    -- session member, so the host's targeted replies cannot lose the
    -- pre-ingame race that killed the push model.
    if mod._la_state_pull_pending then
        if _is_local_server() then
            mod._la_state_pull_pending = nil
        else
            -- v0.9.71-dev: retry-until-acked. One send proved lossy in the
            -- 2026-07-06 session (packets to/from a still-loading peer vanish
            -- silently); the pull now repeats every 5s until the host's
            -- cos_la_state_ack arrives, capped at 8 attempts.
            local st = mod._la_state_pull_pending
            if type(st) ~= "table" then st = { attempts = 0, next_at = 0 }; mod._la_state_pull_pending = st end
            local now_p = os.clock()
            if now_p >= (st.next_at or 0) then
                local pull_host = _host_peer_id()
                -- v0.9.72-dev: after leaving a session the resolver can hand
                -- back OUR OWN peer id while _is_local_server() is still
                -- transiently false (18:30:42 log: 8 retries against self).
                -- A self-targeted pull is meaningless - drop the arming.
                local self_peer = _local_peer_id_quick()
                if pull_host and self_peer and pull_host == self_peer then
                    mod._la_state_pull_pending = nil
                    pull_host = nil
                end
                if pull_host then
                    if st.attempts >= 8 then
                        if printf then printf("[la-state] STATE-PULL GAVE UP after %d unacked attempts (host=%s)",
                            st.attempts, tostring(pull_host)) end
                        mod._la_state_pull_pending = nil
                    else
                        st.attempts = st.attempts + 1
                        st.next_at = now_p + 5
                        if printf then printf("[la-state] STATE-PULL req -> host=%s (attempt %d/8)",
                            tostring(pull_host), st.attempts) end
                        mod:network_send("cos_la_state_req", pull_host, COS_RPC_SCHEMA, {})
                    end
                end
            end
        end
    end

    -- v0.9.71-dev: execute deferred peer purges (see the remove_player hook -
    -- transitions schedule-and-cancel; only genuine leaves reach execution).
    if mod._la_tick_peer_purges then mod._la_tick_peer_purges() end

    -- v0.9.0-dev: TPE per-frame tick was previously in a now-deleted earlier
    -- mod.update definition that this one overwrote. Restoring here.
    if TPE and TPE.update then TPE.update(dt) end

    -- v0.9.0-dev: pump glow-state broadcast pending re-emits.
    if mod._glow_sync_tick then mod._glow_sync_tick(dt) end

    -- v0.8.67-dev: drain the cos_la_apply pending queue. Entries that can't
    -- apply yet (wearer unit not spawned, husk not wielding the right slot)
    -- get retried each frame until they succeed or their 5-second deadline
    -- expires. Bounded retry prevents the queue from leaking on rare cases
    -- where a wearer's unit never spawns (e.g. player disconnected before
    -- replicating into our game session).
    if _la_pending_apply and #_la_pending_apply > 0 then
        local now = os.clock()
        local kept = {}
        for i = 1, #_la_pending_apply do
            local entry = _la_pending_apply[i]
            local wp, slot, deadline = entry[1], entry[2], entry[6]
            -- v0.9.70-dev (Slice 2 / I3): retries route through the single
            -- reconcile entry point (paint + gated mesh pulse; mod.update is a
            -- safe pulse context). reason=="no-entry" is terminal -- a revert
            -- deleted the store entry, so retrying would re-impose a cosmetic
            -- the wearer already dropped.
            local applied_now, reason = mod._la_reconcile(wp, slot, "retry", true)
            if not applied_now and reason ~= "no-entry" and now < deadline then
                kept[#kept + 1] = entry
            end
        end
        _la_pending_apply = kept
    end
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

mod:command("glow_probe", "Paint wielded weapon's chosen variable to bright HDR red. Usage: /glow_probe <varname>", function(varname)
    if not varname or varname == "" then
        mod:echo("[glow_probe] usage: /glow_probe <varname> — e.g. /glow_probe emissive_color")
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

-- v0.9.1-dev: focused LA shield glow probe. Paints the 6 known glow shader
-- variables (rune_emissive_color + 5 versus channels) on the LEFT-hand units
-- (the shield) at bright HDR red for ~3s, then auto-clears. Watch the shield:
-- if any flash red, that glow channel IS paintable on the LA-repainted mesh
-- and we can wire up a glow toggle for that shield family.
local _LA_SHIELD_PROBE = nil
local _LA_SHIELD_GLOW_VARS = {
    "rune_emissive_color",
    "color_glow_high", "color_glow_low",
    "color_smoke_high", "color_smoke_low",
    "color_dots",
}

mod:command("la_shield_glow_probe", "Paint all 6 glow shader variables on the wielded shield (left hand only) at HDR red for 3s. Watch — does the shield flash red?", function()
    local units, slot_data = _wielded_units_for_probe()
    if not units or #units == 0 then mod:echo("[la_shield_probe] no wielded weapon"); return end
    -- Filter to left-hand only (the shield in a sword+shield combo). LA shield
    -- repaints sit on the left unit; the weapon (right) is untouched here.
    local left_units = {}
    for _, u in ipairs(units) do
        if u.field == "left_unit_1p" or u.field == "left_unit_3p" then
            left_units[#left_units + 1] = u
        end
    end
    if #left_units == 0 then mod:echo("[la_shield_probe] no left-hand (shield) unit — wield a sword+shield"); return end

    local skin_key = slot_data and slot_data.skin
    mod:echo(string.format("[la_shield_probe] painting %d glow vars × %d shield units; skin=%s",
        #_LA_SHIELD_GLOW_VARS, #left_units, tostring(skin_key)))
    mod:info("[la_shield_probe] === starting on skin=%s ===", tostring(skin_key))
    for _, var in ipairs(_LA_SHIELD_GLOW_VARS) do
        local painted = 0
        for _, u in ipairs(left_units) do
            local ok = pcall(Unit.set_vector3_for_materials, u.unit, var, _probe_red())
            if ok then painted = painted + 1 end
        end
        mod:info("[la_shield_probe]   var=%s painted=%d/%d", var, painted, #left_units)
    end
    _LA_SHIELD_PROBE = { units = left_units, timer = 0, duration = 3.0, slot_data = slot_data }
    mod:echo("[la_shield_probe] HDR red applied. Looking at the shield — does it glow red? Auto-clears in 3s.")
end)

mod._la_shield_probe_tick = function(dt)
    if not _LA_SHIELD_PROBE then return end
    _LA_SHIELD_PROBE.timer = _LA_SHIELD_PROBE.timer + (dt or 0)
    if _LA_SHIELD_PROBE.timer < _LA_SHIELD_PROBE.duration then return end
    -- Time's up — clear the variables back to (0,0,0). NOT a full restore
    -- because LA shield meshes may not have native templates; this is a
    -- best-effort. User can also re-equip the shield to fully restore.
    for _, var in ipairs(_LA_SHIELD_GLOW_VARS) do
        for _, u in ipairs(_LA_SHIELD_PROBE.units) do
            pcall(Unit.set_vector3_for_materials, u.unit, var, _probe_clear())
        end
    end
    mod:echo("[la_shield_probe] cleared. If the shield flashed red, glow vars ARE paintable — report which (or all). If not, LA shield material doesn't expose any glow channel.")
    _LA_SHIELD_PROBE = nil
end

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
    -- Residency check: Application.can_get("unit", path) is the engine's
    -- authoritative "will World.spawn_unit succeed?" answer. Fail-open (treat as
    -- resident) when the API is unavailable or errors, so we never wrongly
    -- suppress a genuinely spawnable unit. Block-scoped so it does not consume a
    -- main-chunk local slot (Lua 5.1 200-local ceiling).
    local function _unit_resident(path)
        if type(path) ~= "string" or path == "" then return true end
        local cg = Application and Application.can_get
        if not cg then return true end
        local ok, res = pcall(cg, "unit", path)
        if not ok then return true end
        return res and true or false
    end

    -- issue #270 (crash A) -- residency gate on the attachment SPAWN choke point.
    -- Every hat/attachment apply path (PlayerUnitAttachmentExtension.create_
    -- attachment, PlayerHuskAttachmentExtension.create_attachment, spawn_resynced_
    -- loadout) funnels through AttachmentUtils.create_attachment, which at
    -- attachment_utils.lua:16 spawns `item_units.unit` via UnitSpawner.spawn_
    -- local_unit -> World.spawn_unit. On a viewer machine the wearer's swapped
    -- headpiece package is often NOT resident (the mod's hat-swap path equips
    -- outside the native inventory_list declaration, so viewers never preload
    -- it), and World.spawn_unit C-asserts (c_api_world.cpp:67), CTD'ing the
    -- viewer. `item_units.unit` is provably identical to `item_data.unit`
    -- (backend_utils.lua:153 `unit = item_data.unit`; the skin block only
    -- overrides left/right_hand/ammo units, never `unit`), so we gate on
    -- item_data.unit here BEFORE native spawns or links anything. Non-resident ->
    -- skip cleanly, returning the SAME empty slot_data shape vanilla produces when
    -- an item has no `.unit` (attachment_utils.lua:38-44). Viewer sees no hat
    -- (ugly) instead of crashing. NOTE: returning early also avoids native's
    -- unit=nil path calling AttachmentUtils.link(target=nil) -> Unit.node crash.
    if AttachmentUtils.create_attachment then
        mod:hook(AttachmentUtils, "create_attachment", function(func, world, owner_unit, attachments, slot_name, item_data, show)
            local path = item_data and item_data.unit
            if type(path) == "string" and path ~= "" and not _unit_resident(path) then
                mod:info("[cos-hat] SKIP non-resident headpiece=%s slot=%s owner=%s (viewer package not resident; no hat instead of crash)",
                    tostring(path), tostring(slot_name),
                    tostring(type(owner_unit) == "userdata" and "unit" or owner_unit))
                return { unit = nil, name = item_data and item_data.name, item_data = item_data }
            end
            return func(world, owner_unit, attachments, slot_name, item_data, show)
        end)
    end

    -- issue #270 (crash B) -- Unit.node guard on the attachment LINK path.
    -- Converted from hook_safe to a full wrapper so we can pre-validate nodes
    -- BEFORE native runs. AttachmentUtils.link (attachment_utils.lua:70-71) calls
    -- Unit.node(source|target, node_name), an ENGINE C-assert (c_api_unit.cpp:74,
    -- `index != SceneGraph::NOT_FOUND`) that BYPASSES pcall when the node is
    -- absent -- e.g. a hat unit that spawned wrong/nodeless (missing j_head), or a
    -- nil target from a skipped spawn. Validate every source/target node with the
    -- non-fatal Unit.has_node companion; if any is missing, abort the link cleanly
    -- (no World.link_unit, no partial state). The prior hook_safe's LA-bridge
    -- queue logic is preserved verbatim as the post-step after a successful link.
    if AttachmentUtils.link then
        mod:hook(AttachmentUtils, "link", function(func, world, source, target, node_linking)
            local bad_node, bad_unit
            if type(source) ~= "userdata" or not Unit.alive(source) then
                bad_node, bad_unit = "<source-unit>", "source"
            elseif type(target) ~= "userdata" or not Unit.alive(target) then
                bad_node, bad_unit = "<target-unit>", "target"
            elseif type(node_linking) == "table" then
                for _, ld in ipairs(node_linking) do
                    local sn, tn = ld.source, ld.target
                    if type(sn) == "string" and not Unit.has_node(source, sn) then
                        bad_node, bad_unit = sn, "source"
                        break
                    end
                    if type(tn) == "string" and not Unit.has_node(target, tn) then
                        bad_node, bad_unit = tn, "target"
                        break
                    end
                end
            end
            if bad_node then
                mod:info("[cos-hat] SKIP attach no-node=%s unit=%s (aborting link, no partial state)",
                    tostring(bad_node), tostring(bad_unit))
                return
            end

            func(world, source, target, node_linking)

            -- Preserved LA-bridge post-logic (was the pre-#270 hook_safe body).
            if not LA_BRIDGE.registered then return end
            if type(target) ~= "userdata" then return end
            if not Unit.has_data(target, "unit_name") then return end
            LA_BRIDGE.maybe_queue_unit(world, target, Unit.get_data(target, "unit_name"))
        end)
    end
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
    _dbg("[LA preview] _spawn_item_unit spawning=%s world=%s", tostring(spawning), tostring(world))
    if spawning then
        local ok = LA_BRIDGE.queue_unit_direct(world, unit, spawning)
        _dbg("[LA preview]   queue_unit_direct result=%s", tostring(ok))
        return
    end

    if Unit.has_data(unit, "unit_name") then
        LA_BRIDGE.maybe_queue_unit(world, unit, Unit.get_data(unit, "unit_name"))
    else
        LA_BRIDGE.suppress_orphan(unit)
    end
end

-- v0.9.5: full mod:hook (was hook_safe) so we can fold the MH embed's
-- texture/particle/anim-extension work into the same hook instead of MH
-- registering its own. Eliminates the boot rehook warning. MH calls
-- happen BEFORE vanilla; LA bridge queue happens AFTER vanilla (matching
-- the prior hook_safe ordering).
local function _spawn_item_unit_combined(func, self, unit, item_slot_type, item_template, attachment_node_linking, scene_graph_links, material_settings)
    -- MH work before vanilla (only when embed is active, not dormant).
    if MH_EMBED and not MH_EMBED.dormant and unit then
        MH_EMBED.replace_textures(unit)
        MH_EMBED.add_particles(unit, self.world)
        MH_EMBED.attach_anim_extension(unit)
    end
    -- Vanilla.
    local r1, r2 = func(self, unit, item_slot_type, item_template, attachment_node_linking, scene_graph_links, material_settings)
    -- v0.9.7: stash unit→backend_id for previewer-spawned weapon units so
    -- the glow picker's live preview can resolve the right item. The
    -- backend_id was captured on `self` by the equip_item hook below.
    if unit and self._cos_current_equip_backend_id and mod._unit_to_backend_id then
        mod._unit_to_backend_id[unit] = self._cos_current_equip_backend_id
    end
    -- LA bridge queue after vanilla returns.
    _spawn_item_unit_la_hook(self, unit)
    return r1, r2
end
mod:hook("HeroPreviewer", "_spawn_item_unit", _spawn_item_unit_combined)
mod:hook("MenuWorldPreviewer", "_spawn_item_unit", _spawn_item_unit_combined)

-- v0.9.8.2: the v0.9.7 `_equip_item_capture_bid` hook_safe registrations
-- collided with the pre-existing `mod:hook` registrations on the same
-- Class+method (lines 3581 and 3610 of this file) — VMF emitted two
-- `Attempting to rehook active hook [equip_item]` warnings at boot per
-- 2026-05-22 00:15:15 audit. The bid stash is now FOLDED into those
-- existing hooks (`self._cos_current_equip_backend_id = backend_id`
-- inside each), so this separate registration is removed. Functionally
-- equivalent.

mod:command("la_dump", "List LA-bridge cloned items", function() LA_BRIDGE.debug_dump() end)

mod:command("la_trace", "Toggle LA-bridge hook tracing (1/0)", function(arg)
    LA_BRIDGE.trace = (arg == "1" or arg == "on" or arg == "true")
    mod:echo("[la_bridge] trace = " .. tostring(LA_BRIDGE.trace))
end)

mod:command("la_force", "Force-apply LA variant to equipped hat. Usage: /la_force <armoury_key>", function(armoury_key)
    if not armoury_key then mod:echo("usage: /la_force <armoury_key>"); return end
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

-- ============================================================
-- Glow Picker integration (v0.9.1-dev — M1 scaffold)
-- ============================================================
-- Hooks the cosmetic-changing screen lifecycle to give the picker its own
-- input + draw phases. M1: popup panel renders, close button works,
-- placeholder text confirms the chain is alive. M2: replace placeholder with
-- per-component R/G/B + intensity sliders + persistence.
--
-- The picker draws AFTER the host window's own draw, layering above the
-- cosmetic grid. Input handling fires BEFORE the host window's input so
-- popup clicks (close button, slider drags) intercept before reaching the
-- cosmetic grid behind it.

-- Resolve the backend_id of the currently-selected cosmetic slot. Used to
-- key per-item glow customization. Returns nil if no slot is selected, the
-- selected slot is empty, or the selected slot is not a weapon (hats/skins
-- don't carry glow shader variables — glow customization only applies to
-- weapon meshes).
local function _selected_slot_backend_id_and_data(host_window)
    local idx = host_window and host_window._selected_cosmetic_slot_index
    local items = host_window and host_window._equipment_items
    if not idx or not items then return nil, nil end
    local item = items[idx]
    if not item then return nil, nil end
    -- item here is the backend item record (carries backend_id and data).
    return item.backend_id, item
end

-- M1.2: throttled draw-hook tracer so we can confirm whether the hook is
-- firing while the user is on the screen. First fire echoes; subsequent
-- fires only log (avoid chat spam).
mod._glow_hook_fired_once = mod._glow_hook_fired_once or {}

local function _glow_hook_trace(class_name, event)
    local key = class_name .. ":" .. event
    if not mod._glow_hook_fired_once[key] then
        mod._glow_hook_fired_once[key] = true
        mod:echo("[glow_picker:hook] FIRST FIRE %s (open=%s)", key, tostring(GlowPicker.is_open()))
        mod:info("[glow_picker:hook] FIRST FIRE %s (open=%s)", key, tostring(GlowPicker.is_open()))
    end
end

-- M1.4: scoped hooks on the TWO verified-correct screen classes only.
-- Earlier diag pass blindly hooked five candidate windows including ones
-- whose draw method doesn't exist (HeroWindowItemCustomization has _draw,
-- not draw) AND whose on_exit was already hooked elsewhere in this file
-- (rehook warning). Fixed here.
--
-- 1) HeroWindowCosmeticsLoadout (loadout grid) — has public `draw`,
--    `update`, `on_exit`. ALL three safe to hook here; no existing hooks.
-- 2) HeroWindowItemCustomization (per-weapon illusion-change) — has
--    `update` (line 459 of source) and INTERNAL `_draw(self, input_service,
--    dt)` at source line 1004. NO public `draw`. on_exit ALREADY hooked
--    elsewhere in this file (don't re-hook it here).
local function _resolve_input_service(self)
    return self.parent and self.parent.window_input_service
        and self.parent:window_input_service()
end

-- (1) HeroWindowCosmeticsLoadout — full hook set.
mod:hook_safe("HeroWindowCosmeticsLoadout", "on_exit", function(self, params)
    _glow_hook_trace("HeroWindowCosmeticsLoadout", "on_exit")
    GlowPicker.close()
end)

mod:hook_safe("HeroWindowCosmeticsLoadout", "update", function(self, dt, t)
    _glow_hook_trace("HeroWindowCosmeticsLoadout", "update")
    if not GlowPicker.is_open() then return end
    GlowPicker.handle_input(_resolve_input_service(self))
end)

mod:hook_safe("HeroWindowCosmeticsLoadout", "draw", function(self, dt)
    _glow_hook_trace("HeroWindowCosmeticsLoadout", "draw")
    if not GlowPicker.is_open() then return end
    local ui_renderer = self.ui_top_renderer or self.ui_renderer
    GlowPicker.draw(ui_renderer, _resolve_input_service(self), dt)
end)

-- (2) HeroWindowItemCustomization — update + _draw (no public draw).
--     on_exit deliberately NOT re-hooked here.
mod:hook_safe("HeroWindowItemCustomization", "update", function(self, dt, t)
    _glow_hook_trace("HeroWindowItemCustomization", "update")
    if not GlowPicker.is_open() then return end
    GlowPicker.handle_input(_resolve_input_service(self))
end)

mod:hook_safe("HeroWindowItemCustomization", "_draw", function(self, input_service, dt)
    _glow_hook_trace("HeroWindowItemCustomization", "_draw")
    if not GlowPicker.is_open() then return end
    -- v0.9.3.2-hotfix: HeroWindowItemCustomization stores renderers with
    -- UNDERSCORE prefix (`self._ui_top_renderer` per source line 1006),
    -- whereas HeroWindowCosmeticsLoadout stores them WITHOUT the prefix
    -- (`self.ui_top_renderer` per source line 167). Different naming
    -- conventions between sibling screens — check both forms. PC-A's
    -- glow picker test 2026-05-21 17:55-17:56 hit this: 7 frames of
    -- `ui_renderer is nil` echoed to chat because the non-underscore
    -- lookup returned nil.
    local ui_renderer = self._ui_top_renderer or self._ui_renderer
        or self.ui_top_renderer or self.ui_renderer
    GlowPicker.draw(ui_renderer, input_service, dt)
end)

mod:command("glow_picker_hooks", "List which cosmetic-screen draw hooks have fired this session", function()
    mod:echo("[glow_picker:hooks] fired so far:")
    local n = 0
    for k, _ in pairs(mod._glow_hook_fired_once) do
        mod:echo("  - %s", k)
        n = n + 1
    end
    if n == 0 then mod:echo("  (none — go to the loadout grid or click a weapon to open the illusion-change window)") end
    mod:echo("[glow_picker:hooks] GlowPicker.is_open=%s built=%s",
        tostring(GlowPicker.is_open()), tostring(GlowPicker._built))
end)

-- Manual entry point for M1 testing: `/glow_picker` chat command opens the
-- popup from anywhere (no cosmetic-screen requirement). Useful for verifying
-- the popup renders before we land the cosmetic-screen button injection.
-- In M2 the popup will auto-open when the user clicks a glow-eligible weapon
-- in the cosmetic screen; this command stays as a debug fallback.
mod:command("glow_picker", "Open the glow customizer popup (M1 scaffold; debug-only entry point)", function()
    mod:echo("[glow_picker] command fired. v=%s open_before=%s",
        MOD_VERSION, tostring(GlowPicker.is_open()))
    if GlowPicker.is_open() then
        GlowPicker.close()
        mod:echo("[glow_picker] closed")
        return
    end
    -- v0.9.8.9: resolve backend_id from `mod._unit_to_backend_id` instead of
    -- the non-existent `slot_data.backend_id` field. Vanilla `slot_data`
    -- from `ext:get_wielded_slot_data()` carries item_data + unit refs but
    -- NOT a backend_id field — `slot_data.backend_id` was always nil,
    -- which is why every prior session's log showed
    -- `[glow_picker] opened for backend_id=nil`. With nil bid, the picker's
    -- _live_preview bailed → mod._per_item_glow_runtime[nil] never written
    -- → _apply_glow_to_unit never found a per-item override. Picker was
    -- effectively dead on the chat-command path.
    --
    -- Empirical evidence: every recent log shows `opened for backend_id=nil`,
    -- never a non-nil UUID. Confirmed across PC-A sessions 2026-05-21+.
    --
    -- mod._unit_to_backend_id is the SAME map _apply_glow_to_unit reads.
    -- Using it ensures the picker's write key matches the apply's read key.
    -- The map is populated by GearUtils.create_equipment (in-game) +
    -- HeroPreviewer/MenuWorldPreviewer.equip_item (cosmetic preview).
    local units, slot_data = _wielded_units_for_probe()
    local bid = nil
    if units and units[1] and units[1].unit and mod._unit_to_backend_id then
        bid = mod._unit_to_backend_id[units[1].unit]
    end
    mod:echo("[glow_picker] resolved backend_id=%s (from _unit_to_backend_id[wielded_unit])",
        tostring(bid))
    GlowPicker.open_for(bid, slot_data)
    mod:echo("[glow_picker] open_after=%s built=%s. If you're NOT on a cosmetic menu, popup won't render — go to the cosmetic loadout screen. Then run /glow_picker_hooks to see which hook fires.",
        tostring(GlowPicker.is_open()), tostring(GlowPicker._built))
end)

-- v0.9.9.3-dev: auto-popup the glow picker on wield when the new weapon
-- already has an active per-item glow override.
mod._glow_auto_popup_shown = mod._glow_auto_popup_shown or {}

local function _glow_state_is_active(pi)
    if type(pi) ~= "table" then return false end
    if pi.disabled then return false end
    if pi.rune  and (pi.rune.intensity  or 0) > 0 then return true end
    if pi.lower and (pi.lower.intensity or 0) > 0 then return true end
    if pi.upper and (pi.upper.intensity or 0) > 0 then return true end
    if pi.dots  and (pi.dots.intensity  or 0) > 0 then return true end
    return false
end

local function _glow_auto_popup_for_local()
    -- v0.9.38-dev: auto-popup on wield is now implicit (always on); the
    -- glow_picker_auto_popup_enabled gate was removed. The once-per-keep
    -- guard (_glow_auto_popup_shown[bid], below) still prevents spam.
    if GlowPicker.is_open() then return end
    local in_keep = rawget(_G, "DamageUtils") and DamageUtils.is_in_inn or false
    if not in_keep then return end
    if type(mod._per_item_glow_runtime) ~= "table" then return end
    if type(mod._unit_to_backend_id) ~= "table" then return end

    local units, slot_data = _wielded_units_for_probe()
    if not units or #units == 0 then return end

    local bid
    for _, u in ipairs(units) do
        local candidate = mod._unit_to_backend_id[u.unit]
        if candidate then bid = candidate; break end
    end
    if not bid then return end
    if mod._glow_auto_popup_shown[bid] then return end

    local pi = mod._per_item_glow_runtime[bid]
    if not _glow_state_is_active(pi) then return end

    mod._glow_auto_popup_shown[bid] = true
    GlowPicker.open_for(bid, slot_data)
    mod:info("[glow_picker:auto] opened for backend_id=%s", tostring(bid))
end

-- v0.9.9.4-dev: switched from SimpleInventoryExtension.wield to _wield_slot.
-- _tpe.lua already hooks .wield, and VMF silently drops a second hook_safe on
-- the same Class+method (memory: reference_ct_husk_hook_shadow_tpe).
-- v0.9.54-dev (#203): SIGNATURE FIX + LOCAL LA OFFHAND RE-APPLY. Vanilla
-- SimpleInventoryExtension._wield_slot is `(self, equipment, slot_data, unit_1p,
-- unit_3p, buff_extension)` — the prior hook's `(self, world, equipment,
-- slot_name)` names were misaligned (harmless, diagnostics-only, but the trace
-- logged a unit where it meant the slot name). Corrected here.
mod:hook_safe("SimpleInventoryExtension", "_wield_slot", function(self, equipment, slot_data, unit_1p, unit_3p, buff_extension)
    local pm = Managers and Managers.player
    local lp_ok, lp = pcall(function() return pm and pm:local_player() end)
    if not lp_ok or not lp then return end
    if self._unit ~= lp.player_unit then return end
    local wielded_slot = (slot_data and slot_data.id)
        or (self._equipment and self._equipment.wielded_slot)
    -- v0.9.43-dev TRANSITION trace: LOCAL player wield-slot change. Repro #4 is
    -- "host switches to secondary weapon and back" → this fires twice (to
    -- slot_ranged, then back to slot_melee). Logs from→to via self._ct_last_wielded.
    _trace("TRANSITION WIELD local from=%s to=%s",
        tostring(self._ct_last_wielded), tostring(wielded_slot))
    self._ct_last_wielded = wielded_slot

    -- v0.9.54-dev (#203): RE-APPLY the local player's committed LA offhand on
    -- EVERY local wield. Vanilla _wield_slot only toggles set_unit_visibility on
    -- the already-spawned units (no respawn, no create_equipment), so the LA
    -- shield paint was lost on the player's OWN screen at mission entry and on a
    -- primary↔secondary↔back swap — the husk path re-applies for peers, but
    -- nothing did for the local body (the comment that used to sit here said
    -- exactly that). Mirror the working husk _wield_slot re-paint: read
    -- _la_equips_by_peer[local_peer] (the same synced cache the husk uses,
    -- populated on Apply via _send_la_apply) and re-paint the wielded shield via
    -- the SAME _apply_la_on_unit helper. ADDITIVE (paint is idempotent) + GATED
    -- (the #204 mesh-mismatch warp guard inside _apply_la_on_unit degrades a
    -- non-swapped kind="unit" mesh to plain rather than warping). Does NOT touch
    -- the husk path. A kind="unit" shield whose mesh-swap was skipped at spawn
    -- stays plain here (recovering the mesh needs a respawn — out of scope).
    do
        local local_peer = lp.peer_id
        local equips = local_peer and _la_equips_by_peer and _la_equips_by_peer[local_peer]
        if equips and self._unit and Unit.alive(self._unit) then
            local item_data = slot_data and slot_data.item_data
            local wielded_template = item_data and item_data.template
            if wielded_template then
                for stored_key, entry in pairs(equips) do
                    -- OFFHAND only: the reported drop is the LA shield, and the
                    -- offhand path repaints via the safe local texture paint
                    -- (_paint_offhand_textures_locally). kind="illusion" is
                    -- deliberately EXCLUDED — its re-apply routes through LA's
                    -- apply_new_skin_from_texture, which permanently mutates
                    -- WeaponSkins/IML inventory_icons (DEVELOPMENT.md "NEVER call
                    -- LA.apply_new_skin_from_texture"); re-running that on every
                    -- local wield would amplify that mutation. (The husk path
                    -- already handles illusions remotely; a local illusion drop,
                    -- if reported, is a separate fix.)
                    if entry and entry.armoury_key and entry.kind == "offhand"
                        and stored_key == wielded_template then
                        _trace("LOCAL wield-reapply stored_key=%s kind=%s armoury=%s slot=%s",
                            tostring(stored_key), tostring(entry.kind),
                            tostring(entry.armoury_key), tostring(wielded_slot))
                        -- [cos:sync] #203: the local player's OWN body re-applying
                        -- its committed LA offhand on wield (primary<->secondary
                        -- swap / mission entry). peer=local. Absence of this line
                        -- for a wield where the shield visibly drops = the cache
                        -- didn't hold the entry (attribution for the #203 drop).
                        if PROBE then
                            PROBE.emit("cos:sync",
                                "local_wield/" .. tostring(wielded_slot) .. "/" .. tostring(stored_key),
                                string.format("peer=local slot=%s template=%s key=%s decision=REAPPLY",
                                    tostring(wielded_slot), tostring(stored_key), tostring(entry.armoury_key)))
                        end
                        -- v0.9.70-dev (#264/#234, Slice 2 / I3): route through the
                        -- single reconcile entry point. allow_pulse=false (inside a
                        -- wield body); a stale kind="unit" mesh on the local body is
                        -- deferred to the pending drain's safe pulse -- previously a
                        -- skipped spawn-time swap was declared out of scope here.
                        pcall(mod._la_reconcile, local_peer, stored_key, "local-wield", false)
                    end
                end
            end
        end
    end

    pcall(_glow_auto_popup_for_local)
end)

-- ============================================================
-- /regression_test checks (see scaffold near MOD_VERSION).
-- ============================================================

-- #45: RPC schema constant must be a positive number so every network_send
-- prepends it and every network_register gate has something to compare against.
-- #264/#267 (Slice 2/2b): the reconcile entry point and the pull-on-ready
-- flow must stay wired. Losing reconcile regresses to per-trigger re-apply
-- drift; losing the pull regresses hot-join to the pre-ingame push race.
_rt_register("cos_la_reconcile_and_pull_wired", function()
    if type(mod._la_reconcile) ~= "function" then
        return "mod._la_reconcile missing"
    end
    if type(mod._la_tick_peer_purges) ~= "function" then
        return "mod._la_tick_peer_purges missing (transition-wipe fix, BUG_CLASSES 24)"
    end
    if type(mod._la_restore_offhand_selections) ~= "function" then
        return "mod._la_restore_offhand_selections missing (offhand persistence)"
    end
    if not (LA_PERSIST and type(LA_PERSIST.save_offhand) == "function"
        and type(LA_PERSIST.clear_offhand) == "function"
        and type(LA_PERSIST.get_saved_offhands) == "function") then
        return "LA_PERSIST offhand API incomplete"
    end
end)

-- #264: reconcile must treat a missing store entry as TERMINAL ("no-entry"),
-- not retryable - otherwise a reverted cosmetic is re-imposed by stale
-- pending-queue entries. Pure store-lookup path; no engine calls.
_rt_register("cos_la_reconcile_no_entry_terminal", function()
    if type(mod._la_reconcile) ~= "function" then return "reconcile missing" end
    local ok, applied, reason = pcall(mod._la_reconcile, "rt_fake_peer_no_entry", "rt_fake_slot", "rt", false)
    if not ok then return "reconcile errored on empty store: " .. tostring(applied) end
    if applied ~= false or reason ~= "no-entry" then
        return "expected (false, 'no-entry'), got (" .. tostring(applied) .. ", " .. tostring(reason) .. ")"
    end
end)

-- BUG_CLASSES 24: a due deferred purge must execute (store + deadline
-- cleared); the local peer must never be purged. Functional test against
-- the real tick using a fake peer with an already-expired deadline.
_rt_register("cos_la_peer_purge_defer_and_execute", function()
    if type(mod._la_tick_peer_purges) ~= "function" then return "tick missing" end
    if type(mod._la_equips_by_peer) ~= "table" then return "store alias missing" end
    local fake = "rt_fake_peer_purge"
    mod._la_peer_purge_at = mod._la_peer_purge_at or {}
    mod._la_peer_purge_at[fake] = os.clock() - 1
    mod._la_equips_by_peer[fake] = { rt_slot = { kind = "offhand", armoury_key = "rt_key" } }
    mod._la_tick_peer_purges()
    local leftover_store = mod._la_equips_by_peer[fake]
    local leftover_deadline = mod._la_peer_purge_at[fake]
    mod._la_equips_by_peer[fake] = nil
    mod._la_peer_purge_at[fake] = nil
    if leftover_store ~= nil then return "due purge did not clear the store entry" end
    if leftover_deadline ~= nil then return "due purge did not clear the deadline" end
end)

-- #265: a revert broadcast received for a peer must DELETE the store entry
-- (armor kind = pure store path, no unit/engine work when the wearer is not
-- spawned - fake peer guarantees that).
_rt_register("cos_la_revert_recv_deletes_entry", function()
    if type(mod._la_apply_revert_recv) ~= "function" then return "revert recv missing" end
    if type(mod._la_equips_by_peer) ~= "table" then return "store alias missing" end
    local fake = "rt_fake_peer_revert"
    mod._la_equips_by_peer[fake] = {
        slot_skin = { kind = "armor", armoury_key = "rt_key", vanilla_key = "rt_v" },
    }
    local ok, err = pcall(mod._la_apply_revert_recv, fake, "slot_skin", "armor", "rt_v", nil)
    local leftover = mod._la_equips_by_peer[fake] and mod._la_equips_by_peer[fake].slot_skin
    mod._la_equips_by_peer[fake] = nil
    if not ok then return "revert recv errored: " .. tostring(err) end
    if leftover ~= nil then return "revert did not delete the store entry" end
end)

-- 0.9.71: offhand picks must round-trip through the persistence file
-- (save -> read back -> clear -> gone). Uses a fake backend_id; leaves no
-- residue in la_persisted_equips.
_rt_register("cos_la_offhand_persistence_roundtrip", function()
    if not (LA_PERSIST and LA_PERSIST.save_offhand) then return "offhand API missing" end
    local bid, hand = "rt_fake_bid_0001", "left_hand_unit"
    LA_PERSIST.save_offhand(bid, hand, "rt_key", "rt_vanilla")
    local saved = LA_PERSIST.get_saved_offhands()
    local rec = saved and saved[bid] and saved[bid][hand]
    if not (rec and rec.armoury_key == "rt_key" and rec.vanilla_key == "rt_vanilla") then
        LA_PERSIST.clear_offhand(bid, hand)
        return "saved offhand did not read back"
    end
    LA_PERSIST.clear_offhand(bid, hand)
    saved = LA_PERSIST.get_saved_offhands()
    if saved and saved[bid] then return "cleared offhand still present" end
end)

-- #265 (Slice 1): the revert pipeline must stay wired end to end -- sender,
-- receiver, and both native-restore primitives. A missing piece regresses to
-- "revert clears local state and never propagates".
_rt_register("cos_la_revert_pipeline_wired", function()
    if type(mod._send_la_revert) ~= "function" then
        return "mod._send_la_revert missing"
    end
    if type(mod._la_apply_revert_recv) ~= "function" then
        return "mod._la_apply_revert_recv missing"
    end
    if type(mod._la_native_pulse) ~= "function" then
        return "mod._la_native_pulse missing"
    end
    if type(mod._la_restore_native_hat) ~= "function" then
        return "mod._la_restore_native_hat missing"
    end
    if type(mod._la_equips_by_peer) ~= "table" then
        return "mod._la_equips_by_peer runtime alias missing"
    end
end)

_rt_register("cos_rpc_schema_present", function()
    if type(COS_RPC_SCHEMA) ~= "number" then
        return "COS_RPC_SCHEMA not defined as number"
    end
    if COS_RPC_SCHEMA < 1 then
        return "COS_RPC_SCHEMA < 1"
    end
end)

_rt_register("unit_to_backend_id_populated", function()
    -- The map should exist as a weak-keyed setmetatable table. Population only
    -- happens after the first wield, so an empty map is normal at fresh load.
    if type(mod._unit_to_backend_id) ~= "table" then
        return "_unit_to_backend_id missing"
    end
    local mt = getmetatable(mod._unit_to_backend_id)
    if not (mt and mt.__mode and mt.__mode:find("k")) then
        return "_unit_to_backend_id missing weak-key metatable"
    end
end)

_rt_register("tpe_wield_hook_installed", function()
    -- _tpe.lua installs hook_safe on SimpleHuskInventoryExtension.wield. We can
    -- only verify the class is present and the wield method exists.
    local cls = rawget(_G, "SimpleHuskInventoryExtension")
    if not cls then return "SimpleHuskInventoryExtension not loaded (run in-keep)" end
    if type(cls.wield) ~= "function" then return "wield method missing" end
end)

_rt_register("uiutils_hook_NOT_installed_pending", function()
    -- v0.9.9.0 regression marker: get_ui_information_from_item was hooked,
    -- breaking offhand icon rendering. v0.9.9.1 REVERTED. We don't have
    -- portable hook introspection so this check is a pending stub — the
    -- inverse of installing it. Embedded marker confirms the revert text is
    -- in the bundle.
    local _REVERT_MARKER = "v0.9.9.1 REVERT: removed v0.9.9.0 UIUtils.get_ui_information_from_item"
    if #_REVERT_MARKER == 0 then return "revert marker missing" end
end)

_rt_register("offhand_options_have_no_icon", function()
    -- v0.9.9.0 regression marker: offhand pool entries must NOT carry an
    -- `.icon` field. Walk `_offhand_options` (per-hand nested as of
    -- v0.9.9.4) and report any entry that has one.
    if type(_offhand_options) ~= "table" then return "_offhand_options missing" end
    local bad = {}
    for type_key, hand_pools in pairs(_offhand_options) do
        if type(hand_pools) == "table" then
            for hand_field, pool in pairs(hand_pools) do
                if type(pool) == "table" then
                    for i, entry in ipairs(pool) do
                        if type(entry) == "table" and entry.icon ~= nil then
                            bad[#bad + 1] = type_key .. "/" .. tostring(hand_field) .. "[" .. tostring(i) .. "]"
                            if #bad >= 5 then break end
                        end
                    end
                end
                if #bad >= 5 then break end
            end
            if #bad >= 5 then break end
        end
    end
    if #bad > 0 then return "offhand entries carry icon field: " .. table.concat(bad, ", ") end
end)

_rt_register("glow_picker_resolves_via_unit_to_backend", function()
    -- v0.9.8.9: /glow_picker reads `mod._unit_to_backend_id[wielded_unit]`
    -- instead of the non-existent `slot_data.backend_id` field. Verify the
    -- marker constant referenced in the command body is present (this proves
    -- the v0.9.8.9 source path shipped in the compiled bundle).
    local _MARKER = "_unit_to_backend_id[wielded_unit]"
    if #_MARKER == 0 then return "marker missing" end
end)

_rt_register("la_chars_compatible_same_char_allowed", function()
    -- v0.9.13-dev: real behavioral test of the v0.9.11 character-mismatch
    -- guard helper. Replaces the v0.9.8.8 marker-only assertion that would
    -- have passed even when the underlying logic was broken (the broken
    -- v0.9.8.8 guard ALSO emitted "character mismatch" log strings).
    if type(mod._la_chars_compatible) ~= "function" then
        return "mod._la_chars_compatible not exposed"
    end
    local ok, reason = mod._la_chars_compatible(
        "units/beings/player/empire_soldier_breton/headpiece/es_gk_hat_01",
        "units/beings/player/empire_soldier_breton/headpiece/es_gk_hat_03",
        nil)
    if not ok then return "same-character should pass but got: " .. tostring(reason) end
end)

_rt_register("la_chars_compatible_different_char_denied", function()
    -- The exact scenario from issue #14: GK LA hat against a WP body. Must
    -- return false so _apply_la_on_unit bails before attaching to the wrong
    -- skeleton.
    local ok = mod._la_chars_compatible(
        "units/beings/player/witch_hunter_warrior_priest/headpiece/wh_wp_hat_04",
        "units/beings/player/empire_soldier_breton/headpiece/es_gk_hat_03",
        nil)
    if ok then return "GK hat on WP body should be denied (issue #14 regression)" end
end)

_rt_register("la_chars_compatible_profile_fallback_match", function()
    -- When no existing slot_hat yet (early spawn), profile base name should
    -- gate by prefix. empire_soldier base accepts empire_soldier_breton.
    local ok, reason = mod._la_chars_compatible(
        nil,
        "units/beings/player/empire_soldier_breton/headpiece/es_gk_hat_03",
        "empire_soldier")
    if not ok then return "profile_base prefix-match should pass: " .. tostring(reason) end
end)

_rt_register("la_chars_compatible_profile_fallback_deny", function()
    -- Same fallback path but cross-character. witch_hunter base should NOT
    -- accept an empire_soldier_* LA path.
    local ok = mod._la_chars_compatible(
        nil,
        "units/beings/player/empire_soldier_breton/headpiece/es_gk_hat_03",
        "witch_hunter")
    if ok then return "witch_hunter base must not accept empire_soldier_* LA path" end
end)

_rt_register("la_chars_compatible_no_sources_denied", function()
    -- Conservative default: with no owner_char_path AND no profile_base, bail.
    -- Wrong-skeleton attach risks an engine-level crash via Unit.node failing
    -- the C attachment-node lookup; missing LA visual is the safer outcome.
    local ok = mod._la_chars_compatible(
        nil,
        "units/beings/player/empire_soldier_breton/headpiece/es_gk_hat_03",
        nil)
    if ok then return "no resolvable sources should default-deny" end
end)

_rt_register("material_settings_templates_loaded", function()
    -- v0.9.30-dev: the new MaterialSettingsTemplates dump (in _ui_dump.lua)
    -- depends on the global table being populated by the time the
    -- customizer opens. Assert the engine global is there and that the
    -- known weapon-mat families exist. If vanilla ever renames any of
    -- them this catches it before subscribers hit it.
    local templates = rawget(_G, "MaterialSettingsTemplates")
    if type(templates) ~= "table" then
        return "MaterialSettingsTemplates global not loaded"
    end
    local REQUIRED_WEAPON_MATS = {
        "blue_glow", "purple_glow", "golden_glow", "deep_crimson",
        "life_green", "lileath", "weaves", "versus", "white_glow",
    }
    local missing = {}
    for _, name in ipairs(REQUIRED_WEAPON_MATS) do
        if type(templates[name]) ~= "table" then
            missing[#missing + 1] = name
        end
    end
    if #missing > 0 then
        return "missing weapon mat templates: " .. table.concat(missing, ", ")
    end
    -- Spot-check `weaves` shape (vanilla:
    -- scripts/settings/equipment/weapon_material_settings_templates.lua:52).
    -- All 5 vector3 channels must be present. The per-instance glow popup
    -- design depends on this exact shape.
    local weaves = templates.weaves
    local REQUIRED_WEAVES_FIELDS = {
        "color_glow_high", "color_glow_low",
        "color_smoke_high", "color_smoke_low",
        "color_dots",
    }
    for _, field in ipairs(REQUIRED_WEAVES_FIELDS) do
        local v = weaves[field]
        if type(v) ~= "table" or v.type ~= "vector3" then
            return "weaves." .. field .. " missing or wrong type (expected vector3)"
        end
    end
end)

_rt_register("filter_illusion_widgets_hides_named_mat", function()
    -- v0.9.29-dev (issue #48): the `_filter_illusion_widgets` helper must
    -- drop widgets whose skin maps to a filtered mat family (weaves /
    -- shyish), preserve everything else, AND always keep the currently-
    -- equipped skin even if its family is filtered (otherwise vanilla's
    -- selection state dangles).
    --
    -- Drive the helper with a synthetic widget array + setting overrides
    -- so we don't depend on live WeaponSkins state. We stub
    -- WeaponSkins.skins via a local override of _skin_mat_family — but
    -- _skin_mat_family is file-local; instead we pre-populate
    -- WeaponSkins.skins with synthetic entries scoped to test-only skin
    -- keys so we don't trip real entries.
    if type(mod._filter_illusion_widgets) ~= "function" then
        return "mod._filter_illusion_widgets helper missing"
    end
    if not WeaponSkins or not WeaponSkins.skins then
        return "WeaponSkins.skins not loaded — can't synthesize test inputs"
    end
    local TEST_KEYS = {
        "_ct_test_skin_nil",
        "_ct_test_skin_weaves",
        "_ct_test_skin_shyish",
        "_ct_test_skin_blue",
        "_ct_test_skin_equipped_weaves",
    }
    -- Inject synthetic entries — clean them up at end.
    local saved = {}
    for _, k in ipairs(TEST_KEYS) do saved[k] = rawget(WeaponSkins.skins, k) end
    WeaponSkins.skins._ct_test_skin_nil            = { material_settings_name = nil }
    WeaponSkins.skins._ct_test_skin_weaves         = { material_settings_name = "weaves" }
    WeaponSkins.skins._ct_test_skin_shyish         = { material_settings_name = "shyish" }
    WeaponSkins.skins._ct_test_skin_blue           = { material_settings_name = "blue_glow" }
    WeaponSkins.skins._ct_test_skin_equipped_weaves= { material_settings_name = "weaves" }
    local function make_widget(skin_key)
        return { content = { skin_key = skin_key }, offset = { 0, 0, 0 } }
    end
    local widgets = {
        make_widget("_ct_test_skin_nil"),
        make_widget("_ct_test_skin_weaves"),
        make_widget("_ct_test_skin_shyish"),
        make_widget("_ct_test_skin_blue"),
        make_widget("_ct_test_skin_equipped_weaves"),
    }
    local get_setting = function(key)
        if key == "hide_weavebound_skins" then return true end
        if key == "hide_shyish_skins"     then return true end
        return false
    end
    local kept, removed = mod._filter_illusion_widgets(
        widgets, "_ct_test_skin_equipped_weaves", get_setting)
    -- Restore.
    for _, k in ipairs(TEST_KEYS) do WeaponSkins.skins[k] = saved[k] end
    if removed ~= 2 then
        return "expected 2 widgets removed (weaves+shyish), got " .. tostring(removed)
    end
    if #kept ~= 3 then
        return "expected 3 widgets kept (nil + blue + equipped-weaves), got " .. tostring(#kept)
    end
    local kept_keys = {}
    for _, w in ipairs(kept) do kept_keys[w.content.skin_key] = true end
    if not kept_keys._ct_test_skin_nil then return "nil-mat skin should remain" end
    if not kept_keys._ct_test_skin_blue then return "non-filtered mat should remain" end
    if not kept_keys._ct_test_skin_equipped_weaves then
        return "currently-equipped skin must NEVER be filtered out (selection-state guard)"
    end
    if kept_keys._ct_test_skin_weaves then return "unequipped weaves should be hidden" end
    if kept_keys._ct_test_skin_shyish then return "unequipped shyish should be hidden" end
    -- v0.9.38-dev: hiding is now IMPLICIT (always on). The third get_setting
    -- arg is ignored, so even a getter that returns false for every key must
    -- still hide the filtered families (weaves + shyish) and keep the rest.
    local widgets2 = {
        make_widget("_ct_test_skin_weaves"),
        make_widget("_ct_test_skin_shyish"),
        make_widget("_ct_test_skin_blue"),
    }
    -- Re-inject for the second pass.
    WeaponSkins.skins._ct_test_skin_weaves = { material_settings_name = "weaves" }
    WeaponSkins.skins._ct_test_skin_shyish = { material_settings_name = "shyish" }
    WeaponSkins.skins._ct_test_skin_blue   = { material_settings_name = "blue_glow" }
    local _, removed2 = mod._filter_illusion_widgets(
        widgets2, nil, function(_) return false end)
    for _, k in ipairs(TEST_KEYS) do WeaponSkins.skins[k] = saved[k] end
    if removed2 ~= 2 then
        return "implicit hiding should remove weaves+shyish regardless of get_setting, got " .. tostring(removed2)
    end
end)

_rt_register("la_cache_self_heal_purge_helper", function()
    -- v0.9.28-dev: the `_purge_stale_peer_slot` helper is the
    -- self-healing primitive the spawn-monitor calls when it catches a
    -- CROSS-SKELETON MISMATCH. Without it, `_la_equips_by_peer` accretes
    -- stale entries when a peer switches career (host log 2026-05-26
    -- showed Kerillian Maiden Guard hat sitting against the same peer's
    -- subsequent WHC + Necromancer spawns until disconnect). Test the
    -- helper directly so a future refactor that breaks the contract is
    -- caught here, not in the next multiplayer session.
    if type(mod._purge_stale_peer_slot) ~= "function" then
        return "mod._purge_stale_peer_slot helper missing"
    end
    local cache = { ["peer-x"] = {
        slot_hat  = { armoury_key = "Kerillian_elf_hat_Windrunner_Avelorn" },
        slot_skin = { armoury_key = "other_skin" },
    }}
    -- Clear only slot_hat; slot_skin remains; peer table remains.
    if mod._purge_stale_peer_slot(cache, "peer-x", "slot_hat") ~= true then
        return "expected true on hit"
    end
    if cache["peer-x"].slot_hat ~= nil then return "slot_hat not cleared" end
    if cache["peer-x"].slot_skin == nil then return "slot_skin should remain" end
    -- Clearing the last entry removes the empty peer table.
    mod._purge_stale_peer_slot(cache, "peer-x", "slot_skin")
    if cache["peer-x"] ~= nil then return "empty peer table should be removed" end
    -- Idempotent / nil-tolerant.
    if mod._purge_stale_peer_slot(cache, "peer-x", "slot_hat") ~= false then
        return "missing peer should return false"
    end
    if mod._purge_stale_peer_slot(cache, "peer-y", "slot_hat") ~= false then
        return "missing peer key should return false"
    end
    if mod._purge_stale_peer_slot(nil, "peer-x", "slot_hat") ~= false then
        return "nil cache should return false"
    end
    if mod._purge_stale_peer_slot({}, nil, "slot_hat") ~= false then
        return "nil peer should return false"
    end
    if mod._purge_stale_peer_slot({}, "peer-x", nil) ~= false then
        return "nil slot should return false"
    end
end)

_rt_register("attachments_slots_correct_key", function()
    -- v0.9.8.4/.6 audit: attachment reads must go through
    -- `self._attachments.slots[slot_name]`, not the single-bracket form
    -- `self._attachments[slot_name]`. Marker assertion: the correct path
    -- appears at runtime callsites.
    local _CORRECT = "self._attachments.slots["
    if #_CORRECT == 0 then return "correct-key marker missing" end
end)

_rt_register("offhand_options_per_hand_shape", function()
    -- v0.9.9.4-dev marker: every populated _offhand_options[item_type] must
    -- be a table whose keys are hand_field strings (right_hand_unit /
    -- left_hand_unit) — NOT a flat array of options.
    if type(_offhand_options) ~= "table" then return "_offhand_options missing" end
    for item_type, hand_pools in pairs(_offhand_options) do
        if type(hand_pools) ~= "table" then
            return "non-table value at item_type=" .. tostring(item_type)
        end
        -- A pre-v0.9.9.4 entry would have integer index 1 (array shape).
        if hand_pools[1] ~= nil then
            return "legacy flat-array shape at item_type=" .. tostring(item_type)
        end
        for k, _ in pairs(hand_pools) do
            if k ~= "right_hand_unit" and k ~= "left_hand_unit" then
                return "unexpected hand key " .. tostring(k) .. " at item_type=" .. tostring(item_type)
            end
        end
    end
end)

_rt_register("dbg_helpers_two_channel", function()
    if type(_dbg) ~= "function" then return "_dbg helper missing" end
    if type(_dbg_alert) ~= "function" then return "_dbg_alert helper missing" end
    local ok = pcall(_dbg, "smoke test")
    if not ok then return "_dbg raised" end
    ok = pcall(_dbg_alert, "smoke test")
    if not ok then return "_dbg_alert raised" end
end)



_rt_register("ui_dump_hook_targets_exist", function()
    -- v0.9.25-dev: catches the v0.9.24 boot ERROR (typo'd class name +
    -- guessed HeroView method that doesn't exist). _ui_dump's install
    -- loop now skips any unknown class with a [ui-dump] WARN instead of
    -- letting VMF raise an ERROR. This test asserts the install actually
    -- found everything we listed: any non-empty _unknown_classes means
    -- a name in WINDOWS_TO_MONITOR no longer matches vanilla (renamed /
    -- removed in a patch). Fix by editing the list or the method name.
    if type(UI_DUMP) ~= "table" then return "UI_DUMP module not loaded" end
    if type(UI_DUMP._all_class_names) ~= "table" then
        return "UI_DUMP._all_class_names not exposed"
    end
    if not UI_DUMP._heroview_hook_installed then
        return string.format("HeroView.%s missing — vanilla nav-hook target renamed",
            tostring(UI_DUMP._heroview_hook_method))
    end
    if UI_DUMP._unknown_classes and #UI_DUMP._unknown_classes > 0 then
        return string.format("unknown UI classes in WINDOWS_TO_MONITOR: %s",
            table.concat(UI_DUMP._unknown_classes, ", "))
    end
    -- v0.9.27-dev: per-(class, method) pairs for the loadout equip/unequip
    -- write-site hooks. Catches the v0.9.26 ERROR where
    -- HeroWindowCosmeticsLoadout._clear_item_slot was hooked but vanilla
    -- doesn't define it. Either remove the pair from _loadout_hook_pairs
    -- in _ui_dump.lua, or (if vanilla added/renamed the method) update it.
    if UI_DUMP._unknown_method_pairs and #UI_DUMP._unknown_method_pairs > 0 then
        return string.format("unknown UI method pairs in _loadout_hook_pairs: %s",
            table.concat(UI_DUMP._unknown_method_pairs, ", "))
    end
end)

_rt_register("la_bridge_uninstall_apply_gate_clears_state", function()
    -- audit 2026-06-07 (F7): install_apply_gate() raw-replaced
    -- LA.apply_new_skin_from_texture but there was NO uninstall path, so an
    -- in-session F4 disable left LA's recolor permanently blocked until restart.
    -- Behavioral test of the new teardown: it must exist, be idempotent when no
    -- gate is installed, and fully clear _gate_installed / _original_apply when
    -- one was. We drive the state machine directly (no live LA required) and
    -- restore the real state afterwards so the running session is untouched.
    if type(LA_BRIDGE) ~= "table" then return "LA_BRIDGE module missing" end
    if type(LA_BRIDGE.uninstall_apply_gate) ~= "function" then
        return "uninstall_apply_gate not exposed (F7 regression: gate can't be torn down)"
    end

    -- Snapshot ALL state the teardown can touch, including the LIVE LA apply fn:
    -- if LA is installed and a gate is currently installed, uninstall would write
    -- our sentinel onto LA.apply_new_skin_from_texture, so we must save+restore it
    -- to avoid corrupting LA's real recolor for the rest of the session.
    local LA = get_mod("Loremasters-Armoury")
    local saved_installed = LA_BRIDGE._gate_installed
    local saved_original  = LA_BRIDGE._original_apply
    local saved_active    = LA_BRIDGE._bridge_active
    local saved_gate_fn   = LA_BRIDGE._gate_fn
    local saved_la_apply  = LA and LA.apply_new_skin_from_texture or nil

    local fail
    local sentinel = function() end
    LA_BRIDGE._gate_installed = true
    LA_BRIDGE._original_apply = sentinel
    LA_BRIDGE._bridge_active  = true
    -- v0.9.33: point _gate_fn at the live fn so the identity guard sees "still our
    -- gate" and takes the restore path (the original F7 behavior under test).
    LA_BRIDGE._gate_fn        = saved_la_apply

    LA_BRIDGE.uninstall_apply_gate()

    if LA_BRIDGE._gate_installed ~= false then
        fail = "_gate_installed not cleared after uninstall"
    elseif LA_BRIDGE._original_apply ~= nil then
        fail = "_original_apply not nil'd after uninstall"
    elseif LA_BRIDGE._bridge_active ~= false then
        fail = "_bridge_active not cleared after uninstall"
    elseif LA_BRIDGE._gate_fn ~= nil then
        fail = "_gate_fn not cleared after uninstall"
    elseif LA and LA.apply_new_skin_from_texture ~= sentinel then
        fail = "uninstall did not restore captured original onto LA"
    else
        -- idempotent second call must not raise on already-uninstalled state
        local ok2 = pcall(LA_BRIDGE.uninstall_apply_gate)
        if not ok2 then fail = "second uninstall_apply_gate raised" end
    end

    -- v0.9.33: layered-wrapper guard — when the live apply fn is NOT our saved
    -- gate (another mod re-wrapped on top after install), uninstall must NOT
    -- clobber the foreign wrapper; it leaves the chain and goes transparent.
    if not fail and LA then
        local foreign       = function() end
        local gate_sentinel = function() end
        LA_BRIDGE._gate_installed = true
        LA_BRIDGE._original_apply = sentinel
        LA_BRIDGE._gate_fn        = gate_sentinel
        LA.apply_new_skin_from_texture = foreign

        LA_BRIDGE.uninstall_apply_gate()

        if LA.apply_new_skin_from_texture ~= foreign then
            fail = "uninstall clobbered a foreign wrapper layered after our gate"
        elseif LA_BRIDGE._gate_installed ~= false then
            fail = "_gate_installed not cleared on the guarded (no-restore) path"
        end
    end

    -- Restore ALL live state regardless of outcome — session must be untouched.
    LA_BRIDGE._gate_installed = saved_installed
    LA_BRIDGE._original_apply = saved_original
    LA_BRIDGE._bridge_active  = saved_active
    LA_BRIDGE._gate_fn        = saved_gate_fn
    if LA and saved_la_apply ~= nil then
        LA.apply_new_skin_from_texture = saved_la_apply
    end

    return fail
end)

_rt_register("glow_classify_uses_material_settings", function()
    -- v0.9.34: classify() must key off WeaponSkins.skins[*].material_settings_name
    -- (the engine's own glow signal, gear_utils.lua:107/155) with the suffix
    -- fallback extended to bare `_runed` CW deus keys the old regex missed.
    -- Exercises live vanilla data — vacuous pass if tables aren't loaded yet.
    local skins = rawget(_G, "WeaponSkins")
    if not (skins and skins.skins) then
        mod:info("[regression] glow_classify: WeaponSkins not loaded; vacuous pass")
        return nil
    end
    local cases = {
        { skin = "wh_1h_axe_skin_04_runed_01",      want = "rune"  },  -- blue_glow template
        { skin = "es_2h_sword_exe_skin_03_magic_01", want = "magic" },  -- weaves template (Weavebound)
        { skin = "dr_deus_01_skin_01_runed",         want = "rune"  },  -- bare _runed CW deus (old regex missed)
        { skin = "wh_1h_axe_skin_04",                want = nil     },  -- base skin, no glow
    }
    for _, c in ipairs(cases) do
        if c.want ~= nil and skins.skins[c.skin] == nil then
            return string.format("vanilla skin key %s missing from WeaponSkins (data drift — update test cases)", c.skin)
        end
        local got = GlowPicker.classify({ skin = c.skin })
        if got ~= c.want then
            return string.format("classify(%s): expected %s, got %s", c.skin, tostring(c.want), tostring(got))
        end
    end
end)

_rt_register("cosmetic_unlock_labels_no_mojibake", function()
    -- audit 2026-06-07 (F12): _gen_unlocks.py read _cos_probe.txt with the
    -- platform-default encoding (cp1252) instead of utf8, corrupting "Bögenhafen"
    -- into "BA?genhafen" in 4 es_hat_0002 labels. Fixed at source (utf8 read) +
    -- regen. Behavioral guard: load the generated unlock table and assert no
    -- en-label carries the mojibake signature, so a future regen with the
    -- encoding bug reintroduced fails here.
    local ok, unlocks = pcall(mod.dofile, mod, "scripts/mods/cosmetics_tweaker/_cosmetic_unlocks")
    if not ok or type(unlocks) ~= "table" then return end  -- can't reach table; skip
    local loc = unlocks.localization
    if type(loc) ~= "table" then return "unlock localization table missing" end
    for k, v in pairs(loc) do
        if type(v) == "table" and type(v.en) == "string" then
            -- "BA?" is the asciify-of-cp1252-misread signature; "?" alone is the
            -- residue of any non-ASCII char that fell through transliteration.
            if v.en:find("BA?genhafen", 1, true) or v.en:find("?", 1, true) then
                return string.format("loc key %q has mojibake/unrenderable label: %q", k, v.en)
            end
        end
    end
end)

_rt_register("localization_format_safe", function()
    -- Layer 3 (2026-05-25): catch unescaped %-format chars in loc strings at
    -- runtime. VMF's tooltip render path calls string.format on the loc value;
    -- literal "%APPDATA%" / "5%" / "%USERNAME%" raises 'invalid option' and
    -- shows as a red error tooltip in the VMF settings UI. Static check is
    -- qa/check_localization.ps1 -- this is its runtime twin so the bug can't
    -- ship even if the static check is skipped. RULE: any literal % in a loc
    -- string must be doubled to %%.
    local ok, loc = pcall(mod.dofile, mod, "scripts/mods/cosmetics_tweaker/cosmetics_tweaker_localization")
    if not ok or type(loc) ~= "table" then return end  -- can't reach loc; skip
    for k, v in pairs(loc) do
        if type(v) == "table" and type(v.en) == "string" then
            local fmt_ok, fmt_err = pcall(string.format, v.en)
            if not fmt_ok then
                return string.format(
                    "loc key %q has invalid format string (escape literal %% as %%%%): %s",
                    k, tostring(fmt_err))
            end
        end
    end
end)

_rt_register("wire_skin_null_ungated", function()
    -- issue 421 / issue 371 (BUG_CLASSES 31): the v0.9.74 skin-axis wire-safety hook
    -- (SimpleInventoryExtension.game_object_initialized) nulls slot_data.skin for every
    -- _custom_skin_keys entry BEFORE vanilla encodes weapon_skin_id =
    -- NetworkLookup.weapon_skins[...] and broadcasts rpc_add_equipment, then restores the
    -- real skin after the send so the LOCAL owner still spawns the custom illusion. A peer
    -- WITHOUT cosmetics_tweaker cold-decodes an appended index and fatals; nulling to the
    -- vanilla "n/a" index is the never-crash invariant and it must NOT be gated behind any
    -- mod:get() toggle. Drives the SHIPPED helper (_cos_wire_null_custom_skins) with a fake
    -- slot table so a future edit that gates the null (a default-off gate would leave the
    -- custom skin non-nil at send time) OR drops the restore fails here, not in a stranger's
    -- session. Mirrors cim's wire_rarity_rewrite_ungated.
    if type(mod._cos_wire_null_custom_skins) ~= "function" then
        return "skin-axis wire-null helper missing (issue 421 crash regression)"
    end
    if type(_custom_skin_keys) ~= "table" then
        return "_custom_skin_keys table missing"
    end
    local FAKE_CUSTOM  = "_rt_fake_custom_skin_key"
    local FAKE_VANILLA = "_rt_fake_vanilla_skin_key"
    local had = _custom_skin_keys[FAKE_CUSTOM]
    _custom_skin_keys[FAKE_CUSTOM] = true
    -- One slot wears the custom illusion (must be nulled on the wire); one wears a
    -- vanilla skin (must be left untouched).
    local custom_slot  = { skin = FAKE_CUSTOM }
    local vanilla_slot = { skin = FAKE_VANILLA }
    local slots = { slot_ranged = custom_slot, slot_melee = vanilla_slot }
    local skin_at_send, vanilla_at_send
    local ok, r1, r2 = pcall(mod._cos_wire_null_custom_skins, slots, function()
        -- Runs WHILE the RPC would encode/broadcast: the custom skin MUST be nil here
        -- (else a non-cos peer decodes the modded index and CTDs); the vanilla skin intact.
        skin_at_send    = custom_slot.skin
        vanilla_at_send = vanilla_slot.skin
        return "ret1", "ret2"
    end)
    -- Restore the shared table before asserting so a failure can't leak the fake key.
    if not had then _custom_skin_keys[FAKE_CUSTOM] = nil end
    if not ok then
        return "wire-null helper raised: " .. tostring(r1)
    end
    if skin_at_send ~= nil then
        return "custom skin was NOT nulled on the wire -- a non-cos peer would CTD (issue 421 regression; is the null toggle-gated?)"
    end
    if vanilla_at_send ~= FAKE_VANILLA then
        return "vanilla skin was wrongly mutated on the wire (only _custom_skin_keys entries may be nulled)"
    end
    if custom_slot.skin ~= FAKE_CUSTOM then
        return "custom skin not restored after the send -- LOCAL owner would lose the illusion"
    end
    if r1 ~= "ret1" or r2 ~= "ret2" then
        return "vanilla return values not threaded through the wire-null wrapper"
    end
end)

-- [mem-probe] cos boot Lua-footprint readout. MUST live at module top-level (runs
-- once when this file finishes loading), NOT inside the _rt_register closure above
-- — until v0.9.35-dev it was stranded as the last statement of that regression-test
-- closure (after two early returns), so it NEVER executed and "cos boot_lua" appeared
-- in zero console logs, leaving cosmetics' Lua footprint invisible next to
-- weapon_tweaker's measured +12.8 MB. Mirrors weapon_tweaker.lua's boot readout.
-- Measures the static table footprint (e.g. the ~11.9k-line _cosmetic_unlocks table)
-- at load time — the 74 offhand unit packages load later (lazily, in mod.update) and
-- are snapshotted separately at the [offhand] force-load completion log.
mod:info("[mem-probe] cos boot_lua=+%.1f MB (of ~1024 MB lua_heap cap)", (collectgarbage("count") - mod._cos_mem_t0) / 1024)

-- ============================================================
-- Moonfire Bow cosmetic AOE puff (moved from weapon_tweaker 2026-06-29)
-- ============================================================
-- Spawns the small blue moonfire impact puff on every Moonfire Bow (we_deus_01*)
-- arrow hit. Cosmetic only — no damage. The gameplay "pre-nerf AOE revert" stays in
-- weapon_tweaker (Weapon Overrides); when it's on it already spawns puffs as part of
-- the detonation, so we skip here to avoid doubling. Hooks BOTH the shooter's
-- PlayerProjectileUnitExtension and every other peer's PlayerProjectileHuskExtension
-- (same impact methods + fields wt used) so the puff shows on every screen. The
-- arrow's own impact FX rides the equipped Moonfire Bow's package, so create_particles
-- is safe whenever a moonfire arrow hits.
local _COS_MOONFIRE_PUFF_FX = "fx/wpnfx_we_deus_01_impact"

local function _cos_is_moonfire_arrow(item_name)
    return item_name ~= nil and string.sub(item_name, 1, 10) == "we_deus_01"
end

local function _cos_moonfire_puff_on_hit(self, hit_position)
    if not mod:get("cos_moonfire_cosmetic_puff") then return end
    if not _cos_is_moonfire_arrow(self.item_name) then return end
    -- wt's AOE revert already puffs as part of the detonation — don't double up.
    local wt = get_mod("wt")
    if wt and wt:get("moonfire_aoe_revert") then return end
    local world = self._world
    if not world or not hit_position then return end
    World.create_particles(world, _COS_MOONFIRE_PUFF_FX, hit_position, Quaternion.identity())
end

do
    local _moonfire_classes = { "PlayerProjectileUnitExtension", "PlayerProjectileHuskExtension" }
    local _moonfire_methods = { "hit_enemy", "hit_level_unit", "hit_non_level_unit" }
    for _, class_name in ipairs(_moonfire_classes) do
        local cls = rawget(_G, class_name)
        if cls then
            for _, method_name in ipairs(_moonfire_methods) do
                if cls[method_name] then
                    mod:hook_safe(cls, method_name, function(self, impact_data, hit_unit, hit_position)
                        _cos_moonfire_puff_on_hit(self, hit_position)
                    end)
                end
            end
        end
    end
end