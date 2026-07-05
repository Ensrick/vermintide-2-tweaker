local mod = get_mod("gt_dev")

-- _gt_saved_positions.lua — Save / recall the local player's map position (dev tool, #306)
--
-- Registers 20 chat commands in a loop: /save_position_1 .. /save_position_10
-- capture the LOCAL player unit's current position + first-person look rotation;
-- /recall_position_1 .. /recall_position_10 teleport that unit back. Saves are
-- PER MAP: the store is keyed by the current level_key, so every map carries its
-- own 10 slots. Persisted through one VMF setting (`gt_saved_positions`) on every
-- save so slots survive a crash / restart. Client-safe — everything operates on
-- the local player unit only (same movement surface noclip uses), so it works in
-- the keep AND in a mission and never touches another peer.
--
-- CRITICAL Stingray rule: Vector3 / Quaternion are stack temporaries (CLAUDE.md
-- "Lua Environment"). We persist plain number components (x/y/z + qx/qy/qz/qw)
-- and rebuild Vector3(x,y,z) / Quaternion.from_elements(...) at recall time —
-- never the userdata. Mirrors vanilla's own saved-teleport tool, which stores
-- points as {x,y,z,qx,qy,qz,qw} keyed by level and teleports with the same two
-- rebuilds (imgui_teleport_tool.lua:352-363).
--
-- Teleport primitive: PlayerUnitLocomotionExtension:teleport_to(pos, rot)
-- (player_unit_locomotion_extension.lua:1005-1023) — sets the mover + unit
-- position and, when rot is passed, first_person_extension:set_rotation(rot).
-- Rotation restore SHIPS (position + look direction both restored).
-- Level key: Managers.state.game_mode:level_key() (game_mode_manager.lua:897,
-- returns self._level_key) — the mod's existing pattern (_gt_creature_spawner.lua:245).
--
-- PHASE RULE (#337): the teleport MUST run inside mod.update, never directly from
-- the chat-command callback. teleport_to's last line is
-- status_extension:set_falling_height(), which reads POSITION_LOOKUP[unit].z
-- (generic_status_extension.lua:2586-2593). POSITION_LOOKUP holds raw Vector3
-- STACK TEMPORARIES, bulk-refreshed once per frame in StateIngame.pre_update
-- (state_ingame.lua:808) and valid only within that frame's Vector3 pool. The
-- chat-command execution context sits outside that pool window, so the stored
-- entry is a dead handle there: teleport_to teleports (mover + position + rotation
-- all land), then dies on its last line with "bad argument #1 to '__index'
-- (Vector3 expected, got userdata)" — a false "teleport failed" report that also
-- skips set_ignore_next_fall_damage (recalling to a high ledge would take fall
-- damage). Every vanilla teleport_to caller is an update-phase BT action
-- (bt_bot_teleport_to_ally_action.lua:84 etc.), so vanilla never sees this.
-- /recall_position_N therefore only QUEUES; the one-tick-deferred drain in the
-- mod.update chain below performs the teleport in the same phase vanilla uses.
--
-- Owned by: general_tweaker_dev.lua entry point. Consumed via: mod:dofile
-- (runs after the main chunk, so mod._gt_register_update exists). No hooks;
-- registers one 'saved_pos_recall' consumer in the central update registry.

local _SETTING     = "gt_saved_positions"
local _SLOT_COUNT  = 10

-- Structural marker for the /gt_regression_test check registered in the main file.
mod._GT_SAVED_POSITIONS_MARKER      = "gt-saved-positions-per-map-slots"
mod._gt_saved_positions_slot_count  = _SLOT_COUNT

-- printf wrapper for the console-visible diagnostic trace (user runs with mod
-- logging off, so printf is the only channel that lands — repo rule 9). Pre-format
-- so a stray `%` in a level key can't break the engine's own format pass.
local function _pf(fmt, ...)
    local p = rawget(_G, "printf")
    if not p then return end
    local ok, s = pcall(string.format, fmt, ...)
    if ok then p("%s", s) end
end

-- Master in-memory store, seeded from the persisted VMF setting. VMF's mod:get
-- returns a (shallow) clone of the stored table; we own this copy as the source
-- of truth and mod:set the whole thing back on every save. Shape:
--   _positions[level_key_string][slot_string] = { x, y, z, qx, qy, qz, qw }
-- Every level of nesting is a pure string-keyed hash and every leaf is a pure
-- string-keyed hash of numbers — no mixed array/hash tables, which the engine's
-- user-settings serializer rejects (vmf/modules/core/settings.lua:10).
local _positions = mod:get(_SETTING)
if type(_positions) ~= "table" then _positions = {} end

local function _local_player_unit()
    local pm = Managers.player
    local player = pm and pm:local_player()
    return player and player.player_unit
end

-- Guarded read of the current level key (works in keep and mission — the keep is
-- a level with a level_key too, e.g. the "inn_level" family). Returns nil if the
-- game-mode manager isn't up yet (main menu / loading).
local function _current_level_key()
    local state = Managers.state
    local gm = state and state.game_mode
    if not (gm and gm.level_key) then return nil end
    local ok, key = pcall(gm.level_key, gm)
    if ok and type(key) == "string" and key ~= "" then return key end
    return nil
end

-- Capture the local player's position + look rotation into per-map slot `slot`.
local function _save_slot(slot)
    local unit = _local_player_unit()
    if not (unit and Unit.alive(unit)) then
        mod:echo("[gt] save_position_%d: no local player unit (dead, spectating, or not in a level).", slot)
        return
    end
    local level_key = _current_level_key()
    if not level_key then
        mod:echo("[gt] save_position_%d: no current map (not in a level yet).", slot)
        return
    end

    -- Position: read the unit's local position (the same value teleport_to writes
    -- via Unit.set_local_position). Stack temporary — decompose immediately.
    local pos = Unit.local_position(unit, 0)
    local leaf = { x = pos.x, y = pos.y, z = pos.z }

    -- Rotation: the first-person look rotation is what teleport_to restores via
    -- first_person_extension:set_rotation. Decompose to elements immediately.
    local fp = ScriptUnit.has_extension(unit, "first_person_system")
    if fp and fp.current_rotation then
        local rot = fp:current_rotation()
        local qx, qy, qz, qw = Quaternion.to_elements(rot)
        leaf.qx, leaf.qy, leaf.qz, leaf.qw = qx, qy, qz, qw
    end

    _positions[level_key] = _positions[level_key] or {}
    _positions[level_key][tostring(slot)] = leaf
    mod:set(_SETTING, _positions)  -- persist through VMF on every save (crash-safe)

    _pf("[gt:saved_pos] SAVE slot=%d map=%s pos=(%.2f,%.2f,%.2f) rot=%s",
        slot, level_key, leaf.x, leaf.y, leaf.z, leaf.qw and "yes" or "no")
    mod:echo("[gt] Saved position slot %d for this map.", slot)
