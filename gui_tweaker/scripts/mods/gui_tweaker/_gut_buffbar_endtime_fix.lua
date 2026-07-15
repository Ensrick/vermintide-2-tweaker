local mod = get_mod("gut")

-- ============================================================================
-- UI Tweaks buff-bar end-time crash fix (absorbed into gut)
-- ============================================================================
-- THE BUG (diagnosed from a player console log, 2026-06-19):
--   UI Tweaks (internal name "HideBuffs", Workshop 1467751760) throws
--     scripts/mods/HideBuffs/PriorityBuffUI.lua:228: attempt to compare nil
--     with number
--   ~1000+ times per session -- once every frame, for both the main and the
--   second buff bar -- while a STACKING buff is active. Reproduced with Bardin
--   Outcast Engineer's pump stacks (bardin_engineer_pump_buff).
--
--   PriorityBuffUI._add_buff merges a new application of an already-shown buff.
--   When it finds an existing entry with the same name it does (line 228):
--       data.end_time = end_time and ((data.end_time < end_time and end_time)
--                                     or data.end_time)
--   The `end_time and ...` guard only protects the INCOMING end_time against
--   nil. If the stored entry's `data.end_time` is nil -- which happens when the
--   buff was first added while infinite (an infinite buff is stored with
--   end_time = nil) and is later refreshed with a finite end_time -- then
--   `data.end_time < end_time` is `nil < number` and errors.
--
-- THE FIX (sanctioned -- pure-Lua wrap, no forked resources):
--   PriorityBuffUI is a GLOBAL class (PriorityBuffUI = class(PriorityBuffUI),
--   PriorityBuffUI.lua:26), so we wrap PriorityBuffUI._add_buff. Before the
--   original runs we mirror its own match loop and, for the single entry it
--   will act on, backfill a nil stored end_time with the incoming end_time.
--   That makes the vanilla compare `data.end_time < end_time` evaluate to
--   `end_time < end_time` (false), so it keeps the new finite end_time -- the
--   correct "adopt the refreshed end time" result -- with no crash and no
--   visible change beyond stopping the error spam. We only touch the exact
--   crash case (stored nil + incoming non-nil); every other path is untouched.
--   IMPLICIT (no toggle): a crash-prevention fix should never be switchable, so
--   the nil-guard ALWAYS applies. No-op if UI Tweaks isn't installed.

-- Install once. Safe to call repeatedly (guarded) and before/after HideBuffs
-- loads (no-op until PriorityBuffUI exists).
local function apply()
    local PBUI = rawget(_G, "PriorityBuffUI")
    if not (PBUI and type(PBUI._add_buff) == "function") then
        return false
    end
    if PBUI._gut_endtime_fix_installed then
        return true
    end

    local orig = PBUI._add_buff
    PBUI._add_buff = function(self, buff, infinite, end_time)
        -- Only intervene for the precise crash condition: a finite incoming
        -- end_time about to be compared against a stored nil end_time.
        if end_time ~= nil and self and self._active_buffs and buff then
            local template = buff.template
            local buff_id = buff.id
            local buff_name = template and template.name
            local active = self._active_buffs
            -- Mirror _add_buff's match loop: it acts on (and breaks at) the
            -- FIRST entry matching id, else name. The id branch overwrites
            -- end_time directly (safe); only the name branch does the unguarded
            -- compare, so that's the only entry we backfill.
            for j = 1, #active do
                local data = active[j]
                if data.id == buff_id then
                    break
                elseif data.name == buff_name then
                    if data.end_time == nil then
                        data.end_time = end_time
                    end
                    break
                end
            end
        end
        return orig(self, buff, infinite, end_time)
    end

    PBUI._gut_endtime_fix_installed = true
    mod:info("[gut] UI Tweaks buff-bar end-time crash fix installed (PriorityBuffUI._add_buff nil-guard; implicit, always-on)")
    return true
end

return { apply = apply }
