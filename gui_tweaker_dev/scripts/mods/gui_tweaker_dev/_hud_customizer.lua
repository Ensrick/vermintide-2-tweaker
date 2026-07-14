local mod = get_mod("gut_dev")

local CustomizerModule = {}

-- v0.2.5+ debug telemetry. gui_tweaker.lua owns the two-channel _dbg / _dbg_alert
-- helpers (PROJECT_STANDARDS § 3.6); we receive references via init_dbg(...).
-- Default to no-ops so the module is safe to require before init.
local _dbg = function() end
local _dbg_alert = function() end

function CustomizerModule.init_dbg(dbg, dbg_alert)
    if type(dbg) == "function" then _dbg = dbg end
    if type(dbg_alert) == "function" then _dbg_alert = dbg_alert end
end

-- 20x18 absolute floor matches the smallest vanilla widget (pet-count enumerator
-- at pet_ui_definitions.lua:226); the per-entry min_size is recomputed below as
-- max(absolute_floor, vanilla_size * 0.5) so future resize work has a sane bound.
local ABS_MIN_W, ABS_MIN_H = 20, 18

-- Each entry keeps the scenegraph mutation target separate from the node whose
-- world-space rectangle is rendered and hit-tested. This mirrors vanilla
-- HudCustomizer.run's root_scenegraph_id / drag_scenegraph_id contract
-- (scripts/ui/hud_ui/hud_customizer.lua:43-47, 110-122). nominal_size is only a
-- fallback for a missing/zero-sized drag node. definitions_file is documentation.
local REGISTRY = {
    { id = "ability_ui",          class_name = "AbilityUI",          scenegraph_node_id = "ability_root",      drag_scenegraph_node_id = "ability_root",    definitions_file = "scripts/ui/hud_ui/ability_ui_definitions.lua",          vanilla_position = {   0,    0, 10 }, vanilla_size = { 624,  66 }, nominal_size = { 624,  66 }, can_resize_axes = { x = true,  y = false } },
    { id = "equipment_ui",        class_name = "EquipmentUI",        scenegraph_node_id = "pivot",             drag_scenegraph_node_id = "background_panel",definitions_file = "scripts/ui/hud_ui/equipment_ui_definitions.lua",        vanilla_position = {   0,   69,  4 }, vanilla_size = { 300,  60 }, nominal_size = { 300,  60 }, can_resize_axes = { x = false, y = false } },
    { id = "overcharge_bar",      class_name = "OverchargeBarUI",    scenegraph_node_id = "charge_bar",       definitions_file = "scripts/ui/hud_ui/overcharge_bar_ui_definitions.lua",    vanilla_position = {   0, -220,  1 }, vanilla_size = { 250,  16 }, nominal_size = { 250,  16 }, can_resize_axes = { x = true,  y = false } },
    { id = "career_ability_bar",  class_name = "CareerAbilityBarUI", scenegraph_node_id = "ability_bar",      definitions_file = "scripts/ui/hud_ui/career_ability_bar_ui_definitions.lua",vanilla_position = {   0, -200,  1 }, vanilla_size = { 250,  16 }, nominal_size = { 250,  16 }, can_resize_axes = { x = true,  y = false } },
    { id = "energy_bar",          class_name = "EnergyBarUI",        scenegraph_node_id = "charge_bar",       definitions_file = "scripts/ui/hud_ui/energy_bar_ui_definitions.lua",        vanilla_position = {   0, -220,  1 }, vanilla_size = { 250,  16 }, nominal_size = { 250,  16 }, can_resize_axes = { x = true,  y = false } },
    { id = "buff_ui",             class_name = "BuffUI",             scenegraph_node_id = "pivot_root",        drag_scenegraph_node_id = "pivot_dragger",   definitions_file = "scripts/ui/hud_ui/buff_ui_definitions.lua",              vanilla_position = { 150,   18,  1 }, vanilla_size = { 300,  66 }, nominal_size = { 300,  66 }, can_resize_axes = { x = false, y = false } },
    { id = "boss_health",         class_name = "BossHealthUI",       scenegraph_node_id = "pivot_parent",      drag_scenegraph_node_id = "pivot_dragger",   definitions_file = "scripts/ui/hud_ui/boss_health_ui_definitions.lua",       vanilla_position = {   0,  -72,  0 }, vanilla_size = { 500,  70 }, nominal_size = { 500,  70 }, can_resize_axes = { x = false, y = false } },
    { id = "challenge_tracker",   class_name = "ChallengeTrackerUI", scenegraph_node_id = "pivot",             drag_scenegraph_node_id = "quest",           definitions_file = "scripts/ui/hud_ui/challenge_tracker_ui_definitions.lua", vanilla_position = {   1,  155,  0 }, vanilla_size = { 260,  75 }, nominal_size = { 260,  75 }, can_resize_axes = { x = false, y = false } },
    { id = "loot_objective",      class_name = "LootObjectiveUI",    scenegraph_node_id = "background_parent", drag_scenegraph_node_id = "background",      definitions_file = "scripts/ui/hud_ui/loot_objective_ui_definitions.lua",    vanilla_position = {-200, -100,  1 }, vanilla_size = { 383,  86 }, nominal_size = { 383,  86 }, can_resize_axes = { x = false, y = false } },
    { id = "news_feed",           class_name = "NewsFeedUI",         scenegraph_node_id = "pivot",             drag_scenegraph_node_id = "news_pivot_1",    definitions_file = "scripts/ui/hud_ui/news_feed_ui_definitions.lua",         vanilla_position = { -20, -300,  1 }, vanilla_size = { 420, 120 }, nominal_size = { 420, 120 }, can_resize_axes = { x = false, y = false } },
}

