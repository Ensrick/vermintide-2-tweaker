local mod = get_mod("gt_dev")

-- _gt_bots_keep.lua — two host-side bot-roster features.
--
-- Both register Class.method hooks (each a singleton (Class, method) pair, no
-- duplicate-hook collision — audited against the rest of gt_dev). Bundled here
-- because both manage the bot party roster:
--
--   (1) Bots in Keep — host fills empty party slots with bots while in the keep
--       / CW hub / Versus inn. ENABLED (v0.2.146-dev; was kill-switched in
--       v0.2.74-dev). Structure ported from Photo Mode (workshop 3743797855):
--       fill from GameModeInn/InnDeus.server_update, tear down from their
--       cleanup_game_mode_units (fixes the venture-end stat-leak crash), fill
--       gated on the host already holding its party-1 slot (fixes the slot-1
--       startup-race crash). v0.2.147-dev adds a sub-feature: lift the vanilla
--       hub pet ban for human Necromancers, plus BOT necromancers while Bots in
--       Keep is enabled (else Raise Dead hits the _pets_forbidden_in_level
--       early-return).
--   (2) Disable Bots (Solo) — sets script_data.ai_bots_disabled (+ enforce
--       hooks on the three game modes' _handle_bots) to despawn existing bots
--       mid-mission and block re-fill.
--
-- DISPATCH WIRING (no behavior change after extraction):
--   * mod._bik_fill / mod._bik_clear / mod._bik_active / mod._bik_reset_bookkeeping
--     are PUBLIC `mod.` fields (already were — the early on_setting_changed /
--     on_game_state_changed closures in main drove the feature via these table
--     fields). on_game_state_changed calls mod._bik_reset_bookkeeping; the
--     gt_bots_in_keep on_setting_changed branch calls mod._bik_fill/_clear.
--   * mod._gt_apply_no_bots(enabled) — was a file-local (_gt_apply_no_bots) in
--     main, forward-declared near the top. It is now a `mod.` field; the main
--     on_setting_changed (gt_no_bots) and on_game_state_changed (StateIngame
--     enter re-apply) branches were repointed from the bare local to
--     mod._gt_apply_no_bots (resolved at call time).
--   * Both features apply once at module load (Bots in Keep via the kill-switched
--     fill path; Disable Bots via mod._gt_apply_no_bots(mod:get("gt_no_bots"))).
--
-- The bots_in_keep _bik_* regression tests in main read mod._bik_* fields, so
-- they stay resolvable after extraction. Module dofile's AFTER the main chunk,
-- so mod._gt_register_update / mod._gt_dbg are both available at load time.
--
-- Extracted from general_tweaker_dev.lua (Phase 3 refactor, no behavior change).

local _dbg = mod._gt_dbg

-- ============================================================
-- Bots in Keep (host fills party with bots while in any inn-type level)
-- ============================================================
-- Vanilla GameModeInn / GameModeInnDeus / GameModeInnVs:server_update does NOT
-- call _handle_bots, so empty party slots stay empty in the keep / CW hub /
-- Versus inn. The underlying primitives (_add_bot_to_party / _remove_bot_instant)
-- are defined on GameModeBase and are inherited by all inn modes — callable,
-- just never invoked.
--
-- This feature replays GameModeAdventure._handle_bots / _get_first_available_bot_profile
-- against the inn party when:
--   * mod:get("gt_bots_in_keep") is true
--   * Managers.player.is_server (only the host can add bots)
--   * DamageUtils.is_in_inn returns true (inn_level / morris_hub / inn_versus
--     all flip is_in_inn via their level_settings.inn_settings entry)
--   * Managers.state.game_mode:game_mode() exposes _add_bot_to_party (sanity
--     guard — every inn mode does, but cheap to check)
--
-- Profile picking mirrors vanilla: walk PROFILES_BY_AFFILIATION.heroes,
-- filter by profile_synchronizer:is_profile_in_use, sort by
-- PlayerData.bot_spawn_priority (or ProfileIndexToPriorityIndex as the
-- vanilla fallback), then read bot_career_index off the hero_attributes
-- backend interface. No engine-internal field reads — everything is global.
--
-- Bots are tracked in `_bik_spawned` (Player table -> true) so the
-- toggle-off / leave-keep / mod-disable paths can clear specifically the ones
-- we added without disturbing anything vanilla logic might have left in an
-- open slot (none observed in inn modes, but the bookkeeping is cheap
-- insurance for future game mode additions).

local _bik_spawned = {}   -- [Player]=true, host-side tracking of the bots WE added

local function _bik_in_inn()
    local DU = rawget(_G, "DamageUtils")
    if not DU then return false end
    return DU.is_in_inn == true
end

local function _bik_is_host()
    local pm = Managers.player
    return pm and pm.is_server == true
end

-- Bug 2 guard: is the local host already occupying a slot in the heroes party
-- (party 1)? The original crash ("No empty slot in party heroes") happened
-- because the fill ran from a generic update tick and shoved bots into every
-- slot BEFORE the host's own player_entered_game_session assigned their slot.
-- Filling only once the host holds a party-1 slot removes that race entirely.
local function _bik_host_in_party1()
    local pm = Managers.player
    local lp = pm and pm.local_player and pm:local_player()
    if not lp then return false end
    local party_mgr = Managers.party
    if not (party_mgr and party_mgr.get_player_status) then return false end
    local status = party_mgr:get_player_status(lp.peer_id, lp:local_player_id())
    return status ~= nil and status.party_id == 1
end

local function _bik_game_mode()
    local sgm = Managers.state and Managers.state.game_mode
    if not (sgm and sgm.game_mode) then return nil end
    return sgm:game_mode()
end

-- v0.2.146-dev: KILL-SWITCH REMOVED. The two v0.2.74-dev crash classes are now
-- fixed STRUCTURALLY by porting Photo Mode's proven inn-bot lifecycle (workshop
-- 3743797855) instead of the old generic-update-tick fill:
--
--   Bug 1 (GUID 70b90096..., "Stat id <peer>:<lpid> not unregistered" on keep
--   exit) -- FIXED: bots are now torn down from a hook on the inn game mode's
--   own `cleanup_game_mode_units`, which `StateIngame.on_exit` calls at
--   state_ingame.lua:1911 -- BEFORE `check_venture_end` (2119) destroys the
--   venture stats manager. `_remove_bot_instant` unregisters each bot's stat
--   there, while Player refs are still valid, so the fassert can't fire.
--
--   Bug 2 (GUID faed01a7..., "No empty slot in party heroes" on host join) --
--   FIXED: fill is now driven from the inn mode's `server_update` (only ticks
--   once the session is up) AND gated on `_bik_host_in_party1()`, so bots are
--   never added until the host already holds its party-1 slot. The fill only
--   ever takes OPEN slots, so the host's slot is never claimed by a bot.
local function _bik_active()
    return mod:get("gt_bots_in_keep") == true
