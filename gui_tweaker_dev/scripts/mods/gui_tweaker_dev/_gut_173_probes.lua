local mod = get_mod("gut_dev")

-- ============================================================================
-- (#173 Probe B7) force_respawn -> resulting spawn position  --  DIAGNOSTIC ONLY
-- ============================================================================
-- Settles whether a career swap's force_respawn TELEPORTS the player to level start or
-- respawns in place -- the empirical question the source read alone did NOT answer
-- (HERO_SELECT_RESEARCH_173.md, Probe B7 + Solution C3/C5 blocker).
--
-- Symbol verified: GameModeAdventure.force_respawn(self, peer_id, local_player_id) at
-- scripts/managers/game_mode/game_modes/game_mode_adventure.lua:283. gut hooks it NOWHERE
-- else (whole-mod grep before adding -- the other force_respawn mentions in
-- _gut_career_swap.lua / _gut_mission_hero_select.lua are comments, not hooks). hook_safe =
-- pure observation, ZERO behavior change.
--
-- The respawn is processed over subsequent frames, so we capture the PRE position on the
-- hook and read the POST position ~60 frames later on the chained mod.update tick. Positions
-- are captured as NUMBER components immediately (Vector3 is a stack temporary -- never store
-- the raw value; memory reference_vt2 quirk). Tag: [gut:173] (engine printf, mod-log-off safe).

local _printf = rawget(_G, "printf") or function(fmt, ...) print(string.format(fmt, ...)) end

local function _local_unit()
    local pm = Managers and Managers.player
    local p = pm and pm.local_player and pm:local_player()
    return p and p.player_unit
end

-- Returns x, y, z as numbers (or nil) -- never returns/stores a raw Vector3.
local function _pos_xyz(unit)
    if not (unit and Unit.alive(unit)) then return nil end
    local ok, v = pcall(Unit.world_position, unit, 0)
    if not ok or not v then return nil end
    return Vector3.x(v), Vector3.y(v), Vector3.z(v)
end

local function _fmt(x, y, z)
    if not x then return "nil" end
    return string.format("(%.1f, %.1f, %.1f)", x, y, z)
end

-- Pending post-respawn read (numbers only). frames counts down on mod.update.
local _pending = nil

mod:hook_safe("GameModeAdventure", "force_respawn", function(self, peer_id, local_player_id)
    local ok = pcall(function()
        local x, y, z = _pos_xyz(_local_unit())
        _pending = { frames = 60, px = x, py = y, pz = z }
        _printf("[gut:173] B7 force_respawn fired peer=%s lpid=%s pre_pos=%s -- reading post-respawn position in ~60 frames",
            tostring(peer_id), tostring(local_player_id), _fmt(x, y, z))
    end)
    if not ok then _printf("[gut:173] B7 pre-capture error") end
end)

-- Chain mod.update: capture-prev, call-prev-first (never clobber another feature's tick).
-- This module dofile's AFTER the other mod.update definers, so this is their chain.
local _b7_prev_update = mod.update
mod.update = function(dt)
    if _b7_prev_update then _b7_prev_update(dt) end
    if not _pending then return end
    pcall(function()
        _pending.frames = _pending.frames - 1
        if _pending.frames > 0 then return end
        local nx, ny, nz = _pos_xyz(_local_unit())
        local moved = "?"
        if _pending.px and nx then
            local dx, dy, dz = nx - _pending.px, ny - _pending.py, nz - _pending.pz
            moved = string.format("%.1f", math.sqrt(dx * dx + dy * dy + dz * dz))
        end
        _printf("[gut:173] B7 post-respawn pre_pos=%s post_pos=%s moved=%s (moved~0 = respawn-in-place; large = teleport-to-level-start)",
            _fmt(_pending.px, _pending.py, _pending.pz), _fmt(nx, ny, nz), moved)
        _pending = nil
    end)
end

_printf("[gut:173] B7 probe installed (GameModeAdventure.force_respawn spawn-position diagnostic; read-only)")

return {}
