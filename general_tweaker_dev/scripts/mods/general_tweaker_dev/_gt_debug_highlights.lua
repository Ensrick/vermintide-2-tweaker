local mod = get_mod("gt_dev")

-- _gt_debug_highlights.lua -- in-world debug overlay (GitHub #302)
--
-- Draws colored wireframes over normally-invisible gameplay geometry so a tester
-- can see it: interactables, item pickups, pickup spawn points, enemy/player
-- bounding boxes, approximate headshot nodes, and enemy aggro rings.
--
-- ============================================================================
-- RENDER METHOD (v0.2.216-dev rewrite -- the reason phases 1-4 rendered NOTHING)
-- ============================================================================
-- The original implementation drew with a native `LineObject`
-- (World.create_line_object -> LineObject.add_box/sphere/circle ->
-- LineObject.dispatch(level_world, lo)). That path RAN correctly every frame --
-- console-2026-07-12-22.03.01 shows `[gt_dev:DH] drawn ... interact=48..60
-- players=1` once per second in-game, i.e. 48-60 boxes were added and dispatched
-- per frame -- yet the user reported (issue #302, 2026-07-12) that nothing ever
-- appeared on screen. That is direct proof that a raw LineObject.dispatch does
-- NOT visibly render in RETAIL Vermintide 2:
--   * Fatshark stripped Lua debug drawing from release builds. The vanilla
--     drawer wrappers become `DebugDrawerRelease`, whose every method (line,
--     box, sphere, circle, AND `update`, which is what dispatches) is a bare
--     `return` no-op in release (debug_drawer_release.lua). Debug.active is
--     `BUILD ~= "release"` (debug.lua:9), so Debug.update never dispatches
--     either. The debug-line render pass is effectively dead for retail mods.
--   * Every overlay that DOES render in retail (floating damage numbers, HUD
--     world markers, objective/ping icons) is a SCREEN-SPACE gui projected with
--     `Camera.world_to_screen` -- NOT a LineObject (damage_numbers_ui.lua:410,
--     world_marker_ui.lua:618-624, floating_icon_ui.lua:117-131).
--
-- So this file now renders the SAME way the shipped HUD does: project each world
-- point to screen with Camera.world_to_screen and draw 2D lines on a screen gui
-- with ScriptGUI.hud_line (script_gui.lua:45, a rotated Gui.rect_3d). A box is
-- its 8 projected OOBB corners joined by its 12 edges; a ring is N projected
-- points on a world circle. This is the retail-proven method (StreamingInfo /
-- the vanilla HUD use exactly this: screen gui + Camera.world_to_screen).
--
-- Drawn from a hook_safe on IngameUI.update -- the phase the working retail info
-- mods draw from (StreamingInfo hooks IngameUI.update), which ticks in BOTH the
-- keep and a mission (the user tests in the keep / "inn_level"). NOT mod.update:
-- the two proven gt screen-draws (this and _gt_melee_warning's IngameHud.update)
-- and every vanilla screen overlay issue their draw calls in the UI update phase.
--
-- Engine primitives (verified in the decompiled source):
--   Managers.camera:has_viewport("player_1")            floating_icon_ui.lua:120
--   ScriptWorld.viewport(world,"player_1") -> camera    floating_icon_ui.lua:126-128
--   Camera.world_to_screen(cam, wpos) -> screen, dist   world_marker_ui.lua:620 (raw px; .x=x .y=y)
--   Camera.world_position / world_rotation              damage_numbers_ui.lua:156-159 (front guard)
--   ScriptGUI.hud_line(gui, p1, p2, layer, w, color)    script_gui.lua:45 (Gui.rect_3d line)
--   Unit.box(unit) -> pose(Matrix4x4), half_extents     interactable_system.lua:37
--   Matrix4x4.transform(pose, local_corner) -> world    freeflight.lua:54
--   World.create_screen_gui(world,"material",mtrl,"immediate") + can_get guard  (#293/#295)
--   Color(a, r, g, b) is ARGB 0-255                      imgui_physgun.lua:428
--   breed.detection_radius / hit_zones[z].actors[1]      breed_skaven_clan_rat.lua:18,92-97
--
-- Owned by: general_tweaker_dev.lua entry point. Consumed via: mod:dofile.

-- Dev-only gate (survives the dev->stable sed of the literal `gt_dev`; same idiom
-- as _gt_bot_teleport_lab.lua / the Dev Tools data group). In the stable clone
-- get_mod("gt".."_dev") -> nil, so the whole feature is inert there.
local IS_DEV_STREAM = (mod == get_mod("gt" .. "_dev"))

-- Global aliases (booleans/tables/functions only -- NEVER cache Vector3/Color/
-- Matrix4x4, they are frame temporaries per CLAUDE.md "Lua Environment").
local Managers        = Managers
local Unit            = Unit
local World           = World
local Color           = Color
local Vector3         = Vector3
local Matrix4x4       = Matrix4x4
local Quaternion      = Quaternion
local Camera          = Camera
local ScriptWorld     = ScriptWorld
local ScriptViewport  = ScriptViewport
local ScriptGUI       = ScriptGUI
local HEALTH_ALIVE    = HEALTH_ALIVE
local Broadphase      = Broadphase

-- Screen gui material: gw_fonts is the engine's always-resident debug-gui
-- material (the #293/#295 fatal was creating with arial/FONT_MTRL, which is NOT
-- a resident create_screen_gui material). Same constant _gt_bot_teleport_lab uses.
local GUI_MTRL = "materials/fonts/gw_fonts"

-- Line widths (screen px at the gui's native resolution) and z-layer.
local LINE_W_BOX  = 2
local LINE_W_RING = 2
local DRAW_LAYER  = 500   -- z within our screen gui; above the 3D world composite

-- Per-category ARGB tuples ({a, r, g, b}, 0-255). Kept as plain-number tables
-- (safe to store); the Color(...) objects are built fresh each frame (Color is a
-- frame temporary). Alphas are high -- thin projected lines need to read clearly.
local COL = {
    interactable = { 235, 235, 210, 40 },   -- moderate yellow (issue #5)
    pickup       = { 235, 130, 255, 130 },   -- light green (issue #1)
    spawner      = { 210, 205, 205, 205 },   -- light grey (issue #1, spawn points)
    enemy        = { 235, 225, 45, 45 },     -- moderate red (issue #3)
    player       = { 235, 45, 190, 45 },     -- dark green (issue #3)
    headshot     = { 245, 255, 140, 0 },     -- orange (issue #3, headshot zone)
    aggro        = { 190, 255, 175, 40 },    -- amber ring (issue #8, aggro range)
}

-- Per-category unit caps -- this runs per frame, so a pathological level (or a
-- 50 m radius in a horde) can't blow the draw budget. Distance culling happens
-- first; caps are the backstop.
local CAP_ENEMY    = 60
local CAP_PICKUP   = 90
local CAP_SPAWNER  = 60
local CAP_INTERACT = 60
local CAP_AGGRO    = 24   -- rings are the most segment-expensive; cap lower

-- Head marker half-size in world metres (a small screen square is drawn at the
-- head node; the true headshot capsule dimensions are NOT exposed to Lua).
local HEAD_HALF = 0.22
-- Aggro-ring segment count (more = rounder, but each segment is a Gui.rect_3d).
local RING_SEGMENTS = 20

-- Static box-edge table: 8 corners indexed 1..8 by (x,y,z) sign bits (bit0=x,
-- bit1=y, bit2=z; 0 -> -extent, 1 -> +extent). The 12 edges join corners that
-- differ in exactly one bit.
local BOX_CORNER_SIGN = {
    { -1, -1, -1 }, {  1, -1, -1 }, { -1,  1, -1 }, {  1,  1, -1 },
    { -1, -1,  1 }, {  1, -1,  1 }, { -1,  1,  1 }, {  1,  1,  1 },
}
local BOX_EDGES = {
    { 1, 2 }, { 3, 4 }, { 5, 6 }, { 7, 8 },   -- along x
    { 1, 3 }, { 2, 4 }, { 5, 7 }, { 6, 8 },   -- along y
    { 1, 5 }, { 2, 6 }, { 3, 7 }, { 4, 8 },   -- along z
}

-- Extension-class names for get_entities (NOT the system name). Pickups come in
-- four flavors (pickup_system.lua:22-28); enumerate all to catch tomes/grimoires.
local PICKUP_EXTS = {
    "PickupUnitExtension",
    "LifeTimePickupUnitExtension",
    "LimitedOwnedPickupUnitExtension",
    "PlayerTeleportingPickupExtension",
}
local INTERACT_EXTS = {
    "GenericUnitInteractableExtension",
    "LocalInteractableExtension",
}
local SPAWNER_EXT = "PickupSpawnerExtension"

-- ----------------------------------------------------------------------------
-- Small helpers
-- ----------------------------------------------------------------------------

-- printf wrapper (format safely, hand a pre-formatted string to printf so a stray
-- `%` can't break the engine format pass). Always-on dev diagnostic, visible with
-- VMF mod-logging OFF -- same shape as _gt_bot_teleport_lab.lua:_pf.
local function _pf(fmt, ...)
    local p = rawget(_G, "printf")
    if not p then return end
    local ok, s = pcall(string.format, fmt, ...)
    if ok then p("%s", s) end
end

local function _local_player_unit()
    -- local_player_safe nil-checks Managers.state.network first (player_manager
    -- .lua:588-596), the vanilla API for the boot/menu phase. BUT it still calls
    -- Network.peer_id() (player_manager.lua:595), which throws "Network backend
    -- has not been set" during the StateLoading window even when :game() is
    -- truthy -- console-2026-07-12-17.56 logged that 929x, aborting the draw
    -- every frame pre-mission. pcall it: a nil player is a clean skip.
    local pm = Managers.player
    if not (pm and pm.local_player_safe) then return nil end
    local ok, p = pcall(pm.local_player_safe, pm)
    return (ok and p) and p.player_unit or nil
end
-- #511/#508 runtime provenance marker: the local-player read is the readiness-
-- guarded local_player_safe (issue 508), now additionally pcall-wrapped for the
-- StateLoading Network.peer_id throw. Set at LOAD so /gt_regression_test asserts
-- it without an io source-grep (the VMF sandbox has no io library).
mod._gt_dh_local_player_safe = true

local function _entities(name)
    local ent = Managers.state and Managers.state.entity
    if not ent then return nil end
    local ok, map = pcall(ent.get_entities, ent, name)
    return ok and map or nil
end

-- Best-effort unit position for distance culling / ring centres. NEVER read
-- POSITION_LOOKUP here: in the update phase the lookup's raw Vector3 entries are
-- DEAD temporaries for any unit the engine hasn't refreshed this section (keep,
-- menu) -- passing one to a Vector3 API throws "Vector3 expected, got userdata"
-- (the issue-337 bug class). Always read the unit live.
local function _unit_pos(unit)
    if Unit.alive(unit) then
        local ok, wp = pcall(Unit.local_position, unit, 0)
        if ok then return wp end
    end
    return nil
end
-- #511 runtime provenance marker: positions in this file are LIVE reads
-- (Unit.local_position), never POSITION_LOOKUP (issue 302/337). Set at LOAD so
-- /gt_regression_test can assert it without an io source-grep.
mod._gt_dh_live_pos_reads = true

local function _breed_of(unit)
    local ok, breed = pcall(Unit.get_data, unit, "breed")
    if ok and type(breed) == "table" then return breed end
    local au = rawget(_G, "AiUtils")
    if au and au.unit_breed then
        local ok2, b2 = pcall(au.unit_breed, unit)
        if ok2 and type(b2) == "table" then return b2 end
    end
    return nil
end

-- Head actor/node name for a breed: the actor of the hit zone whose
-- hitzone_multiplier_types maps to "headshot" (breed_skaven_clan_rat.lua:89-97),
-- falling back to the conventional "head" zone. Cached per breed table.
local _head_actor_cache = setmetatable({}, { __mode = "k" })
local function _head_actor(breed)
    if not breed then return nil end
    local cached = _head_actor_cache[breed]
    if cached ~= nil then return cached or nil end
    local actor = false
    local zones = breed.hit_zones
    local mult  = breed.hitzone_multiplier_types
    if zones and mult then
        for zone_name, mtype in pairs(mult) do
            if mtype == "headshot" then
                local z = zones[zone_name]
                if z and z.actors and z.actors[1] then actor = z.actors[1]; break end
            end
        end
    end
    if not actor and zones and zones.head and zones.head.actors then
        actor = zones.head.actors[1] or false
    end
    _head_actor_cache[breed] = actor
    return actor or nil
end

-- ----------------------------------------------------------------------------
-- Camera + world_to_screen projection
-- ----------------------------------------------------------------------------

-- The local player's level-world camera (single-viewport PC = "player_1"), the
-- same camera the shipped HUD projects with (floating_icon_ui.lua:117-131).
local function _camera(world)
    local cm = Managers.camera
    if not (cm and cm.has_viewport and cm:has_viewport("player_1")) then return nil end
    local ok, cam = pcall(function()
        local vp = ScriptWorld.viewport(world, "player_1")
        return vp and ScriptViewport.camera(vp)
    end)
    return (ok and cam) or nil
end

-- Project a world position to raw screen pixels. Returns (x, y) or nil if the
-- point is behind the camera (world_to_screen wraps to garbage there, so a
-- forward-dot guard is required -- world_marker_ui.lua:359 uses the same test).
local function _project(cam, cam_pos, cam_fwd, wpos)
    -- dir . forward <= 0 => behind the view plane => skip.
    if Vector3.dot(cam_fwd, wpos - cam_pos) <= 0 then return nil end
    local ok, screen = pcall(Camera.world_to_screen, cam, wpos)
    if not ok or not screen then return nil end
    return screen.x, screen.y
end

-- ----------------------------------------------------------------------------
-- Screen-gui lifecycle (world-identity gated -- Gui.* on a destroyed world is a
-- C-level access violation pcall cannot catch, docs/engine/08 section 32 / #459)
-- ----------------------------------------------------------------------------

-- WorldManager.world() FASSERTS on a missing world (world_manager.lua:111-115);
-- probe has_world first (#459).
local function _world()
    local wm = Managers.world
    if not (wm and wm:has_world("level_world")) then return nil end
    return wm:world("level_world")
end

-- Lazily create (and cache) the screen gui, deferring creation until GUI_MTRL is
-- resident (Application.can_get pre-filter) so a momentary non-residency during a
-- keep<->mission world swap DEFERS a frame instead of the #293/#295 CTD. Recreate
-- on world change.
local function _screen_gui(world)
    if mod._gt_dh_gui_world ~= world then
        mod._gt_dh_gui       = nil
        mod._gt_dh_gui_world = world
    end
    if not mod._gt_dh_gui then
        local app = rawget(_G, "Application")
        local ok, resident = pcall(function()
            return app and app.can_get and app.can_get("material", GUI_MTRL)
        end)
        if ok and resident == true then
            mod._gt_dh_gui = World.create_screen_gui(world, "material", GUI_MTRL, "immediate")
        end
    end
    return mod._gt_dh_gui
end

-- Destroy the cached screen gui, gated on the live-world IDENTITY check (#459):
-- destroying/drawing into a freed world is an uncatchable AV, and a NEW same-named
-- world passing has_world does not validate the OLD cached handle. Always null the
-- fields (a destroyed world already freed its guis).
local function _destroy_gui()
    local gui = mod._gt_dh_gui
    local w   = mod._gt_dh_gui_world
    if gui and w then
        local wm   = Managers.world
        local live = wm and wm:has_world("level_world") and wm:world("level_world")
        if live == w then
            pcall(World.destroy_gui, w, gui)
        else
            _pf("[gt:459:DH] skipped screen-gui destroy - cached world is dead")
        end
    end
    mod._gt_dh_gui       = nil
    mod._gt_dh_gui_world = nil
end
-- #511 runtime provenance marker: the DH world-tied resource (now a screen gui,
-- formerly a LineObject) is released under the issue-459 live-world identity gate
-- (live == w). Set at LOAD so /gt_regression_test can assert it without an io
-- source-grep. (Marker name kept for the existing gt_459_lineobject_cleanup check.)
mod._gt459_liveness_gated_dh = true

-- ----------------------------------------------------------------------------
-- Screen draw primitives (all guarded -- husks despawn between enumeration/draw)
-- ----------------------------------------------------------------------------

-- One rotated screen line p1->p2. Returns 1 if drawn.
local function _line(gui, x1, y1, x2, y2, layer, width, color)
    ScriptGUI.hud_line(gui, Vector3(x1, y1, layer), Vector3(x2, y2, layer), layer, width, color)
    return 1
end

-- Project a unit's OOBB (Unit.box) and draw its 12 edges. An edge is skipped if
-- either endpoint is behind the camera (a partial box reads fine and is far
-- clearer than clamping wrapped coordinates). Returns the number of edges drawn.
local _corner_x, _corner_y = {}, {}   -- reused per-call scratch (indices 1..8)
local function _draw_box(gui, cam, cam_pos, cam_fwd, unit, color)
    if not Unit.alive(unit) then return 0 end
    local ok, pose, ext = pcall(Unit.box, unit)
    if not (ok and pose and ext) then return 0 end
    local ex, ey, ez = ext.x, ext.y, ext.z
    for i = 1, 8 do
        local s = BOX_CORNER_SIGN[i]
        local world_corner = Matrix4x4.transform(pose, Vector3(s[1] * ex, s[2] * ey, s[3] * ez))
        local sx, sy = _project(cam, cam_pos, cam_fwd, world_corner)
        _corner_x[i] = sx   -- nil if behind camera
        _corner_y[i] = sy
    end
    local drawn = 0
    for e = 1, 12 do
        local a, b = BOX_EDGES[e][1], BOX_EDGES[e][2]
        local ax, ay, bx, by = _corner_x[a], _corner_y[a], _corner_x[b], _corner_y[b]
        if ax and bx then
            drawn = drawn + _line(gui, ax, ay, bx, by, DRAW_LAYER, LINE_W_BOX, color)
        end
    end
    return drawn
end

-- Small screen square at the enemy head node (issue #3 headshot marker). Returns
-- lines drawn. Sized in WORLD metres (project head +/- HEAD_HALF along camera
-- right/up so the square scales with distance).
local function _draw_head(gui, cam, cam_pos, cam_fwd, cam_right, cam_up, unit, breed, color)
    local actor = _head_actor(breed)
    if not actor or not Unit.alive(unit) or not Unit.has_node(unit, actor) then return 0 end
    local ok, hpos = pcall(function() return Unit.world_position(unit, Unit.node(unit, actor)) end)
    if not (ok and hpos) then return 0 end
    -- Four corners of a camera-facing square around the head.
    local ro = cam_right * HEAD_HALF
    local uo = cam_up * HEAD_HALF
    local c1x, c1y = _project(cam, cam_pos, cam_fwd, hpos - ro + uo)
    local c2x, c2y = _project(cam, cam_pos, cam_fwd, hpos + ro + uo)
    local c3x, c3y = _project(cam, cam_pos, cam_fwd, hpos + ro - uo)
    local c4x, c4y = _project(cam, cam_pos, cam_fwd, hpos - ro - uo)
    if not (c1x and c2x and c3x and c4x) then return 0 end
    local n = 0
    n = n + _line(gui, c1x, c1y, c2x, c2y, DRAW_LAYER, LINE_W_BOX, color)
    n = n + _line(gui, c2x, c2y, c3x, c3y, DRAW_LAYER, LINE_W_BOX, color)
    n = n + _line(gui, c3x, c3y, c4x, c4y, DRAW_LAYER, LINE_W_BOX, color)
    n = n + _line(gui, c4x, c4y, c1x, c1y, DRAW_LAYER, LINE_W_BOX, color)
    return n
end

-- Aggro ring: a horizontal world circle (radius = breed.detection_radius) at the
-- unit's feet, sampled into RING_SEGMENTS points, projected and joined. Segments
-- with a behind-camera endpoint are skipped. Returns lines drawn.
local _ring_x, _ring_y = {}, {}
local function _draw_ring(gui, cam, cam_pos, cam_fwd, center, radius, color)
    if not radius or radius <= 0 then return 0 end
    local two_pi = math.pi * 2
    for i = 1, RING_SEGMENTS do
        local a = two_pi * (i - 1) / RING_SEGMENTS
        local p = center + Vector3(math.cos(a) * radius, math.sin(a) * radius, 0)
        local sx, sy = _project(cam, cam_pos, cam_fwd, p)
        _ring_x[i] = sx
        _ring_y[i] = sy
    end
    local drawn = 0
    for i = 1, RING_SEGMENTS do
        local j = (i % RING_SEGMENTS) + 1
        local ax, ay, bx, by = _ring_x[i], _ring_y[i], _ring_x[j], _ring_y[j]
        if ax and bx then
            drawn = drawn + _line(gui, ax, ay, bx, by, DRAW_LAYER, LINE_W_RING, color)
        end
    end
    return drawn
end

-- ----------------------------------------------------------------------------
-- Enumeration + AI broadphase query
-- ----------------------------------------------------------------------------

-- Reused broadphase result buffer (avoid a per-frame table alloc). Only indices
-- 1..n returned by the query are read, so stale tail entries are harmless.
local _ai_results = {}
local function _query_ai(center, radius)
    local ent = Managers.state and Managers.state.entity
    local ai  = ent and ent:system("ai_system")
    local bp  = ai and ai.broadphase
    if not bp then return 0 end
    local ok, n = pcall(Broadphase.query, bp, center, radius, _ai_results)
    return (ok and n) or 0
end

-- Draw boxes for a set of extension maps, distance-culled + capped. `seen` (when
-- passed) dedupes across categories: pickups populate it, interactables skip it,
-- so an E-key pickup (which carries BOTH extensions) draws once, as a pickup.
-- Returns (units_boxed, edges_drawn).
local function _draw_ext_boxes(gui, cam, cam_pos, cam_fwd, color, ext_names, player_pos, range_sq, cap, seen)
    local units, edges = 0, 0
    for _, name in ipairs(ext_names) do
        if units >= cap then break end
        local ents = _entities(name)
        if ents then
            for unit in pairs(ents) do
                if units >= cap then break end
                if not (seen and seen[unit]) then
                    local pos = _unit_pos(unit)
                    if pos and Vector3.distance_squared(pos, player_pos) <= range_sq then
                        local n = _draw_box(gui, cam, cam_pos, cam_fwd, unit, color)
                        if n > 0 then
                            units = units + 1
                            edges = edges + n
                            if seen then seen[unit] = true end
                        end
                    end
                end
            end
        end
    end
    return units, edges
end

-- ----------------------------------------------------------------------------
-- Draw core
-- ----------------------------------------------------------------------------

local _master_last   = false
local _report_accum  = 0
local _logged_first  = false   -- one-shot projection breadcrumb per session

local function _draw(dt)
    if not IS_DEV_STREAM then return end

    local master = mod:get("gt_debug_highlights") and true or false
    if master ~= _master_last then
        _master_last = master
        _pf("[gt_dev:DH] master %s", master and "ON" or "OFF")
        if not master then _logged_first = false end
    end
    if not master then _destroy_gui(); return end

    local want_interact = mod:get("gt_dh_interactables")    and true or false
    local want_pickups  = mod:get("gt_dh_pickups")          and true or false
    local want_spawners = mod:get("gt_dh_pickup_spawners")  and true or false
    local want_enemies  = mod:get("gt_dh_hitboxes_enemies") and true or false
    local want_players  = mod:get("gt_dh_hitboxes_players") and true or false
    local want_headshot = mod:get("gt_dh_headshot_zones")   and true or false
    local want_aggro    = mod:get("gt_dh_aggro_ranges")     and true or false

    local want_any = want_interact or want_pickups or want_spawners
                  or want_enemies or want_players or want_headshot or want_aggro
    if not want_any then _destroy_gui(); return end

    local world = _world()
    if not world then _destroy_gui(); return end

    local cam = _camera(world)
    if not cam then return end

    -- Live camera basis (fresh temporaries -- never cached).
    local ok_cp, cam_pos = pcall(Camera.world_position, cam)
    local ok_cr, cam_rot = pcall(Camera.world_rotation, cam)
    if not (ok_cp and ok_cr and cam_pos and cam_rot) then return end
    local cam_fwd   = Quaternion.forward(cam_rot)
    local cam_right = Quaternion.right(cam_rot)
    local cam_up    = Quaternion.up(cam_rot)

    -- Player position for distance culling (live read; see _local_player_unit).
    local player_unit = _local_player_unit()
    local player_pos
    if player_unit and Unit.alive(player_unit) then
        local ok, wp = pcall(Unit.world_position, player_unit, 0)
        if ok then player_pos = wp end
    end
    -- No player unit yet (early keep frame): fall back to the camera position so
    -- the distance cull still has an origin.
    player_pos = player_pos or cam_pos

    local gui = _screen_gui(world)
    if not gui then return end   -- material not resident yet; retry next frame

    local range = mod:get("gt_dh_range") or 30
    if type(range) ~= "number" then range = 30 end
    local range_sq = range * range

    local n_interact, n_pickup, n_spawner = 0, 0, 0
    local n_enemy, n_player, n_head, n_aggro = 0, 0, 0, 0
    local edges = 0

    -- Pickups first so they win the dedupe against interactables.
    local seen = (want_pickups and want_interact) and {} or nil

    if want_pickups then
        local col = Color(COL.pickup[1], COL.pickup[2], COL.pickup[3], COL.pickup[4])
        local u, e = _draw_ext_boxes(gui, cam, cam_pos, cam_fwd, col, PICKUP_EXTS, player_pos, range_sq, CAP_PICKUP, seen)
        n_pickup, edges = u, edges + e
    end

    if want_interact then
        local col = Color(COL.interactable[1], COL.interactable[2], COL.interactable[3], COL.interactable[4])
        local u, e = _draw_ext_boxes(gui, cam, cam_pos, cam_fwd, col, INTERACT_EXTS, player_pos, range_sq, CAP_INTERACT, seen)
        n_interact, edges = u, edges + e
    end

    if want_spawners then
        local col = Color(COL.spawner[1], COL.spawner[2], COL.spawner[3], COL.spawner[4])
        local ents = _entities(SPAWNER_EXT)
        if ents then
            for unit in pairs(ents) do
                if n_spawner >= CAP_SPAWNER then break end
                local pos = _unit_pos(unit)
                if pos and Vector3.distance_squared(pos, player_pos) <= range_sq then
                    local n = _draw_box(gui, cam, cam_pos, cam_fwd, unit, col)
                    if n > 0 then n_spawner = n_spawner + 1; edges = edges + n end
                end
            end
        end
    end

    if want_enemies or want_headshot or want_aggro then
        local col_enemy = want_enemies and Color(COL.enemy[1], COL.enemy[2], COL.enemy[3], COL.enemy[4]) or nil
        local col_head  = want_headshot and Color(COL.headshot[1], COL.headshot[2], COL.headshot[3], COL.headshot[4]) or nil
        local col_aggro = want_aggro and Color(COL.aggro[1], COL.aggro[2], COL.aggro[3], COL.aggro[4]) or nil
        local n = _query_ai(player_pos, range)
        for i = 1, n do
            local unit = _ai_results[i]
            if unit and HEALTH_ALIVE[unit] then
                local breed = _breed_of(unit)
                if breed then
                    if col_enemy and n_enemy < CAP_ENEMY then
                        local e = _draw_box(gui, cam, cam_pos, cam_fwd, unit, col_enemy)
                        if e > 0 then n_enemy = n_enemy + 1; edges = edges + e end
                    end
                    if col_head and n_head < CAP_ENEMY then
                        local e = _draw_head(gui, cam, cam_pos, cam_fwd, cam_right, cam_up, unit, breed, col_head)
                        if e > 0 then n_head = n_head + 1; edges = edges + e end
                    end
                    if col_aggro and n_aggro < CAP_AGGRO then
                        local pos = _unit_pos(unit)
                        if pos then
                            local e = _draw_ring(gui, cam, cam_pos, cam_fwd, pos, breed.detection_radius, col_aggro)
                            if e > 0 then n_aggro = n_aggro + 1; edges = edges + e end
                        end
                    end
                end
            end
        end
    end

    if want_players then
        local col = Color(COL.player[1], COL.player[2], COL.player[3], COL.player[4])
        local pm = Managers.player
        local players = pm and pm.human_and_bot_players and pm:human_and_bot_players()
        if players then
            for _, player in pairs(players) do
                local unit = player.player_unit
                if unit and Unit.alive(unit) then
                    local pos = _unit_pos(unit)
                    if pos and Vector3.distance_squared(pos, player_pos) <= range_sq then
                        local e = _draw_box(gui, cam, cam_pos, cam_fwd, unit, col)
                        if e > 0 then n_player = n_player + 1; edges = edges + e end
                    end
                end
            end
        end
    end

    -- One-shot breadcrumb: proves projection produced on-screen coordinates. If
    -- the user sees NOTHING while this logs positive edge counts, the screen gui
    -- is the failure point (not enumeration, not projection).
    if not _logged_first and edges > 0 then
        _logged_first = true
        local rl = rawget(_G, "RESOLUTION_LOOKUP")
        -- Axis-sanity sample: the local player projects near screen centre-bottom.
        -- If sx/sy are wildly off (e.g. one is ~0 or negative while a box is dead
        -- ahead), the screen axis is wrong; if they look like ~half the res, the
        -- projection is correct and any invisibility is the gui not rendering.
        local px, py = _project(cam, cam_pos, cam_fwd, player_pos + Vector3(0, 0, 1))
        _pf("[gt:302] method=world_to_screen: drew %d edges (res %sx%s); player projects to sx=%s sy=%s -- if you see NO overlay, the screen gui is not rendering (not enum/projection)",
            edges,
            rl and tostring(rl.res_w) or "?", rl and tostring(rl.res_h) or "?",
            px and string.format("%.0f", px) or "nil", py and string.format("%.0f", py) or "nil")
    end

    -- One summary line per second MAX (no per-frame spam), always-on in dev.
    _report_accum = _report_accum + (dt or 0.016)
    if _report_accum >= 1.0 then
        _report_accum = 0
        _pf("[gt_dev:DH] drawn range=%dm edges=%d | interact=%d pickups=%d spawners=%d enemies=%d players=%d heads=%d aggro=%d",
            range, edges, n_interact, n_pickup, n_spawner, n_enemy, n_player, n_head, n_aggro)
    end
end

-- ----------------------------------------------------------------------------
-- Invocation: draw from the UI update phase (retail-proven for screen guis).
-- StreamingInfo draws from IngameUI.update; it ticks in BOTH the keep and a
-- mission, which mod.update-phase screen draws do not reliably render from.
-- Rule #8 pre-flight: grep-verified no other gt_dev hook targets
-- (IngameUI, "update") -> singleton. (The existing gt IngameHud.update hook is
-- _gt_melee_warning's; IngameUI.update is a different pair.)
-- ----------------------------------------------------------------------------
local _err_logged = false
mod:hook_safe("IngameUI", "update", function(self, dt, t)
    -- pcall the whole draw: a stray throw must not spam or disturb IngameUI.update
    -- (the old mod.update-consumer registry pcall'd each consumer; a raw hook body
    -- does not). Log the first error only, then stay quiet.
    local ok, err = pcall(_draw, dt)
    if not ok and not _err_logged then
        _err_logged = true
        _pf("[gt:302:DH] draw raised (logged once): %s", tostring(err))
    end
end)

-- Drop the screen gui on mission (re)enter so a stale world handle is never
-- reused (chain-wrap; never redefine the central handler). Same pattern as
-- _gt_bot_teleport_lab.lua.
do
    local prev = mod.on_game_state_changed
    mod.on_game_state_changed = function(status, state_name)
        if prev then prev(status, state_name) end
        -- Release on EXIT (world still alive, docs/engine/08 section 32) and drop
        -- any stale handle on ENTER.
        if state_name == "StateIngame" and (status == "exit" or status == "enter") then
            _destroy_gui()
        end
    end
end

mod:info("[gt:DH] debug highlights loaded (dev=%s, method=world_to_screen)", tostring(IS_DEV_STREAM))
