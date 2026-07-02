local mod = get_mod("gut")

-- ============================================================================
-- NumericUI ability-cooldown: show REAL-TIME reduced seconds (not a sped-up count)
-- ============================================================================
-- VT2 applies cooldown reduction by making the ability cooldown DECREASE FASTER, not
-- by shortening it. career_extension.lua:244-246:
--   local mult = buff_extension:apply_buffs_to_value(1, "cooldown_regen")
--   self:reduce_activated_ability_cooldown(dt * mult, i)
-- So the raw value from CareerExtension.current_ability_cooldown() ticks down faster
-- than wall-clock under CDR. NumericUI displays that raw value for the local player
-- (NumericUI.lua:1466: math.ceil(career_extension:current_ability_cooldown())), so its
-- on-screen cooldown number visibly SPEEDS UP instead of counting real seconds.
--
-- Fix (from our side, no NumericUI rebuild): while NumericUI is computing its
-- own-player stats — inside its hook on UnitFramesHandler._sync_player_stats — divide
-- the cooldown READ by that SAME cooldown_regen multiplier. cd/mult is the real
-- seconds remaining: it ticks at 1/sec and shows the accurate reduced cooldown. A flag
-- gates it so ONLY NumericUI's display is touched — the game's cooldown logic, the
-- ability-bar fill (current_ability_cooldown_percentage), and bot AI all keep the raw
-- value. (Verified: vanilla _sync_player_stats reads only ability_percentage, never
-- current_ability_cooldown, so the flag can't leak to a vanilla read.)
--
-- No-op if NumericUI isn't installed. Graceful no-op (raw value = original behaviour,
-- no crash) in the unlikely event hook order ever nests us INSIDE NumericUI's hook.

if not get_mod("NumericUI") then return {} end

local ScriptUnit = ScriptUnit
local Unit       = Unit

local _in_sync = false
local _logged  = false

-- The cooldown_regen multiplier currently on the ability owner (1 = no CDR).
local function _cdr_multiplier(career_extension)
    local unit = career_extension and career_extension._unit
    if not (unit and Unit.alive(unit)) then return 1 end
    local buff_ext = ScriptUnit.has_extension(unit, "buff_system")
    if not buff_ext then return 1 end
    local ok, mult = pcall(buff_ext.apply_buffs_to_value, buff_ext, 1, "cooldown_regen")
    if ok and type(mult) == "number" and mult > 0 then return mult end
    return 1
end

-- Flag the window of NumericUI's whole _sync_player_stats pass. We load after NumericUI
-- so our hook is the OUTERMOST wrapper and encloses NumericUI's hook. pcall so the flag
-- is ALWAYS reset even if the chain errors (a stuck-true flag would wrongly divide
-- every cooldown read); re-raise to preserve the original error.
mod:hook("UnitFramesHandler", "_sync_player_stats", function(func, self, unit_frame)
    _in_sync = true
    local ok, err = pcall(func, self, unit_frame)
    _in_sync = false
    if not ok then error(err, 0) end
end)

-- Capture BOTH returns (cooldown, max_cooldown) so we don't collapse the multi-return.
mod:hook("CareerExtension", "current_ability_cooldown", function(func, self, ability_id)
    local cd, max_cd = func(self, ability_id)
    if _in_sync and type(cd) == "number" and cd > 0 then
        local mult = _cdr_multiplier(self)
        if mult > 1 then
            if not _logged then
                _logged = true
                mod:debug("[gut] NumericUI cooldown realtime-fix active: raw=%.1f mult=%.3f -> shown=%.1f",
                    cd, mult, cd / mult)
            end
            cd = cd / mult
        end
    end
    return cd, max_cd
end)

return {}
