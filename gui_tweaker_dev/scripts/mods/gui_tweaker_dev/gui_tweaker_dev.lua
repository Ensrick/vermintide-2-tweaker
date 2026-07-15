local mod = get_mod("gut_dev")
-- [mem-probe] temp Lua-footprint baseline (lua_heap 1 GiB cap diagnostic). Namespaced under
-- the mod table (v0.2.216-dev) so it no longer leaks into _G; read at the boot readout near
-- the end of this file.
mod._gut_mem_t0 = collectgarbage("count")

local MOD_VERSION = "0.2.274-dev"

-- Two-helper debug-logging policy (PROJECT_STANDARDS.md § 3.6).
-- Both route through VMF's built-in logging, gated by VMF output_mode_debug /
-- output_mode_warning. No per-mod toggle.
-- `_dbg` is for confirmation / expected behavior — debug channel only.
-- `_dbg_alert` is for unexpected / wrong / mismatch — warning channel only.
local function _dbg(fmt, ...)
    mod:debug("[gut:dbg] " .. fmt, ...)
end

local function _dbg_alert(fmt, ...)
    -- (warnings noise) demoted mod:warning -> mod:debug. These [gut:dbg] traces (e.g. HUD
    -- widget_init_skip when a scenegraph node isn't present in the keep) are diagnostics, not
    -- real problems, and at warning level they spammed the in-game chat. Debug is off by default.
    mod:debug("[gut:dbg] " .. fmt, ...)
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

mod:info("[gut:LOAD] v%s enabled fp=%s OK", MOD_VERSION, _settings_fingerprint())

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

-- (#345) Dev option status tags mirror GitHub lifecycle state. This runtime check
-- keeps the corrected GUT slice visible even in retail, where source-grep checks
-- cannot use `io`. `verify-fix-coop` intentionally maps to the same menu-facing
-- `[verify-fix]` tag; `[diag]` appears only while diagnostics-armed is active.
_rt_register("issue345_gut_loc_status_sync", function()
    local checks = {
        { "gut_tp_camera_enabled",       "[verify-fix] [Issue 209]", "[diag]" },
        { "gut_skip_cutscenes_hotkey",   "[verify-fix] [Issue 126]", "[diag]" },
        { "gut_mission_inventory_enabled","[verify-fix] [Issue 87]",  "Issue 193" },
        { "gut_cim_bench_in_mission",    "[verify-fix] [Issue 80]",  "[untested]" },
        { "gut_use_non_modded_loadouts", "[verify-fix] [Issue 287]", "[diag]" },
    }
    for i = 1, #checks do
        local key, required, forbidden = checks[i][1], checks[i][2], checks[i][3]
        local ok, value = pcall(mod.localize, mod, key)
        if not ok or type(value) ~= "string" then
            return string.format("%s localization unavailable", key)
        end
        if not string.find(value, required, 1, true) then
            return string.format("%s missing %s", key, required)
        end
        if forbidden and string.find(value, forbidden, 1, true) then
            return string.format("%s retains stale %s", key, forbidden)
        end
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
    local ok, loc = pcall(mod.dofile, mod, "scripts/mods/gui_tweaker_dev/gui_tweaker_localization")
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
    local guard_needle = '_skipped_cutscene_system == self and name == "fx' .. '_fade"'
    if not txt:find(guard_needle, 1, true) then
        return "#140 regression: the post-skip fx_fade swallow guard is gone from flow_cb_cutscene_effect (stray black fade returns on 'A Parting of the Waves' / dlc_dwarf_whaling)"
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
                        local ok_set, err = pcall(BackendUtils.set_loadout_item, backend_id, current_career_name, slot_name)
                        if ok_set then
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
                        local ok_set, err = pcall(BackendUtils.set_loadout_item, backend_id, current_career_name, slot_name)
                        if ok_set then
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
    mod:echo("(Open the hero view to refresh the visual model in the keep.)")
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
local function _register_button_loc()
    local loc = Managers and Managers.localizer
    if loc and loc.append_backend_localizations then
        pcall(loc.append_backend_localizations, loc, { mod_tweaker_button_name = "Mod Tweaker" })
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

_rt_register("mod_tweaker_esc_entry_hook", function()
    local logic_class = rawget(_G, "IngameViewLayoutLogic")
    if not logic_class then return "IngameViewLayoutLogic global not present" end
    if type(logic_class.setup_button_layout) ~= "function" then
        return "IngameViewLayoutLogic.setup_button_layout missing"
    end
    -- Build a fake instance and a layout_data with an Options-shaped entry,
    -- run setup_button_layout, then verify our entry was inserted above it.
    local fake = setmetatable({ _params = {} }, { __index = logic_class })
    local layout = {
        { display_name = "return_to_game_button_name", transition = "exit_menu" },
        { display_name = "options_menu_button_name",   transition = "options_menu" },
        { display_name = "quit_menu_button_name",      transition = "quit_game" },
    }
    local ok = pcall(logic_class.setup_button_layout, fake, layout)
    if not ok then return "setup_button_layout raised on probe layout" end
    local got = fake.active_button_data
    if type(got) ~= "table" then return "active_button_data not populated" end
    local mt_idx, opt_idx = nil, nil
    for i = 1, #got do
        if got[i].transition == "mod_tweaker_view" then mt_idx = i end
        if got[i].transition == "options_menu"     then opt_idx = i end
    end
    if not mt_idx then return "mod_tweaker entry not injected" end
    if not opt_idx then return "options entry vanished (engine change?)" end
    if mt_idx >= opt_idx then return string.format("mod_tweaker entry not above options (mt=%d, opt=%d)", mt_idx, opt_idx) end
end)

_rt_register("mod_tweaker_transition_registered", function()
    local settings = package.loaded["scripts/ui/views/ingame_ui_settings"]
    if not settings then return "ingame_ui_settings not in package.loaded" end
    if not settings.transitions then return "settings.transitions missing" end
    if type(settings.transitions.mod_tweaker_view) ~= "function" then
        return "transitions.mod_tweaker_view is not a function"
    end
    -- Smoke (IN-MISSION fallback, build 2): force is_in_inn=false and supply NO
    -- transition_with_fade so the closure takes the standalone-ModTweakerView branch.
    -- Pre-seed views.mod_tweaker_view so _attach_view short-circuits (idempotent
    -- early-return) without needing a real renderer; the closure must then set
    -- current_view. (The keep branch routes via transition_with_fade -> hero_view
    -- sub-state and is covered by mod_tweaker_substate_registered below.)
    local fake = {
        ingame_ui_context = { is_in_inn = false },
        views = { mod_tweaker_view = { _exit_transition = nil } },
    }
    settings.transitions.mod_tweaker_view(fake)
    if fake.current_view ~= "mod_tweaker_view" then
        return "in-mission transition did not set current_view = mod_tweaker_view"
    end

    -- ORIGIN-CAPTURE (v0.2.58-dev): the in-mission exit must return to whichever
    -- menu the player opened. The closure reads self.current_view (the engine's
    -- pre-closure origin snapshot) and routes "hero_view" origin -> "hero_view",
    -- everything else -> "ingame_menu". Assert both branches so a regression that
    -- re-hardcodes "ingame_menu" (the deprecated-bare-menu bug) is caught.
    local function _exit_for(origin)
        local f = {
            current_view = origin,
            ingame_ui_context = { is_in_inn = false },
            views = { mod_tweaker_view = { _exit_transition = nil } },
        }
        settings.transitions.mod_tweaker_view(f)
        return f.views.mod_tweaker_view._exit_transition
    end
    local et_hero = _exit_for("hero_view")
    if et_hero ~= "hero_view" then
        return string.format("hero_view origin did not set _exit_transition = hero_view (got %s)", tostring(et_hero))
    end
    local et_legacy = _exit_for("ingame_menu")
    if et_legacy ~= "ingame_menu" then
        return string.format("ingame_menu origin did not set _exit_transition = ingame_menu (got %s)", tostring(et_legacy))
    end

    -- KEEP branch (v0.2.60-dev): in the keep (is_in_inn ~= false) the closure must route
    -- to the hero_view sub-state via transition_with_fade WITH force_open = true and
    -- menu_state_name = "gut_mod_tweaker". Dropping force_open is the regression that made
    -- the ESC button darken-then-open-nothing (the keep ESC menu IS hero_view, so without
    -- force_open IngameUI.handle_transition skips the re-enter and menu_state_name is
    -- ignored). Capture the call to assert both params survive.
    if rawget(_G, "HeroViewStateModTweaker") then
        local captured
        local fake_keep = {
            ingame_ui_context = { is_in_inn = true },
            transition_with_fade = function(_self, transition, params)
                captured = { transition = transition, params = params or {} }
            end,
        }
        settings.transitions.mod_tweaker_view(fake_keep)
        if not captured then
            return "keep branch did not call transition_with_fade"
        end
        if captured.transition ~= "hero_view" then
            return string.format("keep branch transition not 'hero_view' (got %s)", tostring(captured.transition))
        end
        if captured.params.menu_state_name ~= "gut_mod_tweaker" then
            return string.format("keep branch menu_state_name not 'gut_mod_tweaker' (got %s)", tostring(captured.params.menu_state_name))
        end
        if captured.params.force_open ~= true then
            return "keep branch missing force_open = true (the darken-then-nothing regression)"
        end
    end
end)

-- Build 2: the Mod Tweaker KEEP sub-state must register exactly like the compendium —
-- the class global exists and the gut_mod_tweaker screen descriptor is appended in the
-- SINGLE HeroView.init hook (no duplicate hook). This marker mirrors the compendium's
-- registration invariant.
_rt_register("mod_tweaker_substate_registered", function()
    if not rawget(_G, "HeroViewStateModTweaker") then
        return "HeroViewStateModTweaker class global not defined (state dofile failed)"
    end
    local C = rawget(_G, "HeroViewStateModTweaker")
    for _, name in ipairs({ "on_enter", "update", "post_update", "on_exit",
                            "input_service", "close_menu" }) do
        if type(C[name]) ~= "function" then
            return string.format("HeroViewStateModTweaker:%s is not a function (got %s)",
                name, type(C[name]))
        end
    end
    if type(mod._gut_open_mod_tweaker) ~= "function" then
        return "mod._gut_open_mod_tweaker opener not defined (inject module didn't load)"
    end
    return nil
end)

_rt_register("mod_tweaker_api_present", function()
    local MT = mod.mod_tweaker
    if not MT then return "mod.mod_tweaker not set; install path failed" end
    for _, name in ipairs({ "register_category", "is_registered", "list_categories",
                            "get_category", "get", "set" }) do
        if type(MT[name]) ~= "function" then
            return string.format("mod.mod_tweaker:%s is not a function (got %s)",
                name, type(MT[name]))
        end
    end
    -- Smoke: register a throwaway category, read back, ensure idempotent rejection.
    local probe_id = "__mt_rt_probe__"
    -- Defensively scrub before registering — _rt_check may have been run already.
    local Settings = mod:dofile("scripts/mods/gui_tweaker_dev/_mod_tweaker_settings")
    if Settings and MT:is_registered(probe_id) then
        -- No public unregister yet; if the probe is still registered from a
        -- prior run, just re-use it (the api is supposed to be idempotent on
        -- this call shape and the smoke is still meaningful).
    else
        local ok = MT:register_category({
            mod_id = probe_id,
            label  = "rt probe",
            widgets = { { setting_id = "probe_flag", type = "checkbox", default = false } },
        })
        if not ok then return "register_category returned false on first call" end
    end
    if not MT:is_registered(probe_id) then return "is_registered() false after register" end
    MT:set(probe_id, "probe_flag", true)
    if MT:get(probe_id, "probe_flag") ~= true then return "get() did not reflect set()" end
end)

-- (#525) Register the engine-free tab-label policy's live check once.
do
    local labels = mod:dofile("scripts/mods/gui_tweaker_dev/_mod_tweaker_tab_labels")
    for _, c in ipairs(labels.rt_checks or {}) do _rt_register(c.name, c.fn) end
end

-- (#559) Search expansion is a transaction, not a write-through rendering shortcut. Exercise the
-- production pure helper in the live Lua 5.1 runtime and assert the view exposes every lifecycle
-- seam that begins, restores, and commits the transaction.
_rt_register("issue559_search_expansion_transaction", function()
    local ok_s, Search = pcall(mod.dofile, mod, "scripts/mods/gui_tweaker_dev/_mod_tweaker_search")
    if not ok_s or type(Search) ~= "table" then return "search transaction module unavailable" end
    for _, name in ipairs({ "begin", "restore", "commit", "finish", "group_keys", "ancestors" }) do
        if type(Search[name]) ~= "function" then return "Search." .. name .. " missing" end
    end

    local expanded = { old_outer = true, old_inner = true, foreign = true }
    local tx = Search.begin(expanded, { "old_outer", "old_inner", "result_outer" }, "probe")
    Search.commit(expanded, tx, { "result_outer" }, true)
    if expanded.old_outer or expanded.old_inner or not expanded.result_outer or not expanded.foreign then
        return "auto-collapse commit did not isolate the result ancestor chain"
    end

    expanded = { old_outer = true, old_inner = true, foreign = true }
    tx = Search.begin(expanded, { "old_outer", "old_inner", "result_outer" }, "probe")
    Search.commit(expanded, tx, { "result_outer" }, false)
    if not expanded.old_outer or not expanded.old_inner or not expanded.result_outer or not expanded.foreign then
        return "non-auto-collapse commit did not preserve snapshot plus result ancestors"
    end

    expanded = { old_outer = true, foreign = true }
    tx = Search.begin(expanded, { "old_outer", "top_outer", "changed_outer" }, "probe")
    Search.finish(expanded, tx, { "changed_outer" }, { "top_outer" }, true)
    if expanded.old_outer or expanded.top_outer or not expanded.changed_outer or not expanded.foreign then
        return "dismissal did not prefer the last changed result branch"
    end

    local ok_v, View = pcall(mod.dofile, mod, "scripts/mods/gui_tweaker_dev/_mod_tweaker_view")
    if not ok_v or type(View) ~= "table" then return "ModTweakerView unavailable" end
    for _, name in ipairs({ "_search_restore", "_search_clear_restore", "_search_finish",
                            "_search_note_setting" }) do
        if type(View[name]) ~= "function" then return "ModTweakerView:" .. name .. " missing" end
    end
end)

_rt_register("issue572_mod_tweaker_native_search_icon", function()
    local ok, defs = pcall(mod.dofile, mod, "scripts/mods/gui_tweaker_dev/_mod_tweaker_definitions")
    if not ok or type(defs) ~= "table" or type(defs.create_search_box) ~= "function" then
        return "Mod Tweaker search definitions unavailable"
    end
    local contract = defs.search_icon_contract
    if type(contract) ~= "table" or contract.texture ~= "search_filters_icon"
        or contract.source ~= "HeroWindowCraftingInventoryConsole"
        or contract.native_size ~= 128 or contract.size ~= 95
        or contract.previous_size ~= 112 or contract.scale_from_previous ~= (95 / 112)
        or contract.scale ~= 0.7421875 or contract.icon_x ~= -28 or contract.icon_y ~= -3
        or contract.native_icon_y ~= -4
        or contract.icon_y ~= math.floor((contract.native_icon_y * contract.size / contract.native_size) + 0.5)
        or contract.visible_left ~= 8 or contract.visible_right ~= 32 then
        return "inventory magnifier material/source contract drifted"
    end
    if type(defs.search_icon_visible) ~= "function"
        or not defs.search_icon_visible({ search_focused = false })
        or defs.search_icon_visible({ search_focused = true }) then
        return "search magnifier focus visibility contract drifted"
    end
    local built, widget = pcall(defs.create_search_box)
    if not built or type(widget) ~= "table" then
        return "search widget build failed: " .. tostring(widget)
    end
    if not widget.content or widget.content.search_icon ~= contract.texture then
        return "search widget does not bind the native inventory texture"
    end
    if widget.content.search_focused ~= false then
        return "search widget does not default to unfocused icon visibility"
    end
    local icon = widget.style and widget.style.search_icon
    local text = widget.style and widget.style.text
    if not icon or not icon.texture_size or icon.texture_size[1] ~= contract.size
        or icon.texture_size[2] ~= contract.size or icon.offset[1] ~= contract.icon_x
        or icon.offset[2] ~= contract.icon_y then
        return "search icon size/padding drifted"
    end
    if not text or not text.offset or text.offset[1] < contract.text_x then
        return "search text can overlap the magnifier"
    end
    local ok_v, View = pcall(mod.dofile, mod, "scripts/mods/gui_tweaker_dev/_mod_tweaker_view")
    if not ok_v or type(View) ~= "table" or type(View._search_placeholder) ~= "function"
        or View._search_placeholder({ _selected = 1, _tabs = { { content = { text = "PROGRESSION" } } } })
            ~= "Search PROGRESSION" then
        return "active-tab search placeholder drifted"
    end
    local hotspot = widget.style and widget.style.hotspot
    if not widget.content.hotspot or not hotspot or not hotspot.size
        or hotspot.size[1] ~= contract.hotspot_w or hotspot.size[2] ~= contract.hotspot_h
        or not hotspot.offset or hotspot.offset[1] ~= 0 or hotspot.offset[2] ~= 0 then
        return "search focus hotspot changed while adding passive icon"
    end
end)

-- (#446) Mutually-exclusive group API + enforcement wiring. Runtime-only (no source
-- read): registers a throwaway 2-member group, verifies the reverse membership lookup
-- resolves both members (and rejects a non-member + malformed shapes), and asserts the
-- view class exposes the _enforce_exclusive method the checkbox toggle handler calls to
-- sweep siblings. A regression that drops the registry surface or unwires enforcement
-- fails here.
_rt_register("mod_tweaker_exclusive_group_api", function()
    local MT = mod.mod_tweaker
    if not MT then return "mod.mod_tweaker not set" end
    for _, name in ipairs({ "register_exclusive_group", "get_exclusive_group_id", "get_exclusive_members" }) do
        if type(MT[name]) ~= "function" then
            return string.format("mod.mod_tweaker:%s is not a function (got %s)", name, type(MT[name]))
        end
    end
    local gid = "__mt_rt_excl__"
    local ok, err = MT:register_exclusive_group(gid, {
        { mod = "__mt_rt_a__", setting = "flag_a" },
        { mod = "__mt_rt_a__", setting = "flag_b" },
    })
    if not ok then return "register_exclusive_group returned false: " .. tostring(err) end
    if MT:get_exclusive_group_id("__mt_rt_a__", "flag_a") ~= gid then return "member flag_a did not resolve to its group" end
    if MT:get_exclusive_group_id("__mt_rt_a__", "flag_b") ~= gid then return "member flag_b did not resolve to its group" end
    if MT:get_exclusive_group_id("__mt_rt_a__", "not_a_member") ~= nil then return "non-member resolved to a group" end
    local members = MT:get_exclusive_members(gid)
    if type(members) ~= "table" or #members ~= 2 then return "get_exclusive_members did not return the 2-member list" end
    -- Reject shapes: empty id, single member.
    if MT:register_exclusive_group("", { { mod = "x", setting = "y" }, { mod = "x", setting = "z" } }) then
        return "empty group_id was not rejected"
    end
    if MT:register_exclusive_group("__mt_rt_solo__", { { mod = "x", setting = "y" } }) then
        return "single-member group was not rejected"
    end
    -- Enforcement is wired: the standalone view class carries the sweep method.
    local ok_v, V = pcall(mod.dofile, mod, "scripts/mods/gui_tweaker_dev/_mod_tweaker_view")
    if not ok_v or type(V) ~= "table" or type(V._enforce_exclusive) ~= "function" then
        return "ModTweakerView:_enforce_exclusive missing (enforcement not wired)"
    end
end)

-- (#505) Filtered/searchable dropdown API + view + defs wiring. Runtime-only (no source read):
-- registers throwaway categories (function form + key-list form), verifies the reverse lookup +
-- rejects malformed shapes, asserts the public API + the view's filter machinery + the defs popup
-- factory's header support are all present. A regression that drops the registry, unwires the
-- filter path, or reverts the header-capable create_dropdown_list fails here.
_rt_register("mod_tweaker_dropdown_filter_api", function()
    local MT = mod.mod_tweaker
    if not MT then return "mod.mod_tweaker not set" end
    for _, name in ipairs({ "register_dropdown_categories", "get_dropdown_categories" }) do
        if type(MT[name]) ~= "function" then
            return string.format("mod.mod_tweaker:%s is not a function (got %s)", name, type(MT[name]))
        end
    end
    local ok, err = MT:register_dropdown_categories("__mt_rt_dd__", "pick", {
        { label = "Even",  match = function(value) return (value % 2) == 0 end },
        { label = "Named", match = { "alpha", "beta" } },   -- key-list form
    })
    if not ok then return "register_dropdown_categories returned false: " .. tostring(err) end
    local cats = MT:get_dropdown_categories("__mt_rt_dd__", "pick")
    if type(cats) ~= "table" or #cats ~= 2 then return "get_dropdown_categories did not return the 2 categories" end
    if type(cats[1].match) ~= "function" or not cats[1].match(4) or cats[1].match(3) then
        return "function-form category match did not normalize correctly"
    end
    if type(cats[2].match) ~= "function" or not cats[2].match("beta") or cats[2].match("gamma") then
        return "key-list category match did not normalize to a membership predicate"
    end
    -- Reject shapes: missing setting_id, empty category list, label-less / matchless entry.
    if MT:register_dropdown_categories("__mt_rt_dd__", "", { { label = "x", match = {} } }) then
        return "empty setting_id was not rejected"
    end
    if MT:register_dropdown_categories("__mt_rt_dd__", "empty", {}) then
        return "empty category list was not rejected"
    end
    if MT:register_dropdown_categories("__mt_rt_dd__", "bad", { { match = function() return true end } }) then
        return "label-less category was not rejected"
    end
    -- View filter machinery is wired.
    local ok_v, V = pcall(mod.dofile, mod, "scripts/mods/gui_tweaker_dev/_mod_tweaker_view")
    if not ok_v or type(V) ~= "table" then return "could not load ModTweakerView" end
    for _, m in ipairs({ "_recompute_dd_visible", "_dd_chips", "_refresh_dropdown_list", "_handle_dropdown_input" }) do
        if type(V[m]) ~= "function" then return "ModTweakerView:" .. m .. " missing (filter path unwired)" end
    end
    -- The defs popup factory must accept a header spec and emit the search-line content id +
    -- chip hotspots. Build a probe popup with 2 chips and assert its shape.
    local ok_d, D = pcall(mod.dofile, mod, "scripts/mods/gui_tweaker_dev/_mod_tweaker_definitions")
    if not ok_d or type(D) ~= "table" or type(D.create_dropdown_list) ~= "function" then
        return "defs.create_dropdown_list missing"
    end
    local header = { query = "ab", chips = { { label = "All", active = true }, { label = "X", active = false } } }
    local ok_w, popup = pcall(D.create_dropdown_list, { "one", "two", "three" }, 1, -100, 1, header)
    if not ok_w or type(popup) ~= "table" then return "create_dropdown_list(header) errored" end
    if popup._dd_chip_count ~= 2 then return "header chips not built (chip_count ~= 2)" end
    if not (popup.content and popup.content.search_text ~= nil) then return "header search_text content missing" end
    if not (popup.content.chip_1 and popup.content.chip_2) then return "chip hotspots missing" end
    -- A plain (no-header) call still works and grows no header band.
    local ok_p, plain = pcall(D.create_dropdown_list, { "one", "two" }, 1, -100, 1)
    if not ok_p or type(plain) ~= "table" then return "create_dropdown_list(no header) errored" end
    if (plain._dd_header_h or 0) ~= 0 or (plain._dd_chip_count or 0) ~= 0 then
        return "plain dropdown grew a header band (backward-compat broken)"
    end
end)

-- v0.2.59-dev — the gear "Advanced Settings" drill-down + the slider thumb-move fix.
-- (1) The defs module must export the gear + back-row factories, and a built gear must
--     carry a hotspot pass WITH an explicit style.hotspot (rows share the mt_list_start
--     node, so a missing style collapses the hit target to 1x1).
-- (2) The slider must drive its thumb/fill via a `local_offset` pass — the ONLY pass
--     type the engine invokes `offset_function` for (ui_passes.lua:4587). A regression
--     that re-attaches offset_function to a texture/rect pass (where it's ignored, the
--     build-3 "thumb doesn't move" bug) would have NO local_offset pass and is caught here.
_rt_register("mod_tweaker_gear_and_slider", function()
    local defs = mod:dofile("scripts/mods/gui_tweaker_dev/_mod_tweaker_definitions")
    if type(defs.create_gear_button) ~= "function" then return "create_gear_button factory missing" end
    if type(defs.create_back_row) ~= "function" then return "create_back_row factory missing" end

    local gear = defs.create_gear_button(-46)
    if type(gear) ~= "table" then return "create_gear_button did not return a widget" end
    local g_has_hotspot, g_styled = false, false
    for _, p in ipairs(gear.element.passes) do
        if p.pass_type == "hotspot" then g_has_hotspot = true; if p.style_id then g_styled = true end end
    end
    if not g_has_hotspot then return "gear widget has no hotspot pass" end
    if not g_styled then return "gear hotspot lacks style_id (hit target would collapse to 1x1)" end
    if not (gear.style and gear.style.hotspot and gear.style.hotspot.size) then
        return "gear hotspot has no explicit style.hotspot.size"
    end

    -- A slider must contain a local_offset pass carrying an offset_function.
    local base = { 0, -10, 0 }
    local slider = defs.create_slider("rt probe", "", base)
    local has_local_offset = false
    for _, p in ipairs(slider.element.passes) do
        if p.pass_type == "local_offset" and type(p.offset_function) == "function" then
            has_local_offset = true
        end
    end
    if not has_local_offset then
        return "slider has no local_offset pass with offset_function (thumb/fill would not move)"
    end
end)

-- #575: caret placement is measured geometry, not character-count or fixed-pixel
-- approximation. Engine-facing defs must expose the exact-metric helpers; the
-- pure module locks centered glyph-origin and proportional-boundary behavior.
_rt_register("mod_tweaker_numeric_caret_geometry", function()
    local defs = mod:dofile("scripts/mods/gui_tweaker_dev/_mod_tweaker_definitions")
    if type(defs.numeric_caret_x) ~= "function" then return "numeric_caret_x missing" end
    if type(defs.numeric_caret_index) ~= "function" then return "numeric_caret_index missing" end
    local N = mod:dofile("scripts/mods/gui_tweaker_dev/_mod_tweaker_numeric_editor")
    if N.caret_x(100, 50, 20, 2, 7) ~= 120 then
        return "centered origin/prefix caret contract drifted"
    end
    local advances = { 0, 5, 12, 19, 22, 29, 36 }
    if N.nearest_index(60.6, 40, advances) ~= 4 then
        return "proportional sign/decimal click boundary drifted"
    end
end)

-- (#164) Mod Tweaker per-setting slider STEP: the resolver's precedence (widget-def `step`
-- field > gut STEP_OVERRIDES registry > natural 1/10^-decimals) and the grid-snap math
-- (anchored at RANGE MIN, clamped to range). The two seeded consumers are ct starting_coins
-- and cim base_power_level, both step 25 via the registry (VMF strips a custom `step` field
-- off a foreign mod's widget, so the registry is the working path — see _resolve_step /
-- STEP_OVERRIDES comments). Guards against a regression that reverts the registry keys to
-- directory names (which silently never match) or drops the min-anchoring.
_rt_register("mod_tweaker_arrow_edge_latch_hold_repeat", function()
    -- (#152) Mod Tweaker slider arrows: a single click = ONE natural increment, EDGE-LATCHED
    -- (one step per physical press, no auto-move on press), and a HELD arrow repeats after a
    -- delay and ACCELERATES - matching the vanilla options slider. Guard the accelerating
    -- hold-repeat by source-pattern on _mod_tweaker_view.lua (path via View._resolve_step).
    -- Split needle so this line can't self-match. No-op if the source is unreadable.
    local ok_view, View = pcall(mod.dofile, mod, "scripts/mods/gui_tweaker_dev/_mod_tweaker_view")
    if not ok_view or type(View) ~= "table" or type(View._resolve_step) ~= "function" then return end
    local ok, info = pcall(debug.getinfo, View._resolve_step, "S")
    if not ok or type(info) ~= "table" or not info.source then return end
    local src_path = info.source:sub(1, 1) == "@" and info.source:sub(2) or info.source
    local txt = _rt_src_read(src_path)  -- (#511) io-safe; nil in retail sandbox => skip
    if not txt then return end
    local hold_needle = "row._arrow_hnext = row._arrow" .. "_hf + math.max(2,"
    if not txt:find(hold_needle, 1, true) then
        return "#152 REGRESSION: the accelerating arrow hold-repeat is gone (Mod Tweaker slider arrows over-adjust / auto-move on press again)"
    end
end)

_rt_register("mod_tweaker_step_resolution", function()
    local ok_view, View = pcall(mod.dofile, mod, "scripts/mods/gui_tweaker_dev/_mod_tweaker_view")
    if not ok_view or type(View) ~= "table" then return "view module unavailable" end
    local resolve, snap = View._resolve_step, View._snap_and_clamp
    if type(resolve) ~= "function" then return "_resolve_step not exposed on the view module" end
    if type(snap) ~= "function" then return "_snap_and_clamp not exposed on the view module" end

    -- (1) Precedence: an explicit widget-def `step` field wins over the registry.
    if resolve({ step = 10 }, "ct_dev", "starting_coins", 0) ~= 10 then
        return "widget-def `step` field did not take precedence over the registry"
    end
    -- (2) Registry hit for BOTH seeded consumers, on stable AND dev ids (by new_mod id).
    for _, case in ipairs({ { "ct", "starting_coins" }, { "ct_dev", "starting_coins" },
                            { "cim", "base_power_level" }, { "cim_dev", "base_power_level" } }) do
        local got = resolve({}, case[1], case[2], 0)
        if got ~= 25 then
            return string.format("registry %s:%s resolved step=%s (want 25) -- key regressed to a directory name?",
                case[1], case[2], tostring(got))
        end
    end
    -- (3) Default: no field, no registry -> natural unit (1 for ints, 10^-decimals otherwise).
    if resolve({}, "some_other_mod", "some_setting", 0) ~= 1 then return "int default step is not 1" end
    if math.abs(resolve({}, "some_other_mod", "x", 2) - 0.01) > 1e-9 then return "2-decimal default step is not 0.01" end

    -- (4) Snap is anchored at RANGE MIN (not 0) and clamps to range. min=10,step=25: 20 rounds
    -- toward 10 (|20-10|/25 < 0.5), NOT to 25 (which is what a 0-anchored snap would give).
    if snap({ min = 10, max = 200, step = 25, num_decimals = 0 }, 20) ~= 10 then
        return "snap not anchored at range min (min=10,step=25,value=20 should snap to 10)"
    end
    -- 324 with min=0,step=25 -> nearest grid multiple 325 (this is the "then snap" on move;
    -- the pre-existing 324 shows as-is at build time, only snapping once the user moves it).
    if snap({ min = 0, max = 3000, step = 25, num_decimals = 0 }, 324) ~= 325 then
        return "snap(324) with step 25 did not land on 325"
    end
    -- Clamp to range.
    if snap({ min = 0, max = 100, step = 25, num_decimals = 0 }, 999) ~= 100 then
        return "snap did not clamp to range max"
    end
end)

-- (#95) Keybind / table read-only values must route through _format_keybind_value
-- in _mod_tweaker_view.lua, NOT tostring(), or a VMF keybind (a Lua TABLE like
-- {"left alt"}) renders its raw address ("CYCLE HUD MODE: table: 0x..."). Source
-- guard: read the VIEW file (anchored via debug.getinfo on a ModTweakerView method)
-- and assert BOTH (a) the formatter helper is present and (b) the read-only branch
-- routes keybind/table values through it. Needles are split across two literals so
-- this test's own source can't self-match. Degrades to a no-op when source
-- introspection is unavailable (deploy/bundle paths ship no readable .lua).
_rt_register("mod_tweaker_keybind_render", function()
    local ok_view, View = pcall(mod.dofile, mod, "scripts/mods/gui_tweaker_dev/_mod_tweaker_view")
    if not ok_view or type(View) ~= "table" or type(View._handle_input) ~= "function" then
        return  -- can't reach the view module; skip
    end
    local ok, info = pcall(debug.getinfo, View._handle_input, "S")
    if not ok or type(info) ~= "table" or not info.source then return end
    local src_path = info.source:sub(1, 1) == "@" and info.source:sub(2) or info.source
    local txt = _rt_src_read(src_path)  -- (#511) io-safe; nil in retail sandbox => skip
    if not txt then return end
    -- (a) the formatter helper must exist.
    local helper_needle = "_format_keybind" .. "_value"
    if not txt:find(helper_needle, 1, true) then
        return "#95 regression: _format_keybind_value is absent from _mod_tweaker_view.lua (keybinds would render a raw table address)"
    end
    -- (b) the read-only branch must route wtype=="keybind" OR a table value through it.
    local branch_needle = 'wtype == "keybind" or type(val)' .. ' == "table"'
    if not txt:find(branch_needle, 1, true) then
        return "#95 regression: read-only row no longer routes keybind/table values through _format_keybind_value (raw 'table: 0x...' would reach the label)"
    end
    local routed_needle = ': " .. _format_keybind' .. "_value(val)"
    if not txt:find(routed_needle, 1, true) then
        return "#95 regression: the keybind/table branch does not call _format_keybind_value(val)"
    end
end)

-- (#91) Scrollbar thumb drag must use a GRAB-OFFSET anchor (the cursor-Y at grab +
-- the scroll_value at grab), then track the cursor DELTA over the thumb's travel —
-- NOT the old absolute-position snap that jumped the thumb top to the cursor.
-- Source guard on _mod_tweaker_view.lua's _handle_input: assert both grab-anchor
-- fields survive. Split needles to avoid self-match; no-op when source unreadable.
_rt_register("mod_tweaker_scrollbar_grab_offset", function()
    local ok_view, View = pcall(mod.dofile, mod, "scripts/mods/gui_tweaker_dev/_mod_tweaker_view")
    if not ok_view or type(View) ~= "table" or type(View._handle_input) ~= "function" then
        return
    end
    local ok, info = pcall(debug.getinfo, View._handle_input, "S")
    if not ok or type(info) ~= "table" or not info.source then return end
    local src_path = info.source:sub(1, 1) == "@" and info.source:sub(2) or info.source
    local txt = _rt_src_read(src_path)  -- (#511) io-safe; nil in retail sandbox => skip
    if not txt then return end
    local cursor_anchor = "_sb_grab_cursor" .. "_y"
    local scroll_anchor = "_sb_grab_scroll" .. "_value"
    if not txt:find(cursor_anchor, 1, true) or not txt:find(scroll_anchor, 1, true) then
        return "#91 regression: scrollbar thumb drag no longer records a grab-offset anchor (reverted to absolute-position snapping — grabbing the thumb jumps it)"
    end
end)

-- (#92 corrected) The stepper/slider arrow glow must match the VANILLA GAME SETTINGS
-- menu (create_stepper_widget, options_view_definitions.lua:3054), NOT VMF. Native draws
-- TWO sprites per arrow: a base `settings_arrow_normal` at FULL alpha (font_default,255 —
-- :3415/:3457) that is NEVER dimmed at idle, plus a separate `settings_arrow_clicked`
-- OVERLAY seeded color {0,255,255,255} = alpha 0 (:3428-3433/:3470-3475) that fades up to
-- 255 on hover (OptionsView.on_stepper_arrow_hover, options_view.lua:4335-4369). The glow
-- is the _clicked overlay APPEARING, not an alpha ramp on the base. Table-introspection of
-- a built slider (which calls _append_arrows) asserts: (a) the base arrows draw
-- settings_arrow_normal at FULL alpha 255 (NOT dim); (b) the _clicked hover OVERLAYS exist
-- drawing settings_arrow_clicked seeded at alpha 0; (c) a local_offset pass with an
-- offset_function drives the overlay alpha 0->255.
_rt_register("mod_tweaker_arrow_hover_glow", function()
    local defs = mod:dofile("scripts/mods/gui_tweaker_dev/_mod_tweaker_definitions")
    if type(defs.create_slider) ~= "function" then return "create_slider factory missing" end
    local base = { 0, -10, 0 }
    local slider = defs.create_slider("rt probe", "", base)
    if type(slider) ~= "table" or not (slider.element and slider.element.passes) then
        return "create_slider did not return a renderable widget"
    end
    -- (a) base arrows draw settings_arrow_normal at FULL alpha (idle must NOT be dimmed —
    -- native :3415/:3457 are font_default,255).
    local la = slider.content and slider.content.left_arrow
    if not (la and la.texture_id == "settings_arrow_normal") then
        return "#92 regression: base left arrow no longer draws settings_arrow_normal"
    end
    local las = slider.style and slider.style.left_arrow
    if not (las and las.color and las.color[1] == 255) then
        return "#92 regression: base arrow not at FULL idle alpha 255 (vanilla draws the idle sprite full; a dimmed idle is the wrong-menu VMF ramp)"
    end
    -- (b) the _clicked hover OVERLAYS must exist, drawing settings_arrow_clicked seeded at
    -- alpha 0 (native left_arrow_hover/right_arrow_hover color {0,...}).
    local lah = slider.content and slider.content.left_arrow_hover
    if not (lah and lah.texture_id == "settings_arrow_clicked") then
        return "#92 regression: missing _clicked hover overlay (vanilla glow = settings_arrow_clicked overlay fading in over the base)"
    end
    local lahs = slider.style and slider.style.left_arrow_hover
    if not (lahs and lahs.color and lahs.color[1] == 0) then
        return "#92 regression: _clicked hover overlay not seeded at alpha 0 (native seed {0,255,255,255}; it ramps to 255 on hover)"
    end
    -- (c) a local_offset pass with an offset_function must drive the overlay alpha ramp
    -- (only a local_offset pass's offset_function runs each frame).
    local has_local_offset = false
    for _, p in ipairs(slider.element.passes) do
        if p.pass_type == "local_offset" and type(p.offset_function) == "function" then
            has_local_offset = true
        end
    end
    if not has_local_offset then
        return "#92 regression: no local_offset pass with an offset_function — the _clicked overlay alpha ramp cannot run"
    end
end)

-- (#92 corrected) The COLLAPSED dropdown arrow must match the VANILLA GAME SETTINGS
-- dropdown (create_drop_down_widget, options_view_definitions.lua:2299): a visible arrow
-- in BOTH states (down sprite when closed, up-flip when open — it never disappears), with
-- the brighter drop_down_menu_arrow_clicked glow sprite layering on hover/open. Asserts:
-- (a) base arrow_down + arrow_up passes both exist and are gated on content.active so one
-- is ALWAYS drawn; (b) an arrow_glow pass draws drop_down_menu_arrow_clicked; (c) the base
-- arrows are at FULL alpha (never gated to a blank/dimmed open state).
_rt_register("mod_tweaker_dropdown_arrow_glow", function()
    local defs = mod:dofile("scripts/mods/gui_tweaker_dev/_mod_tweaker_definitions")
    if type(defs.create_dropdown) ~= "function" then return "create_dropdown factory missing" end
    local dd = defs.create_dropdown("rt probe dd", { 0, -10, 0 }, 0)
    if type(dd) ~= "table" or not (dd.element and dd.element.passes) then
        return "create_dropdown did not return a renderable widget"
    end
    -- (a) both base arrows present; one drawn when closed, one when open -> never blank.
    local has_down, has_up, has_glow = false, false, false
    local down_check, up_check = nil, nil
    for _, p in ipairs(dd.element.passes) do
        if p.style_id == "arrow_down" then has_down = true; down_check = p.content_check_function end
        if p.style_id == "arrow_up"   then has_up   = true; up_check   = p.content_check_function end
        if p.style_id == "arrow_glow" then has_glow = true end
    end
    if not (has_down and has_up) then
        return "#92 regression: dropdown missing a base down/up arrow pass (the arrow must stay visible when open — never gate the only arrow off active)"
    end
    -- The closed pass shows when NOT active, the open pass shows when active -> exactly one
    -- base arrow is always drawn, so opening can never blank the arrow.
    if not (down_check and up_check and down_check({ active = false }) and up_check({ active = true })
            and not down_check({ active = true }) and not up_check({ active = false })) then
        return "#92 regression: dropdown arrow gating wrong (closed must draw the down arrow, open the up arrow — the open state must not be blank)"
    end
    -- (b) the _clicked glow sprite overlay exists (drop_down_menu_arrow_clicked).
    local glowc = dd.content and dd.content.arrow_glow
    if not (has_glow and glowc and glowc.texture_id == "drop_down_menu_arrow_clicked") then
        return "#92 regression: dropdown missing the drop_down_menu_arrow_clicked glow overlay (native hover/open glow sprite)"
    end
    -- (c) base arrows at FULL alpha in both states (native style.arrow color = font_default,255).
    local ad, au = dd.style and dd.style.arrow_down, dd.style and dd.style.arrow_up
    if not (ad and ad.color and ad.color[1] == 255 and au and au.color and au.color[1] == 255) then
        return "#92 regression: dropdown base arrows not at FULL alpha (native arrow is font_default,255 closed AND open; a dim/0 open arrow is the disappearing-arrow defect)"
    end
end)

-- (#93) Compact-ESC menu compaction is now an UNCONDITIONAL implicit feature — the
-- gut_compact_esc_menu TOGGLE + setting were removed (2026-06-24) and the
-- HeroWindowIngameView._update_presentation hook always runs (no-op below the
-- overflow threshold). This guard FAILS if a real setting-READ for that toggle is
-- reintroduced (gating the feature again). It checks the setting-read shape, not the
-- bare string, so the explanatory comment naming the removed toggle does not trip it.
-- Anchored on mod.on_setting_changed (a `mod.` field in the MAIN file). Split needle;
-- no-op when source unreadable.
_rt_register("mod_tweaker_compact_esc_implicit", function()
    local ok, info = pcall(debug.getinfo, mod.on_setting_changed or function() end, "S")
    if not ok or type(info) ~= "table" or not info.source then return end
    local src_path = info.source:sub(1, 1) == "@" and info.source:sub(2) or info.source
    local txt = _rt_src_read(src_path)  -- (#511) io-safe; nil in retail sandbox => skip
    if not txt then return end
    -- A reintroduced gate would read the setting via mod:get(...) on that toggle id.
    -- (The read-shape needle is assembled below from two literals so this very line
    -- and the comment naming the removed toggle can't make the test self-match.)
    local read_needle = 'mod:get("gut_compact_esc' .. '_menu")'
    if txt:find(read_needle, 1, true) then
        return "#93 regression: the gut_compact_esc_menu setting/toggle was reintroduced (the ESC-menu compaction must run unconditionally now)"
    end
end)

-- Bench-in-mission option moved from cim (2026-07-02, user direction): gut owns the
-- widget (cim-gated in _data.lua) and must write through to cim's `allow_in_mission`
-- setting, both on change and at load. Source-pattern guard on both halves; no-op
-- when source unreadable. Split needles so this check never self-matches.
_rt_register("cim_bench_write_through_present", function()
    local ok, info = pcall(debug.getinfo, mod.on_setting_changed or function() end, "S")
    if not ok or type(info) ~= "table" or not info.source then return end
    local src_path = info.source:sub(1, 1) == "@" and info.source:sub(2) or info.source
    local read_all = _rt_src_read  -- (#511) io-safe; nil in retail sandbox => skip
    local main_txt = read_all(src_path)
    if main_txt then
        local wt_needle = 'cim:set("allow_in_' .. 'mission"'
        local n_hits = select(2, main_txt:gsub(wt_needle:gsub("%p", "%%%0"), ""))
        if n_hits < 2 then
            return "cim-bench regression: expected the allow_in_mission write-through in BOTH on_setting_changed and on_all_mods_loaded (found " .. tostring(n_hits) .. ")"
        end
    end
    local dir = src_path:match("^(.*[/\\])[^/\\]*$")
    if dir then
        local data_txt = read_all(dir .. "gui_tweaker_dev_data.lua")
        if data_txt and not data_txt:find('setting_id    = "gut_cim_bench' .. '_in_mission"', 1, true) then
            return "cim-bench regression: gut_cim_bench_in_mission widget missing from gut's In-Mission Menus"
        end
    end
end)

-- (#80) The in-mission Crafting TAB must be gated on gut's OWN
-- gut_cim_bench_in_mission toggle + cim presence (not a bare cim-presence check),
-- and tb[3].disable_button must be driven by that result BOTH ways. Source-pattern
-- guard on _gut_mission_inventory.lua (located via mod.gut_open_mission_inventory,
-- defined there). Split needles so this check can't self-match. No-op if unreadable.
_rt_register("crafting_tab_honors_bench_toggle", function()
    local ok, info = pcall(debug.getinfo, mod.gut_open_mission_inventory or function() end, "S")
    if not ok or type(info) ~= "table" or not info.source then return end
    local src_path = info.source:sub(1, 1) == "@" and info.source:sub(2) or info.source
    local txt = _rt_src_read(src_path)  -- (#511) io-safe; nil in retail sandbox => skip
    if not txt then return end
    local gate_needle = 'mod:get("gut_cim_bench' .. '_in_mission")'
    local tab_needle  = "tb[3].content.button_hotspot.disable" .. "_button = not bench_ok"
    if not txt:find(gate_needle, 1, true) then
        return "#80 regression: the in-mission Crafting tab no longer reads gut_cim_bench_in_mission (bench toggle stopped gating the tab)"
    end
    if not txt:find(tab_needle, 1, true) then
        return "#80 regression: the Crafting tab (tb[3]) disable_button is no longer driven by bench_ok"
    end
end)

-- (#363/#80) In-mission Salvage/Crafting page store-atlas injection. The vanilla
-- Salvage craft page draws its auto-fill rarity buttons (store_tag_icon_weapon_*) out
-- of gui_store_menu_atlas, which lives in materials/ui/ui_1080p_store_menu -- a
-- keep-only (ui_materials_in_inn) resource, so in a mission the ingame renderer lacks it
-- and the draw takes an uncatchable "Material not found in Gui" C-fatal
-- (ui_passes.lua:194). The store package IS resident in-mission (dlcs/store force-loaded
-- at boot), so _gut_gui_material_guard.lua injects it into ingame ui/ui_top renderers
-- when can_get confirms residency (mirrors the pose-atlas #155 injection). This guard
-- FAILS if any of the three load-bearing pieces (STORE_MAT declaration, the append_store
-- residency gate, the token append into the Gui material list) is removed -- the Salvage
-- page would crash in-mission again. The guard file has no addressable mod.* function
-- (it's an anonymous UIRenderer.create hook + `return {}`), so locate it as a sibling of
-- _gut_mission_inventory.lua (via mod.gut_open_mission_inventory) in the same dir. Split
-- needles so this check can't self-match. No-op when source unreadable.
_rt_register("salvage_store_atlas_injected", function()
    local ok, info = pcall(debug.getinfo, mod.gut_open_mission_inventory or function() end, "S")
    if not ok or type(info) ~= "table" or not info.source then return end
    local src_path = info.source:sub(1, 1) == "@" and info.source:sub(2) or info.source
    local dir = src_path:match("^(.*[/\\])[^/\\]*$")
    if not dir then return end
    local txt = _rt_src_read(dir .. "_gut_gui_material_guard.lua")  -- (#511) io-safe; nil in retail => skip
    if not txt then return end
    local decl_needle   = "STORE" .. '_MAT = "materials/ui/ui_1080p_store_menu"'
    local gate_needle   = "if append" .. "_store then"
    local append_needle = "out[oi] = STORE" .. "_MAT"
    if not txt:find(decl_needle, 1, true) then
        return "#363 regression: the store-atlas material path (materials/ui/ui_1080p_store_menu) is gone from the GUI guard"
    end
    if not txt:find(gate_needle, 1, true) then
        return "#363 regression: the append_store residency gate is gone -- store atlas no longer injected into ingame renderers (Salvage page would C-fatal in-mission)"
    end
    if not txt:find(append_needle, 1, true) then
        return "#363 regression: the store-atlas token is no longer appended to the ingame Gui material list (Salvage-page tag icons can't draw in-mission)"
    end
end)

-- (2026-07-02) The Compendium (Armory + Bestiary) must open + work mid-mission with
-- NO keep gate: the is_in_inn keep-block is gone from mod._gut_open_compendium, and
-- the tab-state pass no longer greys the compendium tabs out of the keep. Source-
-- pattern guard on _ba_heroview_inject.lua (via mod._gut_open_compendium) + its
-- sibling _ba_compendium_tabs.lua. Split needles so this check can't self-match.
_rt_register("compendium_mission_access_ungated", function()
    local ok, info = pcall(debug.getinfo, mod._gut_open_compendium or function() end, "S")
    if not ok or type(info) ~= "table" or not info.source then return end
    local inject_path = info.source:sub(1, 1) == "@" and info.source:sub(2) or info.source
    local read_all = _rt_src_read  -- (#511) io-safe; nil in retail sandbox => skip
    local inject_txt = read_all(inject_path)
    if inject_txt then
        -- The compendium-specific keep echo is gone (the Mod Tweaker path keeps its
        -- own distinct message, so this needle is specific to the compendium).
        local keepgate_needle = "The Compendium only opens in the " .. "keep/inn."
        if inject_txt:find(keepgate_needle, 1, true) then
            return "compendium regression: the is_in_inn keep-gate was reintroduced in _gut_open_compendium (mid-mission open blocked again)"
        end
    end
    local tabs_path = inject_path:gsub("_ba_heroview_inject%.lua$", "_ba_compendium_tabs.lua")
    if tabs_path ~= inject_path then
        local tabs_txt = read_all(tabs_path)
        if tabs_txt then
            local grey_needle = "disable_button = not in" .. "_keep"
            if tabs_txt:find(grey_needle, 1, true) then
                return "compendium regression: _apply_tab_state greys the compendium tabs out of the keep again (mid-mission tabs disabled)"
            end
        end
    end
end)

-- (#155/#172) In-mission Cosmetics split: the TAB is vanilla UI (enabled unconditionally,
-- pose items filtered when the atlas isn't resident so no gui_pose_items_atlas C-fatal), the
-- gear-icon customize is gated on cosmetics_tweaker specifically. Source-pattern guard on
-- _gut_mission_inventory.lua (via mod.gut_open_mission_inventory). Split needles so this check
-- can't self-match. No-op if unreadable.
_rt_register("cosmetics_split_tab_ungated_gear_gated", function()
    local ok, info = pcall(debug.getinfo, mod.gut_open_mission_inventory or function() end, "S")
    if not ok or type(info) ~= "table" or not info.source then return end
    local src_path = info.source:sub(1, 1) == "@" and info.source:sub(2) or info.source
    local txt = _rt_src_read(src_path)  -- (#511) io-safe; nil in retail sandbox => skip
    if not txt then return end
    -- (a) Cosmetics tab (tb[4]) enabled unconditionally mid-mission.
    local tab_needle = "tb[4].content.button_hotspot.disable" .. "_button = false"
    if not txt:find(tab_needle, 1, true) then
        return "#172 regression: the in-mission Cosmetics tab (tb[4]) is no longer enabled unconditionally"
    end
    -- (a) Pose items filtered from the grid when the atlas isn't resident.
    local filter_needle = "slot.type == _POSE" .. "_SLOT_TYPE"
    if not txt:find(filter_needle, 1, true) then
        return "#155 regression: the pose-item grid filter (_equip_item_presentation) is gone -- gui_pose_items_atlas C-fatal could return"
    end
    -- (b) Gear-icon customize gated on cosmetics_tweaker specifically (NOT cim).
    local gate_needle = 'return in_keep or (get_mod("cosmetics' .. '_tweaker") ~= nil)'
    if not txt:find(gate_needle, 1, true) then
        return "#172 regression: the gear-icon customize gate is no longer keyed on cosmetics_tweaker specifically"
    end
end)

_rt_register("issue89_cosmetics_only_customize_mount", function()
    -- #89's original implementation plan said Cosmetics had to copy CIM's two
    -- mount hooks before GUT could permit the gear icon. #84 superseded that
    -- architecture: GUT owns the only mid-mission entry and now owns the two
    -- level-free mount hooks itself, while Cosmetics owns the render/apply path.
    -- Assert the live cross-mod contract directly; no retail source I/O.
    if type(mod._gut89_customize_allowed) ~= "function" then
        return "#89 customize policy missing"
    end
    if type(mod._gut89_mount_fix_active) ~= "function" then
        return "#89 mount policy missing"
    end
    local surfaces = mod._gut89_mount_surfaces
    if type(surfaces) ~= "table"
        or surfaces.create_item_preview_widget_definition ~= true
        or surfaces.register_object_sets ~= true
    then
        return "#89 level-free mount sender surfaces incomplete"
    end

    local in_keep = rawget(_G, "DamageUtils") and DamageUtils.is_in_inn or false
    if not in_keep then
        local has_cosmetics = get_mod("cosmetics_tweaker") ~= nil
        if has_cosmetics and mod._gut89_customize_allowed() ~= true then
            return "#89 Cosmetics present but in-mission gear icon remains blocked"
        end
        local has_cim = get_mod("cim_dev") ~= nil or get_mod("cim") ~= nil
        if not has_cim and mod._gut89_mount_fix_active() ~= true then
            return "#89 no-CIM mission path did not activate GUT's level-free mount"
        end
    end
end)

-- hb/ SETTING_NAMES-nil crash (2026-06-24): the BOOT loading screen fires the
-- hb/level_loading_screen.lua LoadingView.create_ui_elements hook before
-- hb_data.lua has populated mod.SETTING_NAMES, so reading
-- mod.SETTING_NAMES.HIDE_LOADING_SCREEN_SUBTITLES indexed a nil value and crashed
-- ("attempt to index field 'SETTING_NAMES' (a nil value)"). The hook now bails with
-- `if not mod.hb_fork_active() then return func(...) end` (#281) -- hb_fork_active()
-- returns false whenever mod.SETTING_NAMES is nil, so it STILL protects the boot
-- crash while also making the fork dormant when stock UI Tweaks owns. This check
-- FAILS if that guard is removed (the crash would return). Source path is derived
-- from a sibling hb/ function (mod.reapply_pickup_ranges, defined in
-- hide_elements.lua) by swapping the filename, since the level_loading_screen
-- hooks are anonymous closures with no addressable reference. Needles are split
-- so this comment/line can't self-match. No-op when source unreadable.
_rt_register("hb_setting_names_guarded", function()
    local ok, info = pcall(debug.getinfo, mod.reapply_pickup_ranges or function() end, "S")
    if not ok or type(info) ~= "table" or not info.source then return end
    local sibling = info.source:sub(1, 1) == "@" and info.source:sub(2) or info.source
    -- hide_elements.lua and level_loading_screen.lua are siblings in hb/.
    local src_path = sibling:gsub("hide_elements%.lua$", "level_loading_screen.lua")
    if src_path == sibling then return end  -- couldn't derive the sibling path; skip
    local txt = _rt_src_read(src_path)  -- (#511) io-safe; nil in retail sandbox => skip
    if not txt then return end
    local guard_needle = "if not mod.hb_fork" .. "_active() then"
    local read_needle = "mod.SETTING_NAMES.HIDE_LOADING_SCREEN" .. "_SUBTITLES"
    local guard_at = txt:find(guard_needle, 1, true)
    local read_at = txt:find(read_needle, 1, true)
    if not read_at then return end  -- hook restructured; the specific read is gone
    if not guard_at or guard_at >= read_at then
        return "hb regression: the LoadingView.create_ui_elements hook in hb/level_loading_screen.lua no longer gates on mod.hb_fork_active() before reading HIDE_LOADING_SCREEN_SUBTITLES (boot loading screen would crash 'index field SETTING_NAMES (a nil value)')"
    end
end)

-- (#281) Absorbed UI Tweaks (HideBuffs) fork boots WITHOUT Penlight. The fork's data
-- file (hb/hb_data.lua) used to `require` a Penlight module that does not exist as a
-- lua resource in the retail sandbox, so it aborted at load -- mod.SETTING_NAMES and
-- the fork's data tables went undefined and every hide/loading-screen feature went
-- silently dead. hb_data.lua now uses a plain-Lua shim (marker hb_pl_shim). RUNTIME
-- proof (authoritative in retail): the data backbone loaded and the shim-built tables
-- exist and behave. SOURCE proof (io-safe, skipped in retail; runs under CI/tools):
-- no Penlight require/usage remains and the shim marker is present. Anchor
-- mod.hb_fork_active resolves hb_data.lua's path (it defines no other function).
-- Needles split so this check can't self-match.
_rt_register("hb_penlight_removed", function()
    if type(mod.SETTING_NAMES) ~= "table" then
        return "hb regression: mod.SETTING_NAMES is not a table (hb_data.lua aborted at load -- Penlight require back?)"
    end
    if mod.SETTING_NAMES.HIDE_LOADING_SCREEN_SUBTITLES == nil or mod.SETTING_NAMES.HIDE_BOSS_HP_BAR == nil then
        return "hb regression: SETTING_NAMES is missing fork keys (hb_data.lua did not run to completion)"
    end
    -- List replacement: ubersreik_lvls is consumed as a :contains list at hide_elements.lua:251.
    local lvls = mod.ubersreik_lvls
    if type(lvls) ~= "table" or type(lvls.contains) ~= "function" then
        return "hb regression: mod.ubersreik_lvls lost its :contains method (List shim broken)"
    end
    if lvls:contains("magnus") ~= true or lvls:contains("__nope__") ~= false then
        return "hb regression: ubersreik_lvls:contains returned wrong results (List shim broken)"
    end
    -- Map replacement: career_name_to_hat_icon is a plain key->value lookup table.
    if type(mod.career_name_to_hat_icon) ~= "table" or mod.career_name_to_hat_icon.es_knight == nil then
        return "hb regression: mod.career_name_to_hat_icon missing (Map shim broken)"
    end
    local ok, info = pcall(debug.getinfo, mod.hb_fork_active or function() end, "S")
    if not ok or type(info) ~= "table" or not info.source then return end
    local src = info.source:sub(1, 1) == "@" and info.source:sub(2) or info.source
    local txt = _rt_src_read(src)  -- (#511) io-safe; nil in retail sandbox => skip
    if not txt then return end
    if txt:find("import" .. "_into", 1, true)
        or txt:find("pl." .. "List", 1, true)
        or txt:find("pl." .. "Map", 1, true) then
        return "hb regression: a Penlight reference is back in hb_data.lua (retail sandbox has no pl.* resource -> load abort)"
    end
    if not txt:find("hb_pl" .. "_shim", 1, true) then
        return "hb regression: the hb_pl_shim marker is gone from hb_data.lua (Penlight replacement removed)"
    end
end)

-- (#281) Absorbed-fork dormancy gate. With the Penlight abort fixed the fork now
-- BOOTS, so it must defer to the stock "UI Tweaks" (HideBuffs) mod when that is
-- installed + enabled (the #312 bridge owns the overlapping settings) -- otherwise
-- the same hides fire twice (and NUM_SUBTITLE_ROWS / OutlineSettings.ranges fight).
-- Previously the fork "self-gated" only by crashing; the explicit gate replaces that.
-- RUNTIME proof: the gate helpers exist and return booleans. SOURCE proof (io-safe):
-- the hide-elements hooks gate on mod.hb_fork_active() (anchor is the sibling
-- mod.reapply_pickup_ranges). Needles split so this check can't self-match.
_rt_register("hb_fork_dormancy_gate", function()
    if type(mod.hb_fork_active) ~= "function" then
        return "hb regression: mod.hb_fork_active dormancy gate missing (fork can't defer to stock UI Tweaks)"
    end
    if type(mod.hb_stock_owns) ~= "function" then
        return "hb regression: mod.hb_stock_owns missing (dormancy gate can't detect stock UI Tweaks)"
    end
    if type(mod.hb_fork_active()) ~= "boolean" or type(mod.hb_stock_owns()) ~= "boolean" then
        return "hb regression: dormancy gate did not return a boolean"
    end
    local ok, info = pcall(debug.getinfo, mod.reapply_pickup_ranges or function() end, "S")
    if not ok or type(info) ~= "table" or not info.source then return end
    local src = info.source:sub(1, 1) == "@" and info.source:sub(2) or info.source
    local txt = _rt_src_read(src)  -- (#511) io-safe; nil in retail sandbox => skip
    if not txt then return end
    if not txt:find("hb_fork" .. "_active()", 1, true) then
        return "hb regression: hide_elements.lua no longer gates on mod.hb_fork_active() (fork double-applies when stock UI Tweaks is enabled)"
    end
end)

-- UI Tweaks "Temporal Fix" (absorbed): re-aligns stock UI Tweaks (HideBuffs)
-- player HP-bar placement broken by the Versus update. Applied at
-- on_all_mods_loaded (HideBuffs must be loaded first); also tried now in case
-- HideBuffs loaded before us. No-op if UI Tweaks isn't installed. See
-- _gut_uitweaks_temporal_fix.lua for the verified diff + mechanism.
local _gut_temporal_fix = mod:dofile("scripts/mods/gui_tweaker_dev/_gut_uitweaks_temporal_fix")
-- UI Tweaks HUD-customizer write-through (#312): when UI Tweaks (HideBuffs) is
-- installed + enabled and gut_uitweaks_sync is on, UI Tweaks OWNS the buff bar,
-- boss HP bar, overcharge bar, and energy bar -- gut's drag editor writes UI
-- Tweaks' offsets instead of its own, so the two never stack. Adds NO game hooks;
-- migrate() re-attempted at on_all_mods_loaded (HideBuffs may load after us). No-op
-- when UI Tweaks is absent. See _gut_uitweaks_sync.lua for the element map + the
-- per-element coordinate-space verification.
local _gut_uitweaks_sync = mod:dofile("scripts/mods/gui_tweaker_dev/_gut_uitweaks_sync")
if _gut_uitweaks_sync and _gut_uitweaks_sync.install then pcall(_gut_uitweaks_sync.install) end

-- (#312) UI Tweaks integration regression tests. Split needles so the source-pattern
-- checks can never self-match; unreadable source => silent skip (pass).
local _gut_read_all = _rt_src_read  -- (#511) io-safe; nil in retail sandbox => skip

_rt_register("issue318_disabled_integrations_keep_normal_sections", function()
    local ok_p, Policy = pcall(mod.dofile, mod,
        "scripts/mods/gui_tweaker_dev/_mod_tweaker_disabled_sections")
    if not ok_p or type(Policy) ~= "table" then
        return "#318 disabled-section policy unavailable"
    end
    local roles = { wt = "weapons", character_weapon_variants = "cwv" }
    local members, count = Policy.select_members({
        { mod_id = "wt", enabled = true },
        { mod_id = "character_weapon_variants", enabled = false },
    }, roles)
    if count ~= 2 or not members.cwv or members.cwv.enabled ~= false then
        return "#318 presence-based Equipment membership dropped disabled CWV"
    end
    local filtered, found = Policy.disable_group_subtree({
        { setting_id = "hb_group", type = "group", depth = 1 },
        { setting_id = "hide_frames", type = "checkbox", depth = 2 },
        { setting_id = "after", type = "group", depth = 1 },
    }, "hb_group")
    if not found or #filtered ~= 2 or filtered[1].disabled ~= true
        or filtered[1].tooltip ~= Policy.REASON then
        return "#318 disabled UI Tweaks subtree is not reduced to an explained header"
    end

    local ok, info = pcall(debug.getinfo, mod.on_setting_changed or function() end, "S")
    if not ok or type(info) ~= "table" or not info.source then return end
    local src = info.source:sub(1, 1) == "@" and info.source:sub(2) or info.source
    local dir = src:match("^(.*[/\\])[^/\\]*$")
    if not dir then return end
    for _, fn in ipairs({ "_mod_tweaker_view.lua", "_mod_tweaker_state.lua" }) do
        local txt = _gut_read_all(dir .. fn)
        if txt then
            if not txt:find("disabled_sections.select_" .. "members(cats, _EQUIP_ROLE)", 1, true) then
                return "#318 " .. fn .. " no longer uses presence-based Equipment membership"
            end
            if not txt:find("disabled_sections.disable_group_" .. "subtree", 1, true) then
                return "#318 " .. fn .. " no longer explains disabled UI Tweaks in place"
            end
            if not txt:find("row._disabled_in_" .. "vmf = true", 1, true) then
                return "#318 " .. fn .. " no longer renders disabled headers read-only/grey"
            end
        end
    end
end)

_rt_register("uitweaks_not_separate_modtweaker_tab", function()
    -- #312 (reworked per user): HideBuffs must NOT be in the _MY_MODS whitelist.
    -- UI Tweaks options live in gut's OWN menu under the single "UI Tweaks" group
    -- (hb_group), not as a separate Mod Tweaker tab. A re-add resurrects the
    -- duplicate tab the user flagged, so this now guards AGAINST the whitelist.
    local ok, info = pcall(debug.getinfo, mod.on_setting_changed or function() end, "S")
    if not ok or type(info) ~= "table" or not info.source then return end
    local src = info.source:sub(1, 1) == "@" and info.source:sub(2) or info.source
    local dir = src:match("^(.*[/\\])[^/\\]*$")
    if not dir then return end
    local needle = "HideBuffs = " .. "true"
    for _, fn in ipairs({ "_mod_tweaker_view.lua", "_mod_tweaker_state.lua" }) do
        local txt = _gut_read_all(dir .. fn)
        if txt and txt:find(needle, 1, true) then
            return "HideBuffs is whitelisted in " .. fn .. " -- that resurrects the separate UI Tweaks tab (#312)"
        end
    end
end)

_rt_register("uitweaks_sync_map_resolves", function()
    -- Every ELEMENT_MAP x/y key must resolve to a real HideBuffs.SETTING_NAMES entry.
    -- Skips cleanly (pass) when UI Tweaks isn't installed.
    local sync = mod._gut_uitweaks_sync
    if type(sync) ~= "table" or type(sync.ELEMENT_MAP) ~= "table" then
        return "uitweaks sync module or ELEMENT_MAP missing"
    end
    local HB = get_mod("HideBuffs")
    if not HB then return end  -- HB absent: nothing to resolve, pass.
    local names = HB.SETTING_NAMES
    if type(names) ~= "table" then return "HideBuffs.SETTING_NAMES missing" end
    for widget_id, m in pairs(sync.ELEMENT_MAP) do
        if type(m) ~= "table" or not m.x or not m.y then
            return "ELEMENT_MAP[" .. tostring(widget_id) .. "] malformed"
        end
        if names[m.x] == nil then
            return string.format("ELEMENT_MAP[%s].x=%s not in HB.SETTING_NAMES", tostring(widget_id), tostring(m.x))
        end
        if names[m.y] == nil then
            return string.format("ELEMENT_MAP[%s].y=%s not in HB.SETTING_NAMES", tostring(widget_id), tostring(m.y))
        end
    end
end)

_rt_register("uitweaks_bridged_to_stock_settings", function()
    -- (#312) The surfaced UI Tweaks toggles in gut's Mod Tweaker MUST route their get/set to
    -- the stock UI Tweaks (HideBuffs) mod so they stay consistent with UI Tweaks' own VMF
    -- options (user reports 2026-07-10 / 2026-07-12: toggles ON in UI Tweaks showed OFF here).
    -- Assert BOTH Mod Tweaker twins carry the bridge helper (marker) AND call it in the
    -- category-build path. Split needles so this check can never self-match; unreadable
    -- source => silent skip (pass).
    local ok, info = pcall(debug.getinfo, mod.on_setting_changed or function() end, "S")
    if not ok or type(info) ~= "table" or not info.source then return end
    local src = info.source:sub(1, 1) == "@" and info.source:sub(2) or info.source
    local dir = src:match("^(.*[/\\])[^/\\]*$")
    if not dir then return end
    local marker    = "[UITWEAKS-BRIDGE" .. "-312]"
    local call_form = "_bridge_uitweaks_to" .. "_stock(out)"
    for _, fn in ipairs({ "_mod_tweaker_view.lua", "_mod_tweaker_state.lua" }) do
        local txt = _gut_read_all(dir .. fn)
        if txt then
            if not txt:find(marker, 1, true) then
                return fn .. " dropped the UI Tweaks->stock HideBuffs bridge helper (#312)"
            end
            if not txt:find(call_form, 1, true) then
                return fn .. " no longer calls the UI Tweaks->stock HideBuffs bridge in the category build (#312)"
            end
        end
    end
end)

_rt_register("vanilla_numeric_mirror_wired", function()
    -- Both mirror setting ids exist in the data tree AND on_setting_changed writes
    -- the vanilla engine setting.
    local ok, info = pcall(debug.getinfo, mod.on_setting_changed or function() end, "S")
    if not ok or type(info) ~= "table" or not info.source then return end
    local src = info.source:sub(1, 1) == "@" and info.source:sub(2) or info.source
    local dir = src:match("^(.*[/\\])[^/\\]*$")
    if dir then
        local data_txt = _gut_read_all(dir .. "gui_tweaker_dev_data.lua")
        if data_txt then
            for _, sid in ipairs({ "gut_vanilla_numeric" .. "_ui", "gut_vanilla_persistent" .. "_ammo" }) do
                if not data_txt:find(sid, 1, true) then
                    return "vanilla mirror setting missing from data tree: " .. sid
                end
            end
        end
    end
    local main_txt = _gut_read_all(src)
    if main_txt and not main_txt:find('set_user_setting("numeric' .. '_ui"', 1, true) then
        return "on_setting_changed missing the numeric_ui vanilla mirror write (#312)"
    end
end)
_rt_register("freecam_invariants", function()
    -- Free Camera (#307) load-bearing invariants, source-pattern checked so the two
    -- prior-attempt failure classes can't regress silently. Resolve the module path
    -- from the main file's source dir (same idiom as the mirror-wired check above).
    local ok, info = pcall(debug.getinfo, mod.on_setting_changed or function() end, "S")
    if not ok or type(info) ~= "table" or not info.source then return end
    local src = info.source:sub(1, 1) == "@" and info.source:sub(2) or info.source
    local dir = src:match("^(.*[/\\])[^/\\]*$")
    if not dir then return end
    -- Wiring must be live regardless of source availability.
    if type(mod._gut_apply_freecam) ~= "function" then return "mod._gut_apply_freecam not wired" end
    if type(mod.gut_freecam_toggle) ~= "function" then return "mod.gut_freecam_toggle not wired" end
    local data_txt = _gut_read_all(dir .. "gui_tweaker_dev_data.lua")
    if data_txt and not data_txt:find("gut_freecam_enabled", 1, true) then
        return "gut_freecam_enabled missing from data tree"
    end
    local fc = _gut_read_all(dir .. "_gut_freecam.lua")
    if not fc then return end   -- source not shipped in bundle; wiring checks above still ran
    -- INVARIANT 1: never call set_disabled (the nil-run_func crash class that killed
    -- the old gt attempt). Match the call form, not the word in comments.
    if fc:find("set_disabled%s*%(") or fc:find(":set_disabled") then
        return "freecam calls set_disabled -- the locomotion-freeze crash class (#307 must never reintroduce)"
    end
    -- INVARIANT 2: the anti-bleed hook is present (the fix the old attempt lacked).
    if not fc:find("is_input_blocked", 1, true) then
        return "freecam missing the PlayerInputExtension.is_input_blocked anti-bleed hook"
    end
    -- INVARIANT 3: an F8 raw keyboard poll is still offered as a convenience exit.
    if not fc:find("Keyboard.button", 1, true) then
        return "freecam missing the raw Keyboard exit poll (belt-and-suspenders exit)"
    end
    -- INVARIANT 4: the disable_free_flight gate is NOT lifted (keeps the vanilla
    -- F8/F9/drop-player dispatcher from running and misfiring).
    if fc:find("disable_free_flight%s*=%s*false") then
        return "freecam lifts disable_free_flight -- exposes the vanilla free-flight key dispatch (#307 keeps the gate up)"
    end
    -- INVARIANT 5 (#307 hard-lock fix): after _enter_free_flight steals every device via
    -- block_device_except_service, we MUST hand them back so ESC/keybind/checkbox exits
    -- keep working (the character stays frozen by is_input_blocked). If this call is ever
    -- removed the mod re-bricks: input locks with only the fragile F8 poll to escape.
    if not fc:find("device_unblock_all_services", 1, true) then
        return "freecam does not unblock input devices after entering free flight -- #307 hard input-lock regressed"
    end
    -- INVARIANT 6 (BUG_CLASSES 32, #459 family): every WorldManager lookup in the freecam
    -- module must route through the has_world-gated _live_world helper. A bare lookup on the
    -- mods_update path fasserts on Leave Game (WorldManager.world, world_manager.lua:111-115),
    -- and a nil check placed after the bare call is dead code. Functional half: the gate
    -- predicate must return nil, not raise, for a world that does not exist.
    if type(mod._gut_fc_live_world) ~= "function" then
        return "freecam _live_world gate helper not wired (mod._gut_fc_live_world) -- BUG_CLASSES 32"
    end
    local ok_lw, lw = pcall(mod._gut_fc_live_world, "__rt_no_such_world__")
    if not ok_lw then
        return "freecam _live_world RAISED on a missing world -- has_world gate broken (BUG_CLASSES 32): " .. tostring(lw)
    end
    if lw ~= nil then
        return "freecam _live_world returned a value for a missing world (gate not gating)"
    end
    -- Pattern half: no bare gated-manager lookup outside the helper (needle split so this
    -- check can't self-match its own source).
    local bare_needle = "Managers.world:" .. "world("
    if fc:find(bare_needle, 1, true) then
        return "freecam has a bare " .. bare_needle .. " call -- must route through _live_world (BUG_CLASSES 32)"
    end
    -- The state-transition force-exit must keep its dead-world release path (the engine's
    -- own _clear_free_flight), or the engine slot leaks active=true across teardown.
    if not fc:find("_clear_free_flight", 1, true) then
        return "freecam dropped the _clear_free_flight dead-world release (class-32 force-exit regressed)"
    end
end)

-- (#313) Crosshair Kill Confirmation bridge regression tests. Split needles so the
-- source-pattern checks can't self-match; unreadable source => silent skip (pass).
_rt_register("mod_tweaker_no_integrated_toplevel_tabs", function()
    -- (#339) A third-party INTEGRATED mod must NEVER get a top-level Mod Tweaker tab --
    -- a tab is only for the author's own Tweaker-series mods. Crosshair Kill Confirmation
    -- (#313, absorbed) must NOT be in the _MY_MODS whitelist of the two TAB-DRIVING files;
    -- its options fold INTO gut's Interface tab under the HUD group via _inject_ckc_into_gut
    -- (the UI Tweaks / HideBuffs #312 precedent). Re-adding CKC to _MY_MODS resurrects the
    -- wrong #313 tab this issue corrects. NOTE: the config-EXPORT whitelist in
    -- _gut_config_file.lua is a SEPARATE concern (settings snapshot/restore) and
    -- legitimately keeps CKC + HideBuffs, so it is intentionally NOT checked here.
    -- Binding rule: gui_tweaker_dev/MOD_TWEAKER_INTEGRATION.md.
    local ok, info = pcall(debug.getinfo, mod.on_setting_changed or function() end, "S")
    if not ok or type(info) ~= "table" or not info.source then return end
    local src = info.source:sub(1, 1) == "@" and info.source:sub(2) or info.source
    local dir = src:match("^(.*[/\\])[^/\\]*$")
    if not dir then return end
    local ckc_tab_needle = '["Crosshair Kill Confirmation"] = ' .. "true"
    local fold_needle    = "_inject_ckc_into" .. "_gut"
    for _, fn in ipairs({ "_mod_tweaker_view.lua", "_mod_tweaker_state.lua" }) do
        local txt = _gut_read_all(dir .. fn)
        if txt then
            if txt:find(ckc_tab_needle, 1, true) then
                return "CKC is whitelisted in _MY_MODS in " .. fn ..
                    " -- resurrects the wrong #313 top-level tab (#339); it must fold into the HUD group"
            end
            if not txt:find(fold_needle, 1, true) then
                return "_inject_ckc_into_gut fold missing from " .. fn ..
                    " -- CKC options would not appear under the Interface>HUD category (#339)"
            end
        end
    end
end)

_rt_register("ckc_bridge_module_wired", function()
    -- The bridge module published its marker + API table at load (regardless of whether
    -- the CKC mod itself is installed).
    if mod._GUT_CKC_BRIDGE_MARKER ~= "gut-ckc-bridge-313" then
        return "mod._GUT_CKC_BRIDGE_MARKER missing/wrong (bridge module not loaded)"
    end
    if type(mod._gut_ckc_bridge) ~= "table" then
        return "mod._gut_ckc_bridge table missing"
    end
end)

_rt_register("ckc_bridge_implicit_no_toggle", function()
    -- (#528) The CKC bridge is IMPLICIT (active whenever CKC is installed + togglable).
    -- The retired gut_ckc_options_bridge availability toggle must stay gone: no widget
    -- in the data file, and the bridge module must not read the setting id. (Inverse of
    -- the pre-#528 ckc_bridge_loc_keys check, which REQUIRED the key.) Split needles;
    -- unreadable source => silent skip.
    local ok, info = pcall(debug.getinfo, mod.on_setting_changed or function() end, "S")
    if not ok or type(info) ~= "table" or not info.source then return end
    local src = info.source:sub(1, 1) == "@" and info.source:sub(2) or info.source
    local dir = src:match("^(.*[/\\])[^/\\]*$")
    if not dir then return end
    local retired = "gut_ckc_options" .. "_bridge"
    local data_txt = _gut_read_all(dir .. "gui_tweaker_dev_data.lua")
    if data_txt and data_txt:find('"' .. retired .. '"', 1, true) then
        return "retired availability toggle " .. retired .. " re-added to the data file (#528: the bridge is implicit)"
    end
    local br_txt = _gut_read_all(dir .. "_gut_ckc_bridge.lua")
    if br_txt and br_txt:find('"' .. retired .. '"', 1, true) then
        return "_gut_ckc_bridge.lua reads " .. retired .. " again (#528: no availability gate; _is_active = CKC presence only)"
    end
end)

_rt_register("ckc_bridge_uses_native_checkbox", function()
    local bridge = mod._gut_ckc_bridge
    local policy = bridge and bridge.widget_policy
    if type(policy) ~= "table" or type(policy.prepare_definition) ~= "function" then
        return "CKC native-checkbox policy missing (#528 follow-up)"
    end
    local row = { setting_name = "crosshair_kill_confirm", widget_type = "drop_down" }
    local token = policy.prepare_definition({ row }, "crosshair_kill_confirm", true)
    if not token or row.widget_type ~= "checkbox" then
        return "CKC row was not redirected through native checkbox factory"
    end
    policy.restore_definition(token)
    if row.widget_type ~= "drop_down" then
        return "CKC row definition was not restored after native list build"
    end
    local content = { flag = false }
    policy.restore_checkbox(content, true)
    if policy.checkbox_value(content) ~= true then
        return "CKC checkbox does not round-trip content.flag"
    end
    local render = bridge and bridge.render_policy
    if type(render) ~= "table" or type(render.harden) ~= "function" then
        return "CKC renderer-safe checkbox policy missing (#528 crash regression)"
    end
    local widget = {
        content = { flag = false, checkbox = "checkbox_unchecked" },
        style = { checkbox = { size = { 16, 16 } } },
        element = { passes = {
            { pass_type = "local_offset", offset_function = function(_, _, c)
                c.checkbox = c.flag and "checkbox_checked" or "checkbox_unchecked"
            end },
            { pass_type = "texture", style_id = "checkbox", texture_id = "checkbox" },
        } },
    }
    if not render.harden(widget) then
        return "CKC borrowed checkbox could not be hardened"
    end
    widget.content.flag = true
    widget.element.passes[1].offset_function(nil, nil, widget.content, nil)
    if widget.content.checkbox ~= "matchmaking_checkbox" then
        return "CKC native offset restored a missing raw checkbox material"
    end
end)

_rt_register("hud_collapsibles_hold_first_position", function()
    -- (#527) Collapsible sub-groups sit FIRST at their level (user doctrine): in the
    -- HUD group the UI Tweaks collapsible (hb_group) must precede the first loose
    -- option (gut_hud_mode), and BOTH Mod Tweaker twins must splice the CKC sub-group
    -- at the START of the HUD child block (marker [CKC-SPLICE-FIRST" .. "-527]).
    -- Source-pattern checks with split needles; unreadable source => silent skip.
    local ok, info = pcall(debug.getinfo, mod.on_setting_changed or function() end, "S")
    if not ok or type(info) ~= "table" or not info.source then return end
    local src = info.source:sub(1, 1) == "@" and info.source:sub(2) or info.source
    local dir = src:match("^(.*[/\\])[^/\\]*$")
    if not dir then return end
    local data_txt = _gut_read_all(dir .. "gui_tweaker_dev_data.lua")
    if data_txt then
        local hb_at   = data_txt:find('"hb' .. '_group"', 1, true)
        local mode_at = data_txt:find('"gut_hud' .. '_mode"', 1, true)
        if hb_at and mode_at and hb_at > mode_at then
            return "hb_group (UI Tweaks collapsible) no longer leads the HUD group -- collapsibles sort first (#527)"
        end
    end
    local splice_needle = "CKC-SPLICE-FIRST" .. "-527"
    for _, fn in ipairs({ "_mod_tweaker_view.lua", "_mod_tweaker_state.lua" }) do
        local txt = _gut_read_all(dir .. fn)
        if txt and not txt:find(splice_needle, 1, true) then
            return fn .. " lost the " .. splice_needle .. " head-of-HUD splice (#527: CKC group must lead the HUD child block)"
        end
    end
end)

_rt_register("ckc_gear_left_of_field_clears_scrollbar", function()
    -- (#313) The vanilla-Options cog must sit in the gutter LEFT of the On/Off field, clear
    -- of the page scrollbar (user report 2026-07-11 "overflows into the scrollbar"). Assert
    -- _append_gear carries the left-gutter marker AND no longer uses the old right-of-row
    -- "+ ROW_W + 10" placement that overlapped the scrollbar. Split needles; unreadable
    -- source => silent skip (retail sandbox has no io -- #511).
    local ok, info = pcall(debug.getinfo, mod.on_setting_changed or function() end, "S")
    if not ok or type(info) ~= "table" or not info.source then return end
    local src = info.source:sub(1, 1) == "@" and info.source:sub(2) or info.source
    local dir = src:match("^(.*[/\\])[^/\\]*$")
    if not dir then return end
    local br_txt = _gut_read_all(dir .. "_gut_ckc_bridge.lua")
    if not br_txt then return end
    local gutter_needle = "CKC-GEAR-LEFT-GUTTER" .. "-313"
    if not br_txt:find(gutter_needle, 1, true) then
        return "_gut_ckc_bridge.lua lost the " .. gutter_needle ..
            " left-gutter cog placement -- the cog would overflow the page scrollbar again (#313)"
    end
    -- The old placement anchored the cog to the row's RIGHT edge (sz[1] + 10). Its return
    -- (the scrollbar overlap) must not come back.
    local old_needle = "(sz[1] or 1300) + " .. "10"
    if br_txt:find(old_needle, 1, true) then
        return "_gut_ckc_bridge.lua still places the cog at row-right (" .. old_needle ..
            ") -- it overlaps the scrollbar; place it left of the field (#313)"
    end
end)

_rt_register("ckc_three_surface_sync_precedence", function()
    -- (#311) The three surfaces (vanilla row / gut Mod Tweaker HUD group / CKC's own VMF page)
    -- converge on one source of truth. Assert (1) the bridge header documents the precedence
    -- (marker [CKC-SYNC-PRECEDENCE-311]) and (2) the Mod Tweaker write-through fires the owner
    -- mod's on_setting_changed live -- _cat_set calls mod_obj.set(id, value, true) so a HUD-group
    -- edit reaches CKC (the own-or-pin doctrine). Split needles; unreadable source => skip.
    local ok, info = pcall(debug.getinfo, mod.on_setting_changed or function() end, "S")
    if not ok or type(info) ~= "table" or not info.source then return end
    local src = info.source:sub(1, 1) == "@" and info.source:sub(2) or info.source
    local dir = src:match("^(.*[/\\])[^/\\]*$")
    if not dir then return end
    local br_txt = _gut_read_all(dir .. "_gut_ckc_bridge.lua")
    if br_txt then
        local prec_needle = "CKC-SYNC-PRECEDENCE" .. "-311"
        if not br_txt:find(prec_needle, 1, true) then
            return "_gut_ckc_bridge.lua header lost the " .. prec_needle ..
                " three-surface sync precedence (#311)"
        end
    end
    local st_txt = _gut_read_all(dir .. "_mod_tweaker_state.lua")
    if st_txt then
        -- _cat_set must fire the owner's on_setting_changed (3rd arg true) so a HUD-group
        -- CKC edit writes THROUGH to the CKC mod live.
        local wt_needle = "mod_obj.set, mod_obj, setting_id, value, " .. "true"
        if not st_txt:find(wt_needle, 1, true) then
            return "_mod_tweaker_state.lua _cat_set no longer live-fires on_setting_changed" ..
                " (mod_obj.set ... true) -- Mod Tweaker HUD-group edits would not reach CKC (#311)"
        end
    end
end)

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
-- NumericUI ability-cooldown realtime fix: VT2 cooldown reduction speeds up the
-- countdown (decreases the value faster), so NumericUI's raw cooldown number visibly
-- speeds up. We divide the cooldown read (only while NumericUI is computing its
-- display) by the cooldown_regen multiplier so it shows accurate, real-time-paced
-- reduced seconds. No-op if NumericUI isn't installed. See _numericui_cooldown_realtime.lua.
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
-- mirrored-scenegraph UIWidget anchored on the frame's pivot slot (#285 fix,
-- ported verbatim from Respawn CD 3747644100). See _gut_respawn_timer.lua.
pcall(mod.dofile, mod, "scripts/mods/gui_tweaker_dev/_gut_respawn_timer")

-- (#285) Guards the respawn-timer #285 fix on THREE invariants:
--   (a) the draw rides IngameHud.update (proven by "Respawn CD", 3747644100),
--       never the broken UnitFrameUI.draw path (which rendered nothing);
--   (b) it draws the number via UIRenderer.draw_widget through a mirrored
--       scenegraph anchored on the frame's `pivot` LOCAL position -- NOT an
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
        return "respawn timer regressed: no longer draws via the mirrored-scenegraph widget path -- #285 wrong-position"
    end
    if txt:find("get_world_position", 1, true) then
        return "respawn timer regressed: reintroduced get_world_position immediate-draw (double-scaled, wrong spot) -- #285"
    end
    if not txt:find("font_size%s*=%s*72") then  -- Lua pattern: whitespace-robust
        return "respawn timer regressed: teammate font base is no longer 72 (renders tiny) -- #285"
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

-- Held-Tab weapon property refresh (#245). The v2 player list renders a
-- detached RPC loadout row; while visible, reconcile only the local equipped
-- melee/ranged properties from their exact live backend instances at 4 Hz.
do
    local ok, api = pcall(mod.dofile, mod,
        "scripts/mods/gui_tweaker_dev/_gut_tab_property_refresh")
    if ok and type(api) == "table" then
        for _, check in ipairs(api.rt_checks or {}) do
            _rt_register(check.name, check.fn)
        end
    else
        _dbg_alert("[gut:245] Tab property refresh failed: %s", tostring(api))
    end
end

-- Floating Damage Numbers (MIGRATED from general_tweaker 2026-06-29): client-side,
-- networking-free numbers over enemies you damage, via the engine's own
-- DamageNumbersUI + DamageUtils.add_unit_floating_damage_numbers. Registers its OWN
-- hooks on DamageUtils.add_damage_network / add_damage_network_player (PRE-FLIGHT:
-- gut has no other hook on either method — it only reads DamageUtils.is_in_inn), and
-- chains mod.on_setting_changed / mod.on_game_state_changed (dofile'd after both are
-- defined). See _gut_damage_numbers.lua.
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

-- Inventory character-preview backdrop dropdown (#522): swaps the environment
-- behind the hero in the inventory preview pane (vanilla / dark camp / victory
-- camp). One singleton pre-hook on HeroWindowCharacterPreview.create_ui_elements
-- (preflight-verified: gut hooks that class nowhere else) mutates the cached
-- viewport def's level/package/env triplet BEFORE vanilla reads it, so vanilla's
-- own managed load + has_loaded gate + symmetric unload handle residency end to
-- end -- no new mount path, no crash path (alternates are the game's standalone
-- end-screen level packages; existence pre-checked via can_get("package")).
-- Chains mod.on_disabled (def restore). See _gut_inventory_backdrop.lua.
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

-- (#313) Crosshair Kill Confirmation options-menu bridge. When the CKC mod
-- ("Crosshair Kill Confirmation") is installed + togglable, takes over the vanilla
-- crosshair_kill_confirm dropdown as an On/Off toggle for the mod, forces the vanilla
-- marker off (remembering + restoring the prior group), and adds a gear that opens the
-- Mod Tweaker on the CKC tab. Self-wires: chains on_all_mods_loaded + on_setting_changed
-- at dofile time (this line is the ONLY main-file contribution). No-op when CKC is absent.
-- Must dofile AFTER on_setting_changed (~632) + the on_all_mods_loaded chain (~2001), both
-- well above here. See _gut_ckc_bridge.lua.
pcall(mod.dofile, mod, "scripts/mods/gui_tweaker_dev/_gut_ckc_bridge")

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
-- hooks run after vanilla population and never mutate career/passive tables.
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
