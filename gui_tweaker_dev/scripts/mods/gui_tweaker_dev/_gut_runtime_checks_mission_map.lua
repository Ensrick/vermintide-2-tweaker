-- _gut_runtime_checks_mission_map.lua - mission-map regression registrations.
--
-- Owns the three existing map backdrop/video/preview checks without running
-- them during installation. Keeps their bodies, order and io-safe source
-- reader contract unchanged; no hooks, commands or engine writes are added.
-- Owned by: gui_tweaker_dev.lua. Consumed via its ordered mod:dofile manifest.
local M = {}
function M.register(context)
    local mod, _rt_register, _rt_src_read = context.mod, context.register, context.read_source
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

end
return M
