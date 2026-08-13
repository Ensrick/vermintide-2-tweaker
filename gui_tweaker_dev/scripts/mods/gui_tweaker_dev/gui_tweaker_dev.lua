local mod = get_mod("gut_dev")
-- #925: attach to the copied shared local-process presentation generation
-- ledger. GUT publishes only when no inner provider (normally Cosmetics'
-- existing BackendUtils hook) already published the same set_loadout action.
mod._ui_presentation_refresh_lib = mod:dofile(
    "scripts/mods/gui_tweaker_dev/_lib_ui_presentation_refresh")
mod._ui_presentation_refresh, mod._ui_presentation_refresh_error =
    mod._ui_presentation_refresh_lib.attach(_G, "gut_dev", 32)
mod._gut925_generation = function()
    local client = mod._ui_presentation_refresh
    local stats = client and client:stats()
    return stats and stats.generation or nil
end
mod._gut925_publish_if_unobserved = function(before_generation, career_name,
        slot_name, backend_id, item)
    local client = mod._ui_presentation_refresh
    if not client then return end
    local stats = client:stats()
    if not mod._ui_presentation_refresh_lib.generation_unchanged(
            before_generation, stats.generation) then
        return -- an inner provider already published this exact mutation
    end
    local item_data = item and item.data
    client:publish({
        kind = "loadout",
        reason = "saved-loadout-restore",
        career_name = career_name,
        slot_name = slot_name,
        backend_id = backend_id,
        item_key = item and (item.key or (item_data and item_data.name)),
    })
end
-- [mem-probe] temp Lua-footprint baseline (lua_heap 1 GiB cap diagnostic). Namespaced under
-- the mod table (v0.2.216-dev) so it no longer leaks into _G; read at the boot readout near
-- the end of this file.
mod._gut_mem_t0 = collectgarbage("count")

local MOD_VERSION = "0.2.332-dev"

-- Two-helper debug-logging policy (PROJECT_STANDARDS.md § 3.6).
-- Both route through VMF's built-in logging, gated by VMF output_mode_debug /
-- output_mode_warning. No per-mod toggle.
-- `_dbg` is for confirmation / expected behavior — debug channel only.
-- `_dbg_alert` is for unexpected / wrong / mismatch — warning channel only.
local function _dbg(fmt, ...)
    mod:debug("[gut:dbg] " .. fmt, ...)
end