end

-- Mirrors GameModeAdventure._get_first_available_bot_profile but reads the
-- inputs from globals because GameModeInn carries no _available_profiles /
-- _bot_profile_id_to_priority_id. Returns (profile_index, bot_career_index)
-- or nil if every hero profile is already reserved.
local function _bik_pick_next_bot()
    local profiles_heroes = PROFILES_BY_AFFILIATION and PROFILES_BY_AFFILIATION.heroes
    if not profiles_heroes then return nil end
    local pm = Managers.player
    local psync = pm and pm.network_manager and pm.network_manager.profile_synchronizer
    if not psync then return nil end

    local available = {}
    for i = 1, #profiles_heroes do
        local pname = profiles_heroes[i]
        local pidx = FindProfileIndex and FindProfileIndex(pname)
        if pidx and not psync:is_profile_in_use(pidx) then
            available[#available + 1] = pidx
        end
    end
    if #available == 0 then return nil end

    local priority_map
    local saved = PlayerData and PlayerData.bot_spawn_priority
    if saved and #saved > 0 then
        priority_map = {}
        for i = 1, #saved do priority_map[saved[i]] = i end
    else
        priority_map = ProfileIndexToPriorityIndex
    end

    table.sort(available, function(a, b)
        return (priority_map[a] or math.huge) < (priority_map[b] or math.huge)
    end)

    local profile_index = available[1]
    local profile = SPProfiles and SPProfiles[profile_index]
    if not profile then return nil end
    local hero_attributes = Managers.backend and Managers.backend:get_interface("hero_attributes")
    local display_name = profile.display_name
    local career_index = (hero_attributes and hero_attributes:get(display_name, "career")) or 1
    local bot_career_index = (hero_attributes and hero_attributes:get(display_name, "bot_career")) or career_index or 1
    return profile_index, bot_career_index
end

-- Delta-fill the heroes party with bots, mirroring GameModeAdventure._handle_bots
-- but for the inn. Driven from the inn mode's server_update (below). Only fills
-- OPEN slots and only once the host already holds its party-1 slot, so it can
-- never take the host's slot (Bug 2). Host-only (bots are server-managed).
local function _bik_fill()
    if not _bik_active() then return 0 end
    if not _bik_is_host() then return 0 end
    if not _bik_in_inn() then return 0 end
    if not _bik_host_in_party1() then return 0 end
    local gm = _bik_game_mode()
    if not (gm and gm._add_bot_to_party) then return 0 end
    local party = Managers.party and Managers.party:get_party(1)
    if not party then return 0 end
    local open = party.num_slots - party.num_used_slots
    if open <= 0 then return 0 end

    local added = 0
    for _ = 1, open do
        local pi, ci = _bik_pick_next_bot()
        if not pi then break end
        local ok, bot = pcall(gm._add_bot_to_party, gm, 1, pi, ci)
        if ok and bot then
            _bik_spawned[bot] = true
            added = added + 1
        else
            break
        end
    end
    if added > 0 then
        _dbg("[bots_in_keep] filled +%d bot(s) into party 1", added)
        if rawget(_G, "printf") then printf("[gt_bots_in_keep] filled +%d bot(s) into party 1", added) end
    end
    return added
end

local function _bik_clear(gm)
    gm = gm or _bik_game_mode()
    local removed = 0
    if gm and gm._remove_bot_instant then
        for bot in pairs(_bik_spawned) do
            local ok = pcall(gm._remove_bot_instant, gm, bot)
            if ok then removed = removed + 1 end
        end
    end
    _bik_spawned = {}
    if removed > 0 then
        _dbg("[bots_in_keep] cleared %d bot(s)", removed)
    end
    return removed
end

-- Retained for the main file's on_game_state_changed call + the regression test,
-- but now a NO-OP. Teardown is owned by the cleanup_game_mode_units hook, which
-- runs inside StateIngame.on_exit (line 1911) BEFORE the venture stats manager
-- is destroyed (2119) and unregisters each bot's stat via _remove_bot_instant.
-- Emptying _bik_spawned here would risk racing that cleanup (VMF's
-- on_game_state_changed may fire first), dropping the tracking before cleanup
-- can unregister the stats -> exactly the Bug 1 stat-leak fassert. So: no-op.
local function _bik_reset_bookkeeping()
    -- intentionally empty; see comment above
end

-- Public on `mod` so the early on_setting_changed / on_game_state_changed
-- closures (in the main chunk) can drive the feature without needing the
-- file-locals visible at compile time. Table-field access is resolved at
-- call time, so no forward-decl is required.
mod._bik_fill = _bik_fill
mod._bik_clear = _bik_clear
mod._bik_active = _bik_active
mod._bik_reset_bookkeeping = _bik_reset_bookkeeping

-- ------------------------------------------------------------
-- Lifecycle hooks (structure ported from Photo Mode, workshop 3743797855).
-- VMF hook/hook_safe CHAIN across mods, so these coexist with Photo Mode if the
-- user also runs it (gt only acts while gt_bots_in_keep is on). NO duplicate-hook
-- risk within gt_dev: grepped -- nothing else hooks these (Class, method) pairs
-- (gt only hooks GameModeInn._cb_start_menu_closed elsewhere). GameModeInn and
-- GameModeInnDeus each carry their OWN copy of the inherited base methods (VT2
-- class() copies parent methods at definition time), so we hook each class.
-- ------------------------------------------------------------

-- (1) FILL: drive from the inn mode's own server_update (post-call). It only
-- fires once the session is running and the host is assigned, so the old
-- generic-tick slot-1 startup race (Bug 2) cannot happen. _bik_fill is fully
-- self-gated (active / host / in-inn / host-in-party-1 / open-slots).
local function _bik_server_update(self, t, dt)   -- luacheck: ignore self t dt
    _bik_fill()
end
mod:hook_safe("GameModeInn", "server_update", _bik_server_update)
mod:hook_safe("GameModeInnDeus", "server_update", _bik_server_update)

-- (2) TEARDOWN: clear our bots from the inn mode's own cleanup_game_mode_units.
-- StateIngame.on_exit calls this (state_ingame.lua:1911) BEFORE check_venture_end
-- (2119) destroys the venture stats manager, so _remove_bot_instant unregisters
-- each bot's stat in time -> fixes Bug 1 (the "Stat id not unregistered" fassert).
-- Unconditional (not gated on the toggle) so bots are ALWAYS cleaned up even if
-- the user flips the setting off mid-session. hook_safe -> vanilla cleanup runs.
local function _bik_cleanup(self)
    _bik_clear(self)
end
mod:hook_safe("GameModeInn", "cleanup_game_mode_units", _bik_cleanup)
mod:hook_safe("GameModeInnDeus", "cleanup_game_mode_units", _bik_cleanup)

-- Regression marker for the v0.2.146-dev bots-in-keep revival (read by the
-- bots_in_keep_crashfix_marker_present check in the main file). If a future
-- refactor re-kill-switches the feature or drops the cleanup_game_mode_units
-- teardown / host-in-party-1 gate, update this marker deliberately.
GT_BIK_CRASHFIX_MARKER_v0_2_146 = "gt-bik-cleanup-and-host-slot-gate"

-- ------------------------------------------------------------
-- (3) NECROMANCER KEEP SKELETONS (v0.2.147-dev; human parity #659 in v0.2.242-dev).
-- ------------------------------------------------------------
-- Fatshark forbids necromancer pets in the hub BY DESIGN: a necromancer (player
-- or bot) cannot raise skeletons in the keep / CW hub. The gate is
-- PassiveAbilityNecromancerCharges._pets_forbidden_in_level, computed in
-- _on_talents_changed as `script_data.pets_forbidden_in_hub and is_in_inn_level`
-- (passive_ability_necromancer_charges.lua:108-110). Both spawn_pet (line 202)
-- and _update_pets_server (line 327) early-return when it's true.
--
-- With Bots in Keep on, a BOT necromancer's AI still runs its raise-dead action
-- on a loop, but every spawn_pet hits that early-return -> "keeps trying over and
-- over but can't raise skeletons" (user report 2026-06-29).
--
-- FIX: clear the gate for human Necromancers whenever vanilla identifies a hub,
-- and for bot Necromancers only while Bots in Keep is active. We post-hook
-- _on_talents_changed — the method where vanilla SETS the flag — and flip
-- _pets_forbidden_in_level back to false according to that policy. The human
-- branch is independent of the bot-roster toggle; the bot branch retains its
-- existing lifecycle gate.
--
-- Why this can actually spawn skeletons in the keep: the real spawn path
-- (_spawn_pet_server -> Managers.state.conflict:spawn_queued_unit) relies on
-- systems the keep DOES have — the conflict director (gt already hooks its
-- spawn_queued_unit / spawn_unit_immediate), the side system, and the ai_system
-- nav_world (our bots navigate it). warm_up_skeletons (run for the bot on the
-- host inside _on_talents_changed) preloads the skeleton breed packages.
--
-- hook_safe (post): vanilla computes _pets_forbidden_in_level first, then we
-- clear it. NO duplicate-hook risk: grepped gt_dev — nothing else hooks
-- PassiveAbilityNecromancerCharges (this is the only hook on that class).
-- VMF hook_safe CHAINS across mods, so this coexists with any other necromancer
-- mod. EXPERIMENTAL: if skeletons spawning in the keep proves unstable in-game,
-- fall back to suppressing the bot's raise-dead loop instead.
local function _bik_necro_should_clear_keep_ban(is_bot, bots_in_keep, pets_forbidden)
    return pets_forbidden == true and (is_bot ~= true or bots_in_keep == true)
end
mod._gt_necro_should_clear_keep_ban = _bik_necro_should_clear_keep_ban

local function _bik_necro_allow_keep_pets(self, unit, talent_extension)   -- luacheck: ignore unit talent_extension
    -- Vanilla assigns `_player` in init before extensions_ready invokes
    -- _on_talents_changed (source lines 13-16, 56-76). Reading it directly
    -- avoids the unit->player reverse-association timing gap at player spawn.
    local player = self._player
    if not player then return end

    local is_bot = player.bot_player == true
    local bots_in_keep = _bik_active()
    if not _bik_necro_should_clear_keep_ban(is_bot, bots_in_keep, self._pets_forbidden_in_level) then
        return
    end

    self._pets_forbidden_in_level = false
    if rawget(_G, "printf") then
        printf(
            "[gt:659] necromancer keep pets allowed owner=%s bots_in_keep=%s server=%s local=%s",
            is_bot and "bot" or "human",
            tostring(bots_in_keep),
            tostring(self._is_server == true),
            tostring(self._is_local == true)
        )
    end
end
mod:hook_safe("PassiveAbilityNecromancerCharges", "_on_talents_changed", _bik_necro_allow_keep_pets)

-- Regression marker for the v0.2.242-dev human + bot keep-skeleton policy
-- (read by necromancer_keep_pet_policy_659 in the main file).
GT_NECRO_KEEP_PETS_MARKER_v0_2_242 = "gt-necro-human-and-bot-keep-pets"

mod:command("bots_in_keep", "Toggle 'Allow Bots in Keep' (host fills the heroes party with bots while in the keep / CW hub / Versus inn).", function()
    mod:set("gt_bots_in_keep", not mod:get("gt_bots_in_keep"))
end)

-- ============================================================
-- Disable Bots (Solo) — remove bots mid-mission + keep them gone
-- ============================================================
-- Backed by the engine flag `script_data.ai_bots_disabled`. Every mission
-- game mode's bot manager checks it inside _handle_bots on EACH server_update:
--   GameModeAdventure._handle_bots  (game_mode_adventure.lua:371)
--   GameModeDeus._handle_bots       (game_mode_deus.lua:527)
--   GameModeWeave._handle_bots      (game_mode_weave.lua:462)
-- When the flag is true and bots exist, vanilla calls self:_clear_bots(true)
-- and returns early — so flipping it ON mid-mission despawns the current bots
-- on the next tick AND blocks the delta-fill that would re-add them. Flipping
-- it OFF lets the normal top-up logic refill on the next tick.
--
-- This is why the old `/bottoggle` (which flips level_settings.no_bots_allowed)
-- did NOT remove bots mid-mission: that flag only gates whether a level permits
-- bots at load time; it has no despawn path and isn't re-read per-tick.
--
-- Host-only effective: bots are server-managed, and script_data is local, so
-- setting the flag on a client does nothing to the host's bot roster. We still
-- set it locally (harmless) and note the host-only caveat in the tooltip.
--
-- Re-applied on every StateIngame enter (see on_game_state_changed) so a user
-- who leaves the toggle ON gets a bot-free party from the first frame of every
-- subsequent mission, surviving the game's own ai_bots_disabled resets.
mod._gt_apply_no_bots = function(enabled)
    -- ROOT-CAUSE FIX (#194): never write the bare `script_data` global NAME.
    -- `script_data = script_data or {}` rawsets `script_data` into the VMF mod
    -- environment table; if `_G.script_data` wasn't populated yet at the FIRST
    -- call (this file applies once at mod load, line below), that caches a
    -- PRIVATE empty table which then permanently shadows the real
    -- `_G.script_data` the game's `_handle_bots` reads -> the flag never flips
    -- -> bots are never disabled (the reported "doesn't work"). The proven
    -- no-bots mods (SpawnTweaks / TrueSoloQoL) only ever FIELD-mutate
    -- script_data, never assign the name. So: read the real engine global via
    -- rawget and mutate the field on it.
    local sd = rawget(_G, "script_data")
    if not sd then
        -- Engine global not up yet (very early load). The _handle_bots enforce
        -- hooks below + the StateIngame re-apply both set it once it exists.
        return
    end
    sd.ai_bots_disabled = enabled and true or nil
    mod._gt_nb_enforce_logged = nil -- re-log the host enforce path next mission
    if rawget(_G, "printf") then
        printf("[gt_no_bots] apply enabled=%s ai_bots_disabled=%s",
            tostring(enabled), tostring(sd.ai_bots_disabled))
    end
end

-- Apply once at load so a persisted ON survives a mod reload before the first
-- state transition fires.
mod._gt_apply_no_bots(mod:get("gt_no_bots"))

mod:command("no_bots", "Toggle 'Disable Bots (Solo)' — despawns existing bots and blocks new ones (host-only).", function()
    local new_val = not mod:get("gt_no_bots")
    mod:set("gt_no_bots", new_val)
    mod._gt_apply_no_bots(new_val)
    mod:echo("Bots: " .. (new_val and "DISABLED (solo)" or "enabled"))
end)

-- ------------------------------------------------------------
-- Proven enforcement hooks (#194) — belt-and-suspenders on the flag above.
-- ------------------------------------------------------------
-- Hook _handle_bots on all three game modes and re-assert ai_bots_disabled from
-- the LIVE setting every server tick. This is exactly how the proven no-bots
-- mods work (SpawnTweaks / TrueSoloQoL hook GameModeAdventure._handle_bots) and
-- makes the toggle immune to any flag-reset / load-order / first-frame timing
-- race. Each mode's _handle_bots reads script_data.ai_bots_disabled at the TOP,
-- clears bots + early-returns, so forcing it here just before vanilla runs is
-- enough. NO duplicate-hook risk: grepped gt_dev — nothing else hooks these
-- (GameModeAdventure/Deus/Weave._handle_bots, AdventureSpawning.force_update_
-- spawn_positions). Host-only by nature: only the host runs _handle_bots.
local function _gt_no_bots_enforce(func, self, ...)
    if mod:get("gt_no_bots") then
        local sd = rawget(_G, "script_data")
        if sd then sd.ai_bots_disabled = true end
        if not mod._gt_nb_enforce_logged and rawget(_G, "printf") then
            mod._gt_nb_enforce_logged = true
            printf("[gt_no_bots] _handle_bots enforce active (host bot suppression on)")
        end
    end
    return func(self, ...)
end
mod:hook("GameModeAdventure", "_handle_bots", _gt_no_bots_enforce)
mod:hook("GameModeDeus", "_handle_bots", _gt_no_bots_enforce)
mod:hook("GameModeWeave", "_handle_bots", _gt_no_bots_enforce)

-- Crash guard: with bots disabled there are no bot units for AdventureSpawning
-- to position, and force_update_spawn_positions can fatal. The proven no-bots
-- mods pcall it while no-bots is on ("Prevent a crash with disabled bots").
-- This only matters once the flag ACTUALLY suppresses bots — which, pre-fix,
-- it never did, so the crash was latent and surfaces now that the toggle works.
mod:hook("AdventureSpawning", "force_update_spawn_positions", function(func, ...)
    if not mod:get("gt_no_bots") then
        return func(...)
    end
    pcall(func, ...)
end)
