local mod = get_mod("gut_dev")

-- ============================================================================
-- GUI material guard -- "Gui material not found" create_screen_gui CTD class
-- ============================================================================
-- SYMPTOM (client CTD on mission load, 2026-07-01): a friend running the "More
-- Loading Screens" mod crashed loading into dlc_castle_nurgle_path1 with
--   <<Script Error>> materials/ui/ui_1080p_chat
--   [0] =[C] create_screen_gui  [1] ui_renderer.lua func  [2] vmf custom_textures  [4] more_loading_screens
--
-- MECHANISM: every screen GUI funnels through UIRenderer.create(world, "material",
-- path, "material", path, ...) -> World.create_screen_gui, a C function that takes a
-- HARD FATAL when any listed material's resource isn't resident. It bypasses pcall
-- AND xpcall -- the crash we caught went THROUGH VMF's own safe_call_nr xpcall and
-- still killed the client -- so we cannot CATCH it, we must PRE-FILTER. ui_1080p_chat
-- is a real vanilla loading-screen material (see vanilla loading_view.lua); it was
-- simply not resident on that client at that instant (a mod-compat timing edge). Any
-- mod that hands the engine a momentarily-unloaded material triggers this class.
--
-- FIX: wrap UIRenderer.create -- the exact funnel VMF's custom_textures already hooks,
-- so it is proven-hookable -- and drop any ("material", <path>) pair whose material is
-- NOT loadable, tested with Application.can_get("material", path). can_get is vanilla's
-- own safe, non-faulting existence check (pickup_system.lua:882 uses
-- can_get("unit", ...) for the identical "don't spawn a missing resource" guard). A
-- missing material now makes that ONE element silently not render instead of crashing.
-- Mod-agnostic: protects against More Loading Screens, Loremaster's Armoury, and our
-- own mods alike, and generalizes the LA-atlas-specific keepalive (_la_atlas_keepalive).
--
-- SAFETY INTERLOCK: the guard stays PASSIVE (pure passthrough) until can_get proves
-- trustworthy against a known-always-resident material (gw_fonts). It also fails OPEN
-- on any error -- if the filter throws, the original args are used untouched. The guard
-- can never be the thing that breaks or blanks GUI creation.

local can_get = Application and Application.can_get

local _self_tested = false
local _trustworthy = false