local function _dbg_alert(fmt, ...)
    -- (warnings noise) mod:warning was demoted here because these [gut:dbg] traces (e.g. HUD
    -- widget_init_skip when a scenegraph node isn't present in the keep) are diagnostics, not
    -- real problems, and at warning level they spammed the in-game chat.
    -- #427: mod:debug was the wrong landing spot -- it is gated off by default, so the alert
    -- emitted nothing at all. Route to LOG-ONLY pcall-guarded engine printf like every other
    -- migrated `_dbg_alert`: printf survives mod-logging-OFF and never reaches chat.
    if not pcall(printf, "[gut:dbg] " .. fmt, ...) then
        pcall(printf, "[gut:dbg] (alert format error: %s)", tostring(fmt))
    end
end

-- Applied marker (PROJECT_STANDARDS.md § 3.6 "Applied marker line (universal)").
-- Walks the data widget tree, FNV-1a-32 hashes setting=value pairs, prints
-- one mod:info line at load. ALWAYS fires (operational telemetry).
local function _settings_fingerprint()
    local ok, data = pcall(require, "scripts/mods/gui_tweaker_dev/gui_tweaker_data")
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

pcall(printf, "[gut:LOAD] v%s enabled fp=%s OK", MOD_VERSION, _settings_fingerprint())

-- Per PROJECT_STANDARDS § 3.6 + § 14a: dev/alpha/beta/0.x versions print
-- version to chat on load so the user can see what's active. Stable
-- (>=1.0.0) versions stay silent. Detect via MOD_VERSION string match.
if MOD_VERSION:find("-dev$") or MOD_VERSION:find("-alpha$") or MOD_VERSION:find("-beta$") or MOD_VERSION:find("-rc%d*$") or MOD_VERSION:find("^0%.") then
    mod:echo(string.format("[gut] v%s loaded", MOD_VERSION))
end

-- v0.2.1-dev: proper _RT_CHECKS regression scaffold (previously a one-line stub).
local _RT_CHECKS = {}
local function _rt_register(name, fn)
    _RT_CHECKS[#_RT_CHECKS + 1] = { name = name, fn = fn }
end
mod._gut_rt_register = _rt_register

-- (#511) io-safe source reader. The VMF retail sandbox exposes NO `io` library
-- (mods are loadstring'd into the game's shared _G by mod_manager.lua:375-386, and
-- the retail Stingray VM never registers `io` -- it registers `os` (mod_manager uses
-- os.date unguarded at :313) but not `io`). A bare `io.open` therefore throws
-- "attempt to index global 'io' (a nil value)", which the regression runner's pcall
-- catches and reports as a FALSE FAIL on healthy code (issue 479 log). Every
-- source-pattern check below routes its source read through this helper, which
-- returns nil (-> the check's "unreadable source => skip" branch, a PASS) instead of
-- throwing. In retail the source-text half is therefore skipped; the RUNTIME markers
-- each check asserts (anchor function / vanilla class / gate behavior) are the
-- authoritative in-game signal, and the source-text needles move to the repo QA
-- gates (PROJECT_STANDARDS 2.2b tier a). Source IS readable under the modding-tools
-- executable / CI, where these needles still run in full.
local function _rt_src_read(path)
    local io_lib = rawget(_G, "io")
    if type(io_lib) ~= "table" or type(io_lib.open) ~= "function" then
        return nil
    end
    local f = io_lib.open(path, "r")
    if not f then return nil end
    local t = f:read("*a")
    f:close()
    return t
end
mod:command("gut_regression_test", "GUI tweaker self-check", function()
    local pass, fail = 0, 0
    mod:echo("=== gut_regression_test (v%s) ===", MOD_VERSION)
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

mod:command("lua_mem", "Print live Lua heap usage (per-mod memory measurement). Optional label: /lua_mem <label>", function(label)
    -- Diagnostic for the VT2 1 GiB lua_heap cap crash ("Not enough memory
    -- reserved for heap lua_heap", reserved 1073741824). Forces a full GC so the
    -- reading is the LIVE footprint (not transient garbage), then reports
    -- collectgarbage("count").
    -- Find a heavy mod: disable all suspects -> launch -> load a level ->
    --   /lua_mem baseline ; then enable ONE mod -> relaunch -> load a level ->
    --   /lua_mem <modname>. The jump between readings is that mod's footprint.
    -- The engine lua_heap holds bytecode + C-side Lua structures ON TOP of this,
    -- so treat the number as a lower-bound proxy and compare DELTAS, not absolutes.
    collectgarbage("collect")
    collectgarbage("collect")
    local kb = collectgarbage("count")
    local lbl = (label and label ~= "") and (" | " .. tostring(label)) or ""
    mod:echo("[lua_mem] %.1f MB live Lua (%.0f KB) -- lua_heap cap is ~1024 MB%s", kb / 1024, kb, lbl)
    mod:info("[lua_mem] live_lua_mb=%.1f live_lua_kb=%.0f label=%s", kb / 1024, kb, tostring(label or ""))
end)

_rt_register("dbg_helpers_two_channel", function()
    if type(_dbg) ~= "function" then return "_dbg helper missing" end
    if type(_dbg_alert) ~= "function" then return "_dbg_alert helper missing" end
    local ok = pcall(_dbg, "smoke test")
    if not ok then return "_dbg raised" end
    ok = pcall(_dbg_alert, "smoke test")
    if not ok then return "_dbg_alert raised" end
end)

_rt_register("issue925_loadout_presentation_publish", function()
    if not mod._ui_presentation_refresh then
        return "shared presentation ledger unavailable: "
            .. tostring(mod._ui_presentation_refresh_error)
    end
    if type(mod._gut925_generation) ~= "function"
            or type(mod._gut925_publish_if_unobserved) ~= "function" then
        return "GUT saved-loadout presentation publisher missing"
    end
    local stats = mod._ui_presentation_refresh:stats()
    if stats.capacity > 128 or stats.retained > stats.capacity then
        return "shared presentation ledger exceeded its bounded capacity"
    end
end)

_rt_register("lifecycle_chain_integrity", function()
    -- issue 425 coverage (audit finding F3): the mod splits ~15 VMF lifecycle callbacks
    -- across 48 files using the capture-prev idiom (`local prev = mod.X; mod.X = function(...)
    -- ...; prev(...) end`). Correct everywhere today, but convention-only -- one file that
    -- forgets the capture silently orphans every earlier-loaded handler with no error. This
    -- drives the on_setting_changed chain end to end: the root handler recognizes a synthetic
    -- probe id (an unknown id every feature handler ignores while still calling prev), so
    -- driving the CURRENT outermost on_setting_changed must walk the whole chain back to the
    -- root and flip the flag. mod.update / mod.on_game_state_changed / mod.on_disabled use the
    -- identical idiom under the same discipline; on_setting_changed is the most-wrapped chain
    -- and the only one an unknown id can drive side-effect-free from any menu state, so it is
    -- the representative integrity proof.
    if type(mod.on_setting_changed) ~= "function" then
        return "mod.on_setting_changed not installed"
    end
    if type(mod._gut_chain_probe) ~= "table" then
        return "chain probe table missing (root handler probe not installed)"
    end
    mod._gut_chain_probe.on_setting_changed = false
    local ok, err = pcall(mod.on_setting_changed, "__gut_chain_probe__")
    if not ok then
        return "driving the on_setting_changed chain raised: " .. tostring(err)
    end
    if not mod._gut_chain_probe.on_setting_changed then
        return "on_setting_changed chain BROKEN: a chaining site dropped its predecessor (earlier-loaded handlers are orphaned)"
    end
end)

_rt_register("mission_map_backdrop_swap", function()
    -- (#336) Mid-mission map CTD guard: the can_get trust-protocol helper must be
    -- wired and the vanilla window must still expose all three hooked methods (a vanilla
    -- rename would silently orphan the swap and re-expose the crash).
    if type(mod._gut_mm_can_get_level) ~= "function" then return "_gut_mm_can_get_level missing" end
    if type(mod.gut_open_mission_map) ~= "function" then return "gut_open_mission_map missing" end
    local w = rawget(_G, "StartGameWindowBackgroundConsole")
    if type(w) ~= "table" then return "StartGameWindowBackgroundConsole class missing" end
    if type(w._create_viewport_definition) ~= "function" then return "_create_viewport_definition missing" end
    if type(w._update_object_sets) ~= "function" then return "_update_object_sets missing" end
    if type(w._setup_object_sets) ~= "function" then return "_setup_object_sets missing" end
    -- (#336 follow-up) The none tier must stay wired: the level-less-def branch marks
    -- _gut_mm_none_backdrop, and the _setup_object_sets divert reads it. Introspect the
    -- module source via the public open function; needle split so this line can't self-match.
    local ok, info = pcall(debug.getinfo, mod.gut_open_mission_map, "S")
    if ok and type(info) == "table" and info.source then
        local src_path = info.source:sub(1, 1) == "@" and info.source:sub(2) or info.source
        local txt = _rt_src_read(src_path)  -- (#511) io-safe; nil in retail sandbox => skip
        if txt and not txt:find("_gut_mm_none" .. "_backdrop", 1, true) then
            return "#336 regression: the none-tier marker _gut_mm_none_backdrop is gone (map fail-closes again when no backdrop level is resident)"
        end
    end
end)

-- (#336 CRASH) Mid-mission map area-video guard: BOTH layers must survive. Layer 1 is the
-- AreaSettings video-material injection in _gut_gui_material_guard.lua (located as a
-- sibling of the map module); layer 2 is the video-widget skip guard on the two
-- area-selection windows in _gut_mission_map.lua. If either is removed, hovering an area
-- on the mid-mission map takes the uncatchable "Material 'area_video_*' not found in Gui"
-- draw fatal again (shipped ui_renderer.lua:1345; crash console-2026-07-06-03.24.08).
-- Split needles so this check can't self-match. No-op if files unreadable.
_rt_register("area_video_guard_two_layers", function()
    local ok, info = pcall(debug.getinfo, mod.gut_open_mission_map or function() end, "S")
    if not ok or type(info) ~= "table" or not info.source then return end
    local map_path = info.source:sub(1, 1) == "@" and info.source:sub(2) or info.source
    local read_all = _rt_src_read  -- (#511) io-safe; nil in retail sandbox => skip
    -- Layer 2: the skip guard in the map module (both windows + the drawable check).
    local map_txt = read_all(map_path)
    if map_txt then
        if not map_txt:find("_area_video" .. "_drawable", 1, true) then
            return "#336 regression: _area_video_drawable is gone from the map module (area videos draw unguarded -> mid-mission draw fatal)"
        end
        if not map_txt:find('"_assign_video' .. '_player"', 1, true) then
            return "#336 regression: the StartGameWindowAreaSelectionConsoleV2._assign_video_player skip guard is gone (console-layout area hover crashes mid-mission again)"
        end
        if not map_txt:find('"_setup_video' .. '_player"', 1, true) then
            return "#336 regression: the StartGameWindowAreaSelection._setup_video_player skip guard is gone (PC-layout area hover crashes mid-mission again)"
        end
    end
    -- Layer 1: the injection + publish in the sibling material guard.
    local dir = map_path:match("^(.*[/\\])[^/\\]*$")
    local guard_txt = dir and read_all(dir .. "_gut_gui_material_guard.lua")
    if guard_txt then
        if not guard_txt:find("_area_video" .. "_entries", 1, true) then
            return "#336 regression: the AreaSettings video-material enumeration is gone from the GUI guard (no injection -> keep-only materials mid-mission)"
        end
        if not guard_txt:find("if append" .. "_areas then", 1, true) then
            return "#336 regression: the append_areas residency gate is gone -- area videos no longer injected into ingame renderers"
        end
        if not guard_txt:find("mod._gut_area_videos" .. "_ingame", 1, true) then
            return "#336 regression: the per-material publish (mod._gut_area_videos_ingame) is gone -- the map module's skip guard falls back to keep-only heuristics"
        end
    end
    -- The two hooked vanilla methods must still exist (a vanilla rename would orphan the
    -- guards and re-expose the crash). Classes load with ingame_ui at boot.
    local v2 = rawget(_G, "StartGameWindowAreaSelectionConsoleV2")
    if type(v2) == "table" and type(v2._assign_video_player) ~= "function" then
        return "vanilla drift: StartGameWindowAreaSelectionConsoleV2._assign_video_player missing (skip guard orphaned)"
    end
    local pc = rawget(_G, "StartGameWindowAreaSelection")
    if type(pc) == "table" and type(pc._setup_video_player) ~= "function" then
        return "vanilla drift: StartGameWindowAreaSelection._setup_video_player missing (skip guard orphaned)"
    end
end)

-- (#336) Mid-mission map PREVIEW backdrop: the package-load + def-swap must survive. The
-- tier-2 swap mounts levels/ui_inventory_preview/world (gated on has_loaded of its managed
-- package under the module's own ref) so the map has a real, framebuffer-clearing menu
-- backdrop mid-mission; losing any piece regresses to the v0.2.198 black plate +
-- button-glow bleeding. Split needles so this check can't self-match. No-op if unreadable.
_rt_register("mission_map_preview_backdrop", function()
    -- (#511) Runtime marker: the map module's public entry must be wired (proves the
    -- module loaded and ran). The source-text needles below are dev/CI-only (io-safe).
    if type(mod.gut_open_mission_map) ~= "function" then
        return "#336 regression: gut_open_mission_map not wired (mission map module failed to load -- preview backdrop gone)"
    end
    local ok, info = pcall(debug.getinfo, mod.gut_open_mission_map, "S")
    if not ok or type(info) ~= "table" or not info.source then return end
    local map_path = info.source:sub(1, 1) == "@" and info.source:sub(2) or info.source
    local txt = _rt_src_read(map_path)  -- (#511) io-safe; nil in retail sandbox => skip
    if not txt then return end
    if not txt:find("resource_packages/levels/ui_inventory" .. "_preview", 1, true) then
        return "#336 regression: the preview-stage package path is gone from the map module (no backdrop package load)"
    end
    if not txt:find("_kick_preview_pkg" .. "_load", 1, true) then
        return "#336 regression: the preview-package async load kick is gone (map never gets the preview backdrop)"
    end
    if not txt:find("has_loaded(PREVIEW" .. "_PKG, MM_PKG_REF)", 1, true) then
        return "#336 regression: the has_loaded package gate is gone from the def-swap (v0.2.190 lesson: can_get('level') is false until the PACKAGE loads; ungated mount = C-fatal, gated absence = black plate)"
    end
    if not txt:find("level_name = PREVIEW" .. "_LEVEL", 1, true) then
        return "#336 regression: the tier-2 def no longer mounts the preview level (black backdrop + glow bleeding return)"
    end
end)

_rt_register("arrow_hover_native_size", function()
    -- (#92/#99) The arrow hover/glow overlay must be the BIGGER native sprite (30x35), NOT the
    -- 19x27 base — drawing it at base size made the glow too small + misplaced. Build a stepper
    -- row and assert the overlay styles match the vanilla size, so the fix can't silently revert
    -- (ground truth: options_view_definitions.lua left_arrow_hover :2206-2216 size 30x35).
    local ok, defs = pcall(mod.dofile, mod, "scripts/mods/gui_tweaker_dev/_mod_tweaker_definitions")
    if not ok or type(defs) ~= "table" or type(defs.create_checkbox) ~= "function" then
        return "definitions/create_checkbox unavailable"
    end
    local ok2, w = pcall(defs.create_checkbox, "RT", { 0, 0, 0 }, 0)
    if not ok2 or type(w) ~= "table" or type(w.style) ~= "table" then
        return "create_checkbox build failed: " .. tostring(w)
    end
    for _, k in ipairs({ "left_arrow_hover", "right_arrow_hover" }) do
        local ts = w.style[k] and w.style[k].texture_size
        if type(ts) ~= "table" or ts[1] ~= 30 or ts[2] ~= 35 then
            return string.format("%s texture_size=%s (want {30,35})", k,
                ts and ("{" .. tostring(ts[1]) .. "," .. tostring(ts[2]) .. "}") or tostring(ts))
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
    local ok, loc = pcall(mod.dofile, mod, "scripts/mods/gui_tweaker_dev/gui_tweaker_dev_localization")
    if not ok or type(loc) ~= "table" then
        return "localization table could not be loaded: " .. tostring(loc)
    end
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

_rt_register("all_languages_defer_340", function()
    -- (#340) The all-languages feature is DETECT-AND-DEFER, not a font swap. The source
    -- mod "Support All Languages" (3232229691) ships a CUSTOM ~32 MB CJK atlas in its own
    -- bundle (see _gut_all_languages.lua header), so gut cannot re-point Fonts at it —
    -- doing so would target a material gut does not ship (Gui material-not-found for every
    -- text surface). This check pins the module to a pure defer: it must LOAD and it must
    -- NEVER perform the swap or install hooks. If a future edit sets does_font_swap true
    -- (or the module fails to load), this fails.
    local t = mod._GUT_ALL_LANGUAGES
    if type(t) ~= "table" then
        return "#340 regression: _gut_all_languages module didn't load (mod._GUT_ALL_LANGUAGES missing)"
    end
    if t.does_font_swap ~= false then
        return "#340 regression: all-languages module now swaps Fonts (does_font_swap ~= false) -- gut ships no atlas, so this points every text surface at a missing material"
    end
    if t.installs_hooks ~= false then
        return "#340 regression: all-languages module now installs hooks (it must stay a pure detect-and-defer no-op)"
    end
    if t.case ~= "custom_font_resource_case2" then
        return "#340 regression: all-languages case changed from custom_font_resource_case2 (the ported mod ships its own font bundle -- re-verify before changing the port shape)"
    end
    if type(t.inspect_fonts) ~= "function" or type(t.inspect_player_names) ~= "function"
        or type(t.utf8_metrics) ~= "function" or type(t.glyph_samples) ~= "table"
        or #t.glyph_samples ~= 6 then
        return "#340 regression: bounded font/glyph/player-name diagnostics are incomplete"
    end
    for _, sample in ipairs(t.glyph_samples) do
        local metrics = t.utf8_metrics(sample.text)
        if type(sample.label) ~= "string" or type(metrics) ~= "table" or metrics.valid ~= true then
            return "#340 regression: glyph diagnostic sample is not valid UTF-8"
        end
    end
    -- Source guard (io-safe; nil in retail => skip, runs under tools/CI): the module must
    -- not contain a live Fonts[1] assignment. Needle split so this line can't self-match.
    local ok, info = pcall(debug.getinfo, function() return mod._GUT_ALL_LANGUAGES end, "S")
    if ok and type(info) == "table" and info.source then
        local dir = (info.source:sub(1, 1) == "@" and info.source:sub(2) or info.source):match("^(.*[/\\])[^/\\]*$")
        local txt = dir and _rt_src_read(dir .. "_gut_all_languages.lua")
        if txt and txt:find("arial%[1%]%s*=%s*arial" .. "_unicode_path") then
            return "#340 regression: _gut_all_languages.lua reintroduced the Fonts[1] swap from the source mod (gut ships no atlas -> broken render)"
        end
    end
end)

_rt_register("issue314_simple_ui_window_confinement", function()
    local compat = mod._gut_simple_ui_compat
    local policy = mod._gut_simple_ui_bounds_policy
    if type(compat) ~= "table" or compat.source_workshop_id ~= "1389872347" then
        return "#314 Simple UI compatibility module/source identity is missing"
    end
    if compat.phase ~= 1 or type(compat.tick) ~= "function" then
        return "#314 bounded phase-1 window recovery tick is not wired"
    end
    if type(policy) ~= "table" or type(policy.confine) ~= "function" then
        return "#314 pure window-confinement policy is missing"
    end
    local fit = policy.confine({ -10, 1000 }, { 400, 300 }, 1920, 1080)
    if not fit or fit.x ~= 0 or fit.y ~= 780 then
        return "#314 fitted-window clamp no longer confines both axes"
    end
    local oversized = policy.confine({ 50, 50 }, { 2200, 1400 }, 1920, 1080)
    if not oversized or oversized.x ~= 0 or oversized.y + 1400 ~= 1080 then
        return "#314 oversized window no longer retains a reachable top/title edge"
    end
end)

-- (#140) "A Parting of the Waves" (dlc_dwarf_whaling) stray post-skip fade fix
-- (v0.2.178-dev): while the #106 post-skip guard is armed for a CutsceneSystem
-- instance, flow_cb_cutscene_effect swallows every fx_fade. The map fires a late
-- fx_fade ~97 ms BEFORE its camera node, so the one-shot _skip_next_fade (armed at
-- the camera node) is still false when the fade arrives - the guard catches it.
-- Source-pattern guard on _gut_cutscenes.lua (located via mod.gut_skip_cutscenes_toggle,
-- defined there). CutsceneSystem class-presence is NOT asserted (it loads in-mission,
-- nil at the keep where this runs). Split needle so this line can't self-match. No-op
-- if unreadable.
_rt_register("cutscene_postskip_fade_swallow", function()
    -- (#511) Runtime marker: the cutscene module's public toggle must be wired.
    if type(mod.gut_skip_cutscenes_toggle) ~= "function" then
        return "#140 regression: gut_skip_cutscenes_toggle not wired (cutscene module failed to load)"
    end
    local ok, info = pcall(debug.getinfo, mod.gut_skip_cutscenes_toggle, "S")
    if not ok or type(info) ~= "table" or not info.source then return end
    local src_path = info.source:sub(1, 1) == "@" and info.source:sub(2) or info.source
    local txt = _rt_src_read(src_path)  -- (#511) io-safe; nil in retail sandbox => skip
    if not txt then return end
    -- ROUND 3 needle (issues 257/274 rework): the swallow site is the marker
    -- comment `_gut_cutscene_fade_swallow_site` plus the episode classifier
    -- call. The pre-rework expression needle (`_skipped_cutscene_system ==
    -- self and name == "fx_fade"`) went stale when the policy274 refactor
    -- renamed the guard read - marker comments survive refactors, expression
    -- needles do not. Split so this registration site cannot self-match.
    local marker_needle = "_gut_cutscene_fade_" .. "swallow_site"
    local classifier_needle = "classify_" .. "fade(_sw_state"
    if not txt:find(marker_needle, 1, true) or not txt:find(classifier_needle, 1, true) then
        return "#140/#257 regression: the fx_fade swallow classification site is gone from flow_cb_cutscene_effect (stray black fade returns on 'A Parting of the Waves' / dlc_dwarf_whaling)"
    end
end)
-- (issue 275) The Skip Cutscenes feature must NEVER latch script_data.skippable_cutscenes
-- ON at rest -- the retail default is unset. gut only SCOPE-unlocks it around a
-- skip_pressed call on a cutscene that carries a wired event_on_skip; a boss cinematic
-- with event_on_skip=nil (Nurgloth on The Enchanter's Lair / dlc_castle) must play out or
-- the fight desyncs and floors at ~66% health (softlock). This guards both the removed
-- global latch and the wired-skip gate that replaced it.
_rt_register("gut_cutscene_no_global_latch", function()
    -- 1. The wired-skip gate must exist and REFUSE a nil-on_skip cutscene while ACCEPTING
    --    a wired one -- this is the whole issue-275 policy in one function.
    local gate = mod._gut_cutscene_has_wired_skip
    if type(gate) ~= "function" then
        return "issue 275 regression: mod._gut_cutscene_has_wired_skip gate missing (cutscene skip gating removed?)"
    end
    if gate({ event_on_skip = nil }) ~= false then
        return "issue 275 regression: wired-skip gate ACCEPTS a nil event_on_skip cutscene (a locked boss cinematic would be skipped -> fight desync)"
    end
    if gate({ event_on_skip = "cs_01_skip" }) ~= true then
        return "issue 275 regression: wired-skip gate REJECTS a wired event_on_skip cutscene (mission-intro skips would break)"
    end
    -- 2. At rest (no cutscene in flight, e.g. run from the keep) the engine skip gate must
    --    be unset. gut never latches it; a truthy value means the load-time / toggle latch
    --    was re-introduced (verify with the source guard below; a co-installed cutscene mod
    --    could also set it).
    if script_data and script_data.skippable_cutscenes then
        return "issue 275 regression: script_data.skippable_cutscenes is truthy at rest (global latch re-introduced? retail leaves it unset)"
    end
    -- 3. Source guard on _gut_cutscenes.lua (located via the toggle fn's source): the
    --    removed toggle-time latch must stay gone and the gate must still be defined.
    local ok, info = pcall(debug.getinfo, mod.gut_skip_cutscenes_toggle or function() end, "S")
    if not ok or type(info) ~= "table" or not info.source then return end
    local src_path = info.source:sub(1, 1) == "@" and info.source:sub(2) or info.source
    local txt = _rt_src_read(src_path)  -- (#511) io-safe; nil in retail sandbox => skip
    if not txt then return end
    local toggle_latch = "skippable_cutscenes = new" .. "_val"   -- split so this file can't self-match
    if txt:find(toggle_latch, 1, true) then
        return "issue 275 regression: the toggle re-latches script_data.skippable_cutscenes (should only scope-unlock around skip_pressed)"
    end
    if not txt:find("_gut_cutscene_has_wired" .. "_skip", 1, true) then
        return "issue 275 regression: the _gut_cutscene_has_wired_skip gate is gone from _gut_cutscenes.lua"
    end
    -- 4. (issue 537) Source guard on the MAIN file too. Step 3 scans ONLY _gut_cutscenes.lua,
    --    so the on_setting_changed re-latch (which lives in gui_tweaker_dev.lua) escaped it
    --    and shipped for many versions. gui_tweaker_dev.lua is the sibling of the toggle's
    --    _gut_cutscenes.lua in the same directory, so derive its path from src_path and
    --    assert the persistent on_setting_changed skip-gate latch write stays removed. The
    --    needle is split so this check text can never self-match.
    local main_path = src_path:gsub("_gut_cutscenes%.lua$", "gui_tweaker_dev.lua")
    local main_txt = _rt_src_read(main_path)  -- (#511) io-safe; nil in retail sandbox => skip
    if not main_txt then return end
    local osc_latch = ".skippable_cutscenes = mod:" .. "get("
    if main_txt:find(osc_latch, 1, true) then
        return "issue 537 regression: on_setting_changed re-latches the engine skip gate (must restore the pre-gut value on disable, never latch on)"
    end
end)
-- ============================================================
-- Loadout Save/Restore (v0.1)
-- ============================================================
-- Clean reimplementation of loadout_manager_vt2's save/restore. The legacy
-- mod OR-merged gear and cosmetics into a single backend_id-per-slot lookup
-- and iterated `slots_by_slot_index`, which routed weapon-skin items
-- (slot_type=melee) into gear slots like slot_ranged and triggered the
-- engine's "cannot equip item in this slot type" rejection. We keep the
-- two namespaces strictly separated: gear iterates `slots_by_ui_slot_index`,
-- cosmetics iterate `slots_by_cosmetic_index`, and each item is validated
-- against its OWN target slot before any write.

local LOADOUT_SLOTS = 30

-- Local player + resolved career name. Returns (career_name, profile, career)
-- or (nil, reason) when no local player/profile is available.
local function _get_current_career()
    local pm = Managers.player
    if not pm then return nil, "Managers.player not available (not in a level?)" end
    local player = pm:local_player(1)
    if not player then return nil, "no local player" end
    local ok_pi, profile_index = pcall(player.profile_index, player)
    local ok_ci, career_index = pcall(player.career_index, player)
    if not (ok_pi and ok_ci and profile_index and career_index) then
        return nil, "could not read profile/career index"
    end
    local profile = SPProfiles and SPProfiles[profile_index]
    if not profile then return nil, "no profile for index " .. tostring(profile_index) end
    local career = profile.careers and profile.careers[career_index]
    if not career then return nil, "no career for index " .. tostring(career_index) end
    return career.name, profile, career
end

-- Localized career display name with safe fallback.
local function _career_display_name(career)
    if not career then return "?" end
    local key = career.display_name or career.name
    if not key then return "?" end
    local ok, name = pcall(Localize, key)
    return (ok and name) or key
end

-- Validate item slot-type compatibility before equipping. Vanilla's backend
-- reads the live CareerSettings item_slot_types_by_slot_name map for this exact
-- decision (playfab_mirror_base.lua:1662-1713, 3387-3402). Reading it on every
-- restore lets Career Tweaker add/remove Foot Knight secondary melee at runtime
-- without a GUT mod-identity dependency, cached clone, or hardcoded career list.
local _gut_loadout_slot_policy = mod:dofile(
    "scripts/mods/gui_tweaker_dev/_gut_loadout_slot_policy"
)

local function _validate_item_for_slot(item, slot_name, career_name)
    if type(_gut_loadout_slot_policy) ~= "table" or
       type(_gut_loadout_slot_policy.validate) ~= "function" then
        return false, "live career slot capability policy unavailable"
    end

    return _gut_loadout_slot_policy.validate(
        item and item.data,
        slot_name,
        career_name,
        CareerSettings
    )
end

if type(printf) == "function" then
    printf("[gut:619] saved-loadout validator=live_career_slot_capability")
end

_rt_register("issue619_saved_loadout_live_slot_capability", function()
    if type(_gut_loadout_slot_policy) ~= "table" or
       type(_gut_loadout_slot_policy.validate) ~= "function" then
        return "loadout slot capability policy unavailable"
    end

    local career_settings = {
        es_knight = {
            item_slot_types_by_slot_name = {
                slot_melee = { "melee" },
                slot_ranged = { "ranged" },
            },
        },
    }
    local item_data = { slot_type = "melee", can_wield = { "es_knight" } }
    local ok = _gut_loadout_slot_policy.validate(
        item_data, "slot_ranged", "es_knight", career_settings
    )
    if ok then return "Foot Knight melee accepted without live slot capability" end

    table.insert(career_settings.es_knight.item_slot_types_by_slot_name.slot_ranged, 1, "melee")
    ok = _gut_loadout_slot_policy.validate(
        item_data, "slot_ranged", "es_knight", career_settings
    )
    if not ok then return "Foot Knight melee rejected after live slot capability insertion" end

    table.remove(career_settings.es_knight.item_slot_types_by_slot_name.slot_ranged, 1)
    ok = _gut_loadout_slot_policy.validate(
        item_data, "slot_ranged", "es_knight", career_settings
    )
    if ok then return "Foot Knight melee remained accepted after live slot capability removal" end
end)

-- Snapshot the current loadout for `career_name`. Reads gear from
-- slots_by_ui_slot_index, cosmetics from slots_by_cosmetic_index, and
-- talents from the talents interface (cloned).
local function _snapshot_loadout(career_name)
    local items_iface = Managers.backend and Managers.backend:get_interface("items")
    if not items_iface then return nil, "no items interface" end
    local gear, cosmetics = {}, {}
    local frame_id = nil
    if InventorySettings and InventorySettings.slots_by_ui_slot_index then
        for _, slot in pairs(InventorySettings.slots_by_ui_slot_index) do
            local ok, id = pcall(items_iface.get_loadout_item_id, items_iface, career_name, slot.name)
            if ok and id then gear[slot.name] = id end
        end
    end
    if InventorySettings and InventorySettings.slots_by_cosmetic_index then
        for _, slot in pairs(InventorySettings.slots_by_cosmetic_index) do
            local ok, id = pcall(items_iface.get_loadout_item_id, items_iface, career_name, slot.name)
            if ok and id then
                cosmetics[slot.name] = id
                if slot.name == "slot_frame" then frame_id = id end
            end
        end
    end
    local talents = nil
    local talents_iface = Managers.backend and Managers.backend:get_interface("talents")
    if talents_iface then
        local ok, t = pcall(talents_iface.get_talents, talents_iface, career_name)
        if ok and type(t) == "table" then talents = table.clone(t) end
    end
    return {
        saved_at    = os.time(),
        career_name = career_name,
        frame       = frame_id,
        gear        = gear,
        cosmetics   = cosmetics,
        talents     = talents or {},
    }
end

-- Apply a saved loadout. Cross-career restore is out of scope for v0.1 — we
-- reject if the snapshot's career doesn't match the current one. Returns
-- (gear_count, cosmetic_count, talents_applied_bool, error_count).
local function _apply_loadout(loadout, current_career_name)
    if not loadout then return 0, 0, false, 0 end
    if loadout.career_name and loadout.career_name ~= current_career_name then
        mod:echo(string.format("Loadout was saved for %s; switch to that career first (cross-career restore is not supported in v0.1).",
            tostring(loadout.career_name)))
        return 0, 0, false, 1
    end
    local items_iface = Managers.backend and Managers.backend:get_interface("items")
    if not items_iface then
        mod:echo("No items interface; cannot restore loadout.")
        return 0, 0, false, 1
    end
    local gear_count, cos_count, errors = 0, 0, 0

    -- Gear namespace -> slots_by_ui_slot_index only.
    if loadout.gear and InventorySettings and InventorySettings.slots_by_ui_slot_index then
        local gear_slot_names = {}
        for _, slot in pairs(InventorySettings.slots_by_ui_slot_index) do
            gear_slot_names[slot.name] = true
        end
        for slot_name, backend_id in pairs(loadout.gear) do
            if not gear_slot_names[slot_name] then
                mod:echo(string.format("Skipping gear slot %s -- not a known gear slot.", tostring(slot_name)))
                -- _dbg: loadout_apply_skip
                pcall(_dbg_alert, "[gui_tweaker] loadout_apply_skip: slot_name=%s reason=not_a_gear_slot",
                    tostring(slot_name))
                errors = errors + 1
            else
                local ok_item, item = pcall(items_iface.get_item_from_id, items_iface, backend_id)
                if not (ok_item and item) then
                    mod:echo(string.format("Skipping %s -- item %s no longer in backend.", slot_name, tostring(backend_id)))
                    pcall(_dbg_alert, "[gui_tweaker] loadout_apply_skip: slot_name=%s reason=item_not_in_backend",
                        tostring(slot_name))
                    errors = errors + 1
                else
                    local valid, reason = _validate_item_for_slot(item, slot_name, current_career_name)
                    if not valid then
                        mod:echo(string.format("Skipping %s -- %s.", slot_name, tostring(reason)))
                        pcall(_dbg_alert, "[gui_tweaker] loadout_apply_skip: slot_name=%s reason=%s",
                            tostring(slot_name), tostring(reason))
                        errors = errors + 1
                    else
                        local generation_before = mod._gut925_generation()
                        local ok_set, err = pcall(BackendUtils.set_loadout_item, backend_id, current_career_name, slot_name)
                        if ok_set then
                            mod._gut925_publish_if_unobserved(generation_before,
                                current_career_name, slot_name, backend_id, item)
                            gear_count = gear_count + 1
                            -- _dbg: loadout_apply_item
                            pcall(_dbg, "[gui_tweaker] loadout_apply_item: slot_name=%s item=%s",
                                tostring(slot_name), tostring(backend_id))
                        else
                            mod:echo(string.format("Skipping %s -- set_loadout_item failed: %s", slot_name, tostring(err)))
                            pcall(_dbg_alert, "[gui_tweaker] loadout_apply_skip: slot_name=%s reason=set_loadout_item_failed:%s",
                                tostring(slot_name), tostring(err))
                            errors = errors + 1
                        end
                    end
                end
            end
        end
    end

    -- Cosmetic namespace -> slots_by_cosmetic_index only.
    if loadout.cosmetics and InventorySettings and InventorySettings.slots_by_cosmetic_index then
        local cos_slot_names = {}
        for _, slot in pairs(InventorySettings.slots_by_cosmetic_index) do
            cos_slot_names[slot.name] = true
        end
        for slot_name, backend_id in pairs(loadout.cosmetics) do
            if not cos_slot_names[slot_name] then
                mod:echo(string.format("Skipping cosmetic slot %s -- not a known cosmetic slot.", tostring(slot_name)))
                pcall(_dbg_alert, "[gui_tweaker] loadout_apply_skip: slot_name=%s reason=not_a_cosmetic_slot",
                    tostring(slot_name))
                errors = errors + 1
            else
                local ok_item, item = pcall(items_iface.get_item_from_id, items_iface, backend_id)
                if not (ok_item and item) then
                    mod:echo(string.format("Skipping %s -- item %s no longer in backend.", slot_name, tostring(backend_id)))
                    pcall(_dbg_alert, "[gui_tweaker] loadout_apply_skip: slot_name=%s reason=item_not_in_backend",
                        tostring(slot_name))
                    errors = errors + 1
                else
                    local valid, reason = _validate_item_for_slot(item, slot_name, current_career_name)
                    if not valid then
                        mod:echo(string.format("Skipping %s -- %s.", slot_name, tostring(reason)))
                        pcall(_dbg_alert, "[gui_tweaker] loadout_apply_skip: slot_name=%s reason=%s",
                            tostring(slot_name), tostring(reason))
                        errors = errors + 1
                    else
                        local generation_before = mod._gut925_generation()
                        local ok_set, err = pcall(BackendUtils.set_loadout_item, backend_id, current_career_name, slot_name)
                        if ok_set then
                            mod._gut925_publish_if_unobserved(generation_before,
                                current_career_name, slot_name, backend_id, item)
                            cos_count = cos_count + 1
                            pcall(_dbg, "[gui_tweaker] loadout_apply_item: slot_name=%s item=%s",
                                tostring(slot_name), tostring(backend_id))
                        else
                            mod:echo(string.format("Skipping %s -- set_loadout_item failed: %s", slot_name, tostring(err)))
                            pcall(_dbg_alert, "[gui_tweaker] loadout_apply_skip: slot_name=%s reason=set_loadout_item_failed:%s",
                                tostring(slot_name), tostring(err))
                            errors = errors + 1
                        end
                    end
                end
            end
        end
    end

    -- Talents.
    local talents_applied = false
    if loadout.talents and #loadout.talents > 0 then
        local talents_iface = Managers.backend and Managers.backend:get_interface("talents")
        if talents_iface then
            local ok_t, err_t = pcall(talents_iface.set_talents, talents_iface, current_career_name, loadout.talents)
            if ok_t then
                talents_applied = true
            else
                mod:echo("Talent restore failed: " .. tostring(err_t))
                errors = errors + 1
            end
        end
    end

    return gear_count, cos_count, talents_applied, errors
end

local function _get_all_loadouts()
    return mod:get("loadouts") or {}
end

local function _save_loadout_to_slot(career_name, n, loadout)
    local all = _get_all_loadouts()
    all[career_name] = all[career_name] or {}
    all[career_name][n] = loadout
    mod:set("loadouts", all)
end

local function _load_loadout_from_slot(career_name, n)
    local all = _get_all_loadouts()
    local by_career = all[career_name]
    return by_career and by_career[n] or nil
end

-- Parse + range-check the slot index argument. Returns (n, nil) or (nil, reason).
local function _parse_slot_arg(arg)
    local n = tonumber(arg)
    if not n then return nil, "slot must be a number 1-" .. LOADOUT_SLOTS end
    n = math.floor(n)
    if n < 1 or n > LOADOUT_SLOTS then return nil, "slot must be 1-" .. LOADOUT_SLOTS end
    return n
end

mod:command("save_loadout", "Save current loadout to slot N (1-30)", function(arg)
    local n, reason = _parse_slot_arg(arg)
    if not n then mod:echo("Save failed: " .. reason) return end
    local career_name, profile_or_err, career = _get_current_career()
    if not career_name then mod:echo("Save failed: " .. tostring(profile_or_err)) return end
    local loadout, snap_err = _snapshot_loadout(career_name)
    if not loadout then mod:echo("Save failed: " .. tostring(snap_err)) return end
    _save_loadout_to_slot(career_name, n, loadout)
    local gear_n, cos_n = 0, 0
    for _ in pairs(loadout.gear) do gear_n = gear_n + 1 end
    for _ in pairs(loadout.cosmetics) do cos_n = cos_n + 1 end
    local talents_n = #(loadout.talents or {})
    mod:echo(string.format("Saved loadout to slot %d for career %s (%d gear, %d cosmetics, %d talents)",
        n, _career_display_name(career), gear_n, cos_n, talents_n))
    -- _dbg: loadout_save
    pcall(function()
        _dbg("[gui_tweaker] loadout_save: slot=%d career=%s gear=%d cosmetics=%d talents=%d",
            n, tostring(career_name), gear_n, cos_n, talents_n)
        for slot_name, backend_id in pairs(loadout.gear) do
            _dbg("[gui_tweaker]   gear.%s = %s", tostring(slot_name), tostring(backend_id))
        end
        for slot_name, backend_id in pairs(loadout.cosmetics) do
            _dbg("[gui_tweaker]   cosmetics.%s = %s", tostring(slot_name), tostring(backend_id))
        end
        local talent_strs = {}
        for i = 1, #(loadout.talents or {}) do talent_strs[i] = tostring(loadout.talents[i]) end
        _dbg("[gui_tweaker]   talents = %s", table.concat(talent_strs, ","))
    end)
end)

mod:command("load_loadout", "Load loadout from slot N (1-30) for current career", function(arg)
    local n, reason = _parse_slot_arg(arg)
    if not n then mod:echo("Load failed: " .. reason) return end
    local career_name, profile_or_err, career = _get_current_career()
    if not career_name then mod:echo("Load failed: " .. tostring(profile_or_err)) return end
    local loadout = _load_loadout_from_slot(career_name, n)
    if not loadout then
        mod:echo(string.format("No loadout in slot %d for career %s", n, _career_display_name(career)))
        return
    end
    local gear_n, cos_n, talents_ok, err_n = _apply_loadout(loadout, career_name)
    mod:echo(string.format("Loaded slot %d for %s -- applied %d gear, %d cosmetics, talents %s, %d errors",
        n, _career_display_name(career), gear_n, cos_n, talents_ok and "yes" or "no", err_n))
    -- _dbg: loadout_apply
    pcall(_dbg, "[gui_tweaker] loadout_apply: slot=%d career=%s gear_applied=%d cosmetics_applied=%d talents_set=%s errors=%d",
        n, tostring(career_name), gear_n, cos_n, talents_ok and "yes" or "no", err_n)
end)

mod:command("list_loadouts", "List saved loadouts for current career", function()
    local career_name, profile_or_err, career = _get_current_career()
    if not career_name then mod:echo("List failed: " .. tostring(profile_or_err)) return end
    local all = _get_all_loadouts()
    local by_career = all[career_name]
    if not by_career then
        mod:echo(string.format("No loadouts saved for %s", _career_display_name(career)))
        return
    end
    local printed = 0
    for n = 1, LOADOUT_SLOTS do
        local lo = by_career[n]
        if lo then
            local gear_n, cos_n = 0, 0
            for _ in pairs(lo.gear or {}) do gear_n = gear_n + 1 end
            for _ in pairs(lo.cosmetics or {}) do cos_n = cos_n + 1 end
            local ts = lo.saved_at and os.date("%Y-%m-%d %H:%M", lo.saved_at) or "?"
            mod:echo(string.format("[%d] saved %s -- %d gear, %d cosmetics", n, ts, gear_n, cos_n))
            printed = printed + 1
        end
    end
    if printed == 0 then
        mod:echo(string.format("No loadouts saved for %s", _career_display_name(career)))
    end
end)

-- ============================================================
-- Versus host-crash fix: UnitFrameUI.add_damage_feedback overflow (v0.2.9, Phase 0)
-- ============================================================
-- VANILLA bug (scripts/ui/hud_ui/unit_frame_ui.lua, add_damage_feedback). A NEW
-- damage-feedback event computes `order_index = #hash_order + 1` and immediately
-- indexes `self._damage_widgets[order_index]`, then `widget.content.visible = true`
-- (vanilla L1687-1690 / L1699-1702) -- BEFORE the over-MAX eviction at the bottom
-- of the function, which is itself dead-coded behind `fassert(false)` (vanilla
-- L1724-1725). The pool only holds `#self._damage_widgets` widgets (4 when
-- features_list.damage is on, 0 when off). When more than that many distinct
-- damage events are active at once, `order_index` exceeds the pool, the lookup
-- returns nil, and `widget.content.visible = true` is a fatal index-of-nil. On
-- the HOST this crashes the whole session.
-- Reproduced in Versus: a Pactsworn Ratling Gunner's sustained machinegun fire
-- stacks 5+ simultaneous damage-feedback messages on one hero frame
-- (crash GUID 59ae9a93-..., 2026-06-15; NumericUI re-news the vanilla UnitFrameUI
-- which keeps this vanilla path live).
--
-- Fix: a real wrapper that DROPS the overflow event before it reaches the nil
-- index -- only when (a) the pool is already full AND (b) a new order_index would
-- be assigned (a brand-new event, or a re-activated `disabled` one). Existing
-- active events (the common case -- repeated hits accumulate into one hash) pass
-- straight through untouched. The cap is self-healing: vanilla
-- `_update_damage_feedback` removes expired events from `_hash_order`
-- (table.remove at the remove_time check, vanilla L1819), freeing slots. No
-- vanilla state is mutated here -- it is a pure pre-call guard that degrades
-- safely (just stops dropping) if the vanilla shape ever drifts. Perf: the
-- full_hash/events work only runs in the rare at-capacity case; the common path
-- is two `#` reads. Always-on (a safety guard, not a toggled feature).
mod._gut_damage_feedback_should_drop = function(num_active, pool_size, is_new_event)
    -- Drop iff a NEW order_index would be assigned and it would exceed the
    -- widget pool (== the vanilla nil-index crash condition).
    return is_new_event and num_active >= pool_size
end

mod:hook("UnitFrameUI", "add_damage_feedback", function(func, self, hash, is_local_player, event_type, attacker_player, target_player, damage_amount)
    local hash_order = self._hash_order
    local damage_widgets = self._damage_widgets
    -- Only the at/over-capacity case can crash; skip all work otherwise.
    if hash_order and damage_widgets and #hash_order >= #damage_widgets then
        local events = self._damage_events
        if events then
            local existing = events[tostring(hash) .. tostring(event_type)]
            local will_add_new = (not existing) or existing.disabled or false
            if mod._gut_damage_feedback_should_drop(#hash_order, #damage_widgets, will_add_new and true or false) then
                return  -- pool full + new event: vanilla would index a nil widget. Drop it.
            end
        end
    end
    return func(self, hash, is_local_player, event_type, attacker_player, target_player, damage_amount)
end)

_rt_register("damage_feedback_overflow_guard", function()
    -- Pins the Versus host-crash fix decision rule across boundary cases.
    local f = mod._gut_damage_feedback_should_drop
    if type(f) ~= "function" then return "damage-feedback overflow guard fn missing (Versus host-crash fix reverted?)" end
    if not f(4, 4, true) then return "must DROP a new event when the 4-widget pool is full (the Versus crash case)" end
    if not f(5, 4, true) then return "must DROP a new event when active count exceeds the pool" end
    if not f(0, 0, true) then return "must DROP a new event when the pool is empty (features_list.damage off)" end
    if f(3, 4, true)     then return "must NOT drop a new event when the pool has a free slot" end
    if f(9, 4, false)    then return "must NOT drop an existing event -- only new events get a new order_index" end
end)

-- ============================================================
-- HUD Customizer (v0.2.0) -- in-game edit-mode + click-and-drag
-- repositioning of native HUD widgets, persisted per-resolution.
-- ============================================================

local Customizer = mod:dofile("scripts/mods/gui_tweaker_dev/_hud_customizer")
-- (#312) Publish the customizer so the UI Tweaks sync module's migrate() can read +
-- clear gut's stored HUD offsets through the SAME in-memory cache the customizer
-- uses (keeps cache and persistent store in lockstep). Resolved at call time.
mod._gut_hud_customizer = Customizer
-- Wire the two-channel debug helpers into the customizer module before any
-- hooks fire (PROJECT_STANDARDS § 3.6 two-helper policy).
pcall(Customizer.init_dbg, _dbg, _dbg_alert)
local ok_install, install_ret, install_failed, install_failures = pcall(Customizer.install_hooks)
if not ok_install then
    mod:echo("gui_tweaker: hud-customizer hook install failed: " .. tostring(install_ret))
end

-- _dbg: boot (one-shot at mod load)
do
    local rw, rh = 0, 0
    pcall(function()
        local r = rawget(_G, "RESOLUTION_LOOKUP")
        if r then rw, rh = r.res_w or 0, r.res_h or 0 end
    end)
    _dbg("[gui_tweaker] boot: v%s, resolution %dx%d", tostring(MOD_VERSION), rw, rh)
    if ok_install then
        local installed_n = tonumber(install_ret) or 0
        local failed_n = tonumber(install_failed) or 0
        local failures_str = "none"
        if type(install_failures) == "table" and #install_failures > 0 then
            failures_str = table.concat(install_failures, ",")
        end
        if failed_n > 0 then
            _dbg_alert("[gui_tweaker] hook_install: installed=%d failed=%d (failures: %s)",
                installed_n, failed_n, failures_str)
        else
            _dbg("[gui_tweaker] hook_install: installed=%d failed=%d (failures: %s)",
                installed_n, failed_n, failures_str)
        end
    else
        _dbg_alert("[gui_tweaker] hook_install: installed=0 failed=? (failures: pcall_err=%s)",
            tostring(install_ret))
    end
    -- Dump the customizer registry — one line per widget.
    pcall(function()
        for i = 1, #Customizer.REGISTRY do
            local e = Customizer.REGISTRY[i]
            _dbg("[gui_tweaker] registry: id=%s class=%s node=%s vanilla_pos={%d,%d} vanilla_size={%d,%d}",
                tostring(e.id), tostring(e.class_name), tostring(e.scenegraph_node_id),
                math.floor(e.vanilla_position[1] or 0), math.floor(e.vanilla_position[2] or 0),
                math.floor(e.vanilla_size[1] or 0), math.floor(e.vanilla_size[2] or 0))
        end
    end)
end

-- _dbg: hero_view auto-dump. Fires whenever HeroView opens.
mod:hook_safe("HeroView", "on_enter", function(self, ...)
    pcall(Customizer.dump_hero_view, self)
end)

-- Lifecycle-chain integrity probe (v0.2.216-dev, issue 425 coverage). This root
-- mod.on_setting_changed is the innermost handler in the capture-prev chain that ~7
-- feature files wrap. The /gut_regression_test `lifecycle_chain_integrity` check drives the
-- CURRENT (outermost) on_setting_changed with the synthetic id below; reaching this root
-- flips the flag, proving every wrapper correctly chained its predecessor. A future file
-- that forgets `local prev = mod.on_setting_changed` orphans this root and fails the check.
mod._gut_chain_probe = { on_setting_changed = false }

-- VMF emits this callback when the user flips any setting. We use it to log
-- the debug-mode transition unconditionally (only place that does so).
mod.on_setting_changed = function(setting_id)
    if setting_id == "__gut_chain_probe__" then
        mod._gut_chain_probe.on_setting_changed = true
        return
    end
    if setting_id == "gut_original_thp_names" then
        if mod._gut_original_thp_names then
            mod._gut_original_thp_names.apply(mod:get(setting_id) and true or false)
        end
    elseif setting_id == "gut_mission_inventory_enabled" then
        -- In-mission inventory's InventorySettings loadout-access data patch (body in
        -- _gut_mission_inventory.lua). Hero-select no longer couples in: since the
        -- #173 rewire it opens CharacterSelectionView, which doesn't read this gate.
        -- mod._gut_apply_keep_menus is a table field resolved at call time (the
        -- module dofile's later in this file).
        if mod._gut_apply_keep_menus then mod._gut_apply_keep_menus() end
    elseif setting_id == "gut_skip_cutscenes_enabled" then
        -- Skip Cutscenes (issue #537 / issue 275). Do NOT latch the shared engine skip
        -- gate on. `script_data.skippable_cutscenes` has exactly ONE runtime reader
        -- (CutsceneSystem.skip_pressed, cutscene_system.lua:98) and the _gut_cutscenes.lua
        -- hooks already scope-unlock it only around a skip on a cutscene that carries a
        -- wired event_on_skip. Persistently latching it true force-unlocks author-locked
        -- boss cinematics (event_on_skip=nil, e.g. Nurgloth on dlc_castle) into a mid-fight
        -- ~66%-health softlock -- the exact issue-275 class the mod fixed everywhere else.
        -- This site escaped the load-time / toggle no-latch cleanup because it lived in
        -- this file, not _gut_cutscenes.lua. On DISABLE, restore the captured pre-gut value
        -- (own-or-pin) so a co-installed cutscene mod / the vanilla debug menu is not
        -- clobbered; the restore helper is defined by _gut_cutscenes.lua (resolved here at
        -- call time). Enabling does nothing -- the per-skip hooks carry the whole feature.
        if not mod:get("gut_skip_cutscenes_enabled") and mod._gut_restore_skippable_cutscenes then
            mod._gut_restore_skippable_cutscenes()
        end
    elseif setting_id == "gut_cim_bench_in_mission" then
        -- Write-through to cim's `allow_in_mission` setting (the widget moved out of
        -- cim into gut's In-Mission Menus, user direction 2026-07-02; cim's
        -- open_forge/open_standard_crafting gates still read cim's OWN setting, so
        -- gut mirrors the value into cim's store on every change). Dev clone first:
        -- the cohort runs cim_dev; stable id as fallback.
        local cim = get_mod("cim_dev") or get_mod("cim")
        if cim then
            cim:set("allow_in_mission", mod:get("gut_cim_bench_in_mission") and true or false)
        end
    elseif setting_id == "gut_vanilla_numeric_ui" then
        -- (#312) Mirror into the vanilla engine user setting. LIVE: UnitFramesHandler
        -- polls Application.user_setting("numeric_ui") every update
        -- (unit_frames_handler.lua:1285), so this takes effect without a restart.
        pcall(function()
            Application.set_user_setting("numeric_ui", mod:get("gut_vanilla_numeric_ui") and true or false)
            Application.save_user_settings()
        end)
    elseif setting_id == "gut_vanilla_persistent_ammo" then
        -- (#312) Mirror into the vanilla engine user setting. NOT live: vanilla
        -- equipment_ui.lua:10 caches persistent_ammo_counter at chunk load, so this
        -- needs a game restart to take effect (stated in the tooltip).
        pcall(function()
            Application.set_user_setting("persistent_ammo_counter", mod:get("gut_vanilla_persistent_ammo") and true or false)
            Application.save_user_settings()
        end)
    elseif setting_id == "gut_uitweaks_sync" then
        -- (#312) Turning sync ON: fold any existing gut HUD offsets for the mapped
        -- elements into UI Tweaks so they aren't lost when gut stops applying its own
        -- offset. One-time + idempotent (guard flag inside migrate); no-op when off.
        if mod:get("gut_uitweaks_sync") and mod._gut_uitweaks_sync and mod._gut_uitweaks_sync.migrate then
            pcall(mod._gut_uitweaks_sync.migrate)
        end
    end
end

-- Re-apply the in-mission inventory InventorySettings patch + ESC-menu entry on
-- every game-state transition, since the engine can reload InventorySettings and
-- the per-mission deus/adventure gate must be re-evaluated. mod._gut_apply_keep_menus
-- is a table field resolved at call time (body in _gut_mission_inventory.lua).
mod.on_game_state_changed = function(status, state_name)
    if mod._gut_apply_keep_menus then mod._gut_apply_keep_menus() end
end

-- Per-frame entry point: pulls activation state, runs the drag machine if
-- we're in edit mode, then injects the overlay draw using IngameHud's renderer.
mod:hook_safe("IngameHud", "post_update", function(self, dt, t)
    pcall(Customizer.tick_activation)
    if Customizer.is_edit_mode() then
        pcall(Customizer.tick_drag)
        local ui_renderer = (self._ingame_ui_context and self._ingame_ui_context.ui_renderer)
            or (Managers.ui and Managers.ui._ingame_ui_context and Managers.ui._ingame_ui_context.ui_top_renderer)
        if ui_renderer then
            pcall(Customizer.draw_overlay, ui_renderer)
        end
    end
end)

-- HUD edit-mode toggle (#310). Shared by BOTH the /edit_hud command AND the
-- gut_edit_hud_hotkey keybind. VMF keybinds with keybind_type="function_call"
-- resolve function_name to mod.<name>, so this MUST be a field on `mod` (same
-- pattern as mod.gut_hud_cycle in _hide_ui.lua). Previously edit mode was only
-- reachable via /edit_hud, so there was no bindable key -- the gap the user hit.
mod.gut_edit_hud_toggle = function()
    local enabled = not (Customizer.is_edit_mode() and true or false)
    -- We only flip the sticky bit; the alt-gesture path stays independent.
    Customizer.set_sticky(enabled)
    if enabled then
        mod:echo("Edit mode: ON (resolution " .. tostring(Customizer.resolution_key()) .. "). Drag widgets with left mouse.")
    else
        mod:echo("Edit mode: OFF.")
    end
end

mod:command("edit_hud", "Toggle HUD edit mode (click-drag widgets to reposition)", function()
    mod.gut_edit_hud_toggle()
end)

mod:command("reset_hud", "Reset HUD widget(s) to vanilla position. Usage: /reset_hud [widget_id]", function(arg)
    if arg and arg ~= "" then
        local ok = Customizer.reset_widget(arg)
        if ok then
            mod:echo("Reset HUD widget '" .. tostring(arg) .. "' to vanilla position.")
        else
            mod:echo("Reset failed: unknown widget id '" .. tostring(arg) .. "'. Run /list_hud for valid ids.")
        end
    else
        local n = Customizer.reset_all()
        mod:echo(string.format("Reset all HUD widgets (%d entries) for resolution %s.", n, tostring(Customizer.resolution_key())))
    end
end)

mod:command("list_hud", "List current HUD widget offsets for this resolution", function()
    local entries = Customizer.list_offsets()
    mod:echo(string.format("HUD offsets for %s:", tostring(Customizer.resolution_key())))
    if #entries == 0 then
        mod:echo("  (no offsets saved -- all widgets at vanilla position)")
        return
    end
    for i = 1, #entries do
        local e = entries[i]
        mod:echo(string.format("  %s: dx=%.1f, dy=%.1f", e.id, e.dx, e.dy))
    end
end)

-- Registered here (not beside the v0.1 checks at the top of the file) because it
-- closes over `Customizer`, which only becomes available after the dofile above.
_rt_register("hud_offset_preserves_vanilla_baseline", function()
    -- audit 2026-06-07 (v0.2.8-dev, F5): _apply_offset_to_scenegraph used to
    -- write the RAW drag delta into local_position, zeroing each widget's
    -- non-zero vanilla baseline (equipment_ui {0,69}, buff_ui {150,18}, etc.) on
    -- the first drag. The math now lives in Customizer.local_position_for and
    -- must return baseline + delta. This check fails if the baseline term is
    -- dropped again (regression to raw-delta assignment).
    if type(Customizer.local_position_for) ~= "function" then
        return "Customizer.local_position_for missing (refactor regressed)"
    end
    -- equipment_ui has a non-zero baseline {0, 69, 4}; it is the canonical case
    -- the old raw-write broke. A 25,-40 drag must land at vanilla + delta.
    local lx, ly = Customizer.local_position_for("equipment_ui", 25, -40)
    if lx ~= 25 then return string.format("equipment_ui x: expected 0+25=25, got %s", tostring(lx)) end
    if ly ~= 29 then return string.format("equipment_ui y: expected 69+(-40)=29, got %s", tostring(ly)) end
    -- buff_ui baseline {150, 18}: a zero drag must return the exact baseline,
    -- proving the baseline survives (the raw-write bug returned {0,0} here).
    local bx, by = Customizer.local_position_for("buff_ui", 0, 0)
    if bx ~= 150 or by ~= 18 then
        return string.format("buff_ui zero-drag: expected {150,18}, got {%s,%s}", tostring(bx), tostring(by))
    end
    -- Unknown id must degrade to {0,0} + delta, never error.
    local ux, uy = Customizer.local_position_for("nonexistent_widget", 7, 9)
    if ux ~= 7 or uy ~= 9 then
        return string.format("unknown id: expected {7,9}, got {%s,%s}", tostring(ux), tostring(uy))
    end
end)

-- (#310) Drag confinement: a HUD element must not be draggable off the displayable
-- HUD area. Customizer.confine_delta clamps the element's box [world, world+size] into
-- the bounds and back-solves the confined delta; this asserts the four cases the drag
-- machine relies on (far-edge clamp, near-edge clamp, in-bounds passthrough, applied-
-- delta accounting) plus the oversize-axis escape hatch (never trap a too-big element).
_rt_register("hud_confine_delta_clamps", function()
    if type(Customizer.confine_delta) ~= "function" then
        return "Customizer.confine_delta missing (#310 confinement regressed)"
    end
    local b = { min_x = 0, min_y = 0, max_x = 1920, max_y = 1080 }
    -- Box at world {100,100} size {200,50}, no prior delta. A huge +2000 drag clamps the
    -- FAR edge to the bounds: x -> 1920-200 = 1720 (delta 1620); y -> 1080-50 = 1030 (delta 930).
    local cdx, cdy = Customizer.confine_delta(100, 100, 200, 50, 0, 0, 2000, 2000, b)
    if cdx ~= 1620 then return string.format("far-x clamp: expected 1620, got %s", tostring(cdx)) end
    if cdy ~= 930  then return string.format("far-y clamp: expected 930, got %s", tostring(cdy)) end
    -- A huge negative drag clamps the NEAR edge to 0: world 100 -> 0 (delta -100).
    local ndx, ndy = Customizer.confine_delta(100, 100, 200, 50, 0, 0, -2000, -2000, b)
    if ndx ~= -100 or ndy ~= -100 then
        return string.format("near clamp: expected {-100,-100}, got {%s,%s}", tostring(ndx), tostring(ndy))
    end
    -- An in-bounds drag passes through unchanged.
    local px, py = Customizer.confine_delta(100, 100, 200, 50, 0, 0, 300, 200, b)
    if px ~= 300 or py ~= 200 then
        return string.format("in-bounds passthrough: expected {300,200}, got {%s,%s}", tostring(px), tostring(py))
    end
    -- Applied-delta accounting: element already shifted +50 (its live world reflects it).
    -- A further request to delta 5000 clamps the same far edge; delta must still resolve to 1620.
    local axx = Customizer.confine_delta(150, 100, 200, 50, 50, 0, 5000, 0, b)
    if axx ~= 1620 then return string.format("applied-delta clamp: expected 1620, got %s", tostring(axx)) end
    -- Element wider than the area on x: that axis is left unclamped (never trap it off-screen).
    local wide = Customizer.confine_delta(0, 100, 3000, 50, 0, 0, 500, 0, b)
    if wide ~= 500 then return string.format("oversize-axis passthrough: expected 500, got %s", tostring(wide)) end
end)

-- (#547) Vanilla draws/hit-tests a drag node independently from the root node
-- it mutates. Keep that two-node contract for pivot-based widgets.
_rt_register("hud_drag_geometry_uses_render_bounds", function()
    if type(Customizer.drag_geometry) ~= "function" then
        return "Customizer.drag_geometry missing (#547 regressed)"
    end
    local entry = Customizer.REGISTRY_BY_ID and Customizer.REGISTRY_BY_ID.equipment_ui
    if not entry or entry.drag_scenegraph_node_id ~= "background_panel" then
        return "equipment_ui drag bounds must use background_panel"
    end
    local move = { world_position = { 10, 20, 1 }, size = { 0, 0 } }
    local bounds = { world_position = { 300, 400, 1 }, size = { 624, 66 } }
    local node, size = Customizer.drag_geometry({ pivot = move, background_panel = bounds }, entry)
    if node ~= bounds or size ~= bounds.size then
        return "drag geometry did not resolve live rendered bounds"
    end
    if entry.scenegraph_node_id ~= "pivot" then
        return "#547 changed equipment movement target instead of only drag bounds"
    end
end)

-- (#310) CareerAbilityBarUI uses `_ui_scenegraph` while the other registered HUD
-- classes generally use `ui_scenegraph`. Keep that bar in the editor and pin the
-- bounded coverage classifier used to prioritize the remaining resize work.
_rt_register("issue310_hud_scenegraph_alias_coverage", function()
    if type(Customizer.scenegraph_for_view) ~= "function" then
        return "scenegraph_for_view missing"
    end
    if type(Customizer.coverage_status) ~= "function" then
        return "coverage_status missing"
    end
    local private = { _ui_scenegraph = { ability_bar = {
        world_position = { 1, 2, 3 }, size = { 250, 16 }, local_position = { 0, -200, 1 },
    } } }
    local scenegraph, source = Customizer.scenegraph_for_view(private)
    if scenegraph ~= private._ui_scenegraph or source ~= "_ui_scenegraph" then
        return "private CareerAbilityBarUI scenegraph alias did not resolve"
    end
    local status = Customizer.coverage_status(private, Customizer.REGISTRY_BY_ID.career_ability_bar)
    if status ~= "ready" then
        return "career ability bar coverage expected ready, got " .. tostring(status)
    end
end)

-- (#310) HUD edit mode suspends local gameplay input (mouse drives the editor, not the
-- character/camera). The freecam PlayerInputExtension.is_input_blocked hook consults
-- Customizer.should_suspend_input(); assert that seam exists, is edit-mode-gated (false
-- when not editing), and that the freecam hook still reads it (the #310 consolidation).
_rt_register("hud_edit_mode_input_suspend_api", function()
    if type(Customizer.should_suspend_input) ~= "function" then
        return "Customizer.should_suspend_input missing (#310 input-suspend seam regressed)"
    end
    if Customizer.is_edit_mode() then
        return "edit mode unexpectedly active during self-test (cannot assert input gating)"
    end
    -- With edit mode off, input must NOT be suspended (short-circuits before the cutscene probe).
    if Customizer.should_suspend_input() ~= false then
        return "should_suspend_input must be false when edit mode is off"
    end
    -- The freecam module's is_input_blocked hook must still consult the seam (source
    -- needle; io-safe -> skipped in the retail sandbox, where the runtime asserts above
    -- are authoritative and the needle moves to repo QA). Path derived from a freecam
    -- function so it tracks the module even if the file is renamed.
    if type(mod.gut_freecam_toggle) == "function" then
        local ok, info = pcall(debug.getinfo, mod.gut_freecam_toggle, "S")
        if ok and type(info) == "table" and info.source then
            local src_path = info.source:sub(1, 1) == "@" and info.source:sub(2) or info.source
            local txt = _rt_src_read(src_path)
            if txt and not txt:find("should_suspend_input", 1, true) then
                return "freecam is_input_blocked hook no longer consults should_suspend_input (#310 merge lost)"
            end
        end
    end
end)

-- ============================================================
-- Mod Tweaker (v0.1 scaffold) -- replacement settings menu surface
-- exposed at `get_mod("gut_dev").mod_tweaker`. v0.1 just stands up the API
-- and registry; the ESC entry, view rendering, and widget factories
-- arrive in follow-up tasks. Authors detect with:
--   local gut = get_mod("gut_dev")
--   if gut and gut.mod_tweaker then
--       gut.mod_tweaker:register_category({ mod_id = "...", label = "...", widgets = {...} })
--   end
-- ============================================================

local ok_mt, ModTweaker = pcall(mod.dofile, mod, "scripts/mods/gui_tweaker_dev/_mod_tweaker")
if ok_mt and type(ModTweaker) == "table" then
    local ok_install, install_err = pcall(ModTweaker.install, _dbg, _dbg_alert)
    if ok_install then
        mod.mod_tweaker = ModTweaker
        _dbg("[gui_tweaker] mod_tweaker: installed (api version v0.1)")
    else
        _dbg_alert("[gui_tweaker] mod_tweaker install failed: %s", tostring(install_err))
    end
else
    _dbg_alert("[gui_tweaker] mod_tweaker dofile failed: %s", tostring(ModTweaker))
end

-- Dogfood category so the view renders real content (and proves the end-to-end:
-- open -> change -> persist -> on_change). gut's own demo settings live in the
-- Mod Tweaker keyspace (mt::gut::*). Replace/extend once per-mod registration (or
-- VMF auto-mirror) lands.
if mod.mod_tweaker and not mod.mod_tweaker:is_registered("gut_dev") then
    mod.mod_tweaker:register_category({
        mod_id = "gut_dev",
        label  = "Tweaker: GUI dev",
        widgets = {
            {
                setting_id = "mt_demo_slider",
                type       = "slider",
                label      = "Demo slider (proof of render)",
                default    = 5,
                range      = { 0, 20 },
                decimals   = 0,
            },
        },
    })
end

-- ESC menu entry injection. Hook the central layout consumer
-- (IngameViewLayoutLogic.setup_button_layout) so we catch every layout variant
-- the engine swaps through: alone / host / client / demo / tutorial / offline /
-- full_access, plus the chat-button injected case. Vanilla source:
-- scripts/ui/views/ingame_view_layout_logic.lua:17-60. hook_safe is correct
-- here because setup_button_layout doesn't return -- it mutates
-- self.active_button_data, which we extend after the iteration runs.
mod:hook_safe("IngameViewLayoutLogic", "setup_button_layout", function(self, layout_data)
    local entries = self.active_button_data
    if type(entries) ~= "table" then return end
    -- Don't double-insert if the hook re-fires on the same active_button_data
    -- (layout swap during gameplay clears + rebuilds — safe to re-add).
    for i = 1, #entries do
        if entries[i].transition == "mod_tweaker_view" then return end
    end
    local insert_at = #entries + 1
    -- Place above Options for visual grouping; if Options isn't in this layout
    -- (e.g. console invert-controls demo), fall through to append.
    for i = 1, #entries do
        if entries[i].transition == "options_menu" then
            insert_at = i
            break
        end
    end
    table.insert(entries, insert_at, {
        -- display_name is a LOC KEY (resolved to "Mod Tweaker" via our
        -- append_backend_localizations). Do NOT add a display_name_func returning the
        -- resolved string: the MODERN menu (hero_window_ingame_view.lua:473) does
        -- `text_field = display_name_func() or display_name` and then LOCALIZES
        -- text_field — so a func returning "Mod Tweaker" gets re-localized into
        -- "<Mod Tweaker>". The key path localizes correctly in BOTH menus.
        display_name = "mod_tweaker_button_name",
        fade         = true,
        transition   = "mod_tweaker_view",
    })
    -- Diagnostic for the "ESC menu looks deprecated after leaving the Mod Tweaker"
    -- report: log the full button list each time the layout is built, so we can see
    -- if the count grows (accumulation) or the set changes after the Mod Tweaker.
    local ts = {}
    for i = 1, #entries do ts[#ts + 1] = tostring(entries[i].transition) end
    mod:debug("[mt:esc] setup_button_layout -> %d buttons: [%s]", #entries, table.concat(ts, ", "))
end)

-- #630: automatic, bounded lifecycle evidence around Mod Tweaker's borrowed
-- renderer pass. This is diagnostics only; the DX12 fence dump does not support
-- changing renderer or focus behavior yet. Both presentation modules consume
-- this one probe so their counters cannot drift.
local _gut_dx12_fence630 = mod:dofile("scripts/mods/gui_tweaker_dev/_gut_dx12_fence630")
mod._gut_dx12_fence630 = _gut_dx12_fence630.new({
    emit = function(line) printf("%s", line) end,
})

-- Build + attach the Mod Tweaker view into an IngameUI instance's `views` table.
-- Idempotent. Used by BOTH the setup_views hook (early attempt) and the
-- transition closure (lazy, on demand). At transition time the IngameUI is fully
-- initialised (self.views populated, self.ingame_ui_context set at
-- ingame_ui.lua:138), so the lazy path is the reliable one — the setup_views
-- post-call hook's timing vs self.views shifted after the game's Versus update,
-- so it now sees self.views as not-yet-a-table and silently bails.
local function _attach_view(self, ctx_arg)
    if not self or type(self.views) ~= "table" then return false end
    if self.views.mod_tweaker_view then return true end
    local ctx = ctx_arg or self.ingame_ui_context
    if not ctx then
        ctx = {
            ui_renderer     = self.ui_renderer,
            ui_top_renderer = self.ui_top_renderer,
            ingame_ui       = self,
            input_manager   = self.input_manager,
            world_manager   = self.world_manager,
        }
    end
    if not (ctx.ui_renderer or ctx.ui_top_renderer) then
        _dbg_alert("[mt] attach: no usable ui_renderer in context; cannot build view")
        return false
    end
    local ok_view, ModTweakerView = pcall(mod.dofile, mod, "scripts/mods/gui_tweaker_dev/_mod_tweaker_view")
    if not ok_view or type(ModTweakerView) ~= "table" then
        _dbg_alert("[mt] attach: view dofile failed: %s", tostring(ModTweakerView))
        return false
    end
    local ok_new, view_or_err = pcall(ModTweakerView.new, ModTweakerView, ctx)
    if not ok_new then
        _dbg_alert("[mt] attach: ModTweakerView:new raised: %s", tostring(view_or_err))
        return false
    end
    self.views.mod_tweaker_view = view_or_err
    _dbg("[mt] attach: ModTweakerView attached")
    return true
end

-- Forward-declared so the transition closure below (and the on_enter re-pin in
-- _mod_tweaker_view.lua) can defensively re-pin LA's atlas + log on every Mod
-- Tweaker open (v0.2.56). The keepalive module is dofile'd much later in this file;
-- this local is ASSIGNED at that dofile site (`_gut_la_keepalive = mod:dofile(...)`),
-- but DECLARED here so the closure captures it as an upvalue. `_mt_open_count` is a
-- module-level open counter for the instrumentation (shows 1st/2nd/3rd/4th open).
local _gut_la_keepalive
local _mt_open_count = 0

-- Re-pin LA's atlas package (pcall-guarded) + log the residency/renderer state on
-- every Mod Tweaker open. The Mod Tweaker BORROWS the long-lived IngameUI renderer
-- (does NOT recreate it), and the keepalive's premise that "LA unloads its own
-- package" means the atlas can go missing between opens — so a one-time pin on
-- StateInGameRunning.on_enter isn't enough; we re-pin on each open. The keepalive's
-- own `has_loaded` force-load guard stays intact (it NEVER force-loads a non-resident
-- LA package — that re-introduces the 0.2.54 crash). `self` is the IngameUI (site i)
-- or the ModTweakerView (site ii) — both expose ui_renderer/ui_top_renderer for the
-- renderer-identity probe. Exposed as mod._gut_mt_repin_la so the view module can
-- call the SAME path.
local function _gut_mt_repin_la(self, site)
    _mt_open_count = _mt_open_count + 1
    local pm = Managers and Managers.package
    local resident = "?"
    if pm and pm.has_loaded then
        local ok_r, r = pcall(pm.has_loaded, pm, "resource_packages/Loremasters-Armoury/Loremasters-Armoury")
        resident = ok_r and tostring(r) or ("err:" .. tostring(r))
    end
    local pinned = "?"
    if _gut_la_keepalive and _gut_la_keepalive.is_pinned then
        local ok_p, p = pcall(_gut_la_keepalive.is_pinned)
        pinned = ok_p and tostring(p) or ("err:" .. tostring(p))
    end
    mod:debug("[gut:la] mod-tweaker open #%d (site=%s): LA_resident=%s gut_pinned=%s ui_renderer=%s ui_top_renderer=%s",
        _mt_open_count, tostring(site), resident, pinned,
        tostring(self and self.ui_renderer), tostring(self and self.ui_top_renderer))
    if _gut_la_keepalive and _gut_la_keepalive.pin then
        local ok_pin, err_pin = pcall(_gut_la_keepalive.pin)
        if not ok_pin then
            mod:warning("[gut:la] re-pin pcall raised on open #%d: %s", _mt_open_count, tostring(err_pin))
        end
    end
end
mod._gut_mt_repin_la = _gut_mt_repin_la

-- Transition + view registration. Two halves:
--   (a) transitions table -- mutated directly via package.loaded so the
--       upvalue `transitions` captured at ingame_ui.lua:50 sees the new entry.
--       The transition closure just sets self.current_view; vanilla pattern
--       is at ingame_ui_settings.lua:537 (options_menu).
--   (b) views table -- hook IngameUI.setup_views post-call (ingame_ui.lua:145)
--       and inject our view instance, mirroring how
--       view_settings.views_function builds the canonical map.
local ok_settings_inject, settings_inject_err = pcall(function()
    local settings = package.loaded["scripts/ui/views/ingame_ui_settings"]
    if not settings or not settings.transitions then
        error("ingame_ui_settings not in package.loaded; mod likely loaded too early")
    end
    if settings.transitions.mod_tweaker_view then
        _dbg("[mt] transition mod_tweaker_view already registered (idempotent)")
        return
    end
    settings.transitions.mod_tweaker_view = function(self)
        -- BUILD 2 ROUTING (v0.2.57-dev). The ESC "Mod Tweaker" button has TWO targets:
        --
        --   * IN THE KEEP/INN -> open the HeroView SUB-STATE (gut_mod_tweaker,
        --     _mod_tweaker_state.lua). A sub-state stays INSIDE the already-open
        --     hero_view and never recreates its renderer, so it eliminates BOTH the
        --     deprecated bare-IngameView look on exit AND the LA armoury_atlas
        --     renderer-recreation crash (42c81d84) that the leave/re-enter
        --     standalone-view path triggered. This is the proper fix the old TODO
        --     described.
        --
        --   * IN A MISSION -> there is NO hero_view, so we KEEP the existing standalone
        --     ModTweakerView path (the pre-build-2 behaviour). In a mission the
        --     standalone view's exit routes to "ingame_menu" (never crashed there; no
        --     hero_view to recreate), preserving in-mission access exactly as before.
        --
        -- Keep/inn detection matches _ba_heroview_inject: ingame_ui_context.is_in_inn.
        local ctx = self.ingame_ui_context
        local in_keep = not (ctx and ctx.is_in_inn == false)
        -- v0.2.62-dev REVERT: the keep HeroView sub-state (build 2) reliably OPENED (rows
        -- built) but the HeroView state machine immediately BOUNCED it back to
        -- HeroViewStateOverview (log: overview -> gut_mod_tweaker on_enter rows=13 ->
        -- overview), so it never stayed visible from the ESC button — the "doesn't open
        -- from the main menu" regression. The STANDALONE ModTweakerView opens reliably (it
        -- always did in-mission), and build-3's origin-capture exit (below) returns to the
        -- modern hero_view menu rather than the deprecated bare one, so the sub-state is no
        -- longer needed to avoid the deprecated look. Route the KEEP through the standalone
        -- view too. (HeroViewStateModTweaker + _ba_heroview_inject stay registered for the
        -- /mod_tweaker command.) Flip _USE_KEEP_SUBSTATE back only after the sub-state
        -- bounce is root-caused.
        local _USE_KEEP_SUBSTATE = false
        if _USE_KEEP_SUBSTATE and in_keep and self.transition_with_fade and rawget(_G, "HeroViewStateModTweaker") then
            _dbg("[mt] ESC entry in keep -> hero_view sub-state gut_mod_tweaker")
            -- force_open = true is LOAD-BEARING. The ESC "Mod Tweaker" button fires from
            -- INSIDE the already-open keep ESC menu, which IS hero_view (the ingame_menu
            -- window inside HeroViewStateOverview), so self.current_view == "hero_view"
            -- ALREADY. Without force_open, IngameUI.handle_transition's guard
            -- `if old_view ~= new_view or force_open` (ingame_ui.lua:953) is false→false,
            -- so it SKIPS HeroView:on_enter / post_update_on_enter — and post_update_on_enter
            -- is the ONLY path that reads menu_state_name (hero_view.lua:504-508). Result
            -- (the reported bug): the fade plays but the gut_mod_tweaker sub-state never
            -- opens. force_open forces the re-enter so menu_state_name is honored. This is
            -- the EXACT vanilla keep-button flow: every keep ESC menu button (Inventory,
            -- Loot, ...) uses transition="hero_view" + transition_state=<screen> +
            -- force_open=true (ingame_view_menu_layout_console.lua:742-745).
            self:transition_with_fade("hero_view", {
                menu_state_name = "gut_mod_tweaker",
                force_open = true,
            })
            return
        end

        -- In-mission path (or sub-state unavailable): standalone ModTweakerView.
        -- DEFENSIVE re-pin LA's atlas + instrument BEFORE attaching/showing the view
        -- (site i). The borrowed renderer is long-lived, so the atlas can be unloaded
        -- between opens; re-pin every open (pcall-guarded, has_loaded-gated inside).
        pcall(_gut_mt_repin_la, self, "transition")
        -- Lazy-attach on demand: at click time the IngameUI is fully initialised, so
        -- this is the reliable build point. Idempotent. Only switch if the view
        -- actually attached, so a build failure stays a harmless no-op.
        _attach_view(self)
        if self.views and self.views.mod_tweaker_view then
            -- Capture the ORIGIN menu so exit returns to it. In a mission ESC opens
            -- EITHER the modern HeroView menu (current_view == "hero_view", the default
            -- when use_pc_menu_layout=false) OR the legacy IngameView (current_view ==
            -- "ingame_menu"). self.current_view is still the origin here — the engine
            -- snapshots old_view BEFORE invoking this closure (ingame_ui.lua:946) — so
            -- reading it now gives the menu the player actually opened. Hard-coding
            -- "ingame_menu" dumped modern-menu players into the deprecated bare
            -- IngameView on exit. ModTweakerView:exit already safely handles the
            -- "hero_view" target (supplies { menu_state_name = "overview" }).
            local origin = self.current_view
            self.views.mod_tweaker_view._exit_transition =
                (origin == "hero_view") and "hero_view" or "ingame_menu"
            self.current_view = "mod_tweaker_view"
        else
            _dbg_alert("[mt] transition: view not attached; ESC entry is a no-op")
        end
    end
    _dbg("[mt] transition registered: mod_tweaker_view")
end)
if not ok_settings_inject then
    _dbg_alert("[mt] transitions injection failed: %s", tostring(settings_inject_err))
end

-- ============================================================
-- Open the Mod Tweaker from gameplay (#125) — hotkey + chat command
-- ============================================================
-- The Mod Tweaker settings menu is reachable from the ESC menu's "Mod Tweaker"
-- button (the IngameViewLayoutLogic.setup_button_layout injection above). This
-- exposes a DIRECT opener so a function-call keybind + a chat command can open it
-- without going through the ESC menu first.
--
-- It drives the SAME `mod_tweaker_view` transition the ESC button uses (registered
-- just above), via Managers.ui:handle_transition — so there is NO new hook and NO
-- duplicated open logic. The transition closure handles attach + origin-capture +
-- current_view, and works from raw gameplay (current_view is nil there, so the
-- closure sets _exit_transition = "ingame_menu" as the FALLBACK only). With the
-- #124 change the view's exit always routes to "exit_menu" (game), so a hotkey-
-- opened menu — which has no originating menu — correctly returns to gameplay on
-- exit. Mirrors the sibling in-mission inventory/hero-select openers
-- (Managers.ui:handle_transition(..., { use_fade = true })).
--
-- SCOPE: keep AND mid-mission. The Mod Tweaker is a borrowed-renderer settings
-- LIST (not a preview world), so it is NOT subject to the keep-only preview-world
-- crash class that gates the hero-select/inventory features — the standalone
-- ModTweakerView already opens reliably in-mission via the ESC button, and this
-- reuses that exact path. No Chaos Wastes/deus gate is needed (no loadout surface).
-- (In-mission behavior still wants the user's in-game confirmation.)
mod.gut_open_mod_tweaker = function()
    if not (Managers.ui and Managers.ui.handle_transition) then
        mod:echo("UI manager not available (not in-game?).")
        return
    end
    local ok, err = pcall(function()
        Managers.ui:handle_transition("mod_tweaker_view", { use_fade = true })
    end)
    if not ok then
        mod:echo("Could not open the Mod Tweaker: " .. tostring(err))
    end
end

mod:command("mod_tweaker", "Open the Mod Tweaker settings menu (works in the keep and mid-mission). Same as the gut_open_mod_tweaker_hotkey keybind and the ESC-menu 'Mod Tweaker' button.", function()
    mod.gut_open_mod_tweaker()
end)

-- NOTE the second param: IngameUI.init passes the context to setup_views as an
-- ARGUMENT (ingame_ui.lua:107) and does NOT store self.ingame_ui_context until
-- later, so reading self.ingame_ui_context here is nil — that nil context made
-- ModTweakerView:new throw, the view never attached, and transitioning to the
-- (missing) view crashed IngameUI at ingame_ui.lua:625. Capture the arg instead.
-- Early attach attempt. May no-op if self.views isn't populated yet at this
-- hook's timing (the transition lazy-attach is the guaranteed path).
mod:hook_safe("IngameUI", "setup_views", function(self, ingame_ui_context)
    _attach_view(self, ingame_ui_context)
end)

-- The ESC-menu "Mod Tweaker" button is the raw key "mod_tweaker_button_name"
-- (ingame_view.lua:252 content.title_text = data.display_name, :138
-- title_text.localize = true), localized at draw by the engine localizer. VMF mod
-- loc is NOT in the engine tables, so it rendered as "<mod_tweaker_button_name>".
--
-- TWO prior HOOK fixes FAILED: (a) hooking _G.Localize — the global is set via
-- rawset in LocalizationManager.init, so a re-init blows the VMF wrapper away; and
-- (b) hooking LocalizationManager.lookup — the button's text pass ALSO localizes
-- via LocalizationManager.simple_lookup (ui_passes.lua:1599), a SIBLING method that
-- `lookup` never routes through. Both are interception; both miss a path.
--
-- ROOT-CAUSE FIX (workflow wf_8504e8ba): SUPPLY the string instead of intercepting.
-- LocalizationManager._base_lookup checks self._backend_localizations FIRST
-- (localization_manager.lua:50-51) and is the shared bottom of BOTH lookup and
-- simple_lookup, so registering the string there resolves on every path natively —
-- no wrapped closure to bypass. (LA already hooks _base_lookup in the field,
-- confirming that table is the universal chokepoint.)
--
-- (#153/#292) The same defect class covers every gut key the ENGINE localizes:
-- the hidden-passive perk rows render display_name/description through GLOBAL
-- Localize (hero_window_talents.lua:477, hero_window_talents_console.lua:672),
-- and the Video-tab profile widgets localize their title text, tooltip keys and
-- the dropdown label (setup third return, consumed at options_view.lua:1280)
-- through localize=true widget fields. Those keys lived only in VMF's mod-local
-- table, so they drew as raw "<key>" text. Supply them to the SAME backend table
-- here. The English strings are read from the mod localization file (single
-- source of truth); VMF's "%%" escapes are collapsed to a literal "%" because
-- the engine path has NO string.format pass for these strings (a perk row with
-- no description_values returns Localize(str) untouched, ui_utils.lua:36-38).
-- The dropdown OPTION texts are deliberately absent: they are pre-resolved via
-- mod:localize inside the setup callbacks and never hit the engine localizer.
local ENGINE_UI_LOC_KEYS = {
    -- #153 hidden career passives (native Perks rows).
    "gut_hidden_passive_whc_headshot_name",
    "gut_hidden_passive_whc_headshot_desc",
    "gut_hidden_passive_whc_crit_name",
    "gut_hidden_passive_whc_crit_desc",
    "gut_hidden_passive_whc_combined_name",
    "gut_hidden_passive_whc_combined_desc",
    -- #292 Video-tab profile controls (title, dropdown labels, tooltips).
    "gut_video_profiles_header",
    "gut_video_profile_selector",
    "gut_video_profile_selector_tooltip",
    "gut_video_profile_action",
    "gut_video_profile_action_tooltip",
}

local engine_ui_loc_cache  -- built once; re-registration re-USES it (dofile is not free)
local function _engine_ui_localizations()
    if engine_ui_loc_cache then return engine_ui_loc_cache end
    local strings = {}
    local ok, loc_table = pcall(mod.dofile, mod,
        "scripts/mods/gui_tweaker_dev/gui_tweaker_dev_localization")
    if not ok or type(loc_table) ~= "table" then
        return strings
    end
    local complete = true
    for _, key in ipairs(ENGINE_UI_LOC_KEYS) do
        local entry = loc_table[key]
        local text = type(entry) == "table" and entry.en
        if type(text) == "string" then
            strings[key] = text:gsub("%%%%", "%%")
        else
            complete = false
        end
    end
    -- Cache only a complete harvest so a failed early read retries next call.
    if complete then engine_ui_loc_cache = strings end
    return strings
end

local function _register_button_loc()
    local loc = Managers and Managers.localizer
    if loc and loc.append_backend_localizations then
        pcall(loc.append_backend_localizations, loc, { mod_tweaker_button_name = "Mod Tweaker" })
        -- (#153/#292) engine-rendered gut UI keys (see ENGINE_UI_LOC_KEYS above).
        pcall(loc.append_backend_localizations, loc, _engine_ui_localizations())
        -- #352 uses the same native backend-localization path for the explicit
        -- legacy THP names. Re-supply them after language/localizer re-init.
        local thp_names = mod._gut_original_thp_names
        if thp_names and thp_names.register_backend_localizations then
            thp_names.register_backend_localizations()
        end
        -- PROBE: after registering, what does the engine localizer actually return
        -- for the key? If this prints "Mod Tweaker", the append works and any <> the
        -- user still sees is a DIFFERENT element (not this ESC button). If it prints
        -- "<mod_tweaker_button_name>", the backend-loc path is NOT what this button
        -- localizes through and we need a different fix.
        local resolved = "?"
        if rawget(_G, "Localize") then pcall(function() resolved = Localize("mod_tweaker_button_name") end) end
        mod:info("[mt] registered backend loc; Localize('mod_tweaker_button_name') -> '%s'", tostring(resolved))
        return true
    end
    mod:info("[mt] backend-loc register SKIPPED (Managers.localizer not ready at this point)")
    return false
end
-- Register at boot if the localizer is already up; otherwise on_all_mods_loaded (below)
-- and the IngameView.on_enter retry guarantee it's set before the ESC menu draws.
_register_button_loc()
-- _backend_localizations is reset to {} in LocalizationManager.init (a mid-session
-- language switch re-inits), so re-register after any re-init. This is DATA, not a
-- wrapped closure — immune to the rawset/VMF-chain fragility that killed both hooks.
mod:hook_safe("LocalizationManager", "init", function()
    _register_button_loc()
end)
-- Belt-and-suspenders: register when the ESC menu opens (Managers.localizer is
-- definitely up by then), so even if boot/on_all_mods_loaded missed, the key is set
-- before the button's title_text is drawn. (gut hooks HeroView.on_enter, not
-- IngameView.on_enter — distinct pair, no duplicate.)
mod:hook_safe("IngameView", "on_enter", function()
    _register_button_loc()
end)

-- (#153/#292) Lock: every engine-rendered gut UI key must resolve through the
-- GLOBAL localizer path (same structure as issue352's loc validation in
-- _gut_original_thp_names.lua). FAILS whenever a key is missing from the loc
-- file, still carries a VMF %% escape, or is not being served by the engine
-- localizer (Localize falls through to "<key>" when unsupplied).
_rt_register("issue153_292_engine_ui_loc_supplied", function()
    local strings = _engine_ui_localizations()
    for _, key in ipairs(ENGINE_UI_LOC_KEYS) do
        local text = strings[key]
        if type(text) ~= "string" then
            return "engine-UI localization source missing key: " .. key
        end
        if text:find("%%%%") then
            return "engine-UI localization still carries a VMF %% escape: " .. key
        end
    end
    local localize = rawget(_G, "Localize")
    if type(localize) ~= "function" then
        return "global Localize unavailable (engine-UI keys cannot resolve)"
    end
    for _, key in ipairs(ENGINE_UI_LOC_KEYS) do
        local ok, resolved = pcall(localize, key)
        if not ok or resolved ~= strings[key] then
            return string.format("engine localizer does not serve %s (got %s)",
                key, tostring(resolved))
        end
    end
end)

-- ESC/keep-menu button-overflow compaction (v0.2.56; REWRITTEN v0.2.64-dev — was
-- hooking the WRONG class for 8 versions).
--
-- DIAGNOSIS of why the prior fix never worked:
--   * The keep pause/ESC menu the user sees is NOT the legacy IngameView. The
--     reported button list (character_selection / spoils_of_war /
--     return_to_pc_menu_hero_view / quit_game_hero_view, 10 entries) is the MODERN
--     HeroView sub-window `HeroWindowIngameView` (hero_window_ingame_view.lua) — the
--     "Main Menu" screen inside hero_view. That class has NO set_background_height
--     method; the gut hook on `IngameView.set_background_height` therefore NEVER
--     FIRED for the keep menu. (Legacy IngameView is only the bare in-MISSION menu.)
--   * Even on the legacy IngameView path the logo branch was dead: IngameView.
--     create_ui_elements (ingame_view.lua:122-152) NEVER assigns self.logo — the logo
--     widget isn't even instantiated there (it has no `logo` widget def), so
--     `if self.logo ...` was always nil. The visible logo comes from the modern menu.
--
-- The modern menu lays out its button column + sizes its panel in
-- HeroWindowIngameView._update_presentation (hero_window_ingame_view.lua:490-515):
-- each title button gets `offset[2] = -(60 * index - 1)` (spacing = 60, line 504),
-- and the background panel grows to `total_height + 90` (line 513). With 10 buttons
-- the column runs `0 .. -540` and overflows off the bottom. The logo widget is
-- `_widgets_by_name.logo` (definitions :287, scenegraph node "logo").
--
-- FIX: hook_safe `HeroWindowIngameView._update_presentation` (runs AFTER vanilla
-- positions the column, so our shift/hide stick) and, once over the overflow
-- threshold: (a) lift the whole button column up by re-walking the same index→offset
-- math with a reduced spacing AND a positive top bias, and (b) hide the logo by
-- zeroing its style.color alpha. hook_safe is correct (the vanilla method returns
-- nothing; it mutates widget offsets + the scenegraph in place). This (Class,method)
-- pair is hooked NOWHERE ELSE in gut — grep-verified before adding (the only other
-- HeroView-family hook is HeroView.on_enter, a different class+method).
--
-- (#93) ALWAYS-ON implicit feature (2026-06-24): the `gut_compact_esc_menu` toggle +
-- setting were removed — this was never meant to be optional (gut itself adds the Mod
-- Tweaker ESC button that causes the overflow this fixes, so the fix should always run,
-- like wt's auto-vent). The hook is only a no-op below the overflow threshold anyway, so
-- there's nothing to gate. No setting read remains.
--
-- NOTE the COLUMN_SHIFT / SPACING numbers below are TUNE-IN-GAME values — they move
-- the column the right DIRECTION (up) but the exact lift needs an in-game eyeball.
local _MT_ESC_OVERFLOW_THRESHOLD = 8   -- vanilla keep menu is ~8 buttons; gut + VMF push it to 10
mod:hook_safe("HeroWindowIngameView", "_update_presentation", function(self)
    local buttons = self._title_button_widgets
    local layout_logic = self.layout_logic
    if not (buttons and layout_logic) then return end
    local ok_ld, layout_data = pcall(layout_logic.layout_data, layout_logic)
    if not ok_ld or type(layout_data) ~= "table" then return end
    local num = #layout_data
    if num < _MT_ESC_OVERFLOW_THRESHOLD then return end

    -- Re-pack the column tighter so all `num` buttons fit, and bias the whole stack
    -- UP. Vanilla uses spacing = 60 starting near offset 0 (descending). We compress
    -- spacing and add a positive top bias = half the saved height, re-centring the
    -- shorter column. (Vanilla math: hero_window_ingame_view.lua:497-505.)
    local VANILLA_SPACING = 60
    local SPACING = 48                                  -- tighter rows (TUNE IN-GAME)
    local saved = (VANILLA_SPACING - SPACING) * num     -- total height reclaimed
    local TOP_BIAS = math.floor(saved / 2)              -- lift so the column re-centres
    for index = 1, num do
        local w = buttons[index]
        if w and w.offset then
            -- mirrors vanilla `-(spacing * index - 1)` with our spacing + the up-bias.
            w.offset[2] = -(SPACING * index - 1) + TOP_BIAS
        end
    end

    -- Hide the keep logo so the (now lifted) column has clear headroom. The logo
    -- widget is _widgets_by_name.logo (definitions :287, built via
    -- UIWidgets.create_simple_texture). create_simple_texture nests color under
    -- style.texture_id.color, NOT style.color (ui_widgets.lua:5302-5318) — the prior
    -- IngameView code read the wrong path, which was part of why "logo still shows".
    -- VT2 color tables are {A,R,G,B}, so alpha is index [1]. Idempotent — re-zeroing
    -- each presentation rebuild is harmless.
    local wbn = self._widgets_by_name
    local logo = wbn and wbn.logo
    local lstyle = logo and logo.style and logo.style.texture_id
    if lstyle and lstyle.color then
        lstyle.color[1] = 0
    end

    -- Lift the keep separator/divider by the same amount as the button column so it
    -- sits ABOVE the menu text instead of bleeding through it. _widgets_by_name.divider
    -- is the upper rule (hero_window_ingame_view_definitions.lua:279,
    -- UIWidgets.create_simple_texture("divider_01_top", "divider"); sg node "divider").
    -- NOT divider_bottom (:280, the lower rule). It's registered into _widgets_by_name
    -- in create_ui_elements (:161-169), so it's drawable/mutable here. The button
    -- column was lifted +TOP_BIAS via each button widget's render offset[2] (:1096);
    -- mutating the divider's render offset[2] the SAME {0,0,0} field keeps the shift
    -- isolated to the divider texture (does NOT cascade to the logo/panel/buttons that
    -- are scenegraph-parented to the "divider" node — a render-offset change doesn't
    -- touch the scenegraph). Idempotent: TOP_BIAS is recomputed each presentation
    -- rebuild and vanilla never resets this offset, so SET (not +=) to avoid drift.
    local divider = wbn and wbn.divider
    if divider and divider.offset then
        divider.offset[2] = TOP_BIAS
    end
end)

mod:dofile("scripts/mods/gui_tweaker_dev/_gut_mod_tweaker_contracts").install({
    register = _rt_register,
    src_read = _rt_src_read,
})
local _gut_ui_tweaks = mod:dofile("scripts/mods/gui_tweaker_dev/_gut_ui_tweaks_integration").install({
    register = _rt_register,
    src_read = _rt_src_read,
})
local _gut_temporal_fix = _gut_ui_tweaks.temporal_fix
local _gut_uitweaks_sync = _gut_ui_tweaks.sync
-- UI Tweaks buff-bar end-time crash fix (absorbed): nil-guards
-- PriorityBuffUI._add_buff so stacking buffs (e.g. Bardin OE pump stacks) stop
-- spamming "attempt to compare nil with number" every frame. No-op if UI Tweaks
-- isn't installed. See _gut_buffbar_endtime_fix.lua for the diagnosed mechanic.
local _gut_buffbar_fix = mod:dofile("scripts/mods/gui_tweaker_dev/_gut_buffbar_endtime_fix")
-- Settings snapshot export: retail exposes no file-read channel (#517), so
-- /export_settings dumps TOML to the log and the desktop companion persists it.
local _gut_config = mod:dofile("scripts/mods/gui_tweaker_dev/_gut_config_file")
_rt_register("issue517_config_read_retired", function()
    if type(_gut_config) ~= "table" or _gut_config.read_supported ~= false then
        return "#517 regression: config module no longer declares retail read-back unsupported"
    end
    if _gut_config.apply ~= nil then
        return "#517 regression: impossible retail config apply path was reintroduced"
    end
    if type(_gut_config.export_to_log) ~= "function" then
        return "#517 regression: settings snapshot export was lost while retiring read-back"
    end
end)
-- Hide UI (3 modes: off/partial/complete/camera) — migrated from general_tweaker.
-- Owns mod.update (chains any prior) for per-frame complete/camera enforcement;
-- registers the gut_hud_cycle keybind function + /hud command.
local _gut_hide_ui = mod:dofile("scripts/mods/gui_tweaker_dev/_hide_ui")
-- GUI material guard: drops any unloadable material from UIRenderer.create before it
-- reaches World.create_screen_gui, which C-fatals (bypasses pcall/xpcall) on a missing
-- material. Prevents the "Gui material not found" client CTD class on mod-compat edges
-- (e.g. More Loading Screens + ui_1080p_chat on mission load, 2026-07-01). Mod-agnostic;
-- the general form of the LA-atlas keepalive below. See _gut_gui_material_guard.lua.
pcall(mod.dofile, mod, "scripts/mods/gui_tweaker_dev/_gut_gui_material_guard")
-- Loremaster's Armoury atlas keep-alive: pins LA's package so its custom atlas can't
-- be unloaded out from under the hero-view HDR renderer (VMF injects it there and the
-- engine C-fatals on a missing material). No-op if LA isn't installed. See
-- _la_atlas_keepalive.lua (crash efadf778).
-- Assigns the forward-declared `_gut_la_keepalive` upvalue (declared above the Mod
-- Tweaker transition closure so that closure + the view module can call its pin()).
_gut_la_keepalive = mod:dofile("scripts/mods/gui_tweaker_dev/_la_atlas_keepalive")
-- NumericUI compatibility: real-time ability cooldown plus #249 authoritative
-- teammate ammo from the owner/husk InventoryExtension exact current/max pair.
-- No-op if NumericUI isn't installed. See _numericui_cooldown_realtime.lua.
local _gut_numericui_cd = mod:dofile("scripts/mods/gui_tweaker_dev/_numericui_cooldown_realtime")
local _gut_prev_on_all_mods_loaded = mod.on_all_mods_loaded
mod.on_all_mods_loaded = function(...)
    if _gut_prev_on_all_mods_loaded then _gut_prev_on_all_mods_loaded(...) end
    if _gut_temporal_fix and _gut_temporal_fix.apply then pcall(_gut_temporal_fix.apply) end
    if _gut_buffbar_fix and _gut_buffbar_fix.apply then pcall(_gut_buffbar_fix.apply) end
    -- (#312) UI Tweaks write-through: re-attempt the one-time migrate now that
    -- HideBuffs is definitely loaded (folds any pre-existing gut HUD offsets in).
    if _gut_uitweaks_sync and _gut_uitweaks_sync.migrate then pcall(_gut_uitweaks_sync.migrate) end
    -- (#312) Seed gut's vanilla-HUD mirror toggles FROM the live engine user
    -- settings, so a change made in the vanilla Options menu wins. No notify -> no
    -- write-back loop (would re-fire on_setting_changed and thrash the engine save).
    pcall(function()
        mod:set("gut_vanilla_numeric_ui", Application.user_setting("numeric_ui") and true or false)
        mod:set("gut_vanilla_persistent_ammo", Application.user_setting("persistent_ammo_counter") and true or false)
    end)
    -- Bench-in-mission option (moved from cim 2026-07-02): one-time ADOPTION of the
    -- user's pre-existing cim `allow_in_mission` value into gut's toggle (marker-based,
    -- NOT nil-based - VMF may materialize widget defaults, so a nil check can't tell
    -- "never adopted" from "default"), then on every later boot PUSH gut's value into
    -- cim's store so the two never drift (cim's readers keep reading cim's own key).
    local cim = get_mod("cim_dev") or get_mod("cim")
    if cim then
        if mod:get("gut_cim_bench_adopted") ~= true then
            mod:set("gut_cim_bench_in_mission", cim:get("allow_in_mission") and true or false)
            mod:set("gut_cim_bench_adopted", true)
            printf("[gut_dev:CIM_BENCH] adopted cim allow_in_mission=%s into gut toggle (one-time)",
                tostring(cim:get("allow_in_mission")))
        else
            cim:set("allow_in_mission", mod:get("gut_cim_bench_in_mission") and true or false)
        end
    end
end
if _gut_temporal_fix and _gut_temporal_fix.apply then pcall(_gut_temporal_fix.apply) end
if _gut_buffbar_fix and _gut_buffbar_fix.apply then pcall(_gut_buffbar_fix.apply) end

-- Parry Indicator (absorbed): recolours the HUD block shields during the
-- timed-block window for EVERY weapon (the original gated on the Parry trait).
-- Optional via `gut_parry_indicator`. Hooks register at dofile time. See
-- _gut_parry_indicator.lua for the verified mechanic + the dropped gate.
pcall(mod.dofile, mod, "scripts/mods/gui_tweaker_dev/_gut_parry_indicator")

-- Optional: large respawn countdown over a dead teammate's portrait (client-safe
-- estimate anchored to the dead-skull state). Draws from IngameHud.update via a
-- UIWidget anchored on the frame's own live portrait scenegraph (#285 fix,
-- ported verbatim from Respawn CD 3747644100). See _gut_respawn_timer.lua.
pcall(mod.dofile, mod, "scripts/mods/gui_tweaker_dev/_gut_respawn_timer")

-- (#285) Guards the respawn-timer #285 fix on THREE invariants:
--   (a) the draw rides IngameHud.update (proven by "Respawn CD", 3747644100),
--       never the broken UnitFrameUI.draw path (which rendered nothing);
--   (b) it draws the number via UIRenderer.draw_widget through the live team
--       frame scenegraph and its canonical `portrait_pivot` -- NOT a mirrored
--       copy and NOT an
--       immediate draw_text at get_world_position, which double-applies the
--       resolution scale and lands the number off the portrait (the "wrong
--       spot / tiny red numbers over the health bar" report);
--   (c) the teammate font base stays large (72), so it can't regress to tiny.
_rt_register("respawn_timer_ingamehud_draw_path", function()
    local fn = mod._gut_respawn_draw
    if type(fn) ~= "function" then
        return "respawn timer module not installed (mod._gut_respawn_draw missing)"
    end
    local ok, info = pcall(debug.getinfo, fn, "S")
    if not ok or type(info) ~= "table" or not info.source then return end
    local path = info.source:sub(1, 1) == "@" and info.source:sub(2) or info.source
    local txt = _rt_src_read(path)  -- (#511) io-safe; nil in retail sandbox => skip
    if not txt then return end
    if not txt:find('hook_safe("IngameHud", "update"', 1, true) then
        return "respawn timer regressed: draw no longer rides hook_safe(IngameHud, update) -- #285"
    end
    if txt:find('"UnitFrameUI", "draw"', 1, true) then
        return "respawn timer regressed: reintroduced the broken UnitFrameUI.draw hook (renders nothing) -- #285"
    end
    if not txt:find("UIRenderer.draw_widget", 1, true) then
        return "respawn timer regressed: no longer draws via the widget path -- #285 wrong-position"
    end
    if txt:find("get_world_position", 1, true) then
        return "respawn timer regressed: reintroduced get_world_position immediate-draw (double-scaled, wrong spot) -- #285"
    end
    if not txt:find("font_size%s*=%s*72") then  -- Lua pattern: whitespace-robust
        return "respawn timer regressed: teammate font base is no longer 72 (renders tiny) -- #285"
    end
    if not txt:find("frame_scenegraph", 1, true)
        or not txt:find("frame_scenegraph.portrait_pivot", 1, true)
        or not txt:find("widget.ui_scenegraph", 1, true) then
        return "respawn timer regressed: draw no longer uses the live frame portrait scenegraph -- #285"
    end
    if txt:find("SCENEGRAPH_DEF", 1, true) then
        return "respawn timer regressed: copied frame scenegraph reintroduced -- #285"
    end
end)

-- (#539) Mid-mission Customize crash guard: the _get_item ItemId-normalizer must stay
-- wired and behavioral. Vanilla HeroWindowItemCustomization._setup_illusions does
-- string.gsub(item.ItemId, "^vs_", "") -- the sole item.ItemId read in that window -- and
-- a modded-realm mission loadout item carries no ItemId, so without the normalizer the
-- gear-icon Customize screen hard-crashes mid-mission. io-safe: driven synthetically, no
-- source read (the normalizer is a pure function the module publishes on mod.).
_rt_register("customize_item_id_normalized_539", function()
    if type(mod._gut539_normalize_item_id) ~= "function" then
        return "_gut539_normalize_item_id missing (#539 fix stripped)"
    end
    -- A nil-ItemId item gets ItemId filled from its key.
    local a = { key = "wh_1h_axe" }
    local filled = mod._gut539_normalize_item_id(a)
    if not (filled and a.ItemId == "wh_1h_axe") then
        return "normalizer did not fill nil ItemId from key (got ItemId=" .. tostring(a.ItemId) .. ")"
    end
    -- An item that already carries an ItemId is left untouched (no clobber).
    local b = { key = "x", ItemId = "vs_es_1h_sword" }
    local touched = mod._gut539_normalize_item_id(b)
    if touched or b.ItemId ~= "vs_es_1h_sword" then
        return "normalizer mutated an item that already had an ItemId"
    end
    -- Rename guard: the vanilla choke point the hook wraps must still exist.
    local w = rawget(_G, "HeroWindowItemCustomization")
    if type(w) ~= "table" or type(w._get_item) ~= "function" then
        return "HeroWindowItemCustomization._get_item vanished (hook orphaned)"
    end
end)

-- Modded-realm-scoped native loadouts (#175): while in the modded (EAC-untrusted) realm,
-- the native I-VI loadout bar reads/writes a MODDED-ONLY VMF store so official-realm
-- loadouts are never touched by modded play. Intercepts the backend MIRROR
-- (PlayFabMirrorAdventure) reads/writes -- the single convergence point below the item +
-- talents interfaces (PRE-FLIGHT: gut has no other hook on PlayFabMirrorAdventure,
-- BackendInterfaceItemPlayfab.refresh_bot_loadouts, or HeroWindowLoadoutSelectionConsole
-- ._save_bot_equipment; gut's only HeroWindowLoadoutSelectionConsole hook is on
-- ._show_context_menu in _gut_mission_inventory.lua). Inert in the official realm and in
-- Versus. See _gut_native_loadouts.lua for the full isolation rationale.
local _gut_native_loadouts = mod:dofile("scripts/mods/gui_tweaker_dev/_gut_native_loadouts")
if type(_gut_native_loadouts) == "table" and type(_gut_native_loadouts.rt_checks) == "table" then
    for _, c in ipairs(_gut_native_loadouts.rt_checks) do
        _rt_register(c.name, c.fn)
    end
end

-- Exit-time loadout/cosmetic persistence backstop (#354/#353/#287/#175). Re-read the live
-- selected loadout and reconcile it into the modded store at bounded exit edges, so state
-- mutated through a path that missed the equip-time capture (LA-cloned cosmetic dispatch, a
-- WT cross-character weapon whose apply lands outside a captured equip) is not lost on quit.
-- exit_snapshot is idempotent (a clean state writes nothing) and inert outside the modded
-- Adventure realm; full rationale + isolation in _gut_native_loadouts.lua. These are VMF
-- lifecycle callbacks CHAINED off the previous handler -- NOT engine hooks -- so there is no
-- (Class, method) collision (NON-NEGOTIABLE 8). Every edge is pcall-guarded.
if type(_gut_native_loadouts) == "table" and type(_gut_native_loadouts.exit_snapshot) == "function" then
    local _snap = function(edge) pcall(_gut_native_loadouts.exit_snapshot, edge) end
    local _prev_ogsc = mod.on_game_state_changed
    mod.on_game_state_changed = function(status, state_name)
        if _prev_ogsc then _prev_ogsc(status, state_name) end
        if status == "exit" and state_name == "StateIngame" then
            _snap("ingame_exit")            -- leaving the keep/mission; backend still warm
        elseif status == "enter" and state_name == "StateTitleScreen" then
            _snap("title_enter")            -- returned to the title screen (quit-to-menu)
        end
    end
    local _prev_unload = mod.on_unload
    mod.on_unload = function(...)
        if _prev_unload then _prev_unload(...) end
        _snap("unload")                     -- game shutdown / mod unload
    end
end

-- Native-loadout 30-slot capacity census (#231). The six-button window has
-- direct logical-index coupling across selection/context/delete/bot paths, so
-- this phase records the data, frozen-widget and asset boundaries without
-- mutating the realm-shared InventorySettings table.
do
    local ok, api = pcall(mod.dofile, mod,
        "scripts/mods/gui_tweaker_dev/_gut_loadout_capacity_probe")
    if ok and type(api) == "table" then
        for _, check in ipairs(api.rt_checks or {}) do
            _rt_register(check.name, check.fn)
        end
    else
        _dbg_alert("[gut:231] capacity probe failed: %s", tostring(api))
    end
end

-- Bot designated-loadout victory pose (#232). PlayerBot.spawn passes is_bot for
-- skin/frame but omits it for the adjacent pose lookup; repair that one argument
-- only while the synchronous bot-spawn call is active.
do
    local ok, api = pcall(mod.dofile, mod,
        "scripts/mods/gui_tweaker_dev/_gut_bot_pose")
    if ok and type(api) == "table" then
        for _, check in ipairs(api.rt_checks or {}) do
            _rt_register(check.name, check.fn)
        end
    else
        _dbg_alert("[gut:232] bot-pose module failed: %s", tostring(api))
    end
end

-- Held-Tab live-session loadout provider (#245 properties/traits, #246
-- equipped illusion, #250 CW talents, #533 CW collectible rows). The v2 player
-- list renders detached RPC loadout rows frozen at add_equipment time; while
-- visible, the provider reconciles the local player's melee/ranged
-- properties+traits+skin from their exact live backend instances at 4 Hz,
-- decorates every player's row skin from the synchronized (wearer, slot)
-- cosmetic identity, repairs the deus talent strip after vanilla populates it,
-- and suppresses the adventure tome/grim/dice rows inside the deus mechanism.
-- One module owns both IngamePlayerListUI hooks (see its header).
do
    local ok, api = pcall(mod.dofile, mod,
        "scripts/mods/gui_tweaker_dev/_gut_tab_property_refresh")
    if ok and type(api) == "table" then
        for _, check in ipairs(api.rt_checks or {}) do
            _rt_register(check.name, check.fn)
        end
    else
        _dbg_alert("[gut:245] Tab live-loadout provider failed: %s", tostring(api))
    end
end

-- Floating Damage Numbers (MIGRATED from general_tweaker 2026-06-29): client-side,
-- networking-free numbers over enemies you damage, via the engine's own
-- DamageNumbersUI + DamageUtils.add_unit_floating_damage_numbers. Registers its OWN
-- hooks on DamageUtils.add_damage_network / add_damage_network_player plus the #938
-- burst-aggregation hook on DamageUtils.add_unit_floating_damage_numbers itself
-- (PRE-FLIGHT: gut has no other hook on any of the three methods — it only reads
-- DamageUtils.is_in_inn), and chains mod.update / mod.on_setting_changed /
-- mod.on_game_state_changed (dofile'd after all are defined).
-- See _gut_damage_numbers.lua.
pcall(mod.dofile, mod, "scripts/mods/gui_tweaker_dev/_gut_damage_numbers")

-- Main Menu & Startup (MIGRATED from general_tweaker 2026-06-29, #190): two
-- independent toggles (both default OFF) — "Skip start screen" (sets
-- GameSettingsDevelopment.skip_start_screen, next-launch) + "Return to Main Menu
-- quits to desktop" (remaps the return_to_title_screen transitions to quit_game),
-- plus the /quit instant-exit command. Plain engine-data reassignments, NO
-- hooks (no duplicate-hook concern); chains mod.on_setting_changed + mod.on_disabled.
-- See _gut_mainmenu.lua.
pcall(mod.dofile, mod, "scripts/mods/gui_tweaker_dev/_gut_mainmenu")

-- 3rd-Person Camera (MIGRATED from general_tweaker 2026-06-29, #191): follow camera
-- with distance/height/side-offset sliders (Camera Distance min stays -3.0 per #147),
-- the gut_tp_camera_enabled toggle + /tp command. Hooks
-- PlayerUnitFirstPerson.set_first_person_mode + .extensions_ready (PRE-FLIGHT: gut has
-- no other hook on PlayerUnitFirstPerson). Chains mod.update (tp re-apply timer) +
-- mod.on_setting_changed / mod.on_game_state_changed / mod.on_disabled. Dropped gt's
-- godmode/noclip post-spawn-reapply trigger (gut has neither). See _gut_camera.lua.
pcall(mod.dofile, mod, "scripts/mods/gui_tweaker_dev/_gut_camera")

-- Free Camera (#307): detached fly-cam via the engine FreeFlightManager (NOT the
-- rig-offset 3P camera above). Character stops responding to input and stays put;
-- WASD/mouse/E/Q fly the detached camera, F8 exits. Deliberately does NOT lift the
-- disable_free_flight gate (so the vanilla F8/F9/drop-player dispatcher never runs)
-- and never calls loco:set_disabled (the crash class that killed the old gt attempt).
-- Hooks PlayerInputExtension.is_input_blocked + FreeFlightManager._exit_free_flight
-- (preflight: no other gut hook on either). Must dofile AFTER _gut_camera so it
-- chains mod.update / on_setting_changed / on_game_state_changed. See _gut_freecam.lua.
pcall(mod.dofile, mod, "scripts/mods/gui_tweaker_dev/_gut_freecam")

-- Skip Cutscenes (MIGRATED from general_tweaker 2026-06-25, issue #106): hooks
-- CutsceneSystem.flow_cb_cutscene_effect / flow_cb_activate_cutscene_logic /
-- skip_pressed + ShowCursorStack.pop, exposes mod.gut_skip_cutscenes_toggle, and
-- chains mod.update for the deferred auto-skip processor. Behavior is unchanged from
-- gt (CW/deus gating + deferred-skip teardown preserved verbatim); ADDS a printf-based
-- [gut:cutscene] diagnostic (survives mod-logging-off) for the stuck dlc_castle CW
-- cutscene (#106). PRE-FLIGHT: gut has no other CutsceneSystem / ShowCursorStack.pop
-- hook (it only CALLS ShowCursorStack.show/.hide). Dofile'd AFTER _hide_ui.lua so its
-- mod.update chain captures the hide-ui update as prev. See _gut_cutscenes.lua.
do
    local ok, cutscenes = pcall(mod.dofile, mod, "scripts/mods/gui_tweaker_dev/_gut_cutscenes")
    if ok and type(cutscenes) == "table" then
        for _, c in ipairs(cutscenes.rt_checks or {}) do _rt_register(c.name, c.fn) end
    end
end

-- Disable Loading-Screen Monologues (MIGRATED from general_tweaker 2026-06-29, #192):
-- the REMAINDER of gt's old "Cutscenes & Monologues" group after the cutscene-skip
-- half migrated (#106). Flips script_data.disable_level_intro_dialogue; no hooks.
-- Chains mod.on_setting_changed; exposes mod.gut_intro_monologue_toggle + /intromono.
-- See _gut_monologue.lua.
pcall(mod.dofile, mod, "scripts/mods/gui_tweaker_dev/_gut_monologue")

-- In-mission inventory access (migrated from general_tweaker 2026-06-24): Open
-- Inventory In Mission (mod.gut_open_mission_inventory + /inv) + Customize
-- gear-icon cim crash-gate (HeroWindowLoadoutConsole._customize_item) + Show menu
-- tabs in-mission (HeroWindowPanelConsole.on_enter) + the InventorySettings/ESC
-- "Open Inventory" data patch (mod._gut_apply_keep_menus, driven by the
-- on_setting_changed branch + on_game_state_changed dispatcher above). All hooks
-- are singletons (preflight-verified: gut has no other HeroWindowLoadoutConsole /
-- HeroWindowPanelConsole hook). See _gut_mission_inventory.lua.
pcall(mod.dofile, mod, "scripts/mods/gui_tweaker_dev/_gut_mission_inventory")

-- In-mission HERO SELECT (#173 rewire, 2026-07-02): opens the REAL hero/career
-- selection screen (CharacterSelectionView, the keep "C"-key grid) mid-mission via
-- the vanilla `character_selection_force` transition
-- (mod.gut_open_mission_hero_select + /hero_select + the gut_open_hero_select_hotkey
-- keybind). Mid-mission the view's keep-only backdrop world is swapped in the cached
-- defs table to the mission-loadable `levels/ui_inventory_preview/world` (managed
-- package force-load under our own ref) and restored the moment the viewport mounts.
-- Career swap respawns IN PLACE (B7-proven). Registers two hook_safe singletons on
-- CharacterSelectionView (post_update_on_enter / on_exit -- restore points;
-- preflight-verified: gut hooks that class nowhere else). Deus/CW stays hard-blocked
-- (career swap would desync the deus profile/boon state). Full design + bundle
-- evidence in _gut_mission_hero_select.lua and HERO_SELECT_RESEARCH_173.md.
pcall(mod.dofile, mod, "scripts/mods/gui_tweaker_dev/_gut_mission_hero_select")

-- In-mission MISSION MAP (#305, #336): opens the start-game / mission-selection view
-- (the keep "M" map) mid-mission via the vanilla `start_game_view_force` transition
-- (mod.gut_open_mission_map + /map + the gut_mission_map_hotkey keybind, default M).
-- Adventure-only (deus/versus/weave blocked); optional host-only toggle. Mid-mission the
-- background window's keep-only world is swapped to the inventory-preview stage (managed
-- package async-loaded under ref "gut_mission_map"; level-less fallback while it streams),
-- picking a mission auto-starts it (countdown-flag arm + complete_level divert), and the
-- area-selection video widgets are skipped when their material is not in the ingame Gui
-- (the #336 area_video_* draw fatal). Hooks (all preflight-verified singletons): FOUR on
-- StartGameWindowBackgroundConsole, TWO on the area-selection windows
-- (StartGameWindowAreaSelectionConsoleV2._assign_video_player /
-- StartGameWindowAreaSelection._setup_video_player), hook_safe on
-- MatchmakingStateWaitForCountdown.on_enter, full hook on GameModeManager.complete_level;
-- chains mod.on_game_state_changed (preview-package arm). See _gut_mission_map.lua.
pcall(mod.dofile, mod, "scripts/mods/gui_tweaker_dev/_gut_mission_map")

-- #649: filter only late custom careers lacking boot-time completion definitions;
-- StatisticsDatabase itself remains untouched. See guard module for source proof.
pcall(mod.dofile, mod, "scripts/mods/gui_tweaker_dev/_gut_guard649_mission_completion")

-- Inventory character-preview lighting (#522): preserves the vanilla preview
-- scene and installs one zero-allocation exposure callback on only
-- HeroWindowCharacterPreview.world_previewer.world. The exact prior callback is
-- chained/restored on Vanilla, exit, and disable. No package/level swap remains.
-- See _gut_inventory_backdrop.lua.
do  -- do-block: locals release back to the chunk (Lua 5.1 200-local ceiling)
    local ok_invbd, invbd = pcall(mod.dofile, mod, "scripts/mods/gui_tweaker_dev/_gut_inventory_backdrop")
    if ok_invbd and type(invbd) == "table" and type(invbd.rt_checks) == "table" then
        for _, c in ipairs(invbd.rt_checks) do
            _rt_register(c.name, c.fn)
        end
    end
end

-- EXPERIMENTAL/diagnostic (#173 feasibility): /gut_swap_career <n> asks the game to
-- swap the LOCAL player's CURRENT hero to career index n (1-4) mid-mission via the
-- vanilla ProfileRequester:request_profile(..., force_respawn=true). No UI, no
-- CharacterSelectionView (that's the mid-mission crash) -- just the host-mediated
-- profile-request call, mirroring ImguiCareerDebug's mid-mission requester accessor.
-- Heavy [gut:career] printf logging to farm ground truth on whether the swap+respawn
-- works live. Registers NO hooks (command only). See _gut_career_swap.lua.
pcall(mod.dofile, mod, "scripts/mods/gui_tweaker_dev/_gut_career_swap")

-- Dev probe: capture the live vanilla OptionsView so /dump_options can dump
-- its real scroll/mask/scrollbar layout - ground-truth for the Mod Tweaker
-- scrollbar. See _gut_diag_optionsview.lua (renamed from _gut_options_probe; #499).
do
    local ok_profiles, profiles = pcall(mod.dofile, mod, "scripts/mods/gui_tweaker_dev/_gut_video_profiles")
    if ok_profiles and type(profiles) == "table" and type(profiles.rt_checks) == "table" then
        for _, c in ipairs(profiles.rt_checks) do _rt_register(c.name, c.fn) end
    elseif not ok_profiles then
        printf("[gut:292] Video profile module failed to load: %s", tostring(profiles))
    end
end
pcall(mod.dofile, mod, "scripts/mods/gui_tweaker_dev/_gut_diag_optionsview")

-- (#340) All-language display support: DETECT-AND-DEFER only. The source mod
-- "Support All Languages" (Workshop 3232229691) ships a CUSTOM ~32 MB CJK font
-- atlas inside its own bundle (decompiled mechanism in _gut_all_languages.lua),
-- so gut cannot deliver the feature without redistributing another author's font.
-- This module installs NO hooks, adds NO menu toggle, and performs NO font swap —
-- it records the case-2 finding + a defer guard and printf-logs whether the
-- standalone mod is present. Resolution is documentation + recommend 3232229691.
pcall(mod.dofile, mod, "scripts/mods/gui_tweaker_dev/_gut_all_languages")

-- On Yer Feet, Mates! revive scoreboard attribution (#438). Vanilla's
-- server-side rpc_request_revive omits the StatisticsUtil call used by ordinary
-- revives and Comet's Gift. Repair only an unchanged revive count, so an
-- upstream or parallel credit wins without duplication.
do
    local ok, api = pcall(mod.dofile, mod,
        "scripts/mods/gui_tweaker_dev/_gut_revive_scoreboard")
    if ok and type(api) == "table" then
        for _, check in ipairs(api.rt_checks or {}) do
            _rt_register(check.name, check.fn)
        end
    else
        printf("[gut:438] revive-scoreboard module failed: %s", tostring(api))
    end
end

-- End-score Damage Taken green-circle attribution (#1151). Vanilla seeds the
-- candidate at zero before taking a minimum, so positive values can never win.
-- The adapter recomputes only that row after vanilla has appended each player.
do
    local ok, api = pcall(mod.dofile, mod,
        "scripts/mods/gui_tweaker_dev/_gut_damage_taken_scoreboard")
    if ok and type(api) == "table" then
        for _, check in ipairs(api.rt_checks or {}) do
            _rt_register(check.name, check.fn)
        end
    else
        printf("[gut:1151] damage-taken scoreboard module failed: %s", tostring(api))
    end
end

-- Original per-career names for the three level-five temporary-health talents
-- (#352). This mutates only each canonical talent record's presentation key.
do
    local ok, api = pcall(mod.dofile, mod, "scripts/mods/gui_tweaker_dev/_gut_original_thp_names")
    if ok and type(api) == "table" then
        mod._gut_original_thp_names = api
        _rt_register("issue352_original_thp_names_exact_identity", function()
            return api.validate(mod:get("gut_original_thp_names") and true or false)
        end)
    else
        _dbg_alert("[gut:352] original THP-name module failed: %s", tostring(api))
    end
end

-- Source-confirmed hidden innate career bonuses (#153). Presentation only:
-- the wrapper supplies a temporary Perks collection to the synchronous vanilla
-- population call, then restores the exact original table on success or error.
do
    local ok, api = pcall(mod.dofile, mod,
        "scripts/mods/gui_tweaker_dev/_gut_hidden_passives")
    if ok and type(api) == "table" then
        for _, check in ipairs(api.rt_checks or {}) do
            _rt_register(check.name, check.fn)
        end
    else
        _dbg_alert("[gut:153] hidden-passive module failed: %s", tostring(api))
    end
end

-- (#314) Clean compatibility phase for the external sanctioned-but-unlicensed
-- Simple UI mod. Confines its public live window records to the current screen;
-- no upstream code/assets are copied and no external function is replaced.
pcall(mod.dofile, mod, "scripts/mods/gui_tweaker_dev/_gut_simple_ui_compat")

-- Bestiary & Armory (absorbed): merged weapon (Armory) + enemy (Bestiary)
-- compendium with a PURE-DYNAMIC data layer — weapons enumerated live from
-- ItemMasterList, enemies from Breeds, so new content appears with no hardcoded
-- list. Currently ships the data providers + dump/open commands; the HeroView
-- compendium UI is built in subsequent phases. See _ba_compendium.lua.
-- Phase 0 of the HeroView compendium UI: the state class must dofile FIRST (so the
-- global HeroViewStateCompendium exists before HeroView resolves it), then the
-- injection (HeroView.init screen registration + /armory open), then the data
-- layer + commands.
-- The Mod Tweaker KEEP sub-state class (build 2) must ALSO dofile before the inject
-- module, for the same reason: _ba_heroview_inject registers BOTH the gut_compendium
-- and gut_mod_tweaker screens in its single HeroView.init hook, and HeroView resolves
-- state_name -> global class at transition time. The standalone in-mission
-- ModTweakerView (_mod_tweaker_view) is unchanged and stays the mission path.
pcall(mod.dofile, mod, "scripts/mods/gui_tweaker_dev/_ba_compendium_state")
pcall(mod.dofile, mod, "scripts/mods/gui_tweaker_dev/_mod_tweaker_state")
pcall(mod.dofile, mod, "scripts/mods/gui_tweaker_dev/_ba_heroview_inject")
pcall(mod.dofile, mod, "scripts/mods/gui_tweaker_dev/_ba_compendium")

-- UI Tweaks (HideBuffs) absorbed features — Phase 1: hide UI elements, hide
-- active buffs, loading-screen hides, Hide-HUD hotkey. `hb_data` defines the data
-- backbone (SETTING_NAMES, alignments, etc.) and MUST load first. Disable the
-- standalone "UI Tweaks" mod once gut covers it, to avoid double-hooking.
pcall(mod.dofile, mod, "scripts/mods/gui_tweaker_dev/hb/hb_data")
pcall(mod.dofile, mod, "scripts/mods/gui_tweaker_dev/hb/hide_elements")
pcall(mod.dofile, mod, "scripts/mods/gui_tweaker_dev/hb/level_loading_screen")

-- Scoreboard feature inventory (#272 phase 1). This central diagnostics module
-- inventories the vanilla eleven-topic catalog and records which requested
-- fields require new accumulation. Phase 2's independent live presenter is
-- loaded below; neither phase copies the unlicensed external implementation.
do
    local ok, diagnostics = pcall(mod.dofile, mod,
        "scripts/mods/gui_tweaker_dev/_gut_diagnostics")
    if ok and type(diagnostics) == "table" then
        for _, check in ipairs(diagnostics.rt_checks or {}) do
            _rt_register(check.name, check.fn)
        end
    else
        printf("[gut:272] diagnostics module failed: %s", tostring(diagnostics))
    end
end

-- Native live Tab statistics page (#272 phase 2). This consumes only the
-- ScoreboardHelper snapshot inventoried above and draws through the existing
-- IngamePlayerListUI lifecycle; no competing Tab input or custom transport.
do
    local ok, live_page = pcall(mod.dofile, mod,
        "scripts/mods/gui_tweaker_dev/_gut_scoreboard_live")
    if ok and type(live_page) == "table" then
        for _, check in ipairs(live_page.rt_checks or {}) do
            _rt_register(check.name, check.fn)
        end
    else
        printf("[gut:272] live scoreboard module failed: %s", tostring(live_page))
    end
end

-- Adventure disconnect/rejoin scoreboard retention (#437). This reuses the
-- #272 catalog policy, copies only scoreboard leaf paths, and owns no RPC.
do
    local ok, retention = pcall(mod.dofile, mod,
        "scripts/mods/gui_tweaker_dev/_gut_scoreboard_retention")
    if ok and type(retention) == "table" then
        for _, check in ipairs(retention.rt_checks or {}) do
            _rt_register(check.name, check.fn)
        end
    else
        printf("[gut:437] scoreboard retention module failed: %s", tostring(retention))
    end
end

-- (#281) Confirm the absorbed UI Tweaks (HideBuffs) fork actually booted: it used to
-- abort at load on a missing Penlight resource (hb_data.lua required a pl.* module
-- that does not exist in the retail sandbox), leaving mod.SETTING_NAMES nil and the
-- hide / loading-screen feature set silently dead. printf so it lands in the log with
-- mod-logging OFF. stock_owns=true means the stock UI Tweaks mod is present+enabled
-- and gut's fork is intentionally dormant (the #312 bridge owns the settings).
printf("[gut:281] hb fork boot: SETTING_NAMES=%s ubersreik_lvls=%s stock_owns=%s fork_active=%s",
    (type(mod.SETTING_NAMES) == "table") and "ok" or "NIL",
    (type(mod.ubersreik_lvls) == "table" and type(mod.ubersreik_lvls.contains) == "function") and "ok" or "BAD",
    tostring(mod.hb_stock_owns and mod.hb_stock_owns()),
    tostring(mod.hb_fork_active and mod.hb_fork_active()))

mod:info(string.format("gui_tweaker v%s ready (loadout save/restore + HUD edit mode + mod_tweaker api + bestiary/armory)", MOD_VERSION))

mod:info("[mem-probe] gut boot_lua=+%.1f MB (of ~1024 MB lua_heap cap)", (collectgarbage("count") - mod._gut_mem_t0) / 1024)
