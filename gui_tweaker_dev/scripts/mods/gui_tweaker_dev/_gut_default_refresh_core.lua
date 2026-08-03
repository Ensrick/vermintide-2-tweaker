-- _gut_default_refresh_core.lua -- pure policy for the issue #1033 presentation half.
--
-- The Equipment DEFAULT reset (see _gut_native_loadouts.lua reset_modded_loadouts)
-- is a persistence transaction: it rewrites the modded loadout store and dirtifies
-- the backend interfaces, but nothing republishes the LIVE character. Vanilla's
-- own publish seams only run on equip EVENTS: the hero-view equip request drains
-- into SimpleInventoryExtension.create_equipment_in_slot, which RPCs every peer
-- (rpc_add_equipment, simple_inventory_extension.lua:1372/:1455), and skin changes
-- take one profile respawn (hero_view_state_overview.lua:1158-1162 ->
-- ingame_ui.lua:1290-1303). A DEFAULT reset fires none of them, so the keep/lobby
-- unit (and its husk on other peers) keeps rendering the pre-reset equipment.
--
-- This module is the PURE decision + receipt half: no engine calls, offline-locked
-- by qa/lua/tests/test_gut_default_refresh.lua and the issue1033 rt check. The
-- engine-facing owner is _gut_default_reset_refresh.lua.
--
-- Policy: refresh via one bounded profile re-request (vanilla's skin-change path)
-- ONLY in the keep ("inn" game mode). A mission respawn teleports to level start
-- with fresh health/ammo (GameModeAdventure.force_respawn; see
-- _gut_career_swap.lua's caveat), so in-mission the reset DEFERS: the next spawn
-- boundary (keep load / level transition) consumes the reset rows naturally.
--
-- Owned by: _gut_default_reset_refresh.lua. Consumed via: mod:dofile (single call).

local M = {}

M.MARKER = "default_refresh_core_v1"

-- Receipt slots: the visible identities RainReligion observed stale (melee +
-- cosmetic). slot_skin is covered by the respawn itself but has no comparable
-- live per-slot read, so the receipt tracks the three slot-data-backed ones.
M.RECEIPT_SLOTS = { "slot_melee", "slot_ranged", "slot_hat" }

-- Keep game-mode key (GameModeSettings.inn, game_mode_settings.lua:100).
M.KEEP_GAME_MODE = "inn"

-- Bounded after-receipt watch budget (seconds).
M.WATCH_BUDGET_SECONDS = 15

-- classify(state) -> action, reason
--   state = {
--     mirror_live         = bool  -- the Adventure mirror was live (reset seeded)
--     reset_scope_active  = bool  -- the reset covered the ACTIVE career
--     has_player          = bool  -- local player identity resolved
--     unit_alive          = bool  -- live local player unit exists
--     game_mode_key       = string|nil
--     requester_available = bool  -- ProfileRequester reachable
--   }
-- Actions: "respawn" (fire one bounded profile re-request now),
--          "defer"   (durable reset stands; next spawn boundary reconciles),
--          "skip"    (nothing to refresh).
function M.classify(state)
    if type(state) ~= "table" then return "skip", "no-state" end
    if not state.mirror_live then return "skip", "mirror-not-adventure" end
    if not state.reset_scope_active then return "skip", "reset-career-not-active" end
    if not state.has_player or not state.unit_alive then return "skip", "no-live-player" end
    if state.game_mode_key ~= M.KEEP_GAME_MODE then
        return "defer", "not-keep:" .. tostring(state.game_mode_key)
    end
    if not state.requester_available then return "defer", "no-profile-requester" end
    return "respawn", "keep-live"
end

-- match(desired, live, slots) -> all_matched, mismatched_slot_list
-- A nil DESIRED value is never a mismatch: a reseeded row may legitimately hold
-- no hat, and the receipt must not fail on an empty-but-correct slot.
function M.match(desired, live, slots)
    slots = slots or M.RECEIPT_SLOTS
    local all = true
    local mismatched = {}
    for i = 1, #slots do
        local slot = slots[i]
        local want = desired and desired[slot]
        if want ~= nil and (type(live) ~= "table" or live[slot] ~= want) then
            all = false
            mismatched[#mismatched + 1] = slot
        end
    end
    return all, mismatched
end

-- expired(elapsed, budget) -> bool. Non-numeric elapsed never expires the watch
-- prematurely (treated as 0); the engine owner supplies real dt sums.
function M.expired(elapsed, budget)
    return (tonumber(elapsed) or 0) > (tonumber(budget) or M.WATCH_BUDGET_SECONDS)
end

return M
