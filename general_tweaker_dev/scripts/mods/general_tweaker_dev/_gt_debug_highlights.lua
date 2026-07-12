local mod = get_mod("gt_dev")

-- _gt_debug_highlights.lua -- in-world debug wireframe overlay (GitHub #302, phase 1)
--
-- Draws colored LineObject wireframes in the level world for normally-invisible
-- gameplay geometry so a tester can see it: interactables, item pickups, pickup
-- spawn points, enemy/player bounding boxes, approximate headshot nodes, and
-- enemy aggro rings. One shared line object per world, rebuilt + dispatched every
-- frame from mod._gt_register_update("debug_highlights", ...). Everything OFF ==
-- zero work (early-out before any enumeration). WIREFRAME ONLY -- the issue asks
-- for translucent fills too, but filled world-gui triangles are deferred to a
-- later phase (see #302 report / CHANGELOG).
--
-- Draw core / lifecycle copied from _gt_solo_qol.lua's boss-sphere debug draw
-- (lines ~325-340): Managers.world:world("level_world") -> recreate the line
-- object on world change -> World.create_line_object(world, false) ->
-- LineObject.reset -> add primitives -> LineObject.dispatch(world, lo). Same
-- pattern _gt_bot_teleport_lab.lua uses for its leash lines.
--
-- CLIENT/HOST: every shipped category is client-safe. Interactables / pickups /
-- pickup-spawners enumerate via Managers.state.entity:get_entities(<ExtName>)
-- which is populated per-peer (entity_manager2.lua:56-58, :272). Enemies come
-- from the ai_system broadphase (ai_system.lua:94 self.broadphase, populated on
-- every peer as husks register), players from Managers.player:human_and_bot_players().
-- No category reads host-only state, so no host gating is needed this round.
-- (Deferred categories navmesh / monster-spawn-triggers ARE host-only -- see report.)
--
-- Engine primitives (verified in the decompiled source):
--   LineObject.add_box(lo, color, pose, extents)      debug_drawer.lua:102 (native OOBB)
--   LineObject.add_sphere(lo, color, center, radius)  debug_drawer.lua:27
--   LineObject.add_circle(lo, color, center, r, norm) debug_drawer.lua:114
--   Unit.box(unit) -> pose(Matrix4x4), half_extents(Vector3)  interactable_system.lua:37
--   Color(a, r, g, b) is ARGB 0-255                    imgui_physgun.lua:428
--   breed.detection_radius (static)                    breed_skaven_clan_rat.lua:18
--   breed.hit_zones[zone].actors[1] head node          breed_skaven_clan_rat.lua:92-97
--
-- Owned by: general_tweaker_dev.lua entry point. Consumed via: mod:dofile.

-- Dev-only gate (survives the dev->stable sed of the literal `gt_dev`; same idiom
-- as _gt_bot_teleport_lab.lua / the Dev Tools data group). In the stable clone
-- get_mod("gt".."_dev") -> nil, so the whole feature is inert there.
local IS_DEV_STREAM = (mod == get_mod("gt" .. "_dev"))

-- Global aliases (booleans/tables/functions only -- NEVER cache Vector3/Color,
-- they are frame temporaries per CLAUDE.md "Lua Environment").
local Managers        = Managers
local Unit            = Unit
local World           = World
local LineObject      = LineObject
local Color           = Color
local Vector3         = Vector3
local HEALTH_ALIVE    = HEALTH_ALIVE
local Broadphase      = Broadphase

-- Per-category ARGB tuples ({a, r, g, b}, 0-255). Kept as plain-number tables
-- (safe to store); the Color(...) objects are built fresh each frame in _draw
-- (Color is a frame temporary). Alphas kept readable but below opaque to reduce
-- clutter when several categories are on at once.
local COL = {
    interactable = { 210, 235, 210, 40 },   -- moderate yellow (issue #5)
    pickup       = { 200, 130, 255, 130 },   -- light green (issue #1)
    spawner      = { 170, 205, 205, 205 },   -- light grey (issue #1, spawn points)
    enemy        = { 205, 225, 45, 45 },     -- moderate red (issue #3)
    player       = { 210, 45, 150, 45 },     -- dark green (issue #3)
    headshot     = { 225, 255, 140, 0 },     -- orange (issue #3, headshot zone)
    aggro        = { 130, 255, 175, 40 },    -- amber ring (issue #8, aggro range)
}

-- Per-category unit caps -- this runs per frame, so a pathological level (or a
-- 50 m radius in a horde) can't blow the draw budget. Distance culling happens
-- first; caps are the backstop.
local CAP_ENEMY       = 60
local CAP_PICKUP      = 90
local CAP_SPAWNER     = 60
local CAP_INTERACT    = 60
-- Approximate headshot sphere radius (m). True hit-zone capsule dimensions are
-- NOT exposed to Lua (only the actor NODE position is) -- this proxy is ~ the
-- clan-rat ragdoll_actor_thickness head value (breed_skaven_clan_rat.lua:~236).
local HEADSHOT_RADIUS = 0.28

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
    -- local_player() routes straight to Network.peer_id() with no readiness
    -- guard (player_manager.lua:580-586) and asserts "Network backend has not
    -- been set" in the boot/menu phase -- this file runs as a mod.update
    -- consumer, which ticks there too (issue 508: 60/s error spam at load).
    -- local_player_safe (player_manager.lua:588-596) nil-checks
    -- Managers.state.network first; it is the vanilla API for this timing.
    local pm = Managers.player
    if not (pm and pm.local_player_safe) then return nil end
    local p = pm:local_player_safe()
    return p and p.player_unit
end
-- #511 runtime provenance marker: the local-player read above uses the readiness-
-- guarded local_player_safe (issue 508), set at LOAD so /gt_regression_test can
-- assert it without an io source-grep (the VMF sandbox has no io library). The
-- textual "no bare :local_player() in this file" invariant belongs in a repo QA
-- gate (PROJECT_STANDARDS 2.2b tier a); this positive flag is the in-game half.
mod._gt_dh_local_player_safe = true

local function _entities(name)
    local ent = Managers.state and Managers.state.entity
    if not ent then return nil end
    local ok, map = pcall(ent.get_entities, ent, name)
    return ok and map or nil
end

-- Best-effort unit position for distance culling. NEVER read POSITION_LOOKUP
-- here: this file runs as a mod.update consumer, and in that phase the lookup's
-- raw Vector3 entries are DEAD temporaries for any unit the engine hasn't
-- refreshed this section (keep, menu, chat phase) -- passing one to a Vector3
-- API throws "Vector3 expected, got userdata" (the issue-337 bug class that
-- already bit the local-player read below; 3031-error spam 2026-07-06 when the
-- highlights first went live in the keep). Always read the unit live.
local function _unit_pos(unit)
    if Unit.alive(unit) then
        local ok, wp = pcall(Unit.local_position, unit, 0)
        if ok then return wp end
    end
    return nil
end
-- #511 runtime provenance marker: positions in this file are LIVE reads
-- (Unit.local_position), never POSITION_LOOKUP (dead temporaries in mod.update,
-- issue 302/337). Set at LOAD so /gt_regression_test can assert it without an io
-- source-grep. The textual "no POSITION_LOOKUP index in this file" invariant
-- belongs in a repo QA gate (PROJECT_STANDARDS 2.2b tier a); this is the in-game half.
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
-- Draw primitives (all guarded -- husks despawn between enumeration and draw)
-- ----------------------------------------------------------------------------

local function _add_unit_box(lo, color, unit)
    if not Unit.alive(unit) then return false end
    local ok, pose, ext = pcall(Unit.box, unit)
    if ok and pose and ext then
        LineObject.add_box(lo, color, pose, ext)
        return true
    end
    return false
end

local function _add_head_sphere(lo, color, unit, breed)
    local actor = _head_actor(breed)
    if not actor or not Unit.alive(unit) or not Unit.has_node(unit, actor) then return false end
    local ok, pos = pcall(function()
        return Unit.world_position(unit, Unit.node(unit, actor))
    end)
    if ok and pos then
        LineObject.add_sphere(lo, color, pos, HEADSHOT_RADIUS)
        return true
    end
    return false
end

local function _add_aggro_circle(lo, color, unit, breed, up)
    local r = breed and breed.detection_radius
    if not r or r <= 0 then return false end
    local pos = _unit_pos(unit)   -- live read; POSITION_LOOKUP is dead in mod.update
    if not pos then return false end
    LineObject.add_circle(lo, color, pos, r, up)
    return true
end

-- ----------------------------------------------------------------------------
-- Draw core / lifecycle
-- ----------------------------------------------------------------------------

-- WorldManager.world() FASSERTS on a missing world (world_manager.lua:111-115);
-- probe has_world first (#459) -- _draw runs from mods_update, which keeps
-- ticking between game states where level_world does not exist.
local function _world()
    local wm = Managers.world
    if not (wm and wm:has_world("level_world")) then return nil end
    return wm:world("level_world")
end

local function _line_object(world)
    if mod._gt_dh_line_world ~= world then
        mod._gt_dh_line_object = nil
        mod._gt_dh_line_world  = world
    end
    if not mod._gt_dh_line_object then
        mod._gt_dh_line_object = World.create_line_object(world, false)
    end
    return mod._gt_dh_line_object
end

-- Erase any lingering lines and drop the cached handle (idempotent: safe to call
-- every off-frame). Mirrors _gt_bot_teleport_lab.lua:_clear_and_null, including
-- the #459 world-liveness IDENTITY gate: reset/dispatch into a destroyed world is
-- a C-level access violation that pcall cannot catch (StateIngame.on_exit tears
-- the level world down while mods_update keeps ticking), and a NEW same-named
-- world passing has_world does not validate the OLD cached handle. Nulling the
-- fields is always correct: a destroyed world already freed its line objects.
local function _clear()
    local lo = mod._gt_dh_line_object
    local w  = mod._gt_dh_line_world
    if lo and w then
        local wm   = Managers.world
        local live = wm and wm:has_world("level_world") and wm:world("level_world")
        if live == w then
            pcall(function()
                LineObject.reset(lo)
                LineObject.dispatch(w, lo)
            end)
        else
            -- Fires at most once per teardown: the fields are nulled below.
            _pf("[gt:459:DH] skipped LineObject cleanup - cached world is dead")
        end
    end
    mod._gt_dh_line_object = nil
    mod._gt_dh_line_world  = nil
end
-- #511 runtime provenance marker: _clear gates its LineObject reset/dispatch on
-- the live-world identity check (live == w, issue 459 AV guard). Set at LOAD so
-- /gt_regression_test can assert it without an io source-grep (io is nil in the VMF
-- sandbox). The exact "live == w" SOURCE-TEXT belongs in a repo QA gate
-- (PROJECT_STANDARDS 2.2b tier a).
mod._gt459_liveness_gated_dh = true

local _master_last  = false
local _report_accum = 0

-- Draw boxes for a set of extension maps, distance-culled + capped. `seen` (when
-- passed) dedupes across categories: pickups populate it, interactables skip it,
-- so an E-key pickup (which carries BOTH extensions) draws once, as a pickup.
local function _draw_ext_boxes(lo, color, ext_names, player_pos, range_sq, cap, seen)
    local drawn = 0
    for _, name in ipairs(ext_names) do
        if drawn >= cap then break end
        local ents = _entities(name)
        if ents then
            for unit in pairs(ents) do
                if drawn >= cap then break end
                if not (seen and seen[unit]) then
                    local pos = _unit_pos(unit)
                    if pos and Vector3.distance_squared(pos, player_pos) <= range_sq then
                        if _add_unit_box(lo, color, unit) then
                            drawn = drawn + 1
                            if seen then seen[unit] = true end
                        end
                    end
                end
            end
        end
    end
    return drawn
end

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

local function _draw(dt)
    if not IS_DEV_STREAM then return end

    local master = mod:get("gt_debug_highlights") and true or false
    if master ~= _master_last then
        _master_last = master
        _pf("[gt_dev:DH] master %s", master and "ON" or "OFF")
    end
    if not master then _clear(); return end

    local want_interact = mod:get("gt_dh_interactables")   and true or false
    local want_pickups  = mod:get("gt_dh_pickups")         and true or false
    local want_spawners = mod:get("gt_dh_pickup_spawners") and true or false
    local want_enemies  = mod:get("gt_dh_hitboxes_enemies") and true or false
    local want_players  = mod:get("gt_dh_hitboxes_players") and true or false
    local want_headshot = mod:get("gt_dh_headshot_zones")  and true or false
    local want_aggro    = mod:get("gt_dh_aggro_ranges")    and true or false

    local want_any = want_interact or want_pickups or want_spawners
                  or want_enemies or want_players or want_headshot or want_aggro
    if not want_any then _clear(); return end

    local player_unit = _local_player_unit()
    -- DO NOT read POSITION_LOOKUP[player_unit] here: for the LOCAL PLAYER that entry
    -- is a DEAD frame-pool Vector3 handle in this (mod.update) phase. AI/pickup
    -- entries are refreshed every frame by their own systems (ai_slot/aggro/spawner),
    -- but the player's is seeded once at spawn and never refreshed in Lua
    -- (PositionLookupSystem.update is a no-op). The stale userdata fed
    -- Vector3.distance_squared as arg#2 and raised "bad argument #2 (Vector3
    -- expected, got userdata)" every frame -- 1182x in console-2026-07-05-17.19.28,
    -- which also aborted the draw so NOTHING rendered. Same POSITION_LOOKUP-stale
    -- class as the #337 recall crash. Read a LIVE position off the unit instead
    -- (valid for the whole synchronous _draw frame, same as `up` below).
    local player_pos = nil
    if player_unit and Unit.alive(player_unit) then
        local ok, wp = pcall(Unit.world_position, player_unit, 0)
        if ok then player_pos = wp end
    end
    if not player_pos then _clear(); return end

    local world = _world()
    if not world then _clear(); return end
    local lo = _line_object(world)
    if not lo then return end
    LineObject.reset(lo)

    local range    = mod:get("gt_dh_range") or 30
    if type(range) ~= "number" then range = 30 end
    local range_sq = range * range
    local up       = Vector3(0, 0, 1)   -- fresh each frame (Vector3 is a temporary)

    local n_interact, n_pickup, n_spawner = 0, 0, 0
    local n_enemy, n_player, n_head, n_aggro = 0, 0, 0, 0

    -- Pickups first so they win the dedupe against interactables.
    local seen = (want_pickups and want_interact) and {} or nil

    if want_pickups then
        local col = Color(COL.pickup[1], COL.pickup[2], COL.pickup[3], COL.pickup[4])
        n_pickup = _draw_ext_boxes(lo, col, PICKUP_EXTS, player_pos, range_sq, CAP_PICKUP, seen)
    end

    if want_interact then
        local col = Color(COL.interactable[1], COL.interactable[2], COL.interactable[3], COL.interactable[4])
        n_interact = _draw_ext_boxes(lo, col, INTERACT_EXTS, player_pos, range_sq, CAP_INTERACT, seen)
    end

    if want_spawners then
        local col = Color(COL.spawner[1], COL.spawner[2], COL.spawner[3], COL.spawner[4])
        local ents = _entities(SPAWNER_EXT)
        if ents then
            for unit in pairs(ents) do
                if n_spawner >= CAP_SPAWNER then break end
                if Unit.alive(unit) then
                    local pos = _unit_pos(unit)
                    if pos and Vector3.distance_squared(pos, player_pos) <= range_sq then
                        if _add_unit_box(lo, col, unit) then n_spawner = n_spawner + 1 end
                    end
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
                    if col_enemy and n_enemy < CAP_ENEMY and _add_unit_box(lo, col_enemy, unit) then
                        n_enemy = n_enemy + 1
                    end
                    if col_head and n_head < CAP_ENEMY and _add_head_sphere(lo, col_head, unit, breed) then
                        n_head = n_head + 1
                    end
                    if col_aggro and n_aggro < CAP_ENEMY and _add_aggro_circle(lo, col_aggro, unit, breed, up) then
                        n_aggro = n_aggro + 1
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
                    local pos = _unit_pos(unit)   -- live read; POSITION_LOOKUP is dead in mod.update
                    if pos and Vector3.distance_squared(pos, player_pos) <= range_sq then
                        if _add_unit_box(lo, col, unit) then n_player = n_player + 1 end
                    end
                end
            end
        end
    end

    LineObject.dispatch(world, lo)

    -- One summary line per second MAX (no per-frame spam), always-on in dev.
    _report_accum = _report_accum + (dt or 0)
    if _report_accum >= 1.0 then
        _report_accum = 0
        _pf("[gt_dev:DH] drawn range=%dm interact=%d pickups=%d spawners=%d enemies=%d players=%d headshots=%d aggro=%d",
            range, n_interact, n_pickup, n_spawner, n_enemy, n_player, n_head, n_aggro)
    end
end

if mod._gt_register_update then
    mod._gt_register_update("debug_highlights", _draw)
end

-- Drop the cached draw resources on mission (re)enter so a stale world handle is
-- never reused (chain-wrap; never redefine the central handler). Same pattern as
-- _gt_bot_teleport_lab.lua.
do
    local prev = mod.on_game_state_changed
    mod.on_game_state_changed = function(status, state_name)
        if prev then prev(status, state_name) end
        if status == "enter" and state_name == "StateIngame" then
            _clear()
        end
    end
end

mod:info("[gt:DH] debug highlights loaded (dev=%s)", tostring(IS_DEV_STREAM))
