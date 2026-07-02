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
-- material when it's resident but missing (#155). Returns (new_table, count) when the list
-- changed, or nil to signal "unchanged -- use the originals" (preserves the fast path).
local function _prepare(n, ...)
    local args = { ... }

    -- Pass 1: classify this create call. `has_ingame_sig` marks the ingame ui/ui_top
    -- renderers (the ones the in-mission Cosmetics window draws on); `has_pose` = the pose
    -- material is already in the list (keep context -- nothing to inject).
    local has_ingame_sig, has_pose = false, false
    do
        local i = 1
        while i <= n do
            local tok = args[i]
            if tok == "material" and i < n and type(args[i + 1]) == "string" then
                local path = args[i + 1]
                if path == INGAME_SIG then has_ingame_sig = true end
                if path == POSE_MAT   then has_pose = true end
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
    end

    if not dropped and not append_pose then
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

mod:info("[gut] GUI material guard installed (drops unloadable create_screen_gui materials to prevent client CTDs; injects the pose-cosmetics atlas into in-mission renderers when resident, #155)")

return {}