-- (#155) In-mission Cosmetics-tab pose-atlas injection ------------------------------
-- The Cosmetics loadout window draws weapon-POSE items through the `gui_pose_items_atlas`
-- material, which lives inside the `materials/ui/ui_1080p_pose_cosmetics` resource. Vanilla
-- (ingame_ui_settings.lua ui_renderer_function / ui_top_renderer_function) only appends that
-- resource to the ingame renderer's Gui material list when `is_in_inn` is true, so in a
-- mission the material is ABSENT from the Gui and the pose draw takes a C-level "Material
-- not found in Gui" fatal at DRAW time (ui_passes.lua:134) -- a different, uncatchable path
-- from the create_screen_gui fatal the drop-filter below handles. Since UIRenderer.create is
-- the funnel that builds every ingame Gui's material list, we ADD the pose resource to that
-- list for ingame renderers that lack it, but ONLY when the resource is actually resident
-- (can_get true) -- adding a non-resident material would itself fatal create_screen_gui (the
-- drop-filter would then strip it, leaving the draw to crash). The result is published in
-- `mod._gut_pose_atlas_ingame` so _gut_mission_inventory.lua can gate the in-mission tab on
-- whether the atlas actually made it into the Gui. NOTE: if the resource is NOT resident in
-- a mission (it may be a keep-only package), injection is skipped and the tab stays gated --
-- the printf below reports that, which tells us a package pin is required to go further.
local POSE_MAT   = "materials/ui/ui_1080p_pose_cosmetics"
local INGAME_SIG = "materials/ui/ui_1080p_hud_atlas_textures"  -- in every ingame ui/ui_top renderer material list
local _pose_logged_state = nil  -- edge latch: nil / "present" / "absent" (de-spam the printf)

-- (#80) In-mission Crafting-tab store-atlas injection. The vanilla salvage craft page
-- (craft_page_salvage_console.lua:398) draws its auto-fill rarity buttons
-- (store_tag_icon_weapon_plentiful/common/rare/exotic) out of the `gui_store_menu_atlas`
-- material, which lives in `materials/ui/ui_1080p_store_menu`. store_ui_settings.lua lists
-- that resource under `ui_materials_in_inn`, so vanilla adds it to the ingame ui/ui_top
-- renderer material list ONLY in the keep -- in a mission the Salvage page draws it and takes
-- the same uncatchable "Material not found in Gui" DRAW fatal (ui_passes.lua:194) as the pose
-- atlas above. UNLIKE the pose atlas, the store resource IS resident in a mission
-- (resource_packages/dlcs/store is force-loaded at boot -- see the console-*.log
-- `Force_load: resource_packages/dlcs/store` line), so the can_get-gated injection actually
-- lands, letting the in-mission Crafting tab's Salvage page render. Crash console
-- 2026-07-06-00.49.xx (salvage page on wood_elf, gui_store_menu_atlas not found in Gui).
local STORE_MAT = "materials/ui/ui_1080p_store_menu"
local _store_logged_state = nil

-- (#336) In-mission mission-map AREA-VIDEO injection. The console area-selection window
-- (start_game_window_area_selection_console_v2.lua:647-670 _assign_video_player, drawn at
-- :628-638) and its PC sibling (start_game_window_area_selection.lua:458-476) draw each
-- area's preview video through the AreaSettings[*].video_settings.material_name material
-- (e.g. area_video_bogenhafen), whose material resource is video_settings.resource
-- (area_settings.lua:12-15). Vanilla appends those resources to the ingame ui/ui_top
-- renderer material lists ONLY inside `if is_in_inn` (ingame_ui_settings.lua:594-601
-- ui_renderer_function; :681-688 ui_top_renderer_function), so a mid-mission map open that
-- reaches area selection takes the uncatchable "Material 'area_video_*' not found in Gui"
-- DRAW fatal at UIRenderer.draw_video -> Gui.video (shipped ui_renderer.lua:1345; user
-- crash console-2026-07-06-03.24.08, dlc_dwarf_whaling, 03:28:50). Same class as the pose
-- (#155) and store (#80) atlases above: inject each area-video resource into ingame
-- renderers when it is resident (can_get-gated -- a non-resident add would itself fatal
-- create_screen_gui). The per-material outcome is published in
-- `mod._gut_area_videos_ingame` (material_name -> true/false) so _gut_mission_map.lua can
-- skip the video widget for any material that did NOT make it into the Gui (the
-- belt-and-suspenders second layer).
local _area_logged_state = nil

-- AreaSettings video entries ({ material_name=, resource= } per area). Read live each
-- ingame-renderer create: the table is boot-populated (base area_settings.lua + the DLC
-- level_unlock_settings_* files) long before any mission renderer exists.
local function _area_video_entries()
    local out = {}
    local area_settings = rawget(_G, "AreaSettings")
    if type(area_settings) ~= "table" then return out end
    for _, settings in pairs(area_settings) do
        local vs = settings.video_settings
        if type(vs) == "table" and vs.resource and vs.material_name then
            out[#out + 1] = vs
        end
    end
    return out
end

-- gw_fonts is in nearly every UIRenderer.create material list and is resident whenever
-- GUIs are created. If can_get can't see it, can_get's "material" resource type is not
-- reliable in this build -> we NEVER filter (avoid false-dropping valid materials and
-- blanking the UI). Tested lazily on the first create call (by then fonts are loaded).
local function _guard_trustworthy()
    if _self_tested then return _trustworthy end
    _self_tested = true
    if not can_get then
        printf("[gut:gui-guard] Application.can_get unavailable -- guard PASSIVE (no filtering)")
        return false
    end
    local ok, avail = pcall(can_get, "material", "materials/fonts/gw_fonts")
    _trustworthy = (ok and avail == true)
    if _trustworthy then
        printf("[gut:gui-guard] active (can_get('material') self-test passed)")
    else
        printf("[gut:gui-guard] PASSIVE -- can_get('material') self-test returned %s (not trustworthy)", tostring(avail))
    end
    return _trustworthy
end

-- Processes a UIRenderer.create material list: DROPS every ("material", <unloadable path>)
-- pair (the create_screen_gui CTD guard) and, for ingame renderers, ADDS the pose-cosmetics
-- material (#155), the store-menu atlas (#80) and the AreaSettings area-video materials
-- (#336) when resident but missing. Returns (new_table, count) when the list changed, or
-- nil to signal "unchanged -- use the originals" (preserves the fast path).
local function _prepare(n, ...)
    local args = { ... }

    -- Pass 1: classify this create call. `has_ingame_sig` marks the ingame ui/ui_top
    -- renderers (the ones the in-mission Cosmetics window draws on); `has_pose` = the pose
    -- material is already in the list (keep context -- nothing to inject). `seen` records
    -- every material path in the list for the area-video presence check (#336).
    local has_ingame_sig, has_pose, has_store = false, false, false
    local seen = {}
    do
        local i = 1
        while i <= n do
            local tok = args[i]
            if tok == "material" and i < n and type(args[i + 1]) == "string" then
                local path = args[i + 1]
                seen[path] = true
                if path == INGAME_SIG then has_ingame_sig = true end
                if path == POSE_MAT   then has_pose = true end
                if path == STORE_MAT  then has_store = true end
                i = i + 2
            else
                i = i + 1
            end
        end
    end

    -- Decide injection: only for an ingame renderer that lacks the pose material, and ONLY
    -- when the resource is actually resident (else adding it would fatal create_screen_gui).
    local append_pose = false
    if has_ingame_sig and not has_pose then
        local ok, avail = pcall(can_get, "material", POSE_MAT)
        append_pose = (ok and avail == true)
    end
    -- (#80) store atlas: same gate. It IS resident in-mission (dlcs/store force-loaded at
    -- boot), so this injection lands where the pose one self-skips.
    local append_store = false
    if has_ingame_sig and not has_store then
        local ok, avail = pcall(can_get, "material", STORE_MAT)
        append_store = (ok and avail == true)
    end
    -- (#336) area videos: same gate, one decision per AreaSettings entry. Also PUBLISH the
    -- per-material outcome (material_name -> in-Gui true/false) for the mission-map module's
    -- video-widget skip guard, and collect the injected/skipped names for the edge log.
    local append_areas = nil
    local area_injected, area_skipped, area_present = nil, nil, 0
    if has_ingame_sig then
        local flags = {}
        for _, vs in ipairs(_area_video_entries()) do
            if seen[vs.resource] then
                flags[vs.material_name] = true          -- keep context: vanilla already listed it
                area_present = area_present + 1
            else
                local ok, avail = pcall(can_get, "material", vs.resource)
                if ok and avail == true then
                    append_areas = append_areas or {}
                    append_areas[#append_areas + 1] = vs.resource
                    flags[vs.material_name] = true
                    area_injected = area_injected or {}
                    area_injected[#area_injected + 1] = vs.material_name
                else
                    flags[vs.material_name] = false     -- NOT in the Gui: drawing it would fatal
                    area_skipped = area_skipped or {}
                    area_skipped[#area_skipped + 1] = vs.material_name
                end
            end
        end
        mod._gut_area_videos_ingame = flags
    end

    -- Pass 2: copy tokens, dropping any ("material", <unloadable>) pair (existing guard).
    local out, oi = {}, 0
    local dropped
    local i = 1
    while i <= n do
        local tok = args[i]
        if tok == "material" and i < n and type(args[i + 1]) == "string" then
            local path = args[i + 1]
            local ok, avail = pcall(can_get, "material", path)
            if ok and avail == false then
                dropped = dropped or {}
                dropped[#dropped + 1] = path            -- would fatal create_screen_gui -> drop the pair
            else
                oi = oi + 1; out[oi] = tok
                oi = oi + 1; out[oi] = path
            end
            i = i + 2
        else
            oi = oi + 1; out[oi] = tok                  -- preserve non-material tokens ("immediate", etc.)
            i = i + 1
        end
    end
    if append_pose then
        oi = oi + 1; out[oi] = "material"
        oi = oi + 1; out[oi] = POSE_MAT                 -- (#155) resident -> add to the ingame Gui
    end
    if append_store then
        oi = oi + 1; out[oi] = "material"
        oi = oi + 1; out[oi] = STORE_MAT                -- (#80) resident -> in-mission Salvage/Crafting page can draw
    end
    if append_areas then
        for j = 1, #append_areas do
            oi = oi + 1; out[oi] = "material"
            oi = oi + 1; out[oi] = append_areas[j]      -- (#336) resident -> mid-mission map area videos can draw
        end
    end

    -- Publish the in-mission pose-atlas Gui-residency signal for the Cosmetics-tab gate in
    -- _gut_mission_inventory.lua. Only meaningful for ingame renderers; edge-logged.
    if has_ingame_sig then
        local now_present = has_pose or append_pose
        mod._gut_pose_atlas_ingame = now_present
        local state = now_present and "present" or "absent"
        if _pose_logged_state ~= state then
            _pose_logged_state = state
            if append_pose then
                printf("[gut:155] injected '%s' into an ingame UI renderer (pose atlas now in its Gui -> in-mission Cosmetics tab can draw)", POSE_MAT)
            elseif has_pose then
                printf("[gut:155] ingame UI renderer already carries '%s' (keep context) -- no injection needed", POSE_MAT)
            else
                printf("[gut:155] pose atlas '%s' NOT resident (can_get=false) at ingame-renderer create -- Cosmetics tab stays gated in-mission; a package pin is needed to go further", POSE_MAT)
            end
        end

        -- (#80) store-atlas residency: edge-logged so the next in-mission Salvage test verifies.
        local store_state = (has_store or append_store) and "present" or "absent"
        if _store_logged_state ~= store_state then
            _store_logged_state = store_state
            if append_store then
                printf("[gut:80] injected '%s' into an ingame UI renderer (gui_store_menu_atlas now in its Gui -> in-mission Salvage/Crafting page can draw)", STORE_MAT)
            elseif has_store then
                printf("[gut:80] ingame UI renderer already carries '%s' (keep context) -- no injection needed", STORE_MAT)
            else
                printf("[gut:80] store atlas '%s' NOT resident (can_get=false) at ingame-renderer create -- Salvage-page tag icons cannot draw in-mission", STORE_MAT)
            end
        end

        -- (#336) area-video residency: edge-logged counts + names so the next mid-mission
        -- map open verifies which area previews can draw and which are video-skipped.
        local n_inj = area_injected and #area_injected or 0
        local n_skip = area_skipped and #area_skipped or 0
        local area_state = string.format("present=%d injected=%d skipped=%d", area_present, n_inj, n_skip)
        if _area_logged_state ~= area_state then
            _area_logged_state = area_state
            printf("[gut:336] area-video materials at ingame-renderer create: %s%s%s", area_state,
                n_inj > 0 and (" injected=[" .. table.concat(area_injected, ",") .. "]") or "",
                n_skip > 0 and (" video-skipped=[" .. table.concat(area_skipped, ",") .. "] (not resident; mission-map area preview stays a static image)") or "")
        end
    end

    if not dropped and not append_pose and not append_store and not append_areas then
        return nil  -- unchanged: caller uses the originals
    end
    if dropped then
        for j = 1, #dropped do
            printf("[gut:gui-guard] dropped unloadable GUI material '%s' (prevented create_screen_gui CTD)", tostring(dropped[j]))
        end
    end
    return out, oi
end

-- gut hooks UIRenderer.create NOWHERE else (verified via grep before adding) -- no
-- duplicate-hook collision. VMF/More Loading Screens hook it too, from OTHER mods, so
-- the hooks chain cleanly.
mod:hook("UIRenderer", "create", function(func, world, ...)
    if not _guard_trustworthy() then return func(world, ...) end
    local ok, prepared, count = pcall(_prepare, select("#", ...), ...)
    if ok and prepared then
        return func(world, unpack(prepared, 1, count))  -- unpack-safe: explicit count, no nil-hole
    end
    return func(world, ...)                             -- fail-open: unchanged OR error -> originals untouched
end)

mod:info("[gut] GUI material guard installed (drops unloadable create_screen_gui materials to prevent client CTDs; injects the pose-cosmetics atlas #155, the store-menu atlas #80 and the AreaSettings area-video materials #336 into in-mission renderers when resident)")

return {}