-- Bars already mutate their rendered, positive-size node, so make that identity
-- explicit too; callers never need to guess based on node size.
for i = 1, #REGISTRY do
    local entry = REGISTRY[i]
    entry.drag_scenegraph_node_id = entry.drag_scenegraph_node_id or entry.scenegraph_node_id
end

-- Compute min_size per entry from the absolute floor + 50% of vanilla_size, so
-- future resize work has a per-widget bound; v0.2.0 never actually reads this.
for i = 1, #REGISTRY do
    local v = REGISTRY[i].vanilla_size
    REGISTRY[i].min_size = { math.max(ABS_MIN_W, v[1] * 0.5), math.max(ABS_MIN_H, v[2] * 0.5) }
end

CustomizerModule.REGISTRY = REGISTRY

-- (#310) Displayable HUD area, expressed in the SAME reference space as the cursor
-- (UIInverseScaleVectorToResolution) and node.world_position. ui_scenegraph.lua:210-213
-- + the root/`fit` branches (:236-246) put that space at [0 .. res_w*inv_scale] x
-- [0 .. res_h*inv_scale] -- i.e. 1920x1080 at 1080p, scaled proportionally at other
-- resolutions. nil-safe -> 1080p default so a missing RESOLUTION_LOOKUP never traps a drag.
function CustomizerModule.hud_bounds()
    local r = rawget(_G, "RESOLUTION_LOOKUP")
    local inv = (r and r.inv_scale) or 1
    local w = (r and r.res_w) or 1920
    local h = (r and r.res_h) or 1080
    return { min_x = 0, min_y = 0, max_x = w * inv, max_y = h * inv }
end

-- (#310) Confine a proposed drag delta so the element's box [world, world+size] stays
-- inside `bounds` (the displayable HUD area). world_x/y + size describe the element's
-- LIVE box this frame; applied_dx/dy is the delta already applied (last frame), which
-- lets us map delta-space onto world-space 1:1 (a delta change shifts world_position by
-- the same amount, since the parent chain is fixed). Returns the clamped delta. Pure +
-- unit-tested (`hud_confine_delta_clamps`). If the element is WIDER/TALLER than the area
-- on an axis, that axis is left unclamped so an oversize element is never trapped.
function CustomizerModule.confine_delta(world_x, world_y, size_x, size_y, applied_dx, applied_dy, dx, dy, bounds)
    local wx = world_x + (dx - applied_dx)
    local wy = world_y + (dy - applied_dy)
    local max_x = bounds.max_x - (size_x or 0)
    local max_y = bounds.max_y - (size_y or 0)
    if max_x >= bounds.min_x then
        if wx < bounds.min_x then wx = bounds.min_x elseif wx > max_x then wx = max_x end
    end
    if max_y >= bounds.min_y then
        if wy < bounds.min_y then wy = bounds.min_y elseif wy > max_y then wy = max_y end
    end
    return wx - world_x + applied_dx, wy - world_y + applied_dy
end

-- O(1) lookup by widget id (used by drag/apply/reset/list).
local REGISTRY_BY_ID = {}
for i = 1, #REGISTRY do REGISTRY_BY_ID[REGISTRY[i].id] = REGISTRY[i] end
CustomizerModule.REGISTRY_BY_ID = REGISTRY_BY_ID

-- (#310) HUD classes are not consistent about scenegraph visibility. Most of the
-- original classes expose `ui_scenegraph`, but CareerAbilityBarUI stores the same
-- live table as `_ui_scenegraph` (career_ability_bar_ui.lua:101).
function CustomizerModule.scenegraph_for_view(view)
    if type(view) ~= "table" then return nil, "missing_view" end
    if type(view.ui_scenegraph) == "table" then return view.ui_scenegraph, "ui_scenegraph" end
    if type(view._ui_scenegraph) == "table" then return view._ui_scenegraph, "_ui_scenegraph" end
    return nil, "missing_scenegraph"
end

-- Pure coverage classifier used by the bounded live #310 probe and offline tests.
function CustomizerModule.coverage_status(view, entry)
    if type(entry) ~= "table" then return "missing_entry", "none" end
    local scenegraph, source = CustomizerModule.scenegraph_for_view(view)
    if not scenegraph then return source, source end
    local move = scenegraph[entry.scenegraph_node_id]
    if not move then return "missing_move_node", source end
    local drag_id = entry.drag_scenegraph_node_id or entry.scenegraph_node_id
    local drag = scenegraph[drag_id]
    if not drag and drag_id ~= entry.scenegraph_node_id then
        return "move_fallback", source
    end
    if not drag then return "missing_drag_node", source end
    local size = drag.size
    if not (size and tonumber(size[1]) and tonumber(size[1]) > 0
            and tonumber(size[2]) and tonumber(size[2]) > 0) then
        return "nominal_size_fallback", source
    end
    return "ready", source
end

-- Resolve the rectangle used by hit testing, confinement, and overlay drawing.
-- The movement node remains entry.scenegraph_node_id. Missing dynamic nodes (for
-- example an empty news feed) fall back safely to the movement node + nominal size.
-- Exported as an engine-free seam for issue #547 regression coverage.
function CustomizerModule.drag_geometry(scenegraph, entry)
    if type(scenegraph) ~= "table" or type(entry) ~= "table" then return nil end
    local drag_id = entry.drag_scenegraph_node_id or entry.scenegraph_node_id
    local node = scenegraph[drag_id] or scenegraph[entry.scenegraph_node_id]
    if not node or not node.world_position then return nil end
    local size = node.size
    if not (size and size[1] and size[1] > 0 and size[2] and size[2] > 0) then
        size = entry.nominal_size or { 0, 0 }
    end
    return node, size, drag_id
end

-- internal state
local _edit_mode_sticky = false
local _edit_mode_alt = false
local _was_edit_mode = false
local _drag_active = nil
local _drag_hover = nil
local _drag_base = { 0, 0 }
local _drag_start_offset = nil
local _offsets_cache = {}
local _resolution_key = nil
local _live_views = {}
local _coverage_probe_emitted = false

-- "1920x1080" from current resolution; nil-safe if RESOLUTION_LOOKUP is missing.
local function _resolution_key_now()
    local r = rawget(_G, "RESOLUTION_LOOKUP")
    if not r or not r.res_w or not r.res_h then return "0x0" end
    return string.format("%dx%d", r.res_w, r.res_h)
end

-- Read mod:get("hud_offsets") and lift the current resolution's bucket into the
-- _offsets_cache. Defaults to empty when none exists.
local function _load_offsets_for_resolution()
    _resolution_key = _resolution_key_now()
    local all = mod:get("hud_offsets") or {}
    _offsets_cache = all[_resolution_key] or {}
    -- _dbg: offsets_load
    local n = 0
    for _ in pairs(_offsets_cache) do n = n + 1 end
    pcall(_dbg, "[gui_tweaker] offsets_load: resolution=%s widgets_found=%d", tostring(_resolution_key), n)
end

-- Write _offsets_cache back to the persistent mod:set("hud_offsets") table
-- under the current resolution key.
local function _save_offsets()
    local all = mod:get("hud_offsets") or {}
    all[_resolution_key] = _offsets_cache
    mod:set("hud_offsets", all)
    -- _dbg: offsets_save
    local n = 0
    for _ in pairs(_offsets_cache) do n = n + 1 end
    pcall(_dbg, "[gui_tweaker] offsets_save: resolution=%s widgets_with_offsets=%d", tostring(_resolution_key), n)
end

-- Return {dx, dy} for widget_id (defaulting to {0, 0} when unset).
local function _get_widget_offset(widget_id)
    local entry = _offsets_cache[widget_id]
    if entry and entry.offset then return entry.offset[1], entry.offset[2] end
    return 0, 0
end

-- Write {dx, dy} into the cache (does not persist; caller decides when).
local function _set_widget_offset(widget_id, dx, dy)
    _offsets_cache[widget_id] = { offset = { dx, dy } }
end

-- Resolve the absolute local_position for widget_id given a pure drag delta.
-- audit 2026-06-07 (v0.2.8-dev, F5): the math is baseline + delta. Vanilla
-- HudCustomizer.run (hud_customizer.lua:119-122) assigns the RAW offset because
-- the nodes it customizes baseline at {0,0} and its offset_registry IS that
-- node's local_position. Our registry targets real HUD widget nodes whose
-- vanilla baselines are non-zero (equipment_ui pivot {0,69}, buff_ui pivot_root
-- {150,18}, boss_health pivot_parent {0,-72}, etc.), so a raw write zeroed the
-- baseline and snapped the widget to screen origin on the first drag. Exposed on
-- the module so the regression test can assert the math without a live scenegraph.
function CustomizerModule.local_position_for(widget_id, dx, dy)
    local entry = REGISTRY_BY_ID[widget_id]
    local base = entry and entry.vanilla_position
    local bx = (base and base[1]) or 0
    local by = (base and base[2]) or 0
    return bx + (dx or 0), by + (dy or 0)
end

-- Mutate the saved offset INTO the widget's scenegraph node local_position.
-- Writes baseline + pure delta (see local_position_for above); the baseline is
-- the registry entry's vanilla_position, the same field reset_widget restores to.
-- No-op when offset is {0, 0} unless forced; safe under pcall against missing nodes.
--
-- (#312) UI Tweaks ownership: when the standalone UI Tweaks mod (HideBuffs) owns
-- this element (sync on + HB enabled), IT writes the element's own node/offset every
-- frame. gut must contribute nothing, so pin gut's node to the vanilla baseline --
-- this both zeros gut's own contribution and clears any residual gut offset so the
-- two can't stack. See _gut_uitweaks_sync.lua for the element map + verification.
local function _apply_offset_to_scenegraph(view, node_id, widget_id, force)
    local scenegraph = CustomizerModule.scenegraph_for_view(view)
    if not scenegraph then return end
    local node = scenegraph[node_id]
    if not node or not node.local_position then return end
    local sync = mod._gut_uitweaks_sync
    if sync and sync.is_owned and sync.is_owned(widget_id) then
        local bx, by = CustomizerModule.local_position_for(widget_id, 0, 0)
        node.local_position[1] = bx
        node.local_position[2] = by
        return
    end
    local dx, dy = _get_widget_offset(widget_id)
    if not force and dx == 0 and dy == 0 then return end
    local lx, ly = CustomizerModule.local_position_for(widget_id, dx, dy)
    node.local_position[1] = lx
    node.local_position[2] = ly
end

-- Re-apply every registered widget's offset against every live view we have
-- (called each frame while in edit mode so drag updates feel immediate).
local function _reapply_all_offsets()
    for i = 1, #REGISTRY do
        local entry = REGISTRY[i]
        local view = _live_views[entry.class_name]
        if view then
            local ok = pcall(_apply_offset_to_scenegraph, view, entry.scenegraph_node_id, entry.id, true)
            if not ok then end
        end
    end
end

-- True when EITHER the sticky toggle OR the held-LEFT-ALT-while-chat-focused
-- gesture is active. Mirrors vanilla HudCustomizer.is_active (line 23) for
-- the alt-path, with an added sticky-toggle path for accessibility.
function CustomizerModule.is_edit_mode()
    return _edit_mode_sticky or _edit_mode_alt
end

-- (#310) Cutscene-owns-input probe (mirror of _gut_camera's _gut_cutscene_owns_camera):
-- cutscene skip runs on a SEPARATE input service, so suspending PlayerInputExtension
-- during a cutscene is both pointless and explicitly excluded by the mode's safety
-- contract. pcall-guarded end to end (a nil entity manager in a menu returns false).
local function _cutscene_active()
    local mgr_state = Managers and Managers.state
    local entity_mgr = mgr_state and mgr_state.entity
    if not entity_mgr then return false end
    local ok, cs = pcall(entity_mgr.system, entity_mgr, "cutscene_system")
    if not ok or not cs then return false end
    local ok2, active = pcall(cs.is_active, cs)
    return ok2 and active or false
end

-- (#310) Whether HUD edit mode should suspend LOCAL gameplay input right now. The
-- freecam PlayerInputExtension.is_input_blocked hook consults this (VMF drops a 2nd hook
-- on that pair, so the edit-mode block is CONSOLIDATED into freecam's sole hook) to
-- freeze the character + camera while edit mode is active, so the mouse drives the HUD
-- editor rather than aiming/turning. Excludes cutscenes; edit-mode-gated (short-circuits
-- before the cutscene probe when not editing, so it is cheap and menu-safe).
function CustomizerModule.should_suspend_input()
    return CustomizerModule.is_edit_mode() and not _cutscene_active()
end

-- Flip the sticky toggle and (de)assert the cursor visibility stack reason.
function CustomizerModule.set_sticky(enabled)
    local prev = _edit_mode_sticky
    _edit_mode_sticky = enabled and true or false
    if prev ~= _edit_mode_sticky then
        -- _dbg: edit_mode (sticky transition)
        pcall(_dbg, "[gui_tweaker] edit_mode: sticky=%s alt=%s effective=%s resolution=%s",
            tostring(_edit_mode_sticky), tostring(_edit_mode_alt),
            tostring(CustomizerModule.is_edit_mode()), tostring(_resolution_key or _resolution_key_now()))
    end
end

-- (#310) Emit one bounded inventory per edit-mode entry. Ten registry rows plus
-- one summary identify absent views, graph spelling, and node/size readiness.
local function _emit_coverage_probe()
    if _coverage_probe_emitted then return end
    _coverage_probe_emitted = true
    local ready, fallback, missing = 0, 0, 0
    for i = 1, #REGISTRY do
        local entry = REGISTRY[i]
        local view = _live_views[entry.class_name]
        local status, source = CustomizerModule.coverage_status(view, entry)
        if status == "ready" then
            ready = ready + 1
        elseif status == "move_fallback" or status == "nominal_size_fallback" then
            fallback = fallback + 1
        else
            missing = missing + 1
        end
        printf("[gut:310] HUD coverage id=%s class=%s status=%s scenegraph=%s move=%s drag=%s",
            tostring(entry.id), tostring(entry.class_name), tostring(status), tostring(source),
            tostring(entry.scenegraph_node_id), tostring(entry.drag_scenegraph_node_id))
    end
    printf("[gut:310] HUD coverage summary ready=%d fallback=%d missing=%d total=%d",
        ready, fallback, missing, #REGISTRY)
end

-- Reset transient drag/hover state to a clean baseline.
local function _clear_drag_state()
    _drag_active = nil
    _drag_hover = nil
    _drag_base[1], _drag_base[2] = 0, 0
    _drag_start_offset = nil
end

-- Read keyboard for the held-LEFT-ALT-while-chat-focused activation gesture
-- and update _edit_mode_alt. Also enters/exits the cursor-show stack on
-- effective edit-mode transitions.
function CustomizerModule.tick_activation()
    local chat_missing = false
    local kb_err = nil
    local ok, alt = pcall(function()
        local chat = Managers.chat
        if not (chat and chat.chat_gui and chat.chat_gui.chat_focused) then
            if not (chat and chat.chat_gui) then chat_missing = true end
            return false
        end
        local ok2, val = pcall(function() return Keyboard.button(Keyboard.button_id("left alt")) > 0.5 end)
        if not ok2 then kb_err = tostring(val); return false end
        return val
    end)
    local new_alt = ok and alt or false

    -- _dbg: activation_check failure paths
    if chat_missing then
        pcall(_dbg, "[gui_tweaker] activation_check: chat_manager_missing")
    end
    if kb_err then
        pcall(_dbg_alert, "[gui_tweaker] activation_check: keyboard_read_failed err=%s", tostring(kb_err))
    end

    -- _dbg: edit_mode_alt (only on transition)
    if new_alt ~= _edit_mode_alt then
        local chat_focused = false
        pcall(function()
            chat_focused = Managers.chat and Managers.chat.chat_gui
                and Managers.chat.chat_gui.chat_focused and true or false
        end)
        pcall(_dbg, "[gui_tweaker] edit_mode_alt: %s (chat_focused=%s)",
            tostring(new_alt), tostring(chat_focused))
    end
    _edit_mode_alt = new_alt

    local now = CustomizerModule.is_edit_mode()
    if now ~= _was_edit_mode then
        if now then
            pcall(ShowCursorStack.show, "gut_edit_hud")
            -- _dbg: cursor_stack push
            pcall(_dbg, "[gui_tweaker] cursor_stack: push reason=gut_edit_hud")
            -- (#310) User-visible diagnostic (printf, since mod logging is off): edit
            -- mode is on, so local gameplay input is now suspended (freecam's
            -- is_input_blocked hook reads should_suspend_input()).
            printf("[gut:310] HUD edit mode ON -- local input suspended (resolution %s)",
                tostring(_resolution_key or _resolution_key_now()))
            pcall(_emit_coverage_probe)
        else
            pcall(ShowCursorStack.hide, "gut_edit_hud")
            -- _dbg: cursor_stack pop
            pcall(_dbg, "[gui_tweaker] cursor_stack: pop reason=gut_edit_hud")
            printf("[gut:310] HUD edit mode OFF -- local input restored")
            _clear_drag_state()
            _coverage_probe_emitted = false
        end
        _was_edit_mode = now
    end
end

-- Read cursor in UI-space (post-inverse-scale). Returns Vector3 or nil if the
-- engine helper threw (e.g. mouse not yet wired up at very early load).
local function _cursor_ui_space()
    local ok, c = pcall(function()
        return UIInverseScaleVectorToResolution(Mouse.axis(Mouse.axis_id("cursor")))
    end)
    return ok and c or nil
end

-- Per-frame drag state machine. Walks the registry, hit-tests every widget
-- bounding box against the cursor, transitions hover -> active on left-mouse
-- press, and updates the offset live while held. Persists on release.
function CustomizerModule.tick_drag()
    local cursor = _cursor_ui_space()
    if not cursor then _drag_hover = nil return end

    local pressed = false
    local released = false
    pcall(function() pressed = Mouse.pressed(Mouse.button_id("left")) end)
    pcall(function() released = Mouse.released(Mouse.button_id("left")) end)

    if _drag_active then
        local dx = cursor[1] - _drag_base[1]
        local dy = cursor[2] - _drag_base[2]
        -- (#312) Owned elements write through to UI Tweaks instead of gut's own store.
        local sync = mod._gut_uitweaks_sync
        local owned = sync and sync.is_owned and sync.is_owned(_drag_active)
        if owned then
            pcall(sync.preview, _drag_active, dx, dy)  -- in-memory HB write; HB redraws next frame
        else
            -- (#310) Confine the drag so the element's box stays within the displayable
            -- HUD area. Uses the element's LIVE world box + the delta applied last frame
            -- (_get_widget_offset still holds it, we overwrite below) to clamp in
            -- world-space, then back-solves the confined delta. Owned elements delegate to
            -- UI Tweaks and are left to HB's own layout, so this path is gut-native only.
            local entry = REGISTRY_BY_ID[_drag_active]
            local view  = entry and _live_views[entry.class_name]
            local scenegraph = CustomizerModule.scenegraph_for_view(view)
            local node, size = CustomizerModule.drag_geometry(scenegraph, entry)
            if node and node.world_position then
                local adx, ady = _get_widget_offset(_drag_active)
                local ok_c, cdx, cdy = pcall(CustomizerModule.confine_delta,
                    node.world_position[1], node.world_position[2], size[1], size[2],
                    adx, ady, dx, dy, CustomizerModule.hud_bounds())
                if ok_c then dx, dy = cdx, cdy end
            end
            _set_widget_offset(_drag_active, dx, dy)
        end
        if released then
            local id = _drag_active
            local start_dx, start_dy = _drag_start_offset and _drag_start_offset[1] or 0,
                                       _drag_start_offset and _drag_start_offset[2] or 0
            local delta_x = dx - start_dx
            local delta_y = dy - start_dy
            if owned then
                pcall(sync.commit, id, dx, dy)  -- HB durable write + notify (re-layout)
            else
                _save_offsets()
            end
            _drag_active = nil
            _drag_start_offset = nil
            -- _dbg: drag_end
            pcall(_dbg, "[gui_tweaker] drag_end: id=%s owned=%s final_offset={%d,%d} delta={%d,%d}",
                tostring(id), tostring(owned and true or false), dx, dy, delta_x, delta_y)
        end
        _reapply_all_offsets()
        return
    end

    _drag_hover = nil
    for i = 1, #REGISTRY do
        local entry = REGISTRY[i]
        local view = _live_views[entry.class_name]
        local scenegraph = CustomizerModule.scenegraph_for_view(view)
        local node, size = CustomizerModule.drag_geometry(scenegraph, entry)
        if node and node.world_position then
            local pos = Vector3(node.world_position[1], node.world_position[2], 999)
            local hit = false
            pcall(function() hit = math.point_is_inside_2d_box(cursor, pos, size) end)
            if hit then
                _drag_hover = entry.id
                if pressed then
                    -- (#312) Anchor the drag at the element's CURRENT offset: UI Tweaks'
                    -- when it owns this element, else gut's own stored offset.
                    local sync = mod._gut_uitweaks_sync
                    local dx, dy
                    if sync and sync.is_owned and sync.is_owned(entry.id) then
                        dx, dy = 0, 0
                        pcall(function() dx, dy = sync.get_offset(entry.id) end)
                    else
                        dx, dy = _get_widget_offset(entry.id)
                    end
                    _drag_active = entry.id
                    _drag_base[1] = cursor[1] - dx
                    _drag_base[2] = cursor[2] - dy
                    _drag_start_offset = { dx, dy }
                    -- _dbg: drag_start
                    pcall(_dbg, "[gui_tweaker] drag_start: id=%s cursor={%d,%d} prior_offset={%d,%d}",
                        tostring(entry.id), cursor[1], cursor[2], dx, dy)
                end
                break
            end
        end
    end
    _reapply_all_offsets()
end

-- Translucent border + body fill. Colors mirror vanilla HudCustomizer
-- (light_sky_blue default, silver hover, cheeseburger active).
local function _color(name, alpha)
    if rawget(_G, "Colors") and Colors.get_color_table_with_alpha then
        local ok, c = pcall(Colors.get_color_table_with_alpha, name, alpha)
        if ok and c then return c end
    end
    return { alpha, 255, 255, 255 }
end

-- Draw 4-strip border + dim fill on every registered widget's bounding box,
-- coloring by drag/hover state. Matches vanilla hud_customizer.lua:89-107.
function CustomizerModule.draw_overlay(ui_renderer)
    if not ui_renderer then return end
    local bg = _color("black", 100)
    local default_color = _color("light_sky_blue", 200)
    local hover_color = _color("silver", 230)
    local active_color = _color("cheeseburger", 230)
    local border = 3
    for i = 1, #REGISTRY do
        local entry = REGISTRY[i]
        local view = _live_views[entry.class_name]
        local scenegraph = CustomizerModule.scenegraph_for_view(view)
        local node, size = CustomizerModule.drag_geometry(scenegraph, entry)
        if node and node.world_position then
            local pos = Vector3(node.world_position[1], node.world_position[2], 999)
            local color = default_color
            if _drag_active == entry.id then
                color = active_color
            elseif _drag_hover == entry.id then
                color = hover_color
            end
            local h_size = Vector2(size[1], border)
            local v_size = Vector2(border, size[2] - 2 * border)
            local a_size = Vector2(size[1], size[2])
            pcall(function()
                UIRenderer.draw_rect(ui_renderer, pos, a_size, bg)
                UIRenderer.draw_rect(ui_renderer, pos + Vector2(0, size[2] - border), h_size, color)
                UIRenderer.draw_rect(ui_renderer, pos, h_size, color)
                UIRenderer.draw_rect(ui_renderer, pos + Vector2(0, border), v_size, color)
                UIRenderer.draw_rect(ui_renderer, pos + Vector2(size[1] - border, border), v_size, color)
            end)
        end
    end
end

-- mod:hook_safe on each registered class's :init, capturing the view as the
-- live instance and applying the saved offset to its scenegraph immediately.
function CustomizerModule.install_hooks()
    local installed, failed, failures = 0, 0, {}
    for i = 1, #REGISTRY do
        local entry = REGISTRY[i]
        local ok_a = pcall(function()
            mod:hook_safe(entry.class_name, "init", function(self)
                _live_views[entry.class_name] = self
                pcall(_apply_offset_to_scenegraph, self, entry.scenegraph_node_id, entry.id, false)
                -- _dbg: widget_init / widget_init_skip
                pcall(function()
                    local scenegraph = CustomizerModule.scenegraph_for_view(self)
                    local node = scenegraph and scenegraph[entry.scenegraph_node_id]
                    if not node then
                        _dbg_alert("[gui_tweaker] widget_init_skip: id=%s class=%s reason=scenegraph_node_missing",
                            tostring(entry.id), tostring(entry.class_name))
                        return
                    end
                    local wp = node.world_position or {0, 0}
                    local sz = (node.size and node.size[1] and node.size[1] > 0 and node.size) or entry.nominal_size or {0, 0}
                    local dx, dy = _get_widget_offset(entry.id)
                    _dbg("[gui_tweaker] widget_init: id=%s node=%s world_pos={%d,%d} size={%d,%d} offset={%d,%d}",
                        tostring(entry.id), tostring(entry.scenegraph_node_id),
                        math.floor(wp[1] or 0), math.floor(wp[2] or 0),
                        math.floor(sz[1] or 0), math.floor(sz[2] or 0),
                        math.floor(dx or 0), math.floor(dy or 0))
                end)
            end)
        end)
        local ok_b = pcall(function()
            mod:hook_safe(entry.class_name, "destroy", function(self)
                if _live_views[entry.class_name] == self then
                    _live_views[entry.class_name] = nil
                end
            end)
        end)
        if ok_a and ok_b then
            installed = installed + 1
        else
            failed = failed + 1
            failures[#failures + 1] = entry.class_name
        end
    end
    return installed, failed, failures
end

-- (#312) Public offset accessors for the UI Tweaks sync module's one-time migrate()
-- (reads gut's stored offset then clears it as it folds the value into UI Tweaks).
-- Kept on the customizer so the in-memory cache and the persistent store stay in
-- lockstep (clearing goes through _save_offsets, not a raw mod:set behind our back).
function CustomizerModule.get_widget_offset(widget_id)
    return _get_widget_offset(widget_id)
end
function CustomizerModule.clear_widget_offset(widget_id)
    _offsets_cache[widget_id] = nil
    _save_offsets()
end

-- Set widget's offset back to {0, 0}, persist, and re-apply to the live view.
function CustomizerModule.reset_widget(widget_id)
    local entry = REGISTRY_BY_ID[widget_id]
    if not entry then return false end
    -- (#312) If UI Tweaks owns this element, zero ITS offset too (element back to
    -- vanilla) with a durable save; gut's node is already pinned to vanilla by the
    -- owner-aware apply path, so clearing gut's store below just tidies bookkeeping.
    local sync = mod._gut_uitweaks_sync
    if sync and sync.is_owned and sync.is_owned(widget_id) then
        pcall(sync.reset, widget_id)
    end
    _offsets_cache[widget_id] = nil
    _save_offsets()
    local view = _live_views[entry.class_name]
    if view then
        local scenegraph = CustomizerModule.scenegraph_for_view(view)
        local node = scenegraph and scenegraph[entry.scenegraph_node_id]
        if node and node.local_position then
            node.local_position[1] = entry.vanilla_position[1]
            node.local_position[2] = entry.vanilla_position[2]
        end
    end
    return true
end

-- Reset every registered widget for the current resolution.
function CustomizerModule.reset_all()
    local n = 0
    for i = 1, #REGISTRY do
        if CustomizerModule.reset_widget(REGISTRY[i].id) then n = n + 1 end
    end
    return n
end

-- Snapshot of current offsets keyed by widget_id (sorted by registry order).
function CustomizerModule.list_offsets()
    local out = {}
    for i = 1, #REGISTRY do
        local entry = REGISTRY[i]
        local dx, dy = _get_widget_offset(entry.id)
        if dx ~= 0 or dy ~= 0 then
            out[#out + 1] = { id = entry.id, dx = dx, dy = dy }
        end
    end
    return out
end

-- Current resolution key (exposed for the /list_hud command).
function CustomizerModule.resolution_key()
    return _resolution_key or _resolution_key_now()
end

-- v0.2.5+: HeroView debug dump. Walks the view's state machine + active windows
-- and emits one `[gui_tweaker] hero_view: ...` line per field. Mirrors what
-- general_tweaker's /gt_dump_hero_view command produces. pcall-wrapped end-to-end
-- so a structural surprise doesn't crash gameplay.
function CustomizerModule.dump_hero_view(view)
    pcall(function()
        if not view then
            _dbg("[gui_tweaker] hero_view: dump skipped (nil view)")
            return
        end
        -- (#224 follow-up) Resolve the live state or report a clear reason via printf
        -- (user-visible; mod:debug is invisible with mod logging OFF). This dump runs
        -- from HeroView.on_enter, which fires BEFORE post_update_on_enter creates the
        -- state machine (hero_view.lua:499-514) -- so a nil machine here is expected
        -- timing, not a resolution failure.
        local machine = view._machine
        local state = machine and machine._state or nil
        if state then
            local state_name = "?"
            local state_index = "?"
            pcall(function()
                local mt = getmetatable(state)
                state_name = (mt and mt.__index and mt.__index.NAME) or state.NAME or tostring(state)
            end)
            pcall(function() state_index = tostring(state.state_index or state._state_index or "?") end)
            printf("[gut:heroview] dump: state=%s state_index=%s", tostring(state_name), tostring(state_index))
        elseif not machine then
            printf("[gut:heroview] dump: state machine not created yet (on_enter precedes post_update_on_enter)")
        else
            printf("[gut:heroview] dump: machine present but no active _state")
        end

        if state and type(state._layout_settings) == "table" then
            local count = 0
            for k, v in pairs(state._layout_settings) do
                count = count + 1
                if count <= 32 then
                    _dbg("[gui_tweaker] hero_view: layout_settings.%s=%s",
                        tostring(k), tostring(v))
                end
            end
            _dbg("[gui_tweaker] hero_view: layout_settings_count=%d", count)
        end

        if state and type(state._window_layouts) == "table" then
            _dbg("[gui_tweaker] hero_view: window_layouts_count=%d", #state._window_layouts)
        end

        if state and type(state._active_windows) == "table" then
            local n = 0
            for _ in pairs(state._active_windows) do n = n + 1 end
            _dbg("[gui_tweaker] hero_view: active_windows_count=%d", n)
            for win_name, win in pairs(state._active_windows) do
                local win_class = "?"
                pcall(function()
                    local mt = getmetatable(win)
                    win_class = (mt and mt.__index and mt.__index.NAME) or win.NAME or tostring(win_name)
                end)
                _dbg("[gui_tweaker] hero_view: window=%s class=%s", tostring(win_name), tostring(win_class))
                if type(win._widgets_by_name) == "table" then
                    local widget_names = {}
                    for wname, _ in pairs(win._widgets_by_name) do
                        widget_names[#widget_names + 1] = tostring(wname)
                    end
                    table.sort(widget_names)
                    _dbg("[gui_tweaker] hero_view: window=%s widgets=%s",
                        tostring(win_name), table.concat(widget_names, ","))
                end
            end
        end
    end)
end

-- Load offsets on require; wrapped so a corrupt/missing mod:get doesn't crash
-- the wider gui_tweaker init.
pcall(_load_offsets_for_resolution)

return CustomizerModule