end

-- Queue a recall of per-map slot `slot`. Validation runs here (instant feedback in
-- chat); the TELEPORT itself is deferred one tick to the mod.update drain below --
-- see the PHASE RULE (#337) in the file docstring. The payload is plain numbers
-- (the persisted leaf), never Vector3/Quaternion temporaries, so it is safe to
-- carry across the frame boundary.
local _pending_recall = nil

local function _recall_slot(slot)
    local unit = _local_player_unit()
    if not (unit and Unit.alive(unit)) then
        mod:echo("[gt] recall_position_%d: no local player unit (dead, spectating, or not in a level).", slot)
        return
    end
    local level_key = _current_level_key()
    if not level_key then
        mod:echo("[gt] recall_position_%d: no current map (not in a level yet).", slot)
        return
    end
    local by_level = _positions[level_key]
    local saved = by_level and by_level[tostring(slot)]
    if not saved then
        mod:echo("[gt] recall_position_%d: nothing saved in slot %d for this map.", slot, slot)
        return
    end

    local loco = ScriptUnit.has_extension(unit, "locomotion_system")
    if not (loco and loco.teleport_to) then
        mod:echo("[gt] recall_position_%d: no locomotion extension on the player unit.", slot)
        return
    end

    -- Last-write-wins: mashing two recall commands in one frame keeps the newest.
    _pending_recall = { slot = slot, level_key = level_key, saved = saved }
    _pf("[gt:saved_pos] RECALL slot=%d map=%s queued for next update tick (#337 phase rule)", slot, level_key)
end

-- Drain the queued recall inside the game-update phase, where POSITION_LOOKUP
-- entries belong to the live frame pool (the phase every vanilla teleport_to
-- caller runs in). Re-validates unit + level because a frame elapsed since queue
-- time (level transitions and deaths are slower than one tick, but the guards are
-- free and the failure echo names the reason).
local function _drain_pending_recall()
    local job = _pending_recall
    if not job then return end
    _pending_recall = nil

    local slot, saved = job.slot, job.saved
    local unit = _local_player_unit()
    if not (unit and Unit.alive(unit)) then
        mod:echo("[gt] recall_position_%d: player unit vanished before the teleport tick.", slot)
        return
    end
    if _current_level_key() ~= job.level_key then
        mod:echo("[gt] recall_position_%d: map changed before the teleport tick.", slot)
        return
    end
    local loco = ScriptUnit.has_extension(unit, "locomotion_system")
    if not (loco and loco.teleport_to) then
        mod:echo("[gt] recall_position_%d: no locomotion extension on the player unit.", slot)
        return
    end

    -- Rebuild fresh stack temporaries from the stored components at apply time.
    local pos = Vector3(saved.x, saved.y, saved.z)
    local rot = nil
    if saved.qx and saved.qy and saved.qz and saved.qw then
        rot = Quaternion.from_elements(saved.qx, saved.qy, saved.qz, saved.qw)
    end

    local ok, err = pcall(loco.teleport_to, loco, pos, rot)
    if not ok then
        _pf("[gt:saved_pos] RECALL slot=%d map=%s FAILED: %s", slot, job.level_key, tostring(err))
        mod:echo("[gt] recall_position_%d: teleport failed (see console log).", slot)
        return
    end
    _pf("[gt:saved_pos] RECALL slot=%d map=%s pos=(%.2f,%.2f,%.2f) rot=%s",
        slot, job.level_key, saved.x, saved.y, saved.z, rot and "yes" or "no")
    mod:echo("[gt] Recalled to position slot %d.", slot)
end

-- Register the drain with gt's central per-frame consumer registry (Issue #16;
-- isolated pcall per consumer, general_tweaker_dev.lua:337-352) -- the same path
-- the ai_pending / afk_autobot / btlab_draw consumers use. Guarded like
-- _gt_bot_teleport_lab.lua:1195 so a load-order surprise degrades to a chat
-- error instead of a nil call.
if mod._gt_register_update then
    mod._gt_register_update("saved_pos_recall", _drain_pending_recall)
else
    mod:error("[gt:saved_pos] mod._gt_register_update missing -- recall drain not wired (#337)")
end

-- Expose for the main-file /gt_regression_test structural check (call-time resolved).
mod._gt_save_position   = _save_slot
mod._gt_recall_position = _recall_slot

-- Register the 20 commands in a loop. Lua 5.1 gives each numeric-for iteration a
-- fresh `slot` local, so every closure captures its own slot value correctly.
-- Command descriptions are plain strings (no localization needed — matches every
-- other gt command, e.g. /noclip).
for slot = 1, _SLOT_COUNT do
    mod:command("save_position_" .. slot,
        "Save the local player's position to per-map slot " .. slot,
        function() _save_slot(slot) end)
    mod:command("recall_position_" .. slot,
        "Teleport to per-map saved position slot " .. slot,
        function() _recall_slot(slot) end)
end
